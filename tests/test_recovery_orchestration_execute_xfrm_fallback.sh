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

	# Mock attempt_xfrm_recovery to succeed (no real xfrm stack in unit context)
	attempt_xfrm_recovery() {
		return 0
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

	# Per-connection recovery method persisted (Tier 2 stores even when other checks differ)
	assert_equal "$(get_recovery_method "TEST" "$external_peer_ip")" "xfrm"

	# Should NOT write global restart count (Tier 2 path does not record restarts for rate limit)
	[[ ! -e "$RESTART_COUNT_FILE" ]]

	# Logged attempt + success (behavior, not call chain to mocks)
	# format_peer_ip_display() wraps the peer (external-only) in parentheses
	assert_log_contains "$LOG_FILE" "Attempting xfrm-based per-connection recovery for ($external_peer_ip)"
	assert_log_contains "$LOG_FILE" "xfrm-based surgical cleanup completed successfully for ($external_peer_ip)"
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

	# Mock attempt_xfrm_recovery to succeed (no real xfrm stack in unit context)
	attempt_xfrm_recovery() {
		return 0
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

	assert_equal "$(get_recovery_method "TEST" "$external_peer_ip")" "xfrm"
	# Tier 3 appends a restart timestamp for global rate limiting
	[[ -s "$RESTART_COUNT_FILE" ]]

	assert_log_contains "$LOG_FILE" "Tier 3: Attempting xfrm-based per-connection recovery for ($external_peer_ip)"
	assert_log_contains "$LOG_FILE" "Tier 3: xfrm-based per-connection recovery successful for ($external_peer_ip)"
}

# bats test_tags=category:high-risk,priority:high
@test "_execute_xfrm_recovery_with_fallback: Tier 3 does not store recovery method when peer IP is empty" {
	# Purpose: When peer IP is empty, no per-peer recovery_method state key is written, but xfrm+restart still run.
	# Importance: Tier 3 full_restart allows empty external peer; state layer cannot name a per-peer file without an IP
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export ENABLE_XFRM_RECOVERY=1

	# Mock attempt_xfrm_recovery to succeed (no real xfrm stack in unit context)
	attempt_xfrm_recovery() {
		return 0
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

	assert_equal "$(get_recovery_method "TEST" "")" ""
	[[ -s "$RESTART_COUNT_FILE" ]]
	assert_log_contains "$LOG_FILE" "Tier 3: xfrm-based per-connection recovery successful"
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

	# Mock attempt_xfrm_recovery to fail
	attempt_xfrm_recovery() {
		return 1
	}

	# Mock select_recovery_strategy to succeed (fallback available)
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

	# Test parameters
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"
	local tier=2
	declare -A recovery_info

	# Call directly (not via run) to preserve nameref array updates; Bats may fail a non-zero return, so capture with ||
	local exit_code=0
	_execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "" "ipsec reload (affects all tunnels)" || exit_code=$?

	assert_equal "$exit_code" 1

	# Observable outcome: recovery_info reflects the chosen all-tunnels fallback strategy
	assert_equal "${recovery_info[strategy]}" "ipsec_reload"
	assert_equal "${recovery_info[command]}" "ipsec reload"
	assert_equal "${recovery_info[impact]}" "all-tunnels"
	assert_equal "${recovery_info[available]}" "1"

	# Storing "xfrm" is attempted before xfrm run; with failed xfrm, method remains xfrm in state
	assert_equal "$(get_recovery_method "TEST" "$external_peer_ip")" "xfrm"

	assert_log_contains "$LOG_FILE" "Attempting xfrm-based per-connection recovery for ($external_peer_ip)"
	assert_log_contains "$LOG_FILE" "xfrm-based recovery failed for ($external_peer_ip)"
	assert_log_contains "$LOG_FILE" "falling back to ipsec reload (affects all tunnels)"
}

# bats test_tags=category:high-risk,priority:high
@test "_execute_xfrm_recovery_with_fallback: fallback uses all-tunnels strategy (nameref, not per-peer IP)" {
	# Purpose: When xfrm fails, the flow selects a non-surgical (all-tunnels) strategy; the nameref is what downstream runs.
	# Importance: Same behavior whether or not the caller had a peer IP; impact must be "all-tunnels" for the fallback arm
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export ENABLE_XFRM_RECOVERY=1

	# Mock attempt_xfrm_recovery to fail
	attempt_xfrm_recovery() {
		return 1
	}

	# Mock select_recovery_strategy
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

	# Test parameters
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"
	local tier=2
	declare -A recovery_info

	local exit_code=0
	_execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "" "ipsec reload" || exit_code=$?

	assert_equal "$exit_code" 1
	assert_equal "${recovery_info[impact]}" "all-tunnels"
	assert_log_contains "$LOG_FILE" "xfrm-based recovery failed for ($external_peer_ip)"
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

	# Mock attempt_xfrm_recovery to fail
	attempt_xfrm_recovery() {
		return 1
	}

	# Mock select_recovery_strategy to fail (no fallback available)
	# Arguments: $1 peer_ip, $2 tier, $3 result nameref. Returns: 1 no fallback.
	select_recovery_strategy() {
		local result_ref_name="$3"
		local -n result="$result_ref_name"
		result["strategy"]="unavailable"
		result["command"]=""
		result["impact"]=""
		result["available"]=0
		return 1
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

	assert_equal "$(get_recovery_method "TEST" "$external_peer_ip")" "xfrm"
	assert_log_contains "$LOG_FILE" "xfrm recovery failed and no fallback strategy available"
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

	# Mock attempt_xfrm_recovery to fail
	attempt_xfrm_recovery() {
		return 1
	}

	# Mock select_recovery_strategy to succeed (fallback available)
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

	# Test parameters for Tier 3
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"
	local tier=3
	declare -A recovery_info

	local exit_code=0
	_execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "Tier 3: " "full restart" || exit_code=$?

	assert_equal "$exit_code" 1

	assert_equal "${recovery_info[strategy]}" "ipsec_restart"
	assert_equal "${recovery_info[command]}" "ipsec restart"
	assert_equal "${recovery_info[impact]}" "all-tunnels"
	assert_equal "${recovery_info[available]}" "1"

	assert_equal "$(get_recovery_method "TEST" "$external_peer_ip")" "xfrm"
	assert_log_contains "$LOG_FILE" "Tier 3: xfrm-based recovery failed for ($external_peer_ip)"
	assert_log_contains "$LOG_FILE" "falling back to full restart"
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

	# Mock attempt_xfrm_recovery to fail
	attempt_xfrm_recovery() {
		return 1
	}

	# Mock select_recovery_strategy to fail (no fallback available)
	# Arguments: $1 peer_ip, $2 tier, $3 result nameref. Returns: 1 no fallback.
	select_recovery_strategy() {
		local result_ref_name="$3"
		local -n result="$result_ref_name"
		result["strategy"]="unavailable"
		result["command"]=""
		result["impact"]=""
		result["available"]=0
		return 1
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

	assert_equal "$(get_recovery_method "TEST" "$external_peer_ip")" "xfrm"
	assert_log_contains "$LOG_FILE" "Tier 3: xfrm recovery failed and no fallback strategy available"
}

# ============================================================================
# TIER-SPECIFIC BEHAVIOR TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "_execute_xfrm_recovery_with_fallback: Tier 2 with empty peer completes; no per-peer recovery_method on disk" {
	# Purpose: Tier 2 still attempts store_recovery_method, but the state layer has no per-peer file without a peer id.
	# Importance: Orchestration tolerates full_restart-style empty peer on Tier 2; success is still logged
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_recovery_module

	# Set up config
	export ENABLE_XFRM_RECOVERY=1

	# Test stub: mock successful xfrm recovery for _execute_xfrm_recovery_with_fallback.
	#
	# Returns:
	# 0: success
	attempt_xfrm_recovery() {
		return 0
	}

	# Test parameters - empty peer IP for Tier 2
	local external_peer_ip=""
	local location_name="TEST"
	local tier=2
	declare -A recovery_info

	run _execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "" "ipsec reload"

	assert_success
	assert_equal "$(get_recovery_method "TEST" "")" ""
	[[ ! -e "$RESTART_COUNT_FILE" ]]
	assert_log_contains "$LOG_FILE" "xfrm-based surgical cleanup completed successfully"
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

	# Test stub: mock successful xfrm recovery for _execute_xfrm_recovery_with_fallback.
	#
	# Returns:
	# 0: success
	attempt_xfrm_recovery() {
		return 0
	}

	# Test parameters with custom log prefix
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"
	local tier=3
	declare -A recovery_info
	local log_prefix="Tier 3: "

	run _execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "$log_prefix" "full restart"

	assert_success
	assert_log_contains "$LOG_FILE" "Tier 3: Attempting xfrm-based per-connection recovery for ($external_peer_ip)"
	assert_log_contains "$LOG_FILE" "Tier 3: xfrm-based per-connection recovery successful for ($external_peer_ip)"
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

	# Test stub: mock failed xfrm recovery so fallback path is exercised.
	#
	# Returns:
	# 1: simulated xfrm failure
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

	# Test parameters with custom fallback action
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"
	local tier=2
	declare -A recovery_info
	local fallback_action="ipsec reload (affects all tunnels)"

	run _execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "" "$fallback_action"

	assert_failure
	assert_equal "$status" 1
	assert_log_contains "$LOG_FILE" "falling back to $fallback_action"
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

	# Test stub: mock successful xfrm recovery for _execute_xfrm_recovery_with_fallback.
	#
	# Returns:
	# 0: success
	attempt_xfrm_recovery() {
		return 0
	}

	# Test parameters with empty location name
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name=""
	local tier=2
	declare -A recovery_info

	run _execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "" "ipsec reload"

	# Succeeds; empty location is invalid for get_peer_state_file_path, so per-peer recovery_method is not written
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

	# Test stub: mock failed xfrm recovery so fallback path is exercised.
	#
	# Returns:
	# 1: simulated xfrm failure
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

	# Test parameters - declare array but don't initialize values
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"
	local tier=3
	declare -A recovery_info

	local exit_code=0
	_execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" "$tier" "recovery_info" "Tier 3: " "full restart" || exit_code=$?

	assert_equal "$exit_code" 1
	assert_equal "${recovery_info[strategy]}" "ipsec_restart"
	assert_equal "${recovery_info[command]}" "ipsec restart"
	assert_equal "${recovery_info[impact]}" "all-tunnels"
	assert_equal "${recovery_info[available]}" "1"
	assert_equal "$(get_recovery_method "TEST" "$external_peer_ip")" "xfrm"
	assert_log_contains "$LOG_FILE" "Tier 3: xfrm-based recovery failed for ($external_peer_ip)"
}
