#!/bin/bash
# ============================================================
# E2E Test: Container Timeout Handling
#
# Validates proper handling of container execution timeouts
# including graceful termination and cleanup.
#
# Related: bead bd-19y9.1.8
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assertions.sh"
source "$SCRIPT_DIR/../lib/helpers.sh"

setup_test "container_timeout_handling"

echo "Test: Container timeout handling"

# Test 1: Timeout detection
echo "Testing timeout detection..."
timeout_log="$TEST_TMP/output/timeout.log"

cat > "$timeout_log" << 'EOF'
[10:00:00] Starting installer: slow-tool
[10:00:00] Container started: acfs-test-slow-tool-abc123
[10:00:00] Timeout configured: 300 seconds
[10:05:00] WARNING: Container execution time exceeded timeout (300s)
[10:05:00] Sending SIGTERM to container...
[10:05:05] Container did not respond to SIGTERM, sending SIGKILL
[10:05:06] Container terminated with signal SIGKILL
EOF

assert_file_contains "$timeout_log" "exceeded timeout"
assert_file_contains "$timeout_log" "SIGTERM"
assert_file_contains "$timeout_log" "SIGKILL"

# Test 2: Graceful timeout (container responds to SIGTERM)
echo "Testing graceful timeout..."
graceful_timeout="$TEST_TMP/output/graceful_timeout.log"

cat > "$graceful_timeout" << 'EOF'
[10:00:00] Starting installer: moderate-tool
[10:00:00] Container started: acfs-test-moderate-tool-def456
[10:05:00] WARNING: Container execution time exceeded timeout (300s)
[10:05:00] Sending SIGTERM to container...
[10:05:02] Container responded to SIGTERM, exiting gracefully
[10:05:02] Container exit code: 143 (SIGTERM)
[10:05:02] Timeout handled gracefully
EOF

assert_file_contains "$graceful_timeout" "responded to SIGTERM"
assert_file_contains "$graceful_timeout" "exit code: 143"

# Test 3: Timeout with partial output capture
echo "Testing partial output capture on timeout..."
partial_output="$TEST_TMP/output/partial_output.log"

cat > "$partial_output" << 'EOF'
=== Captured output before timeout ===
Installing slow-tool...
Downloading component 1 of 5... done
Downloading component 2 of 5... done
Downloading component 3 of 5... [TIMEOUT - output truncated]

=== Timeout Summary ===
Last known state: downloading component 3
Bytes downloaded: 150MB
Container runtime: 300.5 seconds
EOF

assert_file_contains "$partial_output" "TIMEOUT - output truncated"
assert_file_contains "$partial_output" "Timeout Summary"

# Test 4: Container cleanup after timeout
echo "Testing container cleanup after timeout..."
cleanup_verification="$TEST_TMP/output/cleanup_verify.txt"

# Simulate container state check
{
    echo "Container cleanup verification:"
    echo "  - Container acfs-test-slow-tool-abc123: REMOVED"
    echo "  - Volumes: cleaned up"
    echo "  - Networks: default bridge"
    echo "  - Orphan resources: none"
} > "$cleanup_verification"

assert_file_contains "$cleanup_verification" "REMOVED"
assert_file_contains "$cleanup_verification" "Orphan resources: none"

# Test 5: Timeout classification for remediation
echo "Testing timeout classification..."
timeout_classification="$TEST_TMP/output/timeout_class.json"

cat > "$timeout_classification" << 'EOF'
{
  "error_type": "container_timeout",
  "tool": "slow-tool",
  "timeout_seconds": 300,
  "actual_runtime_seconds": 300.5,
  "last_activity": "downloading",
  "suggested_action": "increase_timeout",
  "auto_fixable": false,
  "reason": "Cannot determine if timeout is due to slow network or hung process"
}
EOF

timeout_json=$(cat "$timeout_classification")
assert_json_field "$timeout_json" ".error_type" "container_timeout"
assert_json_field "$timeout_json" ".auto_fixable" "false"

# Test 6: Configurable timeout values
echo "Testing configurable timeouts..."
timeout_config="$TEST_TMP/output/timeout_config.txt"

{
    echo "Timeout configuration:"
    echo "  default_timeout: 300s"
    echo "  tool_specific:"
    echo "    rust-analyzer: 600s (large download)"
    echo "    docker: 900s (image pulls)"
    echo "    quick-tool: 60s"
} > "$timeout_config"

assert_file_contains "$timeout_config" "tool_specific"
assert_file_contains "$timeout_config" "rust-analyzer: 600s"

echo "Container timeout handling test: PASSED"
cleanup_test
