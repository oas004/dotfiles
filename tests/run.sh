#!/usr/bin/env bash
# Single entry point for the test suite.
#
#   tests/run.sh
#
# Runs, in order:
#   1. tests/bootstrap_test.sh
#   2. every tests/*_test.lua, each in a fresh `nvim --headless -c "luafile <file>"`
#   3. a startup smoke test (tests/startup_smoke.lua) that opens sample files,
#      waits for their LSP clients and fails on errors in :messages
#
# Every nvim started for steps 2 and 3 records deprecation warnings (any
# vim.deprecate() call that shows a warning, from this config or a plugin),
# and the test fails if there were any.
#
# Environment:
#   NVIM_APPNAME   which config nvim loads (passed through untouched). The
#                  config dir must resolve to this checkout, otherwise the run
#                  aborts so you never test the wrong config by accident.
#   NVIM           nvim binary to use (default: nvim)
#   TEST_SKIP      space or comma separated names to skip, e.g.
#                  "bootstrap smoke config_test" (.lua/.sh suffix optional)
#   TEST_TIMEOUT   per-test timeout in seconds (default: 180)
#   SMOKE_WAIT_MS  how long the smoke test waits for LSP clients to attach
#                  (default: 60000 on CI, 30000 otherwise)
#   SMOKE_EXTS     file extensions the smoke test opens (default: "lua rs")

set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT" || exit 1

NVIM="${NVIM:-nvim}"
TEST_TIMEOUT="${TEST_TIMEOUT:-180}"
SMOKE_EXTS="${SMOKE_EXTS:-lua rs}"
SKIP_LIST=" $(printf '%s' "${TEST_SKIP:-}" | tr ',' ' ') "

if ! command -v "$NVIM" >/dev/null 2>&1; then
  echo "error: '$NVIM' not found on PATH" >&2
  exit 1
fi

# Refuse to run against a config that is not this checkout.
config_dir="$("$NVIM" --headless --clean -c 'lua io.stdout:write(vim.fn.stdpath("config"))' -c 'qa!' 2>/dev/null </dev/null)"
config_real="$(cd "$config_dir" 2>/dev/null && pwd -P || true)"
if [[ "$config_real" != "$ROOT" ]]; then
  echo "error: nvim would load the config at '$config_dir'," >&2
  echo "       but this checkout is '$ROOT'." >&2
  echo "       Set NVIM_APPNAME to the checkout's directory name under ~/.config," >&2
  echo "       e.g. NVIM_APPNAME=$(basename "$ROOT") tests/run.sh" >&2
  exit 1
fi

LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nvim-tests.XXXXXX")"
trap 'rm -rf "$LOG_DIR"' EXIT

PASSED=()
FAILED=()
SKIPPED=()

is_skipped() {
  local name="$1"
  [[ "$SKIP_LIST" == *" $name "* ]] ||
    [[ "$SKIP_LIST" == *" $name.lua "* ]] ||
    [[ "$SKIP_LIST" == *" $name.sh "* ]]
}

# run_with_timeout <seconds> <logfile> <cmd...>
# Runs cmd with output to logfile, kills it after <seconds>. Returns the
# command's exit code, or 124 on timeout.
run_with_timeout() {
  local secs="$1" log="$2"
  shift 2
  local marker="$log.timeout"
  "$@" >"$log" 2>&1 </dev/null &
  local pid=$!
  (
    sleep "$secs"
    touch "$marker"
    kill -TERM "$pid" 2>/dev/null
    sleep 5
    kill -KILL "$pid" 2>/dev/null
  ) >/dev/null 2>&1 &
  local watchdog=$!
  wait "$pid"
  local rc=$?
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  if [[ -e "$marker" ]]; then
    return 124
  fi
  return "$rc"
}

# Loaded with --cmd before init.lua in every nvim the tests start. Wraps
# vim.deprecate so each deprecation warning that is actually shown (it returns
# the message then) gets appended to $NVIM_TEST_DEPRECATIONS with a traceback.
# run_test fails the test if that file is not empty.
deprecation_hook='local file = vim.env.NVIM_TEST_DEPRECATIONS
local orig = vim.deprecate
vim.deprecate = function(name, ...)
  local msg = orig(name, ...)
  if msg and file then
    local trace = debug.traceback("", 2)
    -- TEMPORARY: telescope.nvim at the commit in lazy-lock.json calls
    -- vim.tbl_islist. The telescope PR fixes that; remove this entry with it.
    if name == "vim.tbl_islist" and trace:find("lua/telescope/", 1, true) then
      return msg
    end
    local f = io.open(file, "a")
    if f then
      f:write(msg, trace, "\n")
      f:close()
    end
  end
  return msg
end'

# run_test <name> <cmd...>
run_test() {
  local name="$1"
  shift
  if is_skipped "$name"; then
    echo "--- SKIP $name (TEST_SKIP)"
    SKIPPED+=("$name")
    return
  fi
  echo "--- RUN  $name"
  local log="$LOG_DIR/$name.log"
  local deprecations="$LOG_DIR/$name.deprecations"
  local start=$SECONDS
  NVIM_TEST_DEPRECATIONS="$deprecations" run_with_timeout "$TEST_TIMEOUT" "$log" "$@"
  local rc=$?
  local took=$((SECONDS - start))
  sed 's/^/    /' "$log"
  # Some test files print without a trailing newline.
  [[ -s "$log" && -n "$(tail -c 1 "$log")" ]] && echo
  if [[ -s "$deprecations" ]]; then
    echo "    === deprecation warnings ==="
    sed 's/^/    /' "$deprecations"
  fi
  if [[ -s "$deprecations" && $rc -ne 124 ]]; then
    echo "--- FAIL $name (deprecation warnings, ${took}s)"
    FAILED+=("$name")
  elif [[ $rc -eq 0 ]]; then
    echo "--- PASS $name (${took}s)"
    PASSED+=("$name")
  elif [[ $rc -eq 124 ]]; then
    echo "--- FAIL $name (timed out after ${TEST_TIMEOUT}s; the test must exit with qa! or cq)"
    FAILED+=("$name")
  else
    echo "--- FAIL $name (exit $rc, ${took}s)"
    FAILED+=("$name")
  fi
}

echo "Config:  $config_dir"
echo "Neovim:  $("$NVIM" --version | head -n 1)"
echo

# 1. Bootstrap script tests
run_test bootstrap bash tests/bootstrap_test.sh

# 2. Lua test files. If luafile itself errors (e.g. a syntax error) the
#    test never reaches qa!/cq, so fail fast on v:errmsg instead of waiting
#    for the timeout. Tests that finish asynchronously still work, since
#    luafile returns without an error for them.
shopt -s nullglob
for file in tests/*_test.lua; do
  name="$(basename "$file" .lua)"
  run_test "$name" "$NVIM" --headless --cmd "lua $deprecation_hook" \
    -c 'let v:errmsg = ""' \
    -c "luafile $file" \
    -c 'if v:errmsg != "" | echomsg "luafile error: " . v:errmsg | cquit 3 | endif'
done
shopt -u nullglob

# 3. Startup smoke test
SMOKE_DIR="$LOG_DIR/smoke"
mkdir -p "$SMOKE_DIR"
smoke_files=()
for ext in $SMOKE_EXTS; do
  f="$SMOKE_DIR/sample.$ext"
  case "$ext" in
    lua) printf 'local M = {}\n\nfunction M.add(a, b)\n  return a + b\nend\n\nreturn M\n' >"$f" ;;
    rs) printf 'fn add(a: i32, b: i32) -> i32 {\n    a + b\n}\n\nfn main() {\n    println!("{}", add(1, 2));\n}\n' >"$f" ;;
    kt) printf 'fun add(a: Int, b: Int): Int = a + b\n\nfun main() {\n    println(add(1, 2))\n}\n' >"$f" ;;
    *) printf '\n' >"$f" ;;
  esac
  smoke_files+=("$f")
done
# The --cmd hook runs before init.lua and records ERROR-level vim.notify
# calls (e.g. utils.safe_require failures), whose text need not contain "Error".
notify_hook='_G.startup_smoke_errors = {}
local orig = vim.notify
vim.notify = function(msg, level, opts)
  if level and level >= vim.log.levels.ERROR then
    table.insert(_G.startup_smoke_errors, tostring(msg))
  end
  return orig(msg, level, opts)
end'
run_test smoke "$NVIM" --headless --cmd "lua $deprecation_hook" --cmd "lua $notify_hook" "${smoke_files[@]}" \
  -c "luafile tests/startup_smoke.lua"

echo
echo "=== Summary ==="
echo "Passed:  ${#PASSED[@]}${PASSED[*]:+ (${PASSED[*]})}"
echo "Failed:  ${#FAILED[@]}${FAILED[*]:+ (${FAILED[*]})}"
echo "Skipped: ${#SKIPPED[@]}${SKIPPED[*]:+ (${SKIPPED[*]})}"

[[ ${#FAILED[@]} -eq 0 ]]
