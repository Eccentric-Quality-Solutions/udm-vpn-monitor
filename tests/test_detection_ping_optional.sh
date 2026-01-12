#!/usr/bin/env bats
#
# Tests for check_ping_optional() and check_ping_if_enabled() edge cases
# Specifically tests the SA existence check fix to ensure accurate logging
# when vpn_ok=0 but SA actually exists

load test_helper
load helpers/detection

# Source the detection library functions
# shellcheck source=../lib/detection.sh
source "${BATS_TEST_DIRNAME}/../lib/detection.sh"

# Source logging for log_message functions
# shellcheck source=../lib/logging.sh
source "${BATS_TEST_DIRNAME}/../lib/logging.sh"

# Source common functions
# shellcheck source=../lib/common.sh
source "${BATS_TEST_DIRNAME}/../lib/common.sh"

# ============================================================================
# SETUP
# ============================================================================

# ============================================================================
# TESTS FOR check_ping_optional()
# ============================================================================

# bats test_tags=category:unit,category:high-risk,priority:high
@test "check_ping_optional - vpn_ok=0 but SA exists, ping succeeds - logs SA exists message" {
	# Purpose: Test that when vpn_ok=0 but SA actually exists, we log accurate message
	# Expected: Should log "VPN SA exists but ping check..." not "VPN tunnel is down (no SA found)"
	# Importance: Validates fix for contradictory detection messages bug
	setup_ping_optional_test

	local external_peer_ip="203.0.113.1"
	local internal_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"

	# Mock ip command to return SA exists (for check_ipsec_phase2)
	cat >"${TEST_DIR}/ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
	# Return SA exists for external_peer_ip
	echo "src 203.0.113.1 dst 203.0.113.1"
	echo "	proto esp spi 0x12345678 reqid 1 mode tunnel"
	exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "${TEST_DIR}/ip"
	add_mock_to_path

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

	# Mock build_route_message to return empty (not needed for this test)
	# Mock function to simulate route message building
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds, prints empty string
	build_route_message() {
		echo ""
	}
	export -f build_route_message

	# Call check_ping_optional with vpn_ok=0 but SA exists
	run check_ping_optional 0 "$external_peer_ip" "$internal_peer_ip" "$location_name"

	# Should succeed (always returns 0)
	assert_success

	# Should log that SA exists (not "no SA found")
	# The message format is "VPN SA exists but ping check failed" or "VPN connectivity verified"
	assert_file_contains "$LOG_FILE" "VPN SA exists" || assert_file_contains "$LOG_FILE" "VPN connectivity verified"
	assert_file_contains "$LOG_FILE" "ping check"

	# Should NOT log contradictory "no SA found" message
	run grep -q "VPN tunnel is down (no SA found)" "$LOG_FILE" || true
	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:unit,category:high-risk,priority:high
@test "check_ping_optional - vpn_ok=0 and SA doesn't exist, ping succeeds - logs no SA message" {
	# Purpose: Test that when vpn_ok=0 and SA doesn't exist, we log accurate message
	# Expected: Should log "VPN tunnel is down (no SA found)" when ping succeeds via alternative route
	# Importance: Validates accurate logging when SA truly doesn't exist
	setup_ping_optional_test

	local external_peer_ip="203.0.113.1"
	local internal_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"

	# Mock ip command to return no SA (for check_ipsec_phase2)
	cat >"${TEST_DIR}/ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
	# Return empty (no SA)
	exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "${TEST_DIR}/ip"
	add_mock_to_path

	# Mock ping to succeed (connectivity via alternative route)
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

	# Mock build_route_message
	# Mock function to simulate route message building
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds, prints route message
	build_route_message() {
		echo " (route: dev vti66)"
	}
	export -f build_route_message

	# Call check_ping_optional with vpn_ok=0 and SA doesn't exist
	run check_ping_optional 0 "$external_peer_ip" "$internal_peer_ip" "$location_name"

	# Should succeed (always returns 0)
	assert_success

	# Should log "no SA found" message
	assert_file_contains "$LOG_FILE" "VPN tunnel is down (no SA found)"
	assert_file_contains "$LOG_FILE" "connectivity exists via alternative route"

	remove_mock_from_path
}

# bats test_tags=category:unit,category:high-risk,priority:high
@test "check_ping_optional - vpn_ok=0 but SA exists, ping fails - logs SA exists but ping failed" {
	# Purpose: Test that when vpn_ok=0 but SA exists and ping fails, we log accurate message
	# Expected: Should log "VPN SA exists but ping check failed" not "no SA found"
	# Importance: Validates fix for routing issue detection
	setup_ping_optional_test

	local external_peer_ip="203.0.113.1"
	local internal_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"

	# Mock ip command to return SA exists
	cat >"${TEST_DIR}/ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
	echo "src 203.0.113.1 dst 203.0.113.1"
	echo "	proto esp spi 0x12345678 reqid 1 mode tunnel"
	exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "${TEST_DIR}/ip"
	add_mock_to_path

	# Mock ping to fail
	mock_ping "${TEST_PEER_IP}" 0 >/dev/null
	mv "${TEST_DIR}/mock_ping" "${TEST_DIR}/ping" 2>/dev/null || true
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

	# Mock build_route_message
	# Mock function to simulate route message building
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds, prints empty string
	build_route_message() {
		echo ""
	}
	export -f build_route_message

	# Call check_ping_optional with vpn_ok=0 but SA exists and ping fails
	run check_ping_optional 0 "$external_peer_ip" "$internal_peer_ip" "$location_name"

	# Should succeed (always returns 0)
	assert_success

	# Should log that SA exists but ping failed
	assert_file_contains "$LOG_FILE" "VPN SA exists"
	assert_file_contains "$LOG_FILE" "ping check failed"

	# Should NOT log contradictory "no SA found" message
	run grep -q "VPN tunnel is down (no SA found)" "$LOG_FILE" || true
	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "check_ping_optional - ping check disabled - early return" {
	# Purpose: Test that check_ping_optional returns early when ping check is disabled
	# Expected: No ping checks performed, no SA checks performed
	# Importance: Validates early exit optimization
	setup_ping_optional_test

	export ENABLE_PING_CHECK=0

	local external_peer_ip="203.0.113.1"
	local internal_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"

	# Call check_ping_optional
	run check_ping_optional 0 "$external_peer_ip" "$internal_peer_ip" "$location_name"

	# Should succeed
	assert_success

	# Should not have any log entries (early return)
	# Log file may not exist if no logging occurred
	if [[ -f "$LOG_FILE" ]]; then
		local line_count
		line_count=$(wc -l <"$LOG_FILE" 2>/dev/null || echo "0")
		assert_equal "$line_count" "0"
	else
		# Log file doesn't exist - that's fine for early return
		# This is expected when ENABLE_PING_CHECK=0
		assert_success
	fi

	remove_mock_from_path
}

# ============================================================================
# TESTS FOR check_ping_if_enabled()
# ============================================================================

# bats test_tags=category:unit,category:high-risk,priority:high
@test "check_ping_if_enabled - sa_exists=1, ping succeeds - logs connectivity verified" {
	# Purpose: Test that check_ping_if_enabled correctly handles sa_exists=1 with successful ping
	# Expected: Should log "VPN connectivity verified: ping check passed"
	# Importance: Validates function works correctly with explicit SA status
	setup_ping_optional_test

	local ping_target="${TEST_PEER_IP}"
	local location_name="TEST"

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

	# Call check_ping_if_enabled with sa_exists=1
	run check_ping_if_enabled 1 "$ping_target" "" "$location_name"

	# Should succeed
	assert_success

	# Should log connectivity verified
	assert_file_contains "$LOG_FILE" "VPN connectivity verified"
	assert_file_contains "$LOG_FILE" "ping check passed"

	remove_mock_from_path
}

# bats test_tags=category:unit,category:high-risk,priority:high
@test "check_ping_if_enabled - sa_exists=1, ping fails - logs SA exists but ping failed" {
	# Purpose: Test that check_ping_if_enabled correctly handles sa_exists=1 with failed ping
	# Expected: Should log "VPN SA exists but ping check failed"
	# Importance: Validates routing issue detection
	setup_ping_optional_test

	local ping_target="${TEST_PEER_IP}"
	local location_name="TEST"

	# Mock ping to fail
	mock_ping "${TEST_PEER_IP}" 0 >/dev/null
	mv "${TEST_DIR}/mock_ping" "${TEST_DIR}/ping" 2>/dev/null || true
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

	# Call check_ping_if_enabled with sa_exists=1
	run check_ping_if_enabled 1 "$ping_target" "" "$location_name"

	# Should succeed
	assert_success

	# Should log SA exists but ping failed
	assert_file_contains "$LOG_FILE" "VPN SA exists"
	assert_file_contains "$LOG_FILE" "ping check failed"

	remove_mock_from_path
}

# bats test_tags=category:unit,category:high-risk,priority:high
@test "check_ping_if_enabled - sa_exists=0, ping succeeds - logs no SA but alternative route" {
	# Purpose: Test that check_ping_if_enabled correctly handles sa_exists=0 with successful ping
	# Expected: Should log "VPN tunnel is down (no SA found), but connectivity exists via alternative route"
	# Importance: Validates alternative route detection
	setup_ping_optional_test

	local ping_target="${TEST_PEER_IP}"
	local location_name="TEST"

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

	# Mock build_route_message
	# Mock function to simulate route message building
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds, prints route message
	build_route_message() {
		echo " (route: dev vti66)"
	}
	export -f build_route_message

	# Call check_ping_if_enabled with sa_exists=0
	run check_ping_if_enabled 0 "$ping_target" "" "$location_name"

	# Should succeed
	assert_success

	# Should log no SA but alternative route
	assert_file_contains "$LOG_FILE" "VPN tunnel is down (no SA found)"
	assert_file_contains "$LOG_FILE" "connectivity exists via alternative route"

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "check_ping_if_enabled - sa_exists=0, ping fails - no log (expected behavior)" {
	# Purpose: Test that check_ping_if_enabled doesn't log when SA doesn't exist and ping fails
	# Expected: No log entry (this is expected - no SA and no connectivity)
	# Importance: Validates silent failure case
	setup_ping_optional_test

	local ping_target="${TEST_PEER_IP}"
	local location_name="TEST"

	# Mock ping to fail
	mock_ping "${TEST_PEER_IP}" 0 >/dev/null
	mv "${TEST_DIR}/mock_ping" "${TEST_DIR}/ping" 2>/dev/null || true
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

	# Call check_ping_if_enabled with sa_exists=0
	run check_ping_if_enabled 0 "$ping_target" "" "$location_name"

	# Should succeed
	assert_success

	# Should not have any log entries (no SA and ping failed - expected silent case)
	# When SA doesn't exist and ping fails, no log entry is created
	if [[ -f "$LOG_FILE" ]]; then
		run grep -q "VPN tunnel is down\|VPN SA exists\|ping check" "$LOG_FILE" || true
		assert_failure
	else
		# Log file doesn't exist - that's fine for silent case
		assert_success
	fi

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "check_ping_if_enabled - multiple IPs, sa_exists=1, ping succeeds - logs correctly" {
	# Purpose: Test that check_ping_if_enabled handles multiple IPs correctly with SA exists
	# Expected: Should log "VPN connectivity verified: ping check passed for multiple internal IPs"
	# Importance: Validates multiple IP support
	setup_ping_optional_test

	local ping_target="${TEST_PEER_IP} 192.168.1.2"
	local location_name="TEST"

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

	# Call check_ping_if_enabled with sa_exists=1 and multiple IPs
	run check_ping_if_enabled 1 "$ping_target" "" "$location_name"

	# Should succeed
	assert_success

	# Should log connectivity verified for multiple IPs
	assert_file_contains "$LOG_FILE" "VPN connectivity verified"
	assert_file_contains "$LOG_FILE" "multiple internal IPs"

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "check_ping_if_enabled - ping check disabled - early return" {
	# Purpose: Test that check_ping_if_enabled returns early when ping check is disabled
	# Expected: No ping checks performed
	# Importance: Validates early exit optimization
	setup_ping_optional_test

	export ENABLE_PING_CHECK=0

	local ping_target="${TEST_PEER_IP}"
	local location_name="TEST"

	# Call check_ping_if_enabled
	run check_ping_if_enabled 1 "$ping_target" "" "$location_name"

	# Should succeed
	assert_success

	# Should not have any log entries (early return)
	# Log file may not exist if no logging occurred
	if [[ -f "$LOG_FILE" ]]; then
		local line_count
		line_count=$(wc -l <"$LOG_FILE" 2>/dev/null || echo "0")
		assert_equal "$line_count" "0"
	else
		# Log file doesn't exist - that's fine for early return
		# This is expected when ENABLE_PING_CHECK=0
		assert_success
	fi

	remove_mock_from_path
}
