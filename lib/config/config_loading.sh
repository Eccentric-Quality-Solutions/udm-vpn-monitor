#!/bin/bash
#
# Configuration file loading and parsing for UDM VPN Monitor
# Handles loading configuration files and safely parsing variable assignments
#
# Version: 0.6.0

# Source configuration schema
# shellcheck source=lib/config_schema.sh
# Pre-declare CONFIG_SCHEMA as empty array to avoid unbound variable errors with set -u
# The schema file will populate it when sourced
# Use -gA to ensure it's global (important when config.sh is sourced from within functions)
declare -gA CONFIG_SCHEMA=()

# Source centralized fallback functions
# shellcheck source=lib/fallbacks.sh
# Determine lib directory (parent directory of config/)
# If LIB_DIR is not set, determine it from this file's location (go up one level from config/ to lib/)
if [[ -z "${LIB_DIR:-}" ]]; then
	# LIB_DIR not set, try to determine from BASH_SOURCE[0] using readlink if available
	# This handles cases where the file was sourced with a relative path
	source_file="${BASH_SOURCE[0]}"
	# Use check_command_available() for consistent command checking (from common.sh)
	# Fall back to command -v if check_command_available() not available (e.g., if sourced directly)
	# readlink is optional - if not available, we'll use other methods below
	if (declare -f check_command_available >/dev/null 2>&1 && check_command_available "readlink" || command -v readlink >/dev/null 2>&1) && [[ -L "$source_file" ]] || [[ -f "$source_file" ]]; then
		# Try to resolve to absolute path
		if source_file=$(readlink -f "$source_file" 2>/dev/null) || [[ "$source_file" =~ ^/ ]]; then
			# This file is in lib/config/, so go up one level to get lib/
			LIB_DIR="$(cd "$(dirname "$source_file")/.." && pwd)" 2>/dev/null || LIB_DIR=""
		fi
	fi
	# If still empty, try relative to current directory as last resort
	if [[ -z "${LIB_DIR:-}" ]] && [[ "${BASH_SOURCE[0]}" =~ \.\.?/ ]]; then
		# This file is in lib/config/, so go up one level to get lib/
		LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" 2>/dev/null || LIB_DIR=""
	fi
fi
# Source fallbacks.sh to get define_schema_fallbacks function
# Try to source fallbacks.sh, but don't fail if it doesn't exist (fallback functions are optional)
if [[ -n "${LIB_DIR:-}" ]] && [[ -f "${LIB_DIR}/fallbacks.sh" ]] && [[ -r "${LIB_DIR}/fallbacks.sh" ]]; then
	source "${LIB_DIR}/fallbacks.sh" 2>/dev/null || true
fi

# Try to source the schema file directly
# Note: We source directly instead of using safe_source_lib because the array declaration
# in the schema file needs to populate the pre-declared array, and safe_source_lib
# doesn't work correctly for this use case.
if [[ -n "${LIB_DIR:-}" ]] && [[ -f "${LIB_DIR}/config_schema.sh" ]] && [[ -r "${LIB_DIR}/config_schema.sh" ]]; then
	# Source the schema file, suppressing stderr to avoid cluttering output
	# The array is already declared above, so the schema file will populate it
	if ! source "${LIB_DIR}/config_schema.sh" 2>/dev/null; then
		# Source failed, array remains empty, use fallback functions
		# Check if function exists before calling (fallbacks.sh may have failed to source)
		if declare -f define_schema_fallbacks >/dev/null 2>&1; then
			define_schema_fallbacks
		fi
	fi
else
	# File doesn't exist or isn't readable, array is already empty, use fallback functions
	# Check if function exists before calling (fallbacks.sh may have failed to source)
	if declare -f define_schema_fallbacks >/dev/null 2>&1; then
		define_schema_fallbacks
	fi
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
		handle_error_or_exit_fake_mode "SYSTEM" "Cannot create ${description} directory: $dir" || return 1
	fi

	# Verify directory was actually created (defensive check)
	# This handles edge cases where mkdir -p might appear to succeed but directory doesn't exist
	if [[ ! -d "$dir" ]]; then
		# In fake mode: returns 1, in normal mode: exits via die()
		handle_error_or_exit_fake_mode "SYSTEM" "Directory was not created: $dir" || return 1
	fi

	return 0
}

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

	handle_error_or_exit_fake_mode "SYSTEM" "$full_message"
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
			log_message "ERROR" "SYSTEM" "Invalid configuration line: $line (value must be quoted if it contains spaces, quotes, or comment markers) (line $line_num)"
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
						log_message "ERROR" "SYSTEM" "Invalid configuration line: $line (unexpected content after closing quote) (line $line_num)"
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
						log_message "ERROR" "SYSTEM" "Invalid configuration line: $line (unexpected content after closing quote) (line $line_num)"
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
		log_message "ERROR" "SYSTEM" "Unclosed ${quote_char} quote in configuration line: $line (line $line_num)"
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
		log_message "ERROR" "SYSTEM" "Invalid configuration line: $line (expected VAR=value or VAR=\"value\") (line $line_num)"
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
#   1: Configuration file contains invalid or dangerous content
#
# Behavior:
#   - Normal mode: Fails fast - exits script immediately on first error via handle_config_error()
#     This ensures invalid configuration is caught early and prevents partial configuration state.
#   - Fake mode (testing): Partial loading - continues processing all lines, collects errors,
#     and returns 1 at the end if any errors occurred. This allows tests to validate multiple
#     error conditions in a single config file.
#   - Valid lines are processed and variables are set even if other lines have errors (in fake mode)
#
# Side effects:
#   - Sets global configuration variables via safe indirect assignment (declare -g + printf -v)
#   - Calls die() if invalid content is detected in normal mode (exits script)
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

# Validate critical configuration variables after parsing
#
# Validates that all required configuration variables are declared after parsing completes.
# This ensures that even if parsing partially failed, we catch missing critical variables
# before proceeding with incomplete configuration.
#
# Arguments:
#   None
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
		handle_error "ERROR" "SYSTEM" "Missing required configuration variables: ${missing_required[*]}"
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
	if ! handle_error_or_exit_fake_mode "SYSTEM" "$message" "$exit_code"; then
		# In fake mode, handle_error_or_exit_fake_mode returns 1
		# Exit gracefully with code 0 in fake mode since load_config is called at top level
		exit "${EXIT_SUCCESS:-0}"
	fi
	# In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
	# This line is unreachable but included for clarity
}

# Load configuration from file
#
# Loads and validates configuration from the specified configuration file.
# Applies schema defaults before parsing, validates critical variables after parsing,
# and ensures required directories exist. Preserves LOG_FILE if set before calling
# (for custom log files like keepalive).
#
# Arguments:
#   $1: Path to configuration file
#
# Returns:
#   0: Success (configuration loaded and validated)
#   1: Error in fake mode (directory creation failed)
#   Exits script with error code in normal mode on fatal errors
#
# Side effects:
#   - Sets global configuration variables from config file
#   - Applies schema defaults for unset variables
#   - Creates LOGS_DIR and STATE_DIR directories if needed
#   - Updates LOCKFILE, COOLDOWN_UNTIL_FILE, PIDFILE paths based on STATE_DIR
#   - Logs configuration loading status
load_config() {
	local config_file="$1"

	# Save LOG_FILE before any processing to preserve it if explicitly set by caller
	# This allows scripts like vpn-keepalive.sh to set their own log file before calling load_config()
	local log_file_before_load="${LOG_FILE:-}"
	# Compute basename once for reuse (DRY)
	local log_file_basename
	log_file_basename=$(basename "$log_file_before_load" 2>/dev/null || echo "")

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
		handle_error "WARNING" "SYSTEM" "Configuration path is a directory, not a file: $config_file"
		handle_error "WARNING" "SYSTEM" "Using default configuration values"
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

		# Preserve LOG_FILE if it was set before load_config() AND it's not the default monitor log
		# This ensures log_message() uses the correct log file for custom log files (e.g., keepalive)
		# but allows config file to override the default monitor log
		if [[ -n "$log_file_before_load" ]] && [[ "$log_file_basename" != "vpn-monitor.log" ]]; then
			LOG_FILE="$log_file_before_load"
		fi

		log_message "INFO" "SYSTEM" "Configuration loaded from: $config_file"
	else
		# File doesn't exist or isn't readable
		# Check if file exists but isn't readable (for better error message)
		if [[ -f "$config_file" ]]; then
			handle_fatal_config_error "Configuration file is not readable: $config_file" "${EXIT_CONFIG_ERROR:-2}"
		fi

		handle_error "WARNING" "SYSTEM" "Configuration file not found: $config_file"
		handle_error "WARNING" "SYSTEM" "Using default configuration values"
	fi

	# Compute log paths after config loading (consolidated path computation)
	# Priority:
	#   1. If LOG_FILE was explicitly set before load_config() was called, preserve it (unless config file overrides it)
	#   2. If LOG_FILE was explicitly set in config file, use that value
	#   3. If LOGS_DIR was explicitly set in config (changed after parsing), use that value
	#   4. Otherwise, ensure LOG_FILE matches LOGS_DIR (LOGS_DIR is already set correctly from config)
	local log_filename
	log_filename=$(basename "$LOG_FILE" 2>/dev/null || echo "vpn-monitor.log")
	local log_file_dir
	log_file_dir=$(dirname "$LOG_FILE" 2>/dev/null)

	# If LOGS_DIR wasn't explicitly set in config but LOG_FILE was overridden, derive LOGS_DIR from LOG_FILE
	if [[ "$logs_dir_before_parse" == "${LOGS_DIR:-}" ]] && [[ -n "$log_file_dir" ]] && [[ "$log_file_dir" != "${LOGS_DIR:-}" ]]; then
		LOGS_DIR="$log_file_dir"
	fi

	# Preserve LOG_FILE if it was explicitly set before load_config() AND it's not the default monitor log
	# This allows scripts like vpn-keepalive.sh to set their own log file (e.g., vpn-keepalive.log)
	# while still allowing config file to override the default monitor log (vpn-monitor.log)
	if [[ -n "$log_file_before_load" ]] && [[ "$log_file_basename" != "vpn-monitor.log" ]]; then
		# LOG_FILE was explicitly set before load_config() and it's a custom log file - preserve it
		# But update its directory if LOGS_DIR changed (preserving filename)
		if [[ "$logs_dir_before_parse" != "${LOGS_DIR:-}" ]]; then
			# LOGS_DIR changed, update LOG_FILE to use new directory but keep filename
			local preserved_log_filename
			preserved_log_filename=$(basename "$log_file_before_load" 2>/dev/null || echo "vpn-monitor.log")
			LOG_FILE="${LOGS_DIR}/${preserved_log_filename}"
		else
			# LOGS_DIR didn't change, preserve original LOG_FILE exactly
			LOG_FILE="$log_file_before_load"
		fi
	else
		# LOG_FILE wasn't set before load_config(), or it was the default monitor log - use computed value
		# This respects LOG_FILE from config file or uses default based on LOGS_DIR
		LOG_FILE="${LOGS_DIR}/${log_filename}"
	fi

	# Compute state paths after config loading (consolidated path computation)
	# Update paths that depend on STATE_DIR (STATE_DIR is already set correctly from config)
	# Always update these paths to ensure they match STATE_DIR after config loading
	LOCKFILE="${STATE_DIR}/vpn-monitor.lock"
	COOLDOWN_UNTIL_FILE="${STATE_DIR}/cooldown_until"
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
		if is_fake_mode && [[ -n "$log_file_before_load" ]] && [[ "$log_file_before_load" != "${LOGS_DIR}/${log_filename}" ]]; then
			local original_log_file_dir
			original_log_file_dir=$(dirname "$log_file_before_load" 2>/dev/null)
			if [[ -n "$original_log_file_dir" ]] && mkdir -p "$original_log_file_dir" 2>/dev/null && [[ -w "$original_log_file_dir" ]]; then
				# Fallback to original log file location
				LOGS_DIR="$original_log_file_dir"
				LOG_FILE="$log_file_before_load"
				handle_error "WARNING" "SYSTEM" "Failed to create logs directory: $original_logs_dir, using original log file location: $LOG_FILE"
			else
				# Can't fallback - log_message will write to stderr
				handle_error "WARNING" "SYSTEM" "Failed to create logs directory: $original_logs_dir (continuing in fake mode, logs will go to stderr)"
			fi
		fi
	fi

	# Ensure state directory exists after config loading (in case STATE_DIR was overridden)
	if ! ensure_directory_exists "$STATE_DIR" "state"; then
		# Directory creation failed - in fake mode this returns 1, in normal mode it exits
		# If we get here in fake mode, log warning but continue
		if is_fake_mode; then
			handle_error "WARNING" "SYSTEM" "Failed to create state directory: $STATE_DIR (continuing in fake mode)"
		fi
	fi
}
