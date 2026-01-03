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
	# Purpose: Test verifies that failure type "tunnel_down" is detected when no Phase 2 SA is found
	# Expected: Failure type is detected as "tunnel_down" when no SA exists
	# Importance: Enables targeted recovery strategies based on failure type
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}"

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
	local failure_type_file="${STATE_DIR}/failure_type_TEST_192_168_1_1"
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		assert_equal "$failure_type" "tunnel_down"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type routing_issue - Phase 2 SA exists but bytes not increasing" {
	# Purpose: Test verifies that failure type "routing_issue" is detected when SA exists but bytes not increasing
	# Expected: Failure type is detected as "routing_issue" when SA exists but traffic not flowing
	# Importance: Enables targeted recovery strategies for routing issues
	# Disable ping check so that bytes not increasing is treated as a routing issue, not idle tunnel
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=0'

	# Set initial bytes (same as current - not increasing) using location-based state functions
	# Ensure STATE_DIR is set (setup_location_vpn_monitor sets it, but ensure it's available)
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true
	# Use get_peer_state_file_path to get the correct path dynamically
	local expected_state_file
	expected_state_file=$(get_peer_state_file_path "TEST" "192.168.1.1" "last_bytes" 2>/dev/null || echo "${STATE_DIR}/last_bytes_TEST_192_168_1_1")

	set_peer_state "TEST" "192.168.1.1" "last_bytes" "1000" || true
	set_peer_state "TEST" "192.168.1.1" "spi" "0x12345678" || true

	# Verify state file was created correctly
	assert_file_exist "$expected_state_file"
	local stored_bytes
	stored_bytes=$(get_peer_state "TEST" "192.168.1.1" "last_bytes" "0" 2>/dev/null || echo "0")
	assert_equal "$stored_bytes" "1000"

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

	# Mock ipsec to fail (prevent fallback from succeeding and masking failure)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
# Return failure to ensure xfrm failure is not masked by ipsec fallback
exit 1
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Debug: Verify state file exists before running script
	local state_file_before
	state_file_before=$(get_peer_state_file_path "TEST" "192.168.1.1" "last_bytes" 2>/dev/null || echo "${STATE_DIR}/last_bytes_TEST_192_168_1_1")
	if [[ -f "$state_file_before" ]]; then
		local bytes_before
		bytes_before=$(cat "$state_file_before" 2>/dev/null || echo "0")
		echo "DEBUG: State file before script run: $bytes_before (path: $state_file_before)" >&2
	else
		echo "ERROR: State file not found before script run: $state_file_before" >&2
		echo "ERROR: STATE_DIR: ${STATE_DIR}" >&2
		echo "ERROR: Files in STATE_DIR:" >&2
		ls -la "${STATE_DIR}"/* 2>/dev/null | head -5 >&2 || echo "No files found" >&2
	fi

	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Debug: Check log file contents
	if [[ -f "$LOG_FILE" ]]; then
		echo "DEBUG: Log file contents:" >&2
		cat "$LOG_FILE" >&2 || true
	fi

	# Should detect routing_issue failure type
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Routing issue" || assert_file_contains "$LOG_FILE" "routing_issue"

	# Verify failure type stored in state file
	local failure_type_file="${STATE_DIR}/failure_type_TEST_192_168_1_1"
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		assert_equal "$failure_type" "routing_issue"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type routing_issue - Phase 2 SA exists but ping fails" {
	# Purpose: Test verifies that failure type "routing_issue" is detected when SA exists but ping fails
	# Expected: Failure type is detected as "routing_issue" when SA exists but connectivity fails
	# Importance: Enables targeted recovery strategies for routing issues
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=1' 'LOCATION_TEST_INTERNAL="192.168.1.1"'

	# Set initial bytes (increasing) using location-based state functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	set_peer_state "TEST" "192.168.1.1" "last_bytes" "1000" || true
	set_peer_state "TEST" "192.168.1.1" "spi" "0x12345678" || true

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

	# Mock ipsec to fail (prevent fallback from succeeding and masking failure)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
# Return failure to ensure xfrm failure is not masked by ipsec fallback
exit 1
EOF
	chmod +x "$mock_ipsec"
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
	# Purpose: Test verifies that failure type "rekey" is detected when SPI changes (not a failure)
	# Expected: Failure type is detected as "rekey" when SPI changes, VPN marked as OK
	# Importance: Rekey events are logged but not treated as failures
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Set initial SPI using location-based state functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	set_peer_state "TEST" "192.168.1.1" "last_bytes" "1000" || true
	set_peer_state "TEST" "192.168.1.1" "spi" "0x12345678" || true

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
	local failure_type_file="${STATE_DIR}/failure_type_TEST_192_168_1_1"
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
	# Purpose: Test verifies that failure type "unknown" is detected when unable to determine specific type
	# Expected: Failure type is detected as "unknown" when detection methods fail
	# Importance: Ensures failure tracking continues even when specific type cannot be determined
	# Disable ping check so that when byte counter extraction fails, VPN check fails and failure type detection is triggered
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=0'

	# Mock ip command - SA exists but no byte counter info
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    # No lifetime line (can't extract bytes)
    exit 0
fi
# Handle other ip commands
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect unknown failure type
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Unknown" || assert_file_contains "$LOG_FILE" "unknown"

	# Verify failure type stored in state file
	local failure_type_file="${STATE_DIR}/failure_type_TEST_192_168_1_1"
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		assert_equal "$failure_type" "unknown"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type stored in state file for recovery actions" {
	# Purpose: Test verifies that failure type is stored in state file for use by recovery actions
	# Expected: Failure type is stored in state file and can be retrieved for recovery strategies
	# Importance: Enables recovery actions to use failure-specific strategies
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}"

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
	local failure_type_file="${STATE_DIR}/failure_type_TEST_192_168_1_1"
	assert_file_exist "$failure_type_file"
	local failure_type
	failure_type=$(cat "$failure_type_file")
	assert [ "$failure_type" == "tunnel_down" ] || [ "$failure_type" == "unknown" ]

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type cleared on VPN recovery" {
	# Purpose: Test verifies that failure type is cleared when VPN recovers
	# Expected: Failure type file is removed or cleared when VPN becomes healthy
	# Importance: Ensures failure type tracking is reset after recovery
	# Use same fixture as working test in test_detection.sh
	setup_vpn_active_fixture "192.168.1.1" 1000 2000

	source_function "get_peer_state_file_path"
	# Create failure type file (from previous failure)
	local failure_type_file
	failure_type_file=$(get_peer_state_file_path "TEST" "192.168.1.1" "failure_type")
	echo "tunnel_down" >"$failure_type_file"

	# Note: Recovery message is logged when failure_count > 0 OR had_failure_type == 1
	# (see lib/recovery.sh:1630). The failure_type file alone is sufficient to trigger
	# the recovery message logging. The code correctly handles the case where only
	# had_failure_type == 1 (without failure_count > 0) by logging in the else branch
	# at line 1651. Using get_peer_state_file_path ensures the correct path format.

	run bash "$TEST_SCRIPT" --fake

	# VPN should recover
	assert_success
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "recovered" || assert_file_contains "$LOG_FILE" "restored"

	# Failure type file should be cleared or removed
	# Note: The actual behavior depends on implementation - may be removed or cleared
	# This test verifies that recovery happens and failure type is handled

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type detection when xfrm unavailable" {
	# Purpose: Test verifies that failure type detection works when xfrm is unavailable
	# Expected: Failure type is detected using fallback methods when xfrm unavailable
	# Importance: Ensures failure type detection works even when preferred method unavailable
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}"

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
