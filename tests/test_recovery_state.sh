#!/usr/bin/env bats
#
# Tests for Recovery State Management Functions
# Tests recovery method tracking and peer display formatting
#
# Version: 0.7.0

load test_helper
load helpers/test_data
load helpers/assertions

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# STORE_RECOVERY_METHOD TESTS
# ============================================================================

# bats test_tags=category:unit
@test "store_recovery_method - stores valid recovery method (xfrm)" {
	# Purpose: Test verifies that store_recovery_method stores valid xfrm recovery method
	# Expected: Function calls set_peer_state_non_critical with correct parameters
	# Importance: Recovery method tracking enables logging which method succeeded
	local location_name="TEST"
	local peer_ip="${TEST_PEER_IP}"
	local recovery_method="xfrm"
	local stored_value=""

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock set_peer_state_non_critical to capture calls
	# Use a file to store the value since subshells can't modify parent variables
	local mock_file="${TEST_DIR}/mock_stored_value"
	# Mock function to simulate setting peer state non-critical value
	#
	# Arguments:
	#   $1: Location name
	#   $2: Peer IP address
	#   $3: State key
	#   $4: State value
	#
	# Returns:
	#   0: Always succeeds
	set_peer_state_non_critical() {
		if [[ "$1" == "$location_name" ]] && [[ "$2" == "$peer_ip" ]] && [[ "$3" == "recovery_method" ]] && [[ "$4" == "$recovery_method" ]]; then
			echo "$4" >"$mock_file"
		fi
	}
	export -f set_peer_state_non_critical

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run store_recovery_method "$location_name" "$peer_ip" "$recovery_method"
	assert_success
	if [[ -f "$mock_file" ]]; then
		stored_value=$(cat "$mock_file")
	fi
	assert_equal "$stored_value" "$recovery_method"
}

# bats test_tags=category:unit
@test "store_recovery_method - stores valid recovery method (ipsec_reload)" {
	# Purpose: Test verifies that store_recovery_method stores valid ipsec_reload recovery method
	# Expected: Function calls set_peer_state_non_critical with correct parameters
	# Importance: Ensures all valid recovery methods can be stored
	local location_name="TEST"
	local peer_ip="${TEST_PEER_IP}"
	local recovery_method="ipsec_reload"
	local stored_value=""

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock set_peer_state_non_critical to capture calls
	# Use a file to store the value since subshells can't modify parent variables
	local mock_file="${TEST_DIR}/mock_stored_value2"
	# Mock function to simulate setting peer state non-critical value
	#
	# Arguments:
	#   $1: Location name
	#   $2: Peer IP address
	#   $3: State key
	#   $4: State value
	#
	# Returns:
	#   0: Always succeeds
	set_peer_state_non_critical() {
		if [[ "$1" == "$location_name" ]] && [[ "$2" == "$peer_ip" ]] && [[ "$3" == "recovery_method" ]] && [[ "$4" == "$recovery_method" ]]; then
			echo "$4" >"$mock_file"
		fi
	}
	export -f set_peer_state_non_critical

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run store_recovery_method "$location_name" "$peer_ip" "$recovery_method"
	assert_success
	if [[ -f "$mock_file" ]]; then
		stored_value=$(cat "$mock_file")
	fi
	assert_equal "$stored_value" "$recovery_method"
}

# bats test_tags=category:unit
@test "store_recovery_method - stores valid recovery method (ipsec_restart)" {
	# Purpose: Test verifies that store_recovery_method stores valid ipsec_restart recovery method
	# Expected: Function calls set_peer_state_non_critical with correct parameters
	# Importance: Ensures all valid recovery methods can be stored
	local location_name="TEST"
	local peer_ip="${TEST_PEER_IP}"
	local recovery_method="ipsec_restart"
	local stored_value=""

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock set_peer_state_non_critical to capture calls
	# Use a file to store the value since subshells can't modify parent variables
	local mock_file="${TEST_DIR}/mock_stored_value3"
	# Mock function to simulate setting peer state non-critical value
	#
	# Arguments:
	#   $1: Location name
	#   $2: Peer IP address
	#   $3: State key
	#   $4: State value
	#
	# Returns:
	#   0: Always succeeds
	set_peer_state_non_critical() {
		if [[ "$1" == "$location_name" ]] && [[ "$2" == "$peer_ip" ]] && [[ "$3" == "recovery_method" ]] && [[ "$4" == "$recovery_method" ]]; then
			echo "$4" >"$mock_file"
		fi
	}
	export -f set_peer_state_non_critical

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run store_recovery_method "$location_name" "$peer_ip" "$recovery_method"
	assert_success
	if [[ -f "$mock_file" ]]; then
		stored_value=$(cat "$mock_file")
	fi
	assert_equal "$stored_value" "$recovery_method"
}

# bats test_tags=category:unit
@test "store_recovery_method - skips empty recovery method" {
	# Purpose: Test verifies that store_recovery_method skips storing when recovery method is empty
	# Expected: Function returns success but does not call set_peer_state_non_critical
	# Importance: Empty recovery methods should not be stored
	local location_name="TEST"
	local peer_ip="${TEST_PEER_IP}"
	local recovery_method=""
	local was_called=0

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock set_peer_state_non_critical to track calls
	# Use a file to track calls since subshells can't modify parent variables
	local mock_file="${TEST_DIR}/mock_called_empty_method"
	# Mock function to track calls to set_peer_state_non_critical
	#
	# Arguments:
	#   $@: All arguments passed to function
	#
	# Returns:
	#   0: Always succeeds
	set_peer_state_non_critical() {
		touch "$mock_file"
	}
	export -f set_peer_state_non_critical

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run store_recovery_method "$location_name" "$peer_ip" "$recovery_method"
	assert_success
	# Function should skip when recovery_method is empty, so mock should not be called
	if [[ -f "$mock_file" ]]; then
		was_called=1
	fi
	assert_equal "$was_called" 0
}

# bats test_tags=category:unit
@test "store_recovery_method - handles missing state functions gracefully" {
	# Purpose: Test verifies that store_recovery_method handles missing set_peer_state_non_critical gracefully
	# Expected: Function returns success even when state function is unavailable
	# Importance: Recovery method storage is non-critical and should not fail if state functions are missing
	local location_name="TEST"
	local peer_ip="${TEST_PEER_IP}"
	local recovery_method="xfrm"

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Ensure set_peer_state_non_critical is not available
	unset -f set_peer_state_non_critical 2>/dev/null || true

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run store_recovery_method "$location_name" "$peer_ip" "$recovery_method"
	assert_success
}

# bats test_tags=category:unit
@test "store_recovery_method - handles empty location_name gracefully" {
	# Purpose: Test verifies that store_recovery_method handles empty location_name gracefully
	# Expected: Function returns success and calls set_peer_state_non_critical with empty location
	# Importance: Empty location names should be handled without errors
	local location_name=""
	local peer_ip="${TEST_PEER_IP}"
	local recovery_method="xfrm"
	local was_called=0

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock set_peer_state_non_critical to track calls
	# Use a file to track calls since subshells can't modify parent variables
	local mock_file="${TEST_DIR}/mock_called_empty_loc"
	# Mock function to track calls to set_peer_state_non_critical
	#
	# Arguments:
	#   $@: All arguments passed to function
	#
	# Returns:
	#   0: Always succeeds
	set_peer_state_non_critical() {
		touch "$mock_file"
	}
	export -f set_peer_state_non_critical

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run store_recovery_method "$location_name" "$peer_ip" "$recovery_method"
	assert_success
	if [[ -f "$mock_file" ]]; then
		was_called=1
	fi
	assert_equal "$was_called" 1
}

# bats test_tags=category:unit
@test "store_recovery_method - handles empty peer_ip gracefully" {
	# Purpose: Test verifies that store_recovery_method handles empty peer_ip gracefully
	# Expected: Function returns success and calls set_peer_state_non_critical with empty peer_ip
	# Importance: Empty peer IPs should be handled without errors
	local location_name="TEST"
	local peer_ip=""
	local recovery_method="xfrm"
	local was_called=0

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock set_peer_state_non_critical to track calls
	# Use a file to track calls since subshells can't modify parent variables
	local mock_file="${TEST_DIR}/mock_called_empty_ip"
	# Mock function to track calls to set_peer_state_non_critical
	#
	# Arguments:
	#   $@: All arguments passed to function
	#
	# Returns:
	#   0: Always succeeds
	set_peer_state_non_critical() {
		touch "$mock_file"
	}
	export -f set_peer_state_non_critical

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run store_recovery_method "$location_name" "$peer_ip" "$recovery_method"
	assert_success
	if [[ -f "$mock_file" ]]; then
		was_called=1
	fi
	assert_equal "$was_called" 1
}

# ============================================================================
# GET_RECOVERY_METHOD TESTS
# ============================================================================

# bats test_tags=category:unit
@test "get_recovery_method - retrieves stored recovery method" {
	# Purpose: Test verifies that get_recovery_method retrieves stored recovery method
	# Expected: Function returns the stored recovery method value
	# Importance: Recovery method retrieval enables logging which method succeeded
	local location_name="TEST"
	local peer_ip="${TEST_PEER_IP}"
	local expected_method="xfrm"

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock get_peer_state to return expected value
	# Mock function to simulate getting peer state value
	#
	# Arguments:
	#   $1: Location name
	#   $2: Peer IP address
	#   $3: State key
	#
	# Returns:
	#   0: Always succeeds
	#
	# Outputs:
	#   State value to stdout if found, empty string otherwise
	get_peer_state() {
		if [[ "$1" == "$location_name" ]] && [[ "$2" == "$peer_ip" ]] && [[ "$3" == "recovery_method" ]]; then
			echo "$expected_method"
		else
			echo ""
		fi
	}

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run get_recovery_method "$location_name" "$peer_ip"
	assert_success
	assert_output "$expected_method"
}

# bats test_tags=category:unit
@test "get_recovery_method - returns empty for non-existent recovery method" {
	# Purpose: Test verifies that get_recovery_method returns empty string when no recovery method is stored
	# Expected: Function returns empty string
	# Importance: Non-existent recovery methods should return empty, not error
	local location_name="TEST"
	local peer_ip="${TEST_PEER_IP}"

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock get_peer_state to return empty (default)
	# Mock function to simulate getting peer state value (returns empty)
	#
	# Arguments:
	#   $1: Location name
	#   $2: Peer IP address
	#   $3: State key
	#
	# Returns:
	#   0: Always succeeds
	#
	# Outputs:
	#   Empty string to stdout
	get_peer_state() {
		if [[ "$1" == "$location_name" ]] && [[ "$2" == "$peer_ip" ]] && [[ "$3" == "recovery_method" ]]; then
			echo ""
		else
			echo ""
		fi
	}

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run get_recovery_method "$location_name" "$peer_ip"
	assert_success
	assert_output ""
}

# bats test_tags=category:unit
@test "get_recovery_method - handles missing state functions gracefully" {
	# Purpose: Test verifies that get_recovery_method handles missing get_peer_state gracefully
	# Expected: Function returns empty string when state function is unavailable
	# Importance: Recovery method retrieval should not fail if state functions are missing
	local location_name="TEST"
	local peer_ip="${TEST_PEER_IP}"

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Ensure get_peer_state is not available
	unset -f get_peer_state 2>/dev/null || true

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run get_recovery_method "$location_name" "$peer_ip"
	assert_success
	assert_output ""
}

# bats test_tags=category:unit
@test "get_recovery_method - handles empty location_name gracefully" {
	# Purpose: Test verifies that get_recovery_method handles empty location_name gracefully
	# Expected: Function returns empty string
	# Importance: Empty location names should be handled without errors
	local location_name=""
	local peer_ip="${TEST_PEER_IP}"

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock get_peer_state to return empty
	# Mock function to simulate getting peer state value (returns empty)
	#
	# Arguments:
	#   $@: All arguments passed to function
	#
	# Returns:
	#   0: Always succeeds
	#
	# Outputs:
	#   Empty string to stdout
	get_peer_state() {
		echo ""
	}

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run get_recovery_method "$location_name" "$peer_ip"
	assert_success
	assert_output ""
}

# bats test_tags=category:unit
@test "get_recovery_method - handles empty peer_ip gracefully" {
	# Purpose: Test verifies that get_recovery_method handles empty peer_ip gracefully
	# Expected: Function returns empty string
	# Importance: Empty peer IPs should be handled without errors
	local location_name="TEST"
	local peer_ip=""

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock get_peer_state to return empty
	# Mock function to simulate getting peer state value (returns empty)
	#
	# Arguments:
	#   $@: All arguments passed to function
	#
	# Returns:
	#   0: Always succeeds
	#
	# Outputs:
	#   Empty string to stdout
	get_peer_state() {
		echo ""
	}

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run get_recovery_method "$location_name" "$peer_ip"
	assert_success
	assert_output ""
}

# ============================================================================
# CLEAR_RECOVERY_METHOD TESTS
# ============================================================================

# bats test_tags=category:unit
@test "clear_recovery_method - clears existing recovery method" {
	# Purpose: Test verifies that clear_recovery_method clears existing recovery method
	# Expected: Function calls delete_peer_state with correct parameters
	# Importance: Recovery method cleanup prevents stale information from being displayed
	local location_name="TEST"
	local peer_ip="${TEST_PEER_IP}"
	local was_called=0
	local called_with_key=""

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock delete_peer_state to track calls
	# Use files to track calls since subshells can't modify parent variables
	local mock_file="${TEST_DIR}/mock_called_clear"
	local key_file="${TEST_DIR}/mock_key"
	# Mock function to simulate deleting peer state
	#
	# Arguments:
	#   $1: Location name
	#   $2: Peer IP address
	#   $3: State key
	#
	# Returns:
	#   0: Always succeeds
	delete_peer_state() {
		if [[ "$1" == "$location_name" ]] && [[ "$2" == "$peer_ip" ]] && [[ "$3" == "recovery_method" ]]; then
			touch "$mock_file"
			echo "$3" >"$key_file"
		fi
		return 0
	}
	export -f delete_peer_state

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run clear_recovery_method "$location_name" "$peer_ip"
	assert_success
	if [[ -f "$mock_file" ]]; then
		was_called=1
		called_with_key=$(cat "$key_file")
	fi
	assert_equal "$was_called" 1
	assert_equal "$called_with_key" "recovery_method"
}

# bats test_tags=category:unit
@test "clear_recovery_method - succeeds when recovery method doesn't exist" {
	# Purpose: Test verifies that clear_recovery_method succeeds when recovery method doesn't exist
	# Expected: Function returns success even when nothing to clear
	# Importance: Clearing non-existent recovery methods should not fail
	local location_name="TEST"
	local peer_ip="${TEST_PEER_IP}"

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock delete_peer_state to return success (file doesn't exist)
	# Mock function to simulate deleting peer state (always succeeds)
	#
	# Arguments:
	#   $@: All arguments passed to function
	#
	# Returns:
	#   0: Always succeeds
	delete_peer_state() {
		return 0
	}

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run clear_recovery_method "$location_name" "$peer_ip"
	assert_success
}

# bats test_tags=category:unit
@test "clear_recovery_method - handles missing state functions gracefully" {
	# Purpose: Test verifies that clear_recovery_method handles missing delete_peer_state gracefully
	# Expected: Function returns success even when state function is unavailable
	# Importance: Recovery method clearing is non-critical and should not fail if state functions are missing
	local location_name="TEST"
	local peer_ip="${TEST_PEER_IP}"

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Ensure delete_peer_state is not available
	unset -f delete_peer_state 2>/dev/null || true

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run clear_recovery_method "$location_name" "$peer_ip"
	assert_success
}

# bats test_tags=category:unit
@test "clear_recovery_method - handles empty location_name gracefully" {
	# Purpose: Test verifies that clear_recovery_method handles empty location_name gracefully
	# Expected: Function returns success and calls delete_peer_state with empty location
	# Importance: Empty location names should be handled without errors
	local location_name=""
	local peer_ip="${TEST_PEER_IP}"
	local was_called=0

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock delete_peer_state to track calls
	# Use a file to track calls since subshells can't modify parent variables
	local mock_file="${TEST_DIR}/mock_called_clear_empty_loc"
	# Mock function to track calls to delete_peer_state
	#
	# Arguments:
	#   $@: All arguments passed to function
	#
	# Returns:
	#   0: Always succeeds
	delete_peer_state() {
		touch "$mock_file"
		return 0
	}
	export -f delete_peer_state

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run clear_recovery_method "$location_name" "$peer_ip"
	assert_success
	if [[ -f "$mock_file" ]]; then
		was_called=1
	fi
	assert_equal "$was_called" 1
}

# bats test_tags=category:unit
@test "clear_recovery_method - handles empty peer_ip gracefully" {
	# Purpose: Test verifies that clear_recovery_method handles empty peer_ip gracefully
	# Expected: Function returns success and calls delete_peer_state with empty peer_ip
	# Importance: Empty peer IPs should be handled without errors
	local location_name="TEST"
	local peer_ip=""
	local was_called=0

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock delete_peer_state to track calls
	# Use a file to track calls since subshells can't modify parent variables
	local mock_file="${TEST_DIR}/mock_called_clear_empty_ip"
	# Mock function to track calls to delete_peer_state
	#
	# Arguments:
	#   $@: All arguments passed to function
	#
	# Returns:
	#   0: Always succeeds
	delete_peer_state() {
		touch "$mock_file"
		return 0
	}
	export -f delete_peer_state

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run clear_recovery_method "$location_name" "$peer_ip"
	assert_success
	if [[ -f "$mock_file" ]]; then
		was_called=1
	fi
	assert_equal "$was_called" 1
}

# ============================================================================
# FORMAT_RECOVERY_METHOD TESTS
# ============================================================================

# bats test_tags=category:unit
@test "format_recovery_method - formats xfrm method" {
	# Purpose: Test verifies that format_recovery_method formats xfrm method correctly
	# Expected: Function returns "xfrm-based recovery"
	# Importance: Recovery method formatting enables user-friendly log messages
	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	run format_recovery_method "xfrm"
	assert_success
	assert_output "xfrm-based recovery"
}

# bats test_tags=category:unit
@test "format_recovery_method - formats ipsec_reload method" {
	# Purpose: Test verifies that format_recovery_method formats ipsec_reload method correctly
	# Expected: Function returns "ipsec reload"
	# Importance: Ensures all valid recovery methods are formatted correctly
	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	run format_recovery_method "ipsec_reload"
	assert_success
	assert_output "ipsec reload"
}

# bats test_tags=category:unit
@test "format_recovery_method - formats ipsec_restart method" {
	# Purpose: Test verifies that format_recovery_method formats ipsec_restart method correctly
	# Expected: Function returns "ipsec restart"
	# Importance: Ensures all valid recovery methods are formatted correctly
	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	run format_recovery_method "ipsec_restart"
	assert_success
	assert_output "ipsec restart"
}

# bats test_tags=category:unit
@test "format_recovery_method - returns unknown recovery method for empty string" {
	# Purpose: Test verifies that format_recovery_method returns "unknown recovery method" for empty string
	# Expected: Function returns "unknown recovery method"
	# Importance: Empty recovery methods should display a user-friendly message
	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	run format_recovery_method ""
	assert_success
	assert_output "unknown recovery method"
}

# bats test_tags=category:unit
@test "format_recovery_method - returns string as-is for unknown non-empty method" {
	# Purpose: Test verifies that format_recovery_method returns unknown method string as-is
	# Expected: Function returns the input string unchanged
	# Importance: Unknown recovery methods should be displayed as-is for debugging
	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	run format_recovery_method "unknown_method"
	assert_success
	assert_output "unknown_method"
}

# bats test_tags=category:unit
@test "format_recovery_method - handles invalid characters in method name" {
	# Purpose: Test verifies that format_recovery_method handles invalid characters in method name
	# Expected: Function returns the input string as-is
	# Importance: Invalid method names should be displayed as-is for debugging
	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	run format_recovery_method "method-with-special-chars_123"
	assert_success
	assert_output "method-with-special-chars_123"
}

# ============================================================================
# FORMAT_PEER_DISPLAY TESTS
# ============================================================================

# bats test_tags=category:unit
@test "format_peer_display - returns IP address without connection name" {
	# Purpose: Test verifies that format_peer_display returns IP address when connection name is not found
	# Expected: Function returns just the IP address
	# Importance: Peer display formatting provides consistent logging format
	local peer_ip="${TEST_PEER_IP}"

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock discover_connection_name to return empty (connection not found)
	# Mock function to simulate discovering connection name (returns empty)
	#
	# Arguments:
	#   $1: Peer IP address
	#
	# Returns:
	#   0: Always succeeds
	#
	# Outputs:
	#   Empty string to stdout
	discover_connection_name() {
		echo ""
	}

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run format_peer_display "$peer_ip"
	assert_success
	assert_output "$peer_ip"
}

# bats test_tags=category:unit
@test "format_peer_display - returns IP address with connection name" {
	# Purpose: Test verifies that format_peer_display returns IP address with connection name when found
	# Expected: Function returns "IP (conn: connection_name)"
	# Importance: Connection names provide better debugging information in logs
	local peer_ip="${TEST_PEER_IP}"
	local conn_name="site-a"
	local expected_output="${peer_ip} (conn: ${conn_name})"

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock discover_connection_name by creating a script in PATH
	# command -v will find scripts in PATH, which is more reliable than exported functions
	local mock_script="${TEST_DIR}/discover_connection_name"
	cat >"$mock_script" <<EOF
#!/bin/bash
if [[ "\$1" == "$peer_ip" ]]; then
	echo "$conn_name"
else
	echo ""
fi
EOF
	chmod +x "$mock_script"
	export PATH="${TEST_DIR}:${PATH}"

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run format_peer_display "$peer_ip"
	assert_success
	assert_output "$expected_output"
}

# bats test_tags=category:unit
@test "format_peer_display - handles invalid IP format gracefully" {
	# Purpose: Test verifies that format_peer_display handles invalid IP format gracefully
	# Expected: Function returns the input string (possibly with connection name if found)
	# Importance: Invalid IP formats should not cause errors
	local invalid_ip="not.an.ip.address"

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock discover_connection_name to return empty
	# Mock function to simulate discovering connection name (returns empty)
	#
	# Arguments:
	#   $1: Peer IP address
	#
	# Returns:
	#   0: Always succeeds
	#
	# Outputs:
	#   Empty string to stdout
	discover_connection_name() {
		echo ""
	}

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run format_peer_display "$invalid_ip"
	assert_success
	assert_output "$invalid_ip"
}

# bats test_tags=category:unit
@test "format_peer_display - handles missing discover_connection_name function gracefully" {
	# Purpose: Test verifies that format_peer_display handles missing discover_connection_name gracefully
	# Expected: Function returns just the IP address
	# Importance: Missing discovery function should not cause errors
	local peer_ip="${TEST_PEER_IP}"

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Ensure discover_connection_name is not available
	unset -f discover_connection_name 2>/dev/null || true

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run format_peer_display "$peer_ip"
	assert_success
	assert_output "$peer_ip"
}

# bats test_tags=category:unit
@test "format_peer_display - handles empty peer IP gracefully" {
	# Purpose: Test verifies that format_peer_display handles empty peer IP gracefully
	# Expected: Function returns empty string
	# Importance: Empty peer IPs should be handled without errors
	local peer_ip=""

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock discover_connection_name to return empty
	# Mock function to simulate discovering connection name (returns empty)
	#
	# Arguments:
	#   $1: Peer IP address
	#
	# Returns:
	#   0: Always succeeds
	#
	# Outputs:
	#   Empty string to stdout
	discover_connection_name() {
		echo ""
	}

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run format_peer_display "$peer_ip"
	assert_success
	assert_output ""
}

# bats test_tags=category:unit
@test "format_peer_display - handles discover_connection_name failure gracefully" {
	# Purpose: Test verifies that format_peer_display handles discover_connection_name failure gracefully
	# Expected: Function returns just the IP address when discovery fails
	# Importance: Discovery failures should not prevent peer display formatting
	local peer_ip="${TEST_PEER_IP}"

	# Set up required environment variables
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR

	# Mock discover_connection_name to fail
	# Mock function to simulate discovering connection name (fails)
	#
	# Arguments:
	#   $1: Peer IP address
	#
	# Returns:
	#   1: Always fails
	discover_connection_name() {
		return 1
	}

	# Source the function directly from recovery_state.sh
	# shellcheck source=../lib/recovery/recovery_state.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery/recovery_state.sh" 2>/dev/null || true

	# Run the function
	run format_peer_display "$peer_ip"
	assert_success
	assert_output "$peer_ip"
}
