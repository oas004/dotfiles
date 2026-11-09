#!/usr/bin/env bash
# Tests for bootstrap.sh
# Run with: ./tests/bootstrap_test.sh
#
# SC1090: the tests source "$BOOTSTRAP". SC2016: stub bodies are single
# quoted on purpose, they expand when the stub runs. SC2034: variables like
# DRY_RUN and PKG_MGR are read by the sourced bootstrap.sh functions.
# shellcheck disable=SC1090,SC2016,SC2034

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
    output=$({ install_pkg git; install_pkg ripgrep; apt_install python3 python3-venv; } 2>&1)
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
        [[ "$output" == *"apt-get install -y curl"* ]]
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

# Test: rust-analyzer and rustfmt come from rustup components. rustup
# installs proxies for both even without the component, and the proxy fails
# with "Unknown binary", so a rust-analyzer on PATH doesn't mean it works.
# FAKE_COMPONENTS is what `rustup component list --installed` prints.
make_stub "$STUB_ROOT/rust-proxy" rustc 'echo "rustc 1.90.0 (abc 2025-01-01)"'
make_stub "$STUB_ROOT/rust-proxy" rustup '
if [[ "$*" == "component list --installed" ]]; then printf "%b" "$FAKE_COMPONENTS"; fi
exit 0'
make_stub "$STUB_ROOT/rust-proxy" rust-analyzer "echo \"error: Unknown binary 'rust-analyzer' in official toolchain\" >&2; exit 1"
make_stub "$STUB_ROOT/rust-proxy" rustfmt "echo \"error: Unknown binary 'rustfmt' in official toolchain\" >&2; exit 1"

t_rust_analyzer_proxy() (
    source "$BOOTSTRAP"
    export PATH="$STUB_ROOT/rust-proxy:$PATH"
    export FAKE_COMPONENTS='cargo-aarch64-apple-darwin\nrust-src\nrustfmt-aarch64-apple-darwin\n'
    DRY_RUN=1
    local output
    output=$(install_rust 2>&1) &&
        [[ "$output" == *"Would: rustup component add rust-analyzer"* ]] &&
        [[ "$output" != *"rustup component add rustfmt"* ]]
)
test_case "rust-analyzer proxy without the component triggers rustup component add" t_rust_analyzer_proxy

t_rust_components_installed() (
    source "$BOOTSTRAP"
    export PATH="$STUB_ROOT/rust-proxy:$PATH"
    export FAKE_COMPONENTS='rust-analyzer-x86_64-unknown-linux-gnu\nrustfmt-x86_64-unknown-linux-gnu\n'
    DRY_RUN=1
    local output
    output=$(install_rust 2>&1) && [[ "$output" != *"component add"* ]]
)
test_case "installed rust-analyzer and rustfmt components are not added again" t_rust_components_installed

t_rustfmt_proxy() (
    source "$BOOTSTRAP"
    export PATH="$STUB_ROOT/rust-proxy:$PATH" FAKE_COMPONENTS='rust-src\n'
    DRY_RUN=1
    local output
    output=$(install_rust 2>&1) &&
        [[ "$output" == *"Would: rustup component add rust-analyzer"* ]] &&
        [[ "$output" == *"Would: rustup component add rustfmt"* ]]
)
test_case "rustfmt proxy without the component triggers rustup component add" t_rustfmt_proxy

t_summary_rust_analyzer_broken() (
    source "$BOOTSTRAP"
    export PATH="$STUB_ROOT/rust-proxy:$STUB_ROOT/nvim:$PATH" FAKE_NVIM_VERSION=0.12.1
    DRY_RUN=0
    local output
    output=$(print_summary 2>&1) &&
        [[ "$output" == *"rust-analyzer does not run"*"rustup component add rust-analyzer"* ]] &&
        [[ "$output" != *"via rustup"* ]]
)
test_case "summary warns when rust-analyzer does not run" t_summary_rust_analyzer_broken

t_summary_google_java_format() (
    source "$BOOTSTRAP"
    local output
    DRY_RUN=1
    output=$(PATH="$STUB_ROOT/empty" print_summary 2>&1) &&
        [[ "$output" == *"google-java-format not found"* ]] &&
        make_stub "$STUB_ROOT/gjf" google-java-format 'exit 0' &&
        output=$(PATH="$STUB_ROOT/gjf" print_summary 2>&1) &&
        [[ "$output" != *"google-java-format"* ]]
)
test_case "summary warns when google-java-format is missing" t_summary_google_java_format

# Test: fresh machine gets what Mason and the formatters need, and no Node.js
t_system_deps_per_pkg_mgr() (
    source "$BOOTSTRAP"
    OS=linux DRY_RUN=1
    local mgr output
    for mgr in brew apt dnf pacman; do
        output=$(PKG_MGR=$mgr PATH="$STUB_ROOT/uname" FAKE_ARCH=x86_64 install_system_deps 2>&1) || return 1
        case "$mgr" in
            brew)   [[ "$output" == *"brew install unzip"* && "$output" == *"brew install jq"* ]] ;;
            apt)    [[ "$output" == *"apt-get install -y unzip"* && "$output" == *"apt-get install -y jq"* ]] ;;
            dnf)    [[ "$output" == *"dnf install -y unzip"* && "$output" == *"dnf install -y jq"* ]] ;;
            pacman) [[ "$output" == *"pacman -S --noconfirm unzip"* && "$output" == *"pacman -S --noconfirm jq"* ]] ;;
        esac || return 1
        [[ "$output" == *" tar"* && "$output" == *" gzip"* ]] || return 1
        [[ "$output" != *[Nn]ode* && "$output" != *npm* ]] || return 1
    done
)
test_case "fresh machine installs unzip, tar, gzip and jq but not Node.js" t_system_deps_per_pkg_mgr

test_case "dry-run does not install Node.js" bash -c "
    output=\$('$BOOTSTRAP' --dry-run 2>&1)
    [[ \"\$output\" != *'Node'* ]] && [[ \"\$output\" != *'nodejs'* ]] && [[ \"\$output\" != *'npm'* ]]
"

# Test: JDK 21+ for jdtls and gradle_ls. Fake JDKs print `java -version`
# like OpenJDK does, on stderr.
make_jdk() {
    make_stub "$STUB_ROOT/$1/bin" java "echo 'openjdk version \"$2\" 2024-01-16 LTS' >&2"
}
make_jdk jdk8 1.8.0_392
make_jdk jdk17 17.0.9
make_jdk jdk21 21.0.6
make_jdk jdk25 25

t_java_major() (
    source "$BOOTSTRAP"
    [[ "$(java_major "$STUB_ROOT/jdk8/bin/java")" == 8 ]] &&
        [[ "$(java_major "$STUB_ROOT/jdk17/bin/java")" == 17 ]] &&
        [[ "$(java_major "$STUB_ROOT/jdk21/bin/java")" == 21 ]] &&
        [[ "$(java_major "$STUB_ROOT/jdk25/bin/java")" == 25 ]]
)
test_case "java_major parses java -version" t_java_major

t_jdk_per_pkg_mgr() (
    source "$BOOTSTRAP"
    unset JAVA_HOME
    MACOS_JAVA_HOME_CMD=/nonexistent DRY_RUN=1
    local mgr output
    for mgr in brew apt dnf pacman; do
        # No java on PATH
        output=$(PKG_MGR=$mgr PATH="$STUB_ROOT/empty" install_jdk 2>&1) || return 1
        case "$mgr" in
            brew)   [[ "$output" == *"brew install openjdk@21"* &&
                       "$output" == *"keg-only"*'export JAVA_HOME="'*"/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"* ]] ;;
            apt)    [[ "$output" == *"apt-get install -y openjdk-21-jdk"* ]] ;;
            dnf)    [[ "$output" == *"dnf install -y java-21-openjdk-devel"* ]] ;;
            pacman) [[ "$output" == *"pacman -S --noconfirm jdk21-openjdk"* ]] ;;
        esac || return 1
    done
)
test_case "missing JDK installs JDK 21 per package manager" t_jdk_per_pkg_mgr

t_jdk_versions() (
    source "$BOOTSTRAP"
    unset JAVA_HOME
    MACOS_JAVA_HOME_CMD=/nonexistent PKG_MGR=apt DRY_RUN=1
    local old new home_old
    old=$(PATH="$STUB_ROOT/jdk17/bin:$PATH" install_jdk 2>&1) &&
        new=$(PATH="$STUB_ROOT/jdk21/bin:$PATH" install_jdk 2>&1) &&
        # jdtls uses JAVA_HOME over PATH
        home_old=$(JAVA_HOME="$STUB_ROOT/jdk17" PATH="$STUB_ROOT/jdk21/bin:$PATH" install_jdk 2>&1) &&
        [[ "$old" == *"openjdk-21-jdk"* ]] &&
        [[ "$new" == *"Java 21 already installed"* && "$new" != *"apt-get"* ]] &&
        [[ "$home_old" == *"openjdk-21-jdk"* ]]
)
test_case "JDK older than 21 (on PATH or in JAVA_HOME) installs JDK 21" t_jdk_versions

t_jdk_macos_java_home() (
    source "$BOOTSTRAP"
    unset JAVA_HOME
    PKG_MGR=brew DRY_RUN=1
    local found fallback
    # java_home finds an installed JDK 21 that isn't the default
    make_stub "$STUB_ROOT/java_home21" java_home "echo '$STUB_ROOT/jdk21'"
    # java_home returns another JDK when none matches -v 21+
    make_stub "$STUB_ROOT/java_home17" java_home "echo '$STUB_ROOT/jdk17'"
    found=$(MACOS_JAVA_HOME_CMD="$STUB_ROOT/java_home21/java_home" PATH="$STUB_ROOT/jdk17/bin:$PATH" install_jdk 2>&1) &&
        fallback=$(MACOS_JAVA_HOME_CMD="$STUB_ROOT/java_home17/java_home" PATH="$STUB_ROOT/jdk17/bin:$PATH" install_jdk 2>&1) &&
        [[ "$found" == *"export JAVA_HOME=\"$STUB_ROOT/jdk21\""* && "$found" != *"brew install"* ]] &&
        [[ "$fallback" == *"brew install openjdk@21"* ]]
)
test_case "macOS suggests an installed JDK 21 instead of installing one" t_jdk_macos_java_home

# Test: python3 with venv for Mason's jedi-language-server
make_stub "$STUB_ROOT/py-novenv" python3 'exit 1'
make_stub "$STUB_ROOT/py-venv" python3 'exit 0'

t_python_per_pkg_mgr() (
    source "$BOOTSTRAP"
    DRY_RUN=1
    local mgr output
    for mgr in brew apt dnf pacman; do
        output=$(PKG_MGR=$mgr PATH="$STUB_ROOT/py-novenv" install_python 2>&1) || return 1
        case "$mgr" in
            brew)   [[ "$output" == *"brew install python"* ]] ;;
            apt)    [[ "$output" == *"apt-get install -y python3 python3-venv"* ]] ;;
            dnf)    [[ "$output" == *"dnf install -y python3"* ]] ;;
            pacman) [[ "$output" == *"pacman -S --noconfirm python"* ]] ;;
        esac || return 1
    done
    output=$(PKG_MGR=apt PATH="$STUB_ROOT/py-venv" install_python 2>&1) &&
        [[ "$output" != *"apt-get"* ]]
)
test_case "python3 without venv installs python3-venv per package manager" t_python_per_pkg_mgr

t_ghcup_warns() (
    source "$BOOTSTRAP"
    make_stub "$STUB_ROOT/ghcup" ghcup 'exit 0'
    local missing present
    missing=$(PATH="$STUB_ROOT/empty" check_ghcup 2>&1) &&
        present=$(PATH="$STUB_ROOT/ghcup" check_ghcup 2>&1) &&
        [[ "$missing" == *"ghcup not found"*"get-ghcup.haskell.org"* ]] &&
        [[ "$present" != *"WARN"* ]]
)
test_case "missing ghcup warns with the install command" t_ghcup_warns

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
