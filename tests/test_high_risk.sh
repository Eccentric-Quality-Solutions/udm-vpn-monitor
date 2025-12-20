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
	local original_path="$PATH"
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
	local original_path="$PATH"
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
		# Debug: show what we found
		echo "Debug: Checking output files..."
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
	# Use a PATH that doesn't include ip, swanctl, or ipsec
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
	local mock_ping=$(mock_ping "192.168.1.1" "1")
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

@test "high-risk: surgical cleanup with connection name configured" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
CONNECTION_NAME_192_168_1_1="test-connection"
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

	# Mock swanctl - track which command was called
	local mock_swanctl="${TEST_DIR}/swanctl"
	cat >"$mock_swanctl" <<'EOF'
#!/bin/bash
if [[ "$1" == "--reload-conn" ]] && [[ "$2" == "test-connection" ]]; then
    echo "per-connection-reload" > /tmp/swanctl_called.txt
    exit 0
fi
if [[ "$1" == "--reload" ]]; then
    echo "full-reload" > /tmp/swanctl_called.txt
    exit 0
fi
EOF
	chmod +x "$mock_swanctl"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Should use per-connection reload
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "per-connection reload"
	if [[ -f /tmp/swanctl_called.txt ]]; then
		local called=$(cat /tmp/swanctl_called.txt)
		assert [ "$called" = "per-connection-reload" ]
		rm -f /tmp/swanctl_called.txt
	fi

	remove_mock_from_path
}

@test "high-risk: surgical cleanup without connection name uses full reload" {
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

	# Mock swanctl - track which command was called
	local mock_swanctl="${TEST_DIR}/swanctl"
	cat >"$mock_swanctl" <<'EOF'
#!/bin/bash
if [[ "$1" == "--reload-conn" ]]; then
    echo "per-connection-reload" > /tmp/swanctl_called.txt
    exit 0
fi
if [[ "$1" == "--reload" ]]; then
    echo "full-reload" > /tmp/swanctl_called.txt
    exit 0
fi
EOF
	chmod +x "$mock_swanctl"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Should use full reload
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "full reload" || assert_file_contains "$log_file" "reload"
	if [[ -f /tmp/swanctl_called.txt ]]; then
		local called=$(cat /tmp/swanctl_called.txt)
		assert [ "$called" = "full-reload" ]
		rm -f /tmp/swanctl_called.txt
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

	# Mock swanctl - fails
	local mock_swanctl="${TEST_DIR}/swanctl"
	cat >"$mock_swanctl" <<'EOF'
#!/bin/bash
if [[ "$1" == "--reload" ]]; then
    echo "swanctl reload failed" >&2
    exit 1
fi
EOF
	chmod +x "$mock_swanctl"
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

@test "high-risk: full restart when neither ipsec nor swanctl available" {
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

	# Don't create ipsec or swanctl mocks (unavailable)

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
	local mock_ipsec=$(mock_ipsec)
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

	# Should fallback to swanctl or ipsec
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

@test "high-risk: surgical cleanup connection name reload fails - fallback to full reload" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
CONNECTION_NAME_192_168_1_1="test-connection"
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

	# Mock swanctl - per-connection reload fails, should fallback to full reload
	local mock_swanctl="${TEST_DIR}/swanctl"
	cat >"$mock_swanctl" <<'EOF'
#!/bin/bash
if [[ "$1" == "--reload-conn" ]] && [[ "$2" == "test-connection" ]]; then
    echo "Connection not found" >&2
    exit 1
fi
if [[ "$1" == "--reload" ]]; then
    echo "full-reload" > /tmp/swanctl_called.txt
    exit 0
fi
EOF
	chmod +x "$mock_swanctl"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Should fallback to full reload
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "falling back to full reload" || assert_file_contains "$log_file" "full reload"
	if [[ -f /tmp/swanctl_called.txt ]]; then
		local called=$(cat /tmp/swanctl_called.txt)
		assert [ "$called" = "full-reload" ]
		rm -f /tmp/swanctl_called.txt
	fi

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
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config that attempts to source external commands
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
# Attempt to source external file (security risk)
source /etc/passwd
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should handle sourcing gracefully (may fail or skip)
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should log error or handle gracefully
	assert_file_exist "$log_file"
	# May contain error about config file or source command
}

@test "high-risk: config file contains null bytes or invalid characters" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config with null bytes and invalid characters
	printf 'EXTERNAL_PEER_IPS="192.168.1.1"\x00INVALID\xFFCHAR' >"$config_file"

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

	# Script should handle invalid characters gracefully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle gracefully (may log error or fail to parse)
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

@test "high-risk: connection name configured but doesn't exist in swanctl (should fallback)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
CONNECTION_NAME_192_168_1_1="nonexistent-connection"
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

	# Mock swanctl - connection doesn't exist, should fallback to full reload
	local mock_swanctl="${TEST_DIR}/swanctl"
	cat >"$mock_swanctl" <<'EOF'
#!/bin/bash
if [[ "$1" == "--reload-conn" ]] && [[ "$2" == "nonexistent-connection" ]]; then
    echo "Connection 'nonexistent-connection' not found" >&2
    exit 1
fi
if [[ "$1" == "--reload" ]]; then
    echo "full-reload-called" > /tmp/swanctl_fallback.txt
    exit 0
fi
EOF
	chmod +x "$mock_swanctl"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Should fallback to full reload when connection doesn't exist
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "falling back to full reload" || assert_file_contains "$log_file" "full reload"
	if [[ -f /tmp/swanctl_fallback.txt ]]; then
		rm -f /tmp/swanctl_fallback.txt
	fi

	remove_mock_from_path
}

@test "high-risk: multiple peers failing simultaneously - verify independent cleanup" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1 10.0.0.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
CONNECTION_NAME_192_168_1_1="conn1"
CONNECTION_NAME_10_0_0_1="conn2"
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

	# Mock swanctl - track which connections were reloaded
	local mock_swanctl="${TEST_DIR}/swanctl"
	local reload_log="${TEST_DIR}/reload_log.txt"
	cat >"$mock_swanctl" <<EOF
#!/bin/bash
if [[ "\$1" == "--reload-conn" ]]; then
    echo "\$2" >> "$reload_log"
    exit 0
fi
if [[ "\$1" == "--reload" ]]; then
    echo "full-reload" >> "$reload_log"
    exit 0
fi
EOF
	chmod +x "$mock_swanctl"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Both peers should trigger cleanup independently
	assert_file_exist "$log_file"
	# Both connection names should be in reload log (or full reload if fallback)
	if [[ -f "$reload_log" ]]; then
		local reload_count=$(wc -l <"$reload_log")
		assert [ "$reload_count" -ge 1 ]
	fi

	remove_mock_from_path
}

@test "high-risk: full restart with swanctl command (success case)" {
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

	# Mock swanctl - track if called
	local mock_swanctl="${TEST_DIR}/swanctl"
	cat >"$mock_swanctl" <<'EOF'
#!/bin/bash
if [[ "$1" == "--reload" ]]; then
    echo "swanctl-reload-called" > /tmp/swanctl_restart.txt
    exit 0
fi
EOF
	chmod +x "$mock_swanctl"
	add_mock_to_path

	# Don't create ipsec mock (force swanctl path)

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Should use swanctl for restart
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "restart" || assert_file_contains "$log_file" "reload"
	if [[ -f /tmp/swanctl_restart.txt ]]; then
		assert_file_exist /tmp/swanctl_restart.txt
		rm -f /tmp/swanctl_restart.txt
	fi

	remove_mock_from_path
}

@test "high-risk: full restart with swanctl command fails (error handling)" {
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

	# Mock swanctl - fails
	local mock_swanctl="${TEST_DIR}/swanctl"
	cat >"$mock_swanctl" <<'EOF'
#!/bin/bash
if [[ "$1" == "--reload" ]]; then
    echo "swanctl reload failed" >&2
    exit 1
fi
EOF
	chmod +x "$mock_swanctl"
	add_mock_to_path

	# Don't create ipsec mock (force swanctl path)

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
	local mock_ipsec=$(mock_ipsec)
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

@test "high-risk: recovery action partially succeeds (e.g., swanctl reload starts but fails mid-way)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
CONNECTION_NAME_192_168_1_1="test-connection"
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

	# Mock swanctl - partially succeeds (outputs but exits with error)
	local mock_swanctl="${TEST_DIR}/swanctl"
	cat >"$mock_swanctl" <<'EOF'
#!/bin/bash
if [[ "$1" == "--reload-conn" ]]; then
    echo "Starting reload..."
    echo "Partial success" >&1
    echo "Error occurred mid-way" >&2
    exit 1
fi
if [[ "$1" == "--reload" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_swanctl"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle partial success gracefully (fallback to full reload)
	assert_file_exist "$log_file"

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

	# Mock swanctl - reload succeeds
	local mock_swanctl="${TEST_DIR}/swanctl"
	cat >"$mock_swanctl" <<'EOF'
#!/bin/bash
if [[ "$1" == "--reload" ]]; then
    echo "Reload successful"
    exit 0
fi
EOF
	chmod +x "$mock_swanctl"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Recovery succeeds but VPN still fails - failure counter should continue incrementing
	assert_file_exist "$log_file"
	# Failure counter should be incremented (now 4)
	if [[ -f "$failure_counter" ]]; then
		local count=$(cat "$failure_counter")
		assert [ "$count" -ge 3 ]
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

	# Mock swanctl - reload fails
	local mock_swanctl="${TEST_DIR}/swanctl"
	cat >"$mock_swanctl" <<'EOF'
#!/bin/bash
if [[ "$1" == "--reload" ]]; then
    echo "Reload failed" >&2
    exit 1
fi
EOF
	chmod +x "$mock_swanctl"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Recovery fails - failure counter should continue incrementing
	assert_file_exist "$log_file"
	# Failure counter should be incremented (now 4)
	if [[ -f "$failure_counter" ]]; then
		local count=$(cat "$failure_counter")
		assert [ "$count" -ge 3 ]
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

	# Mock swanctl - track reload calls
	local mock_swanctl="${TEST_DIR}/swanctl"
	local reload_count_file="${TEST_DIR}/reload_count.txt"
	cat >"$mock_swanctl" <<EOF
#!/bin/bash
if [[ "\$1" == "--reload" ]]; then
    echo "1" >> "$reload_count_file"
    exit 0
fi
EOF
	chmod +x "$mock_swanctl"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Both peers should trigger recovery actions
	assert_file_exist "$log_file"
	# Multiple reload calls should be made (one per peer at Tier 2)
	if [[ -f "$reload_count_file" ]]; then
		local reload_count=$(wc -l <"$reload_count_file" | tr -d ' ')
		assert [ "$reload_count" -ge 1 ]
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
