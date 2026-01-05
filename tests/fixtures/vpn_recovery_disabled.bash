#!/usr/bin/env bash
#
# Test fixture: VPN with Recovery Disabled
#
# Sets up a test environment where recovery actions are disabled.
# This fixture combines common setup steps for tests that need recovery disabled.
#
# Arguments:
#   $1: Peer IP address (default: "${TEST_PEER_IP}")
#   $2: Failure count (default: 0)
#   $3: Bytes value (default: 1000)
#   $4: SPI value (default: 0x12345678)
#   $5+: Additional config variables as KEY="VALUE" pairs
#
# Side effects:
#   - Sets up test VPN monitor environment with recovery disabled
#   - Creates state files
#   - Creates mock VPN environment
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR variables
#   - Sets ENABLE_XFRM_RECOVERY=0 and ENABLE_NETWORK_PARTITION_CHECK=0
#
# Example:
#   setup_vpn_recovery_disabled_fixture "${TEST_PEER_IP}"
#   # VPN with recovery disabled
#
#   setup_vpn_recovery_disabled_fixture "${TEST_PEER_IP}" 3 5000
#   # VPN with recovery disabled, 3 failures, 5000 bytes
setup_vpn_recovery_disabled_fixture() {
	local peer_ip="${1:-${TEST_PEER_IP}}"
	local failure_count="${2:-0}"
	local bytes="${3:-1000}"
	local spi="${4:-0x12345678}"
	shift 4 || true
	local extra_config=("$@")

	# Set up test VPN monitor with recovery disabled
	# Use setup_test_config_with_recovery_disabled pattern
	setup_test_vpn_monitor "$peer_ip" "${TEST_DIR}" \
		'ENABLE_XFRM_RECOVERY=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0' \
		"${extra_config[@]}"

	# Set up state files using location-aware functions
	# setup_test_vpn_monitor creates location "TEST1" for single IP
	ensure_state_functions_loaded
	set_peer_state "TEST1" "$peer_ip" "failure_count" "$failure_count" || true
	if [[ "$bytes" != "0" ]] || [[ "$failure_count" -gt 0 ]]; then
		set_peer_state "TEST1" "$peer_ip" "last_bytes" "$bytes" || true
	fi
	if [[ -n "$spi" ]]; then
		set_peer_state "TEST1" "$peer_ip" "spi" "$spi" || true
	fi

	# Set up mock VPN environment
	setup_mock_vpn_environment "$peer_ip" "$bytes" "$spi"
}
