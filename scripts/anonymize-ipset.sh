#!/bin/bash
#
# UDM VPN Monitor Ipset Sets Anonymization Script
# Anonymizes IP addresses, set names, MAC addresses, and hostnames in ipset save output
# while maintaining consistency so sets remain understandable
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

# Extract set names from ipset save file
#
# Scans the file and extracts all unique set names.
# Handles set names in "create SET_NAME" and "add SET_NAME" lines.
#
# Arguments:
#   $1: Input file path
#
# Returns:
#   0: Success
#
# Output:
#   Prints unique set names (one per line) to stdout
extract_set_names_from_ipset() {
	local input_file="$1"
	local set_names=()

	# Extract set names from "create SET_NAME" and "add SET_NAME" patterns
	while IFS= read -r line || [[ -n "$line" ]]; do
		# Skip empty lines
		[[ -z "$line" ]] && continue

		# Pattern 1: "create SET_NAME ..."
		if [[ $line =~ ^create[[:space:]]+([A-Za-z0-9_]+) ]]; then
			local set_name="${BASH_REMATCH[1]}"
			set_names+=("$set_name")
		# Pattern 2: "add SET_NAME ..."
		elif [[ $line =~ ^add[[:space:]]+([A-Za-z0-9_]+) ]]; then
			local set_name="${BASH_REMATCH[1]}"
			set_names+=("$set_name")
		fi
	done <"$input_file"

	# Remove duplicates and sort
	printf '%s\n' "${set_names[@]}" | sort -u
}

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

UDM VPN Monitor Ipset Sets Anonymization Tool v0.1.0
Anonymizes IP addresses, set names, MAC addresses, and hostnames in ipset save output
while maintaining consistency so sets remain understandable.

Options:
  -i, --input FILE      Input ipset save file (required)
  -o, --output FILE     Output file for anonymized sets (default: stdout)
  -m, --mapping-file FILE  Mapping file for unified anonymization (optional)
                          If provided, loads existing mappings and saves updated mappings
  -v, --verbose         Verbose output
  -h, --help            Show this help message

Examples:
  $0 -i /tmp/ipset-save.txt -o anonymized-ipset.txt
  $0 -i ipset-sets.txt | less
  $0 -i ipset-sets.txt -o anonymized-ipset.txt -v

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

	# Prevent overwriting input file
	if [[ -n "$OUTPUT_FILE" ]]; then
		local input_abs
		local output_abs
		input_abs=$(readlink -f "$INPUT_FILE" 2>/dev/null || realpath "$INPUT_FILE" 2>/dev/null || echo "$INPUT_FILE")
		output_abs=$(readlink -f "$OUTPUT_FILE" 2>/dev/null || realpath "$OUTPUT_FILE" 2>/dev/null || echo "$OUTPUT_FILE")
		if [[ "$input_abs" == "$output_abs" ]]; then
			echo "ERROR: Output file cannot be the same as input file: $INPUT_FILE" >&2
			echo "       Use a different output filename to avoid overwriting the input file." >&2
			exit 1
		fi
	fi
}

# Get temporary directory for file operations
#
# Determines a writable temporary directory, falling back to input file directory if needed.
#
# Arguments:
#   $1: Input file path (for fallback directory)
#
# Returns:
#   0: Success
#
# Output:
#   Prints temp directory path to stdout
get_temp_dir() {
	local input_file="$1"
	local temp_dir="${TMPDIR:-/tmp}"
	# Ensure temp directory exists and is writable
	if [[ ! -d "$temp_dir" ]] || [[ ! -w "$temp_dir" ]]; then
		temp_dir="$(dirname "$input_file")"
	fi
	echo "$temp_dir"
}

# Anonymize ipset save file
#
# Reads input ipset save file, replaces all IP addresses, set names,
# MAC addresses, and hostnames with anonymized versions, and writes to output.
#
# Arguments:
#   $1: Input file path
#   $2: Output file path (or empty for stdout)
#
# Returns:
#   0: Success
#   1: Error
anonymize_ipset_file() {
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
	done < <(extract_ipv4_from_file "$input_file")

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

	[[ $VERBOSE -eq 1 ]] && echo "Extracting set names..." >&2
	local set_name_count=0
	while IFS= read -r set_name || [[ -n "$set_name" ]]; do
		[[ -z "$set_name" ]] && continue
		# Use unified mapping function (call without command substitution to avoid subshell)
		get_or_create_set_name_mapping "$set_name" >/dev/null
		set_name_count=$((set_name_count + 1))
		[[ $VERBOSE -eq 1 ]] && echo "  Mapping $set_name -> ${ANON_SET_NAME_MAP[$set_name]}" >&2
	done < <(extract_set_names_from_ipset "$input_file")

	[[ $VERBOSE -eq 1 ]] && echo "Extracted $set_name_count unique set names" >&2

	# Build sed scripts for replacements (separate scripts for each type)
	[[ $VERBOSE -eq 1 ]] && echo "Building replacement scripts..." >&2
	local ipv4_sed_script
	local ipv6_sed_script
	local mac_sed_script
	local hostname_sed_script
	local set_name_sed_script
	local temp_dir
	temp_dir=$(get_temp_dir "$input_file")
	if ! ipv4_sed_script=$(mktemp "${temp_dir}/anonymize-ipset-ipv4-XXXXXX" 2>/dev/null); then
		ipv4_sed_script="${temp_dir}/anonymize-ipset-ipv4-$$"
		touch "$ipv4_sed_script" || return 1
	fi
	if ! ipv6_sed_script=$(mktemp "${temp_dir}/anonymize-ipset-ipv6-XXXXXX" 2>/dev/null); then
		ipv6_sed_script="${temp_dir}/anonymize-ipset-ipv6-$$"
		touch "$ipv6_sed_script" || return 1
	fi
	if ! mac_sed_script=$(mktemp "${temp_dir}/anonymize-ipset-mac-XXXXXX" 2>/dev/null); then
		mac_sed_script="${temp_dir}/anonymize-ipset-mac-$$"
		touch "$mac_sed_script" || return 1
	fi
	if ! hostname_sed_script=$(mktemp "${temp_dir}/anonymize-ipset-hostname-XXXXXX" 2>/dev/null); then
		hostname_sed_script="${temp_dir}/anonymize-ipset-hostname-$$"
		touch "$hostname_sed_script" || return 1
	fi
	if ! set_name_sed_script=$(mktemp "${temp_dir}/anonymize-ipset-setname-XXXXXX" 2>/dev/null); then
		set_name_sed_script="${temp_dir}/anonymize-ipset-setname-$$"
		touch "$set_name_sed_script" || return 1
	fi

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
		rm -f "${ipv4_sed_script:-}" "${ipv6_sed_script:-}" "${mac_sed_script:-}" "${hostname_sed_script:-}" "${set_name_sed_script:-}"
	}
	trap cleanup_temp_files EXIT

	# Build set name replacements script (must be first to avoid conflicts)
	# Process set names in reverse order of length to avoid partial replacements
	set +u
	if [[ ${#ANON_SET_NAME_MAP[@]} -gt 0 ]]; then
		local sorted_set_names
		readarray -t sorted_set_names < <(printf '%s\n' "${!ANON_SET_NAME_MAP[@]}" | awk '{print length($0), $0}' | sort -rn | cut -d' ' -f2-)
		for set_name in "${sorted_set_names[@]}"; do
			[[ -z "$set_name" ]] && continue
			local anonymized_set="${ANON_SET_NAME_MAP[$set_name]}"
			# Escape special regex characters in set name
			local escaped_set
			escaped_set=$(escape_sed_regex "$set_name")

			# Escape special characters in anonymized set name (for sed replacement)
			local escaped_anon_set
			escaped_anon_set=$(escape_sed_replacement "$anonymized_set" "@")

			# Replace set names in "create SET_NAME" and "add SET_NAME" patterns
			# Use | as delimiter to avoid issues with / in set names
			printf 's|^create %s |create %s |g\n' "$escaped_set" "$escaped_anon_set" >>"$set_name_sed_script"
			printf 's|^add %s |add %s |g\n' "$escaped_set" "$escaped_anon_set" >>"$set_name_sed_script"
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
			# Pattern: word boundary or non-word char, then IP, then end of word or non-word char
			# For IPs with CIDR, we need to match the / as well, so use [^0-9./] to exclude digits, dots, and slashes
			# Use @ as delimiter to avoid issues with / and | in patterns
			if [[ "$ip" =~ / ]]; then
				# IP has CIDR notation - match including the CIDR
				printf 's@(^|[^0-9./])%s([^0-9./]|$)@\\1%s\\2@g\n' "$escaped_ip" "$escaped_anon_ip" >>"$ipv4_sed_script"
			else
				# IP without CIDR - original pattern
				printf 's@(^|[^0-9.])%s([^0-9.]|$)@\\1%s\\2@g\n' "$escaped_ip" "$escaped_anon_ip" >>"$ipv4_sed_script"
			fi
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

	# Process ipset file with multiple sed invocations
	# Order: set names first, then hostnames, MACs, IPv6, IPv4
	# This ensures longer patterns are replaced before shorter ones
	[[ $VERBOSE -eq 1 ]] && echo "Anonymizing ipset file..." >&2

	# Use -E for extended regex to support backreferences
	# Chain sed invocations in order using pipes
	local temp_stage
	local temp_dir
	temp_dir=$(get_temp_dir "$input_file")
	if ! temp_stage=$(mktemp "${temp_dir}/anonymize-ipset-stage-XXXXXX" 2>/dev/null); then
		# Fallback: create file in same directory as input
		temp_stage="${temp_dir}/anonymize-ipset-stage-$$"
		touch "$temp_stage" || {
			echo "ERROR: Failed to create temporary file" >&2
			return 1
		}
	fi
	cp "$input_file" "$temp_stage" || {
		echo "ERROR: Failed to copy input file to temporary file" >&2
		return 1
	}

	# Stage 1: set names (must be first)
	if [[ -s "$set_name_sed_script" ]]; then
		if sed -Ef "$set_name_sed_script" "$temp_stage" >"${temp_stage}.2" 2>/dev/null; then
			mv "${temp_stage}.2" "$temp_stage"
		else
			echo "WARNING: sed failed for set names, continuing..." >&2
		fi
	fi

	# Stage 2: hostnames
	if [[ -s "$hostname_sed_script" ]]; then
		if sed -Ef "$hostname_sed_script" "$temp_stage" >"${temp_stage}.2" 2>/dev/null; then
			mv "${temp_stage}.2" "$temp_stage"
		else
			echo "WARNING: sed failed for hostnames, continuing..." >&2
		fi
	fi

	# Stage 3: MAC addresses
	if [[ -s "$mac_sed_script" ]]; then
		if sed -Ef "$mac_sed_script" "$temp_stage" >"${temp_stage}.2" 2>/dev/null; then
			mv "${temp_stage}.2" "$temp_stage"
		else
			echo "WARNING: sed failed for MAC addresses, continuing..." >&2
		fi
	fi

	# Stage 4: IPv6
	if [[ -s "$ipv6_sed_script" ]]; then
		if sed -Ef "$ipv6_sed_script" "$temp_stage" >"${temp_stage}.2" 2>/dev/null; then
			mv "${temp_stage}.2" "$temp_stage"
		else
			echo "WARNING: sed failed for IPv6, continuing..." >&2
		fi
	fi

	# Stage 5: IPv4
	if [[ -s "$ipv4_sed_script" ]]; then
		if sed -Ef "$ipv4_sed_script" "$temp_stage" >"${temp_stage}.2" 2>/dev/null; then
			mv "${temp_stage}.2" "$temp_stage"
		else
			echo "WARNING: sed failed for IPv4, continuing..." >&2
		fi
	fi

	# Copy final result to output
	if [[ -n "$output_file" ]]; then
		# Ensure output directory exists
		local output_dir
		output_dir=$(dirname "$output_file")
		if [[ -n "$output_dir" ]] && [[ "$output_dir" != "." ]]; then
			mkdir -p "$output_dir" || {
				echo "ERROR: Failed to create output directory: $output_dir" >&2
				rm -f "$temp_stage" "${temp_stage}.2"
				return 1
			}
		fi
		cp "$temp_stage" "$output_file" || {
			echo "ERROR: Failed to copy result to output file: $output_file" >&2
			rm -f "$temp_stage" "${temp_stage}.2"
			return 1
		}
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
# Main entry point for the script. Parses arguments and performs ipset anonymization.
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

	# Anonymize ipset file
	if ! anonymize_ipset_file "$INPUT_FILE" "$OUTPUT_FILE"; then
		echo "ERROR: Failed to anonymize ipset file" >&2
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
	if [[ -n "$OUTPUT_FILE" ]]; then
		echo "Anonymized ipset sets written to: $OUTPUT_FILE" >&2
	else
		# Output was to stdout, summary already shown via verbose
		:
	fi

	return 0
}

# Run main function
main "$@"
