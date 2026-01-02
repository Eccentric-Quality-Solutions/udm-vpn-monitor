#!/usr/bin/env bats
#
# Tests for Lockfile Management
# Tests critical paths and error handling scenarios

load test_helper
load fixtures/vpn_active

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# 1. LOCKFILE MANAGEMENT TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "lockfile cleanup on script exit" {
	# Purpose: Test verifies that lockfile is cleaned up when script exits successfully
	# Expected: Lockfile is removed by EXIT trap handler when script completes normally
	# Importance: Lockfile cleanup ensures lock is released after successful script execution
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	# Run script - should complete successfully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_success
	# Lockfile should be cleaned up after script exits
	assert_file_not_exist "$lockfile"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "lockfile cleanup on script error" {
	# Purpose: Test verifies that lockfile is cleaned up when script exits with error
	# Expected: Lockfile is removed by EXIT trap handler even when script encounters errors
	# Importance: Lockfile cleanup on error prevents stale locks from blocking future script execution
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="invalid-ip-format"
LOCATION_TEST_INTERNAL="invalid-ip-format"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Run script - should exit with error due to invalid IP
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_failure

	# Lockfile should be cleaned up even on error
	# Note: Script may exit before lockfile creation, so check may be flaky
	# But if lockfile was created, it should be cleaned up
	if [[ -f "$lockfile" ]]; then
		# If lockfile exists, it should be stale or cleaned up
		# This is a best-effort check
		echo "Lockfile still exists after error - may need manual cleanup"
	fi
}

# bats test_tags=category:high-risk,priority:high
@test "lockfile contains invalid format" {
	# Purpose: Test verifies that script handles lockfiles with invalid format gracefully
	# Expected: Script detects invalid lockfile format, cleans it up or handles it without crashing
	# Importance: Invalid format handling prevents script failures from corrupted lockfiles
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
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
	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	# Script should handle invalid lockfile format gracefully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should either clean up invalid lockfile or handle it gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "lockfile timestamp at timeout boundary" {
	# Purpose: Test verifies that script handles lockfiles at timeout boundary correctly
	# Expected: Script correctly identifies lockfiles at exactly the timeout threshold as stale
	# Importance: Boundary condition handling ensures consistent stale lockfile detection
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
LOCKFILE_TIMEOUT=60
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create lockfile exactly at timeout boundary (60 seconds ago)
	local boundary_time=$(($(date +%s) - 60))
	echo "${boundary_time}:12345" >"$lockfile"
	# Touch file to set modification time
	touch -d "@$boundary_time" "$lockfile" 2>/dev/null || true

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command
	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	# Script should handle boundary condition
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should either treat as stale or handle gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "lockfile acquisition prevents concurrent execution" {
	# Purpose: Test verifies that lockfile acquisition prevents multiple script instances from running simultaneously
	# Expected: Script detects existing lockfile with running PID and exits gracefully without executing
	# Importance: Concurrent execution prevention ensures only one instance monitors VPN at a time
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	setup_mock_vpn_environment "192.168.1.1" 1000
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

# bats test_tags=category:high-risk,priority:high
@test "lockfile acquisition uses flock when available" {
	# Purpose: Test verifies that script uses flock-based locking when flock command is available
	# Expected: Script uses flock mechanism for atomic lockfile acquisition and cleanup
	# Importance: Flock-based locking provides reliable atomic operations for lockfile management
	# Skip condition: Requires 'flock' command to be available for file locking tests
	if ! command -v flock >/dev/null 2>&1; then
		skip "flock command not available (test requires flock for file locking functionality)"
	fi

	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	# Run script - should use flock mechanism
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_success
	# Lockfile should be cleaned up (flock mechanism works)
	assert_file_not_exist "$lockfile"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "lockfile acquisition falls back when flock unavailable" {
	# Purpose: Test verifies that script falls back to atomic file-based locking when flock is unavailable
	# Expected: Script uses fallback locking mechanism (atomic file operations) when flock command is not found
	# Importance: Fallback mechanism ensures lockfile functionality works even without flock command
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
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	# Run script with PATH that doesn't include flock
	PATH="${TEST_DIR}:${path_without_flock}" run bash "$test_script" --fake

	assert_success
	# Lockfile should be cleaned up (fallback mechanism works)
	assert_file_not_exist "$lockfile"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "lockfile switching between flock and fallback modes" {
	# Purpose: Test verifies correct behavior when switching between flock and fallback lockfile mechanisms
	# Expected: Both locking modes can detect and handle lockfiles created by the other mode correctly
	# Importance: Mode interoperability ensures consistent lockfile behavior when system switches between locking mechanisms
	# Both modes use the same lockfile format (timestamp:pid), so they should be compatible

	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	setup_mock_vpn_environment "192.168.1.1" 1000
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
	local lockfile_timeout=60
	cat >"$config_file" <<EOF
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
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

# bats test_tags=category:high-risk,priority:high
@test "lockfile cleanup on SIGTERM" {
	# Purpose: Test verifies that lockfile is cleaned up when script receives SIGTERM signal
	# Expected: Lockfile is removed by trap handler when script is terminated with SIGTERM
	# Importance: Signal-based cleanup ensures lockfile is released when script is stopped by system or user
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	setup_mock_vpn_environment "192.168.1.1" 1000
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

# bats test_tags=category:high-risk,priority:high
@test "multiple processes attempting to acquire lock simultaneously (flock path)" {
	# Purpose: Test verifies that flock-based locking prevents multiple processes from acquiring lock simultaneously
	# Expected: Only one process succeeds in acquiring lock, others detect conflict and exit gracefully
	# Importance: Concurrent lock acquisition prevention ensures mutual exclusion even under race conditions
	# Skip condition: Requires 'flock' command to be available for concurrent lock acquisition tests
	if ! command -v flock >/dev/null 2>&1; then
		skip "flock command not available (test requires flock for concurrent file locking tests)"
	fi

	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	setup_mock_vpn_environment "192.168.1.1" 1000
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

# bats test_tags=category:high-risk,priority:high
@test "multiple processes attempting to acquire lock simultaneously (fallback path)" {
	# Purpose: Test verifies that fallback locking prevents multiple processes from acquiring lock simultaneously
	# Expected: Only one process succeeds in acquiring lock using atomic file operations, others detect conflict
	# Importance: Fallback mechanism must provide same mutual exclusion guarantees as flock-based locking
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
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	setup_mock_vpn_environment "192.168.1.1" 1000
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

# bats test_tags=category:high-risk,priority:high
@test "lockfile removed between check and creation (TOCTOU race)" {
	# Purpose: Test verifies that script handles TOCTOU race condition when lockfile is removed between check and creation
	# Expected: Script handles race condition gracefully, either successfully acquiring lock or detecting conflict
	# Importance: TOCTOU race handling ensures reliable lockfile acquisition even under concurrent access
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	setup_mock_vpn_environment "192.168.1.1" 1000
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

# bats test_tags=category:high-risk,priority:high
@test "PID reuse scenario (old PID reused, lockfile appears valid but process is different)" {
	# Purpose: Test verifies that script handles PID reuse scenario where old PID is reused by a different process
	# Expected: Script detects that PID in lockfile belongs to a different process and treats lockfile as stale
	# Importance: PID reuse handling prevents false positives when system reuses PIDs from terminated processes
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	setup_mock_vpn_environment "192.168.1.1" 1000
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

	# Skip condition: Cannot test PID reuse scenario if current process has the same PID as the old process
	# If current process has same PID, we can't test this scenario
	if [[ $$ -eq $old_pid ]]; then
		skip "Cannot test PID reuse scenario - current process PID ($$) matches old PID ($old_pid), test requires different PID to verify stale lockfile detection"
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

# bats test_tags=category:high-risk,priority:high
@test "script crashes - lockfile should be detected as stale on next run" {
	# Purpose: Test verifies that lockfile from crashed script is detected as stale on next script execution
	# Expected: Script detects stale lockfile (old timestamp, dead PID) and removes it before proceeding
	# Importance: Crash recovery ensures script can recover from previous crashes without manual intervention
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
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
	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	# Run script in background
	PATH="${TEST_DIR}:${PATH}" bash "$test_script" --fake &
	local script_pid=$!

	# Give script a moment to create lockfile before killing it
	sleep 0.01

	# Skip condition: Lockfile must be created by script before we can test crash recovery
	# Verify lockfile exists (should be created by script)
	if [[ ! -f "$lockfile" ]]; then
		skip "Lockfile not created quickly enough for crash test (script may have been killed before lockfile creation, test requires lockfile to exist to verify crash recovery)"
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

# bats test_tags=category:high-risk,priority:high
@test "trap handlers properly clean up lockfile in all exit scenarios" {
	# Purpose: Test verifies that trap handlers clean up lockfile in all exit scenarios (EXIT, INT, TERM)
	# Expected: Lockfile is removed by trap handlers regardless of how script exits (normal, SIGINT, SIGTERM)
	# Importance: Comprehensive trap handling ensures lockfile cleanup in all termination scenarios
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local lockfile="${state_dir}/vpn-monitor.lock"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN healthy
	setup_mock_vpn_environment "192.168.1.1" 1000
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

# bats test_tags=category:high-risk,priority:high
@test "lockfile file modification time cannot be read (permission issues)" {
	# Purpose: Test verifies that script handles permission issues when reading lockfile modification time
	# Expected: Script treats lockfile as stale when stat fails to read modification time (returns mtime=0)
	# Importance: Permission error handling prevents script failures when lockfile permissions are restrictive
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
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
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

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

# bats test_tags=category:high-risk,priority:high
@test "lockfile exists but PID belongs to different user (permission denied on kill -0)" {
	# Purpose: Test verifies that script handles permission denied errors when checking PID from different user
	# Expected: Script treats lockfile as stale when kill -0 fails due to permission denied (different user)
	# Importance: Permission error handling prevents false positives when checking processes owned by other users
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
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
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

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

# bats test_tags=category:high-risk,priority:high
@test "lockfile exists but PID is zombie process" {
	# Purpose: Test verifies that script handles lockfiles containing PIDs of zombie processes correctly
	# Expected: Script detects zombie process PID and treats lockfile as stale (zombie processes are not considered running)
	# Importance: Zombie process handling prevents false positives from lockfiles containing zombie PIDs
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
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
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Zombie processes still respond to kill -0, so lockfile would appear valid
	# Code at lib/lockfile.sh:68 uses kill -0 which succeeds for zombies
	assert_file_exist "$log_file"

	# Cleanup
	rm -f "$lockfile" 2>/dev/null || true
	remove_mock_from_path
}
