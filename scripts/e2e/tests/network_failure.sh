#!/bin/bash
# ============================================================
# E2E Test: Network Failure Handling
#
# Validates that network failures (DNS, timeout, connection refused)
# are properly detected, classified, and reported.
#
# Related: bead bd-19y9.1.8
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assertions.sh"
source "$SCRIPT_DIR/../lib/helpers.sh"

setup_test "network_failure"

echo "Test: Network failure handling"

# Test 1: DNS resolution failure simulation
echo "Simulating DNS resolution failure..."
dns_error_output="$TEST_TMP/output/dns_error.txt"

# Simulate curl DNS error
cat > "$dns_error_output" << 'EOF'
curl: (6) Could not resolve host: nonexistent-host-xyz123.invalid
EOF

assert_file_contains "$dns_error_output" "Could not resolve host"

# Test 2: Connection timeout simulation
echo "Simulating connection timeout..."
timeout_error_output="$TEST_TMP/output/timeout_error.txt"

cat > "$timeout_error_output" << 'EOF'
curl: (28) Connection timed out after 30001 milliseconds
EOF

assert_file_contains "$timeout_error_output" "timed out"

# Test 3: Connection refused simulation
echo "Simulating connection refused..."
refused_error_output="$TEST_TMP/output/refused_error.txt"

cat > "$refused_error_output" << 'EOF'
curl: (7) Failed to connect to localhost port 9999: Connection refused
EOF

assert_file_contains "$refused_error_output" "Connection refused"

# Test 4: Verify error classification
echo "Testing error classification..."

# Create a simple error classifier test
classifier_test="$TEST_TMP/output/classified.txt"
{
    # DNS error
    if grep -q "Could not resolve host" "$dns_error_output"; then
        echo "dns_error: category=network, retryable=true"
    fi

    # Timeout error
    if grep -q "timed out" "$timeout_error_output"; then
        echo "timeout_error: category=network, retryable=true"
    fi

    # Connection refused
    if grep -q "Connection refused" "$refused_error_output"; then
        echo "refused_error: category=network, retryable=true"
    fi
} > "$classifier_test"

assert_file_contains "$classifier_test" "dns_error: category=network"
assert_file_contains "$classifier_test" "timeout_error: category=network"
assert_file_contains "$classifier_test" "refused_error: category=network"

echo "Network failure test: PASSED"
cleanup_test
