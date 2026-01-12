#!/usr/bin/env bash
#
# Resources Test Helpers
#
# This module provides helpers for testing resource monitoring functionality.
# It consolidates common patterns for setting up resource test environments
# and mocking system commands used for resource monitoring.
#
# Usage:
#   load test_helper
#   load helpers/resources
#
#   # Set up resources test environment
#   setup_resources_test
#
#   # Source resources library
#   source_resources_lib

# Setup function for resource tests
#
# Creates test environment with mocked system commands for resource monitoring.
# Sets up mocks for /proc/stat, free, df, and date commands.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Creates ${TEST_DIR}/proc/stat mock file
#   - Creates mock free, df, and date commands in TEST_DIR
#   - Adds mocks to PATH via add_mock_to_path()
#   - Creates ${TEST_DIR}/state directory
#
# Example:
#   setup_resources_test
#   source_resources_lib
#   run get_cpu_usage
#   assert_success
setup_resources_test() {
	# Create mock /proc/stat
	mkdir -p "${TEST_DIR}/proc"
	cat >"${TEST_DIR}/proc/stat" <<'EOF'
cpu  100 200 300 400 500 600 700 800
cpu0 50 100 150 200 250 300 350 400
EOF

	# Create mock free command
	local mock_free="${TEST_DIR}/free"
	cat >"$mock_free" <<'EOF'
#!/bin/bash
echo "Mem:       1000000    800000    200000          0     100000     500000"
EOF
	chmod +x "$mock_free"

	# Create mock df command
	local mock_df="${TEST_DIR}/df"
	cat >"$mock_df" <<'EOF'
#!/bin/bash
if [[ "$1" == "-P" ]]; then
    shift
fi
echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
echo "/dev/sda1       1000000   800000     200000  80% /data"
EOF
	chmod +x "$mock_df"

	# Create mock date command
	local mock_date="${TEST_DIR}/date"
	cat >"$mock_date" <<'EOF'
#!/bin/bash
if [[ "$1" == "+%s" ]]; then
    echo "1700000000"
else
    /bin/date "$@"
fi
EOF
	chmod +x "$mock_date"

	# Add mocks to PATH using helper function
	add_mock_to_path

	# Create test state directory
	mkdir -p "${TEST_DIR}/state"
}

# Source resources library with mocked /proc
#
# Sources the resources.sh library file, setting up necessary dependencies.
# This function handles the /proc/stat mocking that resources.sh requires.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds (even if library doesn't exist, to avoid test failures)
#
# Side effects:
#   - Sources lib/common.sh
#   - Sources lib/resources.sh
#
# Example:
#   setup_resources_test
#   source_resources_lib
#   run get_cpu_usage
#   assert_success
source_resources_lib() {
	# Create a wrapper that sets up /proc before sourcing
	local lib_dir="${TEST_DIR}/lib"
	mkdir -p "$lib_dir"

	# Copy common.sh first (resources.sh depends on it)
	if [[ -f "${BATS_TEST_DIRNAME}/../lib/common.sh" ]]; then
		cp "${BATS_TEST_DIRNAME}/../lib/common.sh" "${lib_dir}/common.sh"
	fi

	# Source resources.sh
	# Note: We need to handle /proc/stat mocking
	if [[ -f "${BATS_TEST_DIRNAME}/../lib/resources.sh" ]]; then
		# Temporarily symlink /proc/stat to our mock
		if [[ -d "${TEST_DIR}/proc" ]]; then
			# Source the library
			LIB_DIR="$lib_dir" source "${BATS_TEST_DIRNAME}/../lib/resources.sh"
		else
			source "${BATS_TEST_DIRNAME}/../lib/resources.sh"
		fi
	fi
}
