#!/bin/bash
#
# Configuration loading and validation for UDM VPN Monitor
# Handles loading configuration files and validating settings
#
# Version: 0.4.3
#
# Default Value Handling:
#   Default values are defined in lib/config_schema.sh as the single source of truth.
#   The load_config() function reads defaults from the schema using get_config_default(),
#   ensuring consistency and eliminating duplication. To change defaults, update only
#   config_schema.sh - load_config() will automatically use the updated values.
#
#   Default application logic is centralized in apply_optional_default() function, which
#   is used by apply_config_default(), validate_config_type(), and validate_config_rule()
#   to ensure consistent behavior when applying defaults for optional variables that are
#   empty or invalid. This eliminates duplication and ensures defaults are applied uniformly.
#

# Source constants for magic numbers
# shellcheck source=lib/constants.sh
# Determine lib directory (where this file is located)
# Always set LIB_DIR, even if empty (handles cases where BASH_SOURCE[0] resolution fails)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 2>/dev/null || LIB_DIR=""
# Note: safe_source_lib not available here since constants.sh is sourced before common.sh
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
# Pre-declare CONFIG_SCHEMA as empty array to avoid unbound variable errors with set -u
# The schema file will populate it when sourced
# Use -gA to ensure it's global (important when config.sh is sourced from within functions)
declare -gA CONFIG_SCHEMA=()

# Define fallback functions (used if schema file can't be loaded)
# These are defined as a function to avoid duplication
define_schema_fallback_functions() {
	get_config_schema() { return 1; }
	is_config_required() { return 1; }
	get_config_default() {
		echo ""
		return 0
	}
}

# Try to source the schema file directly
# Note: We source directly instead of using safe_source_lib because the array declaration
# in the schema file needs to populate the pre-declared array, and safe_source_lib
# doesn't work correctly for this use case.
# Handle case where LIB_DIR might be empty (e.g., when sourced with relative path and cd fails)
if [[ -z "${LIB_DIR:-}" ]]; then
	# LIB_DIR not set, try to determine from BASH_SOURCE[0] using readlink if available
	# This handles cases where the file was sourced with a relative path
	source_file="${BASH_SOURCE[0]}"
	if command -v readlink >/dev/null 2>&1 && [[ -L "$source_file" ]] || [[ -f "$source_file" ]]; then
		# Try to resolve to absolute path
		if source_file=$(readlink -f "$source_file" 2>/dev/null) || [[ "$source_file" =~ ^/ ]]; then
			LIB_DIR="$(cd "$(dirname "$source_file")" && pwd)" 2>/dev/null || LIB_DIR=""
		fi
	fi
	# If still empty, try relative to current directory as last resort
	if [[ -z "${LIB_DIR:-}" ]] && [[ "${BASH_SOURCE[0]}" =~ \.\.?/ ]]; then
		LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 2>/dev/null || LIB_DIR=""
	fi
fi

if [[ -n "${LIB_DIR:-}" ]] && [[ -f "${LIB_DIR}/config_schema.sh" ]] && [[ -r "${LIB_DIR}/config_schema.sh" ]]; then
	# Source the schema file, suppressing stderr to avoid cluttering output
	# The array is already declared above, so the schema file will populate it
	if ! source "${LIB_DIR}/config_schema.sh" 2>/dev/null; then
		# Source failed, array remains empty, use fallback functions
		define_schema_fallback_functions
	fi
else
	# File doesn't exist or isn't readable, array is already empty, use fallback functions
	define_schema_fallback_functions
fi

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
#   Never returns if directory creation fails (exits script)
#
# Side effects:
#   - In fake mode: logs error and exits with code 0
#   - In normal mode: dies (exits script) if directory creation fails
#
# Note:
#   Requires handle_error_or_exit_fake_mode function to be available (from logging.sh)
ensure_directory_exists() {
	local dir="$1"
	local description="${2:-directory}"

	# Try to create directory
	if ! mkdir -p "$dir" 2>/dev/null; then
		# In fake mode: returns 1, in normal mode: exits via die()
		handle_error_or_exit_fake_mode "Cannot create ${description} directory: $dir" || return 1
	fi

	# Verify directory was actually created (defensive check)
	# This handles edge cases where mkdir -p might appear to succeed but directory doesn't exist
	if [[ ! -d "$dir" ]]; then
		# In fake mode: returns 1, in normal mode: exits via die()
		handle_error_or_exit_fake_mode "Directory was not created: $dir" || return 1
	fi

	return 0
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

# Handle configuration parsing error
#
# Provides consistent error handling for configuration parsing errors that should
# exit gracefully in fake mode (NO_ESCALATE=1) or die in normal mode. This function
# standardizes the pattern of handling errors differently based on fake mode.
#
# Arguments:
#   $1: Error message to log
#   $2: Line number where error occurred (optional, for better error messages)
#
# Returns:
#   1: In fake mode (allows calling function to detect error and return failure)
#   Never returns in normal mode (dies with specified exit code)
#
# Side effects:
#   - Logs error message using handle_error in fake mode
#   - Dies (exits with code 1) in normal mode
#
# Examples:
#   handle_config_error "Dangerous content detected" 5
#   # Logs error or dies depending on fake mode
#   if ! handle_config_error "Parse error"; then
#       # In fake mode, this branch executes (returns 1)
#       return 1
#   fi
#
# Note:
#   Requires handle_error_or_exit_fake_mode function to be available (from logging.sh)
#   In fake mode, returns 1 to allow callers to track errors and return failure status
handle_config_error() {
	local message="$1"
	local line_num="${2:-}"
	local full_message

	if [[ -n "$line_num" ]]; then
		full_message="$message (line $line_num)"
	else
		full_message="$message"
	fi

	handle_error_or_exit_fake_mode "$full_message"
}

# Parse quoted or unquoted value from assignment
#
# Extracts and validates the value portion of a configuration assignment.
# Handles double-quoted, single-quoted, and unquoted values.
# Properly handles escaped quotes and validates quote pairing.
#
# Arguments:
#   $1: Assignment value (the part after VAR=, already trimmed and comment-removed)
#   $2: Original configuration line (for error messages)
#   $3: Line number (for error messages)
#   $4: Name of associative array to store result (passed by reference)
#
# Returns:
#   0: Value parsed successfully (result["value"] is set)
#   1: Invalid value format or syntax error
#
# Output:
#   Sets associative array element:
#   - result["value"]: Extracted variable value
#
# Side effects:
#   - Sets associative array element via nameref
#   - Logs error messages on syntax errors
#
# Examples:
#   declare -A parse_result
#   if parse_quoted_value "Site-to-Site" "VPN_NAME=Site-to-Site" 1 "parse_result"; then
#       echo "Value: ${parse_result[value]}"
#   fi
#   declare -A parse_result
#   if parse_quoted_value "\"value with \\\" escaped\"" "VAR=\"value with \\\" escaped\"" 1 "parse_result"; then
#       echo "Value: ${parse_result[value]}"
#   fi
#
# Note:
#   Requires log_message function to be available (from logging.sh)
#   Properly handles escaped quotes (\", \') and validates quote pairing
parse_quoted_value() {
	local assignment="$1"
	local line="$2"
	local line_num="$3"
	local -n result_array="$4"
	local i=0
	local len=${#assignment}
	local in_quotes=false
	local quote_char=""
	local result=""
	local escaped=false
	local quote_closed=false

	# Handle empty assignment
	if [[ -z "$assignment" ]]; then
		result_array["value"]=""
		return 0
	fi

	# Check if assignment starts with a quote
	if [[ "${assignment:0:1}" == "\"" ]]; then
		in_quotes=true
		quote_char="\""
		i=1
	elif [[ "${assignment:0:1}" == "'" ]]; then
		in_quotes=true
		quote_char="'"
		i=1
	fi

	# If not quoted, validate it's a simple unquoted value
	if [[ "$in_quotes" == false ]]; then
		# Unquoted value must not contain spaces, quotes, or comment markers
		if [[ "$assignment" =~ [[:space:]\"\'\#] ]]; then
			log_message "ERROR" "Invalid configuration line: $line (value must be quoted if it contains spaces, quotes, or comment markers) (line $line_num)"
			return 1
		fi
		result_array["value"]="$assignment"
		return 0
	fi

	# Parse quoted string character by character
	# Note: Single quotes in bash don't allow escaping - everything is literal except the quote itself
	# Double quotes allow escaping with backslash
	while [[ $i -lt $len ]]; do
		local char="${assignment:$i:1}"

		if [[ "$quote_char" == "'" ]]; then
			# Single-quoted string: no escaping, everything literal except closing quote
			if [[ "$char" == "'" ]]; then
				# Closing single quote found
				# Check if there's any content after the closing quote
				if [[ $((i + 1)) -lt $len ]]; then
					local remaining="${assignment:$((i + 1))}"
					# Allow trailing whitespace after closing quote
					if [[ "$remaining" =~ ^[[:space:]]*$ ]]; then
						# Only whitespace after quote - valid
						quote_closed=true
						break
					else
						# Non-whitespace after quote - invalid (unexpected content)
						log_message "ERROR" "Invalid configuration line: $line (unexpected content after closing quote) (line $line_num)"
						return 1
					fi
				else
					# End of string - valid closing quote
					quote_closed=true
					break
				fi
			else
				# Regular character in single-quoted string - add as-is
				result="${result}${char}"
			fi
		else
			# Double-quoted string: handle escaping
			if [[ "$escaped" == true ]]; then
				# Handle escaped characters
				if [[ "$char" == "\\" ]]; then
					# Escaped backslash - add single backslash
					result="${result}\\"
				elif [[ "$char" == "\"" ]]; then
					# Escaped double quote - add literal quote
					result="${result}\""
				elif [[ "$char" == "'" ]]; then
					# Escaped single quote - add literal quote
					result="${result}'"
				else
					# Other escaped character - add as-is (backslash + char)
					result="${result}\\${char}"
				fi
				escaped=false
			elif [[ "$char" == "\\" ]]; then
				# Escape character - next character is escaped
				escaped=true
			elif [[ "$char" == "\"" ]]; then
				# Closing double quote found
				# Check if there's any content after the closing quote
				if [[ $((i + 1)) -lt $len ]]; then
					local remaining="${assignment:$((i + 1))}"
					# Allow trailing whitespace after closing quote
					if [[ "$remaining" =~ ^[[:space:]]*$ ]]; then
						# Only whitespace after quote - valid
						quote_closed=true
						break
					else
						# Non-whitespace after quote - invalid (unexpected content)
						log_message "ERROR" "Invalid configuration line: $line (unexpected content after closing quote) (line $line_num)"
						return 1
					fi
				else
					# End of string - valid closing quote
					quote_closed=true
					break
				fi
			else
				# Regular character - add to result
				result="${result}${char}"
			fi
		fi

		i=$((i + 1))
	done

	# Check if we're still in quotes (unclosed quote)
	# If quote_closed is true, we successfully found and processed the closing quote
	if [[ "$in_quotes" == true ]] && [[ "$quote_closed" == false ]]; then
		# Quote was not closed - this is an error
		log_message "ERROR" "Unclosed ${quote_char} quote in configuration line: $line (line $line_num)"
		return 1
	fi

	# Set the extracted value
	result_array["value"]="$result"
	return 0
}

# Parse variable assignment from configuration line
#
# Extracts variable name and value from a configuration line in the format VAR=value.
# Handles quoted values (double quotes, single quotes) and unquoted values.
# Validates quote syntax and value format.
#
# Arguments:
#   $1: Configuration line to parse (should already be trimmed)
#   $2: Line number (for error messages)
#   $3: Name of associative array to store result (passed by reference)
#
# Returns:
#   0: Assignment parsed successfully (result["name"] and result["value"] are set)
#   1: Invalid assignment format or syntax error
#
# Output:
#   Sets associative array elements:
#   - result["name"]: Extracted variable name
#   - result["value"]: Extracted variable value
#
# Side effects:
#   - Sets associative array elements via nameref
#   - Logs error messages on syntax errors
#
# Examples:
#   declare -A parse_result
#   if parse_assignment "VPN_NAME=Site-to-Site" 1 "parse_result"; then
#       echo "Variable: ${parse_result[name]}, Value: ${parse_result[value]}"
#   fi
#
# Note:
#   Requires log_message function to be available (from logging.sh)
#   Requires parse_quoted_value function to be available
parse_assignment() {
	local line="$1"
	local line_num="$2"
	local -n result_array="$3"

	# Check if line matches VAR=value pattern
	if ! [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
		log_message "ERROR" "Invalid configuration line: $line (expected VAR=value or VAR=\"value\") (line $line_num)"
		return 1
	fi

	result_array["name"]="${BASH_REMATCH[1]}"
	local assignment="${BASH_REMATCH[2]}"

	# Remove trailing comment if present
	assignment="${assignment%%#*}"
	# Remove trailing whitespace after removing comment
	assignment="${assignment%"${assignment##*[![:space:]]}"}"

	# Parse value (quoted or unquoted)
	if ! parse_quoted_value "$assignment" "$line" "$line_num" "$3"; then
		return 1
	fi

	return 0
}

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
#   - Uses local associative array for parsing (no global variable pollution)
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
	local -A parse_result
	local parse_error=0

	# Read config file line by line
	while IFS= read -r line || [[ -n "$line" ]]; do
		line_num=$((line_num + 1))
		# Reset associative array for each line
		parse_result=()

		# Remove leading/trailing whitespace first
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"

		# Skip empty lines after trimming
		if [[ -z "$line" ]]; then
			continue
		fi

		# Skip comment lines (lines starting with #)
		if [[ "$line" =~ ^[[:space:]]*# ]]; then
			continue
		fi

		# Validate security - reject lines with dangerous patterns
		if [[ "$line" =~ [\`\$\(] ]] || [[ "$line" =~ (eval|source|exec|\.\s*\/) ]]; then
			if ! handle_config_error "Configuration file contains dangerous content: $line" "$line_num"; then
				# In fake mode, handle_config_error returns 1 (failure)
				# In normal mode, handle_config_error exits and never returns
				parse_error=1
			fi
		fi

		# Parse assignment
		if ! parse_assignment "$line" "$line_num" "parse_result"; then
			if ! handle_config_error "Failed to parse configuration file: $config_file (line $line_num: $line)"; then
				# In fake mode, handle_config_error returns 1 (failure)
				# In normal mode, handle_config_error exits and never returns
				parse_error=1
			fi
			continue
		fi

		# Validate variable name is in schema whitelist
		if ! get_config_schema "${parse_result[name]}" >/dev/null 2>&1; then
			# Variable not in schema - reject it for security
			# This prevents setting arbitrary variables that could be used for code injection
			if ! handle_config_error "Unknown configuration variable '${parse_result[name]}' (not in schema whitelist)" "$line_num"; then
				# In fake mode, handle_config_error returns 1 (failure)
				# In normal mode, handle_config_error exits and never returns
				parse_error=1
			fi
			continue
		fi

		# Safely assign variable value using printf -v (no code execution)
		# Use declare -g to ensure variable is in global scope
		safe_set_variable "${parse_result[name]}" "${parse_result[value]}"
	done <"$config_file"

	# Return error status if any parsing errors occurred (in fake mode)
	if [[ "$parse_error" -eq 1 ]]; then
		return 1
	fi

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
# Validate critical configuration variables after parsing
#
# Validates that all required configuration variables are declared after parsing completes.
# This ensures that even if parsing partially failed, we catch missing critical variables
# before proceeding with incomplete configuration.
#
# Returns:
#   0: All required variables are declared
#   1: One or more required variables are missing
#
# Side effects:
#   - Logs errors for missing required variables
#
# Note:
#   This function should be called immediately after safe_parse_config_file() succeeds
#   to catch cases where parsing partially failed but didn't return an error.
#   Since apply_schema_defaults() runs before parsing, all variables should already be
#   declared, but this provides a defensive check for edge cases.
validate_critical_config_vars() {
	local var_name
	local schema
	local schema_parts
	local required
	local missing_required=()

	# Check all schema-defined variables
	for var_name in "${!CONFIG_SCHEMA[@]}"; do
		# Get schema for this variable
		schema=$(get_config_schema "$var_name" 2>/dev/null || echo "")
		if [[ -z "$schema" ]]; then
			# Variable not in schema - skip (for backward compatibility)
			continue
		fi

		# Parse schema using standard function (consistent with rest of codebase)
		schema_parts=$(parse_config_schema "$schema")
		{
			read -r required
		} <<<"$schema_parts"

		# Only validate required variables here
		# Optional variables are validated later in validate_config_schema()
		if [[ "$required" != "required" ]]; then
			continue
		fi

		# Check if required variable is declared
		# Since apply_schema_defaults() runs before parsing, all variables should
		# already be declared, but this provides a defensive check for edge cases
		# where parsing might have failed silently or defaults weren't applied correctly
		if ! declare -p "$var_name" &>/dev/null; then
			# Variable not declared at all - this is a critical error
			missing_required+=("$var_name")
		fi
	done

	# Report missing required variables
	if [[ ${#missing_required[@]} -gt 0 ]]; then
		handle_error "ERROR" "Missing required configuration variables: ${missing_required[*]}"
		return 1
	fi

	return 0
}

# Handle fatal config error with proper fake mode support
#
# Helper function to handle fatal configuration errors that need to exit gracefully
# in fake mode. Since load_config is called at the top level, it must exit directly
# with code 0 in fake mode rather than returning an error code.
#
# Arguments:
#   $1: Error message
#   $2: Exit code (optional, defaults to EXIT_CONFIG_ERROR)
#
# Returns:
#   Never returns (exits script)
#
# Side effects:
#   - Logs error message
#   - Exits with code 0 in fake mode
#   - Exits with specified code in normal mode
handle_fatal_config_error() {
	local message="$1"
	local exit_code="${2:-${EXIT_CONFIG_ERROR:-2}}"
	if ! handle_error_or_exit_fake_mode "$message" "$exit_code"; then
		# In fake mode, handle_error_or_exit_fake_mode returns 1
		# Exit gracefully with code 0 in fake mode since load_config is called at top level
		exit "${EXIT_SUCCESS:-0}"
	fi
	# In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
	# This line is unreachable but included for clarity
}

load_config() {
	local config_file="$1"

	# Set default configuration values from schema
	# This ensures variables have values before config file is parsed,
	# allowing scripts to reference config variables safely.
	# Defaults are read from config_schema.sh, making it the single source of truth.
	apply_schema_defaults

	# Save LOGS_DIR before parsing config to detect if it was explicitly set
	local logs_dir_before_parse="${LOGS_DIR:-}"

	# Check if config path is a directory (not a file)
	if [[ -d "$config_file" ]]; then
		# Config path is a directory, not a file
		handle_error "WARNING" "Configuration path is a directory, not a file: $config_file"
		handle_error "WARNING" "Using default configuration values"
	# Load configuration if it exists and is readable
	elif file_exists_and_readable "$config_file"; then
		# Safely parse config file instead of sourcing (prevents arbitrary code execution)
		# Only whitelisted variables from CONFIG_SCHEMA can be set
		# Only simple variable assignments are allowed (VAR=value or VAR="value")
		if ! safe_parse_config_file "$config_file"; then
			handle_fatal_config_error "Failed to parse configuration file: $config_file" "${EXIT_CONFIG_ERROR:-2}"
		fi

		# Validate that critical configuration variables are set after parsing
		# This ensures that even if parsing partially failed, we catch missing critical variables
		if ! validate_critical_config_vars; then
			handle_fatal_config_error "Critical configuration variables are missing after parsing: $config_file" "${EXIT_CONFIG_ERROR:-2}"
		fi

		log_message "INFO" "Configuration loaded from: $config_file"
	else
		# File doesn't exist or isn't readable
		# Check if file exists but isn't readable (for better error message)
		if [[ -f "$config_file" ]]; then
			handle_fatal_config_error "Configuration file is not readable: $config_file" "${EXIT_CONFIG_ERROR:-2}"
		fi

		handle_error "WARNING" "Configuration file not found: $config_file"
		handle_error "WARNING" "Using default configuration values"
	fi

	# Compute log paths after config loading (consolidated path computation)
	# Priority:
	#   1. If LOGS_DIR was explicitly set in config (changed after parsing), use that value
	#   2. If LOG_FILE was explicitly overridden (via config or environment), derive LOGS_DIR from it
	#   3. Otherwise, ensure LOG_FILE matches LOGS_DIR (LOGS_DIR is already set correctly from config)
	local log_filename
	log_filename=$(basename "$LOG_FILE" 2>/dev/null || echo "vpn-monitor.log")
	local original_log_file="${LOG_FILE}" # Save original LOG_FILE before updating
	local log_file_dir
	log_file_dir=$(dirname "$LOG_FILE" 2>/dev/null)

	# If LOGS_DIR wasn't explicitly set in config but LOG_FILE was overridden, derive LOGS_DIR from LOG_FILE
	if [[ "$logs_dir_before_parse" == "${LOGS_DIR:-}" ]] && [[ -n "$log_file_dir" ]] && [[ "$log_file_dir" != "${LOGS_DIR:-}" ]]; then
		LOGS_DIR="$log_file_dir"
	fi

	# Ensure LOG_FILE matches LOGS_DIR (this happens in all cases)
	LOG_FILE="${LOGS_DIR}/${log_filename}"

	# Compute state paths after config loading (consolidated path computation)
	# Update paths that depend on STATE_DIR (STATE_DIR is already set correctly from config)
	if [[ -n "${LOCKFILE:-}" ]]; then
		LOCKFILE="${STATE_DIR}/vpn-monitor.lock"
	fi
	if [[ -n "${COOLDOWN_UNTIL_FILE:-}" ]]; then
		COOLDOWN_UNTIL_FILE="${STATE_DIR}/cooldown_until"
	fi
	if [[ -n "${PIDFILE:-}" ]]; then
		PIDFILE="${STATE_DIR}/vpn-keepalive.pid"
	fi

	# Ensure logs directory exists after config loading (in case paths changed)
	# This must be called after LOGS_DIR is potentially updated from LOG_FILE override
	local original_logs_dir="${LOGS_DIR}"
	if ! ensure_directory_exists "$LOGS_DIR" "logs"; then
		# Directory creation failed - in fake mode this returns 1, in normal mode it exits
		# If we get here in fake mode, try to fallback to original log file location
		# log_message will fallback to stderr if this also fails
		if is_fake_mode && [[ -n "$original_log_file" ]] && [[ "$original_log_file" != "${LOGS_DIR}/${log_filename}" ]]; then
			local original_log_file_dir
			original_log_file_dir=$(dirname "$original_log_file" 2>/dev/null)
			if [[ -n "$original_log_file_dir" ]] && mkdir -p "$original_log_file_dir" 2>/dev/null && [[ -w "$original_log_file_dir" ]]; then
				# Fallback to original log file location
				LOGS_DIR="$original_log_file_dir"
				LOG_FILE="$original_log_file"
				handle_error "WARNING" "Failed to create logs directory: $original_logs_dir, using original log file location: $LOG_FILE"
			else
				# Can't fallback - log_message will write to stderr
				handle_error "WARNING" "Failed to create logs directory: $original_logs_dir (continuing in fake mode, logs will go to stderr)"
			fi
		fi
	fi

	# Ensure state directory exists after config loading (in case STATE_DIR was overridden)
	if ! ensure_directory_exists "$STATE_DIR" "state"; then
		# Directory creation failed - in fake mode this returns 1, in normal mode it exits
		# If we get here in fake mode, log warning but continue
		if is_fake_mode; then
			handle_error "WARNING" "Failed to create state directory: $STATE_DIR (continuing in fake mode)"
		fi
	fi
}

# Parse configuration schema string
#
# Parses a schema string in the format: "required|type|rule1|rule2|...|default:value"
# into individual components. Handles multiple rules separated by pipes.
#
# Arguments:
#   $1: Schema string to parse (format: "required|type|rule1|rule2|...|default:value")
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints parsed components separated by newlines:
#   - Line 1: required status ("required" or "optional")
#   - Line 2: variable type ("string" or "integer")
#   - Line 3: validation rules (joined with ||| separator, may be empty)
#   - Line 4: default value (may be empty, format: "default:value" or empty)
#
# Examples:
#   schema_parts=$(parse_config_schema "required|integer|min:1|max:10|default:5")
#   # Output: "required\ninteger\nmin:1|||max:10\n5"
#   # Note: Rules are joined with ||| separator to avoid conflicts with commas in values: rules
#
# Rule Separator Format:
#   Rules in the schema definition are separated by single pipe (|) characters.
#   During parsing, multiple rules are joined with triple-pipe (|||) separator
#   to avoid conflicts with commas in values: rules (e.g., "values:0,1").
#
#   Example: "optional|integer|min:1|max:10|default:3"
#   Parsed rules string: "min:1|||max:10"
#
#   When validating, rules are split by ||| separator first. If no ||| found,
#   falls back to comma-separated format for backward compatibility.
#   Special case: Single "values:" rule is not split (comma is part of value).
#
# Note:
#   Schema format allows multiple rules separated by pipes (e.g., "min:1|max:10").
#   Rules are joined with ||| separator internally to avoid conflicts with commas
#   in values: rules. The default value is extracted from the last field starting with "default:".
parse_config_schema() {
	local schema="$1"
	local required
	local var_type
	local rules=""
	local default_val=""

	# Split schema by pipe
	IFS='|' read -ra parts <<<"$schema"

	# First part is required status
	required="${parts[0]}"

	# Second part is type
	var_type="${parts[1]}"

	# Remaining parts are rules and default
	# Rules are everything before a part starting with "default:"
	# Default is the part starting with "default:" (extract value after "default:")
	# Use ||| as separator to avoid conflicts with commas in values: rules (e.g., values:0,1)
	local i=2
	while [[ $i -lt ${#parts[@]} ]]; do
		if [[ "${parts[$i]}" =~ ^default:(.*)$ ]]; then
			# Found default value
			default_val="${BASH_REMATCH[1]}"
			break
		else
			# This is a rule - add to rules (using ||| separator to avoid comma conflicts)
			if [[ -z "$rules" ]]; then
				rules="${parts[$i]}"
			else
				rules="${rules}|||${parts[$i]}"
			fi
		fi
		i=$((i + 1))
	done

	echo "$required"
	echo "$var_type"
	echo "$rules"
	echo "$default_val"
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
		handle_error "WARNING" "$warning_msg"
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
		handle_error_or_exit_fake_mode "$var_name is required but not configured" "${EXIT_VALIDATION_ERROR:-3}"
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
				# Use handle_error_or_exit_fake_mode to respect fake mode
				# In fake mode, it returns 1; in normal mode it calls die() and never returns
				if ! handle_error_or_exit_fake_mode "$var_name must be an integer (current value: '$var_value')" "${EXIT_VALIDATION_ERROR:-3}"; then
					# In fake mode, handle_error_or_exit_fake_mode returns 1
					return 1
				fi
				# In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
			else
				# Validate default before applying to avoid setting invalid global variable
				if [[ -z "$default_val" ]]; then
					# No default available
					handle_error "WARNING" "$var_name must be an integer (current value: '$var_value'), no default available"
					return 1
				elif ! [[ "$default_val" =~ ^[0-9]+$ ]]; then
					# Default value is invalid - don't apply it
					handle_error "ERROR" "Default value for $var_name is invalid (default: '$default_val'), cannot apply default" 0
					return 1
				fi
				# Default is valid, apply it (centralized logic)
				local updated_value
				if updated_value=$(apply_optional_default "$var_name" "$var_value" "$required" "$default_val" "$var_name must be an integer (current value: '$var_value'), using default: $default_val"); then
					var_value="$updated_value"
				else
					# This should not happen since we validated default above, but handle gracefully
					handle_error "WARNING" "$var_name must be an integer (current value: '$var_value'), failed to apply default"
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
				# Note: This function exits, so return 1 won't be reached
				# but we include it for clarity and in case exit is trapped
				handle_error_or_exit_fake_mode "$var_name cannot be empty" "${EXIT_VALIDATION_ERROR:-3}"
				# If handle_error_or_exit_fake_mode doesn't exit (e.g., in tests), return error
				return 1
			else
				# Apply default value for optional variables (centralized logic)
				local updated_value
				if updated_value=$(apply_optional_default "$var_name" "$var_value" "$required" "$default_val" "$var_name is empty, using default: $default_val"); then
					var_value="$updated_value"
				else
					handle_error "WARNING" "$var_name is empty, no default available"
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
				# Note: This function exits, so return 1 won't be reached
				# but we include it for clarity and in case exit is trapped
				handle_error_or_exit_fake_mode "$var_name must be at least $min_val (current value: $var_value)" "${EXIT_VALIDATION_ERROR:-3}"
				# If handle_error_or_exit_fake_mode doesn't exit (e.g., in tests), return error
				return 1
			else
				# Apply default value for optional variables (centralized logic)
				local updated_value
				if updated_value=$(apply_optional_default "$var_name" "$var_value" "$required" "$default_val" "$var_name must be at least $min_val (current value: $var_value), using default: $default_val"); then
					var_value="$updated_value"
				else
					handle_error "WARNING" "$var_name must be at least $min_val (current value: $var_value), no default available"
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
				# Note: This function exits, so return 1 won't be reached
				# but we include it for clarity and in case exit is trapped
				handle_error_or_exit_fake_mode "$var_name must be at most $max_val (current value: $var_value)" "${EXIT_VALIDATION_ERROR:-3}"
				# If handle_error_or_exit_fake_mode doesn't exit (e.g., in tests), return error
				return 1
			else
				# Apply default value for optional variables (centralized logic)
				local updated_value
				if updated_value=$(apply_optional_default "$var_name" "$var_value" "$required" "$default_val" "$var_name must be at most $max_val (current value: $var_value), using default: $default_val"); then
					var_value="$updated_value"
				else
					handle_error "WARNING" "$var_name must be at most $max_val (current value: $var_value), no default available"
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
				# Note: This function exits, so return 1 won't be reached
				# but we include it for clarity and in case exit is trapped
				handle_error_or_exit_fake_mode "$var_name must be one of: $allowed_values (current value: '$var_value')" "${EXIT_VALIDATION_ERROR:-3}"
				# If handle_error_or_exit_fake_mode doesn't exit (e.g., in tests), return error
				return 1
			else
				# Apply default value for optional variables (centralized logic)
				local updated_value
				if updated_value=$(apply_optional_default "$var_name" "$var_value" "$required" "$default_val" "$var_name must be one of: $allowed_values (current value: '$var_value'), using default: $default_val"); then
					var_value="$updated_value"
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

	# Split rules by ||| separator (used to avoid conflicts with commas in values: rules)
	# Fallback to comma for backward compatibility with old format
	# Special case: if rules is a single values: rule (e.g., "values:0,1"), don't split it
	local rule_array=()
	if [[ "$rules" == *"|||"* ]]; then
		# Use awk to split by ||| since IFS doesn't support multi-character separators
		while IFS= read -r rule; do
			[[ -n "$rule" ]] && rule_array+=("$rule")
		done < <(echo "$rules" | awk -F'\\|\\|\\|' '{for(i=1;i<=NF;i++) print $i}')
	elif [[ "$rules" =~ ^values: ]]; then
		# Single values: rule - don't split (comma is part of the rule value)
		rule_array=("$rules")
	else
		# Old format: comma-separated (for backward compatibility)
		IFS=',' read -ra rule_array <<<"$rules"
	fi

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
#   validate_config_var "EXTERNAL_PEER_IPS"
#   validate_config_var "TIER1_THRESHOLD" "5"
#
# Note:
#   Requires CONFIG_SCHEMA to be defined (from config_schema.sh)
#   Unknown variables (not in schema) are allowed for backward compatibility
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

	# ============================================================
	# SECTION 3: Apply default value if needed
	# ============================================================
	# Check if required variable is empty
	if [[ "$required" == "required" ]] && [[ -z "$var_value" ]]; then
		handle_error_or_exit_fake_mode "$var_name is required but not configured" "${EXIT_VALIDATION_ERROR:-3}"
		return 1
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
	case "$var_type" in
	integer)
		if ! [[ "$var_value" =~ ^[0-9]+$ ]]; then
			if [[ "$required" == "required" ]]; then
				handle_error_or_exit_fake_mode "$var_name must be an integer (current value: '$var_value')" "${EXIT_VALIDATION_ERROR:-3}"
				return 1
			else
				# Optional variable with invalid type - try to apply default
				if [[ -z "$default_val" ]]; then
					handle_error "WARNING" "$var_name must be an integer (current value: '$var_value'), no default available"
					return 1
				elif ! [[ "$default_val" =~ ^[0-9]+$ ]]; then
					# Default value is invalid - don't apply it
					handle_error "ERROR" "Default value for $var_name is invalid (default: '$default_val'), cannot apply default" 0
					return 1
				else
					# Default is valid, apply it (using centralized function)
					local updated_value
					if updated_value=$(apply_optional_default "$var_name" "$var_value" "$required" "$default_val" "$var_name must be an integer (current value: '$var_value'), using default: $default_val"); then
						var_value="$updated_value"
					else
						# This should not happen since we validated default above, but handle gracefully
						handle_error "WARNING" "$var_name must be an integer (current value: '$var_value'), failed to apply default"
						return 1
					fi
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

	# ============================================================
	# SECTION 5: Validate rules
	# ============================================================
	if [[ -n "$rules" ]]; then
		# Split rules by ||| separator (used to avoid conflicts with commas in values: rules)
		# Fallback to comma for backward compatibility with old format
		# Special case: if rules is a single values: rule (e.g., "values:0,1"), don't split it
		local rule_array=()
		if [[ "$rules" == *"|||"* ]]; then
			# Use awk to split by ||| since IFS doesn't support multi-character separators
			while IFS= read -r rule; do
				[[ -n "$rule" ]] && rule_array+=("$rule")
			done < <(echo "$rules" | awk -F'\\|\\|\\|' '{for(i=1;i<=NF;i++) print $i}')
		elif [[ "$rules" =~ ^values: ]]; then
			# Single values: rule - don't split (comma is part of the rule value)
			rule_array=("$rules")
		else
			# Old format: comma-separated (for backward compatibility)
			IFS=',' read -ra rule_array <<<"$rules"
		fi

		for rule in "${rule_array[@]}"; do
			if ! var_value=$(validate_config_rule "$var_name" "$var_value" "$var_type" "$required" "$default_val" "$rule"); then
				return 1
			fi
		done
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

# Extract location name from variable name
#
# Extracts the location name from a LOCATION_<NAME>_EXTERNAL or LOCATION_<NAME>_INTERNAL variable name.
# Pattern: Extract text between LOCATION_ and _EXTERNAL or _INTERNAL
#
# Arguments:
#   $1: Variable name (e.g., "LOCATION_NYC_EXTERNAL")
#
# Returns:
#   0: Location name extracted successfully
#   1: Invalid variable name format
#
# Output:
#   Prints location name to stdout (e.g., "NYC")
#
# Examples:
#   location=$(extract_location_name "LOCATION_NYC_EXTERNAL")
#   # Returns: "NYC"
#
# Note:
#   Validates that extracted name is a valid identifier (alphanumeric + underscore)
extract_location_name() {
	local var_name="$1"
	local location_name=""

	# Extract location name from LOCATION_<NAME>_EXTERNAL pattern
	if [[ "$var_name" =~ ^LOCATION_(.+)_EXTERNAL$ ]]; then
		location_name="${BASH_REMATCH[1]}"
	# Extract location name from LOCATION_<NAME>_INTERNAL pattern
	elif [[ "$var_name" =~ ^LOCATION_(.+)_INTERNAL$ ]]; then
		location_name="${BASH_REMATCH[1]}"
	else
		return 1
	fi

	# Validate location name is a valid identifier (alphanumeric + underscore)
	if ! [[ "$location_name" =~ ^[A-Za-z0-9_]+$ ]]; then
		return 1
	fi

	echo "$location_name"
	return 0
}

# Parse location-based configuration
#
# Scans all variables matching LOCATION_*_EXTERNAL pattern and extracts location data
# into a structured associative array format.
#
# Returns:
#   0: Configuration parsed successfully
#   1: Configuration error (no locations found, duplicate names, etc.)
#
# Output:
#   Sets global associative array LOCATIONS with structure:
#     LOCATIONS["<location_name>"]["external"] = external IP
#     LOCATIONS["<location_name>"]["internal"] = space-separated internal IPs (can be empty)
#
# Side effects:
#   - Sets global LOCATIONS associative array
#   - Logs errors for invalid configurations
#   - Exits script on critical errors
#
# Examples:
#   parse_location_config
#   # Sets LOCATIONS["NYC"]["external"]="203.0.113.1"
#   # Sets LOCATIONS["NYC"]["internal"]="192.168.1.1 192.168.1.88"
#
# Algorithm Overview:
#   This function implements a two-pass parsing algorithm to handle location-based configuration:
#   Pass 1: Collect all LOCATION_* variables (both EXTERNAL and INTERNAL)
#   Pass 2: Process EXTERNAL variables and match with corresponding INTERNAL variables
#
#   Two-pass design rationale:
#   - Allows matching EXTERNAL and INTERNAL variables by location name
#   - Handles cases where variables appear in any order in config file
#   - Enables efficient duplicate detection (both variable-level and location-level)
#   - Separates parsing (Pass 1) from validation and storage (Pass 2)
#
# Pass 1 Details (Collection Phase):
#   - Scans entire config file line by line
#   - Filters for variables matching pattern: LOCATION_*_(EXTERNAL|INTERNAL)
#   - Uses parse_assignment() for proper quote handling and value extraction
#   - Stores variables in associative array: location_vars["VAR_NAME"] = "value"
#   - Tracks seen variables to detect duplicate definitions
#   - Skips comments, empty lines, and invalid assignments gracefully
#
#   Edge cases handled in Pass 1:
#   - Duplicate variable definitions: Detected via seen_vars tracking, fails immediately
#   - Invalid variable format: Skipped (not a LOCATION_* variable)
#   - Parse errors: Skipped (allows config to have other variables)
#   - Comments and empty lines: Skipped (don't affect parsing)
#
# Pass 2 Details (Processing Phase):
#   - Iterates over collected EXTERNAL variables only
#   - Extracts location name from variable name (e.g., "LOCATION_NYC_EXTERNAL" → "NYC")
#   - Sanitizes location name (normalizes case, replaces spaces/underscores)
#   - Detects duplicate sanitized names (different variable names can map to same location)
#   - Validates external IP is non-empty (required field)
#   - Looks up corresponding INTERNAL variable by constructing variable name
#   - Stores location data in global LOCATIONS array
#
#   Edge cases handled in Pass 2:
#   - Invalid location name format: Logs warning, skips location
#   - Duplicate sanitized names: Fails (e.g., "NYC" and "nyc" would conflict)
#   - Empty external IP: Logs warning, skips location (graceful degradation)
#   - Missing INTERNAL variable: Uses empty string (INTERNAL is optional)
#   - No locations found: Fails (at least one location required)
#
# Variable Name Format:
#   Expected format: LOCATION_<NAME>_EXTERNAL and LOCATION_<NAME>_INTERNAL
#   Examples:
#     - LOCATION_NYC_EXTERNAL="203.0.113.1"
#     - LOCATION_NYC_INTERNAL="192.168.1.1 192.168.1.2"
#     - LOCATION_SF_OFFICE_EXTERNAL="198.51.100.1"
#
#   Location name extraction:
#     - Extracted from variable name using extract_location_name()
#     - Supports underscores, numbers, and mixed case
#     - Sanitized using sanitize_location_name() for consistency
#
# Data Storage Format:
#   LOCATIONS array uses format: "external:<ip>|internal:<ips>"
#   Example: LOCATIONS["NYC"]="external:203.0.113.1|internal:192.168.1.1 192.168.1.2"
#
#   Rationale for delimited format:
#   - Single associative array key (location name)
#   - Preserves both external and internal IPs
#   - Pipe separator avoids conflicts with IP addresses
#   - Easy to parse with regex when retrieving values
#
# Assumptions:
#   - Config file format is consistent (shell variable assignments)
#   - Location names are unique after sanitization
#   - External IP is required, internal IP is optional
#   - Variable names follow LOCATION_*_EXTERNAL/INTERNAL pattern
#   - parse_assignment() handles quote escaping correctly
#   - extract_location_name() and sanitize_location_name() are available
#
# Error Handling Strategy:
#   - Critical errors (duplicates, no locations): Fail immediately with error code
#   - Non-critical errors (empty external IP, invalid format): Log warning, skip location
#   - Allows partial success: Some locations may be invalid, others valid
#   - Final validation: Ensures at least one valid location exists
#
# Examples:
#   Config file:
#     LOCATION_NYC_EXTERNAL="203.0.113.1"
#     LOCATION_NYC_INTERNAL="192.168.1.1"
#     LOCATION_SF_EXTERNAL="198.51.100.1"
#
#   After parsing:
#     LOCATIONS["NYC"]="external:203.0.113.1|internal:192.168.1.1"
#     LOCATIONS["SF"]="external:198.51.100.1|internal:"
#
#   Edge case: Duplicate sanitized names
#     LOCATION_NYC_EXTERNAL="203.0.113.1"
#     LOCATION_nyc_EXTERNAL="198.51.100.1"  # Fails: "NYC" and "nyc" both sanitize to same name
#
# Note:
#   Requires extract_location_name() and sanitize_location_name() functions (from common.sh)
#   Validates location names are unique
#   Validates each location has external IP (required)
parse_location_config() {
	# Declare LOCATIONS array if it doesn't exist, otherwise clear it
	# This ensures it works both when called directly and when called via 'run' in tests
	if ! declare -p LOCATIONS &>/dev/null; then
		declare -gA LOCATIONS=()
	else
		LOCATIONS=()
	fi
	local var_name
	local location_name
	local sanitized_name
	local external_ip
	local internal_ip
	local -A seen_locations=()

	# Scan config file for LOCATION_*_EXTERNAL and LOCATION_*_INTERNAL variables
	# We read the config file directly to parse location configurations
	local config_file="${CONFIG_FILE:-}"

	# Check if config file exists and is a regular file (not a directory)
	if [[ -z "$config_file" ]] || [[ ! -f "$config_file" ]]; then
		# Check if it's a directory (which would cause a hang if we try to read from it)
		# When config file is a directory, load_config already handled it by logging warnings
		# and using defaults. Here we just return 0 (no locations found) and let validation
		# handle the "no locations" case.
		if [[ -d "$config_file" ]]; then
			# Config file is a directory - no locations to parse
			# load_config already logged warnings about this
			return 0
		fi
		handle_error_or_exit_fake_mode "Config file not found: ${config_file:-<not set>}" "${EXIT_VALIDATION_ERROR:-3}"
		return 1
	fi

	# PASS 1: Collection Phase - Gather all LOCATION_* variables
	# Purpose: Build a complete inventory of location-related variables before processing
	# This allows us to match EXTERNAL and INTERNAL variables regardless of order in config file
	#
	# Data structures:
	#   location_vars: Associative array mapping variable names to values
	#                  Example: location_vars["LOCATION_NYC_EXTERNAL"]="203.0.113.1"
	#   seen_vars: Tracks which variable names we've encountered (for duplicate detection)
	local -A location_vars=()
	local -A seen_vars=() # Track seen variable names to detect duplicates
	local line_num=0
	local -A parse_result

	# Read config file line by line
	# Note: Uses "|| [[ -n "$line" ]]" to handle files without trailing newline
	while IFS= read -r line || [[ -n "$line" ]]; do
		line_num=$((line_num + 1))
		parse_result=()

		# Skip comments and empty lines (don't affect parsing state)
		[[ "$line" =~ ^[[:space:]]*# ]] && continue
		[[ -z "${line// /}" ]] && continue

		# Normalize whitespace: remove leading/trailing spaces
		# This handles indented config files and trailing spaces
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"

		# Parse variable assignment using parse_assignment() for proper quote handling
		# This handles quoted values, escaped quotes, and complex value formats
		# Suppress errors (2>/dev/null) to allow graceful skipping of invalid lines
		# Note: We don't validate against schema here - that happens in Pass 2
		if ! parse_assignment "$line" "$line_num" "parse_result" 2>/dev/null; then
			continue # Skip lines that don't parse as valid assignments
		fi

		local var_name="${parse_result[name]}"

		# Filter: Only process LOCATION_* variables matching pattern
		# Pattern: LOCATION_<name>_(EXTERNAL|INTERNAL)
		# Examples: LOCATION_NYC_EXTERNAL, LOCATION_SF_OFFICE_INTERNAL
		if [[ "$var_name" =~ ^LOCATION_.+_(EXTERNAL|INTERNAL)$ ]]; then
			# Duplicate detection: Check if we've seen this exact variable name before
			# This catches cases like:
			#   LOCATION_NYC_EXTERNAL="203.0.113.1"
			#   LOCATION_NYC_EXTERNAL="198.51.100.1"  # Duplicate definition
			if [[ -n "${seen_vars[$var_name]:-}" ]]; then
				# Extract location name for better error message
				# If extraction fails, use variable name directly
				if location_name=$(extract_location_name "$var_name" 2>/dev/null); then
					local sanitized_name
					sanitized_name=$(sanitize_location_name "$location_name")
					handle_error_or_exit_fake_mode "Duplicate location name detected: $sanitized_name (from variable $var_name)" "${EXIT_VALIDATION_ERROR:-3}"
					return 1
				else
					handle_error_or_exit_fake_mode "Duplicate location name detected: $var_name" "${EXIT_VALIDATION_ERROR:-3}"
					return 1
				fi
			fi
			# Mark variable as seen and store its value
			seen_vars["$var_name"]=1
			location_vars["$var_name"]="${parse_result[value]}"
		fi
	done <"$config_file"

	# PASS 2: Processing Phase - Process EXTERNAL variables and match with INTERNAL
	# Purpose: Transform collected variables into structured location data
	# Only processes EXTERNAL variables (they define locations), INTERNAL variables are looked up
	#
	# Processing steps for each EXTERNAL variable:
	#   1. Extract location name from variable name
	#   2. Sanitize location name (normalize for consistency)
	#   3. Detect duplicate sanitized names (different vars → same location)
	#   4. Validate external IP is non-empty (required)
	#   5. Look up corresponding INTERNAL variable
	#   6. Store location data in global LOCATIONS array
	for var_name in "${!location_vars[@]}"; do
		# Filter: Only process EXTERNAL variables (they define locations)
		# INTERNAL variables are looked up later when processing their corresponding EXTERNAL
		if [[ ! "$var_name" =~ ^LOCATION_.+_EXTERNAL$ ]]; then
			continue
		fi

		# Step 1: Extract location name from variable name
		# Example: "LOCATION_NYC_EXTERNAL" → "NYC"
		# If extraction fails, variable format is invalid (skip with warning)
		if ! location_name=$(extract_location_name "$var_name"); then
			handle_error "WARNING" "Invalid location variable name format: $var_name (skipping)"
			continue
		fi

		# Step 2: Sanitize location name for consistency
		# This normalizes case, handles underscores/spaces, etc.
		# Example: "NYC", "nyc", "New_York_City" might all sanitize to same name
		sanitized_name=$(sanitize_location_name "$location_name")

		# Step 3: Check for duplicate sanitized location names
		# This catches cases where different variable names map to same location:
		#   LOCATION_NYC_EXTERNAL and LOCATION_nyc_EXTERNAL → both sanitize to "NYC"
		#   LOCATION_NEW_YORK_EXTERNAL and LOCATION_NewYork_EXTERNAL → might conflict
		if [[ -n "${seen_locations[$sanitized_name]:-}" ]]; then
			handle_error_or_exit_fake_mode "Duplicate location name detected: $sanitized_name (from variable $var_name)" "${EXIT_VALIDATION_ERROR:-3}"
			return 1
		fi
		seen_locations[$sanitized_name]=1 # Mark location as processed

		# Step 4: Get external IP value (already parsed and unquoted by parse_assignment)
		external_ip="${location_vars[$var_name]}"

		# Step 5: Validate external IP is non-empty (required field)
		# Empty external IP means no peer to monitor, so skip this location
		# This is a non-critical error: log warning but don't fail entire config
		if [[ -z "$external_ip" ]]; then
			handle_error "WARNING" "Location $sanitized_name: EXTERNAL IP is empty (skipping empty peer)"
			continue
		fi

		# Step 6: Look up corresponding INTERNAL IP variable
		# Construct variable name: LOCATION_<name>_INTERNAL
		# Use empty string if INTERNAL variable doesn't exist (it's optional)
		# Example: For LOCATION_NYC_EXTERNAL, look up LOCATION_NYC_INTERNAL
		local internal_var_name="LOCATION_${location_name}_INTERNAL"
		internal_ip="${location_vars[$internal_var_name]:-}" # Default to empty if not found

		# Step 7: Store location data in global LOCATIONS array
		# Format: "external:<ip>|internal:<ips>" (pipe separator avoids IP conflicts)
		# Example: "external:203.0.113.1|internal:192.168.1.1 192.168.1.2"
		LOCATIONS["$sanitized_name"]="external:$external_ip|internal:$internal_ip"
	done

	# Final validation: Ensure at least one valid location was found
	# This catches cases where:
	#   - No LOCATION_*_EXTERNAL variables exist in config
	#   - All locations were skipped due to validation errors (empty IPs, etc.)
	# This is a critical error: cannot proceed without at least one location to monitor
	if [[ ${#LOCATIONS[@]} -eq 0 ]]; then
		handle_error_or_exit_fake_mode "No location-based configuration found. At least one LOCATION_*_EXTERNAL variable is required." "${EXIT_VALIDATION_ERROR:-3}"
		return 1
	fi

	return 0
}

# Get external IP for a location
#
# Retrieves the external IP address for a given location name.
#
# Arguments:
#   $1: Location name (sanitized)
#
# Returns:
#   0: External IP found
#   1: Location not found
#
# Output:
#   Prints external IP to stdout
#
# Note:
#   Requires parse_location_config() to be called first
get_location_external_ip() {
	local location_name="$1"
	local location_data="${LOCATIONS[$location_name]:-}"

	if [[ -z "$location_data" ]]; then
		return 1
	fi

	# Extract external IP from location data format: "external:IP|internal:IPs"
	if [[ "$location_data" =~ external:([^|]+) ]]; then
		echo "${BASH_REMATCH[1]}"
		return 0
	fi

	return 1
}

# Get internal IPs for a location
#
# Retrieves the internal IP addresses (space-separated) for a given location name.
#
# Arguments:
#   $1: Location name (sanitized)
#
# Returns:
#   0: Internal IPs found (may be empty string)
#   1: Location not found
#
# Output:
#   Prints internal IPs (space-separated) to stdout, or empty string if not set
#
# Note:
#   Requires parse_location_config() to be called first
get_location_internal_ips() {
	local location_name="$1"
	local location_data="${LOCATIONS[$location_name]:-}"

	if [[ -z "$location_data" ]]; then
		return 1
	fi

	# Extract internal IPs from location data format: "external:IP|internal:IPs"
	if [[ "$location_data" =~ internal:(.+)$ ]]; then
		echo "${BASH_REMATCH[1]}"
		return 0
	fi

	# No internal IPs set - return empty string
	echo ""
	return 0
}

# Validate configuration
#
# Validates that required configuration variables are set and have valid values.
# Uses schema-based validation for type checking and rules, plus custom validation
# for complex cases (IP addresses, location-based configuration).
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
		handle_error_or_exit_fake_mode "Configuration validation failed - check schema rules" "${EXIT_VALIDATION_ERROR:-3}"
	fi

	# Check for old format variables (should not exist)
	if [[ -n "${EXTERNAL_PEER_IPS:-}" ]] || [[ -n "${INTERNAL_PEER_IPS:-}" ]]; then
		handle_error_or_exit_fake_mode "Old configuration format detected (EXTERNAL_PEER_IPS/INTERNAL_PEER_IPS). Please migrate to location-based format using the migration script." "${EXIT_VALIDATION_ERROR:-3}"
		return 1
	fi

	# Parse location-based configuration
	if ! parse_location_config; then
		handle_error_or_exit_fake_mode "Failed to parse location-based configuration" "${EXIT_VALIDATION_ERROR:-3}"
		return 1
	fi

	# Validate location-based configuration: IP address formats
	local location_name
	local external_ip
	local internal_ips
	local IFS=' '
	local -a internal_ips_array

	for location_name in "${!LOCATIONS[@]}"; do
		# Get external IP for this location
		if ! external_ip=$(get_location_external_ip "$location_name"); then
			handle_error_or_exit_fake_mode "Location $location_name: Failed to get external IP" "${EXIT_VALIDATION_ERROR:-3}"
			return 1
		fi

		# Validate external IP format
		if ! validate_ip_address "$external_ip"; then
			handle_error_or_exit_fake_mode "Location $location_name: Invalid external IP format: $external_ip" "${EXIT_VALIDATION_ERROR:-3}"
			return 1
		fi

		# Get internal IPs for this location (may be empty)
		internal_ips=$(get_location_internal_ips "$location_name")

		# Validate internal IPs if set
		if [[ -n "$internal_ips" ]]; then
			read -ra internal_ips_array <<<"$internal_ips"
			for internal_ip in "${internal_ips_array[@]}"; do
				# Skip empty IPs
				if [[ -z "$internal_ip" ]]; then
					continue
				fi

				# Validate IP address format
				if ! validate_ip_address "$internal_ip"; then
					handle_error_or_exit_fake_mode "Location $location_name: Invalid internal IP format: $internal_ip" "${EXIT_VALIDATION_ERROR:-3}"
					return 1
				fi
			done

			# Validate LOCAL_UDM_IP is configured when ping checks are enabled with internal IPs
			if [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
				if [[ -z "${LOCAL_UDM_IP:-}" ]]; then
					handle_error "WARNING" "LOCAL_UDM_IP is not configured but ENABLE_PING_CHECK=1 and location $location_name has internal IPs"
					handle_error "WARNING" "LOCAL_UDM_IP is required for ping checks with internal IPs. Ping checks may fail without it."
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
