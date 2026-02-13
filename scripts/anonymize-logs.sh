#!/bin/bash
#
# UDM VPN Monitor Log Anonymization Script
# Anonymizes location names, IP addresses (IPv4/IPv6), MAC addresses, and hostnames
# in vpn-monitor.log files while maintaining consistency so logs remain understandable
#
# Version: 0.1.0
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source anonymization library
# shellcheck source=../lib/anonymize.sh
source "${PROJECT_ROOT}/lib/anonymize.sh" 2>/dev/null || {
	echo "Error: Could not source lib/anonymize.sh" >&2
	exit 1
}

# Source common utilities (for escape_sed_regex/escape_sed_replacement)
# shellcheck source=../lib/common.sh
source "${PROJECT_ROOT}/lib/common.sh" 2>/dev/null || {
	echo "Error: Could not source lib/common.sh" >&2
	exit 1
}

# Default values
INPUT_FILE=""
OUTPUT_FILE=""
MAPPING_FILE=""
VERBOSE=0

# Print usage information
#
# Displays help text for the script.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
show_usage() {
	cat <<EOF
Usage: $0 [OPTIONS]

UDM VPN Monitor Log Anonymization Tool v0.1.0
Anonymizes location names and IP addresses in vpn-monitor.log files
while maintaining consistency so logs remain understandable.

Options:
  -i, --input FILE      Input log file (required)
  -o, --output FILE     Output file for anonymized log (default: stdout)
  -m, --mapping-file FILE  Mapping file for unified anonymization (optional)
                          If provided, loads existing mappings and saves updated mappings
  -v, --verbose         Verbose output
  -h, --help            Show this help message

Examples:
  $0 -i /data/vpn-monitor/logs/vpn-monitor.log -o anonymized.log
  $0 -i vpn-monitor.log | less
  $0 -i vpn-monitor.log -o anonymized.log -v

EOF
}

# Parse command line arguments
#
# Processes command line arguments and sets global variables.
#
# Arguments:
#   $@: Command line arguments
#
# Returns:
#   0: Success
#   1: Error (exits script)
parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-i | --input)
			INPUT_FILE="$2"
			shift 2
			;;
		-o | --output)
			OUTPUT_FILE="$2"
			shift 2
			;;
		-m | --mapping-file)
			MAPPING_FILE="$2"
			shift 2
			;;
		-v | --verbose)
			VERBOSE=1
			shift
			;;
		-h | --help)
			show_usage
			exit 0
			;;
		*)
			echo "ERROR: Unknown option: $1" >&2
			show_usage
			exit 1
			;;
		esac
	done

	# Validate required arguments
	if [[ -z "$INPUT_FILE" ]]; then
		echo "ERROR: Input file is required" >&2
		show_usage
		exit 1
	fi

	if [[ ! -f "$INPUT_FILE" ]]; then
		echo "ERROR: Input file not found: $INPUT_FILE" >&2
		exit 1
	fi

	if [[ ! -r "$INPUT_FILE" ]]; then
		echo "ERROR: Input file not readable: $INPUT_FILE" >&2
		exit 1
	fi
}

# Note: hash_string, anonymize_ipv4, anonymize_ipv6, anonymize_location are now provided by lib/anonymize.sh
# Note: extract_ips_from_log and extract_locations_from_log are provided by lib/anonymize.sh

# Generate anonymized output filename based on input filename
#
# Extracts location name from input filename (if present) and replaces it with
# anonymized location name in the output filename.
# Pattern: vpn-monitor-<location>.log -> vpn-monitor-<anonymized_location>-anonymized.log
#
# Arguments:
#   $1: Input file path
#   $2: Output file path (may be empty or contain original location)
#   $3: Input log file (for extracting locations if needed)
#
# Returns:
#   0: Success
#
# Output:
#   Prints anonymized output filename to stdout
generate_anonymized_output_filename() {
	local input_file="$1"
	local output_file="${2:-}"
	local log_file="$3"

	# Extract basename from input file
	local input_basename
	input_basename=$(basename "$input_file")

	# Check if input filename matches pattern: vpn-monitor-<location>.log
	# Accept both uppercase and lowercase location names
	local location=""
	if [[ "$input_basename" =~ ^vpn-monitor-([A-Za-z][A-Za-z0-9_]+)\.log$ ]]; then
		location="${BASH_REMATCH[1]}"
		# Convert to uppercase for consistency (location names in logs are uppercase)
		location=$(echo "$location" | tr '[:lower:]' '[:upper:]')
	fi

	# If no location found in filename, use output file as-is (or generate default)
	if [[ -z "$location" ]]; then
		if [[ -n "$output_file" ]]; then
			echo "$output_file"
		else
			# Default: replace .log with -anonymized.log
			echo "${input_basename%.log}-anonymized.log"
		fi
		return 0
	fi

	# Get anonymized location name
	# First check if mapping already exists
	local anonymized_location=""
	if [[ -n "${ANON_LOCATION_MAP[$location]:-}" ]]; then
		anonymized_location="${ANON_LOCATION_MAP[$location]}"
	else
		# Location not yet mapped - extract from log file to create mapping
		# This ensures we have the anonymized location before generating filename
		[[ $VERBOSE -eq 1 ]] && echo "Extracting location '$location' from log to create mapping..." >&2
		get_or_create_location_mapping "$location" >/dev/null
		anonymized_location="${ANON_LOCATION_MAP[$location]}"
	fi

	# Generate output filename
	if [[ -n "$output_file" ]]; then
		# Replace location in output filename if it contains the original location
		# Pattern: vpn-monitor-<location>-anonymized.log or vpn-monitor-<location>.log
		local output_basename
		output_basename=$(basename "$output_file")
		local output_dir
		output_dir=$(dirname "$output_file")

		# Replace original location with anonymized location in filename
		# Check if output filename contains the original location name (case-insensitive)
		# Convert to lowercase for comparison since filenames may be lowercase
		local location_lower
		location_lower=$(echo "$location" | tr '[:upper:]' '[:lower:]')
		local output_basename_lower
		output_basename_lower=$(echo "$output_basename" | tr '[:upper:]' '[:lower:]')

		# Pattern: vpn-monitor-<location>(-anonymized)?.log
		# First extract location from output filename to get the actual case
		local pattern="^vpn-monitor-([^-.]+)(-anonymized)?\\.log\$"
		if [[ "$output_basename" =~ $pattern ]]; then
			local location_in_filename="${BASH_REMATCH[1]}"
			local location_in_filename_lower
			location_in_filename_lower=$(echo "$location_in_filename" | tr '[:upper:]' '[:lower:]')

			# Check if the location in filename matches our location (case-insensitive)
			if [[ "$location_in_filename_lower" == "$location_lower" ]]; then
				# Replace the location in filename with anonymized location
				output_basename="${output_basename//${location_in_filename}/${anonymized_location}}"
			fi
		elif [[ "$output_basename" == "vpn-monitor-anonymized.log" ]] || [[ "$output_basename" == "anonymized.log" ]]; then
			# Default anonymized filename - replace with location-specific name
			output_basename="vpn-monitor-${anonymized_location}-anonymized.log"
		fi

		# Reconstruct full path
		if [[ "$output_dir" != "." ]]; then
			echo "${output_dir}/${output_basename}"
		else
			echo "$output_basename"
		fi
	else
		# No output file specified - generate based on input
		echo "vpn-monitor-${anonymized_location}-anonymized.log"
	fi
}

# Anonymize log file
#
# Reads input log file, replaces all IP addresses (IPv4/IPv6), MAC addresses,
# hostnames, and location names with anonymized versions, and writes to output.
#
# Arguments:
#   $1: Input log file path
#   $2: Output file path (or empty for stdout)
#
# Returns:
#   0: Success
#   1: Error
anonymize_log_file() {
	local input_file="$1"
	local output_file="${2:-}"

	[[ $VERBOSE -eq 1 ]] && echo "Extracting IPv4 addresses..." >&2
	local ipv4_count=0
	while IFS= read -r ip || [[ -n "$ip" ]]; do
		[[ -z "$ip" ]] && continue
		# Use unified mapping function (call without command substitution to avoid subshell)
		get_or_create_ipv4_mapping "$ip" >/dev/null
		ipv4_count=$((ipv4_count + 1))
		[[ $VERBOSE -eq 1 ]] && echo "  Mapping $ip -> ${ANON_IPV4_MAP[$ip]}" >&2
	done < <(extract_ips_from_log "$input_file")

	[[ $VERBOSE -eq 1 ]] && echo "Extracted $ipv4_count unique IPv4 addresses" >&2

	[[ $VERBOSE -eq 1 ]] && echo "Extracting IPv6 addresses..." >&2
	local ipv6_count=0
	while IFS= read -r ip || [[ -n "$ip" ]]; do
		[[ -z "$ip" ]] && continue
		# Use unified mapping function (call without command substitution to avoid subshell)
		get_or_create_ipv6_mapping "$ip" >/dev/null
		ipv6_count=$((ipv6_count + 1))
		[[ $VERBOSE -eq 1 ]] && echo "  Mapping $ip -> ${ANON_IPV6_MAP[$ip]}" >&2
	done < <(extract_ipv6_from_file "$input_file")

	[[ $VERBOSE -eq 1 ]] && echo "Extracted $ipv6_count unique IPv6 addresses" >&2

	[[ $VERBOSE -eq 1 ]] && echo "Extracting MAC addresses..." >&2
	local mac_count=0
	while IFS= read -r mac || [[ -n "$mac" ]]; do
		[[ -z "$mac" ]] && continue
		# Use unified mapping function (call without command substitution to avoid subshell)
		get_or_create_mac_mapping "$mac" >/dev/null
		mac_count=$((mac_count + 1))
		[[ $VERBOSE -eq 1 ]] && echo "  Mapping $mac -> ${ANON_MAC_MAP[$mac]}" >&2
	done < <(extract_mac_addresses_from_file "$input_file")

	[[ $VERBOSE -eq 1 ]] && echo "Extracted $mac_count unique MAC addresses" >&2

	[[ $VERBOSE -eq 1 ]] && echo "Extracting hostnames..." >&2
	local hostname_count=0
	while IFS= read -r hostname || [[ -n "$hostname" ]]; do
		[[ -z "$hostname" ]] && continue
		# Use unified mapping function (call without command substitution to avoid subshell)
		get_or_create_hostname_mapping "$hostname" >/dev/null
		hostname_count=$((hostname_count + 1))
		[[ $VERBOSE -eq 1 ]] && echo "  Mapping $hostname -> ${ANON_HOSTNAME_MAP[$hostname]}" >&2
	done < <(extract_hostnames_from_file "$input_file")

	[[ $VERBOSE -eq 1 ]] && echo "Extracted $hostname_count unique hostnames" >&2

	[[ $VERBOSE -eq 1 ]] && echo "Extracting location names..." >&2
	local location_count=0
	while IFS= read -r location || [[ -n "$location" ]]; do
		[[ -z "$location" ]] && continue
		# Use unified mapping function (call without command substitution to avoid subshell)
		get_or_create_location_mapping "$location" >/dev/null
		location_count=$((location_count + 1))
		[[ $VERBOSE -eq 1 ]] && echo "  Mapping $location -> ${ANON_LOCATION_MAP[$location]}" >&2
	done < <(extract_locations_from_log "$input_file")

	[[ $VERBOSE -eq 1 ]] && echo "Extracted $location_count unique location names" >&2

	# Build sed scripts for replacements (separate scripts for each type)
	[[ $VERBOSE -eq 1 ]] && echo "Building replacement scripts..." >&2
	local location_sed_script
	local ipv4_sed_script
	local ipv6_sed_script
	local mac_sed_script
	local hostname_sed_script
	location_sed_script=$(mktemp)
	ipv4_sed_script=$(mktemp)
	ipv6_sed_script=$(mktemp)
	mac_sed_script=$(mktemp)
	hostname_sed_script=$(mktemp)

	# Cleanup temporary files
	#
	# Removes temporary sed script files created during anonymization.
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds
	cleanup_temp_files() {
		rm -f "${location_sed_script:-}" "${ipv4_sed_script:-}" "${ipv6_sed_script:-}" "${mac_sed_script:-}" "${hostname_sed_script:-}"
	}
	trap cleanup_temp_files EXIT

	# Build location replacements script
	# Process locations in reverse order of length to avoid partial replacements
	set +u
	if [[ ${#ANON_LOCATION_MAP[@]} -gt 0 ]]; then
		local sorted_locations
		readarray -t sorted_locations < <(printf '%s\n' "${!ANON_LOCATION_MAP[@]}" | awk '{print length($0), $0}' | sort -rn | cut -d' ' -f2-)
		for location in "${sorted_locations[@]}"; do
			[[ -z "$location" ]] && continue
			local anonymized_location="${ANON_LOCATION_MAP[$location]}"
			# Escape special regex characters in location name
			local escaped_location
			escaped_location=$(escape_sed_regex "$location")

			# Escape special characters in anonymized location (for sed replacement)
			local escaped_anon_location
			escaped_anon_location=$(escape_sed_replacement "$anonymized_location" "@")

			# Replace "location LOCATION_NAME" patterns (lowercase)
			# Escape literal parentheses in patterns for extended regex
			# Group printf commands with same redirect to satisfy shellcheck SC2129
			# Use | as delimiter to avoid issues with / in location names
			{
				printf 's|location %s |location %s |g\n' "$escaped_location" "$escaped_anon_location"
				printf 's|location %s\\(|location %s(|g\n' "$escaped_location" "$escaped_anon_location"
				printf 's|for location %s |for location %s |g\n' "$escaped_location" "$escaped_anon_location"
				printf 's|for location %s\\(|for location %s(|g\n' "$escaped_location" "$escaped_anon_location"
				# Replace "Location LOCATION_NAME" patterns (capital L)
				printf 's|Location %s |Location %s |g\n' "$escaped_location" "$escaped_anon_location"
				printf 's|Location %s -|Location %s -|g\n' "$escaped_location" "$escaped_anon_location"
				# Replace location names at start of log entries: [timestamp] [LEVEL] LOCATION:
				# Pattern: ] LOCATION: (after log level)
				printf 's|\\] %s:|] %s:|g\n' "$escaped_location" "$escaped_anon_location"
				# Replace location names in comma-separated lists and standalone
				# Use pattern that matches word boundaries: non-word char or start/end of line before/after
				# This catches remaining instances (must be last to avoid conflicts with above patterns)
				printf 's@(^|[^A-Z0-9_])%s([^A-Z0-9_]|$)@\\1%s\\2@g\n' "$escaped_location" "$escaped_anon_location"
			} >>"$location_sed_script"
		done
	fi
	set -u

	# Build IPv4 replacements script
	# Process IPs in reverse order of length to avoid partial replacements
	set +u
	if [[ ${#ANON_IPV4_MAP[@]} -gt 0 ]]; then
		local sorted_ips
		readarray -t sorted_ips < <(printf '%s\n' "${!ANON_IPV4_MAP[@]}" | awk '{print length($0), $0}' | sort -rn | cut -d' ' -f2-)
		for ip in "${sorted_ips[@]}"; do
			[[ -z "$ip" ]] && continue
			local anonymized_ip="${ANON_IPV4_MAP[$ip]}"
			# Escape special regex characters in IP for sed pattern
			local escaped_ip
			escaped_ip=$(escape_sed_regex "$ip")
			# Escape special characters in anonymized IP (for sed replacement)
			local escaped_anon_ip
			escaped_anon_ip=$(escape_sed_replacement "$anonymized_ip" "@")
			# Pattern: start of word or non-word char, then IP, then end of word or non-word char
			# Use @ as delimiter to avoid issues with / and | in patterns
			printf 's@(^|[^0-9.])%s([^0-9.]|$)@\\1%s\\2@g\n' "$escaped_ip" "$escaped_anon_ip" >>"$ipv4_sed_script"
		done
	fi
	set -u

	# Build IPv6 replacements script
	set +u
	if [[ ${#ANON_IPV6_MAP[@]} -gt 0 ]]; then
		local sorted_ips
		readarray -t sorted_ips < <(printf '%s\n' "${!ANON_IPV6_MAP[@]}" | awk '{print length($0), $0}' | sort -rn | cut -d' ' -f2-)
		for ip in "${sorted_ips[@]}"; do
			[[ -z "$ip" ]] && continue
			local anonymized_ip="${ANON_IPV6_MAP[$ip]}"
			# Escape special regex characters in IPv6 for sed pattern
			# Note: escape_sed_regex handles all regex metacharacters; colon (:) is not a regex metacharacter
			# but we escape it manually for IPv6 addresses to be safe with sed patterns
			local escaped_ip
			escaped_ip=$(escape_sed_regex "$ip")
			# Manually escape colon for IPv6 (not a regex metacharacter, but defensive programming)
			escaped_ip="${escaped_ip//:/\\:}"
			# Escape special characters in anonymized IP (for sed replacement)
			local escaped_anon_ip
			escaped_anon_ip=$(escape_sed_replacement "$anonymized_ip" "@")
			# Pattern: word boundary or non-word char, then IP, then word boundary or non-word char
			# Use @ as delimiter to avoid issues with / and | in patterns
			printf 's@(^|[^0-9a-fA-F:./])%s([^0-9a-fA-F:./]|$)@\\1%s\\2@g\n' "$escaped_ip" "$escaped_anon_ip" >>"$ipv6_sed_script"
		done
	fi
	set -u

	# Build MAC address replacements script
	set +u
	if [[ ${#ANON_MAC_MAP[@]} -gt 0 ]]; then
		local sorted_macs
		readarray -t sorted_macs < <(printf '%s\n' "${!ANON_MAC_MAP[@]}" | awk '{print length($0), $0}' | sort -rn | cut -d' ' -f2-)
		for mac in "${sorted_macs[@]}"; do
			[[ -z "$mac" ]] && continue
			local anonymized_mac="${ANON_MAC_MAP[$mac]}"
			# Escape colons in MAC for sed pattern
			# Note: colon is not a regex metacharacter, but we escape it for MAC addresses
			local escaped_mac="${mac//:/\\:}"
			# Escape special characters in anonymized MAC (for sed replacement)
			# Note: colon doesn't need escaping in replacement strings, but keeping for consistency
			local escaped_anon_mac
			escaped_anon_mac=$(escape_sed_replacement "$anonymized_mac" "@")
			escaped_anon_mac="${escaped_anon_mac//:/\\:}"
			# Pattern: word boundary, then MAC, then word boundary
			# Use | as delimiter (simple pattern, no alternation operator)
			printf 's|\\b%s\\b|%s|g\n' "$escaped_mac" "$escaped_anon_mac" >>"$mac_sed_script"
		done
	fi
	set -u

	# Build hostname replacements script
	set +u
	if [[ ${#ANON_HOSTNAME_MAP[@]} -gt 0 ]]; then
		local sorted_hostnames
		readarray -t sorted_hostnames < <(printf '%s\n' "${!ANON_HOSTNAME_MAP[@]}" | awk '{print length($0), $0}' | sort -rn | cut -d' ' -f2-)
		for hostname in "${sorted_hostnames[@]}"; do
			[[ -z "$hostname" ]] && continue
			local anonymized_hostname="${ANON_HOSTNAME_MAP[$hostname]}"
			# Escape special regex characters in hostname
			local escaped_hostname
			escaped_hostname=$(escape_sed_regex "$hostname")
			# Escape special characters in anonymized hostname (for sed replacement)
			local escaped_anon_hostname
			escaped_anon_hostname=$(escape_sed_replacement "$anonymized_hostname" "@")
			# Pattern: word boundary, then hostname, then word boundary
			# Use | as delimiter (simple pattern, no alternation operator)
			printf 's|\\b%s\\b|%s|g\n' "$escaped_hostname" "$escaped_anon_hostname" >>"$hostname_sed_script"
		done
	fi
	set -u

	# Process log file with multiple sed invocations
	# Order: hostnames, MACs, locations, IPv6, IPv4
	# This ensures longer patterns are replaced before shorter ones
	[[ $VERBOSE -eq 1 ]] && echo "Anonymizing log file..." >&2

	# Use -E for extended regex to support backreferences
	# Chain sed invocations in order using pipes
	local temp_stage
	temp_stage=$(mktemp)
	cp "$input_file" "$temp_stage"

	# Stage 1: hostnames
	if [[ -s "$hostname_sed_script" ]]; then
		sed -Ef "$hostname_sed_script" "$temp_stage" >"${temp_stage}.2" 2>/dev/null || true
		mv "${temp_stage}.2" "$temp_stage"
	fi

	# Stage 2: MAC addresses
	if [[ -s "$mac_sed_script" ]]; then
		sed -Ef "$mac_sed_script" "$temp_stage" >"${temp_stage}.2" 2>/dev/null || true
		mv "${temp_stage}.2" "$temp_stage"
	fi

	# Stage 3: locations
	if [[ -s "$location_sed_script" ]]; then
		sed -Ef "$location_sed_script" "$temp_stage" >"${temp_stage}.2" 2>/dev/null || true
		mv "${temp_stage}.2" "$temp_stage"
	fi

	# Stage 4: IPv6
	if [[ -s "$ipv6_sed_script" ]]; then
		sed -Ef "$ipv6_sed_script" "$temp_stage" >"${temp_stage}.2" 2>/dev/null || true
		mv "${temp_stage}.2" "$temp_stage"
	fi

	# Stage 5: IPv4
	if [[ -s "$ipv4_sed_script" ]]; then
		sed -Ef "$ipv4_sed_script" "$temp_stage" >"${temp_stage}.2" 2>/dev/null || true
		mv "${temp_stage}.2" "$temp_stage"
	fi

	# Copy final result to output
	if [[ -n "$output_file" ]]; then
		cp "$temp_stage" "$output_file"
	else
		cat "$temp_stage"
	fi
	rm -f "$temp_stage" "${temp_stage}.2"

	local line_count
	line_count=$(wc -l <"$input_file" || echo "0")

	[[ $VERBOSE -eq 1 ]] && echo "Processed $line_count lines" >&2
	[[ $VERBOSE -eq 1 ]] && echo "Anonymization complete!" >&2

	return 0
}

# Main execution
#
# Main entry point for the script. Parses arguments and performs log anonymization.
#
# Arguments:
#   $@: Command line arguments
#
# Returns:
#   0: Success
#   1: Error (exits script)
main() {
	# Parse command line arguments
	parse_args "$@"

	# Load existing mapping file if provided
	if [[ -n "$MAPPING_FILE" ]]; then
		if [[ -f "$MAPPING_FILE" ]]; then
			[[ $VERBOSE -eq 1 ]] && echo "Loading existing mapping file: $MAPPING_FILE" >&2
			if ! load_mapping_file "$MAPPING_FILE"; then
				echo "WARNING: Failed to load mapping file: $MAPPING_FILE" >&2
				echo "         Continuing with new mappings..." >&2
			fi
		else
			[[ $VERBOSE -eq 1 ]] && echo "Mapping file does not exist, will create new one: $MAPPING_FILE" >&2
		fi
	fi

	# Generate anonymized output filename if output file is specified
	# This replaces location name in filename with anonymized location name
	local final_output_file="$OUTPUT_FILE"
	if [[ -n "$OUTPUT_FILE" ]]; then
		final_output_file=$(generate_anonymized_output_filename "$INPUT_FILE" "$OUTPUT_FILE" "$INPUT_FILE")
		[[ $VERBOSE -eq 1 ]] && [[ "$final_output_file" != "$OUTPUT_FILE" ]] && echo "Output filename updated: $OUTPUT_FILE -> $final_output_file" >&2
	fi

	# Anonymize log file
	if ! anonymize_log_file "$INPUT_FILE" "$final_output_file"; then
		echo "ERROR: Failed to anonymize log file" >&2
		exit 1
	fi

	# Save mapping file if provided
	if [[ -n "$MAPPING_FILE" ]]; then
		[[ $VERBOSE -eq 1 ]] && echo "Saving mapping file: $MAPPING_FILE" >&2
		if ! save_mapping_file "$MAPPING_FILE"; then
			echo "WARNING: Failed to save mapping file: $MAPPING_FILE" >&2
		fi
	fi

	# Print summary
	if [[ -n "$final_output_file" ]]; then
		echo "Anonymized log written to: $final_output_file" >&2
	else
		# Output was to stdout, summary already shown via verbose
		:
	fi

	return 0
}

# Run main function
main "$@"
