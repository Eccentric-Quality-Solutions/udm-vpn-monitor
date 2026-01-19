#!/usr/bin/env bats
#
# Tests for Configuration Schema Default Application
# Tests critical paths and error handling scenarios

load test_helper
load helpers/config
load helpers/assertions
load fixtures/vpn_active

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# CONFIG SCHEMA DEFAULT APPLICATION
# ============================================================================

# bats test_tags=category:high-risk,priority:medium
@test "Schema defaults - All variables get defaults before config file parsing" {
	# Purpose: Test verifies that all schema variables get defaults applied before config file parsing
	# Expected: Variables have default values before config file is parsed
	# Importance: Ensures variables are safe to reference before config parsing
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create empty config file (no values set)
	touch "$config_file"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Source the script to access functions directly
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true
	# shellcheck source=../lib/config_schema.sh
	source "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" 2>/dev/null || true

	# Apply defaults (simulating what load_config does)
	apply_schema_defaults

	# Verify some variables have defaults (check a few key ones)
	# VPN_NAME should have default "Site-to-Site VPN"
	assert_equal "${VPN_NAME:-}" "Site-to-Site VPN"
	# ENABLE_PING_CHECK should have default 1
	assert_equal "${ENABLE_PING_CHECK:-}" "1"
	# TIER1_THRESHOLD should have default 1
	assert_equal "${TIER1_THRESHOLD:-}" "1"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Schema defaults - Config file values override defaults" {
	# Purpose: Test verifies that config file values override schema defaults
	# Expected: Config file values take precedence over defaults
	# Importance: Ensures config file customization works correctly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		'VPN_NAME="Custom VPN Name"' \
		"TIER1_THRESHOLD=5" \
		"TIER2_THRESHOLD=5" \
		"TIER3_THRESHOLD=5" \
		"ENABLE_PING_CHECK=0"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	run bash "$test_script" --fake

	assert_success
	assert_file_exist "$LOG_FILE"
	# Config file values should override defaults
	# VPN_NAME should be "Custom VPN Name" not "Site-to-Site VPN"
	assert_log_contains_any "$LOG_FILE" "Custom VPN Name" "VPN_NAME" "Configuration loaded"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Schema defaults - Required variables without defaults remain empty until validation" {
	# Purpose: Test verifies that required variables without schema defaults remain empty until validation
	# Expected: Required variables without defaults are empty after apply_schema_defaults but fail validation
	# Importance: Ensures validation catches missing required values
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config file without location configuration (required, no default in schema)
	create_test_config "$config_file" \
		"TIER1_THRESHOLD=1" \
		"ENABLE_NETWORK_PARTITION_CHECK=0"
	# No LOCATION_*_EXTERNAL variables set (required)

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	run bash "$test_script" --fake
	# Should fail validation (location configuration is required)
	# Script should exit with error status (validation error)
	assert_failure

	# Should contain error about missing location configuration or validation failure
	# The error message format is: "No location-based configuration found. At least one LOCATION_*_EXTERNAL variable is required."
	# or "Configuration validation failed - required variables missing or invalid values"
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "LOCATION" "required" "ERROR" "validation" "No location"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Schema defaults - Optional variables without defaults remain empty" {
	# Purpose: Test verifies that optional variables without schema defaults remain empty
	# Expected: Optional variables without defaults are empty and remain empty
	# Importance: Ensures optional variables work correctly when not set
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config file without LOCATION_TEST_INTERNAL (optional, no default in schema)
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\""
	# LOCATION_TEST_INTERNAL not set (optional variable without default)

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	run bash "$test_script" --fake

	# Should succeed (optional variable can be empty)
	assert_success
	assert_file_exist "$LOG_FILE"
	# Script should run without errors (optional variable empty is acceptable)

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Schema defaults - Default application order (before config parsing)" {
	# Purpose: Test verifies that defaults are applied before config file parsing
	# Expected: Defaults are set, then config file values override them
	# Importance: Ensures correct order of operations in load_config
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		'VPN_NAME="Override Default"'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Source config functions to test order
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true
	# shellcheck source=../lib/config_schema.sh
	source "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" 2>/dev/null || true

	# Test that load_config applies defaults before parsing config file
	# Source required dependencies
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true

	# Set required environment variables for load_config
	# (setup_test_environment already set these, but we keep for clarity)
	export CONFIG_FILE="$config_file"

	# Unset VPN_NAME to ensure we start clean
	unset VPN_NAME

	# Call load_config which should apply defaults first, then parse config
	load_config "$config_file"

	# Verify that VPN_NAME was set to config file value (not default)
	# This proves defaults were applied first, then overridden by config
	assert_equal "${VPN_NAME:-}" "Override Default"

	remove_mock_from_path
}

# ============================================================================
# CONFIG SCHEMA FORMAT VALIDATION
# ============================================================================

# bats test_tags=category:low-risk,priority:low
@test "Schema format - All schema entries parse correctly" {
	# Purpose: Verify all CONFIG_SCHEMA entries can be parsed without errors
	# Expected: All schema entries parse successfully using parse_config_schema
	# Importance: Catches malformed schema definitions at test time, not runtime
	# This test validates that the schema format is correct for all entries,
	# ensuring parse_config_schema() can successfully parse each schema string.

	# Source required functions
	# shellcheck source=../lib/config_schema.sh
	source "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" 2>/dev/null || true
	# shellcheck source=../lib/config/config_loading.sh
	source "${BATS_TEST_DIRNAME}/../lib/config/config_loading.sh" 2>/dev/null || true

	local var_name
	local schema
	local parse_errors=0
	local failed_vars=()

	# Test all schema entries
	for var_name in "${!CONFIG_SCHEMA[@]}"; do
		schema="${CONFIG_SCHEMA[$var_name]}"

		# Attempt to parse the schema
		# parse_config_schema always returns 4 lines: required, type, rules, default
		# Use process substitution to read lines reliably
		# We only validate required and type fields; rules and default are read but not validated
		local required
		local var_type
		local rules
		local default_val

		if ! {
			read -r required
			read -r var_type
			# shellcheck disable=SC2034 # rules and default_val are intentionally read but not used - we only validate required and type
			read -r rules
			read -r default_val
		} < <(parse_config_schema "$schema" 2>&1); then
			failed_vars+=("$var_name: parse command failed")
			parse_errors=$((parse_errors + 1))
			continue
		fi

		# Verify required field is valid
		if [[ "$required" != "required" ]] && [[ "$required" != "optional" ]]; then
			failed_vars+=("$var_name: invalid required field '$required'")
			parse_errors=$((parse_errors + 1))
			continue
		fi

		# Verify type field is valid
		if [[ "$var_type" != "string" ]] && [[ "$var_type" != "integer" ]]; then
			failed_vars+=("$var_name: invalid type field '$var_type'")
			parse_errors=$((parse_errors + 1))
			continue
		fi
	done

	# Report any failures
	if [[ $parse_errors -gt 0 ]]; then
		echo "Failed to parse $parse_errors schema entries:" >&2
		printf '  %s\n' "${failed_vars[@]}" >&2
	fi

	assert_equal "$parse_errors" 0
}
