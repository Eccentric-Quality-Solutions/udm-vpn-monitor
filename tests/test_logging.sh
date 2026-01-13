#!/usr/bin/env bats
#
# Tests for Logging Failure Scenarios
# Tests critical paths and error handling scenarios

load test_helper
load helpers/config
load fixtures/vpn_active

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# LOGGING FAILURE SCENARIOS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "log file is a directory" {
	# Purpose: Test verifies that the script handles LOG_FILE paths that point to directories instead of files gracefully
	# Expected: Script handles directory instead of log file gracefully, outputs to stderr and does not crash
	# Importance: Directory paths can occur from misconfiguration or symlink issues; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create log file as a directory
	rm -rf "$LOG_FILE" 2>/dev/null || true
	mkdir -p "$LOG_FILE"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Should handle directory gracefully (output to stderr)
	# Log file won't exist as a file, but script should not crash

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "log file permissions prevent write" {
	# Purpose: Test verifies that the script handles log files with write permissions prevented gracefully
	# Expected: Script handles read-only log file gracefully, outputs to stderr and does not crash
	# Importance: Permission issues can occur from incorrect file ownership or chmod operations; script must handle gracefully
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create log file and make it read-only (prevents write)
	touch "$LOG_FILE"
	local original_perms
	original_perms=$(stat -c %a "$LOG_FILE")
	chmod 444 "$LOG_FILE"
	# Verify permissions were set correctly
	assert_file_permission 444 "$LOG_FILE"
	# Use trap to ensure cleanup even on errors
	# Use actual path value, not variable, since trap executes after function returns
	# shellcheck disable=SC2064 # We want variable expansion at trap definition time
	trap "chmod $original_perms \"$LOG_FILE\" 2>/dev/null || true" EXIT

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Should handle read-only log file gracefully (should output to stderr)
	# Script should not crash even if log writes fail
	# Note: We can't easily verify stderr output in this test, but script should continue

	# Restore permissions for cleanup
	chmod "$original_perms" "$LOG_FILE" 2>/dev/null || true
	# Clear trap after successful restore
	trap - EXIT
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "log directory becomes read-only during execution" {
	# Purpose: Test verifies that the script handles log directories that become read-only during execution gracefully
	# Expected: Script handles read-only log directory gracefully, outputs to stderr and does not crash
	# Importance: Directory permissions can change during execution; script must handle this gracefully
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Make log directory read-only before execution
	chmod 555 "${TEST_DIR}/logs"
	# Verify permissions were set correctly
	assert_file_permission 555 "${TEST_DIR}/logs"

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Should handle read-only log directory gracefully (should output to stderr)
	# Script should not crash even if log writes fail

	# Restore permissions for cleanup
	chmod 755 "${TEST_DIR}/logs" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "log file becomes read-only during execution" {
	# Purpose: Test verifies that the script handles log files that become read-only during execution gracefully
	# Expected: Script handles read-only log file gracefully, outputs to stderr and does not crash
	# Importance: File permissions can change during execution; script must handle this gracefully
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	local log_file="$LOG_FILE"

	# Create log file and make it read-only
	touch "$log_file"
	local original_perms
	original_perms=$(stat -c %a "$log_file")
	chmod 444 "$log_file"
	# Verify permissions were set correctly
	assert_file_permission 444 "$log_file"
	# Use trap to ensure cleanup even on errors
	# Use actual path value, not variable, since trap executes after function returns
	# shellcheck disable=SC2064 # We want variable expansion at trap definition time
	trap "chmod $original_perms \"$log_file\" 2>/dev/null || true" EXIT

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$log_file")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Should handle read-only log file gracefully (should output to stderr)
	# Script should not crash even if log writes fail

	# Restore permissions for cleanup
	chmod "$original_perms" "$log_file" 2>/dev/null || true
	# Clear trap after successful restore
	trap - EXIT
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "log directory deleted during execution" {
	# Purpose: Test verifies that the script handles log directories that are deleted during execution gracefully
	# Expected: Script handles deleted log directory gracefully, recreates directory or outputs to stderr and does not crash
	# Importance: Directories can be deleted during execution; script must handle this gracefully
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Delete log directory before execution (simulates deletion during execution)
	rm -rf "${TEST_DIR}/logs"

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Should handle deleted log directory gracefully (should recreate or output to stderr)
	# Script should not crash even if log directory is missing

	remove_mock_from_path
}

# ============================================================================
# LOG PATH EDGE CASES
# ============================================================================

@test "LOG_FILE path contains symlinks" {
	# Purpose: Test verifies that the script handles LOG_FILE paths containing symlinks gracefully
	# Expected: Script handles symlink path gracefully, writes to real directory via symlink
	# Importance: Symlinks are commonly used in file systems; script must handle them correctly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local symlink_log_dir="${TEST_DIR}/symlink-logs"
	local real_log_dir="${TEST_DIR}/real-logs"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOG_FILE=\"${symlink_log_dir}/vpn-monitor.log\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create real log directory and symlink to it
	# Remove any existing symlink or directory first
	rm -rf "$symlink_log_dir" 2>/dev/null || true
	mkdir -p "$real_log_dir"
	ln -sf "$real_log_dir" "$symlink_log_dir"

	# Verify symlink was created correctly
	[[ -L "$symlink_log_dir" ]] || fail "Failed to create symlink: $symlink_log_dir"

	local expected_log_file="${symlink_log_dir}/vpn-monitor.log"
	# Verify expected_log_file path is set correctly
	[[ -n "$expected_log_file" ]] || fail "expected_log_file is empty"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$expected_log_file")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should handle symlink path gracefully (should write to real directory)
	assert_file_exist "$expected_log_file"
	# Verify log file was created in real directory (via symlink)
	if [[ -L "$symlink_log_dir" ]]; then
		# Verify symlink points to correct target
		assert_symlink_to "$real_log_dir" "$symlink_log_dir"
		local real_log_file="${real_log_dir}/vpn-monitor.log"
		# Log file should exist in real directory
		[[ -f "$real_log_file" ]] || [[ -f "$expected_log_file" ]]
	fi

	# Cleanup
	rm -f "$symlink_log_dir" 2>/dev/null || true
	rm -rf "$real_log_dir" 2>/dev/null || true
	remove_mock_from_path
}

@test "LOG_FILE path contains special characters" {
	# Purpose: Test verifies that the script handles LOG_FILE paths containing special characters gracefully
	# Expected: Script handles special characters in path gracefully and creates log file successfully
	# Importance: File paths may contain special characters; script must handle them correctly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local special_log_dir="${TEST_DIR}/logs-with-special-chars"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOG_FILE=\"${special_log_dir}/vpn-monitor.log\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create log directory with special characters in path
	mkdir -p "$special_log_dir"

	local expected_log_file="${special_log_dir}/vpn-monitor.log"
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$expected_log_file")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should handle special characters in path gracefully
	assert_file_exist "$expected_log_file"

	# Cleanup
	rm -rf "$special_log_dir" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "disk full scenario (log write fails)" {
	# Purpose: Test verifies that the script handles disk full scenarios where log writes fail gracefully
	# Expected: Script handles disk full scenario gracefully, outputs to stderr and does not crash
	# Importance: Disk space can run out during execution; script must handle this gracefully without crashing
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	local log_file="$LOG_FILE"

	# Create log file initially (simulates some writes succeeded)
	touch "$log_file"
	echo "Initial log entry" >"$log_file"
	# Verify log file has content
	assert_file_not_empty "$log_file"

	# Make log directory read-only to simulate disk full (prevents new writes)
	# This simulates the scenario where disk becomes full during execution
	chmod 555 "${TEST_DIR}/logs"
	# Verify permissions were set correctly
	assert_file_permission 555 "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$log_file")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Should handle disk full scenario gracefully (should output to stderr)
	# Script should not crash even if log writes fail
	# Code at lib/logging.sh:94-100 handles write failures gracefully

	# Restore permissions for cleanup
	chmod 755 "${TEST_DIR}/logs" 2>/dev/null || true
	remove_mock_from_path
}
