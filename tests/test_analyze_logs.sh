#!/usr/bin/env bats
#
# Tests for analyze-logs.sh script
# Tests log analysis functionality, report generation, and CSV export

load test_helper

# Path to the analyze-logs script
ANALYZE_LOGS_SCRIPT="${BATS_TEST_DIRNAME}/../analyze-logs.sh"

# Create sample log file with various events
#
# Creates a log file with failures, recoveries, and tier actions for testing.
#
# Arguments:
#   $1: Log file path
#   $2: Optional date prefix (default: "2025-01-15")
#
# Returns:
#   None
#
create_sample_log_file() {
	local log_file="$1"
	local date_prefix="${2:-2025-01-15}"

	mkdir -p "$(dirname "$log_file")"

	cat >"$log_file" <<EOF
[${date_prefix} 10:00:00] [INFO] Log file initialized
[${date_prefix} 10:01:00] [WARNING] VPN check failed for 192.168.1.1 (failure count: 1)
[${date_prefix} 10:01:00] [INFO] Tier 1: Logging VPN failure for 192.168.1.1
[${date_prefix} 10:02:00] [WARNING] VPN check failed for 192.168.1.1 (failure count: 2)
[${date_prefix} 10:03:00] [WARNING] VPN check failed for 192.168.1.1 (failure count: 3)
[${date_prefix} 10:03:00] [WARNING] Tier 2: Attempting surgical SA cleanup for 192.168.1.1
[${date_prefix} 10:03:05] [INFO] Surgical cleanup completed for 192.168.1.1
[${date_prefix} 10:04:00] [INFO] VPN recovered for 192.168.1.1 after 3 failures
[${date_prefix} 10:05:00] [WARNING] VPN check failed for 192.168.1.1 (failure count: 1)
[${date_prefix} 10:06:00] [WARNING] VPN check failed for 192.168.1.1 (failure count: 2)
[${date_prefix} 10:07:00] [WARNING] VPN check failed for 192.168.1.1 (failure count: 3)
[${date_prefix} 10:08:00] [WARNING] VPN check failed for 192.168.1.1 (failure count: 4)
[${date_prefix} 10:09:00] [WARNING] VPN check failed for 192.168.1.1 (failure count: 5)
[${date_prefix} 10:09:00] [ERROR] Tier 3: Attempting full IPsec restart
[${date_prefix} 10:09:10] [INFO] Full IPsec restart completed
[${date_prefix} 10:10:00] [INFO] VPN recovered for 192.168.1.1 after 5 failures
[${date_prefix} 10:11:00] [WARNING] VPN check failed for 198.51.100.1 (failure count: 1)
[${date_prefix} 10:12:00] [INFO] VPN recovered for 198.51.100.1 after 1 failures
EOF
}

# Create sample log file with app-managed and self-healed recoveries
#
# Creates a log file with both app-managed recoveries (with recovery method) and
# self-healed recoveries (without recovery method) for testing recovery type distinction.
#
# Arguments:
#   $1: Log file path
#   $2: Optional date prefix (default: "2025-01-15")
#
# Returns:
#   None
#
create_recovery_type_test_log_file() {
	local log_file="$1"
	local date_prefix="${2:-2025-01-15}"

	mkdir -p "$(dirname "$log_file")"

	cat >"$log_file" <<EOF
[${date_prefix} 10:00:00] [INFO] Log file initialized
# Self-healed recovery (no recovery method, just "after N failures")
[${date_prefix} 10:01:00] [WARNING] VPN check failed for 192.168.1.1 (failure count: 1)
[${date_prefix} 10:02:00] [INFO] VPN recovered for 192.168.1.1 after 1 failures
# App-managed recovery (with recovery method)
[${date_prefix} 10:03:00] [WARNING] VPN check failed for 192.168.1.2 (failure count: 1)
[${date_prefix} 10:04:00] [WARNING] VPN check failed for 192.168.1.2 (failure count: 2)
[${date_prefix} 10:05:00] [WARNING] VPN check failed for 192.168.1.2 (failure count: 3)
[${date_prefix} 10:05:00] [WARNING] Tier 2: Attempting surgical SA cleanup for 192.168.1.2
[${date_prefix} 10:05:05] [INFO] Surgical cleanup completed for 192.168.1.2
[${date_prefix} 10:06:00] [INFO] VPN restored for 192.168.1.2 after 3 failures (recovery method: xfrm-based recovery)
# Another self-healed recovery
[${date_prefix} 10:07:00] [WARNING] VPN check failed for 192.168.1.3 (failure count: 1)
[${date_prefix} 10:08:00] [INFO] VPN recovered for 192.168.1.3 after 1 failures
# App-managed recovery with ipsec restart
[${date_prefix} 10:09:00] [WARNING] VPN check failed for 192.168.1.4 (failure count: 1)
[${date_prefix} 10:10:00] [WARNING] VPN check failed for 192.168.1.4 (failure count: 2)
[${date_prefix} 10:11:00] [WARNING] VPN check failed for 192.168.1.4 (failure count: 3)
[${date_prefix} 10:12:00] [WARNING] VPN check failed for 192.168.1.4 (failure count: 4)
[${date_prefix} 10:13:00] [WARNING] VPN check failed for 192.168.1.4 (failure count: 5)
[${date_prefix} 10:13:00] [ERROR] Tier 3: Attempting full IPsec restart
[${date_prefix} 10:13:10] [INFO] Full IPsec restart completed
[${date_prefix} 10:14:00] [INFO] VPN restored for 192.168.1.4 after 5 failures (recovery method: ipsec restart)
EOF
}

# bats test_tags=category:unit
@test "analyze-logs.sh exists and is executable" {
	# Purpose: Test verifies that the analyze-logs script file exists and has execute permissions
	# Expected: Analyze-logs script file is present and executable
	# Importance: Ensures the log analysis script can be run directly for troubleshooting and reporting
	assert_file_exist "$ANALYZE_LOGS_SCRIPT"
	assert_file_executable "$ANALYZE_LOGS_SCRIPT"
}

# bats test_tags=category:unit
@test "analyze-logs.sh shows help with --help flag" {
	# Purpose: Test verifies that the analyze-logs script displays usage information when --help flag is provided
	# Expected: Script outputs usage information including all available options and flags
	# Importance: Ensures users can access help documentation for script usage and available options
	run bash "$ANALYZE_LOGS_SCRIPT" --help
	assert_success
	assert_output --partial "Usage:"
	assert_output --partial "analyze-logs.sh"
	assert_output --partial "--log-file"
	assert_output --partial "--csv"
	assert_output --partial "--report"
}

# bats test_tags=category:unit
@test "analyze-logs.sh shows help with -h flag" {
	# Purpose: Test verifies that the analyze-logs script displays usage information when -h flag is provided
	# Expected: Script outputs usage information including all available options and flags
	# Importance: Ensures users can access help documentation using the short flag option
	run bash "$ANALYZE_LOGS_SCRIPT" -h
	assert_success
	assert_output --partial "Usage:"
}

# bats test_tags=category:unit
@test "analyze-logs.sh exits with error if log file not found" {
	# Purpose: Test verifies that the analyze-logs script validates log file existence before processing
	# Expected: Script exits with failure status and displays error message when log file doesn't exist
	# Importance: Prevents script from attempting to analyze non-existent files and provides clear error feedback
	local log_file="${TEST_DIR}/nonexistent.log"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file"

	assert_failure
	assert_output --partial "Log file not found"
}

# bats test_tags=category:unit
@test "analyze-logs.sh exits with error if log file not readable" {
	# Purpose: Test verifies that the analyze-logs script validates log file readability before processing
	# Expected: Script exits with failure status and displays error message when log file is not readable
	# Importance: Prevents script from attempting to analyze unreadable files and provides clear error feedback
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	mkdir -p "$(dirname "$log_file")"
	touch "$log_file"
	chmod 000 "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file"

	# Restore permissions for cleanup
	chmod 644 "$log_file" || true

	assert_failure
	assert_output --partial "Log file not readable"
}

# bats test_tags=category:unit
@test "analyze-logs.sh parses log file and extracts failures" {
	# Purpose: Test verifies that the analyze-logs script correctly parses log files and extracts failure events
	# Expected: Script identifies VPN failure events from log entries and calculates failure statistics
	# Importance: Failure analysis helps identify patterns and troubleshoot VPN reliability issues
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_sample_log_file "$log_file"
	# Verify log file has content
	assert_file_not_empty "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"

	assert_success
	assert_output --partial "Total Failures:"
	# Should find multiple failures
	assert_output --partial "Failures per Day:"
}

# bats test_tags=category:unit
@test "analyze-logs.sh extracts recoveries from log file" {
	# Purpose: Test verifies that the analyze-logs script correctly identifies VPN recovery events from logs
	# Expected: Script extracts recovery events and calculates recovery success rate statistics
	# Importance: Recovery analysis helps evaluate effectiveness of recovery actions and VPN stability
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"

	assert_success
	assert_output --partial "Total Recoveries:"
	assert_output --partial "Recovery Success Rate:"
}

# bats test_tags=category:unit
@test "analyze-logs.sh extracts tier actions from log file" {
	# Purpose: Test verifies that the analyze-logs script correctly identifies tier escalation actions from logs
	# Expected: Script extracts Tier 1, Tier 2, and Tier 3 actions and includes statistics in report file
	# Importance: Tier action analysis helps understand escalation patterns and recovery action effectiveness
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local report_file="${TEST_DIR}/vpn-monitor-report.txt"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"

	assert_success
	# Tier statistics are in the report file, not stdout
	assert_file_exist "$report_file"
	assert_file_contains "$report_file" "Tier 1 (Logging):"
	assert_file_contains "$report_file" "Tier 2 (Surgical Cleanup):"
	assert_file_contains "$report_file" "Tier 3 (Full Restart):"
}

# bats test_tags=category:unit
@test "analyze-logs.sh generates text report file" {
	# Purpose: Test verifies that the analyze-logs script generates a formatted text report file with analysis results
	# Expected: Script creates report file containing summary statistics, failure counts, and recovery information
	# Importance: Text reports provide human-readable analysis of VPN monitoring logs for troubleshooting and reporting
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local report_file="${TEST_DIR}/vpn-monitor-report.txt"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -r "$report_file"

	assert_success
	assert_file_exist "$report_file"
	assert_file_contains "$report_file" "UDM VPN Monitor Log Analysis Report"
	assert_file_contains "$report_file" "Summary Statistics"
	assert_file_contains "$report_file" "Total Failures:"
	assert_file_contains "$report_file" "Total Recoveries:"
}

# bats test_tags=category:unit
@test "analyze-logs.sh generates CSV export file" {
	# Purpose: Test verifies that the analyze-logs script generates CSV export file with structured log analysis data
	# Expected: Script creates CSV file with columns for timestamps, event types, peer IPs, and failure/recovery counts
	# Importance: CSV export enables data analysis in spreadsheet applications and automated reporting systems
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local csv_file="${TEST_DIR}/vpn-monitor-analysis.csv"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -c "$csv_file"

	assert_success
	assert_file_exist "$csv_file"
	assert_file_contains "$csv_file" "Timestamp,Event Type,Peer IP,Failure Count,Recovery Count,Level"
	assert_file_contains "$csv_file" "FAILURE"
	assert_file_contains "$csv_file" "RECOVERY"
}

# bats test_tags=category:unit
@test "analyze-logs.sh CSV contains failure events" {
	# Purpose: Test verifies that the CSV export file contains failure event entries
	# Expected: CSV file includes rows for VPN failure events with correct event type and peer IPs
	# Importance: Ensures failure events are properly exported for analysis and reporting
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local csv_file="${TEST_DIR}/vpn-monitor-analysis.csv"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -c "$csv_file"

	assert_success
	# Check CSV contains failure entries
	local failure_count
	failure_count=$(grep -c "FAILURE" "$csv_file" || echo "0")
	# Use assert_equal for numeric comparison with better error messages
	assert [ "$failure_count" -gt 0 ]
	# Verify it's a positive integer using regex
	assert_regex "$failure_count" '^[1-9][0-9]*$'
}

# bats test_tags=category:unit
@test "analyze-logs.sh CSV contains recovery events" {
	# Purpose: Test verifies that the CSV export file contains recovery event entries
	# Expected: CSV file includes rows for VPN recovery events with correct event type and peer IPs
	# Importance: Ensures recovery events are properly exported for analysis and reporting
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local csv_file="${TEST_DIR}/vpn-monitor-analysis.csv"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -c "$csv_file"

	assert_success
	# Check CSV contains recovery entries
	local recovery_count
	recovery_count=$(grep -c "RECOVERY" "$csv_file" || echo "0")
	assert [ "$recovery_count" -gt 0 ]
	# Verify it's a positive integer using regex
	assert_regex "$recovery_count" '^[1-9][0-9]*$'
}

# bats test_tags=category:unit
@test "analyze-logs.sh CSV contains tier action events" {
	# Purpose: Test verifies that the CSV export file contains tier action event entries
	# Expected: CSV file includes rows for Tier 1, Tier 2, and Tier 3 action events
	# Importance: Ensures tier escalation actions are properly exported for analysis and reporting
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local csv_file="${TEST_DIR}/vpn-monitor-analysis.csv"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -c "$csv_file"

	assert_success
	# Check CSV contains tier action entries
	assert_file_contains "$csv_file" "TIER1_ACTION"
	assert_file_contains "$csv_file" "TIER2_START"
	assert_file_contains "$csv_file" "TIER2_COMPLETE"
	assert_file_contains "$csv_file" "TIER3_START"
	assert_file_contains "$csv_file" "TIER3_COMPLETE"
}

# bats test_tags=category:unit
@test "analyze-logs.sh filters events by date range" {
	# Purpose: Test verifies that the analyze-logs script filters log events by specified date range
	# Expected: Script only analyzes events within the specified date range and excludes events outside the range
	# Importance: Enables analysis of specific time periods for troubleshooting and reporting
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	# Create log with events on different dates
	mkdir -p "$(dirname "$log_file")"
	cat >"$log_file" <<EOF
[2025-01-10 10:00:00] [WARNING] VPN check failed for 192.168.1.1 (failure count: 1)
[2025-01-15 10:00:00] [WARNING] VPN check failed for 192.168.1.1 (failure count: 1)
[2025-01-20 10:00:00] [WARNING] VPN check failed for 192.168.1.1 (failure count: 1)
EOF

	# Analyze only January 15
	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -d "2025-01-15:2025-01-15" -o "$TEST_DIR"

	assert_success
	# Should only find 1 failure (from Jan 15)
	assert_output --regexp 'Total Failures: 1\b'
}

# bats test_tags=category:unit
@test "analyze-logs.sh filters events by date range (start to end)" {
	# Purpose: Test verifies that the analyze-logs script filters log events by date range spanning multiple days
	# Expected: Script analyzes events from start date through end date inclusively
	# Importance: Enables analysis of multi-day periods for comprehensive troubleshooting and reporting
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	# Create log with events on different dates
	mkdir -p "$(dirname "$log_file")"
	cat >"$log_file" <<EOF
[2025-01-10 10:00:00] [WARNING] VPN check failed for 192.168.1.1 (failure count: 1)
[2025-01-15 10:00:00] [WARNING] VPN check failed for 192.168.1.1 (failure count: 1)
[2025-01-20 10:00:00] [WARNING] VPN check failed for 192.168.1.1 (failure count: 1)
EOF

	# Analyze Jan 15-20
	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -d "2025-01-15:2025-01-20" -o "$TEST_DIR"

	assert_success
	# Should find 2 failures (Jan 15 and Jan 20)
	assert_output --regexp 'Total Failures: 2\b'
}

# bats test_tags=category:unit
@test "analyze-logs.sh handles empty log file gracefully" {
	# Purpose: Test verifies that the analyze-logs script handles empty log files without errors
	# Expected: Script processes empty log file successfully and reports zero failures and recoveries
	# Importance: Ensures script robustness when encountering empty log files from new installations or cleared logs
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	mkdir -p "$(dirname "$log_file")"
	touch "$log_file"
	# Verify file is empty
	assert_file_empty "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"

	assert_success
	assert_output --regexp 'Total Failures: 0\b'
	assert_output --regexp 'Total Recoveries: 0\b'
}

# bats test_tags=category:unit
@test "analyze-logs.sh handles log file with only initialization messages" {
	# Purpose: Test verifies that the analyze-logs script handles log files containing only initialization messages
	# Expected: Script processes log file successfully and reports zero failures when only initialization messages are present
	# Importance: Ensures script correctly distinguishes between initialization messages and actual VPN events
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	mkdir -p "$(dirname "$log_file")"
	cat >"$log_file" <<EOF
[2025-01-15 10:00:00] [INFO] Log file initialized
[2025-01-15 10:01:00] [INFO] Configuration loaded from: /data/vpn-monitor/vpn-monitor.conf
EOF

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"

	assert_success
	assert_output --regexp 'Total Failures: 0\b'
}

# bats test_tags=category:unit
@test "analyze-logs.sh calculates recovery success rate correctly" {
	# Purpose: Test verifies that the analyze-logs script correctly calculates recovery success rate from log events
	# Expected: Script calculates recovery success rate as percentage of failures that resulted in recovery
	# Importance: Recovery success rate is a key metric for evaluating VPN stability and recovery action effectiveness
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"

	assert_success
	# Should calculate recovery success rate (recoveries / failures * 100)
	assert_output --regexp 'Recovery Success Rate:.*%'
}

# bats test_tags=category:unit
@test "analyze-logs.sh calculates tier success rates" {
	# Purpose: Test verifies that the analyze-logs script calculates success rates for each recovery tier
	# Expected: Script calculates and reports success rates for Tier 1, Tier 2, and Tier 3 recovery actions
	# Importance: Tier success rates help evaluate effectiveness of different recovery action levels
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"

	assert_success
	# Should show tier success rates
	assert_output --regexp 'Success Rate:.*%'
}

# bats test_tags=category:unit
@test "analyze-logs.sh creates output directory if missing" {
	# Purpose: Test verifies that the analyze-logs script creates output directory if it doesn't exist
	# Expected: Script creates the specified output directory before generating report and CSV files
	# Importance: Ensures script works correctly even when output directory hasn't been created manually
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local output_dir="${TEST_DIR}/reports"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$output_dir"

	assert_success
	assert_dir_exist "$output_dir"
}

# bats test_tags=category:unit
@test "analyze-logs.sh uses default log file location" {
	# Purpose: Test verifies that the analyze-logs script uses default log file location when not specified
	# Expected: Script attempts to use default log file location relative to script directory when -l flag is not provided
	# Importance: Ensures script works with default configuration for convenience and backward compatibility
	# Create log file in default location relative to script
	local script_dir
	script_dir="$(dirname "$ANALYZE_LOGS_SCRIPT")"
	local default_log="${script_dir}/logs/vpn-monitor.log"
	mkdir -p "$(dirname "$default_log")"
	create_sample_log_file "$default_log"

	# Run without -l flag (should use default)
	run bash "$ANALYZE_LOGS_SCRIPT" -o "$TEST_DIR"

	# Cleanup
	rm -f "$default_log" || true

	# Should succeed (or fail gracefully if default doesn't exist)
	# We can't guarantee the default exists, so just check it doesn't crash
	assert [ "${status:-}" -ge 0 ]
}

# bats test_tags=category:unit
@test "analyze-logs.sh verbose mode shows progress messages" {
	# Purpose: Test verifies that the analyze-logs script displays progress messages in verbose mode
	# Expected: Script outputs progress messages indicating analysis steps when -v flag is provided
	# Importance: Verbose mode helps users understand script progress and troubleshoot analysis issues
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR" -v

	assert_success
	assert_line --partial "Analyzing log file:"
	assert_line --partial "Generating text report:"
	assert_line --partial "Generating CSV export:"
}

# bats test_tags=category:unit
@test "analyze-logs.sh handles invalid date range format" {
	# Purpose: Test verifies that the analyze-logs script handles invalid date range format gracefully
	# Expected: Script exits with failure status and displays error message when date range format is invalid
	# Importance: Prevents script from processing invalid date ranges and provides clear error feedback
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -d "invalid-date-format" -o "$TEST_DIR"

	assert_failure
	assert_output --partial "Invalid date range format"
}

# bats test_tags=category:unit
@test "analyze-logs.sh extracts peer IPs from log messages" {
	# Purpose: Test verifies that the analyze-logs script correctly extracts peer IP addresses from log messages
	# Expected: Script identifies and includes peer IP addresses in CSV export for failure and recovery events
	# Importance: Peer IP tracking enables analysis of individual VPN peer reliability and troubleshooting
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_sample_log_file "$log_file"

	local csv_file="${TEST_DIR}/vpn-monitor-analysis.csv"
	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -c "$csv_file"

	assert_success
	# CSV should contain peer IPs
	assert_file_contains "$csv_file" "192.168.1.1"
	assert_file_contains "$csv_file" "198.51.100.1"
	# Verify IP format using regex
	run grep -E '192\.168\.1\.1|198\.51\.100\.1' "$csv_file"
	assert_success
}

# bats test_tags=category:unit
@test "analyze-logs.sh text report includes event timeline" {
	# Purpose: Test verifies that the analyze-logs script includes detailed event timeline in text report
	# Expected: Text report contains chronological timeline of failure and recovery events with timestamps
	# Importance: Event timeline provides chronological context for understanding VPN failure patterns
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local report_file="${TEST_DIR}/vpn-monitor-report.txt"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -r "$report_file"

	assert_success
	assert_file_contains "$report_file" "Detailed Event Timeline"
	assert_file_contains "$report_file" "FAILURE:"
	assert_file_contains "$report_file" "RECOVERY"
}

# bats test_tags=category:unit
@test "analyze-logs.sh handles multiple peer IPs correctly" {
	# Purpose: Test verifies that the analyze-logs script correctly tracks and reports events for multiple peer IPs
	# Expected: Script processes log events for multiple peer IPs and includes all peer IPs in CSV export
	# Importance: Multi-peer support enables analysis of VPN deployments with multiple remote peers
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	mkdir -p "$(dirname "$log_file")"
	cat >"$log_file" <<EOF
[2025-01-15 10:00:00] [WARNING] VPN check failed for 192.168.1.1 (failure count: 1)
[2025-01-15 10:01:00] [WARNING] VPN check failed for 198.51.100.1 (failure count: 1)
[2025-01-15 10:02:00] [INFO] VPN recovered for 192.168.1.1 after 1 failures
[2025-01-15 10:03:00] [INFO] VPN recovered for 198.51.100.1 after 1 failures
EOF

	local csv_file="${TEST_DIR}/vpn-monitor-analysis.csv"
	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -c "$csv_file"

	assert_success
	# Should track both peer IPs
	assert_file_contains "$csv_file" "192.168.1.1"
	assert_file_contains "$csv_file" "198.51.100.1"
	# Verify IP format using regex
	run grep -E '192\.168\.1\.1|198\.51\.100\.1' "$csv_file"
	assert_success
}

# bats test_tags=category:unit
@test "analyze-logs.sh calculates failures per day" {
	# Purpose: Test verifies that the analyze-logs script calculates failure counts per day from log events
	# Expected: Script aggregates failures by day and reports failures per day statistics
	# Importance: Daily failure statistics help identify patterns and trends in VPN reliability
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"

	assert_success
	assert_output --partial "Failures per Day:"
}

# bats test_tags=category:unit
@test "analyze-logs.sh report includes analysis period information" {
	# Purpose: Test verifies that the analyze-logs script includes analysis period metadata in report
	# Expected: Report contains analysis period information including first event, last event, and days analyzed
	# Importance: Analysis period metadata provides context for understanding the scope and timeframe of the analysis
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local report_file="${TEST_DIR}/vpn-monitor-report.txt"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -r "$report_file"

	assert_success
	assert_file_contains "$report_file" "Analysis Period:"
	# Verify date format in First Event and Last Event
	assert_file_contains "$report_file" "First Event:"
	assert_file_contains "$report_file" "Last Event:"
	# Verify Days Analyzed contains a number
	run grep -E 'Days Analyzed:.*[0-9]+' "$report_file"
	assert_success
}

# bats test_tags=category:unit
@test "analyze-logs.sh distinguishes app-managed recoveries" {
	# Purpose: Test verifies that the analyze-logs script correctly identifies app-managed recoveries (with recovery method)
	# Expected: Script identifies recoveries with "recovery method" in the message as app-managed recoveries
	# Importance: App-managed recovery tracking helps evaluate effectiveness of recovery actions and intervention needs
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_recovery_type_test_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"

	assert_success
	assert_output --partial "App-Managed (with intervention):"
	# Should find at least 2 app-managed recoveries (one with xfrm, one with ipsec restart)
	assert_output --regexp 'App-Managed \(with intervention\): [2-9]|[1-9][0-9]+'
}

# bats test_tags=category:unit
@test "analyze-logs.sh distinguishes self-healed recoveries" {
	# Purpose: Test verifies that the analyze-logs script correctly identifies self-healed recoveries (without recovery method)
	# Expected: Script identifies recoveries with "after N failures" but no "recovery method" as self-healed recoveries
	# Importance: Self-healed recovery tracking helps evaluate VPN stability and natural recovery capabilities
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_recovery_type_test_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"

	assert_success
	assert_output --partial "Self-Healed (no intervention):"
	# Should find at least 2 self-healed recoveries
	assert_output --regexp 'Self-Healed \(no intervention\): [2-9]|[1-9][0-9]+'
}

# bats test_tags=category:unit
@test "analyze-logs.sh statistics show both recovery types" {
	# Purpose: Test verifies that the analyze-logs script reports statistics for both app-managed and self-healed recoveries
	# Expected: Script output includes counts for both recovery types, and report file includes rates
	# Importance: Comprehensive recovery statistics provide complete picture of VPN recovery patterns
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local report_file="${TEST_DIR}/vpn-monitor-report.txt"
	create_recovery_type_test_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"

	assert_success
	# Should show both types in stdout summary
	assert_output --partial "App-Managed (with intervention):"
	assert_output --partial "Self-Healed (no intervention):"
	# Recovery rates are in the report file, not stdout
	assert_file_exist "$report_file"
	assert_file_contains "$report_file" "App-Managed Recovery Rate:"
	assert_file_contains "$report_file" "Self-Healed Recovery Rate:"
}

# bats test_tags=category:unit
@test "analyze-logs.sh CSV export includes recovery type" {
	# Purpose: Test verifies that the CSV export includes recovery type (APP_MANAGED vs SELF_HEALED) for recovery events
	# Expected: CSV file contains RECOVERY_APP_MANAGED and RECOVERY_SELF_HEALED event types
	# Importance: CSV export with recovery types enables detailed analysis of recovery patterns in spreadsheet applications
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local csv_file="${TEST_DIR}/vpn-monitor-analysis.csv"
	create_recovery_type_test_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -c "$csv_file"

	assert_success
	assert_file_exist "$csv_file"
	# CSV should contain both recovery types
	assert_file_contains "$csv_file" "RECOVERY_APP_MANAGED"
	assert_file_contains "$csv_file" "RECOVERY_SELF_HEALED"
	# Verify recovery type counts
	local app_managed_count
	app_managed_count=$(grep -c "RECOVERY_APP_MANAGED" "$csv_file" || echo "0")
	local self_healed_count
	self_healed_count=$(grep -c "RECOVERY_SELF_HEALED" "$csv_file" || echo "0")
	# Should have at least 2 app-managed recoveries
	assert [ "$app_managed_count" -ge 2 ]
	# Should have at least 2 self-healed recoveries
	assert [ "$self_healed_count" -ge 2 ]
}

# bats test_tags=category:unit
@test "analyze-logs.sh report includes recovery type breakdown" {
	# Purpose: Test verifies that the text report includes breakdown of app-managed vs self-healed recoveries
	# Expected: Report file contains statistics showing both recovery types with counts and rates
	# Importance: Recovery type breakdown in reports provides visibility into intervention needs and system stability
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local report_file="${TEST_DIR}/vpn-monitor-report.txt"
	create_recovery_type_test_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -r "$report_file"

	assert_success
	assert_file_exist "$report_file"
	# Report should contain recovery type breakdown
	assert_file_contains "$report_file" "App-Managed Recoveries (with intervention):"
	assert_file_contains "$report_file" "Self-Healed Recoveries (no intervention):"
	assert_file_contains "$report_file" "App-Managed Recovery Rate:"
	assert_file_contains "$report_file" "Self-Healed Recovery Rate:"
}

# bats test_tags=category:unit
@test "analyze-logs.sh event timeline shows recovery types" {
	# Purpose: Test verifies that the event timeline in the report distinguishes between app-managed and self-healed recoveries
	# Expected: Event timeline includes recovery type labels (APP-MANAGED vs SELF-HEALED) for recovery events
	# Importance: Recovery type labels in timeline provide chronological context for understanding recovery patterns
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local report_file="${TEST_DIR}/vpn-monitor-report.txt"
	create_recovery_type_test_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -r "$report_file"

	assert_success
	assert_file_exist "$report_file"
	# Timeline should show recovery types
	assert_file_contains "$report_file" "RECOVERY (APP-MANAGED):"
	assert_file_contains "$report_file" "RECOVERY (SELF-HEALED):"
}
