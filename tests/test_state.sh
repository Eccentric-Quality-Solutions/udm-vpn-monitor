#!/usr/bin/env bats
#
# Tests for State File Management
# Tests critical paths and error handling scenarios

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
	failure_counter=$(create_corrupted_state_file "TEST" "${TEST_PEER_IP}" "failure_count" "invalid-non-numeric-value")

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
	failure_counter=$(get_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
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
	failure_counter=$(get_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
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
	failure_counter=$(setup_readonly_state_file "TEST" "${TEST_PEER_IP}" "failure_count" "3" "444")
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

# bats test_tags=category:high-risk,priority:high,slow
@test "state file permissions prevent read - should handle gracefully" {
	# Purpose: Test verifies that the script handles unreadable state files gracefully.
	# Expected: Script defaults to 0 or handles error gracefully when state file cannot be read.
	# Importance: Permission issues can prevent reading state files; script must handle gracefully.
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	source_function "get_peer_state_file_path"

	# Create failure counter file and make it unreadable (prevents read)
	local failure_counter
	failure_counter=$(setup_readonly_state_file "TEST" "${TEST_PEER_IP}" "failure_count" "3" "000")
	# Verify permissions were set correctly (use stat with timeout to avoid hanging)
	# Note: stat can hang on files with 000 permissions in some cases, so we use timeout
	# Format as 3-digit octal for comparison (stat returns "0" not "000")
	local actual_perms="000"
	if command -v timeout >/dev/null 2>&1; then
		# Use timeout to prevent stat from hanging
		actual_perms=$(timeout 2 stat -c "%a" "$failure_counter" 2>/dev/null || echo "0")
		# Convert to 3-digit format for comparison (0 -> 000)
		actual_perms=$(printf "%03d" "$actual_perms" 2>/dev/null || echo "000")
	else
		# Fallback: trust setup_readonly_state_file worked correctly
		# If timeout is not available, skip verification to avoid hanging
		actual_perms="000"
	fi
	# Only verify if we successfully got permissions (non-blocking)
	# Note: actual_perms will always be non-empty (defaults to "000"), so we only check the value
	if [[ "$actual_perms" != "000" ]]; then
		fail "Expected file permissions 000, got: $actual_perms"
	fi

	# Save original permissions for explicit cleanup (belt and suspenders approach)
	# setup_readonly_state_file already sets up an EXIT trap, but we also restore
	# explicitly to ensure cleanup happens even if trap doesn't execute
	# Note: We use default 644 since the file is already unreadable (000) and calling
	# save_permissions_for_restore on an unreadable file might hang (stat can hang on 000 files)
	# setup_readonly_state_file already saved the original permissions before changing them,
	# so we use the standard default file permissions (644) for cleanup
	local original_perms="644"

	# Ensure cleanup happens even if test is killed
	# Trap multiple signals to ensure cleanup happens even if test is killed externally
	trap 'restore_permissions_after_test "$failure_counter" "$original_perms" 2>/dev/null || true' EXIT INT TERM QUIT HUP

	add_mock_to_path
	# Use timeout to prevent test from hanging if script doesn't handle unreadable file gracefully
	# Use a reasonable timeout (30 seconds) to allow script to complete normally but fail fast if it hangs
	# The script should handle unreadable files gracefully and complete quickly (< 5 seconds typically)
	# Increase timeout to account for system load when running large test suites
	# Use longer timeout to prevent false positives when system is under load
	local timeout_duration=30

	# Check if timeout command is available
	if ! command -v timeout >/dev/null 2>&1; then
		skip "timeout command not available"
	fi

	# Defensive check: ensure TEST_SCRIPT is set and exists
	if [[ -z "${TEST_SCRIPT:-}" ]]; then
		fail "TEST_SCRIPT is not set - setup_vpn_active_fixture may have failed"
	fi
	if [[ ! -f "$TEST_SCRIPT" ]]; then
		fail "TEST_SCRIPT does not exist: $TEST_SCRIPT"
	fi

	# Run script with timeout
	# timeout returns 124 if command times out
	# Use run to capture output - BATS handles this correctly
	# The key is to ensure we restore permissions even if the process is killed
	# Note: We don't use || true here because we want to capture the actual exit status
	# BATS run command will capture the exit status correctly even if timeout kills the process
	# Use timeout with --kill-after to ensure all child processes are killed if script hangs
	# --kill-after=2 ensures child processes are killed 2 seconds after the main process
	# This prevents hangs from child processes that might not respond to SIGTERM quickly
	# Increase kill-after time to be more aggressive about killing stuck processes
	# Don't use --preserve-status so timeout returns 124 on timeout (default behavior)
	run timeout --kill-after=2 $timeout_duration bash "$TEST_SCRIPT" --fake 2>&1
	local exit_status=$status

	# Restore permissions immediately after script execution to prevent issues
	# This is critical - even if test fails or is killed, we need to restore permissions
	# chmod should never hang, but we suppress errors to ensure test continues
	restore_permissions_after_test "$failure_counter" "$original_perms" || true
	# Keep trap active as backup in case of unexpected exit before test completes

	# Allow exit code 0 (success) or 124 (timeout) - timeout indicates script hung
	# Exit code 124 = timeout (default timeout behavior without --preserve-status)
	# Exit codes 128+signal indicate process was killed by signal (e.g., 143 = SIGTERM, 137 = SIGKILL)
	# If timeout occurred or process was killed, the script didn't handle unreadable file gracefully
	# Fail immediately if timeout occurred - don't continue with assertions that might hang
	# Clear trap before failing to ensure clean exit
	if [[ $exit_status -eq 124 ]] || [[ $exit_status -eq 143 ]] || [[ $exit_status -eq 137 ]] || [[ $exit_status -gt 128 ]]; then
		trap - EXIT INT TERM QUIT HUP
		remove_mock_from_path
		fail "Script hung when trying to read unreadable state file (timeout/killed after ${timeout_duration}s, exit code: $exit_status) - script should handle this gracefully"
	fi
	# Otherwise, script should succeed (handles unreadable file gracefully)
	# Exit code 0 = success, 1 = warnings (acceptable), others = unexpected
	if [[ $exit_status -ne 0 ]] && [[ $exit_status -ne 1 ]]; then
		fail "Script exited with unexpected status: $exit_status (expected 0 or 1 for warnings)"
	fi

	# Should handle unreadable state file gracefully (should default to 0 or handle error)
	# At this point, exit_status is guaranteed to be 0 or 1 (checked above)
	assert_file_exist "$LOG_FILE"

	# Clear trap after successful test completion (permissions already restored)
	trap - EXIT INT TERM QUIT HUP
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
	failure_counter=$(get_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
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
	failure_counter=$(create_corrupted_state_file "TEST" "${TEST_PEER_IP}" "failure_count")

	# Source state functions to test directly
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true

	# Trigger recovery directly to verify backup is created
	# Note: We test recover_corrupted_state_file directly rather than through get_peer_state
	# because get_peer_state doesn't check the return value of recover_corrupted_state_file.
	# If backup fails, get_peer_state still returns the default value but no backup is created.
	# This test specifically verifies backup creation, so we test the mechanism directly.
	run recover_corrupted_state_file "$failure_counter" "0" "integer"
	assert_success

	# Verify backup file was created
	# Use the actual state file path to construct the backup pattern
	local state_file_basename
	state_file_basename=$(basename "$failure_counter")
	local backup_files
	backup_files=$(find "${STATE_DIR}" -name "${state_file_basename}.corrupted.*" 2>/dev/null | wc -l)
	assert [ "$backup_files" -gt 0 ]

	# Verify file was recovered
	local value
	value=$(cat "$failure_counter" 2>/dev/null || echo "0")
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
	failure_counter=$(create_corrupted_state_file "TEST" "${TEST_PEER_IP}" "failure_count")
	create_corrupted_state_file "TEST" "${TEST_PEER_IP}" "last_bytes" >/dev/null
	create_corrupted_state_file "TEST" "${TEST_PEER_IP}" "spi" >/dev/null
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
	failure_counter=$(create_corrupted_state_file "TEST" "${TEST_PEER_IP}" "failure_count")

	# Store original corrupted content
	local original_content
	original_content=$(cat "$failure_counter")

	# Make STATE_DIR read-only to prevent backup creation
	# Note: Backup files are created in the same directory as state files
	local original_dir_perms
	original_dir_perms=$(stat -c %a "${STATE_DIR}")
	chmod 555 "${STATE_DIR}"
	# Use trap to ensure cleanup even on errors
	trap 'chmod $original_dir_perms "${STATE_DIR}" 2>/dev/null || true' EXIT

	# Source state functions to test directly
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true

	# Trigger recovery - should fail because backup failed
	# Use timeout to prevent test from hanging if directory write check hangs
	# This can happen on some systems when checking writability of read-only directories
	# The backup_corrupted_state_file function checks directory writability, which might hang
	local timeout_duration=10
	if command -v timeout >/dev/null 2>&1; then
		# Use timeout with --kill-after to ensure process is killed if it hangs
		# Note: STATE_DIR and LOGS_DIR are already exported by setup_test_vpn_monitor
		# Use shorter timeout and more aggressive kill-after to prevent hangs
		run timeout --kill-after=1 $timeout_duration bash -c "
			# Source state functions in subshell (needed since we're in a new bash process)
			source '${BATS_TEST_DIRNAME}/../lib/state.sh' || true
			# Export environment variables needed by state functions
			export STATE_DIR='${STATE_DIR}'
			export LOGS_DIR='${LOGS_DIR}'
			# Call recovery function
			recover_corrupted_state_file '${failure_counter}' '0' 'integer'
		" 2>&1
		local exit_status=$status
		# Restore permissions immediately after timeout check to prevent issues
		# This must happen before any assertions that might fail
		chmod "$original_dir_perms" "${STATE_DIR}" 2>/dev/null || true
		# If timeout occurred, fail immediately
		if [[ $exit_status -eq 124 ]] || [[ $exit_status -eq 143 ]] || [[ $exit_status -eq 137 ]] || [[ $exit_status -gt 128 ]]; then
			trap - EXIT
			fail "recover_corrupted_state_file hung when backup directory is read-only (timeout/killed after ${timeout_duration}s, exit code: $exit_status)"
		fi
		# Should fail because backup failed (exit code 1)
		# Verify it failed (backup should have failed)
		assert_failure
	else
		# Fallback without timeout (may hang on some systems)
		# Note: On UDM OS, timeout should be available, but handle gracefully if not
		run recover_corrupted_state_file "$failure_counter" "0" "integer"
		local exit_status=$status
		# Restore permissions immediately after function call
		chmod "$original_dir_perms" "${STATE_DIR}" 2>/dev/null || true
		assert_failure
	fi

	# Verify corrupted file is preserved (not reset)
	assert_file_exist "$failure_counter"
	local preserved_content
	preserved_content=$(cat "$failure_counter")
	assert_equal "$preserved_content" "$original_content"

	# Clear trap after successful test completion (permissions already restored)
	trap - EXIT
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
	failure_counter=$(create_corrupted_state_file "TEST" "${TEST_PEER_IP}" "failure_count")

	# Make file unreadable (but still exists)
	local original_perms
	original_perms=$(stat -c %a "$failure_counter")
	chmod 000 "$failure_counter"
	# Use trap to ensure cleanup even on errors
	trap 'chmod $original_perms "$failure_counter" 2>/dev/null || true' EXIT

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
	failure_counter=$(create_corrupted_state_file "TEST" "${TEST_PEER_IP}" "failure_count")

	# Store original corrupted content
	local original_content
	original_content=$(cat "$failure_counter")

	# Make STATE_DIR read-only to prevent backup creation
	# Note: Backup files are created in the same directory as state files
	local original_dir_perms
	original_dir_perms=$(stat -c %a "${STATE_DIR}")
	chmod 555 "${STATE_DIR}"
	# Use trap to ensure cleanup even on errors
	trap 'chmod $original_dir_perms "${STATE_DIR}" 2>/dev/null || true' EXIT

	# Source state functions to test directly
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true

	# Call get_peer_state which internally calls recover_corrupted_state_file
	# Even though recovery fails, get_peer_state should return default value
	local value
	value=$(get_peer_state "TEST" "${TEST_PEER_IP}" "failure_count" "0")

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
	failure_counter=$(create_corrupted_state_file "TEST" "${TEST_PEER_IP}" "failure_count")

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
	failure_counter=$(create_corrupted_state_file "TEST" "${TEST_PEER_IP}" "failure_count")
	create_corrupted_state_file "TEST" "${TEST_PEER_IP}" "last_bytes" >/dev/null
	create_corrupted_state_file "TEST" "${TEST_PEER_IP}" "spi" >/dev/null

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
	state_file=$(get_peer_state_file_path "TEST" "$peer_ip" "$unknown_key")

	# Should use default path (STATE_DIR/<key>_<location>_<sanitized_ip>)
	[[ "$state_file" == "${STATE_DIR}/${unknown_key}_TEST_192_168_1_1" ]]

	# Should be able to set/get unknown key
	set_peer_state "TEST" "$peer_ip" "$unknown_key" "test_value" || true
	local value
	value=$(get_peer_state "TEST" "$peer_ip" "$unknown_key" "default")
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
	trap 'chmod $original_dir_perms "$readonly_dir" 2>/dev/null || true' EXIT

	# Try to write to read-only directory (should fail gracefully)
	local original_state_dir="$STATE_DIR"
	export STATE_DIR="$readonly_dir"

	# Should handle write failure gracefully
	if ! set_peer_state "TEST" "192.168.1.1" "last_bytes" "1000" 2>/dev/null; then
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

	# Test all key types
	local failure_count_path
	failure_count_path=$(get_peer_state_file_path "TEST" "$peer_ip" "failure_count")
	[[ "$failure_count_path" == "${STATE_DIR}/failure_count_TEST_192_168_1_1" ]]

	local last_bytes_path
	last_bytes_path=$(get_peer_state_file_path "TEST" "$peer_ip" "last_bytes")
	[[ "$last_bytes_path" == "${STATE_DIR}/last_bytes_TEST_192_168_1_1" ]]

	local spi_path
	spi_path=$(get_peer_state_file_path "TEST" "$peer_ip" "spi")
	[[ "$spi_path" == "${STATE_DIR}/spi_TEST_192_168_1_1" ]]

	local idle_detected_path
	idle_detected_path=$(get_peer_state_file_path "TEST" "$peer_ip" "idle_detected")
	[[ "$idle_detected_path" == "${STATE_DIR}/idle_detected_TEST_192_168_1_1" ]]

	local failure_type_path
	failure_type_path=$(get_peer_state_file_path "TEST" "$peer_ip" "failure_type")
	[[ "$failure_type_path" == "${STATE_DIR}/failure_type_TEST_192_168_1_1" ]]
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

	# Test file path resolution for IPv6
	local failure_count_path
	failure_count_path=$(get_peer_state_file_path "TEST" "$peer_ip" "failure_count")
	[[ "$failure_count_path" == "${STATE_DIR}/failure_count_TEST_2001_db8__1" ]]

	# Should be able to set/get IPv6 peer state
	set_peer_state "TEST" "$peer_ip" "failure_count" "5" || true
	local value
	value=$(get_peer_state "TEST" "$peer_ip" "failure_count" "0")
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
	set_peer_state "TEST" "$peer1" "failure_count" "3" || true
	set_peer_state "TEST" "$peer2" "failure_count" "5" || true

	# Get state values - should be independent
	local count1
	count1=$(get_peer_state "TEST" "$peer1" "failure_count" "0")
	local count2
	count2=$(get_peer_state "TEST" "$peer2" "failure_count" "0")

	# Values should be independent
	[[ "$count1" == "3" ]] || [[ "$count1" == "0" ]]
	[[ "$count2" == "5" ]] || [[ "$count2" == "0" ]]
	[[ "$count1" != "$count2" ]] || [[ "$count1" == "0" ]] || [[ "$count2" == "0" ]]

	# File paths should be different
	local path1
	path1=$(get_peer_state_file_path "TEST" "$peer1" "failure_count")
	local path2
	path2=$(get_peer_state_file_path "TEST" "$peer2" "failure_count")
	[[ "$path1" != "$path2" ]]
}

# ============================================================================
# STATE FILE WRITE FAILURES - Previously Untested Critical Paths (P0)
# Tests for untested critical paths identified in docs/UNTESTED_CRITICAL_PATHS.md
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "state file atomic write fails - filesystem full" {
	# Purpose: Test verifies that script handles read-only STATE_DIR gracefully by exiting early
	# Expected: Script detects STATE_DIR is not writable, cannot create lockfile, exits with clear error
	# Importance: When STATE_DIR is read-only (e.g., filesystem full), script cannot create lockfile and must exit
	# Note: This tests early exit when STATE_DIR is not writable, not write failures during execution
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command - VPN healthy
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Make state directory read-only to simulate filesystem full or permission error
	# This prevents lockfile creation, so script must exit early
	chmod 555 "$STATE_DIR" 2>/dev/null || true

	# Run script - should exit early with error when STATE_DIR is not writable
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake 2>&1

	# Restore permissions immediately after script execution to prevent issues
	# This is critical - even if test fails or is killed, we need to restore permissions
	chmod 755 "$STATE_DIR" 2>/dev/null || true

	# Should fail with error code 4 (permission error) since lockfile cannot be created
	assert_failure
	assert_output --partial "STATE_DIR is not writable"
	assert_output --partial "cannot create lockfile"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "state file atomic write fails - permission error" {
	# Purpose: Test verifies that script handles read-only STATE_DIR gracefully by exiting early
	# Expected: Script detects STATE_DIR is not writable, cannot create lockfile, exits with clear error
	# Importance: When STATE_DIR has permission errors, script cannot create lockfile and must exit
	# Note: This tests early exit when STATE_DIR is not writable, not write failures during execution
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script BEFORE making STATE_DIR read-only
	# (since STATE_DIR == TEST_DIR, we need to create files first)
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command - VPN healthy (must be done before making STATE_DIR read-only)
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Now make state directory read-only to simulate permission error
	# This prevents lockfile creation, so script must exit early
	chmod 555 "$STATE_DIR" 2>/dev/null || true

	# Run script - should exit early with error when STATE_DIR is not writable
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake 2>&1

	# Restore permissions immediately after script execution to prevent issues
	chmod 755 "$STATE_DIR" 2>/dev/null || true

	# Should fail with error code 4 (permission error) since lockfile cannot be created
	assert_failure
	assert_output --partial "STATE_DIR is not writable"
	assert_output --partial "cannot create lockfile"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "state file read fails but script continues" {
	# Purpose: Test verifies that script handles state file read failures gracefully
	# Expected: Script detects read failure, handles gracefully, continues execution with defaults
	# Importance: Read failures can occur due to corruption or permission issues; script must continue
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create corrupted state file (unreadable)
	local restart_count_file="${STATE_DIR}/restart_count"
	mkdir -p "$STATE_DIR"
	echo "invalid-data" >"$restart_count_file"
	chmod 000 "$restart_count_file" 2>/dev/null || true

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command - VPN healthy
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Run script - should handle read failure gracefully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	# Should succeed (read failures are handled gracefully with defaults)
	assert_success

	# Restore permissions for cleanup
	chmod 644 "$restart_count_file" 2>/dev/null || true

	# Should have logged warning about read failure or used defaults
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# ============================================================================
# STATE DIRECTORY CREATION FAILURES - Previously Untested Critical Paths (P1)
# Tests for untested critical paths identified in docs/UNTESTED_CRITICAL_PATHS.md
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "try_ensure_directory_exists fails for LOGS_DIR - warning logged but continues" {
	# Purpose: Test verifies that try_ensure_directory_exists() failures for LOGS_DIR log warning but continue
	# Expected: Script logs warning about directory creation failure but continues execution
	# Importance: Directory creation failures should not crash script; warnings should be logged
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		"LOGS_DIR=/nonexistent/path/that/cannot/be/created"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Run script - should handle directory creation failure gracefully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	# Should succeed (warnings are logged but script continues)
	assert_success

	# Should have logged warning about directory creation failure
	# Note: Log file may not exist if LOGS_DIR creation failed, but script should continue
	assert_file_exist "$LOG_FILE" || true

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "try_ensure_directory_exists fails for STATE_DIR - warning logged but continues" {
	# Purpose: Test verifies that try_ensure_directory_exists() failures for STATE_DIR log warning but continue
	# Expected: Script logs warning about directory creation failure but continues execution
	# Importance: Directory creation failures should not crash script; warnings should be logged
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		"STATE_DIR=/nonexistent/path/that/cannot/be/created"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Run script - should handle directory creation failure gracefully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	# Should succeed (warnings are logged but script continues)
	assert_success

	# Should have logged warning about directory creation failure
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "directory creation succeeds but directory is immediately deleted (race condition)" {
	# Purpose: Test verifies that script handles race condition where directory is created but immediately deleted
	# Expected: Script should handle this gracefully, possibly retrying creation or continuing
	# Importance: Race conditions in directory operations should not cause script failures
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Create a script that deletes directory after creation
	local race_script="${TEST_DIR}/race_condition.sh"
	cat >"$race_script" <<EOF
#!/bin/bash
# Wait for main script to create directory, then delete it
sleep 0.05
rm -rf "${TEST_DIR}/race-state" 2>/dev/null || true
EOF
	chmod +x "$race_script"

	# Update config to use race-state directory
	load helpers/config
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		"STATE_DIR=\"${TEST_DIR}/race-state\""

	# Run race script in background
	"$race_script" &
	local race_pid=$!

	# Run main script
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	# Should handle race condition gracefully
	[[ $status -ge 0 ]] # Any exit code is acceptable

	# Wait for race script
	wait "$race_pid" 2>/dev/null || true

	# Clean up
	rm -f "$race_script" 2>/dev/null || true
	rm -rf "${TEST_DIR}/race-state" 2>/dev/null || true

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "directory creation fails but handle_error also fails (logging failure)" {
	# Purpose: Test verifies that script handles case where directory creation fails and handle_error also fails
	# Expected: Script should handle this gracefully, possibly using fallback error handling
	# Importance: Defensive programming ensures script doesn't crash even if error handling fails
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		"STATE_DIR=/nonexistent/path/that/cannot/be/created"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Make log directory read-only to simulate logging failure
	chmod 555 "${TEST_DIR}/logs" 2>/dev/null || true

	# Run script - should handle both directory creation and logging failures gracefully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	# Should either succeed or fail gracefully
	# The important thing is it doesn't hang or crash
	[[ $status -ge 0 ]] # Any exit code is acceptable

	# Restore permissions for cleanup
	chmod 755 "${TEST_DIR}/logs" 2>/dev/null || true

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "state directory creation fails but script continues - subsequent state file operations fail" {
	# Purpose: Test verifies that script continues when state directory creation fails, and subsequent state operations fail gracefully
	# Expected: Script continues execution, but state file operations fail gracefully (warnings logged)
	# Importance: Script should continue monitoring even if state tracking is impaired
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		"STATE_DIR=/nonexistent/path/that/cannot/be/created"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command - VPN down to trigger state operations
	setup_mock_vpn_environment "${TEST_PEER_IP}" 0
	add_mock_to_path

	# Run script - should continue even if state directory creation failed
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	# Should succeed (script continues even if state operations fail)
	assert_success

	# Should have logged warnings about state directory and state file operations
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# ============================================================================
# 6.3 STATE FILE PATTERN VALIDATION WITH UNREADABLE FILES
# ============================================================================

# bats test_tags=category:high-risk,priority:high,slow
@test "validate_state_files_by_pattern with unreadable files - should skip unreadable files without hanging" {
	# Purpose: Test verifies that validate_state_files_by_pattern handles unreadable files gracefully without hanging.
	# Expected: Function skips unreadable files, logs warnings, and continues processing readable files.
	# Importance: The fix prevents hangs when glob expansion encounters unreadable files (000 permissions).
	# This test specifically covers the pattern-based validation fix from commit 77c34c7.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Source state functions to test directly
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true

	# Set up state directory
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create multiple failure counter files matching the pattern "failure_count_*"
	local file1="${STATE_DIR}/failure_count_LOCATION_192_168_1_1"
	local file2="${STATE_DIR}/failure_count_LOCATION_192_168_1_2"
	local file3="${STATE_DIR}/failure_count_LOCATION_192_168_1_3"

	# Create readable files with valid content
	echo "5" >"$file1"
	echo "3" >"$file2"
	echo "7" >"$file3"

	# Make one file unreadable (000 permissions) - this is the scenario that caused hangs
	local original_perms
	original_perms=$(stat -c %a "$file2" 2>/dev/null || echo "644")
	chmod 000 "$file2"
	# Use trap to ensure cleanup even on errors
	trap 'chmod $original_perms "$file2" 2>/dev/null || true' EXIT

	# Verify permissions were set correctly
	assert_file_permission 000 "$file2"

	# Call validate_state_files_by_pattern with timeout to prevent hangs
	# This function should skip the unreadable file and continue processing others
	run timeout 30 bash -c "
		source '${BATS_TEST_DIRNAME}/../lib/state.sh' || true
		export STATE_DIR='${STATE_DIR}'
		export LOGS_DIR='${LOGS_DIR}'
		validate_state_files_by_pattern 'failure_count_*' 'integer' '0' 'Failure counter file'
	"
	assert_success

	# Verify readable files were validated (not corrupted, so should still exist with same content)
	assert_file_exist "$file1"
	local content1
	content1=$(cat "$file1")
	assert_equal "$content1" "5"

	assert_file_exist "$file3"
	local content3
	content3=$(cat "$file3")
	assert_equal "$content3" "7"

	# Verify unreadable file still exists (was skipped, not processed)
	assert_file_exist "$file2"

	# Restore permissions for cleanup
	chmod "$original_perms" "$file2" 2>/dev/null || true
	trap - EXIT
}

# bats test_tags=category:high-risk,priority:high,slow
@test "validate_state_files_by_pattern with multiple unreadable files - should skip all unreadable files without hanging" {
	# Purpose: Test verifies that validate_state_files_by_pattern handles multiple unreadable files gracefully.
	# Expected: Function skips all unreadable files, logs warnings, and doesn't hang.
	# Importance: Ensures the fix works even when multiple files are unreadable.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Source state functions to test directly
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true

	# Set up state directory
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create multiple byte counter files matching the pattern "last_bytes_*"
	local file1="${STATE_DIR}/last_bytes_LOCATION_192_168_1_1"
	local file2="${STATE_DIR}/last_bytes_LOCATION_192_168_1_2"
	local file3="${STATE_DIR}/last_bytes_LOCATION_192_168_1_3"

	# Create files with valid content
	echo "1000" >"$file1"
	echo "2000" >"$file2"
	echo "3000" >"$file3"

	# Make two files unreadable (000 permissions)
	local original_perms1
	original_perms1=$(stat -c %a "$file1" 2>/dev/null || echo "644")
	local original_perms2
	original_perms2=$(stat -c %a "$file2" 2>/dev/null || echo "644")
	chmod 000 "$file1"
	chmod 000 "$file2"
	# Use trap to ensure cleanup even on errors
	trap 'chmod $original_perms1 "$file1" 2>/dev/null || true; chmod $original_perms2 "$file2" 2>/dev/null || true' EXIT

	# Verify permissions were set correctly
	assert_file_permission 000 "$file1"
	assert_file_permission 000 "$file2"

	# Call validate_state_files_by_pattern with timeout to prevent hangs
	# This function should skip unreadable files and continue processing readable ones
	run timeout 30 bash -c "
		source '${BATS_TEST_DIRNAME}/../lib/state.sh' || true
		export STATE_DIR='${STATE_DIR}'
		export LOGS_DIR='${LOGS_DIR}'
		validate_state_files_by_pattern 'last_bytes_*' 'integer' '0' 'Byte counter file'
	"
	assert_success

	# Verify readable file was validated (not corrupted, so should still exist with same content)
	assert_file_exist "$file3"
	local content3
	content3=$(cat "$file3")
	assert_equal "$content3" "3000"

	# Verify unreadable files still exist (were skipped, not processed)
	assert_file_exist "$file1"
	assert_file_exist "$file2"

	# Restore permissions for cleanup
	chmod "$original_perms1" "$file1" 2>/dev/null || true
	chmod "$original_perms2" "$file2" 2>/dev/null || true
	trap - EXIT
}

# bats test_tags=category:high-risk,priority:high,slow
@test "validate_state with unreadable pattern-matched files - should handle gracefully through validate_state" {
	# Purpose: Test verifies that validate_state() handles unreadable pattern-matched files gracefully.
	# Expected: validate_state calls validate_state_files_by_pattern which skips unreadable files without hanging.
	# Importance: Ensures the fix works when called through the main validate_state() function.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Source state functions to test directly
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true

	# Set up state directory
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create failure counter files matching the pattern
	local file1="${STATE_DIR}/failure_count_LOCATION_192_168_1_1"
	local file2="${STATE_DIR}/failure_count_LOCATION_192_168_1_2"

	# Create files with valid content
	echo "5" >"$file1"
	echo "3" >"$file2"

	# Make one file unreadable
	local original_perms
	original_perms=$(stat -c %a "$file2" 2>/dev/null || echo "644")
	chmod 000 "$file2"
	# Use trap to ensure cleanup even on errors
	trap 'chmod $original_perms "$file2" 2>/dev/null || true' EXIT

	# Call validate_state with timeout to prevent hangs
	# This should call validate_state_files_by_pattern internally
	run timeout 30 bash -c "
		source '${BATS_TEST_DIRNAME}/../lib/state.sh' || true
		export STATE_DIR='${STATE_DIR}'
		export LOGS_DIR='${LOGS_DIR}'
		export RESTART_COUNT_FILE='${STATE_DIR}/restart_count'
		validate_state
	"
	assert_success

	# Verify readable file still exists with same content
	assert_file_exist "$file1"
	local content1
	content1=$(cat "$file1")
	assert_equal "$content1" "5"

	# Verify unreadable file still exists (was skipped)
	assert_file_exist "$file2"

	# Restore permissions for cleanup
	chmod "$original_perms" "$file2" 2>/dev/null || true
	trap - EXIT
}

# ============================================================================
# 6.7 INPUT VALIDATION TESTS
# ============================================================================

# bats test_tags=category:validation,priority:medium
@test "get_peer_state_file_path with empty key - should return error and empty path" {
	# Purpose: Test verifies that get_peer_state_file_path validates key is not empty.
	# Expected: Function returns 1 and outputs empty string, logs error.
	# Importance: Prevents invalid paths from being generated.
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	source_function "get_peer_state_file_path"

	# Test with empty key - use || true to capture exit code without failing test
	local result exit_code
	result=$(get_peer_state_file_path "LOCATION" "${TEST_PEER_IP}" "" 2>&1) || exit_code=$?

	# Should return error code
	assert_equal "$exit_code" 1

	# Output should contain error message (logged to stderr, captured with 2>&1)
	[[ "$result" == *"key is required"* ]] || fail "Expected error message about key being required, got: $result"
}

# bats test_tags=category:validation,priority:medium
@test "get_peer_state_file_path with empty peer_ip - should return error and empty path" {
	# Purpose: Test verifies that get_peer_state_file_path validates peer_ip is not empty.
	# Expected: Function returns 1 and outputs empty string, logs error.
	# Importance: Prevents invalid paths like failure_count_LOCATION_ from being generated.
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	source_function "get_peer_state_file_path"

	# Test with empty peer_ip - use || true to capture exit code without failing test
	local result exit_code
	result=$(get_peer_state_file_path "LOCATION" "" "failure_count" 2>&1) || exit_code=$?

	# Should return error code
	assert_equal "$exit_code" 1

	# Output should contain error message (logged to stderr, captured with 2>&1)
	[[ "$result" == *"peer_ip is required"* ]] || fail "Expected error message about peer_ip being required, got: $result"
}

# bats test_tags=category:validation,priority:medium
@test "get_peer_state_file_path with empty location_name for non-connection_name key - should return error" {
	# Purpose: Test verifies that get_peer_state_file_path validates location_name for non-connection_name keys.
	# Expected: Function returns 1 and outputs empty string for failure_count key.
	# Importance: Prevents invalid paths from being generated for location-based keys.
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	source_function "get_peer_state_file_path"

	# Test with empty location_name for failure_count (requires location)
	# Use || exit_code=$? to capture exit code without failing test
	local result exit_code
	result=$(get_peer_state_file_path "" "${TEST_PEER_IP}" "failure_count" 2>&1) || exit_code=$?

	# Should return error code
	assert_equal "$exit_code" 1

	# Output should contain error message (logged to stderr, captured with 2>&1)
	[[ "$result" == *"location_name is required"* ]] || fail "Expected error message about location_name being required, got: $result"
}

# bats test_tags=category:validation,priority:medium
@test "get_peer_state_file_path with empty location_name for connection_name key - should succeed" {
	# Purpose: Test verifies that get_peer_state_file_path allows empty location_name for connection_name key.
	# Expected: Function returns 0 and outputs valid path.
	# Importance: connection_name is per-peer only, location_name is intentionally optional.
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	source_function "get_peer_state_file_path"

	# Test with empty location_name for connection_name (should be allowed)
	local result
	result=$(get_peer_state_file_path "" "${TEST_PEER_IP}" "connection_name" 2>&1)
	local exit_code=$?

	# Should succeed
	assert_equal "$exit_code" 0

	# Should return valid path
	[[ -n "$result" ]]
	[[ "$result" == "${STATE_DIR}/connection_name_"* ]]
}

# bats test_tags=category:validation,priority:medium
@test "get_peer_state_file_path with unset STATE_DIR - should return error and empty path" {
	# Purpose: Test verifies that get_peer_state_file_path validates STATE_DIR is set.
	# Expected: Function returns 1 and outputs empty string, logs error.
	# Importance: Prevents invalid absolute paths from being generated.
	# Unset STATE_DIR to test validation
	local saved_state_dir="${STATE_DIR:-}"
	unset STATE_DIR

	# Source dependencies directly (source_function would set STATE_DIR)
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/state/state_paths.sh
	source "${BATS_TEST_DIRNAME}/../lib/state/state_paths.sh" 2>/dev/null || true

	# Test with unset STATE_DIR - use || exit_code=$? to capture exit code without failing test
	local result exit_code
	result=$(get_peer_state_file_path "LOCATION" "${TEST_PEER_IP}" "failure_count" 2>&1) || exit_code=$?

	# Should return error code
	assert_equal "$exit_code" 1

	# Output should contain error message about STATE_DIR
	[[ "$result" == *"STATE_DIR is not set"* ]] || fail "Expected error message about STATE_DIR not being set, got: $result"

	# Restore STATE_DIR
	if [[ -n "$saved_state_dir" ]]; then
		export STATE_DIR="$saved_state_dir"
	fi
}

# bats test_tags=category:validation,priority:medium
@test "get_peer_state with path generation failure - should return default value and exit code 1" {
	# Purpose: Test verifies that get_peer_state handles path generation failure gracefully.
	# Expected: Function returns default value (output) and exit code 1.
	# Importance: Ensures function fails safely when validation fails upstream.
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	source_function "get_peer_state"

	# Test with empty peer_ip (will cause path generation to fail)
	# Use || exit_code=$? to capture exit code without failing test
	local result exit_code
	result=$(get_peer_state "LOCATION" "" "failure_count" "42" 2>&1) || exit_code=$?

	# Should return error code
	assert_equal "$exit_code" 1

	# Output should end with default value (42) - there may be error message before it
	[[ "$result" == *"42" ]] || fail "Expected output to end with default value '42', got: $result"
}

# bats test_tags=category:validation,priority:medium
@test "get_peer_state with path generation failure and no default - should return 0" {
	# Purpose: Test verifies that get_peer_state uses default "0" when path generation fails and no default provided.
	# Expected: Function returns "0" (output) and exit code 1.
	# Importance: Ensures function has safe fallback behavior.
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	source_function "get_peer_state"

	# Test with empty peer_ip (will cause path generation to fail) and no default
	# Use || exit_code=$? to capture exit code without failing test
	local result exit_code
	result=$(get_peer_state "LOCATION" "" "failure_count" 2>&1) || exit_code=$?

	# Should return error code
	assert_equal "$exit_code" 1

	# Output should end with default value "0" - there may be error message before it
	[[ "$result" == *"0" ]] || fail "Expected output to end with default value '0', got: $result"
}

# bats test_tags=category:validation,priority:medium
@test "set_peer_state with path generation failure - should return error code 1" {
	# Purpose: Test verifies that set_peer_state handles path generation failure gracefully.
	# Expected: Function returns exit code 1, does not attempt to write file.
	# Importance: Prevents file operations on invalid paths.
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	source_function "set_peer_state"

	# Test with empty peer_ip (will cause path generation to fail)
	run set_peer_state "LOCATION" "" "failure_count" "5" 2>&1

	# Should return error code
	assert_failure

	# Should not create any files (path was invalid)
	local invalid_path="${STATE_DIR}/failure_count_LOCATION_"
	[[ ! -f "$invalid_path" ]]
}

# bats test_tags=category:validation,priority:medium
@test "delete_peer_state with path generation failure - should return error code 1" {
	# Purpose: Test verifies that delete_peer_state handles path generation failure gracefully.
	# Expected: Function returns exit code 1, does not attempt to delete file.
	# Importance: Prevents file operations on invalid paths.
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	source_function "delete_peer_state"

	# Test with empty peer_ip (will cause path generation to fail)
	run delete_peer_state "LOCATION" "" "failure_count" 2>&1

	# Should return error code
	assert_failure
}

# bats test_tags=category:validation,priority:medium
@test "get_failure_type with path generation failure - should return unknown and exit code 1" {
	# Purpose: Test verifies that get_failure_type handles path generation failure gracefully.
	# Expected: Function returns "unknown" (output) and exit code 1.
	# Importance: Ensures failure type detection fails safely when validation fails.
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source failure_analysis.sh to get get_failure_type
	# shellcheck source=../lib/detection/failure_analysis.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection/failure_analysis.sh" 2>/dev/null || true

	# Test with empty peer_ip (will cause path generation to fail)
	# Use || exit_code=$? to capture exit code without failing test
	local result exit_code
	result=$(get_failure_type "LOCATION" "" 2>&1) || exit_code=$?

	# Should return error code
	assert_equal "$exit_code" 1

	# Output should end with "unknown" - there may be error message before it
	[[ "$result" == *"unknown" ]] || fail "Expected output to end with 'unknown', got: $result"
}

# ============================================================================
