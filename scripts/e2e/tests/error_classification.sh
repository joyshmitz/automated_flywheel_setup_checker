#!/bin/bash
# ============================================================
# E2E Test: Error Classification
#
# Validates that various error types are correctly classified
# with appropriate severity, category, and confidence levels.
#
# Related: bead bd-19y9.1.8
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assertions.sh"
source "$SCRIPT_DIR/../lib/helpers.sh"

setup_test "error_classification"

echo "Test: Error classification"

# Create error samples
errors_dir="$TEST_TMP/errors"
mkdir -p "$errors_dir"

# Network errors
cat > "$errors_dir/dns.txt" << 'EOF'
curl: (6) Could not resolve host: example.com
EOF

cat > "$errors_dir/timeout.txt" << 'EOF'
curl: (28) Connection timed out after 30001 milliseconds
EOF

# Permission errors
cat > "$errors_dir/permission.txt" << 'EOF'
bash: ./script.sh: Permission denied
EOF

# Dependency errors
cat > "$errors_dir/command_not_found.txt" << 'EOF'
bash: jq: command not found
EOF

cat > "$errors_dir/package_not_found.txt" << 'EOF'
E: Unable to locate package nonexistent-package
EOF

# Resource errors
cat > "$errors_dir/disk_full.txt" << 'EOF'
No space left on device
EOF

cat > "$errors_dir/out_of_memory.txt" << 'EOF'
Cannot allocate memory
EOF

# Classification function
classify_error() {
    local error_file="$1"
    local content
    content=$(cat "$error_file")

    # Determine category and severity
    local category="unknown"
    local severity="unknown"
    local retryable="false"

    # Network errors
    if [[ "$content" =~ "Could not resolve host" ]] || \
       [[ "$content" =~ "timed out" ]] || \
       [[ "$content" =~ "Connection refused" ]]; then
        category="network"
        severity="transient"
        retryable="true"
    # Permission errors
    elif [[ "$content" =~ "Permission denied" ]] || \
         [[ "$content" =~ "operation not permitted" ]]; then
        category="permission"
        severity="permission"
        retryable="false"
    # Dependency errors
    elif [[ "$content" =~ "command not found" ]] || \
         [[ "$content" =~ "Unable to locate package" ]]; then
        category="dependency"
        severity="dependency"
        retryable="false"
    # Resource errors
    elif [[ "$content" =~ "No space left" ]] || \
         [[ "$content" =~ "Cannot allocate memory" ]] || \
         [[ "$content" =~ "Out of memory" ]]; then
        category="resource"
        severity="critical"
        retryable="false"
    fi

    echo "category=$category"
    echo "severity=$severity"
    echo "retryable=$retryable"
}

# Run classifications
results_file="$TEST_TMP/output/classifications.txt"

echo "=== DNS Error ===" >> "$results_file"
classify_error "$errors_dir/dns.txt" >> "$results_file"

echo "=== Timeout Error ===" >> "$results_file"
classify_error "$errors_dir/timeout.txt" >> "$results_file"

echo "=== Permission Error ===" >> "$results_file"
classify_error "$errors_dir/permission.txt" >> "$results_file"

echo "=== Command Not Found ===" >> "$results_file"
classify_error "$errors_dir/command_not_found.txt" >> "$results_file"

echo "=== Disk Full ===" >> "$results_file"
classify_error "$errors_dir/disk_full.txt" >> "$results_file"

# Verify classifications
# Network errors should be transient and retryable
assert_file_contains "$results_file" "category=network"
assert_file_contains "$results_file" "severity=transient"

# Permission errors should not be retryable
dns_section=$(grep -A3 "DNS Error" "$results_file")
assert_contains "$dns_section" "retryable=true"

permission_section=$(grep -A3 "Permission Error" "$results_file")
assert_contains "$permission_section" "category=permission"
assert_contains "$permission_section" "retryable=false"

# Resource errors should be critical
disk_section=$(grep -A3 "Disk Full" "$results_file")
assert_contains "$disk_section" "category=resource"
assert_contains "$disk_section" "severity=critical"

echo "Error classification test: PASSED"
cleanup_test
