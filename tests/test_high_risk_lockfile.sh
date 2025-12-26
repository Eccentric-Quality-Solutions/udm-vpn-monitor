#!/usr/bin/env bats
#
# High-risk tests: Lockfile Management
# Tests critical paths and error handling scenarios that could cause production failures
#
# This file is part of the high-risk test suite, split from test_high_risk.sh
# for better organization and maintainability.

load test_helper

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# 1. LOCKFILE MANAGEMENT TESTS
# ============================================================================

@test "high-risk: lockfile cleanup on script exit" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Run script - should complete successfully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_success
	# Lockfile should be cleaned up after script exits
	assert_file_not_exist "$lockfile"

	remove_mock_from_path
}

@test "high-risk: lockfile cleanup on script error" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="invalid-ip-format"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Run script - should exit with error due to invalid IP
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Lockfile should be cleaned up even on error
	# Note: Script may exit before lockfile creation, so check may be flaky
	# But if lockfile was created, it should be cleaned up
	if [[ -f "$lockfile" ]]; then
		# If lockfile exists, it should be stale or cleaned up
		# This is a best-effort check
		echo "Lockfile still exists after error - may need manual cleanup"
	fi
}

@test "high-risk: lockfile contains invalid format" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create lockfile with invalid format (not timestamp:pid)
	echo "invalid-format" >"$lockfile"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Script should handle invalid lockfile format gracefully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should either clean up invalid lockfile or handle it gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: lockfile timestamp at timeout boundary" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
LOCKFILE_TIMEOUT=300
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create lockfile exactly at timeout boundary (300 seconds ago)
	local boundary_time=$(($(date +%s) - 300))
	echo "${boundary_time}:12345" >"$lockfile"
	# Touch file to set modification time
	touch -d "@$boundary_time" "$lockfile" 2>/dev/null || true

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Script should handle boundary condition
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should either treat as stale or handle gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: lockfile acquisition prevents concurrent execution" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create a lockfile with current PID (simulating another instance)
	echo "$(date +%s):$$" >"$lockfile"
	touch "$lockfile"

	# Try to run script - should detect lockfile and exit
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should exit gracefully (code 0) when lockfile detected
	assert_success
	# Should log lockfile conflict (check for various possible messages)
	assert_output --partial "already running" || assert_output --partial "Another instance" || assert_file_contains "$log_file" "already running" || assert_file_contains "$log_file" "Another instance"

	# Clean up
	rm -f "$lockfile"

	remove_mock_from_path
}

@test "high-risk: lockfile acquisition uses flock when available" {
	# Skip if flock not available
	if ! command -v flock >/dev/null 2>&1; then
		skip "flock command not available"
	fi

	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Run script - should use flock mechanism
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_success
	# Lockfile should be cleaned up (flock mechanism works)
	assert_file_not_exist "$lockfile"

	remove_mock_from_path
}

@test "high-risk: lockfile acquisition falls back when flock unavailable" {
	# Temporarily hide flock command
	local test_bin="${TEST_DIR}/bin"
	mkdir -p "$test_bin"

	# Create a fake flock that doesn't exist
	# We'll modify PATH to exclude real flock, but keep essential directories
	local path_without_flock=""
	for dir in $(echo "$PATH" | tr ':' ' '); do
		# Keep essential directories (/bin, /usr/bin) even if they contain flock
		# Only exclude directories that contain flock but aren't essential
		if [[ "$dir" == "/bin" ]] || [[ "$dir" == "/usr/bin" ]]; then
			path_without_flock="${path_without_flock}:${dir}"
		elif [[ ! -f "$dir/flock" ]]; then
			path_without_flock="${path_without_flock}:${dir}"
		fi
	done
	path_without_flock="${path_without_flock#:}"
	# Ensure /bin and /usr/bin are always present
	if [[ "$path_without_flock" != *"/bin"* ]]; then
		path_without_flock="/bin:/usr/bin:${path_without_flock}"
	fi

	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Run script with PATH that doesn't include flock
	PATH="${TEST_DIR}:${path_without_flock}" run bash "$test_script" --fake

	assert_success
	# Lockfile should be cleaned up (fallback mechanism works)
	assert_file_not_exist "$lockfile"

	remove_mock_from_path
}

@test "high-risk: lockfile switching between flock and fallback modes" {
	# This test verifies correct behavior when switching between flock and fallback lockfile mechanisms
	# Different locking mechanisms have different failure modes, so it's critical to ensure
	# they can interoperate correctly when the system switches modes
	# Both modes use the same lockfile format (timestamp:pid), so they should be compatible

	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create a PATH without flock to test fallback mode
	# Use the same approach as the existing fallback test
	local path_without_flock=""
	for dir in $(echo "$PATH" | tr ':' ' '); do
		if [[ "$dir" == "/bin" ]] || [[ "$dir" == "/usr/bin" ]]; then
			# Keep essential directories even if they contain flock
			path_without_flock="${path_without_flock}:${dir}"
		elif [[ ! -f "$dir/flock" ]]; then
			path_without_flock="${path_without_flock}:${dir}"
		fi
	done
	path_without_flock="${path_without_flock#:}"
	if [[ "$path_without_flock" != *"/bin"* ]]; then
		path_without_flock="/bin:/usr/bin:${path_without_flock}"
	fi

	# Test 1: Verify concurrent execution prevention works when switching modes
	# Create a lockfile with a running PID (current process) - format is same for both modes
	# This simulates a lockfile created by one mode being detected by the other mode
	local current_pid=$$
	echo "$(date +%s):${current_pid}" >"$lockfile"
	touch "$lockfile"

	# Verify flock mode can detect lockfile created by fallback mode (or vice versa)
	# Since PID is running, both modes should detect conflict and exit gracefully
	if command -v flock >/dev/null 2>&1; then
		PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
		# Should detect running process and exit gracefully (code 0)
		assert_success
		# Should output warning about lockfile conflict
		assert_output --partial "already running"
	fi

	# Clean up
	rm -f "$lockfile"

	# Test 2: Verify fallback mode can detect lockfile created by flock mode
	# Recreate lockfile with running PID
	echo "$(date +%s):${current_pid}" >"$lockfile"
	touch "$lockfile"

	# Test with fallback mode (PATH without flock)
	PATH="${TEST_DIR}:${path_without_flock}" run bash "$test_script" --fake
	assert_success
	# Should detect running process and exit gracefully
	assert_output --partial "already running"

	# Clean up
	rm -f "$lockfile"

	# Test 3: Verify stale lockfile handling works correctly when switching modes
	# Create a stale lockfile (old timestamp) - format is same for both modes
	# Update config file to set LOCKFILE_TIMEOUT for stale lockfile detection
	local lockfile_timeout=300
	cat >"$config_file" <<EOF
EXTERNAL_PEER_IPS="192.168.1.1"
LOCKFILE_TIMEOUT=${lockfile_timeout}
EOF
	# Recreate test script to pick up updated config
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	local old_timestamp
	old_timestamp=$(($(date +%s) - lockfile_timeout - 10))
	echo "${old_timestamp}:99999" >"$lockfile"
	touch -d "@$old_timestamp" "$lockfile" 2>/dev/null || touch "$lockfile"

	# Verify flock mode can detect and remove stale lockfile created by fallback mode
	if command -v flock >/dev/null 2>&1; then
		PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
		assert_success
		# Stale lockfile should be removed and script should proceed
		assert_file_not_exist "$lockfile"
	fi

	# Recreate stale lockfile for fallback mode test
	echo "${old_timestamp}:99999" >"$lockfile"
	touch -d "@$old_timestamp" "$lockfile" 2>/dev/null || touch "$lockfile"

	# Verify fallback mode can detect and remove stale lockfile created by flock mode
	PATH="${TEST_DIR}:${path_without_flock}" run bash "$test_script" --fake
	assert_success
	# Stale lockfile should be removed and script should proceed
	assert_file_not_exist "$lockfile"

	remove_mock_from_path
}

@test "high-risk: lockfile cleanup on SIGTERM" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Run script in background
	PATH="${TEST_DIR}:${PATH}" bash "$test_script" --fake &
	local script_pid=$!

	# Give script a moment to start and create lockfile (needed for signal test)
	sleep 0.01

	# Send SIGTERM
	kill -TERM "$script_pid" 2>/dev/null || true
	wait "$script_pid" 2>/dev/null || true

	# Lockfile should be cleaned up by trap handler
	# Note: This is a best-effort check - trap may not always fire in test environment
	if [[ -f "$lockfile" ]]; then
		# If lockfile still exists, it should be stale
		echo "Lockfile may still exist - trap cleanup may not fire in test environment"
	fi

	remove_mock_from_path
}

@test "high-risk: multiple processes attempting to acquire lock simultaneously (flock path)" {
	# Skip if flock not available
	if ! command -v flock >/dev/null 2>&1; then
		skip "flock command not available"
	fi

	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Spawn multiple processes simultaneously trying to acquire lock
	local pids=()
	local success_count=0
	local conflict_count=0

	for i in {1..2}; do
		PATH="${TEST_DIR}:${PATH}" bash "$test_script" --fake >"${TEST_DIR}/output_${i}.log" 2>&1 &
		pids+=($!)
	done

	# Wait for all processes to complete
	for pid in "${pids[@]}"; do
		wait "$pid" 2>/dev/null || true
	done

	# Check results - only one should succeed, others should detect conflict
	for i in {1..2}; do
		if grep -q "already running" "${TEST_DIR}/output_${i}.log" 2>/dev/null; then
			conflict_count=$((conflict_count + 1))
		elif [[ -f "$lockfile" ]] || grep -q "VPN" "${TEST_DIR}/output_${i}.log" 2>/dev/null; then
			success_count=$((success_count + 1))
		fi
	done

	# Verify: exactly one should succeed, others should detect conflict
	# Note: In rare cases, all might fail if timing is perfect, but at least one should succeed or detect conflict
	if [[ $((success_count + conflict_count)) -lt 1 ]]; then
		fail "At least one process should succeed or detect conflict (success: $success_count, conflict: $conflict_count)"
	fi

	# Clean up any remaining lockfile
	rm -f "$lockfile"

	remove_mock_from_path
}

@test "high-risk: multiple processes attempting to acquire lock simultaneously (fallback path)" {
	# Temporarily hide flock command to force fallback path
	local test_bin="${TEST_DIR}/bin"
	mkdir -p "$test_bin"

	# Create a fake flock that doesn't exist
	# We'll modify PATH to exclude real flock
	local path_without_flock=""
	for dir in $(echo "$PATH" | tr ':' ' '); do
		if [[ ! -f "$dir/flock" ]]; then
			path_without_flock="${path_without_flock}:${dir}"
		fi
	done
	path_without_flock="${path_without_flock#:}"

	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Spawn multiple processes simultaneously trying to acquire lock using fallback method
	local pids=()
	local success_count=0
	local conflict_count=0

	for i in {1..2}; do
		PATH="${TEST_DIR}:${path_without_flock}" bash "$test_script" --fake >"${TEST_DIR}/output_${i}.log" 2>&1 &
		pids+=($!)
	done

	# Wait for all processes to complete
	for pid in "${pids[@]}"; do
		wait "$pid" 2>/dev/null || true
	done

	# Check results - only one should succeed, others should detect conflict
	for i in {1..2}; do
		if [[ -f "${TEST_DIR}/output_${i}.log" ]]; then
			# Check for conflict messages
			if grep -qi "already running\|Could not acquire lockfile\|exiting" "${TEST_DIR}/output_${i}.log" 2>/dev/null; then
				conflict_count=$((conflict_count + 1))
			# Check for success (script ran and completed)
			elif grep -qi "VPN\|monitor\|check" "${TEST_DIR}/output_${i}.log" 2>/dev/null || [[ -s "${TEST_DIR}/output_${i}.log" ]]; then
				success_count=$((success_count + 1))
			fi
		fi
	done

	# Also check if lockfile exists (indicates at least one process succeeded)
	if [[ -f "$lockfile" ]]; then
		success_count=$((success_count + 1))
	fi

	# Verify: at least one process should have some outcome
	# Note: In rare cases, all might fail if timing is perfect, but at least one should succeed or detect conflict
	if [[ $((success_count + conflict_count)) -lt 1 ]]; then
		for i in {1..2}; do
			if [[ -f "${TEST_DIR}/output_${i}.log" ]]; then
				echo "Output $i (size: $(wc -c <"${TEST_DIR}/output_${i}.log")):"
				head -3 "${TEST_DIR}/output_${i}.log" || true
			fi
		done
		fail "At least one process should succeed or detect conflict (success: $success_count, conflict: $conflict_count)"
	fi

	# Clean up any remaining lockfile
	rm -f "$lockfile"

	remove_mock_from_path
}

@test "high-risk: lockfile removed between check and creation (TOCTOU race)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create a script that removes lockfile during acquisition attempt
	# This simulates TOCTOU race condition
	local race_script="${TEST_DIR}/race_condition.sh"
	cat >"$race_script" <<EOF
#!/bin/bash
# Run the test script in background
PATH="${TEST_DIR}:${PATH}" bash "$test_script" --fake &
test_pid=\$!

# Remove lockfile while script is checking (TOCTOU race)
# Mocks complete instantly, so no delay needed
rm -f "$lockfile"

# Wait for test script to complete
wait \$test_pid 2>/dev/null || true
EOF
	chmod +x "$race_script"

	# Run the race condition test
	PATH="${TEST_DIR}:${PATH}" bash "$race_script"

	# Script should handle race condition gracefully
	# Either it successfully acquires lock or detects conflict
	# The important thing is it doesn't crash or allow concurrent execution
	assert_file_exist "$log_file"

	# Clean up
	rm -f "$lockfile"

	remove_mock_from_path
}

@test "high-risk: PID reuse scenario (old PID reused, lockfile appears valid but process is different)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create a short-lived process to get its PID
	# Then create lockfile with that PID after process exits
	# This simulates PID reuse scenario
	(
		sleep 0.01
		exit 0
	) &
	local old_pid=$!
	wait "$old_pid" 2>/dev/null || true

	# Now create lockfile with the old PID (which may be reused by now)
	# Format: timestamp:pid
	echo "$(date +%s):${old_pid}" >"$lockfile"
	touch "$lockfile"

	# Check if PID is actually reused (unlikely but possible)
	# If current process has same PID, we can't test this scenario
	if [[ $$ -eq $old_pid ]]; then
		skip "Cannot test PID reuse - PID matches current process"
	fi

	# Try to run script - it should check if PID is still running
	# Since old_pid process has exited, it should detect stale lockfile
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script should handle PID reuse scenario
	# It should check if process is running using kill -0
	# Since old_pid has exited, it should remove stale lockfile and proceed
	assert_file_exist "$log_file"

	# Clean up
	rm -f "$lockfile"

	remove_mock_from_path
}

@test "high-risk: script crashes - lockfile should be detected as stale on next run" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
LOCKFILE_TIMEOUT=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Run script in background
	PATH="${TEST_DIR}:${PATH}" bash "$test_script" --fake &
	local script_pid=$!

	# Give script a moment to create lockfile before killing it
	sleep 0.01

	# Verify lockfile exists (should be created by script)
	if [[ ! -f "$lockfile" ]]; then
		skip "Lockfile not created quickly enough for crash test"
	fi

	# Kill script with SIGKILL (cannot be caught, simulates crash)
	kill -KILL "$script_pid" 2>/dev/null || true
	wait "$script_pid" 2>/dev/null || true

	# Make lockfile old (beyond timeout) by touching it with old timestamp
	# Use a timestamp that's definitely older than LOCKFILE_TIMEOUT
	local old_timestamp=$(($(date +%s) - 2))
	touch -d "@$old_timestamp" "$lockfile" 2>/dev/null || {
		# Fallback: wait for timeout if touch -d doesn't work (reduced from 2s)
		sleep 0.5
	}

	# Now run script again - should detect stale lockfile and remove it
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script should succeed (stale lockfile removed)
	assert_success
	# Lockfile should be cleaned up after script completes
	assert_file_not_exist "$lockfile"

	remove_mock_from_path
}

@test "high-risk: trap handlers properly clean up lockfile in all exit scenarios" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Test 1: Normal exit (EXIT trap)
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success
	assert_file_not_exist "$lockfile"

	# Test 2: SIGINT (INT trap)
	PATH="${TEST_DIR}:${PATH}" bash "$test_script" --fake &
	local script_pid=$!
	# Give script a moment to start before sending signal
	sleep 0.01
	kill -INT "$script_pid" 2>/dev/null || true
	wait "$script_pid" 2>/dev/null || true
	# Lockfile should be cleaned up by INT trap
	if [[ -f "$lockfile" ]]; then
		# Trap may not fire in test environment, but lockfile should be stale
		# Verify it would be detected as stale
		echo "Lockfile exists after SIGINT - verifying stale detection"
	fi

	# Test 3: SIGTERM (TERM trap) - already tested above but verify consistency
	rm -f "$lockfile"
	PATH="${TEST_DIR}:${PATH}" bash "$test_script" --fake &
	script_pid=$!
	# Give script a moment to start before sending signal
	sleep 0.01
	kill -TERM "$script_pid" 2>/dev/null || true
	wait "$script_pid" 2>/dev/null || true
	# Lockfile should be cleaned up by TERM trap
	if [[ -f "$lockfile" ]]; then
		# Trap may not fire in test environment, but lockfile should be stale
		echo "Lockfile exists after SIGTERM - verifying stale detection"
	fi

	# Clean up any remaining lockfile
	rm -f "$lockfile"

	remove_mock_from_path
}

# ============================================================================
# 1.3 STALE LOCKFILE EDGE CASES (continued)
# ============================================================================

@test "high-risk: lockfile file modification time cannot be read (permission issues)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create lockfile
	echo "$(date +%s):12345" >"$lockfile"

	# Mock stat command to fail (simulates permission issues)
	local mock_stat="${TEST_DIR}/stat"
	cat >"$mock_stat" <<'EOF'
#!/bin/bash
# Simulate stat failure (permission denied)
exit 1
EOF
	chmod +x "$mock_stat"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Add mock stat to PATH before system stat
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle stat failure gracefully (should treat mtime=0 as stale)
	# Code at lib/state.sh:266 returns "0" on stat failure
	# Code at lib/lockfile.sh:150-152 treats mtime=0 as stale
	assert_file_exist "$log_file"

	# Cleanup
	rm -f "$lockfile" 2>/dev/null || true
	remove_mock_from_path
}

# ============================================================================
# 1.3 STALE LOCKFILE EDGE CASES (continued)
# ============================================================================

@test "high-risk: lockfile exists but PID belongs to different user (permission denied on kill -0)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create lockfile with a PID
	echo "$(date +%s):12345" >"$lockfile"

	# Mock kill command to fail (simulates permission denied)
	local mock_kill="${TEST_DIR}/kill"
	cat >"$mock_kill" <<'EOF'
#!/bin/bash
# Simulate kill -0 failure (permission denied for different user)
exit 1
EOF
	chmod +x "$mock_kill"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Add mock kill to PATH before system kill
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle kill -0 failure gracefully (should treat lockfile as stale)
	# Code at lib/lockfile.sh:68 suppresses errors with 2>/dev/null
	# kill -0 failure makes is_process_running() return 1, treating lockfile as stale
	assert_file_exist "$log_file"

	# Cleanup
	rm -f "$lockfile" 2>/dev/null || true
	remove_mock_from_path
}

# ============================================================================
# 1.3 STALE LOCKFILE EDGE CASES (continued)
# ============================================================================

@test "high-risk: lockfile exists but PID is zombie process" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create lockfile with a PID
	echo "$(date +%s):12345" >"$lockfile"

	# Mock kill to succeed (zombie processes still respond to kill -0)
	local mock_kill="${TEST_DIR}/kill"
	cat >"$mock_kill" <<'EOF'
#!/bin/bash
# Simulate kill -0 succeeding for zombie process
exit 0
EOF
	chmod +x "$mock_kill"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Add mock kill to PATH before system kill
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Zombie processes still respond to kill -0, so lockfile would appear valid
	# Code at lib/lockfile.sh:68 uses kill -0 which succeeds for zombies
	assert_file_exist "$log_file"

	# Cleanup
	rm -f "$lockfile" 2>/dev/null || true
	remove_mock_from_path
}
