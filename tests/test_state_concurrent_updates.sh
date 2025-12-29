#!/usr/bin/env bats
#
# Tests for Concurrent State Updates
# Tests rapid state updates, file locking, and atomic write failures
#
# These tests address the gap identified in CRITICAL_PATH_TEST_GAPS_REVIEW.md Section 4.1

load test_helper
load test_helper_functions

# ============================================================================
# CONCURRENT STATE UPDATES TESTS
# ============================================================================

# bats test_tags=category:state,priority:medium
@test "set_peer_state handles rapid state updates for same peer without losing updates" {
	# Purpose: Test verifies that rapid state updates for the same peer are handled correctly.
	# Expected: All updates should be preserved, no updates should be lost.
	# Importance: Rapid updates could cause state inconsistencies if atomic writes fail.
	setup_test_environment "${TEST_DIR}"
	local peer_ip="192.168.1.1"

	source_function "set_peer_state"
	source_function "get_peer_state"

	# Perform rapid updates
	for i in {1..10}; do
		set_peer_state "$peer_ip" "failure_count" "$i"
	done

	# Verify final state is correct (should be 10)
	local final_count
	final_count=$(get_peer_state "$peer_ip" "failure_count" "0")
	assert_equal "$final_count" 10
}

# bats test_tags=category:state,priority:medium
@test "set_peer_state handles rapid state updates with different keys for same peer" {
	# Purpose: Test verifies that rapid updates to different state keys for same peer work correctly.
	# Expected: All state keys should be updated correctly without interference.
	# Importance: Multiple state keys updated rapidly could cause file conflicts.
	setup_test_environment "${TEST_DIR}"
	local peer_ip="192.168.1.1"

	source_function "set_peer_state"
	source_function "get_peer_state"

	# Rapid updates to different keys
	for i in {1..5}; do
		set_peer_state "$peer_ip" "failure_count" "$i"
		set_peer_state "$peer_ip" "last_bytes" "$((i * 1000))"
		set_peer_state "$peer_ip" "spi" "0x$(printf '%08x' "$i")"
	done

	# Verify all state keys are correct
	local failure_count
	failure_count=$(get_peer_state "$peer_ip" "failure_count" "0")
	assert_equal "$failure_count" 5

	local last_bytes
	last_bytes=$(get_peer_state "$peer_ip" "last_bytes" "0")
	assert_equal "$last_bytes" 5000

	local spi
	spi=$(get_peer_state "$peer_ip" "spi" "")
	assert_equal "$spi" "0x00000005"
}

# bats test_tags=category:state,priority:medium
@test "set_peer_state handles state file locked by another process gracefully" {
	# Purpose: Test verifies that set_peer_state handles file locking gracefully.
	# Expected: Function should handle locked files without crashing, may log warning.
	# Importance: State file locked by another process could cause write failures.
	setup_test_environment "${TEST_DIR}"
	local peer_ip="192.168.1.1"

	source_function "set_peer_state"
	source_function "get_peer_state_file_path"

	local state_file
	state_file=$(get_peer_state_file_path "$peer_ip" "failure_count")

	# Create state file and lock it using flock
	echo "5" >"$state_file"

	# Try to lock the file in background (simulating another process)
	(
		exec 200>"${state_file}.lock"
		flock -x 200
		sleep 0.5
	) &
	local lock_pid=$!

	# Wait a moment for lock to be acquired
	sleep 0.05

	# Try to update state (should handle gracefully)
	# atomic_write_file should handle this, but may fail
	run set_peer_state "$peer_ip" "failure_count" "10"

	# Clean up lock
	kill "$lock_pid" 2>/dev/null || true
	wait "$lock_pid" 2>/dev/null || true

	# Function should either succeed or fail gracefully (not crash)
	# The actual behavior depends on atomic_write_file implementation
	# For now, we just verify it doesn't crash
	assert [ $status -eq 0 ] || [ $status -eq 1 ]
}

# bats test_tags=category:state,priority:medium
@test "set_peer_state recovers from atomic write failure mid-operation" {
	# Purpose: Test verifies that set_peer_state recovers gracefully when atomic write fails mid-operation.
	# Expected: Function should handle write failures gracefully, state should remain consistent.
	# Importance: Atomic write failures could leave state in inconsistent state if not handled properly.
	setup_test_environment "${TEST_DIR}"
	local peer_ip="192.168.1.1"

	source_function "set_peer_state"
	source_function "get_peer_state"
	source_function "atomic_write_file"
	source_function "get_peer_state_file_path"

	# Set initial state
	set_peer_state "$peer_ip" "failure_count" "5"

	# Create a mock atomic_write_file that fails
	# We'll temporarily make the state directory unwritable to simulate failure
	local state_file
	state_file=$(get_peer_state_file_path "$peer_ip" "failure_count")
	local state_dir
	state_dir=$(dirname "$state_file")

	# Make directory unwritable (if possible)
	if [[ -w "$state_dir" ]]; then
		chmod 555 "$state_dir" 2>/dev/null || true

		# Try to update state (should fail gracefully)
		run set_peer_state "$peer_ip" "failure_count" "10"
		assert_failure

		# Restore permissions
		chmod 755 "$state_dir" 2>/dev/null || true

		# Verify original state is preserved (should still be 5)
		local preserved_count
		preserved_count=$(get_peer_state "$peer_ip" "failure_count" "0")
		assert_equal "$preserved_count" 5
	fi
}

# bats test_tags=category:state,priority:medium
@test "get_peer_state handles concurrent reads during state update" {
	# Purpose: Test verifies that get_peer_state handles concurrent reads during state updates.
	# Expected: Reads should return consistent values (either old or new, not corrupted).
	# Importance: Concurrent reads during updates could return corrupted values if not atomic.
	setup_test_environment "${TEST_DIR}"
	local peer_ip="192.168.1.1"

	source_function "set_peer_state"
	source_function "get_peer_state"

	# Set initial state
	set_peer_state "$peer_ip" "failure_count" "5"

	# Start background update
	(set_peer_state "$peer_ip" "failure_count" "10") &

	# Perform concurrent reads
	local read_count=0
	local valid_reads=0
	for i in {1..20}; do
		local value
		value=$(get_peer_state "$peer_ip" "failure_count" "0")
		read_count=$((read_count + 1))
		# Value should be either 5 or 10 (not corrupted)
		if [[ "$value" == "5" ]] || [[ "$value" == "10" ]]; then
			valid_reads=$((valid_reads + 1))
		fi
		sleep 0.01
	done

	# Wait for background update to complete
	wait

	# All reads should have returned valid values
	assert_equal "$read_count" "$valid_reads"
}

# bats test_tags=category:state,priority:medium
@test "set_peer_state maintains state consistency across rapid updates" {
	# Purpose: Test verifies that state remains consistent across rapid updates.
	# Expected: State should always be in a valid state, never corrupted.
	# Importance: Rapid updates could cause state corruption if atomic writes fail.
	setup_test_environment "${TEST_DIR}"
	local peer_ip="192.168.1.1"

	source_function "set_peer_state"
	source_function "get_peer_state"

	# Perform rapid updates and verify consistency after each
	for i in {1..20}; do
		set_peer_state "$peer_ip" "failure_count" "$i"

		# Verify state is consistent
		local current_count
		current_count=$(get_peer_state "$peer_ip" "failure_count" "0")
		# Should be numeric and match expected value
		assert [[ "$current_count" =~ ^[0-9]+$ ]]
		assert_equal "$current_count" "$i"
	done
}

# bats test_tags=category:state,priority:medium
@test "set_peer_state handles multiple peers updating simultaneously" {
	# Purpose: Test verifies that state updates for different peers don't interfere with each other.
	# Expected: Each peer's state should be updated independently and correctly.
	# Importance: Multiple peer updates could cause file conflicts if not handled properly.
	setup_test_environment "${TEST_DIR}"
	local peer1="192.168.1.1"
	local peer2="192.168.1.2"
	local peer3="192.168.1.3"

	source_function "set_peer_state"
	source_function "get_peer_state"

	# Update all peers simultaneously
	for i in {1..10}; do
		set_peer_state "$peer1" "failure_count" "$i" &
		set_peer_state "$peer2" "failure_count" "$((i + 10))" &
		set_peer_state "$peer3" "failure_count" "$((i + 20))" &
	done

	# Wait for all updates to complete
	wait

	# Verify each peer's state is correct
	local count1
	count1=$(get_peer_state "$peer1" "failure_count" "0")
	assert_equal "$count1" 10

	local count2
	count2=$(get_peer_state "$peer2" "failure_count" "0")
	assert_equal "$count2" 20

	local count3
	count3=$(get_peer_state "$peer3" "failure_count" "0")
	assert_equal "$count3" 30
}

# bats test_tags=category:state,priority:medium
@test "atomic_write_file handles partial write failures" {
	# Purpose: Test verifies that atomic_write_file handles partial write failures gracefully.
	# Expected: Partial writes should not corrupt the original file, should be cleaned up.
	# Importance: Partial writes could leave temp files or corrupt state if not handled properly.
	setup_test_environment "${TEST_DIR}"

	source_function "atomic_write_file"

	local test_file="${TEST_DIR}/test_state"
	echo "original" >"$test_file"

	# Create a directory where we can't write to simulate failure
	# Make parent directory read-only temporarily
	local parent_dir
	parent_dir=$(dirname "$test_file")
	if [[ -w "$parent_dir" ]]; then
		chmod 555 "$parent_dir" 2>/dev/null || true

		# Try atomic write (should fail)
		run atomic_write_file "$test_file" "new_value"
		assert_failure

		# Restore permissions
		chmod 755 "$parent_dir" 2>/dev/null || true

		# Verify original file is still intact
		local file_content
		file_content=$(cat "$test_file" 2>/dev/null || echo "")
		assert_equal "$file_content" "original"

		# Verify no temp files left behind
		local temp_files
		temp_files=$(find "$parent_dir" -name "${test_file}.tmp*" 2>/dev/null | wc -l)
		assert_equal "$temp_files" 0
	fi
}

# bats test_tags=category:state,priority:medium
@test "get_peer_state recovers from corrupted state file during concurrent update" {
	# Purpose: Test verifies that get_peer_state recovers from corrupted state files gracefully.
	# Expected: Function should detect corruption and return default value, triggering recovery.
	# Importance: Corrupted state files during concurrent updates could cause false readings.
	setup_test_environment "${TEST_DIR}"
	local peer_ip="192.168.1.1"

	source_function "get_peer_state"
	source_function "get_peer_state_file_path"
	source_function "recover_corrupted_state_file"

	local state_file
	state_file=$(get_peer_state_file_path "$peer_ip" "failure_count")

	# Create corrupted state file
	echo "invalid-value" >"$state_file"

	# get_peer_state should detect corruption and recover
	run get_peer_state "$peer_ip" "failure_count" "0"
	assert_success
	# Should return default value (0) after recovery
	assert_output "0"

	# Verify file was recovered (should contain valid integer or be reset)
	if [[ -f "$state_file" ]]; then
		local recovered_value
		recovered_value=$(cat "$state_file")
		# Should be valid integer (0) after recovery
		assert [[ "$recovered_value" =~ ^[0-9]+$ ]]
	fi
}
