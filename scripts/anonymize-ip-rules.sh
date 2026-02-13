#!/bin/bash
#
# UDM VPN Monitor IP Rules Anonymization Script
# Anonymizes IP addresses and interface names in ip route output
# while maintaining consistency so rules remain understandable
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

# Note: hash_string, anonymize_ipv4, anonymize_ipv6, anonymize_interface are now provided by lib/anonymize.sh
# Note: extract_ipv4, extract_ipv6, and extract_interfaces are now provided by lib/anonymize.sh
# as extract_ipv4_from_file, extract_ipv6_from_file, and extract_interfaces_from_file
# However, IP routes use "dev <interface>" pattern which is different from firewall rules,
# so we need a custom extractor for route files
#
# Extract all interface names from IP route file
#
# Scans the file and extracts all unique interface names.
# Handles interface names after "dev" keyword in route entries.
#
# Arguments:
#   $1: Input file path
#
# Returns:
#   0: Success
#
# Output:
#   Prints unique interface names (one per line) to stdout
extract_interfaces_from_route_file() {
	local input_file="$1"
	local interfaces=()

	# Extract interface names from route entries
	# Pattern: "dev <interface>" appears in route output
	while IFS= read -r line || [[ -n "$line" ]]; do
		# Skip empty lines
		[[ -z "$line" ]] && continue

		# Extract from "dev <interface>" pattern
		# Process line word by word to find interfaces
		local prev_word=""
		for word in $line; do
			# Check if previous word was "dev"
			if [[ "$prev_word" == "dev" ]]; then
				# Validate it looks like an interface name
				if [[ $word =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
					interfaces+=("$word")
				fi
			fi
			prev_word="$word"
		done
	done <"$input_file"

	# Remove duplicates and sort
	printf '%s\n' "${interfaces[@]}" | sort -u
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

UDM VPN Monitor IP Rules Anonymization Tool v0.1.0
Anonymizes IP addresses and interface names in ip route output
while maintaining consistency so rules remain understandable.

Options:
  -i, --input FILE      Input IP rules file (required)
  -o, --output FILE     Output file for anonymized rules (default: stdout)
  -m, --mapping-file FILE  Mapping file for unified anonymization (optional)
                          If provided, loads existing mappings and saves updated mappings
  -v, --verbose         Verbose output
  -h, --help            Show this help message

Examples:
  $0 -i /tmp/ip-route.txt -o anonymized-routes.txt
  $0 -i routes-ipv4.txt | less
  $0 -i routes-ipv6.txt -o anonymized-routes.txt -v

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

# Anonymize IP rules file
#
# Reads input IP rules file, replaces all IP addresses and interface names
# with anonymized versions, and writes to output.
#
# Arguments:
#   $1: Input file path
#   $2: Output file path (or empty for stdout)
#
# Returns:
#   0: Success
#   1: Error
anonymize_ip_rules_file() {
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

	[[ $VERBOSE -eq 1 ]] && echo "Extracting interface names..." >&2
	local interface_count=0
	while IFS= read -r iface || [[ -n "$iface" ]]; do
		[[ -z "$iface" ]] && continue
		# Use unified mapping function (call without command substitution to avoid subshell)
		get_or_create_interface_mapping "$iface" >/dev/null
		interface_count=$((interface_count + 1))
		[[ $VERBOSE -eq 1 ]] && echo "  Mapping $iface -> ${ANON_INTERFACE_MAP[$iface]}" >&2
	done < <(extract_interfaces_from_route_file "$input_file")

	[[ $VERBOSE -eq 1 ]] && echo "Extracted $interface_count unique interface names" >&2

	# Build sed scripts for replacements
	[[ $VERBOSE -eq 1 ]] && echo "Building replacement scripts..." >&2
	local ipv4_sed_script
	local ipv6_sed_script
	local interface_sed_script
	ipv4_sed_script=$(mktemp)
	ipv6_sed_script=$(mktemp)
	interface_sed_script=$(mktemp)

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
		rm -f "${ipv4_sed_script:-}" "${ipv6_sed_script:-}" "${interface_sed_script:-}"
	}
	trap cleanup_temp_files EXIT

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
			# Pattern: word boundary or non-word char, then IP, then word boundary or non-word char
			# Use @ as delimiter to avoid issues with / and | in patterns
			printf 's@(^|[^0-9.])%s([^0-9./]|$)@\\1%s\\2@g\n' "$escaped_ip" "$escaped_anon_ip" >>"$ipv4_sed_script"
		done
	fi
	set -u

	# Build IPv6 replacements script
	# Process IPs in reverse order of length to avoid partial replacements
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

	# Build interface replacements script
	# Process interfaces in reverse order of length to avoid partial replacements
	set +u
	if [[ ${#ANON_INTERFACE_MAP[@]} -gt 0 ]]; then
		local sorted_interfaces
		readarray -t sorted_interfaces < <(printf '%s\n' "${!ANON_INTERFACE_MAP[@]}" | awk '{print length($0), $0}' | sort -rn | cut -d' ' -f2-)
		for iface in "${sorted_interfaces[@]}"; do
			[[ -z "$iface" ]] && continue
			local anonymized_iface="${ANON_INTERFACE_MAP[$iface]}"
			# Escape special regex characters in interface name
			local escaped_iface
			escaped_iface=$(escape_sed_regex "$iface")

			# Escape special characters in anonymized interface (for sed replacement)
			local escaped_anon_iface
			escaped_anon_iface=$(escape_sed_replacement "$anonymized_iface" "#")

			# Replace interface names after "dev" keyword
			# Pattern: "dev <interface>" or "dev<interface>" (with optional space)
			# Use # as delimiter to avoid issues with / and | in patterns
			printf 's#(^|[^a-zA-Z0-9_-])dev +%s( |$)#\\1dev %s\\2#g\n' "$escaped_iface" "$escaped_anon_iface" >>"$interface_sed_script"
		done
	fi
	set -u

	# Process IP rules file with multiple sed invocations
	# Order: interfaces first, then IPv6, then IPv4
	# This ensures longer patterns are replaced before shorter ones
	[[ $VERBOSE -eq 1 ]] && echo "Anonymizing IP rules file..." >&2

	# Use -E for extended regex to support backreferences
	# Chain sed invocations in order using pipes
	# Build pipeline conditionally, starting with input file
	# Test each sed script individually to identify issues
	local temp_stage
	temp_stage=$(mktemp)
	cp "$input_file" "$temp_stage"

	# Stage 1: interfaces
	if [[ -s "$interface_sed_script" ]]; then
		if ! sed -Ef "$interface_sed_script" "$temp_stage" >"${temp_stage}.2" 2>"${temp_stage}.err"; then
			echo "ERROR: Failed in interface sed script: $interface_sed_script" >&2
			cat "${temp_stage}.err" >&2
			head -3 "$interface_sed_script" >&2
			rm -f "${temp_stage}.err"
			return 1
		fi
		rm -f "${temp_stage}.err"
		mv "${temp_stage}.2" "$temp_stage"
	fi

	# Stage 2: IPv6
	if [[ -s "$ipv6_sed_script" ]]; then
		if ! sed -Ef "$ipv6_sed_script" "$temp_stage" >"${temp_stage}.2" 2>"${temp_stage}.err"; then
			echo "ERROR: Failed in IPv6 sed script: $ipv6_sed_script" >&2
			cat "${temp_stage}.err" >&2
			head -3 "$ipv6_sed_script" >&2
			rm -f "${temp_stage}.err"
			return 1
		fi
		rm -f "${temp_stage}.err"
		mv "${temp_stage}.2" "$temp_stage"
	fi

	# Stage 3: IPv4
	if [[ -s "$ipv4_sed_script" ]]; then
		if ! sed -Ef "$ipv4_sed_script" "$temp_stage" >"${temp_stage}.2" 2>"${temp_stage}.err"; then
			echo "ERROR: Failed in IPv4 sed script: $ipv4_sed_script" >&2
			cat "${temp_stage}.err" >&2
			head -3 "$ipv4_sed_script" >&2
			rm -f "${temp_stage}.err"
			return 1
		fi
		rm -f "${temp_stage}.err"
		mv "${temp_stage}.2" "$temp_stage"
	fi

	# Copy final result to output
	if [[ -n "$output_file" ]]; then
		cp "$temp_stage" "$output_file"
	else
		cat "$temp_stage"
	fi
	rm -f "$temp_stage" "${temp_stage}.2" "${temp_stage}.err"

	local line_count
	line_count=$(wc -l <"$input_file" || echo "0")

	[[ $VERBOSE -eq 1 ]] && echo "Processed $line_count lines" >&2
	[[ $VERBOSE -eq 1 ]] && echo "Anonymization complete!" >&2

	return 0
}

# Main execution
#
# Main entry point for the script. Parses arguments and performs IP rules anonymization.
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

	# Anonymize IP rules file
	if ! anonymize_ip_rules_file "$INPUT_FILE" "$OUTPUT_FILE"; then
		echo "ERROR: Failed to anonymize IP rules file" >&2
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
		echo "Anonymized IP rules written to: $OUTPUT_FILE" >&2
	else
		# Output was to stdout, summary already shown via verbose
		:
	fi

	return 0
}

# Run main function (unless we're being sourced for function extraction)
if [[ -z "${GENERATE_MAPPING_MODE:-}" ]]; then
	main "$@"
fi
