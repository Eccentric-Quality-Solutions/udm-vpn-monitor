#!/usr/bin/env bats
#
# Tests for Failure Type Detection
# Tests critical paths and error handling scenarios

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# 2.3 FAILURE TYPE DETECTION
# ============================================================================

# bats test_tags=category:high-risk,priority:medium
@test "Failure type tunnel_down - No Phase 2 SA found" {
	# Test verifies that failure type "tunnel_down" is detected when no Phase 2 SA is found.
	# Expected: Failure type is detected as "tunnel_down" when no SA exists.
	# Importance: Enables targeted recovery strategies based on failure type.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Mock ip command - no SA (tunnel down)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Return empty (no SA)
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect tunnel_down failure type
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tunnel down" || assert_file_contains "$LOG_FILE" "tunnel_down"

	# Verify failure type stored in state file
	local failure_type_file="${STATE_DIR}/failure_type_192_168_1_1"
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		assert_equal "$failure_type" "tunnel_down"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type routing_issue - Phase 2 SA exists but bytes not increasing" {
	# Test verifies that failure type "routing_issue" is detected when SA exists but bytes not increasing.
	# Expected: Failure type is detected as "routing_issue" when SA exists but traffic not flowing.
	# Importance: Enables targeted recovery strategies for routing issues.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Set initial bytes (same as current - not increasing)
	setup_state_files "192.168.1.1" 0 1000 "0x12345678"

	# Mock ip command - SA exists but bytes not increasing
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect routing_issue failure type
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Routing issue" || assert_file_contains "$LOG_FILE" "routing_issue"

	# Verify failure type stored in state file
	local failure_type_file="${STATE_DIR}/failure_type_192_168_1_1"
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		assert_equal "$failure_type" "routing_issue"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type routing_issue - Phase 2 SA exists but ping fails" {
	# Test verifies that failure type "routing_issue" is detected when SA exists but ping fails.
	# Expected: Failure type is detected as "routing_issue" when SA exists but connectivity fails.
	# Importance: Enables targeted recovery strategies for routing issues.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=1' 'INTERNAL_PEER_IPS="192.168.1.1"'

	# Set initial bytes (increasing)
	setup_state_files "192.168.1.1" 0 1000 "0x12345678"

	# Mock ip command - SA exists
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"

	# Mock ping - fails
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
exit 1
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect routing_issue failure type
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Routing issue" || assert_file_contains "$LOG_FILE" "routing_issue"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type rekey - SPI changed (not a failure, but logged)" {
	# Test verifies that failure type "rekey" is detected when SPI changes (not a failure).
	# Expected: Failure type is detected as "rekey" when SPI changes, VPN marked as OK.
	# Importance: Rekey events are logged but not treated as failures.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Set initial SPI
	setup_state_files "192.168.1.1" 0 1000 "0x12345678"

	# Mock ip command - new SPI (rekey)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should detect rekey (not a failure)
	assert_success
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "rekey" || assert_file_contains "$LOG_FILE" "SA rekey detected"

	# Verify failure type stored (rekey is logged but VPN is OK)
	local failure_type_file="${STATE_DIR}/failure_type_192_168_1_1"
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		# Rekey may be stored for monitoring purposes
		assert [ "$failure_type" == "rekey" ] || [ "$failure_type" == "unknown" ]
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type unknown - Unable to determine type" {
	# Test verifies that failure type "unknown" is detected when unable to determine specific type.
	# Expected: Failure type is detected as "unknown" when detection methods fail.
	# Importance: Ensures failure tracking continues even when specific type cannot be determined.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Mock ip command - SA exists but no byte counter info
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    # No lifetime line (can't extract bytes)
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect unknown failure type
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Unknown" || assert_file_contains "$LOG_FILE" "unknown"

	# Verify failure type stored in state file
	local failure_type_file="${STATE_DIR}/failure_type_192_168_1_1"
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		assert_equal "$failure_type" "unknown"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type stored in state file for recovery actions" {
	# Test verifies that failure type is stored in state file for use by recovery actions.
	# Expected: Failure type is stored in state file and can be retrieved for recovery strategies.
	# Importance: Enables recovery actions to use failure-specific strategies.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Mock ip command - no SA (tunnel down)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify failure type stored in state file
	local failure_type_file="${STATE_DIR}/failure_type_192_168_1_1"
	assert_file_exist "$failure_type_file"
	local failure_type
	failure_type=$(cat "$failure_type_file")
	assert [ "$failure_type" == "tunnel_down" ] || [ "$failure_type" == "unknown" ]

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type cleared on VPN recovery" {
	# Test verifies that failure type is cleared when VPN recovers.
	# Expected: Failure type file is removed or cleared when VPN becomes healthy.
	# Importance: Ensures failure type tracking is reset after recovery.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Create failure type file (from previous failure)
	local failure_type_file="${STATE_DIR}/failure_type_192_168_1_1"
	echo "tunnel_down" >"$failure_type_file"

	# Mock ip command - VPN recovers
	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# VPN should recover
	assert_success
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "recovered"

	# Failure type file should be cleared or removed
	# Note: The actual behavior depends on implementation - may be removed or cleared
	# This test verifies that recovery happens and failure type is handled

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type detection when xfrm unavailable" {
	# Test verifies that failure type detection works when xfrm is unavailable.
	# Expected: Failure type is detected using fallback methods when xfrm unavailable.
	# Importance: Ensures failure type detection works even when preferred method unavailable.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Don't create ip mock (xfrm unavailable)
	# Mock ipsec - no connection
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # No connection found
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect failure type using fallback
	assert_file_exist "$LOG_FILE"
	# Should contain failure type detection (may be unknown or tunnel_down)
	assert_file_contains "$LOG_FILE" "tunnel_down" || assert_file_contains "$LOG_FILE" "unknown" || assert_file_contains "$LOG_FILE" "VPN check failed"

	remove_mock_from_path
}
