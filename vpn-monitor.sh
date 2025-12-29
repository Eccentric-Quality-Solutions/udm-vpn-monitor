#!/bin/bash
#
# UDM VPN Monitor
# Monitors Site-to-Site VPN connections using IPsec xfrm state byte counters
# Implements tiered recovery: log → surgical cleanup → full restart
#
# Designed for UniFi Dream Machine (UDM) running UniFi OS 4.3+
#
# Version: 0.4.1
#

# Strict error handling: exit on error, undefined vars, pipe failures
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/vpn-monitor.conf"
STATE_DIR="${SCRIPT_DIR}"
LOGS_DIR="${STATE_DIR}/logs"
# shellcheck disable=SC2034
LOCKFILE="${STATE_DIR}/vpn-monitor.lock"
LOG_FILE="${LOGS_DIR}/vpn-monitor.log"

# Script version
SCRIPT_VERSION="0.4.1"

# Source library modules
# shellcheck source=lib/logging.sh
source "${SCRIPT_DIR}/lib/logging.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/state.sh
source "${SCRIPT_DIR}/lib/state.sh"
# shellcheck source=lib/detection.sh
source "${SCRIPT_DIR}/lib/detection.sh"
# shellcheck source=lib/recovery.sh
source "${SCRIPT_DIR}/lib/recovery.sh"
# shellcheck source=lib/lockfile.sh
source "${SCRIPT_DIR}/lib/lockfile.sh"
# shellcheck source=lib/resources.sh
source "${SCRIPT_DIR}/lib/resources.sh"

# Parse help flags early (before directory creation)
# This allows --help/-h to work even if directories don't exist
for arg in "$@"; do
	case "$arg" in
	--help | -h)
		echo "Usage: $0 [OPTIONS]"
		echo ""
		echo "UDM VPN Monitor v${SCRIPT_VERSION:-0.0.1}"
		echo "Monitors Site-to-Site VPN connections using IPsec xfrm state byte counters."
		echo "Implements tiered recovery: log → surgical cleanup → full restart"
		echo ""
		echo "Options:"
		echo "  --fake     Run checks and log failures but don't escalate tiers"
		echo "  --help     Show this help message"
		echo "  --version  Show version information"
		echo ""
		exit 0
		;;
	--version | -v)
		echo "UDM VPN Monitor v${SCRIPT_VERSION:-0.0.1}"
		exit 0
		;;
	esac
done

# Check for --fake flag early (before directory creation and config loading)
# This allows directory creation and config errors to exit gracefully in fake mode instead of crashing
for arg in "$@"; do
	case "$arg" in
	--fake)
		NO_ESCALATE=1
		break
		;;
	esac
done

# Ensure state directory exists (needed before logging)
if ! ensure_directory_exists "$STATE_DIR" "state"; then
	exit 1
fi

# Ensure logs directory exists (needed before logging)
if ! ensure_directory_exists "$LOGS_DIR" "logs"; then
	exit 1
fi

# State files
# Note: Failure counters are per-peer: ${LOGS_DIR}/failure_counter_<peer_ip_sanitized>
RESTART_COUNT_FILE="${LOGS_DIR}/restart_count"
# LAST_BYTES_FILE will be per-peer: ${STATE_DIR}/last_bytes_<peer_ip_sanitized>
COOLDOWN_UNTIL_FILE="${STATE_DIR}/cooldown_until"

# Test log file write capability early (before config loading)
#
# This test uses the default LOG_FILE path (${STATE_DIR}/logs/vpn-monitor.log).
# If LOG_FILE is later overridden in config, subsequent logs will go to the new location,
# but this initial test message will remain in the default location. This is intentional:
# the early test validates that the default log location is writable, which is important
# for error handling during config loading. If config loading fails, error messages can
# still be written to the default location.
#
# Note:
#   After config loading, recalculate_log_paths() is called to update LOG_FILE/LOGS_DIR
#   if they were overridden. The new log directory is created at that point.
#   If log file write fails, we output to stderr and continue (log_message handles this gracefully)
if ! touch "$LOG_FILE" 2>/dev/null; then
	# Log file write failed - output to stderr and continue
	# log_message() will handle subsequent write failures gracefully
	echo "[$(get_formatted_timestamp)] [WARNING] Cannot write to log file: $LOG_FILE (check permissions on directory: $(dirname "$LOG_FILE"))" >&2
	echo "[$(get_formatted_timestamp)] [WARNING] Continuing execution - log messages will be output to stderr" >&2
fi

# Verify logging works by writing a test message
# This ensures log_message function will work before we proceed
# If this fails, log_message() will handle it gracefully by outputting to stderr
if ! echo "[$(get_formatted_timestamp)] [INFO] Log file initialized" >>"$LOG_FILE" 2>/dev/null; then
	# Log file write failed - output to stderr and continue
	echo "[$(get_formatted_timestamp)] [WARNING] Cannot write to log file after touch test: $LOG_FILE" >&2
	echo "[$(get_formatted_timestamp)] [WARNING] Continuing execution - log messages will be output to stderr" >&2
fi

# Load configuration
load_config "$CONFIG_FILE"

# Update state file paths to use LOGS_DIR (in case STATE_DIR was overridden)
# Note: Failure counters are per-peer: ${LOGS_DIR}/failure_counter_<peer_ip_sanitized>
RESTART_COUNT_FILE="${LOGS_DIR}/restart_count"

# Check cron persistence
#
# Verifies that the cron job entry still exists in the crontab.
# This helps detect if cron jobs were removed during UniFi OS upgrades.
# Checks root crontab for lines containing "vpn-monitor.sh".
#
# Returns:
#   0: Always succeeds (warnings logged but don't fail script)
#
# Side effects:
#   - Logs warning if cron job not found
#   - Suggests re-running install.sh to restore cron job
#
# Examples:
#   check_cron_persistence
#   # Logs warning if cron job missing
#
# Note:
#   This check is performed once per script run (tracked via .cron_checked file)
#   to avoid log spam on every execution.
#   Uses crontab -l and grep to check for vpn-monitor.sh entry
#   Requires log_message function to be available
check_cron_persistence() {
	if ! crontab -l 2>/dev/null | grep -q "vpn-monitor.sh"; then
		log_message "WARNING" "Cron job not found! Persistence may have been lost."
		log_message "WARNING" "Re-run install.sh to restore cron job."
	fi
}

# Validate command-line arguments
#
# Validates command-line arguments for conflicts and invalid combinations.
# Checks for conflicting flags (--help/--version/--fake) and validates file paths if provided.
# Unknown arguments that look like file paths are validated for existence and readability.
#
# Arguments:
#   $@: Command-line arguments to validate
#
# Returns:
#   0: Arguments are valid
#   1: Invalid arguments or conflicts detected (calls die() and exits script)
#
# Side effects:
#   - Exits script with error message via die() if validation fails
#   - Logs warnings for unknown arguments (but doesn't fail)
#
# Examples:
#   validate_args "$@"
#   # Exits if conflicts detected (e.g., --help and --version together)
#
# Note:
#   Requires die and log_message functions to be available
#   Conflicting flags: --help/--version cannot be used together or with --fake
#   File paths are checked for existence and readability/accessibility
validate_args() {
	local unknown_args=()

	# Check for conflicts and unknown arguments
	# Note: --help and --version are handled early (lines 43-64) and exit before this function is called
	# So we only need to validate --fake and unknown arguments here
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--fake)
			# --fake flag is valid, no conflict checking needed since --help/--version exit early
			shift
			;;
		*)
			# Check if argument looks like a file path
			if [[ "$1" =~ ^/ ]] || [[ "$1" =~ ^\./ ]] || [[ "$1" =~ ^\.\./ ]]; then
				# Looks like a file path - validate it exists
				if [[ ! -e "$1" ]]; then
					die "File or directory does not exist: $1"
				fi
				# If it's a file, check if it's readable
				if [[ -f "$1" ]] && ! file_exists_and_readable "$1"; then
					die "File is not readable: $1"
				fi
				# If it's a directory, check if it's accessible
				if directory_exists "$1" && [[ ! -x "$1" ]]; then
					die "Directory is not accessible: $1"
				fi
			else
				unknown_args+=("$1")
			fi
			shift
			;;
		esac
	done

	# Report unknown arguments
	if [[ ${#unknown_args[@]} -gt 0 ]]; then
		for arg in "${unknown_args[@]}"; do
			log_message "WARNING" "Unknown argument: $arg (use --help for usage)"
		done
	fi

	return 0
}

# Parse command-line arguments
#
# Processes command-line arguments and sets corresponding global flags.
# Validates arguments before processing to catch conflicts early.
#
# Arguments:
#   $@: Command-line arguments to parse
#
# Supported options:
#   --fake: Enable fake mode (NO_ESCALATE=1) - runs checks but doesn't escalate tiers
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Sets NO_ESCALATE flag if --fake is provided
#   - Logs fake mode enablement if --fake is used
#
# Examples:
#   parse_args "$@"
#   # Processes arguments, sets flags
#
# Note:
#   --help and --version are handled early (lines 43-64) and exit before this function is called.
#   Requires validate_args, log_message, and SCRIPT_VERSION to be set.
#   Unknown arguments are handled by validate_args (warnings logged).
parse_args() {
	# Validate arguments first
	validate_args "$@"

	# Process arguments
	# Note: --help and --version are handled early (lines 43-64) and exit before this function is called
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--fake)
			NO_ESCALATE=1
			log_message "INFO" "Fake mode enabled: tier escalation disabled"
			shift
			;;
		*)
			# Unknown arguments already handled by validate_args
			shift
			;;
		esac
	done
}

# Main execution
#
# Main entry point for the VPN monitor script.
# Initializes state, checks cooldown, validates configuration, and monitors all configured peers.
#
# Arguments:
#   $@: Command-line arguments (passed to parse_args)
#
# Returns:
#   0: All peers healthy or checks completed successfully
#   1: One or more peers failed checks or configuration error
#
# Execution flow:
#   1. Parse command-line arguments
#   2. Initialize state files
#   3. Check cooldown period (exit if in cooldown)
#   4. Check cron persistence (once per run)
#   5. Validate EXTERNAL_PEER_IPS configuration
#   6. Monitor each configured peer IP (external and internal)
#   7. Exit with appropriate status code
#
# Side effects:
#   - Creates state files and directories
#   - Writes to log file
#   - May execute recovery actions (if not in fake mode)
# Initialize monitor script
#
# Parses command-line arguments, logs script start, and initializes state.
# This is the first step in the monitoring process, setting up the environment.
#
# Arguments:
#   $@: Command-line arguments to parse (passed to parse_args)
#
# Returns:
#   0: Always succeeds (may exit script for --help/--version)
#
# Side effects:
#   - Parses arguments via parse_args() (may exit for --help/--version)
#   - Logs script start message with PID
#   - Logs fake mode status if enabled
#   - Initializes state files via init_state()
#   - Enables debug output if DEBUG=1
#
# Examples:
#   initialize_monitor "$@"
#   # Sets up script environment, parses args, logs start
#
# Note:
#   Requires parse_args, log_message, init_state, VPN_NAME, NO_ESCALATE, DEBUG to be set
#   Debug output goes to stderr (>&2)
initialize_monitor() {
	# Parse command-line arguments
	parse_args "$@"

	# Log script start
	if [[ "${NO_ESCALATE:-0}" -eq 1 ]]; then
		log_message "INFO" "${VPN_NAME:-VPN} monitor script started in fake mode (PID: $$) - tier escalation disabled"
	else
		log_message "INFO" "${VPN_NAME:-VPN} monitor script started (PID: $$)"
	fi

	# Debug output (only if DEBUG=1)
	debug_log "Starting main() function, PID: $$"
	debug_log "After log_message call"

	# Initialize state
	debug_log "Calling init_state()"
	init_state
	debug_log "After init_state()"
}

# Validate monitor state and check cooldown
#
# Validates state files for corruption, checks for network partition, and checks if script should exit due to cooldown.
# Network partition check happens before cooldown check to ensure partition detection works even during cooldown periods.
# Performs cron persistence check once per run (tracked via .cron_checked file).
# This ensures state integrity before proceeding with monitoring.
#
# Returns:
#   0: State is valid, network is healthy (or partition check disabled), and not in cooldown (continues execution)
#   Exits script with code 0 if network is partitioned or in cooldown
#
# Side effects:
#   - May exit script if network is partitioned (logs message, exits with code 0)
#   - May exit script if in cooldown (logs message, exits with code 0)
#   - Updates network partition state file if partition status changed
#   - Logs warnings about state file issues (but doesn't fail)
#   - Checks cron persistence once per run (creates .cron_checked file)
#   - Enables debug output if DEBUG=1
#
# Examples:
#   validate_monitor_state
#   # Validates state, checks partition, checks cooldown, may exit if partitioned or in cooldown
#
# Note:
#   Requires validate_state, check_cooldown, check_cron_persistence, check_network_partition,
#   get_network_partition_state, set_network_partition_state, log_message, STATE_DIR, DEBUG to be set
#   Cron check is performed once per run to avoid log spam
#   Network partition check runs before cooldown check to ensure partition detection works during cooldown
validate_monitor_state() {
	# Validate state files (check for corruption)
	if ! validate_state; then
		log_message "WARNING" "State file validation detected issues - some state files may be corrupted"
	fi

	# Check system resources (CPU, RAM, disk space)
	# This check happens early to throttle execution if resources are constrained
	# Resource monitoring may exit early if resources are severely constrained
	if ! check_system_resources "$STATE_DIR"; then
		log_message "INFO" "Script exiting: system resources constrained"
		exit 0
	fi

	# Check for network partition before cooldown check
	# Partition check should happen first because if network is partitioned,
	# we should skip VPN checks regardless of cooldown status
	if [[ "${ENABLE_NETWORK_PARTITION_CHECK:-1}" -eq 1 ]]; then
		local dns_server="${NETWORK_PARTITION_DNS_SERVER:-8.8.8.8}"
		local dns_hostname="${NETWORK_PARTITION_DNS_HOSTNAME:-google.com}"
		local dns_timeout="${NETWORK_PARTITION_DNS_TIMEOUT:-2}"
		local interfaces="${NETWORK_PARTITION_INTERFACES:-br0,eth0}"

		# Get current partition state once (DRY principle)
		local prev_partition_state
		prev_partition_state=$(get_network_partition_state)

		if ! check_network_partition "$dns_server" "$dns_hostname" "$dns_timeout" "$interfaces"; then
			# Network is partitioned - skip VPN checks
			if [[ "$prev_partition_state" -eq 0 ]]; then
				log_message "WARNING" "Network partition detected - skipping VPN checks until connectivity restored"
				set_network_partition_state 1
			else
				log_message "INFO" "Network still partitioned - VPN checks skipped"
			fi
			# Exit early - don't check cooldown or process peers
			exit 0
		else
			# Network is healthy - check if it was previously partitioned
			if [[ "$prev_partition_state" -eq 1 ]]; then
				log_message "INFO" "Network connectivity restored - resuming VPN monitoring"
				set_network_partition_state 0
			fi
		fi
	fi

	# Check cooldown
	debug_log "Checking cooldown"
	if check_cooldown; then
		debug_log "In cooldown, exiting"
		log_message "INFO" "Script exiting: in cooldown period"
		exit 0
	fi
	debug_log "Not in cooldown, continuing"

	# Check cron persistence (first run only, to avoid log spam)
	if [[ ! -f "${STATE_DIR}/.cron_checked" ]]; then
		debug_log "Checking cron persistence"
		check_cron_persistence
		# Create .cron_checked file - handle errors gracefully
		if ! touch "${STATE_DIR}/.cron_checked" 2>/dev/null; then
			handle_error "WARNING" "Cannot create .cron_checked file in ${STATE_DIR} (check permissions)"
		fi
	fi
}

# Process all peer IPs
#
# Iterates through configured peer IPs and monitors each one.
# Validates configuration before processing to ensure EXTERNAL_PEER_IPS is set correctly.
# Network partition check is performed earlier in validate_monitor_state() before this function is called.
# Skips empty peer IPs with a warning.
# Uses EXTERNAL_PEER_IPS for xfrm state checks and INTERNAL_PEER_IPS for ping checks.
#
# Returns:
#   0: All peers are healthy (all monitor_peer calls succeeded)
#   1: One or more peers have issues (at least one monitor_peer call failed)
#
# Side effects:
#   - Validates configuration via validate_config()
#   - Calls monitor_peer() for each peer IP pair (external, internal)
#   - Logs warnings for empty peer IPs (skips them)
#   - Enables debug output if DEBUG=1
#
# Examples:
#   if ! process_peer_ips; then
#       echo "Some peers have issues"
#   fi
#
# Note:
#   Requires validate_config, monitor_peer, log_message, EXTERNAL_PEER_IPS, INTERNAL_PEER_IPS, DEBUG to be set
#   EXTERNAL_PEER_IPS should be space-separated list of external/public IP addresses
#   INTERNAL_PEER_IPS should be space-separated list of internal/private IP addresses (optional)
#   Network partition check is performed in validate_monitor_state() before this function is called
process_peer_ips() {
	local all_ok=0

	# Validate configuration
	debug_log "Validating EXTERNAL_PEER_IPS (value: '${EXTERNAL_PEER_IPS}')"
	debug_log "INTERNAL_PEER_IPS (value: '${INTERNAL_PEER_IPS}')"

	# Validate configuration (includes EXTERNAL_PEER_IPS validation via schema)
	validate_config

	# Network partition check is now done in validate_monitor_state() before cooldown check
	# This ensures partition detection happens even during cooldown periods

	# Process each peer IP
	# Convert space-separated string to array to avoid word splitting and globbing
	# Use IFS to split on spaces, read into array with proper quoting
	local IFS=' '
	local -a external_peer_ips_array
	local -a internal_peer_ips_array
	read -ra external_peer_ips_array <<<"$EXTERNAL_PEER_IPS"
	read -ra internal_peer_ips_array <<<"$INTERNAL_PEER_IPS"

	local idx=0
	for external_peer_ip in "${external_peer_ips_array[@]}"; do
		# Basic validation: non-empty (shouldn't happen after validate_config, but check anyway)
		if [[ -z "$external_peer_ip" ]]; then
			log_message "WARNING" "Skipping empty external peer IP"
			continue
		fi

		# Get corresponding internal IP (if available)
		local internal_peer_ip=""
		if [[ $idx -lt ${#internal_peer_ips_array[@]} ]] && [[ -n "${internal_peer_ips_array[$idx]}" ]]; then
			internal_peer_ip="${internal_peer_ips_array[$idx]}"
		fi

		# Monitor peer with both external and internal IPs
		if ! monitor_peer "$external_peer_ip" "$internal_peer_ip"; then
			all_ok=1
		fi

		((idx++))
	done

	return $all_ok
}

# Main function
#
# Orchestrates the VPN monitoring process from start to finish.
# This is the main entry point called by acquire_lockfile.
#
# Execution flow:
#   1. Initializes the monitor (parse args, log start, init state)
#   2. Validates state, checks network partition, and checks cooldown (may exit if partitioned or in cooldown)
#   3. Processes all peer IPs (monitors each configured peer)
#   4. Logs completion status and exits with appropriate status code
#
# Arguments:
#   $@: Command-line arguments (passed to initialize_monitor)
#
# Returns:
#   0: All peers healthy or checks completed successfully
#   1: One or more peers failed checks or configuration error
#
# Side effects:
#   - May exit script if in cooldown (via validate_monitor_state)
#   - Creates state files and directories
#   - Writes to log file
#   - May execute recovery actions (if not in fake mode)
#   - Exits script with status code (0 = success, 1 = warnings/errors)
#
# Examples:
#   main "$@"
#   # Runs complete monitoring process
#
# Note:
#   Requires initialize_monitor, validate_monitor_state, process_peer_ips,
#   log_message to be set
#   Called by acquire_lockfile to ensure single instance execution
main() {
	# Initialize monitor script
	initialize_monitor "$@"

	# Validate state and check cooldown (may exit if in cooldown)
	validate_monitor_state

	# Process all peer IPs
	local all_ok=0
	if ! process_peer_ips; then
		all_ok=1
	fi

	# Log completion and exit
	if [[ $all_ok -eq 0 ]]; then
		log_message "INFO" "VPN monitor check completed successfully"
	else
		log_message "WARNING" "VPN monitor check completed with warnings/errors"
	fi

	# In fake mode, always exit with 0 (we're just checking/logging, not taking action)
	# Failures are logged but don't cause the script to fail in fake mode
	if [[ "${NO_ESCALATE:-0}" -eq 1 ]]; then
		exit 0
	fi

	exit $all_ok
}

# Run with lockfile protection
acquire_lockfile main "$@"
