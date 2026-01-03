#!/usr/bin/env bats
#
# Tests for Recovery Method Tracking
# Tests that recovery methods are properly stored, retrieved, and included in restoration messages
#
# These tests verify the recovery method tracking feature that allows correlation
# between recovery attempts and VPN restoration events.

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_at_tier

# ============================================================================
# RECOVERY METHOD TRACKING TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "recovery method tracking: recovery method is stored when xfrm recovery is attempted" {
	# Purpose: Test verifies that recovery method is stored when xfrm recovery is attempted
	# Expected: store_recovery_method is called with "xfrm" when xfrm recovery is attempted
	# Importance: Ensures recovery method tracking works for xfrm-based recovery
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_XFRM_RECOVERY=1' 'TIER2_THRESHOLD=3'

	# Mock ip command for xfrm recovery
	# Note: get_xfrm_state_for_peer may call "ip -s xfrm state" first, then fall back to "ip xfrm state"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "-s" ]] && [[ "$2" == "xfrm" ]] && [[ "$3" == "state" ]]; then
	# Handle "ip -s xfrm state" (with statistics flag)
	echo "src 10.0.0.1 dst 192.168.1.1"
	echo "  proto esp spi 0x12345678 reqid 1 mode tunnel"
	echo "  lifetime current:"
	echo "    1000(bytes), 10(packets)"
	exit 0
elif [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
	# Handle "ip xfrm state" (without statistics flag)
	echo "src 10.0.0.1 dst 192.168.1.1"
	echo "  proto esp spi 0x12345678 reqid 1 mode tunnel"
	echo "  lifetime current:"
	echo "    1000(bytes), 10(packets)"
	exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Mock check_ipsec_phase2 function to succeed (SA re-established)
	local mock_check_ipsec_phase2="${TEST_DIR}/check_ipsec_phase2"
	cat >"$mock_check_ipsec_phase2" <<'EOF'
#!/bin/bash
# Simulate SA re-established
exit 0
EOF
	chmod +x "$mock_check_ipsec_phase2"
	add_mock_to_path

	source_recovery_module

	# Override check_ipsec_phase2 function to use mock
	check_ipsec_phase2() {
		"$mock_check_ipsec_phase2" "$@"
	}

	# Set up failure count at Tier 2 threshold
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local location_name="TEST"
	local peer_ip="192.168.1.1"
	set_peer_state "$location_name" "$peer_ip" "failure_count" "3"

	# Call surgical_cleanup which should store recovery method
	surgical_cleanup "$peer_ip" "$location_name"

	# Verify recovery method was stored
	local recovery_method
	recovery_method=$(get_recovery_method "$location_name" "$peer_ip")
	assert_equal "$recovery_method" "xfrm"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery method tracking: recovery method is stored when ipsec_reload recovery is attempted" {
	# Purpose: Test verifies that recovery method is stored when ipsec_reload recovery is attempted
	# Expected: store_recovery_method is called with "ipsec_reload" when ipsec reload is attempted
	# Importance: Ensures recovery method tracking works for ipsec reload recovery
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_XFRM_RECOVERY=0' 'TIER2_THRESHOLD=3'

	# Mock ipsec command for reload
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
	exit 0
fi
if [[ "$1" == "status" ]]; then
	echo "Connections:"
	echo "  test-conn: ESTABLISHED 1 hour ago, 192.168.1.1...10.0.0.1"
	exit 0
fi
exec /usr/bin/ipsec "$@"
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	source_recovery_module

	# Set up failure count at Tier 2 threshold
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local location_name="TEST"
	local peer_ip="192.168.1.1"
	set_peer_state "$location_name" "$peer_ip" "failure_count" "3"

	# Call surgical_cleanup which should store recovery method
	surgical_cleanup "$peer_ip" "$location_name"

	# Verify recovery method was stored
	local recovery_method
	recovery_method=$(get_recovery_method "$location_name" "$peer_ip")
	assert_equal "$recovery_method" "ipsec_reload"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery method tracking: recovery method is updated when fallback occurs" {
	# Purpose: Test verifies that recovery method is updated when xfrm fails and falls back to ipsec_reload
	# Expected: Recovery method is updated from "xfrm" to "ipsec_reload" when fallback occurs
	# Importance: Ensures fallback recovery methods are correctly tracked
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_XFRM_RECOVERY=1' 'TIER2_THRESHOLD=3'

	# Mock ip command - xfrm recovery will fail (no SAs found)
	# Note: get_xfrm_state_for_peer may call "ip -s xfrm state" first, then fall back to "ip xfrm state"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "-s" ]] && [[ "$2" == "xfrm" ]] && [[ "$3" == "state" ]]; then
	# Handle "ip -s xfrm state" - return empty (no SAs found)
	exit 0
elif [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
	# Handle "ip xfrm state" - return empty (no SAs found)
	exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Mock ipsec command for fallback reload
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
	exit 0
fi
if [[ "$1" == "status" ]]; then
	echo "Connections:"
	echo "  test-conn: ESTABLISHED 1 hour ago, 192.168.1.1...10.0.0.1"
	exit 0
fi
exec /usr/bin/ipsec "$@"
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	source_recovery_module

	# Set up failure count at Tier 2 threshold
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local location_name="TEST"
	local peer_ip="192.168.1.1"
	set_peer_state "$location_name" "$peer_ip" "failure_count" "3"

	# Call surgical_cleanup - xfrm will fail, fallback to ipsec_reload
	surgical_cleanup "$peer_ip" "$location_name"

	# Verify recovery method was updated to ipsec_reload (not xfrm)
	local recovery_method
	recovery_method=$(get_recovery_method "$location_name" "$peer_ip")
	assert_equal "$recovery_method" "ipsec_reload"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery method tracking: VPN restored message includes recovery method" {
	# Purpose: Test verifies that "VPN restored" message includes the recovery method that was used
	# Expected: Log message contains "VPN restored" with recovery method information
	# Importance: Provides visibility into which recovery method successfully restored the VPN
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_XFRM_RECOVERY=1' 'TIER2_THRESHOLD=3'

	# Mock ip command for xfrm recovery
	# Note: get_xfrm_state_for_peer may call "ip -s xfrm state" first, then fall back to "ip xfrm state"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "-s" ]] && [[ "$2" == "xfrm" ]] && [[ "$3" == "state" ]]; then
	# Handle "ip -s xfrm state" (with statistics flag)
	echo "src 10.0.0.1 dst 192.168.1.1"
	echo "  proto esp spi 0x12345678 reqid 1 mode tunnel"
	echo "  lifetime current:"
	echo "    12345(bytes), 100(packets)"
	exit 0
elif [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
	# Handle "ip xfrm state" (without statistics flag)
	echo "src 10.0.0.1 dst 192.168.1.1"
	echo "  proto esp spi 0x12345678 reqid 1 mode tunnel"
	echo "  lifetime current:"
	echo "    12345(bytes), 100(packets)"
	exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Mock check_ipsec_phase2 function to succeed (SA re-established)
	local mock_check_ipsec_phase2="${TEST_DIR}/check_ipsec_phase2"
	cat >"$mock_check_ipsec_phase2" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$mock_check_ipsec_phase2"
	add_mock_to_path

	source_recovery_module

	# Override check_ipsec_phase2 function to use mock
	check_ipsec_phase2() {
		"$mock_check_ipsec_phase2" "$@"
	}

	# Set up failure count at Tier 2 threshold
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local location_name="TEST"
	local peer_ip="192.168.1.1"
	set_peer_state "$location_name" "$peer_ip" "failure_count" "3"

	# Perform recovery (stores recovery method)
	surgical_cleanup "$peer_ip" "$location_name"

	# Now simulate VPN recovery - update mock ip to return active VPN state
	# Set up state with previous byte counter (bytes will increase)
	set_peer_state "$location_name" "$peer_ip" "last_bytes" "10000" || true

	# Update mock ip to return active VPN (SA exists, bytes increasing)
	# Format matches UDM OS format for proper parsing
	# Note: get_xfrm_state_for_peer may call "ip -s xfrm state" first, then fall back to "ip xfrm state"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "-s" ]] && [[ "$2" == "xfrm" ]] && [[ "$3" == "state" ]]; then
	# Handle "ip -s xfrm state" (with statistics flag)
	echo "src 10.0.0.1 dst 192.168.1.1"
	echo "  proto esp spi 0x12345678 reqid 1 mode tunnel"
	echo "  lifetime current:"
	echo "    20000(bytes), 200(packets)"
	exit 0
elif [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
	# Handle "ip xfrm state" (without statistics flag)
	echo "src 10.0.0.1 dst 192.168.1.1"
	echo "  proto esp spi 0x12345678 reqid 1 mode tunnel"
	echo "  lifetime current:"
	echo "    20000(bytes), 200(packets)"
	exit 0
fi
exec /usr/bin/ip "$@"
EOF

	# Call monitor_location - VPN should be detected as healthy
	monitor_location "$location_name" "$peer_ip" ""

	# Verify log contains "VPN restored" with recovery method
	assert_file_contains "$LOG_FILE" "VPN restored"
	assert_file_contains "$LOG_FILE" "recovery method: xfrm-based recovery"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery method tracking: recovery method is cleared after logging" {
	# Purpose: Test verifies that recovery method is cleared after being logged in restoration message
	# Expected: Recovery method state file is deleted after VPN restoration is logged
	# Importance: Prevents stale recovery method information from being displayed
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_XFRM_RECOVERY=1' 'TIER2_THRESHOLD=3'

	# Mock ip command for xfrm recovery
	# Note: get_xfrm_state_for_peer may call "ip -s xfrm state" first, then fall back to "ip xfrm state"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "-s" ]] && [[ "$2" == "xfrm" ]] && [[ "$3" == "state" ]]; then
	# Handle "ip -s xfrm state" (with statistics flag)
	echo "src 10.0.0.1 dst 192.168.1.1"
	echo "  proto esp spi 0x12345678 reqid 1 mode tunnel"
	echo "  lifetime current:"
	echo "    12345(bytes), 100(packets)"
	exit 0
elif [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
	# Handle "ip xfrm state" (without statistics flag)
	echo "src 10.0.0.1 dst 192.168.1.1"
	echo "  proto esp spi 0x12345678 reqid 1 mode tunnel"
	echo "  lifetime current:"
	echo "    12345(bytes), 100(packets)"
	exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Mock check_ipsec_phase2 function to succeed
	local mock_check_ipsec_phase2="${TEST_DIR}/check_ipsec_phase2"
	cat >"$mock_check_ipsec_phase2" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$mock_check_ipsec_phase2"
	add_mock_to_path

	source_recovery_module

	# Override check_ipsec_phase2 function to use mock
	check_ipsec_phase2() {
		"$mock_check_ipsec_phase2" "$@"
	}

	# Set up failure count at Tier 2 threshold
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local location_name="TEST"
	local peer_ip="192.168.1.1"
	set_peer_state "$location_name" "$peer_ip" "failure_count" "3"

	# Perform recovery (stores recovery method)
	surgical_cleanup "$peer_ip" "$location_name"

	# Verify recovery method was stored
	local recovery_method
	recovery_method=$(get_recovery_method "$location_name" "$peer_ip")
	assert_equal "$recovery_method" "xfrm"

	# Now simulate VPN recovery - update mock ip to return active VPN state
	# Set up state with previous byte counter (bytes will increase)
	set_peer_state "$location_name" "$peer_ip" "last_bytes" "10000" || true

	# Update mock ip to return active VPN (SA exists, bytes increasing)
	# Format matches UDM OS format for proper parsing
	# Note: get_xfrm_state_for_peer may call "ip -s xfrm state" first, then fall back to "ip xfrm state"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "-s" ]] && [[ "$2" == "xfrm" ]] && [[ "$3" == "state" ]]; then
	# Handle "ip -s xfrm state" (with statistics flag)
	echo "src 10.0.0.1 dst 192.168.1.1"
	echo "  proto esp spi 0x12345678 reqid 1 mode tunnel"
	echo "  lifetime current:"
	echo "    20000(bytes), 200(packets)"
	exit 0
elif [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
	# Handle "ip xfrm state" (without statistics flag)
	echo "src 10.0.0.1 dst 192.168.1.1"
	echo "  proto esp spi 0x12345678 reqid 1 mode tunnel"
	echo "  lifetime current:"
	echo "    20000(bytes), 200(packets)"
	exit 0
fi
exec /usr/bin/ip "$@"
EOF

	# Call monitor_location - VPN should be detected as healthy and recovery method cleared
	monitor_location "$location_name" "$peer_ip" ""

	# Verify recovery method was cleared
	recovery_method=$(get_recovery_method "$location_name" "$peer_ip")
	assert_equal "$recovery_method" ""

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery method tracking: recovery method format is correct for all methods" {
	# Purpose: Test verifies that format_recovery_method correctly formats all recovery method types
	# Expected: format_recovery_method returns user-friendly descriptions for all method types
	# Importance: Ensures recovery method display is consistent and readable
	source_recovery_module

	# Test xfrm format
	local formatted
	formatted=$(format_recovery_method "xfrm")
	assert_equal "$formatted" "xfrm-based recovery"

	# Test ipsec_reload format
	formatted=$(format_recovery_method "ipsec_reload")
	assert_equal "$formatted" "ipsec reload"

	# Test ipsec_restart format
	formatted=$(format_recovery_method "ipsec_restart")
	assert_equal "$formatted" "ipsec restart"

	# Test unknown format
	formatted=$(format_recovery_method "unknown_method")
	assert_equal "$formatted" "unknown_method"

	# Test empty format
	formatted=$(format_recovery_method "")
	assert_equal "$formatted" "unknown recovery method"
}
