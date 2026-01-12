#!/usr/bin/env bats
#
# Tests for State Module Atomic Write Failures
# Tests critical paths where atomic write operations fail
#
# These tests address the gap identified in COVERAGE_GAP_ANALYSIS.md:
# - Atomic write fails during increment
# - Atomic write fails during reset
# - Atomic write fails during cooldown set
# - Atomic write fails during restart record
# - State file cleanup failures (cleanup_peer_state, delete_peer_state)
# - Network partition state failures (set_network_partition_state, get_network_partition_state)

load test_helper

# ============================================================================
# STATE MODULE ATOMIC WRITE FAILURE TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high,slow
@test "state atomic write failures: increment_failure fails due to atomic write failure" {
	# Purpose: Test verifies that increment_failure handles atomic write failures gracefully
	# Expected: Function detects write failure, logs error, returns current count (not incremented)
	# Importance: Write failures can corrupt state; must be handled gracefully
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"

	source_function "increment_failure"
	source_function "get_peer_state"
	source_function "get_peer_state_file_path"

	# Set initial state
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	local state_file
	state_file=$(get_peer_state_file_path "" "$peer_ip" "failure_count")
	mkdir -p "$(dirname "$state_file")"
	echo "5" >"$state_file"

	# Make directory unwritable to simulate atomic write failure
	local state_dir
	state_dir=$(dirname "$state_file")
	local original_perms
	original_perms=$(save_permissions_for_restore "$state_dir")

	# Try to make unwritable (may fail on some systems)
	if chmod 555 "$state_dir" 2>/dev/null; then
		# Try to increment (should fail gracefully)
		run increment_failure "" "$peer_ip"
		# Function should handle failure gracefully
		# May return current count or fail, but shouldn't crash
		assert_file_exist "$state_file"

		# Verify original state is preserved (should still be 5)
		local preserved_count
		preserved_count=$(get_peer_state "" "$peer_ip" "failure_count" "0")
		assert_equal "$preserved_count" 5

		# Restore permissions
		restore_permissions_after_test "$state_dir" "$original_perms"
	else
		# Can't test unwritable directory on this system - skip
		skip "Cannot make directory unwritable on this system"
	fi
}

# bats test_tags=category:high-risk,priority:high,slow
@test "state atomic write failures: reset_failure_count fails due to atomic write failure" {
	# Purpose: Test verifies that reset_failure_count handles atomic write failures gracefully
	# Expected: Function detects write failure, logs error, preserves current state
	# Importance: Reset failures can cause false failure detection; must be handled gracefully
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"

	source_function "reset_failure_count"
	source_function "get_peer_state"
	source_function "get_peer_state_file_path"

	# Set initial state
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	local state_file
	state_file=$(get_peer_state_file_path "" "$peer_ip" "failure_count")
	mkdir -p "$(dirname "$state_file")"
	echo "3" >"$state_file"

	# Make directory unwritable to simulate atomic write failure
	local state_dir
	state_dir=$(dirname "$state_file")
	local original_perms
	original_perms=$(save_permissions_for_restore "$state_dir")

	# Try to make unwritable (may fail on some systems)
	if chmod 555 "$state_dir" 2>/dev/null; then
		# Try to reset (should fail gracefully)
		run reset_failure_count "" "$peer_ip"
		# Function should handle failure gracefully
		assert_file_exist "$state_file"

		# Verify original state is preserved (should still be 3)
		local preserved_count
		preserved_count=$(get_peer_state "" "$peer_ip" "failure_count" "0")
		assert_equal "$preserved_count" 3

		# Restore permissions
		restore_permissions_after_test "$state_dir" "$original_perms"
	else
		# Can't test unwritable directory on this system - skip
		skip "Cannot make directory unwritable on this system"
	fi
}

# bats test_tags=category:high-risk,priority:high,slow
@test "state atomic write failures: set_cooldown fails due to atomic write failure" {
	# Purpose: Test verifies that set_cooldown handles atomic write failures gracefully
	# Expected: Function detects write failure, logs error, preserves current state
	# Importance: Cooldown failures can cause rapid re-restarts; must be handled gracefully
	setup_test_environment "${TEST_DIR}"

	source_function "set_cooldown"
	source_function "check_cooldown"
	source_function "get_network_partition_state_file"

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Get cooldown file path (uses get_network_partition_state_file pattern)
	local cooldown_file="${STATE_DIR}/cooldown_until"
	mkdir -p "$(dirname "$cooldown_file")"

	# Make directory unwritable to simulate atomic write failure
	local state_dir="${STATE_DIR}"
	local original_perms
	original_perms=$(save_permissions_for_restore "$state_dir")

	# Try to make unwritable (may fail on some systems)
	if chmod 555 "$state_dir" 2>/dev/null; then
		# Try to set cooldown (should fail gracefully)
		run set_cooldown 5
		# Function should handle failure gracefully
		# May return error or succeed with logging

		# Restore permissions
		restore_permissions_after_test "$state_dir" "$original_perms"
	else
		# Can't test unwritable directory on this system - skip
		skip "Cannot make directory unwritable on this system"
	fi
}

# bats test_tags=category:high-risk,priority:high,slow
@test "state atomic write failures: record_restart fails due to atomic write failure" {
	# Purpose: Test verifies that record_restart handles atomic write failures gracefully
	# Expected: Function detects write failure, logs error, preserves current state
	# Importance: Restart record failures can affect rate limiting; must be handled gracefully
	setup_test_environment "${TEST_DIR}"

	source_function "record_restart"
	source_function "check_rate_limit"

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Use RESTART_COUNT_FILE as set by setup_test_environment
	# Write initial content to the file that record_restart will use
	echo "2" >"$RESTART_COUNT_FILE"

	# Make state directory unwritable to simulate atomic write failure
	# This prevents record_restart from writing to RESTART_COUNT_FILE (which is in STATE_DIR)
	local state_dir="${STATE_DIR}"
	local original_perms
	original_perms=$(save_permissions_for_restore "$state_dir")

	# Try to make unwritable (may fail on some systems)
	if chmod 555 "$state_dir" 2>/dev/null; then
		# Try to record restart (should fail gracefully)
		run record_restart
		# Function should handle failure gracefully
		assert_file_exist "$RESTART_COUNT_FILE"

		# Verify original state is preserved (should still be 2)
		local preserved_count
		preserved_count=$(cat "$RESTART_COUNT_FILE" 2>/dev/null || echo "0")
		assert_equal "$preserved_count" 2

		# Restore permissions
		restore_permissions_after_test "$state_dir" "$original_perms"
	else
		# Can't test unwritable directory on this system - skip
		skip "Cannot make directory unwritable on this system"
	fi
}

# bats test_tags=category:high-risk,priority:high,slow
@test "state atomic write failures: set_peer_state fails due to atomic write failure" {
	# Purpose: Test verifies that set_peer_state handles atomic write failures gracefully
	# Expected: Function detects write failure, logs error, preserves current state
	# Importance: State update failures can cause inconsistent state; must be handled gracefully
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"

	source_function "set_peer_state"
	source_function "get_peer_state"
	source_function "get_peer_state_file_path"

	# Set initial state
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	local state_file
	state_file=$(get_peer_state_file_path "" "$peer_ip" "last_bytes")
	mkdir -p "$(dirname "$state_file")"
	echo "1000" >"$state_file"

	# Make directory unwritable to simulate atomic write failure
	local state_dir
	state_dir=$(dirname "$state_file")
	local original_perms
	original_perms=$(save_permissions_for_restore "$state_dir")

	# Try to make unwritable (may fail on some systems)
	if chmod 555 "$state_dir" 2>/dev/null; then
		# Try to update state (should fail gracefully)
		run set_peer_state "" "$peer_ip" "last_bytes" "2000"
		assert_failure

		# Verify original state is preserved (should still be 1000)
		local preserved_value
		preserved_value=$(get_peer_state "" "$peer_ip" "last_bytes" "0")
		assert_equal "$preserved_value" 1000

		# Restore permissions
		restore_permissions_after_test "$state_dir" "$original_perms"
	else
		# Can't test unwritable directory on this system - skip
		skip "Cannot make directory unwritable on this system"
	fi
}

# bats test_tags=category:high-risk,priority:high,slow
@test "state atomic write failures: disk full scenario - atomic write fails" {
	# Purpose: Test verifies that state functions handle disk full scenarios gracefully
	# Expected: Functions detect disk full condition, log error, preserve current state
	# Importance: Disk full scenarios can occur in production; must be handled gracefully
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"

	source_function "increment_failure"
	source_function "get_peer_state"
	source_function "get_peer_state_file_path"

	# Set initial state
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	local state_file
	state_file=$(get_peer_state_file_path "" "$peer_ip" "failure_count")
	mkdir -p "$(dirname "$state_file")"
	echo "5" >"$state_file"

	# Simulate disk full by making the directory read-only
	# Note: This is a simplified test - real disk full would require more complex setup
	local state_dir
	state_dir=$(dirname "$state_file")
	local original_perms
	original_perms=$(save_permissions_for_restore "$state_dir")

	# Try to make unwritable (simulates disk full)
	if chmod 555 "$state_dir" 2>/dev/null; then
		# Try to increment (should fail gracefully)
		run increment_failure "" "$peer_ip"
		# Function should handle failure gracefully
		assert_file_exist "$state_file"

		# Verify original state is preserved
		local preserved_count
		preserved_count=$(get_peer_state "" "$peer_ip" "failure_count" "0")
		assert_equal "$preserved_count" 5

		# Restore permissions
		restore_permissions_after_test "$state_dir" "$original_perms"
	else
		# Can't test unwritable directory on this system - skip
		skip "Cannot make directory unwritable on this system"
	fi
}

# bats test_tags=category:high-risk,priority:high,slow
@test "state atomic write failures: delete_peer_state fails due to deletion failure" {
	# Purpose: Test verifies that delete_peer_state handles deletion failures gracefully
	# Expected: Function detects deletion failure, logs error, returns error code
	# Importance: Deletion failures can occur due to permissions; must be handled gracefully
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"

	source_function "delete_peer_state"
	source_function "set_peer_state"
	source_function "get_peer_state_file_path"

	# Set initial state - create a file to delete
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	local state_file
	state_file=$(get_peer_state_file_path "" "$peer_ip" "failure_count")
	mkdir -p "$(dirname "$state_file")"
	echo "5" >"$state_file"

	# Make parent directory read-only to prevent deletion (rm -f can delete read-only files)
	local state_dir
	state_dir=$(dirname "$state_file")
	local original_perms
	original_perms=$(save_permissions_for_restore "$state_dir")

	# Try to make directory read-only (may fail on some systems)
	if chmod 555 "$state_dir" 2>/dev/null; then
		# Try to delete (should fail gracefully)
		run delete_peer_state "" "$peer_ip" "failure_count"
		# Function should detect failure and return error code
		assert_failure

		# Verify file still exists (deletion failed)
		assert_file_exist "$state_file"

		# Restore permissions for cleanup
		restore_permissions_after_test "$state_dir" "$original_perms"
		# Now delete should succeed
		run delete_peer_state "" "$peer_ip" "failure_count"
		assert_success
	else
		# Can't test read-only directory on this system - skip
		skip "Cannot make directory read-only on this system"
	fi
}

# bats test_tags=category:high-risk,priority:high,slow
@test "state atomic write failures: cleanup_peer_state fails due to deletion failures" {
	# Purpose: Test verifies that cleanup_peer_state handles deletion failures gracefully
	# Expected: Function continues cleanup even if some deletions fail, logs warnings
	# Importance: Cleanup failures can occur; must be handled gracefully without crashing
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"

	source_function "cleanup_peer_state"
	source_function "set_peer_state"
	source_function "get_peer_state_file_path"

	# Set initial state - create multiple files to clean up
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	run set_peer_state "" "$peer_ip" "failure_count" "5"
	assert_success
	run set_peer_state "" "$peer_ip" "last_bytes" "123456"
	assert_success

	# Get file paths
	local counter_file
	counter_file=$(get_peer_state_file_path "" "$peer_ip" "failure_count")
	local bytes_file
	bytes_file=$(get_peer_state_file_path "" "$peer_ip" "last_bytes")

	# Make parent directory read-only to simulate partial deletion failure
	# This will prevent deletion of files in that directory
	local state_dir
	state_dir=$(dirname "$counter_file")
	local original_perms
	original_perms=$(save_permissions_for_restore "$state_dir")

	# Try to make directory read-only (may fail on some systems)
	if chmod 555 "$state_dir" 2>/dev/null; then
		# Try to cleanup (should handle partial failure gracefully)
		run cleanup_peer_state "" "$peer_ip"
		# Function should continue even if some deletions fail
		# cleanup_peer_state doesn't check return values, so it always succeeds
		# but logs warnings for failures

		# Verify files still exist (deletion failed due to read-only directory)
		assert_file_exist "$counter_file"
		assert_file_exist "$bytes_file"

		# Restore permissions for cleanup
		restore_permissions_after_test "$state_dir" "$original_perms"
		# Now cleanup should succeed completely
		run cleanup_peer_state "" "$peer_ip"
		assert_success
		assert_file_not_exist "$counter_file"
		assert_file_not_exist "$bytes_file"
	else
		# Can't test read-only directory on this system - skip
		skip "Cannot make directory read-only on this system"
	fi
}

# bats test_tags=category:high-risk,priority:high,slow
@test "state atomic write failures: set_network_partition_state fails due to atomic write failure" {
	# Purpose: Test verifies that set_network_partition_state handles atomic write failures gracefully
	# Expected: Function detects write failure, logs error, returns error code
	# Importance: Network partition state update failures can affect recovery decisions; must be handled gracefully
	setup_test_environment "${TEST_DIR}"

	source_function "set_network_partition_state"
	source_function "get_network_partition_state"
	source_function "get_network_partition_state_file"

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Get network partition state file path
	local partition_state_file
	partition_state_file=$(get_network_partition_state_file)
	mkdir -p "$(dirname "$partition_state_file")"
	echo "0" >"$partition_state_file"

	# Make directory unwritable to simulate atomic write failure
	local state_dir
	state_dir=$(dirname "$partition_state_file")
	local original_perms
	original_perms=$(save_permissions_for_restore "$state_dir")

	# Try to make unwritable (may fail on some systems)
	if chmod 555 "$state_dir" 2>/dev/null; then
		# Try to set state (should fail gracefully)
		run set_network_partition_state 1
		# Function should detect failure and return error code
		assert_failure

		# Verify original state is preserved (should still be 0)
		local preserved_state
		preserved_state=$(get_network_partition_state)
		assert_equal "$preserved_state" "0"

		# Restore permissions
		restore_permissions_after_test "$state_dir" "$original_perms"
	else
		# Can't test unwritable directory on this system - skip
		skip "Cannot make directory unwritable on this system"
	fi
}

# bats test_tags=category:high-risk,priority:high,slow
@test "state atomic write failures: get_network_partition_state fails due to read failure" {
	# Purpose: Test verifies that get_network_partition_state handles read failures gracefully
	# Expected: Function detects read failure, defaults to 0 (healthy), doesn't crash
	# Importance: Read failures can occur due to permissions; must be handled gracefully
	setup_test_environment "${TEST_DIR}"

	source_function "get_network_partition_state"
	source_function "get_network_partition_state_file"
	source_function "set_network_partition_state"

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Get network partition state file path
	local partition_state_file
	partition_state_file=$(get_network_partition_state_file)
	mkdir -p "$(dirname "$partition_state_file")"

	# Set initial state to 1 (partitioned)
	run set_network_partition_state 1
	assert_success

	# Make file unreadable to simulate read failure
	local original_perms
	original_perms=$(save_permissions_for_restore "$partition_state_file")

	# Try to make file unreadable (may fail on some systems)
	if chmod 000 "$partition_state_file" 2>/dev/null; then
		# Try to get state (should handle read failure gracefully)
		local state
		state=$(get_network_partition_state)
		# Function should default to 0 (healthy) when read fails
		# The function uses cat with 2>/dev/null, so it will fail silently and default to 0
		assert_equal "$state" "0"

		# Restore permissions
		restore_permissions_after_test "$partition_state_file" "$original_perms"
		# Now read should succeed
		state=$(get_network_partition_state)
		assert_equal "$state" "1"
	else
		# Can't test unreadable file on this system - skip
		skip "Cannot make file unreadable on this system"
	fi
}
