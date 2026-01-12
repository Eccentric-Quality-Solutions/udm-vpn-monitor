#!/usr/bin/env bash
#
# Test fixture: VPN Rekey Scenario
#
# Sets up a test environment where the VPN has undergone a rekey (SPI change).
# This fixture combines common setup steps for tests that need to verify rekey detection.
#
# Arguments:
#   $1: Peer IP address (default: "${TEST_PEER_IP}")
#   $2: Old SPI value (default: 0x12345678)
#   $3: New SPI value (default: 0x87654321)
#   $4: Old bytes value (default: 5000)
#   $5: New bytes value (default: 1000, typically lower after rekey)
#   $6+: Additional config variables as KEY="VALUE" pairs
#
# Side effects:
#   - Sets up test VPN monitor environment
#   - Creates state files with old SPI and old bytes
#   - Creates mock VPN environment with new SPI and new bytes
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR variables
#
# Example:
#   setup_vpn_rekey_fixture "${TEST_PEER_IP}"
#   # VPN has rekeyed, SPI changed from 0x12345678 to 0x87654321
#
#   setup_vpn_rekey_fixture "${TEST_PEER_IP2}" "0x11111111" "0x22222222" 10000 2000
#   # VPN has rekeyed with custom SPI and bytes values
setup_vpn_rekey_fixture() {
	local peer_ip="${1:-${TEST_PEER_IP}}"
	local old_spi="${2:-0x12345678}"
	local new_spi="${3:-0x87654321}"
	local old_bytes="${4:-5000}"
	local new_bytes="${5:-1000}"
	shift 5 || true
	local extra_config=("$@")

	# Set up test VPN monitor with location-based config
	setup_location_vpn_monitor "$peer_ip" "${TEST_DIR}" "${extra_config[@]}"

	# Set up state files with old SPI and old bytes (before rekey) using location-based state functions
	# setup_location_vpn_monitor creates location "TEST"
	ensure_state_functions_loaded
	set_peer_state "TEST" "$peer_ip" "last_bytes" "$old_bytes" || true
	if [[ -n "$old_spi" ]]; then
		set_peer_state "TEST" "$peer_ip" "spi" "$old_spi" || true
	fi

	# Create mock ip command that returns new SPI (rekey occurred)
	mock_ip_xfrm_state "$peer_ip" "$new_bytes" "$new_spi" "$peer_ip" >/dev/null
	add_mock_to_path

	export MOCK_IP="${TEST_DIR}/ip"
}
