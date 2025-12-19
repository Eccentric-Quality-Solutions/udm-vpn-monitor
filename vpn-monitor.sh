#!/bin/bash
#
# UDM VPN Monitor
# Monitors Site-to-Site VPN connections using IPsec xfrm state byte counters
# Implements tiered recovery: log → surgical cleanup → full restart
#
# Designed for UniFi Dream Machine (UDM) running UniFi OS 4.3+
#
# Version: 0.0.1
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
SCRIPT_VERSION="0.0.1"

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

# Ensure state directory exists (needed before logging)
ensure_directory_exists "$STATE_DIR" "state"

# Ensure logs directory exists (needed before logging)
ensure_directory_exists "$LOGS_DIR" "logs"

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
if ! touch "$LOG_FILE" 2>/dev/null; then
	die "Cannot write to log file: $LOG_FILE (check permissions on directory: $(dirname "$LOG_FILE"))"
fi

# Verify logging works by writing a test message
# This ensures log_message function will work before we proceed
if ! echo "[$(get_formatted_timestamp)] [INFO] Log file initialized" >>"$LOG_FILE" 2>/dev/null; then
	die "Cannot write to log file after touch test: $LOG_FILE"
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
	local help_seen=0
	local version_seen=0
	local fake_seen=0
	local unknown_args=()

	# Check for conflicts and unknown arguments
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--help | -h)
			help_seen=1
			;;
		--version | -v)
			version_seen=1
			;;
		--fake)
			fake_seen=1
			;;
		*)
			# Check if argument looks like a file path
			if [[ "$1" =~ ^/ ]] || [[ "$1" =~ ^\./ ]] || [[ "$1" =~ ^\.\./ ]]; then
				# Looks like a file path - validate it exists
				if [[ ! -e "$1" ]]; then
					die "File or directory does not exist: $1"
				fi
				# If it's a file, check if it's readable
				if [[ -f "$1" ]] && [[ ! -r "$1" ]]; then
					die "File is not readable: $1"
				fi
				# If it's a directory, check if it's accessible
				if [[ -d "$1" ]] && [[ ! -x "$1" ]]; then
					die "Directory is not accessible: $1"
				fi
			else
				unknown_args+=("$1")
			fi
			;;
		esac
		shift
	done

	# Check for conflicting flags (help and version are mutually exclusive with others)
	if [[ $help_seen -eq 1 ]] && [[ $version_seen -eq 1 ]]; then
		die "Conflicting flags: --help and --version cannot be used together"
	fi

	if [[ $help_seen -eq 1 ]] && [[ $fake_seen -eq 1 ]]; then
		die "Conflicting flags: --help and --fake cannot be used together"
	fi

	if [[ $version_seen -eq 1 ]] && [[ $fake_seen -eq 1 ]]; then
		die "Conflicting flags: --version and --fake cannot be used together"
	fi

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
# Handles help and version flags by displaying information and exiting.
#
# Arguments:
#   $@: Command-line arguments to parse
#
# Supported options:
#   --fake: Enable fake mode (NO_ESCALATE=1) - runs checks but doesn't escalate tiers
#   --help, -h: Display help message and exit with code 0
#   --version, -v: Display version information and exit with code 0
#
# Returns:
#   0: Always succeeds (exits with 0 for --help/--version, continues otherwise)
#
# Side effects:
#   - Sets NO_ESCALATE flag if --fake is provided
#   - Logs fake mode enablement if --fake is used
#   - Exits script with code 0 for --help/--version
#
# Examples:
#   parse_args "$@"
#   # Processes arguments, sets flags, may exit for --help/--version
#
# Note:
#   Requires validate_args, log_message, and SCRIPT_VERSION to be set
#   Unknown arguments are handled by validate_args (warnings logged)
parse_args() {
	# Validate arguments first
	validate_args "$@"

	# Process arguments
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--fake)
			NO_ESCALATE=1
			log_message "INFO" "Fake mode enabled: tier escalation disabled"
			shift
			;;
		--help | -h)
			echo "Usage: $0 [OPTIONS]"
			echo ""
			echo "UDM VPN Monitor v${SCRIPT_VERSION:-0.0.1}"
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
	if [[ $NO_ESCALATE -eq 1 ]]; then
		log_message "INFO" "${VPN_NAME:-VPN} monitor script started in fake mode (PID: $$) - tier escalation disabled"
	else
		log_message "INFO" "${VPN_NAME:-VPN} monitor script started (PID: $$)"
	fi

	# Debug output (only if DEBUG=1)
	if [[ "${DEBUG:-0}" -eq 1 ]]; then
		echo "DEBUG: Starting main() function, PID: $$" >&2
		echo "DEBUG: After log_message call" >&2
	fi

	# Initialize state
	if [[ "${DEBUG:-0}" -eq 1 ]]; then
		echo "DEBUG: Calling init_state()" >&2
	fi
	init_state
	if [[ "${DEBUG:-0}" -eq 1 ]]; then
		echo "DEBUG: After init_state()" >&2
	fi
}

# Validate monitor state and check cooldown
#
# Validates state files for corruption and checks if script should exit due to cooldown.
# Performs cron persistence check once per run (tracked via .cron_checked file).
# This ensures state integrity before proceeding with monitoring.
#
# Returns:
#   0: State is valid and not in cooldown (continues execution)
#   1: Should exit (in cooldown, script exits with code 0)
#
# Side effects:
#   - May exit script if in cooldown (logs message, exits with code 0)
#   - Logs warnings about state file issues (but doesn't fail)
#   - Checks cron persistence once per run (creates .cron_checked file)
#   - Enables debug output if DEBUG=1
#
# Examples:
#   validate_monitor_state
#   # Validates state, checks cooldown, may exit if in cooldown
#
# Note:
#   Requires validate_state, check_cooldown, check_cron_persistence, log_message,
#   STATE_DIR, DEBUG to be set
#   Cron check is performed once per run to avoid log spam
validate_monitor_state() {
	# Validate state files (check for corruption)
	if ! validate_state; then
		log_message "WARNING" "State file validation detected issues - some state files may be corrupted"
	fi

	# Check cooldown
	if [[ "${DEBUG:-0}" -eq 1 ]]; then
		echo "DEBUG: Checking cooldown" >&2
	fi
	if check_cooldown; then
		if [[ "${DEBUG:-0}" -eq 1 ]]; then
			echo "DEBUG: In cooldown, exiting" >&2
		fi
		log_message "INFO" "Script exiting: in cooldown period"
		exit 0
	fi
	if [[ "${DEBUG:-0}" -eq 1 ]]; then
		echo "DEBUG: Not in cooldown, continuing" >&2
	fi

	# Check cron persistence (first run only, to avoid log spam)
	if [[ ! -f "${STATE_DIR}/.cron_checked" ]]; then
		if [[ "${DEBUG:-0}" -eq 1 ]]; then
			echo "DEBUG: Checking cron persistence" >&2
		fi
		check_cron_persistence
		touch "${STATE_DIR}/.cron_checked"
	fi
}

# Process all peer IPs
#
# Iterates through configured peer IPs and monitors each one.
# Validates configuration before processing to ensure EXTERNAL_PEER_IPS is set correctly.
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
process_peer_ips() {
	local all_ok=0

	# Validate configuration
	if [[ "${DEBUG:-0}" -eq 1 ]]; then
		echo "DEBUG: Validating EXTERNAL_PEER_IPS (value: '${EXTERNAL_PEER_IPS}')" >&2
		echo "DEBUG: INTERNAL_PEER_IPS (value: '${INTERNAL_PEER_IPS}')" >&2
	fi
	validate_config

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
#   2. Validates state and checks cooldown (may exit if in cooldown)
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

	exit $all_ok
}

# Run with lockfile protection
acquire_lockfile main "$@"
