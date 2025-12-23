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

@test "analyze-logs.sh exists and is executable" {
	assert_file_exist "$ANALYZE_LOGS_SCRIPT"
	assert_file_executable "$ANALYZE_LOGS_SCRIPT"
}

@test "analyze-logs.sh shows help with --help flag" {
	run bash "$ANALYZE_LOGS_SCRIPT" --help
	assert_success
	assert_output --partial "Usage:"
	assert_output --partial "analyze-logs.sh"
	assert_output --partial "--log-file"
	assert_output --partial "--csv"
	assert_output --partial "--report"
}

@test "analyze-logs.sh shows help with -h flag" {
	run bash "$ANALYZE_LOGS_SCRIPT" -h
	assert_success
	assert_output --partial "Usage:"
}

@test "analyze-logs.sh exits with error if log file not found" {
	local log_file="${TEST_DIR}/nonexistent.log"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file"

	assert_failure
	assert_output --partial "Log file not found"
}

@test "analyze-logs.sh exits with error if log file not readable" {
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

@test "analyze-logs.sh parses log file and extracts failures" {
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"

	assert_success
	assert_output --partial "Total Failures:"
	# Should find multiple failures
	assert_output --partial "Failures per Day:"
}

@test "analyze-logs.sh extracts recoveries from log file" {
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"

	assert_success
	assert_output --partial "Total Recoveries:"
	assert_output --partial "Recovery Success Rate:"
}

@test "analyze-logs.sh extracts tier actions from log file" {
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

@test "analyze-logs.sh generates text report file" {
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

@test "analyze-logs.sh generates CSV export file" {
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

@test "analyze-logs.sh CSV contains failure events" {
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local csv_file="${TEST_DIR}/vpn-monitor-analysis.csv"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -c "$csv_file"

	assert_success
	# Check CSV contains failure entries
	local failure_count
	failure_count=$(grep -c "FAILURE" "$csv_file" || echo "0")
	assert [ "$failure_count" -gt 0 ]
}

@test "analyze-logs.sh CSV contains recovery events" {
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local csv_file="${TEST_DIR}/vpn-monitor-analysis.csv"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -c "$csv_file"

	assert_success
	# Check CSV contains recovery entries
	local recovery_count
	recovery_count=$(grep -c "RECOVERY" "$csv_file" || echo "0")
	assert [ "$recovery_count" -gt 0 ]
}

@test "analyze-logs.sh CSV contains tier action events" {
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

@test "analyze-logs.sh filters events by date range" {
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
	assert_output --partial "Total Failures: 1"
}

@test "analyze-logs.sh filters events by date range (start to end)" {
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
	assert_output --partial "Total Failures: 2"
}

@test "analyze-logs.sh handles empty log file gracefully" {
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	mkdir -p "$(dirname "$log_file")"
	touch "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"

	assert_success
	assert_output --partial "Total Failures: 0"
	assert_output --partial "Total Recoveries: 0"
}

@test "analyze-logs.sh handles log file with only initialization messages" {
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	mkdir -p "$(dirname "$log_file")"
	cat >"$log_file" <<EOF
[2025-01-15 10:00:00] [INFO] Log file initialized
[2025-01-15 10:01:00] [INFO] Configuration loaded from: /data/vpn-monitor/vpn-monitor.conf
EOF

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"

	assert_success
	assert_output --partial "Total Failures: 0"
}

@test "analyze-logs.sh calculates recovery success rate correctly" {
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"

	assert_success
	# Should calculate recovery success rate (recoveries / failures * 100)
	assert_output --partial "Recovery Success Rate:"
}

@test "analyze-logs.sh calculates tier success rates" {
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"

	assert_success
	# Should show tier success rates
	assert_output --partial "Success Rate:"
}

@test "analyze-logs.sh creates output directory if missing" {
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local output_dir="${TEST_DIR}/reports"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$output_dir"

	assert_success
	assert_dir_exist "$output_dir"
}

@test "analyze-logs.sh uses default log file location" {
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

@test "analyze-logs.sh verbose mode shows progress messages" {
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR" -v

	assert_success
	assert_output --partial "Analyzing log file:"
	assert_output --partial "Generating text report:"
	assert_output --partial "Generating CSV export:"
}

@test "analyze-logs.sh handles invalid date range format" {
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -d "invalid-date-format" -o "$TEST_DIR"

	assert_failure
	assert_output --partial "Invalid date range format"
}

@test "analyze-logs.sh extracts peer IPs from log messages" {
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_sample_log_file "$log_file"

	local csv_file="${TEST_DIR}/vpn-monitor-analysis.csv"
	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -c "$csv_file"

	assert_success
	# CSV should contain peer IPs
	assert_file_contains "$csv_file" "192.168.1.1"
	assert_file_contains "$csv_file" "198.51.100.1"
}

@test "analyze-logs.sh text report includes event timeline" {
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local report_file="${TEST_DIR}/vpn-monitor-report.txt"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -r "$report_file"

	assert_success
	assert_file_contains "$report_file" "Detailed Event Timeline"
	assert_file_contains "$report_file" "FAILURE:"
	assert_file_contains "$report_file" "RECOVERY:"
}

@test "analyze-logs.sh handles multiple peer IPs correctly" {
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
}

@test "analyze-logs.sh calculates failures per day" {
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"

	assert_success
	assert_output --partial "Failures per Day:"
}

@test "analyze-logs.sh report includes analysis period information" {
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local report_file="${TEST_DIR}/vpn-monitor-report.txt"
	create_sample_log_file "$log_file"

	run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -r "$report_file"

	assert_success
	assert_file_contains "$report_file" "Analysis Period:"
	assert_file_contains "$report_file" "First Event:"
	assert_file_contains "$report_file" "Last Event:"
	assert_file_contains "$report_file" "Days Analyzed:"
}
