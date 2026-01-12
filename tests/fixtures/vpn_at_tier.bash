#!/usr/bin/env bash
#
# Test fixture: VPN at Specific Tier Threshold
#
# Sets up a test environment where the VPN has reached a specific tier threshold.
# This fixture simplifies setting up tier-specific test scenarios by automatically
# configuring the failure count and tier thresholds.
#
# Arguments:
#   $1: Tier number (1, 2, or 3) (default: 1)
#   $2: Peer IP address (default: "${TEST_PEER_IP}")
#   $3+: Additional config variables as KEY="VALUE" pairs
#
# Side effects:
#   - Sets up test VPN monitor environment
#   - Creates state files with failure count matching tier threshold
#   - Creates mock VPN environment (VPN down by default)
#   - Sets tier thresholds in config
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR variables
#
# Example:
#   setup_vpn_at_tier_fixture 1 "${TEST_PEER_IP}"
#   # VPN at Tier 1 threshold (failure_count=1, TIER1_THRESHOLD=1)
#
#   setup_vpn_at_tier_fixture 2 "192.168.1.1" 'ENABLE_XFRM_RECOVERY=0'
#   # VPN at Tier 2 threshold (failure_count=3, TIER2_THRESHOLD=3)
setup_vpn_at_tier_fixture() {
	local tier="${1:-1}"
	local peer_ip="${2:-${TEST_PEER_IP}}"
	shift 2 || true
	local extra_config=("$@")

	# Map tier number to failure count and threshold
	local failure_count
	local tier_threshold_config
	case "$tier" in
	1)
		failure_count=1
		tier_threshold_config=('TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5')
		;;
	2)
		failure_count=3
		tier_threshold_config=('TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5')
		;;
	3)
		failure_count=5
		tier_threshold_config=('TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5')
		;;
	*)
		echo "Error: Invalid tier number: $tier. Must be 1, 2, or 3." >&2
		return 1
		;;
	esac

	# Combine tier thresholds with extra config
	local all_config=("${tier_threshold_config[@]}" "${extra_config[@]}")

	# Set up test VPN monitor with location-based config
	setup_location_vpn_monitor "$peer_ip" "${TEST_DIR}" "${all_config[@]}"

	# Set up state files with failure count matching tier threshold
	# setup_location_vpn_monitor creates location "TEST"
	ensure_state_functions_loaded
	set_peer_state "TEST" "$peer_ip" "failure_count" "$failure_count" || true

	# Create mock ip command that returns empty output (VPN down, no SA)
	mock_ip_vpn_down >/dev/null

	# Add mocks to PATH
	add_mock_to_path

	export MOCK_IP="${TEST_DIR}/ip"
}
