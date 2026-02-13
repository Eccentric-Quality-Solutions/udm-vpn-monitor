#!/bin/bash
#
# UDM Routes and Firewall Export Script
# Exports all IP routes (IPv4 and IPv6), iptables firewall rules, and ipset sets from a UDM system
#
# Version: 0.2.0
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source common functions
# shellcheck source=../lib/common.sh
source "${PROJECT_ROOT}/lib/common.sh" 2>/dev/null || {
	echo "Error: Could not source lib/common.sh" >&2
	exit 1
}

# Default values
OUTPUT_DIR=""
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

UDM Routes and Firewall Export Tool
Exports all IP routes (IPv4 and IPv6), iptables firewall rules, and ipset sets to timestamped files.

Options:
  -o, --output DIR          Output directory for exported files (required)
  -v, --verbose             Verbose output
  --help                    Show this help message

Output Files:
  The script creates timestamped files organized into subdirectories:
  - routes-ipv4-<timestamp>.txt              IPv4 routes from 'ip route' (in output directory root)
  - routes-ipv6-<timestamp>.txt              IPv6 routes from 'ip -6 route' (in output directory root)
  - firewall-rules/firewall-rules-<timestamp>.txt  All iptables rules from 'iptables-save'
  - firewall-rules/ipset-sets-<timestamp>.txt      All ipset sets and their members from 'ipset save'

  Timestamp format: YYYY-MM-DD-HH-MM-SS (e.g., 2026-01-20-14-30-00)
  
  Firewall-related files (firewall-rules and ipset-sets) are automatically
  organized into a 'firewall-rules' subdirectory for better organization.

  Note: ipset export may be skipped if the 'ipset' command is not available
        or if it requires root privileges that are not available.

Examples:
  $0 -o /tmp/udm-export
  $0 --output /data/vpn-monitor/exports --verbose

EOF
}

# Parse command line arguments
#
# Processes command line arguments and sets global variables.
#
# Arguments:
#   $@: Command line arguments to parse
#
# Returns:
#   0: Success
#   1: Error
parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-o | --output)
			if [[ $# -lt 2 ]]; then
				log_error "Option $1 requires an argument"
				show_usage
				exit 1
			fi
			OUTPUT_DIR="$2"
			shift 2
			;;
		-v | --verbose)
			VERBOSE=1
			shift
			;;
		--help)
			show_usage
			exit 0
			;;
		*)
			log_error "Unknown option: $1"
			show_usage
			exit 1
			;;
		esac
	done

	# Validate required parameters
	if [[ -z "$OUTPUT_DIR" ]]; then
		log_error "Output directory is required. Use -o/--output to specify output directory."
		show_usage
		exit 1
	fi

	return 0
}

# Validate output directory
#
# Checks if the output directory exists and is writable.
#
# Arguments:
#   $1: Directory path to validate
#
# Returns:
#   0: Directory is valid and writable
#   1: Directory validation failed
validate_output_directory() {
	local dir="$1"

	# Check if directory exists
	if [[ ! -d "$dir" ]]; then
		log_error "Output directory does not exist: $dir"
		return 1
	fi

	# Check if directory is writable
	if ! directory_writable "$dir"; then
		log_error "Output directory is not writable: $dir"
		return 1
	fi

	return 0
}

# Generate timestamp string
#
# Generates a timestamp string in the format YYYY-MM-DD-HH-MM-SS.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints timestamp string to stdout
generate_timestamp() {
	date +"%Y-%m-%d-%H-%M-%S"
}

# Capture IPv4 routes
#
# Captures all IPv4 routes using 'ip route' command.
#
# Arguments:
#   $1: Output file path
#
# Returns:
#   0: Success
#   1: Error
capture_ipv4_routes() {
	local output_file="$1"
	local ip_cmd

	# Get full path to ip command
	ip_cmd=$(get_ip_command_path)

	[[ $VERBOSE -eq 1 ]] && log_info "Capturing IPv4 routes..."

	# Execute ip route command and save to file
	if ! "$ip_cmd" route >"$output_file" 2>&1; then
		log_error "Failed to capture IPv4 routes"
		return 1
	fi

	[[ $VERBOSE -eq 1 ]] && log_info "IPv4 routes saved to: $output_file"
	return 0
}

# Capture IPv6 routes
#
# Captures all IPv6 routes using 'ip -6 route' command.
#
# Arguments:
#   $1: Output file path
#
# Returns:
#   0: Success
#   1: Error
capture_ipv6_routes() {
	local output_file="$1"
	local ip_cmd

	# Get full path to ip command
	ip_cmd=$(get_ip_command_path)

	[[ $VERBOSE -eq 1 ]] && log_info "Capturing IPv6 routes..."

	# Execute ip -6 route command and save to file
	if ! "$ip_cmd" -6 route >"$output_file" 2>&1; then
		log_error "Failed to capture IPv6 routes"
		return 1
	fi

	[[ $VERBOSE -eq 1 ]] && log_info "IPv6 routes saved to: $output_file"
	return 0
}

# Capture firewall rules
#
# Captures all iptables rules using 'iptables-save' command.
#
# Arguments:
#   $1: Output file path
#
# Returns:
#   0: Success
#   1: Error
capture_firewall_rules() {
	local output_file="$1"
	local iptables_save_cmd

	# Get full path to iptables-save command
	iptables_save_cmd=$(get_command_path "iptables-save")

	[[ $VERBOSE -eq 1 ]] && log_info "Capturing firewall rules..."

	# Execute iptables-save command and save to file
	# Note: iptables-save may require root privileges
	if ! "$iptables_save_cmd" >"$output_file" 2>&1; then
		log_error "Failed to capture firewall rules"
		log_error "Note: iptables-save may require root privileges"
		return 1
	fi

	[[ $VERBOSE -eq 1 ]] && log_info "Firewall rules saved to: $output_file"
	return 0
}

# Capture ipset sets
#
# Captures all ipset sets and their members using 'ipset save' command.
# This is important because iptables rules reference ipset sets by name,
# but the actual members (IP addresses/networks) are stored separately.
#
# Arguments:
#   $1: Output file path
#
# Returns:
#   0: Success
#   1: Error (command not available or permission denied)
capture_ipset_sets() {
	local output_file="$1"
	local ipset_cmd

	# Check if ipset command is available
	if ! check_command_available "ipset"; then
		[[ $VERBOSE -eq 1 ]] && log_info "ipset command not available, skipping ipset export"
		return 1
	fi

	# Get full path to ipset command
	ipset_cmd=$(get_command_path "ipset")

	[[ $VERBOSE -eq 1 ]] && log_info "Capturing ipset sets..."

	# Execute ipset save command and save to file
	# Note: ipset save may require root privileges
	if ! "$ipset_cmd" save >"$output_file" 2>&1; then
		log_error "Failed to capture ipset sets"
		log_error "Note: ipset save may require root privileges"
		return 1
	fi

	[[ $VERBOSE -eq 1 ]] && log_info "Ipset sets saved to: $output_file"
	return 0
}

# Main function
#
# Main execution flow for the script.
#
# Arguments:
#   $@: Command line arguments
#
# Returns:
#   0: Success
#   1: Error (exits script on error)
main() {
	local timestamp
	local routes_ipv4_file
	local routes_ipv6_file
	local firewall_rules_file
	local ipset_sets_file
	local errors=0

	# Parse arguments
	parse_args "$@"

	# Validate output directory
	if ! validate_output_directory "$OUTPUT_DIR"; then
		exit 1
	fi

	# Check command availability
	[[ $VERBOSE -eq 1 ]] && log_info "Checking required commands..."

	if ! check_command_available "ip"; then
		log_error "ip command not available"
		exit 1
	fi

	if ! check_command_available "iptables-save"; then
		log_error "iptables-save command not available"
		exit 1
	fi

	# Generate timestamp
	timestamp=$(generate_timestamp)

	# Create firewall-rules subdirectory if it doesn't exist
	local firewall_rules_dir="${OUTPUT_DIR}/firewall-rules"
	if ! mkdir -p "$firewall_rules_dir" 2>/dev/null; then
		log_error "Failed to create firewall-rules subdirectory: $firewall_rules_dir"
		exit 1
	fi

	# Set output file paths
	# Routes stay in the root output directory
	routes_ipv4_file="${OUTPUT_DIR}/routes-ipv4-${timestamp}.txt"
	routes_ipv6_file="${OUTPUT_DIR}/routes-ipv6-${timestamp}.txt"
	# Firewall-related files go into firewall-rules subdirectory
	firewall_rules_file="${firewall_rules_dir}/firewall-rules-${timestamp}.txt"
	ipset_sets_file="${firewall_rules_dir}/ipset-sets-${timestamp}.txt"

	log_info "Exporting UDM routes, firewall rules, and ipset sets..."
	log_info "Output directory: $OUTPUT_DIR"
	log_info "Timestamp: $timestamp"

	# Capture IPv4 routes
	if ! capture_ipv4_routes "$routes_ipv4_file"; then
		errors=$((errors + 1))
	fi

	# Capture IPv6 routes
	if ! capture_ipv6_routes "$routes_ipv6_file"; then
		errors=$((errors + 1))
	fi

	# Capture firewall rules
	if ! capture_firewall_rules "$firewall_rules_file"; then
		errors=$((errors + 1))
	fi

	# Capture ipset sets (optional - may fail if command not available or no root)
	if ! capture_ipset_sets "$ipset_sets_file"; then
		# Don't count ipset failures as errors since it's optional
		[[ $VERBOSE -eq 1 ]] && log_info "Ipset export skipped (command not available or permission denied)"
	fi

	# Display summary
	echo ""
	echo "=========================================="
	echo "Export Complete"
	echo "=========================================="
	if [[ $errors -eq 0 ]]; then
		log_info "All exports completed successfully"
		echo ""
		echo "Files created:"
		echo "  - $routes_ipv4_file"
		echo "  - $routes_ipv6_file"
		echo "  - $firewall_rules_file"
		if [[ -f "$ipset_sets_file" ]]; then
			echo "  - $ipset_sets_file"
		fi
		echo ""
		return 0
	else
		log_error "Export completed with $errors error(s)"
		echo ""
		if [[ -f "$routes_ipv4_file" ]]; then
			echo "  - $routes_ipv4_file"
		fi
		if [[ -f "$routes_ipv6_file" ]]; then
			echo "  - $routes_ipv6_file"
		fi
		if [[ -f "$firewall_rules_file" ]]; then
			echo "  - $firewall_rules_file"
		fi
		if [[ -f "$ipset_sets_file" ]]; then
			echo "  - $ipset_sets_file"
		fi
		echo ""
		exit 1
	fi
}

# Run main function
main "$@"
