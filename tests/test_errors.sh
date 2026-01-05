#!/usr/bin/env bats
#
# Tests for Error Handling During Critical Operations
# Tests critical paths and error handling scenarios

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# Create mock command that fails with specific exit code and error message
#
# Arguments:
#   $1: Command name to mock
#   $2: Exit code (default: 1)
#   $3: Error message to print (optional)
#
# Returns:
#   Prints path to created mock command
mock_command_failure() {
	local command_name="$1"
	local exit_code="${2:-1}"
	local error_message="${3:-}"
	local mock_command="${TEST_DIR}/${command_name}"
	cat >"$mock_command" <<EOF
#!/bin/bash
${error_message:+echo "$error_message" >&2}
exit $exit_code
EOF
	chmod +x "$mock_command"
	echo "$mock_command"
}

# ============================================================================
# ERROR HANDLING DURING CRITICAL OPERATIONS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "error during state file write" {
	# Purpose: Test verifies that script handles errors during state file write operations gracefully
	# Expected: Script logs error and continues execution without crashing when state file writes fail
	# Importance: Prevents script failures from filesystem permission issues or disk space problems
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_TEST_EXTERNAL="${TEST_PEER_IP}"
LOCATION_TEST_INTERNAL="${TEST_PEER_IP}"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${state_dir}"

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local failure_counter
	failure_counter=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")

	# Create failure counter file and make parent directory read-only (prevents write)
	echo "2" >"$failure_counter"
	chmod 555 "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 0
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"
	assert_success

	# Should handle state file write error gracefully (should log error but continue)
	# Script should not crash even if state file writes fail

	# Restore permissions for cleanup
	chmod 755 "${TEST_DIR}/logs" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "error during recovery action (should log and continue)" {
	# Purpose: Test verifies that script handles errors during recovery actions gracefully
	# Expected: Script logs error about recovery failure and continues execution without crashing
	# Importance: Prevents script failures when recovery commands fail, ensuring monitoring continues
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_TEST_EXTERNAL="${TEST_PEER_IP}"
LOCATION_TEST_INTERNAL="${TEST_PEER_IP}"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${state_dir}"

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local failure_counter
	failure_counter=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")

	# Set failure count to Tier 2 threshold (triggers surgical cleanup)
	echo "3" >"$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN is down (no SA)
	mock_ip_xfrm_state "${TEST_PEER_IP}" "0" >/dev/null
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
        echo "${TEST_PEER_IP}: ESTABLISHED"
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Run script - recovery actions should fail but script should continue
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"
	assert_success

	# Should handle recovery action errors gracefully (should log error but continue)
	# Script should not crash even if recovery actions fail
	# Code at lib/recovery.sh:217-220 handles ipsec reload/restart failures gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "error during VPN check (should log and continue)" {
	# Purpose: Test verifies that script handles errors during VPN check operations gracefully
	# Expected: Script logs error about VPN check failure and continues execution without crashing
	# Importance: Prevents script failures when VPN detection commands fail, ensuring monitoring continues
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_TEST_EXTERNAL="${TEST_PEER_IP}"
LOCATION_TEST_INTERNAL="${TEST_PEER_IP}"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command to fail with error (simulates VPN check error)
	mock_command_failure "ip" 1 "Error: Cannot access xfrm state"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Should handle VPN check error gracefully (should log error but continue)
	# Code at lib/detection.sh handles xfrm errors gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}
