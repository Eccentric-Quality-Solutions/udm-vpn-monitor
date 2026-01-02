#!/usr/bin/env bats
#
# Tests for Idle Tunnel Detection
# Tests critical paths and error handling scenarios

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_idle

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# 2.4 IDLE TUNNEL DETECTION
# ============================================================================

# bats test_tags=category:high-risk,priority:medium
@test "Idle tunnel detected - Bytes not increasing but ping succeeds" {
	# Purpose: Test verifies that idle tunnel detection works when bytes are not increasing but ping succeeds
	# Expected: Tunnel is marked as idle but healthy, idle state stored in state file
	# Importance: Prevents false failure detection for tunnels that are healthy but not passing traffic
	setup_vpn_idle_fixture "192.168.1.1" 1000 "10.0.0.1"

	run bash "$TEST_SCRIPT" --fake

	# Should detect idle tunnel (ping succeeds)
	assert_success
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "idle but healthy" || assert_file_contains "$LOG_FILE" "ping check passed"

	# Idle state should be stored (use get_peer_state_file_path to get correct path)
	local idle_file
	idle_file=$(get_peer_state_file_path "TEST" "192.168.1.1" "idle_detected" 2>/dev/null || echo "${STATE_DIR}/idle_detected_TEST_192_168_1_1")
	assert_file_exist "$idle_file"
	local idle_state
	idle_state=$(cat "$idle_file" 2>/dev/null || echo "")
	[[ "$idle_state" == "1" ]]

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Idle tunnel detected - Idle state stored in state file" {
	# Purpose: Test verifies that idle tunnel state is stored in state file
	# Expected: idle_detected file is created with value "1" when idle tunnel is detected
	# Importance: Idle state tracking allows monitoring idle tunnels over time
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=1' 'LOCATION_TEST_INTERNAL="10.0.0.1"'

	source_function "get_peer_state_file_path"

	# Set initial byte counter (bytes not increasing)
	# Use location name "TEST" as created by setup_location_vpn_monitor
	local last_bytes_file
	last_bytes_file=$(get_peer_state_file_path "TEST" "192.168.1.1" "last_bytes")
	echo "1000" >"$last_bytes_file"

	# Mock ip command - SA exists, bytes static
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

	# Mock ping - succeeds
	mock_ping_success >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake

	# Idle state file should exist and contain "1"
	# Use location name "TEST" as created by setup_location_vpn_monitor
	local idle_file
	idle_file=$(get_peer_state_file_path "TEST" "192.168.1.1" "idle_detected")
	assert_file_exist "$idle_file"
	local idle_state
	idle_state=$(cat "$idle_file" 2>/dev/null || echo "")
	[[ "$idle_state" == "1" ]]

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Idle tunnel - Keepalive suggestion logged when keepalive disabled" {
	# Purpose: Test verifies that keepalive suggestion is logged when idle tunnel detected and keepalive disabled
	# Expected: Log message suggests enabling ENABLE_KEEPALIVE=1 when idle tunnel detected
	# Importance: Helps users prevent idle tunnel timeouts
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=1' 'ENABLE_KEEPALIVE=0' 'LOCATION_NYC_INTERNAL="10.0.0.1"'

	source_function "get_peer_state_file_path"

	# Set initial byte counter (bytes not increasing)
	# Use location name "TEST1" as created by setup_test_vpn_monitor (LOCATION_NYC_INTERNAL doesn't create a location without EXTERNAL)
	local last_bytes_file
	last_bytes_file=$(get_peer_state_file_path "TEST1" "192.168.1.1" "last_bytes")
	echo "1000" >"$last_bytes_file"

	# Mock ip command - SA exists, bytes static
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

	# Mock ping - succeeds
	mock_ping_success >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake

	# Should log keepalive suggestion
	assert_success
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "ENABLE_KEEPALIVE" || assert_file_contains "$LOG_FILE" "keepalive"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Idle tunnel - Keepalive daemon check when keepalive enabled" {
	# Purpose: Test verifies that keepalive daemon status is checked when keepalive is enabled
	# Expected: Log message checks if keepalive daemon is running when idle tunnel detected
	# Importance: Helps users ensure keepalive daemon is running when enabled
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=1' 'ENABLE_KEEPALIVE=1' 'LOCATION_NYC_INTERNAL="10.0.0.1"'

	source_function "get_peer_state_file_path"

	# Set initial byte counter (bytes not increasing)
	# Use location name "TEST1" as created by setup_test_vpn_monitor (LOCATION_NYC_INTERNAL doesn't create a location without EXTERNAL)
	local last_bytes_file
	last_bytes_file=$(get_peer_state_file_path "TEST1" "192.168.1.1" "last_bytes")
	echo "1000" >"$last_bytes_file"

	# Mock ip command - SA exists, bytes static
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

	# Mock ping - succeeds
	mock_ping_success >/dev/null
	add_mock_to_path

	# Don't create keepalive pidfile (daemon not running)
	run bash "$TEST_SCRIPT" --fake

	# Should check keepalive daemon status
	assert_success
	assert_file_exist "$LOG_FILE"
	# Should log message about keepalive daemon (may suggest starting it)
	assert_file_contains "$LOG_FILE" "keepalive" || assert_file_contains "$LOG_FILE" "daemon"

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:medium
@test "Idle tunnel - Traffic resumes, idle state cleared" {
	# Purpose: Test verifies that idle state is cleared when traffic resumes
	# Expected: idle_detected file is deleted or cleared when bytes start increasing again
	# Importance: Ensures idle state doesn't persist after traffic resumes
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=1' 'LOCATION_TEST_INTERNAL="10.0.0.1"'

	source_function "get_peer_state_file_path"

	# Set initial byte counter and idle state
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local last_bytes_file
	last_bytes_file=$(get_peer_state_file_path "TEST" "192.168.1.1" "last_bytes")
	echo "1000" >"$last_bytes_file"
	local idle_file
	idle_file=$(get_peer_state_file_path "TEST" "192.168.1.1" "idle_detected")
	echo "1" >"$idle_file"

	# Mock ip command - SA exists, bytes increasing (traffic resumed)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"

	# Mock ping - succeeds (required when ENABLE_PING_CHECK=1)
	mock_ping_success >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake

	# Should clear idle state (traffic is flowing)
	assert_success
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "traffic flowing" || assert_file_contains "$LOG_FILE" "VPN OK"

	# Idle state file should be deleted or cleared
	if [[ -f "$idle_file" ]]; then
		local idle_state
		idle_state=$(cat "$idle_file" 2>/dev/null || echo "")
		[[ "$idle_state" != "1" ]]
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Idle tunnel - Ping check disabled, idle not detected" {
	# Purpose: Test verifies that idle tunnel is not detected when ping check is disabled
	# Expected: Tunnel is marked as suspect/failed when bytes not increasing and ping disabled
	# Importance: Ping check is required for idle tunnel detection
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=0' 'LOCATION_TEST_INTERNAL="10.0.0.1"'

	source_function "get_peer_state_file_path"

	# Set initial byte counter (bytes not increasing)
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local last_bytes_file
	last_bytes_file=$(get_peer_state_file_path "TEST" "192.168.1.1" "last_bytes")
	echo "1000" >"$last_bytes_file"

	# Mock ip command - SA exists, bytes static
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

	run bash "$TEST_SCRIPT" --fake

	# Should not detect idle tunnel (ping disabled)
	assert_success
	assert_file_exist "$LOG_FILE"
	# Should mark as suspect/failed (bytes not increasing, ping disabled)
	assert_file_contains "$LOG_FILE" "suspect" || assert_file_contains "$LOG_FILE" "bytes not increasing"

	# Idle state should not be set
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local idle_file
	idle_file=$(get_peer_state_file_path "TEST" "192.168.1.1" "idle_detected")
	if [[ -f "$idle_file" ]]; then
		fail "Idle state should not be set when ping check is disabled"
	fi

	remove_mock_from_path
}
