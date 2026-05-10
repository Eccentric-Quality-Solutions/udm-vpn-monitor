#!/bin/bash
#
# UDM VPN Monitor
# Monitors Site-to-Site VPN connections using IPsec xfrm state byte counters
# Implements tiered recovery: log → surgical cleanup → full restart
#
# Designed for UniFi Dream Machine (UDM) running UniFi OS 4.3+
#
# Version: 0.8.3
#

# Strict error handling: exit on error, undefined vars, pipe failures
set -euo pipefail
# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/vpn-monitor.conf"
STATE_DIR="${SCRIPT_DIR}/state"
LOGS_DIR="${SCRIPT_DIR}/logs"
# shellcheck disable=SC2034
LOCKFILE="${STATE_DIR}/vpn-monitor.lock"
LOG_FILE="${LOGS_DIR}/vpn-monitor.log"

# Script version
SCRIPT_VERSION="0.8.3"

# Source library modules
# shellcheck source=lib/logging.sh
source "${SCRIPT_DIR}/lib/logging.sh" || {
	echo "ERROR: Failed to source logging.sh" >&2
	exit 2
}
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh" || {
	echo "ERROR: Failed to source config.sh" >&2
	exit 2
}
# shellcheck source=lib/state.sh
source "${SCRIPT_DIR}/lib/state.sh" || {
	echo "ERROR: Failed to source state.sh" >&2
	exit 2
}
# shellcheck source=lib/detection.sh
source "${SCRIPT_DIR}/lib/detection.sh" || {
	echo "ERROR: Failed to source detection.sh" >&2
	exit 2
}
# shellcheck source=lib/recovery.sh
source "${SCRIPT_DIR}/lib/recovery.sh" || {
	echo "ERROR: Failed to source recovery.sh" >&2
	exit 2
}
# shellcheck source=lib/lockfile.sh
source "${SCRIPT_DIR}/lib/lockfile.sh" || {
	echo "ERROR: Failed to source lockfile.sh" >&2
	exit 2
}
# shellcheck source=lib/resources.sh
source "${SCRIPT_DIR}/lib/resources.sh" || {
	echo "ERROR: Failed to source resources.sh" >&2
	exit 2
}

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
		exit "${EXIT_SUCCESS:-0}"
		;;
	--version | -v)
		echo "UDM VPN Monitor v${SCRIPT_VERSION:-0.0.1}"
		exit "${EXIT_SUCCESS:-0}"
		;;
	esac
done

# Check for --fake flag early (before directory creation and config loading)
# This allows directory creation and config errors to exit gracefully in fake mode instead of crashing
for arg in "$@"; do
	case "$arg" in
	--fake)
		NO_ESCALATE=1
		export NO_ESCALATE
		NO_ESCALATE_SET_FROM_CMD=1
		break
		;;
	esac
done

# Ensure state directory exists (needed before logging)
if ! ensure_directory_exists "$STATE_DIR" "state"; then
	if is_fake_mode; then
		exit "${EXIT_SUCCESS:-0}"
	fi
	exit "${EXIT_GENERAL_ERROR:-1}"
fi

# Ensure logs directory exists (needed before logging)
if ! ensure_directory_exists "$LOGS_DIR" "logs"; then
	if is_fake_mode; then
		exit "${EXIT_SUCCESS:-0}"
	fi
	exit "${EXIT_GENERAL_ERROR:-1}"
fi

# State files
# Note: Failure counters are per-peer: ${STATE_DIR}/failure_count_<location>_<peer_ip_sanitized>
RESTART_COUNT_FILE="${STATE_DIR}/restart_count"
TIER2_RECOVERY_COUNT_FILE="${STATE_DIR}/tier2_recovery_count"
# LAST_BYTES_FILE will be per-peer: ${STATE_DIR}/last_bytes_<peer_ip_sanitized>
#
# Touch default LOG_FILE before load_config so the default log path is writable if config
# load fails. After load, LOG_FILE may move; this probe and the DEBUG line below stay under
# the pre-config default. Paths and log dirs are reconciled in load_config().
if ! touch "$LOG_FILE" 2>/dev/null; then
	# Log file write failed - output to stderr and continue
	# log_message() will handle subsequent write failures gracefully
	log_message "WARNING" "SYSTEM" "Cannot write to log file: $LOG_FILE (check permissions on directory: $(dirname "$LOG_FILE")) - continuing execution with log messages output to stderr"
fi

# DEBUG so scheduled runs do not generate an INFO line every execution.
log_message "DEBUG" "SYSTEM" "Log file initialized"

# Load configuration
if ! load_config "$CONFIG_FILE"; then
	# load_config failed - in fake mode this returns 1, in normal mode it exits via handle_error_or_exit_fake_mode
	if is_fake_mode; then
		exit "${EXIT_SUCCESS:-0}"
	fi
	exit "${EXIT_VALIDATION_ERROR:-3}"
fi

# Validate configuration early (before network partition check)
if ! validate_config; then
	# Normal: fatal errors never return (die in validate_config). If we are here, fake mode
	# got return 1—exit non-zero (unlike load_config above) so tests can assert validation failure.
	exit "${EXIT_VALIDATION_ERROR:-3}"
fi

# Update state file paths that depend on LOGS_DIR
RESTART_COUNT_FILE="${STATE_DIR}/restart_count"
TIER2_RECOVERY_COUNT_FILE="${STATE_DIR}/tier2_recovery_count"

# Check cron persistence
#
# Verifies that the cron job entry still exists in the crontab.
# This helps detect if cron jobs were removed during UniFi OS upgrades.
# Checks root crontab for lines containing "vpn-monitor" (matches both
# vpn-monitor.sh and vpn-monitor-wrapper.sh, since either is a valid install).
check_cron_persistence() {
	if ! crontab -l 2>/dev/null | grep -q "vpn-monitor"; then
		log_message "WARNING" "SYSTEM" "Cron job not found! Persistence may have been lost. Re-run install.sh to restore cron job."
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
#   - Logs warnings for unknown arguments and exits with error
validate_args() {
	local unknown_args=()

	# Check for conflicts and unknown arguments
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

	# Report unknown arguments and exit with error
	if [[ ${#unknown_args[@]} -gt 0 ]]; then
		for arg in "${unknown_args[@]}"; do
			log_message "WARNING" "SYSTEM" "Unknown argument: $arg (use --help for usage)"
		done
		die "Unknown arguments provided: ${unknown_args[*]} (use --help for usage)" "${EXIT_VALIDATION_ERROR:-3}"
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
# Side effects:
#   - Sets NO_ESCALATE flag if --fake is provided
#   - Logs fake mode enablement if --fake is used
parse_args() {
	# Validate arguments first
	validate_args "$@"

	# Process arguments
	# Note: --help and --version are handled early (lines 43-64) and exit before this function is called
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--fake)
			NO_ESCALATE=1
			export NO_ESCALATE
			NO_ESCALATE_SET_FROM_CMD=1
			log_message "INFO" "SYSTEM" "Fake mode enabled: tier escalation disabled"
			shift
			;;
		*)
			# Unknown arguments already handled by validate_args
			shift
			;;
		esac
	done
}

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
#   - Compacts restart count file via compact_restart_count_file()
#   - Enables debug output if DEBUG=1
initialize_monitor() {
	# Parse command-line arguments
	parse_args "$@"

	# Log script start
	if [[ "${NO_ESCALATE:-0}" -eq 1 ]]; then
		log_message "WARNING" "SYSTEM" "VPN monitor script started in fake mode (PID: $$) - tier escalation disabled"
	else
		log_message "INFO" "SYSTEM" "VPN monitor script started (PID: $$)"
	fi

	# Debug output (only if DEBUG=1)
	debug_log "Starting main() function, PID: $$"
	debug_log "After log_message call"

	# Initialize state
	debug_log "Calling init_state()"
	init_state
	debug_log "After init_state()"
	# Compact restart count file once per run (under main lock) to limit file growth
	compact_restart_count_file
	compact_tier2_recovery_count_file
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
validate_monitor_state() {
	# Validate state files (check for corruption)
	if ! validate_state; then
		log_message "WARNING" "SYSTEM" "State file validation detected issues - some state files may be corrupted"
	fi

	# Check system resources (CPU, RAM, disk space)
	# This check happens early to throttle execution if resources are constrained
	if ! check_system_resources "$STATE_DIR"; then
		log_message "ERROR" "SYSTEM" "Script exiting: system resources constrained"
		exit "${EXIT_SUCCESS:-0}"
	fi
	# Log summary if hour has elapsed (tracks statistics for CPU, RAM, and disk checks)
	log_resource_monitoring_summary_if_due

	# Check for network partition before cooldown check
	# Partition check should happen first because if network is partitioned,
	# we should skip VPN checks regardless of cooldown status
	if [[ "${ENABLE_NETWORK_PARTITION_CHECK:-1}" -eq 1 ]]; then
		local dns_server="${NETWORK_PARTITION_DNS_SERVER:-8.8.8.8}"
		local dns_hostname="${NETWORK_PARTITION_DNS_HOSTNAME:-google.com}"
		local dns_timeout="${NETWORK_PARTITION_DNS_TIMEOUT:-2}"
		local interfaces="${NETWORK_PARTITION_INTERFACES:-br0,eth0}"

		# Get current partition state once
		local prev_partition_state
		prev_partition_state=$(get_network_partition_state)

		if ! check_network_partition "$dns_server" "$dns_hostname" "$dns_timeout" "$interfaces"; then
			# Network is partitioned - update state but continue to allow recovery code to check partition state
			log_message "WARNING" "SYSTEM" "Network partition - skipping VPN checks until connectivity restored"
			set_network_partition_state 1
			# Don't exit early - let recovery code check partition state and skip recovery actions
			# This allows tests to verify that recovery is skipped when partition is detected
		else
			# Network is healthy - check if it was previously partitioned
			if [[ "$prev_partition_state" -eq 1 ]]; then
				log_message "INFO" "SYSTEM" "Network connectivity restored - resuming VPN monitoring"
				set_network_partition_state 0
			fi
		fi
		# Log summary if hour has elapsed (tracks statistics for all three checks)
		log_network_partition_summary_if_due
	fi

	# Check cron persistence (first run only, to avoid log spam)
	if [[ ! -f "${STATE_DIR}/.cron_checked" ]]; then
		debug_log "Checking cron persistence"
		check_cron_persistence
		# Create .cron_checked file - handle errors gracefully
		if ! touch "${STATE_DIR}/.cron_checked" 2>/dev/null; then
			handle_error "ERROR" "SYSTEM" "Cannot create .cron_checked file in ${STATE_DIR} (check permissions)"
		fi
	fi
}

# Process all locations
#
# Iterates through configured locations and monitors each one.
# Uses location external IP for xfrm state checks and location internal IPs for ping checks.
#
# Returns:
#   0: All locations are healthy (all monitor_location calls succeeded)
#   1: One or more locations have issues (at least one monitor_location call failed)
#
# Side effects:
#   - Uses LOCATIONS array populated by validate_config()
#   - Calls monitor_location() for each location
#   - Logs warnings for invalid locations (skips them)
#   - Enables debug output if DEBUG=1
process_locations() {
	local all_ok=0

	# Defensive check: verify LOCATIONS is populated
	if [[ ${#LOCATIONS[@]} -eq 0 ]]; then
		handle_error_or_exit_fake_mode "SYSTEM" "No locations configured" "${EXIT_VALIDATION_ERROR:-3}"
		return 1
	fi

	# Log found locations
	local location_list=""
	for loc in "${!LOCATIONS[@]}"; do
		if [[ -n "$location_list" ]]; then
			location_list="${location_list}, "
		fi
		# Get external and internal IPs for this location
		local external_ip
		local internal_ips
		external_ip=$(get_location_external_ip "$loc" 2>/dev/null || echo "")
		internal_ips=$(get_location_internal_ips "$loc" 2>/dev/null || echo "")

		# Format location with IPs in parentheses
		if [[ -n "$internal_ips" ]]; then
			location_list="${location_list}${loc} (${external_ip}, ${internal_ips})"
		else
			location_list="${location_list}${loc} (${external_ip})"
		fi
	done
	log_message "INFO" "SYSTEM" "Found ${#LOCATIONS[@]} location(s): $location_list"

	# DESIGN DECISION: System-wide failure detection uses failure counts from the previous cycle
	# rather than checking VPN status in the current cycle. This is an intentional trade-off:
	#
	# Benefits:
	#   - Efficiency: Avoids double-checking VPNs (once for system-wide detection, once for monitoring)
	#   - Conservative: Better to coordinate recovery unnecessarily than miss a real system-wide failure
	#   - Acceptable staleness: One-cycle delay (30-60 seconds) is negligible for coordination purposes
	#
	# Trade-offs:
	#   - If a VPN recovers naturally between cycles, it may still be counted as "failing" for one cycle
	#   - This can cause unnecessary recovery coordination, but this is safer than missing failures
	#   - The impact is minimal: one location (coordinator) still attempts recovery, others just skip

	# Step 1: Check existing failure counts from previous cycle
	declare -A location_failure_status
	for location_name in "${!LOCATIONS[@]}"; do
		# Get external IP for this location
		local external_peer_ip
		if ! external_peer_ip=$(get_location_external_ip "$location_name"); then
			handle_error "WARNING" "$location_name" "Failed to get external IP (skipping)"
			all_ok=1
			location_failure_status["$location_name"]=1
			continue
		fi

		# Check existing failure count from previous cycle
		# If failure count > 0, location was failing in the previous cycle
		local failure_count
		failure_count=$(get_failure_count "$location_name" "$external_peer_ip")
		if [[ "$failure_count" -gt 0 ]]; then
			location_failure_status["$location_name"]=1
		else
			location_failure_status["$location_name"]=0
		fi
	done

	# Step 2: Detect system-wide failure based on current status
	# This happens before recovery attempts to coordinate recovery
	local now
	now=$(get_unix_timestamp)
	# Create arrays for detection function (it expects associative array references)
	# Both arrays use location names as keys
	declare -A location_names_for_detection
	declare -A failure_statuses_for_detection
	for loc in "${!LOCATIONS[@]}"; do
		# location_names_for_detection: key = location name, value = 1 (just a marker)
		location_names_for_detection["$loc"]=1
		# failure_statuses_for_detection: key = location name, value = failure status (0 or 1)
		failure_statuses_for_detection["$loc"]="${location_failure_status[$loc]:-0}"
	done
	if detect_system_wide_failure "location_names_for_detection" "failure_statuses_for_detection" 2>/dev/null; then
		local prev_failure_state
		prev_failure_state=$(get_system_wide_failure_state)

		if [[ "$prev_failure_state" -ne 1 ]]; then
			# System-wide failure just detected
			set_system_wide_failure_state 1
			set_system_wide_failure_timestamp "$now"
			log_message "WARNING" "SYSTEM" "System-wide failure detected: ${FAILED_LOCATION_COUNT:-0} of ${TOTAL_LOCATION_COUNT:-0} locations failing (threshold: ${SYSTEM_WIDE_FAILURE_THRESHOLD:-100}%). Recovery will be coordinated to prevent cascades and rate limiting"
		fi
	else
		# No system-wide failure detected
		local prev_failure_state
		prev_failure_state=$(get_system_wide_failure_state)
		if [[ "$prev_failure_state" -eq 1 ]]; then
			# System-wide failure was previously detected but is now resolved
			# Note: set_system_wide_failure_state automatically clears coordinator when state is set to 0
			set_system_wide_failure_state 0
			local timestamp
			timestamp=$(get_system_wide_failure_timestamp)
			local duration="0"
			[[ "$timestamp" -gt 0 ]] && duration=$(calculate_duration "$timestamp" "$now" 2>/dev/null || echo "0")
			log_message "INFO" "SYSTEM" "System-wide failure resolved (duration: ${duration}s)"
		fi
	fi

	# Step 3: Process each location with recovery coordination
	# monitor_location() will check should_location_attempt_recovery() internally
	# to coordinate recovery during system-wide failures
	for location_name in "${!LOCATIONS[@]}"; do
		# Get external IP for this location (resolved from DNS if needed)
		local external_peer_ip
		if ! external_peer_ip=$(get_location_external_ip_resolved "$location_name"); then
			# DNS resolution failed or location not found - skip
			handle_error "WARNING" "$location_name" "Failed to get or resolve external IP (skipping)"
			continue
		fi

		# Get internal IPs for this location (resolved from DNS if needed, may be empty)
		local internal_ips
		internal_ips=$(get_location_internal_ips_resolved "$location_name" 2>/dev/null || echo "")

		# Monitor location with external IP and internal IPs
		# Recovery coordination is handled in determine_recovery_action()
		if ! monitor_location "$location_name" "$external_peer_ip" "$internal_ips"; then
			all_ok=1
		fi
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
#   - Creates state files and directories
#   - Writes to log file
#   - May execute recovery actions (if not in fake mode)
#   - Exits script with status code (0 = success, 1 = warnings/errors)
main() {
	# Initialize monitor script
	initialize_monitor "$@"

	# Validate state and check cooldown (may exit if in cooldown)
	validate_monitor_state

	# Apply startup grace period if this is first run after restart
	# This prevents false positives when IPsec/xfrm subsystems are still initializing
	#
	# We consider it a "fresh start" if:
	#   1. The timestamp file doesn't exist (first run ever, or state directory was cleared)
	#   2. The timestamp file is older than 5 minutes (likely system restart or script hasn't run in a while)
	#      Note: 5-minute threshold assumes cron runs at least every minute. If file is older than 5 minutes
	local last_run_timestamp_file="${STATE_DIR}/.last_run_timestamp"
	local apply_grace_period=0
	local grace_period="${STARTUP_GRACE_PERIOD:-5}"

	if [[ ! -f "$last_run_timestamp_file" ]]; then
		# File doesn't exist - first run detected
		apply_grace_period=1
	elif [[ "$grace_period" -gt 0 ]]; then
		# File exists - check if it's recent (within last 5 minutes)
		# Use find to check file age (more portable than stat).
		# Capture stdout only; stderr is discarded so error messages are not treated as result.
		local find_result
		local find_exit_code
		find_result=$(find "$last_run_timestamp_file" -mmin -5 2>/dev/null)
		find_exit_code=$?
		if [[ "${DEBUG:-0}" -eq 1 ]]; then
			log_message "DEBUG" "SYSTEM" "Grace period check: file=$last_run_timestamp_file, find_result='$find_result', find_exit=$find_exit_code"
		fi
		if [[ $find_exit_code -ne 0 ]] || [[ -z "$find_result" ]]; then
			# File is older than 5 minutes - likely a restart
			apply_grace_period=1
		fi
	fi

	if [[ "$apply_grace_period" -eq 1 ]] && [[ "$grace_period" -gt 0 ]]; then
		log_message "INFO" "SYSTEM" "First run detected - waiting ${grace_period} seconds for IPsec/xfrm to initialize; VPN checks will begin after grace period"
		sleep "$grace_period"
		log_message "INFO" "SYSTEM" "Startup grace period complete - beginning VPN checks"
	fi

	# Update timestamp file on every run to track last execution time
	# Handle errors gracefully - if we can't create/update the file, continue anyway
	if ! touch "$last_run_timestamp_file" 2>/dev/null; then
		handle_error "WARNING" "SYSTEM" "Cannot create/update .last_run_timestamp file in ${STATE_DIR} (check permissions) - grace period may apply on next restart"
	fi

	# Process all locations
	local all_ok=0
	if ! process_locations; then
		all_ok=1
	fi

	# Log completion and exit
	if [[ $all_ok -eq 0 ]]; then
		log_message "INFO" "SYSTEM" "The VPN monitor script has successfully finished running"
	else
		log_message "WARNING" "SYSTEM" "The VPN monitor script finished running with issues (some locations below recovery threshold)"
	fi

	# In fake mode, always exit with 0 (we're just checking/logging, not taking action)
	# Failures are logged but don't cause the script to fail in fake mode
	if [[ "${NO_ESCALATE:-0}" -eq 1 ]]; then
		exit "${EXIT_SUCCESS:-0}"
	fi

	exit $all_ok
}

# Run with lockfile protection
acquire_lockfile main "$@"
