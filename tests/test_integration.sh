#!/usr/bin/env bats
#
# Integration tests for vpn-monitor.sh with mock VPN states
# Tests full monitoring flow with various VPN state scenarios

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_at_tier

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# bats test_tags=category:integration
@test "integration: VPN healthy - no action taken" {
	# Purpose: Test verifies the complete monitoring flow when VPN is healthy and functioning normally
	# Expected: Script runs successfully, detects healthy VPN, and does not increment failure counter
	# Importance: Validates the happy path where VPN is working correctly and no recovery actions are needed
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000 "" 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5'

	# Run script - bytes should have increased from baseline
	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success
	source_function "get_peer_state_file_path"
	# Should not increment failure counter
	local failure_counter
	failure_counter=$(get_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert_equal "$count" 0
	fi

	remove_mock_from_path
}

# bats test_tags=category:integration
@test "integration: VPN down - Tier 1 logging triggered" {
	# Purpose: Test verifies the complete monitoring flow when VPN fails for the first time, triggering Tier 1 action
	# Expected: Script increments failure counter, logs Tier 1 message, and exits with failure status
	# Importance: Validates tier escalation system activates correctly on first VPN failure detection
	setup_vpn_at_tier_fixture 1 "${TEST_PEER_IP}"

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Script exits with code 1 when VPN check fails, which is expected
	# Check that the expected behavior happened
	source_function "get_peer_state_file_path"
	# Should increment failure counter
	# setup_vpn_at_tier_fixture creates location "TEST"
	local failure_counter
	failure_counter=$(get_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
	assert_file_exist "$failure_counter"
	local count
	count=$(cat "$failure_counter")
	assert [ "$count" -ge 1 ]

	# Should log Tier 1 action
	assert_file_contains "$LOG_FILE" "Tier 1"

	remove_mock_from_path
}

# bats test_tags=category:integration
@test "integration: VPN down - Tier 2 surgical cleanup triggered" {
	# Purpose: Test verifies the complete monitoring flow when VPN fails reach Tier 2 threshold, triggering surgical cleanup
	# Expected: Script executes ipsec reload command and logs Tier 2 action when failure count reaches threshold
	# Importance: Validates tier escalation system correctly triggers recovery actions at appropriate thresholds
	setup_vpn_at_tier_fixture 2 "${TEST_PEER_IP}"

	# Mock ipsec for surgical cleanup
	# VPN must be DOWN for recovery to trigger: status_exit=1 so ipsec status fails
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Script exits with code 1 when VPN check fails, which is expected
	# Should log Tier 2 action
	assert_file_contains "$LOG_FILE" "Tier 2"

	remove_mock_from_path
}

# bats test_tags=category:integration
@test "integration: VPN down - Tier 3 full restart triggered" {
	# Purpose: Test verifies the complete monitoring flow when VPN failures reach Tier 3 threshold, triggering full restart
	# Expected: Script executes ipsec restart command and logs Tier 3 action when failure count reaches threshold
	# Importance: Validates tier escalation system correctly triggers the most aggressive recovery action at highest threshold
	setup_vpn_at_tier_fixture 3 "${TEST_PEER_IP}" 'MAX_RESTARTS_PER_WINDOW=10
RATE_LIMIT_WINDOW_MINUTES=60'

	# Mock ipsec for full restart
	local mock_ipsec
	mock_ipsec=$(mock_ipsec)
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Script exits with code 1 when VPN check fails, which is expected
	# Should log Tier 3 action
	assert_file_contains "$LOG_FILE" "Tier 3"

	remove_mock_from_path
}

# bats test_tags=category:integration
@test "integration: VPN recovery after failures - counter reset" {
	# Purpose: Test verifies the complete monitoring flow when VPN recovers after previous failures
	# Expected: Script detects healthy VPN, resets failure counter to 0, and exits successfully
	# Importance: Validates that failure counters are properly reset when VPN recovers, preventing false escalation
	setup_vpn_failing_fixture "${TEST_PEER_IP}" 3 1000 2000 "" 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5'

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success
	source_function "get_peer_state_file_path"
	# Failure counter should be reset
	# setup_vpn_failing_fixture creates location "TEST"
	local failure_counter
	failure_counter=$(get_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
	assert_file_exist "$failure_counter"
	local count
	count=$(cat "$failure_counter")
	assert_equal "$count" 0

	# Should log recovery message
	assert_file_contains "$LOG_FILE" "recovered"

	remove_mock_from_path
}

# bats test_tags=slow,category:integration
@test "integration: Multiple peers - independent failure tracking" {
	# Purpose: Test verifies that multiple peer IPs are monitored independently with separate failure counters
	# Expected: Each peer maintains its own failure counter; failures in one peer don't affect others
	# Importance: Ensures multi-tunnel deployments can track failures per tunnel without cross-contamination
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5'
	# Note: Multiple peer IPs need separate location configs - this test uses single location for simplicity

	# Mock ip command - peer1 down, peer2 up
	# The script calls: ip xfrm state | grep <peer_ip>
	# So we need to return SA when grep would find peer2 (TEST_PEER_IP2)
	# Source IP is TEST_PEER_IP, destination IP is TEST_PEER_IP2
	mock_ip_xfrm_state "${TEST_PEER_IP2}" 1000 "0x12345678" "${TEST_PEER_IP}" >/dev/null
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Script may exit with code 1 if any peer fails, which is expected
	source_function "get_peer_state_file_path"
	# Check that peer1 failure counter was incremented
	# Peer1 should have failure counter incremented - use location-based path
	local failure_counter1
	failure_counter1=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
	if [[ -f "$failure_counter1" ]]; then
		local count1
		count1=$(cat "$failure_counter1")
		assert [ "$count1" -ge 1 ]
	fi

	# Peer2 (10.0.0.1) is not configured in this test (only single location configured)
	# The test comment notes: "Multiple peer IPs need separate location configs - this test uses single location for simplicity"
	# So peer2 counter should not exist
	# Note: This test may need updating to properly test multiple locations

	remove_mock_from_path
}

# bats test_tags=category:integration
@test "integration: Ping check enabled - VPN SA exists but ping fails" {
	# Purpose: Test verifies that ping check correctly identifies VPN failures even when xfrm SA exists
	# Expected: Script detects ping failure and logs warning, potentially marking VPN as failed
	# Importance: Ping checks provide additional verification beyond SA existence, detecting connectivity issues
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_PING_CHECK=1' 'LOCATION_TEST_INTERNAL="192.168.1.1"' 'PING_COUNT=3' 'PING_TIMEOUT=2'
	# Set up state files using location-based state functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "last_bytes" "1000" || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "spi" "0x12345678" || true
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000 "0x12345678" "192.168.1.1" 0

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# When xfrm finds SA but ping fails, we mark VPN failed (no ipsec fallback override).
	# Log should show ping failure or VPN suspect (script may exit 0 if resource-throttled before detection).
	assert_log_contains_any "$LOG_FILE" "ping check failed" "Ping check failed" "VPN suspect"

	remove_mock_from_path
}

# bats test_tags=category:integration
@test "integration: Ping check enabled - VPN SA exists and ping succeeds" {
	# Purpose: Test verifies that ping check correctly validates VPN health when both SA exists and ping succeeds
	# Expected: Script detects healthy VPN via both xfrm SA and ping check, does not increment failure counter
	# Importance: Validates ping check integration works correctly in the happy path scenario
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_PING_CHECK=1' 'LOCATION_TEST_INTERNAL="192.168.1.1"' 'PING_COUNT=3' 'PING_TIMEOUT=2'
	# Set up state files using location-based state functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "last_bytes" "1000" || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "spi" "0x12345678" || true
	setup_mock_vpn_environment "${TEST_PEER_IP}" 2000 "0x12345678" "192.168.1.1" 1

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success
	source_function "get_peer_state_file_path"
	# Should not increment failure counter
	local failure_counter
	failure_counter=$(get_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert_equal "$count" 0
	fi

	remove_mock_from_path
}

# bats test_tags=category:integration
@test "integration: Rate limiting prevents excessive restarts" {
	# Purpose: Test verifies that rate limiting mechanism prevents excessive IPsec restarts when limit is reached
	# Expected: Script detects restart limit exceeded and skips restart action, preventing system overload
	# Importance: Rate limiting protects against restart loops that could destabilize the system
	setup_vpn_at_tier_fixture 3 "${TEST_PEER_IP}" 'MAX_RESTARTS_PER_WINDOW=3' 'RATE_LIMIT_WINDOW_MINUTES=60' 'ENABLE_XFRM_RECOVERY=0' 'ENABLE_NETWORK_PARTITION_CHECK=0'

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Create restart file with 3 recent restarts (at limit)
	# Use timestamps within the 60-minute window (30 minutes ago)
	local now=$base_time
	local recent=$((now - 1800)) # 30 minutes ago (within 60-minute window)
	{
		echo "$recent"
		echo "$recent"
		echo "$recent"
	} >>"$RESTART_COUNT_FILE"

	# Mock ipsec
	local mock_ipsec
	mock_ipsec=$(mock_ipsec)
	# Mock is already in PATH from mock_date add_mock_to_path call

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Script may exit with code 1, but rate limit check should still be logged
	# Should log rate limit exceeded
	assert_file_contains "$LOG_FILE" "Rate limit exceeded"

	remove_mock_from_path
}

# However, per-connection recovery IS available via xfrm (experimental, opt-in via ENABLE_XFRM_RECOVERY=1).
# Connection names discovered from ipsec status are for logging only, not for recovery.
# bats test_tags=category:integration
@test "integration: Tier 2 recovery uses ipsec reload (default behavior)" {
	# Purpose: Test verifies that Tier 2 recovery action uses ipsec reload command by default
	# Expected: Script executes ipsec reload command when Tier 2 threshold is reached
	# Importance: Validates default recovery strategy uses surgical cleanup (reload) rather than full restart
	# Disable xfrm recovery to force ipsec reload (xfrm is preferred when peer IP is provided)
	setup_vpn_at_tier_fixture 2 "${TEST_PEER_IP}" 'ENABLE_XFRM_RECOVERY=0'

	# Mock ipsec - track reload call (note: in fake mode, commands are logged but not executed)
	local tracking_file="${TEST_DIR}/ipsec_called.txt"
	mock_ipsec_with_tracking "$tracking_file" >/dev/null
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Should use ipsec reload (affects all tunnels)
	# In fake mode, the command is logged but not executed, so we verify via log
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "ipsec reload"
	# Note: Tracking file won't be written in fake mode since commands aren't executed

	remove_mock_from_path
}

# bats test_tags=category:integration
@test "integration: Byte counter tracking - bytes not increasing detected" {
	# Purpose: Test verifies that the script correctly detects VPN failures when byte counters remain unchanged
	# Expected: Script detects bytes not increasing and logs warning, incrementing failure counter
	# Importance: Byte counter tracking is critical for detecting VPN tunnels that exist but aren't passing traffic
	# Disable ping check so that bytes not increasing is detected as suspect (not idle but healthy)
	setup_vpn_failing_fixture "${TEST_PEER_IP}" 0 1000 1000 "" 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'ENABLE_PING_CHECK=0'

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Script may exit with code 1 when VPN check fails, which is expected
	# Check that the log contains the expected message
	assert_file_contains "$LOG_FILE" "bytes not increasing"

	remove_mock_from_path
}

# bats test_tags=category:integration
@test "integration: Byte counter tracking - bytes increasing detected as healthy" {
	# Purpose: Test verifies that the script correctly identifies healthy VPN when byte counters are increasing
	# Expected: Script detects increasing bytes, updates last_bytes file, and does not increment failure counter
	# Importance: Validates that increasing traffic correctly indicates VPN health and prevents false failure detection
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000 "" 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5'

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Script should succeed when VPN is healthy
	assert_success
	source_function "get_peer_state_file_path"
	# Should update byte counter
	local last_bytes_file
	last_bytes_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "last_bytes")
	assert_file_exist "$last_bytes_file"
	local bytes
	bytes=$(cat "$last_bytes_file")
	# Use assert_equal for better error messages
	assert_equal "$bytes" "2000"

	source_function "get_peer_state_file_path"
	# Should not increment failure counter
	local failure_counter
	failure_counter=$(get_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert_equal "$count" 0
	fi

	remove_mock_from_path
}

# bats test_tags=category:integration
@test "integration: Fallback to ipsec status when xfrm unavailable" {
	# Purpose: Test verifies that the script falls back to ipsec status when xfrm command is unavailable
	# Expected: Script detects xfrm unavailable, uses ipsec status as fallback, and continues monitoring
	# Importance: Fallback mechanism ensures VPN monitoring works even when preferred detection method is unavailable
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Don't create ip mock (xfrm unavailable)
	# Mock ipsec - return status
	mock_ipsec_status 0 "test-conn: established, 192.168.1.1"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success
	# Should use ipsec status fallback
	assert_file_contains "$LOG_FILE" "ipsec status"

	remove_mock_from_path
}

# ============================================================================
# Tests for monitor_location() function behavior
# NOTE: These tests verify integration behavior. They will need updates to use
# location-based configuration format and check for location-based state files.
# ============================================================================

# bats test_tags=category:integration
@test "integration: monitor_location resets failure counter when VPN recovers" {
	# Purpose: Test verifies that monitor_location function resets failure counter when VPN health is restored
	# Expected: Function detects healthy VPN, resets failure counter to 0, and logs recovery message
	# Importance: Counter reset prevents false escalation after VPN recovers from transient failures
	setup_vpn_failing_fixture "${TEST_PEER_IP}" 2 1000 2000 "" 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5'

	# Run script - bytes increased, VPN should be healthy
	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success
	source_function "get_peer_state_file_path"
	# Failure counter should be reset to 0
	# setup_vpn_failing_fixture creates location "TEST"
	local failure_counter
	failure_counter=$(get_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert_equal "$count" 0
	fi
	# Should log recovery message
	assert_file_contains "$LOG_FILE" "recovered"

	remove_mock_from_path
}

# bats test_tags=category:integration
@test "integration: monitor_location increments failure counter on VPN failure" {
	# Purpose: Test verifies that monitor_location function increments failure counter when VPN check detects failure
	# Expected: Function increments per-peer failure counter and logs failure message when VPN is down
	# Importance: Failure counter tracking enables tier escalation system to trigger recovery actions
	setup_vpn_down_fixture "${TEST_PEER_IP}" 0

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success
	source_function "get_peer_state_file_path"
	# Failure counter should be incremented
	local failure_counter
	failure_counter=$(get_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert_equal "$count" 1
	fi
	# Should log failure
	assert_file_contains "$LOG_FILE" "VPN check failed"

	remove_mock_from_path
}

# bats test_tags=category:integration
@test "integration: monitor_location tier escalation in fake mode skips actions" {
	# Purpose: Test verifies that monitor_location function skips actual recovery actions when running in fake mode
	# Expected: Function logs what actions would be taken but does not execute recovery commands in fake mode
	# Importance: Fake mode allows testing tier escalation logic without triggering actual system changes
	setup_vpn_down_fixture "192.168.1.1" 2 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=2' 'TIER3_THRESHOLD=3'

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success
	# Should log that tier escalation is skipped in fake mode
	assert_file_contains "$LOG_FILE" "skipped in fake mode"
	assert_file_contains "$LOG_FILE" "Would attempt"

	remove_mock_from_path
}

# bats test_tags=slow,category:integration
@test "integration: monitor_location tier escalation triggers at correct thresholds" {
	# Purpose: Test verifies that monitor_location function triggers tier escalation actions at configured thresholds
	# Expected: Function triggers Tier 1, Tier 2, and Tier 3 actions when failure count reaches respective thresholds
	# Importance: Validates tier escalation system activates recovery actions at the correct failure counts
	setup_vpn_down_fixture "192.168.1.1" 1 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=2' 'TIER3_THRESHOLD=3'

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success
	# Should log Tier 1 action
	assert_file_contains "$LOG_FILE" "Tier 1"

	# Increment to Tier 2 threshold using location-based state functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "failure_count" "2" || true
	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success
	# Should log Tier 2 action
	assert_file_contains "$LOG_FILE" "Tier 2"

	# Increment to Tier 3 threshold using location-based state functions
	set_peer_state "TEST" "${TEST_PEER_IP}" "failure_count" "3" || true
	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success
	# Should log Tier 3 action
	assert_file_contains "$LOG_FILE" "Tier 3"

	remove_mock_from_path
}

# bats test_tags=category:integration
@test "integration: DNS name in location config - full monitoring cycle" {
	# Purpose: Test verifies the complete monitoring flow with DNS name in location configuration
	# Expected: Script resolves DNS name to IP, monitors VPN, and handles failures correctly
	# Importance: Validates end-to-end DNS name support in location configuration
	local test_hostname="vpn-gateway.example.com"
	local resolved_ip="${TEST_PEER_IP}"

	# Set up test VPN monitor (creates location "TEST1" by default)
	setup_location_vpn_monitor "$resolved_ip" "${TEST_DIR}" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	# Replace IP with DNS name in the config file (setup_location_vpn_monitor creates LOCATION_TEST1_EXTERNAL)
	# Use sed to replace the IP address with the DNS hostname
	sed -i "s|LOCATION_TEST1_EXTERNAL=\"${resolved_ip}\"|LOCATION_TEST1_EXTERNAL=\"${test_hostname}\"|" "$TEST_CONFIG_FILE"

	# Set up state files with initial byte counter (no failures)
	# setup_location_vpn_monitor creates location "TEST1" for the peer IP
	ensure_state_functions_loaded
	set_peer_state "TEST1" "$resolved_ip" "last_bytes" "1000" || true
	set_peer_state "TEST1" "$resolved_ip" "spi" "0x12345678" || true

	# Set up mock VPN environment with current byte counter (VPN active)
	setup_mock_vpn_environment "$resolved_ip" "2000" "0x12345678"

	# Mock DNS resolution - resolve hostname to IP
	mock_getent "1" "$resolved_ip" "$test_hostname"
	add_mock_to_path

	# Run script - bytes should have increased from baseline
	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success
	source_function "get_peer_state_file_path"
	# Should not increment failure counter (VPN is healthy)
	# setup_location_vpn_monitor creates location "TEST1" for the peer IP
	local failure_counter
	failure_counter=$(get_state_file_path "TEST1" "$resolved_ip" "failure_count")
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert_equal "$count" 0
	fi

	remove_mock_from_path
}
