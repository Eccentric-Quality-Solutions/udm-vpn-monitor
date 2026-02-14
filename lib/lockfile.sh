#!/bin/bash
#
# Lockfile management for UDM VPN Monitor
# Handles flock-based and fallback lockfile mechanisms to prevent concurrent execution
#
# Version: 0.8.0
#

# shellcheck source=lib/common.sh
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LIB_DIR}/common.sh"

# shellcheck source=lib/logging.sh
source "${LIB_DIR}/logging.sh"

# Maximum number of retry attempts for fallback lockfile acquisition
# Used when flock is unavailable. Set to 1 to limit retries and prevent infinite loops.
# Note: This is a fallback method with inherent race conditions - retries help but don't eliminate all races.
readonly FALLBACK_MAX_RETRIES=1

# Hard maximum lockfile age in seconds (regardless of clock direction).
# A lockfile whose mtime differs from "now" by more than this (past or future) is always treated as stale.
# Prevents far-future or corrupted timestamps (e.g. year 2099, NTP jump) from permanently blocking execution.
readonly LOCKFILE_MAX_AGE_SECONDS=3600

# Extract PID from lockfile
#
# Extracts the process ID from a lockfile in the format "timestamp:pid".
# Returns empty string if lockfile doesn't exist or PID cannot be extracted.
# Uses cut command to extract second field (after colon).
#
# Arguments:
#   $1: Optional lockfile path (defaults to $LOCKFILE if not provided)
#
# Returns:
#   0: Always succeeds (even if file doesn't exist)
#
# Output:
#   Prints PID (integer) to stdout, or empty string if unavailable
#
# Examples:
#   pid=$(extract_lockfile_pid)
#   if [[ -n "$pid" ]]; then
#       echo "Lockfile PID: $pid"
#   fi
#
# Note:
#   Requires LOCKFILE to be set (from config.sh) if argument not provided
#   Lockfile format: "timestamp:pid" (e.g., "1704067200:12345")
#   Uses cut -d: -f2 to extract PID field
extract_lockfile_pid() {
	local lockfile="${1:-$LOCKFILE}"
	# Check if file is readable before attempting to read
	# This prevents hangs when lockfile is unreadable (chmod 000)
	if ! file_exists_and_readable "$lockfile"; then
		echo "" # Return empty string (no PID available)
		return 0
	fi
	cat "$lockfile" 2>/dev/null | cut -d: -f2 || echo ""
}

# Check if process is running
#
# Checks if a process with the given PID is currently running.
# Uses kill -0 which checks process existence without sending a signal.
# This is a safe way to verify if a PID is valid and the process exists.
#
# Arguments:
#   $1: Process ID to check (integer, may be empty)
#
# Returns:
#   0: Process is running (PID is valid and process exists)
#   1: Process is not running or PID is empty/invalid
#
# Examples:
#   if is_process_running "$pid"; then
#       echo "Process $pid is still running"
#   fi
#
# Note:
#   Uses kill -0 which sends signal 0 (no-op) to check process existence
#   Empty PID returns 1 (not running)
#   Errors are suppressed (2>/dev/null) to handle invalid PIDs gracefully
is_process_running() {
	local pid="$1"

	if [[ -z "$pid" ]]; then
		return 1 # Empty PID, not running
	fi

	if kill -0 "$pid" 2>/dev/null; then
		return 0 # Process is running
	else
		return 1 # Process is not running
	fi
}

# Create lockfile atomically
#
# Creates a lockfile atomically using noclobber mode (set -C).
# Format: timestamp:pid (e.g., "1704067200:12345")
# Uses subshell with set -C to prevent race conditions.
#
# Arguments:
#   $1: Optional lockfile path (defaults to $LOCKFILE if not provided)
#
# Returns:
#   0: Lockfile created successfully
#   1: Failed to create lockfile (already exists or other error)
#
# Side effects:
#   - Creates lockfile with timestamp:pid format
#   - Lockfile contains: "$(get_unix_timestamp):$$"
#
# Examples:
#   if create_lockfile_atomically; then
#       echo "Lock acquired"
#   else
#       echo "Lock already exists"
#   fi
#
# Note:
#   Requires LOCKFILE to be set (from config.sh) if argument not provided
#   Uses set -C (noclobber) in subshell for atomic check-and-create
#   Trap setup should be handled by the caller after successful lock acquisition
create_lockfile_atomically() {
	local lockfile="${1:-$LOCKFILE}"

	# set -C: noclobber mode - prevents overwriting existing file (atomic check-and-create)
	if (
		set -C
		echo "$(get_unix_timestamp):$$" >"$lockfile"
	) 2>/dev/null; then
		return 0 # Success
	else
		return 1 # Failed (file already exists or other error)
	fi
}

# Check if lockfile is stale (exceeded timeout)
#
# Determines if an existing lockfile is stale (older than LOCKFILE_TIMEOUT seconds).
# Stale lockfiles indicate a hung or crashed previous instance that didn't clean up.
# Compares file modification time to current time using safe timestamp arithmetic.
#
# Arguments:
#   None
#
# Returns:
#   0: Lockfile is stale (exceeded timeout) or unreadable
#   1: Lockfile is not stale (within timeout) or doesn't exist
#
# Examples:
#   if check_lockfile_stale; then
#       echo "Lockfile is stale, removing..."
#       rm -f "$LOCKFILE"
#   fi
#
# Note:
#   Uses get_file_mtime to get file modification time
#   Requires LOCKFILE, LOCKFILE_TIMEOUT, LOCKFILE_MAX_AGE_SECONDS, get_file_mtime, and calculate_duration to be set
#   If file mtime cannot be determined (returns 0), considers lockfile stale
#   Uses calculate_duration() for safe timestamp arithmetic (handles clock skew)
#   Detects clock skew: if lockfile mtime is in the future but within LOCKFILE_MAX_AGE_SECONDS, logs warning
#   but does not treat as stale (safer to keep lockfile than remove valid one)
#   Clock skew can occur due to NTP adjustments, VM snapshot restores, or system clock changes
#   Hard maximum age: if lockfile mtime differs from now by more than LOCKFILE_MAX_AGE_SECONDS in either
#   direction, the lockfile is always treated as stale (prevents far-future/corrupt timestamps from blocking)
check_lockfile_stale() {
	if [[ ! -f "$LOCKFILE" ]]; then
		return 1 # No lockfile, not stale
	fi

	local lockfile_age
	local lockfile_mtime
	local now
	local clock_skew_threshold=60 # Seconds - detect significant clock skew (future-dated lockfile)

	now=$(get_unix_timestamp)
	lockfile_mtime=$(get_file_mtime "$LOCKFILE")

	if [[ $lockfile_mtime -eq 0 ]]; then
		# Can't get mtime, assume stale if file exists but unreadable
		return 0 # Consider stale
	fi

	# Hard maximum age: if lockfile is more than LOCKFILE_MAX_AGE_SECONDS from "now" in either direction,
	# treat as stale (prevents far-future or corrupted timestamps from permanently blocking execution)
	local abs_age=$((lockfile_mtime - now))
	[[ $abs_age -lt 0 ]] && abs_age=$((-abs_age))
	if [[ $abs_age -gt $LOCKFILE_MAX_AGE_SECONDS ]]; then
		return 0 # Stale (exceeds hard maximum age in either direction)
	fi

	# Check for clock skew: lockfile mtime in the future (but within hard max age)
	# This can happen if system clock moved backward (NTP adjustment, VM restore)
	# We log info but don't treat as stale (safer to keep lockfile than remove valid one)
	if [[ $lockfile_mtime -gt $now ]]; then
		local future_diff=$((lockfile_mtime - now))
		if [[ $future_diff -gt $clock_skew_threshold ]]; then
			# Significant clock skew detected - log warning but don't treat as stale
			if type log_message >/dev/null 2>&1; then
				log_message "INFO" "SYSTEM" "Clock skew detected: lockfile mtime is ${future_diff}s in the future (lockfile: $lockfile_mtime, now: $now). Not treating as stale."
			fi
			return 1 # Not stale (future-dated due to clock skew)
		fi
		# Small future difference (<= threshold) - likely minor NTP adjustment, treat as not stale
		return 1
	fi

	# Use calculate_duration() for safe timestamp arithmetic
	# This handles negative values (clamps to 0) and validates timestamps
	lockfile_age=$(calculate_duration "$lockfile_mtime" "$now" 2>/dev/null || echo "0")

	if [[ "$lockfile_age" -gt "$LOCKFILE_TIMEOUT" ]]; then
		return 0 # Stale (exceeded timeout)
	fi

	return 1 # Not stale
}

# Remove stale lockfile if needed
#
# Checks if lockfile is stale and removes it if so, logging a warning.
# This is a helper function to reduce code duplication across lockfile functions.
# Extracts PID from lockfile before removal for warning message.
#
# Arguments:
#   None
#
# Returns:
#   0: Lockfile was stale and removed (or didn't exist)
#   1: Lockfile exists and is not stale (still valid)
#
# Side effects:
#   - Removes stale lockfile if it exists and is stale
#   - Logs warning message to stderr with PID if removed
#
# Examples:
#   if remove_stale_lockfile_if_needed; then
#       echo "Stale lockfile removed, can proceed"
#   fi
#
# Note:
#   Requires LOCKFILE, extract_lockfile_pid, and check_lockfile_stale to be set
#   Warning message includes PID from lockfile for debugging
#   Outputs to stderr (>&2) for visibility
remove_stale_lockfile_if_needed() {
	if [[ ! -f "$LOCKFILE" ]]; then
		return 0 # No lockfile, nothing to remove
	fi

	if ! check_lockfile_stale; then
		return 1 # Lockfile exists and is not stale
	fi

	# Lockfile is stale, remove it and log
	local stale_pid
	stale_pid=$(extract_lockfile_pid "$LOCKFILE" || echo "unknown")
	rm -f "$LOCKFILE"
	log_message "INFO" "SYSTEM" "Removed stale lockfile (timeout exceeded, PID was: $stale_pid)"
	return 0
}

# Log lockfile conflict and exit
#
# Logs an info message about lockfile conflict and exits the script gracefully.
# Handles both log file write and stderr output consistently.
# Exits with code 0 (success) to avoid cron job failures.
#
# Arguments:
#   $1: Optional PID of conflicting process (included in message if provided)
#   $2: Optional custom message (defaults to "Another instance is already running")
#
# Returns:
#   Never returns (exits script with code 0)
#
# Side effects:
#   - Writes info message to log file (if possible, errors ignored)
#   - Outputs info message to stderr
#   - Exits script with code 0 (success, to avoid cron failures)
#
# Examples:
#   log_and_exit_lockfile_conflict "$pid"
#   log_and_exit_lockfile_conflict "" "Custom conflict message"
#
# Note:
#   Requires log_message() function to be available (from logging.sh)
#   log_message() handles timestamp formatting and log file writes internally
#   Log file write errors are handled gracefully by log_message() (outputs to stderr if file write fails)
#   Always exits with code 0 to prevent cron job failures
log_and_exit_lockfile_conflict() {
	local pid="${1:-}"
	local custom_message="${2:-}"

	# Build message
	local message
	if [[ -n "$custom_message" ]]; then
		message="$custom_message"
	elif [[ -n "$pid" ]]; then
		message="Another instance (PID $pid) is already running, exiting"
	else
		message="Another instance is already running, exiting"
	fi

	# Use log_message() for consistent logging (handles file write failures gracefully)
	# log_message() will output to stderr for INFO level messages
	log_message "INFO" "SYSTEM" "$message"

	exit "${EXIT_SUCCESS:-0}"
}

# Acquire lockfile using flock (preferred method)
#
# Attempts to acquire lockfile using flock command.
# Handles stale lockfiles and retries as needed.
#
# This implementation uses explicit fd opening inside the subshell (not the
# `( ... ) 9>file` pattern) to avoid a TOCTOU race condition where the file
# would be created/truncated before any lock logic runs.
#
# Arguments:
#   $1: Function to execute after lock is acquired (typically main function)
#   $@: Arguments to pass to the function
#
# Returns:
#   Never returns directly (exits via log_and_exit_lockfile_conflict or executes function)
#
# Side effects:
#   - Creates lockfile with timestamp:pid
#   - Executes provided function with arguments
#   - Removes lockfile on exit (always, since we created/truncated it)
#
# Note:
#   Requires LOCKFILE, check_lockfile_stale, log_and_exit_lockfile_conflict to be set
acquire_lockfile_flock() {
	local main_func="$1"
	shift

	# Save existing lockfile info BEFORE entering subshell (before truncation)
	# This allows us to:
	# 1. Report the correct PID in conflict messages (file will be truncated when we open it)
	# 2. Know if the lockfile was stale (for retry logic after flock fails)
	# 3. Exit early if another instance is running (don't truncate their lockfile)
	local existing_pid=""
	local was_stale=0
	if file_exists_and_readable "$LOCKFILE"; then
		existing_pid=$(extract_lockfile_pid "$LOCKFILE" 2>/dev/null || echo "")
		# If lockfile has a running PID, exit immediately
		# This prevents us from truncating another process's lockfile
		if [[ -n "$existing_pid" ]] && is_process_running "$existing_pid"; then
			log_and_exit_lockfile_conflict "$existing_pid"
		fi
		# Check if stale for retry logic (used if flock fails)
		if check_lockfile_stale; then
			was_stale=1
		fi
	fi

	# Use subshell to isolate traps and ensure cleanup
	# NOTE: We do NOT use `) 9>"$LOCKFILE"` because that opens the file
	# BEFORE any subshell code runs, causing TOCTOU issues. Instead, we
	# use explicit `exec 9>` inside the subshell for control.
	(
		# Track signal type for proper exit code
		local signal_exit_code=0
		# Track if we actually acquired the lock
		local lock_acquired=0
		# Track if cleanup has already run (prevents double cleanup)
		local cleanup_done=0
		# Track if we opened the file (for cleanup purposes)
		local file_opened=0

		# Cleanup function for signal handlers
		# Ensures file descriptor is closed and lockfile is removed
		#
		# Arguments:
		#   None (uses $? to capture exit code from trap context)
		#
		# Returns:
		#   Never returns (exits script with appropriate exit code)
		#
		# Side effects:
		#   - Closes file descriptor 9
		#   - Removes lockfile if we opened it (we always clean up what we create)
		#   - Exits script with appropriate exit code
		cleanup_and_exit() {
			local actual_exit_code=$?

			# Prevent double cleanup (defensive programming)
			if [[ $cleanup_done -eq 1 ]]; then
				if [[ ${signal_exit_code:-0} -ne 0 ]]; then
					exit "$signal_exit_code"
				else
					exit "$actual_exit_code"
				fi
			fi
			cleanup_done=1

			# Close file descriptor first (more critical than removing lockfile)
			exec 9>&- 2>/dev/null || true

			# Always remove lockfile if we opened it
			# We created/truncated it via our redirect, so we should clean it up
			# regardless of whether we acquired the lock. This prevents orphan lockfiles.
			if [[ $file_opened -eq 1 ]]; then
				rm -f "$LOCKFILE" 2>/dev/null || true
			fi

			if [[ ${signal_exit_code:-0} -ne 0 ]]; then
				exit "$signal_exit_code"
			else
				exit "$actual_exit_code"
			fi
		}

		# Set up cleanup trap to ensure lock is released
		# INT (Ctrl+C) should exit with 130, TERM with 143
		trap 'signal_exit_code=130; cleanup_and_exit' INT
		trap 'signal_exit_code=143; cleanup_and_exit' TERM
		trap 'cleanup_and_exit' EXIT

		# Open lockfile for writing (creates/truncates the file)
		# This is explicit so we control when it happens and can track it
		exec 9>"$LOCKFILE"
		file_opened=1

		# Try non-blocking flock
		if flock -n 9; then
			# Lock acquired - write our PID
			echo "$(get_unix_timestamp):$$" >"$LOCKFILE"
			lock_acquired=1

			# Run main function and capture its exit code
			"$main_func" "$@"
			local main_exit_code=$?

			if [[ $signal_exit_code -eq 0 ]]; then
				signal_exit_code=$main_exit_code
			fi
		else
			# flock failed - another process might have the lock
			# Check if the lockfile WAS stale (before we truncated it)
			# We saved this info before entering the subshell
			if [[ "$was_stale" -eq 1 ]]; then
				# Lockfile was stale - close fd, remove file, reopen, retry
				# This is the proper sequence: we must close and reopen to get a new inode
				exec 9>&- 2>/dev/null || true
				rm -f "$LOCKFILE"
				log_message "INFO" "SYSTEM" "Removed stale lockfile (timeout exceeded, previous PID was: ${existing_pid:-unknown})"

				# Reopen fd to new file
				exec 9>"$LOCKFILE"

				if flock -n 9; then
					# Got the lock on second try
					echo "$(get_unix_timestamp):$$" >"$LOCKFILE"
					lock_acquired=1

					"$main_func" "$@"
					local main_exit_code=$?

					if [[ $signal_exit_code -eq 0 ]]; then
						signal_exit_code=$main_exit_code
					fi
				else
					# Still can't get lock - another process beat us to it
					log_and_exit_lockfile_conflict "${existing_pid:-}"
				fi
			else
				# Lockfile was not stale - another instance is actually running
				log_and_exit_lockfile_conflict "${existing_pid:-}"
			fi
		fi

		# Explicit cleanup (EXIT trap also runs but cleanup_done prevents double)
		exec 9>&- 2>/dev/null || true
		if [[ $file_opened -eq 1 ]]; then
			rm -f "$LOCKFILE" 2>/dev/null || true
		fi
		cleanup_done=1
	)
}

# Acquire lockfile using fallback method (atomic file creation)
#
# Attempts to acquire lockfile using atomic file creation (noclobber).
# Less reliable than flock but works on systems without flock.
#
# **Race Condition Limitations:**
# This fallback method has inherent TOCTOU (Time-Of-Check-Time-Of-Use) race conditions:
# - Between checking if lockfile exists and reading its PID
# - Between checking and attempting atomic creation
# - During retry logic when another process may acquire the lock
#
# These races are mitigated by:
# - Atomic file creation using `set -C` (noclobber mode)
# - Retry logic (limited to FALLBACK_MAX_RETRIES attempts)
# - PID validation before treating lockfile as valid
#
# However, in rare cases, concurrent execution may still occur if:
# - Multiple processes attempt lock acquisition simultaneously
# - Race windows align unfavorably
# - PID reuse occurs between check and validation
#
# This is acceptable for a fallback method that is only used when flock is unavailable
# (which should be rare on UDM OS 4.3+). The primary flock method provides proper
# atomic locking when available.
#
# Arguments:
#   $1: Function to execute after lock is acquired (typically main function)
#   $@: Arguments to pass to the function
#
# Returns:
#   Never returns directly (exits via log_and_exit_lockfile_conflict or executes function)
#
# Side effects:
#   - Creates lockfile with timestamp:pid
#   - Executes provided function with arguments
#   - Removes lockfile on exit
#
# Note:
#   Requires LOCKFILE, remove_stale_lockfile_if_needed, extract_lockfile_pid,
#   is_process_running, create_lockfile_atomically, log_and_exit_lockfile_conflict to be set
acquire_lockfile_fallback() {
	local main_func="$1"
	shift

	# Fallback: simple lockfile check (less reliable but better than nothing)
	# Use atomic file creation to avoid race conditions
	# Format: timestamp:pid
	local lock_pid=""
	local lock_acquired=0

	# Check if existing lockfile is stale
	if file_exists_and_readable "$LOCKFILE"; then
		if remove_stale_lockfile_if_needed; then
			# Lockfile was stale and removed, continue to try acquiring lock
			:
		else
			# Lockfile exists and is not stale, check PID
			lock_pid=$(extract_lockfile_pid "$LOCKFILE")
			if is_process_running "$lock_pid"; then
				# Process is still running
				log_and_exit_lockfile_conflict "$lock_pid"
			fi
			# PID is dead but lockfile not stale (shouldn't happen often), remove it
			rm -f "$LOCKFILE"
		fi
	fi

	# Try to create lockfile atomically with timestamp:pid format
	if create_lockfile_atomically "$LOCKFILE"; then
		# Successfully created lockfile
		lock_acquired=1
	else
		# Race condition - another process got it first
		# Check if the PID in the lockfile is still running before exiting
		if file_exists_and_readable "$LOCKFILE"; then
			lock_pid=$(extract_lockfile_pid "$LOCKFILE")
			if is_process_running "$lock_pid"; then
				# Process is still running - legitimate lockfile
				log_and_exit_lockfile_conflict "$lock_pid"
			else
				# PID is not running - stale lockfile, remove it and try again
				rm -f "$LOCKFILE"
				log_message "INFO" "SYSTEM" "Removed stale lockfile (PID $lock_pid not running), retrying"
				# Retry lockfile creation (limited to FALLBACK_MAX_RETRIES attempts)
				if create_lockfile_atomically "$LOCKFILE"; then
					lock_acquired=1
				else
					# Still can't acquire after retry - another process may have gotten it
					# Check PID one more time
					if file_exists_and_readable "$LOCKFILE"; then
						lock_pid=$(extract_lockfile_pid "$LOCKFILE")
						if is_process_running "$lock_pid"; then
							log_and_exit_lockfile_conflict "$lock_pid"
						fi
					fi
					# Final fallback - couldn't acquire lockfile after FALLBACK_MAX_RETRIES attempts
					log_and_exit_lockfile_conflict "" "Could not acquire lockfile after ${FALLBACK_MAX_RETRIES} retry attempt(s), exiting"
				fi
			fi
		else
			# Lockfile doesn't exist (shouldn't happen after failed creation, but handle it)
			log_and_exit_lockfile_conflict "" "Could not acquire lockfile, exiting"
		fi
	fi

	if [[ $lock_acquired -eq 1 ]]; then
		# Track signal type for proper exit code
		local signal_exit_code=0

		# Cleanup function for signal handlers
		# Ensures lockfile is removed on exit.
		#
		# Arguments:
		#   None (uses $? to capture exit code from trap context)
		#
		# Returns:
		#   Never returns (exits script with appropriate exit code)
		#
		# Side effects:
		#   - Removes lockfile
		#   - Exits script with appropriate exit code
		cleanup_and_exit() {
			# Capture the actual exit code from the script
			# When called from EXIT trap, $? contains the exit code that triggered the trap
			local actual_exit_code=$?

			rm -f "$LOCKFILE"

			# Use signal_exit_code if it's non-zero (set by signal handler)
			# Otherwise use actual_exit_code (from die() or main return)
			# This preserves exit codes from die() calls or main function returns
			if [[ ${signal_exit_code:-0} -ne 0 ]]; then
				exit "$signal_exit_code"
			else
				exit "$actual_exit_code"
			fi
		}

		# Set up cleanup trap to ensure lockfile is removed on exit
		# INT (Ctrl+C) should exit with 130, TERM with 143
		# shellcheck disable=SC2064
		trap 'signal_exit_code=130; cleanup_and_exit' INT
		# shellcheck disable=SC2064
		trap 'signal_exit_code=143; cleanup_and_exit' TERM
		# shellcheck disable=SC2064
		trap 'cleanup_and_exit' EXIT

		# Run main function and capture its exit code
		"$main_func" "$@"
		local main_exit_code=$?

		# If no signal was received, use main function's exit code
		# (signal_exit_code is only set by signal handlers)
		if [[ ${signal_exit_code:-0} -eq 0 ]]; then
			signal_exit_code=$main_exit_code
		fi

		# Explicitly remove lockfile before exit (trap handles cleanup on error)
		rm -f "$LOCKFILE"
	fi
}

# Check directory writability and exit with error if not writable
#
# Checks if a directory is writable before attempting to create lockfile.
# This prevents hanging when directories are read-only.
# Exits the script with appropriate error message if directory is not writable.
#
# Arguments:
#   $1: Directory path to check
#   $2: Description of directory for error message (e.g., "STATE_DIR" or "Lockfile directory")
#
# Returns:
#   Never returns if directory is not writable (exits script)
#   0: Directory is writable or doesn't exist (check passed)
#
# Side effects:
#   - Exits script with error if directory exists but is not writable
#   - Always exits with error code (even in fake mode) since lockfile is required for script execution
check_directory_writable_for_lockfile() {
	local dir="$1"
	local description="$2"

	# Skip check if directory doesn't exist or is empty
	if [[ -z "$dir" ]] || [[ ! -d "$dir" ]]; then
		return 0
	fi

	# Check if directory is writable
	local is_writable=0
	if type directory_writable >/dev/null 2>&1; then
		directory_writable "$dir" && is_writable=1 || is_writable=0
	elif [[ -w "$dir" ]]; then
		is_writable=1
	fi

	# Exit with error if directory is not writable
	# Note: This is a fatal error that prevents script execution (cannot create lockfile),
	# so we exit with error code even in fake mode
	if [[ $is_writable -eq 0 ]]; then
		local error_msg="${description} is not writable: $dir (cannot create lockfile). Please check directory permissions or choose a writable directory"
		# Log error message first (respects fake mode for logging)
		if type handle_error_or_exit_fake_mode >/dev/null 2>&1; then
			# Log the error (this respects fake mode for logging)
			handle_error_or_exit_fake_mode "SYSTEM" "$error_msg" "${EXIT_PERMISSION_ERROR:-4}" 2>/dev/null || true
		fi
		# Always exit with error code - this is fatal and prevents script execution
		# Even in fake mode, we cannot proceed without a lockfile
		if type die >/dev/null 2>&1; then
			die "$error_msg" "${EXIT_PERMISSION_ERROR:-4}"
		else
			# Fallback if die() is not available - use log_message() if available, otherwise echo
			if type log_message >/dev/null 2>&1; then
				log_message "ERROR" "SYSTEM" "$error_msg"
			else
				echo "ERROR: $error_msg" >&2
			fi
			exit "${EXIT_PERMISSION_ERROR:-4}"
		fi
	fi

	return 0
}

# Attempts to acquire lockfile using flock if available, otherwise falls back to atomic file creation.
#
# Arguments:
#   $1: Function to execute after lock is acquired (typically main function)
#   $@: Arguments to pass to the function
#
# Returns:
#   In fake mode: May return with exit code from main function if lockfile directory cannot be created
#   Otherwise: Never returns directly (exits via log_and_exit_lockfile_conflict, early error exit, or executes function)
#
# Side effects:
#   - Creates lockfile with timestamp:pid
#   - Executes provided function with arguments
#   - Removes lockfile on exit
#   - Exits early with error if STATE_DIR is not writable
#   - In fake mode: May skip lockfile acquisition if directory cannot be created
acquire_lockfile() {
	local main_func="$1"
	shift

	# Check if STATE_DIR is writable before attempting to acquire lockfile
	# This prevents hanging when STATE_DIR is read-only
	local lockfile_dir
	if [[ -n "${LOCKFILE:-}" ]]; then
		lockfile_dir=$(dirname "$LOCKFILE" 2>/dev/null || echo "")
	fi
	if [[ -z "$lockfile_dir" ]] || [[ "$lockfile_dir" == "." ]]; then
		# Fallback to STATE_DIR if we can't determine lockfile directory
		lockfile_dir="${STATE_DIR:-}"
	fi

	# In fake mode, if the lockfile directory doesn't exist and can't be created,
	# skip lockfile acquisition and just run the main function directly
	# This allows the script to continue in fake mode even when STATE_DIR can't be created
	if is_fake_mode && [[ -n "$lockfile_dir" ]] && [[ ! -d "$lockfile_dir" ]]; then
		# Check if we can create the directory using the standard utility function
		if ! try_ensure_directory_exists "$lockfile_dir"; then
			# Directory doesn't exist and can't be created - skip lockfile in fake mode
			# Log a warning but continue execution
			if type handle_error >/dev/null 2>&1; then
				handle_error "WARNING" "SYSTEM" "Lockfile directory does not exist and cannot be created: $lockfile_dir (skipping lockfile in fake mode)"
			fi
			# Just run the main function directly without lockfile protection
			"$main_func" "$@"
			return $?
		fi
	fi

	# Always check STATE_DIR writability if it's set and exists
	# This prevents hanging when STATE_DIR is read-only, even if LOCKFILE isn't set yet
	check_directory_writable_for_lockfile "${STATE_DIR:-}" "STATE_DIR"

	# Also check lockfile_dir if it's different from STATE_DIR
	if [[ -n "$lockfile_dir" ]] && [[ "$lockfile_dir" != "${STATE_DIR:-}" ]]; then
		check_directory_writable_for_lockfile "$lockfile_dir" "Lockfile directory"
	fi

	if check_command_available "flock"; then
		acquire_lockfile_flock "$main_func" "$@"
	else
		acquire_lockfile_fallback "$main_func" "$@"
	fi
}
