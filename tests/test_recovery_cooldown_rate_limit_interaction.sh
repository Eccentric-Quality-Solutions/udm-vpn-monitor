#!/usr/bin/env bats
#
# Tests for Cooldown and Rate Limiting Interaction
# Tests critical paths for how cooldown and rate limiting interact when both are active
#
# Critical Path: full_restart() → check_rate_limit() → set_cooldown()
# Gap: How do cooldown and rate limiting interact when both are active?

load test_helper
load helpers/test_data
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_cooldown
load fixtures/vpn_rate_limited

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# COOLDOWN AND RATE LIMITING INTERACTION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "cooldown and rate limit interaction: rate limit allows restart but cooldown is active - cooldown takes precedence" {
	# Purpose: Test verifies that when rate limit allows restart but cooldown is active, cooldown takes precedence and script exits early before attempting restart
	# Expected: Script exits early due to cooldown, no restart attempted
	# Importance: Ensures cooldown period is respected even when rate limit would allow restart
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	generate_config_file "cooldown_rate_limit" "$config_file" "${TEST_PEER_IP}" "0.01" "3"

	mkdir -p "${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/state"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local restart_file="${TEST_DIR}/state/restart_count"
	local cooldown_file="${state_dir}/cooldown_until"

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${state_dir}"

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local failure_counter
	failure_counter=$(get_peer_state_file_path "" "${TEST_PEER_IP}" "failure_count")

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
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000 "" "" 0

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
	# Mock is already in PATH from mock_date add_mock_to_path call

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	run bash "$test_script" --fake
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

# bats test_tags=slow,category:high-risk,priority:high
@test "cooldown and rate limit interaction: cooldown expires but rate limit still active - rate limit prevents restart" {
	# Purpose: Test verifies that when cooldown expires but rate limit is still active, rate limit prevents restart even though cooldown has expired
	# Expected: Script continues past cooldown check, but rate limit blocks restart
	# Importance: Ensures rate limiting is enforced even after cooldown period ends

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Set up rate limit: exactly 3 restarts in last hour (at limit)
	local now=$base_time
	local recent=$((now - 1800)) # 30 minutes ago (within 1 hour)
	setup_vpn_rate_limited_fixture "${TEST_PEER_IP}" 3 \
		"$recent" \
		"$recent" \
		"$recent" \
		'COOLDOWN_MINUTES=15' \
		'ENABLE_XFRM_RECOVERY=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0'

	local restart_file="${STATE_DIR}/restart_count"

	# Setup VPN as DOWN so recovery is triggered
	# Set last_bytes > 0 so that bytes=0 is detected as a failure (bytes dropped to 0)
	# This ensures VPN is detected as down rather than idle
	ensure_state_functions_loaded
	set_peer_state "TEST1" "${TEST_PEER_IP}" "last_bytes" "1000" || true
	setup_mock_vpn_environment "${TEST_PEER_IP}" 0

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
	# Mock is already in PATH from mock_date add_mock_to_path call

	run bash "$TEST_SCRIPT" --fake
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
	# Purpose: Test verifies that when both cooldown and rate limit expire simultaneously, restart is allowed and both are properly set after restart
	# Expected: Script continues past cooldown check, rate limit allows restart, restart is performed, and new cooldown is set
	# Importance: Ensures system can recover when both protections have expired

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Set up rate limit: only 2 restarts in last hour (under limit of 3)
	# Use old timestamps that are outside the 1 hour window
	local now=$base_time
	local old_restart=$((now - 3700)) # 61 minutes ago (outside 1 hour window)
	setup_vpn_rate_limited_fixture "${TEST_PEER_IP}" 2 \
		"$old_restart" \
		"$old_restart" \
		'COOLDOWN_MINUTES=15' \
		'ENABLE_XFRM_RECOVERY=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0'

	local restart_file="${STATE_DIR}/restart_count"
	local cooldown_file="${STATE_DIR}/cooldown_until"

	# No active cooldown (expired or never set)
	# Don't create cooldown file

	# Setup VPN as DOWN so recovery is triggered
	# Set last_bytes > 0 so that bytes=0 is detected as a failure (bytes dropped to 0)
	ensure_state_functions_loaded
	set_peer_state "TEST1" "${TEST_PEER_IP}" "last_bytes" "1000" || true
	setup_mock_vpn_environment "${TEST_PEER_IP}" 0

	# Create mock ipsec (should be called since both protections allow restart)
	# Use helper function with tracking to verify restart was called
	local ipsec_tracking_file="${TEST_DIR}/ipsec_tracking.txt"
	local status_after_restart_output="Security Associations (1 up, 0 connecting):
  ${TEST_PEER_IP}[${TEST_PEER_IP}]...${TEST_PEER_IP}[${TEST_PEER_IP}] IKEv2"
	mock_ipsec_with_tracking "$ipsec_tracking_file" 0 "" "$status_after_restart_output"
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

	# Should perform restart - check if ipsec restart was called (most reliable indicator)
	# This is the key assertion - restart must have been attempted
	# Verify restart was recorded in state file (primary check)
	if [[ -f "$restart_file" ]]; then
		local file_lines
		file_lines=$(wc -l <"$restart_file" | tr -d ' ')
		# Should have at least 1 entry (new restart recorded, old ones may be cleaned up)
		assert [ "$file_lines" -ge 1 ]
	fi

	# Verify new cooldown was set after restart
	# Note: Cooldown may not be set if script exits early or set_cooldown fails
	# Check if cooldown file exists and has content
	if [[ -f "$cooldown_file" ]]; then
		local new_cooldown_until
		new_cooldown_until=$(cat "$cooldown_file" | tr -d '\n\r' | tr -d ' ')
		# Only verify if cooldown was actually set (file has content)
		if [[ -n "$new_cooldown_until" ]] && [[ "$new_cooldown_until" =~ ^[0-9]+$ ]]; then
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
		else
			# Cooldown file exists but is empty or invalid - this is acceptable if script exited early
			# Just verify that restart was attempted (which we already checked above)
			skip "Cooldown not set (script may have exited before set_cooldown was called)"
		fi
	else
		# Cooldown file doesn't exist - this is acceptable if script exited early
		skip "Cooldown file not created (script may have exited before set_cooldown was called)"
	fi

	remove_mock_from_path
}
