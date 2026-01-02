#!/usr/bin/env bash
#
# Test fixture: VPN Rekey Scenario
#
# Sets up a test environment where the VPN has undergone a rekey (SPI change).
# This fixture combines common setup steps for tests that need to verify rekey detection.
#
# Arguments:
#   $1: Peer IP address (default: "192.168.1.1")
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
#   setup_vpn_rekey_fixture "192.168.1.1"
#   # VPN has rekeyed, SPI changed from 0x12345678 to 0x87654321
#
#   setup_vpn_rekey_fixture "10.0.0.1" "0x11111111" "0x22222222" 10000 2000
#   # VPN has rekeyed with custom SPI and bytes values
setup_vpn_rekey_fixture() {
	local peer_ip="${1:-192.168.1.1}"
	local old_spi="${2:-0x12345678}"
	local new_spi="${3:-0x87654321}"
	local old_bytes="${4:-5000}"
	local new_bytes="${5:-1000}"
	shift 5 || true
	local extra_config=("$@")

	# Set up test VPN monitor with config
	setup_test_vpn_monitor "$peer_ip" "${TEST_DIR}" "${extra_config[@]}"

	# Set up state files with old SPI and old bytes (before rekey) using location-aware functions
	# setup_test_vpn_monitor creates location "TEST1" for single IP
	ensure_state_functions_loaded
	set_peer_state "TEST1" "$peer_ip" "last_bytes" "$old_bytes" || true
	if [[ -n "$old_spi" ]]; then
		set_peer_state "TEST1" "$peer_ip" "spi" "$old_spi" || true
	fi

	# Create mock ip command that returns new SPI (rekey occurred)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    echo "src $peer_ip dst $peer_ip"
    echo "    proto esp spi $new_spi reqid 1 mode tunnel"
    echo "    lifetime current: $new_bytes bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	export MOCK_IP="$mock_ip"
}
