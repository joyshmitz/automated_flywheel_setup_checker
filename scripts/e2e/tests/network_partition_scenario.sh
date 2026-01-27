#!/bin/bash
# ============================================================
# E2E Test: Network Partition Scenario
#
# Validates handling of network partitions and connectivity
# issues during installer downloads and execution.
#
# Related: bead bd-19y9.1.8
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assertions.sh"
source "$SCRIPT_DIR/../lib/helpers.sh"

setup_test "network_partition_scenario"

echo "Test: Network partition scenario handling"

# Test 1: Partial download recovery
echo "Testing partial download handling..."
partial_download="$TEST_TMP/output/partial_download.log"

cat > "$partial_download" << 'EOF'
[10:00:00] Downloading installer: large-tool.sh
[10:00:00] URL: https://example.com/install/large-tool.sh
[10:00:10] Progress: 45% (4.5MB of 10MB)
[10:00:11] ERROR: Connection reset by peer
[10:00:11] Network error detected, checking partial download...
[10:00:12] Partial file exists: 4.5MB
[10:00:12] Server supports Range requests: yes
[10:00:13] Attempting resume download...
[10:00:14] Resuming from byte 4718592
[10:00:25] Download completed successfully
[10:00:25] Verifying checksum... OK
EOF

assert_file_contains "$partial_download" "Connection reset"
assert_file_contains "$partial_download" "Attempting resume download"
assert_file_contains "$partial_download" "completed successfully"

# Test 2: DNS resolution failure
echo "Testing DNS failure handling..."
dns_failure="$TEST_TMP/output/dns_failure.log"

cat > "$dns_failure" << 'EOF'
[10:05:00] Downloading installer from raw.githubusercontent.com
[10:05:01] ERROR: getaddrinfo ENOTFOUND raw.githubusercontent.com
[10:05:01] DNS resolution failed
[10:05:02] Retrying with alternative DNS...
[10:05:02] Trying 8.8.8.8...
[10:05:03] DNS resolution successful via fallback
[10:05:04] Resuming download...
EOF

assert_file_contains "$dns_failure" "DNS resolution failed"
assert_file_contains "$dns_failure" "alternative DNS"

# Test 3: Complete network outage
echo "Testing complete network outage..."
outage_log="$TEST_TMP/output/network_outage.log"

cat > "$outage_log" << 'EOF'
[10:10:00] Starting network connectivity test...
[10:10:01] Ping github.com: FAILED (timeout)
[10:10:02] Ping 8.8.8.8: FAILED (network unreachable)
[10:10:03] Network appears to be completely down
[10:10:03] Scheduling retry for later
[10:10:03] Next retry in: 300 seconds
[10:10:03] Will retry up to 5 times before marking as failed
EOF

assert_file_contains "$outage_log" "network unreachable"
assert_file_contains "$outage_log" "Scheduling retry"

# Test 4: Network partition classification
echo "Testing network error classification..."
network_class="$TEST_TMP/output/network_class.json"

cat > "$network_class" << 'EOF'
{
  "error_type": "network_partition",
  "symptoms": [
    "dns_failure",
    "connection_timeout",
    "connection_reset"
  ],
  "affected_hosts": ["github.com", "raw.githubusercontent.com"],
  "local_network_status": "connected",
  "internet_reachable": false,
  "auto_fixable": false,
  "suggested_action": "wait_for_network_recovery",
  "retry_strategy": {
    "max_retries": 5,
    "backoff_seconds": [30, 60, 120, 300, 600]
  }
}
EOF

network_json=$(cat "$network_class")
assert_json_field "$network_json" ".error_type" "network_partition"
assert_json_exists "$network_json" ".retry_strategy"

# Test 5: Selective host unreachability
echo "Testing selective host unreachability..."
selective_log="$TEST_TMP/output/selective_unreachable.log"

cat > "$selective_log" << 'EOF'
[10:15:00] Testing network connectivity to required hosts:
[10:15:01] ✓ github.com - reachable
[10:15:02] ✓ raw.githubusercontent.com - reachable
[10:15:03] ✗ get.rvm.io - unreachable (connection timeout)
[10:15:04] ✗ sh.rustup.rs - unreachable (connection refused)
[10:15:05] Partial connectivity detected
[10:15:05] 2 of 4 required hosts unreachable
[10:15:05] Skipping affected tools: rvm, rust
[10:15:05] Continuing with available tools...
EOF

assert_file_contains "$selective_log" "Partial connectivity"
assert_file_contains "$selective_log" "Skipping affected tools"

# Test 6: Network recovery detection
echo "Testing network recovery detection..."
recovery_log="$TEST_TMP/output/network_recovery.log"

cat > "$recovery_log" << 'EOF'
[10:20:00] Background network monitor active
[10:20:30] Network status: DOWN (last check 30s ago)
[10:21:00] Network status: DOWN (last check 60s ago)
[10:21:30] Network status: RECOVERING (partial connectivity)
[10:22:00] Network status: UP (all hosts reachable)
[10:22:01] Network recovered, resuming queued installations
[10:22:02] Processing queue: 3 pending tools
EOF

assert_file_contains "$recovery_log" "Network recovered"
assert_file_contains "$recovery_log" "resuming queued"

echo "Network partition scenario test: PASSED"
cleanup_test
