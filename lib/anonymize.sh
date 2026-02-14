#!/bin/bash
#
# Unified Anonymization Library for UDM VPN Monitor
# Provides shared anonymization functions for IP addresses, interfaces, locations,
# MAC addresses, hostnames, and ipset set names with unified mapping support.
#
# Version: 0.8.1
#
# This library provides:
# - Core anonymization functions (hash_string, anonymize_*)
# - Mapping file management (load, save, get_or_create)
# - Extraction functions for different file formats
# - Unified mapping arrays for consistency across all anonymization scripts
#

# Interface name prefixes for anonymization (common network interface patterns)
readonly INTERFACE_PREFIXES=(
	"eth" "ens" "enp" "eno" "wlan" "wlp" "br" "bond" "vlan" "tun" "tap"
	"ppp" "lo" "docker" "veth" "virbr" "vmnet" "wg" "ipsec"
)

# City names for location anonymization (common US cities)
readonly CITY_NAMES=(
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

# Global mapping arrays (declared as associative arrays)
# These are populated when mapping files are loaded or when anonymization occurs
declare -gA ANON_IPV4_MAP
declare -gA ANON_IPV6_MAP
declare -gA ANON_INTERFACE_MAP
declare -gA ANON_LOCATION_MAP
declare -gA ANON_SET_NAME_MAP
declare -gA ANON_MAC_MAP
declare -gA ANON_HOSTNAME_MAP

# Generate deterministic hash from string
#
# Creates a deterministic numeric hash from a string input.
# Used to ensure consistent mapping of IPs and identifiers.
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

# Anonymize IPv6 address
#
# Maps an IPv6 address to a consistent anonymized address in the fc00::/7 range (ULA).
# Uses deterministic hashing to ensure same input always produces same output.
#
# Arguments:
#   $1: Original IPv6 address
#
# Returns:
#   0: Success
#
# Output:
#   Prints anonymized IPv6 address to stdout
anonymize_ipv6() {
	local original_ip="$1"
	local hash
	hash=$(hash_string "$original_ip")

	# Map to fc00::/7 range (ULA - Unique Local Addresses)
	# Use hash to generate consistent hextets
	# Format: fc00:xxxx:xxxx:xxxx:xxxx:xxxx:xxxx:xxxx
	local hextet1="fc00"
	local hextet2=$(printf "%04x" $(((hash / 268435456) % 65536)))
	local hextet3=$(printf "%04x" $(((hash / 4096) % 65536)))
	local hextet4=$(printf "%04x" $((hash % 65536)))
	local hextet5=$(printf "%04x" $(((hash * 7 / 268435456) % 65536)))
	local hextet6=$(printf "%04x" $(((hash * 11 / 4096) % 65536)))
	local hextet7=$(printf "%04x" $(((hash * 13) % 65536)))
	local hextet8=$(printf "%04x" $(((hash * 17 / 256) % 65536)))

	echo "${hextet1}:${hextet2}:${hextet3}:${hextet4}:${hextet5}:${hextet6}:${hextet7}:${hextet8}"
}

# Anonymize interface name
#
# Maps an interface name to a consistent anonymized name.
# Uses deterministic hashing to ensure same input always produces same output.
#
# Arguments:
#   $1: Original interface name
#
# Returns:
#   0: Success
#
# Output:
#   Prints anonymized interface name to stdout
anonymize_interface() {
	local original_iface="$1"
	local hash
	hash=$(hash_string "$original_iface")

	# Special case: lo -> lo (keep loopback as is)
	if [[ "$original_iface" == "lo" ]]; then
		echo "lo"
		return 0
	fi

	# Determine prefix based on hash
	local prefix_index=$((hash % ${#INTERFACE_PREFIXES[@]}))
	local prefix="${INTERFACE_PREFIXES[$prefix_index]}"

	# Generate numeric suffix (0-9999)
	local suffix=$((hash % 10000))

	echo "${prefix}${suffix}"
}

# Anonymize location name
#
# Maps a location name to a consistent anonymized city name.
# Uses deterministic hashing to ensure same input always produces same output.
#
# Arguments:
#   $1: Original location name
#
# Returns:
#   0: Success
#
# Output:
#   Prints anonymized location name to stdout
anonymize_location() {
	local original_location="$1"
	local hash
	hash=$(hash_string "$original_location")

	# Map to city name based on hash
	local city_index=$((hash % ${#CITY_NAMES[@]}))
	echo "${CITY_NAMES[$city_index]}"
}

# Anonymize ipset set name
#
# Maps an ipset set name to a consistent anonymized name.
# Uses deterministic hashing to ensure same input always produces same output.
#
# Arguments:
#   $1: Original set name
#
# Returns:
#   0: Success
#
# Output:
#   Prints anonymized set name to stdout (format: SET_<number>)
anonymize_set_name() {
	local original_set="$1"
	local hash
	hash=$(hash_string "$original_set")

	# Generate SET_<number> format where number is based on hash
	# Use modulo to keep numbers reasonable (0-999999)
	local set_number=$((hash % 1000000))
	echo "SET_${set_number}"
}

# Anonymize MAC address
#
# Maps a MAC address to a consistent anonymized MAC in the locally-administered range (02:xx:xx:xx:xx:xx).
# Uses deterministic hashing to ensure same input always produces same output.
#
# Arguments:
#   $1: Original MAC address (format: aa:bb:cc:dd:ee:ff)
#
# Returns:
#   0: Success
#
# Output:
#   Prints anonymized MAC address to stdout
anonymize_mac_address() {
	local original_mac="$1"
	local hash
	hash=$(hash_string "$original_mac")

	# Map to locally-administered MAC range (02:xx:xx:xx:xx:xx)
	# First octet is always 02 (locally administered, unicast)
	local octet1="02"
	# Remaining octets based on hash
	local octet2=$(printf "%02x" $(((hash / 16777216) % 256)))
	local octet3=$(printf "%02x" $(((hash / 65536) % 256)))
	local octet4=$(printf "%02x" $(((hash / 256) % 256)))
	local octet5=$(printf "%02x" $((hash % 256)))
	# Use a different part of hash for last octet to avoid collisions
	local octet6=$(printf "%02x" $(((hash * 7) % 256)))

	echo "${octet1}:${octet2}:${octet3}:${octet4}:${octet5}:${octet6}"
}

# Anonymize hostname/FQDN
#
# Maps a hostname or FQDN to a consistent anonymized hostname.
# Uses deterministic hashing to ensure same input always produces same output.
#
# Arguments:
#   $1: Original hostname/FQDN
#
# Returns:
#   0: Success
#
# Output:
#   Prints anonymized hostname to stdout (format: host-<number>.local)
anonymize_hostname() {
	local original_hostname="$1"
	local hash
	hash=$(hash_string "$original_hostname")

	# Generate host-<number>.local format
	# Use modulo to keep numbers reasonable (0-999999)
	local host_number=$((hash % 1000000))
	echo "host-${host_number}.local"
}

# Get or create IPv4 mapping
#
# Returns existing mapping if available, otherwise creates new one and stores it.
#
# Arguments:
#   $1: Original IPv4 address (with optional CIDR)
#
# Returns:
#   0: Success
#
# Output:
#   Prints anonymized IPv4 address to stdout
get_or_create_ipv4_mapping() {
	local original="$1"
	if [[ -n "${ANON_IPV4_MAP[$original]:-}" ]]; then
		echo "${ANON_IPV4_MAP[$original]}"
	else
		# Extract base IP (without CIDR) for anonymization
		local base_ip="${original%%/*}"
		local anonymized_base
		anonymized_base=$(anonymize_ipv4 "$base_ip")

		# Preserve CIDR notation if present
		if [[ "$original" =~ / ]]; then
			local cidr="${original#*/}"
			# If original IP ends in .0 and has network CIDR (not /32 which is a host),
			# normalize anonymized network to .0 for better readability
			if [[ "$base_ip" =~ \.0$ ]] && [[ "$cidr" != "32" ]]; then
				# Normalize to network address: replace last octet with 0
				local normalized_anon="${anonymized_base%.*}.0"
				ANON_IPV4_MAP["$original"]="${normalized_anon}/${cidr}"
				echo "${normalized_anon}/${cidr}"
			else
				ANON_IPV4_MAP["$original"]="${anonymized_base}/${cidr}"
				echo "${anonymized_base}/${cidr}"
			fi
		else
			ANON_IPV4_MAP["$original"]="$anonymized_base"
			echo "$anonymized_base"
		fi
	fi
}

# Get or create IPv6 mapping
#
# Returns existing mapping if available, otherwise creates new one and stores it.
#
# Arguments:
#   $1: Original IPv6 address (with optional CIDR)
#
# Returns:
#   0: Success
#
# Output:
#   Prints anonymized IPv6 address to stdout
get_or_create_ipv6_mapping() {
	local original="$1"
	if [[ -n "${ANON_IPV6_MAP[$original]:-}" ]]; then
		echo "${ANON_IPV6_MAP[$original]}"
	else
		# Extract base IP (without CIDR) for anonymization
		local base_ip="${original%%/*}"
		local anonymized_base
		anonymized_base=$(anonymize_ipv6 "$base_ip")

		# Preserve CIDR notation if present
		if [[ "$original" =~ / ]]; then
			local cidr="${original#*/}"
			ANON_IPV6_MAP["$original"]="${anonymized_base}/${cidr}"
			echo "${anonymized_base}/${cidr}"
		else
			ANON_IPV6_MAP["$original"]="$anonymized_base"
			echo "$anonymized_base"
		fi
	fi
}

# Get or create interface mapping
#
# Returns existing mapping if available, otherwise creates new one and stores it.
#
# Arguments:
#   $1: Original interface name
#
# Returns:
#   0: Success
#
# Output:
#   Prints anonymized interface name to stdout
get_or_create_interface_mapping() {
	local original="$1"
	if [[ -n "${ANON_INTERFACE_MAP[$original]:-}" ]]; then
		echo "${ANON_INTERFACE_MAP[$original]}"
	else
		local anonymized
		anonymized=$(anonymize_interface "$original")
		ANON_INTERFACE_MAP["$original"]="$anonymized"
		echo "$anonymized"
	fi
}

# Check if a city name is already used as a value in ANON_LOCATION_MAP.
# ANON_LOCATION_MAP keys are original location names; values are anonymized city names.
# We must check values, not keys, to avoid hash collisions (different originals → same city).
#
# Arguments:
#   $1: City name to check (e.g. "CHICAGO")
#
# Returns:
#   0: City is already used as a value
#   1: City is not used
_is_location_city_used() {
	local city="$1"
	local orig
	for orig in "${!ANON_LOCATION_MAP[@]}"; do
		if [[ "${ANON_LOCATION_MAP[$orig]}" == "$city" ]]; then
			return 0
		fi
	done
	return 1
}

# Get or create location mapping
#
# Returns existing mapping if available, otherwise creates new one and stores it.
# Tracks used city names to ensure uniqueness (checks VALUES in map, not keys).
#
# Arguments:
#   $1: Original location name
#
# Returns:
#   0: Success
#
# Output:
#   Prints anonymized location name to stdout
get_or_create_location_mapping() {
	local original="$1"
	if [[ -n "${ANON_LOCATION_MAP[$original]:-}" ]]; then
		echo "${ANON_LOCATION_MAP[$original]}"
	else
		# Use hash to find starting city, then find next available
		local hash
		hash=$(hash_string "$original")
		local start_index=$((hash % ${#CITY_NAMES[@]}))
		local city_index=$start_index
		local anonymized_city
		local attempts=0

		# Find next available city name (with safety limit)
		# Must check if city is already used as a VALUE, not as a key
		while _is_location_city_used "${CITY_NAMES[$city_index]}" && [[ $attempts -lt ${#CITY_NAMES[@]} ]]; do
			city_index=$(((city_index + 1) % ${#CITY_NAMES[@]}))
			attempts=$((attempts + 1))
		done

		# If all cities are used, append number for uniqueness
		if [[ $attempts -ge ${#CITY_NAMES[@]} ]]; then
			local suffix=1
			local candidate
			while true; do
				candidate="${CITY_NAMES[$start_index]}_${suffix}"
				if ! _is_location_city_used "$candidate"; then
					break
				fi
				suffix=$((suffix + 1))
			done
			anonymized_city="$candidate"
		else
			anonymized_city="${CITY_NAMES[$city_index]}"
		fi

		ANON_LOCATION_MAP["$original"]="$anonymized_city"
		echo "$anonymized_city"
	fi
}

# Get or create set name mapping
#
# Returns existing mapping if available, otherwise creates new one and stores it.
#
# Arguments:
#   $1: Original set name
#
# Returns:
#   0: Success
#
# Output:
#   Prints anonymized set name to stdout
get_or_create_set_name_mapping() {
	local original="$1"
	if [[ -n "${ANON_SET_NAME_MAP[$original]:-}" ]]; then
		echo "${ANON_SET_NAME_MAP[$original]}"
	else
		local anonymized
		anonymized=$(anonymize_set_name "$original")
		ANON_SET_NAME_MAP["$original"]="$anonymized"
		echo "$anonymized"
	fi
}

# Get or create MAC address mapping
#
# Returns existing mapping if available, otherwise creates new one and stores it.
#
# Arguments:
#   $1: Original MAC address
#
# Returns:
#   0: Success
#
# Output:
#   Prints anonymized MAC address to stdout
get_or_create_mac_mapping() {
	local original="$1"
	if [[ -n "${ANON_MAC_MAP[$original]:-}" ]]; then
		echo "${ANON_MAC_MAP[$original]}"
	else
		local anonymized
		anonymized=$(anonymize_mac_address "$original")
		ANON_MAC_MAP["$original"]="$anonymized"
		echo "$anonymized"
	fi
}

# Get or create hostname mapping
#
# Returns existing mapping if available, otherwise creates new one and stores it.
#
# Arguments:
#   $1: Original hostname/FQDN
#
# Returns:
#   0: Success
#
# Output:
#   Prints anonymized hostname to stdout
get_or_create_hostname_mapping() {
	local original="$1"
	if [[ -n "${ANON_HOSTNAME_MAP[$original]:-}" ]]; then
		echo "${ANON_HOSTNAME_MAP[$original]}"
	else
		local anonymized
		anonymized=$(anonymize_hostname "$original")
		ANON_HOSTNAME_MAP["$original"]="$anonymized"
		echo "$anonymized"
	fi
}

# Load mapping file
#
# Loads existing mappings from a file into the global mapping arrays.
# File format is human-readable with sections for each mapping type.
#
# Arguments:
#   $1: Mapping file path
#
# Returns:
#   0: Success
#   1: Error (file not found or invalid format)
load_mapping_file() {
	local mapping_file="$1"

	if [[ ! -f "$mapping_file" ]]; then
		return 1
	fi

	if [[ ! -r "$mapping_file" ]]; then
		return 1
	fi

	local current_section=""

	while IFS= read -r line || [[ -n "$line" ]]; do
		# Skip comments and empty lines
		[[ "$line" =~ ^# ]] && continue
		[[ -z "${line// /}" ]] && continue

		# Detect section headers
		if [[ "$line" =~ ^IPv4\ Addresses: ]]; then
			current_section="ipv4"
			continue
		elif [[ "$line" =~ ^IPv6\ Addresses: ]]; then
			current_section="ipv6"
			continue
		elif [[ "$line" =~ ^Interfaces: ]]; then
			current_section="interface"
			continue
		elif [[ "$line" =~ ^Locations: ]]; then
			current_section="location"
			continue
		elif [[ "$line" =~ ^Set\ Names: ]]; then
			current_section="set_name"
			continue
		elif [[ "$line" =~ ^MAC\ Addresses: ]]; then
			current_section="mac"
			continue
		elif [[ "$line" =~ ^Hostnames: ]]; then
			current_section="hostname"
			continue
		elif [[ "$line" =~ ^-+$ ]]; then
			# Section separator line
			continue
		fi

		# Parse mapping line: "original -> anonymized"
		# Use a variable to avoid issues with -> in regex
		local mapping_pattern='^([^[:space:]]+)[[:space:]]*->[[:space:]]*([^[:space:]]+)$'
		if [[ "$line" =~ $mapping_pattern ]]; then
			local original="${BASH_REMATCH[1]}"
			local anonymized="${BASH_REMATCH[2]}"

			case "$current_section" in
			ipv4)
				ANON_IPV4_MAP["$original"]="$anonymized"
				;;
			ipv6)
				ANON_IPV6_MAP["$original"]="$anonymized"
				;;
			interface)
				ANON_INTERFACE_MAP["$original"]="$anonymized"
				;;
			location)
				ANON_LOCATION_MAP["$original"]="$anonymized"
				;;
			set_name)
				ANON_SET_NAME_MAP["$original"]="$anonymized"
				;;
			mac)
				ANON_MAC_MAP["$original"]="$anonymized"
				;;
			hostname)
				ANON_HOSTNAME_MAP["$original"]="$anonymized"
				;;
			esac
		fi
	done <"$mapping_file"

	return 0
}

# Save mapping file
#
# Saves all mappings from global arrays to a human-readable file.
#
# Arguments:
#   $1: Mapping file path
#
# Returns:
#   0: Success
#   1: Error
save_mapping_file() {
	local mapping_file="$1"
	local timestamp
	timestamp=$(date +"%Y-%m-%d %H:%M:%S")

	# Create output directory if needed
	local mapping_dir
	mapping_dir=$(dirname "$mapping_file")
	if [[ -n "$mapping_dir" ]] && [[ "$mapping_dir" != "." ]]; then
		mkdir -p "$mapping_dir" || return 1
	fi

	{
		echo "# Unified Anonymization Mapping"
		echo "# Generated: $timestamp"
		echo ""

		# IPv4 Addresses
		set +u
		if [[ ${#ANON_IPV4_MAP[@]} -gt 0 ]]; then
			echo "IPv4 Addresses:"
			echo "--------------------------------------------------"
			# Sort keys for consistent output
			printf '%s\n' "${!ANON_IPV4_MAP[@]}" | sort | while IFS= read -r key; do
				echo "$key -> ${ANON_IPV4_MAP[$key]}"
			done
			echo ""
		fi
		set -u

		# IPv6 Addresses
		set +u
		if [[ ${#ANON_IPV6_MAP[@]} -gt 0 ]]; then
			echo "IPv6 Addresses:"
			echo "--------------------------------------------------"
			printf '%s\n' "${!ANON_IPV6_MAP[@]}" | sort | while IFS= read -r key; do
				echo "$key -> ${ANON_IPV6_MAP[$key]}"
			done
			echo ""
		fi
		set -u

		# Interfaces
		set +u
		if [[ ${#ANON_INTERFACE_MAP[@]} -gt 0 ]]; then
			echo "Interfaces:"
			echo "--------------------------------------------------"
			printf '%s\n' "${!ANON_INTERFACE_MAP[@]}" | sort | while IFS= read -r key; do
				echo "$key -> ${ANON_INTERFACE_MAP[$key]}"
			done
			echo ""
		fi
		set -u

		# Set Names
		set +u
		if [[ ${#ANON_SET_NAME_MAP[@]} -gt 0 ]]; then
			echo "Set Names:"
			echo "--------------------------------------------------"
			printf '%s\n' "${!ANON_SET_NAME_MAP[@]}" | sort | while IFS= read -r key; do
				echo "$key -> ${ANON_SET_NAME_MAP[$key]}"
			done
			echo ""
		fi
		set -u

		# MAC Addresses
		set +u
		if [[ ${#ANON_MAC_MAP[@]} -gt 0 ]]; then
			echo "MAC Addresses:"
			echo "--------------------------------------------------"
			printf '%s\n' "${!ANON_MAC_MAP[@]}" | sort | while IFS= read -r key; do
				echo "$key -> ${ANON_MAC_MAP[$key]}"
			done
			echo ""
		fi
		set -u

		# Hostnames
		set +u
		if [[ ${#ANON_HOSTNAME_MAP[@]} -gt 0 ]]; then
			echo "Hostnames:"
			echo "--------------------------------------------------"
			printf '%s\n' "${!ANON_HOSTNAME_MAP[@]}" | sort | while IFS= read -r key; do
				echo "$key -> ${ANON_HOSTNAME_MAP[$key]}"
			done
			echo ""
		fi
		set -u

		# Locations
		set +u
		if [[ ${#ANON_LOCATION_MAP[@]} -gt 0 ]]; then
			echo "Locations:"
			echo "--------------------------------------------------"
			printf '%s\n' "${!ANON_LOCATION_MAP[@]}" | sort | while IFS= read -r key; do
				echo "$key -> ${ANON_LOCATION_MAP[$key]}"
			done
		fi
		set -u
	} >"$mapping_file" || return 1

	return 0
}

# Extract IPv4 addresses from file
#
# Scans the file and extracts all unique IPv4 addresses.
# Handles CIDR notation, single IPs, and IP ranges.
#
# Arguments:
#   $1: Input file path
#
# Returns:
#   0: Success
#
# Output:
#   Prints unique IPv4 addresses (one per line) to stdout
extract_ipv4_from_file() {
	local input_file="$1"
	# Extract IPv4 addresses (with optional CIDR notation)
	# Pattern matches: 1-3 digits, dot, 1-3 digits, dot, 1-3 digits, dot, 1-3 digits, optional /number
	grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?\b' "$input_file" | sort -u
}

# Extract IPv6 addresses from file
#
# Scans the file and extracts all unique IPv6 addresses.
# Handles compressed notation, CIDR notation, and full addresses.
#
# Arguments:
#   $1: Input file path
#
# Returns:
#   0: Success
#
# Output:
#   Prints unique IPv6 addresses (one per line) to stdout
extract_ipv6_from_file() {
	local input_file="$1"
	# Extract IPv6 addresses (more specific pattern to avoid false positives)
	# Pattern matches IPv6 addresses including compressed notation (::) with optional CIDR notation
	# Excludes simple patterns like "10:00:00" that appear in timestamps
	# Timestamps are typically "HH:MM:SS" format (2 colons, 6-8 characters, decimal only)
	# Valid IPv6 addresses are longer, have CIDR notation, contain hex digits, or have different structure
	# IPv6 regex handles: full addresses, compressed (::), link-local (fe80::), loopback (::1), etc.
	grep -oE '(\[)?(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:))(/[0-9]{1,3})?(\])?' "$input_file" |
		grep -vE '^::?$' |
		# Filter out exact timestamp patterns: HH:MM:SS or HH:MM:SS] (6-8 chars, 2 colons, decimal only)
		# Timestamps match pattern: 1-2 digits, colon, 1-2 digits, colon, 1-2 digits, optional ]
		grep -vE '^\[?[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}\]?$' |
		# Keep addresses that are longer than timestamps OR have IPv6-specific features:
		# - Have CIDR notation (contain /)
		# - Are in brackets (start with [)
		# - Contain hex digits a-f (timestamps are decimal only)
		# - Are longer than 8 characters (timestamps are max 8 chars: "HH:MM:SS")
		# - Have IPv6 compression (contain ::)
		grep -E '(^\[|/|::|[a-fA-F]|.{9,})' |
		sort -u
}

# Extract interface names from file
#
# Scans the file and extracts all unique interface names.
# Handles interface names in -i, -o, --in-interface, --out-interface options.
#
# Arguments:
#   $1: Input file path
#
# Returns:
#   0: Success
#
# Output:
#   Prints unique interface names (one per line) to stdout
extract_interfaces_from_file() {
	local input_file="$1"
	local interfaces=()

	# Extract interface names from various iptables options
	# Pattern 1: -i interface or -o interface
	# Pattern 2: --in-interface interface or --out-interface interface
	# Pattern 3: -i! interface or -o! interface (negated)
	while IFS= read -r line || [[ -n "$line" ]]; do
		# Skip comments and table/chain declarations
		[[ "$line" =~ ^# ]] && continue
		[[ "$line" =~ ^[*:] ]] && continue
		[[ "$line" == "COMMIT" ]] && continue

		# Extract from -i, -o, --in-interface, and --out-interface options
		# Process line word by word to find interfaces (single pass for efficiency)
		local prev_word=""
		for word in $line; do
			# Check if previous word was an interface option
			if [[ "$prev_word" == "-i" ]] || [[ "$prev_word" == "-o" ]] ||
				[[ "$prev_word" == "--in-interface" ]] || [[ "$prev_word" == "--out-interface" ]]; then
				# Remove negation prefix if present
				local iface_name="${word#!}"
				# Validate it looks like an interface name
				if [[ $iface_name =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
					interfaces+=("$iface_name")
				fi
			fi
			prev_word="$word"
		done
	done <"$input_file"

	# Remove duplicates and sort
	printf '%s\n' "${interfaces[@]}" | sort -u
}

# Extract IP addresses from log file
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
extract_ips_from_log() {
	local log_file="$1"
	# Extract IPv4 addresses (pattern: 1-3 digits, dot, 1-3 digits, dot, 1-3 digits, dot, 1-3 digits)
	# This pattern matches IPs in various contexts
	grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$log_file" | sort -u
}

# Extract location names from log file
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
extract_locations_from_log() {
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
		# Also handles new format with IPs: "Found 2 location(s): NYC (203.0.113.1, 192.168.1.1), DC (198.51.100.1)"
		# Extract all uppercase words/underscores after "location(s):" or "location:"
		# Pattern matches location names optionally followed by parentheses with IPs
		elif [[ $line =~ location\(s\)?:\ (.+) ]]; then
			# Extract the comma-separated list (may include parentheses with IPs)
			local location_list="${BASH_REMATCH[1]}"
			# Split by comma and add each location
			IFS=',' read -ra location_array <<<"$location_list"
			for loc in "${location_array[@]}"; do
				# Trim whitespace
				loc="${loc#"${loc%%[![:space:]]*}"}"
				loc="${loc%"${loc##*[![:space:]]}"}"
				# Extract location name (remove parentheses and IPs if present)
				# Pattern: "LOCATION_NAME" or "LOCATION_NAME (IP, IP)"
				if [[ $loc =~ ^([A-Z][A-Z0-9_]+) ]]; then
					locations+=("${BASH_REMATCH[1]}")
				elif [[ -n "$loc" ]]; then
					# Fallback: if pattern doesn't match, try to extract any uppercase word
					# This handles edge cases
					if [[ $loc =~ ([A-Z][A-Z0-9_]+) ]]; then
						locations+=("${BASH_REMATCH[1]}")
					fi
				fi
			done
		fi
	done <"$log_file"

	# Remove duplicates and sort
	printf '%s\n' "${locations[@]}" | sort -u
}

# Extract MAC addresses from file
#
# Scans the file and extracts all unique MAC addresses.
# Handles standard MAC format: aa:bb:cc:dd:ee:ff
#
# Arguments:
#   $1: Input file path
#
# Returns:
#   0: Success
#
# Output:
#   Prints unique MAC addresses (one per line) to stdout
extract_mac_addresses_from_file() {
	local input_file="$1"
	# Extract MAC addresses (format: aa:bb:cc:dd:ee:ff)
	# Pattern matches: 2 hex digits, colon, repeated 5 times, then 2 hex digits
	grep -oE '\b([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b' "$input_file" | sort -u
}

# Extract hostnames/FQDNs from file
#
# Scans the file and extracts all unique hostnames and FQDNs.
# Handles various formats: hostname, hostname.domain, hostname.domain.tld
#
# Arguments:
#   $1: Input file path
#
# Returns:
#   0: Success
#
# Output:
#   Prints unique hostnames/FQDNs (one per line) to stdout
extract_hostnames_from_file() {
	local input_file="$1"
	# Extract hostnames/FQDNs
	# Pattern matches: alphanumeric/hyphen segments separated by dots, ending with TLD
	# Excludes common false positives like version numbers (e.g., "v1.0.0")
	# More specific pattern to avoid matching IP addresses or timestamps
	grep -oE '\b([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}\b' "$input_file" |
		# Filter out common false positives
		grep -vE '^[0-9]+\.[0-9]+\.[0-9]+' |                         # Version numbers
		grep -vE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | # IP addresses
		sort -u
}
