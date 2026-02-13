#!/usr/bin/env bats
#
# Tests for Resource Monitoring Statistics Tracking
# Tests track_resource_check(), track_resource_constraint(), and
# log_resource_monitoring_summary_if_due() functions.
#

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

# Setup function for resource monitoring stats tests
#
# Sets up test environment for resource monitoring statistics tests.
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
setup_resource_monitoring_stats_test() {
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
@test "track_resource_check - tracks CPU success" {
	setup_resource_monitoring_stats_test

	track_resource_check "cpu" 1

	assert_file_exist "${STATE_DIR}/resource_cpu_check_success_count"
	local count
	count=$(cat "${STATE_DIR}/resource_cpu_check_success_count" 2>/dev/null || echo "0")
	assert_equal "$count" "1"
}

# bats test_tags=category:unit
@test "track_resource_check - tracks RAM failure" {
	setup_resource_monitoring_stats_test

	track_resource_check "ram" 0

	assert_file_exist "${STATE_DIR}/resource_ram_check_fail_count"
	local count
	count=$(cat "${STATE_DIR}/resource_ram_check_fail_count" 2>/dev/null || echo "0")
	assert_equal "$count" "1"
}

# bats test_tags=category:unit
@test "track_resource_check - tracks disk success and increments" {
	setup_resource_monitoring_stats_test

	track_resource_check "disk" 1
	track_resource_check "disk" 1

	local count
	count=$(cat "${STATE_DIR}/resource_disk_check_success_count" 2>/dev/null || echo "0")
	assert_equal "$count" "2"
}

# bats test_tags=category:unit
@test "track_resource_check - handles invalid resource type gracefully" {
	setup_resource_monitoring_stats_test

	run track_resource_check "invalid" 1
	assert_success
	assert_file_not_exist "${STATE_DIR}/resource_invalid_check_success_count"
}

# bats test_tags=category:unit
@test "track_resource_check - handles missing STATE_DIR gracefully" {
	unset STATE_DIR

	run track_resource_check "cpu" 1
	assert_success
}

# ============================================================================
# CONSTRAINT EVENT TESTS
# ============================================================================

# bats test_tags=category:unit
@test "track_resource_constraint - tracks CPU constraint event" {
	setup_resource_monitoring_stats_test

	track_resource_constraint "cpu_constrained"

	assert_file_exist "${STATE_DIR}/resource_cpu_constrained_count"
	local count
	count=$(cat "${STATE_DIR}/resource_cpu_constrained_count" 2>/dev/null || echo "0")
	assert_equal "$count" "1"
}

# bats test_tags=category:unit
@test "track_resource_constraint - tracks disk critical event" {
	setup_resource_monitoring_stats_test

	track_resource_constraint "disk_critical"

	local count
	count=$(cat "${STATE_DIR}/resource_disk_critical_count" 2>/dev/null || echo "0")
	assert_equal "$count" "1"
}

# bats test_tags=category:unit
@test "track_resource_constraint - handles invalid constraint gracefully" {
	setup_resource_monitoring_stats_test

	run track_resource_constraint "invalid_constraint"
	assert_success
	assert_file_not_exist "${STATE_DIR}/resource_invalid_constraint_count"
}

# ============================================================================
# SUMMARY LOGGING TESTS
# ============================================================================

# bats test_tags=category:unit
@test "log_resource_monitoring_summary_if_due - logs summary when hour has elapsed" {
	setup_resource_monitoring_stats_test

	local start_time=1000
	local later_time=4600

	echo "$start_time" >"${STATE_DIR}/resource_monitoring_summary_last_time"

	track_resource_check "cpu" 1
	track_resource_check "ram" 0
	track_resource_check "disk" 1
	track_resource_constraint "cpu_constrained"
	track_resource_constraint "disk_critical"

	setup_mock_timestamp "$later_time"

	log_resource_monitoring_summary_if_due

	assert_file_contains "$LOG_FILE" "Resource monitoring summary (past hour)"
	assert_file_contains "$LOG_FILE" "CPU checks succeeded 1 times, failed 0 times"
	assert_file_contains "$LOG_FILE" "RAM checks succeeded 0 times, failed 1 times"
	assert_file_contains "$LOG_FILE" "Disk checks succeeded 1 times, failed 0 times"
	assert_file_contains "$LOG_FILE" "CPU constrained 1 times"
	assert_file_contains "$LOG_FILE" "Disk critical 1 times"
}

# bats test_tags=category:unit
@test "log_resource_monitoring_summary_if_due - does not log before interval" {
	setup_resource_monitoring_stats_test

	local start_time=1000
	local later_time=2000

	echo "$start_time" >"${STATE_DIR}/resource_monitoring_summary_last_time"

	track_resource_check "cpu" 1

	setup_mock_timestamp "$later_time"
	log_resource_monitoring_summary_if_due

	run grep -q "Resource monitoring summary" "$LOG_FILE" || true
	assert_failure
}

# bats test_tags=category:unit
@test "log_resource_monitoring_summary_if_due - resets counters after logging" {
	setup_resource_monitoring_stats_test

	local start_time=1000
	local later_time=4600
	echo "$start_time" >"${STATE_DIR}/resource_monitoring_summary_last_time"

	track_resource_check "cpu" 1
	track_resource_check "ram" 1
	track_resource_constraint "cpu_constrained"

	setup_mock_timestamp "$later_time"
	log_resource_monitoring_summary_if_due

	local cpu_success
	cpu_success=$(cat "${STATE_DIR}/resource_cpu_check_success_count" 2>/dev/null || echo "invalid")
	assert_equal "$cpu_success" "0"

	local cpu_constrained
	cpu_constrained=$(cat "${STATE_DIR}/resource_cpu_constrained_count" 2>/dev/null || echo "invalid")
	assert_equal "$cpu_constrained" "0"
}

# bats test_tags=category:unit
@test "log_resource_monitoring_summary_if_due - handles first call when last_time=0" {
	setup_resource_monitoring_stats_test

	track_resource_check "cpu" 1
	setup_mock_timestamp 1000

	log_resource_monitoring_summary_if_due

	assert_file_contains "$LOG_FILE" "Resource monitoring summary (past hour)"
}

# bats test_tags=category:unit
@test "log_resource_monitoring_summary_if_due - handles missing STATE_DIR gracefully" {
	unset STATE_DIR
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${LOGS_DIR}"
	export LOG_FILE="${LOGS_DIR}/vpn-monitor.log"

	run log_resource_monitoring_summary_if_due
	assert_success
}

# bats test_tags=category:unit
@test "log_resource_monitoring_summary_if_due - handles corrupted state files gracefully" {
	# Purpose: Test that function handles corrupted (non-numeric) state files
	# Expected: Function treats corrupted values as 0, continues normally
	# Importance: Validates error recovery
	setup_resource_monitoring_stats_test

	local start_time=1000
	local later_time=4600

	# Set last_time to start_time
	echo "$start_time" >"${STATE_DIR}/resource_monitoring_summary_last_time"

	# Track some checks first (so there are non-zero counts to log)
	track_resource_check "cpu" 1
	track_resource_check "ram" 1

	# Now corrupt some state files (non-numeric values)
	# The function should treat these as 0 when reading
	echo "invalid" >"${STATE_DIR}/resource_cpu_check_success_count"
	echo "corrupted" >"${STATE_DIR}/resource_ram_check_fail_count"

	# Mock timestamp to later time (1 hour later)
	setup_mock_timestamp "$later_time"

	# Should handle corruption gracefully - corrupted values treated as 0,
	# but other valid counts (ram success) should still be logged
	run log_resource_monitoring_summary_if_due
	assert_success

	# Verify summary was logged (corrupted CPU counts treated as 0, RAM counts logged)
	assert_file_contains "$LOG_FILE" "Resource monitoring summary (past hour)"
	assert_file_contains "$LOG_FILE" "CPU checks succeeded 0 times"
	assert_file_contains "$LOG_FILE" "RAM checks succeeded 1 times"
}

# bats test_tags=category:unit
@test "log_resource_monitoring_summary_if_due - does not log when no checks occurred" {
	setup_resource_monitoring_stats_test

	local start_time=1000
	local later_time=4600
	echo "$start_time" >"${STATE_DIR}/resource_monitoring_summary_last_time"

	setup_mock_timestamp "$later_time"
	log_resource_monitoring_summary_if_due

	run grep -q "Resource monitoring summary" "$LOG_FILE" || true
	assert_failure
}
