#!/usr/bin/env bash
#
# Test fixture: VPN Flapping Scenario
#
# Sets up a test environment where the VPN can transition between up/down states
# during test execution. This fixture provides helper functions to switch states
# dynamically, making it ideal for testing VPN flapping scenarios.
#
# Arguments:
#   $1: Peer IP address (default: "${TEST_PEER_IP}")
#   $2: Initial state ("up" or "down", default: "up")
#   $3: Initial byte counter value (default: 1000, used when initial state is "up")
#   $4: Current byte counter value (default: 2000, used when initial state is "up")
#   $5: SPI value (default: 0x12345678) OR first config variable if it contains '='
#   $6+: Additional config variables as KEY="VALUE" pairs
#
# Note: If $5 contains '=', it is treated as a config variable and default SPI is used.
#
# Side effects:
#   - Sets up test VPN monitor environment
#   - Creates state files with initial state
#   - Creates mock VPN environment with initial state
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR variables
#   - Exports helper functions: switch_vpn_to_up(), switch_vpn_to_down()
#   - Exports VPN_FLAPPING_PEER_IP, VPN_FLAPPING_SPI for use by helper functions
#
# Example:
#   setup_vpn_flapping_fixture "${TEST_PEER_IP}" "up"
#   # VPN starts up, can switch to down with switch_vpn_to_down()
#
#   setup_vpn_flapping_fixture "${TEST_PEER_IP}" "down"
#   # VPN starts down, can switch to up with switch_vpn_to_up()
#
#   setup_vpn_flapping_fixture "${TEST_PEER_IP}" "up" 1000 2000 0x12345678 \
#       'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3'
#   # VPN starts up with custom bytes and SPI, config variables set
setup_vpn_flapping_fixture() {
	local peer_ip="${1:-${TEST_PEER_IP}}"
	local initial_state="${2:-up}"
	local initial_bytes="${3:-1000}"
	local current_bytes="${4:-2000}"

	# Check if position 5 is a config variable (contains '=') or an SPI value
	local spi
	local extra_config
	if [[ -n "${5:-}" ]] && [[ "$5" == *"="* ]]; then
		# Position 5 is a config variable, use default SPI
		spi="0x12345678"
		shift 4 || true
		extra_config=("$@")
	else
		# Position 5 is SPI value (or empty, use default)
		spi="${5:-0x12345678}"
		shift 5 || true
		extra_config=("$@")
	fi

	# Validate initial state
	if [[ "$initial_state" != "up" ]] && [[ "$initial_state" != "down" ]]; then
		echo "Error: initial_state must be 'up' or 'down', got: $initial_state" >&2
		return 1
	fi

	# Set up test VPN monitor with location-based config
	setup_location_vpn_monitor "$peer_ip" "${TEST_DIR}" "${extra_config[@]}"

	# Store peer IP and SPI for helper functions
	export VPN_FLAPPING_PEER_IP="$peer_ip"
	export VPN_FLAPPING_SPI="$spi"
	export VPN_FLAPPING_INITIAL_BYTES="$initial_bytes"
	export VPN_FLAPPING_CURRENT_BYTES="$current_bytes"

	# Set up state files based on initial state using location-based state functions
	# setup_location_vpn_monitor creates location "TEST"
	ensure_state_functions_loaded

	if [[ "$initial_state" == "up" ]]; then
		# VPN is up - set initial byte counter
		set_peer_state "TEST" "$peer_ip" "last_bytes" "$initial_bytes" || true
		if [[ -n "$spi" ]]; then
			set_peer_state "TEST" "$peer_ip" "spi" "$spi" || true
		fi

		# Set up mock VPN environment with current byte counter (VPN active)
		setup_mock_vpn_environment "$peer_ip" "$current_bytes" "$spi"
	else
		# VPN is down - no state files needed initially (will be created on first failure)
		# Create mock ip command that returns empty output (VPN down, no SA)
		mock_ip_vpn_down >/dev/null
		add_mock_to_path
		export MOCK_IP="${TEST_DIR}/ip"
	fi

	# Define helper functions to switch VPN states
	# These functions are available in the test scope after calling setup_vpn_flapping_fixture

	# Switch VPN to up state
	# Arguments:
	#   $1: Optional byte counter value (default: uses VPN_FLAPPING_CURRENT_BYTES)
	#   $2: Optional SPI value (default: uses VPN_FLAPPING_SPI)
	switch_vpn_to_up() {
		local bytes="${1:-${VPN_FLAPPING_CURRENT_BYTES}}"
		local spi_value="${2:-${VPN_FLAPPING_SPI}}"
		local peer_ip_value="${VPN_FLAPPING_PEER_IP}"

		# Update mock ip command to return SA (VPN up)
		mock_ip_xfrm_state "$peer_ip_value" "$bytes" "$spi_value" >/dev/null
		# Ensure mock is in PATH
		add_mock_to_path
		export MOCK_IP="${TEST_DIR}/ip"
	}

	# Switch VPN to down state
	switch_vpn_to_down() {
		# Update mock ip command to return empty output (VPN down)
		mock_ip_vpn_down >/dev/null
		# Ensure mock is in PATH
		add_mock_to_path
		export MOCK_IP="${TEST_DIR}/ip"
	}

	# Export helper functions so they're available in test scope
	export -f switch_vpn_to_up
	export -f switch_vpn_to_down
}
