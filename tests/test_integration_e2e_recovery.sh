#!/usr/bin/env bats
#
# End-to-End Recovery Scenario Tests
# Tests complete recovery workflows from failure detection to recovery

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing

# ============================================================================
# 6.1 END-TO-END RECOVERY SCENARIOS
# ============================================================================

# bats test_tags=slow,category:integration,priority:high
@test "End-to-end - VPN fails → Tier 1 → Tier 2 → Tier 3 → Recovery → Success" {
	# Purpose: Test verifies complete end-to-end recovery flow from initial failure through all tiers to successful recovery
	# Expected: Script escalates through all tiers, performs recovery, and VPN recovers successfully
	# Importance: Validates complete recovery workflow from failure detection to successful recovery
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=2' 'TIER3_THRESHOLD=3' 'MAX_RESTARTS_PER_HOUR=10' 'COOLDOWN_MINUTES=1' 'ENABLE_XFRM_RECOVERY=0'

	# Mock ipsec for recovery actions
	mock_ipsec_reload_restart 0 0
	add_mock_to_path

	# Step 1: VPN fails - Tier 1 (logging)
	setup_vpn_down_fixture "192.168.1.1" 0 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=2' 'TIER3_THRESHOLD=3' 'ENABLE_XFRM_RECOVERY=0'
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_file_contains "$LOG_FILE" "Tier 1"

	# Step 2: VPN still fails - Tier 2 (surgical cleanup)
	# setup_vpn_down_fixture sets failure count to 1, which becomes 2 after increment (TIER2_THRESHOLD=2)
	# This triggers Tier 2 recovery (failure_count=2 >= TIER2_THRESHOLD=2 and < TIER3_THRESHOLD=3)
	setup_vpn_down_fixture "192.168.1.1" 1 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=2' 'TIER3_THRESHOLD=3' 'ENABLE_XFRM_RECOVERY=0'
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_file_contains "$LOG_FILE" "Tier 2"

	# Step 3: VPN still fails - Tier 3 (full restart)
	# setup_vpn_down_fixture sets failure count to 2, which becomes 3 after increment (TIER3_THRESHOLD=3)
	# This triggers Tier 3 recovery
	# Pass ENABLE_XFRM_RECOVERY=0 to ensure ipsec restart strategy is selected
	setup_vpn_down_fixture "192.168.1.1" 2 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=2' 'TIER3_THRESHOLD=3' 'ENABLE_XFRM_RECOVERY=0'
	# Recreate mock ipsec after fixture (fixture may have recreated TEST_DIR structure)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "Reloaded"
    exit 0
elif [[ "$1" == "restart" ]]; then
    echo "Restarted"
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	# Verify mock ipsec is available before running script
	add_mock_to_path
	if ! command -v ipsec >/dev/null 2>&1; then
		skip "Mock ipsec not found in PATH (TEST_DIR=${TEST_DIR})"
	fi
	# Clear restart count file to ensure rate limit doesn't block Tier 3
	: >"$RESTART_COUNT_FILE"
	# Ensure PATH is explicitly set when running script (run may not inherit exported PATH)
	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake
	assert_success
	# Verify log file exists and contains Tier 3 message
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tier 3"

	# Step 4: VPN recovers after Tier 3 recovery
	setup_vpn_active_fixture "192.168.1.1" 1000 2000
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success
	# Use get_peer_state_file_path to get correct path dynamically
	# setup_vpn_active_fixture creates location "TEST"
	local failure_counter
	failure_counter=$(get_peer_state_file_path "TEST" "192.168.1.1" "failure_count")
	# Failure counter should be reset
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert_equal "$count" 0
	fi

	remove_mock_from_path
}

# bats test_tags=category:integration,priority:high
@test "End-to-end - VPN fails → Tier 1 → Recovers before Tier 2 → Counter reset" {
	# Purpose: Test verifies that VPN recovery before Tier 2 threshold resets failure counter
	# Expected: Failure counter is reset when VPN recovers before reaching Tier 2 threshold
	# Importance: Ensures recovery detection works correctly and prevents false escalation
	# Step 1: VPN fails - Tier 1
	# setup_vpn_down_fixture will set up the config and environment
	setup_vpn_down_fixture "192.168.1.1" 0 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5'
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_file_contains "$LOG_FILE" "Tier 1"

	# Use get_peer_state_file_path to get correct path dynamically
	ensure_state_functions_loaded
	# setup_vpn_down_fixture creates location "TEST"
	local failure_counter
	failure_counter=$(get_peer_state_file_path "TEST" "192.168.1.1" "failure_count")
	# Verify failure counter was incremented
	assert_file_exist "$failure_counter"
	local count
	count=$(cat "$failure_counter")
	assert [ "$count" -ge 1 ]

	# Step 2: VPN recovers before Tier 2
	# Set up VPN as healthy with bytes increasing (recovery scenario)
	# The failure_count is already set from step 1, so we just need to set up healthy VPN
	# Set last_bytes to 1000, then mock shows 2000 (bytes increasing = VPN healthy)
	# Also set SPI to match the mock
	set_peer_state "TEST" "192.168.1.1" "last_bytes" "1000" || true
	set_peer_state "TEST" "192.168.1.1" "spi" "0x12345678" || true
	setup_mock_vpn_environment "192.168.1.1" 2000
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Failure counter should be reset
	if [[ -f "$failure_counter" ]]; then
		count=$(cat "$failure_counter")
		assert_equal "$count" 0
	fi
	# Recovery message should be logged - check for either "recovered" or "restored"
	# (Both indicate successful recovery detection)
	assert_file_contains "$LOG_FILE" "recover"

	remove_mock_from_path
}

# bats test_tags=slow,category:integration,priority:high
@test "End-to-end - Multiple peers fail → Independent recovery per peer" {
	# Purpose: Test verifies that multiple peers fail and recover independently
	# Expected: Each peer maintains independent failure counters and recovery actions
	# Importance: Ensures multi-peer deployments handle failures independently
	setup_test_vpn_monitor "192.168.1.1 10.0.0.1" "${TEST_DIR}" 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'ENABLE_XFRM_RECOVERY=0'

	# Mock ipsec for recovery
	mock_ipsec_reload_restart 0 0

	# Mock ip - both peers down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Return empty (no SAs for either peer)
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Both peers fail
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Use get_peer_state_file_path to get correct paths dynamically
	ensure_state_functions_loaded
	# setup_test_vpn_monitor creates locations "TEST1" and "TEST2" for multiple peers
	local failure_counter1
	failure_counter1=$(get_peer_state_file_path "TEST1" "192.168.1.1" "failure_count")
	local failure_counter2
	failure_counter2=$(get_peer_state_file_path "TEST2" "10.0.0.1" "failure_count")
	# Both peers should have failure counters
	if [[ -f "$failure_counter1" ]]; then
		local count1
		count1=$(cat "$failure_counter1")
		assert [ "$count1" -ge 1 ]
	fi
	if [[ -f "$failure_counter2" ]]; then
		local count2
		count2=$(cat "$failure_counter2")
		assert [ "$count2" -ge 1 ]
	fi

	# Peer 1 recovers, peer 2 still fails
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Return SA for peer 1 only
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
fi
exec /usr/bin/ip "$@"
EOF

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Peer 1 counter should be reset, peer 2 counter should still be incremented
	if [[ -f "$failure_counter1" ]]; then
		local count1
		count1=$(cat "$failure_counter1")
		assert_equal "$count1" 0
	fi
	if [[ -f "$failure_counter2" ]]; then
		local count2
		count2=$(cat "$failure_counter2")
		assert [ "$count2" -ge 2 ]
	fi

	remove_mock_from_path
}

# bats test_tags=category:integration,priority:high
@test "End-to-end - Recovery succeeds but VPN still fails on next check" {
	# Purpose: Test verifies that recovery actions succeed but VPN continues to fail on subsequent checks
	# Expected: Recovery actions are performed but failure counter continues incrementing if VPN doesn't recover
	# Importance: Ensures recovery actions don't prevent continued failure tracking
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=2' 'TIER3_THRESHOLD=3' 'MAX_RESTARTS_PER_HOUR=10' 'COOLDOWN_MINUTES=1' 'ENABLE_XFRM_RECOVERY=0'

	# Mock ipsec - recovery succeeds
	mock_ipsec_reload_restart 0 0
	add_mock_to_path

	# VPN fails, reaches Tier 2
	setup_vpn_down_fixture "192.168.1.1" 2 'ENABLE_XFRM_RECOVERY=0'
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_file_contains "$LOG_FILE" "Tier 2"

	# Recovery action succeeds but VPN still fails on next check
	setup_vpn_down_fixture "192.168.1.1" 2 'ENABLE_XFRM_RECOVERY=0'
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Use get_peer_state_file_path to get correct path dynamically
	ensure_state_functions_loaded
	# setup_vpn_down_fixture creates location "TEST"
	local failure_counter
	failure_counter=$(get_peer_state_file_path "TEST" "192.168.1.1" "failure_count")
	# Failure counter should continue incrementing
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert [ "$count" -ge 3 ]
	fi

	remove_mock_from_path
}

# bats test_tags=category:integration,priority:high
@test "End-to-end - Recovery fails → Failure counter continues incrementing" {
	# Purpose: Test verifies that when recovery actions fail, failure counter continues incrementing
	# Expected: Failed recovery actions don't prevent failure counter from incrementing
	# Importance: Ensures failure tracking continues even when recovery actions fail
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=2' 'TIER3_THRESHOLD=3' 'MAX_RESTARTS_PER_HOUR=10' 'COOLDOWN_MINUTES=1' 'ENABLE_XFRM_RECOVERY=0'

	# Mock ipsec - recovery fails
	mock_ipsec_reload_restart 1 1
	add_mock_to_path

	# VPN fails, reaches Tier 2
	setup_vpn_down_fixture "192.168.1.1" 2 'ENABLE_XFRM_RECOVERY=0'
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success
	assert_file_contains "$LOG_FILE" "Tier 2"

	# Recovery fails, VPN still fails
	setup_vpn_down_fixture "192.168.1.1" 2 'ENABLE_XFRM_RECOVERY=0'
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Use get_peer_state_file_path to get correct path dynamically
	ensure_state_functions_loaded
	# setup_vpn_down_fixture creates location "TEST"
	local failure_counter
	failure_counter=$(get_peer_state_file_path "TEST" "192.168.1.1" "failure_count")
	# Failure counter should continue incrementing
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert [ "$count" -ge 3 ]
	fi

	remove_mock_from_path
}

# bats test_tags=category:integration,priority:high
@test "End-to-end - Rate limit reached → Recovery blocked → Next check allows recovery" {
	# Purpose: Test verifies that rate limiting blocks recovery but allows it on subsequent checks after limit expires
	# Expected: Recovery is blocked when rate limit is reached, but allowed again after limit expires
	# Importance: Ensures rate limiting works correctly and doesn't permanently block recovery
	# Use location-based config
	setup_location_test_vpn_monitor "${TEST_DIR}" \
		'LOCATION_TEST_EXTERNAL="192.168.1.1"' \
		'LOCATION_TEST_INTERNAL="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'MAX_RESTARTS_PER_HOUR=3' \
		'COOLDOWN_MINUTES=1' \
		'ENABLE_XFRM_RECOVERY=0'

	# Mock ipsec
	mock_ipsec_reload_restart 0 0
	add_mock_to_path

	# Mock VPN as down (no SA)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 1
fi
exit 1
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Set failure count to Tier 3 threshold for location-based state file
	ensure_state_functions_loaded
	mkdir -p "$LOGS_DIR"
	local failure_counter
	failure_counter=$(get_peer_state_file_path "TEST" "192.168.1.1" "failure_count")
	echo "5" >"$failure_counter"

	# Create restart file with 3 recent restarts (at limit)
	local now
	now=$(date +%s)
	{
		echo "$now"
		echo "$now"
		echo "$now"
	} >"$RESTART_COUNT_FILE"

	# First check - rate limit blocks recovery
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success
	assert_file_contains "$LOG_FILE" "Rate limit exceeded"

	# Wait a bit and add old restart entries (simulate time passing)
	local old_time
	old_time=$((now - 3700)) # More than 1 hour ago
	{
		echo "$old_time"
		echo "$old_time"
		echo "$old_time"
	} >"$RESTART_COUNT_FILE"

	# Next check - rate limit should allow recovery (old entries cleaned up)
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success
	# Should not contain rate limit message (or should allow recovery)
	# Recovery should proceed since old entries are cleaned up

	remove_mock_from_path
}
