#!/bin/bash
#
# UDM VPN Monitor Configuration Comparison Tool
# Compares template config file with existing user config file
# Shows new fields in template and deprecated fields in existing config
#
# Version: 0.4.3
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_CONFIG=""
EXISTING_CONFIG=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
	case "$1" in
	-t | --template)
		TEMPLATE_CONFIG="$2"
		shift 2
		;;
	-e | --existing)
		EXISTING_CONFIG="$2"
		shift 2
		;;
	-h | --help)
		cat <<EOF
Usage: $0 [OPTIONS]

UDM VPN Monitor Configuration Comparison Tool
Compares template config file with existing user config file to show:
  - Fields in template that aren't in existing config (new fields you might want to add)
  - Fields in existing config that aren't in template (deprecated/removed fields)

Options:
  -t, --template FILE   Path to template config file (default: auto-detect)
  -e, --existing FILE   Path to existing user config file (default: auto-detect)
  -h, --help            Show this help message

Examples:
  $0
  $0 --template ./vpn-monitor.conf --existing /data/vpn-monitor/vpn-monitor.conf
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

# Auto-detect template config file if not provided
if [[ -z "$TEMPLATE_CONFIG" ]]; then
	TEMPLATE_CONFIG="${SCRIPT_DIR}/vpn-monitor.conf"

	# If not in script directory, try to find it
	if [[ ! -f "$TEMPLATE_CONFIG" ]]; then
		# Try parent directory (if running from scripts/)
		if [[ -f "${SCRIPT_DIR}/../vpn-monitor.conf" ]]; then
			TEMPLATE_CONFIG="${SCRIPT_DIR}/../vpn-monitor.conf"
		fi
	fi
fi

# Auto-detect existing config file if not provided
if [[ -z "$EXISTING_CONFIG" ]]; then
	# Try common installation location first
	if [[ -f "/data/vpn-monitor/vpn-monitor.conf" ]]; then
		EXISTING_CONFIG="/data/vpn-monitor/vpn-monitor.conf"
	# Try script directory
	elif [[ -f "${SCRIPT_DIR}/vpn-monitor.conf" ]]; then
		EXISTING_CONFIG="${SCRIPT_DIR}/vpn-monitor.conf"
	fi
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Get variable value from config file
#
# Extracts the value for a specific variable from a config file.
# Handles quoted and unquoted values.
#
# Arguments:
#   $1: Path to config file
#   $2: Variable name
#
# Returns:
#   0: Variable found
#   1: Variable not found
#
# Output:
#   Prints the value (with quotes removed) to stdout
get_config_value() {
	local config_file="$1"
	local var_name="$2"
	local line
	local value

	if [[ ! -f "$config_file" ]] || [[ ! -r "$config_file" ]]; then
		return 1
	fi

	# Find the variable assignment line
	line=$(grep "^${var_name}=" "$config_file" 2>/dev/null | head -1)

	if [[ -z "$line" ]]; then
		return 1
	fi

	# Extract value after the equals sign
	value="${line#"${var_name}"=}"

	# Remove surrounding quotes (handles both single and double quotes)
	# Trim leading/trailing whitespace first
	value=$(echo "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

	# Remove quotes if present
	if [[ "$value" =~ ^\".*\"$ ]]; then
		value="${value#\"}"
		value="${value%\"}"
	elif [[ "$value" =~ ^\'.*\'$ ]]; then
		value="${value#\'}"
		value="${value%\'}"
	fi

	# Trim whitespace again after quote removal
	value=$(echo "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

	echo "$value"
	return 0
}

# Main function to compare configurations
#
# Compares template config file with existing user config file and reports:
# - New variables (in template but not in existing config)
# - Deprecated variables (in existing config but not in template)
# - Common variables (in both)
#
# Returns:
#   0: Comparison completed successfully
#   1: Error during comparison
main() {
	local new_vars=()
	local deprecated_vars=()
	local common_vars=()
	local template_vars=()
	local existing_vars=()
	local var_name
	local has_differences=0

	echo "Comparing configuration files:"
	echo "  Template:  $TEMPLATE_CONFIG"
	echo "  Existing:  $EXISTING_CONFIG"
	echo ""

	# Check if template config file exists
	if [[ ! -f "$TEMPLATE_CONFIG" ]]; then
		echo -e "${RED}[ERROR]${NC} Template config file not found: $TEMPLATE_CONFIG" >&2
		echo "" >&2
		echo "Please specify the template config file with --template or run this script from the installation directory." >&2
		return 1
	fi

	# Check if existing config file exists
	if [[ ! -f "$EXISTING_CONFIG" ]]; then
		echo -e "${RED}[ERROR]${NC} Existing config file not found: $EXISTING_CONFIG" >&2
		echo "" >&2
		echo "Please specify the existing config file with --existing or ensure it exists at:" >&2
		echo "  /data/vpn-monitor/vpn-monitor.conf" >&2
		return 1
	fi

	# Parse variables from template config file
	local temp_output
	if ! temp_output=$(parse_config_variables "$TEMPLATE_CONFIG"); then
		echo -e "${RED}[ERROR]${NC} Failed to parse template configuration file" >&2
		return 1
	fi

	# Read variable names into array (one per line)
	if [[ -n "$temp_output" ]]; then
		mapfile -t template_vars <<<"$temp_output"
	fi

	# Check for duplicate variables in template
	declare -A template_var_count=()
	local template_duplicates=()
	for var_name in "${template_vars[@]}"; do
		# Initialize to 0 if not set, then increment
		template_var_count["$var_name"]=$((${template_var_count["$var_name"]:-0} + 1))
		if [[ ${template_var_count["$var_name"]} -eq 2 ]]; then
			template_duplicates+=("$var_name")
		fi
	done

	# Parse variables from existing config file
	if ! temp_output=$(parse_config_variables "$EXISTING_CONFIG"); then
		echo -e "${RED}[ERROR]${NC} Failed to parse existing configuration file" >&2
		return 1
	fi

	# Read variable names into array (one per line)
	if [[ -n "$temp_output" ]]; then
		mapfile -t existing_vars <<<"$temp_output"
	fi

	# Check for duplicate variables in existing config
	declare -A existing_var_count=()
	local existing_duplicates=()
	for var_name in "${existing_vars[@]}"; do
		# Initialize to 0 if not set, then increment
		existing_var_count["$var_name"]=$((${existing_var_count["$var_name"]:-0} + 1))
		if [[ ${existing_var_count["$var_name"]} -eq 2 ]]; then
			existing_duplicates+=("$var_name")
		fi
	done

	# Create associative arrays for quick lookup
	# Use unique variable names only (first occurrence) for comparison
	declare -A template_vars_map
	declare -A existing_vars_map

	# Build maps using only first occurrence of each variable
	for var_name in "${template_vars[@]}"; do
		# Only add if not already in map (first occurrence)
		if [[ -z "${template_vars_map[$var_name]:-}" ]]; then
			template_vars_map["$var_name"]=1
		fi
	done

	for var_name in "${existing_vars[@]}"; do
		# Only add if not already in map (first occurrence)
		if [[ -z "${existing_vars_map[$var_name]:-}" ]]; then
			existing_vars_map["$var_name"]=1
		fi
	done

	# Find new variables (in template but not in existing)
	# Iterate through unique template variables only (use map keys to avoid duplicates)
	for var_name in "${!template_vars_map[@]}"; do
		if [[ -z "${existing_vars_map[$var_name]:-}" ]]; then
			new_vars+=("$var_name")
		else
			common_vars+=("$var_name")
		fi
	done

	# Find deprecated variables (in existing but not in template)
	# Iterate through unique existing variables only (use map keys to avoid duplicates)
	for var_name in "${!existing_vars_map[@]}"; do
		if [[ -z "${template_vars_map[$var_name]:-}" ]]; then
			deprecated_vars+=("$var_name")
		fi
	done

	# Report results
	echo "=========================================="
	echo "Configuration Comparison Report"
	echo "=========================================="
	echo ""

	# Report duplicate variables (warnings)
	if [[ ${#template_duplicates[@]} -gt 0 ]]; then
		echo -e "${YELLOW}[!] Duplicate Variables in Template (${#template_duplicates[@]})${NC}"
		echo "The following variables appear multiple times in the template config:"
		echo ""
		for var_name in "${template_duplicates[@]}"; do
			echo -e "  ${YELLOW}*${NC} ${var_name} (appears ${template_var_count[$var_name]} times)"
		done
		echo ""
		echo "Only the first occurrence will be used. Consider removing duplicates."
		echo ""
	fi

	if [[ ${#existing_duplicates[@]} -gt 0 ]]; then
		echo -e "${YELLOW}[!] Duplicate Variables in Existing Config (${#existing_duplicates[@]})${NC}"
		echo "The following variables appear multiple times in your existing config:"
		echo ""
		for var_name in "${existing_duplicates[@]}"; do
			echo -e "  ${YELLOW}*${NC} ${var_name} (appears ${existing_var_count[$var_name]} times)"
		done
		echo ""
		echo "Only the first occurrence will be used. Consider removing duplicates."
		echo ""
	fi

	# Report new variables
	if [[ ${#new_vars[@]} -gt 0 ]]; then
		has_differences=1
		echo -e "${YELLOW}[!] New Settings in Template (${#new_vars[@]})${NC}"
		echo "The following settings are in the template but not in your existing config:"
		echo ""
		for var_name in "${new_vars[@]}"; do
			local default_val
			default_val=$(get_config_value "$TEMPLATE_CONFIG" "$var_name" 2>/dev/null || echo "")
			echo -e "  ${YELLOW}*${NC} ${var_name}"
			if [[ -n "$default_val" ]]; then
				# Check if value needs quoting (contains spaces or special chars)
				if [[ "$default_val" =~ [[:space:]] ]] || [[ "$default_val" =~ [\"\'] ]]; then
					echo "      Template value: \"${default_val}\""
					echo "      Add to your config: ${var_name}=\"${default_val}\""
				else
					echo "      Template value: ${default_val}"
					echo "      Add to your config: ${var_name}=${default_val}"
				fi
			else
				echo "      Template value: (empty)"
				echo "      Add to your config: ${var_name}=\"\""
			fi
			echo ""
		done
	else
		echo -e "${GREEN}[✓]${NC} No new settings in template"
		echo ""
	fi

	# Report deprecated variables
	if [[ ${#deprecated_vars[@]} -gt 0 ]]; then
		has_differences=1
		echo -e "${RED}[!] Deprecated Settings in Existing Config (${#deprecated_vars[@]})${NC}"
		echo "The following settings are in your existing config but not in the template:"
		echo ""
		for var_name in "${deprecated_vars[@]}"; do
			local current_val
			current_val=$(get_config_value "$EXISTING_CONFIG" "$var_name" 2>/dev/null || echo "")
			echo -e "  ${RED}*${NC} ${var_name}"
			if [[ -n "$current_val" ]]; then
				echo "      Current value: ${current_val}"
			fi
			echo "      This setting may be deprecated or removed in the current version."
			echo ""
		done
		echo "You can safely remove these settings from your config file if they're no longer needed."
		echo ""
	else
		echo -e "${GREEN}[✓]${NC} No deprecated settings found"
		echo ""
	fi

	# Summary
	echo "=========================================="
	echo "Summary:"
	echo "  Common settings: ${GREEN}${#common_vars[@]}${NC}"
	if [[ ${#new_vars[@]} -gt 0 ]]; then
		echo "  New settings in template: ${YELLOW}${#new_vars[@]}${NC}"
	fi
	if [[ ${#deprecated_vars[@]} -gt 0 ]]; then
		echo "  Deprecated settings: ${RED}${#deprecated_vars[@]}${NC}"
	fi
	echo ""

	if [[ $has_differences -eq 1 ]]; then
		echo "=========================================="
		echo "Recommendations:"
		echo "=========================================="
		echo ""
		if [[ ${#new_vars[@]} -gt 0 ]]; then
			echo "Consider adding the following to your config file:"
			echo ""
			for var_name in "${new_vars[@]}"; do
				local default_val
				default_val=$(get_config_value "$TEMPLATE_CONFIG" "$var_name" 2>/dev/null || echo "")
				if [[ -n "$default_val" ]]; then
					# Check if value needs quoting
					if [[ "$default_val" =~ [[:space:]] ]] || [[ "$default_val" =~ [\"\'] ]]; then
						echo "${var_name}=\"${default_val}\""
					else
						echo "${var_name}=${default_val}"
					fi
				else
					echo "${var_name}=\"\""
				fi
			done
			echo ""
		fi
		if [[ ${#deprecated_vars[@]} -gt 0 ]]; then
			echo "You may want to remove these deprecated settings:"
			echo ""
			for var_name in "${deprecated_vars[@]}"; do
				echo "# ${var_name}=..."
			done
			echo ""
		fi
		return 0
	else
		echo -e "${GREEN}Your configuration file is up to date with the template!${NC}"
		return 0
	fi
}

# Run main function
main "$@"
