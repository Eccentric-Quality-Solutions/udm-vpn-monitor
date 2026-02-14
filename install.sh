#!/bin/bash
#
# UDM VPN Monitor Installation Script
# Installs the VPN monitoring script with cron-based execution
#
# Designed for UniFi Dream Machine (UDM) running UniFi OS 4.3+
#
# Version: 0.8.0
#

set -euo pipefail

# Installation paths
SCRIPT_NAME="vpn-monitor.sh"
CONFIG_NAME="vpn-monitor.conf"
INSTALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# INSTALL_DIR will be set based on DEV_MODE flag
INSTALL_DIR=""

# Flags
SKIP_CRON=0
SILENT=0
OVERWRITE_CONF=0
DEV_MODE=0
INTERACTIVE=0
KEEPALIVE_ONLY=0
APPEND_MISSING_CONFIG=0

# Verify lib directory exists before sourcing
# The lib directory should be present from the installation package extraction
if [[ ! -d "${INSTALL_SCRIPT_DIR}/lib" ]]; then
	echo "[ERROR] Library directory not found: ${INSTALL_SCRIPT_DIR}/lib"
	echo "[ERROR] Please ensure the installation package was extracted correctly"
	echo "[ERROR] Required library files: common.sh, config.sh, config_schema.sh, constants.sh, detection.sh, lockfile.sh, logging.sh, recovery.sh, resources.sh, state.sh"
	exit 1
fi

# Verify common.sh exists
if [[ ! -f "${INSTALL_SCRIPT_DIR}/lib/common.sh" ]]; then
	echo "[ERROR] Required library file not found: ${INSTALL_SCRIPT_DIR}/lib/common.sh"
	echo "[ERROR] Please ensure all library files are present"
	exit 1
fi

# Source shared common functions (logging, root check)
# shellcheck source=lib/common.sh
source "${INSTALL_SCRIPT_DIR}/lib/common.sh"

# Source detection functions for IP address validation
# shellcheck source=lib/detection.sh
source "${INSTALL_SCRIPT_DIR}/lib/detection.sh"

# Source config schema for default values (single source of truth for tier thresholds, etc.)
# shellcheck source=lib/config_schema.sh
source "${INSTALL_SCRIPT_DIR}/lib/config_schema.sh"

# Check if we're on a UDM
#
# Verifies that the system is a UniFi Dream Machine by checking for /data directory.
# Skips check if DEV_MODE is enabled (for testing on non-UDM systems).
#
# Arguments:
#   None
#
# Returns:
#   0: UDM detected or dev mode enabled
#   1: Not a UDM system (exits script with error)
check_udm() {
	if [[ $DEV_MODE -eq 1 ]]; then
		log_info "Dev mode enabled, skipping UDM check"
		return 0
	fi

	if [[ ! -d "/data" ]]; then
		log_error "Is this a UniFi Dream Machine? This script is designed for UniFi Dream Machines - /data directory not found"
		exit 1
	fi

	log_info "Detected UDM system"
}

# Create installation directory
#
# Creates the installation directory (INSTALL_DIR) if it doesn't exist.
# In production mode: /data/vpn-monitor
# In dev mode: ./vpn-monitor (current working directory)
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds (exits script on failure)
create_install_dir() {
	log_info "Creating installation directory: $INSTALL_DIR"
	mkdir -p "$INSTALL_DIR"
	log_info "Creating logs directory: ${INSTALL_DIR}/logs"
	mkdir -p "${INSTALL_DIR}/logs"
}

# Prompt for config value interactively
#
# Prompts the user for a configuration value, showing the default in brackets.
# If user presses Enter without input, uses the default value.
# Used during interactive installation mode to gather configuration values.
#
# Arguments:
#   $1: Config parameter name (e.g., "EXTERNAL_PEER_IPS") - used for reference, not displayed
#   $2: Default value (shown in brackets, used if user presses Enter)
#   $3: Description/prompt text (displayed to user)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the user's value (or default if empty) to stdout
#
# Examples:
#   value=$(prompt_config_value "EXTERNAL_PEER_IPS" "" "External peer IP address(es)")
#   # Prompts: "Peer IP address(es): "
#   value=$(prompt_config_value "TIER1_THRESHOLD" "1" "Tier 1 threshold")
#   # Prompts: "Tier 1 threshold [1]: "
#
# Note:
#   Uses read -p to prompt user
#   Empty input (Enter) uses default value
prompt_config_value() {
	# shellcheck disable=SC2034
	# param_name is used for documentation/reference purposes
	local param_name="$1"
	local default_value="$2"
	local description="$3"
	local user_input=""

	# Display prompt with default
	if [[ -n "$default_value" ]]; then
		read -rp "${description} [${default_value}]: " user_input
	else
		read -rp "${description}: " user_input
	fi

	# Use default if empty
	if [[ -z "$user_input" ]]; then
		echo "$default_value"
	else
		echo "$user_input"
	fi
}

# Prompt for config value and assign to variable
#
# Prompts the user for a configuration value and assigns it to a variable.
# Combines prompting and assignment to reduce boilerplate code.
#
# Arguments:
#   $1: Variable name (will be set in global scope)
#   $2: Default value (shown in brackets, used if user presses Enter)
#   $3: Description/prompt text (displayed to user)
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Sets the variable named in $1 in global scope (accessible to caller)
#
# Examples:
#   prompt_and_set_config "external_peer_ips" "" "External peer IP address(es)"
#   # Prompts user and sets $external_peer_ips variable in global scope
#
# Note:
#   Uses declare -g to set variables in global scope so they're accessible to the caller.
#   Variables will be set in global scope and accessible after the function returns.
prompt_and_set_config() {
	local var_name="$1"
	local default_value="$2"
	local description="$3"
	local value
	value=$(prompt_config_value "$var_name" "$default_value" "$description")
	declare -g "$var_name"
	printf -v "$var_name" '%s' "$value"
}

# Prompt for all configuration values interactively
#
# Prompts the user for all configuration values needed for the VPN monitor.
# Sets variables in global scope using declare -g, making them accessible to the caller.
#
# Arguments:
#   Default values are passed as parameters (14 total):
#     $1: default_peer_ips
#     $2: default_tier1
#     $3: default_tier2
#     $4: default_tier3
#     $5: default_max_restarts
#     $6: default_cron_schedule
#     $7: default_lockfile_timeout
#     $8: default_enable_ping
#     $9: default_ping_count
#     ${10}: default_ping_timeout
#     ${11}: default_debug
#     ${12}: default_enable_keepalive
#     ${13}: default_keepalive_interval
#     ${14}: default_keepalive_ping_count
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Sets the following variables in global scope:
#     external_peer_ips, internal_peer_ips, tier1, tier2, tier3,
#     max_restarts, cron_schedule, lockfile_timeout, enable_ping,
#     ping_count, ping_timeout, debug, enable_keepalive, keepalive_interval,
#     keepalive_ping_count
#
# Note:
#   Uses declare -g to set variables in global scope.
#   Variables will be accessible in the caller's scope after calling this function.
#   These variables are only used within create_interactive_config() and do not
#   persist beyond that function's execution.
prompt_all_config_values() {
	local default_peer_ips="$1"
	local default_tier1="$2"
	local default_tier2="$3"
	local default_tier3="$4"
	local default_max_restarts="$5"
	local default_cron_schedule="$6"
	local default_lockfile_timeout="$7"
	local default_enable_ping="${8}"
	local default_ping_count="${9}"
	local default_ping_timeout="${10}"
	local default_debug="${11}"
	local default_enable_keepalive="${12}"
	local default_keepalive_interval="${13}"
	local default_keepalive_ping_count="${14}"

	# Prompt for location-based configuration
	# Prompt for at least one location
	prompt_and_set_config "location_name" "NYC" "Location name for first VPN location (e.g., NYC, DC, OFFICE)"
	# Get location_name value (it was set in global scope by prompt_and_set_config)
	local current_location_name="${location_name}"
	prompt_and_set_config "external_peer_ips" "$default_peer_ips" "External/Public IP address for location ${current_location_name} (external/public IP of remote VPN gateway)"
	prompt_and_set_config "internal_peer_ips" "" "Internal/Private IP address(es) for location ${current_location_name} (optional, space-separated, for ping checks, empty to skip)"
	prompt_and_set_config "tier1" "$default_tier1" "Tier 1 threshold (failures before logging)"
	prompt_and_set_config "tier2" "$default_tier2" "Tier 2 threshold (failures before surgical cleanup)"
	prompt_and_set_config "tier3" "$default_tier3" "Tier 3 threshold (failures before full restart)"
	prompt_and_set_config "max_restarts" "$default_max_restarts" "Maximum restarts per window"
	prompt_and_set_config "cron_schedule" "$default_cron_schedule" "Cron schedule (e.g., '*/1 * * * *' for every minute)"
	prompt_and_set_config "lockfile_timeout" "$default_lockfile_timeout" "Lockfile timeout (seconds)"
	prompt_and_set_config "enable_ping" "$default_enable_ping" "Enable ping connectivity check (0 or 1)"
	prompt_and_set_config "ping_count" "$default_ping_count" "Ping count (number of packets)"
	prompt_and_set_config "ping_timeout" "$default_ping_timeout" "Ping timeout per packet (seconds)"
	prompt_and_set_config "debug" "$default_debug" "Enable debug logging (0 or 1)"
	prompt_and_set_config "enable_keepalive" "$default_enable_keepalive" "Enable VPN keepalive daemon (0 or 1)"
	prompt_and_set_config "keepalive_interval" "$default_keepalive_interval" "Keepalive ping interval (seconds)"
	prompt_and_set_config "keepalive_ping_count" "$default_keepalive_ping_count" "Keepalive ping count (packets)"
}

# Sanitize location name for config variable names
#
# Sanitizes a location name for use in config variable names (e.g., LOCATION_NYC_EXTERNAL).
# Replaces invalid characters with underscores, converts to uppercase, removes leading
# underscores, and ensures a valid identifier format.
#
# Arguments:
#   $1: Location name to sanitize (e.g., "NYC", "New York", "DC-Office")
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints sanitized location name to stdout (e.g., "NYC", "NEW_YORK", "DC_OFFICE")
#   Prints "LOCATION" if input is empty or becomes empty after sanitization
#
# Examples:
#   sanitized=$(sanitize_location_name_for_config "NYC")
#   # Returns: "NYC"
#
#   sanitized=$(sanitize_location_name_for_config "New York")
#   # Returns: "NEW_YORK"
#
#   sanitized=$(sanitize_location_name_for_config "_Office")
#   # Returns: "OFFICE" (leading underscore removed)
#
#   sanitized=$(sanitize_location_name_for_config "")
#   # Returns: "LOCATION" (default for empty input)
#
# Note:
#   - Used specifically for config variable names (LOCATION_*_EXTERNAL format)
#   - Differs from sanitize_location_name() in lib/common.sh which is for filenames
#   - Config variable names can't start with underscores, so they are removed
sanitize_location_name_for_config() {
	local location_name="$1"
	local sanitized

	# Replace invalid chars with underscore and convert to uppercase
	sanitized=$(echo "$location_name" | sed 's/[^A-Za-z0-9_]/_/g' | tr '[:lower:]' '[:upper:]')

	# Remove all leading underscores (config variable names can't start with underscore)
	while [[ "$sanitized" =~ ^_ ]]; do
		sanitized="${sanitized#_}"
	done

	# If empty after sanitization, use default (matches library function behavior)
	if [[ -z "$sanitized" ]]; then
		sanitized="LOCATION"
	fi

	echo "$sanitized"
	return 0
}

# Create config file interactively
#
# Prompts the user for each configuration value with defaults.
# Creates the config file with user-provided values.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds (exits script on failure)
#
# Side effects:
#   Creates ${INSTALL_DIR}/${CONFIG_NAME} with user-provided values
create_interactive_config() {
	log_info "Interactive configuration mode"
	echo ""
	log_info "Please provide configuration values (press Enter to accept default)"
	echo ""

	# Default values (tier thresholds from schema; fallback if schema unavailable)
	local default_peer_ips=""
	local default_tier1 default_tier2 default_tier3
	default_tier1=$(get_config_default "TIER1_THRESHOLD" 2>/dev/null || echo "1")
	default_tier2=$(get_config_default "TIER2_THRESHOLD" 2>/dev/null || echo "2")
	default_tier3=$(get_config_default "TIER3_THRESHOLD" 2>/dev/null || echo "3")
	local default_max_restarts=3
	local default_log_file="${INSTALL_DIR}/logs/vpn-monitor.log"
	local default_state_dir="${INSTALL_DIR}/state"
	local default_cron_schedule="*/1 * * * *"
	local default_lockfile_timeout=300
	local default_enable_ping=1
	local default_ping_count=3
	local default_ping_timeout=2
	local default_debug=0
	local default_enable_keepalive="1"
	local default_keepalive_interval="30"
	local default_keepalive_ping_count="1"

	# Prompt for all configuration values
	# Variables will be set in global scope by prompt_all_config_values
	prompt_all_config_values \
		"$default_peer_ips" \
		"$default_tier1" \
		"$default_tier2" \
		"$default_tier3" \
		"$default_max_restarts" \
		"$default_cron_schedule" \
		"$default_lockfile_timeout" \
		"$default_enable_ping" \
		"$default_ping_count" \
		"$default_ping_timeout" \
		"$default_debug" \
		"$default_enable_keepalive" \
		"$default_keepalive_interval" \
		"$default_keepalive_ping_count"

	# Create config file
	# shellcheck disable=SC2154
	# Variables are set in global scope by prompt_all_config_values() via declare -g
	# Sanitize location name for use in variable name
	local sanitized_location_name
	sanitized_location_name=$(sanitize_location_name_for_config "${location_name}")

	cat >"${INSTALL_DIR}/${CONFIG_NAME}" <<EOF
# UDM VPN Monitor Configuration
# Generated via interactive installation

# Location-based VPN configuration
# Format: LOCATION_<NAME>_EXTERNAL="external_ip"
# Format: LOCATION_<NAME>_INTERNAL="internal_ip1 internal_ip2 ..."
# Location names are automatically extracted from variable names (text between LOCATION_ and _EXTERNAL)
# For locations with multiple internal IPs, VPN is considered healthy if ≥30% respond to pings
# shellcheck disable=SC2154
# Variables are set in global scope by prompt_all_config_values() via declare -g
LOCATION_${sanitized_location_name}_EXTERNAL="${external_peer_ips}"
LOCATION_${sanitized_location_name}_INTERNAL="${internal_peer_ips}"

# Failure threshold: number of consecutive failures before taking action
TIER1_THRESHOLD=${tier1}
TIER2_THRESHOLD=${tier2}
TIER3_THRESHOLD=${tier3}

# Rate limiting configuration
MAX_RESTARTS_PER_WINDOW=${max_restarts}
RATE_LIMIT_WINDOW_MINUTES=60

# Log file location (must be in /data/ for persistence)
LOG_FILE="${default_log_file}"

# State directory (for counter files and lockfiles)
STATE_DIR="${default_state_dir}"

# Cron schedule (cron format: minute hour day month weekday)
CRON_SCHEDULE="${cron_schedule}"

# Monitor wrapper (sub-minute execution) - set to 1 for checks every MONITOR_INTERVAL seconds
ENABLE_MONITOR_WRAPPER=1
MONITOR_INTERVAL=20

# Lockfile timeout (seconds)
LOCKFILE_TIMEOUT=${lockfile_timeout}

# Ping connectivity check
ENABLE_PING_CHECK=${enable_ping}

# Ping count (number of packets to send)
PING_COUNT=${ping_count}

# Ping timeout per packet (seconds)
PING_TIMEOUT=${ping_timeout}

# VPN Keepalive Daemon
ENABLE_KEEPALIVE=${enable_keepalive}
KEEPALIVE_INTERVAL=${keepalive_interval}
KEEPALIVE_PING_COUNT=${keepalive_ping_count}

# Network Partition Detection
ENABLE_NETWORK_PARTITION_CHECK=1

# Resource Monitoring
ENABLE_RESOURCE_MONITORING=1

# Enable debug logging (set to 1 for verbose output)
DEBUG=${debug}
EOF

	log_info "Configuration file created: ${INSTALL_DIR}/${CONFIG_NAME}"
}

# Install config file (from template or create default)
#
# Installs the configuration file to the installation directory.
# If INTERACTIVE flag is set, prompts for each value.
# If a config template exists in the source directory, copies it.
# Otherwise, creates a default configuration file.
#
# Arguments:
#   $1: Optional message to display before installation
#
# Returns:
#   0: Always succeeds (exits script on failure)
#
# Side effects:
#   Creates or overwrites ${INSTALL_DIR}/${CONFIG_NAME}
install_config_file() {
	local overwrite_msg="$1"

	if [[ -n "$overwrite_msg" ]]; then
		log_info "$overwrite_msg"
	fi

	# Interactive mode: prompt for each value
	if [[ $INTERACTIVE -eq 1 ]]; then
		create_interactive_config
		return 0
	fi

	# Non-interactive mode: copy template or create default
	if [[ -f "${INSTALL_SCRIPT_DIR}/${CONFIG_NAME}" ]]; then
		cp "${INSTALL_SCRIPT_DIR}/${CONFIG_NAME}" "${INSTALL_DIR}/${CONFIG_NAME}"
		chmod 644 "${INSTALL_DIR}/${CONFIG_NAME}"
		log_info "Installed ${CONFIG_NAME} (please customize it)"
	else
		log_warn "Config template not found, creating default"
		# Use schema defaults for tier thresholds (single source of truth)
		local install_tier1 install_tier2 install_tier3
		install_tier1=$(get_config_default "TIER1_THRESHOLD" 2>/dev/null || echo "1")
		install_tier2=$(get_config_default "TIER2_THRESHOLD" 2>/dev/null || echo "2")
		install_tier3=$(get_config_default "TIER3_THRESHOLD" 2>/dev/null || echo "3")
		cat >"${INSTALL_DIR}/${CONFIG_NAME}" <<EOF
# UDM VPN Monitor Configuration
# Location-based VPN configuration
# Format: LOCATION_<NAME>_EXTERNAL="external_ip"
# Format: LOCATION_<NAME>_INTERNAL="internal_ip1 internal_ip2 ..."
# Location names are automatically extracted from variable names (text between LOCATION_ and _EXTERNAL)
# For locations with multiple internal IPs, VPN is considered healthy if ≥30% respond to pings
# Example:
#   LOCATION_NYC_EXTERNAL="203.0.113.1"
#   LOCATION_NYC_INTERNAL="192.168.1.1 192.168.1.88"
#   LOCATION_DC_EXTERNAL="203.0.113.2"
#   LOCATION_DC_INTERNAL="192.168.10.1 192.168.10.254"
#
# Add your locations below (no example locations are shipped).
TIER1_THRESHOLD=${install_tier1}
TIER2_THRESHOLD=${install_tier2}
TIER3_THRESHOLD=${install_tier3}
MAX_RESTARTS_PER_WINDOW=20
RATE_LIMIT_WINDOW_MINUTES=60
LOG_FILE="${INSTALL_DIR}/logs/vpn-monitor.log"
STATE_DIR="${INSTALL_DIR}/state"
CRON_SCHEDULE="*/1 * * * *"
ENABLE_MONITOR_WRAPPER=1
MONITOR_INTERVAL=20
LOCKFILE_TIMEOUT=300
ENABLE_PING_CHECK=1
PING_COUNT=3
PING_TIMEOUT=2
ENABLE_KEEPALIVE=1
KEEPALIVE_INTERVAL=30
KEEPALIVE_PING_COUNT=1
ENABLE_NETWORK_PARTITION_CHECK=1
ENABLE_RESOURCE_MONITORING=1
DEBUG=0
EOF
	fi
}

# Extract version from script file
#
# Extracts the SCRIPT_VERSION value from a script file.
# Looks for lines matching "SCRIPT_VERSION=\"...\"" or "SCRIPT_VERSION='...'".
#
# Arguments:
#   $1: Path to script file
#
# Returns:
#   0: Version found and printed to stdout
#   1: Version not found
#
# Output:
#   Prints version string to stdout (e.g., "0.0.1")
get_script_version() {
	local script_file="$1"
	if [[ ! -f "$script_file" ]]; then
		return 1
	fi

	# Try to extract SCRIPT_VERSION="..." or SCRIPT_VERSION='...'
	local version
	version=$(grep -E '^SCRIPT_VERSION=["'\'']' "$script_file" 2>/dev/null | head -1 | sed -E "s/^SCRIPT_VERSION=[\"']([^\"']+)[\"'].*/\1/" | tr -d ' ')

	if [[ -n "$version" ]]; then
		echo "$version"
		return 0
	fi

	return 1
}

# Get current version being installed
#
# Extracts the version from the source vpn-monitor.sh script.
# Falls back to install script version comment if not found.
#
# Arguments:
#   None
#
# Returns:
#   0: Version found and printed to stdout
#   1: Version not found
#
# Output:
#   Prints version string to stdout
get_current_version() {
	local version=""

	# Try to get version from source vpn-monitor.sh
	if [[ -f "${INSTALL_SCRIPT_DIR}/${SCRIPT_NAME}" ]]; then
		version=$(get_script_version "${INSTALL_SCRIPT_DIR}/${SCRIPT_NAME}")
	fi

	# Fallback to install script version comment
	if [[ -z "$version" ]]; then
		version=$(grep -E '^# Version:' "${INSTALL_SCRIPT_DIR}/install.sh" 2>/dev/null | head -1 | sed -E 's/^# Version:[[:space:]]*//' | tr -d ' ')
	fi

	if [[ -n "$version" ]]; then
		echo "$version"
		return 0
	fi

	return 1
}

# Display upgrade information
#
# Detects if an existing installation exists and displays version upgrade information
# including old version, new version, and changelog summary.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds (warnings logged but don't fail)
#
# Side effects:
#   - Prints upgrade information to terminal if upgrade detected
display_upgrade_info() {
	# Check if existing installation exists
	if [[ ! -f "${INSTALL_DIR}/${SCRIPT_NAME}" ]]; then
		# No existing installation
		return 0
	fi

	# Get old version from installed script
	local old_version
	if ! old_version=$(get_script_version "${INSTALL_DIR}/${SCRIPT_NAME}"); then
		# Could not determine old version
		return 0
	fi

	# Get new version being installed
	local new_version
	if ! new_version=$(get_current_version); then
		# Could not determine new version
		return 0
	fi

	# Check if versions are different
	if [[ "$old_version" == "$new_version" ]]; then
		# Same version, no upgrade info needed
		return 0
	fi

	# Display upgrade information
	echo ""
	log_info "Upgrading existing installation detected"
	log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	log_info "Current version:  $old_version"
	log_info "New version:      $new_version"
	echo ""
	log_info "To see changes between versions, open: ${INSTALL_SCRIPT_DIR}/CHANGELOG.md"
	log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo ""
}

# Compare template config with existing config
#
# Runs compare-config.sh to show differences between template and existing config.
# Only runs when config file is preserved (not overwritten) and not in silent mode.
#
# Arguments:
#   None
#
# Returns:
#   0: Comparison completed (or skipped)
#
# Side effects:
#   - Prints comparison results to terminal
compare_template_with_existing_config() {
	local existing_config="${INSTALL_DIR}/${CONFIG_NAME}"
	local template_config="${INSTALL_SCRIPT_DIR}/${CONFIG_NAME}"
	local compare_script="${INSTALL_DIR}/compare-config.sh"

	# Skip in silent mode
	if [[ $SILENT -eq 1 ]]; then
		return 0
	fi

	# Skip if config file doesn't exist
	if [[ ! -f "$existing_config" ]]; then
		return 0
	fi

	# Skip if template doesn't exist
	if [[ ! -f "$template_config" ]]; then
		return 0
	fi

	# Skip if compare script doesn't exist (shouldn't happen, but be safe)
	if [[ ! -f "$compare_script" ]] || [[ ! -x "$compare_script" ]]; then
		return 0
	fi

	# Run comparison (suppress errors to avoid failing install)
	echo ""
	log_info "Comparing template configuration with your existing config..."
	echo ""
	if "$compare_script" --template "$template_config" --existing "$existing_config" 2>/dev/null; then
		# Comparison succeeded
		echo ""
		log_info "To review configuration differences anytime, run: ${compare_script}"
		echo ""
	else
		# Comparison failed (script may have issues, but don't fail install)
		log_warn "Could not compare template with existing config (non-fatal)"
	fi

	return 0
}

# Offer to append missing config values to existing config file
#
# When an existing config is preserved, checks for variables in the template that
# are missing from the existing config. If any are found, asks the user if they
# want to append them to the end of the config file with template default values.
# Paths containing /data/vpn-monitor are substituted with the actual INSTALL_DIR.
#
# Arguments:
#   None
#
# Returns:
#   0: Completed (appended or user declined)
#
# Side effects:
#   - May append lines to existing config file
#   - Prompts user when run in non-silent mode and missing values exist
offer_append_missing_config_values() {
	local existing_config="${INSTALL_DIR}/${CONFIG_NAME}"
	local template_config="${INSTALL_SCRIPT_DIR}/${CONFIG_NAME}"
	local compare_script="${INSTALL_DIR}/compare-config.sh"
	local missing_lines
	local line

	# Skip in silent mode (no user interaction)
	if [[ $SILENT -eq 1 ]]; then
		return 0
	fi

	# Skip if config or compare script doesn't exist
	if [[ ! -f "$existing_config" ]] || [[ ! -f "$template_config" ]] ||
		[[ ! -f "$compare_script" ]] || [[ ! -x "$compare_script" ]]; then
		return 0
	fi

	missing_lines=$("$compare_script" --template "$template_config" --existing "$existing_config" --list-missing-with-values 2>/dev/null) || true

	if [[ -z "${missing_lines//[[:space:]]/}" ]]; then
		return 0
	fi

	echo ""
	log_warn "Missing configuration values were found in the template."
	log_info "The following settings are not in your existing config:"
	echo ""
	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ -z "$line" ]] && continue
		log_info "  $line"
	done <<<"$missing_lines"
	echo ""
	read -rp "Append these values to the end of your config file? (yes/no) [no]: " REPLY
	echo ""
	if [[ ! "$REPLY" =~ ^[Yy][Ee][Ss]$ ]]; then
		log_info "Skipping append (user declined)"
		return 0
	fi

	# Substitute /data/vpn-monitor with actual INSTALL_DIR in paths
	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ -z "$line" ]] && continue
		line="${line//\/data\/vpn-monitor/$INSTALL_DIR}"
		if echo "$line" >>"$existing_config"; then
			log_info "Appended: $line"
		else
			log_error "Failed to append: $line"
		fi
	done <<<"$missing_lines"

	log_info "Missing values appended to ${existing_config}"
	return 0
}

# Auto-append missing config values to existing config file (non-interactive)
#
# When --silent --append-missing-config is used, appends variables from the template
# that are missing from the existing config, without prompting.
# Paths containing /data/vpn-monitor are substituted with the actual INSTALL_DIR.
#
# Arguments:
#   None
#
# Returns:
#   0: Completed (appended or nothing to append)
#
# Side effects:
#   - May append lines to existing config file
auto_append_missing_config_values() {
	local existing_config="${INSTALL_DIR}/${CONFIG_NAME}"
	local template_config="${INSTALL_SCRIPT_DIR}/${CONFIG_NAME}"
	local compare_script="${INSTALL_DIR}/compare-config.sh"
	local missing_lines
	local line

	# Skip if config or compare script doesn't exist
	if [[ ! -f "$existing_config" ]] || [[ ! -f "$template_config" ]] ||
		[[ ! -f "$compare_script" ]] || [[ ! -x "$compare_script" ]]; then
		return 0
	fi

	missing_lines=$("$compare_script" --template "$template_config" --existing "$existing_config" --list-missing-with-values 2>/dev/null) || true

	if [[ -z "${missing_lines//[[:space:]]/}" ]]; then
		return 0
	fi

	log_info "Appending missing configuration values to existing config..."

	# Substitute /data/vpn-monitor with actual INSTALL_DIR in paths
	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ -z "$line" ]] && continue
		line="${line//\/data\/vpn-monitor/$INSTALL_DIR}"
		if echo "$line" >>"$existing_config"; then
			log_info "Appended: $line"
		else
			log_error "Failed to append: $line"
		fi
	done <<<"$missing_lines"

	log_info "Missing values appended to ${existing_config}"
	return 0
}

# Install scripts
#
# Copies the main VPN monitor script, library files, and configuration file to the installation directory.
# Handles existing config files based on SILENT and OVERWRITE_CONF flags.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds (exits script on failure)
#
# Side effects:
#   - Copies vpn-monitor.sh to installation directory
#   - Copies lib/ directory with all library modules to installation directory
#   - Copies vpn-keepalive.sh to installation directory (if available)
#   - Copies analyze-logs.sh to installation directory (if available)
#   - Copies check-utilities.sh to installation directory (if available)
#   - Copies scripts/ utilities to installation directory (if available): anonymize-logs.sh,
#     deploy-to-udm.sh, deploy-to-udms.sh, migrate-config-to-locations.sh
#   - Copies scripts/deploy-udms.conf.example (if available)
#   - Sets executable permissions on scripts
#   - Installs config file (may prompt user in interactive mode)
install_scripts() {
	log_info "Installing scripts..."

	# Copy main script
	if [[ -f "${INSTALL_SCRIPT_DIR}/${SCRIPT_NAME}" ]]; then
		cp "${INSTALL_SCRIPT_DIR}/${SCRIPT_NAME}" "${INSTALL_DIR}/${SCRIPT_NAME}"
		chmod 755 "${INSTALL_DIR}/${SCRIPT_NAME}"
		log_info "Installed ${SCRIPT_NAME}"
	else
		log_error "Source file not found: ${INSTALL_SCRIPT_DIR}/${SCRIPT_NAME}"
		exit 1
	fi

	# Copy library directory (required for vpn-monitor.sh)
	if [[ -d "${INSTALL_SCRIPT_DIR}/lib" ]]; then
		# Create lib directory in installation directory
		mkdir -p "${INSTALL_DIR}/lib"
		# Copy all library files
		cp -r "${INSTALL_SCRIPT_DIR}/lib"/* "${INSTALL_DIR}/lib/"
		log_info "Installed lib/ directory (library modules)"
	else
		log_error "Library directory not found: ${INSTALL_SCRIPT_DIR}/lib - vpn-monitor.sh requires library files to function"
		exit 1
	fi

	# Copy keepalive script (optional utility)
	if [[ -f "${INSTALL_SCRIPT_DIR}/vpn-keepalive.sh" ]]; then
		cp "${INSTALL_SCRIPT_DIR}/vpn-keepalive.sh" "${INSTALL_DIR}/vpn-keepalive.sh"
		chmod 755 "${INSTALL_DIR}/vpn-keepalive.sh"
		log_info "Installed vpn-keepalive.sh"
	fi

	# Copy monitor wrapper script (for sub-minute execution when ENABLE_MONITOR_WRAPPER=1)
	if [[ -f "${INSTALL_SCRIPT_DIR}/vpn-monitor-wrapper.sh" ]]; then
		cp "${INSTALL_SCRIPT_DIR}/vpn-monitor-wrapper.sh" "${INSTALL_DIR}/vpn-monitor-wrapper.sh"
		chmod 755 "${INSTALL_DIR}/vpn-monitor-wrapper.sh"
		log_info "Installed vpn-monitor-wrapper.sh (sub-minute execution)"
	fi

	# Copy log analysis script (optional utility)
	if [[ -f "${INSTALL_SCRIPT_DIR}/analyze-logs.sh" ]]; then
		cp "${INSTALL_SCRIPT_DIR}/analyze-logs.sh" "${INSTALL_DIR}/analyze-logs.sh"
		chmod 755 "${INSTALL_DIR}/analyze-logs.sh"
		log_info "Installed analyze-logs.sh (log analysis utility)"
	fi

	# Copy utility checker script (optional utility)
	if [[ -f "${INSTALL_SCRIPT_DIR}/check-utilities.sh" ]]; then
		cp "${INSTALL_SCRIPT_DIR}/check-utilities.sh" "${INSTALL_DIR}/check-utilities.sh"
		chmod 755 "${INSTALL_DIR}/check-utilities.sh"
		log_info "Installed check-utilities.sh (utility availability checker)"
	fi

	# Copy config checker script (optional utility)
	if [[ -f "${INSTALL_SCRIPT_DIR}/check-config.sh" ]]; then
		cp "${INSTALL_SCRIPT_DIR}/check-config.sh" "${INSTALL_DIR}/check-config.sh"
		chmod 755 "${INSTALL_DIR}/check-config.sh"
		log_info "Installed check-config.sh (configuration validator)"
	fi

	# Copy config comparison script (optional utility)
	if [[ -f "${INSTALL_SCRIPT_DIR}/compare-config.sh" ]]; then
		cp "${INSTALL_SCRIPT_DIR}/compare-config.sh" "${INSTALL_DIR}/compare-config.sh"
		chmod 755 "${INSTALL_DIR}/compare-config.sh"
		log_info "Installed compare-config.sh (template vs existing config comparison)"
	fi

	# Copy scripts directory utilities (optional)
	if [[ -f "${INSTALL_SCRIPT_DIR}/scripts/anonymize-logs.sh" ]] ||
		[[ -f "${INSTALL_SCRIPT_DIR}/scripts/deploy-to-udm.sh" ]] ||
		[[ -f "${INSTALL_SCRIPT_DIR}/scripts/deploy-to-udms.sh" ]] ||
		[[ -f "${INSTALL_SCRIPT_DIR}/scripts/migrate-config-to-locations.sh" ]] ||
		[[ -f "${INSTALL_SCRIPT_DIR}/scripts/deploy-udms.conf.example" ]]; then
		mkdir -p "${INSTALL_DIR}/scripts"
	fi
	if [[ -f "${INSTALL_SCRIPT_DIR}/scripts/anonymize-logs.sh" ]]; then
		cp "${INSTALL_SCRIPT_DIR}/scripts/anonymize-logs.sh" "${INSTALL_DIR}/scripts/anonymize-logs.sh"
		chmod 755 "${INSTALL_DIR}/scripts/anonymize-logs.sh"
		log_info "Installed scripts/anonymize-logs.sh (log anonymization utility)"
	fi
	if [[ -f "${INSTALL_SCRIPT_DIR}/scripts/deploy-to-udm.sh" ]]; then
		cp "${INSTALL_SCRIPT_DIR}/scripts/deploy-to-udm.sh" "${INSTALL_DIR}/scripts/deploy-to-udm.sh"
		chmod 755 "${INSTALL_DIR}/scripts/deploy-to-udm.sh"
		log_info "Installed scripts/deploy-to-udm.sh (deploy to single UDM)"
	fi
	if [[ -f "${INSTALL_SCRIPT_DIR}/scripts/deploy-to-udms.sh" ]]; then
		cp "${INSTALL_SCRIPT_DIR}/scripts/deploy-to-udms.sh" "${INSTALL_DIR}/scripts/deploy-to-udms.sh"
		chmod 755 "${INSTALL_DIR}/scripts/deploy-to-udms.sh"
		log_info "Installed scripts/deploy-to-udms.sh (deploy to multiple UDMs)"
	fi
	if [[ -f "${INSTALL_SCRIPT_DIR}/scripts/migrate-config-to-locations.sh" ]]; then
		cp "${INSTALL_SCRIPT_DIR}/scripts/migrate-config-to-locations.sh" "${INSTALL_DIR}/scripts/migrate-config-to-locations.sh"
		chmod 755 "${INSTALL_DIR}/scripts/migrate-config-to-locations.sh"
		log_info "Installed scripts/migrate-config-to-locations.sh (config migration utility)"
	fi
	if [[ -f "${INSTALL_SCRIPT_DIR}/scripts/deploy-udms.conf.example" ]]; then
		cp "${INSTALL_SCRIPT_DIR}/scripts/deploy-udms.conf.example" "${INSTALL_DIR}/scripts/deploy-udms.conf.example"
		log_info "Installed scripts/deploy-udms.conf.example (template for deploy-udms.conf used by scripts/deploy-to-udms.sh)"
	fi

	# Handle config file installation
	if [[ -f "${INSTALL_DIR}/${CONFIG_NAME}" ]]; then
		# Config file already exists
		if [[ $INTERACTIVE -eq 1 ]]; then
			# Interactive mode: always prompt for new values (overwrites existing)
			install_config_file "Config file exists, creating new interactive configuration"
		elif [[ $SILENT -eq 1 ]]; then
			# Silent mode: only overwrite if explicitly requested
			if [[ $OVERWRITE_CONF -eq 1 ]]; then
				install_config_file "Overwriting existing config file (--overwrite-conf flag)"
			else
				log_info "Config file already exists, preserving: ${INSTALL_DIR}/${CONFIG_NAME}"
				# Compare template with existing config to show what's new
				compare_template_with_existing_config
				# Append missing values: auto-append if --append-missing-config, else offer (skipped in silent)
				if [[ $APPEND_MISSING_CONFIG -eq 1 ]]; then
					auto_append_missing_config_values
				else
					offer_append_missing_config_values
				fi
			fi
		else
			# Non-interactive, non-silent mode: ask user
			echo ""
			log_warn "Config file already exists: ${INSTALL_DIR}/${CONFIG_NAME}"
			read -rp "Overwrite existing config file? (yes/no) [no]: " REPLY
			echo ""
			if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
				install_config_file "Overwriting existing config file"
			else
				log_info "Preserving existing config file: ${INSTALL_DIR}/${CONFIG_NAME}"
				# Compare template with existing config to show what's new
				compare_template_with_existing_config
				# Offer to append missing values
				offer_append_missing_config_values
			fi
		fi
	else
		# Config file doesn't exist, install it
		install_config_file "Installing config file"
	fi
}

# Parse and validate cron schedule from config file
#
# Extracts CRON_SCHEDULE from config file and validates it has proper format.
# Handles quoted and unquoted values cleanly.
#
# Arguments:
#   $1: Path to config file
#
# Returns:
#   0: Valid cron schedule found and parsed
#   1: No valid cron schedule found, config file not found, or config file unreadable (use default)
#
# Output:
#   Prints the validated cron schedule to stdout (if valid)
parse_cron_schedule() {
	local config_file="$1"
	local schedule=""

	# Check if config file exists
	if [[ ! -f "$config_file" ]]; then
		return 1
	fi

	# Check file readability before grep operation (prevents hangs on unreadable files)
	if ! file_exists_and_readable "$config_file"; then
		return 1
	fi

	# Read the CRON_SCHEDULE line from config
	local line
	line=$(grep "^CRON_SCHEDULE=" "$config_file" 2>/dev/null | head -1)

	if [[ -z "$line" ]]; then
		return 1
	fi

	# Extract value after the equals sign
	schedule="${line#CRON_SCHEDULE=}"

	# Remove surrounding quotes (handles both single and double quotes)
	# Trim leading/trailing whitespace first
	schedule=$(trim "$schedule")

	# Remove quotes if present
	if [[ "$schedule" =~ ^\".*\"$ ]]; then
		schedule="${schedule#\"}"
		schedule="${schedule%\"}"
	elif [[ "$schedule" =~ ^\'.*\'$ ]]; then
		schedule="${schedule#\'}"
		schedule="${schedule%\'}"
	fi

	# Trim whitespace again after quote removal
	schedule=$(trim "$schedule")

	# Validate: must be non-empty
	if [[ -z "$schedule" ]]; then
		return 1
	fi

	# Validate: must contain at least one digit or asterisk (basic cron field requirement)
	if [[ ! "$schedule" =~ [0-9*] ]]; then
		return 1
	fi

	# Validate: must have exactly 5 space-separated fields
	# Split into array and count fields
	local IFS=' '
	local -a fields
	read -ra fields <<<"$schedule"

	if [[ ${#fields[@]} -ne 5 ]]; then
		return 1
	fi

	# Basic validation: each field should contain valid cron characters
	# Valid characters: digits, asterisk, comma, dash, slash
	# Note: Fields are already split by spaces, so individual fields shouldn't contain whitespace
	local field
	for field in "${fields[@]}"; do
		if [[ ! "$field" =~ ^[0-9*,\-/\]+$ ]]; then
			return 1
		fi
	done

	# Valid schedule found
	echo "$schedule"
	return 0
}

# Setup cron job
#
# Adds a cron job entry to run the VPN monitor script on a schedule.
# Reads CRON_SCHEDULE from config file if available, otherwise uses default (*/1 * * * *).
# Skips if cron entry already exists (to avoid duplicates).
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds (warnings logged but don't fail)
#
# Side effects:
#   - Adds cron entry to root crontab
#   - Displays current cron entries
#
# Note:
#   Cron schedule format: minute hour day month weekday
#   Example: "*/1 * * * *" = every 1 minute
setup_cron() {
	log_info "Setting up cron job..."

	# Load cron schedule from config if it exists, otherwise use default
	local cron_schedule="*/1 * * * *"
	if [[ -f "${INSTALL_DIR}/${CONFIG_NAME}" ]]; then
		local config_schedule
		if config_schedule=$(parse_cron_schedule "${INSTALL_DIR}/${CONFIG_NAME}"); then
			cron_schedule="$config_schedule"
			log_info "Using cron schedule from config: $cron_schedule"
		else
			log_info "Using default cron schedule: $cron_schedule"
		fi
	else
		log_info "Using default cron schedule: $cron_schedule"
	fi

	# Check if wrapper mode is enabled
	local enable_wrapper=0
	if [[ -f "${INSTALL_DIR}/${CONFIG_NAME}" ]]; then
		local val
		val=$(grep -E "^ENABLE_MONITOR_WRAPPER=" "${INSTALL_DIR}/${CONFIG_NAME}" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "1")
		[[ "$val" == "1" ]] && enable_wrapper=1
	fi

	local cron_entry
	if [[ $enable_wrapper -eq 1 ]]; then
		# Wrapper runs in background; cron starts it every minute for resurrection
		cron_entry="${cron_schedule} ${INSTALL_DIR}/vpn-monitor-wrapper.sh >> ${INSTALL_DIR}/logs/cron.log 2>&1 &"
		log_info "Using monitor wrapper (sub-minute execution via MONITOR_INTERVAL)"
	else
		cron_entry="${cron_schedule} ${INSTALL_DIR}/${SCRIPT_NAME} >> ${INSTALL_DIR}/logs/cron.log 2>&1"
	fi

	# Note: cron.log will be created automatically on first cron run in the logs directory.
	# Log rotation is configured via logrotate (see install_logrotate_config function).

	# Remove existing vpn-monitor cron entry (direct or wrapper) so we can add/update
	local crontab_content
	crontab_content=$(crontab -l 2>/dev/null || echo "")
	if echo "$crontab_content" | grep -q "vpn-monitor"; then
		local filtered_content
		filtered_content=$(echo "$crontab_content" | grep -v "vpn-monitor")
		if [[ -n "$filtered_content" ]]; then
			echo "$filtered_content" | crontab -
		else
			crontab -r 2>/dev/null || true
		fi
		log_info "Removed existing vpn-monitor cron entry"
	fi

	# Add cron entry
	(
		crontab -l 2>/dev/null || true
		echo "$cron_entry"
	) | crontab -
	log_info "Cron job installed: $([ $enable_wrapper -eq 1 ] && echo 'wrapper (sub-minute)' || echo "direct ($cron_schedule)")"

	# Display current cron entries
	log_info "Current cron entries:"
	crontab -l 2>/dev/null | grep -E "(vpn-monitor|^#)" || log_warn "No cron entries found"
}

# Install systemd service for keepalive daemon
#
# Installs the systemd service file for the VPN keepalive daemon.
# Only installs if systemd is available and not in dev mode.
#
# Arguments:
#   None
#
# Returns:
#   0: Service installed successfully (or skipped if not applicable)
#   1: Failed to install service
#
# Side effects:
#   - Creates /etc/systemd/system/vpn-keepalive.service
#   - Reloads systemd daemon
# Note: Service restart is handled by enable_and_start_keepalive_service() or
#       by the caller if the service is running but keepalive is disabled.
install_keepalive_service() {
	# Skip in dev mode (systemd services are system-wide)
	if [[ $DEV_MODE -eq 1 ]]; then
		log_info "Skipping systemd service installation (dev mode)"
		return 0
	fi

	# Check if systemd is available
	if ! command -v systemctl >/dev/null 2>&1; then
		log_warn "systemctl not found, skipping systemd service installation. Keepalive daemon must be started manually: ${INSTALL_DIR}/vpn-keepalive.sh start"
		return 0
	fi

	# Check if we have write access to /etc/systemd/system
	if [[ ! -w /etc/systemd/system ]]; then
		log_warn "Cannot write to /etc/systemd/system, skipping systemd service installation. Keepalive daemon must be started manually: ${INSTALL_DIR}/vpn-keepalive.sh start"
		return 0
	fi

	# Check if keepalive script exists
	if [[ ! -f "${INSTALL_DIR}/vpn-keepalive.sh" ]]; then
		log_info "Keepalive script not found, skipping systemd service installation"
		return 0
	fi

	local service_file="/etc/systemd/system/vpn-keepalive.service"
	local template_file="${INSTALL_SCRIPT_DIR}/vpn-keepalive.service"

	# Check if template exists
	if [[ ! -f "$template_file" ]]; then
		log_warn "Service template not found: $template_file"
		log_warn "Skipping systemd service installation"
		return 0
	fi

	log_info "Installing systemd service for VPN keepalive daemon..."

	# Replace %INSTALL_DIR% placeholder with actual install directory
	sed "s|%INSTALL_DIR%|${INSTALL_DIR}|g" "$template_file" >"$service_file"

	# Verify the service file was created
	if [[ ! -f "$service_file" ]]; then
		log_error "Failed to create systemd service file"
		log_warn "Keepalive daemon can still be started manually: ${INSTALL_DIR}/vpn-keepalive.sh start"
		return 0 # Don't fail installation for optional feature
	fi

	# Reload systemd daemon to pick up new service
	if ! systemctl daemon-reload; then
		log_error "Failed to reload systemd daemon"
		log_warn "Keepalive daemon can still be started manually: ${INSTALL_DIR}/vpn-keepalive.sh start"
		return 0 # Don't fail installation for optional feature
	fi

	log_info "Systemd service installed: $service_file"

	return 0
}

# Enable and start keepalive service
#
# Enables and starts (or restarts) the systemd service for the VPN keepalive daemon.
# Only works if systemd is available and service is installed.
# Uses restart instead of start so it works whether the service is already running or not.
#
# Arguments:
#   None
#
# Returns:
#   0: Service enabled/started successfully (or skipped if not applicable)
#   1: Failed to enable/start service
#
# Side effects:
#   - Enables systemd service for auto-start on boot
#   - Starts or restarts the service immediately
enable_and_start_keepalive_service() {
	# Skip in dev mode
	if [[ $DEV_MODE -eq 1 ]]; then
		log_info "Skipping keepalive service enable (dev mode)"
		return 0
	fi

	# Check if systemd is available
	if ! command -v systemctl >/dev/null 2>&1; then
		log_warn "systemctl not found, cannot enable keepalive service"
		log_warn "Start keepalive manually: ${INSTALL_DIR}/vpn-keepalive.sh start"
		return 0
	fi

	# Check if service file exists
	local service_file="/etc/systemd/system/vpn-keepalive.service"
	if [[ ! -f "$service_file" ]]; then
		log_warn "Systemd service file not found: $service_file"
		log_warn "Install service first, then enable: systemctl enable --now vpn-keepalive"
		return 0
	fi

	# Check if keepalive is enabled in config
	if [[ -f "${INSTALL_DIR}/${CONFIG_NAME}" ]]; then
		local enable_keepalive
		enable_keepalive=$(grep -E "^ENABLE_KEEPALIVE=" "${INSTALL_DIR}/${CONFIG_NAME}" | cut -d'=' -f2 | tr -d '"' || echo "0")
		if [[ "$enable_keepalive" != "1" ]]; then
			log_warn "ENABLE_KEEPALIVE is not set to 1 in config file"
			log_warn "Set ENABLE_KEEPALIVE=1 in ${INSTALL_DIR}/${CONFIG_NAME}, then enable service"
			log_info "To enable later: systemctl enable --now vpn-keepalive"
			return 0
		fi
	else
		log_warn "Config file not found: ${INSTALL_DIR}/${CONFIG_NAME}"
		log_warn "Set ENABLE_KEEPALIVE=1 in config file, then enable service"
		return 0
	fi

	log_info "Enabling and starting VPN keepalive service..."

	# Enable service for auto-start on boot
	if ! systemctl enable vpn-keepalive 2>&1; then
		log_error "Failed to enable systemd service"
		log_warn "Keepalive daemon can still be started manually: ${INSTALL_DIR}/vpn-keepalive.sh start"
		return 0 # Don't fail installation for optional feature
	fi

	# Start or restart service immediately
	# Use restart instead of start so it works whether service is running or not
	local start_output
	start_output=$(systemctl restart vpn-keepalive 2>&1)
	local start_exit=$?
	if [[ $start_exit -ne 0 ]]; then
		log_error "Failed to start/restart systemd service"
		if [[ -n "$start_output" ]]; then
			log_error "Error details: $start_output"
		fi
		# Try to get more details from systemd journal
		local journal_output
		journal_output=$(journalctl -u vpn-keepalive -n 10 --no-pager 2>&1 | tail -5 || true)
		if [[ -n "$journal_output" ]]; then
			log_error "Systemd journal output:"
			# Use here-string to avoid subshell issues with while loop
			while IFS= read -r line; do
				log_error "  $line"
			done <<<"$journal_output"
		fi
		log_warn "Service enabled but not started. Check status: systemctl status vpn-keepalive"
		log_warn "Start manually: systemctl restart vpn-keepalive or ${INSTALL_DIR}/vpn-keepalive.sh start"
		return 0 # Don't fail installation for optional feature
	fi

	log_info "VPN keepalive service enabled and started successfully"
	return 0
}

# Install logrotate configuration for application logs
#
# Creates a logrotate configuration file to manage log rotation for both
# cron.log and vpn-monitor.log. Rotates logs daily, keeps 7 days of logs,
# compresses old logs. Only installs in production mode (not dev mode) and
# if logrotate is available.
#
# Arguments:
#   None
#
# Returns:
#   0: Logrotate config installed successfully (or skipped if not applicable)
#   1: Failed to install logrotate config
#
# Side effects:
#   Creates /etc/logrotate.d/vpn-monitor if logrotate is available
install_logrotate_config() {
	# Skip in dev mode (logrotate configs are system-wide)
	if [[ $DEV_MODE -eq 1 ]]; then
		log_info "Skipping logrotate config installation (dev mode)"
		return 0
	fi

	# Check if logrotate is available
	if ! command -v logrotate >/dev/null 2>&1; then
		log_warn "logrotate not found, skipping log rotation configuration"
		log_warn "Log files will grow indefinitely without manual rotation"
		return 0
	fi

	# Check if we have write access to /etc/logrotate.d
	if [[ ! -w /etc/logrotate.d ]]; then
		log_warn "Cannot write to /etc/logrotate.d, skipping log rotation configuration"
		log_warn "Log files will grow indefinitely without manual rotation"
		return 0
	fi

	local logrotate_config="/etc/logrotate.d/vpn-monitor"

	log_info "Installing logrotate configuration for application logs..."

	# Create logrotate configuration for both log files
	cat >"$logrotate_config" <<EOF
# UDM VPN Monitor - Log rotation
# Automatically rotated by logrotate
# Rotates both cron.log and vpn-monitor.log daily, keeps 7 days of compressed logs
${INSTALL_DIR}/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
    sharedscripts
    postrotate
        # No action needed after rotation
    endscript
}
EOF

	# Verify the config file was created
	if [[ -f "$logrotate_config" ]]; then
		log_info "Logrotate configuration installed: $logrotate_config"
		log_info "Log files will be rotated daily, keeping 7 days of compressed logs"
		return 0
	else
		log_error "Failed to create logrotate configuration"
		return 1
	fi
}

# Verify installation
#
# Verifies that the installation completed successfully by checking:
#   - Script file exists and is executable
#   - Library directory exists with required files
#   - Config file exists
#   - Cron entry exists (if cron setup was not skipped)
#
# Arguments:
#   None
#
# Returns:
#   0: Installation verified successfully
#   1: Verification failed (errors found)
verify_installation() {
	log_info "Verifying installation..."

	local errors=0

	# Check script exists and is executable
	if [[ ! -f "${INSTALL_DIR}/${SCRIPT_NAME}" ]]; then
		log_error "Script not found: ${INSTALL_DIR}/${SCRIPT_NAME}"
		errors=$((errors + 1))
	elif [[ ! -x "${INSTALL_DIR}/${SCRIPT_NAME}" ]]; then
		log_error "Script is not executable: ${INSTALL_DIR}/${SCRIPT_NAME}"
		errors=$((errors + 1))
	else
		log_info "Script verified: ${INSTALL_DIR}/${SCRIPT_NAME}"
	fi

	# Check library directory exists
	if [[ ! -d "${INSTALL_DIR}/lib" ]]; then
		log_error "Library directory not found: ${INSTALL_DIR}/lib"
		errors=$((errors + 1))
	else
		# Check for required library files (directly sourced by vpn-monitor.sh)
		local required_libs=(
			"logging.sh"
			"config.sh"
			"state.sh"
			"detection.sh"
			"recovery.sh"
			"lockfile.sh"
			"resources.sh"
		)
		# Also check for indirectly required files (sourced by other lib files)
		local indirect_libs=(
			"constants.sh"
			"common.sh"
			"config_schema.sh"
		)
		local missing_libs=0
		for lib_file in "${required_libs[@]}" "${indirect_libs[@]}"; do
			if [[ ! -f "${INSTALL_DIR}/lib/${lib_file}" ]]; then
				log_error "Required library file not found: ${INSTALL_DIR}/lib/${lib_file}"
				missing_libs=$((missing_libs + 1))
			fi
		done
		if [[ $missing_libs -eq 0 ]]; then
			log_info "Library directory verified: ${INSTALL_DIR}/lib (all required files present)"
		else
			errors=$((errors + missing_libs))
		fi
	fi

	# Check config exists
	if [[ ! -f "${INSTALL_DIR}/${CONFIG_NAME}" ]]; then
		log_error "Config not found: ${INSTALL_DIR}/${CONFIG_NAME}"
		errors=$((errors + 1))
	else
		log_info "Config verified: ${INSTALL_DIR}/${CONFIG_NAME}"
	fi

	# Check cron entry (only if cron setup was not skipped)
	if [[ $SKIP_CRON -eq 0 ]]; then
		if ! crontab -l 2>/dev/null | grep -q "vpn-monitor.sh"; then
			log_warn "Cron entry not found (may have been skipped if already exists)"
		else
			log_info "Cron entry verified"
		fi
	else
		log_info "Cron setup skipped (--no-cron flag used)"
	fi

	if [[ $errors -eq 0 ]]; then
		log_info "Installation verified successfully"
		return 0
	else
		log_error "Installation verification failed with $errors error(s)"
		return 1
	fi
}

# Detect local UDM IP from br0 interface
#
# Attempts to auto-detect the local UDM internal IP address from the br0 interface.
# Used during installation to help configure LOCAL_UDM_IP if not manually set.
#
# Arguments:
#   None
#
# Returns:
#   0: IP address detected and printed to stdout
#   1: Failed to detect IP address
#
# Output:
#   Prints detected IP address to stdout if found, empty string otherwise
#
# Note:
#   Uses 'ip addr show br0' to extract the first IPv4 address
#   Requires 'ip' command to be available
detect_local_udm_ip() {
	if ! check_command_available "ip"; then
		return 1
	fi

	# Get first IPv4 address from br0 interface
	# Format: "inet 192.168.1.1/24" -> extract "192.168.1.1"
	local br0_ip
	br0_ip=$(ip addr show br0 2>/dev/null | grep -oE 'inet [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1 | awk '{print $2}')

	# Validate extracted IP address format before returning
	if [[ -n "$br0_ip" ]] && validate_ip_address "$br0_ip"; then
		echo "$br0_ip"
		return 0
	fi

	return 1
}

# Check and setup routes for ping connectivity
#
# Verifies that LOCAL_UDM_IP is configured and route exists on br0 interface.
# If LOCAL_UDM_IP is not configured, attempts auto-detection from br0.
# Adds route if needed and tests ping connectivity to all internal IPs from all locations.
# Uses check_ping_connectivity() from detection.sh which has proper fallback logic
# for finding ping commands (ping vs ping6, timeout handling, etc.).
#
# Arguments:
#   None
#
# Returns:
#   0: Route setup successful (or not needed)
#   1: Route setup failed
#
# Side effects:
#   - May update config file with detected LOCAL_UDM_IP
#   - Adds route to br0 interface if needed
#   - Tests ping connectivity to all INTERNAL_PEER_IPs from all configured locations
check_and_setup_routes() {
	# Only proceed if ping checks are enabled and internal peer IPs are configured
	if [[ "${ENABLE_PING_CHECK:-0}" -ne 1 ]]; then
		return 0
	fi

	# Check if any location has internal IPs configured (location-based config)
	# Source config file to check for LOCATION_*_INTERNAL variables
	local config_file="${INSTALL_DIR}/${CONFIG_NAME}"
	local has_internal_ips=0
	if [[ -f "$config_file" ]]; then
		while IFS='=' read -r key value || [[ -n "$key" ]]; do
			# Skip comments and empty lines
			[[ "$key" =~ ^# ]] && continue
			[[ -z "$key" ]] && continue

			# Check for LOCATION_*_INTERNAL pattern
			if [[ "$key" =~ ^LOCATION_.+_INTERNAL$ ]]; then
				# Remove quotes and trim whitespace
				value=$(echo "$value" | sed "s/^[\"']//" | sed "s/[\"']$//")
				value=$(trim "$value")
				if [[ -n "$value" ]]; then
					has_internal_ips=1
					break
				fi
			fi
		done <"$config_file" || true
	fi

	if [[ $has_internal_ips -eq 0 ]]; then
		# No internal peer IPs configured - route setup not needed
		return 0
	fi

	log_info "Checking route setup for ping connectivity..."

	# Get LOCAL_UDM_IP from config
	local local_udm_ip="${LOCAL_UDM_IP:-}"

	# If LOCAL_UDM_IP is not configured, attempt auto-detection
	if [[ -z "$local_udm_ip" ]]; then
		log_info "LOCAL_UDM_IP not configured, attempting auto-detection from br0 interface..."
		if local_udm_ip=$(detect_local_udm_ip 2>/dev/null); then
			log_info "Auto-detected LOCAL_UDM_IP: $local_udm_ip"
			# Update config file with detected IP (reuse existing config_file variable)
			if [[ -f "$config_file" ]]; then
				update_config_value "$config_file" "LOCAL_UDM_IP" "$local_udm_ip" "^ENABLE_PING_CHECK="
				log_info "Updated config file with LOCAL_UDM_IP: $local_udm_ip"
			fi
		else
			log_warn "Failed to auto-detect LOCAL_UDM_IP from br0 interface"
			log_warn "Please configure LOCAL_UDM_IP manually in ${INSTALL_DIR}/${CONFIG_NAME}"
			return 1
		fi
	fi

	# Validate LOCAL_UDM_IP format using proper validation function
	# This function handles both IPv4 and IPv6 validation, including security checks
	if ! validate_ip_address "$local_udm_ip"; then
		log_warn "Invalid LOCAL_UDM_IP format: $local_udm_ip"
		return 1
	fi

	# Check if route exists, add if needed
	if ! check_command_or_warn "ip" "Cannot detect local IP"; then
		return 1
	fi

	# Check if route exists on br0
	if ip addr show br0 2>/dev/null | grep -q "inet ${local_udm_ip}/"; then
		log_info "Route already exists on br0: $local_udm_ip/32"
	else
		log_info "Adding route to br0: $local_udm_ip/32"
		if ip addr add "${local_udm_ip}/32" dev br0 2>/dev/null; then
			log_info "Route added successfully: $local_udm_ip/32 on br0"
		else
			# Check if route was added by another process (race condition)
			if ip addr show br0 2>/dev/null | grep -q "inet ${local_udm_ip}/"; then
				log_info "Route exists on br0 (added by another process): $local_udm_ip/32"
			else
				log_warn "Failed to add route to br0: $local_udm_ip/32"
				log_warn "You may need to add it manually: ip addr add $local_udm_ip/32 dev br0"
				return 1
			fi
		fi
	fi

	# Test ping connectivity to all internal peer IPs from all locations
	# Use check_ping_connectivity() from detection.sh which has proper fallback logic
	# This function handles ping6 fallback, timeout wrapping, and proper error messages
	# Set LOG_FILE for log_message() used by check_ping_connectivity()
	# If log directory exists, use it; otherwise log_message() will output to stderr
	if [[ -f "$config_file" ]]; then
		# Set LOG_FILE for log_message() used by check_ping_connectivity()
		# The log directory should exist (created by create_install_dir()), but handle gracefully if not
		if [[ -d "${INSTALL_DIR}/logs" ]]; then
			LOG_FILE="${INSTALL_DIR}/logs/vpn-monitor.log"
			export LOG_FILE
		fi
		# If LOG_FILE is not set, log_message() will output to stderr (which is fine for installation)

		local tested_any=0
		local ping_failed_any=0
		local location_name=""

		# Collect all internal IPs from all locations
		while IFS='=' read -r key value || [[ -n "$key" ]]; do
			# Skip comments and empty lines
			[[ "$key" =~ ^# ]] && continue
			[[ -z "$key" ]] && continue

			# Check for LOCATION_*_INTERNAL pattern
			if [[ "$key" =~ ^LOCATION_(.+)_INTERNAL$ ]]; then
				# Extract location name from variable name (e.g., LOCATION_NYC_INTERNAL -> NYC)
				location_name="${BASH_REMATCH[1]}"

				# Remove quotes and trim whitespace
				value=$(echo "$value" | sed "s/^[\"']//" | sed "s/[\"']$//")
				value=$(trim "$value")
				if [[ -n "$value" ]]; then
					# Split space-separated IPs into array
					# Use inline IFS to avoid affecting while loop (critical: while loop uses IFS='=')
					# Inline IFS=' ' only affects this read command, similar to while IFS='=' read
					local internal_ips_array
					IFS=' ' read -ra internal_ips_array <<<"$value"

					# Test each internal IP for this location
					for internal_ip in "${internal_ips_array[@]}"; do
						# Skip empty entries
						[[ -z "$internal_ip" ]] && continue

						tested_any=1
						# Use check_ping_connectivity() which logs its own messages and has proper fallback logic
						# This function handles ping6 fallback, timeout wrapping, and proper error messages
						# Note: check_ping_connectivity() uses log_message() which outputs to log file or stderr
						if ! check_ping_connectivity "$internal_ip" "$local_udm_ip" "$location_name"; then
							ping_failed_any=1
						fi
					done
				fi
			fi
		done <"$config_file" || true

		if [[ $tested_any -eq 0 ]]; then
			log_info "No internal IPs configured for ping testing"
		else
			log_info "Ping connectivity tests completed (route has been added and will be used during monitoring)"
			# Log VPN tunnel warning once if any ping tests failed (reduces noise)
			if [[ $ping_failed_any -eq 1 ]]; then
				log_warn "Some ping tests failed - this may be normal if the VPN tunnel is not yet established"
			fi
		fi
	fi

	return 0
}

# Validate configuration after installation
#
# Checks if at least one location is configured in the config file.
# If no locations found and not in silent mode, prompts the user to configure it.
# This helps catch configuration issues early during installation.
#
# Arguments:
#   None
#
# Returns:
#   0: Configuration is valid (or silent mode)
#   1: Configuration is invalid (no locations configured)
#
# Side effects:
#   - May prompt user for location configuration if empty and not in silent mode
#     (prompts for each location: name, external IP, optional internal IP; LOCAL_UDM_IP once on first;
#      after each location, prompts "Add another location?" to allow multiple)
#   - Logs warnings if configuration is invalid
validate_config_after_install() {
	local config_file="${INSTALL_DIR}/${CONFIG_NAME}"

	# Skip validation in silent mode or if config file doesn't exist
	if [[ $SILENT -eq 1 ]] || [[ ! -f "$config_file" ]]; then
		return 0
	fi

	# Check if at least one LOCATION_*_EXTERNAL variable exists and is not empty
	local location_found=0
	while IFS='=' read -r key value || [[ -n "$key" ]]; do
		# Skip comments and empty lines
		[[ "$key" =~ ^# ]] && continue
		[[ -z "$key" ]] && continue

		# Check for LOCATION_*_EXTERNAL pattern
		if [[ "$key" =~ ^LOCATION_.+_EXTERNAL$ ]]; then
			# Remove quotes and trim whitespace
			value=$(echo "$value" | sed "s/^[\"']//" | sed "s/[\"']$//")
			value=$(trim "$value")
			if [[ -n "$value" ]]; then
				location_found=1
				break
			fi
		fi
	done <"$config_file" || true

	# Check if any location was found
	if [[ $location_found -eq 0 ]]; then
		echo ""
		log_warn "⚠️  CONFIGURATION REQUIRED: No VPN locations configured"
		echo ""
		log_info "At least one LOCATION_*_EXTERNAL variable is required for the VPN monitor to work."
		log_info "Example: LOCATION_NYC_EXTERNAL=\"203.0.113.1\""
		log_info "This should be the external/public IP address of your remote VPN gateway."
		echo ""
		if [[ $INTERACTIVE -eq 0 ]]; then
			# Not in interactive mode, but config is empty - prompt user
			read -rp "Configure a location now? (yes/no) [yes]: " REPLY
			echo ""
			if [[ -z "$REPLY" ]] || [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]] || [[ $REPLY =~ ^[Yy]$ ]]; then
				local added_at_least_one=0
				local first_location=1
				local local_udm_ip_value=""
				local -A added_sanitized_names=()
				while true; do
					local location_name
					local external_peer_ip
					local internal_peer_ips
					read -rp "Remote location name (e.g., NYC, DC, OFFICE): " location_name
					read -rp "Remote external/public IP address: " external_peer_ip
					read -rp "Remote internal IP (optional, for ping checks; space-separated for multiple; empty to skip): " internal_peer_ips
					if [[ $first_location -eq 1 ]]; then
						read -rp "Local UDM IP (optional; source IP for ping checks; empty to skip or auto-detect later): " local_udm_ip_value
						local_udm_ip_value=$(trim "$local_udm_ip_value")
					fi
					location_name=$(trim "$location_name")
					external_peer_ip=$(trim "$external_peer_ip")
					internal_peer_ips=$(trim "$internal_peer_ips")
					if [[ -n "$location_name" ]] && [[ -n "$external_peer_ip" ]]; then
						local sanitized_name
						sanitized_name=$(sanitize_location_name_for_config "$location_name")
						if [[ -n "${added_sanitized_names[$sanitized_name]:-}" ]]; then
							log_warn "Location '${sanitized_name}' was already added; skipping duplicate."
						else
							{
								echo ""
								echo "# Location configuration"
								echo "LOCATION_${sanitized_name}_EXTERNAL=\"${external_peer_ip}\""
								echo "LOCATION_${sanitized_name}_INTERNAL=\"${internal_peer_ips}\""
							} >>"$config_file"
							added_sanitized_names["$sanitized_name"]=1
							if [[ $first_location -eq 1 ]] && [[ -n "$local_udm_ip_value" ]]; then
								update_config_value "$config_file" "LOCAL_UDM_IP" "$local_udm_ip_value" "^ENABLE_PING_CHECK="
								log_info "LOCAL_UDM_IP set in ${config_file}"
							fi
							log_info "Location '${location_name}' added to ${config_file}"
							added_at_least_one=1
							first_location=0
						fi
					else
						log_warn "Location name and external IP are required; this location was skipped."
					fi
					echo ""
					read -rp "Add another location? (yes/no) [no]: " REPLY
					echo ""
					if [[ -z "$REPLY" ]] || [[ $REPLY =~ ^[Nn][Oo]$ ]] || [[ $REPLY =~ ^[Nn]$ ]]; then
						break
					fi
					[[ "$REPLY" =~ ^[Yy][Ee][Ss]$ ]] || [[ "$REPLY" =~ ^[Yy]$ ]] || break
				done
				if [[ $added_at_least_one -eq 1 ]]; then
					log_info "Note: IP addresses will be validated when the monitor runs"
					return 0
				fi
				log_warn "No locations were added. Please configure manually."
				return 1
			else
				log_info "Skipping configuration. Please edit ${config_file} manually."
				return 1
			fi
		else
			# Interactive mode already handled this, but config is still empty
			log_warn "No locations configured after interactive configuration."
			log_warn "Please edit ${config_file} and add at least one LOCATION_*_EXTERNAL variable before running the monitor."
			return 1
		fi
	fi

	return 0
}

# Display next steps
#
# Displays post-installation instructions to the user.
# Shows configuration file location, testing instructions, and persistence notes.
# Skips output in silent mode.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
display_next_steps() {
	if [[ $SILENT -eq 1 ]]; then
		# Silent mode: minimal output
		return 0
	fi

	echo ""
	log_info "Installation complete!"
	echo ""
	log_info "Next steps:"
	echo "  1. Edit the configuration file:"
	echo "     ${INSTALL_DIR}/${CONFIG_NAME}"
	echo ""
	echo "  2. Configure at least one VPN location using location-based format:"
	echo "     LOCATION_<NAME>_EXTERNAL=\"external_ip\""
	echo "     LOCATION_<NAME>_INTERNAL=\"internal_ip\" (optional)"
	echo "     Example: LOCATION_NYC_EXTERNAL=\"203.0.113.1\""
	echo ""
	echo "  4. Test the script manually:"
	echo "     ${INSTALL_DIR}/${SCRIPT_NAME}"
	echo ""
	echo "  5. Monitor the log file:"
	echo "     tail -f ${INSTALL_DIR}/logs/vpn-monitor.log"
	echo ""
	if [[ $SKIP_CRON -eq 1 ]]; then
		log_warn "NOTE: Cron job was not installed (--no-cron flag used)"
		echo "  - Run the script manually or set up your own scheduling"
		echo "  - To install cron later, run: ./install.sh"
		echo ""
	else
		if [[ $DEV_MODE -eq 1 ]]; then
			log_warn "NOTE: Dev mode installation"
			echo "  - Files installed to: ${INSTALL_DIR}"
			echo "  - Cron job installed (if not skipped)"
			echo ""
		else
			echo ""
			log_warn "⚠️  IMPORTANT: Cron Job Persistence"
			log_warn "═══════════════════════════════════════════════════════════════"
			echo "  Cron jobs may be wiped during UniFi OS upgrades."
			echo "  If monitoring stops after an upgrade, re-run this installer:"
			echo "    ./install.sh --silent"
			echo ""
			echo "  Or manually restore the cron job:"
			echo "    crontab -e"
			echo "    # Add: $(grep CRON_SCHEDULE "${INSTALL_DIR}/${CONFIG_NAME}" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "*/1 * * * *") ${INSTALL_DIR}/${SCRIPT_NAME} >> ${INSTALL_DIR}/logs/cron.log 2>&1"
			log_warn "═══════════════════════════════════════════════════════════════"
			echo ""
			log_info "Persistence Notes:"
			echo "  - Scripts survive reboots (stored in /data/)"
			echo "  - Configuration files persist across reboots"
			echo "  - Log files persist across reboots"
			echo ""
		fi
	fi
	log_info "To uninstall, run:"
	echo "  ./uninstall.sh"
	echo ""
	echo "  Or manually remove:"
	echo "  - ${INSTALL_DIR}/"
	if [[ $SKIP_CRON -eq 0 ]]; then
		echo "  - Cron entry (crontab -e)"
	fi
	echo ""
}

# Display help message
#
# Prints usage information and available options for the install script.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
display_help() {
	echo "Usage: $0 [OPTIONS]"
	echo ""
	echo "Options:"
	echo "  --no-cron         Install without setting up cron job"
	echo "  --silent          Perform installation silently (no prompts)"
	echo "  --interactive     Prompt for each config value with defaults"
	echo "  --overwrite-conf       Overwrite existing config file (only works with --silent)"
	echo "  --append-missing-config  Auto-append new config fields to existing config (only with --silent)"
	echo "  --dev                  Install to current working directory (dev mode)"
	echo "  --keepalive-only  Only install and enable keepalive daemon (requires existing installation)"
	echo "  --help, -h        Show this help message"
	echo ""
	echo "Examples:"
	echo "  $0                                    # Standard installation"
	echo "  $0 --interactive                      # Interactive config setup"
	echo "  $0 --silent                          # Silent installation, preserve existing config"
	echo "  $0 --silent --overwrite-conf          # Silent installation, overwrite config"
	echo "  $0 --silent --append-missing-config   # Silent installation, append new config fields"
	echo "  $0 --silent --no-cron                 # Silent installation, no cron"
	echo "  $0 --dev                              # Install to current directory (dev mode)"
	echo "  $0 --dev --silent --no-cron           # Dev mode, silent, no cron"
	echo "  $0 --interactive --dev                # Interactive config, dev mode"
	echo "  $0 --silent --no-cron --overwrite-conf  # Silent installation, no cron, overwrite config"
	echo "  $0 --keepalive-only                   # Install and enable keepalive daemon only"
	echo ""
}

# Parse command-line arguments
#
# Processes command-line arguments and sets corresponding global flags.
# Also determines INSTALL_DIR based on DEV_MODE flag.
#
# Arguments:
#   $@: Command-line arguments
#
# Supported options:
#   --no-cron: Skip cron job setup
#   --silent: Perform installation silently (no prompts)
#   --interactive: Prompt for each config value with defaults
#   --overwrite-conf: Overwrite existing config file (only with --silent)
#   --dev: Install to current directory instead of /data/vpn-monitor
#   --keepalive-only: Only install and enable keepalive daemon (requires existing installation)
#   --help, -h: Display help message and exit
#
# Returns:
#   0: Always succeeds (exits with 0 for --help)
#   1: Invalid argument provided (exits script)
#
# Side effects:
#   Sets global flags: SKIP_CRON, SILENT, INTERACTIVE, OVERWRITE_CONF, DEV_MODE, KEEPALIVE_ONLY
#   Sets INSTALL_DIR based on DEV_MODE
parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--no-cron)
			SKIP_CRON=1
			if [[ $SILENT -eq 0 ]]; then
				log_info "Cron setup will be skipped (--no-cron flag)"
			fi
			shift
			;;
		--silent)
			SILENT=1
			shift
			;;
		--interactive)
			INTERACTIVE=1
			if [[ $SILENT -eq 0 ]]; then
				log_info "Interactive mode enabled - will prompt for config values"
			fi
			shift
			;;
		--overwrite-conf)
			OVERWRITE_CONF=1
			shift
			;;
		--append-missing-config)
			APPEND_MISSING_CONFIG=1
			shift
			;;
		--dev)
			DEV_MODE=1
			if [[ $SILENT -eq 0 ]]; then
				log_info "Dev mode enabled - installing to current working directory"
			fi
			shift
			;;
		--keepalive-only)
			KEEPALIVE_ONLY=1
			if [[ $SILENT -eq 0 ]]; then
				log_info "Keepalive-only mode - will only install and enable keepalive daemon"
			fi
			shift
			;;
		--help | -h)
			display_help
			exit 0
			;;
		*)
			log_error "Invalid argument: $1"
			echo ""
			display_help
			exit 1
			;;
		esac
	done

	# Set INSTALL_DIR based on DEV_MODE
	if [[ $DEV_MODE -eq 1 ]]; then
		INSTALL_DIR="$(pwd)/vpn-monitor"
	else
		INSTALL_DIR="/data/vpn-monitor"
	fi

	# Validate flag combinations
	if [[ $OVERWRITE_CONF -eq 1 ]] && [[ $SILENT -eq 0 ]]; then
		log_warn "Warning: --overwrite-conf is only effective with --silent flag"
		log_warn "In interactive mode, you will be prompted to overwrite the config file"
	fi

	if [[ $APPEND_MISSING_CONFIG -eq 1 ]] && [[ $SILENT -eq 0 ]]; then
		log_warn "Warning: --append-missing-config is only effective with --silent flag"
		APPEND_MISSING_CONFIG=0
	fi

	if [[ $INTERACTIVE -eq 1 ]] && [[ $SILENT -eq 1 ]]; then
		log_error "Error: --interactive and --silent flags cannot be used together"
		log_error "Interactive mode requires user prompts, which conflicts with silent mode"
		exit 1
	fi

	if [[ $KEEPALIVE_ONLY -eq 1 ]]; then
		if [[ $INTERACTIVE -eq 1 ]] || [[ $OVERWRITE_CONF -eq 1 ]] || [[ $SKIP_CRON -eq 1 ]]; then
			log_warn "Warning: --keepalive-only mode ignores --interactive, --overwrite-conf, and --no-cron flags"
		fi
	fi
}

# Main installation
#
# Main entry point for the installation script.
# Orchestrates the complete installation process.
#
# Arguments:
#   $@: Command-line arguments (passed to parse_args)
#
# Returns:
#   0: Installation successful
#   1: Installation failed
#
# Execution flow:
#   1. Parse command-line arguments
#   2. Check root privileges (unless dev mode)
#   3. Check UDM system (unless dev mode)
#   4. Create installation directory
#   5. Install scripts and config
#   6. Setup cron job (unless skipped)
#   7. Verify installation
#   8. Display next steps
main() {
	# Parse command-line arguments
	parse_args "$@"

	if [[ $SILENT -eq 0 ]]; then
		if [[ $KEEPALIVE_ONLY -eq 1 ]]; then
			log_info "UDM VPN Monitor - Keepalive Installation"
			log_info "=========================================="
		else
			log_info "UDM VPN Monitor Installation"
			log_info "=============================="
		fi
		if [[ $DEV_MODE -eq 1 ]]; then
			log_info "Dev mode: Installing to ${INSTALL_DIR}"
		fi
		echo ""
	fi

	# Handle keepalive-only mode
	if [[ $KEEPALIVE_ONLY -eq 1 ]]; then
		# Skip root check in dev mode
		if [[ $DEV_MODE -eq 0 ]]; then
			check_root
		fi

		# Check if installation exists
		if [[ ! -d "$INSTALL_DIR" ]]; then
			log_error "Installation directory not found: $INSTALL_DIR"
			log_error "Please run full installation first: ./install.sh"
			exit 1
		fi

		if [[ ! -f "${INSTALL_DIR}/${CONFIG_NAME}" ]]; then
			log_error "Configuration file not found: ${INSTALL_DIR}/${CONFIG_NAME}"
			log_error "Please run full installation first: ./install.sh"
			exit 1
		fi

		# Check if keepalive script exists, if not install it
		if [[ ! -f "${INSTALL_DIR}/vpn-keepalive.sh" ]]; then
			log_info "Keepalive script not found, installing..."
			if [[ ! -f "${INSTALL_SCRIPT_DIR}/vpn-keepalive.sh" ]]; then
				log_error "Keepalive script template not found: ${INSTALL_SCRIPT_DIR}/vpn-keepalive.sh"
				exit 1
			fi
			cp "${INSTALL_SCRIPT_DIR}/vpn-keepalive.sh" "${INSTALL_DIR}/vpn-keepalive.sh"
			chmod +x "${INSTALL_DIR}/vpn-keepalive.sh"
			log_info "Installed vpn-keepalive.sh"
		fi

		# Ensure ENABLE_KEEPALIVE=1 in config file
		if grep -q "^ENABLE_KEEPALIVE=" "${INSTALL_DIR}/${CONFIG_NAME}" 2>/dev/null; then
			# Update existing setting
			if [[ "$(grep "^ENABLE_KEEPALIVE=" "${INSTALL_DIR}/${CONFIG_NAME}" | cut -d'=' -f2 | tr -d '"')" != "1" ]]; then
				log_info "Setting ENABLE_KEEPALIVE=1 in config file..."
				sed -i 's/^ENABLE_KEEPALIVE=.*/ENABLE_KEEPALIVE=1/' "${INSTALL_DIR}/${CONFIG_NAME}"
			fi
		else
			# Add setting if not present
			log_info "Adding ENABLE_KEEPALIVE=1 to config file..."
			{
				echo ""
				echo "# VPN Keepalive Daemon"
				echo "ENABLE_KEEPALIVE=1"
			} >>"${INSTALL_DIR}/${CONFIG_NAME}"
		fi

		# Install systemd service
		install_keepalive_service

		# Enable and start service
		enable_and_start_keepalive_service

		if [[ $SILENT -eq 0 ]]; then
			echo ""
			log_info "Keepalive installation complete!"
			echo ""
			log_info "Keepalive daemon status:"
			systemctl status vpn-keepalive --no-pager -l 2>/dev/null || /data/vpn-monitor/vpn-keepalive.sh status 2>/dev/null || log_warn "Could not check keepalive status"
			echo ""
		fi

		exit 0
	fi

	# Normal installation flow
	# Skip root check in dev mode
	if [[ $DEV_MODE -eq 0 ]]; then
		check_root
	fi
	check_udm
	create_install_dir

	# Display upgrade information if existing installation detected
	display_upgrade_info

	install_scripts

	# Validate configuration after installation
	validate_config_after_install

	# Check and setup routes for ping connectivity (if ping checks enabled)
	# Load config values needed for route setup
	if [[ -f "${INSTALL_DIR}/${CONFIG_NAME}" ]]; then
		# Source config to get ENABLE_PING_CHECK, LOCAL_UDM_IP
		# Note: Internal IPs are now checked from location-based config in check_and_setup_routes()
		# shellcheck source=/dev/null
		source "${INSTALL_DIR}/${CONFIG_NAME}" 2>/dev/null || true
		ENABLE_PING_CHECK="${ENABLE_PING_CHECK:-1}"
		LOCAL_UDM_IP="${LOCAL_UDM_IP:-}"
		check_and_setup_routes || log_warn "Route setup completed with warnings (ping checks may not work until LOCAL_UDM_IP is configured)"
	fi

	# Setup cron only if not skipped
	if [[ $SKIP_CRON -eq 0 ]]; then
		setup_cron
		# Install logrotate configuration for application logs
		install_logrotate_config
	else
		log_info "Skipping cron setup (--no-cron flag used)"
	fi

	# Install systemd service for keepalive daemon
	install_keepalive_service

	# Enable and start keepalive service if enabled in config
	if [[ -f "${INSTALL_DIR}/${CONFIG_NAME}" ]]; then
		local enable_keepalive
		enable_keepalive=$(grep -E "^ENABLE_KEEPALIVE=" "${INSTALL_DIR}/${CONFIG_NAME}" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "0")
		if [[ "$enable_keepalive" == "1" ]]; then
			enable_and_start_keepalive_service
		else
			# If service is already running but keepalive is disabled, restart it to pick up service file changes
			if command -v systemctl >/dev/null 2>&1 && systemctl is-active vpn-keepalive >/dev/null 2>&1; then
				log_info "Service is running but keepalive is disabled, restarting to pick up service file changes..."
				if systemctl restart vpn-keepalive 2>&1; then
					log_info "Service restarted successfully"
				else
					log_warn "Failed to restart service, but service file was updated"
					log_warn "Restart manually: systemctl restart vpn-keepalive"
				fi
			fi
		fi
	fi

	if verify_installation; then
		display_next_steps
		exit 0
	else
		log_error "Installation completed with errors"
		exit 1
	fi
}

# Run main
main "$@"
