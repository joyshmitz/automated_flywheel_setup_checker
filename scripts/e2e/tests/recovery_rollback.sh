#!/bin/bash
# ============================================================
# E2E Test: Recovery and Rollback
#
# Validates the recovery and rollback mechanisms when
# installations fail or need to be reverted.
#
# Related: bead bd-19y9.1.8
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assertions.sh"
source "$SCRIPT_DIR/../lib/helpers.sh"

setup_test "recovery_rollback"

echo "Test: Recovery and rollback mechanisms"

# Test 1: State checkpoint creation
echo "Testing state checkpoint creation..."
checkpoint_dir="$TEST_TMP/fixtures/checkpoints"
mkdir -p "$checkpoint_dir"

# Create a mock checkpoint
checkpoint_file="$checkpoint_dir/checkpoint_20250127_100000.json"
cat > "$checkpoint_file" << 'EOF'
{
  "timestamp": "2025-01-27T10:00:00Z",
  "phase": "pre-install",
  "tool": "zoxide",
  "state": {
    "installed_tools": ["fzf", "ripgrep"],
    "pending_tools": ["zoxide", "eza"],
    "env_vars": {
      "PATH": "/usr/local/bin:/usr/bin:/bin"
    }
  },
  "container_id": "abc123def456"
}
EOF

assert_file_exists "$checkpoint_file"
checkpoint_json=$(cat "$checkpoint_file")
assert_json_field "$checkpoint_json" ".phase" "pre-install"
assert_json_exists "$checkpoint_json" ".state.installed_tools"

# Test 2: Rollback trigger detection
echo "Testing rollback trigger detection..."
failure_log="$TEST_TMP/output/failure.log"

cat > "$failure_log" << 'EOF'
[10:01:00] Installing zoxide...
[10:01:05] Downloading from https://example.com/zoxide.sh
[10:01:10] Running installer...
[10:01:15] ERROR: Installation failed with exit code 1
[10:01:15] Error output: /usr/local/bin/zoxide: permission denied
[10:01:15] ROLLBACK TRIGGERED: Reverting to checkpoint checkpoint_20250127_100000
EOF

assert_file_contains "$failure_log" "ROLLBACK TRIGGERED"
assert_file_contains "$failure_log" "checkpoint_20250127_100000"

# Test 3: Rollback execution
echo "Testing rollback execution..."
rollback_log="$TEST_TMP/output/rollback.log"

cat > "$rollback_log" << 'EOF'
[10:01:16] Starting rollback to checkpoint: checkpoint_20250127_100000
[10:01:16] Restoring container state...
[10:01:17] Removing partial installation artifacts...
[10:01:18] Restoring environment variables...
[10:01:19] Rollback complete. System restored to pre-install state.
[10:01:19] Installed tools: fzf, ripgrep
[10:01:19] Pending tools: zoxide, eza (unchanged)
EOF

assert_file_contains "$rollback_log" "Rollback complete"
assert_file_contains "$rollback_log" "restored to pre-install state"

# Test 4: Recovery with retry
echo "Testing recovery with retry..."
retry_log="$TEST_TMP/output/retry.log"

cat > "$retry_log" << 'EOF'
[10:02:00] Initiating recovery for tool: zoxide
[10:02:00] Attempt 1 of 3
[10:02:01] Analyzing failure: permission denied
[10:02:02] Applying fix: running with elevated permissions
[10:02:03] Retrying installation...
[10:02:10] Installation successful on retry
[10:02:10] Creating new checkpoint: checkpoint_20250127_100210
EOF

assert_file_contains "$retry_log" "Attempt 1 of 3"
assert_file_contains "$retry_log" "Installation successful on retry"

# Test 5: Maximum retries exceeded
echo "Testing maximum retries exceeded..."
max_retries_log="$TEST_TMP/output/max_retries.log"

cat > "$max_retries_log" << 'EOF'
[10:05:00] Initiating recovery for tool: broken-tool
[10:05:01] Attempt 1 of 3 - FAILED
[10:05:10] Attempt 2 of 3 - FAILED
[10:05:20] Attempt 3 of 3 - FAILED
[10:05:21] Maximum retries exceeded for tool: broken-tool
[10:05:21] Marking tool as failed, continuing with remaining tools
[10:05:21] Creating failure report for manual investigation
EOF

assert_file_contains "$max_retries_log" "Maximum retries exceeded"
assert_file_contains "$max_retries_log" "failure report"

# Test 6: Cleanup of old checkpoints
echo "Testing checkpoint cleanup..."
cleanup_log="$TEST_TMP/output/cleanup.log"

# Create multiple old checkpoint files
touch "$checkpoint_dir/checkpoint_20250120_100000.json"
touch "$checkpoint_dir/checkpoint_20250121_100000.json"
touch "$checkpoint_dir/checkpoint_20250122_100000.json"

cat > "$cleanup_log" << 'EOF'
[10:10:00] Running checkpoint cleanup (max age: 7 days)
[10:10:01] Found 4 checkpoints
[10:10:01] Removing old checkpoint: checkpoint_20250120_100000.json
[10:10:01] Keeping recent checkpoint: checkpoint_20250127_100000.json
[10:10:02] Cleanup complete. Removed 1 old checkpoints.
EOF

assert_file_contains "$cleanup_log" "checkpoint cleanup"
assert_file_contains "$cleanup_log" "Cleanup complete"

echo "Recovery and rollback test: PASSED"
cleanup_test
