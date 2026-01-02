#!/usr/bin/env bash
#
# Test fixture: VPN Rate Limited Scenario
#
# Sets up a test environment where rate limiting is active.
# This fixture sets up the restart_count file with recent restart timestamps
# and configures the environment to trigger Tier 3 recovery (which is rate limited).
#
# Arguments:
#   $1: Peer IP address (default: "192.168.1.1")
#   $2: Number of restart timestamps to create if none provided (default: 3)
#   $3+: Restart timestamps (epoch seconds, one per line in restart_count file)
#        If not provided, creates timestamps relative to current time
#   Additional config variables as KEY="VALUE" pairs can be passed after timestamps
#
# Side effects:
#   - Sets up test VPN monitor environment
#   - Creates restart_count file with restart timestamps
#   - Sets up state files with failure count to trigger Tier 3
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR variables
#
# Example:
#   # Use default: 3 restarts within last hour
#   setup_vpn_rate_limited_fixture "192.168.1.1"
#
#   # Provide specific timestamps
#   local now=$(date +%s)
#   setup_vpn_rate_limited_fixture "192.168.1.1" 3 \
#       $((now - 100)) \
#       $((now - 200)) \
#       $((now - 300))
#
#   # Custom config
#   setup_vpn_rate_limited_fixture "192.168.1.1" 3 \
#       $((now - 100)) \
#       $((now - 200)) \
#       $((now - 300)) \
#       'MAX_RESTARTS_PER_HOUR=5'
setup_vpn_rate_limited_fixture() {
	local peer_ip="${1:-192.168.1.1}"
	local restart_count="${2:-3}"
	shift 2 || true

	# Collect timestamps and extra config
	local timestamps=()
	local extra_config=()
	local collecting_timestamps=true

	for arg in "$@"; do
		if [[ "$collecting_timestamps" == "true" ]] && [[ "$arg" =~ ^[0-9]+$ ]]; then
			# Numeric argument - treat as timestamp
			timestamps+=("$arg")
		else
			# Non-numeric or first non-numeric - treat as config
			collecting_timestamps=false
			extra_config+=("$arg")
		fi
	done

	# If no timestamps provided, generate them relative to current time
	if [[ ${#timestamps[@]} -eq 0 ]]; then
		local now
		now=$(date +%s)
		# Create timestamps within last hour (spaced evenly)
		local interval=$((3600 / restart_count))
		for ((i = 0; i < restart_count; i++)); do
			timestamps+=($((now - (i * interval))))
		done
	fi

	# Set up test VPN monitor with default rate limit config
	# Allow override via extra_config
	local default_config=(
		'MAX_RESTARTS_PER_HOUR=3'
		'TIER3_THRESHOLD=5'
	)
	setup_test_vpn_monitor "$peer_ip" "${TEST_DIR}" "${default_config[@]}" "${extra_config[@]}"

	# Create restart count file with timestamps
	local restart_file="${STATE_DIR}/restart_count"
	# Clear file if it exists
	: >"$restart_file"
	for ts in "${timestamps[@]}"; do
		echo "$ts" >>"$restart_file"
	done

	# Set failure count to trigger Tier 3 (default is 5, matching TIER3_THRESHOLD) using location-aware functions
	ensure_state_functions_loaded
	# setup_test_vpn_monitor creates location "TEST1" for single IP
	set_peer_state "TEST1" "$peer_ip" "failure_count" "5" || true
}
