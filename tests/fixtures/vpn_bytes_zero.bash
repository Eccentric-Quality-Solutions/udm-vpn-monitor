#!/usr/bin/env bash
#
# Test fixture: VPN with Bytes=0 (Suspect Condition)
#
# Sets up a test environment where the VPN SA exists but byte counter is exactly 0,
# indicating a suspect condition (tunnel established but not passing traffic).
# This fixture combines common setup steps for tests that need this specific scenario.
#
# Arguments:
#   $1: Peer IP address (default: "${TEST_PEER_IP}")
#   $2: SPI value (default: 0x12345678)
#   $3+: Additional config variables as KEY="VALUE" pairs
#
# Side effects:
#   - Sets up test VPN monitor environment
#   - Creates mock ip command that returns SA with bytes=0
#   - Adds mocks to PATH
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR variables
#
# Example:
#   setup_vpn_bytes_zero_fixture "${TEST_PEER_IP}"
#   # VPN SA exists but bytes=0 (suspect condition)
#
#   setup_vpn_bytes_zero_fixture "${TEST_PEER_IP}" "0x87654321" 'ENABLE_NETWORK_PARTITION_CHECK=0'
#   # VPN SA exists but bytes=0 with custom SPI and config
setup_vpn_bytes_zero_fixture() {
	local peer_ip="${1:-${TEST_PEER_IP}}"
	local spi="${2:-0x12345678}"
	shift 2 || true
	local extra_config=("$@")

	# Set up test VPN monitor with location-based config
	setup_location_vpn_monitor "$peer_ip" "${TEST_DIR}" "${extra_config[@]}"

	# Mock ip command - SA exists but bytes=0
	mock_ip_xfrm_state "$peer_ip" "0" "$spi" >/dev/null

	# Add mocks to PATH
	add_mock_to_path

	export MOCK_IP="${TEST_DIR}/ip"
}
