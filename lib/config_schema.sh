#!/bin/bash
#
# Configuration schema definition for UDM VPN Monitor
# Defines validation rules for all configuration variables
#
# Version: 0.6.0
#

# Configuration schema definition
#
# Format: CONFIG_SCHEMA["variable_name"]="required|type|rules|default"
#   - required: "required" or "optional"
#   - type: "string" or "integer"
#   - rules: Multiple rules separated by pipe (|) characters in the schema definition.
#            Internally, rules are joined with triple-pipe (|||) separator to avoid
#            conflicts with commas in values: rules. When parsing, rules are split
#            by ||| separator first, with fallback to comma for backward compatibility.
#            Rule types:
#     * non-empty: value must not be empty (for strings)
#     * min:N: minimum value (for integers)
#     * max:N: maximum value (for integers)
#     * values:V1,V2,V3: allowed values (for integers or strings)
#                  Note: Commas in values: rules are preserved (e.g., "values:0,1")
#     * min:VAR: minimum value must be >= value of VAR (for integers)
#   - default: default value if optional and not set
#
# RULE SEPARATOR FORMAT:
#   Rules in the schema definition are separated by single pipe (|) characters.
#   During parsing, multiple rules are joined with triple-pipe (|||) separator
#   to avoid conflicts with commas in values: rules (e.g., "values:0,1").
#
#   Example schema: "optional|integer|min:1|max:10|default:3"
#   After parsing: rules string becomes "min:1|||max:10"
#   This allows proper splitting without breaking "values:0,1" rules.
#
#   When validating, rules are split by ||| separator first. If no ||| found,
#   falls back to comma-separated format for backward compatibility.
#   Special case: Single "values:" rule is not split (comma is part of value).
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
#   ["PING_COUNT"]="optional|integer|min:1|max:10|default:3"
#     # Schema: "optional|integer|min:1|max:10|default:3"
#     # Parsed rules: "min:1|||max:10" (joined with ||| separator)
#
# NOTE: Default values are defined in THIS file (CONFIG_SCHEMA) as the single source of truth.
# The load_config() function in lib/config.sh reads defaults from this schema using
# get_config_default(), ensuring consistency and eliminating duplication.
#
# IMPORTANT: To change defaults, update ONLY this file (CONFIG_SCHEMA array).
# The load_config() function will automatically use the updated defaults.
#
# Purpose:
#   - Single source of truth for all default values
#   - Early initialization in load_config() reads from schema
#   - Validation and correction also use schema defaults
#   - Ensures consistency across the codebase
# Declare and populate CONFIG_SCHEMA array
# Use -g flag to ensure global scope (important when sourced from config.sh)
# This ensures the array is accessible in the parent scope even if config.sh
# pre-declared it as empty
declare -gA CONFIG_SCHEMA=(
	# Required configuration
	# NOTE: Required variables have backward compatibility defaults for old config files
	# These defaults are applied in load_config() but validation still requires them to be set
	# Location-based configuration: LOCATION_*_EXTERNAL and LOCATION_*_INTERNAL are pattern-matched
	# Pattern matching is handled in get_config_schema() function
	["TIER1_THRESHOLD"]="required|integer|min:1|default:1"
	# NOTE: TIER2_THRESHOLD has relative validation (depends on TIER1_THRESHOLD)
	# Validation order is handled safely - see validate_config_schema() documentation
	["TIER2_THRESHOLD"]="required|integer|min:TIER1_THRESHOLD|default:3"
	# NOTE: TIER3_THRESHOLD has relative validation (depends on TIER2_THRESHOLD)
	# Validation order is handled safely - see validate_config_schema() documentation
	["TIER3_THRESHOLD"]="required|integer|min:TIER2_THRESHOLD|default:5"
	# Rate limiting configuration (replaces MAX_RESTARTS_PER_HOUR and COOLDOWN_MINUTES)
	# Backward compatibility: If MAX_RESTARTS_PER_HOUR is set, it will be migrated to MAX_RESTARTS_PER_WINDOW with RATE_LIMIT_WINDOW_MINUTES=60
	["MAX_RESTARTS_PER_WINDOW"]="required|integer|min:1|max:20|default:20"
	["RATE_LIMIT_WINDOW_MINUTES"]="required|integer|min:5|max:1440|default:60"
	["MIN_RESTART_INTERVAL_SECONDS"]="required|integer|min:0|max:300|default:40"
	# Backward compatibility: MAX_RESTARTS_PER_HOUR is deprecated but still supported
	["MAX_RESTARTS_PER_HOUR"]="optional|integer|min:1|max:60|default:"
	# Backward compatibility: COOLDOWN_MINUTES is deprecated but still supported (migrated to MIN_RESTART_INTERVAL_SECONDS)
	["COOLDOWN_MINUTES"]="optional|integer|min:1|max:1440|default:"

	# Optional configuration with defaults
	["VPN_NAME"]="optional|string||default:Site-to-Site VPN"
	["ENABLE_PING_CHECK"]="optional|integer|values:0,1|default:1"
	["LOCAL_UDM_IP"]="optional|string||default:"
	["PING_COUNT"]="optional|integer|min:1|max:10|default:3"
	["PING_TIMEOUT"]="optional|integer|min:1|max:30|default:2"
	["PING_SUMMARY_INTERVAL_MINUTES"]="optional|integer|min:1|max:1440|default:7"
	["ENABLE_KEEPALIVE"]="optional|integer|values:0,1|default:1"
	["KEEPALIVE_INTERVAL"]="optional|integer|min:10|max:300|default:30"
	["KEEPALIVE_PING_COUNT"]="optional|integer|min:1|max:5|default:1"
	["DEBUG"]="optional|integer|values:0,1|default:0"
	["NO_ESCALATE"]="optional|integer|values:0,1|default:0"
	["ENABLE_SYSTEM_WIDE_FAILURE_DETECTION"]="optional|integer|values:0,1|default:1"
	["SYSTEM_WIDE_FAILURE_THRESHOLD"]="optional|integer|min:0|max:100|default:100"
	["COORDINATE_SYSTEM_WIDE_RECOVERY"]="optional|integer|values:0,1|default:1"
	# xfrm-based per-connection recovery (enabled by default for UDM OS 4.3+)
	["ENABLE_XFRM_RECOVERY"]="optional|integer|values:0,1|default:1"
	# Recovery verification timeout (seconds) - maximum time to wait for recovery verification
	["RECOVERY_VERIFY_TIMEOUT"]="optional|integer|min:10|max:300|default:30"
	["LOCKFILE_TIMEOUT"]="optional|integer|min:60|max:3600|default:300"
	["LOG_FILE"]="optional|string||default:"
	["STATE_DIR"]="optional|string||default:"
	["LOGS_DIR"]="optional|string||default:"
	["CRON_SCHEDULE"]="optional|string||default:*/1 * * * *"
	# Network partition detection (enabled by default)
	["ENABLE_NETWORK_PARTITION_CHECK"]="optional|integer|values:0,1|default:1"
	["NETWORK_PARTITION_DNS_SERVER"]="optional|string||default:8.8.8.8"
	["NETWORK_PARTITION_DNS_HOSTNAME"]="optional|string||default:google.com"
	["NETWORK_PARTITION_DNS_TIMEOUT"]="optional|integer|min:1|max:10|default:2"
	["NETWORK_PARTITION_INTERFACES"]="optional|string||default:br0,eth0"
	# Resource monitoring (enabled by default)
	["ENABLE_RESOURCE_MONITORING"]="optional|integer|values:0,1|default:1"
	["RESOURCE_CPU_THRESHOLD"]="optional|integer|min:50|max:100|default:90"
	["RESOURCE_CPU_DURATION"]="optional|integer|min:10|max:600|default:60"
	["RESOURCE_RAM_THRESHOLD"]="optional|integer|min:50|max:100|default:90"
	["RESOURCE_RAM_DURATION"]="optional|integer|min:10|max:600|default:60"
	["RESOURCE_DISK_WARNING_THRESHOLD"]="optional|integer|min:5|max:50|default:20"
	["RESOURCE_DISK_CRITICAL_THRESHOLD"]="optional|integer|min:1|max:20|default:10"
	# Status logging interval (seconds) - how often to log periodic status updates for healthy VPN peers
	["STATUS_LOG_INTERVAL_SECONDS"]="optional|integer|min:0|max:3600|default:300"
)

# Get schema for a configuration variable
#
# Retrieves the schema definition for a given configuration variable from CONFIG_SCHEMA.
# Schema format: "required|type|rules|default"
# Supports pattern matching for location-based variables:
#   - LOCATION_*_EXTERNAL: required|string|non-empty
#   - LOCATION_*_INTERNAL: optional|string
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
#   schema=$(get_config_schema "LOCATION_NYC_EXTERNAL")
#   # Returns: "required|string|non-empty"
#   schema=$(get_config_schema "LOCATION_NYC_INTERNAL")
#   # Returns: "optional|string"
#
# Note:
#   Requires CONFIG_SCHEMA associative array to be defined (from this file)
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
#   Default values cannot contain pipe characters (|). If you need a default
#   with a pipe character:
#   1. Use a different format (e.g., comma-separated list)
#   2. Set the default in the calling code instead of schema
#   3. Contact maintainers to discuss schema format changes
#
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
