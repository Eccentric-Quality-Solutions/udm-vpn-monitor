#!/usr/bin/env bats
#
# Tests for Detection Reliability Safeguard
# Tests that recovery escalation is blocked when detection is unreliable
#
# These tests verify the safety safeguard that prevents recovery escalation
# when both detection tools (ip and ipsec) are unavailable and failure type
# is "unknown", preventing false recovery actions.

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_at_tier

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# DETECTION RELIABILITY SAFEGUARD TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "detection reliability: recovery escalation blocked when both ip and ipsec unavailable" {
	# Purpose: Test verifies that recovery escalation is blocked when both detection tools are unavailable
	# Expected: Script logs error about unreliable detection and skips Tier 2/3 recovery escalation
	# Importance: Prevents false recovery actions when detection is unreliable
	setup_vpn_at_tier_fixture 3 "${TEST_PEER_IP}" 'MAX_RESTARTS_PER_HOUR=10' 'COOLDOWN_MINUTES=1' 'ENABLE_NETWORK_PARTITION_CHECK=0'

	# Remove ip mock (make it unavailable)
	# setup_vpn_at_tier_fixture creates a mock ip, but we need to remove it
	rm -f "${TEST_DIR}/ip"

	# Don't create ipsec mock (unavailable)
	# Ensure PATH doesn't include system directories with these commands
	local original_path="$PATH"
	export PATH="${TEST_DIR}:/usr/bin:/bin"

	# Verify commands are truly unavailable (check_command_available checks system dirs)
	# Skip test if commands are found in system directories
	# check_command_available is loaded via test_helper (sources common.sh)
	if check_command_available "ip" || check_command_available "ipsec"; then
		skip "ip or ipsec found in system directories - cannot test 'both unavailable' scenario"
	fi

	run bash "$TEST_SCRIPT" --fake

	# Script should handle gracefully (exit code 0 or 1 is acceptable)
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should log error about unreliable detection
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Detection unreliable"
	assert_file_contains "$LOG_FILE" "skipping recovery escalation"

	# Should NOT attempt Tier 3 recovery
	assert_log_not_contains "$LOG_FILE" "Tier 3: Attempting IPsec restart"
	assert_log_not_contains "$LOG_FILE" "Tier 3: Would attempt full IPsec restart"

	# Should still log Tier 1 failure (monitoring continues)
	assert_file_contains "$LOG_FILE" "Tier 1" || assert_file_contains "$LOG_FILE" "VPN check failed"

	# Restore PATH
	export PATH="$original_path"
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "detection reliability: recovery escalation proceeds when ip available" {
	# Purpose: Test verifies that recovery escalation proceeds when at least one detection tool is available
	# Expected: Script proceeds with recovery escalation when ip command is available (even if ipsec unavailable)
	# Importance: Ensures recovery works when at least one detection method is available
	setup_vpn_at_tier_fixture 3 "${TEST_PEER_IP}" 'MAX_RESTARTS_PER_HOUR=10' 'COOLDOWN_MINUTES=1' 'ENABLE_NETWORK_PARTITION_CHECK=0' 'ENABLE_XFRM_RECOVERY=0'

	# Keep ip mock (available) - setup_vpn_at_tier_fixture creates it
	# Don't create ipsec mock (unavailable)

	# Mock ipsec for recovery (even though detection can't use it, recovery needs it)
	mock_ipsec_reload_restart 0 0
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake

	# Script should handle gracefully
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should proceed with Tier 3 recovery (ip is available, so detection is reliable)
	assert_file_exist "$LOG_FILE"
	# Should attempt Tier 3 recovery
	assert_file_contains "$LOG_FILE" "Tier 3" || assert_file_contains "$LOG_FILE" "Would attempt"

	# Should NOT log detection unreliable error
	assert_log_not_contains "$LOG_FILE" "Detection unreliable"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "detection reliability: recovery escalation proceeds when ipsec available" {
	# Purpose: Test verifies that recovery escalation proceeds when at least one detection tool is available
	# Expected: Script proceeds with recovery escalation when ipsec command is available (even if ip unavailable)
	# Importance: Ensures recovery works when at least one detection method is available
	setup_vpn_at_tier_fixture 3 "${TEST_PEER_IP}" 'MAX_RESTARTS_PER_HOUR=10' 'COOLDOWN_MINUTES=1' 'ENABLE_NETWORK_PARTITION_CHECK=0' 'ENABLE_XFRM_RECOVERY=0'

	# Remove ip mock (unavailable)
	rm -f "${TEST_DIR}/ip"

	# Create ipsec mock (available for both detection and recovery)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # Return empty (no connection found) to simulate VPN failure
    exit 0
elif [[ "$1" == "restart" ]]; then
    echo "Restarted"
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"

	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake

	# Script should handle gracefully
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should proceed with Tier 3 recovery (ipsec is available, so detection is reliable)
	assert_file_exist "$LOG_FILE"
	# Should attempt Tier 3 recovery
	assert_file_contains "$LOG_FILE" "Tier 3" || assert_file_contains "$LOG_FILE" "Would attempt"

	# Should NOT log detection unreliable error
	assert_log_not_contains "$LOG_FILE" "Detection unreliable"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "detection reliability: failures still logged when recovery blocked" {
	# Purpose: Test verifies that failures are still logged even when recovery escalation is blocked
	# Expected: Script logs VPN failure and Tier 1 message even when recovery is blocked
	# Importance: Ensures monitoring continues even when recovery is unavailable
	setup_vpn_at_tier_fixture 3 "${TEST_PEER_IP}" 'MAX_RESTARTS_PER_HOUR=10' 'COOLDOWN_MINUTES=1' 'ENABLE_NETWORK_PARTITION_CHECK=0'

	# Remove ip mock (unavailable)
	rm -f "${TEST_DIR}/ip"

	# Don't create ipsec mock (unavailable)
	local original_path="$PATH"
	export PATH="${TEST_DIR}:/usr/bin:/bin"

	# Verify commands are truly unavailable (check_command_available checks system dirs)
	# Skip test if commands are found in system directories
	if check_command_available "ip" || check_command_available "ipsec"; then
		skip "ip or ipsec found in system directories - cannot test 'both unavailable' scenario"
	fi

	run bash "$TEST_SCRIPT" --fake

	# Script should handle gracefully
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should log VPN failure
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "VPN check failed"

	# Should log Tier 1 message (monitoring continues)
	assert_file_contains "$LOG_FILE" "Tier 1" || assert_file_contains "$LOG_FILE" "Logging.*failure"

	# Should log that recovery was skipped
	assert_file_contains "$LOG_FILE" "recovery skipped - detection unreliable"

	# Restore PATH
	export PATH="$original_path"
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "detection reliability: safeguard only applies to unknown failure type" {
	# Purpose: Test verifies that safeguard only applies when failure type is "unknown"
	# Expected: Recovery proceeds normally when failure type is known (e.g., "tunnel_down") even if detection tools limited
	# Importance: Ensures safeguard doesn't block recovery when we can reliably determine failure type
	setup_vpn_at_tier_fixture 3 "${TEST_PEER_IP}" 'MAX_RESTARTS_PER_HOUR=10' 'COOLDOWN_MINUTES=1' 'ENABLE_NETWORK_PARTITION_CHECK=0' 'ENABLE_XFRM_RECOVERY=0'

	# Keep ip mock (available) - needed to detect tunnel_down failure type
	# setup_vpn_at_tier_fixture creates mock ip that returns empty (VPN down)
	# This will result in "tunnel_down" failure type, not "unknown"

	# Mock ipsec for recovery
	mock_ipsec_reload_restart 0 0
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake

	# Script should handle gracefully
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should proceed with Tier 3 recovery (failure type is known, not unknown)
	assert_file_exist "$LOG_FILE"
	# Should attempt Tier 3 recovery
	assert_file_contains "$LOG_FILE" "Tier 3" || assert_file_contains "$LOG_FILE" "Would attempt"

	# Should NOT log detection unreliable error (failure type is known)
	assert_log_not_contains "$LOG_FILE" "Detection unreliable"

	remove_mock_from_path
}
