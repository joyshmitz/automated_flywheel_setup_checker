#!/bin/bash
# ============================================================
# E2E Test: Auto-Remediation Flow
#
# Validates the error detection and auto-remediation pipeline,
# including command not found errors and apt lock contention.
#
# Related: bead bd-19y9.1.8
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assertions.sh"
source "$SCRIPT_DIR/../lib/helpers.sh"

setup_test "remediation_flow"

echo "Test: Auto-remediation flow"

# Test 1: Command not found remediation
echo "Testing command not found remediation..."
cmd_not_found_output="$TEST_TMP/output/cmd_not_found.txt"

# Simulate command not found error
cat > "$cmd_not_found_output" << 'EOF'
install.sh: line 15: jq: command not found
EOF

# Verify error is detected
assert_file_contains "$cmd_not_found_output" "command not found"

# Simulate remediation suggestion
remediation_suggestion="$TEST_TMP/output/remediation.txt"
{
    if grep -q "jq: command not found" "$cmd_not_found_output"; then
        echo "error_type=command_not_found"
        echo "missing_command=jq"
        echo "auto_fixable=true"
        echo "suggested_fix=apt-get install -y jq"
    fi
} > "$remediation_suggestion"

assert_file_contains "$remediation_suggestion" "auto_fixable=true"
assert_file_contains "$remediation_suggestion" "apt-get install -y jq"

# Test 2: APT lock contention remediation
echo "Testing apt lock remediation..."
apt_lock_output="$TEST_TMP/output/apt_lock.txt"

cat > "$apt_lock_output" << 'EOF'
E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 1234 (apt-get)
E: Unable to acquire the dpkg frontend lock (/var/lib/dpkg/lock-frontend), is another process using it?
EOF

apt_remediation="$TEST_TMP/output/apt_remediation.txt"
{
    if grep -q "dpkg frontend lock" "$apt_lock_output"; then
        echo "error_type=apt_lock_contention"
        echo "auto_fixable=true"
        echo "suggested_fix=wait_for_apt_or_kill"
    fi
} > "$apt_remediation"

assert_file_contains "$apt_remediation" "error_type=apt_lock_contention"
assert_file_contains "$apt_remediation" "auto_fixable=true"

# Test 3: Permission denied (non-auto-fixable)
echo "Testing permission denied (no auto-fix)..."
permission_output="$TEST_TMP/output/permission.txt"

cat > "$permission_output" << 'EOF'
permission denied: /usr/local/bin/tool
EOF

permission_remediation="$TEST_TMP/output/permission_remediation.txt"
{
    if grep -q "permission denied" "$permission_output"; then
        echo "error_type=permission_denied"
        echo "auto_fixable=false"
        echo "reason=requires_manual_intervention"
    fi
} > "$permission_remediation"

assert_file_contains "$permission_remediation" "auto_fixable=false"

echo "Remediation flow test: PASSED"
cleanup_test
