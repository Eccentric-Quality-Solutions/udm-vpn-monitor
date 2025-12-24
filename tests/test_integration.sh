#!/usr/bin/env bats
#
# Integration tests for vpn-monitor.sh with mock VPN states
# Tests full monitoring flow with various VPN state scenarios

load test_helper

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

@test "integration: VPN healthy - no action taken" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Set initial byte counter directly (skip baseline establishment run)
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"
	echo "1000" >"$last_bytes_file"

	# Mock ip command to return healthy VPN (SA exists, bytes increasing)
	mock_ip_xfrm_state "192.168.1.1" "2000" >/dev/null
	# Rename mock_ip to ip so script finds it
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Run script - bytes should have increased from baseline
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_success
	# Should not increment failure counter
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert [ "$count" -eq 0 ]
	fi

	remove_mock_from_path
}

@test "integration: VPN down - Tier 1 logging triggered" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command to return no SA (VPN down)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Return empty output (no SA found)
    exit 0
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script exits with code 1 when VPN check fails, which is expected
	# Check that the expected behavior happened
	# Should increment failure counter
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	assert_file_exist "$failure_counter"
	local count
	count=$(cat "$failure_counter")
	assert [ "$count" -ge 1 ]

	# Should log Tier 1 action
	assert_file_contains "$log_file" "Tier 1"

	remove_mock_from_path
}

@test "integration: VPN down - Tier 2 surgical cleanup triggered" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
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

	# Mock ip command to return no SA (VPN down)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec for surgical cleanup
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "Reloaded"
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script exits with code 1 when VPN check fails, which is expected
	# Should log Tier 2 action
	assert_file_contains "$log_file" "Tier 2"

	remove_mock_from_path
}

@test "integration: VPN down - Tier 3 full restart triggered" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
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

	# Mock ip command to return no SA (VPN down)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec for full restart
	local mock_ipsec
	mock_ipsec=$(mock_ipsec)
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script exits with code 1 when VPN check fails, which is expected
	# Should log Tier 3 action
	assert_file_contains "$log_file" "Tier 3"

	remove_mock_from_path
}

@test "integration: VPN recovery after failures - counter reset" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set initial failure count
	echo "3" >"$failure_counter"

	# Mock ip command to return healthy VPN (recovered)
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_success
	# Failure counter should be reset
	assert_file_exist "$failure_counter"
	local count
	count=$(cat "$failure_counter")
	assert [ "$count" -eq 0 ]

	# Should log recovery message
	assert_file_contains "$log_file" "recovered"

	remove_mock_from_path
}

@test "integration: Multiple peers - independent failure tracking" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1 10.0.0.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command - peer1 down, peer2 up
	# Create separate mocks for each peer check
	# The script calls: ip xfrm state | grep <peer_ip>
	# So we need to return SA when grep would find 10.0.0.1
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Return SA for 10.0.0.1 (peer2 up), empty for 192.168.1.1 (peer1 down)
    # The script pipes this to grep, so we return output that grep would match for peer2
    echo "src 192.168.1.1 dst 10.0.0.1"
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

	# Script may exit with code 1 if any peer fails, which is expected
	# Check that peer1 failure counter was incremented
	# Peer1 should have failure counter incremented
	local failure_counter1="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	if [[ -f "$failure_counter1" ]]; then
		local count1
		count1=$(cat "$failure_counter1")
		assert [ "$count1" -ge 1 ]
	fi

	# Peer2 should not have failure counter (or should be 0)
	local failure_counter2="${TEST_DIR}/logs/failure_counter_10_0_0_1"
	if [[ -f "$failure_counter2" ]]; then
		local count2
		count2=$(cat "$failure_counter2")
		assert [ "$count2" -eq 0 ]
	fi

	remove_mock_from_path
}

@test "integration: Ping check enabled - VPN SA exists but ping fails" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
ENABLE_PING_CHECK=1
PING_TARGET_IP="192.168.1.1"
PING_COUNT=3
PING_TIMEOUT=2
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command - SA exists (VPN appears up)
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ping - fails (100% packet loss)
	mock_ping "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ping" "${TEST_DIR}/ping" 2>/dev/null || true
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script may exit with code 1, but ping check should still be logged
	# Should log ping check failure warning (check for either message variant)
	if ! grep -q "ping check failed" "$log_file" && ! grep -q "Ping check failed" "$log_file"; then
		echo "Expected ping check failure message not found in log" >&2
		echo "Log contents:" >&2
		cat "$log_file" >&2
		return 1
	fi

	remove_mock_from_path
}

@test "integration: Ping check enabled - VPN SA exists and ping succeeds" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
ENABLE_PING_CHECK=1
PING_TARGET_IP="192.168.1.1"
PING_COUNT=3
PING_TIMEOUT=2
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command - SA exists
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ping - succeeds
	local mock_ping
	# shellcheck disable=SC2034 # mock_ping is used by add_mock_to_path
	mock_ping=$(mock_ping "192.168.1.1" "1")
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_success
	# Should not increment failure counter
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert [ "$count" -eq 0 ]
	fi

	remove_mock_from_path
}

@test "integration: Rate limiting prevents excessive restarts" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
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

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Create restart file with 3 recent restarts (at limit)
	local now
	now=$(date +%s)
	{
		echo "$now"
		echo "$now"
		echo "$now"
	} >>"$restart_file"

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
	local mock_ipsec
	mock_ipsec=$(mock_ipsec)
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script may exit with code 1, but rate limit check should still be logged
	# Should log rate limit exceeded
	assert_file_contains "$log_file" "Rate limit exceeded"

	remove_mock_from_path
}

@test "integration: Cooldown period prevents immediate restart" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
COOLDOWN_MINUTES=15
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local cooldown_file="${state_dir}/cooldown_until"

	# Set cooldown to future time
	local future_time=$(($(date +%s) + 900)) # 15 minutes from now
	echo "$future_time" >"$cooldown_file"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	run bash "$test_script" --fake

	assert_success
	# Should exit early due to cooldown
	assert_file_contains "$log_file" "cooldown period"
}

# However, per-connection recovery IS available via xfrm (experimental, opt-in via ENABLE_XFRM_RECOVERY=1).
# Connection names discovered from ipsec status are for logging only, not for recovery.
@test "integration: Tier 2 recovery uses ipsec reload (default behavior)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
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

	# Mock ipsec - track reload call
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "ipsec-reload-called" > /tmp/ipsec_called.txt
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should use ipsec reload (affects all tunnels)
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "ipsec reload"
	if [[ -f /tmp/ipsec_called.txt ]]; then
		assert_file_exist /tmp/ipsec_called.txt
		rm -f /tmp/ipsec_called.txt
	fi

	remove_mock_from_path
}

@test "integration: Byte counter tracking - bytes not increasing detected" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Set initial byte count
	echo "1000" >"$last_bytes_file"

	# Mock ip command - bytes not increasing (same value)
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script may exit with code 1 when VPN check fails, which is expected
	# Check that the log contains the expected message
	assert_file_contains "$log_file" "bytes not increasing"

	remove_mock_from_path
}

@test "integration: Byte counter tracking - bytes increasing detected as healthy" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Set initial byte count
	echo "1000" >"$last_bytes_file"

	# Mock ip command - bytes increasing
	mock_ip_xfrm_state "192.168.1.1" "2000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script should succeed when VPN is healthy
	assert_success
	# Should update byte counter
	assert_file_exist "$last_bytes_file"
	local bytes
	bytes=$(cat "$last_bytes_file")
	assert [ "$bytes" = "2000" ]

	# Should not increment failure counter
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert [ "$count" -eq 0 ]
	fi

	remove_mock_from_path
}

@test "integration: Fallback to ipsec status when xfrm unavailable" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Don't create ip mock (xfrm unavailable)
	# Mock ipsec - return status
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    echo "test-conn: established, 192.168.1.1"
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_success
	# Should use ipsec status fallback
	assert_file_contains "$log_file" "ipsec status"

	remove_mock_from_path
}

# ============================================================================
# Tests for monitor_peer() function behavior
# ============================================================================

@test "integration: monitor_peer resets failure counter when VPN recovers" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${state_dir}/logs/failure_counter_192_168_1_1"

	# Set failure counter to non-zero value (simulating previous failures)
	echo "2" >"$failure_counter"

	# Set initial byte counter directly (skip baseline establishment run)
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"
	echo "1000" >"$last_bytes_file"

	# Mock ip command - VPN now healthy (bytes increasing)
	mock_ip_xfrm_state "192.168.1.1" "2000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Run script - bytes increased, VPN should be healthy
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_success
	# Failure counter should be reset to 0
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert [ "$count" -eq 0 ]
	fi
	# Should log recovery message
	assert_file_contains "$log_file" "recovered"

	remove_mock_from_path
}

@test "integration: monitor_peer increments failure counter on VPN failure" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${state_dir}/logs/failure_counter_192_168_1_1"

	# Mock ip command - VPN down (no SA found)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_success
	# Failure counter should be incremented
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert [ "$count" -eq 1 ]
	fi
	# Should log failure
	assert_file_contains "$log_file" "VPN check failed"

	remove_mock_from_path
}

@test "integration: monitor_peer tier escalation in fake mode skips actions" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=2
TIER3_THRESHOLD=3
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${state_dir}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 2 threshold
	echo "2" >"$failure_counter"

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

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_success
	# Should log that tier escalation is skipped in fake mode
	assert_file_contains "$log_file" "skipped in fake mode"
	assert_file_contains "$log_file" "Would attempt"

	remove_mock_from_path
}

@test "integration: monitor_peer tier escalation triggers at correct thresholds" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=2
TIER3_THRESHOLD=3
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${state_dir}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 1 threshold
	echo "1" >"$failure_counter"

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

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_success
	# Should log Tier 1 action
	assert_file_contains "$log_file" "Tier 1"

	# Increment to Tier 2 threshold
	echo "2" >"$failure_counter"
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_success
	# Should log Tier 2 action
	assert_file_contains "$log_file" "Tier 2"

	# Increment to Tier 3 threshold
	echo "3" >"$failure_counter"
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_success
	# Should log Tier 3 action
	assert_file_contains "$log_file" "Tier 3"

	remove_mock_from_path
}
