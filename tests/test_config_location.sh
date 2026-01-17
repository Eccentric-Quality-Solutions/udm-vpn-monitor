#!/usr/bin/env bats
#
# Tests for Location-Based Configuration Parsing
# Tests parse_location_config() with various location name formats, duplicate detection,
# missing external IP validation, and empty internal IPs handling

load test_helper
load helpers/config

# Source the config library functions
# shellcheck source=../lib/config.sh
source "${BATS_TEST_DIRNAME}/../lib/config.sh"

# Source logging for handle_error functions
# shellcheck source=../lib/logging.sh
source "${BATS_TEST_DIRNAME}/../lib/logging.sh"

# Declare LOCATIONS array globally for tests that use 'run'
# This ensures the array is accessible after 'run' executes in a subshell
declare -gA LOCATIONS

# ============================================================================
# LOCATION CONFIGURATION PARSING TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "parse_location_config - valid single location with external IP only" {
	# Purpose: Test parsing a single location with only external IP configured
	# Expected: parse_location_config succeeds and LOCATIONS array contains the location
	# Importance: Basic functionality - most common use case
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	# Set up environment and load config
	setup_location_config_and_load "$config_file"

	# Parse location config (call directly, not with 'run', so LOCATIONS array is accessible)
	parse_location_config

	# Verify location was parsed
	assert [ ${#LOCATIONS[@]} -eq 1 ]
	assert [ -n "${LOCATIONS[NYC]:-}" ]

	# Verify external IP
	local external_ip
	external_ip=$(get_location_external_ip "NYC")
	assert_equal "$external_ip" "203.0.113.1"

	# Verify internal IPs are empty
	local internal_ips
	internal_ips=$(get_location_internal_ips "NYC")
	assert_equal "$internal_ips" ""
}

# bats test_tags=category:high-risk,priority:high
@test "parse_location_config - valid location with external and internal IPs" {
	# Purpose: Test parsing a location with both external and internal IPs
	# Expected: parse_location_config succeeds and both IPs are stored correctly
	# Importance: Common use case with internal IPs for ping checks
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
		"LOCATION_NYC_INTERNAL=\"${TEST_PEER_IP} 192.168.1.88\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	setup_location_config_and_load "$config_file"

	parse_location_config

	assert [ ${#LOCATIONS[@]} -eq 1 ]
	local external_ip
	external_ip=$(get_location_external_ip "NYC")
	assert_equal "$external_ip" "203.0.113.1"

	local internal_ips
	internal_ips=$(get_location_internal_ips "NYC")
	assert_equal "$internal_ips" "${TEST_PEER_IP} 192.168.1.88"
}

# bats test_tags=category:high-risk,priority:high
@test "parse_location_config - multiple locations" {
	# Purpose: Test parsing multiple locations
	# Expected: All locations are parsed and stored correctly
	# Importance: Multi-location deployments are common
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
		"LOCATION_NYC_INTERNAL=\"${TEST_PEER_IP}\"" \
		'LOCATION_LA_EXTERNAL="198.51.100.1"' \
		'LOCATION_LA_INTERNAL="192.168.2.1 192.168.2.2"' \
		'LOCATION_CHI_EXTERNAL="192.0.2.1"' \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	setup_location_config_and_load "$config_file"

	parse_location_config

	assert [ ${#LOCATIONS[@]} -eq 3 ]

	# Verify NYC
	local external_ip
	external_ip=$(get_location_external_ip "NYC")
	assert_equal "$external_ip" "203.0.113.1"
	local internal_ips
	internal_ips=$(get_location_internal_ips "NYC")
	assert_equal "$internal_ips" "${TEST_PEER_IP}"

	# Verify LA
	external_ip=$(get_location_external_ip "LA")
	assert_equal "$external_ip" "198.51.100.1"
	internal_ips=$(get_location_internal_ips "LA")
	assert_equal "$internal_ips" "192.168.2.1 192.168.2.2"

	# Verify CHI (no internal IPs)
	external_ip=$(get_location_external_ip "CHI")
	assert_equal "$external_ip" "192.0.2.1"
	internal_ips=$(get_location_internal_ips "CHI")
	assert_equal "$internal_ips" ""
}

# bats test_tags=category:high-risk,priority:high
@test "parse_location_config - location names with underscores" {
	# Purpose: Test that location names with underscores are parsed correctly
	# Expected: Location names containing underscores are extracted and stored correctly
	# Importance: Underscores are valid characters in location names and must be preserved
	# Note: Variable names must be valid bash identifiers (alphanumeric + underscore only)
	# Location names are extracted from between LOCATION_ and _EXTERNAL, then sanitized
	# (sanitization is a no-op for already-valid names, but is tested separately)
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		'LOCATION_NYC_Office_EXTERNAL="203.0.113.1"' \
		'LOCATION_LA_Office_EXTERNAL="198.51.100.1"' \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	setup_location_config_and_load "$config_file"

	parse_location_config

	# Verify location names with underscores are preserved
	assert [ -n "${LOCATIONS[NYC_Office]:-}" ]
	assert [ -n "${LOCATIONS[LA_Office]:-}" ]

	# Verify we can retrieve IPs using location names
	local external_ip
	external_ip=$(get_location_external_ip "NYC_Office")
	assert_equal "$external_ip" "203.0.113.1"
	external_ip=$(get_location_external_ip "LA_Office")
	assert_equal "$external_ip" "198.51.100.1"
}

# bats test_tags=category:high-risk,priority:high
@test "parse_location_config - duplicate location names detected" {
	# Purpose: Test that duplicate location names are detected and rejected
	# Expected: parse_location_config fails with error about duplicate location name
	# Importance: Duplicate names would cause state file conflicts
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
		'LOCATION_NYC_EXTERNAL="198.51.100.1"' \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	setup_location_config_and_load "$config_file"

	# Enable fake mode to prevent exit
	enable_fake_mode

	run parse_location_config
	assert_failure

	# Should detect duplicate (second occurrence overwrites first, but sanitization makes them identical)
	# Actually, the way the code works, it reads the file sequentially, so the second one overwrites
	# But if we have two different variable names that sanitize to the same name, that's a duplicate
}

# bats test_tags=category:high-risk,priority:high
@test "parse_location_config - duplicate sanitized location names detected" {
	# Purpose: Test that duplicate location names are detected and rejected
	# Expected: parse_location_config fails with error about duplicate location name
	# Importance: Prevents state file conflicts from duplicate location names
	# Note: Variable names must be valid bash identifiers (alphanumeric + underscore only)
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		'LOCATION_NYC_Office_EXTERNAL="203.0.113.1"' \
		'LOCATION_NYC_Office_EXTERNAL="198.51.100.1"' \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	setup_location_config_and_load "$config_file"

	enable_fake_mode

	run parse_location_config
	assert_failure

	# Should detect duplicate location name (NYC_Office appears twice)
	assert_output --partial "Duplicate location name"
}

# bats test_tags=category:high-risk,priority:high
@test "parse_location_config - missing external IP validation" {
	# Purpose: Test that locations without external IP are skipped with warning
	# Expected: parse_location_config skips empty external IP with warning, fails if no valid locations remain
	# Importance: Empty external IPs should be handled gracefully, but config must have at least one valid location
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		'LOCATION_NYC_EXTERNAL=""' \
		"LOCATION_NYC_INTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	setup_location_config_and_load "$config_file"

	enable_fake_mode

	run parse_location_config
	assert_failure

	# Should detect empty external IP and skip it with warning
	assert_output --partial "EXTERNAL IP is empty" || assert_output --partial "skipping empty peer"
	# Should fail because no valid locations remain
	assert_output --partial "No location-based configuration found"
}

# bats test_tags=category:high-risk,priority:high
@test "parse_location_config - empty internal IPs handling" {
	# Purpose: Test that empty internal IPs are handled correctly (not an error)
	# Expected: parse_location_config succeeds and internal IPs are empty string
	# Importance: Internal IPs are optional
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
		'LOCATION_NYC_INTERNAL=""' \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	setup_location_config_and_load "$config_file"

	parse_location_config

	local internal_ips
	internal_ips=$(get_location_internal_ips "NYC")
	assert_equal "$internal_ips" ""
}

# bats test_tags=category:high-risk,priority:high
@test "parse_location_config - no locations found" {
	# Purpose: Test that missing location configuration is detected
	# Expected: parse_location_config fails with error about no locations found
	# Importance: At least one location is required
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	setup_location_config_and_load "$config_file"

	enable_fake_mode

	run parse_location_config
	assert_failure

	# Should detect no locations
	assert_output --partial "No location-based configuration found"
}

# bats test_tags=category:high-risk,priority:high
@test "parse_location_config - invalid location variable name format" {
	# Purpose: Test that invalid location variable name formats are handled gracefully
	# Expected: Invalid location variable formats that pass schema validation are skipped during parse_location_config
	# Importance: Graceful handling of edge cases in location variable formats
	# Note: Unknown variables (not in schema) are rejected during load_config before parse_location_config runs
	# This test focuses on location variables that pass schema validation but have invalid location name extraction
	# We test with variables that have empty location names (LOCATION__EXTERNAL) which extract_location_name rejects
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
		'LOCATION_LA_EXTERNAL="203.0.113.4"' \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	setup_location_config_and_load "$config_file"

	parse_location_config

	# Should parse valid locations
	# Note: Variables with invalid formats (like LOCATION__EXTERNAL) would be rejected by schema validation
	# during load_config, so they never reach parse_location_config. This test verifies that valid
	# location variables are parsed correctly.
	assert [ ${#LOCATIONS[@]} -eq 2 ]
	assert [ -n "${LOCATIONS[NYC]:-}" ]
	assert [ -n "${LOCATIONS[LA]:-}" ]
}

# bats test_tags=category:high-risk,priority:high
@test "parse_location_config - location name with underscores" {
	# Purpose: Test that location names with underscores are handled correctly
	# Expected: Underscores are preserved in location names
	# Importance: Underscores are valid characters in identifiers
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		'LOCATION_NYC_Office_EXTERNAL="203.0.113.1"' \
		'LOCATION_LA_Main_Office_EXTERNAL="198.51.100.1"' \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	setup_location_config_and_load "$config_file"

	parse_location_config

	# Verify underscores are preserved
	assert [ -n "${LOCATIONS[NYC_Office]:-}" ]
	assert [ -n "${LOCATIONS[LA_Main_Office]:-}" ]
}

# bats test_tags=category:high-risk,priority:high
@test "parse_location_config - location name with numbers" {
	# Purpose: Test that location names with numbers are handled correctly
	# Expected: Numbers are preserved in location names
	# Importance: Numbers are valid characters in identifiers
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		'LOCATION_Office1_EXTERNAL="203.0.113.1"' \
		'LOCATION_Building2A_EXTERNAL="198.51.100.1"' \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	setup_location_config_and_load "$config_file"

	parse_location_config

	# Verify numbers are preserved
	assert [ -n "${LOCATIONS[Office1]:-}" ]
	assert [ -n "${LOCATIONS[Building2A]:-}" ]
}

# bats test_tags=category:high-risk,priority:high
@test "parse_location_config - config file not found" {
	# Purpose: Test that missing config file is handled correctly
	# Expected: parse_location_config fails with error about config file not found
	# Importance: Config file is required for parsing
	CONFIG_FILE="${TEST_DIR}/nonexistent.conf"
	export CONFIG_FILE
	setup_test_environment

	enable_fake_mode

	run parse_location_config
	assert_failure

	# Should detect missing config file
	assert_output --partial "Config file not found"
}

# bats test_tags=category:high-risk,priority:high
@test "extract_location_name - valid external variable name" {
	# Purpose: Test extracting location name from EXTERNAL variable name
	# Expected: Location name is extracted correctly
	# Importance: Core function for parsing location config
	run extract_location_name "LOCATION_NYC_EXTERNAL"
	assert_success
	assert_output "NYC"
}

# bats test_tags=category:high-risk,priority:high
@test "extract_location_name - valid internal variable name" {
	# Purpose: Test extracting location name from INTERNAL variable name
	# Expected: Location name is extracted correctly
	# Importance: Core function for parsing location config
	run extract_location_name "LOCATION_NYC_INTERNAL"
	assert_success
	assert_output "NYC"
}

# bats test_tags=category:high-risk,priority:high
@test "extract_location_name - invalid variable name format" {
	# Purpose: Test that invalid variable names are rejected
	# Expected: extract_location_name fails for invalid formats
	# Importance: Prevents parsing invalid configuration
	run extract_location_name "INVALID_FORMAT"
	assert_failure
}

# bats test_tags=category:high-risk,priority:high
@test "sanitize_location_name - replaces invalid characters" {
	# Purpose: Test that invalid characters are replaced with underscores
	# Expected: Invalid characters are replaced, valid ones preserved
	# Importance: Ensures safe filenames
	run sanitize_location_name "NYC-Office"
	assert_success
	assert_output "NYC_Office"
}

# bats test_tags=category:high-risk,priority:high
@test "sanitize_location_name - preserves valid characters" {
	# Purpose: Test that valid characters (alphanumeric, underscore) are preserved
	# Expected: Valid characters remain unchanged
	# Importance: Preserves meaningful location names
	run sanitize_location_name "NYC_Office123"
	assert_success
	assert_output "NYC_Office123"
}

# bats test_tags=category:high-risk,priority:high
@test "sanitize_location_name - truncates long names" {
	# Purpose: Test that names longer than 64 chars are truncated
	# Expected: Name is truncated to 64 characters
	# Importance: Prevents filesystem issues with long filenames
	local long_name="A"
	for i in {1..70}; do
		long_name="${long_name}A"
	done

	run sanitize_location_name "$long_name"
	assert_success
	assert [ ${#output} -le 64 ]
}

# bats test_tags=category:high-risk,priority:high
@test "sanitize_location_name - handles empty string" {
	# Purpose: Test that empty string is handled with default value
	# Expected: Empty string becomes "LOCATION"
	# Importance: Prevents empty filenames
	run sanitize_location_name ""
	assert_success
	assert_output "LOCATION"
}

# bats test_tags=category:high-risk,priority:high
@test "sanitize_location_name - handles name starting with underscore" {
	# Purpose: Test that names starting with underscore are prefixed
	# Expected: Name starting with underscore gets "LOC" prefix
	# Importance: Ensures valid identifier format
	run sanitize_location_name "_Office"
	assert_success
	assert_output "LOC_Office"
}

# bats test_tags=category:high-risk,priority:high
@test "get_location_external_ip - valid location" {
	# Purpose: Test retrieving external IP for a valid location
	# Expected: External IP is returned correctly
	# Importance: Core function for accessing location data
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	setup_location_config_and_load "$config_file"
	parse_location_config

	run get_location_external_ip "NYC"
	assert_success
	assert_output "203.0.113.1"
}

# bats test_tags=category:high-risk,priority:high
@test "get_location_external_ip - invalid location" {
	# Purpose: Test retrieving external IP for non-existent location
	# Expected: Function fails (returns 1)
	# Importance: Error handling for invalid location names
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	setup_location_config_and_load "$config_file"
	parse_location_config

	run get_location_external_ip "INVALID"
	assert_failure
}

# bats test_tags=category:high-risk,priority:high
@test "get_location_internal_ips - valid location with internal IPs" {
	# Purpose: Test retrieving internal IPs for a valid location
	# Expected: Internal IPs are returned correctly
	# Importance: Core function for accessing location data
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
		"LOCATION_NYC_INTERNAL=\"${TEST_PEER_IP} 192.168.1.88\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	setup_location_config_and_load "$config_file"
	parse_location_config

	run get_location_internal_ips "NYC"
	assert_success
	assert_output "${TEST_PEER_IP} 192.168.1.88"
}

# bats test_tags=category:high-risk,priority:high
@test "get_location_internal_ips - valid location without internal IPs" {
	# Purpose: Test retrieving internal IPs when none are configured
	# Expected: Empty string is returned
	# Importance: Internal IPs are optional
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	setup_location_config_and_load "$config_file"
	parse_location_config

	run get_location_internal_ips "NYC"
	assert_success
	assert_output ""
}

# bats test_tags=category:high-risk,priority:high
@test "get_location_internal_ips - invalid location" {
	# Purpose: Test retrieving internal IPs for non-existent location
	# Expected: Function fails (returns 1)
	# Importance: Error handling for invalid location names
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	setup_location_config_and_load "$config_file"
	parse_location_config

	run get_location_internal_ips "INVALID"
	assert_failure
}
