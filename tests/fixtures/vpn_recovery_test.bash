#!/usr/bin/env bash
#
# Test fixture: VPN Recovery Test Setup
#
# Sets up a test environment for recovery tests with pass-through mocks.
# This fixture is designed for recovery strategy selection and recovery mechanism tests
# that need ip/ipsec commands to pass through to real commands.
#
# Arguments:
#   $1: Peer IP address (default: "${TEST_PEER_IP}")
#   $2+: Additional config variables as KEY="VALUE" pairs
#
# Side effects:
#   - Sets up test VPN monitor environment with ENABLE_XFRM_RECOVERY=1 by default
#   - Creates pass-through mocks for ip and ipsec commands
#   - Adds mocks to PATH
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR variables
#
# Example:
#   setup_vpn_recovery_test_fixture "${TEST_PEER_IP}"
#   # Recovery test setup with pass-through mocks
#
#   setup_vpn_recovery_test_fixture "${TEST_PEER_IP}" 'ENABLE_XFRM_RECOVERY=1' 'TIER1_THRESHOLD=1'
#   # Recovery test setup with custom config
setup_vpn_recovery_test_fixture() {
	local peer_ip="${1:-${TEST_PEER_IP}}"
	shift 1 || true
	local extra_config=("$@")

	# Check if ENABLE_XFRM_RECOVERY is already provided in extra_config
	local has_xfrm_recovery=0
	for config_var in "${extra_config[@]}"; do
		if [[ "$config_var" =~ ^ENABLE_XFRM_RECOVERY= ]]; then
			has_xfrm_recovery=1
			break
		fi
	done

	# Only set ENABLE_XFRM_RECOVERY=1 if not already provided
	local config_args=("${extra_config[@]}")
	if [[ $has_xfrm_recovery -eq 0 ]]; then
		config_args=("ENABLE_XFRM_RECOVERY=1" "${config_args[@]}")
	fi

	# Set up test VPN monitor with location-based config
	setup_location_vpn_monitor "$peer_ip" "${TEST_DIR}" "${config_args[@]}"

	# Create pass-through mocks for recovery tests
	# These mocks allow real commands to be called, useful for recovery strategy selection
	mock_ip_pass_through >/dev/null
	mock_ipsec_pass_through >/dev/null

	# Add mocks to PATH
	add_mock_to_path

	export MOCK_IP="${TEST_DIR}/ip"
	export MOCK_IPSEC="${TEST_DIR}/ipsec"
}
