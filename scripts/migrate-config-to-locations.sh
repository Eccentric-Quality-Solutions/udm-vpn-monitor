#!/bin/bash
#
# Migration script to convert old EXTERNAL_PEER_IPS/INTERNAL_PEER_IPS format
# to new location-based configuration format
#
# Version: 1.0.0
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# Allow CONFIG_FILE to be overridden via environment variable
CONFIG_FILE="${CONFIG_FILE:-${PROJECT_ROOT}/vpn-monitor.conf}"

# Source library modules for validation (optional - script works without them)
# shellcheck source=lib/logging.sh
source "${PROJECT_ROOT}/lib/logging.sh" 2>/dev/null || true
# shellcheck source=lib/config.sh
source "${PROJECT_ROOT}/lib/config.sh" 2>/dev/null || true

# Function to validate IP address format
validate_ip() {
	local ip="$1"
	if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		return 0
	fi
	# Check IPv6 format (simplified)
	if [[ "$ip" =~ : ]]; then
		return 0
	fi
	return 1
}

# Function to read old config values
# Note: sanitize_location_name() is available from common.sh (sourced via config.sh)
read_old_config() {
	local config_file="$1"
	local external_ips=""
	local internal_ips=""

	# Read config file and extract EXTERNAL_PEER_IPS and INTERNAL_PEER_IPS
	while IFS='=' read -r key value || [[ -n "$key" ]]; do
		# Skip comments and empty lines
		[[ "$key" =~ ^# ]] && continue
		[[ -z "$key" ]] && continue

		# Trim whitespace from key
		key=$(echo "$key" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

		# Remove quotes from value and trim whitespace
		value=$(echo "$value" | sed "s/^[\"']//" | sed "s/[\"']$//" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

		case "$key" in
		EXTERNAL_PEER_IPS)
			external_ips="$value"
			;;
		INTERNAL_PEER_IPS)
			internal_ips="$value"
			;;
		esac
	done <"$config_file" || true

	echo "$external_ips|$internal_ips"
}

# Function to generate location names
generate_location_names() {
	local count="$1"
	local mode="${2:-default}" # default, interactive, csv
	local csv_file="${3:-}"
	local -a names=()

	case "$mode" in
	default)
		# Generate default names: LOCATION_1, LOCATION_2, etc.
		for ((i = 1; i <= count; i++)); do
			names+=("LOCATION_$i")
		done
		;;
	interactive)
		# Prompt user for each location name
		echo "Enter location names (one per line, press Enter to finish):"
		for ((i = 1; i <= count; i++)); do
			read -r -p "Location $i name: " name
			if [[ -z "$name" ]]; then
				name="LOCATION_$i"
			fi
			names+=("$(sanitize_location_name "$name")")
		done
		;;
	csv)
		# Read from CSV file (format: index,name)
		if [[ ! -f "$csv_file" ]]; then
			echo "ERROR: CSV file not found: $csv_file" >&2
			return 1
		fi
		local -A csv_names=()
		while IFS=',' read -r idx name || [[ -n "$idx" ]]; do
			[[ -z "$idx" ]] && continue
			csv_names["$idx"]="$(sanitize_location_name "$name")"
		done <"$csv_file"

		# Generate names from CSV, fallback to default if missing
		for ((i = 1; i <= count; i++)); do
			if [[ -n "${csv_names[$i]:-}" ]]; then
				names+=("${csv_names[$i]}")
			else
				names+=("LOCATION_$i")
			fi
		done
		;;
	esac

	# Print names (one per line)
	for name in "${names[@]}"; do
		echo "$name"
	done
}

# Function to migrate config
migrate_config() {
	local config_file="$1"
	local mode="${2:-default}"
	local csv_file="${3:-}"

	# Read old config
	local old_config
	if ! old_config=$(read_old_config "$config_file"); then
		echo "ERROR: Failed to read old config" >&2
		return 1
	fi

	local external_ips="${old_config%%|*}"
	local internal_ips="${old_config#*|}"

	# Validate old config exists
	if [[ -z "$external_ips" ]]; then
		echo "ERROR: EXTERNAL_PEER_IPS not found in config file" >&2
		return 1
	fi

	# Parse external IPs into array
	local IFS=' '
	local -a external_array
	read -ra external_array <<<"$external_ips"
	local external_count=${#external_array[@]}

	# Parse internal IPs into array (if provided)
	local -a internal_array=()
	if [[ -n "$internal_ips" ]]; then
		read -ra internal_array <<<"$internal_ips"
	fi

	# Generate location names
	local -a location_names
	while IFS= read -r name; do
		location_names+=("$name")
	done < <(generate_location_names "$external_count" "$mode" "$csv_file")

	# Create backup
	local backup_file
	backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
	cp "$config_file" "$backup_file"
	echo "Backup created: $backup_file"

	# Read entire config file
	local temp_file
	temp_file=$(mktemp)

	# Write new config (preserve other settings, replace old format)
	while IFS= read -r line || [[ -n "$line" ]]; do
		# Skip old format lines
		if [[ "$line" =~ ^EXTERNAL_PEER_IPS= ]] || [[ "$line" =~ ^INTERNAL_PEER_IPS= ]]; then
			continue
		fi

		# Write line as-is
		echo "$line" >>"$temp_file"
	done <"$config_file"

	# Append location-based config
	{
		echo ""
		echo "# Location-based VPN configuration (migrated from EXTERNAL_PEER_IPS/INTERNAL_PEER_IPS)"
		echo "# Migration date: $(date)"
		echo ""
	} >>"$temp_file"

	for ((i = 0; i < external_count; i++)); do
		local location_name="${location_names[$i]}"
		local external_ip="${external_array[$i]}"

		# Validate external IP
		if ! validate_ip "$external_ip"; then
			echo "WARNING: Skipping invalid external IP: $external_ip" >&2
			continue
		fi

		# Get corresponding internal IP(s)
		# If there are more internal IPs than external IPs, associate remaining IPs with last external IP
		local internal_ip=""
		if [[ ${#internal_array[@]} -gt 0 ]]; then
			if [[ $i -lt ${#internal_array[@]} ]]; then
				# Map internal IPs to external IPs by index
				# If this is the last external IP and there are more internal IPs, include all remaining
				if [[ $i -eq $((external_count - 1)) ]] && [[ ${#internal_array[@]} -gt $external_count ]]; then
					# Include all internal IPs from index i onwards as space-separated string
					local -a remaining_ips=()
					for ((j = i; j < ${#internal_array[@]}; j++)); do
						if [[ -n "${internal_array[$j]}" ]]; then
							remaining_ips+=("${internal_array[$j]}")
						fi
					done
					if [[ ${#remaining_ips[@]} -gt 0 ]]; then
						internal_ip="${remaining_ips[*]}"
					fi
				else
					# Single internal IP mapped to this external IP
					if [[ -n "${internal_array[$i]}" ]]; then
						internal_ip="${internal_array[$i]}"
					fi
				fi
			fi
		fi

		# Write location config
		echo "LOCATION_${location_name}_EXTERNAL=\"$external_ip\"" >>"$temp_file"
		if [[ -n "$internal_ip" ]]; then
			echo "LOCATION_${location_name}_INTERNAL=\"$internal_ip\"" >>"$temp_file"
		else
			echo "LOCATION_${location_name}_INTERNAL=\"\"" >>"$temp_file"
		fi
		echo "" >>"$temp_file"
	done

	# Replace config file
	mv "$temp_file" "$config_file"

	echo "Migration completed successfully!"
	echo ""
	echo "Note: Old state files will not be migrated. New state files will be created"
	echo "      as locations are monitored. Old state files can be manually cleaned up"
	echo "      from /data/vpn-monitor/state/ if desired."
}

# Main function
main() {
	local mode="default"
	local csv_file=""

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--interactive | -i)
			mode="interactive"
			shift
			;;
		--csv)
			mode="csv"
			csv_file="$2"
			shift 2
			;;
		--help | -h)
			echo "Usage: $0 [--interactive|--csv FILE]"
			echo ""
			echo "Migrates vpn-monitor.conf from old format (EXTERNAL_PEER_IPS/INTERNAL_PEER_IPS)"
			echo "to new location-based format (LOCATION_*_EXTERNAL/LOCATION_*_INTERNAL)."
			echo ""
			echo "Options:"
			echo "  --interactive, -i    Prompt for location names interactively"
			echo "  --csv FILE           Read location names from CSV file (format: index,name)"
			echo "  --help, -h           Show this help message"
			echo ""
			echo "Default: Generates location names automatically (LOCATION_1, LOCATION_2, etc.)"
			exit 0
			;;
		*)
			echo "ERROR: Unknown option: $1" >&2
			echo "Use --help for usage information" >&2
			exit 1
			;;
		esac
	done

	# Check config file exists
	if [[ ! -f "$CONFIG_FILE" ]]; then
		echo "ERROR: Config file not found: $CONFIG_FILE" >&2
		exit 1
	fi

	# Check for old format
	local old_config
	old_config=$(read_old_config "$CONFIG_FILE")
	local external_ips="${old_config%%|*}"

	if [[ -z "$external_ips" ]]; then
		echo "ERROR: Old format (EXTERNAL_PEER_IPS) not found in config file" >&2
		echo "Config file may already be migrated or in incorrect format." >&2
		exit 1
	fi

	# Perform migration
	migrate_config "$CONFIG_FILE" "$mode" "$csv_file"
}

# Run main function
main "$@"
