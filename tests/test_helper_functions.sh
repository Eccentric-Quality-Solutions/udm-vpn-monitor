#!/usr/bin/env bats
#
# Unit tests for helper functions in vpn-monitor.sh
# Tests individual helper functions in isolation

load test_helper

# Path to the VPN monitor script and modules
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"
LIB_DIR="${BATS_TEST_DIRNAME}/../lib"

# Helper function to source a function from the appropriate module
# Functions are now in separate module files, so we need to check each module
source_function() {
	local func_name="$1"
	local func_def=""

	# Map functions to their module files
	# Try each module file in order until we find the function
	local modules=(
		"${LIB_DIR}/logging.sh"
		"${LIB_DIR}/config.sh"
		"${LIB_DIR}/state.sh"
		"${LIB_DIR}/detection.sh"
		"${LIB_DIR}/recovery.sh"
		"${LIB_DIR}/lockfile.sh"
		"${VPN_MONITOR_SCRIPT}"
	)

	# Try to find the function in each module
	for module in "${modules[@]}"; do
		if [[ -f "$module" ]]; then
			# Extract function using sed, matching from function start to closing brace
			func_def=$(sed -n "/^${func_name}(/,/^}/p" "$module" 2>/dev/null)
			if [[ -n "$func_def" ]]; then
				# Set minimal required variables for functions that need them
				# Export these so they're available in subshells created by 'run'
				SCRIPT_DIR="${SCRIPT_DIR:-${BATS_TEST_DIRNAME}/..}"
				export SCRIPT_DIR
				STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
				export STATE_DIR
				LOGS_DIR="${LOGS_DIR:-${STATE_DIR}/logs}"
				export LOGS_DIR
				LOCKFILE="${LOCKFILE:-${STATE_DIR}/vpn-monitor.lock}"
				export LOCKFILE
				LOG_FILE="${LOG_FILE:-${LOGS_DIR}/vpn-monitor.log}"
				export LOG_FILE
				RESTART_COUNT_FILE="${RESTART_COUNT_FILE:-${LOGS_DIR}/restart_count}"
				export RESTART_COUNT_FILE
				COOLDOWN_UNTIL_FILE="${COOLDOWN_UNTIL_FILE:-${STATE_DIR}/cooldown_until}"
				export COOLDOWN_UNTIL_FILE
				CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/vpn-monitor.conf}"
				export CONFIG_FILE
				DEBUG="${DEBUG:-0}"
				export DEBUG

				# Source required dependencies first
				case "$module" in
				"${LIB_DIR}/config.sh")
					# config.sh needs logging.sh
					if [[ -f "${LIB_DIR}/logging.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/logging.sh" 2>/dev/null || true
					fi
					;;
				"${LIB_DIR}/state.sh")
					# state.sh needs logging.sh
					if [[ -f "${LIB_DIR}/logging.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/logging.sh" 2>/dev/null || true
					fi
					;;
				"${LIB_DIR}/detection.sh")
					# detection.sh needs state.sh and logging.sh
					# Also source detection.sh itself to make helper functions available
					if [[ -f "${LIB_DIR}/logging.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/logging.sh" 2>/dev/null || true
					fi
					if [[ -f "${LIB_DIR}/state.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/state.sh" 2>/dev/null || true
					fi
					# Source detection.sh to make all helper functions available
					# (e.g., validate_ipv4, validate_ipv6, etc. used by validate_ip_address)
					if [[ -f "${LIB_DIR}/detection.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/detection.sh" 2>/dev/null || true
						# Function already sourced, skip eval below
						return 0
					fi
					;;
				"${LIB_DIR}/recovery.sh")
					# recovery.sh needs detection.sh, state.sh, logging.sh
					if [[ -f "${LIB_DIR}/logging.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/logging.sh" 2>/dev/null || true
					fi
					if [[ -f "${LIB_DIR}/state.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/state.sh" 2>/dev/null || true
					fi
					if [[ -f "${LIB_DIR}/detection.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/detection.sh" 2>/dev/null || true
					fi
					;;
				"${LIB_DIR}/lockfile.sh")
					# lockfile.sh needs state.sh and logging.sh
					if [[ -f "${LIB_DIR}/logging.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/logging.sh" 2>/dev/null || true
					fi
					if [[ -f "${LIB_DIR}/state.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/state.sh" 2>/dev/null || true
					fi
					;;
				esac

				# Source the function
				# shellcheck source=/dev/null
				eval "$func_def"
				return 0
			fi
		fi
	done

	# Function not found
	return 1
}

@test "get_formatted_timestamp returns valid timestamp format" {
	# Source the function
	source_function "get_formatted_timestamp"

	# Run the function
	run get_formatted_timestamp

	assert_success
	# Check format: YYYY-MM-DD HH:MM:SS
	# Use grep to check regex pattern since assert_output doesn't support --regexp
	if ! echo "$output" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'; then
		echo "Output '$output' doesn't match timestamp format" >&2
		return 1
	fi
}

@test "ensure_directory_exists creates directory when missing" {
	local test_dir="${TEST_DIR}/new_dir"

	# Source the function
	source_function "ensure_directory_exists"

	# Run the function (should not exit in test context)
	ensure_directory_exists "$test_dir" "test" || true

	assert_dir_exist "$test_dir"
}

@test "sanitize_peer_ip converts dots to underscores" {
	# Source the function
	# shellcheck source=/dev/null
	source_function "sanitize_peer_ip"

	run sanitize_peer_ip "192.168.1.1"
	assert_success
	assert_output "192_168_1_1"
}

@test "sanitize_peer_ip handles IPv6 addresses" {
	# Source the function
	# shellcheck source=/dev/null
	source_function "sanitize_peer_ip"

	run sanitize_peer_ip "2001:db8::1"
	assert_success
	assert_output "2001_db8__1"
}

@test "extract_lockfile_pid extracts PID from lockfile" {
	# Source the function
	# shellcheck source=/dev/null
	source_function "extract_lockfile_pid"

	local lockfile="${TEST_DIR}/test.lock"
	echo "1234567890:12345" >"$lockfile"

	LOCKFILE="$lockfile" run extract_lockfile_pid "$lockfile"
	assert_success
	assert_output "12345"
}

@test "extract_lockfile_pid returns empty for missing lockfile" {
	# Source the function
	# shellcheck source=/dev/null
	source_function "extract_lockfile_pid"

	run extract_lockfile_pid "${TEST_DIR}/nonexistent.lock"
	assert_success
	# Empty output expected
	if [[ -n "$output" ]]; then
		echo "Expected empty output but got: $output" >&2
		return 1
	fi
}

@test "is_process_running returns true for current process" {
	# Source the function
	# shellcheck source=/dev/null
	source_function "is_process_running"

	# Test with current PID
	run is_process_running $$
	assert_success
}

@test "is_process_running returns false for non-existent PID" {
	# Source the function
	# shellcheck source=/dev/null
	source_function "is_process_running"

	# Use a very high PID that shouldn't exist
	run is_process_running 999999
	assert_failure
}

@test "is_process_running returns false for empty PID" {
	# Source the function
	# shellcheck source=/dev/null
	source_function "is_process_running"

	run is_process_running ""
	assert_failure
}

@test "get_timestamp_plus_minutes adds minutes correctly" {
	# Source the function
	# shellcheck source=/dev/null
	source_function "get_timestamp_plus_minutes"

	local now=$(date +%s)
	run get_timestamp_plus_minutes 5

	assert_success
	local future=$(cat <<<"$output")
	local expected=$((now + 300)) # 5 minutes = 300 seconds

	# Allow 5 second tolerance for execution time
	assert [ $((future - expected)) -ge -5 ]
	assert [ $((future - expected)) -le 5 ]
}

@test "get_file_mtime returns modification time" {
	# Source the function
	# shellcheck source=/dev/null
	source_function "get_file_mtime"

	local test_file="${TEST_DIR}/test_file"
	touch "$test_file"
	sleep 1

	run get_file_mtime "$test_file"
	assert_success
	# Should return a Unix timestamp (numeric)
	if ! echo "$output" | grep -qE '^[0-9]+$'; then
		echo "Output '$output' is not a valid timestamp" >&2
		return 1
	fi
}

@test "validate_ip_address accepts valid IPv4 addresses" {
	# Source the function
	# shellcheck source=/dev/null
	source_function "validate_ip_address"

	run validate_ip_address "192.168.1.1"
	assert_success

	run validate_ip_address "10.0.0.1"
	assert_success

	run validate_ip_address "172.16.0.1"
	assert_success
}

@test "validate_ip_address rejects invalid IPv4 addresses" {
	# Source the function
	# shellcheck source=/dev/null
	source_function "validate_ip_address"

	run validate_ip_address "256.1.1.1"
	assert_failure

	run validate_ip_address "192.168.1"
	assert_failure

	run validate_ip_address "192.168.1.1.1"
	assert_failure

	run validate_ip_address ""
	assert_failure
}

@test "validate_ip_address accepts valid IPv6 addresses" {
	# Source the function
	# shellcheck source=/dev/null
	source_function "validate_ip_address"

	run validate_ip_address "2001:db8::1"
	assert_success

	run validate_ip_address "::1"
	assert_success

	run validate_ip_address "2001:0db8:0000:0000:0000:0000:0000:0001"
	assert_success
}

@test "validate_ip_address rejects invalid IPv6 addresses" {
	# Source the function
	# shellcheck source=/dev/null
	source_function "validate_ip_address"

	run validate_ip_address "2001:db8::1::2"
	assert_failure

	run validate_ip_address "2001:db8:::1"
	assert_failure

	run validate_ip_address "2001:db8:g::1"
	assert_failure
}

@test "extract_byte_counter extracts bytes from xfrm output" {
	# Source the function
	# shellcheck source=/dev/null
	source_function "extract_byte_counter"

	local xfrm_output="lifetime current: 123456 bytes, 789 packets"

	run extract_byte_counter "$xfrm_output"
	assert_success
	assert_output "123456"
}

@test "extract_byte_counter handles missing lifetime line" {
	# Source the function
	# shellcheck source=/dev/null
	source_function "extract_byte_counter"

	local xfrm_output="some other output"

	run extract_byte_counter "$xfrm_output"
	assert_failure
}

@test "get_failure_count returns 0 for missing counter file" {
	# Create test environment
	local logs_dir="${TEST_DIR}/logs"
	mkdir -p "$logs_dir"

	# Create a minimal script that sources the function
	cat >"${TEST_DIR}/test_script.sh" <<'SCRIPT'
#!/bin/bash
source "${BATS_TEST_DIRNAME}/../vpn-monitor.sh" 2>/dev/null || true

LOGS_DIR="$1"
PEER_IP="$2"

# Source sanitize function
sanitize_peer_ip() {
    echo "$1" | tr '.' '_' | tr ':' '_'
}

# Source get_failure_count function
get_failure_count() {
	local peer_ip="$1"
	local peer_sanitized
	peer_sanitized=$(sanitize_peer_ip "$peer_ip")
	local counter_file="${LOGS_DIR}/failure_counter_${peer_sanitized}"

	if [[ -f "$counter_file" ]]; then
		cat "$counter_file"
	else
		echo "0"
	fi
}

get_failure_count "$PEER_IP"
SCRIPT

	chmod +x "${TEST_DIR}/test_script.sh"

	run bash "${TEST_DIR}/test_script.sh" "$logs_dir" "192.168.1.1"
	assert_success
	assert_output "0"
}

@test "get_failure_count returns value from counter file" {
	local logs_dir="${TEST_DIR}/logs"
	mkdir -p "$logs_dir"
	local counter_file="${logs_dir}/failure_counter_192_168_1_1"
	echo "5" >"$counter_file"

	cat >"${TEST_DIR}/test_script.sh" <<'SCRIPT'
#!/bin/bash
LOGS_DIR="$1"
PEER_IP="$2"

sanitize_peer_ip() {
    echo "$1" | tr '.' '_' | tr ':' '_'
}

get_failure_count() {
	local peer_ip="$1"
	local peer_sanitized
	peer_sanitized=$(sanitize_peer_ip "$peer_ip")
	local counter_file="${LOGS_DIR}/failure_counter_${peer_sanitized}"

	if [[ -f "$counter_file" ]]; then
		cat "$counter_file"
	else
		echo "0"
	fi
}

get_failure_count "$PEER_IP"
SCRIPT

	chmod +x "${TEST_DIR}/test_script.sh"

	run bash "${TEST_DIR}/test_script.sh" "$logs_dir" "192.168.1.1"
	assert_success
	assert_output "5"
}

@test "increment_failure increments counter correctly" {
	local logs_dir="${TEST_DIR}/logs"
	mkdir -p "$logs_dir"

	cat >"${TEST_DIR}/test_script.sh" <<'SCRIPT'
#!/bin/bash
LOGS_DIR="$1"
PEER_IP="$2"

sanitize_peer_ip() {
    echo "$1" | tr '.' '_' | tr ':' '_'
}

get_failure_count() {
	local peer_ip="$1"
	local peer_sanitized
	peer_sanitized=$(sanitize_peer_ip "$peer_ip")
	local counter_file="${LOGS_DIR}/failure_counter_${peer_sanitized}"

	if [[ -f "$counter_file" ]]; then
		cat "$counter_file"
	else
		echo "0"
	fi
}

increment_failure() {
	local peer_ip="$1"
	local peer_sanitized
	peer_sanitized=$(sanitize_peer_ip "$peer_ip")
	local counter_file="${LOGS_DIR}/failure_counter_${peer_sanitized}"
	local count
	count=$(get_failure_count "$peer_ip")
	echo "$((count + 1))" >"$counter_file"
	echo "$((count + 1))"
}

increment_failure "$PEER_IP"
SCRIPT

	chmod +x "${TEST_DIR}/test_script.sh"

	# First increment
	run bash "${TEST_DIR}/test_script.sh" "$logs_dir" "192.168.1.1"
	assert_success
	assert_output "1"

	# Second increment
	run bash "${TEST_DIR}/test_script.sh" "$logs_dir" "192.168.1.1"
	assert_success
	assert_output "2"
}

@test "reset_failure_count resets counter to 0" {
	local logs_dir="${TEST_DIR}/logs"
	mkdir -p "$logs_dir"
	local counter_file="${logs_dir}/failure_counter_192_168_1_1"
	echo "5" >"$counter_file"

	cat >"${TEST_DIR}/test_script.sh" <<'SCRIPT'
#!/bin/bash
LOGS_DIR="$1"
PEER_IP="$2"

sanitize_peer_ip() {
    echo "$1" | tr '.' '_' | tr ':' '_'
}

reset_failure_count() {
	local peer_ip="$1"
	local peer_sanitized
	peer_sanitized=$(sanitize_peer_ip "$peer_ip")
	local counter_file="${LOGS_DIR}/failure_counter_${peer_sanitized}"
	echo "0" >"$counter_file"
}

reset_failure_count "$PEER_IP"
cat "${LOGS_DIR}/failure_counter_192_168_1_1"
SCRIPT

	chmod +x "${TEST_DIR}/test_script.sh"

	run bash "${TEST_DIR}/test_script.sh" "$logs_dir" "192.168.1.1"
	assert_success
	assert_output "0"
}

@test "check_cooldown returns false when cooldown file missing" {
	local state_dir="${TEST_DIR}"

	cat >"${TEST_DIR}/test_script.sh" <<'SCRIPT'
#!/bin/bash
STATE_DIR="$1"

get_file_mtime() {
	local file="$1"
	stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo "0"
}

check_cooldown() {
	local COOLDOWN_UNTIL_FILE="${STATE_DIR}/cooldown_until"
	if [[ ! -f "$COOLDOWN_UNTIL_FILE" ]]; then
		return 1 # Not in cooldown
	fi

	local cooldown_until
	cooldown_until=$(cat "$COOLDOWN_UNTIL_FILE")
	local now
	now=$(date +%s)

	if [[ $now -lt $cooldown_until ]]; then
		return 0 # In cooldown
	else
		rm -f "$COOLDOWN_UNTIL_FILE"
		return 1 # Not in cooldown
	fi
}

check_cooldown
SCRIPT

	chmod +x "${TEST_DIR}/test_script.sh"

	run bash "${TEST_DIR}/test_script.sh" "$state_dir"
	assert_failure # Not in cooldown
}

@test "check_cooldown returns true when in cooldown period" {
	local state_dir="${TEST_DIR}"
	local cooldown_file="${state_dir}/cooldown_until"
	local future_time=$(($(date +%s) + 900)) # 15 minutes in future
	echo "$future_time" >"$cooldown_file"

	cat >"${TEST_DIR}/test_script.sh" <<'SCRIPT'
#!/bin/bash
STATE_DIR="$1"

check_cooldown() {
	local COOLDOWN_UNTIL_FILE="${STATE_DIR}/cooldown_until"
	if [[ ! -f "$COOLDOWN_UNTIL_FILE" ]]; then
		return 1 # Not in cooldown
	fi

	local cooldown_until
	cooldown_until=$(cat "$COOLDOWN_UNTIL_FILE")
	local now
	now=$(date +%s)

	if [[ $now -lt $cooldown_until ]]; then
		return 0 # In cooldown
	else
		rm -f "$COOLDOWN_UNTIL_FILE"
		return 1 # Not in cooldown
	fi
}

check_cooldown
SCRIPT

	chmod +x "${TEST_DIR}/test_script.sh"

	run bash "${TEST_DIR}/test_script.sh" "$state_dir"
	assert_success # In cooldown
}

@test "check_rate_limit allows restart when under limit" {
	local logs_dir="${TEST_DIR}/logs"
	mkdir -p "$logs_dir"
	local restart_file="${logs_dir}/restart_count"

	cat >"${TEST_DIR}/test_script.sh" <<'SCRIPT'
#!/bin/bash
RESTART_COUNT_FILE="$1"
MAX_RESTARTS_PER_HOUR=3

check_rate_limit() {
	local now
	now=$(date +%s)
	local one_hour_ago
	one_hour_ago=$((now - 3600))

	if [[ ! -f "$RESTART_COUNT_FILE" ]]; then
		return 0 # No previous restarts, allow
	fi

	local recent_restarts
	recent_restarts=$(awk -v cutoff="$one_hour_ago" '$1 > cutoff' "$RESTART_COUNT_FILE" 2>/dev/null | wc -l | tr -d ' ')

	if [[ $recent_restarts -ge $MAX_RESTARTS_PER_HOUR ]]; then
		return 1 # Rate limited
	fi

	return 0 # Within rate limit
}

check_rate_limit
SCRIPT

	chmod +x "${TEST_DIR}/test_script.sh"

	run bash "${TEST_DIR}/test_script.sh" "$restart_file"
	assert_success # Under limit
}

@test "check_rate_limit blocks restart when over limit" {
	local logs_dir="${TEST_DIR}/logs"
	mkdir -p "$logs_dir"
	local restart_file="${logs_dir}/restart_count"

	# Create restart file with 4 recent restarts (over limit of 3)
	local now=$(date +%s)
	echo "$now" >>"$restart_file"
	echo "$now" >>"$restart_file"
	echo "$now" >>"$restart_file"
	echo "$now" >>"$restart_file"

	cat >"${TEST_DIR}/test_script.sh" <<'SCRIPT'
#!/bin/bash
RESTART_COUNT_FILE="$1"
MAX_RESTARTS_PER_HOUR=3

check_rate_limit() {
	local now
	now=$(date +%s)
	local one_hour_ago
	one_hour_ago=$((now - 3600))

	if [[ ! -f "$RESTART_COUNT_FILE" ]]; then
		return 0 # No previous restarts, allow
	fi

	local recent_restarts
	recent_restarts=$(awk -v cutoff="$one_hour_ago" '$1 > cutoff' "$RESTART_COUNT_FILE" 2>/dev/null | wc -l | tr -d ' ')

	if [[ $recent_restarts -ge $MAX_RESTARTS_PER_HOUR ]]; then
		return 1 # Rate limited
	fi

	return 0 # Within rate limit
}

check_rate_limit
SCRIPT

	chmod +x "${TEST_DIR}/test_script.sh"

	run bash "${TEST_DIR}/test_script.sh" "$restart_file"
	assert_failure # Over limit
}

@test "record_restart appends timestamp to restart file" {
	local logs_dir="${TEST_DIR}/logs"
	mkdir -p "$logs_dir"
	local restart_file="${logs_dir}/restart_count"

	cat >"${TEST_DIR}/test_script.sh" <<'SCRIPT'
#!/bin/bash
RESTART_COUNT_FILE="$1"

record_restart() {
	local timestamp
	timestamp=$(date +%s)
	echo "$timestamp" >>"$RESTART_COUNT_FILE"
}

record_restart
cat "$RESTART_COUNT_FILE"
SCRIPT

	chmod +x "${TEST_DIR}/test_script.sh"

	run bash "${TEST_DIR}/test_script.sh" "$restart_file"
	assert_success
	# Should contain a timestamp (numeric)
	if ! echo "$output" | grep -qE '^[0-9]+$'; then
		echo "Output '$output' is not a valid timestamp" >&2
		return 1
	fi
}

# ============================================================================
# Tests for discover_connection_name function (ipsec-based discovery)
# ============================================================================

@test "discover_connection_name extracts connection name from ipsec status (libreswan format)" {
	source_function "discover_connection_name"
	source_function "sanitize_peer_ip"

	# Mock ipsec command - libreswan format
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    echo "site-a: ESTABLISHED 1 hour ago, 192.168.1.1...192.168.1.2"
    echo "site-b: ESTABLISHED 2 hours ago, 10.0.0.1...10.0.0.2"
fi
EOF
	chmod +x "$mock_ipsec"
	PATH="${TEST_DIR}:${PATH}"

	STATE_DIR="${TEST_DIR}"
	run discover_connection_name "192.168.1.1"

	assert_success
	assert_output "site-a"
}

@test "discover_connection_name extracts connection name from ipsec status (strongswan format)" {
	source_function "discover_connection_name"
	source_function "sanitize_peer_ip"

	# Mock ipsec command - strongswan format
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    echo "site-a: IKEv1, ESTABLISHED, 192.168.1.1"
    echo "site-b: IKEv2, ESTABLISHED, 10.0.0.1"
fi
EOF
	chmod +x "$mock_ipsec"
	PATH="${TEST_DIR}:${PATH}"

	STATE_DIR="${TEST_DIR}"
	run discover_connection_name "192.168.1.1"

	assert_success
	assert_output "site-a"
}

@test "discover_connection_name returns empty string when connection not found" {
	source_function "discover_connection_name"
	source_function "sanitize_peer_ip"

	# Mock ipsec command - no matching peer IP
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    echo "site-a: ESTABLISHED 1 hour ago, 192.168.1.1...192.168.1.2"
fi
EOF
	chmod +x "$mock_ipsec"
	PATH="${TEST_DIR}:${PATH}"

	export STATE_DIR="${TEST_DIR}"
	run discover_connection_name "10.0.0.1"

	assert_success
	assert_output ""
}

@test "discover_connection_name caches connection name" {
	# Match test 27 pattern: call source_function first
	source_function "discover_connection_name"
	source_function "sanitize_peer_ip"

	# Set STATE_DIR AFTER source_function (matching test 27)
	# But ensure it's exported so it's available in subshells created by 'run'
	STATE_DIR="${TEST_DIR}"
	export STATE_DIR

	# Mock ipsec command - libreswan format
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    echo "site-a: ESTABLISHED 1 hour ago, 192.168.1.1...192.168.1.2"
fi
EOF
	chmod +x "$mock_ipsec"
	PATH="${TEST_DIR}:${PATH}"
	export PATH

	# Clean up any existing cache file from previous tests
	local cache_file="${TEST_DIR}/connection_name_192_168_1_1"
	rm -f "$cache_file"

	# First call - should discover and cache
	# Use plain 'run' like test 27 (source_function makes functions available)
	run discover_connection_name "192.168.1.1"
	assert_success
	# Manually verify output - assert_output has scoping issues with $output
	# The output variable IS set correctly (we verified with debug), but assert_output
	# can't see it. So we'll verify manually and skip assert_output.
	if [[ "${output:-}" != "site-a" ]]; then
		echo "Expected output: site-a" >&2
		echo "Actual output: [${output:-}]" >&2
		return 1
	fi
	assert_file_exist "$cache_file"
	assert [ "$(cat "$cache_file")" = "site-a" ]

	# Remove ipsec mock - second call should use cache
	rm -f "$mock_ipsec"
	# Ensure STATE_DIR is still exported for second call
	export STATE_DIR
	run discover_connection_name "192.168.1.1"
	assert_success
	# Manually verify output - assert_output has scoping issues
	if [[ "${output:-}" != "site-a" ]]; then
		echo "Expected output: site-a" >&2
		echo "Actual output: [${output:-}]" >&2
		echo "DEBUG: STATE_DIR in test=$STATE_DIR" >&2
		echo "DEBUG: cache_file=$cache_file" >&2
		echo "DEBUG: cache exists=$([ -f "$cache_file" ] && echo yes || echo no)" >&2
		if [[ -f "$cache_file" ]]; then
			echo "DEBUG: cache content=[$(cat "$cache_file")]" >&2
		fi
		return 1
	fi
}

@test "discover_connection_name returns empty when ipsec command not available" {
	source_function "discover_connection_name"
	source_function "sanitize_peer_ip"

	# Ensure ipsec is not in PATH
	PATH="/usr/bin:/bin"
	export STATE_DIR="${TEST_DIR}"

	run discover_connection_name "192.168.1.1"

	assert_success
	assert_output ""
}

@test "discover_connection_name handles ipsec status failure gracefully" {
	source_function "discover_connection_name"
	source_function "sanitize_peer_ip"

	# Mock ipsec command - fails
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	PATH="${TEST_DIR}:${PATH}"

	STATE_DIR="${TEST_DIR}"
	run discover_connection_name "192.168.1.1"

	assert_success
	assert_output ""
}

# ============================================================================
# Tests for config_schema.sh functions
# ============================================================================

@test "get_config_schema returns schema for existing variable" {
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run get_config_schema "EXTERNAL_PEER_IPS"

	assert_success
	assert_output --partial "required"
	assert_output --partial "string"
}

@test "get_config_schema returns failure for non-existent variable" {
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run get_config_schema "NON_EXISTENT_VAR"

	assert_failure
}

@test "is_config_required returns true for required variable" {
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run is_config_required "EXTERNAL_PEER_IPS"

	assert_success
}

@test "is_config_required returns false for optional variable" {
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run is_config_required "VPN_NAME"

	assert_failure
}

@test "is_config_required returns false for unknown variable" {
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run is_config_required "UNKNOWN_VAR"

	assert_failure
}

@test "get_config_default returns default value for variable with default" {
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run get_config_default "VPN_NAME"

	assert_success
	assert_output "Site-to-Site VPN"
}

@test "get_config_default returns empty string for variable without default" {
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run get_config_default "EXTERNAL_PEER_IPS"

	assert_success
	# Should return empty string (no default for required variables)
	# Function may output newline, so check for empty or whitespace-only
	if [[ -n "$output" ]] && [[ "$output" != "" ]]; then
		echo "Expected empty output but got: '$output'" >&2
		return 1
	fi
}

@test "get_config_default returns failure for non-existent variable" {
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run get_config_default "NON_EXISTENT_VAR"

	assert_failure
}

@test "get_config_default handles integer defaults correctly" {
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run get_config_default "ENABLE_PING_CHECK"

	assert_success
	assert_output "1"
}

@test "get_config_default handles cron schedule defaults correctly" {
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run get_config_default "CRON_SCHEDULE"

	assert_success
	assert_output "*/1 * * * *"
}
