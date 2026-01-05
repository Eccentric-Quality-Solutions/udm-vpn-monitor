#!/usr/bin/env bash
#
# Test fixture: VPN Cooldown Scenario
#
# Sets up a test environment where the VPN is in a cooldown period.
# During cooldown, the monitor should not take action even if VPN fails.
#
# Arguments:
#   $1: Peer IP address (default: "${TEST_PEER_IP}")
#   $2: Failure count (default: 5, typically high enough to trigger cooldown)
#   $3: Cooldown duration in seconds (default: 900 = 15 minutes)
#   $4+: Additional config variables as KEY="VALUE" pairs
#
# Side effects:
#   - Sets up test VPN monitor environment
#   - Creates state files with failure count and cooldown timestamp
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR variables
#
# Example:
#   setup_vpn_cooldown_fixture "${TEST_PEER_IP}"
#   # VPN in cooldown for 15 minutes
#
#   setup_vpn_cooldown_fixture "${TEST_PEER_IP}" 5 3600
#   # VPN in cooldown for 1 hour
setup_vpn_cooldown_fixture() {
	local peer_ip="${1:-${TEST_PEER_IP}}"
	local failure_count="${2:-5}"
	local cooldown_duration="${3:-900}"
	shift 3 || true
	local extra_config=("$@")

	# Calculate cooldown until timestamp (current time + duration)
	local cooldown_until
	cooldown_until=$(($(date +%s) + cooldown_duration))

	# Set up test VPN monitor with config
	setup_test_vpn_monitor "$peer_ip" "${TEST_DIR}" "${extra_config[@]}"

	# Set up state files with failure count and cooldown timestamp using location-aware functions
	# setup_test_vpn_monitor creates location "TEST1" for single IP
	ensure_state_functions_loaded
	set_peer_state "TEST1" "$peer_ip" "failure_count" "$failure_count" || true

	# Set up cooldown file (system-wide, not per-peer)
	if [[ -n "$cooldown_until" ]] && [[ "$cooldown_until" != "0" ]]; then
		local cooldown_file="${STATE_DIR:-${TEST_DIR}}/cooldown_until"
		echo "$cooldown_until" >"$cooldown_file"
	fi
}
