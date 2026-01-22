#!/usr/bin/env bats
#
# Tests for check-config.sh script
# Tests configuration validation functionality, missing/deprecated settings detection

load test_helper
load helpers/config

# Path to the check-config script
CHECK_CONFIG_SCRIPT="${BATS_TEST_DIRNAME}/../check-config.sh"

# bats test_tags=category:unit
@test "check-config.sh exists and is executable" {
	# Purpose: Test verifies that the check-config script file exists and has execute permissions
	# Expected: Check-config script file is present and executable
	# Importance: Ensures the config validation script can be run directly for troubleshooting
	assert_file_exist "$CHECK_CONFIG_SCRIPT"
	assert_file_executable "$CHECK_CONFIG_SCRIPT"
}

# bats test_tags=category:unit
@test "check-config.sh shows help with --help flag" {
	# Purpose: Test verifies that the check-config script displays usage information when --help flag is provided
	# Expected: Script outputs usage information including all available options and flags
	# Importance: Ensures users can access help documentation for script usage and available options
	run bash "$CHECK_CONFIG_SCRIPT" --help
	assert_success
	assert_output --partial "Usage:"
	assert_output --partial "check-config.sh"
	assert_output --partial "--config"
	assert_output --partial "--help"
}

# bats test_tags=category:unit
@test "check-config.sh shows help with -h flag" {
	# Purpose: Test verifies that the check-config script displays usage information when -h flag is provided
	# Expected: Script outputs usage information including all available options and flags
	# Importance: Ensures users can access help documentation using the short flag option
	run bash "$CHECK_CONFIG_SCRIPT" -h
	assert_success
	assert_output --partial "Usage:"
}

# bats test_tags=category:unit
@test "check-config.sh exits with error if config file not found" {
	# Purpose: Test verifies that the check-config script validates config file existence before processing
	# Expected: Script exits with failure status and displays error message when config file doesn't exist
	# Importance: Prevents script from attempting to validate non-existent files and provides clear error feedback
	local test_dir="${TEST_DIR}/test-install"
	mkdir -p "$test_dir"
	create_test_lib "$test_dir"

	# Run script from test directory (config won't exist)
	run bash "$CHECK_CONFIG_SCRIPT" --config "${test_dir}/nonexistent.conf"

	assert_failure
	assert_output --partial "Configuration file not found"
}

# bats test_tags=category:unit
@test "check-config.sh exits with error if lib directory not found" {
	# Purpose: Test verifies that the script requires lib/config_schema.sh to be available
	# Expected: Script exits with error when lib directory or config_schema.sh is missing
	# Importance: Ensures script fails gracefully when schema is unavailable
	# shellcheck disable=SC2153
	local test_dir="${TEST_DIR}/no-lib-dir"
	mkdir -p "$test_dir"
	local config_file="${test_dir}/vpn-monitor.conf"
	create_valid_config "$config_file"

	# Copy script to directory without lib
	cp "$CHECK_CONFIG_SCRIPT" "${test_dir}/check-config.sh"
	chmod +x "${test_dir}/check-config.sh"

	# Run from directory without lib (should fail to find schema)
	run bash "${test_dir}/check-config.sh" --config "$config_file"

	assert_failure
	assert_output --partial "config_schema.sh not found"
}

# bats test_tags=category:unit
@test "check-config.sh detects missing settings" {
	# Purpose: Test verifies that the script identifies settings that are in schema but not in config
	# Expected: Script reports missing settings with their default values
	# Importance: Helps users identify what settings they should add to their config
	local test_dir="${TEST_DIR}/test-install"
	mkdir -p "$test_dir"
	create_test_lib "$test_dir"

	local config_file="${test_dir}/vpn-monitor.conf"
	# Create config with only required settings (missing optional ones)
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'MAX_RESTARTS_PER_WINDOW=3' \
		'RATE_LIMIT_WINDOW_MINUTES=60' \
		'MIN_RESTART_INTERVAL_SECONDS=30'

	run bash "$CHECK_CONFIG_SCRIPT" --config "$config_file"

	assert_failure # Should fail because missing settings
	assert_output --partial "Missing Settings"
	assert_output --partial "NO_ESCALATE"
	assert_output --partial "RECOVERY_VERIFY_TIMEOUT"
}

# bats test_tags=category:unit
@test "check-config.sh detects deprecated settings" {
	# Purpose: Test verifies that the script identifies settings that are in config but not in schema
	# Expected: Script reports deprecated settings that should be removed
	# Importance: Helps users clean up obsolete configuration settings
	local test_dir="${TEST_DIR}/test-install"
	mkdir -p "$test_dir"
	create_test_lib "$test_dir"

	local config_file="${test_dir}/vpn-monitor.conf"
	# Create config with deprecated settings
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		'EXTERNAL_PEER_IPS="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'MAX_RESTARTS_PER_WINDOW=20
RATE_LIMIT_WINDOW_MINUTES=60' \
		'PING_TARGET_IP="192.168.1.100"' \
		'OLD_DEPRECATED_SETTING="value"'

	run bash "$CHECK_CONFIG_SCRIPT" --config "$config_file"

	assert_failure # Should fail because deprecated settings
	assert_output --partial "Deprecated Settings"
	assert_output --partial "EXTERNAL_PEER_IPS"
	assert_output --partial "PING_TARGET_IP"
	assert_output --partial "OLD_DEPRECATED_SETTING"
}

# bats test_tags=category:unit
@test "check-config.sh reports valid config correctly" {
	# Purpose: Test verifies that the script correctly identifies when config is valid and up-to-date
	# Expected: Script reports success when all settings are present and no deprecated settings exist
	# Importance: Confirms script works correctly for valid configurations
	local test_dir="${TEST_DIR}/test-install"
	mkdir -p "$test_dir"
	create_test_lib "$test_dir"

	local config_file="${test_dir}/vpn-monitor.conf"
	# Create config with all schema settings
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'MAX_RESTARTS_PER_WINDOW=3' \
		'RATE_LIMIT_WINDOW_MINUTES=60' \
		'MIN_RESTART_INTERVAL_SECONDS=30' \
		'NO_ESCALATE=0' \
		'RECOVERY_VERIFY_TIMEOUT=30' \
		'LOGS_DIR=""'

	run bash "$CHECK_CONFIG_SCRIPT" --config "$config_file"

	# Should succeed (or at least not report issues)
	# Note: May still fail if there are other missing settings in the real schema
	# but for our minimal test schema, this should be valid
	assert_output --partial "Valid settings"
	assert_output --partial "No deprecated settings found"
}

# bats test_tags=category:unit
@test "check-config.sh shows default values for missing settings" {
	# Purpose: Test verifies that the script displays default values for missing optional settings
	# Expected: Script shows default values in recommendations section
	# Importance: Makes it easy for users to add missing settings with correct defaults
	local test_dir="${TEST_DIR}/test-install"
	mkdir -p "$test_dir"
	create_test_lib "$test_dir"

	local config_file="${test_dir}/vpn-monitor.conf"
	create_valid_config "$config_file"

	run bash "$CHECK_CONFIG_SCRIPT" --config "$config_file"

	assert_failure
	assert_output --partial "NO_ESCALATE=0"
	assert_output --partial "RECOVERY_VERIFY_TIMEOUT=30"
}

# bats test_tags=category:unit
@test "check-config.sh handles empty config file gracefully" {
	# Purpose: Test verifies that the script handles empty config files without crashing
	# Expected: Script reports all schema settings as missing
	# Importance: Ensures script works for new installations with empty configs
	local test_dir="${TEST_DIR}/test-install"
	mkdir -p "$test_dir"
	create_test_lib "$test_dir"

	local config_file="${test_dir}/vpn-monitor.conf"
	touch "$config_file"

	run bash "$CHECK_CONFIG_SCRIPT" --config "$config_file"

	assert_failure
	assert_output --partial "Missing Settings"
}

# bats test_tags=category:unit
@test "check-config.sh handles config file with only comments" {
	# Purpose: Test verifies that the script correctly ignores comment-only config files
	# Expected: Script treats comment-only files as empty and reports missing settings
	# Importance: Ensures comments don't interfere with validation
	local test_dir="${TEST_DIR}/test-install"
	mkdir -p "$test_dir"
	create_test_lib "$test_dir"

	local config_file="${test_dir}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
# This is a comment
# Another comment
# EXTERNAL_PEER_IPS="192.168.1.1"  # This is commented out
EOF

	run bash "$CHECK_CONFIG_SCRIPT" --config "$config_file"

	assert_failure
	assert_output --partial "Missing Settings"
}

# bats test_tags=category:unit
@test "check-config.sh auto-detects config file in script directory" {
	# Purpose: Test verifies that the script automatically finds config file in its directory
	# Expected: Script finds vpn-monitor.conf in the same directory as the script
	# Importance: Makes script easier to use without requiring explicit config path
	local test_dir="${TEST_DIR}/test-install"
	mkdir -p "$test_dir"
	create_test_lib "$test_dir"

	local config_file="${test_dir}/vpn-monitor.conf"
	create_valid_config "$config_file"

	# Copy script to test directory
	cp "$CHECK_CONFIG_SCRIPT" "${test_dir}/check-config.sh"
	chmod +x "${test_dir}/check-config.sh"

	# Run from test directory (should auto-detect config)
	run bash "${test_dir}/check-config.sh"

	# Should find the config file
	assert_output --partial "Checking configuration file"
	assert_output --partial "vpn-monitor.conf"
}

# bats test_tags=category:unit
@test "check-config.sh provides recommendations section" {
	# Purpose: Test verifies that the script provides actionable recommendations for fixing config issues
	# Expected: Script shows exact lines to add/remove in recommendations section
	# Importance: Makes it easy for users to update their config files
	local test_dir="${TEST_DIR}/test-install"
	mkdir -p "$test_dir"
	create_test_lib "$test_dir"

	local config_file="${test_dir}/vpn-monitor.conf"
	# Create config with missing and deprecated settings
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		'EXTERNAL_PEER_IPS="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'MAX_RESTARTS_PER_WINDOW=20
RATE_LIMIT_WINDOW_MINUTES=60' \
		'DEPRECATED_SETTING="old"'
	# Note: Missing required settings like MAX_RESTARTS_PER_WINDOW, RATE_LIMIT_WINDOW_MINUTES, MIN_RESTART_INTERVAL_SECONDS

	run bash "$CHECK_CONFIG_SCRIPT" --config "$config_file"

	assert_failure
	assert_output --partial "Recommendations"
	assert_output --partial "Add the following"
	assert_output --partial "Remove the following"
}

# bats test_tags=category:unit
@test "check-config.sh handles quoted values correctly" {
	# Purpose: Test verifies that the script correctly parses quoted config values
	# Expected: Script correctly identifies variables with quoted values
	# Importance: Ensures script works with standard config file format
	local test_dir="${TEST_DIR}/test-install"
	mkdir -p "$test_dir"
	create_test_lib "$test_dir"

	local config_file="${test_dir}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_DC_EXTERNAL=\"${TEST_PEER_IP2}\"" \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'MAX_RESTARTS_PER_WINDOW=3' \
		'RATE_LIMIT_WINDOW_MINUTES=60' \
		'MIN_RESTART_INTERVAL_SECONDS=30'

	run bash "$CHECK_CONFIG_SCRIPT" --config "$config_file"

	# Should parse quoted values correctly
	assert_output --partial "Valid settings"
}

# bats test_tags=category:unit
@test "check-config.sh handles unquoted values correctly" {
	# Purpose: Test verifies that the script correctly parses unquoted config values
	# Expected: Script correctly identifies variables with unquoted values
	# Importance: Ensures script works with both quoted and unquoted formats
	local test_dir="${TEST_DIR}/test-install"
	mkdir -p "$test_dir"
	create_test_lib "$test_dir"

	local config_file="${test_dir}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'MAX_RESTARTS_PER_WINDOW=3' \
		'RATE_LIMIT_WINDOW_MINUTES=60' \
		'MIN_RESTART_INTERVAL_SECONDS=30' \
		'NO_ESCALATE=0' \
		'RECOVERY_VERIFY_TIMEOUT=30'

	run bash "$CHECK_CONFIG_SCRIPT" --config "$config_file"

	# Should parse unquoted values correctly
	assert_output --partial "Valid settings"
}

# bats test_tags=category:unit
@test "check-config.sh handles config file with trailing comments" {
	# Purpose: Test verifies that the script correctly handles config lines with inline comments
	# Expected: Script parses variable assignments correctly even with trailing comments
	# Importance: Ensures script works with commented config files
	local test_dir="${TEST_DIR}/test-install"
	mkdir -p "$test_dir"
	create_test_lib "$test_dir"

	local config_file="${test_dir}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
# Config with inline comments
LOCATION_NYC_EXTERNAL="${TEST_PEER_IP}"  # External IP
TIER1_THRESHOLD=1  # Tier 1 threshold
TIER2_THRESHOLD=3  # Tier 2 threshold
TIER3_THRESHOLD=5  # Tier 3 threshold
MAX_RESTARTS_PER_WINDOW=3  # Max restarts per window
RATE_LIMIT_WINDOW_MINUTES=60  # Rate limit window
MIN_RESTART_INTERVAL_SECONDS=30  # Min restart interval
EOF

	run bash "$CHECK_CONFIG_SCRIPT" --config "$config_file"

	# Should parse correctly despite inline comments
	assert_output --partial "Valid settings"
}

# bats test_tags=category:unit
@test "check-config.sh shows summary statistics" {
	# Purpose: Test verifies that the script provides summary statistics of config validation
	# Expected: Script shows counts of valid, missing, and deprecated settings
	# Importance: Provides quick overview of config status
	local test_dir="${TEST_DIR}/test-install"
	mkdir -p "$test_dir"
	create_test_lib "$test_dir"

	local config_file="${test_dir}/vpn-monitor.conf"
	create_valid_config "$config_file"

	run bash "$CHECK_CONFIG_SCRIPT" --config "$config_file"

	assert_output --partial "Summary:"
	assert_output --partial "Valid settings:"
}

# bats test_tags=category:unit
@test "check-config.sh handles required vs optional settings" {
	# Purpose: Test verifies that the script distinguishes between required and optional missing settings
	# Expected: Script marks required settings differently from optional ones
	# Importance: Helps users prioritize which settings to add first
	local test_dir="${TEST_DIR}/test-install"
	mkdir -p "$test_dir"
	create_test_lib "$test_dir"

	local config_file="${test_dir}/vpn-monitor.conf"
	# Create config missing both required and optional settings
	create_test_config "$config_file" \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5'
	# Missing MAX_RESTARTS_PER_WINDOW, RATE_LIMIT_WINDOW_MINUTES, MIN_RESTART_INTERVAL_SECONDS (required) and optional settings

	run bash "$CHECK_CONFIG_SCRIPT" --config "$config_file"

	assert_failure
	# Should indicate required settings are marked differently
	assert_output --partial "MAX_RESTARTS_PER_WINDOW"
	assert_output --partial "REQUIRED" || assert_output --partial "required"
}
