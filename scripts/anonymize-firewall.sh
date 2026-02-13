#!/bin/bash
#
# UDM VPN Monitor Firewall Rules Anonymization Script
# Anonymizes IP addresses, interface names, and other identifiers in iptables-save output
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

# Anonymize identifier (generic string)
#
# Maps an identifier string to a consistent anonymized version.
# Uses deterministic hashing to ensure same input always produces same output.
# This function is specific to firewall rules (comment identifiers).
#
# Arguments:
#   $1: Original identifier
#
# Returns:
#   0: Success
#
# Output:
#   Prints anonymized identifier to stdout
anonymize_identifier() {
	local original_id="$1"
	local hash
	hash=$(hash_string "$original_id")

	# Generate a consistent identifier using hash
	# Format: ID_XXXX where XXXX is hex representation
	local hex_hash
	hex_hash=$(printf "%08x" "$hash")
	echo "ID_${hex_hash}"
}

# Note: extract_ipv4, extract_ipv6, and extract_interfaces are now provided by lib/anonymize.sh
# as extract_ipv4_from_file, extract_ipv6_from_file, and extract_interfaces_from_file

# Extract chain names from firewall rules
#
# Scans the file and extracts all unique chain names.
# Handles chain names in chain declarations (:CHAIN_NAME) and chain references (-A CHAIN_NAME, -j CHAIN_NAME).
#
# Arguments:
#   $1: Input file path
#
# Returns:
#   0: Success
#
# Output:
#   Prints unique chain names (one per line) to stdout
extract_chain_names_from_firewall() {
	local input_file="$1"
	local chain_names=()

	# Extract chain names from various patterns
	while IFS= read -r line || [[ -n "$line" ]]; do
		# Skip comments and table declarations
		[[ "$line" =~ ^# ]] && continue
		[[ "$line" =~ ^\* ]] && continue
		[[ "$line" == "COMMIT" ]] && continue

		# Extract from chain declaration: :CHAIN_NAME [policy] [packets:bytes]
		if [[ $line =~ ^:([A-Za-z0-9_]+) ]]; then
			local chain_name="${BASH_REMATCH[1]}"
			# Skip standard chains (INPUT, OUTPUT, FORWARD, PREROUTING, POSTROUTING)
			if [[ ! "$chain_name" =~ ^(INPUT|OUTPUT|FORWARD|PREROUTING|POSTROUTING)$ ]]; then
				chain_names+=("$chain_name")
			fi
		fi

		# Extract from chain reference: -A CHAIN_NAME or -j CHAIN_NAME
		# Pattern: -A CHAIN_NAME or -j CHAIN_NAME (followed by space or end of line)
		if [[ $line =~ -[Aj][[:space:]]+([A-Za-z0-9_]+)([[:space:]]|$) ]]; then
			local chain_name="${BASH_REMATCH[1]}"
			# Skip standard chains (INPUT, OUTPUT, FORWARD, PREROUTING, POSTROUTING)
			if [[ ! "$chain_name" =~ ^(INPUT|OUTPUT|FORWARD|PREROUTING|POSTROUTING)$ ]]; then
				chain_names+=("$chain_name")
			fi
		fi
	done <"$input_file"

	# Remove duplicates and sort
	printf '%s\n' "${chain_names[@]}" | sort -u
}

# Extract ipset set names from firewall rules
#
# Scans the file and extracts all unique ipset set names.
# Handles set names in -m set --match-set SET_NAME patterns.
#
# Arguments:
#   $1: Input file path
#
# Returns:
#   0: Success
#
# Output:
#   Prints unique set names (one per line) to stdout
extract_set_names_from_firewall() {
	local input_file="$1"
	local set_names=()

	# Extract set names from --match-set patterns
	while IFS= read -r line || [[ -n "$line" ]]; do
		# Skip comments and table/chain declarations
		[[ "$line" =~ ^# ]] && continue
		[[ "$line" =~ ^[*:] ]] && continue
		[[ "$line" == "COMMIT" ]] && continue

		# Extract from --match-set SET_NAME pattern
		# Pattern: --match-set SET_NAME [src|dst|...]
		if [[ $line =~ --match-set[[:space:]]+([A-Za-z0-9_]+) ]]; then
			local set_name="${BASH_REMATCH[1]}"
			set_names+=("$set_name")
		fi
	done <"$input_file"

	# Remove duplicates and sort
	printf '%s\n' "${set_names[@]}" | sort -u
}

# Extract identifiers from comments
#
# Scans comments in the file and extracts potential identifiers.
# This is a heuristic approach - may need refinement based on actual usage.
#
# Arguments:
#   $1: Input file path
#
# Returns:
#   0: Success
#
# Output:
#   Prints unique identifiers (one per line) to stdout
extract_comment_identifiers() {
	local input_file="$1"
	local identifiers=()

	# Extract potential identifiers from comments
	# This is a simple heuristic - looks for words that might be identifiers
	while IFS= read -r line || [[ -n "$line" ]]; do
		# Only process comment lines
		[[ ! "$line" =~ ^# ]] && continue

		# Remove the # and leading whitespace
		local comment="${line#\#}"
		comment="${comment#"${comment%%[![:space:]]*}"}"

		# Skip empty comments or very short ones
		[[ ${#comment} -lt 3 ]] && continue

		# Extract words that look like identifiers (uppercase, alphanumeric, underscores)
		# This is a heuristic - may need adjustment
		if [[ $comment =~ ([A-Z][A-Z0-9_]{2,}) ]]; then
			identifiers+=("${BASH_REMATCH[1]}")
		fi
	done <"$input_file"

	# Remove duplicates and sort
	printf '%s\n' "${identifiers[@]}" | sort -u
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

UDM VPN Monitor Firewall Rules Anonymization Tool v0.1.0
Anonymizes IP addresses, interface names, and other identifiers in iptables-save output
while maintaining consistency so rules remain understandable.

Options:
  -i, --input FILE      Input firewall rules file (required)
  -o, --output FILE     Output file for anonymized rules (default: stdout)
  -m, --mapping-file FILE  Mapping file for unified anonymization (optional)
                          If provided, loads existing mappings and saves updated mappings
  -v, --verbose         Verbose output
  -h, --help            Show this help message

Examples:
  $0 -i /tmp/iptables-save.txt -o anonymized-rules.txt
  $0 -i firewall-rules.txt | less
  $0 -i firewall-rules.txt -o anonymized-rules.txt -v

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

# Anonymize firewall rules file
#
# Reads input firewall rules file, replaces all IP addresses, interface names,
# and other identifiers with anonymized versions, and writes to output.
#
# Arguments:
#   $1: Input file path
#   $2: Output file path (or empty for stdout)
#
# Returns:
#   0: Success
#   1: Error
anonymize_firewall_file() {
	local input_file="$1"
	local output_file="${2:-}"

	# Local map for identifiers (firewall-specific, not in unified library)
	declare -A identifier_map

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
	done < <(extract_interfaces_from_file "$input_file")

	[[ $VERBOSE -eq 1 ]] && echo "Extracted $interface_count unique interface names" >&2

	[[ $VERBOSE -eq 1 ]] && echo "Extracting chain names..." >&2
	local chain_name_count=0
	local chain_names_array=()
	while IFS= read -r chain_name || [[ -n "$chain_name" ]]; do
		[[ -z "$chain_name" ]] && continue
		# Use unified mapping function (call without command substitution to avoid subshell)
		# Chain names use the same mapping as set names for consistency
		get_or_create_set_name_mapping "$chain_name" >/dev/null
		chain_names_array+=("$chain_name")
		chain_name_count=$((chain_name_count + 1))
		[[ $VERBOSE -eq 1 ]] && echo "  Mapping $chain_name -> ${ANON_SET_NAME_MAP[$chain_name]}" >&2
	done < <(extract_chain_names_from_firewall "$input_file")

	[[ $VERBOSE -eq 1 ]] && echo "Extracted $chain_name_count unique chain names" >&2

	[[ $VERBOSE -eq 1 ]] && echo "Extracting ipset set names..." >&2
	local set_name_count=0
	while IFS= read -r set_name || [[ -n "$set_name" ]]; do
		[[ -z "$set_name" ]] && continue
		# Use unified mapping function (call without command substitution to avoid subshell)
		get_or_create_set_name_mapping "$set_name" >/dev/null
		set_name_count=$((set_name_count + 1))
		[[ $VERBOSE -eq 1 ]] && echo "  Mapping $set_name -> ${ANON_SET_NAME_MAP[$set_name]}" >&2
	done < <(extract_set_names_from_firewall "$input_file")

	[[ $VERBOSE -eq 1 ]] && echo "Extracted $set_name_count unique set names" >&2

	[[ $VERBOSE -eq 1 ]] && echo "Extracting identifiers from comments..." >&2
	local identifier_count=0
	while IFS= read -r identifier || [[ -n "$identifier" ]]; do
		[[ -z "$identifier" ]] && continue
		if [[ -z "${identifier_map[$identifier]:-}" ]]; then
			identifier_map["$identifier"]=$(anonymize_identifier "$identifier")
			identifier_count=$((identifier_count + 1))
			[[ $VERBOSE -eq 1 ]] && echo "  Mapping $identifier -> ${identifier_map[$identifier]}" >&2
		fi
	done < <(extract_comment_identifiers "$input_file")

	[[ $VERBOSE -eq 1 ]] && echo "Extracted $identifier_count unique identifiers" >&2

	# Build sed scripts for replacements
	[[ $VERBOSE -eq 1 ]] && echo "Building replacement scripts..." >&2
	local ipv4_sed_script
	local ipv6_sed_script
	local interface_sed_script
	local chain_name_sed_script
	local set_name_sed_script
	local identifier_sed_script
	ipv4_sed_script=$(mktemp)
	ipv6_sed_script=$(mktemp)
	interface_sed_script=$(mktemp)
	chain_name_sed_script=$(mktemp)
	set_name_sed_script=$(mktemp)
	identifier_sed_script=$(mktemp)

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
		rm -f "${ipv4_sed_script:-}" "${ipv6_sed_script:-}" "${interface_sed_script:-}" "${chain_name_sed_script:-}" "${set_name_sed_script:-}" "${identifier_sed_script:-}"
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
			escaped_anon_iface=$(escape_sed_replacement "$anonymized_iface" "@")

			# Replace interface names in various contexts
			# Pattern 1: -i interface or -o interface
			# In extended regex (-E), use + for one or more (not \+)
			# Use @ as delimiter (| is alternation in extended regex, / may appear in interface names)
			printf 's@-([io]) +([!]?)%s( |$)@-\\1 \\2%s\\3@g\n' "$escaped_iface" "$escaped_anon_iface" >>"$interface_sed_script"
			# Pattern 2: --in-interface interface or --out-interface interface
			printf 's@--(in|out)-interface +([!]?)%s( |$)@--\\1-interface \\2%s\\3@g\n' "$escaped_iface" "$escaped_anon_iface" >>"$interface_sed_script"
		done
	fi
	set -u

	# Build chain name replacements script
	# Process chain names in reverse order of length to avoid partial replacements
	# Only process chain names that are not standard chains (INPUT, OUTPUT, FORWARD, etc.)
	set +u
	if [[ ${#chain_names_array[@]} -gt 0 ]]; then
		# Process chain names that were extracted earlier
		local sorted_chain_names
		readarray -t sorted_chain_names < <(printf '%s\n' "${chain_names_array[@]}" | awk '{print length($0), $0}' | sort -rn | cut -d' ' -f2-)
		for chain_name in "${sorted_chain_names[@]}"; do
			[[ -z "$chain_name" ]] && continue
			# Skip if not in map (shouldn't happen, but be safe)
			[[ -z "${ANON_SET_NAME_MAP[$chain_name]:-}" ]] && continue
			local anonymized_chain="${ANON_SET_NAME_MAP[$chain_name]}"
			# Escape special regex characters in chain name
			local escaped_chain
			escaped_chain=$(escape_sed_regex "$chain_name")

			# Escape special characters in anonymized chain name (for sed replacement)
			local escaped_anon_chain
			escaped_anon_chain=$(escape_sed_replacement "$anonymized_chain" "@")

			# Replace chain names in various contexts
			# Pattern 1: Chain declaration :CHAIN_NAME [policy] [packets:bytes]
			# Use @ as delimiter (| is alternation in extended regex)
			printf 's@^:%s @:%s @g\n' "$escaped_chain" "$escaped_anon_chain" >>"$chain_name_sed_script"
			# Pattern 2: Chain reference -A CHAIN_NAME (followed by space or end of line)
			printf 's@-A %s( |$)@-A %s\\1@g\n' "$escaped_chain" "$escaped_anon_chain" >>"$chain_name_sed_script"
			# Pattern 3: Jump to chain -j CHAIN_NAME (followed by space or end of line)
			printf 's@-j %s( |$)@-j %s\\1@g\n' "$escaped_chain" "$escaped_anon_chain" >>"$chain_name_sed_script"
		done
	fi
	set -u

	# Build set name replacements script
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

			# Replace set names in --match-set pattern
			# Pattern: --match-set SET_NAME [src|dst|...]
			# Use @ as delimiter (| is alternation in extended regex)
			printf 's@--match-set %s @--match-set %s @g\n' "$escaped_set" "$escaped_anon_set" >>"$set_name_sed_script"
		done
	fi
	set -u

	# Build identifier replacements script
	# Process identifiers in reverse order of length to avoid partial replacements
	if [[ -n "${!identifier_map[*]}" ]]; then
		local sorted_identifiers
		readarray -t sorted_identifiers < <(printf '%s\n' "${!identifier_map[@]}" | awk '{print length($0), $0}' | sort -rn | cut -d' ' -f2-)
		for identifier in "${sorted_identifiers[@]}"; do
			[[ -z "$identifier" ]] && continue
			local anonymized_id="${identifier_map[$identifier]}"
			# Escape special regex characters in identifier
			local escaped_id
			escaped_id=$(escape_sed_regex "$identifier")

			# Escape special characters in anonymized identifier (for sed replacement)
			local escaped_anon_id
			escaped_anon_id=$(escape_sed_replacement "$anonymized_id" "@")

			# Replace identifiers in comments
			# Pattern: identifier at word boundaries
			# Use @ as delimiter to avoid issues with / and | in patterns
			printf 's@(^|[^A-Z0-9_])%s([^A-Z0-9_]|$)@\\1%s\\2@g\n' "$escaped_id" "$escaped_anon_id" >>"$identifier_sed_script"
		done
	fi

	# Process firewall rules file with multiple sed invocations
	# Order: identifiers first, then chain names, then set names, then interfaces, then IPv6, then IPv4
	# This ensures longer patterns are replaced before shorter ones
	[[ $VERBOSE -eq 1 ]] && echo "Anonymizing firewall rules file..." >&2

	# Use -E for extended regex to support backreferences
	# Chain sed invocations in order using pipes
	# Build pipeline conditionally, starting with input file
	# Test each sed script individually to identify issues
	local temp_stage
	temp_stage=$(mktemp)
	cp "$input_file" "$temp_stage"

	# Stage 1: identifiers
	if [[ -s "$identifier_sed_script" ]]; then
		if ! sed -Ef "$identifier_sed_script" "$temp_stage" >"${temp_stage}.2" 2>"${temp_stage}.err"; then
			echo "ERROR: Failed in identifier sed script: $identifier_sed_script" >&2
			cat "${temp_stage}.err" >&2
			head -3 "$identifier_sed_script" >&2
			rm -f "${temp_stage}.err"
			return 1
		fi
		rm -f "${temp_stage}.err"
		mv "${temp_stage}.2" "$temp_stage"
	fi

	# Stage 2: chain names (before set names to avoid conflicts)
	if [[ -s "$chain_name_sed_script" ]]; then
		if ! sed -Ef "$chain_name_sed_script" "$temp_stage" >"${temp_stage}.2" 2>"${temp_stage}.err"; then
			echo "ERROR: Failed in chain name sed script: $chain_name_sed_script" >&2
			cat "${temp_stage}.err" >&2
			head -3 "$chain_name_sed_script" >&2
			rm -f "${temp_stage}.err"
			return 1
		fi
		rm -f "${temp_stage}.err"
		mv "${temp_stage}.2" "$temp_stage"
	fi

	# Stage 3: set names
	if [[ -s "$set_name_sed_script" ]]; then
		if ! sed -Ef "$set_name_sed_script" "$temp_stage" >"${temp_stage}.2" 2>"${temp_stage}.err"; then
			echo "ERROR: Failed in set name sed script: $set_name_sed_script" >&2
			cat "${temp_stage}.err" >&2
			head -3 "$set_name_sed_script" >&2
			rm -f "${temp_stage}.err"
			return 1
		fi
		rm -f "${temp_stage}.err"
		mv "${temp_stage}.2" "$temp_stage"
	fi

	# Stage 4: interfaces
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

	# Stage 5: IPv6
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

	# Stage 6: IPv4
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
# Main entry point for the script. Parses arguments and performs firewall rules anonymization.
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

	# Anonymize firewall rules file
	if ! anonymize_firewall_file "$INPUT_FILE" "$OUTPUT_FILE"; then
		echo "ERROR: Failed to anonymize firewall rules file" >&2
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
		echo "Anonymized firewall rules written to: $OUTPUT_FILE" >&2
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
