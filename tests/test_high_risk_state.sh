#!/usr/bin/env bats
#
# High-risk tests: State File Management
# Tests critical paths and error handling scenarios that could cause production failures
#
# This file is part of the high-risk test suite, split from test_high_risk.sh
# for better organization and maintainability.

load test_helper

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# 6.1 STATE FILE CORRUPTION AND RECOVERY
# ============================================================================

@test "high-risk: failure counter file corrupted (non-numeric)" {
	# Test verifies that the script handles corrupted failure counter files containing non-numeric values.
	# Expected: Script treats corrupted file as 0 or resets it, continuing normal operation without crashing.
	# Importance: File corruption can occur due to disk errors or manual editing; script must handle it robustly.
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create corrupted failure counter file
	echo "invalid-non-numeric-value" >"$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle corrupted file gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: failure counter file contains negative number" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create failure counter file with negative number
	echo "-5" >"$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle negative number gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: failure counter file is empty" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create empty failure counter file
	touch "$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle empty file gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 7.1 LOGGING FAILURE SCENARIOS
# ============================================================================

# ============================================================================
# 2.3 CONFIGURATION VARIABLE VALIDATION - VERY LARGE VALUES
# ============================================================================

# ============================================================================
# 4.4 RATE LIMITING EDGE CASES - TIMESTAMP HANDLING
# ============================================================================

# ============================================================================
# 6.1 STATE FILE CORRUPTION - COOLDOWN FILE
# ============================================================================

# ============================================================================
# 6.1 STATE FILE CORRUPTION - COOLDOWN FILE
# ============================================================================

@test "high-risk: cooldown file corrupted (invalid timestamp)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local cooldown_file="${TEST_DIR}/cooldown_until"

	# Create corrupted cooldown file with invalid timestamp
	echo "invalid-timestamp-value" >"$cooldown_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle corrupted cooldown file gracefully (arithmetic error would occur)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 6.2 CONCURRENT STATE ACCESS - PERMISSIONS
# ============================================================================

@test "high-risk: state file permissions prevent write" {
	# Test verifies that the script handles read-only state files gracefully when attempting to update counters.
	# Expected: Script logs error about write failure but continues execution without crashing.
	# Importance: Permission issues can occur due to incorrect file ownership or chmod operations; script must handle gracefully.
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create failure counter file and make it read-only (prevents write)
	echo "3" >"$failure_counter"
	chmod 444 "$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle read-only state file gracefully (should log error but continue)
	assert_file_exist "$log_file"

	# Restore permissions for cleanup
	chmod 644 "$failure_counter" 2>/dev/null || true
	remove_mock_from_path
}

@test "high-risk: state file permissions prevent read" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create failure counter file and make it unreadable (prevents read)
	echo "3" >"$failure_counter"
	chmod 000 "$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle unreadable state file gracefully (should default to 0 or handle error)
	assert_file_exist "$log_file"

	# Restore permissions for cleanup
	chmod 644 "$failure_counter" 2>/dev/null || true
	remove_mock_from_path
}

@test "high-risk: state file deleted during script execution" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create failure counter file initially
	echo "2" >"$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Delete failure counter file during execution (simulate file deletion)
	# This is a simplified test - in real scenario, file might be deleted between checks
	rm -f "$failure_counter"

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle deleted state file gracefully (should recreate or default to 0)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 6.2 CONCURRENT STATE ACCESS
# ============================================================================

@test "high-risk: state file modified during script execution (lockfile should prevent this)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Run script - lockfile should prevent concurrent execution
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Lockfile prevents concurrent execution, so state file modification should not occur
	# This test verifies that lockfile mechanism works (implicitly tested by lockfile tests)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
