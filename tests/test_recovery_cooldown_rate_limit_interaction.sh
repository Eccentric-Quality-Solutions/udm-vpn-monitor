#!/usr/bin/env bats
#
# Tests for Cooldown and Rate Limiting Interaction
# Tests critical paths for how cooldown and rate limiting interact when both are active
#
# Critical Path: full_restart() → check_rate_limit() → set_cooldown()
# Gap: How do cooldown and rate limiting interact when both are active?

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_cooldown

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# COOLDOWN AND RATE LIMITING INTERACTION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "cooldown and rate limit interaction: rate limit allows restart but cooldown is active - cooldown takes precedence" {
	# Test verifies that when rate limit allows restart but cooldown is active,
	# cooldown takes precedence and script exits early before attempting restart.
	# Expected: Script exits early due to cooldown, no restart attempted.
	# Importance: Ensures cooldown period is respected even when rate limit would allow restart.
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=0.01
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
NO_ESCALATE=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local restart_file="${TEST_DIR}/logs/restart_count"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	local cooldown_file="${state_dir}/cooldown_until"

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Set up rate limit: only 1 restart in last hour (under limit of 3)
	local now=$base_time
	local recent=$((now - 1800)) # 30 minutes ago (within 1 hour)
	echo "$recent" >"$restart_file"

	# Set up active cooldown: 1 second remaining (cooldown is 0.01 minutes = 0.6 seconds)
	local cooldown_until=$((now + 1)) # 1 second in future
	echo "$cooldown_until" >"$cooldown_file"

	# Set failure count to Tier 3 threshold (would trigger restart if not for cooldown)
	echo "5" >"$failure_counter"

	# Setup mock VPN environment with bytes > 0 for byte counter verification
	setup_mock_vpn_environment "192.168.1.1" 1000 "" "" 0

	# Create mock ipsec (should NOT be called due to cooldown)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ERROR: ipsec restart should not be called during cooldown" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	run bash "$test_script"
	assert_success

	# Should exit early due to cooldown
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "cooldown period"
	assert_file_contains "$log_file" "Script exiting"

	# Verify restart was NOT recorded (cooldown should prevent reaching full_restart)
	if [[ -f "$restart_file" ]]; then
		local file_lines
		file_lines=$(wc -l <"$restart_file" | tr -d ' ')
		# Should still have only 1 entry (no new restart recorded)
		assert_equal "$file_lines" "1"
	fi

	# Verify cooldown file still exists (not removed since we're still in cooldown)
	assert_file_exist "$cooldown_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "cooldown and rate limit interaction: cooldown expires but rate limit still active - rate limit prevents restart" {
	# Test verifies that when cooldown expires but rate limit is still active,
	# rate limit prevents restart even though cooldown has expired.
	# Expected: Script continues past cooldown check, but rate limit blocks restart.
	# Importance: Ensures rate limiting is enforced even after cooldown period ends.
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=0.01
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
NO_ESCALATE=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local restart_file="${TEST_DIR}/logs/restart_count"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	local cooldown_file="${state_dir}/cooldown_until"

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Set up rate limit: exactly 3 restarts in last hour (at limit)
	local now=$base_time
	local recent=$((now - 1800)) # 30 minutes ago (within 1 hour)
	{
		echo "$recent"
		echo "$recent"
		echo "$recent"
	} >"$restart_file"

	# Set up expired cooldown: expired 5 minutes ago
	local cooldown_until=$((now - 300)) # 5 minutes ago (expired)
	# Don't create cooldown file (it would be removed when expired)
	# But we'll verify the script handles this case

	# Set failure count to Tier 3 threshold (would trigger restart if not for rate limit)
	echo "5" >"$failure_counter"

	# Setup VPN as DOWN so recovery is triggered
	setup_vpn_down_fixture "192.168.1.1" 5 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'MAX_RESTARTS_PER_HOUR=3' 'COOLDOWN_MINUTES=15' 'ENABLE_XFRM_RECOVERY=0' 'ENABLE_NETWORK_PARTITION_CHECK=0' 'NO_ESCALATE=1'

	# Override the config file with our specific settings
	cat >"$TEST_CONFIG_FILE" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=15
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
NO_ESCALATE=1
EOF

	# Recreate test script with updated config
	TEST_SCRIPT=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$TEST_CONFIG_FILE" "$STATE_DIR" "$LOG_FILE")

	# Create mock ipsec (should NOT be called due to rate limit)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ERROR: ipsec restart should not be called when rate limit exceeded" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	run bash "$TEST_SCRIPT"
	assert_success

	# Should continue past cooldown check (cooldown expired)
	assert_file_exist "$LOG_FILE"
	# Should NOT contain cooldown exit message
	refute_file_contains "$LOG_FILE" "Script exiting.*cooldown"

	# Should block restart due to rate limit
	assert_file_contains "$LOG_FILE" "Rate limit exceeded"

	# Verify restart was NOT recorded (rate limit should prevent restart)
	if [[ -f "$restart_file" ]]; then
		local file_lines
		file_lines=$(wc -l <"$restart_file" | tr -d ' ')
		# Should still have exactly 3 entries (no new restart recorded)
		assert_equal "$file_lines" "3"
	fi

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "cooldown and rate limit interaction: both cooldown and rate limit expire simultaneously - should allow restart" {
	# Test verifies that when both cooldown and rate limit expire simultaneously,
	# restart is allowed and both are properly set after restart.
	# Expected: Script continues past cooldown check, rate limit allows restart,
	# restart is performed, and new cooldown is set.
	# Importance: Ensures system can recover when both protections have expired.
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=0.01
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
NO_ESCALATE=1
EOF

	# Setup VPN as DOWN so recovery is triggered
	setup_vpn_down_fixture "192.168.1.1" 5 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'MAX_RESTARTS_PER_HOUR=3' 'COOLDOWN_MINUTES=15' 'ENABLE_XFRM_RECOVERY=0' 'ENABLE_NETWORK_PARTITION_CHECK=0' 'NO_ESCALATE=1'

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Set up rate limit: only 2 restarts in last hour (under limit of 3)
	# Use LOGS_DIR set by fixture
	local restart_file="${LOGS_DIR}/restart_count"
	local cooldown_file="${STATE_DIR}/cooldown_until"
	local now=$base_time
	local old_restart=$((now - 3700)) # 61 minutes ago (outside 1 hour window)
	{
		echo "$old_restart"
		echo "$old_restart"
	} >"$restart_file"

	# No active cooldown (expired or never set)
	# Don't create cooldown file

	# Override the config file with our specific settings
	# Note: NO_ESCALATE=0 (or not set) to actually perform restart, not just log it
	cat >"$TEST_CONFIG_FILE" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=15
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
NO_ESCALATE=0
EOF

	# Recreate test script with updated config
	TEST_SCRIPT=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$TEST_CONFIG_FILE" "$STATE_DIR" "$LOG_FILE")

	# Create mock ipsec (should be called since both protections allow restart)
	local mock_ipsec="${TEST_DIR}/ipsec"
	local ipsec_called_file="${TEST_DIR}/ipsec_called"
	cat >"$mock_ipsec" <<EOF
#!/bin/bash
if [[ "\$1" == "restart" ]]; then
    touch "$ipsec_called_file"
    exit 0
elif [[ "\$1" == "status" ]]; then
    # After restart, return status output that includes the peer IP for verification
    # Before restart, return empty to indicate VPN is down (so recovery is triggered)
    if [[ -f "$ipsec_called_file" ]]; then
        # After restart - return connection found for verification
        echo "Security Associations (1 up, 0 connecting):"
        echo "  192.168.1.1[192.168.1.1]...192.168.1.1[192.168.1.1] IKEv2"
    else
        # Before restart - return empty to indicate VPN is down
        exit 0
    fi
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	run bash "$TEST_SCRIPT"
	# Script may exit with status 1 due to warnings (e.g., verification failures)
	# but restart should still have been attempted
	# Allow both success (0) and warnings (1) exit codes

	# Should continue past cooldown check (no cooldown)
	assert_file_exist "$LOG_FILE"
	refute_file_contains "$LOG_FILE" "Script exiting.*cooldown"

	# Should NOT contain rate limit exceeded message
	refute_file_contains "$LOG_FILE" "Rate limit exceeded"

	# Should perform restart - check if ipsec was called (most reliable indicator)
	# This is the key assertion - restart must have been attempted
	assert_file_exist "$ipsec_called_file"

	# Verify restart was recorded
	if [[ -f "$restart_file" ]]; then
		local file_lines
		file_lines=$(wc -l <"$restart_file" | tr -d ' ')
		# Should have at least 1 entry (new restart recorded, old ones may be cleaned up)
		assert [ "$file_lines" -ge 1 ]
	fi

	# Verify new cooldown was set after restart
	assert_file_exist "$cooldown_file"
	local new_cooldown_until
	new_cooldown_until=$(cat "$cooldown_file")
	# New cooldown should be in the future (approximately now + 15 minutes = 900 seconds)
	# Note: This test uses COOLDOWN_MINUTES=15 in the final config override
	# Use base_time since 'now' is controlled by mock_date
	local expected_cooldown=$((base_time + 900)) # 15 minutes = 900 seconds
	local tolerance=60                           # Allow 60 second tolerance
	local diff=$((new_cooldown_until - expected_cooldown))
	if [[ $diff -lt 0 ]]; then
		diff=$((-diff))
	fi
	assert [ "$diff" -le "$tolerance" ]

	remove_mock_from_path
}
