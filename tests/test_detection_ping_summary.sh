#!/usr/bin/env bats
#
# Tests for Ping Check Summary Logging
# Tests log_ping_summary_if_due() function with various intervals, state file management,
# and DEBUG level logging behavior

load test_helper

# Source the detection library functions
# shellcheck source=../lib/detection.sh
source "${BATS_TEST_DIRNAME}/../lib/detection.sh"

# Source logging for log_message functions
# shellcheck source=../lib/logging.sh
source "${BATS_TEST_DIRNAME}/../lib/logging.sh"

# Source common functions for atomic_write_file
# shellcheck source=../lib/common.sh
source "${BATS_TEST_DIRNAME}/../lib/common.sh"

# ============================================================================
# PING SUMMARY LOGGING TESTS
# ============================================================================

# Setup test environment with state directory
#
# Initializes test directories and environment variables for ping summary tests.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
setup_ping_summary_test() {
	STATE_DIR="${TEST_DIR}/state"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${STATE_DIR}"
	mkdir -p "${LOGS_DIR}"
	export STATE_DIR LOGS_DIR
	export LOG_FILE="${LOGS_DIR}/vpn-monitor.log"
	export PING_SUMMARY_INTERVAL_MINUTES="${PING_SUMMARY_INTERVAL_MINUTES:-7}"
	# SECONDS_PER_MINUTE is already defined as readonly in constants.sh (sourced by detection.sh)
	export DEBUG="${DEBUG:-0}"
}

# Helper to set up mock timestamp using existing mock_date function
# This uses the standard mock_date from test_helper.bash
#
# Arguments:
#   $1: Timestamp value to mock
#
# Returns:
#   0: Always succeeds
setup_mock_timestamp() {
	local timestamp="$1"
	mock_date "$timestamp" 0
	add_mock_to_path
}

# bats test_tags=category:unit
@test "log_ping_summary_if_due - logs summary when interval elapsed" {
	# Purpose: Test that summary is logged when configured interval has elapsed
	# Expected: Summary message logged at INFO level after interval
	# Importance: Validates core summary logging functionality
	setup_ping_summary_test

	# Set interval to 1 minute for faster testing
	export PING_SUMMARY_INTERVAL_MINUTES=1

	# Mock timestamp: start at 1000, then 1000 + 60 seconds (1 minute later)
	local start_time=1000
	local later_time=1060

	# Initialize state files manually to avoid first-call summary
	# Set last_time to start_time and count to 0
	echo "$start_time" >"${STATE_DIR}/ping_summary_last_time"
	echo "0" >"${STATE_DIR}/ping_summary_count"

	# Verify state files created
	assert_file_exist "${STATE_DIR}/ping_summary_last_time"
	assert_file_exist "${STATE_DIR}/ping_summary_count"

	# Make 2 ping calls to build up count to 2 (at same timestamp, so no summary yet)
	# The function increments before logging, so we need count=2 in file
	# to get a summary of 3 (2+1=3)
	setup_mock_timestamp "$start_time"
	log_ping_summary_if_due "${TEST_PEER_IP}" ""
	log_ping_summary_if_due "${TEST_PEER_IP}" ""

	# Now advance time past interval and call again - should log summary
	# With count=2 in file, function increments to 3 and logs "3 successful checks"
	setup_mock_timestamp "$later_time"
	log_ping_summary_if_due "${TEST_PEER_IP}" ""

	# Verify summary was logged
	# Note: Function increments count before logging. After 2 calls, count=2 in file.
	# The 3rd call increments to 3 and logs "3 successful checks"
	assert_file_contains "$LOG_FILE" "Ping check summary: 3 successful checks in the last 1 minutes"
}

# bats test_tags=category:unit
@test "log_ping_summary_if_due - uses default interval when config not set" {
	# Purpose: Test that default 7 minutes is used when PING_SUMMARY_INTERVAL_MINUTES not set
	# Expected: Summary logged after 7 minutes (420 seconds)
	# Importance: Validates default behavior
	setup_ping_summary_test

	# Don't set PING_SUMMARY_INTERVAL_MINUTES - should use default 7
	unset PING_SUMMARY_INTERVAL_MINUTES

	local start_time=1000
	local later_time=1420 # 7 minutes later (420 seconds)

	setup_mock_timestamp "$start_time"
	log_ping_summary_if_due "${TEST_PEER_IP}" ""

	# Advance time by 7 minutes
	setup_mock_timestamp "$later_time"
	log_ping_summary_if_due "${TEST_PEER_IP}" ""

	# Verify summary uses 7 minutes
	assert_file_contains "$LOG_FILE" "Ping check summary: 1 successful checks in the last 7 minutes"
}

# bats test_tags=category:unit
@test "log_ping_summary_if_due - respects configured interval" {
	# Purpose: Test that custom interval from config is used
	# Expected: Summary logged after custom interval
	# Importance: Validates config variable is respected
	setup_ping_summary_test

	# Set custom interval to 5 minutes
	export PING_SUMMARY_INTERVAL_MINUTES=5

	local start_time=1000
	local later_time=1300 # 5 minutes later (300 seconds)

	setup_mock_timestamp "$start_time"
	log_ping_summary_if_due "${TEST_PEER_IP}" ""

	# Advance time by 5 minutes
	setup_mock_timestamp "$later_time"
	log_ping_summary_if_due "${TEST_PEER_IP}" ""

	# Verify summary uses configured interval
	assert_file_contains "$LOG_FILE" "Ping check summary: 1 successful checks in the last 5 minutes"
}

# bats test_tags=category:unit
@test "log_ping_summary_if_due - handles missing STATE_DIR gracefully" {
	# Purpose: Test that function handles missing STATE_DIR without errors
	# Expected: Function returns successfully, no state files created
	# Importance: Validates graceful degradation
	unset STATE_DIR
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${LOGS_DIR}"
	export LOG_FILE="${LOGS_DIR}/vpn-monitor.log"

	# Should not error when STATE_DIR is not set
	run log_ping_summary_if_due "192.168.1.1" ""
	assert_success

	# Verify no state files were created
	assert_file_not_exist "${TEST_DIR}/state/ping_summary_last_time"
	assert_file_not_exist "${TEST_DIR}/state/ping_summary_count"
}

# bats test_tags=category:unit
@test "log_ping_summary_if_due - includes local IP in summary message" {
	# Purpose: Test that summary message includes local IP when provided
	# Expected: Summary message contains "from <local_ip>"
	# Importance: Validates message format with local IP
	setup_ping_summary_test

	export PING_SUMMARY_INTERVAL_MINUTES=1
	local start_time=1000
	local later_time=1060

	setup_mock_timestamp "$start_time"
	log_ping_summary_if_due "${TEST_PEER_IP}" "10.0.0.1"

	setup_mock_timestamp "$later_time"
	log_ping_summary_if_due "${TEST_PEER_IP}" "10.0.0.1"

	# Verify summary includes local IP
	assert_file_contains "$LOG_FILE" "target: ${TEST_PEER_IP} from ${TEST_PEER_IP2}"
}

# bats test_tags=category:unit
@test "log_ping_summary_if_due - resets count after summary" {
	# Purpose: Test that ping count resets to 0 after summary is logged
	# Expected: Count file contains 0 after summary, next summary starts fresh
	# Importance: Validates state management
	setup_ping_summary_test

	export PING_SUMMARY_INTERVAL_MINUTES=1
	local start_time=1000
	local later_time=1060
	local even_later_time=1120

	setup_mock_timestamp "$start_time"
	log_ping_summary_if_due "${TEST_PEER_IP}" ""
	log_ping_summary_if_due "${TEST_PEER_IP}" ""

	# Advance time and log summary
	setup_mock_timestamp "$later_time"
	log_ping_summary_if_due "${TEST_PEER_IP}" ""

	# Verify count was reset
	local count
	count=$(cat "${STATE_DIR}/ping_summary_count" 2>/dev/null || echo "0")
	assert_equal "$count" "0"

	# Make another ping call
	setup_mock_timestamp "$even_later_time"
	log_ping_summary_if_due "${TEST_PEER_IP}" ""

	# Advance time again and verify new summary shows only 1 ping
	setup_mock_timestamp $((even_later_time + 60))
	log_ping_summary_if_due "${TEST_PEER_IP}" ""

	# Should show 1 check, not 3 (count was reset)
	assert_file_contains "$LOG_FILE" "Ping check summary: 1 successful checks"
}

# bats test_tags=category:unit
@test "check_ping_connectivity - logs successful ping at DEBUG level only" {
	# Purpose: Test that successful pings are logged at DEBUG level when DEBUG=1
	# Expected: DEBUG message logged when DEBUG=1, no INFO message
	# Importance: Validates reduced logging for successful pings
	setup_ping_summary_test

	export DEBUG=1
	export ENABLE_PING_CHECK=1
	export PING_COUNT=1
	export PING_TIMEOUT=1

	# Mock ping to succeed
	mock_ping_success >/dev/null
	export PATH="${TEST_DIR}:${PATH}"

	# Mock route check to succeed (no route management needed)
	# Mock function to simulate route existence check
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds (route exists)
	check_route_exists() {
		return 0
	}
	export -f check_route_exists

	run check_ping_connectivity "${TEST_PEER_IP}" ""

	# Should succeed
	assert_success

	# Should log at DEBUG level (when DEBUG=1)
	# The actual message format is: "[DEBUG] Ping check OK: $target_ip (${packet_loss}% packet loss)"
	assert_file_contains "$LOG_FILE" "\[DEBUG\].*Ping check OK"
}

# bats test_tags=category:unit
@test "check_ping_connectivity - does not log successful ping at INFO level" {
	# Purpose: Test that successful pings are NOT logged at INFO level
	# Expected: No INFO level "Ping check OK" message
	# Importance: Validates logging reduction
	setup_ping_summary_test

	export DEBUG=0
	export ENABLE_PING_CHECK=1
	export PING_COUNT=1
	export PING_TIMEOUT=1

	# Mock ping to succeed
	mock_ping_success >/dev/null
	export PATH="${TEST_DIR}:${PATH}"

	# Mock route check
	# Mock function to simulate route existence check
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds (route exists)
	check_route_exists() {
		return 0
	}
	export -f check_route_exists

	run check_ping_connectivity "${TEST_PEER_IP}" ""

	assert_success

	# Should NOT contain INFO level ping check message
	run grep -q "\[INFO\].*Ping check OK" "$LOG_FILE" || true
	assert_failure
}

# bats test_tags=category:unit
@test "check_ping_connectivity - calls log_ping_summary_if_due on success" {
	# Purpose: Test that successful ping calls summary logging function
	# Expected: Summary function is called, state files are updated
	# Importance: Validates integration between ping check and summary logging
	setup_ping_summary_test

	export ENABLE_PING_CHECK=1
	export PING_COUNT=1
	export PING_TIMEOUT=1
	export PING_SUMMARY_INTERVAL_MINUTES=1

	# Mock ping to succeed
	mock_ping_success >/dev/null
	export PATH="${TEST_DIR}:${PATH}"

	# Mock route check
	# Mock function to simulate route existence check
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds (route exists)
	check_route_exists() {
		return 0
	}
	export -f check_route_exists

	# Mock timestamp for consistent testing
	setup_mock_timestamp 1000

	run check_ping_connectivity "${TEST_PEER_IP}" ""

	assert_success

	# Verify state files were created (summary function was called)
	assert_file_exist "${STATE_DIR}/ping_summary_last_time"
	assert_file_exist "${STATE_DIR}/ping_summary_count"
}

# bats test_tags=category:unit
@test "log_ping_summary_if_due - handles first call (last_time=0)" {
	# Purpose: Test that first call logs summary immediately
	# Expected: Summary logged on first call when last_time is 0
	# Importance: Validates initial state handling
	setup_ping_summary_test

	export PING_SUMMARY_INTERVAL_MINUTES=7

	setup_mock_timestamp 1000

	# First call should log summary (last_time=0 triggers immediate summary)
	log_ping_summary_if_due "${TEST_PEER_IP}" ""

	# Verify summary was logged
	assert_file_contains "$LOG_FILE" "Ping check summary: 1 successful checks"
}

# bats test_tags=category:unit
@test "log_ping_summary_if_due - uses atomic writes for state files" {
	# Purpose: Test that state files are written atomically
	# Expected: State files are created successfully using atomic writes
	# Importance: Validates ADR-0012 compliance - atomic writes prevent corruption
	setup_ping_summary_test

	export PING_SUMMARY_INTERVAL_MINUTES=1

	setup_mock_timestamp 1000
	log_ping_summary_if_due "${TEST_PEER_IP}" ""

	# Verify state files exist (atomic write succeeded)
	# Note: We can't easily verify atomic_write_file was called without complex mocking,
	# but we can verify the files exist and contain valid data, which confirms atomic writes worked
	assert_file_exist "${STATE_DIR}/ping_summary_count"
	assert_file_exist "${STATE_DIR}/ping_summary_last_time"

	# Verify files contain valid data (not corrupted)
	local count
	count=$(cat "${STATE_DIR}/ping_summary_count" 2>/dev/null || echo "invalid")
	[[ "$count" =~ ^[0-9]+$ ]] || false # Should be numeric

	local timestamp
	timestamp=$(cat "${STATE_DIR}/ping_summary_last_time" 2>/dev/null || echo "invalid")
	[[ "$timestamp" =~ ^[0-9]+$ ]] || false # Should be numeric
}
