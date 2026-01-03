#!/bin/bash
#
# UDM VPN Monitor Log Anonymization Script
# Anonymizes location names and IP addresses in vpn-monitor.log files
# while maintaining consistency so logs remain understandable
#
# Version: 1.0.0
#

set -euo pipefail

# Default values
INPUT_FILE=""
OUTPUT_FILE=""
VERBOSE=0

# City names for location anonymization (common US cities)
CITY_NAMES=(
	"HOUSTON" "DALLAS" "PHOENIX" "SAN_ANTONIO" "SAN_DIEGO" "AUSTIN"
	"JACKSONVILLE" "FORT_WORTH" "COLUMBUS" "CHARLOTTE" "SAN_FRANCISCO"
	"INDIANAPOLIS" "SEATTLE" "DENVER" "BOSTON" "EL_PASO" "DETROIT"
	"NASHVILLE" "PORTLAND" "OKLAHOMA_CITY" "LAS_VEGAS" "MEMPHIS"
	"LOUISVILLE" "BALTIMORE" "MILWAUKEE" "ALBUQUERQUE" "TUCSON"
	"FRESNO" "SACRAMENTO" "KANSAS_CITY" "MESA" "ATLANTA"
	"OMAHA" "LOS_ANGELES" "RALEIGH" "VIRGINIA_BEACH" "MIAMI"
	"OAKLAND" "PHILADELPHIA" "CHICAGO" "CLEVELAND" "WICHITA"
	"ARLINGTON" "NEW_ORLEANS" "TAMPA" "HONOLULU" "ANAHEIM"
)

# Print usage information
#
# Displays help text for the script.
#
# Returns:
#   0: Always succeeds
show_usage() {
	cat <<EOF
Usage: $0 [OPTIONS]

UDM VPN Monitor Log Anonymization Tool v1.0.0
Anonymizes location names and IP addresses in vpn-monitor.log files
while maintaining consistency so logs remain understandable.

Options:
  -i, --input FILE      Input log file (required)
  -o, --output FILE     Output file for anonymized log (default: stdout)
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

# Generate deterministic hash from string
#
# Creates a deterministic numeric hash from a string input.
# Used to ensure consistent mapping of IPs and locations.
#
# Arguments:
#   $1: String to hash
#
# Returns:
#   0: Success
#
# Output:
#   Prints hash value to stdout
hash_string() {
	local str="$1"
	# Use a simple hash function (sum of character codes)
	local hash=0
	local i
	for ((i = 0; i < ${#str}; i++)); do
		local char="${str:$i:1}"
		local code
		code=$(printf '%d' "'$char")
		hash=$((hash * 31 + code))
		# Keep hash positive
		hash=$((hash & 0x7FFFFFFF))
	done
	echo "$hash"
}

# Anonymize IPv4 address
#
# Maps an IPv4 address to a consistent anonymized address in the 10.x.x.x range.
# Uses deterministic hashing to ensure same input always produces same output.
#
# Arguments:
#   $1: Original IP address
#
# Returns:
#   0: Success
#
# Output:
#   Prints anonymized IP address to stdout
anonymize_ipv4() {
	local original_ip="$1"
	local hash
	hash=$(hash_string "$original_ip")

	# Map to 10.x.x.x range (10.0.0.0 - 10.255.255.255)
	# Use hash to generate consistent octets
	local octet1=10
	local octet2=$(((hash / 65536) % 256))
	local octet3=$(((hash / 256) % 256))
	local octet4=$((hash % 256))

	# Ensure we don't generate 10.0.0.0 or 10.255.255.255 (edge cases)
	[[ $octet2 -eq 0 ]] && octet2=1
	[[ $octet2 -eq 255 ]] && octet2=254
	[[ $octet3 -eq 0 ]] && octet3=1
	[[ $octet3 -eq 255 ]] && octet3=254
	[[ $octet4 -eq 0 ]] && octet4=1
	[[ $octet4 -eq 255 ]] && octet4=254

	echo "${octet1}.${octet2}.${octet3}.${octet4}"
}

# Extract all IP addresses from log file
#
# Scans the log file and extracts all unique IPv4 addresses.
# Handles various formats: "for IP", "location NAME (IP)", etc.
#
# Arguments:
#   $1: Log file path
#
# Returns:
#   0: Success
#
# Output:
#   Prints unique IP addresses (one per line) to stdout
extract_ips() {
	local log_file="$1"
	# Extract IPv4 addresses (pattern: 1-3 digits, dot, 1-3 digits, dot, 1-3 digits, dot, 1-3 digits)
	# This pattern matches IPs in various contexts
	grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$log_file" | sort -u
}

# Extract all location names from log file
#
# Scans the log file and extracts all unique location names.
# Handles formats: "for location NAME", "location NAME (IP)", etc.
#
# Arguments:
#   $1: Log file path
#
# Returns:
#   0: Success
#
# Output:
#   Prints unique location names (one per line) to stdout
extract_locations() {
	local log_file="$1"
	local locations=()

	# Pattern 1: "for location LOCATION_NAME (IP)" or "location LOCATION_NAME (IP)"
	# Pattern 2: "for location LOCATION_NAME" (without IP)
	# Pattern 3: "location LOCATION_NAME" followed by various text
	# Pattern 4: "Location LOCATION_NAME" (capital L, e.g., "Location AUSTIN - ping failed")
	# Pattern 5: Location names in comma-separated lists (e.g., "Found 11 location(s): PHOENIX, SEATTLE...")
	# Extract location names (uppercase words/underscores between "location" and parentheses or end)
	while IFS= read -r line || [[ -n "$line" ]]; do
		# Pattern: "location NAME (" - most common format
		if [[ $line =~ location\ ([A-Z][A-Z0-9_]+)\ \( ]]; then
			locations+=("${BASH_REMATCH[1]}")
		# Pattern: "for location NAME ("
		elif [[ $line =~ for\ location\ ([A-Z][A-Z0-9_]+)\ \( ]]; then
			locations+=("${BASH_REMATCH[1]}")
		# Pattern: "location NAME" followed by space and various keywords
		elif [[ $line =~ location\ ([A-Z][A-Z0-9_]+)\ (failure|after|VPN|check|recovered|OK|FAILED|until|still|resuming|Logging|Would|Attempting|Performing|Recovery|threshold|reached|skipped) ]]; then
			locations+=("${BASH_REMATCH[1]}")
		# Pattern: "for location NAME" at end or followed by space or colon
		elif [[ $line =~ for\ location\ ([A-Z][A-Z0-9_]+)(\ |:|$) ]]; then
			locations+=("${BASH_REMATCH[1]}")
		# Pattern: "Location NAME" (capital L, e.g., "Location AUSTIN - ping failed")
		elif [[ $line =~ Location\ ([A-Z][A-Z0-9_]+)\ ([-a-z]|$) ]]; then
			locations+=("${BASH_REMATCH[1]}")
		# Pattern: Location names in comma-separated lists (e.g., "Found 11 location(s): PHOENIX, SEATTLE, BOSTON...")
		# Extract all uppercase words/underscores after "location(s):" or "location:"
		elif [[ $line =~ location\(s\)?:\ ([A-Z][A-Z0-9_]+(,\ [A-Z][A-Z0-9_]+)*) ]]; then
			# Extract the comma-separated list
			local location_list="${BASH_REMATCH[1]}"
			# Split by comma and add each location
			IFS=',' read -ra location_array <<<"$location_list"
			for loc in "${location_array[@]}"; do
				# Trim whitespace
				loc="${loc#"${loc%%[![:space:]]*}"}"
				loc="${loc%"${loc##*[![:space:]]}"}"
				if [[ -n "$loc" ]] && [[ $loc =~ ^[A-Z][A-Z0-9_]+$ ]]; then
					locations+=("$loc")
				fi
			done
		fi
	done <"$log_file"

	# Remove duplicates and sort
	printf '%s\n' "${locations[@]}" | sort -u
}

# Anonymize log file
#
# Reads input log file, replaces all IP addresses and location names
# with anonymized versions, and writes to output.
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

	# Create associative arrays for mappings (bash 4+)
	declare -A ip_map
	declare -A location_map

	[[ $VERBOSE -eq 1 ]] && echo "Extracting IP addresses..." >&2
	local ip_count=0
	while IFS= read -r ip || [[ -n "$ip" ]]; do
		[[ -z "$ip" ]] && continue
		if [[ -z "${ip_map[$ip]:-}" ]]; then
			ip_map["$ip"]=$(anonymize_ipv4 "$ip")
			ip_count=$((ip_count + 1))
			[[ $VERBOSE -eq 1 ]] && echo "  Mapping $ip -> ${ip_map[$ip]}" >&2
		fi
	done < <(extract_ips "$input_file")

	[[ $VERBOSE -eq 1 ]] && echo "Extracted $ip_count unique IP addresses" >&2

	[[ $VERBOSE -eq 1 ]] && echo "Extracting location names..." >&2
	local location_count=0
	# Track which city names have been used to ensure unique mappings
	declare -A used_cities=()
	while IFS= read -r location || [[ -n "$location" ]]; do
		[[ -z "$location" ]] && continue
		if [[ -z "${location_map[$location]:-}" ]]; then
			# Ensure unique mapping: use hash as starting point, then find next available city
			local hash
			hash=$(hash_string "$location")
			local start_index=$((hash % ${#CITY_NAMES[@]}))
			local city_index=$start_index
			local anonymized_city
			local attempts=0
			# Find next available city name (with safety limit to prevent infinite loop)
			while [[ -n "${used_cities[${CITY_NAMES[$city_index]}]:-}" ]] && [[ $attempts -lt ${#CITY_NAMES[@]} ]]; do
				city_index=$(((city_index + 1) % ${#CITY_NAMES[@]}))
				attempts=$((attempts + 1))
			done
			# If all cities are used (more locations than city names), append number for uniqueness
			# This should be rare in practice, but ensures we don't have collisions
			if [[ $attempts -ge ${#CITY_NAMES[@]} ]]; then
				# All cities are used, find first available with number suffix
				local suffix=1
				while [[ -n "${used_cities[${CITY_NAMES[$start_index]}_${suffix}]:-}" ]]; do
					suffix=$((suffix + 1))
				done
				anonymized_city="${CITY_NAMES[$start_index]}_${suffix}"
			else
				anonymized_city="${CITY_NAMES[$city_index]}"
			fi
			location_map["$location"]="$anonymized_city"
			used_cities["$anonymized_city"]=1
			location_count=$((location_count + 1))
			[[ $VERBOSE -eq 1 ]] && echo "  Mapping $location -> ${location_map[$location]}" >&2
		fi
	done < <(extract_locations "$input_file")

	[[ $VERBOSE -eq 1 ]] && echo "Extracted $location_count unique location names" >&2

	# Process log file line by line
	[[ $VERBOSE -eq 1 ]] && echo "Anonymizing log file..." >&2

	# Determine output destination
	if [[ -n "$output_file" ]]; then
		exec 3>"$output_file"
	else
		exec 3>&1
	fi

	local line_count=0
	while IFS= read -r line || [[ -n "$line" ]]; do
		local anonymized_line="$line"

		# Replace location names first (before IPs, to avoid conflicts)
		for location in "${!location_map[@]}"; do
			local anonymized_location="${location_map[$location]}"
			# Replace "location LOCATION_NAME" patterns (lowercase)
			anonymized_line="${anonymized_line//location $location /location $anonymized_location }"
			anonymized_line="${anonymized_line//location $location(/location $anonymized_location(}"
			anonymized_line="${anonymized_line//for location $location /for location $anonymized_location }"
			anonymized_line="${anonymized_line//for location $location(/for location $anonymized_location(}"
			# Replace "Location LOCATION_NAME" patterns (capital L, e.g., "Location AUSTIN - ping failed")
			anonymized_line="${anonymized_line//Location $location /Location $anonymized_location }"
			anonymized_line="${anonymized_line//Location $location -/Location $anonymized_location -}"
			# Replace location names in comma-separated lists (e.g., "Found 11 location(s): PHOENIX, SEATTLE...")
			# Use sed for more complex pattern matching with word boundaries
			anonymized_line=$(echo "$anonymized_line" | sed -E "s/\b${location}\b/${anonymized_location}/g")
		done

		# Replace IP addresses
		# Use sed with proper escaping to handle word boundaries
		# Process IPs in reverse order of length to avoid partial replacements
		# (e.g., replace 192.168.1.10 before 192.168.1.1)
		if [[ -n "${!ip_map[*]}" ]]; then
			local sorted_ips
			readarray -t sorted_ips < <(printf '%s\n' "${!ip_map[@]}" | awk '{print length($0), $0}' | sort -rn | cut -d' ' -f2-)
			for ip in "${sorted_ips[@]}"; do
				[[ -z "$ip" ]] && continue
				local anonymized_ip="${ip_map[$ip]}"
				# Escape dots in IP for sed pattern
				local escaped_ip="${ip//./\\.}"
				# Use sed with word boundaries - \b works for IP addresses at word boundaries
				# Pattern: start of word or non-word char, then IP, then end of word or non-word char
				anonymized_line=$(echo "$anonymized_line" | sed -E "s/(^|[^0-9.])${escaped_ip}([^0-9.]|$)/\1${anonymized_ip}\2/g")
			done
		fi

		echo "$anonymized_line" >&3
		line_count=$((line_count + 1))
	done <"$input_file"

	# Close output file descriptor
	exec 3>&-

	[[ $VERBOSE -eq 1 ]] && echo "Processed $line_count lines" >&2
	[[ $VERBOSE -eq 1 ]] && echo "Anonymization complete!" >&2

	return 0
}

# Main execution
main() {
	# Parse command line arguments
	parse_args "$@"

	# Anonymize log file
	if ! anonymize_log_file "$INPUT_FILE" "$OUTPUT_FILE"; then
		echo "ERROR: Failed to anonymize log file" >&2
		exit 1
	fi

	# Print summary
	if [[ -n "$OUTPUT_FILE" ]]; then
		echo "Anonymized log written to: $OUTPUT_FILE" >&2
	else
		# Output was to stdout, summary already shown via verbose
		:
	fi

	return 0
}

# Run main function
main "$@"
