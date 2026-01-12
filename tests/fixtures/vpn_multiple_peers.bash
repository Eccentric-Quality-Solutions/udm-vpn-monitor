#!/usr/bin/env bash
#
# Test fixture: VPN Multiple Peers Scenario
#
# Sets up a test environment with multiple VPN peers for testing multi-peer scenarios.
# This fixture combines common setup steps for tests that need multiple peers.
#
# Arguments:
#   $1: Peer IPs as space-separated string (default: "${TEST_PEER_IP} ${TEST_PEER_IP2} 172.16.0.1")
#   $2: Failure count for all peers (default: 0)
#   $3: Bytes value for all peers (default: 1000)
#   $4: SPI value for all peers (default: 0x12345678)
#   $5+: Additional config variables as KEY="VALUE" pairs
#
# Side effects:
#   - Sets up test VPN monitor environment with multiple peers
#   - Creates state files for all peers
#   - Creates mock VPN environment for all peers
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR variables
#
# Example:
#   setup_vpn_multiple_peers_fixture "${TEST_PEER_IP} ${TEST_PEER_IP2}"
#   # Two peers, both healthy
#
#   setup_vpn_multiple_peers_fixture "192.168.1.1 10.0.0.1 172.16.0.1" 2 5000
#   # Three peers, all with 2 failures and 5000 bytes
setup_vpn_multiple_peers_fixture() {
	local peer_ips="${1:-${TEST_PEER_IP} ${TEST_PEER_IP2} 172.16.0.1}"
	local failure_count="${2:-0}"
	local bytes="${3:-1000}"
	local spi="${4:-0x12345678}"
	shift 4 || true
	local extra_config=("$@")

	# Set up test VPN monitor with multiple peers
	setup_test_vpn_monitor "$peer_ips" "${TEST_DIR}" "${extra_config[@]}"

	# Set up state files for each peer using location-aware functions
	# setup_test_vpn_monitor creates locations TEST1, TEST2, TEST3, etc. for each IP in order
	ensure_state_functions_loaded
	local peer_ip
	local location_num=1
	for peer_ip in $peer_ips; do
		# Skip empty IPs (from multiple spaces)
		[[ -z "$peer_ip" ]] && continue

		# Map IP to location name (TEST1, TEST2, TEST3, etc.)
		local location_name="TEST${location_num}"
		set_peer_state "$location_name" "$peer_ip" "failure_count" "$failure_count" || true
		if [[ "$bytes" != "0" ]] || [[ "$failure_count" -gt 0 ]]; then
			set_peer_state "$location_name" "$peer_ip" "last_bytes" "$bytes" || true
		fi
		if [[ -n "$spi" ]]; then
			set_peer_state "$location_name" "$peer_ip" "spi" "$spi" || true
		fi
		location_num=$((location_num + 1))
	done

	# Create mock ip command that handles multiple peers
	# This mock returns SAs for all configured peers
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Return SA for all configured peers
$(for peer_ip in $peer_ips; do
		echo "    echo \"src $peer_ip dst $peer_ip\""
		echo "    echo \"    proto esp spi $spi reqid 1 mode tunnel\""
		echo "    echo \"    lifetime current: $bytes bytes, 10 packets\""
	done)
fi
EOF
	chmod +x "$mock_ip"

	# Add mocks to PATH (don't call setup_mock_vpn_environment as it would overwrite our custom mock)
	add_mock_to_path

	export MOCK_IP="$mock_ip"
	export VPN_PEER_IPS="$peer_ips"
}
