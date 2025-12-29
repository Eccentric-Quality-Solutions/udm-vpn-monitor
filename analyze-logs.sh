#!/bin/bash
#
# UDM VPN Monitor Log Analysis Script
# Analyzes VPN monitor logs and generates reports on failure frequency and recovery success rate
# Exports data to CSV for spreadsheet analysis
#
# Version: 0.3.0
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/vpn-monitor.conf"
LOGS_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOGS_DIR}/vpn-monitor.log"

# Default values
OUTPUT_DIR="${SCRIPT_DIR}/reports"
CSV_FILE="${OUTPUT_DIR}/vpn-monitor-analysis.csv"
REPORT_FILE="${OUTPUT_DIR}/vpn-monitor-report.txt"
DATE_RANGE=""
VERBOSE=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print usage information
#
# Displays help text for the script.
#
# Returns:
#   0: Always succeeds
show_usage() {
	cat <<EOF
Usage: $0 [OPTIONS]

UDM VPN Monitor Log Analysis Tool v0.0.1
Analyzes VPN monitor logs and generates reports on failure frequency and recovery success rate.

Options:
  -l, --log-file FILE     Path to log file (default: ${LOG_FILE})
  -o, --output-dir DIR    Output directory for reports (default: ${OUTPUT_DIR})
  -c, --csv FILE          CSV output file (default: ${CSV_FILE})
  -r, --report FILE       Text report file (default: ${REPORT_FILE})
  -d, --date-range RANGE  Analyze logs within date range (format: YYYY-MM-DD:YYYY-MM-DD)
  -v, --verbose           Verbose output
  -h, --help              Show this help message

Examples:
  $0                                    # Analyze default log file
  $0 -l /data/vpn-monitor/logs/vpn-monitor.log
  $0 -d 2025-01-01:2025-01-31          # Analyze January 2025 logs
  $0 -o /tmp/reports -v                # Output to /tmp/reports with verbose output

EOF
}

# Parse command line arguments
#
# Processes command line arguments and sets global variables.
#
# Returns:
#   0: Success
#   1: Error (exits script)
parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-l | --log-file)
			LOG_FILE="$2"
			shift 2
			;;
		-o | --output-dir)
			OUTPUT_DIR="$2"
			shift 2
			;;
		-c | --csv)
			CSV_FILE="$2"
			CSV_FILE_SET=1
			shift 2
			;;
		-r | --report)
			REPORT_FILE="$2"
			REPORT_FILE_SET=1
			shift 2
			;;
		-d | --date-range)
			DATE_RANGE="$2"
			shift 2
			;;
		-v | --verbose)
			VERBOSE=1
			shift
			;;
		-h | --help)
			show_usage
			exit 0
			;;
		*)
			echo "ERROR: Unknown option: $1" >&2
			show_usage
			exit 1
			;;
		esac
	done
}

# Extract peer IP from log message
#
# Extracts peer IP address from log messages that contain peer IP information.
#
# Arguments:
#   $1: Log message
#
# Returns:
#   0: Success
#   1: No peer IP found
#
# Output:
#   Prints peer IP to stdout if found
extract_peer_ip() {
	local message="$1"
	# Pattern: "for 203.0.113.1" or "for 198.51.100.1"
	if [[ $message =~ for\ ([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}) ]]; then
		echo "${BASH_REMATCH[1]}"
		return 0
	fi
	# Pattern: IPv6 addresses (simplified)
	if [[ $message =~ for\ ([0-9a-fA-F:]+) ]]; then
		echo "${BASH_REMATCH[1]}"
		return 0
	fi
	return 1
}

# Extract failure count from log message
#
# Extracts failure count number from log messages.
#
# Arguments:
#   $1: Log message
#
# Returns:
#   0: Success
#   1: No failure count found
#
# Output:
#   Prints failure count to stdout if found
extract_failure_count() {
	local message="$1"
	# Pattern: "failure count: 3" or "after 5 failures"
	if [[ $message =~ failure\ count:\ ([0-9]+) ]]; then
		echo "${BASH_REMATCH[1]}"
		return 0
	fi
	if [[ $message =~ after\ ([0-9]+)\ failures ]]; then
		echo "${BASH_REMATCH[1]}"
		return 0
	fi
	return 1
}

# Check if date is within range
#
# Checks if a date string is within the specified date range.
#
# Arguments:
#   $1: Date string (YYYY-MM-DD)
#   $2: Start date (YYYY-MM-DD) or empty
#   $3: End date (YYYY-MM-DD) or empty
#
# Returns:
#   0: Date is within range (or no range specified)
#   1: Date is outside range
date_in_range() {
	local date_str="$1"
	local start_date="${2:-}"
	local end_date="${3:-}"

	# No date range specified - include all dates
	if [[ -z "$start_date" ]] && [[ -z "$end_date" ]]; then
		return 0
	fi

	# Extract date part (YYYY-MM-DD) from timestamp
	local log_date="${date_str%% *}"

	# Compare dates (simple string comparison works for YYYY-MM-DD format)
	if [[ -n "$start_date" ]] && [[ "$log_date" < "$start_date" ]]; then
		return 1
	fi
	if [[ -n "$end_date" ]] && [[ "$log_date" > "$end_date" ]]; then
		return 1
	fi

	return 0
}

# Parse date range
#
# Parses date range string into start and end dates.
#
# Arguments:
#   $1: Date range string (format: YYYY-MM-DD:YYYY-MM-DD)
#
# Returns:
#   0: Success
#   1: Invalid format
#
# Output:
#   Sets global variables DATE_START and DATE_END
parse_date_range() {
	local range="$1"
	if [[ $range =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}):([0-9]{4}-[0-9]{2}-[0-9]{2})$ ]]; then
		DATE_START="${BASH_REMATCH[1]}"
		DATE_END="${BASH_REMATCH[2]}"
		return 0
	elif [[ $range =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})$ ]]; then
		DATE_START="${BASH_REMATCH[1]}"
		DATE_END="${BASH_REMATCH[1]}"
		return 0
	else
		echo "ERROR: Invalid date range format: $range" >&2
		echo "Expected format: YYYY-MM-DD:YYYY-MM-DD or YYYY-MM-DD" >&2
		return 1
	fi
}

# Analyze log file
#
# Parses log file line by line and extracts failure/recovery statistics.
# Categorizes log entries into failures, recoveries, and tier actions.
# Filters by date range if DATE_START and DATE_END are set.
# Extracts peer IPs and failure counts from log messages.
#
# Arguments:
#   $1: Log file path to analyze
#
# Returns:
#   0: Success (log file parsed successfully)
#   1: Error (file not found, not readable, or parsing error)
#
# Side effects:
#   Sets global arrays with parsed data:
#   - FAILURES: Array of failure events (format: "timestamp|peer_ip|failure_count|level")
#   - RECOVERIES: Array of recovery events (format: "timestamp|peer_ip|recovery_count|level")
#   - TIER1_ACTIONS: Array of Tier 1 actions (format: "timestamp|peer_ip|level")
#   - TIER2_ACTIONS: Array of Tier 2 action starts (format: "timestamp|peer_ip|level")
#   - TIER2_COMPLETED: Array of Tier 2 completions (format: "timestamp|peer_ip|level")
#   - TIER3_ACTIONS: Array of Tier 3 action starts (format: "timestamp|peer_ip|level")
#   - TIER3_COMPLETED: Array of Tier 3 completions (format: "timestamp|peer_ip|level")
#
# Examples:
#   if analyze_logs "$log_file"; then
#       echo "Found ${#FAILURES[@]} failures"
#   fi
#
# Note:
#   Requires extract_peer_ip, extract_failure_count, date_in_range functions
#   Log format expected: "[YYYY-MM-DD HH:MM:SS] [LEVEL] message"
#   Filters by date range if DATE_START and DATE_END are set
analyze_logs() {
	local log_file="$1"
	local date_start="${DATE_START:-}"
	local date_end="${DATE_END:-}"

	# Initialize arrays
	FAILURES=()
	RECOVERIES=()
	TIER1_ACTIONS=()
	TIER2_ACTIONS=()
	TIER2_COMPLETED=()
	TIER3_ACTIONS=()
	TIER3_COMPLETED=()

	if [[ ! -f "$log_file" ]]; then
		echo "ERROR: Log file not found: $log_file" >&2
		return 1
	fi

	if [[ ! -r "$log_file" ]]; then
		echo "ERROR: Log file not readable: $log_file" >&2
		return 1
	fi

	[[ $VERBOSE -eq 1 ]] && echo "Analyzing log file: $log_file" >&2

	# Parse log file line by line
	while IFS= read -r line || [[ -n "$line" ]]; do
		# Skip empty lines
		[[ -z "$line" ]] && continue

		# Parse log entry: [YYYY-MM-DD HH:MM:SS] [LEVEL] message
		if [[ ! $line =~ ^\[([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2})\]\ \[([A-Z]+)\]\ (.+)$ ]]; then
			continue
		fi

		local timestamp="${BASH_REMATCH[1]}"
		local level="${BASH_REMATCH[2]}"
		local message="${BASH_REMATCH[3]}"

		# Check date range
		if ! date_in_range "$timestamp" "$date_start" "$date_end"; then
			continue
		fi

		# Extract peer IP if present
		local peer_ip=""
		if peer_ip=$(extract_peer_ip "$message"); then
			:
		else
			peer_ip="unknown"
		fi

		# Categorize log entries
		case "$message" in
		*"VPN check failed"* | *"check failed"*)
			local failure_count=0
			if failure_count=$(extract_failure_count "$message"); then
				:
			fi
			FAILURES+=("${timestamp}|${peer_ip}|${failure_count}|${level}")
			;;
		*"VPN recovered"* | *"recovered"*)
			local recovery_count=0
			if recovery_count=$(extract_failure_count "$message"); then
				:
			fi
			RECOVERIES+=("${timestamp}|${peer_ip}|${recovery_count}|${level}")
			;;
		*"Tier 1:"*)
			TIER1_ACTIONS+=("${timestamp}|${peer_ip}|${level}")
			;;
		*"Tier 2:"*"surgical"* | *"Tier 2:"*"cleanup"*)
			TIER2_ACTIONS+=("${timestamp}|${peer_ip}|${level}")
			;;
		*"Surgical cleanup completed"*)
			TIER2_COMPLETED+=("${timestamp}|${peer_ip}|${level}")
			;;
		*"Tier 3:"*"restart"*)
			TIER3_ACTIONS+=("${timestamp}|${peer_ip}|${level}")
			;;
		*"Full IPsec restart completed"*)
			TIER3_COMPLETED+=("${timestamp}|${peer_ip}|${level}")
			;;
		esac
	done <"$log_file"

	[[ $VERBOSE -eq 1 ]] && echo "Found ${#FAILURES[@]} failures, ${#RECOVERIES[@]} recoveries" >&2

	return 0
}

# Calculate floating point division with fallbacks
#
# Performs floating point division using awk if available, falling back to bash
# integer math.
#
# Arguments:
#   $1: Numerator
#   $2: Denominator
#   $3: Scale (decimal places, default: 2)
#
# Returns:
#   0: Success
#
# Output:
#   Prints result to stdout
#
# Examples:
#   result=$(calculate_float_division 10 3 2)  # Returns "3.33"
#   result=$(calculate_float_division 5 2)      # Returns "2.50" (default scale 2)
calculate_float_division() {
	local numerator="$1"
	local denominator="$2"
	local scale="${3:-2}"
	local result=""

	if [[ $denominator -eq 0 ]]; then
		echo "0"
		return 0
	fi

	# Try awk first (available on UDM systems)
	if command -v awk >/dev/null 2>&1; then
		result=$(awk "BEGIN {printf \"%.${scale}f\", $numerator / $denominator}" 2>/dev/null)
	fi

	# Fallback to bash integer math if awk failed or not available
	# Only fallback if result is empty (not if it's "0.00" which is a valid result)
	if [[ -z "$result" ]]; then
		local int_part=$((numerator / denominator))
		local remainder=$((numerator % denominator))
		# Calculate decimal part (multiply remainder by 10^scale, divide by denominator)
		if [[ $scale -eq 0 ]]; then
			# No decimal places needed
			result="${int_part}"
		else
			local multiplier=1
			local i
			for ((i = 0; i < scale; i++)); do
				multiplier=$((multiplier * 10))
			done
			local decimal_part=$(((remainder * multiplier) / denominator))
			# Pad decimal part with zeros if needed
			local decimal_str="${decimal_part}"
			while [[ ${#decimal_str} -lt $scale ]]; do
				decimal_str="0${decimal_str}"
			done
			result="${int_part}.${decimal_str}"
		fi
	fi

	# Ensure we have a valid value
	[[ -z "$result" ]] && result="0"
	echo "$result"
}

# Calculate statistics
#
# Calculates failure frequency and recovery success rate from parsed data.
#
# Returns:
#   0: Success
#
# Side effects:
#   Sets global variables with statistics
calculate_statistics() {
	local total_failures=${#FAILURES[@]}
	local total_recoveries=${#RECOVERIES[@]}
	local total_tier1=${#TIER1_ACTIONS[@]}
	local total_tier2=${#TIER2_ACTIONS[@]}
	local total_tier2_completed=${#TIER2_COMPLETED[@]}
	local total_tier3=${#TIER3_ACTIONS[@]}
	local total_tier3_completed=${#TIER3_COMPLETED[@]}

	# Calculate date range from log data
	# Find the earliest and latest timestamps across all events
	local first_date=""
	local last_date=""

	# Collect all timestamps and find min/max
	local all_timestamps=()
	local i
	for i in "${!FAILURES[@]}"; do
		local timestamp="${FAILURES[$i]%%|*}"
		all_timestamps+=("$timestamp")
	done
	for i in "${!RECOVERIES[@]}"; do
		local timestamp="${RECOVERIES[$i]%%|*}"
		all_timestamps+=("$timestamp")
	done

	# Find earliest and latest timestamps
	if [[ ${#all_timestamps[@]} -gt 0 ]]; then
		# Sort timestamps to find actual first and last
		IFS=$'\n' sorted_timestamps=($(printf '%s\n' "${all_timestamps[@]}" | sort))
		unset IFS
		first_date="${sorted_timestamps[0]}"
		last_date="${sorted_timestamps[-1]}"
	fi

	# Calculate time span in days
	local days=0
	if [[ -n "$first_date" ]] && [[ -n "$last_date" ]]; then
		# Extract date part (YYYY-MM-DD) from timestamp
		local start_date="${first_date%% *}"
		local end_date="${last_date%% *}"

		# Convert dates to seconds since epoch and calculate difference
		local start_sec=$(date -d "$start_date" +%s 2>/dev/null || echo "0")
		local end_sec=$(date -d "$end_date" +%s 2>/dev/null || echo "0")

		if [[ $start_sec -gt 0 ]] && [[ $end_sec -gt 0 ]]; then
			local diff_sec=$((end_sec - start_sec))
			# Calculate days (always at least 1 if there's any difference)
			if [[ $diff_sec -ge 0 ]]; then
				days=$((diff_sec / 86400))
				# Round up if there's any remainder (so even same-day shows as 1 day)
				if [[ $((diff_sec % 86400)) -gt 0 ]] || [[ $days -eq 0 ]]; then
					days=$((days + 1))
				fi
			else
				# Negative difference shouldn't happen, but handle it
				days=1
			fi
			# Minimum 1 day
			[[ $days -lt 1 ]] && days=1
		else
			# Date parsing failed, default to 1 day
			days=1
		fi
	else
		# No timestamps found, default to 1 day
		days=1
	fi

	# Calculate failure frequency (per day)
	FAILURES_PER_DAY=0
	if [[ $days -gt 0 ]] && [[ $total_failures -gt 0 ]]; then
		FAILURES_PER_DAY=$(calculate_float_division "$total_failures" "$days" 2)
	fi

	# Calculate recovery success rate
	RECOVERY_SUCCESS_RATE=0
	if [[ $total_failures -gt 0 ]] && [[ $total_recoveries -gt 0 ]]; then
		RECOVERY_SUCCESS_RATE=$(calculate_float_division $((total_recoveries * 100)) "$total_failures" 2)
	fi

	# Calculate tier 2 success rate
	TIER2_SUCCESS_RATE=0
	if [[ $total_tier2 -gt 0 ]] && [[ $total_tier2_completed -gt 0 ]]; then
		TIER2_SUCCESS_RATE=$(calculate_float_division $((total_tier2_completed * 100)) "$total_tier2" 2)
	fi

	# Calculate tier 3 success rate
	TIER3_SUCCESS_RATE=0
	if [[ $total_tier3 -gt 0 ]] && [[ $total_tier3_completed -gt 0 ]]; then
		TIER3_SUCCESS_RATE=$(calculate_float_division $((total_tier3_completed * 100)) "$total_tier3" 2)
	fi

	STATS_FIRST_DATE="$first_date"
	STATS_LAST_DATE="$last_date"
	STATS_DAYS="$days"
	STATS_TOTAL_FAILURES="$total_failures"
	STATS_TOTAL_RECOVERIES="$total_recoveries"
	STATS_TOTAL_TIER1="$total_tier1"
	STATS_TOTAL_TIER2="$total_tier2"
	STATS_TOTAL_TIER2_COMPLETED="$total_tier2_completed"
	STATS_TOTAL_TIER3="$total_tier3"
	STATS_TOTAL_TIER3_COMPLETED="$total_tier3_completed"
}

# Generate text report
#
# Generates a human-readable text report with statistics.
#
# Arguments:
#   $1: Output file path
#
# Returns:
#   0: Success
generate_text_report() {
	local report_file="$1"

	{
		echo "=========================================="
		echo "UDM VPN Monitor Log Analysis Report"
		echo "=========================================="
		echo ""
		echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
		echo "Log File: $LOG_FILE"
		if [[ -n "${DATE_START:-}" ]]; then
			echo "Date Range: ${DATE_START} to ${DATE_END:-${DATE_START}}"
		fi
		echo ""
		echo "------------------------------------------"
		echo "Summary Statistics"
		echo "------------------------------------------"
		echo "Analysis Period:"
		echo "  First Event: ${STATS_FIRST_DATE:-N/A}"
		echo "  Last Event:  ${STATS_LAST_DATE:-N/A}"
		echo "  Days Analyzed: ${STATS_DAYS:-0}"
		echo ""
		echo "Failures:"
		echo "  Total Failures: ${STATS_TOTAL_FAILURES:-0}"
		echo "  Failures per Day: ${FAILURES_PER_DAY:-0}"
		echo ""
		echo "Recoveries:"
		echo "  Total Recoveries: ${STATS_TOTAL_RECOVERIES:-0}"
		echo "  Recovery Success Rate: ${RECOVERY_SUCCESS_RATE:-0}%"
		echo ""
		echo "Tier Actions:"
		echo "  Tier 1 (Logging): ${STATS_TOTAL_TIER1:-0}"
		echo "  Tier 2 (Surgical Cleanup):"
		echo "    Attempted: ${STATS_TOTAL_TIER2:-0}"
		echo "    Completed: ${STATS_TOTAL_TIER2_COMPLETED:-0}"
		echo "    Success Rate: ${TIER2_SUCCESS_RATE:-0}%"
		echo "  Tier 3 (Full Restart):"
		echo "    Attempted: ${STATS_TOTAL_TIER3:-0}"
		echo "    Completed: ${STATS_TOTAL_TIER3_COMPLETED:-0}"
		echo "    Success Rate: ${TIER3_SUCCESS_RATE:-0}%"
		echo ""
		echo "------------------------------------------"
		echo "Detailed Event Timeline"
		echo "------------------------------------------"
		echo ""

		# Combine and sort all events by timestamp
		local all_events=()
		local i
		for i in "${!FAILURES[@]}"; do
			all_events+=("FAILURE|${FAILURES[$i]}")
		done
		for i in "${!RECOVERIES[@]}"; do
			all_events+=("RECOVERY|${RECOVERIES[$i]}")
		done
		for i in "${!TIER1_ACTIONS[@]}"; do
			all_events+=("TIER1|${TIER1_ACTIONS[$i]}")
		done
		for i in "${!TIER2_ACTIONS[@]}"; do
			all_events+=("TIER2_START|${TIER2_ACTIONS[$i]}")
		done
		for i in "${!TIER2_COMPLETED[@]}"; do
			all_events+=("TIER2_COMPLETE|${TIER2_COMPLETED[$i]}")
		done
		for i in "${!TIER3_ACTIONS[@]}"; do
			all_events+=("TIER3_START|${TIER3_ACTIONS[$i]}")
		done
		for i in "${!TIER3_COMPLETED[@]}"; do
			all_events+=("TIER3_COMPLETE|${TIER3_COMPLETED[$i]}")
		done

		# Sort events by timestamp (first field after event type)
		IFS=$'\n' sorted_events=($(printf '%s\n' "${all_events[@]}" | sort -t'|' -k2))
		unset IFS

		# Display events (limit to last 50 for readability)
		local display_count=${#sorted_events[@]}
		[[ $display_count -gt 50 ]] && display_count=50

		local start_idx=0
		[[ ${#sorted_events[@]} -gt 50 ]] && start_idx=$((${#sorted_events[@]} - 50))

		local idx
		for ((idx = $start_idx; idx < ${#sorted_events[@]}; idx++)); do
			local event="${sorted_events[$idx]}"
			local event_type="${event%%|*}"
			local event_data="${event#*|}"
			local timestamp="${event_data%%|*}"
			local peer_ip="${event_data#*|}"
			peer_ip="${peer_ip%%|*}"

			case "$event_type" in
			FAILURE)
				local failure_count="${event_data##*|}"
				failure_count="${failure_count%%|*}"
				echo "[$timestamp] FAILURE: Peer $peer_ip (failure count: $failure_count)"
				;;
			RECOVERY)
				local recovery_count="${event_data##*|}"
				recovery_count="${recovery_count%%|*}"
				echo "[$timestamp] RECOVERY: Peer $peer_ip (recovered after $recovery_count failures)"
				;;
			TIER1)
				echo "[$timestamp] TIER 1: Logging action for peer $peer_ip"
				;;
			TIER2_START)
				echo "[$timestamp] TIER 2: Surgical cleanup started for peer $peer_ip"
				;;
			TIER2_COMPLETE)
				echo "[$timestamp] TIER 2: Surgical cleanup completed for peer $peer_ip"
				;;
			TIER3_START)
				echo "[$timestamp] TIER 3: Full restart started for peer $peer_ip"
				;;
			TIER3_COMPLETE)
				echo "[$timestamp] TIER 3: Full restart completed for peer $peer_ip"
				;;
			esac
		done

		if [[ ${#sorted_events[@]} -gt 50 ]]; then
			echo ""
			echo "... (showing last 50 of ${#sorted_events[@]} events)"
		fi

		echo ""
		echo "=========================================="
	} >"$report_file"

	return 0
}

# Generate CSV export
#
# Generates CSV file with detailed event data for spreadsheet analysis.
#
# Arguments:
#   $1: Output CSV file path
#
# Returns:
#   0: Success
generate_csv() {
	local csv_file="$1"

	# Create CSV header
	{
		echo "Timestamp,Event Type,Peer IP,Failure Count,Recovery Count,Level"

		# Export failures
		local i
		for i in "${!FAILURES[@]}"; do
			local failure="${FAILURES[$i]}"
			IFS='|' read -r timestamp peer_ip failure_count level <<<"$failure"
			echo "$timestamp,FAILURE,$peer_ip,$failure_count,,$level"
		done

		# Export recoveries
		for i in "${!RECOVERIES[@]}"; do
			local recovery="${RECOVERIES[$i]}"
			IFS='|' read -r timestamp peer_ip recovery_count level <<<"$recovery"
			echo "$timestamp,RECOVERY,$peer_ip,,$recovery_count,$level"
		done

		# Export Tier 1 actions
		for i in "${!TIER1_ACTIONS[@]}"; do
			local tier1="${TIER1_ACTIONS[$i]}"
			IFS='|' read -r timestamp peer_ip level <<<"$tier1"
			echo "$timestamp,TIER1_ACTION,$peer_ip,,,$level"
		done

		# Export Tier 2 actions
		for i in "${!TIER2_ACTIONS[@]}"; do
			local tier2="${TIER2_ACTIONS[$i]}"
			IFS='|' read -r timestamp peer_ip level <<<"$tier2"
			echo "$timestamp,TIER2_START,$peer_ip,,,$level"
		done

		for i in "${!TIER2_COMPLETED[@]}"; do
			local tier2_complete="${TIER2_COMPLETED[$i]}"
			IFS='|' read -r timestamp peer_ip level <<<"$tier2_complete"
			echo "$timestamp,TIER2_COMPLETE,$peer_ip,,,$level"
		done

		# Export Tier 3 actions
		for i in "${!TIER3_ACTIONS[@]}"; do
			local tier3="${TIER3_ACTIONS[$i]}"
			IFS='|' read -r timestamp peer_ip level <<<"$tier3"
			echo "$timestamp,TIER3_START,$peer_ip,,,$level"
		done

		for i in "${!TIER3_COMPLETED[@]}"; do
			local tier3_complete="${TIER3_COMPLETED[$i]}"
			IFS='|' read -r timestamp peer_ip level <<<"$tier3_complete"
			echo "$timestamp,TIER3_COMPLETE,$peer_ip,,,$level"
		done
	} >"$csv_file"

	return 0
}

# Main execution
main() {
	# Parse command line arguments
	parse_args "$@"

	# Update REPORT_FILE and CSV_FILE to use OUTPUT_DIR if they weren't explicitly set
	# This ensures that when -o changes OUTPUT_DIR, the default report/csv paths are updated
	if [[ -z "${REPORT_FILE_SET:-}" ]]; then
		REPORT_FILE="${OUTPUT_DIR}/vpn-monitor-report.txt"
	fi
	if [[ -z "${CSV_FILE_SET:-}" ]]; then
		CSV_FILE="${OUTPUT_DIR}/vpn-monitor-analysis.csv"
	fi

	# Parse date range if specified
	if [[ -n "$DATE_RANGE" ]]; then
		if ! parse_date_range "$DATE_RANGE"; then
			exit 1
		fi
	fi

	# Ensure output directory exists
	mkdir -p "$OUTPUT_DIR" || {
		echo "ERROR: Cannot create output directory: $OUTPUT_DIR" >&2
		exit 1
	}

	# Analyze logs
	if ! analyze_logs "$LOG_FILE"; then
		exit 1
	fi

	# Calculate statistics
	calculate_statistics

	# Generate reports
	[[ $VERBOSE -eq 1 ]] && echo "Generating text report: $REPORT_FILE" >&2
	generate_text_report "$REPORT_FILE"

	[[ $VERBOSE -eq 1 ]] && echo "Generating CSV export: $CSV_FILE" >&2
	generate_csv "$CSV_FILE"

	# Display summary
	echo ""
	echo "=========================================="
	echo "Analysis Complete"
	echo "=========================================="
	echo "Text Report: $REPORT_FILE"
	echo "CSV Export:  $CSV_FILE"
	echo ""
	echo "Summary:"
	echo "  Total Failures: ${STATS_TOTAL_FAILURES:-0}"
	echo "  Total Recoveries: ${STATS_TOTAL_RECOVERIES:-0}"
	echo "  Recovery Success Rate: ${RECOVERY_SUCCESS_RATE:-0}%"
	echo "  Failures per Day: ${FAILURES_PER_DAY:-0}"
	echo ""

	return 0
}

# Run main function
main "$@"
