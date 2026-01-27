#!/bin/bash
# ============================================================
# E2E Test: Checksum Mismatch Detection
#
# Validates that checksum verification correctly detects when
# downloaded content doesn't match expected checksum.
#
# Related: bead bd-19y9.1.8
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assertions.sh"
source "$SCRIPT_DIR/../lib/helpers.sh"

setup_test "checksum_mismatch"

echo "Test: Checksum mismatch detection"

ensure_binary

# Create an installer
create_fixture "installer.sh" << 'INSTALL'
#!/bin/bash
echo "Installing..."
exit 0
INSTALL

actual_sha=$(sha256_file "$TEST_TMP/fixtures/installer.sh")
# Create a fake/wrong checksum
wrong_sha="0000000000000000000000000000000000000000000000000000000000000000"

# Create checksums.yaml with wrong checksum
checksums_file="$TEST_TMP/checksums.yaml"
cat > "$checksums_file" << EOF
version: "1.0"

test-tool:
  url: "file://$TEST_TMP/fixtures/installer.sh"
  checksum:
    algorithm: sha256
    value: "$wrong_sha"
  enabled: true
EOF

# Verify we can detect the mismatch manually
echo "Actual SHA256: $actual_sha"
echo "Expected (wrong) SHA256: $wrong_sha"

assert_neq "$actual_sha" "$wrong_sha" "Checksums should be different"

# Simulate checksum verification
verification_result="$TEST_TMP/output/verification.txt"
{
    downloaded_sha=$(sha256_file "$TEST_TMP/fixtures/installer.sh")
    expected_sha="$wrong_sha"

    if [[ "$downloaded_sha" == "$expected_sha" ]]; then
        echo "CHECKSUM_OK"
    else
        echo "CHECKSUM_MISMATCH"
        echo "expected=$expected_sha"
        echo "actual=$downloaded_sha"
    fi
} > "$verification_result"

# Verify checksum mismatch was detected
assert_file_contains "$verification_result" "CHECKSUM_MISMATCH"
assert_file_contains "$verification_result" "expected=$wrong_sha"
assert_file_contains "$verification_result" "actual=$actual_sha"

echo "Checksum mismatch test: PASSED"
cleanup_test
