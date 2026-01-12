#!/usr/bin/env bash
#
# Test fixture: VPN Mixed Peers Scenario
#
# Sets up a test environment with multiple VPN peers where some are up and some are down.
# This fixture allows testing independent peer state tracking and per-peer recovery actions.
#
# Arguments:
#   $1: Peer IPs as space-separated string (default: "${TEST_PEER_IP} ${TEST_PEER_IP2} 172.16.0.1")
#   $2: States as space-separated string ("up" or "down" for each peer, default: "up up up")
#   $3: Bytes value for peers that are "up" (default: 1000)
#   $4: SPI value for all peers (default: 0x12345678)
#   $5+: Additional config variables as KEY="VALUE" pairs
#
# Side effects:
#   - Sets up test VPN monitor environment with multiple peers
#   - Creates state files for each peer based on their state
#   - Creates mock VPN environment that returns SAs only for peers that are "up"
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR variables
#
# Example:
#   setup_vpn_mixed_peers_fixture "192.168.1.1 192.168.1.2 192.168.1.3" "up down up"
#   # Sets peer 1 up, peer 2 down, peer 3 up
#
#   setup_vpn_mixed_peers_fixture "${TEST_PEER_IP} ${TEST_PEER_IP2}" "up down" 2000
#   # Two peers: first up with 2000 bytes, second down
setup_vpn_mixed_peers_fixture() {
	local peer_ips="${1:-${TEST_PEER_IP} ${TEST_PEER_IP2} 172.16.0.1}"
	local states="${2:-up up up}"
	local bytes="${3:-1000}"
	local spi="${4:-0x12345678}"
	shift 4 || true
	local extra_config=("$@")

	# Set up test VPN monitor with multiple peers
	setup_test_vpn_monitor "$peer_ips" "${TEST_DIR}" "${extra_config[@]}"

	# Parse peer IPs and states into arrays
	local ip_array
	read -ra ip_array <<<"$peer_ips" || true
	local state_array
	read -ra state_array <<<"$states" || true

	# Validate that we have matching counts (or at least one state per IP)
	local ip_count=0
	local state_count=${#state_array[@]}
	for ip in "${ip_array[@]}"; do
		[[ -n "$ip" ]] && ((ip_count++))
	done

	if [[ $state_count -lt $ip_count ]]; then
		echo "Error: Not enough states provided. Got $state_count states for $ip_count peers" >&2
		return 1
	fi

	# Set up state files for each peer using location-aware functions
	# setup_test_vpn_monitor creates locations TEST1, TEST2, TEST3, etc. for each IP in order
	ensure_state_functions_loaded
	local location_num=1
	local state_idx=0
	for peer_ip in "${ip_array[@]}"; do
		# Skip empty IPs (from multiple spaces)
		[[ -z "$peer_ip" ]] && continue

		# Get state for this peer (default to "up" if not enough states provided)
		local peer_state="${state_array[$state_idx]:-up}"
		((state_idx++))

		# Validate state
		if [[ "$peer_state" != "up" ]] && [[ "$peer_state" != "down" ]]; then
			echo "Error: State must be 'up' or 'down', got: $peer_state for peer $peer_ip" >&2
			return 1
		fi

		# Map IP to location name (TEST1, TEST2, TEST3, etc.)
		local location_name="TEST${location_num}"

		if [[ "$peer_state" == "up" ]]; then
			# Peer is up - set initial byte counter and SPI
			set_peer_state "$location_name" "$peer_ip" "last_bytes" "$bytes" || true
			if [[ -n "$spi" ]]; then
				set_peer_state "$location_name" "$peer_ip" "spi" "$spi" || true
			fi
		else
			# Peer is down - no state files needed initially (will be created on first failure)
			# Optionally set failure count to 0 if we want to track that it's down but not failed yet
			# For now, we leave it without state files
			:
		fi

		((location_num++))
	done

	# Create mock ip command that returns SAs only for peers that are "up"
	# Note: get_xfrm_state_for_peer tries "ip -s xfrm state" first, then falls back to "ip xfrm state"
	local mock_ip="${TEST_DIR}/ip"
	{
		cat <<'EOF'
#!/bin/bash
if [[ "$1" == "-s" ]] && [[ "$2" == "xfrm" ]] && [[ "$3" == "state" ]]; then
    # Handle "ip -s xfrm state" (with statistics flag) - tried first by get_xfrm_state_for_peer
    # Return SA only for peers that are "up"
EOF
		# Add SA output for each peer that is "up"
		state_idx=0
		for peer_ip in "${ip_array[@]}"; do
			[[ -z "$peer_ip" ]] && continue
			local peer_state="${state_array[$state_idx]:-up}"
			((state_idx++))
			if [[ "$peer_state" == "up" ]]; then
				echo "    echo \"src $peer_ip dst $peer_ip\""
				echo "    echo \"    proto esp spi $spi reqid 1 mode tunnel\""
				echo "    echo \"    lifetime current: $bytes bytes, 10 packets\""
			fi
		done
		echo "    exit 0"
		echo "elif [[ \"\$1\" == \"xfrm\" ]] && [[ \"\$2\" == \"state\" ]]; then"
		echo "    # Handle \"ip xfrm state\" (without statistics flag) - fallback used by get_xfrm_state_for_peer"
		echo "    # Return SA only for peers that are \"up\""
		# Add SA output for each peer that is "up" (duplicate for fallback handler)
		state_idx=0
		for peer_ip in "${ip_array[@]}"; do
			[[ -z "$peer_ip" ]] && continue
			local peer_state="${state_array[$state_idx]:-up}"
			((state_idx++))
			if [[ "$peer_state" == "up" ]]; then
				echo "    echo \"src $peer_ip dst $peer_ip\""
				echo "    echo \"    proto esp spi $spi reqid 1 mode tunnel\""
				echo "    echo \"    lifetime current: $bytes bytes, 10 packets\""
			fi
		done
		echo "    exit 0"
		echo "fi"
		echo "# Handle other ip commands"
		echo "exec /usr/bin/ip \"\$@\""
	} >"$mock_ip"
	chmod +x "$mock_ip"

	# Add mocks to PATH (don't call setup_mock_vpn_environment as it would overwrite our custom mock)
	add_mock_to_path

	export MOCK_IP="$mock_ip"
	export VPN_PEER_IPS="$peer_ips"
	export VPN_PEER_STATES="$states"
}
