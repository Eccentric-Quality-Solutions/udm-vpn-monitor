#!/usr/bin/env bats
#
# Tests for build_ping_command() function
# Tests ping command building logic for IPv4 and IPv6 with various scenarios
#
# This test file covers:
# - IPv4 with/without source IP
# - IPv6 with ping6 available
# - IPv6 with ping -6 fallback
# - IPv6 when neither available (should return 1)
# - Empty target IP (should return 1)
# - Variable assignment in caller's scope

load test_helper

# Source the detection library functions
# shellcheck source=../lib/detection.sh
source "${BATS_TEST_DIRNAME}/../lib/detection.sh"

# Source common functions for check_command_available
# shellcheck source=../lib/common.sh
source "${BATS_TEST_DIRNAME}/../lib/common.sh"

# ============================================================================
# UNIT TESTS FOR build_ping_command()
# ============================================================================

# bats test_tags=category:unit,priority:medium
@test "build_ping_command - IPv4 without source IP" {
	# Purpose: Test that build_ping_command correctly builds IPv4 ping command without source IP
	# Expected: ping_cmd="ping", ping_args=()
	# Importance: Basic IPv4 functionality without source IP
	local ping_cmd
	local ping_args=()

	build_ping_command "192.168.1.1" ""
	local exit_code=$?
	assert_equal "$exit_code" 0
	assert_equal "$ping_cmd" "ping"
	assert_equal "${#ping_args[@]}" 0
}

# bats test_tags=category:unit,priority:medium
@test "build_ping_command - IPv4 with source IP" {
	# Purpose: Test that build_ping_command correctly builds IPv4 ping command with source IP
	# Expected: ping_cmd="ping", ping_args=(-I "192.168.1.100")
	# Importance: IPv4 functionality with source IP for routing through VPN tunnel
	local ping_cmd
	local ping_args=()

	build_ping_command "192.168.1.1" "192.168.1.100"
	local exit_code=$?
	assert_equal "$exit_code" 0
	assert_equal "$ping_cmd" "ping"
	assert_equal "${#ping_args[@]}" 2
	assert_equal "${ping_args[0]}" "-I"
	assert_equal "${ping_args[1]}" "192.168.1.100"
}

# bats test_tags=category:unit,priority:medium
@test "build_ping_command - IPv6 with ping6 available" {
	# Purpose: Test that build_ping_command uses ping6 when available for IPv6
	# Expected: ping_cmd="ping6", ping_args=()
	# Importance: IPv6 functionality with native ping6 command
	local ping_cmd
	local ping_args=()

	# Save original check_command_available if it exists
	if command -v check_command_available >/dev/null 2>&1; then
		local func_def
		func_def=$(declare -f check_command_available 2>/dev/null || true)
		if [[ -n "$func_def" ]]; then
			eval "${func_def/check_command_available/check_command_available.original}" 2>/dev/null || true
		fi
	fi

	# Mock check_command_available to return success for ping6
	# Mock function to simulate command availability check for ping6
	#
	# Arguments:
	#   $1: Command name to check
	#
	# Returns:
	#   0: Command is ping6 or original function returns success
	#   1: Command is not ping6 and original function returns failure
	check_command_available() {
		local cmd="$1"
		if [[ "$cmd" == "ping6" ]]; then
			return 0
		fi
		# For other commands, use original if available
		if command -v check_command_available.original >/dev/null 2>&1; then
			check_command_available.original "$@"
		else
			command -v "$cmd" >/dev/null 2>&1
		fi
	}

	build_ping_command "2001:db8::1" ""
	local exit_code=$?
	assert_equal "$exit_code" 0
	assert_equal "$ping_cmd" "ping6"
	assert_equal "${#ping_args[@]}" 0

	# Restore original function if it existed
	if command -v check_command_available.original >/dev/null 2>&1; then
		# Restore function to call original check_command_available
		#
		# Arguments:
		#   $@: All arguments passed to function
		#
		# Returns:
		#   Exit code from original function
		check_command_available() {
			check_command_available.original "$@"
		}
	fi
}

# bats test_tags=category:unit,priority:medium
@test "build_ping_command - IPv6 with ping6 available and source IP" {
	# Purpose: Test that build_ping_command uses ping6 with source IP when available
	# Expected: ping_cmd="ping6", ping_args=(-I "2001:db8::100")
	# Importance: IPv6 functionality with source IP using ping6
	local ping_cmd
	local ping_args=()

	# Save original check_command_available if it exists
	if command -v check_command_available >/dev/null 2>&1; then
		local func_def
		func_def=$(declare -f check_command_available 2>/dev/null || true)
		if [[ -n "$func_def" ]]; then
			eval "${func_def/check_command_available/check_command_available.original}" 2>/dev/null || true
		fi
	fi

	# Mock check_command_available to return success for ping6
	# Mock function to simulate command availability check for ping6
	#
	# Arguments:
	#   $1: Command name to check
	#
	# Returns:
	#   0: Command is ping6 or original function returns success
	#   1: Command is not ping6 and original function returns failure
	check_command_available() {
		local cmd="$1"
		if [[ "$cmd" == "ping6" ]]; then
			return 0
		fi
		# For other commands, use original if available
		if command -v check_command_available.original >/dev/null 2>&1; then
			check_command_available.original "$@"
		else
			command -v "$cmd" >/dev/null 2>&1
		fi
	}

	build_ping_command "2001:db8::1" "2001:db8::100"
	local exit_code=$?
	assert_equal "$exit_code" 0
	assert_equal "$ping_cmd" "ping6"
	assert_equal "${#ping_args[@]}" 2
	assert_equal "${ping_args[0]}" "-I"
	assert_equal "${ping_args[1]}" "2001:db8::100"

	# Restore original function if it existed
	if command -v check_command_available.original >/dev/null 2>&1; then
		# Restore function to call original check_command_available
		#
		# Arguments:
		#   $@: All arguments passed to function
		#
		# Returns:
		#   Exit code from original function
		check_command_available() {
			check_command_available.original "$@"
		}
	fi
}

# bats test_tags=category:unit,priority:medium
@test "build_ping_command - IPv6 with ping -6 fallback" {
	# Purpose: Test that build_ping_command falls back to ping -6 when ping6 not available
	# Expected: ping_cmd="ping", ping_args=(-6)
	# Importance: IPv6 functionality with fallback to ping -6
	local ping_cmd
	local ping_args=()

	# Save original check_command_available if it exists
	if command -v check_command_available >/dev/null 2>&1; then
		local func_def
		func_def=$(declare -f check_command_available 2>/dev/null || true)
		if [[ -n "$func_def" ]]; then
			eval "${func_def/check_command_available/check_command_available.original}" 2>/dev/null || true
		fi
	fi

	# Create mock ping that supports -6 flag
	cat >"${TEST_DIR}/ping" <<'EOF'
#!/bin/bash
# Mock ping that supports -6 flag
if [[ "$1" == "-6" ]]; then
	exit 0
fi
exit 1
EOF
	chmod +x "${TEST_DIR}/ping"
	add_mock_to_path

	# Mock check_command_available to return failure for ping6, success for ping
	# Mock function to simulate command availability check with ping6 unavailable
	#
	# Arguments:
	#   $1: Command name to check
	#
	# Returns:
	#   0: Command is ping or original function returns success
	#   1: Command is ping6 or original function returns failure
	check_command_available() {
		local cmd="$1"
		if [[ "$cmd" == "ping6" ]]; then
			return 1
		fi
		if [[ "$cmd" == "ping" ]]; then
			return 0
		fi
		# For other commands, use original if available
		if command -v check_command_available.original >/dev/null 2>&1; then
			check_command_available.original "$@"
		else
			command -v "$cmd" >/dev/null 2>&1
		fi
	}

	build_ping_command "2001:db8::1" ""
	local exit_code=$?
	assert_equal "$exit_code" 0
	assert_equal "$ping_cmd" "ping"
	assert_equal "${#ping_args[@]}" 1
	assert_equal "${ping_args[0]}" "-6"

	# Restore original function if it existed
	if command -v check_command_available.original >/dev/null 2>&1; then
		# Restore function to call original check_command_available
		#
		# Arguments:
		#   $@: All arguments passed to function
		#
		# Returns:
		#   Exit code from original function
		check_command_available() {
			check_command_available.original "$@"
		}
	fi

	remove_mock_from_path
}

# bats test_tags=category:unit,priority:medium
@test "build_ping_command - IPv6 with ping -6 fallback and source IP" {
	# Purpose: Test that build_ping_command falls back to ping -6 with source IP when ping6 not available
	# Expected: ping_cmd="ping", ping_args=(-6 -I "2001:db8::100")
	# Importance: IPv6 functionality with source IP using ping -6 fallback
	local ping_cmd
	local ping_args=()

	# Save original check_command_available if it exists
	if command -v check_command_available >/dev/null 2>&1; then
		local func_def
		func_def=$(declare -f check_command_available 2>/dev/null || true)
		if [[ -n "$func_def" ]]; then
			eval "${func_def/check_command_available/check_command_available.original}" 2>/dev/null || true
		fi
	fi

	# Create mock ping that supports -6 flag
	cat >"${TEST_DIR}/ping" <<'EOF'
#!/bin/bash
# Mock ping that supports -6 flag
if [[ "$1" == "-6" ]]; then
	exit 0
fi
exit 1
EOF
	chmod +x "${TEST_DIR}/ping"
	add_mock_to_path

	# Mock check_command_available to return failure for ping6, success for ping
	# Mock function to simulate command availability check with ping6 unavailable
	#
	# Arguments:
	#   $1: Command name to check
	#
	# Returns:
	#   0: Command is ping or original function returns success
	#   1: Command is ping6 or original function returns failure
	check_command_available() {
		local cmd="$1"
		if [[ "$cmd" == "ping6" ]]; then
			return 1
		fi
		if [[ "$cmd" == "ping" ]]; then
			return 0
		fi
		# For other commands, use original if available
		if command -v check_command_available.original >/dev/null 2>&1; then
			check_command_available.original "$@"
		else
			command -v "$cmd" >/dev/null 2>&1
		fi
	}

	build_ping_command "2001:db8::1" "2001:db8::100"
	local exit_code=$?
	assert_equal "$exit_code" 0
	assert_equal "$ping_cmd" "ping"
	assert_equal "${#ping_args[@]}" 3
	assert_equal "${ping_args[0]}" "-6"
	assert_equal "${ping_args[1]}" "-I"
	assert_equal "${ping_args[2]}" "2001:db8::100"

	# Restore original function if it existed
	if command -v check_command_available.original >/dev/null 2>&1; then
		# Restore function to call original check_command_available
		#
		# Arguments:
		#   $@: All arguments passed to function
		#
		# Returns:
		#   Exit code from original function
		check_command_available() {
			check_command_available.original "$@"
		}
	fi

	remove_mock_from_path
}

# bats test_tags=category:unit,priority:medium
@test "build_ping_command - IPv6 when neither ping6 nor ping -6 available" {
	# Purpose: Test that build_ping_command returns 1 when IPv6 ping is not available
	# Expected: Function returns 1 (failure)
	# Importance: Error handling when IPv6 ping support is missing
	local ping_cmd
	local ping_args=()

	# Save original check_command_available if it exists
	if command -v check_command_available >/dev/null 2>&1; then
		local func_def
		func_def=$(declare -f check_command_available 2>/dev/null || true)
		if [[ -n "$func_def" ]]; then
			eval "${func_def/check_command_available/check_command_available.original}" 2>/dev/null || true
		fi
	fi

	# Create mock ping that does NOT support -6 flag
	cat >"${TEST_DIR}/ping" <<'EOF'
#!/bin/bash
# Mock ping that does NOT support -6 flag
exit 1
EOF
	chmod +x "${TEST_DIR}/ping"
	add_mock_to_path

	# Mock check_command_available to return failure for both ping6 and ping
	# Mock function to simulate command availability check with both ping6 and ping unavailable
	#
	# Arguments:
	#   $1: Command name to check
	#
	# Returns:
	#   0: Command is not ping6 or ping and original function returns success
	#   1: Command is ping6 or ping, or original function returns failure
	check_command_available() {
		local cmd="$1"
		if [[ "$cmd" == "ping6" ]] || [[ "$cmd" == "ping" ]]; then
			return 1
		fi
		# For other commands, use original if available
		if command -v check_command_available.original >/dev/null 2>&1; then
			check_command_available.original "$@"
		else
			command -v "$cmd" >/dev/null 2>&1
		fi
	}

	# Use set +e to allow function to return error code without failing test
	set +e
	build_ping_command "2001:db8::1" ""
	local exit_code=$?
	set -e
	assert_equal "$exit_code" 1

	# Restore original function if it existed
	if command -v check_command_available.original >/dev/null 2>&1; then
		# Restore function to call original check_command_available
		#
		# Arguments:
		#   $@: All arguments passed to function
		#
		# Returns:
		#   Exit code from original function
		check_command_available() {
			check_command_available.original "$@"
		}
	fi

	remove_mock_from_path
}

# bats test_tags=category:unit,priority:medium
@test "build_ping_command - empty target IP returns 1" {
	# Purpose: Test that build_ping_command returns 1 when target IP is empty
	# Expected: Function returns 1 (failure)
	# Importance: Input validation for empty target IP
	local ping_cmd
	local ping_args=()

	# Use set +e to allow function to return error code without failing test
	set +e
	build_ping_command "" ""
	local exit_code=$?
	set -e
	assert_equal "$exit_code" 1
}

# bats test_tags=category:unit,priority:medium
@test "build_ping_command - variables set correctly in caller's scope" {
	# Purpose: Test that build_ping_command sets variables correctly in caller's scope
	# Expected: ping_cmd and ping_args are set and accessible after function returns
	# Importance: Verifies the variable return pattern works correctly
	local ping_cmd
	local ping_args=()

	# Initialize with values to ensure they're overwritten
	ping_cmd="initial"
	ping_args=("initial" "values")

	build_ping_command "192.168.1.1" "192.168.1.100"
	local exit_code=$?
	assert_equal "$exit_code" 0

	# Verify variables were set correctly
	assert_equal "$ping_cmd" "ping"
	assert_equal "${#ping_args[@]}" 2
	assert_equal "${ping_args[0]}" "-I"
	assert_equal "${ping_args[1]}" "192.168.1.100"
}

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

# bats test_tags=category:integration,priority:medium
@test "build_ping_command integration - check_ping_connectivity uses build_ping_command correctly" {
	# Purpose: Test that check_ping_connectivity correctly uses build_ping_command
	# Expected: check_ping_connectivity works with build_ping_command for IPv4
	# Importance: Integration test to verify the function works in real usage
	setup_test_environment

	# Mock ping to succeed
	mock_ping_success >/dev/null
	add_mock_to_path

	# Mock route check
	# Mock function to simulate route existence check
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds (route exists)
	check_route_exists() {
		return 0
	}
	export -f check_route_exists

	# Mock add_route_if_needed
	# Mock function to simulate adding route if needed
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds
	add_route_if_needed() {
		return 0
	}
	export -f add_route_if_needed

	# Source logging for handle_error
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true

	# Set required config variables
	PING_COUNT=3
	PING_TIMEOUT=2
	export PING_COUNT PING_TIMEOUT

	# Test IPv4 ping
	run check_ping_connectivity "192.168.1.1" "" "TEST"
	assert_success

	# Test IPv4 ping with source IP
	run check_ping_connectivity "192.168.1.1" "192.168.1.100" "TEST"
	assert_success

	remove_mock_from_path
}

# bats test_tags=category:integration,priority:medium
@test "build_ping_command integration - function available from detection library" {
	# Purpose: Test that build_ping_command is available and works when sourced from detection library
	# Expected: build_ping_command works correctly (same as vpn-keepalive.sh would use it)
	# Importance: Integration test to verify the function works when loaded via detection.sh
	# Note: vpn-keepalive.sh sources detection.sh which sources ping_detection.sh where build_ping_command is defined
	# This test verifies the function works in that context
	setup_test_environment

	# Test that build_ping_command is available (already sourced at top of file)
	# and works correctly for IPv4
	local ping_cmd
	local ping_args=()

	build_ping_command "192.168.1.1" ""
	local exit_code=$?
	assert_equal "$exit_code" 0
	assert_equal "$ping_cmd" "ping"
	assert_equal "${#ping_args[@]}" 0

	# Test with source IP
	build_ping_command "192.168.1.1" "192.168.1.100"
	local exit_code=$?
	assert_equal "$exit_code" 0
	assert_equal "$ping_cmd" "ping"
	assert_equal "${#ping_args[@]}" 2
	assert_equal "${ping_args[0]}" "-I"
	assert_equal "${ping_args[1]}" "192.168.1.100"
}
