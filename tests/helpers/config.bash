#!/usr/bin/env bash
#
# Config Test Helpers
#
# This module provides helpers for testing configuration functionality.
# It consolidates common patterns for creating test config files, validating
# config schemas, and setting up config test environments.
#
# Usage:
#   load test_helper
#   load helpers/config
#
#   # Create a test config file
#   create_test_config "${TEST_DIR}/config" "VAR1=value1" "VAR2=value2"
#
#   # Create a valid config file
#   create_valid_config "${TEST_DIR}/config"
#
#   # Create test lib directory
#   create_test_lib "${TEST_DIR}"

# Create a test config file with specified variables
#
# Creates a config file with the provided variable assignments.
# Used to test various config scenarios.
#
# Arguments:
#   $1: Config file path
#   $2+: Variable assignments (e.g., "VAR1=value1" "VAR2=value2")
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Creates config file directory if it doesn't exist
#   - Creates config file with variable assignments
#
# Example:
#   create_test_config "${TEST_DIR}/config" \
#       "LOCATION_NYC_EXTERNAL=\"192.168.1.1\"" \
#       "TIER1_THRESHOLD=1"
create_test_config() {
	local config_file="$1"
	shift
	mkdir -p "$(dirname "$config_file")"

	cat >"$config_file" <<EOF
# Test configuration file
EOF

	# Add each variable assignment
	for var_assignment in "$@"; do
		echo "$var_assignment" >>"$config_file"
	done
}

# Create a minimal valid config file
#
# Creates a config file with all required settings for basic functionality.
# Uses TEST_PEER_IP for the location external IP.
#
# Arguments:
#   $1: Config file path
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Creates config file with required variables
#
# Example:
#   create_valid_config "${TEST_DIR}/config"
#   # Config file now has all required settings
create_valid_config() {
	local config_file="$1"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=2' \
		'TIER3_THRESHOLD=3' \
		'MAX_RESTARTS_PER_WINDOW=20' \
		'RATE_LIMIT_WINDOW_MINUTES=60'
}

# Create a test lib directory with config_schema.sh
#
# Creates a lib directory and copies the project's lib/config_schema.sh into it
# so tests use the real schema and can catch schema validation regressions.
# Requires the repository lib/config_schema.sh to exist (run tests from repo root).
#
# Arguments:
#   $1: Base directory (lib will be created here)
#
# Returns:
#   0: Success (lib created, config_schema.sh copied)
#   1: Project lib/config_schema.sh not found
#
# Side effects:
#   - Creates lib directory structure
#   - Copies lib/config_schema.sh from project
#
# Example:
#   create_test_lib "${TEST_DIR}"
#   # lib/config_schema.sh now exists (copy of project schema)
create_test_lib() {
	local base_dir="$1"
	local lib_dir="${base_dir}/lib"
	local real_schema="${BATS_TEST_DIRNAME}/../lib/config_schema.sh"

	mkdir -p "$lib_dir"

	if [[ ! -f "$real_schema" ]]; then
		echo "create_test_lib: project lib/config_schema.sh not found at $real_schema (run tests from repository root)" >&2
		return 1
	fi
	cp "$real_schema" "${lib_dir}/config_schema.sh"
}

# Copy compare-config.sh script and its dependencies to test directory
#
# Copies the compare-config.sh script to the test directory along with
# lib/common.sh which it depends on. This allows the script to run
# from the test directory and find its dependencies.
#
# Arguments:
#   $1: Test directory where script should be copied
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Copies compare-config.sh to test directory
#   - Creates lib directory in test directory
#   - Copies lib/common.sh to test directory
#   - Makes script executable
#
# Example:
#   copy_compare_config_script "${TEST_DIR}/test-compare"
#   # Script is now at ${TEST_DIR}/test-compare/compare-config.sh
#   # lib/common.sh is at ${TEST_DIR}/test-compare/lib/common.sh
copy_compare_config_script() {
	local test_dir="$1"
	local script_path="${BATS_TEST_DIRNAME}/../compare-config.sh"

	# Copy script to test directory
	if [[ -f "$script_path" ]]; then
		cp "$script_path" "${test_dir}/compare-config.sh"
		chmod +x "${test_dir}/compare-config.sh"
	fi

	# Copy lib directory so script can find lib/common.sh
	mkdir -p "${test_dir}/lib"
	if [[ -f "${BATS_TEST_DIRNAME}/../lib/common.sh" ]]; then
		cp "${BATS_TEST_DIRNAME}/../lib/common.sh" "${test_dir}/lib/common.sh"
	fi
}
