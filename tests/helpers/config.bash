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
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'MAX_RESTARTS_PER_WINDOW=20' \
		'RATE_LIMIT_WINDOW_MINUTES=60'
}

# Create a test lib directory with config_schema.sh
#
# Creates a lib directory structure with a minimal config_schema.sh
# that matches the real schema structure. If the real config_schema.sh
# exists, it copies it; otherwise creates a minimal version for testing.
#
# Arguments:
#   $1: Base directory (lib will be created here)
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Creates lib directory structure
#   - Creates or copies config_schema.sh
#
# Example:
#   create_test_lib "${TEST_DIR}"
#   # lib/config_schema.sh now exists
create_test_lib() {
	local base_dir="$1"
	local lib_dir="${base_dir}/lib"
	mkdir -p "$lib_dir"

	# Copy the real config_schema.sh if available, otherwise create minimal version
	if [[ -f "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" ]]; then
		cp "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" "${lib_dir}/config_schema.sh"
	else
		# Create minimal schema for testing
		cat >"${lib_dir}/config_schema.sh" <<'EOF'
#!/bin/bash
declare -A CONFIG_SCHEMA=(
	["TIER1_THRESHOLD"]="required|integer|min:1|default:1"
	["TIER2_THRESHOLD"]="required|integer|min:TIER1_THRESHOLD|default:3"
	["TIER3_THRESHOLD"]="required|integer|min:TIER2_THRESHOLD|default:5"
	["MAX_RESTARTS_PER_WINDOW"]="required|integer|min:1|max:20|default:20"
	["RATE_LIMIT_WINDOW_MINUTES"]="required|integer|min:5|max:1440|default:60"
	["NO_ESCALATE"]="optional|integer|values:0,1|default:0"
	["RECOVERY_VERIFY_TIMEOUT"]="optional|integer|min:10|max:300|default:30"
	["LOGS_DIR"]="optional|string||default:"
)

# Get configuration schema for a variable
#
# Arguments:
#   $1: Variable name
#
# Returns:
#   0: Schema found and printed to stdout
#   1: Variable not found in schema
get_config_schema() {
	local var_name="$1"
	# Check exact match first
	if [[ -n "${CONFIG_SCHEMA[$var_name]:-}" ]]; then
		echo "${CONFIG_SCHEMA[$var_name]}"
		return 0
	fi
	# Check pattern matches for location-based variables
	# Pattern restricts to valid identifier characters (A-Za-z0-9_) to match extract_location_name() validation
	if [[ "$var_name" =~ ^LOCATION_[A-Za-z0-9_]+_EXTERNAL$ ]]; then
		# LOCATION_*_EXTERNAL pattern: required, string, non-empty
		echo "required|string|non-empty"
		return 0
	elif [[ "$var_name" =~ ^LOCATION_[A-Za-z0-9_]+_INTERNAL$ ]]; then
		# LOCATION_*_INTERNAL pattern: optional, string
		echo "optional|string"
		return 0
	fi
	return 1
}

# Get default value for a configuration variable
#
# Arguments:
#   $1: Variable name
#
# Returns:
#   0: Default value found and printed to stdout
#   1: Variable not found in schema
get_config_default() {
	local var_name="$1"
	local schema
	schema=$(get_config_schema "$var_name")
	if [[ -z "$schema" ]]; then
		return 1
	fi
	if [[ "$schema" =~ default:([^|]+)$ ]]; then
		echo "${BASH_REMATCH[1]}"
	else
		echo ""
	fi
	return 0
}
EOF
	fi
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
