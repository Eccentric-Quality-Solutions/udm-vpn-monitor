#!/bin/bash
#
# UDM VPN Monitor Configuration Validator
# Checks configuration file against schema and reports missing/deprecated settings
#
# Version: 0.3.0
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
	case "$1" in
	-c | --config)
		CONFIG_FILE="$2"
		shift 2
		;;
	-h | --help)
		cat <<EOF
Usage: $0 [OPTIONS]

UDM VPN Monitor Configuration Validator
Checks configuration file against schema and reports missing/deprecated settings.

Options:
  -c, --config FILE    Path to config file (default: auto-detect)
  -h, --help           Show this help message

Examples:
  $0
  $0 --config /data/vpn-monitor/vpn-monitor.conf
EOF
		exit 0
		;;
	*)
		echo "Unknown option: $1" >&2
		echo "Use --help for usage information" >&2
		exit 1
		;;
	esac
done

# Auto-detect config file if not provided
if [[ -z "$CONFIG_FILE" ]]; then
	CONFIG_FILE="${SCRIPT_DIR}/vpn-monitor.conf"

	# Default config file path if not in script directory
	if [[ ! -f "$CONFIG_FILE" ]]; then
		# Try common installation location
		if [[ -f "/data/vpn-monitor/vpn-monitor.conf" ]]; then
			CONFIG_FILE="/data/vpn-monitor/vpn-monitor.conf"
			SCRIPT_DIR="/data/vpn-monitor"
		fi
	fi
fi

# Source library modules (needed for schema)
# shellcheck source=lib/config_schema.sh
if [[ -f "${SCRIPT_DIR}/lib/config_schema.sh" ]]; then
	source "${SCRIPT_DIR}/lib/config_schema.sh"
else
	echo "Error: config_schema.sh not found. Run this script from the installation directory." >&2
	exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse config file to extract variable names
#
# Reads the config file and extracts all variable names that are set.
# Only extracts valid VAR=value lines, ignoring comments and empty lines.
#
# Arguments:
#   $1: Path to config file
#
# Returns:
#   0: Success
#   1: Config file not found or unreadable
#
# Output:
#   Prints variable names (one per line) to stdout
parse_config_variables() {
	local config_file="$1"
	local line
	local var_name

	if [[ ! -f "$config_file" ]] || [[ ! -r "$config_file" ]]; then
		return 1
	fi

	# Read config file line by line
	while IFS= read -r line || [[ -n "$line" ]]; do
		# Skip empty lines
		if [[ -z "${line// /}" ]]; then
			continue
		fi

		# Skip comment lines (lines starting with #)
		if [[ "$line" =~ ^[[:space:]]*# ]]; then
			continue
		fi

		# Remove leading/trailing whitespace
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"

		# Skip empty lines after trimming
		if [[ -z "$line" ]]; then
			continue
		fi

		# Parse variable assignment: VAR=value
		if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
			var_name="${BASH_REMATCH[1]}"
			echo "$var_name"
		fi
	done <"$config_file"

	return 0
}

# Get default value for a config variable
#
# Extracts the default value from schema, formatting it appropriately.
#
# Arguments:
#   $1: Variable name
#
# Output:
#   Prints default value (or empty string if none)
get_formatted_default() {
	local var_name="$1"
	local default_val
	default_val=$(get_config_default "$var_name" 2>/dev/null || echo "")

	if [[ -n "$default_val" ]]; then
		# Check if value needs quoting (contains spaces or special chars)
		if [[ "$default_val" =~ [[:space:]] ]] || [[ "$default_val" =~ [\"\'] ]]; then
			echo "\"${default_val}\""
		else
			echo "$default_val"
		fi
	else
		echo ""
	fi
}

# Main function to check configuration
#
# Compares config file against schema and reports:
# - Missing variables (in schema but not in config)
# - Deprecated variables (in config but not in schema)
# - Valid variables (in both)
#
# Returns:
#   0: Config is valid (may have warnings)
#   1: Config file not found
main() {
	local missing_vars=()
	local deprecated_vars=()
	local valid_vars=()
	local config_vars=()
	local var_name
	local has_issues=0

	echo "Checking configuration file: $CONFIG_FILE"
	echo ""

	# Check if config file exists
	if [[ ! -f "$CONFIG_FILE" ]]; then
		echo -e "${RED}[ERROR]${NC} Configuration file not found: $CONFIG_FILE"
		echo ""
		echo "Please ensure the config file exists or run this script from the installation directory."
		return 1
	fi

	# Parse variables from config file
	# Use mapfile to safely read output into array (avoids word splitting issues)
	local temp_output
	if ! temp_output=$(parse_config_variables "$CONFIG_FILE"); then
		echo -e "${RED}[ERROR]${NC} Failed to parse configuration file"
		return 1
	fi

	# Read variable names into array (one per line)
	local config_vars=()
	if [[ -n "$temp_output" ]]; then
		mapfile -t config_vars <<<"$temp_output"
	fi

	# Create associative array for quick lookup
	declare -A config_vars_map
	for var_name in "${config_vars[@]}"; do
		config_vars_map["$var_name"]=1
	done

	# Check for missing variables (in schema but not in config)
	echo -e "${BLUE}Checking for missing settings...${NC}"
	for var_name in "${!CONFIG_SCHEMA[@]}"; do
		if [[ -z "${config_vars_map[$var_name]:-}" ]]; then
			missing_vars+=("$var_name")
		else
			valid_vars+=("$var_name")
		fi
	done

	# Check for deprecated variables (in config but not in schema)
	echo -e "${BLUE}Checking for deprecated settings...${NC}"
	for var_name in "${config_vars[@]}"; do
		if ! get_config_schema "$var_name" >/dev/null 2>&1; then
			deprecated_vars+=("$var_name")
		fi
	done

	# Report results
	echo ""
	echo "=========================================="
	echo "Configuration Validation Report"
	echo "=========================================="
	echo ""

	# Report missing variables
	if [[ ${#missing_vars[@]} -gt 0 ]]; then
		has_issues=1
		echo -e "${YELLOW}[!] Missing Settings (${#missing_vars[@]})${NC}"
		echo "The following settings are not in your config file but are available:"
		echo ""
		for var_name in "${missing_vars[@]}"; do
			local default_val
			default_val=$(get_formatted_default "$var_name")
			local schema
			schema=$(get_config_schema "$var_name")
			local required
			IFS='|' read -r required _ _ _ <<<"$schema"

			if [[ "$required" == "required" ]]; then
				echo -e "  ${RED}*${NC} ${var_name} (REQUIRED)"
			else
				echo -e "  ${YELLOW}*${NC} ${var_name} (optional)"
			fi

			if [[ -n "$default_val" ]]; then
				echo "      Default: ${var_name}=${default_val}"
			else
				echo "      Default: (no default)"
			fi
			echo ""
		done
	else
		echo -e "${GREEN}[✓]${NC} All expected settings are present"
		echo ""
	fi

	# Report deprecated variables
	if [[ ${#deprecated_vars[@]} -gt 0 ]]; then
		has_issues=1
		echo -e "${RED}[!] Deprecated Settings (${#deprecated_vars[@]})${NC}"
		echo "The following settings are in your config file but are no longer used:"
		echo ""
		for var_name in "${deprecated_vars[@]}"; do
			echo "  - ${var_name}"
		done
		echo ""
		echo "You can safely remove these settings from your config file."
		echo ""
	else
		echo -e "${GREEN}[✓]${NC} No deprecated settings found"
		echo ""
	fi

	# Summary
	echo "=========================================="
	echo "Summary:"
	echo "  Valid settings: ${GREEN}${#valid_vars[@]}${NC}"
	if [[ ${#missing_vars[@]} -gt 0 ]]; then
		echo "  Missing settings: ${YELLOW}${#missing_vars[@]}${NC}"
	fi
	if [[ ${#deprecated_vars[@]} -gt 0 ]]; then
		echo "  Deprecated settings: ${RED}${#deprecated_vars[@]}${NC}"
	fi
	echo ""

	if [[ $has_issues -eq 1 ]]; then
		echo "=========================================="
		echo "Recommendations:"
		echo "=========================================="
		echo ""
		if [[ ${#missing_vars[@]} -gt 0 ]]; then
			echo "Add the following to your config file:"
			echo ""
			for var_name in "${missing_vars[@]}"; do
				local default_val
				default_val=$(get_formatted_default "$var_name")
				if [[ -n "$default_val" ]]; then
					echo "${var_name}=${default_val}"
				else
					echo "# ${var_name}="
				fi
			done
			echo ""
		fi
		if [[ ${#deprecated_vars[@]} -gt 0 ]]; then
			echo "Remove the following from your config file:"
			echo ""
			for var_name in "${deprecated_vars[@]}"; do
				echo "# ${var_name}=..."
			done
			echo ""
		fi
		return 1
	else
		echo -e "${GREEN}Configuration file is up to date!${NC}"
		return 0
	fi
}

# Run main function
main "$@"
