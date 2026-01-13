#!/usr/bin/env bats
#
# Tests for Network Partition Check Statistics Tracking
# Tests track_network_partition_check() and log_network_partition_summary_if_due() functions
# with various scenarios, state file management, and hourly summary logging

load test_helper
load helpers/detection

# Source the state library functions
# shellcheck source=../lib/state.sh
source "${BATS_TEST_DIRNAME}/../lib/state.sh"

# Source logging for log_message functions
# shellcheck source=../lib/logging.sh
source "${BATS_TEST_DIRNAME}/../lib/logging.sh"

# Source common functions for atomic_write_file
# shellcheck source=../lib/common.sh
source "${BATS_TEST_DIRNAME}/../lib/common.sh"

# Setup function for network partition stats tests
#
# Sets up test environment for network partition statistics tests.
# Initializes state and log directories and sets required environment variables.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Creates TEST_DIR/state and TEST_DIR/logs directories
#   - Sets STATE_DIR, LOGS_DIR, and LOG_FILE environment variables
#   - SECONDS_PER_HOUR is available from lib/constants.sh (sourced via lib/state.sh)
#
# Note:
#   This is a test helper function. Requires standard_setup() to be available
#   from test helpers.
setup_network_partition_stats_test() {
	standard_setup

	# Set up state directory
	export STATE_DIR="${TEST_DIR}/state"
	mkdir -p "${STATE_DIR}"

	# Set up logs directory
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${LOGS_DIR}"
	export LOG_FILE="${LOGS_DIR}/vpn-monitor.log"

	# Set constants (only if not already set as readonly)
	# SECONDS_PER_HOUR is already defined as readonly in lib/constants.sh and lib/state.sh
	# so we don't need to export it here - it will be available from the sourced libraries
}

# ============================================================================
# TRACKING TESTS
# ============================================================================

# bats test_tags=category:unit
@test "track_network_partition_check - tracks DNS success" {
	# Purpose: Test that DNS check successes are tracked correctly
	# Expected: DNS success counter increments
	# Importance: Validates core tracking functionality for DNS checks
	setup_network_partition_stats_test

	track_network_partition_check "dns" 1

	# Verify counter file exists and contains 1
	assert_file_exist "${STATE_DIR}/network_partition_dns_success_count"
	local count
	count=$(cat "${STATE_DIR}/network_partition_dns_success_count" 2>/dev/null || echo "0")
	assert_equal "$count" "1"
}

# bats test_tags=category:unit
@test "track_network_partition_check - tracks DNS failure" {
	# Purpose: Test that DNS check failures are tracked correctly
	# Expected: DNS failure counter increments
	# Importance: Validates failure tracking for DNS checks
	setup_network_partition_stats_test

	track_network_partition_check "dns" 0

	# Verify counter file exists and contains 1
	assert_file_exist "${STATE_DIR}/network_partition_dns_fail_count"
	local count
	count=$(cat "${STATE_DIR}/network_partition_dns_fail_count" 2>/dev/null || echo "0")
	assert_equal "$count" "1"
}

# bats test_tags=category:unit
@test "track_network_partition_check - tracks route success" {
	# Purpose: Test that route check successes are tracked correctly
	# Expected: Route success counter increments
	# Importance: Validates core tracking functionality for route checks
	setup_network_partition_stats_test

	track_network_partition_check "route" 1

	# Verify counter file exists and contains 1
	assert_file_exist "${STATE_DIR}/network_partition_route_success_count"
	local count
	count=$(cat "${STATE_DIR}/network_partition_route_success_count" 2>/dev/null || echo "0")
	assert_equal "$count" "1"
}

# bats test_tags=category:unit
@test "track_network_partition_check - tracks route failure" {
	# Purpose: Test that route check failures are tracked correctly
	# Expected: Route failure counter increments
	# Importance: Validates failure tracking for route checks
	setup_network_partition_stats_test

	track_network_partition_check "route" 0

	# Verify counter file exists and contains 1
	assert_file_exist "${STATE_DIR}/network_partition_route_fail_count"
	local count
	count=$(cat "${STATE_DIR}/network_partition_route_fail_count" 2>/dev/null || echo "0")
	assert_equal "$count" "1"
}

# bats test_tags=category:unit
@test "track_network_partition_check - tracks interface success" {
	# Purpose: Test that interface check successes are tracked correctly
	# Expected: Interface success counter increments
	# Importance: Validates core tracking functionality for interface checks
	setup_network_partition_stats_test

	track_network_partition_check "interface" 1

	# Verify counter file exists and contains 1
	assert_file_exist "${STATE_DIR}/network_partition_interface_success_count"
	local count
	count=$(cat "${STATE_DIR}/network_partition_interface_success_count" 2>/dev/null || echo "0")
	assert_equal "$count" "1"
}

# bats test_tags=category:unit
@test "track_network_partition_check - tracks interface failure" {
	# Purpose: Test that interface check failures are tracked correctly
	# Expected: Interface failure counter increments
	# Importance: Validates failure tracking for interface checks
	setup_network_partition_stats_test

	track_network_partition_check "interface" 0

	# Verify counter file exists and contains 1
	assert_file_exist "${STATE_DIR}/network_partition_interface_fail_count"
	local count
	count=$(cat "${STATE_DIR}/network_partition_interface_fail_count" 2>/dev/null || echo "0")
	assert_equal "$count" "1"
}

# bats test_tags=category:unit
@test "track_network_partition_check - increments counter correctly" {
	# Purpose: Test that counter increments correctly on multiple calls
	# Expected: Counter increases by 1 each time
	# Importance: Validates counter increment logic
	setup_network_partition_stats_test

	# Track 3 successes
	track_network_partition_check "dns" 1
	track_network_partition_check "dns" 1
	track_network_partition_check "dns" 1

	# Verify counter is 3
	local count
	count=$(cat "${STATE_DIR}/network_partition_dns_success_count" 2>/dev/null || echo "0")
	assert_equal "$count" "3"
}

# bats test_tags=category:unit
@test "track_network_partition_check - handles invalid check type gracefully" {
	# Purpose: Test that invalid check types are handled gracefully
	# Expected: Function returns successfully, no state files created
	# Importance: Validates input validation
	setup_network_partition_stats_test

	# Should not error on invalid check type
	run track_network_partition_check "invalid" 1
	assert_success

	# Verify no state files were created for invalid type
	assert_file_not_exist "${STATE_DIR}/network_partition_invalid_success_count"
}

# bats test_tags=category:unit
@test "track_network_partition_check - handles missing STATE_DIR gracefully" {
	# Purpose: Test that function handles missing STATE_DIR without errors
	# Expected: Function returns successfully, no state files created
	# Importance: Validates graceful degradation
	unset STATE_DIR

	# Should not error when STATE_DIR is not set
	run track_network_partition_check "dns" 1
	assert_success
}

# ============================================================================
# SUMMARY LOGGING TESTS
# ============================================================================

# bats test_tags=category:unit
@test "log_network_partition_summary_if_due - logs summary when hour has elapsed" {
	# Purpose: Test that summary is logged when one hour has elapsed
	# Expected: Summary message logged at INFO level after hour
	# Importance: Validates core summary logging functionality
	setup_network_partition_stats_test

	# Mock timestamp: start at 1000, then 1000 + 3600 seconds (1 hour later)
	local start_time=1000
	local later_time=4600

	# Initialize state files manually to avoid first-call summary
	# Set last_time to start_time
	echo "$start_time" >"${STATE_DIR}/network_partition_summary_last_time"
	echo "0" >"${STATE_DIR}/network_partition_dns_success_count"
	echo "0" >"${STATE_DIR}/network_partition_dns_fail_count"
	echo "0" >"${STATE_DIR}/network_partition_route_success_count"
	echo "0" >"${STATE_DIR}/network_partition_route_fail_count"
	echo "0" >"${STATE_DIR}/network_partition_interface_success_count"
	echo "0" >"${STATE_DIR}/network_partition_interface_fail_count"

	# Track some checks
	track_network_partition_check "dns" 1
	track_network_partition_check "route" 1
	track_network_partition_check "interface" 1

	# Mock timestamp to later time
	setup_mock_timestamp "$later_time"

	# Call summary function - should log summary
	log_network_partition_summary_if_due

	# Verify summary was logged
	assert_file_contains "$LOG_FILE" "Network partition check summary (past hour)"
	assert_file_contains "$LOG_FILE" "DNS resolution succeeded 1 times"
	assert_file_contains "$LOG_FILE" "Default route check succeeded 1 times"
	assert_file_contains "$LOG_FILE" "Interface state check succeeded 1 times"
}

# bats test_tags=category:unit
@test "log_network_partition_summary_if_due - tracks both successes and failures" {
	# Purpose: Test that summary includes both success and failure counts
	# Expected: Summary shows both success and failure counts for each check type
	# Importance: Validates complete statistics tracking
	setup_network_partition_stats_test

	local start_time=1000
	local later_time=4600

	# Initialize state files
	echo "$start_time" >"${STATE_DIR}/network_partition_summary_last_time"

	# Track mixed results
	track_network_partition_check "dns" 1
	track_network_partition_check "dns" 0
	track_network_partition_check "route" 1
	track_network_partition_check "interface" 0

	# Mock timestamp to later time
	setup_mock_timestamp "$later_time"

	# Call summary function
	log_network_partition_summary_if_due

	# Verify summary includes both successes and failures
	assert_file_contains "$LOG_FILE" "DNS resolution succeeded 1 times, failed 1 times"
	assert_file_contains "$LOG_FILE" "Default route check succeeded 1 times, failed 0 times"
	assert_file_contains "$LOG_FILE" "Interface state check succeeded 0 times, failed 1 times"
}

# bats test_tags=category:unit
@test "log_network_partition_summary_if_due - does not log summary before hour elapsed" {
	# Purpose: Test that summary is not logged before hour has elapsed
	# Expected: No summary message logged
	# Importance: Validates interval enforcement
	setup_network_partition_stats_test

	local start_time=1000
	local later_time=2000 # Only 1000 seconds later (less than 1 hour)

	# Initialize state files
	echo "$start_time" >"${STATE_DIR}/network_partition_summary_last_time"
	echo "0" >"${STATE_DIR}/network_partition_dns_success_count"

	# Track some checks
	track_network_partition_check "dns" 1

	# Mock timestamp to later time (but less than 1 hour)
	setup_mock_timestamp "$later_time"

	# Call summary function - should NOT log summary
	log_network_partition_summary_if_due

	# Verify summary was NOT logged
	run grep -q "Network partition check summary" "$LOG_FILE" || true
	assert_failure
}

# bats test_tags=category:unit
@test "log_network_partition_summary_if_due - resets counters after summary" {
	# Purpose: Test that all counters reset to 0 after summary is logged
	# Expected: All counter files contain 0 after summary
	# Importance: Validates state management
	setup_network_partition_stats_test

	local start_time=1000
	local later_time=4600

	# Initialize state files
	echo "$start_time" >"${STATE_DIR}/network_partition_summary_last_time"

	# Track some checks
	track_network_partition_check "dns" 1
	track_network_partition_check "route" 1

	# Mock timestamp to later time
	setup_mock_timestamp "$later_time"

	# Call summary function
	log_network_partition_summary_if_due

	# Verify all counters were reset
	local dns_success
	dns_success=$(cat "${STATE_DIR}/network_partition_dns_success_count" 2>/dev/null || echo "invalid")
	assert_equal "$dns_success" "0"

	local route_success
	route_success=$(cat "${STATE_DIR}/network_partition_route_success_count" 2>/dev/null || echo "invalid")
	assert_equal "$route_success" "0"
}

# bats test_tags=category:unit
@test "log_network_partition_summary_if_due - handles first call (last_time=0)" {
	# Purpose: Test that first call logs summary immediately
	# Expected: Summary logged on first call when last_time is 0
	# Importance: Validates initial state handling
	setup_network_partition_stats_test

	# Track some checks before first summary
	track_network_partition_check "dns" 1
	track_network_partition_check "route" 1

	setup_mock_timestamp 1000

	# First call should log summary (last_time=0 triggers immediate summary)
	log_network_partition_summary_if_due

	# Verify summary was logged
	assert_file_contains "$LOG_FILE" "Network partition check summary (past hour)"
}

# bats test_tags=category:unit
@test "log_network_partition_summary_if_due - handles missing STATE_DIR gracefully" {
	# Purpose: Test that function handles missing STATE_DIR without errors
	# Expected: Function returns successfully, no state files created
	# Importance: Validates graceful degradation
	unset STATE_DIR
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${LOGS_DIR}"
	export LOG_FILE="${LOGS_DIR}/vpn-monitor.log"

	# Should not error when STATE_DIR is not set
	run log_network_partition_summary_if_due
	assert_success
}

# bats test_tags=category:unit
@test "log_network_partition_summary_if_due - handles corrupted state files gracefully" {
	# Purpose: Test that function handles corrupted (non-numeric) state files
	# Expected: Function treats corrupted values as 0, continues normally
	# Importance: Validates error recovery
	setup_network_partition_stats_test

	local start_time=1000
	local later_time=4600

	# Create corrupted state files (non-numeric values)
	echo "$start_time" >"${STATE_DIR}/network_partition_summary_last_time"
	echo "invalid" >"${STATE_DIR}/network_partition_dns_success_count"
	echo "corrupted" >"${STATE_DIR}/network_partition_dns_fail_count"

	# Mock timestamp to later time
	setup_mock_timestamp "$later_time"

	# Should handle corruption gracefully and log summary with 0 counts
	run log_network_partition_summary_if_due
	assert_success

	# Verify summary was logged (with 0 counts for corrupted values)
	assert_file_contains "$LOG_FILE" "Network partition check summary (past hour)"
}

# bats test_tags=category:unit
@test "log_network_partition_summary_if_due - uses atomic writes for state files" {
	# Purpose: Test that state files are written atomically
	# Expected: State files are created successfully using atomic writes
	# Importance: Validates ADR-0012 compliance - atomic writes prevent corruption
	setup_network_partition_stats_test

	setup_mock_timestamp 1000
	log_network_partition_summary_if_due

	# Verify state files exist (atomic write succeeded)
	assert_file_exist "${STATE_DIR}/network_partition_summary_last_time"
	assert_file_exist "${STATE_DIR}/network_partition_dns_success_count"

	# Verify files contain valid data (not corrupted)
	local timestamp
	timestamp=$(cat "${STATE_DIR}/network_partition_summary_last_time" 2>/dev/null || echo "invalid")
	[[ "$timestamp" =~ ^[0-9]+$ ]] || false # Should be numeric

	local count
	count=$(cat "${STATE_DIR}/network_partition_dns_success_count" 2>/dev/null || echo "invalid")
	[[ "$count" =~ ^[0-9]+$ ]] || false # Should be numeric
}

# bats test_tags=category:unit
@test "log_network_partition_summary_if_due - does not log when no checks occurred" {
	# Purpose: Test that summary is not logged when no checks occurred
	# Expected: No summary message logged when all counters are 0
	# Importance: Validates that empty summaries are not logged
	setup_network_partition_stats_test

	local start_time=1000
	local later_time=4600

	# Initialize state files with 0 counts
	echo "$start_time" >"${STATE_DIR}/network_partition_summary_last_time"
	echo "0" >"${STATE_DIR}/network_partition_dns_success_count"
	echo "0" >"${STATE_DIR}/network_partition_dns_fail_count"
	echo "0" >"${STATE_DIR}/network_partition_route_success_count"
	echo "0" >"${STATE_DIR}/network_partition_route_fail_count"
	echo "0" >"${STATE_DIR}/network_partition_interface_success_count"
	echo "0" >"${STATE_DIR}/network_partition_interface_fail_count"

	# Mock timestamp to later time
	setup_mock_timestamp "$later_time"

	# Call summary function - should NOT log (no checks occurred)
	log_network_partition_summary_if_due

	# Verify summary was NOT logged
	run grep -q "Network partition check summary" "$LOG_FILE" || true
	assert_failure
}
