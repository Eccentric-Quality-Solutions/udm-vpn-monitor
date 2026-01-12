#!/bin/bash
#
# UDM Site-to-Site VPN List Script
# Connects to UDM API and retrieves a list of site-to-site VPN configurations
#
# Version: 0.1.0
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
UDM_HOST=""
UDM_USERNAME=""
UDM_PASSWORD=""
UDM_PORT="443"
SITE_NAME="default"
VERBOSE=0
USE_INSECURE_SSL=0
LIST_SITES_ONLY=0

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

UDM Site-to-Site VPN List Tool
Connects to UDM API and retrieves a list of site-to-site VPN configurations.

Options:
  -h, --host HOST          UDM hostname or IP address (required)
  -u, --username USER      UDM API username (required)
  -p, --password PASS      UDM API password (required)
  -P, --port PORT          UDM API port (default: 443)
  -s, --site SITE          Site name (default: default)
  -l, --list-sites         List all available sites and their IDs (then exit)
  -k, --insecure           Allow insecure SSL connections (skip certificate verification)
  -v, --verbose            Verbose output
  --help                   Show this help message

Environment Variables:
  UDM_HOST                 UDM hostname or IP address
  UDM_USERNAME             UDM API username
  UDM_PASSWORD             UDM API password
  UDM_PORT                 UDM API port (default: 443)
  UDM_SITE                 Site name (default: default)

Examples:
  $0 -h 192.168.1.1 -u admin -p password
  $0 --host 192.168.1.1 --username admin --password password --site production
  UDM_HOST=192.168.1.1 UDM_USERNAME=admin UDM_PASSWORD=password $0

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
		-h | --host)
			UDM_HOST="$2"
			shift 2
			;;
		-u | --username)
			UDM_USERNAME="$2"
			shift 2
			;;
		-p | --password)
			UDM_PASSWORD="$2"
			shift 2
			;;
		-P | --port)
			UDM_PORT="$2"
			shift 2
			;;
		-s | --site)
			SITE_NAME="$2"
			shift 2
			;;
		-l | --list-sites)
			LIST_SITES_ONLY=1
			shift
			;;
		-k | --insecure)
			USE_INSECURE_SSL=1
			shift
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

	# Use environment variables as fallback if not set via command line
	# Note: Variables set via command line will already have values, so env vars won't override them
	UDM_HOST="${UDM_HOST:-}"
	UDM_USERNAME="${UDM_USERNAME:-}"
	UDM_PASSWORD="${UDM_PASSWORD:-}"
	UDM_PORT="${UDM_PORT:-443}"
	if [[ -z "$SITE_NAME" ]] || [[ "$SITE_NAME" == "default" ]]; then
		SITE_NAME="${UDM_SITE:-default}"
	fi

	# Validate required parameters
	if [[ -z "$UDM_HOST" ]]; then
		log_error "UDM host is required. Use -h/--host or set UDM_HOST environment variable."
		show_usage
		exit 1
	fi

	if [[ -z "$UDM_USERNAME" ]]; then
		log_error "UDM username is required. Use -u/--username or set UDM_USERNAME environment variable."
		show_usage
		exit 1
	fi

	if [[ -z "$UDM_PASSWORD" ]]; then
		log_error "UDM password is required. Use -p/--password or set UDM_PASSWORD environment variable."
		show_usage
		exit 1
	fi

	return 0
}

# Check if curl is available
#
# Verifies that curl command is available in PATH.
#
# Arguments:
#   None
#
# Returns:
#   0: curl is available
#   1: curl is not available
check_curl_available() {
	if ! command -v curl >/dev/null 2>&1; then
		log_error "curl command not found. Please install curl."
		return 1
	fi
	return 0
}

# Check if jq is available
#
# Verifies that jq command is available in PATH.
#
# Arguments:
#   None
#
# Returns:
#   0: jq is available
#   1: jq is not available
check_jq_available() {
	if command -v jq >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

# Authenticate to UDM API
#
# Authenticates with the UDM API and returns session cookies.
#
# Arguments:
#   None
#
# Returns:
#   0: Authentication successful
#   1: Authentication failed
#
# Output:
#   Prints cookie file path to stdout on success
authenticate_udm_api() {
	local cookie_file
	local login_url
	local response
	local curl_opts=()

	cookie_file=$(mktemp)
	login_url="https://${UDM_HOST}:${UDM_PORT}/api/auth/login"

	# Build curl options
	curl_opts=(
		-s
		-S
		-c "$cookie_file"
		-X POST
		-H "Content-Type: application/json"
		-d "{\"username\":\"${UDM_USERNAME}\",\"password\":\"${UDM_PASSWORD}\"}"
	)

	if [[ $USE_INSECURE_SSL -eq 1 ]]; then
		curl_opts+=(-k)
	fi

	if [[ $VERBOSE -eq 1 ]]; then
		curl_opts+=(-v)
	fi

	# Attempt login
	if ! response=$(curl "${curl_opts[@]}" "$login_url" 2>&1); then
		log_error "Failed to connect to UDM API at $login_url"
		rm -f "$cookie_file"
		return 1
	fi

	# Check for authentication errors
	if echo "$response" | grep -qi "invalid\|unauthorized\|error"; then
		log_error "Authentication failed. Please check username and password."
		rm -f "$cookie_file"
		return 1
	fi

	# Check if cookie file was created and has content
	if [[ ! -f "$cookie_file" ]] || [[ ! -s "$cookie_file" ]]; then
		log_error "Authentication failed. No session cookie received."
		rm -f "$cookie_file"
		return 1
	fi

	echo "$cookie_file"
	return 0
}

# Get site ID from site name
#
# Retrieves the site ID for a given site name.
#
# Arguments:
#   $1: Cookie file path
#   $2: Site name
#
# Returns:
#   0: Site ID found
#   1: Site ID not found or error
#
# Output:
#   Prints site ID to stdout on success
get_site_id() {
	local cookie_file="$1"
	local site_name="$2"
	local sites_url
	local response
	local site_id
	local curl_opts=()

	sites_url="https://${UDM_HOST}:${UDM_PORT}/api/self/sites"

	curl_opts=(
		-s
		-S
		-b "$cookie_file"
	)

	if [[ $USE_INSECURE_SSL -eq 1 ]]; then
		curl_opts+=(-k)
	fi

	if ! response=$(curl "${curl_opts[@]}" "$sites_url" 2>&1); then
		log_error "Failed to retrieve sites list"
		return 1
	fi

	# Try to parse with jq if available
	if check_jq_available; then
		if site_id=$(echo "$response" | jq -r --arg name "$site_name" '.data[] | select(.name == $name) | ._id' 2>/dev/null); then
			if [[ -n "$site_id" ]] && [[ "$site_id" != "null" ]]; then
				echo "$site_id"
				return 0
			fi
		fi
	fi

	# Fallback: basic text parsing
	if site_id=$(echo "$response" | grep -o "\"_id\":\"[^\"]*\",\"name\":\"${site_name}\"" | grep -o "\"_id\":\"[^\"]*\"" | cut -d'"' -f4); then
		if [[ -n "$site_id" ]]; then
			echo "$site_id"
			return 0
		fi
	fi

	log_error "Site '$site_name' not found"
	return 1
}

# List all available sites
#
# Retrieves and displays all available sites with their IDs and names.
#
# Arguments:
#   $1: Cookie file path
#
# Returns:
#   0: Success
#   1: Error
#
# Output:
#   Prints site list (formatted JSON or text)
list_all_sites() {
	local cookie_file="$1"
	local sites_url
	local response
	local curl_opts=()

	sites_url="https://${UDM_HOST}:${UDM_PORT}/api/self/sites"

	curl_opts=(
		-s
		-S
		-b "$cookie_file"
	)

	if [[ $USE_INSECURE_SSL -eq 1 ]]; then
		curl_opts+=(-k)
	fi

	if ! response=$(curl "${curl_opts[@]}" "$sites_url" 2>&1); then
		log_error "Failed to retrieve sites list"
		return 1
	fi

	# Check for errors in response
	if echo "$response" | grep -qi "error\|unauthorized"; then
		log_error "Error retrieving sites list"
		echo "$response" >&2
		return 1
	fi

	# Format output based on jq availability
	if check_jq_available; then
		# Pretty print JSON with jq
		if echo "$response" | jq '.' >/dev/null 2>&1; then
			local site_count
			site_count=$(echo "$response" | jq '.data | length' 2>/dev/null || echo "0")
			if [[ "$site_count" -eq 0 ]]; then
				log_info "No sites found"
				return 0
			fi
			echo ""
			echo "=== Available Sites ==="
			echo ""
			echo "$response" | jq -r '.data[] | "Site Name: \(.name)\nSite ID:   \(._id)\n"'
			echo ""
			echo "Total sites: $site_count"
			echo ""
		else
			# Invalid JSON, output raw
			echo "$response"
		fi
	else
		# Basic text output
		echo ""
		echo "=== Available Sites ==="
		echo ""
		echo "$response"
		echo ""
		log_info "Tip: Install 'jq' for better formatted output"
	fi

	return 0
}

# Get site-to-site VPNs
#
# Retrieves site-to-site VPN configurations for a given site.
# Note: API endpoint may vary by UDM OS version. This uses the standard UniFi Controller API endpoint.
#
# Arguments:
#   $1: Cookie file path
#   $2: Site ID
#
# Returns:
#   0: Success
#   1: Error
#
# Output:
#   Prints VPN configurations (JSON or formatted text)
get_site_to_site_vpns() {
	local cookie_file="$1"
	local site_id="$2"
	local vpn_url
	local response
	local curl_opts=()

	# UniFi Controller API endpoint for VPN configurations
	# For UDM OS, this endpoint should work, but may need adjustment based on version
	vpn_url="https://${UDM_HOST}:${UDM_PORT}/api/s/${site_id}/rest/vpn"

	curl_opts=(
		-s
		-S
		-b "$cookie_file"
	)

	if [[ $USE_INSECURE_SSL -eq 1 ]]; then
		curl_opts+=(-k)
	fi

	if ! response=$(curl "${curl_opts[@]}" "$vpn_url" 2>&1); then
		log_error "Failed to retrieve VPN configurations"
		return 1
	fi

	# Check for errors in response
	if echo "$response" | grep -qi "error\|unauthorized"; then
		log_error "Error retrieving VPN configurations"
		echo "$response" >&2
		return 1
	fi

	# Check if response is empty or contains no VPN data
	if [[ -z "$response" ]] || [[ "$response" == "[]" ]] || [[ "$response" == "{}" ]]; then
		log_info "No site-to-site VPNs configured for this site"
		return 0
	fi

	# Format output based on jq availability
	if check_jq_available; then
		# Pretty print JSON with jq
		if echo "$response" | jq '.' >/dev/null 2>&1; then
			# Check if data array exists and has items
			local vpn_count
			vpn_count=$(echo "$response" | jq '.data | length' 2>/dev/null || echo "0")
			if [[ "$vpn_count" -eq 0 ]]; then
				log_info "No site-to-site VPNs configured for this site"
				return 0
			fi
			echo "$response" | jq '.'
		else
			# Invalid JSON, output raw
			echo "$response"
		fi
	else
		# Basic text output
		echo "$response"
	fi

	return 0
}

# Logout from UDM API
#
# Logs out from the UDM API session.
#
# Arguments:
#   $1: Cookie file path
#
# Returns:
#   0: Always succeeds
logout_udm_api() {
	local cookie_file="$1"
	local logout_url
	local curl_opts=()

	logout_url="https://${UDM_HOST}:${UDM_PORT}/api/auth/logout"

	curl_opts=(
		-s
		-S
		-b "$cookie_file"
		-X POST
	)

	if [[ $USE_INSECURE_SSL -eq 1 ]]; then
		curl_opts+=(-k)
	fi

	# Attempt logout (ignore errors)
	curl "${curl_opts[@]}" "$logout_url" >/dev/null 2>&1 || true

	# Clean up cookie file
	rm -f "$cookie_file"

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
#   1: Error
main() {
	local cookie_file
	local site_id
	local vpn_data

	# Parse arguments
	parse_args "$@"

	# Check prerequisites
	if ! check_curl_available; then
		exit 1
	fi

	# Authenticate
	log_info "Connecting to UDM at ${UDM_HOST}:${UDM_PORT}..."
	if ! cookie_file=$(authenticate_udm_api); then
		exit 1
	fi

	# Cleanup cookie file on exit
	trap "rm -f '$cookie_file'" EXIT

	log_info "Authentication successful"

	# If --list-sites option is set, list all sites and exit
	if [[ $LIST_SITES_ONLY -eq 1 ]]; then
		log_info "Retrieving list of all sites..."
		if ! list_all_sites "$cookie_file"; then
			exit 1
		fi
		logout_udm_api "$cookie_file"
		trap - EXIT
		return 0
	fi

	# Get site ID
	log_info "Retrieving site ID for site: $SITE_NAME"
	if ! site_id=$(get_site_id "$cookie_file" "$SITE_NAME"); then
		log_error "Site '$SITE_NAME' not found. Use --list-sites to see available sites."
		exit 1
	fi

	log_info "Site ID: $site_id"

	# Get VPN configurations
	log_info "Retrieving site-to-site VPN configurations..."
	if ! vpn_data=$(get_site_to_site_vpns "$cookie_file" "$site_id"); then
		exit 1
	fi

	# Display results
	echo ""
	echo "=== Site-to-Site VPN Configurations ==="
	echo ""
	echo "$vpn_data"
	echo ""

	# Logout
	logout_udm_api "$cookie_file"
	trap - EXIT

	log_info "Done"

	return 0
}

# Run main function
main "$@"
