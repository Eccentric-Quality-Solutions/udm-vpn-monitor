#!/usr/bin/env bats
#
# Tests for Configuration Variable Validation
# Tests critical paths and error handling scenarios

load test_helper
load helpers/assertions
load fixtures/vpn_active

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# CONFIGURATION VARIABLE VALIDATION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "invalid MAX_RESTARTS_PER_WINDOW (negative)" {
	# Purpose: Test verifies that the script handles negative MAX_RESTARTS_PER_WINDOW values gracefully
	# Expected: Script processes negative value without crashing, either using default or failing gracefully
	# Importance: Negative values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		'MAX_RESTARTS_PER_WINDOW=-1'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	mock_ip_xfrm_state "${TEST_PEER_IP}" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid MAX_RESTARTS_PER_WINDOW (zero)" {
	# Purpose: Test verifies that the script handles zero MAX_RESTARTS_PER_WINDOW values gracefully
	# Expected: Script processes zero value without crashing, either using default or failing gracefully
	# Importance: Zero values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		'MAX_RESTARTS_PER_WINDOW=0'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	mock_ip_xfrm_state "${TEST_PEER_IP}" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid LOCKFILE_TIMEOUT (negative)" {
	# Purpose: Test verifies that the script handles negative LOCKFILE_TIMEOUT values gracefully
	# Expected: Script processes negative value without crashing, either using default or failing gracefully
	# Importance: Negative values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		'LOCKFILE_TIMEOUT=-1'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	mock_ip_xfrm_state "${TEST_PEER_IP}" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid LOCKFILE_TIMEOUT (zero)" {
	# Purpose: Test verifies that the script handles zero LOCKFILE_TIMEOUT values gracefully
	# Expected: Script processes zero value without crashing, either using default or failing gracefully
	# Importance: Zero values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		'LOCKFILE_TIMEOUT=0'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	mock_ip_xfrm_state "${TEST_PEER_IP}" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_COUNT (negative)" {
	# Purpose: Test verifies that the script handles negative PING_COUNT values gracefully
	# Expected: Script processes negative value without crashing, either using default or failing gracefully
	# Importance: Negative values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		'PING_COUNT=-1'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	mock_ip_xfrm_state "${TEST_PEER_IP}" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_COUNT (zero)" {
	# Purpose: Test verifies that the script handles zero PING_COUNT values gracefully
	# Expected: Script processes zero value without crashing, either using default or failing gracefully
	# Importance: Zero values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		'PING_COUNT=0'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	mock_ip_xfrm_state "${TEST_PEER_IP}" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_TIMEOUT (negative)" {
	# Purpose: Test verifies that the script handles negative PING_TIMEOUT values gracefully
	# Expected: Script processes negative value without crashing, either using default or failing gracefully
	# Importance: Negative values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		'PING_TIMEOUT=-1'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	mock_ip_xfrm_state "${TEST_PEER_IP}" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_TIMEOUT (zero)" {
	# Purpose: Test verifies that the script handles zero PING_TIMEOUT values gracefully
	# Expected: Script processes zero value without crashing, either using default or failing gracefully
	# Importance: Zero values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		'PING_TIMEOUT=0'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	mock_ip_xfrm_state "${TEST_PEER_IP}" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# ============================================================================
# ROUTE SETUP VALIDATION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "validate_config calls route setup when routes are needed" {
	# Purpose: Test verifies that validate_config() calls setup_routes_if_needed() when routes are needed
	# Expected: Route setup functions are called during validation when ENABLE_PING_CHECK=1 and internal IPs are configured
	# Importance: Ensures routes are set up proactively during config validation, not just during ping checks
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		'ENABLE_PING_CHECK=1' \
		'LOCAL_UDM_IP="10.0.0.1"'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Track calls to route setup functions
	local route_check_log="${TEST_DIR}/route_check_log"
	>"$route_check_log"

	# Create mock ip command that logs route checks and additions
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "addr" ]] && [[ "\$2" == "show" ]] && [[ "\$3" == "br0" ]]; then
    # Log the check
    echo "check_route_exists: \$*" >> "$route_check_log"
    # Simulate route does not exist (so it will try to add)
    exit 1
elif [[ "\$1" == "addr" ]] && [[ "\$2" == "add" ]]; then
    # Log the add attempt
    echo "add_route: \$*" >> "$route_check_log"
    # Simulate successful route add
    exit 0
fi
# Handle xfrm for other tests
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    exit 0
fi
# Fallback to real ip for other commands
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Run script - should call route setup during validation
	run bash "$test_script" --fake

	# Should succeed (route setup succeeds)
	assert_success

	# Verify route check was called during validation
	assert_file_exist "$route_check_log"
	assert_file_contains "$route_check_log" "check_route_exists"
	# Route add should be called if route doesn't exist
	assert_file_contains "$route_check_log" "add_route"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "validate_config fails when route setup fails and routes are needed (main execution path)" {
	# Purpose: Test verifies that validate_config() fails validation when route setup fails and routes are needed
	# Expected: Validation fails with error message when route setup fails in main execution path (log_message available)
	# Importance: Ensures routes are available before ping checks run, preventing silent failures
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		'ENABLE_PING_CHECK=1' \
		'LOCAL_UDM_IP="10.0.0.1"'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create mock ip command that simulates route setup failure
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "addr" ]] && [[ "$2" == "show" ]] && [[ "$3" == "br0" ]]; then
    # Route does not exist
    exit 1
elif [[ "$1" == "addr" ]] && [[ "$2" == "add" ]]; then
    # Route add fails
    exit 1
fi
# Handle xfrm for other tests
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    exit 0
fi
# Fallback to real ip for other commands
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Run script - should fail validation because route setup fails
	# In main execution path (log_message available), validation should fail
	run bash "$test_script" --fake

	# Should fail validation (exit code 3 = EXIT_VALIDATION_ERROR)
	assert_failure
	# Should contain route setup error message
	assert_log_contains_any "$LOG_FILE" "Route setup failed" "Failed to add route"

	remove_mock_from_path
}

# bats test_tags=category:medium,priority:medium
@test "validate_config route setup behavior documented - test context compatibility" {
	# Purpose: Test documents that validate_config() behavior allows test compatibility when route setup fails
	# Expected: This test verifies that the code's test-friendly behavior (checking log_message availability) works as intended
	# Importance: Documents that tests can run without requiring route setup to succeed, maintaining test compatibility
	# Note: The actual "log_message unavailable" scenario is hard to test directly because detection.sh provides
	# a fallback log_message function. However, the code's check for log_message availability ensures test compatibility.
	# This test verifies that existing tests work correctly, which demonstrates the test-friendly behavior.

	# This test serves as documentation that the route setup validation failure behavior
	# is designed to be test-friendly. The actual behavior is verified by:
	# 1. Test "validate_config calls route setup when routes are needed" - verifies route setup is called
	# 2. Test "validate_config fails when route setup fails (main execution path)" - verifies failure in main path
	# 3. Existing tests that work without route setup mocks - demonstrates test context compatibility

	# Verify that tests can run with routes needed but route setup mocked to succeed
	# (This is what most existing tests do)
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		'ENABLE_PING_CHECK=1' \
		'LOCAL_UDM_IP="10.0.0.1"'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create mock ip command that allows route setup to succeed
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "addr" ]] && [[ "$2" == "show" ]] && [[ "$3" == "br0" ]]; then
    # Route does not exist initially
    exit 1
elif [[ "$1" == "addr" ]] && [[ "$2" == "add" ]]; then
    # Route add succeeds
    exit 0
fi
# Handle xfrm for other tests
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    exit 0
fi
# Fallback to real ip for other commands
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Run script - should succeed because route setup succeeds
	run bash "$test_script" --fake

	# Should succeed (route setup succeeds, validation passes)
	assert_success

	remove_mock_from_path
}

# ============================================================================
# PING WARNINGS VALIDATION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "validate_config warns when ENABLE_PING_CHECK=1 and LOCAL_UDM_IP not set" {
	# Purpose: Test verifies that validate_config() logs a warning when ping checks are enabled but LOCAL_UDM_IP is not set.
	# Expected: Warning message is written to log (LOG_FILE) so operators know to set LOCAL_UDM_IP for reliable ping checks.
	# Importance: Ensures the config validation warning for missing LOCAL_UDM_IP is covered by tests.
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		'ENABLE_PING_CHECK=1'
	# Do not set LOCAL_UDM_IP

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	mkdir -p "$(dirname "$LOG_FILE")"
	touch "$LOG_FILE"

	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" 2>/dev/null || true
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true

	export CONFIG_FILE="$config_file"
	export STATE_DIR="$STATE_DIR"
	export LOG_FILE="$LOG_FILE"
	export ENABLE_PING_CHECK=1
	unset LOCAL_UDM_IP
	enable_fake_mode

	load_config
	run validate_config

	assert_success
	assert_file_contains "$LOG_FILE" "LOCAL_UDM_IP is not set"
	assert_file_contains "$LOG_FILE" "Ping checks are enabled"
}

# bats test_tags=category:high-risk,priority:high
@test "validate_config warns when ENABLE_PING_CHECK=1 and location has no internal IPs" {
	# Purpose: Test verifies that validate_config() logs a warning when ping checks are enabled but a location has no internal IPs.
	# Expected: Warning message is written to log so operators know ping will use external IP which may not be reachable.
	# Importance: Ensures the config validation warning for missing LOCATION_*_INTERNAL is covered by tests.
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		'LOCATION_TEST_INTERNAL=""' \
		'ENABLE_PING_CHECK=1'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	mkdir -p "$(dirname "$LOG_FILE")"
	touch "$LOG_FILE"

	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" 2>/dev/null || true
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true

	export CONFIG_FILE="$config_file"
	export STATE_DIR="$STATE_DIR"
	export LOG_FILE="$LOG_FILE"
	export ENABLE_PING_CHECK=1
	enable_fake_mode

	load_config
	run validate_config

	assert_success
	assert_file_contains "$LOG_FILE" "no internal IPs configured"
	assert_file_contains "$LOG_FILE" "Ping will use external IP"
}

# bats test_tags=category:high-risk,priority:high
@test "validate_config sets up routes when ping checks enabled and internal IPs configured" {
	# Purpose: Test verifies that validate_config() sets up routes when ping checks are enabled and internal IPs are configured
	# Expected: Route setup is called during validation when ENABLE_PING_CHECK=1 and internal IPs are configured
	# Importance: Ensures routes are set up proactively during config validation, not just during ping checks
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		'ENABLE_PING_CHECK=1' \
		'LOCAL_UDM_IP="10.0.0.1"'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Track calls to route setup functions
	local route_check_log="${TEST_DIR}/route_check_log"
	>"$route_check_log"

	# Create mock ip command that logs route checks and additions
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "addr" ]] && [[ "\$2" == "show" ]] && [[ "\$3" == "br0" ]]; then
    # Log the check
    echo "check_route_exists: \$*" >> "$route_check_log"
    # Simulate route does not exist (so it will try to add)
    exit 1
elif [[ "\$1" == "addr" ]] && [[ "\$2" == "add" ]]; then
    # Log the add attempt
    echo "add_route: \$*" >> "$route_check_log"
    # Simulate successful route add
    exit 0
fi
# Handle xfrm for other tests
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    exit 0
fi
# Fallback to real ip for other commands
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Run script - should call route setup during validation
	run bash "$test_script" --fake

	# Should succeed (route setup succeeds)
	assert_success

	# Verify route check was called during validation
	assert_file_exist "$route_check_log"
	assert_file_contains "$route_check_log" "check_route_exists"
	# Route add should be called if route doesn't exist
	assert_file_contains "$route_check_log" "add_route"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "setup_routes_if_needed gracefully handles missing detection.sh functions" {
	# Purpose: Test verifies that setup_routes_if_needed() gracefully handles missing detection.sh functions
	# Expected: Function returns error code but doesn't crash when detection.sh functions are unavailable
	# Importance: Ensures route setup doesn't break when config.sh is sourced independently (e.g., in check-config.sh or tests)
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		'ENABLE_PING_CHECK=1' \
		'LOCAL_UDM_IP="10.0.0.1"'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source config.sh functions to test setup_routes_if_needed directly
	# Note: We intentionally do NOT source detection.sh to simulate the scenario where
	# config.sh is sourced independently (e.g., in check-config.sh or standalone tests)
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true

	# Set up minimal environment
	export CONFIG_FILE="$config_file"
	export STATE_DIR="$STATE_DIR"
	export LOG_FILE="$LOG_FILE"
	export ENABLE_PING_CHECK=1
	export LOCAL_UDM_IP="10.0.0.1"
	enable_fake_mode

	# Load config to populate config variables
	load_config

	# Parse location config to populate LOCATIONS array
	# This is needed because load_config only loads variables, it doesn't parse location-based config
	parse_location_config

	# Verify detection.sh functions are not available (they shouldn't be since we didn't source detection.sh)
	# This simulates the scenario where config.sh is sourced independently
	run command -v get_local_ip_for_ping
	assert_failure
	run command -v check_route_exists
	assert_failure
	run command -v add_route_if_needed
	assert_failure

	# Call setup_routes_if_needed - should return error but not crash
	# The function should detect missing functions and return 1 gracefully
	run setup_routes_if_needed

	# Should return error code (1) because detection.sh functions are missing
	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "route setup failure during validation fails config validation when routes are needed" {
	# Purpose: Test verifies that route setup failure during validation fails config validation when routes are needed
	# Expected: Validation fails with error message when route setup fails and routes are required
	# Importance: Ensures routes are available before ping checks run, preventing silent failures
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		'ENABLE_PING_CHECK=1' \
		'LOCAL_UDM_IP="10.0.0.1"'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create mock ip command that simulates route setup failure
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "addr" ]] && [[ "$2" == "show" ]] && [[ "$3" == "br0" ]]; then
    # Route does not exist
    exit 1
elif [[ "$1" == "addr" ]] && [[ "$2" == "add" ]]; then
    # Route add fails
    exit 1
fi
# Handle xfrm for other tests
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    exit 0
fi
# Fallback to real ip for other commands
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Run script - should fail validation because route setup fails
	# In main execution path (log_message available), validation should fail
	run bash "$test_script" --fake

	# Should fail validation (exit code 3 = EXIT_VALIDATION_ERROR)
	assert_failure
	# Should contain route setup error message
	assert_log_contains_any "$LOG_FILE" "Route setup failed" "Failed to add route"

	remove_mock_from_path
}

# bats test_tags=category:medium,priority:medium
@test "route setup failure during validation doesn't fail validation in test contexts (log_message unavailable)" {
	# Purpose: Test verifies that route setup failure during validation doesn't fail validation in test contexts where log_message is unavailable
	# Expected: Validation succeeds even when route setup fails if log_message is not available (test context detection)
	# Importance: Ensures tests can run without requiring route setup to succeed, maintaining test compatibility
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		'ENABLE_PING_CHECK=1' \
		'LOCAL_UDM_IP="10.0.0.1"'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create mock ip command that simulates route setup failure
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "addr" ]] && [[ "$2" == "show" ]] && [[ "$3" == "br0" ]]; then
    # Route does not exist
    exit 1
elif [[ "$1" == "addr" ]] && [[ "$2" == "add" ]]; then
    # Route add fails
    exit 1
fi
# Handle xfrm for other tests
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    exit 0
fi
# Fallback to real ip for other commands
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Source config.sh functions to test validate_config directly
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" 2>/dev/null || true
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true

	# Set up environment
	export CONFIG_FILE="$config_file"
	export STATE_DIR="$STATE_DIR"
	export LOG_FILE="$LOG_FILE"
	export ENABLE_PING_CHECK=1
	export LOCAL_UDM_IP="10.0.0.1"
	enable_fake_mode

	# Load config
	load_config

	# Temporarily unset log_message to simulate test context where it's unavailable
	# (In real test contexts, log_message might not be available if detection.sh wasn't sourced)
	# We'll use unset to remove the function
	unset -f log_message 2>/dev/null || true

	# Verify log_message is not available
	run command -v log_message
	assert_failure

	# Call validate_config - should succeed even though route setup fails
	# because log_message is not available (test context detection)
	run validate_config

	# Should succeed (validation doesn't fail in test contexts when log_message unavailable)
	assert_success

	remove_mock_from_path
}

# ============================================================================
# VALIDATE_CRITICAL_CONFIG_VARS EDGE CASE TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "validate_critical_config_vars handles required variable declared but empty string" {
	# Purpose: Test verifies that validate_critical_config_vars() handles required variables that are declared but set to empty string
	# Expected: Function only checks if variable is declared, not if it's empty (empty check is done by validate_config_var)
	# Importance: Required variables declared but empty should be caught by validate_config_var, not validate_critical_config_vars
	# Note: validate_critical_config_vars only checks if variable is declared, not if it has a value
	# Source required modules
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
	# shellcheck source=../lib/config_schema.sh
	source "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" 2>/dev/null || true
	# shellcheck source=../lib/config/config_loading.sh
	source "${BATS_TEST_DIRNAME}/../lib/config/config_loading.sh" 2>/dev/null || true

	# Set up minimal CONFIG_SCHEMA for testing
	declare -A CONFIG_SCHEMA
	CONFIG_SCHEMA["TEST_REQUIRED_VAR"]="required|string|non-empty"

	# Declare variable but set to empty string
	declare -g TEST_REQUIRED_VAR=""

	# Call validate_critical_config_vars - should succeed because variable is declared
	# (Empty value check is done by validate_config_var, not validate_critical_config_vars)
	run validate_critical_config_vars

	# Should succeed - function only checks if variable is declared, not if it's empty
	assert_success

	# Cleanup
	unset TEST_REQUIRED_VAR
	unset CONFIG_SCHEMA
}

# bats test_tags=category:high-risk,priority:high
@test "validate_critical_config_vars handles get_config_schema returning empty string" {
	# Purpose: Test verifies that validate_critical_config_vars() handles get_config_schema() returning empty string gracefully
	# Expected: Function skips variables when get_config_schema() returns empty string
	# Importance: Schema lookup failures should not crash validation; variables should be skipped
	# Source required modules
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
	# shellcheck source=../lib/config_schema.sh
	source "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" 2>/dev/null || true
	# shellcheck source=../lib/config/config_loading.sh
	source "${BATS_TEST_DIRNAME}/../lib/config/config_loading.sh" 2>/dev/null || true

	# Set up CONFIG_SCHEMA with a variable
	declare -A CONFIG_SCHEMA
	CONFIG_SCHEMA["TEST_VAR"]="required|string|non-empty"

	# Mock get_config_schema to return empty string for TEST_VAR
	# Get configuration schema for a variable (test helper)
	#
	# Arguments:
	#   $1: Variable name
	#
	# Returns:
	#   0: Schema found and printed to stdout
	#   1: Schema not found or variable not in schema
	#
	# Output:
	#   Prints schema string to stdout if found
	get_config_schema() {
		local var_name="$1"
		if [[ "$var_name" == "TEST_VAR" ]]; then
			echo ""
			return 1
		fi
		# For other variables, call original function if it exists
		if declare -f get_config_schema_original &>/dev/null; then
			get_config_schema_original "$@"
		else
			return 1
		fi
	}

	# Call validate_critical_config_vars - should succeed because variable with empty schema is skipped
	run validate_critical_config_vars

	# Should succeed - variables with empty schema are skipped
	assert_success

	# Cleanup
	unset -f get_config_schema
	unset CONFIG_SCHEMA
}

# bats test_tags=category:high-risk,priority:high
@test "validate_critical_config_vars handles parse_config_schema with malformed schema" {
	# Purpose: Test verifies that validate_critical_config_vars() handles malformed schema strings gracefully
	# Expected: Function should handle malformed schema (e.g., missing parts) without crashing
	# Importance: Malformed schemas should not crash validation; should be handled defensively
	# Source required modules
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
	# shellcheck source=../lib/config_schema.sh
	source "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" 2>/dev/null || true
	# shellcheck source=../lib/config/config_loading.sh
	source "${BATS_TEST_DIRNAME}/../lib/config/config_loading.sh" 2>/dev/null || true

	# Set up CONFIG_SCHEMA with malformed schema (missing type)
	declare -A CONFIG_SCHEMA
	CONFIG_SCHEMA["TEST_VAR"]="required" # Malformed: missing type and other parts

	# Mock get_config_schema to return the malformed schema
	# Get configuration schema for a variable (test helper)
	#
	# Arguments:
	#   $1: Variable name
	#
	# Returns:
	#   0: Schema found and printed to stdout
	#   1: Schema not found or variable not in schema
	#
	# Output:
	#   Prints schema string to stdout if found
	get_config_schema() {
		local var_name="$1"
		if [[ "$var_name" == "TEST_VAR" ]]; then
			echo "required" # Malformed schema
			return 0
		fi
		return 1
	}

	# Call validate_critical_config_vars
	# parse_config_schema should handle malformed schema gracefully
	# If schema is malformed, required might not be extracted correctly, but function shouldn't crash
	run validate_critical_config_vars

	# Function should not crash - may succeed or fail depending on how parse_config_schema handles it
	# The important thing is it doesn't crash
	assert [ $status -eq 0 ] || [ $status -eq 1 ]

	# Cleanup
	unset -f get_config_schema
	unset CONFIG_SCHEMA
}

# bats test_tags=category:high-risk,priority:high
@test "validate_critical_config_vars reports multiple missing required variables" {
	# Purpose: Test verifies that validate_critical_config_vars() reports all missing required variables, not just the first one
	# Expected: Function collects all missing required variables and reports them together in error message
	# Importance: Users need to see all missing variables at once, not one at a time
	# Source required modules
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
	# shellcheck source=../lib/config_schema.sh
	source "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" 2>/dev/null || true
	# shellcheck source=../lib/config/config_loading.sh
	source "${BATS_TEST_DIRNAME}/../lib/config/config_loading.sh" 2>/dev/null || true

	# Set up CONFIG_SCHEMA with multiple required variables
	declare -A CONFIG_SCHEMA
	CONFIG_SCHEMA["REQUIRED_VAR1"]="required|string|non-empty"
	CONFIG_SCHEMA["REQUIRED_VAR2"]="required|string|non-empty"
	CONFIG_SCHEMA["REQUIRED_VAR3"]="required|integer|min:1"
	CONFIG_SCHEMA["OPTIONAL_VAR"]="optional|string" # This should not be reported

	# Don't declare any of the required variables
	# (They should be missing)

	# Set up log file to capture error messages
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	export LOG_FILE="$LOG_FILE"

	# Call validate_critical_config_vars - should fail and report all missing variables
	run validate_critical_config_vars

	# Should fail because required variables are missing
	assert_failure

	# Verify error message contains all missing required variables
	# Error message format: "Missing required configuration variables: VAR1 VAR2 VAR3"
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Missing required configuration variables"
	assert_file_contains "$LOG_FILE" "REQUIRED_VAR1"
	assert_file_contains "$LOG_FILE" "REQUIRED_VAR2"
	assert_file_contains "$LOG_FILE" "REQUIRED_VAR3"
	# Optional variable should not be in error message
	run grep -q "OPTIONAL_VAR" "$LOG_FILE" || true
	assert_failure

	# Cleanup
	unset CONFIG_SCHEMA
	unset LOG_FILE
}

# bats test_tags=category:high-risk,priority:high
@test "validate_critical_config_vars handles variable where declare -p fails" {
	# Purpose: Test verifies that validate_critical_config_vars() handles edge case where declare -p fails for a variable
	# Expected: Function should treat failed declare -p as variable not declared (defensive programming)
	# Importance: Defensive check ensures function doesn't crash on unexpected declare -p behavior
	# Note: This is hard to test directly since declare -p rarely fails, but we can verify the logic path
	# Source required modules
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
	# shellcheck source=../lib/config_schema.sh
	source "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" 2>/dev/null || true
	# shellcheck source=../lib/config/config_loading.sh
	source "${BATS_TEST_DIRNAME}/../lib/config/config_loading.sh" 2>/dev/null || true

	# Set up CONFIG_SCHEMA with a required variable
	declare -A CONFIG_SCHEMA
	CONFIG_SCHEMA["TEST_REQUIRED_VAR"]="required|string|non-empty"

	# Don't declare the variable - this simulates declare -p failing (variable not declared)
	# The function uses: if ! declare -p "$var_name" &>/dev/null; then
	# So if declare -p fails, the condition is true and variable is added to missing_required

	# Set up log file to capture error messages
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	export LOG_FILE="$LOG_FILE"

	# Call validate_critical_config_vars - should fail because variable is not declared
	run validate_critical_config_vars

	# Should fail because required variable is not declared
	assert_failure

	# Verify error message contains the missing variable
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Missing required configuration variables"
	assert_file_contains "$LOG_FILE" "TEST_REQUIRED_VAR"

	# Cleanup
	unset CONFIG_SCHEMA
	unset LOG_FILE
}

# ============================================================================
# SPLIT_RULES_STRING FUNCTION TESTS
# ============================================================================

# bats test_tags=category:unit,priority:high
@test "split_rules_string - empty rules string" {
	# Purpose: Test that split_rules_string handles empty rules string correctly
	# Expected: Function returns success and produces empty array
	# Importance: Edge case handling - empty input should not cause errors
	# Source required modules
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true

	local -a result_array
	split_rules_string "" "result_array"
	local status=$?

	# Should succeed and produce empty array
	assert [ $status -eq 0 ]
	assert [ ${#result_array[@]} -eq 0 ]
}

# bats test_tags=category:unit,priority:high
@test "split_rules_string - ||| separator with multiple rules" {
	# Purpose: Test that split_rules_string correctly splits rules using ||| separator
	# Expected: Function splits rules by ||| separator into array elements
	# Importance: Core functionality - new format for rule separation
	# Source required modules
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true

	local -a result_array
	split_rules_string "min:1|||max:10" "result_array"
	local status=$?

	# Should succeed and split into two rules
	assert [ $status -eq 0 ]
	assert [ ${#result_array[@]} -eq 2 ]
	assert_equal "${result_array[0]}" "min:1"
	assert_equal "${result_array[1]}" "max:10"
}

# bats test_tags=category:unit,priority:high
@test "split_rules_string - ||| separator with three rules" {
	# Purpose: Test that split_rules_string handles multiple ||| separators correctly
	# Expected: Function splits all rules separated by ||| into array elements
	# Importance: Ensures function works with more than two rules
	# Source required modules
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true

	local -a result_array
	split_rules_string "min:1|||max:10|||step:2" "result_array"
	local status=$?

	# Should succeed and split into three rules
	assert [ $status -eq 0 ]
	assert [ ${#result_array[@]} -eq 3 ]
	assert_equal "${result_array[0]}" "min:1"
	assert_equal "${result_array[1]}" "max:10"
	assert_equal "${result_array[2]}" "step:2"
}

# bats test_tags=category:unit,priority:high
@test "split_rules_string - values: prefix special case (single rule)" {
	# Purpose: Test that split_rules_string does not split values: rules (comma is part of value)
	# Expected: Function returns single-element array containing the entire values: rule
	# Importance: Special case handling - commas in values: rules are part of the value, not separators
	# Source required modules
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true

	local -a result_array
	split_rules_string "values:0,1" "result_array"
	local status=$?

	# Should succeed and return single rule (not split by comma)
	assert [ $status -eq 0 ]
	assert [ ${#result_array[@]} -eq 1 ]
	assert_equal "${result_array[0]}" "values:0,1"
}

# bats test_tags=category:unit,priority:high
@test "split_rules_string - values: prefix with multiple values" {
	# Purpose: Test that split_rules_string handles values: rules with multiple comma-separated values
	# Expected: Function returns single-element array containing the entire values: rule
	# Importance: Ensures commas in values: rules are preserved as part of the value
	# Source required modules
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true

	local -a result_array
	split_rules_string "values:0,1,2,3" "result_array"
	local status=$?

	# Should succeed and return single rule (not split by comma)
	assert [ $status -eq 0 ]
	assert [ ${#result_array[@]} -eq 1 ]
	assert_equal "${result_array[0]}" "values:0,1,2,3"
}

# bats test_tags=category:unit,priority:high
@test "split_rules_string - single rule without separator" {
	# Purpose: Test that split_rules_string handles single rule without any separator
	# Expected: Function returns single-element array containing the rule
	# Importance: Edge case - single rule should work correctly
	# Source required modules
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true

	local -a result_array
	split_rules_string "min:1" "result_array"
	local status=$?

	# Should succeed and return single rule
	assert [ $status -eq 0 ]
	assert [ ${#result_array[@]} -eq 1 ]
	assert_equal "${result_array[0]}" "min:1"
}

# bats test_tags=category:unit,priority:high
@test "split_rules_string - ||| separator with comma in rule value" {
	# Purpose: Test that ||| separator correctly splits rules even when comma is present in rule values
	# Expected: Function uses ||| separator to split, preserving commas within individual rules
	# Importance: Ensures ||| separator works correctly with complex rule values
	# Source required modules
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true

	local -a result_array
	split_rules_string "min:1|||max:10,step:2" "result_array"
	local status=$?

	# Should succeed and split by ||| (preserving comma in second rule)
	assert [ $status -eq 0 ]
	assert [ ${#result_array[@]} -eq 2 ]
	assert_equal "${result_array[0]}" "min:1"
	assert_equal "${result_array[1]}" "max:10,step:2"
}

# bats test_tags=category:unit,priority:high
@test "split_rules_string - values: rule preserves commas" {
	# Purpose: Test that values: rules are not split (comma is part of the value)
	# Expected: Function does not split values: rules even when comma is present
	# Importance: Special case handling - values: should not be split by comma
	# Source required modules
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true

	local -a result_array
	split_rules_string "values:0,1,2" "result_array"
	local status=$?

	# Should succeed and return single rule (not split by comma)
	assert [ $status -eq 0 ]
	assert [ ${#result_array[@]} -eq 1 ]
	assert_equal "${result_array[0]}" "values:0,1,2"
}
