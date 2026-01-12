#!/usr/bin/env bash
#
# Detection Test Helpers
#
# This module provides helpers for testing VPN detection functionality.
# It consolidates common patterns for setting up detection test environments,
# mocking timestamps, and configuring detection-related test scenarios.
#
# Usage:
#   load test_helper
#   load helpers/detection
#
#   # Set up ping summary test environment
#   setup_ping_summary_test
#
#   # Set up mock timestamp
#   setup_mock_timestamp 1000
#
#   # Set up ping optional test environment
#   setup_ping_optional_test

# Setup test environment with state directory for ping summary tests
#
# Initializes test directories and environment variables for ping summary tests.
# Sets up STATE_DIR, LOGS_DIR, LOG_FILE, and PING_SUMMARY_INTERVAL_MINUTES.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Creates ${TEST_DIR}/state and ${TEST_DIR}/logs directories
#   - Sets STATE_DIR, LOGS_DIR, LOG_FILE environment variables
#   - Sets PING_SUMMARY_INTERVAL_MINUTES to 7 (default) if not already set
#   - Sets DEBUG to 0 (default) if not already set
#
# Example:
#   setup_ping_summary_test
#   export PING_SUMMARY_INTERVAL_MINUTES=1
#   log_ping_summary_if_due "${TEST_PEER_IP}" ""
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
#
# Sets up a mock date command that returns the specified timestamp.
# This uses the standard mock_date function from test_helper.bash.
#
# Arguments:
#   $1: Timestamp value to mock (Unix timestamp)
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Creates mock date command via mock_date()
#   - Adds mock to PATH via add_mock_to_path()
#
# Example:
#   setup_mock_timestamp 1000
#   local current_time
#   current_time=$(date +%s)
#   assert_equal "$current_time" 1000
setup_mock_timestamp() {
	local timestamp="$1"
	mock_date "$timestamp" 0
	add_mock_to_path
}

# Setup test environment for ping optional tests
#
# Initializes test directories and environment variables for ping-related tests.
# Sets up STATE_DIR, LOGS_DIR, LOG_FILE, and ping-related configuration.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Creates ${TEST_DIR}/state and ${TEST_DIR}/logs directories
#   - Sets STATE_DIR, LOGS_DIR, LOG_FILE environment variables
#   - Sets ENABLE_PING_CHECK=1, PING_COUNT=1, PING_TIMEOUT=1
#   - Sets DEBUG to 0 (default) if not already set
#
# Example:
#   setup_ping_optional_test
#   run check_ping_optional "${TEST_PEER_IP}" ""
#   assert_success
setup_ping_optional_test() {
	STATE_DIR="${TEST_DIR}/state"
	LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${STATE_DIR}"
	mkdir -p "${LOGS_DIR}"
	export STATE_DIR LOGS_DIR
	export LOG_FILE="${LOGS_DIR}/vpn-monitor.log"
	export ENABLE_PING_CHECK=1
	export PING_COUNT=1
	export PING_TIMEOUT=1
	export DEBUG="${DEBUG:-0}"
}
