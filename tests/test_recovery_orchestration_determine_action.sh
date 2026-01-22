#!/usr/bin/env bats
#
# Tests for determine_recovery_action Function
# Tests the core orchestration function that decides which recovery tier to use
#
# This test file addresses the gap identified in UNTESTED_FUNCTIONS_REVIEW.md:
# - determine_recovery_action (lib/recovery/recovery_orchestration.sh)
#   - Core orchestration function - decides which recovery tier to use
#   - Risk: Wrong tier selection = wrong recovery actions
#   - Complexity: ~140 lines, multiple branches, safety checks, tier logic

load test_helper
load helpers/assertions
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_at_tier

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# TIER 1: LOGGING TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "determine_recovery_action: Tier 1 logging when failure count below Tier 2 threshold" {
	# Purpose: Test verifies that Tier 1 logging occurs when failure count is below Tier 2 threshold
	# Expected: Function logs Tier 1 message and returns 1 (no recovery attempted)
	# Importance: Ensures proper logging before recovery escalation
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export TIER1_THRESHOLD=1
	export TIER2_THRESHOLD=3
	export TIER3_THRESHOLD=5
	export ENABLE_XFRM_RECOVERY=0
	export ENABLE_NETWORK_PARTITION_CHECK=0

	# Set failure count to 1 (Tier 1 threshold, but below Tier 2)
	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local failure_count=1

	# Set failure count in state
	ensure_state_functions_loaded
	set_peer_state "$location_name" "$external_peer_ip" "failure_count" "$failure_count" || true

	# Mock commands for detection
	mock_ip_vpn_down
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Test determine_recovery_action
	run determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" ""

	# Should return 1 (no recovery attempted, only logging)
	assert_failure

	# Should log Tier 1 message
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tier 1: Logging"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "determine_recovery_action: Tier 1 logging with different failure types" {
	# Purpose: Test verifies that Tier 1 logging includes failure type information
	# Expected: Function logs Tier 1 message with appropriate failure type display
	# Importance: Ensures failure type information is included in logs
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export TIER1_THRESHOLD=1
	export TIER2_THRESHOLD=3
	export TIER3_THRESHOLD=5
	export ENABLE_XFRM_RECOVERY=0
	export ENABLE_NETWORK_PARTITION_CHECK=0

	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local failure_count=1

	# Set failure count in state
	ensure_state_functions_loaded
	set_peer_state "$location_name" "$external_peer_ip" "failure_count" "$failure_count" || true

	# Set failure type to tunnel_down
	if command -v set_peer_state >/dev/null 2>&1; then
		local failure_type_file
		failure_type_file=$(get_peer_state_file_path "$location_name" "$external_peer_ip" "failure_type")
		mkdir -p "$(dirname "$failure_type_file")"
		echo "tunnel_down" >"$failure_type_file"
	fi

	# Mock commands for detection
	mock_ip_vpn_down
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Test determine_recovery_action
	run determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" ""

	# Should return 1 (no recovery attempted)
	assert_failure

	# Should log Tier 1 message with failure type
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tier 1: Logging"
	assert_file_contains "$LOG_FILE" "tunnel down"

	remove_mock_from_path
}

# ============================================================================
# TIER 2: SURGICAL CLEANUP TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "determine_recovery_action: Tier 2 surgical cleanup when failure count at Tier 2 threshold" {
	# Purpose: Test verifies that Tier 2 recovery is triggered when failure count reaches Tier 2 threshold
	# Expected: Function attempts surgical cleanup and returns 0 (recovery attempted)
	# Importance: Ensures Tier 2 recovery triggers at correct threshold
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export TIER1_THRESHOLD=1
	export TIER2_THRESHOLD=3
	export TIER3_THRESHOLD=5
	export ENABLE_XFRM_RECOVERY=0
	export ENABLE_NETWORK_PARTITION_CHECK=0

	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local failure_count=3

	# Set failure count in state
	ensure_state_functions_loaded
	set_peer_state "$location_name" "$external_peer_ip" "failure_count" "$failure_count" || true

	# Mock commands for detection and recovery
	mock_ip_vpn_down
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock surgical_cleanup to track calls
	local surgical_cleanup_called="${TEST_DIR}/surgical_cleanup_called"
	# Override surgical_cleanup function
	surgical_cleanup() {
		echo "called" >"$surgical_cleanup_called"
		return 0
	}

	# Test determine_recovery_action
	run determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" ""

	# Should return 0 (recovery attempted)
	assert_success

	# Should call surgical_cleanup
	assert_file_exist "$surgical_cleanup_called"

	# Should log Tier 2 message
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tier 2: Attempting surgical SA cleanup"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "determine_recovery_action: Tier 2 with NO_ESCALATE mode" {
	# Purpose: Test verifies that Tier 2 recovery is logged but not executed in NO_ESCALATE mode
	# Expected: Function logs what would be done but doesn't execute recovery
	# Importance: Ensures fake mode works correctly for Tier 2
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export TIER1_THRESHOLD=1
	export TIER2_THRESHOLD=3
	export TIER3_THRESHOLD=5
	export ENABLE_XFRM_RECOVERY=0
	export ENABLE_NETWORK_PARTITION_CHECK=0
	export NO_ESCALATE=1

	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local failure_count=3

	# Set failure count in state
	ensure_state_functions_loaded
	set_peer_state "$location_name" "$external_peer_ip" "failure_count" "$failure_count" || true

	# Mock commands for detection
	mock_ip_vpn_down
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock surgical_cleanup to track calls (should not be called)
	local surgical_cleanup_called="${TEST_DIR}/surgical_cleanup_called"
	surgical_cleanup() {
		echo "called" >"$surgical_cleanup_called"
		return 0
	}

	# Test determine_recovery_action
	run determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" ""

	# Should return 0 (recovery attempted, even if fake)
	assert_success

	# Should NOT call surgical_cleanup
	assert_file_not_exist "$surgical_cleanup_called"

	# Should log Tier 2 message with "Would attempt" or "skipped in fake mode"
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Would attempt" "skipped in fake mode" "Tier 2"

	unset NO_ESCALATE
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "determine_recovery_action: Tier 2 with xfrm recovery enabled" {
	# Purpose: Test verifies that Tier 2 recovery attempts xfrm recovery when enabled
	# Expected: Function attempts xfrm-based recovery first
	# Importance: Ensures xfrm recovery is preferred when available
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export TIER1_THRESHOLD=1
	export TIER2_THRESHOLD=3
	export TIER3_THRESHOLD=5
	export ENABLE_XFRM_RECOVERY=1
	export ENABLE_NETWORK_PARTITION_CHECK=0

	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local failure_count=3

	# Set failure count in state
	ensure_state_functions_loaded
	set_peer_state "$location_name" "$external_peer_ip" "failure_count" "$failure_count" || true

	# Mock commands for detection and recovery
	mock_ip_vpn_down
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock surgical_cleanup to track calls
	local surgical_cleanup_called="${TEST_DIR}/surgical_cleanup_called"
	surgical_cleanup() {
		echo "called" >"$surgical_cleanup_called"
		return 0
	}

	# Test determine_recovery_action
	run determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" ""

	# Should return 0 (recovery attempted)
	assert_success

	# Should call surgical_cleanup (which will attempt xfrm recovery)
	assert_file_exist "$surgical_cleanup_called"

	# Should log Tier 2 message
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tier 2: Attempting surgical SA cleanup"

	remove_mock_from_path
}

# ============================================================================
# TIER 3: FULL RESTART TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "determine_recovery_action: Tier 3 full restart when failure count at Tier 3 threshold" {
	# Purpose: Test verifies that Tier 3 recovery is triggered when failure count reaches Tier 3 threshold
	# Expected: Function attempts full restart and returns 0 (recovery attempted)
	# Importance: Ensures Tier 3 recovery triggers at correct threshold
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export TIER1_THRESHOLD=1
	export TIER2_THRESHOLD=3
	export TIER3_THRESHOLD=5
	export ENABLE_XFRM_RECOVERY=0
	export ENABLE_NETWORK_PARTITION_CHECK=0
	export MAX_RESTARTS_PER_WINDOW=10
	RATE_LIMIT_WINDOW_MINUTES=60
	export RATE_LIMIT_WINDOW_MINUTES=60

	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local failure_count=5

	# Set failure count in state
	ensure_state_functions_loaded
	set_peer_state "$location_name" "$external_peer_ip" "failure_count" "$failure_count" || true

	# Mock commands for detection and recovery
	mock_ip_vpn_down
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock full_restart to track calls
	local full_restart_called="${TEST_DIR}/full_restart_called"
	full_restart() {
		echo "called" >"$full_restart_called"
		return 0
	}

	# Mock check_rate_limit to allow restart
	check_rate_limit() {
		return 0
	}

	# Test determine_recovery_action
	run determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" ""

	# Should return 0 (recovery attempted)
	assert_success

	# Should call full_restart
	assert_file_exist "$full_restart_called"

	# Should log Tier 3 message
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tier 3: Attempting IPsec restart"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "determine_recovery_action: Tier 3 with NO_ESCALATE mode" {
	# Purpose: Test verifies that Tier 3 recovery is logged but not executed in NO_ESCALATE mode
	# Expected: Function logs what would be done but doesn't execute recovery
	# Importance: Ensures fake mode works correctly for Tier 3
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export TIER1_THRESHOLD=1
	export TIER2_THRESHOLD=3
	export TIER3_THRESHOLD=5
	export ENABLE_XFRM_RECOVERY=0
	export ENABLE_NETWORK_PARTITION_CHECK=0
	export MAX_RESTARTS_PER_WINDOW=10
	RATE_LIMIT_WINDOW_MINUTES=60
	export RATE_LIMIT_WINDOW_MINUTES=60
	export NO_ESCALATE=1

	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local failure_count=5

	# Set failure count in state
	ensure_state_functions_loaded
	set_peer_state "$location_name" "$external_peer_ip" "failure_count" "$failure_count" || true

	# Mock commands for detection
	mock_ip_vpn_down
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock full_restart to track calls (should not be called)
	local full_restart_called="${TEST_DIR}/full_restart_called"
	full_restart() {
		echo "called" >"$full_restart_called"
		return 0
	}

	# Mock check_rate_limit to allow restart
	check_rate_limit() {
		return 0
	}

	# Test determine_recovery_action
	run determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" ""

	# Should return 0 (recovery attempted, even if fake)
	assert_success

	# Should NOT call full_restart
	assert_file_not_exist "$full_restart_called"

	# Should log Tier 3 message with "Would attempt" or "skipped in fake mode"
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Would attempt" "skipped in fake mode" "Tier 3"

	unset NO_ESCALATE
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "determine_recovery_action: Tier 3 with rate limiting" {
	# Purpose: Test verifies that Tier 3 recovery respects rate limiting
	# Expected: Function logs rate limit message and doesn't attempt restart
	# Importance: Ensures rate limiting prevents restart loops
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export TIER1_THRESHOLD=1
	export TIER2_THRESHOLD=3
	export TIER3_THRESHOLD=5
	export ENABLE_XFRM_RECOVERY=0
	export ENABLE_NETWORK_PARTITION_CHECK=0
	export MAX_RESTARTS_PER_WINDOW=10
	RATE_LIMIT_WINDOW_MINUTES=60
	export RATE_LIMIT_WINDOW_MINUTES=60
	export NO_ESCALATE=1

	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local failure_count=5

	# Set failure count in state
	ensure_state_functions_loaded
	set_peer_state "$location_name" "$external_peer_ip" "failure_count" "$failure_count" || true

	# Mock commands for detection
	mock_ip_vpn_down
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock full_restart to track calls (should not be called)
	local full_restart_called="${TEST_DIR}/full_restart_called"
	full_restart() {
		echo "called" >"$full_restart_called"
		return 0
	}

	# Mock check_rate_limit to block restart
	check_rate_limit() {
		return 1
	}

	# Test determine_recovery_action
	run determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" ""

	# Should return 0 (recovery attempted, even if blocked by rate limit)
	assert_success

	# Should NOT call full_restart
	assert_file_not_exist "$full_restart_called"

	# Should log rate limit message
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "rate limit" "Rate limit exceeded" "skipped in fake mode, rate limit would prevent"

	unset NO_ESCALATE
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "determine_recovery_action: Tier 3 resets failure count on successful restart" {
	# Purpose: Test verifies that failure count is reset after successful Tier 3 recovery
	# Expected: Function resets failure count when full_restart succeeds
	# Importance: Ensures failure count doesn't accumulate after successful recovery
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export TIER1_THRESHOLD=1
	export TIER2_THRESHOLD=3
	export TIER3_THRESHOLD=5
	export ENABLE_XFRM_RECOVERY=0
	export ENABLE_NETWORK_PARTITION_CHECK=0
	export MAX_RESTARTS_PER_WINDOW=10
	RATE_LIMIT_WINDOW_MINUTES=60
	export RATE_LIMIT_WINDOW_MINUTES=60

	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local failure_count=5

	# Set failure count in state
	ensure_state_functions_loaded
	set_peer_state "$location_name" "$external_peer_ip" "failure_count" "$failure_count" || true

	# Mock commands for detection and recovery
	mock_ip_vpn_down
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock full_restart to succeed
	full_restart() {
		return 0
	}

	# Mock check_rate_limit to allow restart
	check_rate_limit() {
		return 0
	}

	# Mock reset_failure_count to track calls
	local reset_called="${TEST_DIR}/reset_called"
	reset_failure_count() {
		echo "called" >"$reset_called"
		# Actually reset the failure count
		if command -v set_peer_state >/dev/null 2>&1; then
			set_peer_state "$location_name" "$external_peer_ip" "failure_count" "0" || true
		fi
	}

	# Test determine_recovery_action
	run determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" ""

	# Should return 0 (recovery attempted)
	assert_success

	# Should reset failure count
	assert_file_exist "$reset_called"

	remove_mock_from_path
}

# ============================================================================
# DETECTION RELIABILITY SAFEGUARD TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "determine_recovery_action: blocks recovery escalation when both ip and ipsec unavailable" {
	# Purpose: Test verifies that recovery escalation is blocked when detection is unreliable
	# Expected: Function logs error about unreliable detection and skips Tier 2/3 recovery
	# Importance: Prevents false recovery actions when detection is unreliable
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export TIER1_THRESHOLD=1
	export TIER2_THRESHOLD=3
	export TIER3_THRESHOLD=5
	export ENABLE_XFRM_RECOVERY=0
	export ENABLE_NETWORK_PARTITION_CHECK=0

	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local failure_count=5

	# Set failure count in state
	ensure_state_functions_loaded
	set_peer_state "$location_name" "$external_peer_ip" "failure_count" "$failure_count" || true

	# Set failure type to unknown (required for safeguard)
	if command -v set_peer_state >/dev/null 2>&1; then
		local failure_type_file
		failure_type_file=$(get_peer_state_file_path "$location_name" "$external_peer_ip" "failure_type")
		mkdir -p "$(dirname "$failure_type_file")"
		echo "unknown" >"$failure_type_file"
	fi

	# Remove mocks (make commands unavailable)
	rm -f "${TEST_DIR}/ip" "${TEST_DIR}/ipsec"

	# Ensure PATH doesn't include system directories with these commands
	local original_path="$PATH"
	export PATH="${TEST_DIR}:/usr/bin:/bin"

	# Verify commands are truly unavailable
	if check_command_available "ip" || check_command_available "ipsec"; then
		skip "ip or ipsec found in system directories - cannot test 'both unavailable' scenario"
	fi

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock full_restart to track calls (should not be called)
	local full_restart_called="${TEST_DIR}/full_restart_called"
	full_restart() {
		echo "called" >"$full_restart_called"
		return 0
	}

	# Test determine_recovery_action
	run determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" ""

	# Should return 0 (recovery attempted, but blocked)
	assert_success

	# Should NOT call full_restart
	assert_file_not_exist "$full_restart_called"

	# Should log error about unreliable detection
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Detection unreliable"
	assert_file_contains "$LOG_FILE" "skipping recovery escalation"

	# Should still log Tier 1 message
	assert_log_contains_any "$LOG_FILE" "Tier 1" "recovery skipped - detection unreliable"

	# Restore PATH
	export PATH="$original_path"
}

# bats test_tags=category:high-risk,priority:high
@test "determine_recovery_action: allows recovery when at least one detection tool available" {
	# Purpose: Test verifies that recovery proceeds when at least one detection tool is available
	# Expected: Function proceeds with recovery when ip is available (even if ipsec unavailable)
	# Importance: Ensures recovery works when at least one detection method is available
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export TIER1_THRESHOLD=1
	export TIER2_THRESHOLD=3
	export TIER3_THRESHOLD=5
	export ENABLE_XFRM_RECOVERY=0
	export ENABLE_NETWORK_PARTITION_CHECK=0
	export MAX_RESTARTS_PER_WINDOW=10
	RATE_LIMIT_WINDOW_MINUTES=60
	export RATE_LIMIT_WINDOW_MINUTES=60

	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local failure_count=5

	# Set failure count in state
	ensure_state_functions_loaded
	set_peer_state "$location_name" "$external_peer_ip" "failure_count" "$failure_count" || true

	# Keep ip mock (available) - remove ipsec mock
	mock_ip_vpn_down
	rm -f "${TEST_DIR}/ipsec"

	# Create ipsec mock for recovery (even though detection can't use it, recovery needs it)
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock full_restart to track calls
	local full_restart_called="${TEST_DIR}/full_restart_called"
	full_restart() {
		echo "called" >"$full_restart_called"
		return 0
	}

	# Mock check_rate_limit to allow restart
	check_rate_limit() {
		return 0
	}

	# Test determine_recovery_action
	run determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" ""

	# Should return 0 (recovery attempted)
	assert_success

	# Should call full_restart (ip is available, so detection is reliable)
	assert_file_exist "$full_restart_called"

	# Should NOT log detection unreliable error
	assert_file_exist "$LOG_FILE"
	assert_log_not_contains "$LOG_FILE" "Detection unreliable"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "determine_recovery_action: safeguard only applies to unknown failure type" {
	# Purpose: Test verifies that safeguard only applies when failure type is "unknown"
	# Expected: Recovery proceeds normally when failure type is known (e.g., "tunnel_down")
	# Importance: Ensures safeguard doesn't block recovery when we can reliably determine failure type
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export TIER1_THRESHOLD=1
	export TIER2_THRESHOLD=3
	export TIER3_THRESHOLD=5
	export ENABLE_XFRM_RECOVERY=0
	export ENABLE_NETWORK_PARTITION_CHECK=0
	export MAX_RESTARTS_PER_WINDOW=10
	RATE_LIMIT_WINDOW_MINUTES=60
	export RATE_LIMIT_WINDOW_MINUTES=60

	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local failure_count=5

	# Set failure count in state
	ensure_state_functions_loaded
	set_peer_state "$location_name" "$external_peer_ip" "failure_count" "$failure_count" || true

	# Set failure type to tunnel_down (known failure type)
	if command -v set_peer_state >/dev/null 2>&1; then
		local failure_type_file
		failure_type_file=$(get_peer_state_file_path "$location_name" "$external_peer_ip" "failure_type")
		mkdir -p "$(dirname "$failure_type_file")"
		echo "tunnel_down" >"$failure_type_file"
	fi

	# Remove mocks (make commands unavailable)
	rm -f "${TEST_DIR}/ip" "${TEST_DIR}/ipsec"

	# Ensure PATH doesn't include system directories
	local original_path="$PATH"
	export PATH="${TEST_DIR}:/usr/bin:/bin"

	# Verify commands are truly unavailable
	if check_command_available "ip" || check_command_available "ipsec"; then
		skip "ip or ipsec found in system directories - cannot test 'both unavailable' scenario"
	fi

	# Create ipsec mock for recovery
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock full_restart to track calls
	local full_restart_called="${TEST_DIR}/full_restart_called"
	full_restart() {
		echo "called" >"$full_restart_called"
		return 0
	}

	# Mock check_rate_limit to allow restart
	check_rate_limit() {
		return 0
	}

	# Test determine_recovery_action
	run determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" ""

	# Should return 0 (recovery attempted)
	assert_success

	# Should call full_restart (failure type is known, so safeguard doesn't apply)
	assert_file_exist "$full_restart_called"

	# Should NOT log detection unreliable error
	assert_file_exist "$LOG_FILE"
	assert_log_not_contains "$LOG_FILE" "Detection unreliable"

	# Restore PATH
	export PATH="$original_path"
	remove_mock_from_path
}

# ============================================================================
# SYSTEM-WIDE FAILURE COORDINATION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "determine_recovery_action: skips recovery when another location is coordinator" {
	# Purpose: Test verifies that recovery is skipped when another location is coordinating
	# Expected: Function skips recovery and logs coordination message
	# Importance: Prevents cascading recovery attempts during system-wide failures
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export TIER1_THRESHOLD=1
	export TIER2_THRESHOLD=3
	export TIER3_THRESHOLD=5
	export ENABLE_XFRM_RECOVERY=0
	export ENABLE_NETWORK_PARTITION_CHECK=0
	export ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1
	export COORDINATE_SYSTEM_WIDE_RECOVERY=1

	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local failure_count=3

	# Set failure count in state
	ensure_state_functions_loaded
	set_peer_state "$location_name" "$external_peer_ip" "failure_count" "$failure_count" || true

	# Set up system-wide failure state with another location as coordinator
	if command -v set_system_wide_failure_state >/dev/null 2>&1; then
		set_system_wide_failure_state 1
	fi

	# Pre-set coordinator to another location
	if command -v get_system_wide_failure_coordinator_file >/dev/null 2>&1; then
		local coordinator_file
		coordinator_file=$(get_system_wide_failure_coordinator_file)
		mkdir -p "$(dirname "$coordinator_file")"
		echo "OTHER_LOCATION" >"$coordinator_file"
	fi

	# Mock commands for detection
	mock_ip_vpn_down
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock surgical_cleanup to track calls (should not be called)
	local surgical_cleanup_called="${TEST_DIR}/surgical_cleanup_called"
	surgical_cleanup() {
		echo "called" >"$surgical_cleanup_called"
		return 0
	}

	# Test determine_recovery_action
	run determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" ""

	# Should return 0 (recovery attempted, but skipped due to coordination)
	assert_success

	# Should NOT call surgical_cleanup
	assert_file_not_exist "$surgical_cleanup_called"

	# Should log coordination message
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Skipping recovery"
	assert_file_contains "$LOG_FILE" "recovery coordinated by another location"

	unset ENABLE_SYSTEM_WIDE_FAILURE_DETECTION
	unset COORDINATE_SYSTEM_WIDE_RECOVERY
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "determine_recovery_action: proceeds with recovery when location is coordinator" {
	# Purpose: Test verifies that recovery proceeds when location is the coordinator
	# Expected: Function attempts recovery normally
	# Importance: Ensures coordinator location can still attempt recovery
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export TIER1_THRESHOLD=1
	export TIER2_THRESHOLD=3
	export TIER3_THRESHOLD=5
	export ENABLE_XFRM_RECOVERY=0
	export ENABLE_NETWORK_PARTITION_CHECK=0
	export ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1
	export COORDINATE_SYSTEM_WIDE_RECOVERY=1

	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local failure_count=3

	# Set failure count in state
	ensure_state_functions_loaded
	set_peer_state "$location_name" "$external_peer_ip" "failure_count" "$failure_count" || true

	# Set up system-wide failure state
	if command -v set_system_wide_failure_state >/dev/null 2>&1; then
		set_system_wide_failure_state 1
	fi

	# Pre-set coordinator to this location
	if command -v get_system_wide_failure_coordinator_file >/dev/null 2>&1; then
		local coordinator_file
		coordinator_file=$(get_system_wide_failure_coordinator_file)
		mkdir -p "$(dirname "$coordinator_file")"
		echo "$location_name" >"$coordinator_file"
	fi

	# Mock commands for detection and recovery
	mock_ip_vpn_down
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock surgical_cleanup to track calls
	local surgical_cleanup_called="${TEST_DIR}/surgical_cleanup_called"
	surgical_cleanup() {
		echo "called" >"$surgical_cleanup_called"
		return 0
	}

	# Test determine_recovery_action
	run determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" ""

	# Should return 0 (recovery attempted)
	assert_success

	# Should call surgical_cleanup (location is coordinator)
	assert_file_exist "$surgical_cleanup_called"

	# Should log Tier 2 message
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tier 2: Attempting surgical SA cleanup"

	unset ENABLE_SYSTEM_WIDE_FAILURE_DETECTION
	unset COORDINATE_SYSTEM_WIDE_RECOVERY
	remove_mock_from_path
}

# ============================================================================
# EDGE CASES AND BOUNDARY CONDITIONS
# ============================================================================

# bats test_tags=category:high-risk,priority:medium
@test "determine_recovery_action: handles failure count exactly at Tier 2 threshold" {
	# Purpose: Test verifies that failure count exactly at Tier 2 threshold triggers Tier 2 recovery
	# Expected: Function triggers Tier 2 recovery when failure_count == TIER2_THRESHOLD
	# Importance: Ensures boundary conditions are handled correctly
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export TIER1_THRESHOLD=1
	export TIER2_THRESHOLD=3
	export TIER3_THRESHOLD=5
	export ENABLE_XFRM_RECOVERY=0
	export ENABLE_NETWORK_PARTITION_CHECK=0

	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local failure_count=3

	# Set failure count in state
	ensure_state_functions_loaded
	set_peer_state "$location_name" "$external_peer_ip" "failure_count" "$failure_count" || true

	# Mock commands for detection and recovery
	mock_ip_vpn_down
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock surgical_cleanup to track calls
	local surgical_cleanup_called="${TEST_DIR}/surgical_cleanup_called"
	surgical_cleanup() {
		echo "called" >"$surgical_cleanup_called"
		return 0
	}

	# Test determine_recovery_action
	run determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" ""

	# Should return 0 (recovery attempted)
	assert_success

	# Should call surgical_cleanup (failure_count == TIER2_THRESHOLD)
	assert_file_exist "$surgical_cleanup_called"

	# Should log Tier 2 message
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tier 2: Attempting surgical SA cleanup"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "determine_recovery_action: handles failure count exactly at Tier 3 threshold" {
	# Purpose: Test verifies that failure count exactly at Tier 3 threshold triggers Tier 3 recovery
	# Expected: Function triggers Tier 3 recovery when failure_count == TIER3_THRESHOLD
	# Importance: Ensures boundary conditions are handled correctly
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export TIER1_THRESHOLD=1
	export TIER2_THRESHOLD=3
	export TIER3_THRESHOLD=5
	export ENABLE_XFRM_RECOVERY=0
	export ENABLE_NETWORK_PARTITION_CHECK=0
	export MAX_RESTARTS_PER_WINDOW=10
	RATE_LIMIT_WINDOW_MINUTES=60
	export RATE_LIMIT_WINDOW_MINUTES=60

	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local failure_count=5

	# Set failure count in state
	ensure_state_functions_loaded
	set_peer_state "$location_name" "$external_peer_ip" "failure_count" "$failure_count" || true

	# Mock commands for detection and recovery
	mock_ip_vpn_down
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock full_restart to track calls
	local full_restart_called="${TEST_DIR}/full_restart_called"
	full_restart() {
		echo "called" >"$full_restart_called"
		return 0
	}

	# Mock check_rate_limit to allow restart
	check_rate_limit() {
		return 0
	}

	# Test determine_recovery_action
	run determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" ""

	# Should return 0 (recovery attempted)
	assert_success

	# Should call full_restart (failure_count == TIER3_THRESHOLD)
	assert_file_exist "$full_restart_called"

	# Should log Tier 3 message
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tier 3: Attempting IPsec restart"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "determine_recovery_action: handles failure count between Tier 2 and Tier 3 thresholds" {
	# Purpose: Test verifies that failure count between Tier 2 and Tier 3 triggers Tier 2 recovery
	# Expected: Function triggers Tier 2 recovery when TIER2_THRESHOLD <= failure_count < TIER3_THRESHOLD
	# Importance: Ensures Tier 2 recovery is used for intermediate failure counts
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export TIER1_THRESHOLD=1
	export TIER2_THRESHOLD=3
	export TIER3_THRESHOLD=5
	export ENABLE_XFRM_RECOVERY=0
	export ENABLE_NETWORK_PARTITION_CHECK=0

	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local failure_count=4

	# Set failure count in state
	ensure_state_functions_loaded
	set_peer_state "$location_name" "$external_peer_ip" "failure_count" "$failure_count" || true

	# Mock commands for detection and recovery
	mock_ip_vpn_down
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock surgical_cleanup to track calls
	local surgical_cleanup_called="${TEST_DIR}/surgical_cleanup_called"
	surgical_cleanup() {
		echo "called" >"$surgical_cleanup_called"
		return 0
	}

	# Test determine_recovery_action
	run determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" ""

	# Should return 0 (recovery attempted)
	assert_success

	# Should call surgical_cleanup (TIER2_THRESHOLD <= failure_count < TIER3_THRESHOLD)
	assert_file_exist "$surgical_cleanup_called"

	# Should log Tier 2 message
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tier 2: Attempting surgical SA cleanup"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "determine_recovery_action: handles failure count above Tier 3 threshold" {
	# Purpose: Test verifies that failure count above Tier 3 threshold triggers Tier 3 recovery
	# Expected: Function triggers Tier 3 recovery when failure_count >= TIER3_THRESHOLD
	# Importance: Ensures Tier 3 recovery is used for high failure counts
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export TIER1_THRESHOLD=1
	export TIER2_THRESHOLD=3
	export TIER3_THRESHOLD=5
	export ENABLE_XFRM_RECOVERY=0
	export ENABLE_NETWORK_PARTITION_CHECK=0
	export MAX_RESTARTS_PER_WINDOW=10
	RATE_LIMIT_WINDOW_MINUTES=60
	export RATE_LIMIT_WINDOW_MINUTES=60

	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local failure_count=10

	# Set failure count in state
	ensure_state_functions_loaded
	set_peer_state "$location_name" "$external_peer_ip" "failure_count" "$failure_count" || true

	# Mock commands for detection and recovery
	mock_ip_vpn_down
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock full_restart to track calls
	local full_restart_called="${TEST_DIR}/full_restart_called"
	full_restart() {
		echo "called" >"$full_restart_called"
		return 0
	}

	# Mock check_rate_limit to allow restart
	check_rate_limit() {
		return 0
	}

	# Test determine_recovery_action
	run determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" ""

	# Should return 0 (recovery attempted)
	assert_success

	# Should call full_restart (failure_count >= TIER3_THRESHOLD)
	assert_file_exist "$full_restart_called"

	# Should log Tier 3 message
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tier 3: Attempting IPsec restart"

	remove_mock_from_path
}
