#!/usr/bin/env bash
# Tests for bootstrap.sh
# Run with: ./tests/bootstrap_test.sh
#
# SC1090: the tests source "$BOOTSTRAP". SC2016: stub bodies are single
# quoted on purpose, they expand when the stub runs.
# shellcheck disable=SC1090,SC2016

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP="$SCRIPT_DIR/../bootstrap.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASSED=0
FAILED=0

test_case() {
    local name="$1"
    shift
    if "$@"; then
        echo -e "${GREEN}✓${NC} $name"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗${NC} $name"
        FAILED=$((FAILED + 1))
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" == *"$needle"* ]]
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" != *"$needle"* ]]
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    [[ "$actual" -eq "$expected" ]]
}

echo "=== Bootstrap Script Tests ==="
echo ""

# Test: Script exists and is executable
test_case "bootstrap.sh exists" test -f "$BOOTSTRAP"
test_case "bootstrap.sh is executable" test -x "$BOOTSTRAP"

# Test: Help flag works
test_case "--help shows usage" bash -c "
    output=\$('$BOOTSTRAP' --help 2>&1)
    [[ \"\$output\" == *'Usage:'* ]] && [[ \"\$output\" == *'--dry-run'* ]]
"

test_case "-h shows usage" bash -c "
    output=\$('$BOOTSTRAP' -h 2>&1)
    [[ \"\$output\" == *'Usage:'* ]]
"

# Test: Dry run mode
test_case "--dry-run doesn't install anything" bash -c "
    output=\$('$BOOTSTRAP' --dry-run 2>&1)
    [[ \"\$output\" == *'DRY RUN'* ]] && [[ \"\$output\" == *'[DRY-RUN]'* ]]
"

test_case "-n is alias for --dry-run" bash -c "
    output=\$('$BOOTSTRAP' -n 2>&1)
    [[ \"\$output\" == *'DRY RUN'* ]]
"

test_case "dry-run shows would-be actions" bash -c "
    output=\$('$BOOTSTRAP' --dry-run 2>&1)
    [[ \"\$output\" == *'Would:'* ]]
"

test_case "dry-run completes successfully" bash -c "
    '$BOOTSTRAP' --dry-run >/dev/null 2>&1
"

# Test: OS detection (source the script to test functions)
test_case "detect_os sets OS variable" bash -c "
    source '$BOOTSTRAP'
    detect_os >/dev/null 2>&1
    [[ -n \"\$OS\" ]]
"

test_case "detect_os sets PKG_MGR variable" bash -c "
    source '$BOOTSTRAP'
    detect_os >/dev/null 2>&1
    [[ -n \"\$PKG_MGR\" ]]
"

# Test: command_exists function
test_case "command_exists finds bash" bash -c "
    source '$BOOTSTRAP'
    command_exists bash
"

test_case "command_exists returns false for nonexistent" bash -c "
    source '$BOOTSTRAP'
    ! command_exists this_command_does_not_exist_12345
"

# Test: Invalid arguments
test_case "invalid arg shows error" bash -c "
    output=\$('$BOOTSTRAP' --invalid-flag 2>&1) || true
    [[ \"\$output\" == *'Unknown option'* ]]
"

# Test: Dry-run mentions key tools
test_case "dry-run mentions rust-analyzer" bash -c "
    output=\$('$BOOTSTRAP' --dry-run 2>&1)
    [[ \"\$output\" == *'rust-analyzer'* ]]
"

test_case "dry-run mentions wasm-tools" bash -c "
    output=\$('$BOOTSTRAP' --dry-run 2>&1)
    [[ \"\$output\" == *'wasm-tools'* ]]
"

test_case "dry-run mentions wit-bindgen" bash -c "
    output=\$('$BOOTSTRAP' --dry-run 2>&1)
    [[ \"\$output\" == *'wit-bindgen'* ]]
"

# Test: INSTALL_KOTLIN environment variable
test_case "INSTALL_KOTLIN=1 mentions kotlin tooling" bash -c "
    output=\$(INSTALL_KOTLIN=1 '$BOOTSTRAP' --dry-run 2>&1)
    [[ \"\$output\" == *'Kotlin'* ]]
"

test_case "without INSTALL_KOTLIN skips kotlin" bash -c "
    output=\$('$BOOTSTRAP' --dry-run 2>&1)
    [[ \"\$output\" != *'Installing Kotlin'* ]]
"

# Test: Verbose mode
test_case "--verbose flag accepted" bash -c "
    '$BOOTSTRAP' --dry-run --verbose >/dev/null 2>&1
"

test_case "-v is alias for --verbose" bash -c "
    '$BOOTSTRAP' -n -v >/dev/null 2>&1
"

# Stub commands for the tests below. Each stub dir is put first on PATH so
# bootstrap.sh functions see fake nvim/rustc/uname instead of the real ones.
STUB_ROOT="$(mktemp -d)"
trap 'rm -rf "$STUB_ROOT"' EXIT

# make_stub DIR NAME BODY: write an executable script DIR/NAME. The shebang
# uses bash's absolute path so stubs also work with a minimal PATH.
BASH_PATH="$(command -v bash)"
make_stub() {
    mkdir -p "$1"
    printf '#!%s\n%s\n' "$BASH_PATH" "$3" >"$1/$2"
    chmod +x "$1/$2"
}

# Fake nvim:
#   --version          prints "NVIM v$FAKE_NVIM_VERSION"
#   --clean ...        prints $FAKE_NVIM_CONFIG (the stdpath("config") query)
#   anything else      logs its arguments to $FAKE_NVIM_LOG and exits with
#                      $FAKE_NVIM_EXIT. Like lazy.nvim, it rewrites
#                      lazy-lock.json: a startup run (one that checks
#                      :Lazy exists) appends $FAKE_STARTUP_LOCK_LINE, a
#                      "Lazy! restore" run appends $FAKE_RESTORE_LOCK_LINE.
make_stub "$STUB_ROOT/nvim" nvim '
if [[ "$1" == "--version" ]]; then echo "NVIM v$FAKE_NVIM_VERSION"; exit 0; fi
if [[ "$1" == "--clean" ]]; then printf "%s" "$FAKE_NVIM_CONFIG"; exit 0; fi
printf "%s\n" "$*" >>"${FAKE_NVIM_LOG:-/dev/null}"
lock="$FAKE_NVIM_CONFIG/lazy-lock.json"
if [[ "$*" == *"Lazy! restore"* ]]; then
    [[ -n "${FAKE_RESTORE_LOCK_LINE:-}" ]] && echo "$FAKE_RESTORE_LOCK_LINE" >>"$lock"
elif [[ "$*" == *"exists('"'"':Lazy'"'"')"* ]]; then
    [[ -n "${FAKE_STARTUP_LOCK_LINE:-}" ]] && echo "$FAKE_STARTUP_LOCK_LINE" >>"$lock"
fi
exit "${FAKE_NVIM_EXIT:-0}"'
make_stub "$STUB_ROOT/uname" uname 'echo "$FAKE_ARCH"'
make_stub "$STUB_ROOT/rust" rustc 'echo "rustc $FAKE_RUST_VERSION (abc 2024-01-01)"'
make_stub "$STUB_ROOT/rust" rustup 'exit 0'
make_stub "$STUB_ROOT/rust" rust-analyzer 'exit 0'
make_stub "$STUB_ROOT/rust" rustfmt 'exit 0'

# Test: version comparison
t_version_ge() (
    source "$BOOTSTRAP"
    version_ge 0.11.0 0.11.0 &&
        version_ge 0.11.4 0.11 &&
        version_ge 0.12.0 0.11.0 &&
        version_ge 1.0 0.12 &&
        version_ge 1.82 1.82.0 &&
        version_ge 1.100.0 1.82 &&
        version_ge 2.0 1.82 &&
        ! version_ge 0.10.4 0.11.0 &&
        ! version_ge 0.9.5 0.11 &&
        ! version_ge 0.11 0.12 &&
        ! version_ge 1.81.9 1.82
)
test_case "version_ge compares dotted versions numerically" t_version_ge

# Test: Neovim version check
t_nvim_version_parse() (
    source "$BOOTSTRAP"
    export PATH="$STUB_ROOT/nvim:$PATH"
    [[ "$(FAKE_NVIM_VERSION=0.11.4 nvim_version)" == "0.11.4" ]] &&
        [[ "$(FAKE_NVIM_VERSION=0.12.0-dev-1234+gabcdef nvim_version)" == "0.12.0" ]]
)
test_case "nvim_version parses release and dev versions" t_nvim_version_parse

t_nvim_too_old_fails() (
    source "$BOOTSTRAP"
    export PATH="$STUB_ROOT/nvim:$PATH" FAKE_NVIM_VERSION=0.10.4
    PKG_MGR=apt DRY_RUN=0
    local output rc=0
    output=$(check_nvim_version 2>&1) || rc=$?
    [[ $rc -ne 0 ]] && [[ "$output" == *"too old"* ]] && [[ "$output" == *"apt-get remove neovim"* ]]
)
test_case "Neovim older than 0.11 fails the check" t_nvim_too_old_fails

t_nvim_too_old_dry_run_warns() (
    source "$BOOTSTRAP"
    export PATH="$STUB_ROOT/nvim:$PATH" FAKE_NVIM_VERSION=0.9.5
    PKG_MGR=brew DRY_RUN=1
    local output
    output=$(check_nvim_version 2>&1) && [[ "$output" == *"would fail in real run"* ]]
)
test_case "Neovim older than 0.11 only warns in dry-run" t_nvim_too_old_dry_run_warns

t_nvim_011_warns() (
    source "$BOOTSTRAP"
    export PATH="$STUB_ROOT/nvim:$PATH" FAKE_NVIM_VERSION=0.11.4
    PKG_MGR=brew DRY_RUN=0
    local output
    output=$(check_nvim_version 2>&1) && [[ "$output" == *"0.12+ recommended"* ]]
)
test_case "Neovim 0.11 passes with a 0.12 recommendation" t_nvim_011_warns

t_nvim_012_ok() (
    source "$BOOTSTRAP"
    export PATH="$STUB_ROOT/nvim:$PATH" FAKE_NVIM_VERSION=0.12.1
    PKG_MGR=brew DRY_RUN=0
    local output
    output=$(check_nvim_version 2>&1) && [[ -z "$output" ]]
)
test_case "Neovim 0.12 passes without warnings" t_nvim_012_ok

# Test: apt installs Neovim from the release tarball, not the apt package
t_nvim_release_url() (
    source "$BOOTSTRAP"
    export PATH="$STUB_ROOT/uname:$PATH"
    DRY_RUN=1
    local x86 arm
    x86=$(FAKE_ARCH=x86_64 install_nvim_release 2>&1) &&
        arm=$(FAKE_ARCH=aarch64 install_nvim_release 2>&1) &&
        [[ "$x86" == *"releases/download/stable/nvim-linux-x86_64.tar.gz"* ]] &&
        [[ "$x86" == *".local/opt/nvim"* ]] && [[ "$x86" == *".local/bin/nvim"* ]] &&
        [[ "$arm" == *"releases/download/stable/nvim-linux-arm64.tar.gz"* ]] &&
        [[ "$(FAKE_ARCH=x86_64 NVIM_RELEASE=v0.12.0 install_nvim_release 2>&1)" == *"download/v0.12.0/"* ]]
)
test_case "Neovim release build URL follows uname -m and NVIM_RELEASE" t_nvim_release_url

t_nvim_release_unknown_arch() (
    source "$BOOTSTRAP"
    export PATH="$STUB_ROOT/uname:$PATH" FAKE_ARCH=riscv64
    DRY_RUN=1
    # install_nvim_release exits, so run it in its own subshell
    ! (install_nvim_release >/dev/null 2>&1)
)
test_case "Neovim release build fails on an unsupported arch" t_nvim_release_unknown_arch

# A failed download must not leave the temp dir behind. Runs in a separate
# bash so set -e from bootstrap.sh applies (test_case runs tests in an if,
# which disables it).
t_nvim_release_cleans_up() (
    local root="$STUB_ROOT/release-fail"
    make_stub "$root/bin" curl 'exit 22'
    # mktemp ignores TMPDIR on some systems, so stub it to use $root/tmp
    make_stub "$root/bin" mktemp "mkdir -p '$root/tmp/dl' && echo '$root/tmp/dl'"
    mkdir -p "$root/tmp" "$root/home"
    local rc=0
    PATH="$root/bin:$STUB_ROOT/uname:$PATH" FAKE_ARCH=x86_64 HOME="$root/home" \
        bash -c 'source "$1"; DRY_RUN=0; install_nvim_release; echo "not reached"' _ "$BOOTSTRAP" \
        >"$root/out" 2>&1 || rc=$?
    [[ $rc -ne 0 ]] &&
        ! grep -q "not reached" "$root/out" &&
        [[ -z "$(ls -A "$root/tmp")" ]] &&
        [[ ! -e "$root/home/.local/bin/nvim" ]]
)
test_case "Neovim release build removes its temp dir when the download fails" t_nvim_release_cleans_up

t_apt_no_neovim_pkg() (
    source "$BOOTSTRAP"
    OS=debian PKG_MGR=apt DRY_RUN=1
    local output
    # Fresh machine: only the uname stub is on PATH, so nvim and the other
    # tools are missing and install_system_deps takes the install branches
    output=$(PATH="$STUB_ROOT/uname" FAKE_ARCH=x86_64 install_system_deps 2>&1) &&
        [[ "$output" == *"nvim-linux-x86_64.tar.gz"* ]] &&
        [[ "$output" != *"apt-get install -y neovim"* ]]
)
test_case "apt installs Neovim from the release build" t_apt_no_neovim_pkg

# Test: apt-get update runs once, before the first install
t_apt_update_once() (
    source "$BOOTSTRAP"
    PKG_MGR=apt DRY_RUN=1
    local output
    output=$({ install_pkg git; install_pkg ripgrep; apt_install nodejs npm; } 2>&1)
    [[ $(grep -c 'apt-get update' <<<"$output") -eq 1 ]] &&
        [[ $(grep -c 'apt-get install' <<<"$output") -eq 3 ]] &&
        [[ "$(grep -m1 'apt-get' <<<"$output")" == *"apt-get update"* ]]
)
test_case "apt-get update runs once before the first install" t_apt_update_once

t_apt_update_fresh_machine() (
    source "$BOOTSTRAP"
    OS=debian PKG_MGR=apt DRY_RUN=1
    local output
    output=$(PATH="$STUB_ROOT/uname" FAKE_ARCH=x86_64 install_system_deps 2>&1)
    [[ $(grep -c 'apt-get update' <<<"$output") -eq 1 ]] &&
        [[ "$output" == *"apt-get install -y curl"* ]] &&
        [[ "$output" == *"apt-get install -y nodejs npm"* ]]
)
test_case "fresh apt machine updates once and installs curl" t_apt_update_fresh_machine

# Test: Rust version check
t_rust_old_updates() (
    source "$BOOTSTRAP"
    export PATH="$STUB_ROOT/rust:$PATH" FAKE_RUST_VERSION=1.75.0
    DRY_RUN=1
    local output
    output=$(install_rust 2>&1) &&
        [[ "$output" == *"too old for wasm-tools"* ]] &&
        [[ "$output" == *"Would: rustup update stable"* ]]
)
test_case "old Rust version triggers rustup update" t_rust_old_updates

t_rust_new_no_update() (
    source "$BOOTSTRAP"
    export PATH="$STUB_ROOT/rust:$PATH" FAKE_RUST_VERSION=1.82.0
    DRY_RUN=1
    local output
    output=$(install_rust 2>&1) && [[ "$output" != *"rustup update"* ]]
)
test_case "Rust 1.82 does not trigger rustup update" t_rust_new_no_update

# Test: plugin sync restores lazy-lock.json versions and surfaces failures
test_case "dry-run restores plugins from lazy-lock.json" bash -c "
    output=\$('$BOOTSTRAP' --dry-run 2>&1)
    [[ \"\$output\" == *'Lazy! restore'* ]] && [[ \"\$output\" != *'Lazy! sync'* ]]
"

# sync_test_setup NAME: set up a fake config dir with a lockfile for sync_nvim.
# Run in the test's subshell; sets FAKE_NVIM_CONFIG and FAKE_NVIM_LOG.
sync_test_setup() {
    export FAKE_NVIM_CONFIG="$STUB_ROOT/config-$1"
    export FAKE_NVIM_LOG="$FAKE_NVIM_CONFIG/nvim.log"
    export PATH="$STUB_ROOT/nvim:$PATH"
    mkdir -p "$FAKE_NVIM_CONFIG"
    printf '{\n  "a.nvim": { "branch": "main", "commit": "aaa" }\n}\n' >"$FAKE_NVIM_CONFIG/lazy-lock.json"
    cp "$FAKE_NVIM_CONFIG/lazy-lock.json" "$FAKE_NVIM_CONFIG/original.json"
    DRY_RUN=0
}

t_sync_runs_restore() (
    source "$BOOTSTRAP"
    sync_test_setup ok
    # Startup rewrites the lockfile (as lazy.nvim does for itself on a fresh
    # machine); sync_nvim must put it back before Lazy! restore
    export FAKE_STARTUP_LOCK_LINE="lazy.nvim fresh clone"
    sync_nvim >/dev/null 2>&1 || return 1
    local -a runs=()
    local line
    while IFS= read -r line; do runs+=("$line"); done <"$FAKE_NVIM_LOG"
    # startup, restore, parser install
    [[ ${#runs[@]} -eq 3 ]] &&
        [[ "${runs[0]}" != *"Lazy! restore"* ]] &&
        [[ "${runs[1]}" == *"+Lazy! restore"* ]] &&
        [[ "${runs[2]}" == *"nvim-treesitter').install"* ]] &&
        cmp -s "$FAKE_NVIM_CONFIG/original.json" "$FAKE_NVIM_CONFIG/lazy-lock.json"
)
test_case "sync_nvim runs Lazy! restore and the parser install" t_sync_runs_restore

# Loading the config starts background parser installs; the startup and
# restore runs must wait for them before +qa, or half-finished installs
# break the next one
t_sync_waits_for_parsers() (
    source "$BOOTSTRAP"
    sync_test_setup settle
    sync_nvim >/dev/null 2>&1 || return 1
    local -a runs=()
    local line
    while IFS= read -r line; do runs+=("$line"); done <"$FAKE_NVIM_LOG"
    local run
    for run in "${runs[@]:0:2}"; do
        # The wait must come after Lazy! restore and before +qa
        [[ "$run" == *"Lazy! restore"*"pcall(require, 'nvim-treesitter')"* ]] ||
            [[ "$run" != *"Lazy! restore"* && "$run" == *"pcall(require, 'nvim-treesitter')"* ]] ||
            return 1
        [[ "$run" == *"):wait(300000)"*"end +qa" ]] || return 1
    done
)
test_case "sync_nvim waits for background parser installs before quitting" t_sync_waits_for_parsers

t_sync_fails_on_nvim_error() (
    source "$BOOTSTRAP"
    sync_test_setup exit
    export FAKE_NVIM_EXIT=1
    local output rc=0
    output=$(sync_nvim 2>&1) || rc=$?
    [[ $rc -ne 0 ]] && [[ "$output" == *"plugin install failed"* ]]
)
test_case "sync_nvim fails when nvim exits non-zero" t_sync_fails_on_nvim_error

t_sync_fails_on_lock_mismatch() (
    source "$BOOTSTRAP"
    sync_test_setup drift
    # Restore "checks out" a commit that differs from the lockfile
    export FAKE_RESTORE_LOCK_LINE='  "b.nvim": { "branch": "main", "commit": "bbb" }'
    local output rc=0
    output=$(sync_nvim 2>&1) || rc=$?
    [[ $rc -ne 0 ]] &&
        [[ "$output" == *"not at their lazy-lock.json commit"* ]] &&
        [[ "$output" == *'+   "b.nvim"'* ]] &&
        [[ $(wc -l <"$FAKE_NVIM_LOG") -eq 2 ]] &&
        cmp -s "$FAKE_NVIM_CONFIG/original.json" "$FAKE_NVIM_CONFIG/lazy-lock.json"
)
test_case "sync_nvim fails when a plugin is not at its locked commit" t_sync_fails_on_lock_mismatch

# Summary
echo ""
echo "=== Results ==="
echo -e "Passed: ${GREEN}$PASSED${NC}, Failed: ${RED}$FAILED${NC}"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
