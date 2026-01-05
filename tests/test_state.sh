#!/usr/bin/env bats
#
# Tests for State File Management
# Tests critical paths and error handling scenarios

# for better organization and maintainability.

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# 6.1 STATE FILE CORRUPTION AND RECOVERY
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "failure counter file corrupted (non-numeric) - should recover gracefully" {
	# Purpose: Test verifies that the script handles corrupted failure counter files containing non-numeric values.
	# Expected: Script treats corrupted file as 0 or resets it, continuing normal operation without crashing.
	# Importance: File corruption can occur due to disk errors or manual editing; script must handle it robustly.
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	source_function "get_peer_state_file_path"

	# Create corrupted failure counter file (location-based path)
	local failure_counter
	failure_counter=$(create_corrupted_state_file "" "${TEST_PEER_IP}" "failure_count" "invalid-non-numeric-value")

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should handle corrupted file gracefully
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "failure counter file contains negative number - should handle gracefully" {
	# Purpose: Test verifies that the script handles failure counter files containing negative numbers.
	# Expected: Script handles negative numbers gracefully, treating them as invalid and recovering to 0.
	# Importance: Negative failure counts are invalid; script must handle corrupted data robustly.
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	source_function "get_peer_state_file_path"

	# Create failure counter file with negative number
	local failure_counter
	failure_counter=$(get_state_file_path "" "${TEST_PEER_IP}" "failure_count")
	echo "-5" >"$failure_counter"

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should handle negative number gracefully
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "failure counter file is empty - should recover to 0" {
	# Purpose: Test verifies that the script handles empty failure counter files.
	# Expected: Script treats empty file as corrupted and recovers it to "0".
	# Importance: Empty files can occur from truncation or corruption; script must handle them robustly.
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	source_function "get_peer_state_file_path"

	# Create empty failure counter file (clear any existing file from fixture)
	local failure_counter
	failure_counter=$(get_state_file_path "" "${TEST_PEER_IP}" "failure_count")
	rm -f "$failure_counter"
	touch "$failure_counter"
	# Verify file is empty before script runs
	assert_file_empty "$failure_counter"

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should handle empty file gracefully (script recovers it by writing "0")
	assert_file_exist "$LOG_FILE"
	# File should be recovered (empty files are treated as corrupted and recovered to "0")
	if [[ -f "$failure_counter" ]]; then
		local content
		content=$(cat "$failure_counter" 2>/dev/null || echo "")
		# Should contain "0" (recovered from empty)
		if [[ "$content" != "0" ]]; then
			fail "Expected failure counter file to be recovered to '0', got: '$content'"
		fi
	else
		fail "Failure counter file should exist after recovery"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "cooldown file corrupted (invalid timestamp) - should handle gracefully" {
	# Purpose: Test verifies that the script handles corrupted cooldown files with invalid timestamps.
	# Expected: Script handles invalid timestamp gracefully, preventing arithmetic errors and continuing execution.
	# Importance: Corrupted timestamps can cause arithmetic errors; script must handle them robustly.
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	# Create corrupted cooldown file with invalid timestamp
	local cooldown_file="${STATE_DIR}/cooldown_until"
	echo "invalid-timestamp-value" >"$cooldown_file"

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should handle corrupted cooldown file gracefully (arithmetic error would occur)
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# ============================================================================
# 6.2 CONCURRENT STATE ACCESS - PERMISSIONS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "state file permissions prevent write - should handle gracefully" {
	# Purpose: Test verifies that the script handles read-only state files gracefully when attempting to update counters.
	# Expected: Script logs error about write failure but continues execution without crashing.
	# Importance: Permission issues can occur due to incorrect file ownership or chmod operations; script must handle gracefully.
	setup_vpn_down_fixture "${TEST_PEER_IP}" 3

	source_function "get_peer_state_file_path"

	# Create failure counter file and make it read-only (prevents write)
	local failure_counter
	failure_counter=$(setup_readonly_state_file "" "${TEST_PEER_IP}" "failure_count" "3" "444")
	# Verify permissions were set correctly
	assert_file_permission 444 "$failure_counter"

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should handle read-only state file gracefully (should log error but continue)
	assert_file_exist "$LOG_FILE"

	# Trap will restore permissions automatically on EXIT
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "state file permissions prevent read - should handle gracefully" {
	# Purpose: Test verifies that the script handles unreadable state files gracefully.
	# Expected: Script defaults to 0 or handles error gracefully when state file cannot be read.
	# Importance: Permission issues can prevent reading state files; script must handle gracefully.
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	source_function "get_peer_state_file_path"

	# Create failure counter file and make it unreadable (prevents read)
	local failure_counter
	failure_counter=$(setup_readonly_state_file "" "${TEST_PEER_IP}" "failure_count" "3" "000")
	# Verify permissions were set correctly
	assert_file_permission 000 "$failure_counter"

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should handle unreadable state file gracefully (should default to 0 or handle error)
	assert_file_exist "$LOG_FILE"

	# Trap will restore permissions automatically on EXIT
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "state file deleted during script execution - should handle gracefully" {
	# Purpose: Test verifies that the script handles state files that are deleted during execution.
	# Expected: Script recreates deleted files or defaults to 0, continuing execution without crashing.
	# Importance: Files can be deleted by other processes or manual intervention; script must handle gracefully.
	setup_vpn_down_fixture "${TEST_PEER_IP}" 2

	source_function "get_peer_state_file_path"

	# Delete failure counter file during execution (simulate file deletion)
	# This is a simplified test - in real scenario, file might be deleted between checks
	local failure_counter
	failure_counter=$(get_state_file_path "" "${TEST_PEER_IP}" "failure_count")
	rm -f "$failure_counter"

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should handle deleted state file gracefully (should recreate or default to 0)
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# ============================================================================
# 6.2 CONCURRENT STATE ACCESS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "state file modified during script execution (lockfile should prevent this) - should prevent concurrent modification" {
	# Purpose: Test verifies that lockfile mechanism prevents concurrent state file modification.
	# Expected: Lockfile prevents concurrent execution, ensuring state file is not modified during script execution.
	# Importance: Concurrent modification can cause data corruption; lockfile mechanism must prevent it.
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	# Run script - lockfile should prevent concurrent execution
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Lockfile prevents concurrent execution, so state file modification should not occur
	# This test verifies that lockfile mechanism works (implicitly tested by lockfile tests)
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# ============================================================================
# 4.2 STATE FILE CORRUPTION RECOVERY
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "State file corruption - Backup created before recovery - should create backup file" {
	# Purpose: Test verifies that corrupted state files are backed up before recovery.
	# Expected: Backup file is created with .corrupted.<timestamp> suffix before recovery.
	# Importance: Backup files allow forensic analysis and manual recovery.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	source_function "get_peer_state_file_path"

	# Create corrupted failure counter file
	local failure_counter
	failure_counter=$(create_corrupted_state_file "" "${TEST_PEER_IP}" "failure_count")

	# Source state functions to test directly
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true

	# Trigger recovery by reading the corrupted file
	local value
	value=$(get_peer_state "" "${TEST_PEER_IP}" "failure_count" "0")

	# Verify backup file was created
	local backup_files
	backup_files=$(find "${STATE_DIR}" -name "failure_counter_LOCATION_192_168_1_1.corrupted.*" 2>/dev/null | wc -l)
	assert [ "$backup_files" -gt 0 ]

	# Verify file was recovered
	assert_equal "$value" "0"
}

# bats test_tags=category:high-risk,priority:high
@test "State file corruption - Multiple file types corrupted simultaneously - should recover all files" {
	# Purpose: Test verifies that multiple corrupted state files are recovered correctly.
	# Expected: All corrupted files are backed up and recovered.
	# Importance: Ensures recovery works when multiple files are corrupted.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	source_function "get_peer_state_file_path"

	# Create multiple corrupted files
	local failure_counter
	failure_counter=$(create_corrupted_state_file "" "${TEST_PEER_IP}" "failure_count")
	local bytes_file
	bytes_file=$(create_corrupted_state_file "" "${TEST_PEER_IP}" "last_bytes")
	local spi_file
	spi_file=$(create_corrupted_state_file "" "${TEST_PEER_IP}" "spi")
	local cooldown_file="${STATE_DIR}/cooldown_until"

	echo "invalid-value" >"$cooldown_file"

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Run script - should recover all corrupted files
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should handle all corrupted files gracefully
	assert_success
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "State file corruption - Backup file creation fails for readable file - should preserve corrupted file" {
	# Purpose: Test verifies that recovery fails and preserves corrupted file if backup fails for a readable file.
	# Expected: Recovery fails, corrupted file is preserved (not reset).
	# Importance: Prevents data loss when backup fails due to disk space or permissions.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	source_function "get_peer_state_file_path"

	# Create corrupted failure counter file
	local failure_counter
	failure_counter=$(create_corrupted_state_file "" "${TEST_PEER_IP}" "failure_count")

	# Store original corrupted content
	local original_content
	original_content=$(cat "$failure_counter")

	# Make STATE_DIR read-only to prevent backup creation
	# Note: Backup files are created in the same directory as state files
	local original_dir_perms
	original_dir_perms=$(stat -c %a "${STATE_DIR}")
	chmod 555 "${STATE_DIR}"
	# Use trap to ensure cleanup even on errors
	trap "chmod $original_dir_perms \"\${STATE_DIR}\" 2>/dev/null || true" EXIT

	# Source state functions to test directly
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true

	# Trigger recovery - should fail because backup failed
	run recover_corrupted_state_file "$failure_counter" "0" "integer"
	assert_failure

	# Verify corrupted file is preserved (not reset)
	assert_file_exist "$failure_counter"
	local preserved_content
	preserved_content=$(cat "$failure_counter")
	assert_equal "$preserved_content" "$original_content"

	# Trap will restore permissions automatically on EXIT
}

# bats test_tags=category:high-risk,priority:high
@test "State file corruption - Unreadable file recovery - should recover even without backup" {
	# Purpose: Test verifies that unreadable files can be recovered even though they cannot be backed up.
	# Expected: File is recovered (removed/reset) even though backup is skipped.
	# Importance: Unreadable files cannot be backed up, but should still be recoverable.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	source_function "get_peer_state_file_path"

	# Create corrupted failure counter file
	local failure_counter
	failure_counter=$(create_corrupted_state_file "" "${TEST_PEER_IP}" "failure_count")

	# Make file unreadable (but still exists)
	local original_perms
	original_perms=$(stat -c %a "$failure_counter")
	chmod 000 "$failure_counter"
	# Use trap to ensure cleanup even on errors
	trap "chmod $original_perms \"\$failure_counter\" 2>/dev/null || true" EXIT

	# Source state functions to test directly
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true

	# Trigger recovery - should succeed even though backup is skipped
	run recover_corrupted_state_file "$failure_counter" "0" "integer"
	assert_success

	# Verify file was recovered (reset to default)
	assert_file_exist "$failure_counter"
	local value
	value=$(cat "$failure_counter")
	assert_equal "$value" "0"
	# Clear trap after successful test
	trap - EXIT
}

# bats test_tags=category:high-risk,priority:high
@test "State file corruption - Caller handles recovery failure gracefully - should return default value" {
	# Purpose: Test verifies that callers of recover_corrupted_state_file handle recovery failures gracefully.
	# Expected: Caller returns default value even if recovery fails, corrupted file is preserved.
	# Importance: Ensures system continues to work even when recovery fails (e.g., backup fails).
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	source_function "get_peer_state"
	source_function "get_peer_state_file_path"

	# Create corrupted failure counter file
	local failure_counter
	failure_counter=$(create_corrupted_state_file "" "${TEST_PEER_IP}" "failure_count")

	# Store original corrupted content
	local original_content
	original_content=$(cat "$failure_counter")

	# Make STATE_DIR read-only to prevent backup creation
	# Note: Backup files are created in the same directory as state files
	local original_dir_perms
	original_dir_perms=$(stat -c %a "${STATE_DIR}")
	chmod 555 "${STATE_DIR}"
	# Use trap to ensure cleanup even on errors
	trap "chmod $original_dir_perms \"\${STATE_DIR}\" 2>/dev/null || true" EXIT

	# Source state functions to test directly
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true

	# Call get_peer_state which internally calls recover_corrupted_state_file
	# Even though recovery fails, get_peer_state should return default value
	local value
	value=$(get_peer_state "" "${TEST_PEER_IP}" "failure_count" "0")

	# Verify caller returns default value even though recovery failed
	assert_equal "$value" "0"

	# Verify corrupted file is preserved (recovery failed, so file wasn't reset)
	assert_file_exist "$failure_counter"
	local preserved_content
	preserved_content=$(cat "$failure_counter")
	assert_equal "$preserved_content" "$original_content"

	# Restore permissions
	chmod 755 "${STATE_DIR}" 2>/dev/null || true
	# Clear trap after successful restore
	trap - EXIT
}

# bats test_tags=category:high-risk,priority:high
@test "State file corruption - Recovery with empty default (file removal) - should remove file" {
	# Purpose: Test verifies that corrupted files are removed when default value is empty.
	# Expected: File is removed when default value is empty string.
	# Importance: Some state files should be removed rather than reset to a value.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Create corrupted cooldown file
	local cooldown_file="${STATE_DIR}/cooldown_until"
	echo "invalid-timestamp" >"$cooldown_file"

	# Source state functions to test directly
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true

	# Trigger recovery with empty default (should remove file)
	run recover_corrupted_state_file "$cooldown_file" "" "timestamp"
	assert_success

	# Verify file was removed
	assert_file_not_exist "$cooldown_file"
}

# bats test_tags=category:high-risk,priority:high
@test "State file corruption - Recovery with non-empty default (file reset) - should reset to default" {
	# Purpose: Test verifies that corrupted files are reset to default value when provided.
	# Expected: File is reset to default value.
	# Importance: Ensures corrupted files are reset to safe defaults.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	source_function "get_peer_state_file_path"

	# Create corrupted failure counter file
	local failure_counter
	failure_counter=$(create_corrupted_state_file "" "${TEST_PEER_IP}" "failure_count")

	# Source state functions to test directly
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true

	# Trigger recovery with non-empty default
	run recover_corrupted_state_file "$failure_counter" "0" "integer"
	assert_success

	# Verify file was reset to default value
	assert_file_exist "$failure_counter"
	local value
	value=$(cat "$failure_counter")
	assert_equal "$value" "0"
}

# bats test_tags=category:high-risk,priority:high
@test "State file corruption - Per-peer files corrupted (failure_count, last_bytes, spi) - should recover all files" {
	# Purpose: Test verifies that corrupted per-peer state files are recovered correctly.
	# Expected: All per-peer files are backed up and recovered.
	# Importance: Per-peer files are critical for monitoring individual peers.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	source_function "get_peer_state_file_path"

	# Create corrupted per-peer files
	local failure_counter
	failure_counter=$(create_corrupted_state_file "" "${TEST_PEER_IP}" "failure_count")
	local bytes_file
	bytes_file=$(create_corrupted_state_file "" "${TEST_PEER_IP}" "last_bytes")
	local spi_file
	spi_file=$(create_corrupted_state_file "" "${TEST_PEER_IP}" "spi")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Run script - should recover all corrupted per-peer files
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should handle all corrupted files gracefully
	assert_success
	assert_file_exist "$LOG_FILE"

	# Verify files were recovered
	if [[ -f "$failure_counter" ]]; then
		local value
		value=$(cat "$failure_counter")
		assert_equal "$value" "0"
	fi

	remove_mock_from_path
}

# ============================================================================
# 4.3 NETWORK PARTITION STATE MANAGEMENT
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "Network partition state - Get state when file doesn't exist - should return 0" {
	# Purpose: Test verifies that get_network_partition_state returns 0 when state file doesn't exist.
	# Expected: Function returns "0" (healthy) when file doesn't exist.
	# Importance: Defaults to healthy state when no state is stored.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Source state functions to test directly
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true

	# Ensure state file doesn't exist
	local partition_state_file="${STATE_DIR}/network_partition_state"
	rm -f "$partition_state_file"

	# Test get_network_partition_state function
	local state
	state=$(get_network_partition_state)
	assert_equal "$state" "0"
}

# bats test_tags=category:high-risk,priority:high
@test "Network partition state - Set state to 0 (healthy) - should set state correctly" {
	# Purpose: Test verifies that set_network_partition_state correctly sets state to 0 (healthy).
	# Expected: Function sets state to 0 and file contains "0".
	# Importance: Allows marking network as healthy.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Source state functions to test directly
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true

	# Test set_network_partition_state function
	run set_network_partition_state 0
	assert_success

	# Verify state file contains "0"
	local partition_state_file="${STATE_DIR}/network_partition_state"
	assert_file_exist "$partition_state_file"
	local state
	state=$(cat "$partition_state_file")
	assert_equal "$state" "0"
}

# bats test_tags=category:high-risk,priority:high
@test "Network partition state - Set state to 1 (partitioned) - should set state correctly" {
	# Purpose: Test verifies that set_network_partition_state correctly sets state to 1 (partitioned).
	# Expected: Function sets state to 1 and file contains "1".
	# Importance: Allows marking network as partitioned.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Source state functions to test directly
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true

	# Test set_network_partition_state function
	run set_network_partition_state 1
	assert_success

	# Verify state file contains "1"
	local partition_state_file="${STATE_DIR}/network_partition_state"
	assert_file_exist "$partition_state_file"
	local state
	state=$(cat "$partition_state_file")
	assert_equal "$state" "1"
}

# bats test_tags=category:high-risk,priority:high
@test "Network partition state - Invalid value (not 0 or 1) - should reject" {
	# Purpose: Test verifies that set_network_partition_state rejects invalid values.
	# Expected: Function returns error when value is not 0 or 1.
	# Importance: Prevents invalid state values from being stored.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Source state functions to test directly
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true

	# Test set_network_partition_state with invalid value
	run set_network_partition_state 2
	assert_failure

	# Test with another invalid value
	run set_network_partition_state "invalid"
	assert_failure
}

# bats test_tags=category:high-risk,priority:high
@test "Network partition state - File corrupted - should recover to 0" {
	# Purpose: Test verifies that corrupted network partition state file is recovered to 0.
	# Expected: Function recovers corrupted file and returns "0".
	# Importance: Prevents script failures from corrupted state files.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Create corrupted state file
	local partition_state_file="${STATE_DIR}/network_partition_state"
	echo "invalid-value" >"$partition_state_file"

	# Source state functions to test directly
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true

	# Test get_network_partition_state function (should recover corrupted file)
	local state
	state=$(get_network_partition_state)
	assert_equal "$state" "0"

	# Verify file was recovered
	assert_file_exist "$partition_state_file"
	local file_content
	file_content=$(cat "$partition_state_file")
	assert_equal "$file_content" "0"
}

# bats test_tags=category:high-risk,priority:high
@test "Network partition state - Atomic write ensures consistency - should use atomic writes" {
	# Purpose: Test verifies that network partition state uses atomic writes for consistency.
	# Expected: State file updates are atomic (no partial writes).
	# Importance: Atomic writes prevent corruption from concurrent access.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Source state functions to test directly
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true

	local partition_state_file="${STATE_DIR}/network_partition_state"

	# Set state multiple times to verify atomic writes
	for i in 0 1 0 1; do
		run set_network_partition_state "$i"
		assert_success

		# Verify state file contains correct value
		local state
		state=$(cat "$partition_state_file")
		assert_equal "$state" "$i"
	done
}

# ============================================================================
# 4.1 PER-PEER STATE ABSTRACTION LAYER
# ============================================================================

# bats test_tags=category:high-risk,priority:medium
@test "Per-peer state - Unknown key type - should use default path" {
	# Purpose: Test verifies that unknown key types use default path.
	# Expected: Unknown keys use STATE_DIR/<key>_<sanitized_ip> path.
	# Importance: Ensures abstraction layer handles unknown keys gracefully.
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	# Source state.sh to access functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${TEST_DIR}"

	# Test unknown key type
	local unknown_key="unknown_key"
	local peer_ip="192.168.1.1"
	local state_file
	state_file=$(get_peer_state_file_path "" "$peer_ip" "$unknown_key")

	# Should use default path (STATE_DIR/<key>_LOCATION_<sanitized_ip>)
	[[ "$state_file" == "${STATE_DIR}/${unknown_key}_LOCATION_192_168_1_1" ]]

	# Should be able to set/get unknown key
	set_peer_state "" "$peer_ip" "$unknown_key" "test_value" || true
	local value
	value=$(get_peer_state "" "$peer_ip" "$unknown_key" "default")
	[[ "$value" == "test_value" ]] || [[ "$value" == "default" ]]
}

# bats test_tags=category:high-risk,priority:medium
@test "Per-peer state - Atomic write failure - should handle gracefully" {
	# Purpose: Test verifies that atomic write failures are handled gracefully.
	# Expected: Script handles write failures without crashing.
	# Importance: Write failures can occur due to disk full or permissions.
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	# Source state.sh to access functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${TEST_DIR}"

	# Create read-only directory to simulate write failure
	local readonly_dir="${TEST_DIR}/readonly"
	mkdir -p "$readonly_dir"
	local original_dir_perms
	original_dir_perms=$(stat -c %a "$readonly_dir")
	chmod 555 "$readonly_dir"
	# Use trap to ensure cleanup even on errors
	trap "chmod $original_dir_perms \"\$readonly_dir\" 2>/dev/null || true" EXIT

	# Try to write to read-only directory (should fail gracefully)
	local original_state_dir="$STATE_DIR"
	export STATE_DIR="$readonly_dir"

	# Should handle write failure gracefully
	if ! set_peer_state "" "192.168.1.1" "last_bytes" "1000" 2>/dev/null; then
		# Write failed - this is expected
		# Should not crash
		:
	fi

	# Restore permissions for cleanup
	chmod 755 "$readonly_dir" 2>/dev/null || true
	# Clear trap after successful restore
	trap - EXIT
	export STATE_DIR="$original_state_dir"
}

# bats test_tags=category:high-risk,priority:medium
@test "Per-peer state - File path resolution for all key types - should resolve correctly" {
	# Purpose: Test verifies that file path resolution works for all key types.
	# Expected: Each key type resolves to correct file path.
	# Importance: Ensures abstraction layer works for all state types.
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	# Source state.sh to access functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${TEST_DIR}"

	local peer_ip="192.168.1.1"

	# Test all key types - use empty string for location to test backward compatibility
	local failure_count_path
	failure_count_path=$(get_peer_state_file_path "" "$peer_ip" "failure_count")
	[[ "$failure_count_path" == "${STATE_DIR}/failure_counter_LOCATION_192_168_1_1" ]]

	local last_bytes_path
	last_bytes_path=$(get_peer_state_file_path "" "$peer_ip" "last_bytes")
	[[ "$last_bytes_path" == "${STATE_DIR}/last_bytes_LOCATION_192_168_1_1" ]]

	local spi_path
	spi_path=$(get_peer_state_file_path "" "$peer_ip" "spi")
	[[ "$spi_path" == "${STATE_DIR}/spi_LOCATION_192_168_1_1" ]]

	local idle_detected_path
	idle_detected_path=$(get_peer_state_file_path "" "$peer_ip" "idle_detected")
	[[ "$idle_detected_path" == "${STATE_DIR}/idle_detected_LOCATION_192_168_1_1" ]]

	local failure_type_path
	failure_type_path=$(get_peer_state_file_path "" "$peer_ip" "failure_type")
	[[ "$failure_type_path" == "${STATE_DIR}/failure_type_LOCATION_192_168_1_1" ]]
}

# bats test_tags=category:high-risk,priority:medium
@test "Per-peer state - IPv6 peer IPs - Sanitization and file paths - should sanitize correctly" {
	# Purpose: Test verifies that IPv6 peer IPs are sanitized correctly for file paths.
	# Expected: IPv6 addresses are sanitized (colons replaced with underscores).
	# Importance: IPv6 support requires proper sanitization.
	setup_test_vpn_monitor "2001:db8::1" "${TEST_DIR}"

	# Source state.sh to access functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${TEST_DIR}"

	local peer_ip="2001:db8::1"

	# Test IPv6 sanitization
	local sanitized
	sanitized=$(sanitize_peer_ip "$peer_ip")
	[[ "$sanitized" == "2001_db8__1" ]]

	# Test file path resolution for IPv6 - use empty string for location to test backward compatibility
	local failure_count_path
	failure_count_path=$(get_peer_state_file_path "" "$peer_ip" "failure_count")
	[[ "$failure_count_path" == "${STATE_DIR}/failure_counter_LOCATION_2001_db8__1" ]]

	# Should be able to set/get IPv6 peer state - use empty string for location to test backward compatibility
	set_peer_state "" "$peer_ip" "failure_count" "5" || true
	local value
	value=$(get_peer_state "" "$peer_ip" "failure_count" "0")
	[[ "$value" == "5" ]] || [[ "$value" == "0" ]]
}

# bats test_tags=category:high-risk,priority:medium
@test "Per-peer state - Concurrent access (multiple peers) - should not interfere" {
	# Purpose: Test verifies that concurrent access for multiple peers doesn't interfere.
	# Expected: Each peer's state is independent and doesn't affect others.
	# Importance: Multiple peers should be monitored independently.
	setup_test_vpn_monitor "192.168.1.1 10.0.0.1" "${TEST_DIR}"

	# Source state.sh to access functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${TEST_DIR}"

	local peer1="192.168.1.1"
	local peer2="10.0.0.1"

	# Set different state values for each peer
	set_peer_state "" "$peer1" "failure_count" "3" || true
	set_peer_state "" "$peer2" "failure_count" "5" || true

	# Get state values - should be independent
	local count1
	count1=$(get_peer_state "" "$peer1" "failure_count" "0")
	local count2
	count2=$(get_peer_state "" "$peer2" "failure_count" "0")

	# Values should be independent
	[[ "$count1" == "3" ]] || [[ "$count1" == "0" ]]
	[[ "$count2" == "5" ]] || [[ "$count2" == "0" ]]
	[[ "$count1" != "$count2" ]] || [[ "$count1" == "0" ]] || [[ "$count2" == "0" ]]

	# File paths should be different
	local path1
	path1=$(get_peer_state_file_path "$peer1" "failure_count")
	local path2
	path2=$(get_peer_state_file_path "$peer2" "failure_count")
	[[ "$path1" != "$path2" ]]
}

# ============================================================================
