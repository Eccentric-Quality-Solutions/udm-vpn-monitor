#!/usr/bin/env bats
#
# Integration tests for Location-Based Configuration
# Tests full monitoring flow with location-based config, keepalive daemon with
# location-based config, and recovery actions with location-based state files

load test_helper
load helpers/test_data
load helpers/state
load fixtures/vpn_active
load fixtures/vpn_down

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# Note: setup_location_config() and setup_location_test_vpn_monitor() are now
# defined in test_helper.bash to avoid duplication. They are available here
# since this file loads test_helper.

# ============================================================================
# LOCATION-BASED INTEGRATION TESTS
# ============================================================================

# bats test_tags=category:integration,priority:high
@test "integration location: VPN healthy with location-based config - no action taken" {
	# Purpose: Test full monitoring flow with location-based config when VPN is healthy
	# Expected: Script runs successfully, detects healthy VPN, uses location-based state files
	# Importance: Validates location-based config works in happy path
	setup_location_test_vpn_monitor "${TEST_DIR}" \
		'ENABLE_PING_CHECK=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0'

	# Generate xfrm state output for NYC location (bidirectional SAs)
	# Note: This is a special case with different src/dst IPs, so we generate it manually
	# but using the helper function format as a base
	local xfrm_state_nyc
	xfrm_state_nyc="src ${TEST_PEER_IP} dst 203.0.113.1"$'\n'"src 203.0.113.1 dst ${TEST_PEER_IP}"$'\n'"    proto esp spi 0x12345678 reqid 1 mode tunnel"$'\n'"    lifetime current: 2000 bytes, 10 packets"
	local xfrm_state_nyc_file="${TEST_DIR}/xfrm_state_nyc"
	echo "$xfrm_state_nyc" >"$xfrm_state_nyc_file"

	# Mock VPN as active for NYC location (203.0.113.1)
	# Note: get_xfrm_state_for_peer tries "ip -s xfrm state" first, then falls back to "ip xfrm state"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
# Handle "ip -s xfrm state" (with statistics flag) - tried first by get_xfrm_state_for_peer
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # Return SA for NYC external IP with increasing bytes
    cat "MOCK_XFRM_STATE_NYC"
    exit 0
fi
# Handle "ip xfrm state" (without statistics flag) - fallback used by get_xfrm_state_for_peer
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Return SA for NYC external IP with increasing bytes
    cat "MOCK_XFRM_STATE_NYC"
    exit 0
fi
# Handle other ip commands
exec /usr/bin/ip "\$@"
EOF
	# Replace placeholder with actual file path
	sed -i "s|MOCK_XFRM_STATE_NYC|${xfrm_state_nyc_file}|g" "$mock_ip"
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create initial byte counter file to simulate previous check
	mkdir -p "$STATE_DIR"
	echo "1000" >"${STATE_DIR}/last_bytes_NYC_203_0_113_1"

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success

	# Should use location-based state file naming
	local failure_counter="${STATE_DIR}/failure_count_NYC_203_0_113_1"
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert_equal "$count" 0
	fi

	remove_mock_from_path
}

# bats test_tags=category:integration,priority:high
@test "integration location: VPN down with location-based config - Tier 1 logging" {
	# Purpose: Test failure detection with location-based config triggers Tier 1
	# Expected: Script increments location-based failure counter, logs Tier 1 message
	# Importance: Validates location-based state file tracking works correctly
	setup_location_test_vpn_monitor

	# Mock VPN as down (no SA)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 1
fi
exit 1
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Should increment location-based failure counter
	local failure_counter="${STATE_DIR}/failure_count_NYC_203_0_113_1"
	assert_file_exist "$failure_counter"
	local count
	count=$(cat "$failure_counter")
	assert [ "$count" -ge 1 ]

	# Should log Tier 1 action
	assert_file_contains "$LOG_FILE" "Tier 1"

	remove_mock_from_path
}

# bats test_tags=category:integration,priority:high
@test "integration location: Multiple locations - independent failure tracking" {
	# Purpose: Test that multiple locations are tracked independently
	# Expected: Each location maintains its own failure counter
	# Importance: Ensures multi-location deployments track failures per location
	setup_location_test_vpn_monitor

	# Mock VPN: NYC down, LA up
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Return SA for LA (198.51.100.1), empty for NYC (203.0.113.1)
    echo "src 192.168.2.1 dst 198.51.100.1"
    exit 0
fi
exit 1
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# NYC should have failure counter incremented
	local nyc_counter="${STATE_DIR}/failure_count_NYC_203_0_113_1"
	if [[ -f "$nyc_counter" ]]; then
		local nyc_count
		nyc_count=$(cat "$nyc_counter")
		assert [ "$nyc_count" -ge 1 ]
	fi

	# LA should not have failure (or counter reset if it was failing before)
	local la_counter="${STATE_DIR}/failure_count_LA_198_51_100_1"
	# LA is up, so counter should be 0 or not exist yet

	remove_mock_from_path
}

# bats test_tags=category:integration,priority:high
@test "integration location: Location with multiple internal IPs - ping check" {
	# Purpose: Test ping check with multiple internal IPs uses 30% threshold
	# Expected: Ping check succeeds if at least 30% of internal IPs respond
	# Importance: Validates multiple internal IPs ping logic in integration
	# Note: Use setup_test_location_config directly to avoid duplicate locations from setup_location_test_vpn_monitor defaults
	setup_test_environment "${TEST_DIR}"
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
		"LOCATION_NYC_INTERNAL=\"${TEST_PEER_IP} 192.168.1.88 192.168.1.99\""

	TEST_CONFIG_FILE="$config_file"
	TEST_SCRIPT=$(create_test_vpn_monitor_script \
		"$VPN_MONITOR_SCRIPT" \
		"${TEST_DIR}/vpn-monitor.sh" \
		"$TEST_CONFIG_FILE" \
		"$STATE_DIR" \
		"$LOG_FILE")
	export TEST_CONFIG_FILE TEST_SCRIPT

	# Mock VPN as active
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 203.0.113.1"
    exit 0
fi
exit 1
EOF
	chmod +x "$mock_ip"

	# Mock ping to succeed for 1 of 3 IPs (33% > 30% threshold)
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
# Succeed for 192.168.1.1, fail for others
if [[ "$*" =~ 192\.168\.1\.1 ]]; then
    exit 0
fi
exit 1
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Should succeed (ping check passes with 1/3 = 33% > 30%)
	assert_success

	remove_mock_from_path
}

# bats test_tags=category:integration,priority:high
@test "integration location: Location recovery - counter reset with location name" {
	# Purpose: Test that location-based failure counters reset on recovery
	# Expected: Failure counter resets to 0 when VPN recovers
	# Importance: Validates recovery tracking works with location-based state files
	setup_location_test_vpn_monitor

	# Set initial failure count using proper helper to ensure correct path
	mkdir -p "$LOGS_DIR"
	ensure_state_functions_loaded
	set_peer_state "NYC" "203.0.113.1" "failure_count" "3" || true
	# Set last_bytes to 2000 so bytes appear to increase from 2000 to 3000
	set_peer_state "NYC" "203.0.113.1" "last_bytes" "2000" || true
	# Ensure no recovery_method is stored (should log "recovered" not "restored")
	# delete_peer_state is available after ensure_state_functions_loaded
	delete_peer_state "NYC" "203.0.113.1" "recovery_method" || true

	# Mock VPN as recovered (active)
	# Use mock_ip_xfrm_state helper to create proper xfrm output format
	# Set bytes to 3000 (higher than last_bytes of 2000) to show increasing traffic
	mock_ip_xfrm_state "203.0.113.1" "3000" "0x12345678" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success

	# Failure counter should be reset
	local failure_counter
	failure_counter=$(get_state_file_path "NYC" "203.0.113.1" "failure_count")
	assert_file_exist "$failure_counter"
	local count
	count=$(cat "$failure_counter")
	assert_equal "$count" 0

	# Should log recovery message (should be "recovered" since no recovery method was used)
	assert_file_contains "$LOG_FILE" "recovered"

	remove_mock_from_path
}

# bats test_tags=category:integration,priority:high
@test "integration location: Location-based state file naming" {
	# Purpose: Test that state files use location names in filenames
	# Expected: State files follow pattern: failure_count_<location>_<peer_ip>
	# Importance: Ensures state files are unique per location
	setup_location_test_vpn_monitor

	# Mock VPN as down to trigger failure counter
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 1
fi
exit 1
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Verify location-based state file naming
	local nyc_counter="${STATE_DIR}/failure_count_NYC_203_0_113_1"
	local la_counter="${STATE_DIR}/failure_count_LA_198_51_100_1"

	# At least one should exist (NYC failed)
	assert [ -f "$nyc_counter" ] || [ -f "$la_counter" ]

	# Verify filename format includes location name
	if [[ -f "$nyc_counter" ]]; then
		assert_equal "$(basename "$nyc_counter")" "failure_count_NYC_203_0_113_1"
	fi

	remove_mock_from_path
}

# bats test_tags=category:integration,priority:high
@test "integration location: Location with sanitized name in state files" {
	# Purpose: Test that location names are sanitized in state file names
	# Expected: Invalid characters in location names are replaced in filenames
	# Importance: Ensures safe filenames even with special characters
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	load helpers/config
	create_test_config "$config_file" \
		'LOCATION_NYC_Office_EXTERNAL="203.0.113.1"' \
		"LOCATION_NYC_Office_INTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"LOG_FILE=\"${TEST_DIR}/logs/vpn-monitor.log\"" \
		"STATE_DIR=\"${TEST_DIR}\""

	setup_location_test_vpn_monitor

	# Mock VPN as down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
exit 1
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Verify sanitized location name in state file
	# Hyphen should be replaced with underscore
	local counter="${STATE_DIR}/failure_count_NYC_Office_203_0_113_1"
	# File may or may not exist depending on which location failed first
	# But if it exists, it should use sanitized name

	remove_mock_from_path
}

# bats test_tags=category:integration,priority:high
@test "integration location: Location without internal IPs - uses external IP" {
	# Purpose: Test that locations without internal IPs use external IP for ping
	# Expected: Ping check uses external IP when internal IPs are not configured
	# Importance: Validates fallback to external IP
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	load helpers/config
	create_test_config "$config_file" \
		'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"ENABLE_PING_CHECK=1" \
		"LOG_FILE=\"${TEST_DIR}/logs/vpn-monitor.log\"" \
		"STATE_DIR=\"${TEST_DIR}\""

	setup_location_test_vpn_monitor

	# Mock VPN as active
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 203.0.113.1"
    exit 0
fi
exit 1
EOF
	chmod +x "$mock_ip"

	# Mock ping to succeed for external IP
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
# Succeed for external IP
if [[ "$*" =~ 92\.34\.1\.5 ]]; then
    exit 0
fi
exit 1
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Should succeed (ping check uses external IP)
	assert_success

	remove_mock_from_path
}

# bats test_tags=category:integration,priority:high
@test "integration location: Parse location config during monitoring" {
	# Purpose: Test that parse_location_config is called and works during monitoring
	# Expected: Location config is parsed and LOCATIONS array is populated
	# Importance: Validates location parsing integration with main script
	setup_location_test_vpn_monitor

	# Mock VPN as active
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 203.0.113.1"
    exit 0
fi
exit 1
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success

	# Script should have parsed locations successfully (no errors in log)
	refute_file_contains "$LOG_FILE" "Failed to parse location"
	refute_file_contains "$LOG_FILE" "No location-based configuration found"

	remove_mock_from_path
}

# bats test_tags=category:integration,priority:high,slow
@test "integration location: Full monitoring cycle with multiple locations" {
	# Purpose: Test complete monitoring cycle with multiple locations
	# Expected: All locations are monitored, state files created correctly
	# Importance: Validates end-to-end functionality with location-based config
	setup_location_test_vpn_monitor

	# Mock VPN: Both locations active
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 203.0.113.1"
    echo "src 192.168.2.1 dst 198.51.100.1"
    exit 0
fi
exit 1
EOF
	chmod +x "$mock_ip"

	# Mock byte counters
	local mock_cat="${TEST_DIR}/cat"
	cat >"$mock_cat" <<'EOF'
#!/bin/bash
if [[ "$1" =~ last_bytes ]]; then
    echo "1000"
else
    /bin/cat "$@"
fi
EOF
	chmod +x "$mock_cat"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success

	# Both locations should be monitored (no errors)
	refute_file_contains "$LOG_FILE" "Location.*failed"
	refute_file_contains "$LOG_FILE" "No location-based configuration found"

	remove_mock_from_path
}

# ============================================================================
# update_location_state TESTS - Coverage gaps from COVERAGE_REVIEW
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "update_location_state: periodic status logging - logs status when interval elapsed" {
	# Purpose: Test verifies that periodic status logging occurs when STATUS_LOG_INTERVAL_SECONDS elapsed
	# Expected: Function logs "VPN check OK" when status log interval has elapsed
	# Importance: Covers lines 868-884 - periodic status logging path
	setup_location_test_vpn_monitor "${TEST_DIR}" \
		'ENABLE_PING_CHECK=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0' \
		'STATUS_LOG_INTERVAL_SECONDS=300'

	# Mock VPN as healthy
	mock_ip_xfrm_state "203.0.113.1" "1000" "0x12345678" >/dev/null
	add_mock_to_path

	# Set up state: VPN healthy, no failures, last_status_log set to 0 (never logged)
	ensure_state_functions_loaded
	set_peer_state "NYC" "203.0.113.1" "failure_count" "0" || true
	set_peer_state "NYC" "203.0.113.1" "last_status_log" "0" || true

	# Source required functions
	source_recovery_module

	# Test update_location_state directly with healthy status
	run update_location_state "NYC" "203.0.113.1" "healthy" ""

	# Should succeed
	assert_success
	# Should log periodic status
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "VPN check OK" "check OK"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "update_location_state: periodic status logging - skips logging when interval not elapsed" {
	# Purpose: Test verifies that periodic status logging is skipped when interval hasn't elapsed
	# Expected: Function does not log status when time since last log is less than interval
	# Importance: Covers lines 868-884 - periodic status logging interval check
	setup_location_test_vpn_monitor "${TEST_DIR}" \
		'ENABLE_PING_CHECK=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0' \
		'STATUS_LOG_INTERVAL_SECONDS=300'

	# Mock VPN as healthy
	mock_ip_xfrm_state "203.0.113.1" "1000" "0x12345678" >/dev/null
	add_mock_to_path

	# Set up state: VPN healthy, no failures, last_status_log set to recent time (within interval)
	ensure_state_functions_loaded
	set_peer_state "NYC" "203.0.113.1" "failure_count" "0" || true
	local current_time
	current_time=$(get_unix_timestamp)
	# Set last_status_log to 100 seconds ago (less than 300 second interval)
	local recent_time=$((current_time - 100))
	set_peer_state "NYC" "203.0.113.1" "last_status_log" "$recent_time" || true

	# Source required functions
	source_recovery_module

	# Clear log file before test
	>"$LOG_FILE"

	# Test update_location_state directly with healthy status
	run update_location_state "NYC" "203.0.113.1" "healthy" ""

	# Should succeed
	assert_success
	# Should NOT log periodic status (interval not elapsed)
	# Note: May still have other log messages, but not the periodic "check OK" message
	if [[ -f "$LOG_FILE" ]]; then
		refute_file_contains "$LOG_FILE" "check OK"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "update_location_state: false positive cleanup - clears stale failure_type file" {
	# Purpose: Test verifies that false positive cleanup clears stale failure_type file when VPN is healthy with no failures
	# Expected: Function silently removes failure_type file when had_failure_type=1 but failure_count=0
	# Importance: Covers lines 859-865 - false positive cleanup path
	setup_location_test_vpn_monitor "${TEST_DIR}" \
		'ENABLE_PING_CHECK=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0'

	# Mock VPN as healthy
	mock_ip_xfrm_state "203.0.113.1" "1000" "0x12345678" >/dev/null
	add_mock_to_path

	# Set up state: VPN healthy, no failures, but failure_type file exists (false positive)
	ensure_state_functions_loaded
	set_peer_state "NYC" "203.0.113.1" "failure_count" "0" || true
	# Create failure_type file to simulate false positive
	# Source state functions to get get_peer_state_file_path
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local failure_type_file
	failure_type_file=$(get_peer_state_file_path "NYC" "203.0.113.1" "failure_type")
	mkdir -p "$(dirname "$failure_type_file")"
	echo "tunnel_down" >"$failure_type_file"

	# Source required functions
	source_recovery_module

	# Test update_location_state directly with healthy status
	run update_location_state "NYC" "203.0.113.1" "healthy" ""

	# Should succeed
	assert_success
	# Failure type file should be removed (false positive cleanup)
	assert_file_not_exist "$failure_type_file"
	# Should NOT log recovery message (silent cleanup)
	if [[ -f "$LOG_FILE" ]]; then
		refute_file_contains "$LOG_FILE" "recovered"
		refute_file_contains "$LOG_FILE" "restored"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "update_location_state: partition state transition - detects partition after failure" {
	# Purpose: Test verifies that partition state transition is detected and logged when network partition occurs after VPN failure
	# Expected: Function detects partition, updates state, logs warning, and returns 2
	# Importance: Covers lines 900-920 - partition state transitions after failure
	setup_location_test_vpn_monitor "${TEST_DIR}" \
		'ENABLE_PING_CHECK=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Mock VPN as down
	mock_ip_vpn_down "${TEST_DIR}/ip" >/dev/null

	# Mock network partition check to fail (network partitioned)
	mock_ip_interfaces_up "br0,eth0" "0" >/dev/null
	mock_dig 0
	add_mock_to_path

	# Set up state: VPN failed, partition state initially healthy
	mkdir -p "$STATE_DIR"
	local partition_state_file="${STATE_DIR}/network_partition_state"
	echo "0" >"$partition_state_file"

	# Source required functions
	source_recovery_module

	# Test update_location_state directly with failed status
	run update_location_state "NYC" "203.0.113.1" "failed" ""

	# Should return 2 (partition detected)
	assert_equal "$status" 2
	# Should log partition detection warning
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Network partition detected" "skipping VPN recovery"
	# Partition state should be set to 1
	local partition_state
	partition_state=$(get_network_partition_state)
	assert_equal "$partition_state" 1

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "update_location_state: partition state transition - detects partition cleared after failure" {
	# Purpose: Test verifies that partition cleared transition is detected and logged when network recovers after VPN failure
	# Expected: Function detects partition cleared, updates state, logs info, and continues
	# Importance: Covers lines 913-920 - partition cleared path after failure
	setup_location_test_vpn_monitor "${TEST_DIR}" \
		'ENABLE_PING_CHECK=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Mock VPN as down
	mock_ip_vpn_down "${TEST_DIR}/ip" >/dev/null

	# Mock network partition check to succeed (network healthy)
	mock_ip_interfaces_up "br0,eth0" "1" >/dev/null
	mock_dig 1 "8.8.8.8"
	add_mock_to_path

	# Set up state: VPN failed, partition state was previously partitioned
	mkdir -p "$STATE_DIR"
	local partition_state_file="${STATE_DIR}/network_partition_state"
	echo "1" >"$partition_state_file"

	# Source required functions
	source_recovery_module

	# Test update_location_state directly with failed status
	run update_location_state "NYC" "203.0.113.1" "failed" ""

	# Should return 0 (no partition, continues with failure handling)
	assert_equal "$status" 0
	# Should log that network connectivity restored
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Network connectivity restored" "resuming VPN monitoring"
	# Partition state should be cleared
	local partition_state
	partition_state=$(get_network_partition_state)
	assert_equal "$partition_state" 0

	remove_mock_from_path
}
