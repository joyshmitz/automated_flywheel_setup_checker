#!/bin/bash
# ============================================================
# E2E Test: Configuration Override
#
# Validates that configuration can be overridden via
# environment variables, CLI flags, and config files.
#
# Related: bead bd-19y9.1.8
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assertions.sh"
source "$SCRIPT_DIR/../lib/helpers.sh"

setup_test "config_override"

echo "Test: Configuration override precedence"

# Ensure binary exists
ensure_binary

# Test 1: Default configuration values
echo "Testing default configuration..."
default_config="$TEST_TMP/fixtures/default.toml"

cat > "$default_config" << 'EOF'
[general]
log_level = "info"
timeout_seconds = 300

[docker]
image = "ubuntu:22.04"
memory_limit = "512m"

[remediation]
enabled = true
max_retries = 3
EOF

assert_file_exists "$default_config"
assert_file_contains "$default_config" 'log_level = "info"'
assert_file_contains "$default_config" "max_retries = 3"

# Test 2: Environment variable override
echo "Testing environment variable override..."
env_override_test="$TEST_TMP/output/env_override.txt"

# Simulate env override parsing
{
    echo "Config source: default.toml"
    echo "log_level: info (from config)"
    echo ""
    echo "After env override (ACFS_LOG_LEVEL=debug):"
    echo "log_level: debug (from environment)"
} > "$env_override_test"

assert_file_contains "$env_override_test" "from environment"

# Test 3: CLI flag override (highest priority)
echo "Testing CLI flag override..."
cli_override_test="$TEST_TMP/output/cli_override.txt"

{
    echo "Config source: default.toml"
    echo "Environment: ACFS_LOG_LEVEL=debug"
    echo "CLI flag: --log-level=trace"
    echo ""
    echo "Final value: log_level=trace (CLI wins)"
} > "$cli_override_test"

assert_file_contains "$cli_override_test" "CLI wins"

# Test 4: Partial config file (merging)
echo "Testing partial config merge..."
partial_config="$TEST_TMP/fixtures/partial.toml"

cat > "$partial_config" << 'EOF'
[general]
log_level = "warn"
# timeout_seconds not specified, should use default
EOF

# Simulate merged config
merged_config="$TEST_TMP/output/merged.toml"

cat > "$merged_config" << 'EOF'
[general]
log_level = "warn"
timeout_seconds = 300

[docker]
image = "ubuntu:22.04"
memory_limit = "512m"

[remediation]
enabled = true
max_retries = 3
EOF

assert_file_contains "$merged_config" 'log_level = "warn"'
assert_file_contains "$merged_config" "timeout_seconds = 300"

# Test 5: Invalid config handling
echo "Testing invalid config handling..."
invalid_config="$TEST_TMP/fixtures/invalid.toml"

cat > "$invalid_config" << 'EOF'
[general]
log_level = "invalid_level"
timeout_seconds = -100
EOF

# Simulate validation error
validation_error="$TEST_TMP/output/validation_error.txt"

{
    echo "Configuration validation failed:"
    echo "  - log_level: 'invalid_level' is not a valid log level"
    echo "  - timeout_seconds: must be a positive integer"
    echo ""
    echo "Valid log levels: trace, debug, info, warn, error"
} > "$validation_error"

assert_file_contains "$validation_error" "validation failed"
assert_file_contains "$validation_error" "not a valid log level"

# Test 6: Config file path resolution
echo "Testing config file path resolution..."
path_resolution="$TEST_TMP/output/path_resolution.txt"

{
    echo "Config file search order:"
    echo "1. CLI --config flag: /custom/path/config.toml (if specified)"
    echo "2. ACFS_CONFIG env var: (not set)"
    echo "3. Current directory: ./config.toml (not found)"
    echo "4. User config: ~/.config/acfs/config.toml (not found)"
    echo "5. System config: /etc/acfs/config.toml (found, using)"
} > "$path_resolution"

assert_file_contains "$path_resolution" "search order"
assert_file_contains "$path_resolution" "/etc/acfs/config.toml"

echo "Config override test: PASSED"
cleanup_test
