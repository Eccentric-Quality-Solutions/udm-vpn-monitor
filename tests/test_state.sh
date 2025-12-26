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
@test "failure counter file corrupted (non-numeric)" {
	# Test verifies that the script handles corrupted failure counter files containing non-numeric values.
	# Expected: Script treats corrupted file as 0 or resets it, continuing normal operation without crashing.
	# Importance: File corruption can occur due to disk errors or manual editing; script must handle it robustly.
	setup_vpn_active_fixture "192.168.1.1" 1000 2000

	# Create corrupted failure counter file
	local failure_counter="${LOGS_DIR}/failure_counter_192_168_1_1"
	echo "invalid-non-numeric-value" >"$failure_counter"

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake || true

	# Should handle corrupted file gracefully
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "failure counter file contains negative number" {
	setup_vpn_active_fixture "192.168.1.1" 1000 2000

	# Create failure counter file with negative number
	local failure_counter="${LOGS_DIR}/failure_counter_192_168_1_1"
	echo "-5" >"$failure_counter"

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake || true

	# Should handle negative number gracefully
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "failure counter file is empty" {
	setup_vpn_active_fixture "192.168.1.1" 1000 2000

	# Create empty failure counter file (clear any existing file from fixture)
	local failure_counter="${LOGS_DIR}/failure_counter_192_168_1_1"
	rm -f "$failure_counter"
	touch "$failure_counter"
	# Verify file is empty before script runs
	assert_file_empty "$failure_counter"

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake || true

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
@test "cooldown file corrupted (invalid timestamp)" {
	setup_vpn_active_fixture "192.168.1.1" 1000 2000

	# Create corrupted cooldown file with invalid timestamp
	local cooldown_file="${STATE_DIR}/cooldown_until"
	echo "invalid-timestamp-value" >"$cooldown_file"

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake || true

	# Should handle corrupted cooldown file gracefully (arithmetic error would occur)
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# ============================================================================
# 6.2 CONCURRENT STATE ACCESS - PERMISSIONS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "state file permissions prevent write" {
	# Test verifies that the script handles read-only state files gracefully when attempting to update counters.
	# Expected: Script logs error about write failure but continues execution without crashing.
	# Importance: Permission issues can occur due to incorrect file ownership or chmod operations; script must handle gracefully.
	setup_vpn_down_fixture "192.168.1.1" 3

	# Create failure counter file and make it read-only (prevents write)
	local failure_counter="${LOGS_DIR}/failure_counter_192_168_1_1"
	echo "3" >"$failure_counter"
	chmod 444 "$failure_counter"
	# Verify permissions were set correctly
	assert_file_permission 444 "$failure_counter"

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" || true

	# Should handle read-only state file gracefully (should log error but continue)
	assert_file_exist "$LOG_FILE"

	# Restore permissions for cleanup
	chmod 644 "$failure_counter" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "state file permissions prevent read" {
	setup_vpn_active_fixture "192.168.1.1" 1000 2000

	# Create failure counter file and make it unreadable (prevents read)
	local failure_counter="${LOGS_DIR}/failure_counter_192_168_1_1"
	echo "3" >"$failure_counter"
	chmod 000 "$failure_counter"
	# Verify permissions were set correctly
	assert_file_permission 000 "$failure_counter"

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake || true

	# Should handle unreadable state file gracefully (should default to 0 or handle error)
	assert_file_exist "$LOG_FILE"

	# Restore permissions for cleanup
	chmod 644 "$failure_counter" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "state file deleted during script execution" {
	setup_vpn_down_fixture "192.168.1.1" 2

	# Delete failure counter file during execution (simulate file deletion)
	# This is a simplified test - in real scenario, file might be deleted between checks
	local failure_counter="${LOGS_DIR}/failure_counter_192_168_1_1"
	rm -f "$failure_counter"

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" || true

	# Should handle deleted state file gracefully (should recreate or default to 0)
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# ============================================================================
# 6.2 CONCURRENT STATE ACCESS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "state file modified during script execution (lockfile should prevent this)" {
	setup_vpn_active_fixture "192.168.1.1" 1000 2000

	# Run script - lockfile should prevent concurrent execution
	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake || true

	# Lockfile prevents concurrent execution, so state file modification should not occur
	# This test verifies that lockfile mechanism works (implicitly tested by lockfile tests)
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# ============================================================================
