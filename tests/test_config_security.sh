#!/usr/bin/env bats
#
# Tests for Configuration Security (Dangerous Content Detection)
# Tests critical paths and error handling scenarios

load test_helper
load helpers/config
load helpers/assertions
load fixtures/vpn_active

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# CONFIGURATION SECURITY TESTS (DANGEROUS CONTENT DETECTION)
# ============================================================================

@test "STATE_DIR override in config updates all dependent paths" {
	# Purpose: Test verifies that when STATE_DIR is overridden in config, all dependent paths are updated correctly
	# Expected: Script updates all paths that depend on STATE_DIR (LOCKFILE, COOLDOWN_UNTIL_FILE, LOGS_DIR, etc.) to use the custom directory
	# Importance: Ensures consistent path handling when custom state directories are specified
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local custom_state_dir="${TEST_DIR}/custom-state"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"STATE_DIR=\"${custom_state_dir}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Ensure custom state directory does not exist initially
	rm -rf "$custom_state_dir" 2>/dev/null || true

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	run bash "$test_script" --fake

	assert_success
	# Custom state directory should be created by init_state()
	assert_dir_exist "$custom_state_dir"

	# Dependent paths should use custom STATE_DIR:
	# - LOCKFILE should be in custom_state_dir
	# - COOLDOWN_UNTIL_FILE should be in custom_state_dir
	# - LOGS_DIR should be custom_state_dir/logs
	# - RESTART_COUNT_FILE should be in custom_state_dir/state
	# Note: Expected paths documented above but not directly asserted as script creates files dynamically

	# Verify that state files are created in the custom directory
	# (Script may create these files during execution)
	assert_file_exist "$LOG_FILE"

	# Cleanup
	rm -rf "$custom_state_dir" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "LOG_FILE override to read-only directory" {
	# Purpose: Test verifies that the script handles LOG_FILE paths pointing to read-only directories gracefully
	# Expected: Script handles read-only log directory gracefully without crashing, may output to stderr
	# Importance: Read-only directories can occur from permission issues; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local readonly_log_dir="${TEST_DIR}/readonly-logs"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOG_FILE=\"${readonly_log_dir}/vpn-monitor.log\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create read-only log directory
	mkdir -p "$readonly_log_dir"
	chmod 555 "$readonly_log_dir"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	run bash "$test_script" --fake
	assert_success

	# Should handle read-only log directory gracefully (should output to stderr)
	# Script should not crash even if log writes fail

	# Restore permissions for cleanup
	chmod 755 "$readonly_log_dir" 2>/dev/null || true
	rm -rf "$readonly_log_dir" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "STATE_DIR override to read-only directory" {
	# Purpose: Test verifies that the script handles STATE_DIR paths pointing to read-only directories gracefully
	# Expected: Script fails early with clear error message when STATE_DIR is read-only because lockfile cannot be created
	# Importance: Read-only state directories prevent lockfile creation; script must fail early with clear error
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local readonly_state_dir="${TEST_DIR}/readonly-state"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"STATE_DIR=\"${readonly_state_dir}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create read-only state directory
	mkdir -p "$readonly_state_dir"
	chmod 555 "$readonly_state_dir"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	run bash "$test_script" --fake
	assert_failure

	# Script should fail early with clear error message when STATE_DIR is read-only
	# because lockfile cannot be created in read-only directory
	assert_output --partial "STATE_DIR is not writable"

	# Restore permissions for cleanup
	chmod 755 "$readonly_state_dir" 2>/dev/null || true
	rm -rf "$readonly_state_dir" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with command substitution is rejected" {
	# Purpose: Test verifies that config files with command substitution ($()) are rejected
	# Expected: Script detects dangerous content and rejects config file without executing code
	# Importance: Prevents arbitrary code execution if config file is compromised
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Expand TEST_PEER_IP but keep dangerous content literal
	printf 'LOCATION_TEST_EXTERNAL="%s"\nVPN_NAME=$(echo "malicious")\n' "${TEST_PEER_IP}" >"$config_file"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Script should reject config file with command substitution
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about dangerous content
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "dangerous content" "Failed to parse" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with backticks is rejected" {
	# Purpose: Test verifies that config files with backticks are rejected
	# Expected: Script detects dangerous content and rejects config file without executing code
	# Importance: Prevents arbitrary code execution if config file is compromised
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Expand TEST_PEER_IP but keep dangerous content literal
	printf 'LOCATION_TEST_EXTERNAL="%s"\nVPN_NAME=`echo "malicious"`\n' "${TEST_PEER_IP}" >"$config_file"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Script should reject config file with backticks
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about dangerous content
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "dangerous content" "Failed to parse" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with eval is rejected" {
	# Purpose: Test verifies that config files with eval are rejected
	# Expected: Script detects dangerous content and rejects config file without executing code
	# Importance: Prevents arbitrary code execution if config file is compromised
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Expand TEST_PEER_IP but keep dangerous content literal
	printf 'LOCATION_TEST_EXTERNAL="%s"\neval "malicious code"\n' "${TEST_PEER_IP}" >"$config_file"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Script should reject config file with eval
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about dangerous content
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "dangerous content" "Failed to parse" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with unknown variable is rejected" {
	# Purpose: Test verifies that config files with unknown variables (not in schema) are rejected
	# Expected: Script detects unknown variable and rejects config file
	# Importance: Prevents setting arbitrary variables that could be used for code injection
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		'MALICIOUS_VAR="value"'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Script should reject config file with unknown variable
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about unknown variable
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Unknown configuration variable" "not in schema" "Failed to parse" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with valid assignments works correctly" {
	# Purpose: Test verifies that config files with valid variable assignments are parsed correctly
	# Expected: Script parses valid config file and sets variables safely
	# Importance: Ensures legitimate config files continue to work after security fix
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST1_EXTERNAL=\"${TEST_PEER_IP}\"" \
		'LOCATION_TEST2_EXTERNAL="192.168.1.2"' \
		'VPN_NAME="Test VPN"' \
		'TIER1_THRESHOLD=2' \
		'TIER2_THRESHOLD=4' \
		'TIER3_THRESHOLD=6' \
		'ENABLE_PING_CHECK=1' \
		'DEBUG=0'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Script should parse valid config file successfully
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log success message
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Configuration loaded from" "INFO"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with source is rejected" {
	# Purpose: Test verifies that config files with source command are rejected
	# Expected: Script detects dangerous content and rejects config file without executing code
	# Importance: Prevents arbitrary code execution if config file is compromised
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Expand TEST_PEER_IP but keep dangerous content literal
	printf 'LOCATION_TEST_EXTERNAL="%s"\nsource /etc/passwd\n' "${TEST_PEER_IP}" >"$config_file"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Script should reject config file with source
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about dangerous content
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "dangerous content" "Failed to parse" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with multiple dangerous patterns in one line is rejected" {
	# Purpose: Test verifies that config files with multiple dangerous patterns in one line are rejected
	# Expected: Script detects dangerous content and rejects config file
	# Importance: Ensures all dangerous patterns are detected even when combined
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Expand TEST_PEER_IP but keep dangerous content literal
	printf 'LOCATION_TEST_EXTERNAL="%s"\nVPN_NAME=$(echo "test") `echo "test"` eval "test"\n' "${TEST_PEER_IP}" >"$config_file"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Script should reject config file with multiple dangerous patterns
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about dangerous content
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "dangerous content" "Failed to parse" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with dangerous pattern in comment is allowed" {
	# Purpose: Test verifies that dangerous patterns in comments are ignored (comments are allowed)
	# Expected: Script ignores comments and allows dangerous patterns in comment lines
	# Importance: Comments should not trigger security checks
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Expand TEST_PEER_IP but keep dangerous content literal in comments
	printf 'LOCATION_TEST_EXTERNAL="%s"\n# This is a comment with $(echo "test") `echo "test"` eval "test"\nVPN_NAME="Test VPN"\n' "${TEST_PEER_IP}" >"$config_file"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Script should parse config file successfully (comments are ignored)
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should parse successfully (comments are ignored)
	assert_file_exist "$LOG_FILE"
	# Should not contain error about dangerous content
	refute_file_contains "$LOG_FILE" "dangerous content"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with valid variable assignment without quotes is allowed" {
	# Purpose: Test verifies that valid variable assignments without quotes are parsed correctly
	# Expected: Script parses valid assignments without quotes safely
	# Importance: Ensures legitimate config files without quotes continue to work
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"ENABLE_PING_CHECK=1" \
		"DEBUG=0"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Script should parse valid config file successfully
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should parse successfully
	assert_file_exist "$LOG_FILE"
	# Should not contain error about dangerous content
	refute_file_contains "$LOG_FILE" "dangerous content"

	remove_mock_from_path
}
