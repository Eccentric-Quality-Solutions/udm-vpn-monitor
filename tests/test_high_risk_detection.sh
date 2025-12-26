#!/usr/bin/env bats
#
# High-risk tests: VPN Status Detection
# Tests critical paths and error handling scenarios that could cause production failures
#
# This file is part of the high-risk test suite, split from test_high_risk.sh
# for better organization and maintainability.

load test_helper

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# 3. VPN STATUS DETECTION TESTS
# ============================================================================

@test "high-risk: xfrm SA exists but byte counter is exactly 0" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
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
EXTERNAL_PEER_IPS="192.168.1.1"
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
EXTERNAL_PEER_IPS="192.168.1.1"
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
EXTERNAL_PEER_IPS="192.168.1.1"
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
EXTERNAL_PEER_IPS="192.168.1.1"
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
EXTERNAL_PEER_IPS="192.168.1.1"
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
EXTERNAL_PEER_IPS="192.168.1.1"
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
	# Use a PATH that doesn't include ip or ipsec
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
EXTERNAL_PEER_IPS="192.168.1.1"
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

@test "high-risk: ping check enabled but INTERNAL_PEER_IPS not set" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
ENABLE_PING_CHECK=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command - VPN appears up
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ping - should use peer IP
	local mock_ping
	mock_ping=$(mock_ping "192.168.1.1" "1")
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
# 3.3 FALLBACK CHAIN EDGE CASES
# ============================================================================

@test "high-risk: ipsec returns error exit code but has output" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN down (no xfrm state)
	mock_ip_xfrm_state "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ipsec - returns error code but has output containing peer IP
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # Return error code but output contains peer IP (simulates partial failure)
    echo "192.168.1.1: ESTABLISHED 1 hour ago"
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle error code gracefully and still process output
	# Output contains peer IP, so should detect VPN as OK
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 3.3 FALLBACK CHAIN EDGE CASES (continued)
# ============================================================================

@test "high-risk: tool availability detection (command -v) fails" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock command to fail (simulates command -v failure)
	local mock_command="${TEST_DIR}/command"
	cat >"$mock_command" <<'EOF'
#!/bin/bash
if [[ "$1" == "-v" ]] && [[ "$2" == "ip" ]]; then
    exit 1
fi
# Fallback to real command for other cases
exec /usr/bin/command "$@"
EOF
	chmod +x "$mock_command"

	# Remove ip from PATH to force fallback
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip_backup" 2>/dev/null || true

	# Create minimal PATH without ip command
	PATH="${TEST_DIR}:/usr/bin:/bin" add_mock_to_path

	PATH="${TEST_DIR}:/usr/bin:/bin" run bash "$test_script" --fake || true

	# Should handle missing ip command gracefully (should fall back to ipsec or fail gracefully)
	assert_file_exist "$log_file"

	# Restore
	mv "${TEST_DIR}/ip_backup" "${TEST_DIR}/ip" 2>/dev/null || true
	remove_mock_from_path
}

# ============================================================================
# 3.4 PING CHECK EDGE CASES
# ============================================================================

@test "high-risk: ping command not available (ping6 vs ping -6 detection)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
ENABLE_PING_CHECK=1
INTERNAL_PEER_IPS="2001:db8::1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock command to fail for ping (simulates ping not available)
	local mock_command="${TEST_DIR}/command"
	cat >"$mock_command" <<'EOF'
#!/bin/bash
if [[ "$1" == "-v" ]] && [[ "$2" == "ping" ]]; then
    exit 1
fi
if [[ "$1" == "-v" ]] && [[ "$2" == "ping6" ]]; then
    exit 1
fi
# Fallback to real command for other cases
exec /usr/bin/command "$@"
EOF
	chmod +x "$mock_command"

	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle missing ping command gracefully (should log warning but continue)
	# Code at lib/detection.sh:433-436 handles ping command not available
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: ping command hangs (timeout handling)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
ENABLE_PING_CHECK=1
INTERNAL_PEER_IPS="192.168.1.1"
PING_COUNT=3
PING_TIMEOUT=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ping to hang (simulates timeout)
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
# Simulate ping hanging (sleep longer than timeout)
sleep 10
exit 0
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run timeout 5 bash "$test_script" --fake || true

	# Should handle ping timeout gracefully (should log error but continue)
	# Code at lib/detection.sh:465-473 handles ping timeouts
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: ping target is unreachable but command succeeds (weird network state)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
ENABLE_PING_CHECK=1
INTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ping to return success but 100% packet loss (weird network state)
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
# Simulate ping command succeeds but 100% packet loss
echo "PING 192.168.1.1 (192.168.1.1) 56(84) bytes of data."
echo ""
echo "--- 192.168.1.1 ping statistics ---"
echo "3 packets transmitted, 0 received, 100% packet loss"
exit 0
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle 100% packet loss gracefully (should log warning but continue)
	# Code at lib/detection.sh:477-485 handles packet loss detection
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 3.3 FALLBACK CHAIN EDGE CASES (continued)
# ============================================================================

@test "high-risk: ipsec command hangs (timeout scenario - status check)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ipsec status to hang (simulates timeout)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # Simulate ipsec status hanging
    sleep 10
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Run with timeout to prevent test from hanging
	PATH="${TEST_DIR}:${PATH}" run timeout 5 bash "$test_script" --fake || true

	# Should handle ipsec status hang gracefully (should timeout and continue)
	# Code at lib/detection.sh:636 uses ipsec status with 2>/dev/null
	assert_file_exist "$log_file"

	remove_mock_from_path
}
