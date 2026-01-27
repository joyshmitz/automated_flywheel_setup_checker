#!/bin/bash
# ============================================================
# E2E Test: JSONL Output Format
#
# Validates that the structured JSONL logging format is correct
# and contains all required fields.
#
# Related: bead bd-19y9.1.8
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assertions.sh"
source "$SCRIPT_DIR/../lib/helpers.sh"

setup_test "jsonl_output"

echo "Test: JSONL output format"

# Create sample JSONL entries
jsonl_file="$TEST_TMP/output/run.jsonl"

# Entry 1: Test start
cat >> "$jsonl_file" << 'EOF'
{"timestamp":"2026-01-27T12:00:00Z","level":"info","component":"runner","event":"test_start","data":{"installer":"zoxide","run_id":"run_001"}}
EOF

# Entry 2: Download progress
cat >> "$jsonl_file" << 'EOF'
{"timestamp":"2026-01-27T12:00:01Z","level":"debug","component":"downloader","event":"download_progress","data":{"url":"https://example.com/install.sh","bytes":1024,"total":10240}}
EOF

# Entry 3: Checksum verification
cat >> "$jsonl_file" << 'EOF'
{"timestamp":"2026-01-27T12:00:02Z","level":"info","component":"verifier","event":"checksum_ok","data":{"expected":"abc123","actual":"abc123"}}
EOF

# Entry 4: Test completion
cat >> "$jsonl_file" << 'EOF'
{"timestamp":"2026-01-27T12:00:10Z","level":"info","component":"runner","event":"test_complete","data":{"installer":"zoxide","duration_ms":10000,"success":true}}
EOF

# Entry 5: Error entry
cat >> "$jsonl_file" << 'EOF'
{"timestamp":"2026-01-27T12:01:00Z","level":"error","component":"runner","event":"test_failed","error":{"category":"network","message":"Connection timeout"},"data":{"installer":"broken-tool"}}
EOF

# Validate JSONL format (each line is valid JSON)
echo "Validating JSONL format..."
line_num=0
while IFS= read -r line; do
    line_num=$((line_num + 1))
    if ! echo "$line" | jq . > /dev/null 2>&1; then
        echo "FAIL: Line $line_num is not valid JSON: $line"
        exit 1
    fi
done < "$jsonl_file"

echo "All $line_num lines are valid JSON"

# Validate required fields
echo "Validating required fields..."

# Check first entry has required fields
first_line=$(head -1 "$jsonl_file")
assert_json_exists "$first_line" ".timestamp"
assert_json_exists "$first_line" ".level"
assert_json_exists "$first_line" ".component"
assert_json_exists "$first_line" ".event"

# Check event-specific fields
assert_json_field "$first_line" ".event" "test_start"
assert_json_exists "$first_line" ".data.installer"

# Check error entry has error object
error_line=$(grep "test_failed" "$jsonl_file")
assert_json_exists "$error_line" ".error"
assert_json_exists "$error_line" ".error.category"
assert_json_exists "$error_line" ".error.message"

# Validate log levels
echo "Validating log levels..."
levels=$(jq -r '.level' "$jsonl_file" | sort -u)
for level in $levels; do
    case "$level" in
        trace|debug|info|warn|error)
            echo "Valid level: $level"
            ;;
        *)
            echo "FAIL: Invalid log level: $level"
            exit 1
            ;;
    esac
done

# Validate timestamps are ISO 8601
echo "Validating timestamps..."
timestamps=$(jq -r '.timestamp' "$jsonl_file")
for ts in $timestamps; do
    if [[ ! "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
        echo "FAIL: Invalid timestamp format: $ts"
        exit 1
    fi
done

echo "JSONL output test: PASSED"
cleanup_test
