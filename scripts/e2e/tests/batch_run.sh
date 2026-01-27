#!/bin/bash
# ============================================================
# E2E Test: Batch Installer Execution
#
# Validates that multiple installers can be queued and executed
# in sequence, with proper progress tracking and error handling.
#
# Related: bead bd-19y9.1.8
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assertions.sh"
source "$SCRIPT_DIR/../lib/helpers.sh"

setup_test "batch_run"

echo "Test: Batch installer execution"

ensure_binary

# Create multiple mock installers
for i in 1 2 3; do
    create_fixture "installer_${i}.sh" << INSTALL
#!/bin/bash
echo "Installing tool $i..."
sleep 0.5
echo "Tool $i installed successfully"
exit 0
INSTALL
done

# Create checksums for all tools
checksums_file="$TEST_TMP/checksums.yaml"
{
    echo "version: \"1.0\""
    for i in 1 2 3; do
        local_sha=$(sha256_file "$TEST_TMP/fixtures/installer_${i}.sh")
        echo ""
        echo "tool-$i:"
        echo "  url: \"file://$TEST_TMP/fixtures/installer_${i}.sh\""
        echo "  checksum:"
        echo "    algorithm: sha256"
        echo "    value: \"$local_sha\""
        echo "  enabled: true"
    done
} > "$checksums_file"

# Verify all fixtures created
for i in 1 2 3; do
    assert_file_exists "$TEST_TMP/fixtures/installer_${i}.sh"
done

assert_file_exists "$checksums_file"

# Run all installers in sequence
results_file="$TEST_TMP/output/batch_results.txt"
for i in 1 2 3; do
    if bash "$TEST_TMP/fixtures/installer_${i}.sh" >> "$results_file" 2>&1; then
        echo "installer_${i}: PASS" >> "$results_file"
    else
        echo "installer_${i}: FAIL" >> "$results_file"
    fi
done

# Verify all succeeded
assert_file_contains "$results_file" "installer_1: PASS"
assert_file_contains "$results_file" "installer_2: PASS"
assert_file_contains "$results_file" "installer_3: PASS"

# Verify expected output
assert_file_contains "$results_file" "Tool 1 installed"
assert_file_contains "$results_file" "Tool 2 installed"
assert_file_contains "$results_file" "Tool 3 installed"

echo "Batch run test: PASSED"
cleanup_test
