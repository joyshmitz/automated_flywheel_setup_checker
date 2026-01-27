#!/bin/bash
# ============================================================
# E2E Test Helper Functions
#
# Provides utility functions for E2E tests.
#
# Related: bead bd-19y9.1.8
# ============================================================

# Get project root (lib -> e2e -> scripts -> project_root)
E2E_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
E2E_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test temporary directory (set by setup_test)
TEST_TMP=""
TEST_NAME=""

# Binary path
CHECKER_BINARY="${E2E_PROJECT_ROOT}/target/release/automated_flywheel_setup_checker"

# Helper logging
_helper_log() {
    echo -e "\033[90m[HELPER]\033[0m $*"
}

# Setup test environment
# Usage: setup_test "test_name"
setup_test() {
    TEST_NAME="$1"
    TEST_TMP=$(mktemp -d "/tmp/e2e-test-${TEST_NAME}-XXXXXX")

    _helper_log "Setting up test: $TEST_NAME"
    _helper_log "Temp directory: $TEST_TMP"

    # Create common directories
    mkdir -p "$TEST_TMP/fixtures"
    mkdir -p "$TEST_TMP/output"
    mkdir -p "$TEST_TMP/logs"

    # Set up trap for cleanup on exit
    trap cleanup_test EXIT
}

# Cleanup test environment
cleanup_test() {
    if [[ -n "$TEST_TMP" && -d "$TEST_TMP" ]]; then
        _helper_log "Cleaning up: $TEST_TMP"
        rm -rf "$TEST_TMP"
    fi

    # Clean up any test containers
    local containers
    containers=$(docker ps -aq --filter "name=acfs-test-${TEST_NAME}" 2>/dev/null || echo "")
    if [[ -n "$containers" ]]; then
        _helper_log "Removing test containers: $containers"
        docker rm -f $containers > /dev/null 2>&1 || true
    fi
}

# Create a test fixture file
# Usage: create_fixture "filename" <<< "content"
#    or: create_fixture "filename" < file
create_fixture() {
    local name="$1"
    local fixture_path="$TEST_TMP/fixtures/$name"
    local fixture_dir
    fixture_dir=$(dirname "$fixture_path")

    mkdir -p "$fixture_dir"
    cat > "$fixture_path"

    # Make executable if it's a script
    if [[ "$name" == *.sh ]]; then
        chmod +x "$fixture_path"
    fi

    echo "$fixture_path"
}

# Create a mock installer script
# Usage: create_mock_installer "name" "exit_code" "stdout" "stderr"
create_mock_installer() {
    local name="$1"
    local exit_code="${2:-0}"
    local stdout="${3:-Installation successful}"
    local stderr="${4:-}"

    create_fixture "${name}.sh" << INSTALLER
#!/bin/bash
echo "$stdout"
[[ -n "$stderr" ]] && echo "$stderr" >&2
exit $exit_code
INSTALLER
}

# Create a mock checksums.yaml file
# Usage: create_mock_checksums "zoxide:sha256:abc123" "rano:sha256:def456"
create_mock_checksums() {
    local checksums_file="$TEST_TMP/checksums.yaml"

    {
        echo "version: \"1.0\""
        echo ""

        for entry in "$@"; do
            local name sha256 url enabled
            IFS=':' read -r name sha256 url enabled <<< "$entry"

            name="${name:-test-tool}"
            sha256="${sha256:-0000000000000000000000000000000000000000000000000000000000000000}"
            url="${url:-https://example.com/install.sh}"
            enabled="${enabled:-true}"

            echo "$name:"
            echo "  url: \"$url\""
            echo "  checksum:"
            echo "    algorithm: sha256"
            echo "    value: \"$sha256\""
            echo "  enabled: $enabled"
            echo ""
        done
    } > "$checksums_file"

    echo "$checksums_file"
}

# Run the checker binary with arguments
# Usage: run_checker [args...]
run_checker() {
    if [[ ! -f "$CHECKER_BINARY" ]]; then
        echo "ERROR: Binary not found at $CHECKER_BINARY" >&2
        return 1
    fi

    "$CHECKER_BINARY" "$@"
}

# Run checker and capture output
# Usage: output=$(run_checker_capture [args...])
run_checker_capture() {
    run_checker "$@" 2>&1
}

# Wait for a condition with timeout
# Usage: wait_for "condition_command" timeout_seconds
wait_for() {
    local condition="$1"
    local timeout="${2:-30}"
    local interval="${3:-1}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if eval "$condition" > /dev/null 2>&1; then
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    return 1
}

# Wait for container to be running
# Usage: wait_for_container "container_name" timeout_seconds
wait_for_container() {
    local container="$1"
    local timeout="${2:-30}"

    wait_for "docker ps --filter 'name=$container' --filter 'status=running' | grep -q '$container'" "$timeout"
}

# Wait for container to exit
# Usage: wait_for_container_exit "container_name" timeout_seconds
wait_for_container_exit() {
    local container="$1"
    local timeout="${2:-60}"

    wait_for "docker ps --filter 'name=$container' --filter 'status=exited' | grep -q '$container'" "$timeout"
}

# Get container exit code
# Usage: get_container_exit_code "container_name"
get_container_exit_code() {
    local container="$1"
    docker inspect "$container" --format='{{.State.ExitCode}}' 2>/dev/null || echo "-1"
}

# Start a mock HTTP server
# Usage: mock_server_id=$(start_mock_server port)
start_mock_server() {
    local port="${1:-8888}"
    local response="${2:-HTTP/1.1 200 OK\r\n\r\nOK}"

    # Use simple netcat server
    local server_script="$TEST_TMP/mock_server.sh"
    cat > "$server_script" << 'SERVERSCRIPT'
#!/bin/bash
PORT="$1"
RESPONSE="$2"
while true; do
    echo -e "$RESPONSE" | nc -l -p "$PORT" -q 1 2>/dev/null || break
done
SERVERSCRIPT
    chmod +x "$server_script"

    "$server_script" "$port" "$response" &
    local pid=$!

    echo "$pid"
}

# Stop mock server
# Usage: stop_mock_server "$server_pid"
stop_mock_server() {
    local pid="$1"
    kill "$pid" 2>/dev/null || true
}

# Generate random string
# Usage: random_string [length]
random_string() {
    local length="${1:-16}"
    head -c "$length" /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c "$length"
}

# Calculate SHA256 of a string
# Usage: sha256_of "content"
sha256_of() {
    echo -n "$1" | sha256sum | awk '{print $1}'
}

# Calculate SHA256 of a file
# Usage: sha256_file "/path/to/file"
sha256_file() {
    sha256sum "$1" | awk '{print $1}'
}

# Create test Docker image
# Usage: create_test_image "image_name" "dockerfile_content"
create_test_image() {
    local name="$1"
    local dockerfile="${2:-FROM ubuntu:22.04\nRUN apt-get update}"

    local build_dir="$TEST_TMP/docker-build"
    mkdir -p "$build_dir"
    echo -e "$dockerfile" > "$build_dir/Dockerfile"

    docker build -t "$name" "$build_dir" > /dev/null 2>&1
}

# Remove test Docker image
# Usage: remove_test_image "image_name"
remove_test_image() {
    local name="$1"
    docker rmi "$name" 2>/dev/null || true
}

# Simulate network failure for container
# Usage: simulate_network_failure "container_name"
simulate_network_failure() {
    local container="$1"
    docker network disconnect bridge "$container" 2>/dev/null || true
}

# Restore network for container
# Usage: restore_network "container_name"
restore_network() {
    local container="$1"
    docker network connect bridge "$container" 2>/dev/null || true
}

# Check if Docker is available
# Usage: require_docker
require_docker() {
    if ! docker info > /dev/null 2>&1; then
        echo "SKIP: Docker not available"
        exit 0
    fi
}

# Skip test with message
# Usage: skip_test "reason"
skip_test() {
    local reason="$1"
    echo "SKIP: $reason"
    exit 0
}

# Mark test as expected to fail
# Usage: expect_failure
expect_failure() {
    set +e
}

# Check binary exists, build if missing
# Usage: ensure_binary
ensure_binary() {
    if [[ ! -f "$CHECKER_BINARY" ]]; then
        _helper_log "Binary not found, building..."
        cargo build --release --manifest-path "$E2E_PROJECT_ROOT/Cargo.toml" 2>&1 || {
            echo "ERROR: Failed to build binary" >&2
            return 1
        }
    fi
}

# Get config path for tests
# Usage: test_config_path
test_config_path() {
    echo "$E2E_PROJECT_ROOT/config/test.toml"
}

# Load test configuration
# Usage: load_test_config
load_test_config() {
    local config_file
    config_file=$(test_config_path)
    if [[ -f "$config_file" ]]; then
        source "$config_file" 2>/dev/null || true
    fi
}
