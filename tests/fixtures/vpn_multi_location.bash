#!/usr/bin/env bash
#
# Test fixture: Multi-Location VPN Scenario
#
# Sets up a test environment with 2–3 named locations and configurable per-location
# state (healthy, failing, idle). Optionally sets shared system-wide failure or
# network partition state. Use for cross-location recovery, per-location rate limits,
# and system-wide failure with partial recovery tests.
#
# Arguments:
#   $1: Location 1 spec "NAME:IP:STATE" (default: "LOC1:${TEST_PEER_IP}:healthy")
#   $2: Location 2 spec (optional, default: "LOC2:192.168.1.2:failing")
#   $3: Location 3 spec (optional)
#   $4+: Extra config as KEY="VALUE". Special keys (consumed, not written to config):
#        SYSTEM_WIDE_FAILURE_STATE=0|1 - write ${STATE_DIR}/system_wide_failure_state
#        NETWORK_PARTITION_STATE=0|1   - write ${STATE_DIR}/network_partition_state
#
# STATE per location:
#   healthy - SA present, bytes increasing (mock returns SA with bytes > last_bytes)
#   failing - No SA in mock (or bytes stale), failure_count set
#   idle    - SA present, bytes unchanged (mock returns same bytes as last_bytes)
#
# Side effects:
#   - Sets up test environment, config with 2–3 locations, test script
#   - Creates per-location state files (failure_count, last_bytes, spi as needed)
#   - Writes system_wide_failure_state / network_partition_state if requested
#   - Creates mock ip that returns SAs only for healthy/idle locations
#   - Adds mock to PATH
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR, MOCK_IP,
#     VPN_MULTI_LOCATION_SPECS (space-separated "NAME:IP:STATE")
#
# Note: IP in NAME:IP:STATE must be IPv4 (colons would break parsing for IPv6).
#
# Example:
#   setup_vpn_multi_location_fixture "LOC1:${TEST_PEER_IP}:healthy" "LOC2:192.168.1.2:failing"
#   setup_vpn_multi_location_fixture "NYC:203.0.113.3:healthy" "LA:198.51.100.2:idle" "DC:192.0.2.2:failing" 'TIER2_THRESHOLD=5'
#   setup_vpn_multi_location_fixture "LOC1:${TEST_PEER_IP}:healthy" "LOC2:192.168.1.2:failing" "SYSTEM_WIDE_FAILURE_STATE=1"
#
setup_vpn_multi_location_fixture() {
	# Split args into location specs (NAME:IP:STATE) and extra_config (KEY=VALUE or special keys)
	local specs=()
	local extra_config=()
	local n_specs=0
	while [[ $# -gt 0 ]]; do
		local arg="$1"
		shift
		# Location spec: exactly two colons, last segment is healthy|failing|idle
		if [[ "$arg" == *:*:* ]]; then
			local state="${arg##*:}"
			if [[ "$state" == "healthy" ]] || [[ "$state" == "failing" ]] || [[ "$state" == "idle" ]]; then
				if [[ $n_specs -lt 3 ]]; then
					specs+=("$arg")
					((n_specs++)) || true
				fi
				continue
			fi
			# Looks like a spec but invalid state
			echo "Error: setup_vpn_multi_location_fixture: invalid state in spec '$arg' (expected healthy|failing|idle)." >&2
			return 1
		fi
		# Otherwise treat as extra config
		extra_config+=("$arg")
	done
	# Default specs if none provided
	if [[ ${#specs[@]} -eq 0 ]]; then
		specs=("LOC1:${TEST_PEER_IP}:healthy" "LOC2:192.168.1.2:failing")
	fi

	local vpn_monitor_script="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

	setup_test_environment "${TEST_DIR}"

	# Build location config vars from specs
	local location_configs=()
	local locations=("${specs[@]}") # NAME:IP:STATE for later
	for spec in "${specs[@]}"; do
		[[ -z "$spec" ]] && continue
		local name ip state
		name="${spec%%:*}"
		local rest="${spec#*:}"
		ip="${rest%%:*}"
		state="${rest##*:}"
		[[ -z "$name" ]] || [[ -z "$ip" ]] && continue
		location_configs+=("LOCATION_${name}_EXTERNAL=\"${ip}\"")
		location_configs+=("LOCATION_${name}_INTERNAL=\"${ip}\"")
	done

	# Filter extra_config: consume SYSTEM_WIDE_FAILURE_STATE and NETWORK_PARTITION_STATE
	local filtered_config=()
	local system_wide_val=""
	local network_partition_val=""
	for var in "${extra_config[@]}"; do
		if [[ "$var" =~ ^SYSTEM_WIDE_FAILURE_STATE=([01])$ ]]; then
			system_wide_val="${BASH_REMATCH[1]}"
		elif [[ "$var" =~ ^NETWORK_PARTITION_STATE=([01])$ ]]; then
			network_partition_val="${BASH_REMATCH[1]}"
		else
			filtered_config+=("$var")
		fi
	done

	TEST_CONFIG_FILE="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$TEST_CONFIG_FILE" \
		"${location_configs[@]}" \
		"${filtered_config[@]}"

	TEST_SCRIPT=$(create_test_vpn_monitor_script \
		"$vpn_monitor_script" \
		"${TEST_DIR}/vpn-monitor.sh" \
		"$TEST_CONFIG_FILE" \
		"$STATE_DIR" \
		"$LOG_FILE")
	export TEST_CONFIG_FILE TEST_SCRIPT

	# Write shared state files if requested
	if [[ -n "$system_wide_val" ]]; then
		local sw_file="${STATE_DIR}/system_wide_failure_state"
		mkdir -p "$(dirname "$sw_file")"
		echo "$system_wide_val" >"$sw_file"
	fi
	if [[ -n "$network_partition_val" ]]; then
		local np_file="${STATE_DIR}/network_partition_state"
		mkdir -p "$(dirname "$np_file")"
		echo "$network_partition_val" >"$np_file"
	fi

	# Per-location state and mock SA data
	ensure_state_functions_loaded
	local default_bytes=1000
	local default_spi="0x12345678"
	local mock_sa_lines=()

	for spec in "${locations[@]}"; do
		local name ip state
		name="${spec%%:*}"
		local rest="${spec#*:}"
		ip="${rest%%:*}"
		state="${rest##*:}"
		[[ -z "$name" ]] || [[ -z "$ip" ]] && continue

		case "$state" in
		healthy)
			set_peer_state "$name" "$ip" "last_bytes" "$((default_bytes - 100))" || true
			set_peer_state "$name" "$ip" "spi" "$default_spi" || true
			mock_sa_lines+=("$ip $((default_bytes)) $default_spi")
			;;
		failing)
			set_peer_state "$name" "$ip" "failure_count" "2" || true
			set_peer_state "$name" "$ip" "last_bytes" "$default_bytes" || true
			# No SA in mock for this IP
			;;
		idle)
			set_peer_state "$name" "$ip" "last_bytes" "$default_bytes" || true
			set_peer_state "$name" "$ip" "spi" "$default_spi" || true
			# SA with same bytes (no traffic)
			mock_sa_lines+=("$ip $default_bytes $default_spi")
			;;
		esac
	done

	# Build mock ip: return SAs only for healthy/idle (from mock_sa_lines)
	local mock_ip="${TEST_DIR}/ip"
	{
		cat <<'MOCKHEAD'
#!/bin/bash
if [[ "$1" == "-s" ]] && [[ "$2" == "xfrm" ]] && [[ "$3" == "state" ]]; then
MOCKHEAD
		for line in "${mock_sa_lines[@]}"; do
			local ip bytes spi
			read -r ip bytes spi <<<"$line" || true
			[[ -z "$ip" ]] && continue
			echo "    echo \"src $ip dst $ip\""
			echo "    echo \"    proto esp spi $spi reqid 1 mode tunnel\""
			echo "    echo \"    lifetime current: $bytes bytes, 10 packets\""
		done
		cat <<'MOCKTAIL'
    exit 0
elif [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
MOCKTAIL
		for line in "${mock_sa_lines[@]}"; do
			local ip bytes spi
			read -r ip bytes spi <<<"$line" || true
			[[ -z "$ip" ]] && continue
			echo "    echo \"src $ip dst $ip\""
			echo "    echo \"    proto esp spi $spi reqid 1 mode tunnel\""
			echo "    echo \"    lifetime current: $bytes bytes, 10 packets\""
		done
		cat <<'MOCKEND'
    exit 0
fi
exec /usr/bin/ip "$@"
MOCKEND
	} >"$mock_ip"
	chmod +x "$mock_ip"

	add_mock_to_path

	export MOCK_IP="$mock_ip"
	export VPN_MULTI_LOCATION_SPECS="${locations[*]:-}"
}
