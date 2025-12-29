#!/bin/bash
#
# Configuration loading and validation for UDM VPN Monitor
# Handles loading configuration files and validating settings
#
# Version: 0.4.0
#
# Default Value Handling:
#   Default values are defined in lib/config_schema.sh as the single source of truth.
#   The load_config() function reads defaults from the schema using get_config_default(),
#   ensuring consistency and eliminating duplication. To change defaults, update only
#   config_schema.sh - load_config() will automatically use the updated values.
#

# Source constants for magic numbers
# shellcheck source=lib/constants.sh
# Determine lib directory (where this file is located)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LIB_DIR}/constants.sh" 2>/dev/null || {
	# Fallback if constants.sh not found (shouldn't happen in normal operation)
	readonly LOCKFILE_TIMEOUT_DEFAULT=300
	readonly SECONDS_PER_MINUTE=60
	readonly SECONDS_PER_HOUR=3600
	readonly SECONDS_PER_DAY=86400
	readonly MAX_IPV6_SEGMENTS=8
}

# Source common utility functions
# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"

# Source configuration schema
# shellcheck source=lib/config_schema.sh
source "${LIB_DIR}/config_schema.sh" 2>/dev/null || {
	# Fallback if config_schema.sh not found
	declare -A CONFIG_SCHEMA=()
	get_config_schema() { return 1; }
	is_config_required() { return 1; }
	get_config_default() {
		echo ""
		return 0
	}
}

# Ensure directory exists
#
# Creates a directory if it doesn't exist, with consistent error handling.
# Exits script with error message if directory creation fails.
#
# Arguments:
#   $1: Directory path to create
#   $2: Description of directory (for error message, e.g., "state", "logs")
#
# Returns:
#   0: Directory exists or was created successfully
#   1: Failed to create directory (exits script)
#
# Side effects:
#   Exits script with error code 1 if directory creation fails
#
# Note:
#   Requires die function to be available (from logging.sh)
ensure_directory_exists() {
	local dir="$1"
	local description="${2:-directory}"

	if ! mkdir -p "$dir" 2>/dev/null; then
		# In fake mode, exit gracefully with success; otherwise die
		if is_fake_mode; then
			handle_error "ERROR" "Cannot create ${description} directory: $dir" 0
			exit 0
		else
			die "Cannot create ${description} directory: $dir"
		fi
	fi
}

# Recalculate log file paths after configuration changes
#
# Updates LOG_FILE and LOGS_DIR based on configuration overrides.
# Priority:
#   1. If LOG_FILE was overridden (via config or environment), derive LOGS_DIR from it
#   2. If LOGS_DIR was overridden (differs from default), update LOG_FILE to use it
#   3. Otherwise, use STATE_DIR/logs as the default location
#
# Side effects:
#   - Updates global LOGS_DIR variable
#   - Updates global LOG_FILE variable
#
# Note:
#   This function should be called after loading configuration or when STATE_DIR changes
#   to ensure log paths reflect the current configuration.
recalculate_log_paths() {
	local default_logs_dir="${STATE_DIR}/logs"
	local saved_logs_dir="$LOGS_DIR"

	# Priority: LOG_FILE override > LOGS_DIR override > defaults
	# Check if LOG_FILE was overridden first (highest priority)
	# LOG_FILE is overridden if it differs from both the default path and the current LOGS_DIR path
	if [[ "$LOG_FILE" != "${default_logs_dir}/vpn-monitor.log" ]] && [[ "$LOG_FILE" != "${saved_logs_dir}/vpn-monitor.log" ]]; then
		# LOG_FILE was overridden (via config or environment), derive LOGS_DIR from it
		LOGS_DIR=$(dirname "$LOG_FILE")
	elif [[ "$LOGS_DIR" != "$default_logs_dir" ]]; then
		# LOGS_DIR was overridden (via config), update LOG_FILE to use it
		LOG_FILE="${LOGS_DIR}/vpn-monitor.log"
	else
		# Neither overridden, use defaults
		LOGS_DIR="$default_logs_dir"
		LOG_FILE="${LOGS_DIR}/vpn-monitor.log"
	fi
}

# Load configuration from file
#
# Loads configuration variables from the config file if it exists.
# Sets default values for all configuration variables.
# Validates configuration file readability and syntax.
#
# Arguments:
#   $1: Path to configuration file
#
# Returns:
#   0: Configuration loaded successfully
#   1: Configuration file error (exits script)
#
# Side effects:
#   - Sources configuration file to set variables
#   - Updates LOG_FILE and LOGS_DIR paths
#   - Calls log_message (requires logging.sh to be sourced)
#   - Exits script on error
#
# Note:
#   Requires log_message function to be available (from logging.sh)
#   Default values are read from config_schema.sh (single source of truth)

# Safely parse configuration file
#
# Parses a configuration file line by line, extracting only valid variable assignments.
# This function prevents arbitrary code execution by:
#   - Only allowing simple variable assignments (VAR=value or VAR="value")
#   - Validating variable names against CONFIG_SCHEMA whitelist
#   - Using safe assignment methods (printf -v) instead of sourcing
#   - Rejecting any lines that contain code execution patterns
#
# Arguments:
#   $1: Path to configuration file
#
# Returns:
#   0: Configuration parsed successfully
#   1: Configuration file contains invalid or dangerous content (exits script)
#
# Side effects:
#   - Sets global configuration variables via safe indirect assignment (declare -g + printf -v)
#   - Calls die() if invalid content is detected (exits script)
#
# Security:
#   This function prevents arbitrary code execution by:
#   - Only parsing lines matching VAR=value or VAR="value" patterns
#   - Validating variable names against CONFIG_SCHEMA whitelist
#   - Rejecting lines with backticks, $(), eval, source, or other code execution patterns
#   - Using printf -v for safe variable assignment (no code execution)
#
# Examples:
#   safe_parse_config_file "/data/vpn-monitor/vpn-monitor.conf"
#   # Parses config file and sets variables safely
#
# Note:
#   Requires CONFIG_SCHEMA to be defined (from config_schema.sh)
#   Requires die function to be available (from logging.sh)
#   Comments (lines starting with #) and empty lines are ignored
safe_parse_config_file() {
	local config_file="$1"
	local line_num=0
	local line
	local var_name
	local var_value

	# Read config file line by line
	while IFS= read -r line || [[ -n "$line" ]]; do
		line_num=$((line_num + 1))

		# Skip empty lines
		if [[ -z "${line// /}" ]]; then
			continue
		fi

		# Skip comment lines (lines starting with #)
		if [[ "$line" =~ ^[[:space:]]*# ]]; then
			continue
		fi

		# Remove leading/trailing whitespace
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"

		# Skip empty lines after trimming
		if [[ -z "$line" ]]; then
			continue
		fi

		# Security check: Reject lines with dangerous patterns that could execute code
		# Check for backticks, command substitution, eval, source, etc.
		if [[ "$line" =~ [\`\$\(] ]] || [[ "$line" =~ (eval|source|exec|\.\s*\/) ]]; then
			# In fake mode, exit gracefully with success; otherwise die
			if is_fake_mode; then
				handle_error "ERROR" "Configuration file contains dangerous content at line $line_num: $line" 0
				return 1
			else
				die "Configuration file contains dangerous content at line $line_num: $line"
				return 1
			fi
		fi

		# Parse variable assignment: VAR=value or VAR="value" or VAR='value'
		# Extract variable name and value using a more robust approach
		# First, check if line matches VAR=value pattern (with optional quotes and trailing comment)
		if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
			var_name="${BASH_REMATCH[1]}"
			local assignment="${BASH_REMATCH[2]}"

			# Remove trailing comment if present
			assignment="${assignment%%#*}"
			# Remove trailing whitespace after removing comment
			assignment="${assignment%"${assignment##*[![:space:]]}"}"

			# Parse value (quoted or unquoted)
			# Check for unclosed quotes first (syntax error)
			if [[ "$assignment" =~ ^\" ]] && [[ ! "$assignment" =~ \"$ ]]; then
				# Starts with double quote but doesn't end with one - unclosed quote
				# In fake mode, exit gracefully with success; otherwise die
				if is_fake_mode; then
					handle_error "ERROR" "Unclosed double quote in configuration line $line_num: $line" 0
					return 1
				else
					die "Unclosed double quote in configuration line $line_num: $line"
					return 1
				fi
			elif [[ "$assignment" =~ ^\' ]] && [[ ! "$assignment" =~ \'$ ]]; then
				# Starts with single quote but doesn't end with one - unclosed quote
				# In fake mode, exit gracefully with success; otherwise die
				if is_fake_mode; then
					handle_error "ERROR" "Unclosed single quote in configuration line $line_num: $line" 0
					return 1
				else
					die "Unclosed single quote in configuration line $line_num: $line"
					return 1
				fi
			elif [[ "$assignment" =~ ^\"(.*)\"$ ]]; then
				# Double-quoted value (may be empty)
				var_value="${BASH_REMATCH[1]}"
			elif [[ "$assignment" =~ ^\'(.*)\'$ ]]; then
				# Single-quoted value (may be empty)
				var_value="${BASH_REMATCH[1]}"
			elif [[ -z "$assignment" ]]; then
				# Empty unquoted value
				var_value=""
			elif [[ "$assignment" =~ ^[^[:space:]#\"\']+$ ]]; then
				# Unquoted value (no spaces, no quotes, no comment markers)
				var_value="$assignment"
			else
				# Invalid value format (has spaces but not quoted, or other issues)
				# In fake mode, exit gracefully with success; otherwise die
				if is_fake_mode; then
					handle_error "ERROR" "Invalid configuration line $line_num: $line (value must be quoted if it contains spaces)" 0
					return 1
				else
					die "Invalid configuration line $line_num: $line (value must be quoted if it contains spaces)"
					return 1
				fi
			fi
		else
			# Invalid line format (doesn't match VAR=value pattern)
			# In fake mode, exit gracefully with success; otherwise die
			if is_fake_mode; then
				handle_error "ERROR" "Invalid configuration line $line_num: $line (expected VAR=value or VAR=\"value\")" 0
				return 1
			else
				die "Invalid configuration line $line_num: $line (expected VAR=value or VAR=\"value\")"
				return 1
			fi
		fi

		# Validate variable name is in schema whitelist
		if ! get_config_schema "$var_name" >/dev/null 2>&1; then
			# Variable not in schema - reject it for security
			# This prevents setting arbitrary variables that could be used for code injection
			# In fake mode, exit gracefully with success; otherwise die
			if is_fake_mode; then
				handle_error "ERROR" "Unknown configuration variable '$var_name' at line $line_num (not in schema whitelist)" 0
				return 1
			else
				die "Unknown configuration variable '$var_name' at line $line_num (not in schema whitelist)"
				return 1
			fi
		fi

		# Safely assign variable value using printf -v (no code execution)
		# Use declare -g to ensure variable is in global scope
		safe_set_variable "$var_name" "$var_value"
	done <"$config_file"

	return 0
}

# Apply default values from schema
#
# Sets default values for all configuration variables from the schema definition.
# This ensures variables have values before config file is parsed, allowing scripts
# to reference config variables safely. Defaults are read from config_schema.sh,
# making it the single source of truth for default values.
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
	local var_type
	local rules
	local default_val_part

	# Iterate through all variables in schema
	for var_name in "${!CONFIG_SCHEMA[@]}"; do
		# Get default value from schema
		default_val=$(get_config_default "$var_name" 2>/dev/null || echo "")

		# Get schema to check if variable is required
		schema=$(get_config_schema "$var_name" 2>/dev/null || echo "")
		if [[ -n "$schema" ]]; then
			# Parse schema to get required status
			IFS='|' read -r required var_type rules default_val_part <<<"$schema"
		else
			required="optional"
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

# Load configuration from file
#
# Loads configuration variables from the config file if it exists.
# Sets default values for all configuration variables from the schema.
# Validates configuration file readability and safely parses it without code execution.
#
# Arguments:
#   $1: Path to configuration file
#
# Returns:
#   0: Configuration loaded successfully
#   1: Configuration file error (exits script)
#
# Side effects:
#   - Safely parses configuration file to set variables (no code execution)
#   - Updates LOG_FILE and LOGS_DIR paths
#   - Calls log_message (requires logging.sh to be sourced)
#   - Exits script on error
#
# Security:
#   This function uses safe_parse_config_file() instead of source to prevent arbitrary
#   code execution. Only whitelisted variables from CONFIG_SCHEMA can be set, and only
#   simple variable assignments are allowed (no command substitution, eval, etc.).
#
# Note:
#   Requires log_message function to be available (from logging.sh)
#   Default values are read from config_schema.sh (single source of truth)
load_config() {
	local config_file="$1"

	# Set default configuration values from schema
	# This ensures variables have values before config file is parsed,
	# allowing scripts to reference config variables safely.
	# Defaults are read from config_schema.sh, making it the single source of truth.
	apply_schema_defaults

	# Check if config path is a directory (not a file)
	if [[ -d "$config_file" ]]; then
		# Config path is a directory, not a file
		handle_error "WARNING" "Configuration path is a directory, not a file: $config_file"
		handle_error "WARNING" "Using default configuration values"
		# Recalculate LOG_FILE path before first log message (in case STATE_DIR was set via environment)
		recalculate_log_paths
	# Load configuration if it exists and is readable
	elif file_exists_and_readable "$config_file"; then
		# Safely parse config file instead of sourcing (prevents arbitrary code execution)
		# Only whitelisted variables from CONFIG_SCHEMA can be set
		# Only simple variable assignments are allowed (VAR=value or VAR="value")
		if ! safe_parse_config_file "$config_file"; then
			# In fake mode, exit gracefully with success; otherwise die
			if is_fake_mode; then
				handle_error "ERROR" "Failed to parse configuration file: $config_file" 0
				exit 0
			else
				die "Failed to parse configuration file: $config_file"
			fi
		fi

		# Recalculate LOG_FILE path before first log message (in case LOG_FILE was overridden in config)
		recalculate_log_paths

		log_message "INFO" "Configuration loaded from: $config_file"
	else
		# File doesn't exist or isn't readable
		# Check if file exists but isn't readable (for better error message)
		if [[ -f "$config_file" ]]; then
			# In fake mode, exit gracefully with success; otherwise die
			if is_fake_mode; then
				handle_error "ERROR" "Configuration file is not readable: $config_file" 0
				exit 0
			else
				die "Configuration file is not readable: $config_file"
			fi
		fi

		# Recalculate LOG_FILE path before first log message (in case STATE_DIR was set via environment)
		recalculate_log_paths

		handle_error "WARNING" "Configuration file not found: $config_file"
		handle_error "WARNING" "Using default configuration values"
	fi

	# Ensure logs directory exists after config loading (in case paths changed)
	ensure_directory_exists "$LOGS_DIR" "logs"
}

# Parse configuration schema string
#
# Parses a schema string in the format: "required|type|rules|default"
# into individual components using pipe (|) as delimiter.
#
# Arguments:
#   $1: Schema string to parse (format: "required|type|rules|default")
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints parsed components separated by newlines:
#   - Line 1: required status ("required" or "optional")
#   - Line 2: variable type ("string" or "integer")
#   - Line 3: validation rules (comma-separated, may be empty)
#   - Line 4: default value (may be empty)
#
# Examples:
#   schema_parts=$(parse_config_schema "required|integer|min:1|default:5")
#   # Output: "required\ninteger\nmin:1\ndefault:5"
#
# Note:
#   LIMITATION: Uses pipe (|) as delimiter. If a default value contains
#   a pipe character, it will be incorrectly split. Current defaults don't contain
#   pipes, so this limitation is acceptable.
#   Uses IFS='|' read to split the schema string
parse_config_schema() {
	local schema="$1"
	IFS='|' read -r required var_type rules default_val <<<"$schema"
	echo "$required"
	echo "$var_type"
	echo "$rules"
	echo "$default_val"
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
apply_config_default() {
	local var_name="$1"
	local var_value="$2"
	local required="$3"
	local default_val="$4"

	# Check if required
	if [[ "$required" == "required" ]] && [[ -z "$var_value" ]]; then
		die "$var_name is required but not configured"
		# If die doesn't exit (e.g., in tests), return error
		return 1
	fi

	# If optional and empty, use default from schema
	#
	# Default values come from lib/config_schema.sh (single source of truth).
	# This function applies defaults from the schema definition and corrects
	# invalid optional values by applying schema defaults.
	if [[ "$required" == "optional" ]] && [[ -z "$var_value" ]] && [[ -n "$default_val" ]]; then
		# Set default value from schema using safe indirect variable assignment
		# Use declare -g to ensure variable is in global scope, then printf -v for safe assignment
		safe_set_variable "$var_name" "$default_val"
		var_value="$default_val"
	fi

	# If still empty and optional, skip validation
	if [[ "$required" == "optional" ]] && [[ -z "$var_value" ]]; then
		echo "$var_value"
		return 0
	fi

	echo "$var_value"
	return 0
}

# Validate configuration variable type
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
				handle_error "ERROR" "$var_name must be an integer (current value: '$var_value')"
			else
				# Apply default value for optional variables
				if [[ -n "$default_val" ]]; then
					handle_error "WARNING" "$var_name must be an integer (current value: '$var_value'), using default: $default_val"
					# Use safe indirect variable assignment instead of eval
					safe_set_variable "$var_name" "$default_val"
					var_value="$default_val"
					# Re-validate with default value
					if ! [[ "$var_value" =~ ^[0-9]+$ ]]; then
						handle_error "ERROR" "Default value for $var_name is also invalid, keeping invalid value" 0
						return 1
					fi
				else
					handle_error "WARNING" "$var_name must be an integer (current value: '$var_value'), no default available"
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
				die "$var_name cannot be empty"
				# If die doesn't exit (e.g., in tests), return error
				return 1
			else
				# Apply default value for optional variables
				if [[ -n "$default_val" ]]; then
					handle_error "WARNING" "$var_name is empty, using default: $default_val"
					# Use safe indirect variable assignment instead of eval
					safe_set_variable "$var_name" "$default_val"
					var_value="$default_val"
				else
					handle_error "WARNING" "$var_name is empty, no default available"
					return 1
				fi
			fi
		fi
		;;
	min:*)
		local min_val="${rule#min:}"
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
				die "$var_name must be at least $min_val (current value: $var_value)"
				# If die doesn't exit (e.g., in tests), return error
				return 1
			else
				# Apply default value for optional variables
				if [[ -n "$default_val" ]]; then
					handle_error "WARNING" "$var_name must be at least $min_val (current value: $var_value), using default: $default_val"
					# Use safe indirect variable assignment instead of eval
					safe_set_variable "$var_name" "$default_val"
					var_value="$default_val"
				else
					handle_error "WARNING" "$var_name must be at least $min_val (current value: $var_value), no default available"
					return 1
				fi
			fi
		fi
		;;
	max:*)
		local max_val="${rule#max:}"
		if [[ "$var_type" == "integer" ]] && [[ "$var_value" -gt "$max_val" ]]; then
			if [[ "$required" == "required" ]]; then
				die "$var_name must be at most $max_val (current value: $var_value)"
				# If die doesn't exit (e.g., in tests), return error
				return 1
			else
				# Apply default value for optional variables
				if [[ -n "$default_val" ]]; then
					handle_error "WARNING" "$var_name must be at most $max_val (current value: $var_value), using default: $default_val"
					# Use safe indirect variable assignment instead of eval
					safe_set_variable "$var_name" "$default_val"
					var_value="$default_val"
				else
					handle_error "WARNING" "$var_name must be at most $max_val (current value: $var_value), no default available"
					return 1
				fi
			fi
		fi
		;;
	values:*)
		local allowed_values="${rule#values:}"
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
				die "$var_name must be one of: $allowed_values (current value: '$var_value')"
				# If die doesn't exit (e.g., in tests), return error
				return 1
			else
				# Apply default value for optional variables
				if [[ -n "$default_val" ]]; then
					handle_error "WARNING" "$var_name must be one of: $allowed_values (current value: '$var_value'), using default: $default_val"
					# Use safe indirect variable assignment instead of eval
					safe_set_variable "$var_name" "$default_val"
					var_value="$default_val"
				else
					handle_error "WARNING" "$var_name must be one of: $allowed_values (current value: '$var_value'), no default available"
					return 1
				fi
			fi
		fi
		;;
	esac

	echo "$var_value"
	return 0
}

# Validate all configuration rules
#
# Validates a configuration variable against all rules in the schema.
# Processes rules sequentially, stopping on first failure.
# Rules are comma-separated (e.g., "min:1,max:10,values:0,1").
#
# Arguments:
#   $1: Variable name (passed to validate_config_rule)
#   $2: Variable value (updated through rule validation chain)
#   $3: Variable type ("integer" or "string")
#   $4: Required flag ("required" or "optional")
#   $5: Default value from schema
#   $6: Rules string (comma-separated list, e.g., "min:1,max:10" or empty)
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
#   var_value=$(validate_config_rules "COOLDOWN_MINUTES" "15" "integer" "required" "" "min:1,max:1440")
#   # Validates both min:1 and max:1440 rules
#
# Note:
#   Empty rules string is valid (no rules to validate)
#   Uses IFS=',' to split rules string into array
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

	IFS=',' read -ra rule_array <<<"$rules"
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
# Handles schema parsing, default application, type validation, and rule validation.
# This is the main validation function that orchestrates all validation steps.
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
#   - May set variable value via safe indirect assignment (declare -g + printf -v) if default is applied for optional variables
#   - Calls die() for required variables that fail validation
#   - Calls log_message() for warnings about optional variables
#
# Examples:
#   validate_config_var "EXTERNAL_PEER_IPS"
#   validate_config_var "TIER1_THRESHOLD" "5"
#
# Note:
#   Requires CONFIG_SCHEMA to be defined (from config_schema.sh)
#   Unknown variables (not in schema) are allowed for backward compatibility
#   Uses indirect variable reference (${!var_name}) to read variable value if not provided
validate_config_var() {
	local var_name="$1"
	local var_value="${2:-}"

	# Get variable value if not provided
	if [[ -z "$var_value" ]]; then
		local indirect_var="${!var_name:-}"
		var_value="$indirect_var"
	fi

	# Get schema
	local schema
	schema=$(get_config_schema "$var_name")
	if [[ -z "$schema" ]]; then
		# Unknown variable - allow it (for backward compatibility)
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

	# Apply default value if needed
	if ! var_value=$(apply_config_default "$var_name" "$var_value" "$required" "$default_val"); then
		return 1
	fi

	# If still empty and optional, skip validation
	if [[ "$required" == "optional" ]] && [[ -z "$var_value" ]]; then
		return 0
	fi

	# Validate type
	if ! var_value=$(validate_config_type "$var_name" "$var_value" "$var_type" "$required" "$default_val"); then
		return 1
	fi

	# Validate rules
	if ! var_value=$(validate_config_rules "$var_name" "$var_value" "$var_type" "$required" "$default_val" "$rules"); then
		return 1
	fi

	return 0
}

# Validate configuration using schema
#
# Validates all configuration variables against the schema definition.
# Uses schema-based validation for type checking and rule validation.
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
# RELATIVE VALIDATION ORDER DEPENDENCY:
#   Some variables have relative validation rules (e.g., TIER2_THRESHOLD >= TIER1_THRESHOLD).
#   Associative array iteration order is not guaranteed, so dependent variables might be
#   validated before their dependencies. This is handled safely because:
#   1. load_config() sets all default values BEFORE this function is called
#   2. validate_config_var() checks if referenced variables exist before using them
#   3. Variables exist from defaults even if not yet validated
#
#   Example dependencies:
#   - TIER2_THRESHOLD depends on TIER1_THRESHOLD
#   - TIER3_THRESHOLD depends on TIER2_THRESHOLD
#
#   All dependencies work correctly regardless of validation order because defaults are
#   set first in load_config().
validate_config_schema() {
	local validation_failed=0

	# Validate all schema-defined variables
	# Note: Iteration order is not guaranteed, but relative validation handles this
	# correctly by checking if referenced variables exist (they do, from load_config defaults)
	for var_name in "${!CONFIG_SCHEMA[@]}"; do
		if ! validate_config_var "$var_name"; then
			validation_failed=1
		fi
	done

	if [[ $validation_failed -eq 1 ]]; then
		return 1
	fi

	return 0
}

# Validate configuration
#
# Validates that required configuration variables are set and have valid values.
# Uses schema-based validation for type checking and rules, plus custom validation
# for complex cases (IP addresses, threshold ordering).
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
validate_config() {
	# Validate using schema (type checking, ranges, relative validation, etc.)
	# Schema validation handles:
	# - Required field checks
	# - Type validation (integer/string)
	# - Range validation (min/max)
	# - Value enumeration (allowed values)
	# - Relative validation (e.g., TIER2_THRESHOLD >= TIER1_THRESHOLD)
	if ! validate_config_schema; then
		# In fake mode, exit gracefully with success; otherwise die
		if is_fake_mode; then
			handle_error "ERROR" "Configuration validation failed - check schema rules" 0
			exit 0
		else
			die "Configuration validation failed - check schema rules"
		fi
	fi

	# Custom validation: IP address format (not handled by schema)
	# Schema validates EXTERNAL_PEER_IPS is non-empty, but IP format validation requires custom logic
	# Convert space-separated string to array to avoid word splitting and globbing
	# Use IFS to split on spaces, read into array with proper quoting
	local IFS=' '
	local -a external_peer_ips_array
	local -a internal_peer_ips_array
	read -ra external_peer_ips_array <<<"$EXTERNAL_PEER_IPS"
	read -ra internal_peer_ips_array <<<"$INTERNAL_PEER_IPS"

	# Validate external peer IPs (required)
	for peer_ip in "${external_peer_ips_array[@]}"; do
		# Basic validation: non-empty (shouldn't happen after schema validation, but check anyway)
		if [[ -z "$peer_ip" ]]; then
			handle_error "WARNING" "Skipping empty external peer IP"
			continue
		fi

		# Validate IP address format using proper validation function
		# This function handles both IPv4 and IPv6 validation, including security checks
		if ! validate_ip_address "$peer_ip"; then
			handle_error "ERROR" "Invalid peer IP format: $peer_ip" 0
			die "Invalid external peer IP format: $peer_ip"
		fi
	done

	# Validate internal peer IPs (optional, but if set must match count and be valid)
	if [[ -n "$INTERNAL_PEER_IPS" ]]; then
		local external_count=${#external_peer_ips_array[@]}
		local internal_count=${#internal_peer_ips_array[@]}

		if [[ $internal_count -gt 0 ]] && [[ $internal_count -ne $external_count ]]; then
			handle_error "WARNING" "INTERNAL_PEER_IPS count ($internal_count) does not match EXTERNAL_PEER_IPS count ($external_count). Only matching internal IPs will be used."
		fi

		# Validate internal IPs (even if count doesn't match, validate what's there)
		for peer_ip in "${internal_peer_ips_array[@]}"; do
			# Basic validation: non-empty
			if [[ -z "$peer_ip" ]]; then
				handle_error "WARNING" "Skipping empty internal peer IP"
				continue
			fi

			# Validate IP address format
			if ! validate_ip_address "$peer_ip"; then
				die "Invalid internal peer IP format: $peer_ip"
			fi
		done

		# Validate LOCAL_UDM_IP is configured when ping checks are enabled with internal IPs
		if [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
			if [[ -z "${LOCAL_UDM_IP:-}" ]]; then
				handle_error "WARNING" "LOCAL_UDM_IP is not configured but ENABLE_PING_CHECK=1 and INTERNAL_PEER_IPS is set"
				handle_error "WARNING" "LOCAL_UDM_IP is required for ping checks with INTERNAL_PEER_IPS. Ping checks may fail without it."
			else
				# Validate LOCAL_UDM_IP format
				if ! validate_ip_address "$LOCAL_UDM_IP"; then
					die "Invalid LOCAL_UDM_IP format: $LOCAL_UDM_IP"
				fi
			fi
		fi
	fi

	# Validate file paths are writable (if they exist)
	# Check STATE_DIR is writable
	if directory_exists "$STATE_DIR" && ! directory_writable "$STATE_DIR"; then
		handle_error "WARNING" "STATE_DIR is not writable: $STATE_DIR (state file writes may fail, output will go to stderr)" 0
	fi

	# Check LOGS_DIR is writable (if it exists)
	if directory_exists "$LOGS_DIR" && ! directory_writable "$LOGS_DIR"; then
		handle_error "WARNING" "LOGS_DIR is not writable: $LOGS_DIR (log writes may fail, output will go to stderr)" 0
	fi

	# Check LOG_FILE parent directory is writable (if it exists)
	local log_file_dir
	log_file_dir=$(dirname "$LOG_FILE")
	if directory_exists "$log_file_dir" && ! directory_writable "$log_file_dir"; then
		handle_error "WARNING" "LOG_FILE directory is not writable: $log_file_dir (log writes may fail, output will go to stderr)" 0
	fi

	return 0
}
