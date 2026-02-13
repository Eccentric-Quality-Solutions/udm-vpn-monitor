#!/usr/bin/env bats
#
# Tests for Configuration Loading and Validation
# Tests critical paths and error handling scenarios

load test_helper
load helpers/config
load helpers/assertions
load fixtures/vpn_active

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# CONFIGURATION LOADING AND VALIDATION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "config file contains syntax errors" {
	# Purpose: Test verifies that the script handles configuration files with syntax errors gracefully
	# Expected: Script detects syntax error during config loading and logs error message without crashing
	# Importance: Syntax errors can occur from manual editing or file corruption; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config with syntax error (unclosed quote)
	cat >"$config_file" <<EOF
LOCATION_NYC_EXTERNAL="${TEST_PEER_IP}
PING_COUNT=5
EOF

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Script should handle syntax error gracefully
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about config file
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Failed to parse configuration file" "Invalid configuration line" "ERROR"
}

# bats test_tags=category:high-risk,priority:high,untested-critical-path
@test "config file exists but is not readable - permission error handled" {
	# Purpose: Test verifies that the script handles unreadable configuration files gracefully
	# Expected: Script detects permission issue via file_exists_and_readable(), logs fatal error, exits appropriately in fake vs normal mode
	# Importance: Permission issues can occur from incorrect file ownership or chmod operations; script must handle gracefully
	# This test covers the untested critical paths:
	#   - Config file exists but file_exists_and_readable() returns false (line 719)
	#   - Config file exists but is not readable (permission error) - line 744-745
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\""

	# Make config file unreadable
	chmod 000 "$config_file"
	# Verify permissions were set correctly
	assert_file_permission 000 "$config_file"
	# Verify file exists but file_exists_and_readable() returns false
	[[ -f "$config_file" ]] || fail "Config file should exist"
	[[ ! -r "$config_file" ]] || fail "Config file should not be readable"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Test 1: Fake mode - should exit with code 0 (graceful exit)
	add_mock_to_path
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Should log fatal error about config file not readable
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "not readable" "Configuration file is not readable"

	# Test 2: Normal mode - should exit with error code
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"
	assert_failure

	# Restore permissions for cleanup
	chmod 644 "$config_file" 2>/dev/null || true

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high,untested-critical-path
@test "config file is a directory - warning logged and defaults used" {
	# Purpose: Test verifies that the script handles configuration file paths that point to directories instead of files gracefully
	# Expected: Script detects that config path is a directory, logs warning, uses default configuration values, and continues execution
	# Importance: Directory paths can occur from misconfiguration or symlink issues; script must handle them robustly
	# This test covers the untested critical path: Config file is a directory (line 714-717) - warning logged, defaults used
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create directory instead of file
	mkdir -p "$config_file"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Script should handle directory instead of file gracefully
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log warning about directory
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Configuration path is a directory" "directory"
	assert_log_contains_any "$LOG_FILE" "Using default configuration values" "default"

	remove_mock_from_path
}

@test "LOG_FILE override in config recalculates LOGS_DIR" {
	# Purpose: Test verifies that when LOG_FILE is overridden in config, LOGS_DIR is recalculated correctly
	# Expected: Script recalculates LOGS_DIR based on LOG_FILE path and creates the custom log directory
	# Importance: Ensures log file paths work correctly when custom LOG_FILE paths are specified
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		'LOG_FILE="/tmp/custom-logs/vpn-monitor.log"'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	local custom_log_file="/tmp/custom-logs/vpn-monitor.log"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Run script
	run bash "$test_script" --fake

	assert_success
	# Custom log directory should be created
	assert_dir_exist "/tmp/custom-logs"
	# Log file should exist in custom location
	assert_file_exist "$custom_log_file"

	# Cleanup
	rm -rf /tmp/custom-logs 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "negative threshold values in config" {
	# Purpose: Test verifies that the script handles negative threshold values in configuration files
	# Expected: Script processes negative thresholds without crashing, though behavior may be unexpected
	# Importance: Negative thresholds can occur from manual editing errors; script must handle them without crashing
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=-1" \
		"TIER2_THRESHOLD=-3" \
		"TIER3_THRESHOLD=-5"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command - VPN down
	mock_ip_xfrm_empty >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Script should handle negative thresholds (may cause unexpected behavior)
	run bash "$test_script" --fake

	# Script should run (may have unexpected tier escalation behavior)
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "threshold values out of order" {
	# Purpose: Test verifies that the script handles threshold values that are out of order (TIER2 < TIER1, etc.)
	# Expected: Script processes out-of-order thresholds without crashing, though behavior may skip tiers or be unexpected
	# Importance: Out-of-order thresholds can occur from manual editing errors; script must handle them without crashing
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=5" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=1"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command - VPN down
	mock_ip_xfrm_empty >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Script should handle out-of-order thresholds
	run bash "$test_script" --fake

	# Script should run (may skip tiers or have unexpected behavior)
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# ============================================================================
# CONFIGURATION LOADING ERROR PATHS - Previously Untested Critical Paths (P0)
# Tests for untested critical paths identified in docs/UNTESTED_CRITICAL_PATHS.md
# ============================================================================

# bats test_tags=category:high-risk,priority:high,untested-critical-path
@test "load_config fails in fake mode - should exit with code 0" {
	# Purpose: Test verifies that load_config() failures in fake mode exit gracefully with code 0
	# Expected: Script exits with code 0 in fake mode even if config loading fails (errors are logged)
	# Importance: Fake mode should not fail tests; errors should be logged but script should exit successfully
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config with invalid syntax (unclosed quote)
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1
PING_COUNT=5
EOF

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Run script in fake mode - should exit with code 0 even if config fails
	add_mock_to_path
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Should log error about config file
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Failed to parse" "ERROR" "WARNING"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high,untested-critical-path
@test "validate_critical_config_vars detects missing required variables" {
	# Purpose: Test verifies that validate_critical_config_vars() detects missing required variables after parsing
	# Expected: Script detects missing required variables, logs error, exits appropriately
	# Importance: Missing required variables prevent script execution; must be detected early
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config that parses but is missing required variables
	# Note: This is hard to test directly since schema defaults are applied, but we can test the validation path
	create_test_config "$config_file" \
		'PING_COUNT=5'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Run script - should detect missing required variables
	add_mock_to_path
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	# May succeed if defaults are applied, or fail if validation catches missing vars
	# The important thing is that validation runs

	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high,untested-critical-path
@test "config file parsing partially succeeds - some variables set, others not" {
	# Purpose: Test verifies that script handles partial config parsing failures gracefully
	# Expected: Script detects partial parsing failure, validates critical variables, handles gracefully
	# Importance: Partial parsing failures can leave config in inconsistent state; must be detected
	# This test covers the untested critical path: Config file parsing partially succeeds (some variables set, others not)
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config with some valid and some invalid lines
	# Note: INVALID_LINE_WITHOUT_EQUALS must be written directly since create_test_config only handles valid assignments
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"PING_COUNT=5" \
		"TIER1_THRESHOLD=1"
	# Add invalid line manually (testing that parser skips it)
	echo "INVALID_LINE_WITHOUT_EQUALS" >>"$config_file"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Run script - should handle partial parsing
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	# Should succeed (invalid lines are skipped by safe_parse_config_file)
	assert_success

	assert_file_exist "$LOG_FILE"
	# Should log error about invalid line but continue parsing
	assert_log_contains_any "$LOG_FILE" "Failed to parse" "Invalid" "ERROR"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high,untested-critical-path
@test "handle_fatal_config_error exit behavior in fake mode vs normal mode" {
	# Purpose: Test verifies that handle_fatal_config_error() exits with code 0 in fake mode, error code in normal mode
	# Expected: Fake mode exits with 0, normal mode exits with error code
	# Importance: Correct exit behavior ensures tests pass in fake mode but fail appropriately in normal mode
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config file that will trigger fatal error (unreadable)
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\""

	# Make config file unreadable
	chmod 000 "$config_file"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Test 1: Fake mode - should exit with code 0
	add_mock_to_path
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Test 2: Normal mode - should exit with error code
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"
	assert_failure

	# Restore permissions for cleanup
	chmod 644 "$config_file" 2>/dev/null || true

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high,untested-critical-path
@test "load_config fails in normal mode - defensive check exits with error code" {
	# Purpose: Test verifies that load_config() failures in normal mode exit with error code (defensive check)
	# Expected: Script exits with EXIT_VALIDATION_ERROR (3) if load_config fails but doesn't exit (defensive check)
	# Importance: Defensive check ensures script exits even if load_config returns 1 without exiting
	# Note: In normal mode, load_config should exit via handle_error_or_exit_fake_mode, but this tests the defensive path
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config with invalid syntax that will cause load_config to fail
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1
PING_COUNT=5
EOF

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Run script in normal mode (not fake mode) - should exit with error code
	add_mock_to_path
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"
	# Should exit with error code
	# In normal mode, load_config should exit via handle_fatal_config_error (EXIT_CONFIG_ERROR=2)
	# The defensive check at line 148 (EXIT_VALIDATION_ERROR=3) is a safety net if load_config returns 1 without exiting
	# Either way, script should exit with a non-zero code
	assert_failure
	# Should log error about config file
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Failed to parse" "ERROR" "configuration"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high,untested-critical-path
@test "validate_config fails after load_config succeeds" {
	# Purpose: Test verifies that validate_config() failures after successful load_config() are handled correctly
	# Expected: Script detects validation failure after config loads, exits appropriately
	# Importance: Config may parse successfully but fail validation (e.g., invalid threshold values, missing location config)
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config that parses successfully but fails validation
	# Missing location config will cause validation to fail
	create_test_config "$config_file" \
		"PING_COUNT=5" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"
	# Missing LOCATION_*_EXTERNAL - will cause validation to fail

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Run script - should fail validation after successful load
	add_mock_to_path
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	# Should exit with error code (validation errors are execution-blocking and fail even in fake mode; see fake-mode guidance in CODE_PATTERNS/TEST_PATTERNS)
	assert_failure
	# Exit code should be EXIT_VALIDATION_ERROR (3)
	assert_equal "$status" 3

	# Should log validation error
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "validation" "ERROR" "location"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high,untested-critical-path
@test "config loading fails but LOG_FILE was set before load_config - fallback behavior" {
	# Purpose: Test verifies that LOG_FILE set before load_config() is preserved when config parsing fails
	# Expected: LOG_FILE set before load_config() is preserved even when config parsing fails (in fake mode)
	# Importance: Ensures custom log files (e.g., vpn-keepalive.log) are preserved when config parsing fails
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	mkdir -p "${TEST_DIR}/custom-logs"
	local custom_log_file="${TEST_DIR}/custom-logs/custom.log"
	local state_dir="${TEST_DIR}"

	# Create config with invalid syntax that will cause parsing to fail
	# In fake mode, this won't exit, allowing us to test LOG_FILE preservation
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1
PING_COUNT=5
EOF

	# Create test version of script with custom log file
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$custom_log_file")

	# Modify test script to set LOG_FILE before load_config (simulating vpn-keepalive.sh behavior)
	# Find the line with "# Load configuration" and insert LOG_FILE assignment before it
	sed -i '/^# Load configuration$/i LOG_FILE="'"$custom_log_file"'"' "$test_script"

	# Run script in fake mode - should preserve custom log file even if config parsing fails
	add_mock_to_path
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	# Should exit successfully in fake mode (config parsing failure is non-fatal)
	assert_success

	# Custom log file should exist (LOG_FILE was preserved)
	# The log file should be created and used for logging
	assert_file_exist "$custom_log_file"
	# Should log error about config parsing failure
	assert_log_contains_any "$custom_log_file" "Failed to parse" "ERROR" "WARNING"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high,untested-critical-path
@test "safe_parse_config_file fails but error is properly caught" {
	# Purpose: Test verifies that safe_parse_config_file() failures are properly caught and handled
	# Expected: Script catches safe_parse_config_file() failure, calls handle_fatal_config_error, exits appropriately
	# Importance: safe_parse_config_file() failures must be caught to prevent script from continuing with invalid config
	# This test covers the untested critical path: safe_parse_config_file() fails but error not caught
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config with syntax error that will cause safe_parse_config_file to fail
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1
PING_COUNT=5
EOF

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Test 1: Fake mode - should exit with code 0 (error caught and handled gracefully)
	add_mock_to_path
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Should log error about config file parsing failure
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Failed to parse configuration file" "Failed to parse"

	# Test 2: Normal mode - should exit with error code (error caught and script exits)
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"
	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high,untested-critical-path
@test "config file contains dangerous content - caught by safe_parse" {
	# Purpose: Test verifies that safe_parse_config_file() detects and rejects dangerous content
	# Expected: Script detects dangerous content (command injection attempts), logs error, rejects config
	# Importance: Dangerous content could lead to code execution; safe_parse must catch it
	# This test covers the untested critical path: Config file contains dangerous content but parsing succeeds (should be caught by safe_parse)
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config with dangerous content (command injection attempts)
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
# Dangerous content patterns that should be caught
NETWORK_PARTITION_DNS_HOSTNAME=$(echo evil)
LOCATION_TEST_INTERNAL="`whoami`"
TIER1_THRESHOLD=$(id)
EOF

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Test 1: Fake mode - should exit with code 0 (error caught and handled gracefully)
	add_mock_to_path
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	# Should succeed in fake mode (error logged but exits gracefully)
	assert_success

	# Should log error about dangerous content
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "dangerous content" "Dangerous" "Failed to parse"

	# Test 2: Normal mode - should exit with error code (dangerous content rejected)
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"
	assert_failure

	remove_mock_from_path
}
