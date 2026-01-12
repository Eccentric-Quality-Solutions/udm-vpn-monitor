#!/usr/bin/env bash
#
# Test fixture: VPN Idle Tunnel Scenario
#
# Sets up a test environment where the VPN tunnel is idle (bytes not increasing)
# but ping succeeds. This simulates a healthy tunnel that is not passing traffic.
#
# Arguments:
#   $1: Peer IP address (default: "${TEST_PEER_IP}")
#   $2: Static bytes value (default: 1000) - bytes that don't increase
#   $3: Internal IP for ping check (default: "${TEST_PEER_IP2}")
#   $4: SPI value (default: 0x12345678)
#   $5+: Additional config variables as KEY="VALUE" pairs
#
# Side effects:
#   - Sets up test VPN monitor environment with ping check enabled
#   - Creates state files with static byte counter
#   - Creates mock VPN environment with static bytes (SA exists but bytes don't increase)
#   - Creates mock ping command that succeeds
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR variables
#
# Example:
#   setup_vpn_idle_fixture "${TEST_PEER_IP}"
#   # Idle tunnel: bytes static at 1000, ping succeeds
#
#   setup_vpn_idle_fixture "${TEST_PEER_IP}" 5000 "10.0.0.1"
#   # Idle tunnel: bytes static at 5000, ping to 10.0.0.1 succeeds
setup_vpn_idle_fixture() {
	local peer_ip="${1:-${TEST_PEER_IP}}"
	local static_bytes="${2:-1000}"
	local internal_ip="${3:-${TEST_PEER_IP2}}"
	local spi="${4:-0x12345678}"
	shift 4 || true
	local extra_config=("$@")

	# Set up test VPN monitor with ping check enabled
	local config_with_ping=("ENABLE_PING_CHECK=1" "LOCATION_TEST_INTERNAL=\"${internal_ip}\"" "${extra_config[@]}")
	setup_location_vpn_monitor "$peer_ip" "${TEST_DIR}" "${config_with_ping[@]}"

	# Set up state files with static byte counter (bytes not increasing)
	# setup_location_vpn_monitor creates location "TEST"
	ensure_state_functions_loaded
	set_peer_state "TEST" "$peer_ip" "last_bytes" "$static_bytes" || true
	if [[ -n "$spi" ]]; then
		set_peer_state "TEST" "$peer_ip" "spi" "$spi" || true
	fi

	# Mock ip command - SA exists, bytes static (not increasing)
	mock_ip_xfrm_state "$peer_ip" "$static_bytes" "$spi" "$peer_ip" >/dev/null

	# Mock ping - succeeds (tunnel is healthy, just idle)
	mock_ping_success >/dev/null

	# Add mocks to PATH
	add_mock_to_path
}
