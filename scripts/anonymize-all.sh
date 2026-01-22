#!/bin/bash
#
# UDM VPN Monitor Unified Anonymization Script
# Runs all anonymization scripts (firewall, IP rules, ipset, logs) with unified mapping
#
# Version: 0.1.0
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
FIREWALL_FILE=""
IP_ROUTES_IPV4_FILE=""
IP_ROUTES_IPV6_FILE=""
IPSET_FILE=""
LOG_FILE=""
INPUT_DIR=""
OUTPUT_DIR=""
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

UDM VPN Monitor Unified Anonymization Tool v0.1.0
Runs all anonymization scripts (firewall, IP rules, ipset, logs) with unified mapping
to ensure consistent anonymization across all file types.

Options:
  -d, --directory DIR       Input directory to auto-detect files (optional)
                            Auto-detects files matching export script patterns:
                            - firewall-rules-*.txt
                            - routes-ipv4-*.txt
                            - routes-ipv6-*.txt
                            - ipset-sets-*.txt
                            Uses most recent file of each type if multiple found
  -f, --firewall FILE       Input firewall rules file (iptables-save format)
                            Overrides auto-detection from directory
  -r4, --routes-ipv4 FILE  Input IPv4 routes file (ip route output)
                            Overrides auto-detection from directory
  -r6, --routes-ipv6 FILE  Input IPv6 routes file (ip -6 route output)
                            Overrides auto-detection from directory
  -s, --ipset FILE          Input ipset sets file (ipset save output)
                            Overrides auto-detection from directory
  -l, --logs FILE           Input VPN monitor log file (vpn-monitor.log)
  -o, --output-dir DIR      Output directory for anonymized files (required)
  -m, --mapping-file FILE   Mapping file for unified anonymization (required)
                            If file exists, loads existing mappings
                            If file doesn't exist, creates new mappings
  -v, --verbose             Verbose output
  -h, --help                Show this help message

Output Files:
  The script creates anonymized versions of all provided input files in the output directory:
  - firewall-rules-anonymized.txt (if --firewall provided)
  - routes-ipv4-anonymized.txt (if --routes-ipv4 provided)
  - routes-ipv6-anonymized.txt (if --routes-ipv6 provided)
  - ipset-sets-anonymized.txt (if --ipset provided)
  - vpn-monitor-anonymized.log (if --logs provided)

Examples:
  # Anonymize all files with unified mapping (explicit files)
  $0 -f firewall.txt -r4 routes-ipv4.txt -r6 routes-ipv6.txt \\
     -s ipset.txt -l vpn-monitor.log \\
     -o /tmp/anonymized -m /tmp/mapping.txt

  # Anonymize using directory mode (auto-detect files)
  $0 -d /tmp/exports -l vpn-monitor.log \\
     -o /tmp/anonymized -m /tmp/mapping.txt

  # Mix directory mode with explicit files (explicit overrides auto-detection)
  $0 -d /tmp/exports -f custom-firewall.txt \\
     -o /tmp/anonymized -m /tmp/mapping.txt -v

EOF
}

# Find most recent file matching pattern in directory
#
# Searches a directory for files matching a glob pattern and returns the most recent one
# (lexicographically sorted, which works correctly for timestamp-based filenames).
#
# Arguments:
#   $1: Directory to search
#   $2: Glob pattern (e.g., "firewall-rules-*.txt")
#
# Returns:
#   0: Always succeeds (for use with set -e)
#
# Output:
#   Prints the path to the most recent matching file to stdout, or nothing if no files found
find_most_recent_file() {
	local dir="$1"
	local pattern="$2"
	local files

	readarray -t files < <(find "$dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | sort -r)
	if [[ ${#files[@]} -gt 0 ]]; then
		echo "${files[0]}"
	fi
	return 0
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
		-d | --directory)
			INPUT_DIR="$2"
			shift 2
			;;
		-f | --firewall)
			FIREWALL_FILE="$2"
			shift 2
			;;
		-r4 | --routes-ipv4)
			IP_ROUTES_IPV4_FILE="$2"
			shift 2
			;;
		-r6 | --routes-ipv6)
			IP_ROUTES_IPV6_FILE="$2"
			shift 2
			;;
		-s | --ipset)
			IPSET_FILE="$2"
			shift 2
			;;
		-l | --logs)
			LOG_FILE="$2"
			shift 2
			;;
		-o | --output-dir)
			OUTPUT_DIR="$2"
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
	if [[ -z "$OUTPUT_DIR" ]]; then
		echo "ERROR: Output directory is required" >&2
		show_usage
		exit 1
	fi

	if [[ -z "$MAPPING_FILE" ]]; then
		echo "ERROR: Mapping file is required" >&2
		show_usage
		exit 1
	fi

	# Auto-detect files from directory if provided and not explicitly set
	if [[ -n "$INPUT_DIR" ]]; then
		if [[ ! -d "$INPUT_DIR" ]]; then
			echo "ERROR: Input directory does not exist: $INPUT_DIR" >&2
			exit 1
		fi

		[[ $VERBOSE -eq 1 ]] && echo "Auto-detecting files in directory: $INPUT_DIR" >&2

		# Find most recent firewall rules file
		if [[ -z "$FIREWALL_FILE" ]]; then
			FIREWALL_FILE=$(find_most_recent_file "$INPUT_DIR" "firewall-rules-*.txt")
			[[ -n "$FIREWALL_FILE" ]] && [[ $VERBOSE -eq 1 ]] && echo "  Found firewall file: $FIREWALL_FILE" >&2
		fi

		# Find most recent IPv4 routes file
		if [[ -z "$IP_ROUTES_IPV4_FILE" ]]; then
			IP_ROUTES_IPV4_FILE=$(find_most_recent_file "$INPUT_DIR" "routes-ipv4-*.txt")
			[[ -n "$IP_ROUTES_IPV4_FILE" ]] && [[ $VERBOSE -eq 1 ]] && echo "  Found IPv4 routes file: $IP_ROUTES_IPV4_FILE" >&2
		fi

		# Find most recent IPv6 routes file
		if [[ -z "$IP_ROUTES_IPV6_FILE" ]]; then
			IP_ROUTES_IPV6_FILE=$(find_most_recent_file "$INPUT_DIR" "routes-ipv6-*.txt")
			[[ -n "$IP_ROUTES_IPV6_FILE" ]] && [[ $VERBOSE -eq 1 ]] && echo "  Found IPv6 routes file: $IP_ROUTES_IPV6_FILE" >&2
		fi

		# Find most recent ipset sets file
		if [[ -z "$IPSET_FILE" ]]; then
			IPSET_FILE=$(find_most_recent_file "$INPUT_DIR" "ipset-sets-*.txt")
			[[ -n "$IPSET_FILE" ]] && [[ $VERBOSE -eq 1 ]] && echo "  Found ipset file: $IPSET_FILE" >&2
		fi
	fi

	# Check that at least one input file is provided
	if [[ -z "$FIREWALL_FILE" ]] && [[ -z "$IP_ROUTES_IPV4_FILE" ]] &&
		[[ -z "$IP_ROUTES_IPV6_FILE" ]] && [[ -z "$IPSET_FILE" ]] && [[ -z "$LOG_FILE" ]]; then
		echo "ERROR: At least one input file must be provided" >&2
		if [[ -n "$INPUT_DIR" ]]; then
			echo "       No matching files found in directory: $INPUT_DIR" >&2
			echo "       Expected patterns:" >&2
			echo "         - firewall-rules-*.txt" >&2
			echo "         - routes-ipv4-*.txt" >&2
			echo "         - routes-ipv6-*.txt" >&2
			echo "         - ipset-sets-*.txt" >&2
			echo "       Or specify files explicitly with -f, -r4, -r6, -s, or -l options" >&2
		fi
		show_usage
		exit 1
	fi

	# Validate input files exist
	local missing_files=()
	[[ -n "$FIREWALL_FILE" ]] && [[ ! -f "$FIREWALL_FILE" ]] && missing_files+=("firewall: $FIREWALL_FILE")
	[[ -n "$IP_ROUTES_IPV4_FILE" ]] && [[ ! -f "$IP_ROUTES_IPV4_FILE" ]] && missing_files+=("routes-ipv4: $IP_ROUTES_IPV4_FILE")
	[[ -n "$IP_ROUTES_IPV6_FILE" ]] && [[ ! -f "$IP_ROUTES_IPV6_FILE" ]] && missing_files+=("routes-ipv6: $IP_ROUTES_IPV6_FILE")
	[[ -n "$IPSET_FILE" ]] && [[ ! -f "$IPSET_FILE" ]] && missing_files+=("ipset: $IPSET_FILE")
	[[ -n "$LOG_FILE" ]] && [[ ! -f "$LOG_FILE" ]] && missing_files+=("logs: $LOG_FILE")

	if [[ ${#missing_files[@]} -gt 0 ]]; then
		echo "ERROR: Input file(s) not found:" >&2
		printf '  %s\n' "${missing_files[@]}" >&2
		exit 1
	fi

	# Create output directory if it doesn't exist
	if [[ ! -d "$OUTPUT_DIR" ]]; then
		mkdir -p "$OUTPUT_DIR" || {
			echo "ERROR: Failed to create output directory: $OUTPUT_DIR" >&2
			exit 1
		}
	fi
}

# Run anonymization script with error handling
#
# Runs an anonymization script and handles errors gracefully.
#
# Arguments:
#   $1: Script path
#   $2: Input file path
#   $3: Output file path
#   $4: Mapping file path
#   $5: Verbose flag (0 or 1)
#
# Returns:
#   0: Success
#   1: Error
run_anonymize_script() {
	local script_path="$1"
	local input_file="$2"
	local output_file="$3"
	local mapping_file="$4"
	local verbose="$5"

	local args=(
		"$script_path"
		-i "$input_file"
		-o "$output_file"
		-m "$mapping_file"
	)
	[[ $verbose -eq 1 ]] && args+=(-v)

	if ! "${args[@]}"; then
		echo "ERROR: Failed to anonymize $input_file" >&2
		return 1
	fi

	return 0
}

# Main execution
#
# Main entry point for the script. Parses arguments and runs all anonymization scripts.
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

	[[ $VERBOSE -eq 1 ]] && echo "Starting unified anonymization..." >&2
	[[ $VERBOSE -eq 1 ]] && echo "Mapping file: $MAPPING_FILE" >&2
	[[ $VERBOSE -eq 1 ]] && echo "Output directory: $OUTPUT_DIR" >&2
	[[ $VERBOSE -eq 1 ]] && echo "" >&2

	local errors=0

	# Anonymize firewall rules
	if [[ -n "$FIREWALL_FILE" ]]; then
		[[ $VERBOSE -eq 1 ]] && echo "Anonymizing firewall rules..." >&2
		local firewall_output="${OUTPUT_DIR}/firewall-rules-anonymized.txt"
		if ! run_anonymize_script "${SCRIPT_DIR}/anonymize-firewall.sh" "$FIREWALL_FILE" "$firewall_output" "$MAPPING_FILE" "$VERBOSE"; then
			errors=$((errors + 1))
		else
			[[ $VERBOSE -eq 1 ]] && echo "  -> $firewall_output" >&2
		fi
	fi

	# Anonymize IPv4 routes
	if [[ -n "$IP_ROUTES_IPV4_FILE" ]]; then
		[[ $VERBOSE -eq 1 ]] && echo "Anonymizing IPv4 routes..." >&2
		local routes_ipv4_output="${OUTPUT_DIR}/routes-ipv4-anonymized.txt"
		if ! run_anonymize_script "${SCRIPT_DIR}/anonymize-ip-rules.sh" "$IP_ROUTES_IPV4_FILE" "$routes_ipv4_output" "$MAPPING_FILE" "$VERBOSE"; then
			errors=$((errors + 1))
		else
			[[ $VERBOSE -eq 1 ]] && echo "  -> $routes_ipv4_output" >&2
		fi
	fi

	# Anonymize IPv6 routes
	if [[ -n "$IP_ROUTES_IPV6_FILE" ]]; then
		[[ $VERBOSE -eq 1 ]] && echo "Anonymizing IPv6 routes..." >&2
		local routes_ipv6_output="${OUTPUT_DIR}/routes-ipv6-anonymized.txt"
		if ! run_anonymize_script "${SCRIPT_DIR}/anonymize-ip-rules.sh" "$IP_ROUTES_IPV6_FILE" "$routes_ipv6_output" "$MAPPING_FILE" "$VERBOSE"; then
			errors=$((errors + 1))
		else
			[[ $VERBOSE -eq 1 ]] && echo "  -> $routes_ipv6_output" >&2
		fi
	fi

	# Anonymize ipset sets
	if [[ -n "$IPSET_FILE" ]]; then
		[[ $VERBOSE -eq 1 ]] && echo "Anonymizing ipset sets..." >&2
		local ipset_output="${OUTPUT_DIR}/ipset-sets-anonymized.txt"
		if ! run_anonymize_script "${SCRIPT_DIR}/anonymize-ipset.sh" "$IPSET_FILE" "$ipset_output" "$MAPPING_FILE" "$VERBOSE"; then
			errors=$((errors + 1))
		else
			[[ $VERBOSE -eq 1 ]] && echo "  -> $ipset_output" >&2
		fi
	fi

	# Anonymize logs
	if [[ -n "$LOG_FILE" ]]; then
		[[ $VERBOSE -eq 1 ]] && echo "Anonymizing VPN monitor logs..." >&2
		local log_output="${OUTPUT_DIR}/vpn-monitor-anonymized.log"
		if ! run_anonymize_script "${SCRIPT_DIR}/anonymize-logs.sh" "$LOG_FILE" "$log_output" "$MAPPING_FILE" "$VERBOSE"; then
			errors=$((errors + 1))
		else
			[[ $VERBOSE -eq 1 ]] && echo "  -> $log_output" >&2
		fi
	fi

	[[ $VERBOSE -eq 1 ]] && echo "" >&2

	# Print summary
	if [[ $errors -eq 0 ]]; then
		echo "Anonymization complete! All files written to: $OUTPUT_DIR" >&2
		echo "Unified mapping file: $MAPPING_FILE" >&2
		return 0
	else
		echo "ERROR: Anonymization completed with $errors error(s)" >&2
		return 1
	fi
}

# Run main function
main "$@"
