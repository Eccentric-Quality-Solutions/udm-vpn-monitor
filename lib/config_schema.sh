#!/bin/bash
#
# Configuration schema definition for UDM VPN Monitor
# Defines validation rules for all configuration variables
#
# Version: 0.0.1
#

# Configuration schema definition
#
# Format: CONFIG_SCHEMA["variable_name"]="required|type|rules|default"
#   - required: "required" or "optional"
#   - type: "string" or "integer"
#   - rules: comma-separated list of validation rules:
#     * non-empty: value must not be empty (for strings)
#     * min:N: minimum value (for integers)
#     * max:N: maximum value (for integers)
#     * values:V1,V2,V3: allowed values (for integers or strings)
#     * min:VAR: minimum value must be >= value of VAR (for integers)
#   - default: default value if optional and not set
#
# LIMITATION: The pipe character (|) is used as a delimiter in the schema format.
# Therefore, default values CANNOT contain pipe characters. If a default value
# contains a pipe, it will be incorrectly parsed. Current defaults don't contain
# pipes, so this limitation is acceptable. If pipe characters are needed in
# defaults, the schema format would need to be redesigned (e.g., use a different
# delimiter or implement escaping).
#
# Examples:
#   ["EXTERNAL_PEER_IPS"]="required|string|non-empty"
#   ["TIER1_THRESHOLD"]="required|integer|min:1"
#   ["TIER2_THRESHOLD"]="required|integer|min:TIER1_THRESHOLD"
#   ["ENABLE_PING_CHECK"]="optional|integer|values:0,1|default:1"
#
# NOTE: Default values are defined in TWO places:
# 1. In lib/config.sh (load_config function) - For backward compatibility
# 2. Here in CONFIG_SCHEMA - For schema-based validation and correction
#
# IMPORTANT: Default values MUST match between both locations.
# Schema defaults take precedence during validation and will override
# load_config() defaults if they differ. To change defaults, update BOTH:
#   - lib/config.sh (load_config function)
#   - This file (CONFIG_SCHEMA array)
#
# Purpose of dual defaults:
#   - load_config() defaults: Early initialization, backward compatibility
#   - Schema defaults: Validation, correction of invalid values, consistency
declare -A CONFIG_SCHEMA=(
	# Required configuration
	["EXTERNAL_PEER_IPS"]="required|string|non-empty"
	["INTERNAL_PEER_IPS"]="optional|string||default:"
	["TIER1_THRESHOLD"]="required|integer|min:1"
	# NOTE: TIER2_THRESHOLD has relative validation (depends on TIER1_THRESHOLD)
	# Validation order is handled safely - see validate_config_schema() documentation
	["TIER2_THRESHOLD"]="required|integer|min:TIER1_THRESHOLD"
	# NOTE: TIER3_THRESHOLD has relative validation (depends on TIER2_THRESHOLD)
	# Validation order is handled safely - see validate_config_schema() documentation
	["TIER3_THRESHOLD"]="required|integer|min:TIER2_THRESHOLD"
	["COOLDOWN_MINUTES"]="required|integer|min:1|max:1440"
	["MAX_RESTARTS_PER_HOUR"]="required|integer|min:1|max:60"

	# Optional configuration with defaults
	["VPN_NAME"]="optional|string||default:Site-to-Site VPN"
	["ENABLE_PING_CHECK"]="optional|integer|values:0,1|default:1"
	["PING_TARGET_IP"]="optional|string||default:"
	["PING_COUNT"]="optional|integer|min:1|max:10|default:3"
	["PING_TIMEOUT"]="optional|integer|min:1|max:30|default:2"
	["DEBUG"]="optional|integer|values:0,1|default:0"
	["NO_ESCALATE"]="optional|integer|values:0,1|default:0"
	# EXPERIMENTAL: xfrm-based recovery (disabled by default - see SWANCTL_ALTERNATIVES.md for risks)
	["ENABLE_XFRM_RECOVERY"]="optional|integer|values:0,1|default:0"
	["LOCKFILE_TIMEOUT"]="optional|integer|min:60|max:3600|default:300"
	["LOG_FILE"]="optional|string||default:"
	["STATE_DIR"]="optional|string||default:"
	["LOGS_DIR"]="optional|string||default:"
	["CRON_SCHEDULE"]="optional|string||default:*/1 * * * *"
)

# Get schema for a configuration variable
#
# Retrieves the schema definition for a given configuration variable from CONFIG_SCHEMA.
# Schema format: "required|type|rules|default"
#
# Arguments:
#   $1: Configuration variable name to look up
#
# Returns:
#   0: Schema found and printed to stdout
#   1: Schema not found (variable not in schema)
#
# Output:
#   Prints schema string to stdout in format: "required|type|rules|default"
#
# Examples:
#   schema=$(get_config_schema "EXTERNAL_PEER_IPS")
#   # Returns: "required|string|non-empty"
#
# Note:
#   Requires CONFIG_SCHEMA associative array to be defined (from this file)
get_config_schema() {
	local var_name="$1"
	if [[ -n "${CONFIG_SCHEMA[$var_name]:-}" ]]; then
		echo "${CONFIG_SCHEMA[$var_name]}"
		return 0
	fi
	return 1
}

# Check if configuration variable is required
#
# Determines if a configuration variable is required based on schema definition.
# Unknown variables (not in schema) are treated as optional.
#
# Arguments:
#   $1: Configuration variable name to check
#
# Returns:
#   0: Variable is required
#   1: Variable is optional or not found in schema
#
# Examples:
#   if is_config_required "EXTERNAL_PEER_IPS"; then
#       echo "EXTERNAL_PEER_IPS is required"
#   fi
#
# Note:
#   Requires CONFIG_SCHEMA array to be defined (from this file)
is_config_required() {
	local var_name="$1"
	local schema
	schema=$(get_config_schema "$var_name")
	if [[ -z "$schema" ]]; then
		return 1 # Unknown variable, treat as optional
	fi
	[[ "$schema" =~ ^required ]]
}

# Get default value for configuration variable
#
# Extracts the default value from the schema definition.
#
# Arguments:
#   $1: Configuration variable name
#
# Returns:
#   0: Default value found or variable has no default
#   1: Schema not found
#
# Output:
#   Prints default value to stdout (empty string if no default)
#
# Limitations:
#   The regex pattern `default:([^|]+)$` extracts everything after "default:" until
#   the end of the string. This works correctly for all current default values.
#   However, if a default value ever needs to contain a pipe character (|), it would
#   be truncated at the first pipe character encountered.
#
#   Current default values (tested and working):
#   - Simple strings: "Site-to-Site VPN"
#   - Integers: "1", "3", "15"
#   - Cron schedules: "*/1 * * * *" (contains spaces and asterisks, no pipes)
#   - Empty strings: ""
#
#   If defaults with pipe characters are needed in the future, consider:
#   - Using a different delimiter in the schema format
#   - Implementing escaping mechanism (e.g., \| for literal pipe)
#   - Using a different schema format that supports complex values
#
#   For now, this limitation is acceptable as no current defaults require pipe characters.
get_config_default() {
	local var_name="$1"
	local schema
	schema=$(get_config_schema "$var_name")
	if [[ -z "$schema" ]]; then
		return 1
	fi

	# Extract default value from schema (format: ...|default:value)
	# LIMITATION: This regex stops at the first pipe character (|).
	# Default values containing pipes will be truncated.
	# Current defaults don't contain pipes, so this is acceptable.
	if [[ "$schema" =~ default:([^|]+)$ ]]; then
		echo "${BASH_REMATCH[1]}"
	else
		echo ""
	fi
	return 0
}
