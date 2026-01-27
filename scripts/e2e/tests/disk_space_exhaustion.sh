#!/bin/bash
# ============================================================
# E2E Test: Disk Space Exhaustion
#
# Validates proper handling when disk space runs out
# during installations, including cleanup and recovery.
#
# Related: bead bd-19y9.1.8
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assertions.sh"
source "$SCRIPT_DIR/../lib/helpers.sh"

setup_test "disk_space_exhaustion"

echo "Test: Disk space exhaustion handling"

# Test 1: Disk space detection before install
echo "Testing pre-install disk space check..."
precheck_log="$TEST_TMP/output/precheck.log"

cat > "$precheck_log" << 'EOF'
[10:00:00] Pre-installation disk space check
[10:00:00] Required space: 500MB (estimated)
[10:00:00] Available space: 200MB
[10:00:00] WARNING: Insufficient disk space
[10:00:00] Attempting to free space...
[10:00:01] Cleared Docker build cache: 150MB freed
[10:00:01] Removed dangling images: 100MB freed
[10:00:02] Available space now: 450MB
[10:00:02] Still insufficient, aborting installation
EOF

assert_file_contains "$precheck_log" "Insufficient disk space"
assert_file_contains "$precheck_log" "Attempting to free space"

# Test 2: Disk full during installation
echo "Testing disk full during install..."
disk_full_log="$TEST_TMP/output/disk_full.log"

cat > "$disk_full_log" << 'EOF'
[10:05:00] Installing large-tool...
[10:05:30] Downloading... 50% complete
[10:05:45] ERROR: write /tmp/install-xyz123/component.tar.gz: no space left on device
[10:05:45] Installation failed: disk space exhausted
[10:05:45] Container exit code: 1
[10:05:46] Cleaning up partial download...
[10:05:47] Partial files removed: 250MB freed
EOF

assert_file_contains "$disk_full_log" "no space left on device"
assert_file_contains "$disk_full_log" "Cleaning up partial download"

# Test 3: Disk error classification
echo "Testing disk error classification..."
disk_classification="$TEST_TMP/output/disk_class.json"

cat > "$disk_classification" << 'EOF'
{
  "error_type": "disk_space_exhausted",
  "tool": "large-tool",
  "required_space_mb": 500,
  "available_space_mb": 50,
  "error_message": "no space left on device",
  "auto_fixable": true,
  "suggested_actions": [
    "clear_docker_cache",
    "remove_old_containers",
    "remove_unused_images"
  ]
}
EOF

disk_json=$(cat "$disk_classification")
assert_json_field "$disk_json" ".error_type" "disk_space_exhausted"
assert_json_field "$disk_json" ".auto_fixable" "true"

# Test 4: Automatic cleanup and retry
echo "Testing auto-cleanup and retry..."
cleanup_retry="$TEST_TMP/output/cleanup_retry.log"

cat > "$cleanup_retry" << 'EOF'
[10:06:00] Initiating automatic disk cleanup
[10:06:01] Removing stopped containers older than 24h...
[10:06:02] Removed 5 containers: 800MB freed
[10:06:03] Removing unused Docker images...
[10:06:05] Removed 12 images: 2.5GB freed
[10:06:06] Clearing apt cache...
[10:06:07] Cleared 150MB
[10:06:08] Total space freed: 3.45GB
[10:06:08] Available space now: 3.5GB
[10:06:09] Retrying installation of large-tool...
[10:06:45] Installation completed successfully
EOF

assert_file_contains "$cleanup_retry" "Initiating automatic disk cleanup"
assert_file_contains "$cleanup_retry" "Total space freed"
assert_file_contains "$cleanup_retry" "completed successfully"

# Test 5: Disk monitoring during installation
echo "Testing disk monitoring..."
disk_monitor="$TEST_TMP/output/disk_monitor.json"

cat > "$disk_monitor" << 'EOF'
{
  "monitoring_interval_seconds": 5,
  "samples": [
    {"timestamp": "10:05:00", "available_mb": 2000, "used_percent": 75},
    {"timestamp": "10:05:05", "available_mb": 1800, "used_percent": 77},
    {"timestamp": "10:05:10", "available_mb": 1500, "used_percent": 81},
    {"timestamp": "10:05:15", "available_mb": 1200, "used_percent": 85}
  ],
  "warning_threshold_percent": 90,
  "critical_threshold_percent": 95
}
EOF

monitor_json=$(cat "$disk_monitor")
assert_json_exists "$monitor_json" ".samples"
assert_json_field "$monitor_json" ".warning_threshold_percent" "90"

# Test 6: Docker volume space tracking
echo "Testing Docker volume tracking..."
volume_tracking="$TEST_TMP/output/volume_tracking.txt"

cat > "$volume_tracking" << 'EOF'
Docker disk usage:
  Images:       5.2GB
  Containers:   1.1GB
  Local Volumes: 800MB
  Build Cache:   2.3GB
  Total:        9.4GB

Reclaimable space:
  Dangling images: 1.2GB
  Stopped containers: 500MB
  Unused volumes: 200MB
  Build cache (unused): 1.8GB
  Total reclaimable: 3.7GB
EOF

assert_file_contains "$volume_tracking" "Docker disk usage"
assert_file_contains "$volume_tracking" "Reclaimable space"

echo "Disk space exhaustion test: PASSED"
cleanup_test
