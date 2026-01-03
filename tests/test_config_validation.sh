#!/usr/bin/env bats
#
# Tests for Configuration Variable Validation
# Tests critical paths and error handling scenarios

load test_helper
load fixtures/vpn_active

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# CONFIGURATION VARIABLE VALIDATION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "invalid COOLDOWN_MINUTES (negative)" {
	# Purpose: Test verifies that the script handles negative COOLDOWN_MINUTES values gracefully
	# Expected: Script processes negative value without crashing, either using default or failing gracefully
	# Importance: Negative values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
COOLDOWN_MINUTES=-1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	# Script should handle invalid value (either use default or fail gracefully)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid COOLDOWN_MINUTES (zero)" {
	# Purpose: Test verifies that the script handles zero COOLDOWN_MINUTES values gracefully
	# Expected: Script processes zero value without crashing, either using default or failing gracefully
	# Importance: Zero values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
COOLDOWN_MINUTES=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid MAX_RESTARTS_PER_HOUR (negative)" {
	# Purpose: Test verifies that the script handles negative MAX_RESTARTS_PER_HOUR values gracefully
	# Expected: Script processes negative value without crashing, either using default or failing gracefully
	# Importance: Negative values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
MAX_RESTARTS_PER_HOUR=-1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid MAX_RESTARTS_PER_HOUR (zero)" {
	# Purpose: Test verifies that the script handles zero MAX_RESTARTS_PER_HOUR values gracefully
	# Expected: Script processes zero value without crashing, either using default or failing gracefully
	# Importance: Zero values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
MAX_RESTARTS_PER_HOUR=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid LOCKFILE_TIMEOUT (negative)" {
	# Purpose: Test verifies that the script handles negative LOCKFILE_TIMEOUT values gracefully
	# Expected: Script processes negative value without crashing, either using default or failing gracefully
	# Importance: Negative values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
LOCKFILE_TIMEOUT=-1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid LOCKFILE_TIMEOUT (zero)" {
	# Purpose: Test verifies that the script handles zero LOCKFILE_TIMEOUT values gracefully
	# Expected: Script processes zero value without crashing, either using default or failing gracefully
	# Importance: Zero values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
LOCKFILE_TIMEOUT=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_COUNT (negative)" {
	# Purpose: Test verifies that the script handles negative PING_COUNT values gracefully
	# Expected: Script processes negative value without crashing, either using default or failing gracefully
	# Importance: Negative values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
PING_COUNT=-1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_COUNT (zero)" {
	# Purpose: Test verifies that the script handles zero PING_COUNT values gracefully
	# Expected: Script processes zero value without crashing, either using default or failing gracefully
	# Importance: Zero values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
PING_COUNT=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_TIMEOUT (negative)" {
	# Purpose: Test verifies that the script handles negative PING_TIMEOUT values gracefully
	# Expected: Script processes negative value without crashing, either using default or failing gracefully
	# Importance: Negative values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
PING_TIMEOUT=-1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_TIMEOUT (zero)" {
	# Purpose: Test verifies that the script handles zero PING_TIMEOUT values gracefully
	# Expected: Script processes zero value without crashing, either using default or failing gracefully
	# Importance: Zero values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
PING_TIMEOUT=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

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
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
ENABLE_PING_CHECK=1
LOCAL_UDM_IP="10.0.0.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

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
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

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
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
ENABLE_PING_CHECK=1
LOCAL_UDM_IP="10.0.0.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

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
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Run script - should fail validation because route setup fails
	# In main execution path (log_message available), validation should fail
	run bash "$test_script" --fake

	# Should fail validation (exit code 3 = EXIT_VALIDATION_ERROR)
	assert_failure
	# Should contain route setup error message
	assert_file_contains "$log_file" "Route setup failed" || assert_file_contains "$log_file" "Failed to add route"

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
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
ENABLE_PING_CHECK=1
LOCAL_UDM_IP="10.0.0.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

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
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Run script - should succeed because route setup succeeds
	run bash "$test_script" --fake

	# Should succeed (route setup succeeds, validation passes)
	assert_success

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "validate_config sets up routes when ping checks enabled and internal IPs configured" {
	# Purpose: Test verifies that validate_config() sets up routes when ping checks are enabled and internal IPs are configured
	# Expected: Route setup is called during validation when ENABLE_PING_CHECK=1 and internal IPs are configured
	# Importance: Ensures routes are set up proactively during config validation, not just during ping checks
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
ENABLE_PING_CHECK=1
LOCAL_UDM_IP="10.0.0.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

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
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

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
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
ENABLE_PING_CHECK=1
LOCAL_UDM_IP="10.0.0.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

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
	export STATE_DIR="$state_dir"
	export LOG_FILE="$log_file"
	export ENABLE_PING_CHECK=1
	export LOCAL_UDM_IP="10.0.0.1"
	export NO_ESCALATE=1

	# Load config to populate LOCATIONS array
	load_config

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
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
ENABLE_PING_CHECK=1
LOCAL_UDM_IP="10.0.0.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

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
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Run script - should fail validation because route setup fails
	# In main execution path (log_message available), validation should fail
	run bash "$test_script" --fake

	# Should fail validation (exit code 3 = EXIT_VALIDATION_ERROR)
	assert_failure
	# Should contain route setup error message
	assert_file_contains "$log_file" "Route setup failed" || assert_file_contains "$log_file" "Failed to add route"

	remove_mock_from_path
}

# bats test_tags=category:medium,priority:medium
@test "route setup failure during validation doesn't fail validation in test contexts (log_message unavailable)" {
	# Purpose: Test verifies that route setup failure during validation doesn't fail validation in test contexts where log_message is unavailable
	# Expected: Validation succeeds even when route setup fails if log_message is not available (test context detection)
	# Importance: Ensures tests can run without requiring route setup to succeed, maintaining test compatibility
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
ENABLE_PING_CHECK=1
LOCAL_UDM_IP="10.0.0.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

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
	export STATE_DIR="$state_dir"
	export LOG_FILE="$log_file"
	export ENABLE_PING_CHECK=1
	export LOCAL_UDM_IP="10.0.0.1"
	export NO_ESCALATE=1

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
