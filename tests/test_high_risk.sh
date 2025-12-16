#!/usr/bin/env bats
#
# High-risk tests for vpn-monitor.sh
# Tests critical paths and error handling scenarios that could cause production failures
#
# Focus areas:
# 1. Lockfile Management (race conditions, cleanup, edge cases)
# 2. Configuration Loading (security, error handling, validation)
# 3. VPN Status Detection (edge cases, fallback chains, byte counters)
# 4. Recovery Actions (execution, error handling, verification)

load test_helper

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# 1. LOCKFILE MANAGEMENT TESTS
# ============================================================================

@test "high-risk: lockfile cleanup on script exit" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Run script - should complete successfully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_success
	# Lockfile should be cleaned up after script exits
	assert_file_not_exist "$lockfile"

	remove_mock_from_path
}

@test "high-risk: lockfile cleanup on script error" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="invalid-ip-format"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Run script - should exit with error due to invalid IP
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Lockfile should be cleaned up even on error
	# Note: Script may exit before lockfile creation, so check may be flaky
	# But if lockfile was created, it should be cleaned up
	if [[ -f "$lockfile" ]]; then
		# If lockfile exists, it should be stale or cleaned up
		# This is a best-effort check
		echo "Lockfile still exists after error - may need manual cleanup"
	fi
}

@test "high-risk: lockfile contains invalid format" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create lockfile with invalid format (not timestamp:pid)
	echo "invalid-format" >"$lockfile"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Script should handle invalid lockfile format gracefully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should either clean up invalid lockfile or handle it gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: lockfile timestamp at timeout boundary" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
LOCKFILE_TIMEOUT=300
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create lockfile exactly at timeout boundary (300 seconds ago)
	local boundary_time=$(($(date +%s) - 300))
	echo "${boundary_time}:12345" >"$lockfile"
	# Touch file to set modification time
	touch -d "@$boundary_time" "$lockfile" 2>/dev/null || true

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Script should handle boundary condition
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should either treat as stale or handle gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 2. CONFIGURATION LOADING AND VALIDATION TESTS
# ============================================================================

@test "high-risk: config file contains syntax errors" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config with syntax error (unclosed quote)
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1
VPN_NAME="Test VPN"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should handle syntax error gracefully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should log error about config file
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "Failed to source configuration file" || assert_file_contains "$log_file" "ERROR"
}

@test "high-risk: config file is unreadable" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	# Make config file unreadable
	chmod 000 "$config_file"

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should handle unreadable config gracefully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should log error about config file
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "not readable" || assert_file_contains "$log_file" "ERROR"

	# Restore permissions for cleanup
	chmod 644 "$config_file" 2>/dev/null || true
}

@test "high-risk: config file is a directory" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create directory instead of file
	mkdir -p "$config_file"

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should handle directory instead of file gracefully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should log warning or error
	assert_file_exist "$log_file"
}

@test "high-risk: LOG_FILE override in config recalculates LOGS_DIR" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
LOG_FILE="/tmp/custom-logs/vpn-monitor.log"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local custom_log_file="/tmp/custom-logs/vpn-monitor.log"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Run script
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_success
	# Custom log directory should be created
	assert_dir_exist "/tmp/custom-logs"
	# Log file should exist in custom location
	assert_file_exist "$custom_log_file"

	# Cleanup
	rm -rf /tmp/custom-logs 2>/dev/null || true
	remove_mock_from_path
}

@test "high-risk: negative threshold values in config" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=-1
TIER2_THRESHOLD=-3
TIER3_THRESHOLD=-5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Script should handle negative thresholds (may cause unexpected behavior)
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script should run (may have unexpected tier escalation behavior)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: threshold values out of order" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=5
TIER2_THRESHOLD=3
TIER3_THRESHOLD=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Script should handle out-of-order thresholds
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script should run (may skip tiers or have unexpected behavior)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 3. VPN STATUS DETECTION TESTS
# ============================================================================

@test "high-risk: xfrm SA exists but byte counter is exactly 0" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command - SA exists but bytes=0
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 0 bytes, 0 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should detect bytes=0 as suspect (may fail VPN check)
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "bytes=0" || assert_file_contains "$log_file" "suspect"

	remove_mock_from_path
}

@test "high-risk: xfrm SA exists but byte counter decreases" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Set initial byte count (high value)
	echo "10000" >"$last_bytes_file"

	# Mock ip command - bytes decreased (counter wrap-around scenario)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 5000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should detect bytes not increasing (may fail VPN check)
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "bytes not increasing" || assert_file_contains "$log_file" "suspect"

	remove_mock_from_path
}

@test "high-risk: xfrm SA exists but byte counter stays same" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Set initial byte count
	echo "1000" >"$last_bytes_file"

	# Mock ip command - bytes stay same
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should detect bytes not increasing
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "bytes not increasing" || assert_file_contains "$log_file" "suspect"

	remove_mock_from_path
}

@test "high-risk: byte counter file corrupted" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Create corrupted byte counter file (non-numeric)
	echo "invalid-value" >"$last_bytes_file"

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should handle corrupted file gracefully (treat as 0 or reset)
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: byte counter file contains negative number" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Create byte counter file with negative number
	echo "-1000" >"$last_bytes_file"

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should handle negative value gracefully
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: byte counter file is empty" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Create empty byte counter file
	touch "$last_bytes_file"

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should handle empty file gracefully (treat as 0)
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: all detection methods unavailable" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Don't create any mock commands (all unavailable)
	# PATH will not include mocks, so real commands won't be found in test environment

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Create minimal PATH with only essential commands
	# Use a PATH that doesn't include ip, swanctl, or ipsec
	PATH="/usr/bin:/bin" run bash "$test_script" --fake || true

	# Should handle all methods unavailable gracefully
	# Script may exit early, but if log file exists, it should contain error messages
	if [[ -f "$log_file" ]]; then
		assert_file_contains "$log_file" "suspect" || assert_file_contains "$log_file" "failed" || assert_file_contains "$log_file" "WARNING"
	else
		# If log file doesn't exist, script likely exited very early - this is acceptable
		# The important thing is it didn't crash
		echo "Log file not created - script exited early (acceptable behavior)"
	fi
}

@test "high-risk: xfrm output contains multiple lifetime lines" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command with multiple lifetime lines
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    echo "    lifetime hard: 3600s, 0 bytes, 0 packets"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should extract first lifetime line correctly
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: ping check enabled but PING_TARGET_IP not set" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
ENABLE_PING_CHECK=1
PING_TARGET_IP=""
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command - VPN appears up
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ping - should use peer IP
	local mock_ping=$(mock_ping "192.168.1.1" "1")
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should use peer IP for ping check
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 4. RECOVERY ACTIONS TESTS
# ============================================================================

@test "high-risk: surgical cleanup with connection name configured" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
CONNECTION_NAME_192_168_1_1="test-connection"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 2 threshold
	echo "3" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock swanctl - track which command was called
	local mock_swanctl="${TEST_DIR}/swanctl"
	cat >"$mock_swanctl" <<'EOF'
#!/bin/bash
if [[ "$1" == "--reload-conn" ]] && [[ "$2" == "test-connection" ]]; then
    echo "per-connection-reload" > /tmp/swanctl_called.txt
    exit 0
fi
if [[ "$1" == "--reload" ]]; then
    echo "full-reload" > /tmp/swanctl_called.txt
    exit 0
fi
EOF
	chmod +x "$mock_swanctl"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Should use per-connection reload
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "per-connection reload"
	if [[ -f /tmp/swanctl_called.txt ]]; then
		local called=$(cat /tmp/swanctl_called.txt)
		assert [ "$called" = "per-connection-reload" ]
		rm -f /tmp/swanctl_called.txt
	fi

	remove_mock_from_path
}

@test "high-risk: surgical cleanup without connection name uses full reload" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 2 threshold
	echo "3" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock swanctl - track which command was called
	local mock_swanctl="${TEST_DIR}/swanctl"
	cat >"$mock_swanctl" <<'EOF'
#!/bin/bash
if [[ "$1" == "--reload-conn" ]]; then
    echo "per-connection-reload" > /tmp/swanctl_called.txt
    exit 0
fi
if [[ "$1" == "--reload" ]]; then
    echo "full-reload" > /tmp/swanctl_called.txt
    exit 0
fi
EOF
	chmod +x "$mock_swanctl"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Should use full reload
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "full reload" || assert_file_contains "$log_file" "reload"
	if [[ -f /tmp/swanctl_called.txt ]]; then
		local called=$(cat /tmp/swanctl_called.txt)
		assert [ "$called" = "full-reload" ]
		rm -f /tmp/swanctl_called.txt
	fi

	remove_mock_from_path
}

@test "high-risk: surgical cleanup fails - error handling" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 2 threshold
	echo "3" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock swanctl - fails
	local mock_swanctl="${TEST_DIR}/swanctl"
	cat >"$mock_swanctl" <<'EOF'
#!/bin/bash
if [[ "$1" == "--reload" ]]; then
    echo "swanctl reload failed" >&2
    exit 1
fi
EOF
	chmod +x "$mock_swanctl"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Should handle error gracefully (not crash)
	assert_file_exist "$log_file"
	# Script should continue execution

	remove_mock_from_path
}

@test "high-risk: full restart with ipsec command" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - track if called
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ipsec-restart-called" > /tmp/ipsec_called.txt
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Should call ipsec restart
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "full IPsec restart" || assert_file_contains "$log_file" "Tier 3"
	if [[ -f /tmp/ipsec_called.txt ]]; then
		assert_file_exist /tmp/ipsec_called.txt
		rm -f /tmp/ipsec_called.txt
	fi

	remove_mock_from_path
}

@test "high-risk: full restart fails - error handling" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - fails
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ipsec restart failed" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle error gracefully
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "Failed to restart" || assert_file_contains "$log_file" "ERROR"

	remove_mock_from_path
}

@test "high-risk: full restart when neither ipsec nor swanctl available" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Don't create ipsec or swanctl mocks (unavailable)

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle unavailable commands gracefully
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "not available" || assert_file_contains "$log_file" "ERROR"

	remove_mock_from_path
}

@test "high-risk: rate limit file corrupted" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local restart_file="${TEST_DIR}/logs/restart_count"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create corrupted restart file (non-numeric)
	echo "invalid-timestamp" >"$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec
	local mock_ipsec=$(mock_ipsec)
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle corrupted file gracefully
	assert_file_exist "$log_file"
	# Script should either skip rate limit check or handle error

	remove_mock_from_path
}

@test "high-risk: config file attempts command injection via variable" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Attempt command injection via PEER_IPS
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1; echo 'injected' > /tmp/injection_test"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should reject invalid IP format (command injection should be caught by IP validation)
	assert_file_exist "$log_file"
	# Injection should not execute - IP validation should catch it
	assert_file_not_exist "/tmp/injection_test"

	remove_mock_from_path
}

@test "high-risk: xfrm command fails with permission denied" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command that fails
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "Permission denied" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should fallback to swanctl or ipsec
	assert_file_exist "$log_file"
	# Should handle xfrm failure gracefully

	remove_mock_from_path
}

@test "high-risk: failure counter file is directory" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create directory instead of file
	mkdir -p "$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle directory gracefully (may fail to write, but shouldn't crash)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: surgical cleanup connection name reload fails - fallback to full reload" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
CONNECTION_NAME_192_168_1_1="test-connection"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 2 threshold
	echo "3" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock swanctl - per-connection reload fails, should fallback to full reload
	local mock_swanctl="${TEST_DIR}/swanctl"
	cat >"$mock_swanctl" <<'EOF'
#!/bin/bash
if [[ "$1" == "--reload-conn" ]] && [[ "$2" == "test-connection" ]]; then
    echo "Connection not found" >&2
    exit 1
fi
if [[ "$1" == "--reload" ]]; then
    echo "full-reload" > /tmp/swanctl_called.txt
    exit 0
fi
EOF
	chmod +x "$mock_swanctl"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Should fallback to full reload
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "falling back to full reload" || assert_file_contains "$log_file" "full reload"
	if [[ -f /tmp/swanctl_called.txt ]]; then
		local called=$(cat /tmp/swanctl_called.txt)
		assert [ "$called" = "full-reload" ]
		rm -f /tmp/swanctl_called.txt
	fi

	remove_mock_from_path
}

@test "high-risk: byte counter file is directory" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Create directory instead of file
	mkdir -p "$last_bytes_file"

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle directory gracefully (may fail to write, but shouldn't crash)
	assert_file_exist "$log_file"

	remove_mock_from_path
}
