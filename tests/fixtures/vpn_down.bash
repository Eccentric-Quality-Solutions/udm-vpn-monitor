#!/usr/bin/env bash
#
# Test fixture: VPN Down Scenario
#
# Sets up a test environment where the VPN is down (no Security Association found).
# This fixture combines common setup steps for tests that need a VPN failure scenario.
#
# Arguments:
#   $1: Peer IP address (default: "${TEST_PEER_IP}")
#   $2: Failure count (default: 0, will be incremented when script runs)
#   $3+: Additional config variables as KEY="VALUE" pairs
#
# Side effects:
#   - Sets up test VPN monitor environment
#   - Creates state files (optional, based on failure count)
#   - Creates mock ip command that returns empty output (no SA)
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR variables
#   - Adds mock commands to PATH
#
# Example:
#   setup_vpn_down_fixture "${TEST_PEER_IP}"
#   # VPN is down, no SA found
#
#   setup_vpn_down_fixture "${TEST_PEER_IP}" 2
#   # VPN is down, already has 2 failures recorded
setup_vpn_down_fixture() {
	local peer_ip="${1:-${TEST_PEER_IP}}"
	local failure_count="${2:-0}"
	shift 2 || true
	local extra_config=("$@")

	# Set up test VPN monitor with location-based config
	setup_location_vpn_monitor "$peer_ip" "${TEST_DIR}" "${extra_config[@]}"

	# Set up state files if failure count > 0 (otherwise no state files needed) using location-based state functions
	# setup_location_vpn_monitor creates location "TEST"
	if [[ "$failure_count" -gt 0 ]]; then
		ensure_state_functions_loaded
		set_peer_state "TEST" "$peer_ip" "failure_count" "$failure_count" || true
	fi

	# Create mock ip command that returns empty output (VPN down, no SA)
	mock_ip_vpn_down >/dev/null

	# Add mocks to PATH
	add_mock_to_path

	export MOCK_IP="${TEST_DIR}/ip"
}
