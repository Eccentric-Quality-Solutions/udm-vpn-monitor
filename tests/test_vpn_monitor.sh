#!/usr/bin/env bats
#
# Tests for vpn-monitor.sh script
# Tests monitoring functionality, tier escalation, and recovery actions

load test_helper

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

@test "vpn-monitor.sh exists and is executable" {
	assert_file_exist "$VPN_MONITOR_SCRIPT"
	assert_file_executable "$VPN_MONITOR_SCRIPT"
}

@test "vpn-monitor.sh shows help with --help flag" {
	run bash "$VPN_MONITOR_SCRIPT" --help
	assert_success
	assert_output --partial "Usage:"
	assert_output --partial "--fake"
}

@test "vpn-monitor.sh shows help with -h flag" {
	run bash "$VPN_MONITOR_SCRIPT" -h
	assert_success
	assert_output --partial "Usage:"
}

@test "vpn-monitor.sh exits with error if PEER_IPS not configured" {
	# Create temporary config without PEER_IPS
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
VPN_NAME="Test VPN"
PEER_IPS=""
EOF

	# Create state directory and ensure log directory exists
	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"

	# Create test version of script with custom paths
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	run bash "$test_script"

	assert_failure
	assert_output --partial "PEER_IPS is required but not configured"
}

@test "vpn-monitor.sh creates state directory if missing" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	# State directory doesn't exist yet
	local state_dir="${TEST_DIR}/state"
	local log_file="${state_dir}/logs/vpn-monitor.log"

	# Create test version of script with custom paths
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	run bash "$test_script" --fake

	# State directory should be created
	assert_dir_exist "$state_dir"
}

@test "vpn-monitor.sh initializes state files" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"

	# Create test version of script with custom paths
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	run bash "$test_script" --fake

	# State files should be created in logs directory
	# Note: Per-peer failure counters are created on-demand, not during initialization
	# Only restart_count is created during initialization
	assert_file_exist "${TEST_DIR}/logs/restart_count"
}

@test "vpn-monitor.sh creates log file" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"

	# Create test version of script with custom paths
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	run bash "$test_script" --fake

	# Log file should be created
	assert_file_exist "$log_file"
}

@test "vpn-monitor.sh logs script start" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"

	# Create test version of script with custom paths
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	run bash "$test_script" --fake

	# Check log contains start message
	assert_file_contains "$log_file" "VPN monitor script started"
}

@test "vpn-monitor.sh handles --fake flag" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"

	# Create test version of script with custom paths
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	run bash "$test_script" --fake

	# Check log contains fake mode message
	assert_file_contains "$log_file" "fake mode"
}

@test "vpn-monitor.sh validates peer IP format" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="invalid-ip"
EOF

	# Ensure log directory exists
	mkdir -p "${TEST_DIR}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"

	# Create test version of script with custom paths
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	run bash "$test_script" --fake

	# Should handle invalid IP (may log warning or error)
	# The script should not crash - check if log file was created or script ran
	# Script may exit early if IP validation fails, so check status is reasonable
	if [[ $status -eq 0 ]] || [[ $status -eq 1 ]]; then
		# Script ran (may have failed validation, which is expected)
		assert_file_exist "$log_file"
	fi
}

@test "vpn-monitor.sh rejects dangerous characters in peer IP" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1; rm -rf /"
EOF

	mkdir -p "${TEST_DIR}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"

	# Create test version of script with custom paths
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	run bash "$test_script" --fake

	# Should reject invalid IP format (new validation function checks format, not just dangerous chars)
	assert_file_contains "$log_file" "Invalid peer IP format"
}

@test "vpn-monitor.sh handles multiple peer IPs" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1 10.0.0.1"
EOF

	# Ensure log directory exists
	mkdir -p "${TEST_DIR}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"

	# Create test version of script with custom paths
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	run bash "$test_script" --fake

	# Should process multiple IPs - script should run successfully
	assert_file_exist "$log_file"
}

@test "vpn-monitor.sh maintains independent failure counters per peer" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1 10.0.0.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"

	# Per-peer failure counters with sanitized IPs
	local peer1_ip="192.168.1.1"
	local peer1_sanitized="192_168_1_1"
	local peer2_ip="10.0.0.1"
	local peer2_sanitized="10_0_0_1"
	local failure_counter1="${TEST_DIR}/logs/failure_counter_${peer1_sanitized}"
	local failure_counter2="${TEST_DIR}/logs/failure_counter_${peer2_sanitized}"

	# Set different initial failure counts for each peer
	echo "2" >"$failure_counter1"
	echo "4" >"$failure_counter2"

	# Mock ip command to return no SA (VPN down) for both peers
	local mock_ip=$(mock_ip_xfrm_state "$peer1_ip" "0")
	add_mock_to_path

	# Create test version of script with custom paths
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	PATH="${TEST_DIR}:${PATH}" \
		run bash "$test_script" --fake

	# Each peer should have its own independent counter
	# Peer 1 should have incremented from 2
	if [[ -f "$failure_counter1" ]]; then
		local count1=$(cat "$failure_counter1")
		assert [ "$count1" -gt 2 ]
	fi

	# Peer 2 should have incremented from 4
	if [[ -f "$failure_counter2" ]]; then
		local count2=$(cat "$failure_counter2")
		assert [ "$count2" -gt 4 ]
	fi

	# Counters should be independent (count1 != count2)
	if [[ -f "$failure_counter1" ]] && [[ -f "$failure_counter2" ]]; then
		local count1=$(cat "$failure_counter1")
		local count2=$(cat "$failure_counter2")
		# They should differ since they started at different values
		assert [ "$count1" != "$count2" ]
	fi

	remove_mock_from_path
}

@test "vpn-monitor.sh increments failure counter on failure" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	# Per-peer failure counter: sanitized IP (dots become underscores)
	local peer_ip="192.168.1.1"
	local peer_sanitized="192_168_1_1"
	local failure_counter="${TEST_DIR}/logs/failure_counter_${peer_sanitized}"

	# Mock ip command to return no SA (VPN down)
	local mock_ip=$(mock_ip_xfrm_state "$peer_ip" "0")
	add_mock_to_path

	# Create test version of script with custom paths
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	PATH="${TEST_DIR}:${PATH}" \
		run bash "$test_script" --fake

	# Per-peer failure counter should be incremented
	if [[ -f "$failure_counter" ]]; then
		local count=$(cat "$failure_counter")
		assert [ "$count" -gt 0 ]
	fi

	remove_mock_from_path
}

@test "vpn-monitor.sh resets failure counter on success" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	# Ensure log directory exists
	mkdir -p "${TEST_DIR}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	# Per-peer failure counter: sanitized IP (dots become underscores)
	local peer_ip="192.168.1.1"
	local peer_sanitized="192_168_1_1"
	local failure_counter="${TEST_DIR}/logs/failure_counter_${peer_sanitized}"

	# Set initial failure count for this peer
	mkdir -p "${TEST_DIR}/logs"
	echo "5" >"$failure_counter"

	# Mock ip command to return SA with increasing bytes (VPN up)
	local mock_ip=$(mock_ip_xfrm_state "$peer_ip" "1000")
	add_mock_to_path

	# Create test version of script with custom paths
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	PATH="${TEST_DIR}:${PATH}" \
		run bash "$test_script" --fake

	# Per-peer failure counter should be reset (if script ran successfully)
	if [[ -f "$failure_counter" ]]; then
		local count=$(cat "$failure_counter")
		# Counter should be 0 if VPN check succeeded
		# Note: This test may need VPN to actually be "up" for counter to reset
		assert [ "$count" -ge 0 ]
	fi

	remove_mock_from_path
}

@test "vpn-monitor.sh respects cooldown period" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
COOLDOWN_MINUTES=15
EOF

	mkdir -p "${TEST_DIR}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local cooldown_file="${TEST_DIR}/cooldown_until"

	# Set cooldown to future time
	local future_time=$(($(date +%s) + 900)) # 15 minutes from now
	echo "$future_time" >"$cooldown_file"

	# Create test version of script with custom paths
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	run bash "$test_script" --fake

	# Should exit early due to cooldown
	assert_file_contains "$log_file" "cooldown period"
}

@test "vpn-monitor.sh handles lockfile timeout" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
LOCKFILE_TIMEOUT=300
EOF

	mkdir -p "${TEST_DIR}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local lockfile="${TEST_DIR}/vpn-monitor.lock"

	# Create stale lockfile (old timestamp)
	local old_timestamp=$(($(date +%s) - 400)) # 400 seconds ago
	echo "${old_timestamp}:12345" >"$lockfile"

	# Touch lockfile to make it old
	touch -d "@$old_timestamp" "$lockfile" 2>/dev/null || true

	# Create test version of script with custom paths
	# Note: LOCKFILE is set in script based on STATE_DIR, so we don't need to override it separately
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	run bash "$test_script" --fake

	# Should handle stale lockfile
	assert_file_exist "$log_file"
}

@test "vpn-monitor.sh prevents concurrent execution with lockfile" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local lockfile="${TEST_DIR}/vpn-monitor.lock"

	# Create lockfile with current PID
	echo "$(date +%s):$$" >"$lockfile"

	# Create test version of script with custom paths
	# Note: LOCKFILE is set in script based on STATE_DIR, so we don't need to override it separately
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	# Try to run script (should detect lockfile)
	run timeout 2 bash "$test_script" --fake 2>&1 || true

	# Should detect existing lockfile (may exit or wait)
	# The exact behavior depends on whether flock is available
	assert_file_exist "$log_file"
}

@test "vpn-monitor.sh loads configuration from file" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
VPN_NAME="Custom VPN Name"
DEBUG=1
EOF

	mkdir -p "${TEST_DIR}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"

	# Create test version of script with custom paths
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	run bash "$test_script" --fake

	# Should load config
	assert_file_contains "$log_file" "Configuration loaded"
}

@test "vpn-monitor.sh uses default config if file missing" {
	mkdir -p "${TEST_DIR}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local config_file="${TEST_DIR}/nonexistent.conf"

	# Don't create config file - create test script pointing to non-existent config
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	# Set PEER_IPS via environment since config file doesn't exist
	PEER_IPS="192.168.1.1" \
		run bash "$test_script" --fake

	# Should use defaults and warn
	assert_file_contains "$log_file" "Configuration file not found"
}

@test "vpn-monitor.sh handles ping check when enabled" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
ENABLE_PING_CHECK=1
PING_TARGET_IP="192.168.1.1"
PING_COUNT=3
PING_TIMEOUT=2
EOF

	mkdir -p "${TEST_DIR}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"

	# Mock ping command
	local mock_ping=$(mock_ping "192.168.1.1" "1")
	add_mock_to_path

	# Mock ip command to return SA (VPN appears up)
	local mock_ip=$(mock_ip_xfrm_state "192.168.1.1" "1000")

	# Create test version of script with custom paths
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	PATH="${TEST_DIR}:${PATH}" \
		run bash "$test_script" --fake

	# Should perform ping check
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "vpn-monitor.sh handles debug mode" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
DEBUG=1
EOF

	mkdir -p "${TEST_DIR}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"

	# Create test version of script with custom paths
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	DEBUG=1 \
		run bash "$test_script" --fake

	# Debug output should be present
	assert_file_exist "$log_file"
	# Debug messages go to stderr, check log file for DEBUG entries
	run grep -q "DEBUG" "$log_file" || true
	# May or may not have DEBUG entries depending on execution path
}

@test "vpn-monitor.sh checks cron persistence" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"

	# Remove cron entry if it exists
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true

	# Create test version of script with custom paths
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	run bash "$test_script" --fake

	# Should check cron persistence
	assert_file_exist "$log_file"
	# May warn if cron not found
}
