#!/usr/bin/env bats
#
# Tests for Logging Prefix Functionality
# Tests log_message and handle_error functions with SYSTEM and location-specific prefixes
#

load test_helper

# Source logging functions directly for unit testing
source_logging_functions() {
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
}

# bats test_tags=category:unit,priority:high
@test "log_message with SYSTEM prefix formats correctly" {
	# Purpose: Test verifies that log_message formats messages correctly with SYSTEM prefix
	# Expected: Log entry format: [timestamp] [LEVEL] SYSTEM: message
	# Importance: SYSTEM prefix is used for system-level messages; format must be correct
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	log_message "INFO" "SYSTEM" "Test system message"

	assert_file_exist "$log_file"
	run grep -E "^\[.*\] \[INFO\] SYSTEM: Test system message" "$log_file"
	assert_success
}

# bats test_tags=category:unit,priority:high
@test "log_message with location prefix formats correctly" {
	# Purpose: Test verifies that log_message formats messages correctly with location prefix
	# Expected: Log entry format: [timestamp] [LEVEL] LOCATION: message
	# Importance: Location prefixes help identify which location has issues; format must be correct
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	log_message "WARNING" "NYC" "Test location message"

	assert_file_exist "$log_file"
	run grep -E "^\[.*\] \[WARNING\] NYC: Test location message" "$log_file"
	assert_success
}

# bats test_tags=category:unit,priority:high
@test "log_message with empty prefix falls back to SYSTEM" {
	# Purpose: Test verifies that log_message handles empty prefix gracefully
	# Expected: Empty prefix falls back to SYSTEM and logs error to stderr
	# Importance: Defensive programming - handles edge cases gracefully
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	# Capture stderr separately to check for error message
	# Note: log_message writes error to stderr when prefix is empty
	local stderr_file="${TEST_DIR}/stderr.log"
	log_message "INFO" "" "Test message" 2>"$stderr_file"

	# Should use SYSTEM as fallback (function returns 0, but logs error to stderr)
	# The function doesn't fail, it just logs an error and continues

	# Should use SYSTEM as fallback in log file
	assert_file_exist "$log_file"
	run grep -E "^\[.*\] \[INFO\] SYSTEM: Test message" "$log_file"
	assert_success

	# Should log error about missing prefix to stderr
	# Error message format: [timestamp] [ERROR] SYSTEM: log_message called without prefix - this is a bug
	if [[ -f "$stderr_file" ]]; then
		run grep -q "log_message called without prefix" "$stderr_file"
		assert_success
	fi
}

# bats test_tags=category:unit,priority:high
@test "log_message with all log levels formats correctly" {
	# Purpose: Test verifies that log_message formats all log levels correctly
	# Expected: All levels (INFO, WARNING, ERROR, DEBUG) format correctly
	# Importance: All log levels must work correctly with prefix functionality
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	log_message "INFO" "SYSTEM" "Info message"
	log_message "WARNING" "SYSTEM" "Warning message"
	log_message "ERROR" "SYSTEM" "Error message"
	DEBUG=1 log_message "DEBUG" "SYSTEM" "Debug message"

	assert_file_exist "$log_file"
	run grep -E "^\[.*\] \[INFO\] SYSTEM: Info message" "$log_file"
	assert_success
	run grep -E "^\[.*\] \[WARNING\] SYSTEM: Warning message" "$log_file"
	assert_success
	run grep -E "^\[.*\] \[ERROR\] SYSTEM: Error message" "$log_file"
	assert_success
	run grep -E "^\[.*\] \[DEBUG\] SYSTEM: Debug message" "$log_file"
	assert_success
}

# bats test_tags=category:unit,priority:high
@test "handle_error with SYSTEM prefix formats correctly" {
	# Purpose: Test verifies that handle_error formats messages correctly with SYSTEM prefix
	# Expected: Error message format: [timestamp] [LEVEL] SYSTEM: message
	# Importance: handle_error must work correctly with prefix functionality
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	handle_error "WARNING" "SYSTEM" "Test warning message" 0

	assert_file_exist "$log_file"
	run grep -E "^\[.*\] \[WARNING\] SYSTEM: Test warning message" "$log_file"
	assert_success
}

# bats test_tags=category:unit,priority:high
@test "handle_error with location prefix formats correctly" {
	# Purpose: Test verifies that handle_error formats messages correctly with location prefix
	# Expected: Error message format: [timestamp] [LEVEL] LOCATION: message
	# Importance: Location-specific error messages help identify which location has issues
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	handle_error "ERROR" "NYC" "Test error message" 0

	assert_file_exist "$log_file"
	run grep -E "^\[.*\] \[ERROR\] NYC: Test error message" "$log_file"
	assert_success
}

# bats test_tags=category:unit,priority:high
@test "handle_error with exit code 0 does not exit" {
	# Purpose: Test verifies that handle_error with exit code 0 does not exit script
	# Expected: Function returns 0 and does not exit
	# Importance: Non-fatal errors should not cause script exit
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	# Should not exit
	run handle_error "ERROR" "SYSTEM" "Test error" 0
	assert_success

	assert_file_exist "$log_file"
	run grep -E "^\[.*\] \[ERROR\] SYSTEM: Test error" "$log_file"
	assert_success
}

# bats test_tags=category:unit,priority:high
@test "handle_error with exit code 1 exits script" {
	# Purpose: Test verifies that handle_error with exit code 1 exits script
	# Expected: Function calls die() which exits with code 1
	# Importance: Fatal errors should cause script exit
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	# Should exit with code 1
	run handle_error "ERROR" "SYSTEM" "Fatal error" 1
	assert_failure
	assert_equal "$status" 1

	assert_file_exist "$log_file"
	run grep -E "^\[.*\] \[ERROR\] SYSTEM: Fatal error" "$log_file"
	assert_success
}

# bats test_tags=category:unit,priority:high
@test "handle_error with custom exit code exits with that code" {
	# Purpose: Test verifies that handle_error exits with specified exit code
	# Expected: Function exits with custom exit code (e.g., 3)
	# Importance: Different exit codes allow callers to distinguish error types
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	# Should exit with code 3
	run handle_error "ERROR" "SYSTEM" "Custom error" 3
	assert_failure
	assert_equal "$status" 3

	assert_file_exist "$log_file"
	run grep -E "^\[.*\] \[ERROR\] SYSTEM: Custom error" "$log_file"
	assert_success
}

# bats test_tags=category:unit,priority:high
@test "handle_error with WARNING severity does not exit even with non-zero code" {
	# Purpose: Test verifies that handle_error with WARNING severity does not exit
	# Expected: WARNING severity never exits, even with non-zero exit code
	# Importance: Warnings should not cause script exit
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	# Should not exit (WARNING severity)
	run handle_error "WARNING" "SYSTEM" "Warning message" 1
	assert_success

	assert_file_exist "$log_file"
	run grep -E "^\[.*\] \[WARNING\] SYSTEM: Warning message" "$log_file"
	assert_success
}

# bats test_tags=category:unit,priority:high
@test "handle_error_or_exit_fake_mode with SYSTEM prefix formats correctly" {
	# Purpose: Test verifies that handle_error_or_exit_fake_mode formats correctly with SYSTEM prefix
	# Expected: Message format: [timestamp] [ERROR] SYSTEM: message
	# Importance: handle_error_or_exit_fake_mode must work correctly with prefix functionality
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	# Enable fake mode
	export NO_ESCALATE=1

	# Should return 1 in fake mode (not exit)
	run handle_error_or_exit_fake_mode "SYSTEM" "Test error message" 2
	assert_failure
	assert_equal "$status" 1

	assert_file_exist "$log_file"
	run grep -E "^\[.*\] \[ERROR\] SYSTEM: Test error message" "$log_file"
	assert_success
}

# bats test_tags=category:unit,priority:high
@test "handle_error_or_exit_fake_mode with location prefix formats correctly" {
	# Purpose: Test verifies that handle_error_or_exit_fake_mode formats correctly with location prefix
	# Expected: Message format: [timestamp] [ERROR] LOCATION: message
	# Importance: Location-specific error messages help identify which location has issues
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	# Enable fake mode
	export NO_ESCALATE=1

	# Should return 1 in fake mode (not exit)
	run handle_error_or_exit_fake_mode "NYC" "Test error message" 3
	assert_failure
	assert_equal "$status" 1

	assert_file_exist "$log_file"
	run grep -E "^\[.*\] \[ERROR\] NYC: Test error message" "$log_file"
	assert_success
}

# bats test_tags=category:unit,priority:high
@test "handle_error_or_exit_fake_mode exits in normal mode" {
	# Purpose: Test verifies that handle_error_or_exit_fake_mode exits in normal mode
	# Expected: Function calls die() which exits with specified code
	# Importance: Fatal errors should cause script exit in normal mode
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	# Disable fake mode
	export NO_ESCALATE=0

	# Should exit with code 2
	run handle_error_or_exit_fake_mode "SYSTEM" "Fatal error" 2
	assert_failure
	assert_equal "$status" 2

	assert_file_exist "$log_file"
	run grep -E "^\[.*\] \[ERROR\] SYSTEM: Fatal error" "$log_file"
	assert_success
}

# bats test_tags=category:unit,priority:high
@test "log_message with multiple arguments concatenates correctly" {
	# Purpose: Test verifies that log_message concatenates multiple arguments correctly
	# Expected: All arguments after prefix are concatenated with spaces
	# Importance: log_message should handle multiple message arguments correctly
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	log_message "INFO" "SYSTEM" "Message" "part" "1" "and" "part" "2"

	assert_file_exist "$log_file"
	run grep -E "^\[.*\] \[INFO\] SYSTEM: Message part 1 and part 2" "$log_file"
	assert_success
}

# bats test_tags=category:unit,priority:high
@test "log_message output to stderr for ERROR level" {
	# Purpose: Test verifies that ERROR level messages output to stderr
	# Expected: ERROR messages appear in stderr output
	# Importance: ERROR messages should be visible even if log file fails
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	run log_message "ERROR" "SYSTEM" "Error message" 2>&1

	assert_file_exist "$log_file"
	# Should appear in stderr
	assert_output --regexp "\[.*\] \[ERROR\] SYSTEM: Error message"
}

# bats test_tags=category:unit,priority:high
@test "log_message output to stderr for WARNING level" {
	# Purpose: Test verifies that WARNING level messages output to stderr
	# Expected: WARNING messages appear in stderr output
	# Importance: WARNING messages should be visible even if log file fails
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	run log_message "WARNING" "NYC" "Warning message" 2>&1

	assert_file_exist "$log_file"
	# Should appear in stderr
	assert_output --regexp "\[.*\] \[WARNING\] NYC: Warning message"
}

# bats test_tags=category:unit,priority:high
@test "log_message with location_name fallback pattern works correctly" {
	# Purpose: Test verifies that ${location_name:-SYSTEM} pattern works correctly
	# Expected: Empty location_name falls back to SYSTEM, non-empty uses location_name
	# Importance: Defensive programming pattern must work correctly
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	# Test with empty location_name
	local location_name=""
	log_message "INFO" "${location_name:-SYSTEM}" "Test message"
	run grep -E "^\[.*\] \[INFO\] SYSTEM: Test message" "$log_file"
	assert_success

	# Test with location_name
	location_name="NYC"
	log_message "INFO" "${location_name:-SYSTEM}" "Test message"
	run grep -E "^\[.*\] \[INFO\] NYC: Test message" "$log_file"
	assert_success
}
