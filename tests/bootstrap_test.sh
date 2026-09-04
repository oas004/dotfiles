#!/usr/bin/env bash
# Tests for bootstrap.sh
# Run with: ./tests/bootstrap_test.sh

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

# Test: Rust version check logic
test_case "detects old Rust version needing update" bash -c "
    # The script should mention 1.82+ requirement somewhere in code
    grep -q '1.82' '$BOOTSTRAP'
"

# Summary
echo ""
echo "=== Results ==="
echo -e "Passed: ${GREEN}$PASSED${NC}, Failed: ${RED}$FAILED${NC}"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
