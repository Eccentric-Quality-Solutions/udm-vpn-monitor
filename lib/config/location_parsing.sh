#!/bin/bash
#
# Location-based configuration parsing for UDM VPN Monitor
# Handles parsing and accessing location-based configuration variables
#
# Version: 0.8.1

# Validate required dependencies at module load time
# These functions must be available when this module is sourced
# Note: handle_error and handle_error_or_exit_fake_mode are expected to be available
# when functions are called (after logging.sh is sourced), not during module sourcing
if ! declare -f sanitize_location_name >/dev/null 2>&1; then
	echo "ERROR: location_parsing.sh requires sanitize_location_name from common.sh" >&2
	return 1 2>/dev/null || exit 1
fi
if ! declare -f parse_assignment >/dev/null 2>&1; then
	echo "ERROR: location_parsing.sh requires parse_assignment from config_loading.sh" >&2
	return 1 2>/dev/null || exit 1
fi

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

# Parse single location from EXTERNAL variable
#
# Processes one EXTERNAL variable and stores location data in global LOCATIONS array.
# Handles extraction, sanitization, validation, and storage of location configuration.
#
# Arguments:
#   $1: Variable name (e.g., "LOCATION_NYC_EXTERNAL")
#   $2: Associative array name containing location variables (e.g., "location_vars")
#   $3: Associative array name for tracking seen locations (e.g., "seen_locations")
#
# Returns:
#   0: Location parsed and stored successfully
#   1: Location skipped (non-critical: invalid format, empty external IP)
#   2: Critical error (duplicate sanitized name) - caller should exit
#
# Side effects:
#   - Adds entry to global LOCATIONS array on success
#   - Updates seen_locations array to track processed locations
#   - Logs warnings for non-critical errors
#   - Calls handle_error_or_exit_fake_mode for critical errors
#
# Examples:
#   parse_single_location "LOCATION_NYC_EXTERNAL" "location_vars" "seen_locations"
#   # Stores LOCATIONS["NYC"]="external:203.0.113.1|internal:192.168.1.1"
#
# Note:
#   Requires extract_location_name() and sanitize_location_name() functions
#   Requires location_vars array to be populated with variable values
parse_single_location() {
	local var_name="$1"
	local location_vars_ref="$2"
	local seen_locations_ref="$3"
	local location_name
	local sanitized_name
	local external_peer_ip
	local internal_peer_ip
	local internal_var_name

	# Step 1: Extract location name from variable name
	# Example: "LOCATION_NYC_EXTERNAL" → "NYC"
	# If extraction fails, variable format is invalid (skip with warning)
	if ! location_name=$(extract_location_name "$var_name"); then
		handle_error "WARNING" "SYSTEM" "Invalid location variable name format: $var_name (skipping)"
		return 1
	fi

	# Step 2: Sanitize location name for consistency
	# This normalizes case, handles underscores/spaces, etc.
	# Example: "NYC", "nyc", "New_York_City" might all sanitize to same name
	sanitized_name=$(sanitize_location_name "$location_name")

	# Step 3: Check for duplicate sanitized location names
	# This catches cases where different variable names map to same location:
	#   LOCATION_NYC_EXTERNAL and LOCATION_nyc_EXTERNAL → both sanitize to "NYC"
	#   LOCATION_NEW_YORK_EXTERNAL and LOCATION_NewYork_EXTERNAL → might conflict
	# Use nameref with different name to avoid circular reference
	# Store reference name in temp variable to avoid expansion issues with set -u
	local ref_name="$seen_locations_ref"
	local -n seen_locs_ref="$ref_name"
	if [[ -n "${seen_locs_ref[$sanitized_name]:-}" ]]; then
		handle_error_or_exit_fake_mode "SYSTEM" "Duplicate location name detected: $sanitized_name (from variable $var_name)" "${EXIT_VALIDATION_ERROR:-3}"
		return 2
	fi
	# shellcheck disable=SC2004 # $sanitized_name is a string variable, not arithmetic
	seen_locs_ref[$sanitized_name]=1 # Mark location as processed

	# Step 4: Get external IP value (already parsed and unquoted by parse_assignment)
	# Use nameref with different name to avoid circular reference
	# Store reference name in temp variable to avoid expansion issues with set -u
	local loc_vars_ref_name="$location_vars_ref"
	local -n loc_vars_ref="$loc_vars_ref_name"
	external_peer_ip="${loc_vars_ref[$var_name]}"

	# Step 5: Validate external IP is non-empty (required field)
	# Empty external IP means no peer to monitor, so skip this location
	# This is a non-critical error: log warning but don't fail entire config
	if [[ -z "$external_peer_ip" ]]; then
		handle_error "WARNING" "$sanitized_name" "EXTERNAL IP is empty (skipping empty peer)"
		return 1
	fi

	# Step 6: Look up corresponding INTERNAL IP variable
	# Construct variable name: LOCATION_<name>_INTERNAL
	# Use empty string if INTERNAL variable doesn't exist (it's optional)
	# Example: For LOCATION_NYC_EXTERNAL, look up LOCATION_NYC_INTERNAL
	internal_var_name="LOCATION_${location_name}_INTERNAL"
	internal_peer_ip="${loc_vars_ref[$internal_var_name]:-}" # Default to empty if not found

	# Step 7: Store location data in global LOCATIONS array
	# Format: "external:<ip>|internal:<ips>" (pipe separator avoids IP conflicts)
	# Example: "external:203.0.113.1|internal:192.168.1.1 192.168.1.2"
	LOCATIONS["$sanitized_name"]="external:$external_peer_ip|internal:$internal_peer_ip"

	return 0
}

# Validate location configuration
#
# Performs final validation that at least one valid location was found.
# This catches cases where no locations exist or all were skipped.
#
# Arguments:
#   None
#
# Returns:
#   0: At least one location found
#   1: No locations found (critical error)
#
# Side effects:
#   - Calls handle_error_or_exit_fake_mode if no locations found
#
# Examples:
#   validate_location_config
#   # Returns 0 if LOCATIONS array has entries, 1 otherwise
#
# Note:
#   Requires global LOCATIONS array to be populated
validate_location_config() {
	# Final validation: Ensure at least one valid location was found
	# This catches cases where:
	#   - No LOCATION_*_EXTERNAL variables exist in config
	#   - All locations were skipped due to validation errors (empty IPs, etc.)
	# This is a critical error: cannot proceed without at least one location to monitor
	if [[ ${#LOCATIONS[@]} -eq 0 ]]; then
		handle_error_or_exit_fake_mode "SYSTEM" "No location-based configuration found. At least one LOCATION_*_EXTERNAL variable is required." "${EXIT_VALIDATION_ERROR:-3}"
		return 1
	fi

	return 0
}

# Parse location-based configuration
#
# Scans all variables matching LOCATION_*_EXTERNAL pattern and extracts location data
# into a structured associative array format.
#
# Arguments:
#   None
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
#   - Calls parse_single_location() for each EXTERNAL variable
#   - Handles skip and critical error return codes appropriately
#
#   Edge cases handled in Pass 2:
#   - Invalid location name format: Logs warning, skips location (via parse_single_location)
#   - Duplicate sanitized names: Fails (via parse_single_location)
#   - Empty external IP: Logs warning, skips location (via parse_single_location)
#   - Missing INTERNAL variable: Uses empty string (via parse_single_location)
#   - No locations found: Fails (via validate_location_config)
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
#   Requires parse_assignment() function (from config_loading.sh)
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
	# shellcheck disable=SC2034 # Used via nameref in parse_single_location
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
		handle_error_or_exit_fake_mode "SYSTEM" "Config file not found: ${config_file:-<not set>}" "${EXIT_VALIDATION_ERROR:-3}"
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
					handle_error_or_exit_fake_mode "SYSTEM" "Duplicate location name detected: $sanitized_name (from variable $var_name)" "${EXIT_VALIDATION_ERROR:-3}"
					return 1
				else
					handle_error_or_exit_fake_mode "SYSTEM" "Duplicate location name detected: $var_name" "${EXIT_VALIDATION_ERROR:-3}"
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
	#   - Calls parse_single_location() to handle extraction, validation, and storage
	#   - Handles skip (non-critical) and critical error return codes
	for var_name in "${!location_vars[@]}"; do
		# Filter: Only process EXTERNAL variables (they define locations)
		# INTERNAL variables are looked up later when processing their corresponding EXTERNAL
		# Pattern restricts to valid identifier characters (A-Za-z0-9_) to match extract_location_name() validation
		if [[ ! "$var_name" =~ ^LOCATION_[A-Za-z0-9_]+_EXTERNAL$ ]]; then
			continue
		fi

		# Parse single location - handles all validation and storage
		# Handle return codes:
		#   0: Success (location parsed and stored) - continue processing
		#   1: Skip (non-critical: invalid format, empty external IP) - continue processing
		#   2: Critical error (duplicate sanitized name) - exit immediately
		parse_single_location "$var_name" "location_vars" "seen_locations"
		local parse_status=$?
		if [[ $parse_status -eq 2 ]]; then
			# Critical error - parse_single_location already called handle_error_or_exit_fake_mode
			return 1
		fi
		# parse_status 0 or 1: continue processing (success or skip)
	done

	# Final validation: Ensure at least one valid location was found
	validate_location_config || return 1

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

# Get external IP for a location (resolved from DNS if needed)
#
# Retrieves the external IP address for a given location name, resolving DNS names to IP addresses.
# If the stored value is already an IP address, returns it unchanged.
# If the stored value is a DNS name, resolves it to an IP address.
#
# Arguments:
#   $1: Location name (sanitized)
#
# Returns:
#   0: External IP found and resolved
#   1: Location not found or DNS resolution failed
#
# Output:
#   Prints resolved IP address to stdout
#
# Side effects:
#   - May perform DNS resolution (cached for performance)
#   - Logs warnings on DNS resolution failures
#
# Note:
#   Requires parse_location_config() to be called first
#   Requires resolve_dns() function from network_validation.sh (available when detection.sh is sourced)
get_location_external_ip_resolved() {
	local location_name="$1"
	local external_value
	local resolved_ip

	# Get original value (IP or DNS name)
	if ! external_value=$(get_location_external_ip "$location_name"); then
		return 1
	fi

	# Resolve DNS name to IP if needed
	if ! resolved_ip=$(resolve_dns "$external_value" 2>/dev/null); then
		handle_error "WARNING" "$location_name" "Failed to resolve external DNS name: $external_value"
		return 1
	fi

	echo "$resolved_ip"
	return 0
}

# Get internal IPs for a location (resolved from DNS if needed)
#
# Retrieves the internal IP addresses (space-separated) for a given location name, resolving DNS names to IP addresses.
# If stored values are already IP addresses, returns them unchanged.
# If stored values are DNS names, resolves them to IP addresses.
#
# Arguments:
#   $1: Location name (sanitized)
#
# Returns:
#   0: Internal IPs found and resolved (may be empty string)
#   1: Location not found or DNS resolution failed
#
# Output:
#   Prints resolved IP addresses (space-separated) to stdout, or empty string if not set
#
# Side effects:
#   - May perform DNS resolution (cached for performance)
#   - Logs warnings on DNS resolution failures
#
# Note:
#   Requires parse_location_config() to be called first
#   Requires resolve_dns() function from network_validation.sh (available when detection.sh is sourced)
get_location_internal_ips_resolved() {
	local location_name="$1"
	local internal_values
	local IFS=' '
	local -a values_array
	local -a resolved_ips_array
	local resolved_ip

	# Get original values (IPs or DNS names)
	if ! internal_values=$(get_location_internal_ips "$location_name"); then
		return 1
	fi

	# If empty, return empty string
	if [[ -z "$internal_values" ]]; then
		echo ""
		return 0
	fi

	# Split into array and resolve each value
	read -ra values_array <<<"$internal_values"
	resolved_ips_array=()

	for value in "${values_array[@]}"; do
		# Skip empty values
		if [[ -z "$value" ]]; then
			continue
		fi

		# Resolve DNS name to IP if needed
		if ! resolved_ip=$(resolve_dns "$value" 2>/dev/null); then
			handle_error "WARNING" "$location_name" "Failed to resolve internal DNS name: $value"
			return 1
		fi

		resolved_ips_array+=("$resolved_ip")
	done

	# Join resolved IPs with spaces
	echo "${resolved_ips_array[*]}"
	return 0
}
