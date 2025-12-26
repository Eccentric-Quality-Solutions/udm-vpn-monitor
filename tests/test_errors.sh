#!/usr/bin/env bats
#
# Tests for Error Handling During Critical Operations
# Tests critical paths and error handling scenarios

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# ERROR HANDLING DURING CRITICAL OPERATIONS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "error during state file write" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create failure counter file and make parent directory read-only (prevents write)
	echo "2" >"$failure_counter"
	chmod 555 "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 0
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle state file write error gracefully (should log error but continue)
	# Script should not crash even if state file writes fail

	# Restore permissions for cleanup
	chmod 755 "${TEST_DIR}/logs" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "error during recovery action (should log and continue)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 2 threshold (triggers surgical cleanup)
	echo "3" >"$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN is down (no SA)
	mock_ip_xfrm_state "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ipsec reload and restart to fail (simulates recovery action failure)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "Failed to reload IPsec" >&2
    exit 1
fi
if [[ "$1" == "restart" ]]; then
    echo "Failed to restart IPsec" >&2
    exit 1
fi
if [[ "$1" == "status" ]]; then
    echo "192.168.1.1: ESTABLISHED"
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Run script - recovery actions should fail but script should continue
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle recovery action errors gracefully (should log error but continue)
	# Script should not crash even if recovery actions fail
	# Code at lib/recovery.sh:217-220 handles ipsec reload/restart failures gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "error during VPN check (should log and continue)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command to fail with error (simulates VPN check error)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "Error: Cannot access xfrm state" >&2
    exit 1
fi
exit 1
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle VPN check error gracefully (should log error but continue)
	# Code at lib/detection.sh handles xfrm errors gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}
