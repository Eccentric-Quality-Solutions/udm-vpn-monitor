#!/usr/bin/env bash
#
# Test fixture: VPN Network Partition Scenario
#
# Sets up a test environment simulating network partition conditions.
# This fixture combines multiple setup steps for testing network partition detection.
#
# Arguments:
#   $1: Peer IP address (default: "${TEST_PEER_IP}")
#   $2: Partition type (default: "all")
#       - "no_default_route": No default route available
#       - "interfaces_down": Network interfaces are down
#       - "dns_failure": DNS resolution fails
#       - "all": All partition conditions combined
#   $3: Interface names as comma-separated string (default: "eth0,eth1", can be overridden via config)
#   $4+: Additional config variables as KEY="VALUE" pairs
#
# Side effects:
#   - Sets up test VPN monitor environment with ENABLE_NETWORK_PARTITION_CHECK=1
#   - Creates mock ip command that handles route and link checks based on partition type
#   - Creates mock dig and nslookup commands for DNS checks (if needed)
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR variables
#   - Adds mock commands to PATH
#
# Example:
#   # Test with all partition conditions
#   setup_vpn_network_partition_fixture "${TEST_PEER_IP}" "all"
#
#   # Test with only DNS failure
#   setup_vpn_network_partition_fixture "192.168.1.1" "dns_failure"
#
#   # Test with custom interfaces
#   setup_vpn_network_partition_fixture "192.168.1.1" "no_default_route" "br0,eth0"
setup_vpn_network_partition_fixture() {
	local peer_ip="${1:-${TEST_PEER_IP}}"
	local partition_type="${2:-all}"
	local interface_names="${3:-eth0,eth1}"
	shift 3 || true
	local extra_config=("$@")

	# Set up test VPN monitor with network partition check enabled
	local default_config=('ENABLE_NETWORK_PARTITION_CHECK=1')
	setup_test_vpn_monitor "$peer_ip" "${TEST_DIR}" "${default_config[@]}" "${extra_config[@]}"

	# Extract interface names from config if NETWORK_PARTITION_INTERFACES is set
	# This allows tests to override via config variable
	if [[ -n "${NETWORK_PARTITION_INTERFACES:-}" ]]; then
		interface_names="${NETWORK_PARTITION_INTERFACES}"
	fi

	# Configure mock parameters based on partition type
	local route_exists="1"
	local route_output="default via ${TEST_PEER_IP} dev eth0"
	# Determine interface states based on partition type and number of interfaces
	# Convert interface names to states array (default: all UP)
	local IFS=','
	local -a interface_array
	read -ra interface_array <<<"$interface_names"
	local interface_states=""
	for _ in "${interface_array[@]}"; do
		interface_states="${interface_states}UP,"
	done
	interface_states="${interface_states%,}" # Remove trailing comma
	local create_dns_mocks=false

	case "$partition_type" in
	"no_default_route")
		route_exists="0"
		route_output=""
		# Keep interfaces UP (default)
		;;
	"interfaces_down")
		# Change all interfaces to DOWN
		interface_states=""
		for _ in "${interface_array[@]}"; do
			interface_states="${interface_states}DOWN,"
		done
		interface_states="${interface_states%,}" # Remove trailing comma
		;;
	"dns_failure")
		create_dns_mocks=true
		# Keep interfaces UP (default)
		;;
	"all")
		route_exists="0"
		route_output=""
		# Change all interfaces to DOWN
		interface_states=""
		for _ in "${interface_array[@]}"; do
			interface_states="${interface_states}DOWN,"
		done
		interface_states="${interface_states%,}" # Remove trailing comma
		create_dns_mocks=true
		;;
	*)
		echo "Warning: Unknown partition type '$partition_type', using 'all'" >&2
		route_exists="0"
		route_output=""
		# Change all interfaces to DOWN
		interface_states=""
		for _ in "${interface_array[@]}"; do
			interface_states="${interface_states}DOWN,"
		done
		interface_states="${interface_states%,}" # Remove trailing comma
		create_dns_mocks=true
		;;
	esac

	# Create combined mock ip command that handles route, link, and xfrm checks
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
# Combined mock ip command for network partition testing
# Handles "ip route show default", "ip link show", and "ip xfrm state" commands

# Handle route checks
if [[ "\$1" == "route" ]] && [[ "\$2" == "show" ]] && [[ "\$3" == "default" ]]; then
    if [[ "$route_exists" == "0" ]]; then
        exit 1  # No default route
    else
        echo "$route_output"
        exit 0
    fi
fi

# Handle link checks
if [[ "\$1" == "link" ]] && [[ "\$2" == "show" ]]; then
    # Parse states and interfaces
    IFS=',' read -r -a state_array <<< "$interface_states"
    IFS=',' read -r -a iface_array <<< "$interface_names"
    
    # If specific interface queried
    if [[ -n "\${3:-}" ]]; then
        for i in "\${!iface_array[@]}"; do
            if [[ "\${iface_array[\$i]}" == "\$3" ]]; then
                local state="\${state_array[\$i]:-UP}"
                echo "\${i}: \$3: <BROADCAST,MULTICAST,\${state},LOWER_UP> mtu 1500"
                exit 0
            fi
        done
        exit 1  # Interface not found
    fi
    
    # Show all interfaces
    for i in "\${!iface_array[@]}"; do
        local iface="\${iface_array[\$i]}"
        local state="\${state_array[\$i]:-UP}"
        echo "\${i}: \${iface}: <BROADCAST,MULTICAST,\${state},LOWER_UP> mtu 1500"
    done
    exit 0
fi

# Handle xfrm state checks - fall back to real command (tests can override if needed)
# This allows tests to combine VPN down scenarios with partition scenarios
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    exec /usr/bin/ip "\$@"
fi

# Handle other ip commands
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"

	# Create DNS mocks if needed
	if [[ "$create_dns_mocks" == "true" ]]; then
		# Create mock dig command - DNS timeout
		mock_dig "0" "" "timeout" >/dev/null
		# Create mock nslookup command - always fails
		mock_nslookup_fail >/dev/null
	fi

	# Add mocks to PATH
	add_mock_to_path

	export MOCK_IP="$mock_ip"
}
