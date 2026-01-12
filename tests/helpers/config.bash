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
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3'
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
	["COOLDOWN_MINUTES"]="required|integer|min:1|max:1440|default:15"
	["MAX_RESTARTS_PER_HOUR"]="required|integer|min:1|max:60|default:3"
	["VPN_NAME"]="optional|string||default:Site-to-Site VPN"
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
	if [[ "$var_name" =~ ^LOCATION_.+_EXTERNAL$ ]]; then
		# LOCATION_*_EXTERNAL pattern: required, string, non-empty
		echo "required|string|non-empty"
		return 0
	elif [[ "$var_name" =~ ^LOCATION_.+_INTERNAL$ ]]; then
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
