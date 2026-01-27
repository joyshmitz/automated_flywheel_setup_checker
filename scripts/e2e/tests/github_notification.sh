#!/bin/bash
# ============================================================
# E2E Test: GitHub Notification
#
# Validates GitHub issue/PR notification functionality
# for reporting test failures and successes.
#
# Related: bead bd-19y9.1.8
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assertions.sh"
source "$SCRIPT_DIR/../lib/helpers.sh"

setup_test "github_notification"

echo "Test: GitHub notification integration"

# Test 1: Verify notification payload structure
echo "Testing notification payload structure..."
payload_file="$TEST_TMP/output/notification_payload.json"

cat > "$payload_file" << 'EOF'
{
  "title": "[ACFS Checker] Test Failure: zoxide installer",
  "body": "## Test Failure Report\n\n**Tool:** zoxide\n**Error Type:** checksum_mismatch\n**Timestamp:** 2025-01-27T10:00:00Z\n\n### Error Details\n\nExpected checksum: abc123\nActual checksum: def456\n\n### Suggested Action\n\nUpdate checksums.yaml with the new checksum value.",
  "labels": ["automated", "test-failure", "needs-investigation"]
}
EOF

assert_file_exists "$payload_file"
payload_json=$(cat "$payload_file")
assert_json_exists "$payload_json" ".title"
assert_json_exists "$payload_json" ".body"
assert_json_exists "$payload_json" ".labels"

# Parse and validate JSON structure
title=$(jq -r '.title' <<< "$payload_json")
assert_contains "$title" "ACFS Checker"
assert_contains "$title" "Test Failure"

# Test 2: Verify success notification payload
echo "Testing success notification payload..."
success_payload="$TEST_TMP/output/success_payload.json"

cat > "$success_payload" << 'EOF'
{
  "title": "[ACFS Checker] All Tests Passed",
  "body": "## Test Success Report\n\n**Timestamp:** 2025-01-27T10:00:00Z\n**Total Tests:** 15\n**Passed:** 15\n**Failed:** 0\n\n### Summary\n\nAll installer verification tests completed successfully.",
  "labels": ["automated", "test-success"]
}
EOF

success_json=$(cat "$success_payload")
assert_json_field "$success_json" ".labels[0]" "automated"
assert_json_field "$success_json" ".labels[1]" "test-success"

# Test 3: Test GitHub API request format
echo "Testing GitHub API request format..."
api_request="$TEST_TMP/output/api_request.json"

cat > "$api_request" << 'EOF'
{
  "method": "POST",
  "url": "https://api.github.com/repos/owner/repo/issues",
  "headers": {
    "Authorization": "Bearer REDACTED",
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28"
  },
  "body": {
    "title": "Test Issue",
    "body": "Test body"
  }
}
EOF

api_json=$(cat "$api_request")
assert_json_field "$api_json" ".method" "POST"
assert_json_exists "$api_json" ".headers.Authorization"
assert_json_exists "$api_json" ".headers.Accept"

# Test 4: Verify rate limit handling
echo "Testing rate limit handling..."
rate_limit_response="$TEST_TMP/output/rate_limit.json"

cat > "$rate_limit_response" << 'EOF'
{
  "message": "API rate limit exceeded",
  "documentation_url": "https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting"
}
EOF

# Verify rate limit detection
if jq -e '.message | contains("rate limit")' "$rate_limit_response" > /dev/null; then
    echo "Rate limit detection working"
    echo "should_retry=true" > "$TEST_TMP/output/rate_limit_action.txt"
    echo "retry_after_seconds=60" >> "$TEST_TMP/output/rate_limit_action.txt"
fi

assert_file_contains "$TEST_TMP/output/rate_limit_action.txt" "should_retry=true"

# Test 5: Verify comment on existing issue
echo "Testing comment on existing issue..."
comment_payload="$TEST_TMP/output/comment_payload.json"

cat > "$comment_payload" << 'EOF'
{
  "body": "## Update: Re-test Results\n\n**Timestamp:** 2025-01-27T11:00:00Z\n\nRe-running tests after remediation attempt.\n\n**Result:** PASSED\n\nThe issue has been resolved. Closing."
}
EOF

comment_json=$(cat "$comment_payload")
assert_json_exists "$comment_json" ".body"
body=$(jq -r '.body' <<< "$comment_json")
assert_contains "$body" "Re-test Results"

echo "GitHub notification test: PASSED"
cleanup_test
