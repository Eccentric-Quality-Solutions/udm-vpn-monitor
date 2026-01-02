#!/usr/bin/env bash
#
# Test fixture: VPN Failing Scenario
#
# Sets up a test environment where the VPN has recorded failures but is still
# being monitored. The VPN may be down or the byte counter may not be increasing.
#
# Arguments:
#   $1: Peer IP address (default: "192.168.1.1")
#   $2: Failure count (default: 3)
#   $3: Last bytes value (default: 1000)
#   $4: Current bytes value for mock (default: 1000, same as last - not increasing)
#   $5: SPI value (default: 0x12345678)
#   $6+: Additional config variables as KEY="VALUE" pairs
#
# Side effects:
#   - Sets up test VPN monitor environment
#   - Creates state files with failure count and last bytes
#   - Creates mock VPN environment with bytes not increasing
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR variables
#
# Example:
#   setup_vpn_failing_fixture "192.168.1.1" 3
#   # VPN has 3 failures, bytes stuck at 1000
#
#   setup_vpn_failing_fixture "192.168.1.1" 5 5000 5000
#   # VPN has 5 failures, bytes stuck at 5000
setup_vpn_failing_fixture() {
	local peer_ip="${1:-192.168.1.1}"
	local failure_count="${2:-3}"
	local last_bytes="${3:-1000}"
	local current_bytes="${4:-$last_bytes}"
	local spi="${5:-0x12345678}"
	shift 5 || true
	local extra_config=("$@")

	# Set up test VPN monitor with location-based config
	setup_location_vpn_monitor "$peer_ip" "${TEST_DIR}" "${extra_config[@]}"

	# Set up state files with failure count and last bytes using location-based state functions
	# setup_location_vpn_monitor creates location "TEST"
	ensure_state_functions_loaded
	set_peer_state "TEST" "$peer_ip" "failure_count" "$failure_count" || true
	set_peer_state "TEST" "$peer_ip" "last_bytes" "$last_bytes" || true
	if [[ -n "$spi" ]]; then
		set_peer_state "TEST" "$peer_ip" "spi" "$spi" || true
	fi

	# Set up mock VPN environment with bytes not increasing (or VPN down)
	# If current_bytes equals last_bytes, bytes aren't increasing (failure scenario)
	setup_mock_vpn_environment "$peer_ip" "$current_bytes" "$spi"
}
