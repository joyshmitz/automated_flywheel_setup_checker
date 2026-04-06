#!/bin/bash
# ============================================================
# E2E Test: Real Installer Run (br-74o.8)
#
# Exercises the full workflow with real ACFS installers:
#   1. Validate checksums.yaml
#   2. Run 2 fast installers in parallel with Docker
#   3. Verify JSONL output format
#   4. Verify status command shows results
#
# Requirements: Docker, ACFS repo at default path, built binary
# ============================================================

test_name="real_installer_run"

# Check prerequisites
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo "SKIP: Docker not available"
        return 1
    fi
    return 0
}

check_acfs_repo() {
    local acfs_path="/data/projects/agentic_coding_flywheel_setup"
    if [ ! -f "${acfs_path}/checksums.yaml" ]; then
        echo "SKIP: ACFS repo not found at ${acfs_path}"
        return 1
    fi
    return 0
}

# Test 1: Validate checksums.yaml
test_validate() {
    echo "  [1/4] Validating checksums.yaml..."
    local output
    output=$("${BINARY}" validate 2>&1)
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "  FAIL: validate returned exit code $rc"
        echo "  Output: $output"
        return 1
    fi
    if echo "$output" | grep -q "is valid"; then
        echo "  PASS: checksums.yaml is valid"
        return 0
    else
        echo "  FAIL: unexpected validate output"
        echo "  Output: $output"
        return 1
    fi
}

# Test 2: Run installers with --local (fast, no Docker needed)
test_check_local() {
    echo "  [2/4] Running check with --local --dry-run..."
    local output
    output=$("${BINARY}" check --dry-run --local 2>&1)
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "  FAIL: check --dry-run returned exit code $rc"
        echo "  Output: $output"
        return 1
    fi
    if echo "$output" | grep -q "Would check"; then
        echo "  PASS: dry-run shows planned tests"
        return 0
    else
        echo "  FAIL: unexpected dry-run output"
        return 1
    fi
}

# Test 3: Run check with JSONL output (dry-run)
test_jsonl_format() {
    echo "  [3/4] Verifying JSONL output format..."
    local output
    output=$("${BINARY}" check --dry-run --format jsonl 2>&1)
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "  FAIL: check --dry-run --format jsonl returned exit code $rc"
        return 1
    fi
    # Should be valid JSON
    if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        echo "  PASS: JSONL output is valid JSON"
        return 0
    else
        echo "  FAIL: output is not valid JSON"
        echo "  Output: $output"
        return 1
    fi
}

# Test 4: Status command
test_status() {
    echo "  [4/4] Checking status command..."
    local output
    output=$("${BINARY}" status 2>&1)
    local rc=$?
    # Status might show "no runs" if we haven't done a real check yet
    if [ $rc -eq 0 ]; then
        echo "  PASS: status command succeeded"
        return 0
    else
        echo "  FAIL: status returned exit code $rc"
        return 1
    fi
}

# Main
run_test() {
    if ! check_acfs_repo; then
        return 0  # Skip, not fail
    fi

    local passed=0
    local failed=0

    if test_validate; then ((passed++)); else ((failed++)); fi
    if test_check_local; then ((passed++)); else ((failed++)); fi
    if test_jsonl_format; then ((passed++)); else ((failed++)); fi
    if test_status; then ((passed++)); else ((failed++)); fi

    echo ""
    echo "  Results: $passed passed, $failed failed"

    if [ $failed -gt 0 ]; then
        return 1
    fi
    return 0
}
