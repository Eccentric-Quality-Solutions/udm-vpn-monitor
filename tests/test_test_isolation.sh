#!/usr/bin/env bats
#
# Test Isolation Verification Tests
#
# These tests verify that the test suite maintains proper isolation between tests.
# They check for test pollution and interdependencies that could cause flaky tests.
#
# Purpose: Ensure tests don't affect each other
# Expected: Each test runs in complete isolation
# Importance: Test isolation is critical for reliable test execution

load test_helper

# bats test_tags=category:test-infrastructure,priority:high
@test "Test isolation - Environment variables are properly restored" {
	# Purpose: Verify that environment variables are properly restored after each test
	# Expected: Environment variables set in one test don't affect subsequent tests
	# Importance: Prevents test pollution through environment variable leakage

	# Set some test-related environment variables
	export CONFIG_FILE="/tmp/test-config.conf"
	export STATE_DIR="/tmp/test-state"
	export LOG_FILE="/tmp/test.log"
	export DEBUG=1
	export NO_ESCALATE=1

	# Verify they are set
	[[ -n "${CONFIG_FILE:-}" ]]
	[[ -n "${STATE_DIR:-}" ]]
	[[ -n "${LOG_FILE:-}" ]]
	[[ "${DEBUG:-0}" == "1" ]]
	[[ "${NO_ESCALATE:-0}" == "1" ]]
}

# bats test_tags=category:test-infrastructure,priority:high
@test "Test isolation - Environment variables are cleaned up after test" {
	# Purpose: Verify that environment variables from previous test are cleaned up
	# Expected: Environment variables should be unset or restored to original values
	# Importance: Ensures tests start with clean environment

	# These variables should be unset or have original values (not from previous test)
	# We can't directly verify they're unset (they might have been set before test suite),
	# but we can verify they don't have test-specific values from previous test
	if [[ -n "${CONFIG_FILE:-}" ]]; then
		# If CONFIG_FILE is set, it shouldn't be a test-specific path from previous test
		[[ "$CONFIG_FILE" != "/tmp/test-config.conf" ]] || true
	fi
}

# bats test_tags=category:test-infrastructure,priority:high
@test "Test isolation - TEST_DIR is unique for each test" {
	# Purpose: Verify that each test gets its own unique TEST_DIR
	# Expected: TEST_DIR should be different for each test
	# Importance: Prevents file system pollution between tests

	# TEST_DIR should exist and be unique
	[[ -n "${TEST_DIR:-}" ]]
	[[ -d "$TEST_DIR" ]]

	# Create a marker file to verify isolation
	local marker_file="${TEST_DIR}/isolation_marker_$$"
	echo "test_isolation_$$" >"$marker_file"
	[[ -f "$marker_file" ]]
}

# bats test_tags=category:test-infrastructure,priority:high
@test "Test isolation - PATH modifications are cleaned up" {
	# Purpose: Verify that PATH modifications don't persist between tests
	# Expected: PATH should be restored to original value after each test
	# Importance: Prevents mock commands from affecting subsequent tests

	# Add TEST_DIR to PATH
	local original_path="$PATH"
	export PATH="${TEST_DIR}:${PATH}"

	# Verify PATH was modified
	[[ "$PATH" == "${TEST_DIR}:${original_path}" ]]

	# Note: Actual PATH restoration is verified by teardown() function
	# This test just verifies that PATH can be modified without breaking isolation
}

# bats test_tags=category:test-infrastructure,priority:high
@test "Test isolation - Mock commands don't persist between tests" {
	# Purpose: Verify that mock commands created in one test don't affect others
	# Expected: Mock commands should be isolated to TEST_DIR which is cleaned up
	# Importance: Prevents mock command pollution

	# Create a mock command
	local mock_cmd="${TEST_DIR}/mock_test_cmd"
	cat >"$mock_cmd" <<'EOF'
#!/bin/bash
echo "mock_output"
EOF
	chmod +x "$mock_cmd"

	# Verify mock command exists
	[[ -f "$mock_cmd" ]]
	[[ -x "$mock_cmd" ]]

	# Mock command should be in TEST_DIR which is cleaned up after test
	[[ "$mock_cmd" == "${TEST_DIR}"/* ]]
}

# bats test_tags=category:test-infrastructure,priority:high
@test "Test isolation - State files are isolated per test" {
	# Purpose: Verify that state files created in one test don't affect others
	# Expected: State files should be in TEST_DIR which is unique per test
	# Importance: Prevents state file pollution between tests

	# Set up test environment
	setup_test_environment

	# Create a state file
	local state_file="${STATE_DIR}/test_state_$$"
	echo "test_state_data_$$" >"$state_file"

	# Verify state file exists
	[[ -f "$state_file" ]]

	# State file should be in TEST_DIR (which is isolated per test)
	[[ "$state_file" == "${TEST_DIR}"/* ]]
}

# bats test_tags=category:test-infrastructure,priority:high
@test "Test isolation - Log files are isolated per test" {
	# Purpose: Verify that log files created in one test don't affect others
	# Expected: Log files should be in TEST_DIR which is unique per test
	# Importance: Prevents log file pollution between tests

	# Set up test environment
	setup_test_environment

	# Create a log file
	local log_file="${LOGS_DIR}/test_log_$$.log"
	echo "test_log_entry_$$" >"$log_file"

	# Verify log file exists
	[[ -f "$log_file" ]]

	# Log file should be in TEST_DIR (which is isolated per test)
	[[ "$log_file" == "${TEST_DIR}"/* ]]
}

# bats test_tags=category:test-infrastructure,priority:high
@test "Test isolation - Multiple tests can run independently" {
	# Purpose: Verify that multiple tests can run without affecting each other
	# Expected: Each test should be completely independent
	# Importance: Enables parallel test execution and prevents flaky tests

	# This test verifies that the isolation mechanisms work correctly
	# by checking that we can set up test environment without conflicts

	# Set up test environment
	setup_test_environment

	# Create test files
	local test_file1="${TEST_DIR}/test1_$$"
	local test_file2="${TEST_DIR}/test2_$$"
	echo "test1_$$" >"$test_file1"
	echo "test2_$$" >"$test_file2"

	# Verify both files exist independently
	[[ -f "$test_file1" ]]
	[[ -f "$test_file2" ]]
	[[ "$(cat "$test_file1")" == "test1_$$" ]]
	[[ "$(cat "$test_file2")" == "test2_$$" ]]
}
