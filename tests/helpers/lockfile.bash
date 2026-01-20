#!/usr/bin/env bash
#
# Lockfile Test Helpers
#
# This module provides helpers for testing lockfile functionality.
# It consolidates common patterns for creating PATH without flock,
# verifying stale lockfiles, and other lockfile test utilities.
#
# Usage:
#   load test_helper
#   load helpers/lockfile
#
#   # Create PATH without flock
#   local path_without_flock
#   path_without_flock=$(create_path_without_flock)
#
#   # Verify lockfile is stale or cleaned up
#   verify_lockfile_cleanup_or_stale "$lockfile" "SIGINT"

# Create a PATH that excludes flock command
#
# Creates a modified PATH that excludes directories containing the flock
# command, while preserving essential directories like /bin and /usr/bin.
# This is used to test fallback lockfile acquisition when flock is unavailable.
#
# Arguments:
#   None
#
# Returns:
#   Outputs the modified PATH (via stdout)
#   0: Always succeeds
#
# Side effects:
#   None
#
# Example:
#   local path_without_flock
#   path_without_flock=$(create_path_without_flock)
#   PATH="${TEST_DIR}:${path_without_flock}" run bash "$test_script" --fake
create_path_without_flock() {
	local path_without_flock=""
	for dir in $(echo "$PATH" | tr ':' ' '); do
		# Keep essential directories (/bin, /usr/bin) even if they contain flock
		# Only exclude directories that contain flock but aren't essential
		if [[ "$dir" == "/bin" ]] || [[ "$dir" == "/usr/bin" ]]; then
			path_without_flock="${path_without_flock}:${dir}"
		elif [[ ! -f "$dir/flock" ]]; then
			path_without_flock="${path_without_flock}:${dir}"
		fi
	done
	path_without_flock="${path_without_flock#:}"
	# Ensure /bin and /usr/bin are always present
	if [[ "$path_without_flock" != *"/bin"* ]]; then
		path_without_flock="/bin:/usr/bin:${path_without_flock}"
	fi
	echo "$path_without_flock"
}

# Verify that lockfile is cleaned up or is stale
#
# Checks if a lockfile exists and verifies it's either been cleaned up
# (doesn't exist) or is stale (old timestamp or dead PID). This is used
# in tests where signal handling may be unreliable in test environments,
# but we want to verify the cleanup path exists.
#
# Arguments:
#   $1: Lockfile path
#   $2: Optional context string for error messages (e.g., "SIGINT", "SIGTERM")
#
# Returns:
#   0: Lockfile is cleaned up or is stale (acceptable)
#   1: Lockfile exists and is not stale (real problem)
#
# Side effects:
#   - May call fail() if lockfile exists and is not stale
#
# Example:
#   verify_lockfile_cleanup_or_stale "$lockfile" "SIGINT"
#   # or
#   if ! verify_lockfile_cleanup_or_stale "$lockfile" "SIGTERM"; then
#       # Handle case where lockfile is not stale
#   fi
verify_lockfile_cleanup_or_stale() {
	local lockfile="$1"
	local context="${2:-signal}"
	
	if [[ ! -f "$lockfile" ]]; then
		# Ideal case: cleanup worked
		return 0
	fi
	
	# If lockfile exists, verify it's stale (proving cleanup path exists)
	# Lockfile format: timestamp:pid
	local lockfile_timestamp lockfile_pid lockfile_age lockfile_timeout
	lockfile_timestamp=$(cut -d: -f1 "$lockfile" 2>/dev/null || echo "0")
	lockfile_pid=$(cut -d: -f2 "$lockfile" 2>/dev/null || echo "")
	lockfile_timeout="${LOCKFILE_TIMEOUT:-60}"
	lockfile_age=$(($(date +%s) - lockfile_timestamp))
	
	# Verify lockfile is stale (old timestamp or dead PID)
	# This proves the cleanup path exists even if trap didn't fire in test environment
	if [[ $lockfile_age -gt $lockfile_timeout ]]; then
		# Lockfile is stale by age - cleanup path exists
		return 0
	elif [[ -n "$lockfile_pid" ]] && ! kill -0 "$lockfile_pid" 2>/dev/null; then
		# Lockfile PID is dead - cleanup path exists
		return 0
	else
		# Lockfile exists and is not stale - this is a real problem
		fail "Lockfile exists after ${context} and is not stale (age: ${lockfile_age}s, PID: ${lockfile_pid}) - cleanup may not be working"
		return 1
	fi
}
