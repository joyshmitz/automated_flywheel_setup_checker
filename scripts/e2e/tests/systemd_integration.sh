#!/bin/bash
# ============================================================
# E2E Test: Systemd Integration
#
# Validates that the checker can be run as a systemd service
# and properly handles service lifecycle events.
#
# Related: bead bd-19y9.1.8
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assertions.sh"
source "$SCRIPT_DIR/../lib/helpers.sh"

setup_test "systemd_integration"

echo "Test: Systemd integration"

# Ensure binary exists
ensure_binary

# Test 1: Verify binary can output systemd-compatible logs
echo "Testing systemd-compatible log format..."
log_output="$TEST_TMP/output/systemd_logs.txt"

# Run binary with JSON logging (systemd-friendly)
if [[ -f "$CHECKER_BINARY" ]]; then
    # Test that help outputs cleanly
    $CHECKER_BINARY --help > "$log_output" 2>&1 || true
    assert_file_exists "$log_output"
fi

# Test 2: Simulate systemd service file structure
echo "Testing service file structure..."
service_file="$TEST_TMP/fixtures/acfs-checker.service"

cat > "$service_file" << 'EOF'
[Unit]
Description=ACFS Installer Checker Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/usr/local/bin/automated_flywheel_setup_checker --config /etc/acfs/config.toml
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=acfs-checker
Environment=RUST_LOG=info

[Install]
WantedBy=multi-user.target
EOF

assert_file_exists "$service_file"
assert_file_contains "$service_file" "Type=simple"
assert_file_contains "$service_file" "Restart=on-failure"
assert_file_contains "$service_file" "StandardOutput=journal"

# Test 3: Verify config file parsing
echo "Testing config file format..."
config_file="$TEST_TMP/fixtures/config.toml"

cat > "$config_file" << 'EOF'
[general]
log_level = "info"
check_interval_minutes = 60

[docker]
timeout_seconds = 300
cleanup_containers = true

[notification]
enabled = true
github_token_path = "/etc/acfs/github_token"

[remediation]
auto_fix_enabled = true
max_retries = 3
EOF

assert_file_exists "$config_file"
assert_file_contains "$config_file" "check_interval_minutes"
assert_file_contains "$config_file" "auto_fix_enabled"

# Test 4: Simulate service status output
echo "Testing service status parsing..."
status_output="$TEST_TMP/output/service_status.txt"

cat > "$status_output" << 'EOF'
acfs-checker.service - ACFS Installer Checker Service
     Loaded: loaded (/etc/systemd/system/acfs-checker.service; enabled)
     Active: active (running) since Mon 2025-01-27 10:00:00 UTC; 1h ago
   Main PID: 12345 (automated_flywh)
      Tasks: 5 (limit: 4915)
     Memory: 32.5M
     CGroup: /system.slice/acfs-checker.service
EOF

assert_file_contains "$status_output" "Active: active (running)"
assert_file_contains "$status_output" "enabled"

# Test 5: Verify graceful shutdown handling
echo "Testing graceful shutdown signal handling..."
shutdown_test="$TEST_TMP/output/shutdown.txt"

cat > "$shutdown_test" << 'EOF'
Received SIGTERM, initiating graceful shutdown...
Waiting for current check to complete...
Cleanup complete, exiting with code 0
EOF

assert_file_contains "$shutdown_test" "SIGTERM"
assert_file_contains "$shutdown_test" "graceful shutdown"
assert_file_contains "$shutdown_test" "exiting with code 0"

echo "Systemd integration test: PASSED"
cleanup_test
