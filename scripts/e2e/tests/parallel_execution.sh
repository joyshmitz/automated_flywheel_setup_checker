#!/bin/bash
# ============================================================
# E2E Test: Parallel Execution
#
# Validates that multiple installers can be tested in parallel
# without interference or race conditions.
#
# Related: bead bd-19y9.1.8
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assertions.sh"
source "$SCRIPT_DIR/../lib/helpers.sh"

setup_test "parallel_execution"

echo "Test: Parallel execution"

# Create multiple installers with different execution times
for i in 1 2 3 4; do
    sleep_time=$((i * 1))  # 1, 2, 3, 4 seconds
    create_fixture "parallel_${i}.sh" << INSTALL
#!/bin/bash
echo "[\$(date +%s)] Starting installer $i"
sleep $sleep_time
echo "[\$(date +%s)] Completed installer $i"
exit 0
INSTALL
done

# Run all installers in parallel
echo "Running 4 installers in parallel..."
results_dir="$TEST_TMP/output/parallel_results"
mkdir -p "$results_dir"

start_time=$(date +%s)

# Launch all in parallel
for i in 1 2 3 4; do
    bash "$TEST_TMP/fixtures/parallel_${i}.sh" > "$results_dir/result_${i}.txt" 2>&1 &
done

# Wait for all to complete
wait

end_time=$(date +%s)
total_time=$((end_time - start_time))

echo "Total parallel execution time: ${total_time}s"

# If truly parallel, total time should be ~4s (longest), not 10s (sum)
# Allow some buffer for overhead
assert_lt "$total_time" 8 "Parallel execution should complete in ~4-5s, not sequential 10s"

# Verify all completed
for i in 1 2 3 4; do
    assert_file_exists "$results_dir/result_${i}.txt"
    assert_file_contains "$results_dir/result_${i}.txt" "Completed installer $i"
done

# Verify no interference (each result has its own installer number)
assert_file_contains "$results_dir/result_1.txt" "installer 1"
assert_file_contains "$results_dir/result_2.txt" "installer 2"
assert_file_contains "$results_dir/result_3.txt" "installer 3"
assert_file_contains "$results_dir/result_4.txt" "installer 4"

# Test resource isolation (using different temp files)
echo "Testing resource isolation..."
for i in 1 2; do
    create_fixture "isolated_${i}.sh" << INSTALL
#!/bin/bash
# Each process writes to a unique file
echo "\$\$" > /tmp/e2e_parallel_test_${i}_\$\$.pid
sleep 1
cat /tmp/e2e_parallel_test_${i}_\$\$.pid
rm /tmp/e2e_parallel_test_${i}_\$\$.pid
exit 0
INSTALL
done

# Run isolated tests in parallel
bash "$TEST_TMP/fixtures/isolated_1.sh" > "$results_dir/isolated_1.txt" 2>&1 &
pid1=$!
bash "$TEST_TMP/fixtures/isolated_2.sh" > "$results_dir/isolated_2.txt" 2>&1 &
pid2=$!

wait $pid1 $pid2

# Verify PIDs are different (isolation)
result1=$(cat "$results_dir/isolated_1.txt")
result2=$(cat "$results_dir/isolated_2.txt")
assert_neq "$result1" "$result2" "Parallel processes should have different PIDs"

echo "Parallel execution test: PASSED"
cleanup_test
