#!/bin/bash
#
# Resource monitoring functions for UDM VPN Monitor
# Monitors CPU, RAM, and disk space usage and implements throttling
#
# Version: 0.5.0
#

# Source common utility functions
# shellcheck source=lib/common.sh
# Determine lib directory (where this file is located)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LIB_DIR}/common.sh" 2>/dev/null || {
	# Fallback if common.sh not found - use centralized fallbacks
	# shellcheck source=lib/fallbacks.sh
	if [[ -n "${LIB_DIR:-}" ]] && [[ -f "${LIB_DIR}/fallbacks.sh" ]] && [[ -r "${LIB_DIR}/fallbacks.sh" ]]; then
		source "${LIB_DIR}/fallbacks.sh" 2>/dev/null && define_common_fallbacks
	fi
}

# Get CPU usage percentage
#
# Calculates current CPU usage percentage by sampling /proc/stat over a short interval.
# Uses a simple method: compares CPU idle time before and after a 1-second sleep.
# This provides a reasonable approximation of current CPU load.
#
# Arguments:
#   None
#
# Returns:
#   0: Success, prints CPU usage percentage (0-100) to stdout
#   1: Failed to calculate CPU usage (fallback to 0)
#
# Output:
#   Prints CPU usage percentage as integer (0-100) to stdout
#
# Examples:
#   cpu_usage=$(get_cpu_usage)
#   if [[ $cpu_usage -gt 90 ]]; then
#       echo "CPU usage is high: ${cpu_usage}%"
#   fi
#
# Note:
#   Requires /proc/stat to be readable
#   Uses 1-second sampling interval for accuracy
#   Returns 0 if calculation fails (graceful degradation)
get_cpu_usage() {
	local cpu_stat_file="/proc/stat"
	if [[ ! -r "$cpu_stat_file" ]]; then
		return 1
	fi

	# Read first line of /proc/stat (CPU totals)
	local cpu_line1
	cpu_line1=$(grep '^cpu ' "$cpu_stat_file" 2>/dev/null | head -n1)
	if [[ -z "$cpu_line1" ]]; then
		return 1
	fi

	# Extract idle time (4th field) and total time
	local idle1 total1
	idle1=$(echo "$cpu_line1" | awk '{print $5}')
	total1=$(echo "$cpu_line1" | awk '{sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum}')

	# Sleep for 1 second to get a sample
	sleep 1

	# Read again
	local cpu_line2
	cpu_line2=$(grep '^cpu ' "$cpu_stat_file" 2>/dev/null | head -n1)
	if [[ -z "$cpu_line2" ]]; then
		return 1
	fi

	local idle2 total2
	idle2=$(echo "$cpu_line2" | awk '{print $5}')
	total2=$(echo "$cpu_line2" | awk '{sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum}')

	# Calculate CPU usage percentage
	local idle_diff=$((idle2 - idle1))
	local total_diff=$((total2 - total1))

	if [[ $total_diff -eq 0 ]]; then
		return 1
	fi

	# Validate that idle_diff <= total_diff (shouldn't happen but possible with timing)
	if [[ $idle_diff -gt $total_diff ]]; then
		# Invalid state - idle time increased more than total time
		# This shouldn't happen but can occur with timing issues
		return 1
	fi

	# Calculate usage: (1 - idle/total) * 100
	# Use awk for floating point math (UDM doesn't have bc)
	local cpu_usage
	cpu_usage=$(awk "BEGIN {printf \"%.0f\", (1 - $idle_diff/$total_diff) * 100}")

	# Clamp CPU usage to 0-100 range (shouldn't be needed but protects against edge cases)
	if [[ $cpu_usage -lt 0 ]]; then
		cpu_usage=0
	elif [[ $cpu_usage -gt 100 ]]; then
		cpu_usage=100
	fi

	echo "$cpu_usage"
	return 0
}

# Get memory usage percentage
#
# Calculates current memory usage percentage using the 'free' command.
# Uses MemTotal and MemAvailable (or MemFree if MemAvailable not available) to calculate usage.
# This provides an accurate view of actual memory pressure.
#
# Arguments:
#   None
#
# Returns:
#   0: Success, prints memory usage percentage (0-100) to stdout
#   1: Failed to calculate memory usage (fallback to 0)
#
# Output:
#   Prints memory usage percentage as integer (0-100) to stdout
#
# Examples:
#   mem_usage=$(get_memory_usage)
#   if [[ $mem_usage -gt 90 ]]; then
#       echo "Memory usage is high: ${mem_usage}%"
#   fi
#
# Note:
#   Requires 'free' command to be available
#   Uses MemAvailable if available (more accurate), falls back to MemFree
#   Returns 0 if calculation fails (graceful degradation)
get_memory_usage() {
	if ! check_command_available "free"; then
		return 1
	fi

	# Get memory info from free command (in KB)
	local mem_info
	mem_info=$(free 2>/dev/null | grep '^Mem:')
	if [[ -z "$mem_info" ]]; then
		return 1
	fi

	local total_kb available_kb
	total_kb=$(echo "$mem_info" | awk '{print $2}')
	available_kb=$(echo "$mem_info" | awk '{print $7}') # MemAvailable (Linux 3.14+)

	# If MemAvailable not available, use MemFree
	if [[ -z "$available_kb" ]] || [[ "$available_kb" == "0" ]]; then
		available_kb=$(echo "$mem_info" | awk '{print $4}') # MemFree
	fi

	if [[ -z "$total_kb" ]] || [[ "$total_kb" -eq 0 ]]; then
		return 1
	fi

	# Calculate usage: (1 - available/total) * 100
	local mem_usage
	mem_usage=$(awk "BEGIN {printf \"%.0f\", (1 - $available_kb/$total_kb) * 100}")
	echo "$mem_usage"
	return 0
}

# Get disk usage percentage for a path
#
# Calculates disk usage percentage for the filesystem containing the specified path.
# Uses 'df' command to get filesystem statistics.
#
# Arguments:
#   $1: Path to check (defaults to /data if not provided)
#
# Returns:
#   0: Success, prints disk usage percentage (0-100) to stdout
#   1: Failed to calculate disk usage (fallback to 0)
#
# Output:
#   Prints disk usage percentage as integer (0-100) to stdout
#
# Examples:
#   disk_usage=$(get_disk_usage "/data")
#   if [[ $disk_usage -gt 80 ]]; then
#       echo "Disk usage is high: ${disk_usage}%"
#   fi
#
# Note:
#   Requires 'df' command to be available
#   Returns usage percentage for the filesystem containing the path
#   Returns 0 if calculation fails (graceful degradation)
get_disk_usage() {
	local path="${1:-/data}"
	if ! check_command_available "df"; then
		return 1
	fi

	# Get disk usage for the filesystem containing the path
	local df_output
	df_output=$(df -P "$path" 2>/dev/null | tail -n1)
	if [[ -z "$df_output" ]]; then
		return 1
	fi

	# Extract usage percentage (5th field, format: "85%")
	local usage_pct
	usage_pct=$(echo "$df_output" | awk '{print $5}' | sed 's/%//')
	if [[ -z "$usage_pct" ]]; then
		return 1
	fi

	echo "$usage_pct"
	return 0
}

# Get free disk space percentage for a path
#
# Calculates free disk space percentage for the filesystem containing the specified path.
# Uses 'df' command to get filesystem statistics.
#
# Arguments:
#   $1: Path to check (defaults to /data if not provided)
#
# Returns:
#   0: Success, prints free disk space percentage (0-100) to stdout
#   1: Failed to calculate free disk space (fallback to 100)
#
# Output:
#   Prints free disk space percentage as integer (0-100) to stdout
#
# Examples:
#   free_space=$(get_free_disk_space "/data")
#   if [[ $free_space -lt 20 ]]; then
#       echo "Free disk space is low: ${free_space}%"
#   fi
#
# Note:
#   Requires 'df' command to be available
#   Returns free space percentage for the filesystem containing the path
#   Returns 100 if calculation fails (assume space available, graceful degradation)
get_free_disk_space() {
	local path="${1:-/data}"
	if ! check_command_available "df"; then
		return 1
	fi

	# Get disk usage for the filesystem containing the path
	local df_output
	df_output=$(df -P "$path" 2>/dev/null | tail -n1)
	if [[ -z "$df_output" ]]; then
		return 1
	fi

	# Extract available and total (in 1K blocks)
	local available_kb total_kb
	available_kb=$(echo "$df_output" | awk '{print $4}')
	total_kb=$(echo "$df_output" | awk '{print $2}')

	if [[ -z "$available_kb" ]] || [[ -z "$total_kb" ]] || [[ "$total_kb" -eq 0 ]]; then
		return 1
	fi

	# Calculate free percentage: (available/total) * 100
	local free_pct
	free_pct=$(awk "BEGIN {printf \"%.0f\", ($available_kb/$total_kb) * 100}")
	echo "$free_pct"
	return 0
}

# Check if resource is constrained and update state tracking
#
# Checks if a resource (CPU or RAM) has been constrained for a specified duration.
# Tracks state in a state file to remember when the resource first became constrained.
# This allows detection of resources that are "pegged" for a period of time.
#
# Arguments:
#   $1: Resource name (e.g., "cpu", "ram")
#   $2: Current usage percentage (0-100)
#   $3: Threshold percentage (0-100) - resource is constrained if usage >= threshold
#   $4: Duration in seconds - resource must be constrained for this duration
#   $5: State directory for storing state files
#
# Returns:
#   0: Resource is constrained (has been >= threshold for >= duration)
#   1: Resource is not constrained, hasn't been constrained long enough, or invalid input
#
# Side effects:
#   - Creates/updates state file: ${STATE_DIR}/resource_${resource}_constrained
#   - State file contains timestamp when resource first became constrained
#   - Removes state file when resource is no longer constrained
#   - Logs warnings for invalid usage values (non-numeric or out of range)
#
# Examples:
#   if check_resource_constrained "cpu" 95 90 60 "$STATE_DIR"; then
#       echo "CPU has been at 90%+ for 60 seconds"
#   fi
#
# Note:
#   Requires STATE_DIR to be writable
#   State file format: unix timestamp (seconds since epoch)
#   Validates usage is numeric and within range (0-100) before processing
#   Returns error (1) and logs warning for invalid usage values
check_resource_constrained() {
	local resource="$1"
	local usage="$2"
	local threshold="$3"
	local duration="$4"
	local state_dir="$5"

	if [[ -z "$resource" ]] || [[ -z "$usage" ]] || [[ -z "$threshold" ]] || [[ -z "$duration" ]] || [[ -z "$state_dir" ]]; then
		return 1
	fi

	# Validate usage is a number and within expected range (0-100)
	if ! [[ "$usage" =~ ^-?[0-9]+$ ]]; then
		# Not a number - invalid input
		if command -v log_message >/dev/null 2>&1; then
			log_message "WARNING" "SYSTEM" "check_resource_constrained: Invalid usage value for ${resource}: '${usage}' (not a number)"
		fi
		return 1
	fi

	# Validate usage is within expected range (0-100)
	if [[ "$usage" -lt 0 ]] || [[ "$usage" -gt 100 ]]; then
		# Out of range - log warning and return error for clearly invalid input
		if command -v log_message >/dev/null 2>&1; then
			log_message "WARNING" "SYSTEM" "check_resource_constrained: Usage value for ${resource} is out of expected range (0-100): ${usage}%"
		fi
		return 1
	fi

	local state_file="${state_dir}/resource_${resource}_constrained"
	local current_time
	current_time=$(date +%s 2>/dev/null)
	if [[ -z "$current_time" ]]; then
		return 1
	fi

	# Ensure state directory exists
	if ! try_ensure_directory_exists "$state_dir"; then
		return 1
	fi

	# Check if resource is currently constrained
	if [[ "$usage" -ge "$threshold" ]]; then
		# Resource is constrained - check if we have a state file
		if [[ -f "$state_file" ]] && file_exists_and_readable "$state_file"; then
			# Read when it first became constrained
			local constrained_since
			constrained_since=$(cat "$state_file" 2>/dev/null)
			if [[ -n "$constrained_since" ]] && [[ "$constrained_since" =~ ^[0-9]+$ ]]; then
				# Check if it's been constrained long enough
				local elapsed=$((current_time - constrained_since))
				if [[ $elapsed -ge $duration ]]; then
					# Resource has been constrained for the required duration
					return 0
				fi
			else
				# Invalid state file, recreate it
				atomic_write_file "$state_file" "$current_time" 2>/dev/null || true
			fi
		else
			# First time we see it constrained, create state file
			atomic_write_file "$state_file" "$current_time" 2>/dev/null || true
		fi
	else
		# Resource is not constrained - remove state file if it exists
		if [[ -f "$state_file" ]]; then
			rm -f "$state_file" 2>/dev/null || true
		fi
	fi

	return 1
}

# Check system resources and implement throttling
#
# Monitors CPU, RAM, and disk space usage and implements throttling if resources are constrained.
# CPU and RAM throttling: exits early if resources have been pegged for a period of time.
# Disk space throttling: logs warnings at 20% free, takes action at 10% free.
#
# Arguments:
#   $1: State directory for storing resource state files
#
# Returns:
#   0: Resources are healthy, script can continue
#   1: Resources are constrained, script should exit early (throttled)
#
# Side effects:
#   - Logs warnings when resources are constrained
#   - May exit script early if resources are severely constrained
#   - Creates/updates resource state files in STATE_DIR
#   - May rotate/cleanup log files if disk space is critical
#
# Examples:
#   if ! check_system_resources "$STATE_DIR"; then
#       log_message "INFO" "Exiting early due to resource constraints"
#       exit 0
#   fi
#
# Note:
#   Requires log_message function to be available
#   Requires configuration variables:
#     - ENABLE_RESOURCE_MONITORING (0 or 1)
#     - RESOURCE_CPU_THRESHOLD (default: 90)
#     - RESOURCE_CPU_DURATION (default: 60 seconds)
#     - RESOURCE_RAM_THRESHOLD (default: 90)
#     - RESOURCE_RAM_DURATION (default: 60 seconds)
#     - RESOURCE_DISK_WARNING_THRESHOLD (default: 20% free)
#     - RESOURCE_DISK_CRITICAL_THRESHOLD (default: 10% free)
check_system_resources() {
	local state_dir="$1"

	# Check if resource monitoring is enabled
	if [[ "${ENABLE_RESOURCE_MONITORING:-1}" -ne 1 ]]; then
		return 0
	fi

	# Get configuration with defaults
	local cpu_threshold="${RESOURCE_CPU_THRESHOLD:-90}"
	local cpu_duration="${RESOURCE_CPU_DURATION:-60}"
	local ram_threshold="${RESOURCE_RAM_THRESHOLD:-90}"
	local ram_duration="${RESOURCE_RAM_DURATION:-60}"
	local disk_warning="${RESOURCE_DISK_WARNING_THRESHOLD:-20}"
	local disk_critical="${RESOURCE_DISK_CRITICAL_THRESHOLD:-10}"

	# Determine path to check (use STATE_DIR or LOGS_DIR if available, fallback to /data)
	local check_path="${STATE_DIR:-/data}"
	if [[ -n "${LOGS_DIR:-}" ]]; then
		check_path="$LOGS_DIR"
	fi

	# Check CPU usage
	local cpu_usage
	if cpu_usage=$(get_cpu_usage 2>/dev/null); then
		if check_resource_constrained "cpu" "$cpu_usage" "$cpu_threshold" "$cpu_duration" "$state_dir"; then
			handle_error "WARNING" "SYSTEM" "CPU usage has been at ${cpu_threshold}%+ (currently ${cpu_usage}%) for ${cpu_duration}s - throttling execution" 0
			return 1
		fi
	fi

	# Check RAM usage
	local ram_usage
	if ram_usage=$(get_memory_usage 2>/dev/null); then
		if check_resource_constrained "ram" "$ram_usage" "$ram_threshold" "$ram_duration" "$state_dir"; then
			handle_error "WARNING" "SYSTEM" "RAM usage has been at ${ram_threshold}%+ (currently ${ram_usage}%) for ${ram_duration}s - throttling execution" 0
			return 1
		fi
	fi

	# Check disk space
	local free_space
	if free_space=$(get_free_disk_space "$check_path" 2>/dev/null); then
		# Log warning at warning threshold (only once, track state to avoid log spam)
		if [[ $free_space -lt $disk_warning ]] && [[ $free_space -ge $disk_critical ]]; then
			local disk_warning_state_file="${state_dir}/resource_disk_warning_logged"
			if [[ ! -f "$disk_warning_state_file" ]]; then
				local filesystem
				filesystem=$(df -P "$check_path" 2>/dev/null | tail -n1 | awk '{print $1}')
				handle_error "WARNING" "SYSTEM" "Free disk space is low: ${free_space}% free on ${filesystem}" 0
				# Mark that we've logged the warning
				atomic_write_file "$disk_warning_state_file" "1" 2>/dev/null || true
			fi
		else
			# Disk space recovered above warning threshold, clear warning state
			local disk_warning_state_file="${state_dir}/resource_disk_warning_logged"
			if [[ -f "$disk_warning_state_file" ]]; then
				rm -f "$disk_warning_state_file" 2>/dev/null || true
			fi
		fi

		# Take action at critical threshold
		if [[ $free_space -lt $disk_critical ]]; then
			local filesystem
			filesystem=$(df -P "$check_path" 2>/dev/null | tail -n1 | awk '{print $1}')
			handle_error "WARNING" "SYSTEM" "Free disk space is critical: ${free_space}% free on ${filesystem}" 0

			# Clear warning state file (so it can warn again if it recovers to warning level)
			local disk_warning_state_file="${state_dir}/resource_disk_warning_logged"
			if [[ -f "$disk_warning_state_file" ]]; then
				rm -f "$disk_warning_state_file" 2>/dev/null || true
			fi

			# Check if we're the cause (log files too large)
			if manage_log_files_on_low_disk "$check_path" "$free_space"; then
				# We managed the log files, check again
				local new_free_space
				if new_free_space=$(get_free_disk_space "$check_path" 2>/dev/null); then
					if [[ $new_free_space -ge $disk_critical ]]; then
						log_message "INFO" "SYSTEM" "Disk space recovered to ${new_free_space}% after log cleanup"
						return 0
					fi
				fi
			fi

			# Still critical - throttle execution
			handle_error "WARNING" "SYSTEM" "Disk space still critical after cleanup - throttling execution" 0
			return 1
		fi
	fi

	return 0
}

# Manage log files when disk space is low
#
# Checks if log files are consuming excessive disk space and takes action:
# - Rotates/truncates log files if they're too large
# - Removes old log files if disk space is still low
# This function helps prevent the monitor from causing disk space issues.
#
# Arguments:
#   $1: Path to check disk space for
#   $2: Current free disk space percentage
#
# Returns:
#   0: Log files were managed (rotated/cleaned)
#   1: Log files were not the issue or couldn't be managed
#
# Side effects:
#   - May rotate/truncate log files
#   - May remove old log files
#   - Logs actions taken
#
# Examples:
#   if manage_log_files_on_low_disk "/data" 8; then
#       echo "Log files were cleaned up"
#   fi
#
# Note:
#   Requires LOG_FILE and LOGS_DIR to be set
#   Requires log_message function to be available
manage_log_files_on_low_disk() {
	local check_path="$1"
	local free_space="$2"

	# Check if we have log file information
	if [[ -z "${LOG_FILE:-}" ]] || [[ -z "${LOGS_DIR:-}" ]]; then
		return 1
	fi

	# Check if log file exists and is large
	if [[ -f "$LOG_FILE" ]]; then
		local log_size_kb
		log_size_kb=$(stat -c%s "$LOG_FILE" 2>/dev/null | awk '{print int($1/1024)}' || echo "0")

		# If log file is larger than 10MB, rotate it
		if [[ -n "$log_size_kb" ]] && [[ "$log_size_kb" -gt 10240 ]]; then
			handle_error "WARNING" "SYSTEM" "Log file is large (${log_size_kb}KB), rotating to free disk space" 0

			# Create rotated log file name
			local rotated_log="${LOG_FILE}.old"

			# Move current log to rotated (if rotated exists, remove it first)
			if [[ -f "$rotated_log" ]]; then
				rm -f "$rotated_log" 2>/dev/null || true
			fi

			# Move current log to rotated
			if mv "$LOG_FILE" "$rotated_log" 2>/dev/null; then
				log_message "INFO" "SYSTEM" "Log file rotated: $LOG_FILE -> $rotated_log"
				# Create new empty log file
				touch "$LOG_FILE" 2>/dev/null || true
			fi
		fi
	fi

	# If disk space is still critical (< 10%), remove old log files
	if [[ $free_space -lt 10 ]]; then
		# Remove rotated log files
		local removed_count=0
		if [[ -d "$LOGS_DIR" ]]; then
			# Find and remove .old log files, oldest first
			# Try GNU find with -printf first, fallback to basic find if not available
			local old_logs
			if old_logs=$(find "$LOGS_DIR" -name "*.old" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | awk '{print $2}' 2>/dev/null); then
				# GNU find with -printf available
				while IFS= read -r old_log; do
					if [[ -n "$old_log" ]] && [[ -f "$old_log" ]]; then
						rm -f "$old_log" 2>/dev/null && ((removed_count++)) || true
					fi
				done <<<"$old_logs"
			else
				# Fallback: basic find (no sorting by age)
				while IFS= read -r old_log; do
					if [[ -n "$old_log" ]] && [[ -f "$old_log" ]]; then
						rm -f "$old_log" 2>/dev/null && ((removed_count++)) || true
					fi
				done < <(find "$LOGS_DIR" -name "*.old" -type f 2>/dev/null)
			fi
		fi

		if [[ $removed_count -gt 0 ]]; then
			log_message "INFO" "SYSTEM" "Removed $removed_count old log file(s) to free disk space"
		fi
	fi

	return 0
}
