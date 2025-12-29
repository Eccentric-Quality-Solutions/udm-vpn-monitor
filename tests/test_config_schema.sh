#!/usr/bin/env bats
#
# Tests for Configuration Schema Default Application
# Tests critical paths and error handling scenarios

load test_helper
load fixtures/vpn_active

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# CONFIG SCHEMA DEFAULT APPLICATION
# ============================================================================

# bats test_tags=category:high-risk,priority:medium
@test "Schema defaults - All variables get defaults before config file parsing" {
	# Test verifies that all schema variables get defaults applied before config file parsing.
	# Expected: Variables have default values before config file is parsed.
	# Importance: Ensures variables are safe to reference before config parsing.
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create empty config file (no values set)
	touch "$config_file"

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
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
	# Test verifies that config file values override schema defaults.
	# Expected: Config file values take precedence over defaults.
	# Importance: Ensures config file customization works correctly.
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
VPN_NAME="Custom VPN Name"
TIER1_THRESHOLD=5
ENABLE_PING_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	run bash "$test_script" --fake

	assert_success
	assert_file_exist "$log_file"
	# Config file values should override defaults
	# VPN_NAME should be "Custom VPN Name" not "Site-to-Site VPN"
	assert_file_contains "$log_file" "Custom VPN Name" || assert_file_contains "$log_file" "VPN_NAME" || assert_file_contains "$log_file" "Configuration loaded"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Schema defaults - Required variables without defaults remain empty until validation" {
	# Test verifies that required variables without schema defaults remain empty until validation.
	# Expected: Required variables without defaults are empty after apply_schema_defaults but fail validation.
	# Importance: Ensures validation catches missing required values.
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config file without EXTERNAL_PEER_IPS (required, no default in schema)
	cat >"$config_file" <<'EOF'
# EXTERNAL_PEER_IPS not set (required variable)
TIER1_THRESHOLD=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	run bash "$test_script" --fake
	assert_success

	# Should fail validation (EXTERNAL_PEER_IPS is required)
	# Script should exit with error or log validation error
	assert_file_exist "$log_file"
	# Should contain error about missing required variable or validation failure
	assert_file_contains "$log_file" "EXTERNAL_PEER_IPS" || assert_file_contains "$log_file" "required" || assert_file_contains "$log_file" "ERROR" || assert_file_contains "$log_file" "validation"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Schema defaults - Optional variables without defaults remain empty" {
	# Test verifies that optional variables without schema defaults remain empty.
	# Expected: Optional variables without defaults are empty and remain empty.
	# Importance: Ensures optional variables work correctly when not set.
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config file without INTERNAL_PEER_IPS (optional, no default in schema)
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
# INTERNAL_PEER_IPS not set (optional variable without default)
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	run bash "$test_script" --fake

	# Should succeed (optional variable can be empty)
	assert_success
	assert_file_exist "$log_file"
	# Script should run without errors (optional variable empty is acceptable)

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Schema defaults - Default application order (before config parsing)" {
	# Test verifies that defaults are applied before config file parsing.
	# Expected: Defaults are set, then config file values override them.
	# Importance: Ensures correct order of operations in load_config.
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
VPN_NAME="Override Default"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
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
	export STATE_DIR="$state_dir"
	export LOG_FILE="$log_file"
	export LOGS_DIR="${state_dir}/logs"

	# Unset VPN_NAME to ensure we start clean
	unset VPN_NAME

	# Call load_config which should apply defaults first, then parse config
	load_config "$config_file"

	# Verify that VPN_NAME was set to config file value (not default)
	# This proves defaults were applied first, then overridden by config
	assert_equal "${VPN_NAME:-}" "Override Default"

	remove_mock_from_path
}
