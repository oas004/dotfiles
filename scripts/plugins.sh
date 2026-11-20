#!/usr/bin/env bash
# Plugin updates and restores, run by `make update` and `make restore`.
#
#   scripts/plugins.sh update
#     Moves every plugin to its newest allowed commit (:Lazy! update, which
#     rewrites lazy-lock.json), updates the treesitter parsers to match, runs
#     tests/run.sh against the result and prints `git diff lazy-lock.json`.
#     Nothing is committed: review the diff and commit it if the tests pass.
#     Refuses to start if lazy-lock.json has uncommitted changes, so the diff
#     shows only this update.
#
#   scripts/plugins.sh restore
#     Puts every plugin back at its lazy-lock.json commit (:Lazy! restore).
#
# nvim-treesitter (#28): lua/plugins/parser.lua pins it to an older commit on
# Neovim 0.11, and lazy-lock.json has to keep that commit so 0.11 can restore
# it. So update never changes its lockfile entry. On 0.12, which follows
# main, both commands move the installed nvim-treesitter to main HEAD and
# then put its lockfile entry back, the way CI's 0.12 job does.
#
# Mason packages are not in lazy-lock.json and are left alone; :Mason
# updates them.
#
# Environment:
#   NVIM          nvim binary to use (default: nvim)
#   NVIM_APPNAME  passed through; the config dir must be this checkout
#   anything tests/run.sh reads (TEST_SKIP, ...), for update

set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT" || exit 1

NVIM="${NVIM:-nvim}"
LOCK="lazy-lock.json"
TS_ENTRY='^  "nvim-treesitter": '

die() {
  echo "error: $*" >&2
  exit 1
}

# lazy.nvim writes the lockfile of the config it loads, so that must be this
# checkout (the same check as tests/run.sh).
config_dir="$("$NVIM" --headless --clean -c 'lua io.stdout:write(vim.fn.stdpath("config"))' -c 'qa!' 2>/dev/null </dev/null)"
config_real="$(cd "$config_dir" 2>/dev/null && pwd -P || true)"
if [[ "$config_real" != "$ROOT" ]]; then
  die "nvim would load the config at '$config_dir', but this checkout is '$ROOT'. Set NVIM_APPNAME to the checkout's directory name under ~/.config."
fi

nvim_012="$("$NVIM" --headless --clean -c 'lua io.stdout:write(vim.fn.has("nvim-0.12"))' -c 'qa!' 2>/dev/null </dev/null)"

# Waits for nvim-treesitter's parser updates and installs (including the
# ones its :TSUpdate build starts) before nvim quits, since quitting during
# one leaves a half-finished install behind (see bootstrap.sh).
ts_settle="lua local ok, ts = pcall(require, 'nvim-treesitter')"
ts_settle+=" if ok and ts.install and ts.update and vim.g.treesitter_parsers then"
ts_settle+=" ts.update(vim.g.treesitter_parsers):wait(300000)"
ts_settle+=" ts.install(vim.g.treesitter_parsers):wait(300000)"
ts_settle+=" end"

run_nvim() {
  "$NVIM" --headless "$@" "+$ts_settle" +qa </dev/null || die "nvim $* failed"
}

# On 0.12, move nvim-treesitter to main HEAD and keep its lockfile entry.
ts_to_main() {
  [[ "$nvim_012" == "1" ]] || return 0
  local entry
  entry="$(grep -E "$TS_ENTRY" "$LOCK")"
  # lazy's headless output doesn't end with a newline
  echo
  echo "Neovim 0.12: moving nvim-treesitter to main (its $LOCK entry stays at the 0.11 pin, see #28)"
  run_nvim "+Lazy! update nvim-treesitter"
  put_back_ts_entry "$entry"
}

# Replace nvim-treesitter's lockfile line with $1, if it changed
put_back_ts_entry() {
  local entry="$1" tmp
  [[ -n "$entry" ]] || return 0
  grep -qxF -- "$entry" "$LOCK" && return 0
  tmp="$(mktemp)"
  awk -v entry="$entry" -v pat="$TS_ENTRY" '$0 ~ pat { print entry; next } { print }' "$LOCK" >"$tmp" &&
    cat "$tmp" >"$LOCK"
  rm -f "$tmp"
}

cmd_restore() {
  echo "Restoring plugins to the commits in $LOCK"
  run_nvim "+Lazy! restore"
  ts_to_main
}

cmd_update() {
  git diff --quiet -- "$LOCK" ||
    die "$LOCK has uncommitted changes; commit or discard them first, so the update diff only shows the update"

  local ts_entry
  ts_entry="$(grep -E "$TS_ENTRY" "$LOCK")"

  echo "Updating plugins"
  run_nvim "+Lazy! update"
  put_back_ts_entry "$ts_entry"

  echo
  echo "Running the tests against the updated plugins"
  tests/run.sh
  local rc=$?

  echo
  if git diff --quiet -- "$LOCK"; then
    echo "No plugin changed."
    return "$rc"
  fi
  echo "=== $LOCK ==="
  git --no-pager diff --stat -- "$LOCK"
  git --no-pager diff -- "$LOCK"
  echo
  if [[ $rc -eq 0 ]]; then
    echo "Tests passed. Review the changes above and commit $LOCK."
  else
    echo "Tests failed. Fix the config, or go back to the committed versions with:"
    echo "  git checkout -- $LOCK && make restore"
  fi
  return "$rc"
}

case "${1:-}" in
  update) cmd_update ;;
  restore) cmd_restore ;;
  *) die "usage: $0 update|restore" ;;
esac
