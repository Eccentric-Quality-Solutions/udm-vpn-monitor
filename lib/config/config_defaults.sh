#!/bin/bash
#
# Configuration default value application for UDM VPN Monitor
# Handles applying default values from schema to configuration variables
#
# Version: 0.5.0

# Apply default values from schema
#
# Sets default values for all configuration variables from the schema definition.
# This ensures variables have values before config file is parsed, allowing scripts
# to reference config variables safely. Defaults are read from config_schema.sh,
# making it the single source of truth for default values.
#
# Arguments:
#   None
#
# Returns:
#   0: Success
#
# Side effects:
#   - Sets global configuration variables to their schema-defined defaults if not already set
#   - Variables are set via indirect assignment (declare -g + printf -v)
#
# Note:
#   Requires CONFIG_SCHEMA to be defined (from config_schema.sh)
#   For required variables without schema defaults, backward compatibility defaults
#   are applied (see function body for details)
apply_schema_defaults() {
	local var_name
	local default_val
	local schema
	local required

	# Iterate through all variables in schema
	for var_name in "${!CONFIG_SCHEMA[@]}"; do
		# Get schema once and parse it to extract all needed values
		schema=$(get_config_schema "$var_name" 2>/dev/null || echo "")
		if [[ -n "$schema" ]]; then
			# Parse schema once to get all values: required, type, rules, and default
			# Split schema by pipe to handle multiple rules correctly
			IFS='|' read -ra parts <<<"$schema"

			# First part is required status
			required="${parts[0]}"

			# Remaining parts are rules and default
			# Rules are everything before a part starting with "default:"
			# Default is the part starting with "default:" (extract value after "default:")
			default_val=""
			local i=2
			while [[ $i -lt ${#parts[@]} ]]; do
				if [[ "${parts[$i]}" =~ ^default:(.*)$ ]]; then
					# Found default value
					default_val="${BASH_REMATCH[1]}"
					break
				fi
				i=$((i + 1))
			done
		else
			required="optional"
			default_val=""
		fi

		# Apply default if variable is not already set
		# Use declare -p to check if variable is set (works for indirect references)
		if ! declare -p "$var_name" &>/dev/null; then
			# Variable not set, apply default
			if [[ -n "$default_val" ]]; then
				# Schema has a default, use it (works for both optional and required variables)
				safe_set_variable "$var_name" "$default_val"
			else
				# No default in schema - leave empty
				# For required variables, validation will catch empty values
				# For optional variables, empty is acceptable
				safe_set_variable "$var_name" ""
			fi
		fi
	done
}

# Apply default value for optional variable (centralized logic)
#
# Centralized function for applying default values to optional configuration variables.
# This function ensures consistent behavior across all validation functions when
# applying defaults for optional variables that are empty or invalid.
#
# Arguments:
#   $1: Variable name (used for error messages and indirect variable assignment)
#   $2: Current variable value (may be updated via indirect assignment if default applied)
#   $3: Required flag ("required" or "optional")
#   $4: Default value from schema (may be empty string)
#   $5: Warning message to log when applying default (optional, for context)
#
# Returns:
#   0: Default applied successfully, or not applicable (required variable or no default)
#   1: Optional variable needs default but none available
#
# Output:
#   Prints updated variable value to stdout (original value if default not applied)
#
# Side effects:
#   - Updates the variable via safe indirect assignment (declare -g + printf -v) if default is applied
#   - Logs warning message if provided and default is applied
#
# Examples:
#   var_value=$(apply_optional_default "VPN_NAME" "$VPN_NAME" "optional" "Site-to-Site VPN" "VPN_NAME is empty, using default")
#   # Sets VPN_NAME="Site-to-Site VPN" if optional and empty, prints value to stdout
#
# Note:
#   This is the centralized default application logic used by apply_config_default(),
#   validate_config_type(), and validate_config_rule() to ensure consistency.
#   Default values come from config_schema.sh (single source of truth)
apply_optional_default() {
	local var_name="$1"
	local var_value="$2"
	local required="$3"
	local default_val="$4"
	local warning_msg="${5:-}"

	# Only apply defaults for optional variables
	if [[ "$required" != "optional" ]]; then
		echo "$var_value"
		return 0
	fi

	# Check if default is available
	if [[ -z "$default_val" ]]; then
		# Optional variable but no default - return failure
		return 1
	fi

	# Apply default value
	# Log warning if message provided
	if [[ -n "$warning_msg" ]]; then
		handle_error "WARNING" "SYSTEM" "$warning_msg"
	fi

	# Set default value using safe indirect variable assignment
	# Use declare -g to ensure variable is in global scope, then printf -v for safe assignment
	safe_set_variable "$var_name" "$default_val"
	echo "$default_val"
	return 0
}

# Apply default value to configuration variable
#
# Applies a default value from schema if the variable is empty.
# Works for both optional and required variables (required variables may have
# backward compatibility defaults in the schema).
# Also corrects invalid optional values by applying schema defaults.
# For required variables without defaults, exits script if value is empty.
#
# Arguments:
#   $1: Variable name (used for error messages and indirect variable assignment)
#   $2: Current variable value (may be updated via indirect assignment if default applied)
#   $3: Required flag ("required" or "optional")
#   $4: Default value from schema (may be empty string)
#
# Returns:
#   0: Default applied or not needed (variable has value)
#   1: Variable is required but empty (calls die() and exits)
#
# Output:
#   Prints updated variable value to stdout
#
# Side effects:
#   - Updates the variable via safe indirect assignment (declare -g + printf -v) if default is applied
#   - Calls die() if required variable is empty (exits script)
#
# Examples:
#   var_value=$(apply_config_default "VPN_NAME" "$VPN_NAME" "optional" "Site-to-Site VPN")
#   # Sets VPN_NAME="Site-to-Site VPN" if empty, prints value to stdout
#
# Note:
#   Requires die function to be available (from logging.sh)
#   Default values come from config_schema.sh (single source of truth)
#   Uses centralized apply_optional_default() function for consistency
apply_config_default() {
	local var_name="$1"
	local var_value="$2"
	local required="$3"
	local default_val="$4"

	# Check if required
	if [[ "$required" == "required" ]] && [[ -z "$var_value" ]]; then
		# Log error message that includes variable name for better debugging
		handle_error_or_exit_fake_mode "SYSTEM" "$var_name is required but not configured" "${EXIT_VALIDATION_ERROR:-3}"
		# If handle_error_or_exit_fake_mode doesn't exit (e.g., in tests), return error
		return 1
	fi

	# If optional and empty, use default from schema (centralized logic)
	# Default values come from lib/config_schema.sh (single source of truth).
	# This function applies defaults from the schema definition and corrects
	# invalid optional values by applying schema defaults.
	if [[ "$required" == "optional" ]] && [[ -z "$var_value" ]]; then
		local updated_value
		if updated_value=$(apply_optional_default "$var_name" "$var_value" "$required" "$default_val" "$var_name is empty, using default: $default_val"); then
			var_value="$updated_value"
		fi
	fi

	# If still empty and optional, skip validation
	if [[ "$required" == "optional" ]] && [[ -z "$var_value" ]]; then
		echo "$var_value"
		return 0
	fi

	echo "$var_value"
	return 0
}
