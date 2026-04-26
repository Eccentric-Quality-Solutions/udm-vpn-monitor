#!/bin/bash
#
# Configuration validation for UDM VPN Monitor
# Handles schema-based validation, type checking, and rule validation
#
# Version: 0.8.3

# Validate configuration variable type
# Note: parse_config_schema() is defined in config_loading.sh and available here
#
# Validates that a configuration variable matches its expected type.
# For integer type: ensures the value is numeric (digits only).
# For string type: type validation is handled by rules (non-empty, etc.).
# For optional variables with invalid types, applies default value if available.
#
# Arguments:
#   $1: Variable name (used for error messages and indirect variable assignment)
#   $2: Variable value (may be updated via indirect assignment if default applied)
#   $3: Variable type ("integer" or "string")
#   $4: Required flag ("required" or "optional")
#   $5: Default value from schema (used for correction if optional)
#
# Returns:
#   0: Type is valid (or corrected to default)
#   1: Type is invalid (required variable fails, or optional has no default)
#
# Output:
#   Prints updated variable value to stdout
#
# Side effects:
#   - May update variable value via safe indirect assignment (declare -g + printf -v) if default is applied for optional variables
#   - Calls die() for required variables with invalid types
#   - Calls log_message() for warnings about optional variables
#
# Examples:
#   var_value=$(validate_config_type "TIER1_THRESHOLD" "5" "integer" "required" "")
#   # Returns "5" if valid, exits if invalid
#
# Note:
#   Requires die and log_message functions to be available
#   Integer validation uses regex: ^[0-9]+$
validate_config_type() {
	local var_name="$1"
	local var_value="$2"
	local var_type="$3"
	local required="$4"
	local default_val="$5"

	case "$var_type" in
	integer)
		if ! [[ "$var_value" =~ ^[0-9]+$ ]]; then
			if [[ "$required" == "required" ]]; then
				# Use handle_error_or_exit_fake_mode to respect fake mode
				# In fake mode, it returns 1; in normal mode it calls die() and never returns
				if ! handle_error_or_exit_fake_mode "SYSTEM" "$var_name must be an integer (current value: '$var_value')" "${EXIT_VALIDATION_ERROR:-3}"; then
					# In fake mode, handle_error_or_exit_fake_mode returns 1
					return 1
				fi
				# In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
			else
				# Validate default before applying to avoid setting invalid global variable
				if [[ -z "$default_val" ]]; then
					# No default available
					handle_error "WARNING" "SYSTEM" "$var_name must be an integer (current value: '$var_value'), no default available"
					return 1
				elif ! [[ "$default_val" =~ ^[0-9]+$ ]]; then
					# Default value is invalid - don't apply it
					handle_error "ERROR" "SYSTEM" "Default value for $var_name is invalid (default: '$default_val'), cannot apply default" 0
					return 1
				fi
				# Default is valid, apply it (centralized logic)
				local updated_value
				if updated_value=$(apply_optional_default "$var_name" "$var_value" "$required" "$default_val" "$var_name must be an integer (current value: '$var_value'), using default: $default_val"); then
					var_value="$updated_value"
				else
					# This should not happen since we validated default above, but handle gracefully
					handle_error "WARNING" "SYSTEM" "$var_name must be an integer (current value: '$var_value'), failed to apply default"
					return 1
				fi
			fi
		fi
		;;
	string)
		# String type validation handled by rules
		;;
	*)
		# Unknown type - allow it
		;;
	esac

	echo "$var_value"
	return 0
}

# Validate a single configuration rule
#
# Validates a configuration variable against a single validation rule.
# Supported rules: non-empty, min:N, max:N, values:V1,V2,V3, min:VAR (relative).
# For optional variables with invalid values, applies default if available.
#
# Arguments:
#   $1: Variable name (used for error messages and indirect variable assignment)
#   $2: Variable value (may be updated via indirect assignment if default applied)
#   $3: Variable type ("integer" or "string")
#   $4: Required flag ("required" or "optional")
#   $5: Default value from schema (used for correction if optional)
#   $6: Rule to validate (e.g., "non-empty", "min:5", "max:10", "values:0,1", "min:TIER1_THRESHOLD")
#
# Returns:
#   0: Rule validation passed (or corrected to default)
#   1: Rule validation failed (required variable fails, or optional has no default)
#
# Output:
#   Prints updated variable value to stdout
#
# Side effects:
#   - May update variable value via safe indirect assignment (declare -g + printf -v) if default is applied for optional variables
#   - Calls die() for required variables that fail validation
#   - Calls log_message() for warnings about optional variables
#
# Examples:
#   var_value=$(validate_config_rule "TIER2_THRESHOLD" "3" "integer" "required" "" "min:TIER1_THRESHOLD")
#   # Validates TIER2_THRESHOLD >= TIER1_THRESHOLD
#
# Note:
#   Requires die and log_message functions to be available
#   Relative validation (min:VAR) checks if referenced variable exists before using it
#   This handles validation order dependencies safely
validate_config_rule() {
	local var_name="$1"
	local var_value="$2"
	local var_type="$3"
	local required="$4"
	local default_val="$5"
	local rule="$6"

	case "$rule" in
	non-empty)
		if [[ -z "$var_value" ]]; then
			if [[ "$required" == "required" ]]; then
				# Use handle_error_or_exit_fake_mode to respect fake mode
				# In fake mode, it returns 1; in normal mode it calls die() and never returns
				if ! handle_error_or_exit_fake_mode "SYSTEM" "$var_name cannot be empty" "${EXIT_VALIDATION_ERROR:-3}"; then
					# In fake mode, handle_error_or_exit_fake_mode returns 1
					return 1
				fi
				# In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
			else
				# Apply default value for optional variables (centralized logic)
				local updated_value
				if updated_value=$(apply_optional_default "$var_name" "$var_value" "$required" "$default_val" "$var_name is empty, using default: $default_val"); then
					var_value="$updated_value"
				else
					handle_error "WARNING" "SYSTEM" "$var_name is empty, no default available"
					return 1
				fi
			fi
		fi
		;;
	min:*)
		local min_val="${rule#min:}"
		# Strip any ||| separator and everything after it (defensive: rules should be split before this function)
		# This prevents syntax errors if a malformed rule somehow contains |||
		min_val="${min_val%%|||*}"
		# Check if it's a reference to another variable (relative validation)
		#
		# RELATIVE VALIDATION ORDER DEPENDENCY:
		# Some variables depend on other variables for validation (e.g., TIER2_THRESHOLD >= TIER1_THRESHOLD).
		# Since associative array iteration order is not guaranteed, TIER2 might be validated before TIER1.
		#
		# This is handled safely because:
		# 1. load_config() sets all default values BEFORE validation runs
		# 2. This code checks if the referenced variable exists before using it
		# 3. If the variable exists (from defaults or already validated), validation proceeds correctly
		#
		# Example: TIER2_THRESHOLD validation depends on TIER1_THRESHOLD:
		#   - If TIER1 validated first: Uses validated value ✓
		#   - If TIER2 validated first: Uses default value from load_config() ✓
		#   - Both cases work correctly because defaults are set first
		#
		# IMPORTANT: Variables referenced in relative validation MUST have defaults set in load_config()
		# to ensure they exist regardless of validation order.
		if [[ "$min_val" =~ ^[A-Z_]+$ ]] && [[ -n "${!min_val:-}" ]]; then
			min_val="${!min_val}"
		fi
		if [[ "$var_type" == "integer" ]] && [[ "$var_value" -lt "$min_val" ]]; then
			if [[ "$required" == "required" ]]; then
				# Use handle_error_or_exit_fake_mode to respect fake mode
				# In fake mode, it returns 1; in normal mode it calls die() and never returns
				if ! handle_error_or_exit_fake_mode "SYSTEM" "$var_name must be at least $min_val (current value: $var_value)" "${EXIT_VALIDATION_ERROR:-3}"; then
					# In fake mode, handle_error_or_exit_fake_mode returns 1
					return 1
				fi
				# In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
			else
				# Apply default value for optional variables (centralized logic)
				local updated_value
				if updated_value=$(apply_optional_default "$var_name" "$var_value" "$required" "$default_val" "$var_name must be at least $min_val (current value: $var_value), using default: $default_val"); then
					var_value="$updated_value"
				else
					handle_error "WARNING" "SYSTEM" "$var_name must be at least $min_val (current value: $var_value), no default available"
					return 1
				fi
			fi
		fi
		;;
	max:*)
		local max_val="${rule#max:}"
		# Strip any ||| separator and everything after it (defensive: rules should be split before this function)
		# This prevents syntax errors if a malformed rule somehow contains |||
		max_val="${max_val%%|||*}"
		if [[ "$var_type" == "integer" ]] && [[ "$var_value" -gt "$max_val" ]]; then
			if [[ "$required" == "required" ]]; then
				# Use handle_error_or_exit_fake_mode to respect fake mode
				# In fake mode, it returns 1; in normal mode it calls die() and never returns
				if ! handle_error_or_exit_fake_mode "SYSTEM" "$var_name must be at most $max_val (current value: $var_value)" "${EXIT_VALIDATION_ERROR:-3}"; then
					# In fake mode, handle_error_or_exit_fake_mode returns 1
					return 1
				fi
				# In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
			else
				# Apply default value for optional variables (centralized logic)
				local updated_value
				if updated_value=$(apply_optional_default "$var_name" "$var_value" "$required" "$default_val" "$var_name must be at most $max_val (current value: $var_value), using default: $default_val"); then
					var_value="$updated_value"
				else
					handle_error "WARNING" "SYSTEM" "$var_name must be at most $max_val (current value: $var_value), no default available"
					return 1
				fi
			fi
		fi
		;;
	values:*)
		local allowed_values="${rule#values:}"
		# Strip any ||| separator and everything after it (defensive: rules should be split before this function)
		# This prevents issues if a malformed rule somehow contains |||
		allowed_values="${allowed_values%%|||*}"
		IFS=',' read -ra value_array <<<"$allowed_values"
		local found=0
		for allowed_val in "${value_array[@]}"; do
			if [[ "$var_value" == "$allowed_val" ]]; then
				found=1
				break
			fi
		done
		if [[ $found -eq 0 ]]; then
			if [[ "$required" == "required" ]]; then
				# Use handle_error_or_exit_fake_mode to respect fake mode
				# In fake mode, it returns 1; in normal mode it calls die() and never returns
				if ! handle_error_or_exit_fake_mode "SYSTEM" "$var_name must be one of: $allowed_values (current value: '$var_value')" "${EXIT_VALIDATION_ERROR:-3}"; then
					# In fake mode, handle_error_or_exit_fake_mode returns 1
					return 1
				fi
				# In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
			else
				# Apply default value for optional variables (centralized logic)
				local updated_value
				if updated_value=$(apply_optional_default "$var_name" "$var_value" "$required" "$default_val" "$var_name must be one of: $allowed_values (current value: '$var_value'), using default: $default_val"); then
					var_value="$updated_value"
				else
					handle_error "WARNING" "SYSTEM" "$var_name must be one of: $allowed_values (current value: '$var_value'), no default available"
					return 1
				fi
			fi
		fi
		;;
	esac

	echo "$var_value"
	return 0
}

# Split rules string into array
#
# Splits a rules string into an array of individual rules, handling:
# - Rules separated by ||| (e.g., "min:1|||max:10")
# - Special case: Single values: rule (e.g., "values:0,1") - comma is part of value, don't split
#
# Arguments:
#   $1: Rules string to split (may be empty)
#   $2: Name of array variable to store results (passed by reference)
#
# Returns:
#   0: Always succeeds (empty rules string results in empty array)
#
# Side effects:
#   - Sets array elements via nameref
#
# Examples:
#   local -a rules_array
#   split_rules_string "min:1|||max:10" "rules_array"
#   # rules_array contains: ("min:1" "max:10")
#
#   split_rules_string "values:0,1" "rules_array"
#   # rules_array contains: ("values:0,1") - not split because comma is part of value
#
# Note:
#   This function centralizes rule splitting logic to avoid duplication.
#   The ||| separator is used to avoid conflicts with commas in values: rules.
split_rules_string() {
	local rules="$1"
	local -n rule_array_ref="$2"

	# Clear the array
	rule_array_ref=()

	# Handle empty rules string
	if [[ -z "$rules" ]]; then
		return 0
	fi

	# Split rules by ||| separator (used to avoid conflicts with commas in values: rules)
	# Special case: if rules is a single values: rule (e.g., "values:0,1"), don't split it
	if [[ "$rules" == *"|||"* ]]; then
		# Split by ||| using parameter expansion (more portable than awk)
		# IFS doesn't support multi-character separators, so we use parameter expansion
		local remaining="$rules"
		while [[ "$remaining" == *"|||"* ]]; do
			# Extract part before ||| separator
			local rule="${remaining%%|||*}"
			[[ -n "$rule" ]] && rule_array_ref+=("$rule")
			# Remove processed part and separator
			remaining="${remaining#*|||}"
		done
		# Add remaining part (after last |||)
		[[ -n "$remaining" ]] && rule_array_ref+=("$remaining")
	elif [[ "$rules" =~ ^values: ]]; then
		# Single values: rule - don't split (comma is part of the rule value)
		rule_array_ref=("$rules")
	else
		# Single rule without separator - add as-is
		rule_array_ref=("$rules")
	fi

	return 0
}

# Validate all configuration rules
#
# Validates a configuration variable against all rules in the schema.
# Processes rules sequentially, stopping on first failure.
# Rules are separated by ||| (e.g., "min:1|||max:10").
#
# Arguments:
#   $1: Variable name (passed to validate_config_rule)
#   $2: Variable value (updated through rule validation chain)
#   $3: Variable type ("integer" or "string")
#   $4: Required flag ("required" or "optional")
#   $5: Default value from schema
#   $6: Rules string (separated by |||, e.g., "min:1|||max:10" or empty)
#
# Returns:
#   0: All rules passed (or no rules to validate)
#   1: One or more rules failed
#
# Output:
#   Prints updated variable value to stdout
#
# Side effects:
#   - May update variable value via safe indirect assignment (declare -g + printf -v) if default is applied for optional variables
#   - Calls validate_config_rule for each rule in the list
#
# Examples:
#   var_value=$(validate_config_rules "MAX_RESTARTS_PER_WINDOW" "20" "integer" "required" "" "min:1|||max:20")
#   # Validates both min:1 and max:20 rules
#
# Note:
#   Empty rules string is valid (no rules to validate)
#   Uses split_rules_string() helper function to split rules string into array
validate_config_rules() {
	local var_name="$1"
	local var_value="$2"
	local var_type="$3"
	local required="$4"
	local default_val="$5"
	local rules="$6"

	if [[ -z "$rules" ]]; then
		echo "$var_value"
		return 0
	fi

	# Split rules string into array using helper function
	local -a rule_array
	split_rules_string "$rules" "rule_array"

	for rule in "${rule_array[@]}"; do
		if ! var_value=$(validate_config_rule "$var_name" "$var_value" "$var_type" "$required" "$default_val" "$rule"); then
			return 1
		fi
	done

	echo "$var_value"
	return 0
}

# Validate configuration variable
#
# Validates a single configuration variable against its schema definition.
# This consolidated function handles all validation aspects in one place:
# 1. Schema retrieval and parsing
# 2. Default value application
# 3. Type validation
# 4. Rule validation
# 5. Global variable update
#
# Arguments:
#   $1: Variable name to validate (must exist in CONFIG_SCHEMA)
#   $2: Optional variable value (if not provided, reads from variable via indirect reference)
#
# Returns:
#   0: Variable is valid (or unknown variable, allowed for backward compatibility)
#   1: Variable is invalid (validation failed)
#
# Side effects:
#   - Updates global variable with final validated/corrected value via safe_set_variable()
#   - Calls handle_error_or_exit_fake_mode() for required variables that fail validation
#   - Calls handle_error() for warnings about optional variables
#
# Examples:
#   validate_config_var "TIER1_THRESHOLD" "5"
#
# Note:
#   Requires CONFIG_SCHEMA to be defined (from config_schema.sh)
#   Unknown variables (not in schema) are allowed (defensive programming - may be set programmatically)
#   Uses indirect variable reference (${!var_name}) to read variable value if not provided
#   Always updates global variable with final validated value to ensure corrections are persisted
validate_config_var() {
	local var_name="$1"
	local var_value="${2:-}"

	# ============================================================
	# SECTION 1: Get variable value if not provided
	# ============================================================
	if [[ -z "$var_value" ]]; then
		local indirect_var="${!var_name:-}"
		var_value="$indirect_var"
	fi

	# ============================================================
	# SECTION 2: Get and parse schema
	# ============================================================
	local schema
	schema=$(get_config_schema "$var_name")
	if [[ -z "$schema" ]]; then
		# Unknown variable - allow it (defensive programming: may be set programmatically)
		# Note: Unknown variables are already rejected during config file parsing for security
		return 0
	fi

	# Parse schema: required|type|rules|default
	local schema_parts
	schema_parts=$(parse_config_schema "$schema")
	local required
	local var_type
	local rules
	local default_val
	{
		read -r required
		read -r var_type
		read -r rules
		read -r default_val
	} <<<"$schema_parts"

	# ============================================================
	# SECTION 3: Apply default value if needed
	# ============================================================
	# Check if required variable is empty
	if [[ "$required" == "required" ]] && [[ -z "$var_value" ]]; then
		# Use handle_error_or_exit_fake_mode to respect fake mode
		# In fake mode, it returns 1; in normal mode it calls die() and never returns
		if ! handle_error_or_exit_fake_mode "SYSTEM" "$var_name is required but not configured" "${EXIT_VALIDATION_ERROR:-3}"; then
			# In fake mode, handle_error_or_exit_fake_mode returns 1
			return 1
		fi
		# In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
	fi

	# Apply default for optional empty variables (using centralized function)
	if [[ "$required" == "optional" ]] && [[ -z "$var_value" ]]; then
		if [[ -n "$default_val" ]]; then
			local updated_value
			if updated_value=$(apply_optional_default "$var_name" "$var_value" "$required" "$default_val" "$var_name is empty, using default: $default_val"); then
				var_value="$updated_value"
			else
				# Optional variable with no default - skip validation
				return 0
			fi
		else
			# Optional variable with no default - skip validation
			return 0
		fi
	fi

	# ============================================================
	# SECTION 4: Validate type
	# ============================================================
	# Use validate_config_type() to avoid code duplication
	# This function handles integer validation, string type handling, and default application
	if ! var_value=$(validate_config_type "$var_name" "$var_value" "$var_type" "$required" "$default_val"); then
		return 1
	fi

	# ============================================================
	# SECTION 5: Validate rules
	# ============================================================
	if [[ -n "$rules" ]]; then
		# Use existing helper function to validate all rules
		if ! var_value=$(validate_config_rules "$var_name" "$var_value" "$var_type" "$required" "$default_val" "$rules"); then
			return 1
		fi
	fi

	# ============================================================
	# SECTION 6: Update global variable with final validated value
	# ============================================================
	# Ensure global variable is updated with final validated/corrected value
	# This is necessary because:
	# 1. If function was called with a value parameter, corrections need to be persisted
	# 2. Individual validation functions update globals when applying corrections, but we need
	#    to ensure the final value (after all validations) is persisted
	# 3. Ensures consistency between local var_value and global variable
	safe_set_variable "$var_name" "$var_value"

	return 0
}

# Validate configuration using schema
#
# Validates all configuration variables against the schema definition.
# Uses schema-based validation for type checking and rule validation.
#
# Arguments:
#   None
#
# Returns:
#   0: Configuration is valid
#   1: Configuration is invalid (exits script)
#
# Side effects:
#   - Calls die() for validation failures
#   - Validates all schema-defined variables
#
# Note:
#   Requires CONFIG_SCHEMA to be defined (from config_schema.sh)
#
# VALIDATION ORDER:
#   Variables with relative validation rules (e.g., min:TIER1_THRESHOLD) must be validated
#   after their dependencies so the referenced variable holds a validated value. We validate
#   in explicit dependency order first, then the remaining schema variables in any order.
#
#   Ordered dependencies (validated in this order):
#   - TIER1_THRESHOLD (no dependency)
#   - TIER2_THRESHOLD (depends on TIER1_THRESHOLD)
#   - TIER3_THRESHOLD (depends on TIER2_THRESHOLD)
#
#   When adding new schema variables with relative min:VAR rules, add them to ordered_deps
#   in dependency order (dependencies first).
validate_config_schema() {
	local validation_failed=0

	# Variables that have relative validation rules; must be validated in this order
	# so that min:VAR rules see already-validated values (avoids undefined iteration order).
	local ordered_deps=(TIER1_THRESHOLD TIER2_THRESHOLD TIER3_THRESHOLD)
	local var_name
	for var_name in "${ordered_deps[@]}"; do
		[[ -z "${CONFIG_SCHEMA[$var_name]:-}" ]] && continue
		if ! validate_config_var "$var_name"; then
			validation_failed=1
		fi
	done

	# Validate remaining schema-defined variables (order does not matter)
	for var_name in "${!CONFIG_SCHEMA[@]}"; do
		# Skip if already validated in ordered_deps
		case " ${ordered_deps[*]} " in *" $var_name "*) continue ;; esac
		# Skip NO_ESCALATE if it was set from command line (runtime flag, not config file option)
		if [[ "$var_name" == "NO_ESCALATE" ]] && [[ "${NO_ESCALATE_SET_FROM_CMD:-0}" -eq 1 ]]; then
			continue
		fi
		if ! validate_config_var "$var_name"; then
			validation_failed=1
		fi
	done

	if [[ $validation_failed -eq 1 ]]; then
		return 1
	fi

	return 0
}

# Ensure LOCAL_UDM_IP is on the default LAN interface for ping (-I) if needed
#
# Runs when:
# - ENABLE_PING_CHECK is enabled
# - At least one location has internal IPs configured
# - LOCAL_UDM_IP is configured
#
# This function is called during config validation to ensure IPs are set up
# proactively, not just when ping checks run. IPs are added on
# DEFAULT_LAN_INTERFACE (typically br0) to enable sourced pings between UDMs.
#
# Arguments:
#   None
#
# Returns:
#   0: Setup completed (or not needed)
#   1: Setup failed (logged as ERROR if ping source on default LAN is required; non-critical in some test contexts)
#
# Side effects:
#   - May add host address on default LAN interface
#   - Logs actions and results
#
# Note:
#   Requires: get_local_ip_for_ping(), check_local_ip_on_default_lan(), add_local_ip_to_default_lan_if_needed()
#   These may be unavailable if config.sh is sourced without detection.sh (e.g. in tests)
ensure_default_lan_local_ip_for_ping() {
	# Check if ping checks enabled
	if [[ "${ENABLE_PING_CHECK:-0}" -ne 1 ]]; then
		return 0
	fi

	# Check if any location has internal IPs (needed to determine if routes are required)
	local has_internal_ips=0
	local location_name
	for location_name in "${!LOCATIONS[@]}"; do
		local internal_ips
		internal_ips=$(get_location_internal_ips "$location_name")
		local get_internal_ret=$?
		if [[ $get_internal_ret -eq "${EXIT_MALFORMED_DATA:-7}" ]]; then
			handle_error "ERROR" "SYSTEM" "Malformed location data for $location_name (cannot determine internal IPs)"
			return 1
		fi
		if [[ -n "$internal_ips" ]]; then
			has_internal_ips=1
			break
		fi
	done

	# If no internal IPs configured, default LAN address setup is not needed
	if [[ $has_internal_ips -eq 0 ]]; then
		return 0
	fi

	local missing_deps=()
	command -v get_local_ip_for_ping >/dev/null 2>&1 || missing_deps+=("get_local_ip_for_ping")
	command -v check_local_ip_on_default_lan >/dev/null 2>&1 || missing_deps+=("check_local_ip_on_default_lan")
	command -v add_local_ip_to_default_lan_if_needed >/dev/null 2>&1 || missing_deps+=("add_local_ip_to_default_lan_if_needed")

	if [[ ${#missing_deps[@]} -gt 0 ]]; then
		if command -v log_message >/dev/null 2>&1; then
			handle_error "ERROR" "SYSTEM" "Cannot set up default LAN ping source during config validation: missing detection.sh functions: ${missing_deps[*]}. Ping source address on default LAN is required for internal IP ping checks but may not be added if VPN checks are skipped. Ensure detection.sh is sourced before config.sh."
		fi
		return 1
	fi

	local local_ip
	local_ip=$(get_local_ip_for_ping)
	if [[ -z "$local_ip" ]]; then
		# LOCAL_UDM_IP not configured (warning may already be logged during validation)
		return 0
	fi

	local lan_if="${DEFAULT_LAN_INTERFACE:-br0}"
	if ! check_local_ip_on_default_lan "$local_ip"; then
		log_message "INFO" "SYSTEM" "Ping source IP not on default LAN ($lan_if) during config validation, attempting to add: $local_ip/${IPV4_CIDR_SINGLE_HOST:-32}"
		if ! add_local_ip_to_default_lan_if_needed "$local_ip"; then
			handle_error "ERROR" "SYSTEM" "Failed to add ping source address during config validation: $local_ip/${IPV4_CIDR_SINGLE_HOST:-32}. Internal IP ping checks require LOCAL_UDM_IP on default LAN; manual fix: ip addr add $local_ip/32 dev $lan_if" 0
			return 1
		fi
	fi

	return 0
}

# Validate configuration
#
# Validates that required configuration variables are set and have valid values.
# Uses schema-based validation for type checking and rules, plus custom validation
# for complex cases (IP addresses, location-based configuration).
#
# Arguments:
#   None
#
# Returns:
#   0: Configuration is valid
#   1: Configuration is invalid (exits script)
#
# Side effects:
#   - Calls log_message for errors
#   - Exits script on validation failure
#
# Note:
#   Requires validate_ip_address function (from detection.sh)
#   Requires log_message function (from logging.sh)
#   Requires CONFIG_SCHEMA to be defined (from config_schema.sh)
#   Requires parse_location_config() function (from location_parsing.sh)
#   Requires get_location_external_ip() and get_location_internal_ips() functions (from location_parsing.sh)
validate_config() {
	# Validate using schema (type checking, ranges, relative validation, etc.)
	# Schema validation handles:
	# - Required field checks
	# - Type validation (integer/string)
	# - Range validation (min/max)
	# - Value enumeration (allowed values)
	# - Relative validation (e.g., TIER2_THRESHOLD >= TIER1_THRESHOLD)
	if ! validate_config_schema; then
		# Use handle_error_or_exit_fake_mode to respect fake mode
		# In fake mode, it returns 1; in normal mode it calls die() and never returns
		if ! handle_error_or_exit_fake_mode "SYSTEM" "Configuration validation failed - check schema rules" "${EXIT_VALIDATION_ERROR:-3}"; then
			# In fake mode, handle_error_or_exit_fake_mode returns 1
			return 1
		fi
		# In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
	fi

	# Parse location-based configuration
	if ! parse_location_config; then
		# Use handle_error_or_exit_fake_mode to respect fake mode
		# In fake mode, it returns 1; in normal mode it calls die() and never returns
		if ! handle_error_or_exit_fake_mode "SYSTEM" "Failed to parse location-based configuration" "${EXIT_VALIDATION_ERROR:-3}"; then
			# In fake mode, handle_error_or_exit_fake_mode returns 1
			return 1
		fi
		# In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
	fi

	# When ping is enabled, warn if LOCAL_UDM_IP or remote IPs are missing
	if [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
		if [[ -z "${LOCAL_UDM_IP:-}" ]]; then
			handle_error "WARNING" "SYSTEM" "Ping checks are enabled (ENABLE_PING_CHECK=1) but LOCAL_UDM_IP is not set. Set LOCAL_UDM_IP for reliable ping checks (source IP for pings)."
		fi
	fi

	# Validate location-based configuration: IP address formats
	local location_name
	local external_peer_ip
	local internal_ips
	local IFS=' ' # Scoped so callers' IFS is not affected (read -ra internal_ips_array uses space separator)
	local -a internal_ips_array

	for location_name in "${!LOCATIONS[@]}"; do
		# Get external IP for this location
		external_peer_ip=$(get_location_external_ip "$location_name")
		local get_external_ret=$?
		if [[ $get_external_ret -ne 0 ]]; then
			local external_err_msg="Failed to get external IP"
			[[ $get_external_ret -eq "${EXIT_MALFORMED_DATA:-7}" ]] && external_err_msg="Malformed location data (invalid format)"
			# Use handle_error_or_exit_fake_mode to respect fake mode
			# In fake mode, it returns 1; in normal mode it calls die() and never returns
			if ! handle_error_or_exit_fake_mode "$location_name" "$external_err_msg" "${EXIT_VALIDATION_ERROR:-3}"; then
				# In fake mode, handle_error_or_exit_fake_mode returns 1
				return 1
			fi
			# In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
		fi

		# Validate external IP or DNS name format
		if ! validate_ip_or_dns "$external_peer_ip"; then
			# Use handle_error_or_exit_fake_mode to respect fake mode
			# In fake mode, it returns 1; in normal mode it calls die() and never returns
			if ! handle_error_or_exit_fake_mode "$location_name" "Invalid external IP or DNS name format: $external_peer_ip" "${EXIT_VALIDATION_ERROR:-3}"; then
				# In fake mode, handle_error_or_exit_fake_mode returns 1
				return 1
			fi
			# In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
		fi

		# Get internal IPs for this location (may be empty)
		internal_ips=$(get_location_internal_ips "$location_name")
		local get_internal_ret=$?
		if [[ $get_internal_ret -eq "${EXIT_MALFORMED_DATA:-7}" ]]; then
			if ! handle_error_or_exit_fake_mode "$location_name" "Malformed location data (invalid format)" "${EXIT_VALIDATION_ERROR:-3}"; then
				return 1
			fi
		fi

		# When ping is enabled and location has no internal IPs, warn (ping will use external IP)
		if [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]] && [[ -z "$internal_ips" ]]; then
			handle_error "WARNING" "$location_name" "Ping checks are enabled but no internal IPs configured (LOCATION_${location_name}_INTERNAL). Ping will use external IP which may not be reachable."
		fi

		# Validate internal IPs or DNS names if set
		if [[ -n "$internal_ips" ]]; then
			read -ra internal_ips_array <<<"$internal_ips"
			for internal_peer_ip in "${internal_ips_array[@]}"; do
				# Skip empty IPs
				if [[ -z "$internal_peer_ip" ]]; then
					continue
				fi

				# Validate IP address or DNS name format
				if ! validate_ip_or_dns "$internal_peer_ip"; then
					# Use handle_error_or_exit_fake_mode to respect fake mode
					# In fake mode, it returns 1; in normal mode it calls die() and never returns
					if ! handle_error_or_exit_fake_mode "$location_name" "Invalid internal IP or DNS name format: $internal_peer_ip" "${EXIT_VALIDATION_ERROR:-3}"; then
						# In fake mode, handle_error_or_exit_fake_mode returns 1
						return 1
					fi
					# In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
				fi
			done

			# Validate LOCAL_UDM_IP is configured when ping checks are enabled with internal IPs
			if [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
				if [[ -z "${LOCAL_UDM_IP:-}" ]]; then
					# Note: location_name is already in log prefix, so we remove redundant location name
					handle_error "WARNING" "$location_name" "LOCAL_UDM_IP is not configured but ENABLE_PING_CHECK=1 and has internal IPs"
					handle_error "WARNING" "$location_name" "LOCAL_UDM_IP is required for ping checks with internal IPs. Ping checks may fail without it."
				else
					# Validate LOCAL_UDM_IP format
					if ! validate_ip_address "$LOCAL_UDM_IP"; then
						die "Invalid LOCAL_UDM_IP format: $LOCAL_UDM_IP"
					fi
				fi
			fi
		fi
	done

	# Validate file paths are writable (if they exist)
	# Check STATE_DIR is writable
	if directory_exists "$STATE_DIR" && ! directory_writable "$STATE_DIR"; then
		handle_error "WARNING" "SYSTEM" "STATE_DIR is not writable: $STATE_DIR (state file writes may fail, output will go to stderr)" 0
	fi

	# Check LOGS_DIR is writable (if it exists)
	if directory_exists "$LOGS_DIR" && ! directory_writable "$LOGS_DIR"; then
		handle_error "WARNING" "SYSTEM" "LOGS_DIR is not writable: $LOGS_DIR (log writes may fail, output will go to stderr)" 0
	fi

	# Check LOG_FILE parent directory is writable (if it exists)
	local log_file_dir
	log_file_dir=$(dirname "$LOG_FILE")
	if directory_exists "$log_file_dir" && ! directory_writable "$log_file_dir"; then
		handle_error "WARNING" "SYSTEM" "LOG_FILE directory is not writable: $log_file_dir (log writes may fail, output will go to stderr)" 0
	fi

	# Ensure LOCAL_UDM_IP on default LAN for ping (-I) when internal IPs are used
	if ! ensure_default_lan_local_ip_for_ping; then
		if command -v log_message >/dev/null 2>&1; then
			if ! handle_error_or_exit_fake_mode "SYSTEM" "Default LAN ping source setup failed during config validation. See previous error messages for details." "${EXIT_VALIDATION_ERROR:-3}"; then
				return 1
			fi
		fi
	fi

	return 0
}
