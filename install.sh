#!/bin/bash
#
# UDM VPN Monitor Installation Script
# Installs the VPN monitoring script with cron-based execution
#
# Designed for UniFi Dream Machine (UDM) running UniFi OS 4.3+
#
# Version: 0.0.1
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

# Verify lib directory exists before sourcing
# The lib directory should be present from the installation package extraction
if [[ ! -d "${INSTALL_SCRIPT_DIR}/lib" ]]; then
	echo "[ERROR] Library directory not found: ${INSTALL_SCRIPT_DIR}/lib"
	echo "[ERROR] Please ensure the installation package was extracted correctly"
	echo "[ERROR] Required library files: common.sh, config.sh, config_schema.sh, constants.sh, detection.sh, lockfile.sh, logging.sh, recovery.sh, state.sh"
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

# Check if we're on a UDM
#
# Verifies that the system is a UniFi Dream Machine by checking for /data directory.
# Skips check if DEV_MODE is enabled (for testing on non-UDM systems).
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
		log_error "This script is designed for UniFi Dream Machines"
		log_error "/data directory not found"
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
	local param_name="$1"
	local default_value="$2"
	local description="$3"
	local user_input=""

	# Display prompt with default
	if [[ -n "$default_value" ]]; then
		read -p "${description} [${default_value}]: " user_input
	else
		read -p "${description}: " user_input
	fi

	# Use default if empty
	if [[ -z "$user_input" ]]; then
		echo "$default_value"
	else
		echo "$user_input"
	fi
}

# Create config file interactively
#
# Prompts the user for each configuration value with defaults.
# Creates the config file with user-provided values.
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

	# Default values
	local default_peer_ips=""
	local default_vpn_name="Site-to-Site VPN"
	local default_tier1=1
	local default_tier2=3
	local default_tier3=5
	local default_cooldown=15
	local default_max_restarts=3
	local default_log_file="${INSTALL_DIR}/logs/vpn-monitor.log"
	local default_state_dir="${INSTALL_DIR}"
	local default_cron_schedule="*/1 * * * *"
	local default_lockfile_timeout=300
	local default_enable_ping=1
	local default_ping_count=3
	local default_ping_timeout=2
	local default_debug=0

	# Prompt for each value
	local external_peer_ips
	external_peer_ips=$(prompt_config_value "EXTERNAL_PEER_IPS" "$default_peer_ips" "External/Public peer IP address(es) to monitor (space-separated, external/public IPs)")

	local internal_peer_ips
	internal_peer_ips=$(prompt_config_value "INTERNAL_PEER_IPS" "" "Internal/Private peer IP address(es) (optional, space-separated, for ping checks, empty to skip)")

	local vpn_name
	vpn_name=$(prompt_config_value "VPN_NAME" "$default_vpn_name" "VPN connection identifier/name")

	local tier1
	tier1=$(prompt_config_value "TIER1_THRESHOLD" "$default_tier1" "Tier 1 threshold (failures before logging)")

	local tier2
	tier2=$(prompt_config_value "TIER2_THRESHOLD" "$default_tier2" "Tier 2 threshold (failures before surgical cleanup)")

	local tier3
	tier3=$(prompt_config_value "TIER3_THRESHOLD" "$default_tier3" "Tier 3 threshold (failures before full restart)")

	local cooldown
	cooldown=$(prompt_config_value "COOLDOWN_MINUTES" "$default_cooldown" "Cooldown period after restart (minutes)")

	local max_restarts
	max_restarts=$(prompt_config_value "MAX_RESTARTS_PER_HOUR" "$default_max_restarts" "Maximum restarts per hour")

	local cron_schedule
	cron_schedule=$(prompt_config_value "CRON_SCHEDULE" "$default_cron_schedule" "Cron schedule (e.g., '*/1 * * * *' for every minute)")

	local lockfile_timeout
	lockfile_timeout=$(prompt_config_value "LOCKFILE_TIMEOUT" "$default_lockfile_timeout" "Lockfile timeout (seconds)")

	local enable_ping
	enable_ping=$(prompt_config_value "ENABLE_PING_CHECK" "$default_enable_ping" "Enable ping connectivity check (0 or 1)")

	local ping_count
	ping_count=$(prompt_config_value "PING_COUNT" "$default_ping_count" "Ping count (number of packets)")

	local ping_timeout
	ping_timeout=$(prompt_config_value "PING_TIMEOUT" "$default_ping_timeout" "Ping timeout per packet (seconds)")

	local debug
	debug=$(prompt_config_value "DEBUG" "$default_debug" "Enable debug logging (0 or 1)")

	local default_enable_keepalive="1"
	local enable_keepalive
	enable_keepalive=$(prompt_config_value "ENABLE_KEEPALIVE" "$default_enable_keepalive" "Enable VPN keepalive daemon (0 or 1)")

	local default_keepalive_interval="30"
	local keepalive_interval
	keepalive_interval=$(prompt_config_value "KEEPALIVE_INTERVAL" "$default_keepalive_interval" "Keepalive ping interval (seconds)")

	local default_keepalive_ping_count="1"
	local keepalive_ping_count
	keepalive_ping_count=$(prompt_config_value "KEEPALIVE_PING_COUNT" "$default_keepalive_ping_count" "Keepalive ping count (packets)")

	# Create config file
	cat >"${INSTALL_DIR}/${CONFIG_NAME}" <<EOF
# UDM VPN Monitor Configuration
# Generated via interactive installation

# External/Public peer IP address(es) to monitor (space-separated list)
# This should be the EXTERNAL/PUBLIC IP address(es) of the remote VPN gateway(s)
# This is the IP address used to establish the IPsec tunnel and check xfrm state
EXTERNAL_PEER_IPS="${external_peer_ips}"

# Internal/Private peer IP address(es) to monitor (space-separated list)
# This should be the INTERNAL/PRIVATE IP address(es) of the remote VPN gateway(s)
# This is the IP address used for ping connectivity checks through the tunnel
# Must match the order of EXTERNAL_PEER_IPS (first internal IP corresponds to first external IP)
# If empty, ping checks will use EXTERNAL_PEER_IPS instead
INTERNAL_PEER_IPS="${internal_peer_ips}"

# VPN connection identifier/name (optional, for logging)
VPN_NAME="${vpn_name}"

# Failure threshold: number of consecutive failures before taking action
TIER1_THRESHOLD=${tier1}
TIER2_THRESHOLD=${tier2}
TIER3_THRESHOLD=${tier3}

# Cooldown period after restart (minutes)
COOLDOWN_MINUTES=${cooldown}

# Maximum restarts per hour (rate limiting)
MAX_RESTARTS_PER_HOUR=${max_restarts}

# Log file location (must be in /data/ for persistence)
LOG_FILE="${default_log_file}"

# State directory (for counter files and lockfiles)
STATE_DIR="${default_state_dir}"

# Cron schedule (cron format: minute hour day month weekday)
CRON_SCHEDULE="${cron_schedule}"

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
		log_info "Installed ${CONFIG_NAME} (please customize it)"
	else
		log_warn "Config template not found, creating default"
		cat >"${INSTALL_DIR}/${CONFIG_NAME}" <<EOF
# UDM VPN Monitor Configuration
EXTERNAL_PEER_IPS=""
INTERNAL_PEER_IPS=""
VPN_NAME="Site-to-Site VPN"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
COOLDOWN_MINUTES=15
MAX_RESTARTS_PER_HOUR=3
LOG_FILE="${INSTALL_DIR}/logs/vpn-monitor.log"
STATE_DIR="${INSTALL_DIR}"
CRON_SCHEDULE="*/1 * * * *"
LOCKFILE_TIMEOUT=300
ENABLE_PING_CHECK=1
PING_COUNT=3
PING_TIMEOUT=2
ENABLE_KEEPALIVE=1
KEEPALIVE_INTERVAL=30
KEEPALIVE_PING_COUNT=1
DEBUG=0
EOF
	fi
}

# Install scripts
#
# Copies the main VPN monitor script, library files, and configuration file to the installation directory.
# Handles existing config files based on SILENT and OVERWRITE_CONF flags.
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
#   - Sets executable permissions on scripts
#   - Installs config file (may prompt user in interactive mode)
install_scripts() {
	log_info "Installing scripts..."

	# Copy main script
	if [[ -f "${INSTALL_SCRIPT_DIR}/${SCRIPT_NAME}" ]]; then
		cp "${INSTALL_SCRIPT_DIR}/${SCRIPT_NAME}" "${INSTALL_DIR}/${SCRIPT_NAME}"
		chmod +x "${INSTALL_DIR}/${SCRIPT_NAME}"
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
		log_error "Library directory not found: ${INSTALL_SCRIPT_DIR}/lib"
		log_error "vpn-monitor.sh requires library files to function"
		exit 1
	fi

	# Copy keepalive script (optional utility)
	if [[ -f "${INSTALL_SCRIPT_DIR}/vpn-keepalive.sh" ]]; then
		cp "${INSTALL_SCRIPT_DIR}/vpn-keepalive.sh" "${INSTALL_DIR}/vpn-keepalive.sh"
		chmod +x "${INSTALL_DIR}/vpn-keepalive.sh"
		log_info "Installed vpn-keepalive.sh"
	fi

	# Copy log analysis script (optional utility)
	if [[ -f "${INSTALL_SCRIPT_DIR}/analyze-logs.sh" ]]; then
		cp "${INSTALL_SCRIPT_DIR}/analyze-logs.sh" "${INSTALL_DIR}/analyze-logs.sh"
		chmod +x "${INSTALL_DIR}/analyze-logs.sh"
		log_info "Installed analyze-logs.sh (log analysis utility)"
	fi

	# Copy utility checker script (optional utility)
	if [[ -f "${INSTALL_SCRIPT_DIR}/check-utilities.sh" ]]; then
		cp "${INSTALL_SCRIPT_DIR}/check-utilities.sh" "${INSTALL_DIR}/check-utilities.sh"
		chmod +x "${INSTALL_DIR}/check-utilities.sh"
		log_info "Installed check-utilities.sh (utility availability checker)"
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
			fi
		else
			# Non-interactive, non-silent mode: ask user
			echo ""
			log_warn "Config file already exists: ${INSTALL_DIR}/${CONFIG_NAME}"
			read -p "Overwrite existing config file? (yes/no) [no]: " -r
			echo ""
			if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
				install_config_file "Overwriting existing config file"
			else
				log_info "Preserving existing config file: ${INSTALL_DIR}/${CONFIG_NAME}"
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
#   1: No valid cron schedule found (use default)
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
	schedule=$(echo "$schedule" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

	# Remove quotes if present
	if [[ "$schedule" =~ ^\".*\"$ ]]; then
		schedule="${schedule#\"}"
		schedule="${schedule%\"}"
	elif [[ "$schedule" =~ ^\'.*\'$ ]]; then
		schedule="${schedule#\'}"
		schedule="${schedule%\'}"
	fi

	# Trim whitespace again after quote removal
	schedule=$(echo "$schedule" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

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

	local cron_entry
	cron_entry="${cron_schedule} ${INSTALL_DIR}/${SCRIPT_NAME} >> ${INSTALL_DIR}/cron.log 2>&1"

	# Note: cron.log will be created automatically on first cron run.
	# Log rotation is configured via logrotate (see install_logrotate_config function).

	# Check if cron entry already exists
	if crontab -l 2>/dev/null | grep -q "vpn-monitor.sh"; then
		log_warn "Cron job already exists, skipping..."
		log_info "To update the cron schedule:"
		log_info "  1. Edit ${INSTALL_DIR}/${CONFIG_NAME} and set CRON_SCHEDULE"
		log_info "  2. Remove old cron entry: crontab -e"
		log_info "  3. Re-run install.sh to install new schedule"
	else
		# Add cron entry
		(
			crontab -l 2>/dev/null || true
			echo "$cron_entry"
		) | crontab -
		log_info "Cron job installed with schedule: $cron_schedule"
	fi

	# Display current cron entries
	log_info "Current cron entries:"
	crontab -l 2>/dev/null | grep -E "(vpn-monitor|^#)" || log_warn "No cron entries found"
}

# Install systemd service for keepalive daemon
#
# Installs and enables the systemd service file for the VPN keepalive daemon.
# Only installs if systemd is available, keepalive is enabled in config, and not in dev mode.
#
# Returns:
#   0: Service installed successfully (or skipped if not applicable)
#   1: Failed to install service
#
# Side effects:
#   - Creates /etc/systemd/system/vpn-keepalive.service
#   - Reloads systemd daemon
#   - Enables service (but doesn't start it - user must enable keepalive first)
install_keepalive_service() {
	# Skip in dev mode (systemd services are system-wide)
	if [[ $DEV_MODE -eq 1 ]]; then
		log_info "Skipping systemd service installation (dev mode)"
		return 0
	fi

	# Check if systemd is available
	if ! command -v systemctl >/dev/null 2>&1; then
		log_warn "systemctl not found, skipping systemd service installation"
		log_warn "Keepalive daemon must be started manually: ${INSTALL_DIR}/vpn-keepalive.sh start"
		return 0
	fi

	# Check if we have write access to /etc/systemd/system
	if [[ ! -w /etc/systemd/system ]]; then
		log_warn "Cannot write to /etc/systemd/system, skipping systemd service installation"
		log_warn "Keepalive daemon must be started manually: ${INSTALL_DIR}/vpn-keepalive.sh start"
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
# Enables and starts the systemd service for the VPN keepalive daemon.
# Only works if systemd is available and service is installed.
#
# Returns:
#   0: Service enabled/started successfully (or skipped if not applicable)
#   1: Failed to enable/start service
#
# Side effects:
#   - Enables systemd service for auto-start on boot
#   - Starts the service immediately
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
	if ! systemctl enable vpn-keepalive >/dev/null 2>&1; then
		log_error "Failed to enable systemd service"
		log_warn "Keepalive daemon can still be started manually: ${INSTALL_DIR}/vpn-keepalive.sh start"
		return 0 # Don't fail installation for optional feature
	fi

	# Start service immediately
	if ! systemctl start vpn-keepalive >/dev/null 2>&1; then
		log_error "Failed to start systemd service"
		log_warn "Service enabled but not started. Check status: systemctl status vpn-keepalive"
		log_warn "Start manually: systemctl start vpn-keepalive or ${INSTALL_DIR}/vpn-keepalive.sh start"
		return 0 # Don't fail installation for optional feature
	fi

	log_info "VPN keepalive service enabled and started successfully"
	return 0
}

# Install logrotate configuration for cron.log
#
# Creates a logrotate configuration file to manage cron.log rotation.
# Rotates cron.log daily, keeps 7 days of logs, compresses old logs.
# Only installs in production mode (not dev mode) and if logrotate is available.
#
# Returns:
#   0: Logrotate config installed successfully (or skipped if not applicable)
#   1: Failed to install logrotate config
#
# Side effects:
#   Creates /etc/logrotate.d/vpn-monitor-cron if logrotate is available
install_logrotate_config() {
	# Skip in dev mode (logrotate configs are system-wide)
	if [[ $DEV_MODE -eq 1 ]]; then
		log_info "Skipping logrotate config installation (dev mode)"
		return 0
	fi

	# Check if logrotate is available
	if ! command -v logrotate >/dev/null 2>&1; then
		log_warn "logrotate not found, skipping log rotation configuration"
		log_warn "cron.log will grow indefinitely without manual rotation"
		return 0
	fi

	# Check if we have write access to /etc/logrotate.d
	if [[ ! -w /etc/logrotate.d ]]; then
		log_warn "Cannot write to /etc/logrotate.d, skipping log rotation configuration"
		log_warn "cron.log will grow indefinitely without manual rotation"
		return 0
	fi

	local logrotate_config="/etc/logrotate.d/vpn-monitor-cron"

	log_info "Installing logrotate configuration for cron.log..."

	# Create logrotate configuration
	cat >"$logrotate_config" <<EOF
# UDM VPN Monitor - cron.log rotation
# Automatically rotated by logrotate
${INSTALL_DIR}/cron.log {
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
		log_info "cron.log will be rotated daily, keeping 7 days of compressed logs"
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
	if ! command -v ip >/dev/null 2>&1; then
		return 1
	fi

	# Get first IPv4 address from br0 interface
	# Format: "inet 192.168.1.1/24" -> extract "192.168.1.1"
	local br0_ip
	br0_ip=$(ip addr show br0 2>/dev/null | grep -oE 'inet [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1 | awk '{print $2}')

	if [[ -n "$br0_ip" ]]; then
		echo "$br0_ip"
		return 0
	fi

	return 1
}

# Check and setup routes for ping connectivity
#
# Verifies that LOCAL_UDM_IP is configured and route exists on br0 interface.
# If LOCAL_UDM_IP is not configured, attempts auto-detection from br0.
# Adds route if needed and tests ping connectivity.
#
# Returns:
#   0: Route setup successful (or not needed)
#   1: Route setup failed
#
# Side effects:
#   - May update config file with detected LOCAL_UDM_IP
#   - Adds route to br0 interface if needed
#   - Tests ping connectivity to first INTERNAL_PEER_IP
check_and_setup_routes() {
	# Only proceed if ping checks are enabled and internal peer IPs are configured
	if [[ "${ENABLE_PING_CHECK:-0}" -ne 1 ]]; then
		return 0
	fi

	# Check if INTERNAL_PEER_IPS is configured
	if [[ -z "${INTERNAL_PEER_IPS:-}" ]]; then
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
			# Update config file with detected IP
			local config_file="${INSTALL_DIR}/${CONFIG_NAME}"
			if [[ -f "$config_file" ]]; then
				# Escape special characters for sed replacement
				local local_udm_ip_escaped
				local_udm_ip_escaped=$(printf '%s\n' "$local_udm_ip" | sed 's/\\/\\\\/g' | sed 's/&/\\&/g' | sed 's/|/\\|/g')
				if grep -q "^LOCAL_UDM_IP=" "$config_file"; then
					# Update existing line
					sed -i "s|^LOCAL_UDM_IP=.*|LOCAL_UDM_IP=\"${local_udm_ip_escaped}\"|" "$config_file"
				else
					# Add new line after ENABLE_PING_CHECK
					sed -i "/^ENABLE_PING_CHECK=/a LOCAL_UDM_IP=\"${local_udm_ip}\"" "$config_file"
				fi
				log_info "Updated config file with LOCAL_UDM_IP: $local_udm_ip"
			fi
		else
			log_warn "Failed to auto-detect LOCAL_UDM_IP from br0 interface"
			log_warn "Please configure LOCAL_UDM_IP manually in ${INSTALL_DIR}/${CONFIG_NAME}"
			return 1
		fi
	fi

	# Validate LOCAL_UDM_IP format (basic check)
	if [[ ! "$local_udm_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		log_warn "Invalid LOCAL_UDM_IP format: $local_udm_ip"
		return 1
	fi

	# Check if route exists, add if needed
	if ! command -v ip >/dev/null 2>&1; then
		log_warn "ip command not available, cannot check/add route"
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

	# Test ping connectivity to first internal peer IP
	local IFS=' '
	local -a internal_peer_ips_array
	read -ra internal_peer_ips_array <<<"$INTERNAL_PEER_IPS"
	if [[ ${#internal_peer_ips_array[@]} -gt 0 ]] && [[ -n "${internal_peer_ips_array[0]}" ]]; then
		local first_internal_ip="${internal_peer_ips_array[0]}"
		log_info "Testing ping connectivity to $first_internal_ip from $local_udm_ip..."
		if ping -I "$local_udm_ip" -c 1 -W 2 "$first_internal_ip" >/dev/null 2>&1; then
			log_info "Ping test successful: $first_internal_ip is reachable from $local_udm_ip"
		else
			log_warn "Ping test failed: $first_internal_ip is not reachable from $local_udm_ip"
			log_warn "This may be normal if the VPN tunnel is not yet established"
			log_warn "The route has been added and will be used during monitoring"
		fi
	fi

	return 0
}

# Validate configuration after installation
#
# Checks if EXTERNAL_PEER_IPS is configured in the config file.
# If empty and not in silent mode, prompts the user to configure it.
# This helps catch configuration issues early during installation.
#
# Returns:
#   0: Configuration is valid (or silent mode)
#   1: Configuration is invalid (EXTERNAL_PEER_IPS is empty)
#
# Side effects:
#   - May prompt user for EXTERNAL_PEER_IPS if empty and not in silent mode
#   - Logs warnings if configuration is invalid
validate_config_after_install() {
	local config_file="${INSTALL_DIR}/${CONFIG_NAME}"

	# Skip validation in silent mode or if config file doesn't exist
	if [[ $SILENT -eq 1 ]] || [[ ! -f "$config_file" ]]; then
		return 0
	fi

	# Extract EXTERNAL_PEER_IPS value from config file
	local external_peer_ips
	external_peer_ips=$(grep -E "^EXTERNAL_PEER_IPS=" "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" || echo "")

	# Trim whitespace
	external_peer_ips=$(echo "$external_peer_ips" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

	# Check if EXTERNAL_PEER_IPS is empty
	if [[ -z "$external_peer_ips" ]]; then
		echo ""
		log_warn "⚠️  CONFIGURATION REQUIRED: EXTERNAL_PEER_IPS is not set"
		echo ""
		log_info "EXTERNAL_PEER_IPS is required for the VPN monitor to work."
		log_info "This should be the external/public IP address(es) of your remote VPN gateway(s)."
		echo ""
		if [[ $INTERACTIVE -eq 0 ]]; then
			# Not in interactive mode, but config is empty - prompt user
			read -p "Enter EXTERNAL_PEER_IPS now? (yes/no) [yes]: " -r
			echo ""
			if [[ -z "$REPLY" ]] || [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]] || [[ $REPLY =~ ^[Yy]$ ]]; then
				local peer_ips
				read -p "EXTERNAL_PEER_IPS (space-separated IP addresses): " peer_ips
				if [[ -n "$peer_ips" ]]; then
					# Escape special characters for sed replacement string (security: prevent command injection)
					# In sed replacement strings, we need to escape: & (matched text) and \ (escape)
					# Also escape the delimiter | if it appears in the value
					local peer_ips_escaped
					peer_ips_escaped=$(printf '%s\n' "$peer_ips" | sed 's/\\/\\\\/g' | sed 's/&/\\&/g' | sed 's/|/\\|/g')

					# Update config file with provided IPs
					if grep -q "^EXTERNAL_PEER_IPS=" "$config_file"; then
						# Update existing line using escaped value
						# Use | as delimiter to avoid conflicts with / in IP addresses
						sed -i "s|^EXTERNAL_PEER_IPS=.*|EXTERNAL_PEER_IPS=\"${peer_ips_escaped}\"|" "$config_file"
					else
						# Add new line (no escaping needed for echo, but use original value)
						echo "EXTERNAL_PEER_IPS=\"${peer_ips}\"" >>"$config_file"
					fi
					log_info "EXTERNAL_PEER_IPS updated in configuration file"
					log_info "Note: IP addresses will be validated when the monitor runs"
					return 0
				else
					log_warn "No IP addresses provided. Please configure EXTERNAL_PEER_IPS manually."
					return 1
				fi
			else
				log_info "Skipping configuration. Please edit ${config_file} manually."
				return 1
			fi
		else
			# Interactive mode already handled this, but config is still empty
			log_warn "EXTERNAL_PEER_IPS is still empty after interactive configuration."
			log_warn "Please edit ${config_file} and set EXTERNAL_PEER_IPS before running the monitor."
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
	echo "  2. Set EXTERNAL_PEER_IPS to your remote VPN endpoint external/public IP address(es)"
	echo "  3. Optionally set INTERNAL_PEER_IPS to your remote VPN endpoint internal/private IP address(es)"
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
			echo "    # Add: $(grep CRON_SCHEDULE "${INSTALL_DIR}/${CONFIG_NAME}" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "*/1 * * * *") ${INSTALL_DIR}/${SCRIPT_NAME} >> ${INSTALL_DIR}/cron.log 2>&1"
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
# Returns:
#   0: Always succeeds
display_help() {
	echo "Usage: $0 [OPTIONS]"
	echo ""
	echo "Options:"
	echo "  --no-cron         Install without setting up cron job"
	echo "  --silent          Perform installation silently (no prompts)"
	echo "  --interactive     Prompt for each config value with defaults"
	echo "  --overwrite-conf  Overwrite existing config file (only works with --silent)"
	echo "  --dev             Install to current working directory (dev mode)"
	echo "  --keepalive-only  Only install and enable keepalive daemon (requires existing installation)"
	echo "  --help, -h        Show this help message"
	echo ""
	echo "Examples:"
	echo "  $0                                    # Standard installation"
	echo "  $0 --interactive                      # Interactive config setup"
	echo "  $0 --silent                          # Silent installation, preserve existing config"
	echo "  $0 --silent --overwrite-conf          # Silent installation, overwrite config"
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
			echo "" >>"${INSTALL_DIR}/${CONFIG_NAME}"
			echo "# VPN Keepalive Daemon" >>"${INSTALL_DIR}/${CONFIG_NAME}"
			echo "ENABLE_KEEPALIVE=1" >>"${INSTALL_DIR}/${CONFIG_NAME}"
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
	install_scripts

	# Validate configuration after installation
	validate_config_after_install

	# Check and setup routes for ping connectivity (if ping checks enabled)
	# Load config values needed for route setup
	if [[ -f "${INSTALL_DIR}/${CONFIG_NAME}" ]]; then
		# Source config to get ENABLE_PING_CHECK, INTERNAL_PEER_IPS, LOCAL_UDM_IP
		# shellcheck source=/dev/null
		source "${INSTALL_DIR}/${CONFIG_NAME}" 2>/dev/null || true
		ENABLE_PING_CHECK="${ENABLE_PING_CHECK:-1}"
		INTERNAL_PEER_IPS="${INTERNAL_PEER_IPS:-}"
		LOCAL_UDM_IP="${LOCAL_UDM_IP:-}"
		check_and_setup_routes || log_warn "Route setup completed with warnings (ping checks may not work until LOCAL_UDM_IP is configured)"
	fi

	# Setup cron only if not skipped
	if [[ $SKIP_CRON -eq 0 ]]; then
		setup_cron
		# Install logrotate configuration for cron.log
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
