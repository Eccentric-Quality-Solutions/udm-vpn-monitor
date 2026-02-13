#!/usr/bin/env bats
#
# Tests for _execute_xfrm_recovery_with_fallback Function
# Tests the fallback logic that orchestrates xfrm recovery with fallback to all-tunnels recovery
#
# This test file addresses the gap identified in UNTESTED_FUNCTIONS_REVIEW.md:
# - _execute_xfrm_recovery_with_fallback (lib/recovery/recovery_orchestration.sh)
#   - Orchestrates xfrm recovery with fallback to all-tunnels recovery
#   - Risk: Wrong fallback = affects all tunnels when only one is down
#   - Complexity: ~50 lines, fallback logic, strategy selection, return code semantics (0/1/2)
#   - Tier-specific behavior (Tier 2 vs Tier 3 differences)

load test_helper
load helpers/assertions

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# RETURN CODE 0: XFRM RECOVERY SUCCEEDS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "_execute_xfrm_recovery_with_fallback: returns 0 when xfrm recovery succeeds (Tier 2)" {
	# Purpose: Test verifies that function returns 0 when xfrm recovery succeeds for Tier 2
	# Expected: Function returns 0, logs success messages, stores recovery method
	# Importance: Ensures successful xfrm recovery path works correctly
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export ENABLE_XFRM_RECOVERY=1

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Track function calls
	local attempt_xfrm_called="${TEST_DIR}/attempt_xfrm_called"
	local store_recovery_called="${TEST_DIR}/store_recovery_called"
	local record_restart_called="${TEST_DIR}/record_restart_called"

	# Mock attempt_xfrm_recovery to succeed
	attempt_xfrm_recovery() {
		echo "called" >"$attempt_xfrm_called"
		return 0
	}

	# Mock store_recovery_method
	store_recovery_method() {
		echo "called" >"$store_recovery_called"
	}

	# Mock record_restart (should not be called for Tier 2)
	record_restart() {
		echo "called" >"$record_restart_called"
	}

	# Mock format_peer_ip_display
	format_peer_ip_display() {
		echo "$1"
	}

	# Test parameters
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"
	local tier=2
	declare -A recovery_info

	# Test function
	run _execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "" "ipsec reload"

	# Should return 0 (success)
	assert_success

	# Should call attempt_xfrm_recovery
	assert_file_exist "$attempt_xfrm_called"

	# Should call store_recovery_method (Tier 2 always stores)
	assert_file_exist "$store_recovery_called"

	# Should NOT call record_restart (Tier 2 doesn't record restart)
	assert_file_not_exist "$record_restart_called"

	# Should log success messages
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "xfrm-based surgical cleanup completed successfully"
}

# bats test_tags=category:high-risk,priority:high
@test "_execute_xfrm_recovery_with_fallback: returns 0 when xfrm recovery succeeds (Tier 3)" {
	# Purpose: Test verifies that function returns 0 when xfrm recovery succeeds for Tier 3
	# Expected: Function returns 0, logs success messages, records restart for rate limiting
	# Importance: Ensures Tier 3 specific behavior (record_restart) works correctly
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export ENABLE_XFRM_RECOVERY=1

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Track function calls
	local attempt_xfrm_called="${TEST_DIR}/attempt_xfrm_called"
	local store_recovery_called="${TEST_DIR}/store_recovery_called"
	local record_restart_called="${TEST_DIR}/record_restart_called"

	# Mock attempt_xfrm_recovery to succeed
	attempt_xfrm_recovery() {
		echo "called" >"$attempt_xfrm_called"
		return 0
	}

	# Mock store_recovery_method
	store_recovery_method() {
		echo "called" >"$store_recovery_called"
	}

	# Mock record_restart (should be called for Tier 3)
	record_restart() {
		echo "called" >"$record_restart_called"
	}

	# Mock format_peer_ip_display
	format_peer_ip_display() {
		echo "$1"
	}

	# Test parameters
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"
	local tier=3
	declare -A recovery_info

	# Test function
	run _execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "Tier 3: " "full restart"

	# Should return 0 (success)
	assert_success

	# Should call attempt_xfrm_recovery
	assert_file_exist "$attempt_xfrm_called"

	# Should call store_recovery_method (Tier 3 stores if peer IP provided)
	assert_file_exist "$store_recovery_called"

	# Should call record_restart (Tier 3 records restart for rate limiting)
	assert_file_exist "$record_restart_called"

	# Should log success messages with log prefix
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tier 3: xfrm-based per-connection recovery successful"
}

# bats test_tags=category:high-risk,priority:high
@test "_execute_xfrm_recovery_with_fallback: Tier 3 does not store recovery method when peer IP is empty" {
	# Purpose: Test verifies that Tier 3 does not store recovery method when peer IP is empty
	# Expected: Function does not call store_recovery_method when peer IP is empty for Tier 3
	# Importance: Ensures Tier 3 handles empty peer IP correctly (full_restart allows empty peer IP)
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export ENABLE_XFRM_RECOVERY=1

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Track function calls
	local store_recovery_called="${TEST_DIR}/store_recovery_called"

	# Mock attempt_xfrm_recovery to succeed
	attempt_xfrm_recovery() {
		return 0
	}

	# Mock store_recovery_method (should not be called for empty peer IP at Tier 3)
	store_recovery_method() {
		echo "called" >"$store_recovery_called"
	}

	# Mock format_peer_ip_display
	format_peer_ip_display() {
		echo "$1"
	}

	# Test parameters - empty peer IP for Tier 3
	local external_peer_ip=""
	local location_name="TEST"
	local tier=3
	declare -A recovery_info

	# Test function
	run _execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "Tier 3: " "full restart"

	# Should return 0 (success)
	assert_success

	# Should NOT call store_recovery_method (Tier 3 only stores if peer IP provided)
	assert_file_not_exist "$store_recovery_called"
}

# ============================================================================
# RETURN CODE 1: XFRM RECOVERY FAILS, FALLBACK SELECTED
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "_execute_xfrm_recovery_with_fallback: returns 1 when xfrm fails and fallback strategy selected" {
	# Purpose: Test verifies that function returns 1 when xfrm fails and fallback strategy is selected
	# Expected: Function returns 1, updates nameref array with fallback strategy, logs fallback message
	# Importance: Ensures fallback logic works correctly when xfrm recovery fails
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export ENABLE_XFRM_RECOVERY=1

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Track function calls
	local attempt_xfrm_called="${TEST_DIR}/attempt_xfrm_called"
	local select_strategy_called="${TEST_DIR}/select_strategy_called"

	# Mock attempt_xfrm_recovery to fail
	attempt_xfrm_recovery() {
		echo "called" >"$attempt_xfrm_called"
		return 1
	}

	# Mock select_recovery_strategy to succeed (fallback available)
	# Arguments: $1 peer_ip, $2 tier, $3 result nameref. Returns: 0 success.
	select_recovery_strategy() {
		echo "called" >"$select_strategy_called"
		local result_ref_name="$3"
		local -n result="$result_ref_name"
		result["strategy"]="ipsec_reload"
		result["command"]="ipsec reload"
		result["impact"]="all-tunnels"
		result["available"]=1
		return 0
	}

	# Mock format_peer_ip_display
	format_peer_ip_display() {
		echo "$1"
	}

	# Test parameters
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"
	local tier=2
	declare -A recovery_info

	# Test function - call directly (not via run) to preserve nameref array updates
	# Disable set -e to allow capturing return code 1
	set +e
	_execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "" "ipsec reload (affects all tunnels)"
	local exit_code=$?
	set -e

	# Should return 1 (fallback selected)
	assert_equal "$exit_code" 1

	# Should call attempt_xfrm_recovery
	assert_file_exist "$attempt_xfrm_called"

	# Should call select_recovery_strategy for fallback (without peer IP)
	assert_file_exist "$select_strategy_called"

	# Should update nameref array with fallback strategy
	assert_equal "${recovery_info[strategy]}" "ipsec_reload"
	assert_equal "${recovery_info[command]}" "ipsec reload"
	assert_equal "${recovery_info[impact]}" "all-tunnels"
	assert_equal "${recovery_info[available]}" "1"

	# Should log fallback message
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "xfrm-based recovery failed"
	assert_file_contains "$LOG_FILE" "falling back to ipsec reload"
}

# bats test_tags=category:high-risk,priority:high
@test "_execute_xfrm_recovery_with_fallback: fallback calls select_recovery_strategy without peer IP" {
	# Purpose: Test verifies that fallback calls select_recovery_strategy without peer IP to force all-tunnels recovery
	# Expected: select_recovery_strategy is called with empty peer IP for fallback
	# Importance: Ensures fallback forces all-tunnels recovery (not per-connection)
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export ENABLE_XFRM_RECOVERY=1

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Track select_recovery_strategy arguments
	local strategy_args_file="${TEST_DIR}/strategy_args"

	# Mock attempt_xfrm_recovery to fail
	attempt_xfrm_recovery() {
		return 1
	}

	# Mock select_recovery_strategy to capture arguments
	# Arguments: $1 peer_ip, $2 tier, $3 result nameref. Returns: 0 success.
	select_recovery_strategy() {
		local peer_ip="$1"
		local tier="$2"
		echo "peer_ip=$peer_ip tier=$tier" >"$strategy_args_file"
		local result_ref_name="$3"
		local -n result="$result_ref_name"
		result["strategy"]="ipsec_reload"
		result["command"]="ipsec reload"
		result["impact"]="all-tunnels"
		result["available"]=1
		return 0
	}

	# Mock format_peer_ip_display
	format_peer_ip_display() {
		echo "$1"
	}

	# Test parameters
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"
	local tier=2
	declare -A recovery_info

	# Test function - call directly (not via run) to preserve nameref array updates
	# Disable set -e to allow capturing return code 1
	set +e
	_execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "" "ipsec reload"
	local exit_code=$?
	set -e

	# Should return 1 (fallback selected)
	assert_equal "$exit_code" 1

	# Should call select_recovery_strategy with empty peer IP
	assert_file_exist "$strategy_args_file"
	assert_file_contains "$strategy_args_file" "peer_ip="
	# Verify peer IP is empty (should not contain the actual peer IP)
	local strategy_args
	strategy_args=$(cat "$strategy_args_file")
	# Check that peer_ip= is followed by space or end of line (empty value)
	if echo "$strategy_args" | grep -q "peer_ip= "; then
		# peer_ip= followed by space (empty)
		: # Success
	elif echo "$strategy_args" | grep -q "peer_ip=\$"; then
		# peer_ip=$ (empty at end)
		: # Success
	elif echo "$strategy_args" | grep -qE "peer_ip=\s*tier="; then
		# peer_ip= followed by whitespace and tier= (empty)
		: # Success
	else
		# Check that it doesn't contain the actual peer IP
		if echo "$strategy_args" | grep -q "$external_peer_ip"; then
			echo "ERROR: peer IP should be empty but found: $strategy_args" >&2
			return 1
		fi
	fi
}

# ============================================================================
# RETURN CODE 2: XFRM RECOVERY FAILS, NO FALLBACK AVAILABLE
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "_execute_xfrm_recovery_with_fallback: returns 2 when xfrm fails and no fallback available" {
	# Purpose: Test verifies that function returns 2 when xfrm fails and no fallback strategy is available
	# Expected: Function returns 2, logs error message, does not update nameref array
	# Importance: Ensures error handling works when no recovery options are available
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export ENABLE_XFRM_RECOVERY=1

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Track function calls
	local attempt_xfrm_called="${TEST_DIR}/attempt_xfrm_called"
	local select_strategy_called="${TEST_DIR}/select_strategy_called"

	# Mock attempt_xfrm_recovery to fail
	attempt_xfrm_recovery() {
		echo "called" >"$attempt_xfrm_called"
		return 1
	}

	# Mock select_recovery_strategy to fail (no fallback available)
	# Arguments: $1 peer_ip, $2 tier, $3 result nameref. Returns: 1 no fallback.
	select_recovery_strategy() {
		echo "called" >"$select_strategy_called"
		local result_ref_name="$3"
		local -n result="$result_ref_name"
		result["strategy"]="unavailable"
		result["command"]=""
		result["impact"]=""
		result["available"]=0
		return 1
	}

	# Mock format_peer_ip_display
	format_peer_ip_display() {
		echo "$1"
	}

	# Test parameters
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"
	local tier=2
	declare -A recovery_info

	# Test function
	run _execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "" "ipsec reload"

	# Should return 2 (no fallback available)
	assert_failure
	assert_equal "$status" 2

	# Should call attempt_xfrm_recovery
	assert_file_exist "$attempt_xfrm_called"

	# Should call select_recovery_strategy for fallback
	assert_file_exist "$select_strategy_called"

	# Should log error message
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "xfrm recovery failed and no fallback strategy available"
}

# bats test_tags=category:high-risk,priority:high
@test "_execute_xfrm_recovery_with_fallback: returns 1 when xfrm fails and fallback strategy selected (Tier 3)" {
	# Purpose: Test verifies that function returns 1 when xfrm fails and fallback strategy is selected for Tier 3
	# Expected: Function returns 1, updates nameref array with fallback strategy, logs fallback message with Tier 3 prefix
	# Importance: Ensures Tier 3 fallback logic works correctly when xfrm recovery fails
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export ENABLE_XFRM_RECOVERY=1

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Track function calls
	local attempt_xfrm_called="${TEST_DIR}/attempt_xfrm_called"
	local select_strategy_called="${TEST_DIR}/select_strategy_called"
	local store_recovery_called="${TEST_DIR}/store_recovery_called"

	# Mock attempt_xfrm_recovery to fail
	attempt_xfrm_recovery() {
		echo "called" >"$attempt_xfrm_called"
		return 1
	}

	# Mock select_recovery_strategy to succeed (fallback available)
	# Arguments: $1 peer_ip, $2 tier, $3 result nameref. Returns: 0 success.
	select_recovery_strategy() {
		echo "called" >"$select_strategy_called"
		local result_ref_name="$3"
		local -n result="$result_ref_name"
		result["strategy"]="ipsec_restart"
		result["command"]="ipsec restart"
		result["impact"]="all-tunnels"
		result["available"]=1
		return 0
	}

	# Mock store_recovery_method (should be called before attempting recovery)
	store_recovery_method() {
		echo "called" >"$store_recovery_called"
	}

	# Mock format_peer_ip_display
	format_peer_ip_display() {
		echo "$1"
	}

	# Test parameters for Tier 3
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"
	local tier=3
	declare -A recovery_info

	# Test function - call directly (not via run) to preserve nameref array updates
	# Disable set -e to allow capturing return code 1
	set +e
	_execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "Tier 3: " "full restart"
	local exit_code=$?
	set -e

	# Should return 1 (fallback selected)
	assert_equal "$exit_code" 1

	# Should call attempt_xfrm_recovery
	assert_file_exist "$attempt_xfrm_called"

	# Should call store_recovery_method (Tier 3 stores if peer IP provided)
	assert_file_exist "$store_recovery_called"

	# Should call select_recovery_strategy for fallback (without peer IP)
	assert_file_exist "$select_strategy_called"

	# Should update nameref array with fallback strategy
	assert_equal "${recovery_info[strategy]}" "ipsec_restart"
	assert_equal "${recovery_info[command]}" "ipsec restart"
	assert_equal "${recovery_info[impact]}" "all-tunnels"
	assert_equal "${recovery_info[available]}" "1"

	# Should log fallback message with Tier 3 prefix
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tier 3: xfrm-based recovery failed"
	assert_file_contains "$LOG_FILE" "falling back to full restart"
}

# bats test_tags=category:high-risk,priority:high
@test "_execute_xfrm_recovery_with_fallback: returns 2 when xfrm fails and no fallback available (Tier 3)" {
	# Purpose: Test verifies that function returns 2 when xfrm fails and no fallback strategy is available for Tier 3
	# Expected: Function returns 2, logs error message with Tier 3 prefix, does not update nameref array
	# Importance: Ensures Tier 3 error handling works when no recovery options are available
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export ENABLE_XFRM_RECOVERY=1

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Track function calls
	local attempt_xfrm_called="${TEST_DIR}/attempt_xfrm_called"
	local select_strategy_called="${TEST_DIR}/select_strategy_called"
	local store_recovery_called="${TEST_DIR}/store_recovery_called"

	# Mock attempt_xfrm_recovery to fail
	attempt_xfrm_recovery() {
		echo "called" >"$attempt_xfrm_called"
		return 1
	}

	# Mock select_recovery_strategy to fail (no fallback available)
	# Arguments: $1 peer_ip, $2 tier, $3 result nameref. Returns: 1 no fallback.
	select_recovery_strategy() {
		echo "called" >"$select_strategy_called"
		local result_ref_name="$3"
		local -n result="$result_ref_name"
		result["strategy"]="unavailable"
		result["command"]=""
		result["impact"]=""
		result["available"]=0
		return 1
	}

	# Mock store_recovery_method (should be called before attempting recovery)
	store_recovery_method() {
		echo "called" >"$store_recovery_called"
	}

	# Mock format_peer_ip_display
	format_peer_ip_display() {
		echo "$1"
	}

	# Test parameters for Tier 3
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"
	local tier=3
	declare -A recovery_info

	# Test function
	run _execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "Tier 3: " "full restart"

	# Should return 2 (no fallback available)
	assert_failure
	assert_equal "$status" 2

	# Should call attempt_xfrm_recovery
	assert_file_exist "$attempt_xfrm_called"

	# Should call store_recovery_method (Tier 3 stores if peer IP provided)
	assert_file_exist "$store_recovery_called"

	# Should call select_recovery_strategy for fallback
	assert_file_exist "$select_strategy_called"

	# Should log error message with Tier 3 prefix
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tier 3: xfrm recovery failed and no fallback strategy available"
}

# ============================================================================
# TIER-SPECIFIC BEHAVIOR TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "_execute_xfrm_recovery_with_fallback: Tier 2 always stores recovery method" {
	# Purpose: Test verifies that Tier 2 always stores recovery method regardless of peer IP
	# Expected: store_recovery_method is called for Tier 2 even with empty peer IP
	# Importance: Ensures Tier 2 behavior is consistent
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export ENABLE_XFRM_RECOVERY=1

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Track function calls
	local store_recovery_called="${TEST_DIR}/store_recovery_called"

	# Mock attempt_xfrm_recovery to succeed
	attempt_xfrm_recovery() {
		return 0
	}

	# Mock store_recovery_method (should be called for Tier 2 even with empty peer IP)
	store_recovery_method() {
		echo "called" >"$store_recovery_called"
	}

	# Mock format_peer_ip_display
	format_peer_ip_display() {
		echo "$1"
	}

	# Test parameters - empty peer IP for Tier 2
	local external_peer_ip=""
	local location_name="TEST"
	local tier=2
	declare -A recovery_info

	# Test function
	run _execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "" "ipsec reload"

	# Should return 0 (success)
	assert_success

	# Should call store_recovery_method (Tier 2 always stores)
	assert_file_exist "$store_recovery_called"
}

# bats test_tags=category:high-risk,priority:high
@test "_execute_xfrm_recovery_with_fallback: log prefix is used in messages" {
	# Purpose: Test verifies that log prefix parameter is correctly used in log messages
	# Expected: Log messages include the provided log prefix
	# Importance: Ensures log prefix functionality works for different callers (surgical_cleanup vs full_restart)
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export ENABLE_XFRM_RECOVERY=1

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock attempt_xfrm_recovery to succeed
	attempt_xfrm_recovery() {
		return 0
	}

	# Mock format_peer_ip_display
	format_peer_ip_display() {
		echo "$1"
	}

	# Test parameters with custom log prefix
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"
	local tier=3
	declare -A recovery_info
	local log_prefix="Tier 3: "

	# Test function
	run _execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "$log_prefix" "full restart"

	# Should return 0 (success)
	assert_success

	# Should log messages with prefix
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tier 3: Attempting xfrm-based per-connection recovery"
	assert_file_contains "$LOG_FILE" "Tier 3: xfrm-based per-connection recovery successful"
}

# bats test_tags=category:high-risk,priority:high
@test "_execute_xfrm_recovery_with_fallback: fallback action description is used in log messages" {
	# Purpose: Test verifies that fallback action description parameter is correctly used in log messages
	# Expected: Log messages include the provided fallback action description
	# Importance: Ensures fallback action description is correctly displayed for different scenarios
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export ENABLE_XFRM_RECOVERY=1

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock attempt_xfrm_recovery to fail
	attempt_xfrm_recovery() {
		return 1
	}

	# Mock select_recovery_strategy to succeed
	# Arguments: $1 peer_ip, $2 tier, $3 result nameref. Returns: 0 success.
	select_recovery_strategy() {
		local result_ref_name="$3"
		local -n result="$result_ref_name"
		result["strategy"]="ipsec_reload"
		result["command"]="ipsec reload"
		result["impact"]="all-tunnels"
		result["available"]=1
		return 0
	}

	# Mock format_peer_ip_display
	format_peer_ip_display() {
		echo "$1"
	}

	# Test parameters with custom fallback action
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"
	local tier=2
	declare -A recovery_info
	local fallback_action="ipsec reload (affects all tunnels)"

	# Test function
	run _execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "" "$fallback_action"

	# Should return 1 (fallback selected)
	assert_failure
	assert_equal "$status" 1

	# Should log fallback message with custom action description
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "falling back to ipsec reload (affects all tunnels)"
}

# ============================================================================
# EDGE CASES
# ============================================================================

# bats test_tags=category:high-risk,priority:medium
@test "_execute_xfrm_recovery_with_fallback: handles empty location name" {
	# Purpose: Test verifies that function handles empty location name gracefully
	# Expected: Function works with empty location name (used in logging)
	# Importance: Ensures function is robust to edge case inputs
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export ENABLE_XFRM_RECOVERY=1

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock attempt_xfrm_recovery to succeed
	attempt_xfrm_recovery() {
		return 0
	}

	# Mock format_peer_ip_display
	format_peer_ip_display() {
		echo "$1"
	}

	# Test parameters with empty location name
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name=""
	local tier=2
	declare -A recovery_info

	# Test function
	run _execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "" "ipsec reload"

	# Should return 0 (success) - empty location name should not cause failure
	assert_success
}

# bats test_tags=category:high-risk,priority:medium
@test "_execute_xfrm_recovery_with_fallback: nameref array is properly initialized before updates" {
	# Purpose: Test verifies that nameref array is properly handled even if not pre-initialized
	# Expected: Function updates nameref array correctly when fallback is selected
	# Importance: Ensures nameref array handling is robust
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export ENABLE_XFRM_RECOVERY=1

	# Initialize logging
	LOG_FILE="${TEST_DIR}/vpn-monitor.log"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "$LOGS_DIR"

	# Mock attempt_xfrm_recovery to fail
	attempt_xfrm_recovery() {
		return 1
	}

	# Mock select_recovery_strategy to succeed
	# Arguments: $1 peer_ip, $2 tier, $3 result nameref. Returns: 0 success.
	select_recovery_strategy() {
		local result_ref_name="$3"
		local -n result="$result_ref_name"
		result["strategy"]="ipsec_restart"
		result["command"]="ipsec restart"
		result["impact"]="all-tunnels"
		result["available"]=1
		return 0
	}

	# Mock format_peer_ip_display
	format_peer_ip_display() {
		echo "$1"
	}

	# Test parameters - declare array but don't initialize values
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"
	local tier=3
	declare -A recovery_info
	# Don't initialize array values - let function handle it

	# Test function - call directly (not via run) to preserve nameref array updates
	# Disable set -e to allow capturing return code 1
	set +e
	_execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "Tier 3: " "full restart"
	local exit_code=$?
	set -e

	# Should return 1 (fallback selected)
	assert_equal "$exit_code" 1

	# Should update nameref array with fallback strategy
	assert_equal "${recovery_info[strategy]}" "ipsec_restart"
	assert_equal "${recovery_info[command]}" "ipsec restart"
	assert_equal "${recovery_info[impact]}" "all-tunnels"
	assert_equal "${recovery_info[available]}" "1"
}
