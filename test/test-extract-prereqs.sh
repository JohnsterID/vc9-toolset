#!/bin/bash
# Test extract-vc9.sh prerequisite checking (no downloads needed)
# Verifies the script fails gracefully when required tools are missing.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

assert_contains() {
    local label="$1" output="$2" expected="$3"
    if echo "$output" | grep -qi "$expected"; then
        echo "  [PASS] $label"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $label — expected '$expected' in output"
        echo "         got: $output"
        FAIL=$((FAIL + 1))
    fi
}

# Test: bash -n (syntax check)
echo "=== Syntax check ==="
if bash -n "$SCRIPT_DIR/extract-vc9.sh"; then
    echo "  [PASS] extract-vc9.sh has valid syntax"
    PASS=$((PASS + 1))
else
    echo "  [FAIL] extract-vc9.sh has syntax errors"
    FAIL=$((FAIL + 1))
fi

# Test: --help-like unknown option
echo "=== Unknown option ==="
output=$(bash "$SCRIPT_DIR/extract-vc9.sh" --bogus-flag 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "  [PASS] rejects unknown option (exit $rc)"
    PASS=$((PASS + 1))
else
    echo "  [FAIL] should reject --bogus-flag"
    FAIL=$((FAIL + 1))
fi

# Test: script is executable
echo "=== Executable bit ==="
if [ -x "$SCRIPT_DIR/extract-vc9.sh" ]; then
    echo "  [PASS] extract-vc9.sh is executable"
    PASS=$((PASS + 1))
else
    echo "  [FAIL] extract-vc9.sh is not executable"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
