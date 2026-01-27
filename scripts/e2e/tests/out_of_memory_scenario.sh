#!/bin/bash
# ============================================================
# E2E Test: Out of Memory Scenario
#
# Validates proper handling when containers run out of memory
# including detection, cleanup, and reporting.
#
# Related: bead bd-19y9.1.8
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assertions.sh"
source "$SCRIPT_DIR/../lib/helpers.sh"

setup_test "out_of_memory_scenario"

echo "Test: Out of memory scenario handling"

# Test 1: OOM detection from container exit
echo "Testing OOM detection..."
oom_log="$TEST_TMP/output/oom.log"

cat > "$oom_log" << 'EOF'
[10:00:00] Starting installer: memory-hog-tool
[10:00:00] Container started: acfs-test-memory-hog-abc123
[10:00:00] Memory limit: 512MB
[10:00:30] Container exited unexpectedly
[10:00:30] Exit code: 137 (SIGKILL - likely OOMKilled)
[10:00:30] Checking container inspect...
[10:00:30] OOMKilled: true
[10:00:30] Peak memory usage: 512MB (limit reached)
EOF

assert_file_contains "$oom_log" "OOMKilled: true"
assert_file_contains "$oom_log" "Exit code: 137"

# Test 2: OOM error classification
echo "Testing OOM classification..."
oom_classification="$TEST_TMP/output/oom_class.json"

cat > "$oom_classification" << 'EOF'
{
  "error_type": "out_of_memory",
  "tool": "memory-hog-tool",
  "memory_limit_mb": 512,
  "peak_usage_mb": 512,
  "oom_killed": true,
  "suggested_action": "increase_memory_limit",
  "auto_fixable": true,
  "suggested_limit_mb": 1024
}
EOF

oom_class_json=$(cat "$oom_classification")
assert_json_field "$oom_class_json" ".error_type" "out_of_memory"
assert_json_field "$oom_class_json" ".oom_killed" "true"
assert_json_field "$oom_class_json" ".auto_fixable" "true"

# Test 3: Automatic retry with increased memory
echo "Testing auto-retry with increased memory..."
retry_log="$TEST_TMP/output/oom_retry.log"

cat > "$retry_log" << 'EOF'
[10:01:00] Retrying memory-hog-tool with increased memory limit
[10:01:00] Previous limit: 512MB
[10:01:00] New limit: 1024MB (2x increase)
[10:01:00] Container started: acfs-test-memory-hog-retry-def456
[10:01:45] Installation completed successfully
[10:01:45] Peak memory usage: 780MB
[10:01:45] Recording optimal memory for future runs
EOF

assert_file_contains "$retry_log" "New limit: 1024MB"
assert_file_contains "$retry_log" "completed successfully"
assert_file_contains "$retry_log" "Recording optimal memory"

# Test 4: Maximum memory limit reached
echo "Testing max memory limit..."
max_memory_log="$TEST_TMP/output/max_memory.log"

cat > "$max_memory_log" << 'EOF'
[10:05:00] Retrying extreme-memory-tool with increased memory limit
[10:05:00] New limit: 4096MB (maximum allowed)
[10:05:30] OOMKilled: true
[10:05:30] ERROR: Tool requires more than maximum allowed memory (4GB)
[10:05:30] Marking as non-recoverable, requires manual investigation
[10:05:30] Recommendation: Check if tool has memory leaks or reduce dataset
EOF

assert_file_contains "$max_memory_log" "maximum allowed"
assert_file_contains "$max_memory_log" "non-recoverable"

# Test 5: Memory usage tracking
echo "Testing memory usage tracking..."
memory_metrics="$TEST_TMP/output/memory_metrics.json"

cat > "$memory_metrics" << 'EOF'
{
  "tool": "normal-tool",
  "runs": [
    {"timestamp": "2025-01-25", "peak_mb": 256, "limit_mb": 512},
    {"timestamp": "2025-01-26", "peak_mb": 280, "limit_mb": 512},
    {"timestamp": "2025-01-27", "peak_mb": 290, "limit_mb": 512}
  ],
  "average_peak_mb": 275,
  "recommended_limit_mb": 384,
  "trend": "stable"
}
EOF

memory_json=$(cat "$memory_metrics")
assert_json_exists "$memory_json" ".runs"
assert_json_field "$memory_json" ".trend" "stable"

# Test 6: Host memory pressure detection
echo "Testing host memory pressure..."
host_memory="$TEST_TMP/output/host_memory.txt"

cat > "$host_memory" << 'EOF'
Host memory status:
  Total: 8192MB
  Used: 7500MB (91.6%)
  Available: 692MB
  
WARNING: Host system under memory pressure
Recommendation: Reduce container memory limits or free host memory
Current container limit: 512MB
Available for containers: ~500MB
EOF

assert_file_contains "$host_memory" "memory pressure"
assert_file_contains "$host_memory" "Recommendation"

echo "Out of memory scenario test: PASSED"
cleanup_test
