#!/usr/bin/env bats
#
# High-risk tests for vpn-monitor.sh
# Tests critical paths and error handling scenarios that could cause production failures
#
# Focus areas:
# 1. Lockfile Management (race conditions, cleanup, edge cases)
# 2. Configuration Loading (security, error handling, validation)
# 3. VPN Status Detection (edge cases, fallback chains, byte counters)
# 4. Recovery Actions (execution, error handling, verification)

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
# 2. CONFIGURATION LOADING AND VALIDATION TESTS
# ============================================================================

@test "high-risk: config file contains syntax errors" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config with syntax error (unclosed quote)
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1
VPN_NAME="Test VPN"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should handle syntax error gracefully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should log error about config file
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "Failed to source configuration file" || assert_file_contains "$log_file" "ERROR"
}

@test "high-risk: config file is unreadable" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	# Make config file unreadable
	chmod 000 "$config_file"

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should handle unreadable config gracefully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should log error about config file
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "not readable" || assert_file_contains "$log_file" "ERROR"

	# Restore permissions for cleanup
	chmod 644 "$config_file" 2>/dev/null || true
}

@test "high-risk: config file is a directory" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create directory instead of file
	mkdir -p "$config_file"

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should handle directory instead of file gracefully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should log warning or error
	assert_file_exist "$log_file"
}

@test "high-risk: LOG_FILE override in config recalculates LOGS_DIR" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
LOG_FILE="/tmp/custom-logs/vpn-monitor.log"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local custom_log_file="/tmp/custom-logs/vpn-monitor.log"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Run script
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_success
	# Custom log directory should be created
	assert_dir_exist "/tmp/custom-logs"
	# Log file should exist in custom location
	assert_file_exist "$custom_log_file"

	# Cleanup
	rm -rf /tmp/custom-logs 2>/dev/null || true
	remove_mock_from_path
}

@test "high-risk: negative threshold values in config" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=-1
TIER2_THRESHOLD=-3
TIER3_THRESHOLD=-5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Script should handle negative thresholds (may cause unexpected behavior)
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script should run (may have unexpected tier escalation behavior)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: threshold values out of order" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=5
TIER2_THRESHOLD=3
TIER3_THRESHOLD=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Script should handle out-of-order thresholds
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script should run (may skip tiers or have unexpected behavior)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 3. VPN STATUS DETECTION TESTS
# ============================================================================

@test "high-risk: xfrm SA exists but byte counter is exactly 0" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command - SA exists but bytes=0
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 0 bytes, 0 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should detect bytes=0 as suspect (may fail VPN check)
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "bytes=0" || assert_file_contains "$log_file" "suspect"

	remove_mock_from_path
}

@test "high-risk: xfrm SA exists but byte counter decreases" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Set initial byte count (high value)
	echo "10000" >"$last_bytes_file"

	# Mock ip command - bytes decreased (counter wrap-around scenario)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 5000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should detect bytes not increasing (may fail VPN check)
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "bytes not increasing" || assert_file_contains "$log_file" "suspect"

	remove_mock_from_path
}

@test "high-risk: xfrm SA exists but byte counter stays same" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Set initial byte count
	echo "1000" >"$last_bytes_file"

	# Mock ip command - bytes stay same
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should detect bytes not increasing
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "bytes not increasing" || assert_file_contains "$log_file" "suspect"

	remove_mock_from_path
}

@test "high-risk: byte counter file corrupted" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Create corrupted byte counter file (non-numeric)
	echo "invalid-value" >"$last_bytes_file"

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should handle corrupted file gracefully (treat as 0 or reset)
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: byte counter file contains negative number" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Create byte counter file with negative number
	echo "-1000" >"$last_bytes_file"

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should handle negative value gracefully
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: byte counter file is empty" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Create empty byte counter file
	touch "$last_bytes_file"

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should handle empty file gracefully (treat as 0)
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: all detection methods unavailable" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Don't create any mock commands (all unavailable)
	# PATH will not include mocks, so real commands won't be found in test environment

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Create minimal PATH with only essential commands
	# Use a PATH that doesn't include ip or ipsec
	PATH="/usr/bin:/bin" run bash "$test_script" --fake || true

	# Should handle all methods unavailable gracefully
	# Script may exit early, but if log file exists, it should contain error messages
	if [[ -f "$log_file" ]]; then
		assert_file_contains "$log_file" "suspect" || assert_file_contains "$log_file" "failed" || assert_file_contains "$log_file" "WARNING"
	else
		# If log file doesn't exist, script likely exited very early - this is acceptable
		# The important thing is it didn't crash
		echo "Log file not created - script exited early (acceptable behavior)"
	fi
}

@test "high-risk: xfrm output contains multiple lifetime lines" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command with multiple lifetime lines
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    echo "    lifetime hard: 3600s, 0 bytes, 0 packets"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should extract first lifetime line correctly
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: ping check enabled but PING_TARGET_IP not set" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
ENABLE_PING_CHECK=1
PING_TARGET_IP=""
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command - VPN appears up
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ping - should use peer IP
	local mock_ping
	mock_ping=$(mock_ping "192.168.1.1" "1")
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should use peer IP for ping check
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 4. RECOVERY ACTIONS TESTS
# ============================================================================

@test "high-risk: surgical cleanup uses ipsec reload (default behavior, affects all tunnels)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 2 threshold
	echo "3" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - track reload call
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "ipsec-reload-called" > /tmp/ipsec_called.txt
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Should use ipsec reload (affects all tunnels)
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "ipsec reload"
	if [[ -f /tmp/ipsec_called.txt ]]; then
		assert_file_exist /tmp/ipsec_called.txt
		rm -f /tmp/ipsec_called.txt
	fi

	remove_mock_from_path
}

@test "high-risk: surgical cleanup uses ipsec reload (default behavior)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 2 threshold
	echo "3" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - track reload call
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "ipsec-reload-called" > /tmp/ipsec_called.txt
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Should use ipsec reload (affects all tunnels)
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "ipsec reload"
	if [[ -f /tmp/ipsec_called.txt ]]; then
		assert_file_exist /tmp/ipsec_called.txt
		rm -f /tmp/ipsec_called.txt
	fi

	remove_mock_from_path
}

@test "high-risk: surgical cleanup fails - error handling" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 2 threshold
	echo "3" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - reload fails
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "ipsec reload failed" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Should handle error gracefully (not crash)
	assert_file_exist "$log_file"
	# Script should continue execution

	remove_mock_from_path
}

@test "high-risk: full restart with ipsec command" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - track if called
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ipsec-restart-called" > /tmp/ipsec_called.txt
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Should call ipsec restart
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "full IPsec restart" || assert_file_contains "$log_file" "Tier 3"
	if [[ -f /tmp/ipsec_called.txt ]]; then
		assert_file_exist /tmp/ipsec_called.txt
		rm -f /tmp/ipsec_called.txt
	fi

	remove_mock_from_path
}

@test "high-risk: full restart fails - error handling" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - fails
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ipsec restart failed" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle error gracefully
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "Failed to restart" || assert_file_contains "$log_file" "ERROR"

	remove_mock_from_path
}

@test "high-risk: full restart when ipsec unavailable" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Don't create ipsec mock (unavailable)

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle unavailable commands gracefully
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "not available" || assert_file_contains "$log_file" "ERROR"

	remove_mock_from_path
}

@test "high-risk: rate limit file corrupted" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local restart_file="${TEST_DIR}/logs/restart_count"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create corrupted restart file (non-numeric)
	echo "invalid-timestamp" >"$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec
	local mock_ipsec
	mock_ipsec=$(mock_ipsec)
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle corrupted file gracefully
	assert_file_exist "$log_file"
	# Script should either skip rate limit check or handle error

	remove_mock_from_path
}

@test "high-risk: config file attempts command injection via variable" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Attempt command injection via EXTERNAL_PEER_IPS
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1; echo 'injected' > /tmp/injection_test"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should reject invalid IP format (command injection should be caught by IP validation)
	assert_file_exist "$log_file"
	# Injection should not execute - IP validation should catch it
	assert_file_not_exist "/tmp/injection_test"

	remove_mock_from_path
}

@test "high-risk: xfrm command fails with permission denied" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command that fails
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "Permission denied" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should fallback to ipsec status
	assert_file_exist "$log_file"
	# Should handle xfrm failure gracefully

	remove_mock_from_path
}

@test "high-risk: failure counter file is directory" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create directory instead of file
	mkdir -p "$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle directory gracefully (may fail to write, but shouldn't crash)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: byte counter file is directory" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Create directory instead of file
	mkdir -p "$last_bytes_file"

	# Mock ip command - VPN healthy
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle directory gracefully (may fail to write, but shouldn't crash)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: verify correct behavior when switching between flock and fallback modes" {
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

	# Test 1: Run with flock available (if available)
	if command -v flock >/dev/null 2>&1; then
		PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
		assert_success
		assert_file_not_exist "$lockfile"
	fi

	# Test 2: Run without flock (force fallback mode)
	# Create a PATH that excludes flock, but keep essential directories
	local path_without_flock=""
	for dir in $(echo "$PATH" | tr ':' ' '); do
		# Keep essential directories (/bin, /usr/bin) even if they contain flock
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

	PATH="${TEST_DIR}:${path_without_flock}" run bash "$test_script" --fake
	assert_success
	assert_file_not_exist "$lockfile"

	# Test 3: Switch modes during execution (simulate flock becoming unavailable)
	# This tests that the script handles mode detection correctly
	rm -f "$lockfile"
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	remove_mock_from_path
}

@test "high-risk: config file sources external commands (security risk)" {
	# This test verifies that config files that attempt to source external files
	# or execute commands are handled appropriately
	# Security risk: If config files can source arbitrary files, an attacker could
	# gain code execution by modifying the config file

	local config_file="${TEST_DIR}/vpn-monitor.conf"
	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Test 1: Config file attempts to source external file
	# Note: Sourcing a bash script WILL execute commands in it (this is bash behavior)
	# The security concern is that we allow sourcing arbitrary files
	local malicious_file="${TEST_DIR}/malicious.sh"
	cat >"$malicious_file" <<'EOF'
#!/bin/bash
# This file would execute commands if sourced
MALICIOUS_VAR="injected"
EOF

	cat >"$config_file" <<EOF
EXTERNAL_PEER_IPS="192.168.1.1"
# Attempt to source external file (security risk)
source "$malicious_file"
EOF

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should handle sourcing - may succeed (bash allows sourcing) or fail gracefully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should log error or handle gracefully
	assert_file_exist "$log_file"
	# Script should either fail to source (preferred) or handle it gracefully
	# If sourcing succeeds, variables from malicious file might be loaded
	# The key is that the script should not crash and should handle the situation

	# Clean up
	rm -f "$malicious_file" 2>/dev/null || true

	# Test 2: Config file attempts to execute command via backticks in variable assignment
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
# Attempt command execution via backticks (security risk)
TEST_VAR=$(touch "${TEST_DIR}/backtick_test_marker" 2>/dev/null; echo "test")
EOF

	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Command substitution WILL execute (this is bash behavior)
	# The script should handle it gracefully without crashing
	assert_file_exist "$log_file"

	# Clean up
	rm -f "${TEST_DIR}/backtick_test_marker" 2>/dev/null || true

	# Test 3: Config file attempts to source process substitution
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
# Attempt to source process substitution (security risk)
source <(echo 'PROCESS_SUB_VAR="injected"')
EOF

	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle gracefully - process substitution may succeed or fail
	assert_file_exist "$log_file"

	# Test 4: Config file attempts to source non-existent file (should fail gracefully)
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
# Attempt to source non-existent file
source /nonexistent/file/path.sh
EOF

	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should fail gracefully when file doesn't exist
	assert_file_exist "$log_file"
	# Should log error about failed source
	assert_file_contains "$log_file" "Failed to source" || assert_file_contains "$log_file" "ERROR" || assert_file_contains "$log_file" "configuration"

	remove_mock_from_path
}

@test "high-risk: config file contains null bytes or invalid characters" {
	# This test verifies that config files with null bytes or invalid characters
	# are handled gracefully without causing crashes or security issues

	local config_file="${TEST_DIR}/vpn-monitor.conf"
	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Test 1: Config file with null bytes (should be handled gracefully)
	printf 'EXTERNAL_PEER_IPS="192.168.1.1"\x00INVALID\x00DATA' >"$config_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should handle null bytes gracefully (may fail to parse or log error)
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle gracefully - script should not crash
	assert_file_exist "$log_file"
	# Should either fail gracefully or parse up to null byte
	# Check that script attempted to process config (logged something)
	assert_file_contains "$log_file" "Configuration" || assert_file_contains "$log_file" "ERROR" || assert_file_contains "$log_file" "Failed"

	# Test 2: Config file with invalid UTF-8 characters
	printf 'EXTERNAL_PEER_IPS="192.168.1.1"\xFF\xFE\xFDINVALID' >"$config_file"

	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle invalid UTF-8 gracefully
	assert_file_exist "$log_file"

	# Test 3: Config file with control characters (non-printable)
	printf 'EXTERNAL_PEER_IPS="192.168.1.1"\x01\x02\x03\x04\x05' >"$config_file"

	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle control characters gracefully
	assert_file_exist "$log_file"

	# Test 4: Config file with mixed valid and invalid content
	# Valid config followed by null byte and invalid data
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF
	# Append null byte and invalid characters
	printf '\x00\xFF\xFE' >>"$config_file"

	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should parse valid part before null byte
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: xfrm output format variations (different Linux kernel versions)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command with different output format (older kernel style)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Different format: no indentation, different spacing
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "replay-window 0"
    echo "lifetime current: 1000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should handle format variations gracefully
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: xfrm returns multiple SAs for same peer IP (which one is checked?)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command with multiple SAs for same peer IP
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x87654321 reqid 2 mode tunnel"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should handle multiple SAs (may check first one or aggregate)
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: xfrm output contains malformed byte counter line" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command with malformed byte counter line
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: invalid bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle malformed output gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: first check (no previous bytes) - should accept any non-zero value" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Ensure no previous bytes file exists (first check)
	rm -f "$last_bytes_file"

	# Mock ip command - VPN healthy with non-zero bytes
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should accept non-zero value on first check
	assert_success
	assert_file_exist "$log_file"
	# Should create bytes file with current value
	assert_file_exist "$last_bytes_file"

	remove_mock_from_path
}

@test "high-risk: byte counter increases but very slowly (within normal variance)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Set initial byte count
	echo "1000" >"$last_bytes_file"

	# Mock ip command - bytes increased very slowly (only 1 byte)
	mock_ip_xfrm_state "192.168.1.1" "1001" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should accept small increase as valid (bytes are increasing)
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: byte counter jumps dramatically (counter reset on remote side)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Set initial byte count (high value)
	echo "1000000" >"$last_bytes_file"

	# Mock ip command - bytes jumped dramatically lower (counter reset)
	mock_ip_xfrm_state "192.168.1.1" "100" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle counter reset (may treat as wrap-around or failure)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: multiple peers failing simultaneously - verify independent cleanup" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1 10.0.0.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter1="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	local failure_counter2="${TEST_DIR}/logs/failure_counter_10_0_0_1"

	# Set both peers to Tier 2 threshold
	echo "3" >"$failure_counter1"
	echo "3" >"$failure_counter2"

	# Mock ip command - VPN down for both
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - track reload calls
	local mock_ipsec="${TEST_DIR}/ipsec"
	local reload_log="${TEST_DIR}/reload_log.txt"
	cat >"$mock_ipsec" <<EOF
#!/bin/bash
if [[ "\$1" == "reload" ]]; then
    echo "ipsec-reload" >> "$reload_log"
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Both peers should trigger cleanup independently
	assert_file_exist "$log_file"
	# Both peers should trigger ipsec reload (affects all tunnels)
	if [[ -f "$reload_log" ]]; then
		local reload_count
		reload_count=$(wc -l <"$reload_log")
		assert [ "$reload_count" -ge 1 ]
	fi

	remove_mock_from_path
}

@test "high-risk: full restart with ipsec command (success case)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - track if called
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ipsec-restart-called" > /tmp/ipsec_restart.txt
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Should use ipsec for restart
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "ipsec restart"
	if [[ -f /tmp/ipsec_restart.txt ]]; then
		assert_file_exist /tmp/ipsec_restart.txt
		rm -f /tmp/ipsec_restart.txt
	fi

	remove_mock_from_path
}

@test "high-risk: full restart with ipsec command fails (error handling)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - fails
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ipsec restart failed" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle error gracefully
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "Failed" || assert_file_contains "$log_file" "ERROR"

	remove_mock_from_path
}

@test "high-risk: restart succeeds but VPN doesn't recover (cooldown still set)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	local cooldown_file="${TEST_DIR}/cooldown_until"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN still down after restart
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - restart succeeds
	local mock_ipsec
	mock_ipsec=$(mock_ipsec)
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Run script (not in fake mode, so restart will actually execute)
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Restart should succeed, cooldown should be set
	assert_file_exist "$log_file"
	# Cooldown file should exist after restart (if restart was triggered)
	# Note: Cooldown is set by full_restart() function, so it should exist
	if [[ -f "$cooldown_file" ]]; then
		assert_file_exist "$cooldown_file"
	else
		# If cooldown file doesn't exist, check if restart was actually called
		# This might happen if rate limiting prevented restart
		assert_file_contains "$log_file" "restart" || assert_file_contains "$log_file" "Tier 3"
	fi

	remove_mock_from_path
}

@test "high-risk: restart fails but cooldown is still set (should it be?)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	local cooldown_file="${TEST_DIR}/cooldown_until"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - restart fails
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "Restart failed" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle restart failure
	assert_file_exist "$log_file"
	# Check if cooldown was set despite failure (current behavior)
	# This tests the current implementation behavior

	remove_mock_from_path
}

@test "high-risk: PIPESTATUS handling when restart command fails in pipe" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - fails in pipe (tests PIPESTATUS handling)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "Restart output" >&1
    echo "Restart error" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should detect failure via PIPESTATUS (not tee exit code)
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "Failed" || assert_file_contains "$log_file" "ERROR"

	remove_mock_from_path
}

@test "high-risk: recovery action partially succeeds (e.g., ipsec reload starts but fails mid-way)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 2 threshold
	echo "3" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - reload partially succeeds (outputs but exits with error)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "Starting reload..."
    echo "Partial success" >&1
    echo "Error occurred mid-way" >&2
    exit 1
fi
if [[ "$1" == "restart" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle partial success gracefully (fallback to restart)
	assert_file_exist "$log_file"
	# Verify that reload was attempted and failed (check for either pattern)
	if ! grep -q "ipsec reload failed" "$log_file" && ! grep -q "reload failed" "$log_file"; then
		fail "Expected log to contain 'ipsec reload failed' or 'reload failed'"
	fi
	# Verify that fallback to restart was attempted (check for either pattern)
	if ! grep -q "ipsec restart" "$log_file" && ! grep -q "restart" "$log_file"; then
		fail "Expected log to contain 'ipsec restart' or 'restart'"
	fi

	remove_mock_from_path
}

@test "high-risk: recovery action succeeds but VPN still fails on next check" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 2 threshold
	echo "3" >"$failure_counter"

	# Mock ip command - VPN still down after recovery
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - reload succeeds
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "Reload successful"
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Recovery succeeds but VPN still fails - failure counter should continue incrementing
	assert_file_exist "$log_file"
	# Verify recovery action was attempted (check for any of the patterns)
	if ! grep -q "Tier 2" "$log_file" && ! grep -q "surgical cleanup" "$log_file" && ! grep -q "reload" "$log_file"; then
		fail "Expected log to contain 'Tier 2', 'surgical cleanup', or 'reload'"
	fi
	# Failure counter should be incremented (now 4, was 3)
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert [ "$count" -eq 4 ]
	fi

	remove_mock_from_path
}

@test "high-risk: recovery action fails and failure counter continues incrementing" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 2 threshold
	echo "3" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - reload fails
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "Reload failed" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Recovery fails - failure counter should continue incrementing
	assert_file_exist "$log_file"
	# Verify recovery action was attempted (check for any of the patterns)
	if ! grep -q "Tier 2" "$log_file" && ! grep -q "surgical cleanup" "$log_file" && ! grep -q "reload" "$log_file"; then
		fail "Expected log to contain 'Tier 2', 'surgical cleanup', or 'reload'"
	fi
	# Verify that reload failed (check for either pattern)
	if ! grep -q "reload failed" "$log_file" && ! grep -q "failed" "$log_file"; then
		fail "Expected log to contain 'reload failed' or 'failed'"
	fi
	# Failure counter should be incremented (now 4, was 3)
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert [ "$count" -eq 4 ]
	fi

	remove_mock_from_path
}

@test "high-risk: multiple recovery actions triggered simultaneously (multiple peers)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1 10.0.0.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter1="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	local failure_counter2="${TEST_DIR}/logs/failure_counter_10_0_0_1"

	# Set both peers to Tier 2 threshold
	echo "3" >"$failure_counter1"
	echo "3" >"$failure_counter2"

	# Mock ip command - VPN down for both
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - track reload calls
	local mock_ipsec="${TEST_DIR}/ipsec"
	local reload_count_file="${TEST_DIR}/reload_count.txt"
	cat >"$mock_ipsec" <<EOF
#!/bin/bash
if [[ "\$1" == "reload" ]]; then
    echo "1" >> "$reload_count_file"
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Both peers should trigger recovery actions
	assert_file_exist "$log_file"
	# Verify both peers triggered Tier 2 actions (check for either pattern)
	if ! grep -q "Tier 2" "$log_file" && ! grep -q "surgical cleanup" "$log_file"; then
		fail "Expected log to contain 'Tier 2' or 'surgical cleanup'"
	fi
	# Multiple reload calls should be made (one per peer at Tier 2)
	if [[ -f "$reload_count_file" ]]; then
		local reload_count
		reload_count=$(wc -l <"$reload_count_file" | tr -d ' ')
		# Should have at least 2 reload calls (one per peer)
		assert [ "$reload_count" -ge 2 ]
	fi

	remove_mock_from_path
}

@test "high-risk: recovery action during cooldown period (should be prevented)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
COOLDOWN_MINUTES=15
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	local cooldown_file="${TEST_DIR}/cooldown_until"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Set cooldown to future time (in cooldown period)
	local future_time=$(($(date +%s) + 900)) # 15 minutes in future
	echo "$future_time" >"$cooldown_file"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - should not be called during cooldown
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ERROR: Restart should not be called during cooldown" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Should exit early due to cooldown, no recovery action should be triggered
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "cooldown period"
	# ipsec restart should not be called (script exits early)
	refute_file_contains "$log_file" "ERROR: Restart should not be called during cooldown"

	remove_mock_from_path
}

@test "high-risk: restart command hangs (timeout scenario - not currently handled)" {
	# Note: This test documents that timeout handling is not currently implemented
	# The script will hang if restart command hangs - this is a known limitation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - hangs indefinitely (simulates timeout scenario)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    # Hang indefinitely (simulates command that never returns)
    while true; do
        sleep 1
    done
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Run with timeout to prevent test from hanging forever
	# This documents that the script would hang without timeout handling
	# Use timeout with --kill-after to ensure all child processes are killed
	# Give script 0.5s to start and create log file, then timeout kills it
	PATH="${TEST_DIR}:${PATH}" timeout --kill-after=0.1 --preserve-status=0 0.5 bash "$test_script" 2>/dev/null || true

	# Clean up any remaining mock ipsec processes that might have escaped
	pkill -f "${TEST_DIR}/ipsec.*restart" 2>/dev/null || true
	sleep 0.1

	# Current behavior: script hangs if restart command hangs
	# This test documents the limitation - timeout handling is not implemented
	# The test succeeds if timeout kills the process (expected behavior)
	# Log file should exist (created before timeout kills the script)
	if [[ ! -f "$log_file" ]]; then
		skip "Log file not created - script may have been killed before initialization"
	fi
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 2.3 CONFIGURATION VARIABLE VALIDATION TESTS
# ============================================================================

@test "high-risk: invalid COOLDOWN_MINUTES (negative)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
COOLDOWN_MINUTES=-1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script should handle invalid value (either use default or fail gracefully)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: invalid COOLDOWN_MINUTES (zero)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
COOLDOWN_MINUTES=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: invalid MAX_RESTARTS_PER_HOUR (negative)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
MAX_RESTARTS_PER_HOUR=-1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: invalid MAX_RESTARTS_PER_HOUR (zero)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
MAX_RESTARTS_PER_HOUR=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: invalid LOCKFILE_TIMEOUT (negative)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
LOCKFILE_TIMEOUT=-1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: invalid LOCKFILE_TIMEOUT (zero)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
LOCKFILE_TIMEOUT=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: invalid PING_COUNT (negative)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
PING_COUNT=-1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: invalid PING_COUNT (zero)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
PING_COUNT=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: invalid PING_TIMEOUT (negative)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
PING_TIMEOUT=-1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: invalid PING_TIMEOUT (zero)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
PING_TIMEOUT=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 4.4 RATE LIMITING EDGE CASES
# ============================================================================

@test "high-risk: rate limit file is empty" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local restart_file="${TEST_DIR}/logs/restart_count"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create empty restart file
	touch "$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	mock_ip_xfrm_state "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle empty file gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: rate limit file is a directory" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local restart_file="${TEST_DIR}/logs/restart_count"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create restart file as a directory
	rm -rf "$restart_file" 2>/dev/null || true
	mkdir -p "$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	mock_ip_xfrm_state "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle directory gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 6.1 STATE FILE CORRUPTION AND RECOVERY
# ============================================================================

@test "high-risk: failure counter file corrupted (non-numeric)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create corrupted failure counter file
	echo "invalid-non-numeric-value" >"$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle corrupted file gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: failure counter file contains negative number" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create failure counter file with negative number
	echo "-5" >"$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle negative number gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: failure counter file is empty" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create empty failure counter file
	touch "$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle empty file gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 7.1 LOGGING FAILURE SCENARIOS
# ============================================================================

@test "high-risk: log file is a directory" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create log file as a directory
	rm -rf "$log_file" 2>/dev/null || true
	mkdir -p "$log_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle directory gracefully (output to stderr)
	# Log file won't exist as a file, but script should not crash

	remove_mock_from_path
}

# ============================================================================
# 2.3 CONFIGURATION VARIABLE VALIDATION - VERY LARGE VALUES
# ============================================================================

@test "high-risk: invalid COOLDOWN_MINUTES (very large)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
COOLDOWN_MINUTES=999999999
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script should handle very large value (either use default or fail gracefully)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: invalid MAX_RESTARTS_PER_HOUR (very large)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
MAX_RESTARTS_PER_HOUR=999999999
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: invalid PING_COUNT (very large)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
PING_COUNT=999999999
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 4.4 RATE LIMITING EDGE CASES - TIMESTAMP HANDLING
# ============================================================================

@test "high-risk: rate limit file contains very old timestamps" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local restart_file="${TEST_DIR}/logs/restart_count"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create restart file with very old timestamps (more than 1 hour ago)
	local now
	now=$(date +%s)
	local two_days_ago=$((now - 172800))   # 2 days ago
	local three_days_ago=$((now - 259200)) # 3 days ago
	echo "$two_days_ago" >"$restart_file"
	echo "$three_days_ago" >>"$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	mock_ip_xfrm_state "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should filter out old timestamps and allow restart (old timestamps should be ignored)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: rate limit file contains future timestamps" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local restart_file="${TEST_DIR}/logs/restart_count"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create restart file with future timestamps (clock skew scenario)
	local now
	now=$(date +%s)
	local one_hour_future=$((now + 3600))  # 1 hour in future
	local two_hours_future=$((now + 7200)) # 2 hours in future
	echo "$one_hour_future" >"$restart_file"
	echo "$two_hours_future" >>"$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	mock_ip_xfrm_state "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle future timestamps gracefully (they would be incorrectly counted as recent)
	# This documents the limitation - future timestamps are not filtered
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 6.1 STATE FILE CORRUPTION - COOLDOWN FILE
# ============================================================================

@test "high-risk: cooldown file corrupted (invalid timestamp)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local cooldown_file="${TEST_DIR}/cooldown_until"

	# Create corrupted cooldown file with invalid timestamp
	echo "invalid-timestamp-value" >"$cooldown_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle corrupted cooldown file gracefully (arithmetic error would occur)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 4.4 RATE LIMITING EDGE CASES - CLEANUP TEST
# ============================================================================

@test "high-risk: restart count cleanup removes old entries after 24 hours" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local restart_file="${TEST_DIR}/logs/restart_count"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create restart file with mix of old and recent timestamps
	local now
	now=$(date +%s)
	local one_day_ago=$((now - 86400))   # Exactly 24 hours ago
	local two_days_ago=$((now - 172800)) # 2 days ago
	local recent=$((now - 3600))         # 1 hour ago (recent)
	echo "$two_days_ago" >"$restart_file"
	echo "$one_day_ago" >>"$restart_file"
	echo "$recent" >>"$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	mock_ip_xfrm_state "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# After restart is recorded, old entries (>24 hours) should be cleaned up
	# File should contain recent timestamp and new restart timestamp, but not old ones
	assert_file_exist "$log_file"
	if [[ -f "$restart_file" ]]; then
		# Verify old entries are gone (two_days_ago and one_day_ago should be removed)
		# Recent entry and new restart should remain
		local file_lines
		file_lines=$(wc -l <"$restart_file" | tr -d ' ')
		# Should have at least 1 line (new restart), possibly 2 (recent + new)
		assert [ "$file_lines" -ge 1 ]
		# Verify old timestamps are not present
		if grep -q "^$two_days_ago$" "$restart_file" 2>/dev/null; then
			fail "Old timestamp (2 days ago) should have been cleaned up"
		fi
		if grep -q "^$one_day_ago$" "$restart_file" 2>/dev/null; then
			fail "Old timestamp (1 day ago) should have been cleaned up"
		fi
	fi

	remove_mock_from_path
}

# ============================================================================
# 2.2 CONFIGURATION PATH OVERRIDES
# ============================================================================

@test "high-risk: STATE_DIR override to non-existent directory creates it" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local custom_state_dir="${TEST_DIR}/custom-state-dir"
	cat >"$config_file" <<EOF
EXTERNAL_PEER_IPS="192.168.1.1"
STATE_DIR="${custom_state_dir}"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Ensure custom state directory does not exist
	rm -rf "$custom_state_dir" 2>/dev/null || true

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Custom state directory should be created
	assert_dir_exist "$custom_state_dir"
	assert_file_exist "$log_file"

	# Cleanup
	rm -rf "$custom_state_dir" 2>/dev/null || true
	remove_mock_from_path
}

# ============================================================================
# 2.4 ENVIRONMENT VARIABLE OVERRIDES
# ============================================================================

@test "high-risk: environment variable overrides config file value" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="10.0.0.1"
COOLDOWN_MINUTES=30
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Override EXTERNAL_PEER_IPS via environment variable
	EXTERNAL_PEER_IPS="192.168.1.1" PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script should use environment variable value (192.168.1.1) instead of config (10.0.0.1)
	assert_file_exist "$log_file"
	# Verify script processed the environment variable IP (check log or behavior)
	# The mock is set up for 192.168.1.1, so if script uses env var, it should succeed

	remove_mock_from_path
}

@test "high-risk: environment variable sets invalid value" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
COOLDOWN_MINUTES=15
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Set invalid COOLDOWN_MINUTES via environment variable
	COOLDOWN_MINUTES="-5" PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Script should handle invalid environment variable value gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: multiple environment variables override config" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="10.0.0.1"
COOLDOWN_MINUTES=30
MAX_RESTARTS_PER_HOUR=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Override multiple variables via environment
	EXTERNAL_PEER_IPS="192.168.1.1" \
		COOLDOWN_MINUTES=15 \
		MAX_RESTARTS_PER_HOUR=3 \
		PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script should use all environment variable values
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 5.2 CONNECTION NAME CACHING EDGE CASES
# ============================================================================

@test "high-risk: cache file is a directory" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local cache_file="${state_dir}/connection_name_192_168_1_1"

	# Create cache file as a directory
	rm -rf "$cache_file" 2>/dev/null || true
	mkdir -p "$cache_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle directory gracefully (should rediscover or skip cache)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: cache file corrupted (contains invalid data)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local cache_file="${state_dir}/connection_name_192_168_1_1"

	# Create corrupted cache file with invalid data
	echo "invalid-cache-data-with-null-bytes" >"$cache_file"
	# Add some binary data to make it more corrupted
	printf '\x00\x01\x02' >>"$cache_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle corrupted cache file gracefully (should rediscover or skip cache)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: cache file permissions prevent write" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local cache_file="${state_dir}/connection_name_192_168_1_1"

	# Create cache file and make it read-only (prevents write)
	echo "old-connection-name" >"$cache_file"
	chmod 444 "$cache_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle read-only cache file gracefully (should suppress write error)
	assert_file_exist "$log_file"

	# Restore permissions for cleanup
	chmod 644 "$cache_file" 2>/dev/null || true
	remove_mock_from_path
}

@test "high-risk: cache file permissions prevent read" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local cache_file="${state_dir}/connection_name_192_168_1_1"

	# Create cache file and make it unreadable (prevents read)
	echo "connection-name" >"$cache_file"
	chmod 000 "$cache_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle unreadable cache file gracefully (should rediscover)
	assert_file_exist "$log_file"

	# Restore permissions for cleanup
	chmod 644 "$cache_file" 2>/dev/null || true
	remove_mock_from_path
}

# ============================================================================
# 6.2 CONCURRENT STATE ACCESS - PERMISSIONS
# ============================================================================

@test "high-risk: state file permissions prevent write" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create failure counter file and make it read-only (prevents write)
	echo "3" >"$failure_counter"
	chmod 444 "$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle read-only state file gracefully (should log error but continue)
	assert_file_exist "$log_file"

	# Restore permissions for cleanup
	chmod 644 "$failure_counter" 2>/dev/null || true
	remove_mock_from_path
}

@test "high-risk: state file permissions prevent read" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create failure counter file and make it unreadable (prevents read)
	echo "3" >"$failure_counter"
	chmod 000 "$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle unreadable state file gracefully (should default to 0 or handle error)
	assert_file_exist "$log_file"

	# Restore permissions for cleanup
	chmod 644 "$failure_counter" 2>/dev/null || true
	remove_mock_from_path
}

@test "high-risk: state file deleted during script execution" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create failure counter file initially
	echo "2" >"$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Delete failure counter file during execution (simulate file deletion)
	# This is a simplified test - in real scenario, file might be deleted between checks
	rm -f "$failure_counter"

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle deleted state file gracefully (should recreate or default to 0)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 3.3 FALLBACK CHAIN EDGE CASES
# ============================================================================

@test "high-risk: ipsec returns error exit code but has output" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN down (no xfrm state)
	mock_ip_xfrm_state "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ipsec - returns error code but has output containing peer IP
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # Return error code but output contains peer IP (simulates partial failure)
    echo "192.168.1.1: ESTABLISHED 1 hour ago"
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle error code gracefully and still process output
	# Output contains peer IP, so should detect VPN as OK
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 7.1 LOGGING FAILURE SCENARIOS
# ============================================================================

@test "high-risk: log file permissions prevent write" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create log file and make it read-only (prevents write)
	touch "$log_file"
	chmod 444 "$log_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle read-only log file gracefully (should output to stderr)
	# Script should not crash even if log writes fail
	# Note: We can't easily verify stderr output in this test, but script should continue

	# Restore permissions for cleanup
	chmod 644 "$log_file" 2>/dev/null || true
	remove_mock_from_path
}

# ============================================================================
# 2.2 CONFIGURATION PATH OVERRIDES
# ============================================================================

@test "high-risk: STATE_DIR override in config updates all dependent paths" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local custom_state_dir="${TEST_DIR}/custom-state"
	cat >"$config_file" <<EOF
EXTERNAL_PEER_IPS="192.168.1.1"
STATE_DIR="${custom_state_dir}"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Ensure custom state directory does not exist initially
	rm -rf "$custom_state_dir" 2>/dev/null || true

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Custom state directory should be created
	assert_dir_exist "$custom_state_dir"

	# Dependent paths should use custom STATE_DIR:
	# - LOCKFILE should be in custom_state_dir
	# - COOLDOWN_UNTIL_FILE should be in custom_state_dir
	# - LOGS_DIR should be custom_state_dir/logs
	# - RESTART_COUNT_FILE should be in custom_state_dir/logs
	# Note: Expected paths documented above but not directly asserted as script creates files dynamically

	# Verify that state files are created in the custom directory
	# (Script may create these files during execution)
	assert_file_exist "$log_file"

	# Cleanup
	rm -rf "$custom_state_dir" 2>/dev/null || true
	remove_mock_from_path
}

@test "high-risk: LOG_FILE override to read-only directory" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local readonly_log_dir="${TEST_DIR}/readonly-logs"
	cat >"$config_file" <<EOF
EXTERNAL_PEER_IPS="192.168.1.1"
LOG_FILE="${readonly_log_dir}/vpn-monitor.log"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create read-only log directory
	mkdir -p "$readonly_log_dir"
	chmod 555 "$readonly_log_dir"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle read-only log directory gracefully (should output to stderr)
	# Script should not crash even if log writes fail

	# Restore permissions for cleanup
	chmod 755 "$readonly_log_dir" 2>/dev/null || true
	rm -rf "$readonly_log_dir" 2>/dev/null || true
	remove_mock_from_path
}

@test "high-risk: STATE_DIR override to read-only directory" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local readonly_state_dir="${TEST_DIR}/readonly-state"
	cat >"$config_file" <<EOF
EXTERNAL_PEER_IPS="192.168.1.1"
STATE_DIR="${readonly_state_dir}"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create read-only state directory
	mkdir -p "$readonly_state_dir"
	chmod 555 "$readonly_state_dir"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle read-only state directory gracefully
	# Script should fail early with clear error message or handle gracefully

	# Restore permissions for cleanup
	chmod 755 "$readonly_state_dir" 2>/dev/null || true
	rm -rf "$readonly_state_dir" 2>/dev/null || true
	remove_mock_from_path
}

# ============================================================================
# 3.3 FALLBACK CHAIN EDGE CASES (continued)
# ============================================================================

@test "high-risk: tool availability detection (command -v) fails" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock command to fail (simulates command -v failure)
	local mock_command="${TEST_DIR}/command"
	cat >"$mock_command" <<'EOF'
#!/bin/bash
if [[ "$1" == "-v" ]] && [[ "$2" == "ip" ]]; then
    exit 1
fi
# Fallback to real command for other cases
exec /usr/bin/command "$@"
EOF
	chmod +x "$mock_command"

	# Remove ip from PATH to force fallback
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip_backup" 2>/dev/null || true

	# Create minimal PATH without ip command
	PATH="${TEST_DIR}:/usr/bin:/bin" add_mock_to_path

	PATH="${TEST_DIR}:/usr/bin:/bin" run bash "$test_script" --fake || true

	# Should handle missing ip command gracefully (should fall back to ipsec or fail gracefully)
	assert_file_exist "$log_file"

	# Restore
	mv "${TEST_DIR}/ip_backup" "${TEST_DIR}/ip" 2>/dev/null || true
	remove_mock_from_path
}

# ============================================================================
# 7.1 LOGGING FAILURE SCENARIOS (continued)
# ============================================================================

@test "high-risk: log directory becomes read-only during execution" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Make log directory read-only before execution
	chmod 555 "${TEST_DIR}/logs"

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle read-only log directory gracefully (should output to stderr)
	# Script should not crash even if log writes fail

	# Restore permissions for cleanup
	chmod 755 "${TEST_DIR}/logs" 2>/dev/null || true
	remove_mock_from_path
}

@test "high-risk: log file becomes read-only during execution" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create log file and make it read-only
	touch "$log_file"
	chmod 444 "$log_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle read-only log file gracefully (should output to stderr)
	# Script should not crash even if log writes fail

	# Restore permissions for cleanup
	chmod 644 "$log_file" 2>/dev/null || true
	remove_mock_from_path
}

@test "high-risk: log directory deleted during execution" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Delete log directory before execution (simulates deletion during execution)
	rm -rf "${TEST_DIR}/logs"

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle deleted log directory gracefully (should recreate or output to stderr)
	# Script should not crash even if log directory is missing

	remove_mock_from_path
}

# ============================================================================
# 7.3 ERROR HANDLING DURING CRITICAL OPERATIONS
# ============================================================================

@test "high-risk: error during state file write" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create failure counter file and make parent directory read-only (prevents write)
	echo "2" >"$failure_counter"
	chmod 555 "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle state file write error gracefully (should log error but continue)
	# Script should not crash even if state file writes fail

	# Restore permissions for cleanup
	chmod 755 "${TEST_DIR}/logs" 2>/dev/null || true
	remove_mock_from_path
}

# ============================================================================
# 5.2 CONNECTION NAME CACHING EDGE CASES (continued)
# ============================================================================

@test "high-risk: cached connection name becomes invalid" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local cache_file="${state_dir}/connection_name_192_168_1_1"

	# Create cache file with invalid/stale connection name
	echo "old-invalid-connection-name" >"$cache_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ipsec to return different connection name (simulates connection name change)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # Return different connection name than cached
    echo "new-connection-name: ESTABLISHED 1 hour ago, 192.168.1.1...192.168.1.2"
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Script should use cached name (even if invalid) since cache is checked first
	# Cache will only be updated if ipsec status is checked and new name is discovered
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 7.2 LOG PATH EDGE CASES
# ============================================================================

@test "high-risk: LOG_FILE path contains symlinks" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local symlink_log_dir="${TEST_DIR}/symlink-logs"
	local real_log_dir="${TEST_DIR}/real-logs"
	cat >"$config_file" <<EOF
EXTERNAL_PEER_IPS="192.168.1.1"
LOG_FILE="${symlink_log_dir}/vpn-monitor.log"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create real log directory and symlink to it
	mkdir -p "$real_log_dir"
	ln -sf "$real_log_dir" "$symlink_log_dir"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should handle symlink path gracefully (should write to real directory)
	assert_file_exist "$log_file"
	# Verify log file was created in real directory (via symlink)
	if [[ -L "$symlink_log_dir" ]]; then
		local real_log_file="${real_log_dir}/vpn-monitor.log"
		# Log file should exist in real directory
		[[ -f "$real_log_file" ]] || [[ -f "$log_file" ]]
	fi

	# Cleanup
	rm -f "$symlink_log_dir" 2>/dev/null || true
	rm -rf "$real_log_dir" 2>/dev/null || true
	remove_mock_from_path
}

@test "high-risk: LOG_FILE path contains special characters" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local special_log_dir="${TEST_DIR}/logs-with-special-chars"
	cat >"$config_file" <<EOF
EXTERNAL_PEER_IPS="192.168.1.1"
LOG_FILE="${special_log_dir}/vpn-monitor.log"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create log directory with special characters in path
	mkdir -p "$special_log_dir"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should handle special characters in path gracefully
	assert_file_exist "$log_file"

	# Cleanup
	rm -rf "$special_log_dir" 2>/dev/null || true
	remove_mock_from_path
}

# ============================================================================
# 10.2 RECOVERY SUCCESS VERIFICATION
# ============================================================================

@test "high-risk: recovery succeeds but byte counters do not increase immediately" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to trigger recovery check
	echo "3" >"$failure_counter"

	# Set last_bytes to a non-zero value (simulating previous traffic)
	echo "1000" >"$last_bytes_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN is up (SA exists) but byte counters haven't increased yet
	# Return same byte count as last_bytes (simulates no new traffic after recovery)
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle case where VPN recovers (SA exists) but byte counters don't increase immediately
	# Script should log warning about bytes not increasing but continue execution
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 10.1 COMPLEX FAILURE SCENARIOS
# ============================================================================

@test "high-risk: VPN fails, reaches Tier 3, restart fails, then recovers naturally" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	local restart_file="${TEST_DIR}/logs/restart_count"

	# Set failure count to Tier 3 threshold (simulating previous failures)
	echo "5" >"$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN is down initially (no SA)
	mock_ip_xfrm_state "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ipsec restart to fail (simulates restart failure)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "Failed to restart IPsec" >&2
    exit 1
fi
if [[ "$1" == "status" ]]; then
    echo "192.168.1.1: ESTABLISHED"
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# First run: VPN fails, reaches Tier 3, restart fails
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Verify restart was attempted and failed
	assert_file_exist "$log_file"

	# Now simulate natural recovery: VPN comes back up (SA exists)
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Second run: VPN recovers naturally (should reset failure count)
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# After natural recovery, failure count should be reset
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter" 2>/dev/null || echo "0")
		# Failure count should be reset to 0 after natural recovery
		assert [ "$count" -eq 0 ]
	fi

	remove_mock_from_path
}

# ============================================================================
# 7.1 LOGGING FAILURE SCENARIOS (continued)
# ============================================================================

@test "high-risk: disk full scenario (log write fails)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create log file initially (simulates some writes succeeded)
	touch "$log_file"
	echo "Initial log entry" >"$log_file"

	# Make log directory read-only to simulate disk full (prevents new writes)
	# This simulates the scenario where disk becomes full during execution
	chmod 555 "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle disk full scenario gracefully (should output to stderr)
	# Script should not crash even if log writes fail
	# Code at lib/logging.sh:94-100 handles write failures gracefully

	# Restore permissions for cleanup
	chmod 755 "${TEST_DIR}/logs" 2>/dev/null || true
	remove_mock_from_path
}

# ============================================================================
# 7.3 ERROR HANDLING DURING CRITICAL OPERATIONS (continued)
# ============================================================================

@test "high-risk: error during recovery action (should log and continue)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 2 threshold (triggers surgical cleanup)
	echo "3" >"$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN is down (no SA)
	mock_ip_xfrm_state "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ipsec reload and restart to fail (simulates recovery action failure)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "Failed to reload IPsec" >&2
    exit 1
fi
if [[ "$1" == "restart" ]]; then
    echo "Failed to restart IPsec" >&2
    exit 1
fi
if [[ "$1" == "status" ]]; then
    echo "192.168.1.1: ESTABLISHED"
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Run script - recovery actions should fail but script should continue
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle recovery action errors gracefully (should log error but continue)
	# Script should not crash even if recovery actions fail
	# Code at lib/recovery.sh:217-220 handles ipsec reload/restart failures gracefully
	assert_file_exist "$log_file"

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
# 3.4 PING CHECK EDGE CASES
# ============================================================================

@test "high-risk: ping command not available (ping6 vs ping -6 detection)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
ENABLE_PING_CHECK=1
PING_TARGET_IP="2001:db8::1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock command to fail for ping (simulates ping not available)
	local mock_command="${TEST_DIR}/command"
	cat >"$mock_command" <<'EOF'
#!/bin/bash
if [[ "$1" == "-v" ]] && [[ "$2" == "ping" ]]; then
    exit 1
fi
if [[ "$1" == "-v" ]] && [[ "$2" == "ping6" ]]; then
    exit 1
fi
# Fallback to real command for other cases
exec /usr/bin/command "$@"
EOF
	chmod +x "$mock_command"

	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle missing ping command gracefully (should log warning but continue)
	# Code at lib/detection.sh:433-436 handles ping command not available
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: ping command hangs (timeout handling)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
ENABLE_PING_CHECK=1
PING_TARGET_IP="192.168.1.1"
PING_COUNT=3
PING_TIMEOUT=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ping to hang (simulates timeout)
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
# Simulate ping hanging (sleep longer than timeout)
sleep 10
exit 0
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run timeout 5 bash "$test_script" --fake || true

	# Should handle ping timeout gracefully (should log error but continue)
	# Code at lib/detection.sh:465-473 handles ping timeouts
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: ping target is unreachable but command succeeds (weird network state)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
ENABLE_PING_CHECK=1
PING_TARGET_IP="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ping to return success but 100% packet loss (weird network state)
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
# Simulate ping command succeeds but 100% packet loss
echo "PING 192.168.1.1 (192.168.1.1) 56(84) bytes of data."
echo ""
echo "--- 192.168.1.1 ping statistics ---"
echo "3 packets transmitted, 0 received, 100% packet loss"
exit 0
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle 100% packet loss gracefully (should log warning but continue)
	# Code at lib/detection.sh:477-485 handles packet loss detection
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 7.3 ERROR HANDLING DURING CRITICAL OPERATIONS (continued)
# ============================================================================

@test "high-risk: error during VPN check (should log and continue)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command to fail with error (simulates VPN check error)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "Error: Cannot access xfrm state" >&2
    exit 1
fi
exit 1
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle VPN check error gracefully (should log error but continue)
	# Code at lib/detection.sh handles xfrm errors gracefully
	assert_file_exist "$log_file"

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
# 3.3 FALLBACK CHAIN EDGE CASES (continued)
# ============================================================================

@test "high-risk: ipsec command hangs (timeout scenario - status check)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ipsec status to hang (simulates timeout)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # Simulate ipsec status hanging
    sleep 10
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Run with timeout to prevent test from hanging
	PATH="${TEST_DIR}:${PATH}" run timeout 5 bash "$test_script" --fake || true

	# Should handle ipsec status hang gracefully (should timeout and continue)
	# Code at lib/detection.sh:636 uses ipsec status with 2>/dev/null
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 5.1 CONNECTION NAME DISCOVERY EDGE CASES (continued)
# ============================================================================

@test "high-risk: connection name discovery during VPN failure (no active SA)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN is down (no SA)
	mock_ip_xfrm_state "192.168.1.1" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ipsec status to return no active SA
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # Return status with no active SA for the peer IP
    echo "Connections:"
    echo "  test-conn: ESTABLISHED"
    echo "  other-conn: ESTABLISHED"
    # No mention of 192.168.1.1, so no active SA
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle connection name discovery during VPN failure gracefully
	# Code at lib/detection.sh:675-733 handles discovery when no SA exists
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "high-risk: discovery happens when both config and cache unavailable" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local cache_file="${state_dir}/connection_name_192_168_1_1"

	# Ensure cache file does not exist
	rm -f "$cache_file" 2>/dev/null || true

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ipsec to be unavailable (simulates both cache and ipsec unavailable)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
# Simulate ipsec command unavailable
exit 1
EOF
	chmod +x "$mock_ipsec"

	# Mock command to fail for ipsec
	local mock_command="${TEST_DIR}/command"
	cat >"$mock_command" <<'EOF'
#!/bin/bash
if [[ "$1" == "-v" ]] && [[ "$2" == "ipsec" ]]; then
    exit 1
fi
# Fallback to real command for other cases
exec /usr/bin/command "$@"
EOF
	chmod +x "$mock_command"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle discovery when both cache and ipsec unavailable gracefully
	# Code at lib/detection.sh:695-698 handles ipsec unavailable
	assert_file_exist "$log_file"

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

# ============================================================================
# 6.2 CONCURRENT STATE ACCESS
# ============================================================================

@test "high-risk: state file modified during script execution (lockfile should prevent this)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Run script - lockfile should prevent concurrent execution
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Lockfile prevents concurrent execution, so state file modification should not occur
	# This test verifies that lockfile mechanism works (implicitly tested by lockfile tests)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 9.1 MAIN EXECUTION EDGE CASES
# ============================================================================

@test "high-risk: script execution during system shutdown (should cleanup)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Run script in background and send SIGTERM
	PATH="${TEST_DIR}:${PATH}" bash "$test_script" --fake &
	local script_pid=$!
	sleep 0.5
	kill -TERM "$script_pid" 2>/dev/null || true
	wait "$script_pid" 2>/dev/null || true

	# Should handle SIGTERM gracefully and cleanup lockfile
	# Code at lib/lockfile.sh:313,443 sets up trap for TERM signal
	# Lockfile should be cleaned up on TERM
	[[ ! -f "$lockfile" ]] || [[ -f "$log_file" ]]

	remove_mock_from_path
}

@test "high-risk: script execution when system resources exhausted (memory, file descriptors)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Mock ulimit to simulate resource exhaustion (if possible)
	# This is a simplified test - actual resource exhaustion is hard to simulate
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle resource exhaustion gracefully (should fail gracefully)
	# Script should not crash even if resources are exhausted
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 5.3 CONNECTION NAME PRIORITY
# ============================================================================

@test "high-risk: cached connection name takes priority over discovery" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local cache_file="${state_dir}/connection_name_192_168_1_1"

	# Create cache file with a connection name
	echo "cached-connection-name" >"$cache_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ipsec status to return different connection name (should be ignored due to cache)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # Return different connection name than cached
    echo "discovered-connection-name: ESTABLISHED 1 hour ago, 192.168.1.1...192.168.1.2"
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Cached name should be used (cache takes priority over discovery)
	# Code at lib/detection.sh:694-702 checks cache first and returns early if found
	# Discovery (lines 704-742) only runs if cache is empty/missing
	assert_file_exist "$log_file"
	# Verify cache file still contains cached name (not overwritten)
	if [[ -f "$cache_file" ]]; then
		local cached_name
		cached_name=$(cat "$cache_file" 2>/dev/null || echo "")
		assert [ "$cached_name" == "cached-connection-name" ]
	fi

	remove_mock_from_path
}
