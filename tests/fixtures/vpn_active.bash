#!/usr/bin/env bash
#
# Test fixture: VPN Active Scenario
#
# Sets up a test environment where the VPN is active and healthy.
# This fixture combines common setup steps for tests that need a working VPN.
#
# Arguments:
#   $1: Peer IP address (default: "${TEST_PEER_IP}")
#   $2: Initial byte counter value (default: 1000)
#   $3: Current byte counter value (default: 2000, should be > initial)
#   $4: SPI value (default: 0x12345678)
#   $5+: Additional config variables as KEY="VALUE" pairs
#
# Side effects:
#   - Sets up test VPN monitor environment
#   - Creates state files with initial byte counter
#   - Creates mock VPN environment with current byte counter
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR variables
#
# Example:
#   setup_vpn_active_fixture "${TEST_PEER_IP}"
#   # VPN is active, bytes increased from 1000 to 2000
#
#   setup_vpn_active_fixture "${TEST_PEER_IP2}" 5000 6000
#   # VPN is active, bytes increased from 5000 to 6000
setup_vpn_active_fixture() {
	local peer_ip="${1:-${TEST_PEER_IP}}"
	local initial_bytes="${2:-1000}"
	local current_bytes="${3:-2000}"
	local spi="${4:-0x12345678}"
	shift 4 || true
	local extra_config=("$@")

	# Set up test VPN monitor with location-based config
	setup_location_vpn_monitor "$peer_ip" "${TEST_DIR}" "${extra_config[@]}"

	# Set up state files with initial byte counter (no failures) using location-based state functions
	# setup_location_vpn_monitor creates location "TEST"
	ensure_state_functions_loaded
	set_peer_state "TEST" "$peer_ip" "last_bytes" "$initial_bytes" || true
	if [[ -n "$spi" ]]; then
		set_peer_state "TEST" "$peer_ip" "spi" "$spi" || true
	fi

	# Set up mock VPN environment with current byte counter (VPN active, bytes increasing)
	setup_mock_vpn_environment "$peer_ip" "$current_bytes" "$spi"
}
