#!/bin/bash
# ============================================================
# E2E Test Assertion Library
#
# Provides assertion functions for E2E tests.
#
# Related: bead bd-19y9.1.8
# ============================================================

# Assertion logging
_assertion_log_fail() {
    echo -e "\033[31m[ASSERTION FAILED]\033[0m $*" >&2
}

_assertion_log_info() {
    echo -e "\033[34m[ASSERTION]\033[0m $*"
}

# Assert two values are equal
# Usage: assert_eq "$actual" "$expected" "message"
assert_eq() {
    local actual="$1"
    local expected="$2"
    local msg="${3:-Values should be equal}"

    if [[ "$actual" != "$expected" ]]; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  Expected: $expected"
        _assertion_log_fail "  Actual:   $actual"
        exit 1
    fi
}

# Assert two values are not equal
# Usage: assert_neq "$actual" "$unexpected" "message"
assert_neq() {
    local actual="$1"
    local unexpected="$2"
    local msg="${3:-Values should not be equal}"

    if [[ "$actual" == "$unexpected" ]]; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  Got: $actual"
        exit 1
    fi
}

# Assert a condition is true (non-empty string)
# Usage: assert_true "$condition" "message"
assert_true() {
    local condition="$1"
    local msg="${2:-Condition should be true}"

    if [[ -z "$condition" ]]; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  Condition evaluated to empty/false"
        exit 1
    fi
}

# Assert a condition is false (empty string)
# Usage: assert_false "$condition" "message"
assert_false() {
    local condition="$1"
    local msg="${2:-Condition should be false}"

    if [[ -n "$condition" ]]; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  Condition evaluated to: $condition"
        exit 1
    fi
}

# Assert a string matches a regex pattern
# Usage: assert_matches "$actual" "pattern" "message"
assert_matches() {
    local actual="$1"
    local pattern="$2"
    local msg="${3:-String should match pattern}"

    if [[ ! "$actual" =~ $pattern ]]; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  Pattern: $pattern"
        _assertion_log_fail "  Actual:  $actual"
        exit 1
    fi
}

# Assert a string does NOT match a regex pattern
# Usage: assert_not_matches "$actual" "pattern" "message"
assert_not_matches() {
    local actual="$1"
    local pattern="$2"
    local msg="${3:-String should not match pattern}"

    if [[ "$actual" =~ $pattern ]]; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  Pattern that should not match: $pattern"
        _assertion_log_fail "  Actual:  $actual"
        exit 1
    fi
}

# Assert a string contains a substring
# Usage: assert_contains "$haystack" "$needle" "message"
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-String should contain substring}"

    if [[ ! "$haystack" == *"$needle"* ]]; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  Looking for: $needle"
        _assertion_log_fail "  In: $haystack"
        exit 1
    fi
}

# Assert a JSON field has expected value
# Usage: assert_json_field "$json_or_file" ".path.to.field" "expected_value"
# Note: First argument can be a file path or JSON content
assert_json_field() {
    local json_or_file="$1"
    local path="$2"
    local expected="$3"
    local msg="${4:-JSON field should have expected value}"

    local json
    # Check if it's a file path
    if [[ -f "$json_or_file" ]]; then
        json=$(cat "$json_or_file")
    else
        json="$json_or_file"
    fi

    local actual
    actual=$(echo "$json" | jq -r "$path" 2>/dev/null)

    if [[ "$actual" != "$expected" ]]; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  JSON path: $path"
        _assertion_log_fail "  Expected:  $expected"
        _assertion_log_fail "  Actual:    $actual"
        exit 1
    fi
}

# Assert a JSON path exists (is not null)
# Usage: assert_json_exists "$json_or_file" ".path.to.field"
# Note: First argument can be a file path or JSON content
assert_json_exists() {
    local json_or_file="$1"
    local path="$2"
    local msg="${3:-JSON path should exist}"

    local json
    # Check if it's a file path
    if [[ -f "$json_or_file" ]]; then
        json=$(cat "$json_or_file")
    else
        json="$json_or_file"
    fi

    if ! echo "$json" | jq -e "$path" > /dev/null 2>&1; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  JSON path does not exist: $path"
        _assertion_log_fail "  JSON: $json"
        exit 1
    fi
}

# Assert a JSON path does NOT exist (is null)
# Usage: assert_json_not_exists "$json_or_file" ".path.to.field"
# Note: First argument can be a file path or JSON content
assert_json_not_exists() {
    local json_or_file="$1"
    local path="$2"
    local msg="${3:-JSON path should not exist}"

    local json
    # Check if it's a file path
    if [[ -f "$json_or_file" ]]; then
        json=$(cat "$json_or_file")
    else
        json="$json_or_file"
    fi

    if echo "$json" | jq -e "$path" > /dev/null 2>&1; then
        local value
        value=$(echo "$json" | jq -r "$path")
        _assertion_log_fail "$msg"
        _assertion_log_fail "  JSON path exists: $path"
        _assertion_log_fail "  Value: $value"
        exit 1
    fi
}

# Assert a file exists
# Usage: assert_file_exists "/path/to/file"
assert_file_exists() {
    local path="$1"
    local msg="${2:-File should exist}"

    if [[ ! -f "$path" ]]; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  File does not exist: $path"
        exit 1
    fi
}

# Assert a file does NOT exist
# Usage: assert_file_not_exists "/path/to/file"
assert_file_not_exists() {
    local path="$1"
    local msg="${2:-File should not exist}"

    if [[ -f "$path" ]]; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  File exists: $path"
        exit 1
    fi
}

# Assert a directory exists
# Usage: assert_dir_exists "/path/to/dir"
assert_dir_exists() {
    local path="$1"
    local msg="${2:-Directory should exist}"

    if [[ ! -d "$path" ]]; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  Directory does not exist: $path"
        exit 1
    fi
}

# Assert a file contains a pattern
# Usage: assert_file_contains "/path/to/file" "pattern"
assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local msg="${3:-File should contain pattern}"

    if [[ ! -f "$file" ]]; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  File does not exist: $file"
        exit 1
    fi

    if ! grep -q "$pattern" "$file"; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  File: $file"
        _assertion_log_fail "  Pattern not found: $pattern"
        exit 1
    fi
}

# Assert a file does NOT contain a pattern
# Usage: assert_file_not_contains "/path/to/file" "pattern"
assert_file_not_contains() {
    local file="$1"
    local pattern="$2"
    local msg="${3:-File should not contain pattern}"

    if [[ ! -f "$file" ]]; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  File does not exist: $file"
        exit 1
    fi

    if grep -q "$pattern" "$file"; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  File: $file"
        _assertion_log_fail "  Pattern should not be present: $pattern"
        exit 1
    fi
}

# Assert no orphan containers exist with given prefix
# Usage: assert_no_orphan_containers "prefix-"
assert_no_orphan_containers() {
    local prefix="$1"
    local msg="${2:-No orphan containers should exist}"

    local orphans
    orphans=$(docker ps -a --filter "name=$prefix" --format "{{.Names}}" 2>/dev/null || echo "")

    if [[ -n "$orphans" ]]; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  Found orphan containers: $orphans"
        # Clean up orphans
        docker rm -f $orphans > /dev/null 2>&1 || true
        exit 1
    fi
}

# Assert exit code equals expected value
# Usage: assert_exit_code "$?" 0 "message"
assert_exit_code() {
    local actual="$1"
    local expected="$2"
    local msg="${3:-Exit code should match}"

    if [[ "$actual" -ne "$expected" ]]; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  Expected exit code: $expected"
        _assertion_log_fail "  Actual exit code:   $actual"
        exit 1
    fi
}

# Assert command succeeds (exit code 0)
# Usage: assert_success "command args..."
assert_success() {
    local cmd="$*"
    local msg="Command should succeed: $cmd"

    if ! eval "$cmd" > /dev/null 2>&1; then
        _assertion_log_fail "$msg"
        exit 1
    fi
}

# Assert command fails (exit code non-zero)
# Usage: assert_failure "command args..."
assert_failure() {
    local cmd="$*"
    local msg="Command should fail: $cmd"

    if eval "$cmd" > /dev/null 2>&1; then
        _assertion_log_fail "$msg"
        exit 1
    fi
}

# Assert numeric value is greater than expected
# Usage: assert_gt "$actual" "$threshold" "message"
assert_gt() {
    local actual="$1"
    local threshold="$2"
    local msg="${3:-Value should be greater than threshold}"

    if [[ ! "$actual" -gt "$threshold" ]]; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  Expected: > $threshold"
        _assertion_log_fail "  Actual:   $actual"
        exit 1
    fi
}

# Assert numeric value is less than expected
# Usage: assert_lt "$actual" "$threshold" "message"
assert_lt() {
    local actual="$1"
    local threshold="$2"
    local msg="${3:-Value should be less than threshold}"

    if [[ ! "$actual" -lt "$threshold" ]]; then
        _assertion_log_fail "$msg"
        _assertion_log_fail "  Expected: < $threshold"
        _assertion_log_fail "  Actual:   $actual"
        exit 1
    fi
}

# Assert array is not empty
# Usage: assert_array_not_empty "${array[@]}"
assert_array_not_empty() {
    local -a arr=("$@")
    local msg="Array should not be empty"

    if [[ ${#arr[@]} -eq 0 ]]; then
        _assertion_log_fail "$msg"
        exit 1
    fi
}
