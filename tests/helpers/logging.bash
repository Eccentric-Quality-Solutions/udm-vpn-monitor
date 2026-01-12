#!/usr/bin/env bash
#
# Logging Test Helpers
#
# This module provides helpers for testing logging functionality.
# It consolidates common patterns for sourcing logging functions and
# setting up logging test environments.
#
# Usage:
#   load test_helper
#   load helpers/logging
#
#   # Source logging functions for unit testing
#   source_logging_functions
#
#   # Run test that uses logging
#   run some_function_that_logs
#   assert_file_contains "$LOG_FILE" "expected log message"

# Source logging functions directly for unit testing
#
# Sources the common.sh and logging.sh library files needed for testing
# logging functionality. This is a convenience function to avoid repeating
# the source commands in multiple test files.
#
# Returns:
#   0: Always succeeds (even if files don't exist, to avoid test failures)
#
# Side effects:
#   - Sources lib/common.sh
#   - Sources lib/logging.sh
#
# Example:
#   source_logging_functions
#   run log_message "INFO" "Test message"
#   assert_file_contains "$LOG_FILE" "Test message"
source_logging_functions() {
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
}
