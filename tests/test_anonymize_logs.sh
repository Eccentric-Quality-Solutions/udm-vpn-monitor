#!/usr/bin/env bats
#
# Tests for anonymize-logs.sh script
# Tests log anonymization functionality, IP and location anonymization, and consistency

load test_helper

# Path to the anonymize-logs script
ANONYMIZE_LOGS_SCRIPT="${BATS_TEST_DIRNAME}/../scripts/anonymize/anonymize-logs.sh"

# Create sample log file with IPs and locations
#
# Creates a log file with IP addresses and location names for testing anonymization.
#
# Arguments:
#   $1: Log file path
#
# Returns:
#   0: Always succeeds
create_sample_log_file() {
	local log_file="$1"

	mkdir -p "$(dirname "$log_file")"

	cat >"$log_file" <<EOF
[2025-01-15 10:00:00] [INFO] VPN check for location NYC (203.0.113.1): OK
[2025-01-15 10:01:00] [WARNING] VPN check failed for location DC (198.51.100.1) (failure count: 1)
[2025-01-15 10:02:00] [INFO] VPN check for location CHICAGO (192.0.2.1): OK
[2025-01-15 10:03:00] [WARNING] VPN check failed for location NYC (203.0.113.1) (failure count: 1)
[2025-01-15 10:04:00] [INFO] VPN check for location DC (198.51.100.1): OK
[2025-01-15 10:05:00] [INFO] VPN check for 10.0.0.1: OK
[2025-01-15 10:06:00] [WARNING] VPN check failed for 172.16.0.1 (failure count: 1)
EOF
}

# bats test_tags=category:unit
@test "anonymize-logs.sh exists and is executable" {
	# Purpose: Test verifies that the anonymize-logs script file exists and has execute permissions
	# Expected: Anonymize-logs script file is present and executable
	# Importance: Ensures the log anonymization script can be run directly for log sanitization
	assert_file_exist "$ANONYMIZE_LOGS_SCRIPT"
	assert_file_executable "$ANONYMIZE_LOGS_SCRIPT"
}

# bats test_tags=category:unit
@test "anonymize-logs.sh shows help with --help flag" {
	# Purpose: Test verifies that the anonymize-logs script displays usage information when --help flag is provided
	# Expected: Script outputs usage information including all available options and flags
	# Importance: Ensures users can access help documentation for script usage and available options
	run bash "$ANONYMIZE_LOGS_SCRIPT" --help
	assert_success
	assert_output --partial "Usage:"
	assert_output --partial "anonymize-logs.sh"
	assert_output --partial "--input"
	assert_output --partial "--output"
	assert_output --partial "--verbose"
}

# bats test_tags=category:unit
@test "anonymize-logs.sh shows help with -h flag" {
	# Purpose: Test verifies that the anonymize-logs script displays usage information when -h flag is provided
	# Expected: Script outputs usage information including all available options and flags
	# Importance: Ensures users can access help documentation using the short flag option
	run bash "$ANONYMIZE_LOGS_SCRIPT" -h
	assert_success
	assert_output --partial "Usage:"
}

# bats test_tags=category:unit
@test "anonymize-logs.sh exits with error if input file not found" {
	# Purpose: Test verifies that the anonymize-logs script validates input file existence before processing
	# Expected: Script exits with failure status and displays error message when input file doesn't exist
	# Importance: Prevents script from attempting to anonymize non-existent files and provides clear error feedback
	local input_file="${TEST_DIR}/nonexistent.log"

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file"

	assert_failure
	assert_output --partial "Input file not found"
}

# bats test_tags=category:unit
@test "anonymize-logs.sh exits with error if input file not readable" {
	# Purpose: Test verifies that the anonymize-logs script validates input file readability before processing
	# Expected: Script exits with failure status and displays error message when input file is not readable
	# Importance: Prevents script from attempting to anonymize unreadable files and provides clear error feedback
	local input_file="${TEST_DIR}/logs/vpn-monitor.log"
	mkdir -p "$(dirname "$input_file")"
	touch "$input_file"
	chmod 000 "$input_file"

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file"

	# Restore permissions for cleanup
	chmod 644 "$input_file" || true

	assert_failure
	assert_output --partial "Input file not readable"
}

# bats test_tags=category:unit
@test "anonymize-logs.sh exits with error if input file not specified" {
	# Purpose: Test verifies that the anonymize-logs script requires input file to be specified
	# Expected: Script exits with failure status and displays error message when input file is missing
	# Importance: Prevents script from running without required input and provides clear error feedback
	run bash "$ANONYMIZE_LOGS_SCRIPT"

	assert_failure
	assert_output --partial "Input file is required"
}

# bats test_tags=category:unit
@test "anonymize-logs.sh anonymizes IP addresses" {
	# Purpose: Test verifies that the anonymize-logs script replaces IP addresses with anonymized versions
	# Expected: Script replaces all IP addresses in log file with anonymized IPs in 10.x.x.x range
	# Importance: IP anonymization is a core feature for protecting sensitive network information
	local input_file="${TEST_DIR}/logs/vpn-monitor.log"
	local output_file="${TEST_DIR}/anonymized.log"
	create_sample_log_file "$input_file"

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify original IPs are not in output
	refute_file_contains "$output_file" "203.0.113.1"
	refute_file_contains "$output_file" "198.51.100.1"
	refute_file_contains "$output_file" "192.0.2.1"
	# Verify anonymized IPs are in 10.x.x.x range
	run grep -oE '\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b' "$output_file"
	assert_success
	# Verify at least one anonymized IP was found
	assert [ "${#lines[@]}" -gt 0 ]
}

# bats test_tags=category:unit
@test "anonymize-logs.sh anonymizes location names" {
	# Purpose: Test verifies that the anonymize-logs script replaces location names with anonymized versions
	# Expected: Script replaces all location names in log file with anonymized city names
	# Importance: Location anonymization is a core feature for protecting sensitive location information
	local input_file="${TEST_DIR}/logs/vpn-monitor.log"
	local output_file="${TEST_DIR}/anonymized.log"
	create_sample_log_file "$input_file"

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify original location names are not in output
	refute_file_contains "$output_file" "location NYC"
	refute_file_contains "$output_file" "location DC"
	refute_file_contains "$output_file" "location CHICAGO"
	# Verify anonymized location names are present (should be city names from CITY_NAMES array)
	# Check for pattern "location CITY_NAME" where CITY_NAME is uppercase
	run grep -E 'location [A-Z][A-Z0-9_]+' "$output_file"
	assert_success
	# Verify at least one anonymized location was found
	assert [ "${#lines[@]}" -gt 0 ]
}

# bats test_tags=category:unit
@test "anonymize-logs.sh produces consistent anonymization across multiple runs" {
	# Purpose: Test verifies that the anonymize-logs script produces the same anonymized output when run multiple times
	# Expected: Running the script twice on the same input produces identical output
	# Importance: Consistency ensures that anonymized logs remain understandable and comparable across runs
	local input_file="${TEST_DIR}/logs/vpn-monitor.log"
	local output_file1="${TEST_DIR}/anonymized1.log"
	local output_file2="${TEST_DIR}/anonymized2.log"
	create_sample_log_file "$input_file"

	# Run anonymization twice
	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file" -o "$output_file1"
	assert_success

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file" -o "$output_file2"
	assert_success

	# Verify both output files exist
	assert_file_exist "$output_file1"
	assert_file_exist "$output_file2"

	# Verify outputs are identical
	run diff "$output_file1" "$output_file2"
	assert_success
	assert_output ""
}

# bats test_tags=category:unit
@test "anonymize-logs.sh handles empty file gracefully" {
	# Purpose: Test verifies that the anonymize-logs script handles empty log files without errors
	# Expected: Script processes empty log file successfully and produces empty output
	# Importance: Ensures script robustness when encountering empty log files from new installations or cleared logs
	local input_file="${TEST_DIR}/logs/vpn-monitor.log"
	local output_file="${TEST_DIR}/anonymized.log"
	mkdir -p "$(dirname "$input_file")"
	touch "$input_file"
	# Verify file is empty
	assert_file_empty "$input_file"

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	assert_file_empty "$output_file"
}

# bats test_tags=category:unit
@test "anonymize-logs.sh outputs to stdout when output file not specified" {
	# Purpose: Test verifies that the anonymize-logs script outputs to stdout when output file is not specified
	# Expected: Script writes anonymized log content to stdout instead of a file
	# Importance: Enables piping anonymized logs to other commands or viewing directly
	local input_file="${TEST_DIR}/logs/vpn-monitor.log"
	create_sample_log_file "$input_file"

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file"

	assert_success
	# Verify output contains anonymized content (should have anonymized IPs)
	assert_output --regexp '10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
	# Verify original IPs are not in output
	refute_output --partial "203.0.113.1"
	refute_output --partial "198.51.100.1"
}

# bats test_tags=category:unit
@test "anonymize-logs.sh verbose mode shows progress messages" {
	# Purpose: Test verifies that the anonymize-logs script displays progress messages in verbose mode
	# Expected: Script outputs progress messages indicating anonymization steps when -v flag is provided
	# Importance: Verbose mode helps users understand script progress and troubleshoot anonymization issues
	local input_file="${TEST_DIR}/logs/vpn-monitor.log"
	local output_file="${TEST_DIR}/anonymized.log"
	create_sample_log_file "$input_file"

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file" -o "$output_file" -v

	assert_success
	# Verify verbose messages are present (sent to stderr)
	assert_line --partial "Extracting IPv4 addresses..."
	assert_line --partial "Extracting location names..."
	assert_line --partial "Anonymizing log file..."
	assert_line --partial "Anonymization complete!"
}

# bats test_tags=category:unit
@test "anonymize-logs.sh maps same IP to same anonymized IP consistently" {
	# Purpose: Test verifies that the same IP address is always mapped to the same anonymized IP
	# Expected: Multiple occurrences of the same IP in the log are all replaced with the same anonymized IP
	# Importance: Ensures consistency within a single anonymization run, making logs understandable
	local input_file="${TEST_DIR}/logs/vpn-monitor.log"
	local output_file="${TEST_DIR}/anonymized.log"
	mkdir -p "$(dirname "$input_file")"
	# Create log with same IP appearing multiple times
	cat >"$input_file" <<EOF
[2025-01-15 10:00:00] [INFO] VPN check for location NYC (203.0.113.1): OK
[2025-01-15 10:01:00] [WARNING] VPN check failed for location NYC (203.0.113.1) (failure count: 1)
[2025-01-15 10:02:00] [INFO] VPN check for location NYC (203.0.113.1): OK
EOF

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	# Extract all anonymized IPs that replaced 203.0.113.1
	# They should all be the same
	# Count unique anonymized IPs (should be 1, since all instances of 203.0.113.1 map to same IP)
	# Note: There might be other IPs in the log, so we check that there's at least one unique IP
	# and that the same IP appears multiple times
	local ip_count
	ip_count=$(grep -oE '\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b' "$output_file" | wc -l)
	# Should have at least 3 anonymized IPs (one for each occurrence)
	assert [ "$ip_count" -ge 3 ]
	# Verify all occurrences use the same anonymized IP (count unique IPs should be 1)
	local unique_count
	unique_count=$(grep -oE '\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b' "$output_file" | sort -u | wc -l)
	# Since we only have one original IP, all should map to the same anonymized IP
	assert [ "$unique_count" -eq 1 ]
}

# bats test_tags=category:unit
@test "anonymize-logs.sh maps same location to same anonymized location consistently" {
	# Purpose: Test verifies that the same location name is always mapped to the same anonymized location
	# Expected: Multiple occurrences of the same location in the log are all replaced with the same anonymized location
	# Importance: Ensures consistency within a single anonymization run, making logs understandable
	local input_file="${TEST_DIR}/logs/vpn-monitor.log"
	local output_file="${TEST_DIR}/anonymized.log"
	mkdir -p "$(dirname "$input_file")"
	# Create log with same location appearing multiple times
	cat >"$input_file" <<EOF
[2025-01-15 10:00:00] [INFO] VPN check for location NYC (203.0.113.1): OK
[2025-01-15 10:01:00] [WARNING] VPN check failed for location NYC (203.0.113.1) (failure count: 1)
[2025-01-15 10:02:00] [INFO] VPN check for location NYC (203.0.113.1): OK
EOF

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	# Extract all anonymized location names (should all be the same for NYC)
	# Count unique anonymized locations (should be 1, since all instances of NYC map to same location)
	local unique_count
	unique_count=$(grep -oE 'location [A-Z][A-Z0-9_]+' "$output_file" | sed 's/location //' | sort -u | wc -l)
	# Since we only have one original location, all should map to the same anonymized location
	assert [ "$unique_count" -eq 1 ]
}

# bats test_tags=category:unit
@test "anonymize-logs.sh handles log file with only IPs (no locations)" {
	# Purpose: Test verifies that the anonymize-logs script handles log files containing only IP addresses without location names
	# Expected: Script successfully anonymizes IP addresses even when no location names are present
	# Importance: Ensures script works with various log formats and doesn't require location names
	local input_file="${TEST_DIR}/logs/vpn-monitor.log"
	local output_file="${TEST_DIR}/anonymized.log"
	mkdir -p "$(dirname "$input_file")"
	cat >"$input_file" <<EOF
[2025-01-15 10:00:00] [INFO] VPN check for 203.0.113.1: OK
[2025-01-15 10:01:00] [WARNING] VPN check failed for 198.51.100.1 (failure count: 1)
[2025-01-15 10:02:00] [INFO] VPN check for 192.0.2.1: OK
EOF

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify original IPs are not in output
	refute_file_contains "$output_file" "203.0.113.1"
	refute_file_contains "$output_file" "198.51.100.1"
	refute_file_contains "$output_file" "192.0.2.1"
	# Verify anonymized IPs are present
	run grep -oE '\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b' "$output_file"
	assert_success
}

# bats test_tags=category:unit
@test "anonymize-logs.sh handles log file with only locations (no IPs)" {
	# Purpose: Test verifies that the anonymize-logs script handles log files containing only location names without IP addresses
	# Expected: Script successfully anonymizes location names even when no IP addresses are present
	# Importance: Ensures script works with various log formats and doesn't require IP addresses
	local input_file="${TEST_DIR}/logs/vpn-monitor.log"
	local output_file="${TEST_DIR}/anonymized.log"
	mkdir -p "$(dirname "$input_file")"
	cat >"$input_file" <<EOF
[2025-01-15 10:00:00] [INFO] VPN check for location NYC: OK
[2025-01-15 10:01:00] [WARNING] VPN check failed for location DC (failure count: 1)
[2025-01-15 10:02:00] [INFO] VPN check for location CHICAGO: OK
EOF

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify original location names are not in output
	refute_file_contains "$output_file" "location NYC"
	refute_file_contains "$output_file" "location DC"
	refute_file_contains "$output_file" "location CHICAGO"
	# Verify anonymized location names are present
	run grep -E 'location [A-Z][A-Z0-9_]+' "$output_file"
	assert_success
}

# bats test_tags=category:unit
@test "anonymize-logs.sh anonymizes capital Location patterns" {
	# Purpose: Test verifies that the anonymize-logs script anonymizes location names in capital "Location" patterns
	# Expected: Script replaces location names in patterns like "Location AUSTIN - ping failed"
	# Importance: Ensures location names are anonymized in all log formats, including keepalive messages
	local input_file="${TEST_DIR}/logs/vpn-monitor.log"
	local output_file="${TEST_DIR}/anonymized.log"
	mkdir -p "$(dirname "$input_file")"
	cat >"$input_file" <<EOF
[2025-01-15 10:00:00] [WARNING] Keepalive: Location NYC - ping failed for 192.168.1.1 (external: 203.0.113.1)
[2025-01-15 10:01:00] [WARNING] Keepalive: Location DC - ping failed for 192.168.1.2 (external: 198.51.100.1)
EOF

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify original location names are not in output
	refute_file_contains "$output_file" "Location NYC"
	refute_file_contains "$output_file" "Location DC"
	# Verify anonymized location names are present
	run grep -E 'Location [A-Z][A-Z0-9_]+' "$output_file"
	assert_success
}

# bats test_tags=category:unit
@test "anonymize-logs.sh anonymizes location names in comma-separated lists" {
	# Purpose: Test verifies that the anonymize-logs script anonymizes location names in comma-separated lists
	# Expected: Script replaces location names in patterns like "Found 11 location(s): PHOENIX (IP, IP), SEATTLE (IP)..."
	# Importance: Ensures location names are anonymized in configuration summary messages (with or without IPs in parentheses)
	local input_file="${TEST_DIR}/logs/vpn-monitor.log"
	local output_file="${TEST_DIR}/anonymized.log"
	mkdir -p "$(dirname "$input_file")"
	cat >"$input_file" <<EOF
[2025-01-15 10:00:00] [INFO] Found 3 location(s): NYC (203.0.113.1, 192.168.1.1), DC (198.51.100.1), CHICAGO (192.0.2.1)
[2025-01-15 10:01:00] [INFO] Found 2 location(s): NYC (203.0.113.1), DC (198.51.100.1)
EOF

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify original location names are not in output
	refute_file_contains "$output_file" "NYC"
	refute_file_contains "$output_file" "DC"
	refute_file_contains "$output_file" "CHICAGO"
	# Verify anonymized location names are present in the list
	run grep -E 'location\(s\): [A-Z][A-Z0-9_]+' "$output_file"
	assert_success
}

# bats test_tags=category:unit
@test "anonymize-logs.sh produces unique anonymized names when many locations hash to same city" {
	# Purpose: Regression test for get_or_create_location_mapping collision bug.
	# Bug: Different original locations could map to same anonymized city (e.g. CHICAGO twice).
	# Fix: _is_location_city_used checks VALUES in map, not keys.
	# Expected: "Found N location(s):" line has N unique anonymized names (no duplicates).
	local input_file="${TEST_DIR}/logs/many-locations.log"
	local output_file="${TEST_DIR}/many-anonymized.log"
	mkdir -p "$(dirname "$input_file")"
	# 12 unique locations - enough to trigger hash collisions in 40-city pool
	cat >"$input_file" <<'EOF'
[2025-01-15 10:00:00] [INFO] Found 12 location(s): SITE_A (1.1.1.1), SITE_B (1.1.1.2), SITE_C (1.1.1.3), SITE_D (1.1.1.4), SITE_E (1.1.1.5), SITE_F (1.1.1.6), SITE_G (1.1.1.7), SITE_H (1.1.1.8), SITE_I (1.1.1.9), SITE_J (1.1.1.10), SITE_K (1.1.1.11), SITE_L (1.1.1.12)
EOF

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	# Extract the location list from "Found 12 location(s): X, Y, Z..."
	local found_line
	found_line=$(grep -o 'Found 12 location(s): .*' "$output_file")
	local location_list="${found_line#Found 12 location(s): }"
	# Split by comma, trim, count unique
	local -a locations=()
	IFS=',' read -ra parts <<<"$location_list"
	for p in "${parts[@]}"; do
		p="${p#"${p%%[![:space:]]*}"}"
		p="${p%"${p##*[![:space:]]}"}"
		# Extract location name (part before space/paren)
		p="${p%% *}"
		p="${p%%(*}"
		[[ -n "$p" ]] && locations+=("$p")
	done
	# Count unique
	local unique_count
	unique_count=$(printf '%s\n' "${locations[@]}" | sort -u | wc -l)
	assert_equal 12 "$unique_count" "Expected 12 unique anonymized location names, got $unique_count (duplicates indicate collision bug)"
}

# bats test_tags=category:unit
@test "anonymize-logs.sh uses shared mapping file so different locations get different anonymized names across runs" {
	# Purpose: Without -m, script uses <input_dir>/anonymization.mapping so mappings persist.
	# Run 1: NYC -> CITY_A. Run 2: ATLANTA (different location) -> CITY_B (not CITY_A).
	# Prevents overwriting: each original location gets a distinct anonymized city.
	local log_dir="${TEST_DIR}/shared_mapping_logs"
	local input_nyc="${log_dir}/vpn-monitor-NYC.log"
	local input_atlanta="${log_dir}/vpn-monitor-ATLANTA.log"
	local output_nyc="${log_dir}/out-nyc.log"
	local output_atlanta="${log_dir}/out-atlanta.log"
	mkdir -p "$log_dir"
	echo '[2025-01-15 10:00:00] [INFO] VPN check for location NYC (10.0.0.1): OK' >"$input_nyc"
	echo '[2025-01-15 10:00:00] [INFO] VPN check for location ATLANTA (10.0.0.2): OK' >"$input_atlanta"

	# Run 1: anonymize NYC log (no -m) -> creates anonymization.mapping with NYC -> something
	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_nyc" -o "$output_nyc"
	assert_success
	local mapping_file="${log_dir}/anonymization.mapping"
	assert_file_exist "$mapping_file"
	run grep -E '^NYC -> ' "$mapping_file"
	assert_success
	local anon_nyc
	anon_nyc=$(grep -E '^NYC -> ' "$mapping_file" | sed 's/^NYC -> //')

	# Run 2: anonymize ATLANTA log (no -m) -> loads same mapping, ATLANTA gets a different city
	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_atlanta" -o "$output_atlanta"
	assert_success
	run grep -E '^ATLANTA -> ' "$mapping_file"
	assert_success
	local anon_atlanta
	anon_atlanta=$(grep -E '^ATLANTA -> ' "$mapping_file" | sed 's/^ATLANTA -> //')
	assert_not_equal "$anon_nyc" "$anon_atlanta" "NYC and ATLANTA must map to different anonymized cities (semi-permanent mapping)"
	# Mapping file should still contain NYC
	run grep -E '^NYC -> ' "$mapping_file"
	assert_success
}

# bats test_tags=category:unit
@test "anonymize-logs.sh rewrites output filename when it contains real location name" {
	# Purpose: When -o is a path like anonymized-vpn-monitor-NYC.log, output is written
	# to vpn-monitor-<ANON>-anonymized.log so the filename does not leak the location.
	# Expected: File is written to canonical anonymized basename in the same directory.
	local log_dir="${TEST_DIR}/rewrite-out"
	local input_file="${log_dir}/vpn-monitor-NYC.log"
	local output_path="${log_dir}/anonymized-vpn-monitor-NYC.log"
	mkdir -p "$log_dir"
	create_sample_log_file "$input_file"

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file" -o "$output_path"

	assert_success
	# Script must not write to the user-provided path that contains the real location
	assert [ ! -f "$output_path" ]
	# Script must write to canonical name vpn-monitor-<ANON>-anonymized.log in same dir
	local canonical
	canonical=$(find "$log_dir" -maxdepth 1 -name 'vpn-monitor-*-anonymized.log' -type f)
	assert [ -n "$canonical" ]
	assert_file_exist "$canonical"
	refute_file_contains "$canonical" "NYC"
}

# bats test_tags=category:unit
@test "anonymize-logs.sh anonymizes output filename when input has IP instead of location" {
	# Purpose: When input is vpn-monitor-<ip>.log (UDM exports use host IP), output filename
	# must use anonymized IP so the filename does not leak the real UDM IP.
	# Expected: vpn-monitor-172.31.11.1.log -> vpn-monitor-<anonymized_ip>-anonymized.log
	local log_dir="${TEST_DIR}/ip-filename"
	local input_file="${log_dir}/vpn-monitor-172.31.11.1.log"
	local output_path="${log_dir}/out.log"
	mkdir -p "$log_dir"
	echo '[2025-01-15 10:00:00] [INFO] VPN check for location NYC (10.0.0.1): OK' >"$input_file"

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file" -o "$output_path" -m "${log_dir}/mapping.txt"

	assert_success
	# Output must not be named with the real IP
	assert [ ! -f "${log_dir}/vpn-monitor-172.31.11.1-anonymized.log" ]
	# Output must be vpn-monitor-<anon_ip>-anonymized.log (anon IP is in 10.x.x.x range)
	local canonical
	canonical=$(find "$log_dir" -maxdepth 1 -name 'vpn-monitor-*-anonymized.log' -type f)
	[[ -n "$canonical" ]] || (echo "No vpn-monitor-*-anonymized.log found in $log_dir" && ls -la "$log_dir" && return 1)
	# Basename must match pattern vpn-monitor-10.x.x.x-anonymized.log (anonymized IP)
	local basename_canonical
	basename_canonical=$(basename "$canonical")
	[[ "$basename_canonical" =~ ^vpn-monitor-10\.[0-9]+\.[0-9]+\.[0-9]+-anonymized\.log$ ]] || (echo "Filename must use anonymized IP, got: $basename_canonical" && return 1)
	# Must not contain real UDM IP in filename
	refute [[ "$basename_canonical" == *"172.31.11.1"* ]]
}

# bats test_tags=category:unit
@test "anonymize-logs.sh preserves log file structure and formatting" {
	# Purpose: Test verifies that the anonymize-logs script preserves the structure and formatting of the log file
	# Expected: Anonymized log maintains the same line count, timestamp format, and log level format as original
	# Importance: Preserving log structure ensures anonymized logs remain readable and parseable
	local input_file="${TEST_DIR}/logs/vpn-monitor.log"
	local output_file="${TEST_DIR}/anonymized.log"
	create_sample_log_file "$input_file"

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	# Verify line count is preserved
	local input_lines
	input_lines=$(wc -l <"$input_file")
	local output_lines
	output_lines=$(wc -l <"$output_file")
	assert_equal "$input_lines" "$output_lines"
	# Verify timestamp format is preserved
	run grep -E '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]' "$output_file"
	assert_success
	# Verify log level format is preserved
	run grep -E '\[(INFO|WARNING|ERROR)\]' "$output_file"
	assert_success
}
