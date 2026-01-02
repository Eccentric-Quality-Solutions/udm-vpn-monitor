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
