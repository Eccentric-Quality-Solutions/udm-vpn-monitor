#!/usr/bin/env bats
#
# Tests for anonymize-ip-rules.sh script
# Tests IP rules anonymization functionality, IP and interface anonymization, and consistency

load test_helper

# Path to the anonymize-ip-rules script
ANONYMIZE_IP_RULES_SCRIPT="${BATS_TEST_DIRNAME}/../scripts/anonymize-ip-rules.sh"

# Create sample IPv4 routes file with IPs and interfaces
#
# Creates an IPv4 routes file with IP addresses and interface names for testing anonymization.
#
# Arguments:
#   $1: Routes file path
create_sample_ipv4_routes_file() {
	local routes_file="$1"

	mkdir -p "$(dirname "$routes_file")"

	cat >"$routes_file" <<EOF
default via 192.168.1.1 dev eth0
10.0.0.0/8 via 10.0.0.1 dev br0
192.168.1.0/24 dev eth0
172.16.0.0/16 via 172.16.0.1 dev eth1
203.0.113.1 dev wlan0
EOF
}

# Create sample IPv6 routes file with IPs and interfaces
#
# Creates an IPv6 routes file with IPv6 addresses and interface names for testing anonymization.
#
# Arguments:
#   $1: Routes file path
create_sample_ipv6_routes_file() {
	local routes_file="$1"

	mkdir -p "$(dirname "$routes_file")"

	cat >"$routes_file" <<EOF
default via fe80::1 dev eth0
2001:db8::/32 via 2001:db8::1 dev br0
2001:db8:1::/64 dev eth0
fc00::/7 via fc00::1 dev eth1
2001:db8:2::1 dev wlan0
EOF
}

# Create sample mixed routes file with both IPv4 and IPv6
#
# Creates a routes file with both IPv4 and IPv6 addresses for testing anonymization.
#
# Arguments:
#   $1: Routes file path
create_sample_mixed_routes_file() {
	local routes_file="$1"

	mkdir -p "$(dirname "$routes_file")"

	cat >"$routes_file" <<EOF
default via 192.168.1.1 dev eth0
10.0.0.0/8 via 10.0.0.1 dev br0
default via fe80::1 dev eth0
2001:db8::/32 via 2001:db8::1 dev br0
EOF
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh exists and is executable" {
	# Purpose: Test verifies that the anonymize-ip-rules script file exists and has execute permissions
	# Expected: Anonymize-ip-rules script file is present and executable
	# Importance: Ensures the IP rules anonymization script can be run directly for route sanitization
	assert_file_exist "$ANONYMIZE_IP_RULES_SCRIPT"
	assert_file_executable "$ANONYMIZE_IP_RULES_SCRIPT"
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh shows help with --help flag" {
	# Purpose: Test verifies that the anonymize-ip-rules script displays usage information when --help flag is provided
	# Expected: Script outputs usage information including all available options and flags
	# Importance: Ensures users can access help documentation for script usage and available options
	run bash "$ANONYMIZE_IP_RULES_SCRIPT" --help
	assert_success
	assert_output --partial "Usage:"
	assert_output --partial "anonymize-ip-rules.sh"
	assert_output --partial "--input"
	assert_output --partial "--output"
	assert_output --partial "--verbose"
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh shows help with -h flag" {
	# Purpose: Test verifies that the anonymize-ip-rules script displays usage information when -h flag is provided
	# Expected: Script outputs usage information including all available options and flags
	# Importance: Ensures users can access help documentation using the short flag option
	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -h
	assert_success
	assert_output --partial "Usage:"
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh exits with error if input file not found" {
	# Purpose: Test verifies that the anonymize-ip-rules script validates input file existence before processing
	# Expected: Script exits with failure status and displays error message when input file doesn't exist
	# Importance: Prevents script from attempting to anonymize non-existent files and provides clear error feedback
	local input_file="${TEST_DIR}/nonexistent-routes.txt"

	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file"

	assert_failure
	assert_output --partial "Input file not found"
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh exits with error if input file not readable" {
	# Purpose: Test verifies that the anonymize-ip-rules script validates input file readability before processing
	# Expected: Script exits with failure status and displays error message when input file is not readable
	# Importance: Prevents script from attempting to anonymize unreadable files and provides clear error feedback
	local input_file="${TEST_DIR}/routes/routes.txt"
	mkdir -p "$(dirname "$input_file")"
	touch "$input_file"
	chmod 000 "$input_file"

	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file"

	# Restore permissions for cleanup
	chmod 644 "$input_file" || true

	assert_failure
	assert_output --partial "Input file not readable"
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh exits with error if input file not specified" {
	# Purpose: Test verifies that the anonymize-ip-rules script requires input file to be specified
	# Expected: Script exits with failure status and displays error message when input file is missing
	# Importance: Prevents script from running without required input and provides clear error feedback
	run bash "$ANONYMIZE_IP_RULES_SCRIPT"

	assert_failure
	assert_output --partial "Input file is required"
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh anonymizes IPv4 addresses" {
	# Purpose: Test verifies that the anonymize-ip-rules script replaces IP addresses with anonymized versions
	# Expected: Script replaces all IP addresses in routes file with anonymized IPs in 10.x.x.x range
	# Importance: IP anonymization is a core feature for protecting sensitive network information
	local input_file="${TEST_DIR}/routes/ipv4-routes.txt"
	local output_file="${TEST_DIR}/anonymized-routes.txt"
	create_sample_ipv4_routes_file "$input_file"

	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify original IPs are not in output
	refute_file_contains "$output_file" "192.168.1.1"
	refute_file_contains "$output_file" "10.0.0.0"
	refute_file_contains "$output_file" "172.16.0.0"
	refute_file_contains "$output_file" "203.0.113.1"
	# Verify anonymized IPs are in 10.x.x.x range
	run grep -oE '\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b' "$output_file"
	assert_success
	# Verify at least one anonymized IP was found
	assert [ "${#lines[@]}" -gt 0 ]
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh preserves CIDR notation in IP addresses" {
	# Purpose: Test verifies that the anonymize-ip-rules script preserves CIDR notation when anonymizing IPs
	# Expected: Script replaces IP addresses but preserves CIDR notation (e.g., /24)
	# Importance: Preserving CIDR notation maintains the meaning of network ranges in route entries
	local input_file="${TEST_DIR}/routes/ipv4-routes.txt"
	local output_file="${TEST_DIR}/anonymized-routes.txt"
	create_sample_ipv4_routes_file "$input_file"

	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify CIDR notation is preserved (should have /24, /8, /16 in output)
	run grep -E '/(8|16|24)' "$output_file"
	assert_success
	# Verify at least one CIDR notation was found
	assert [ "${#lines[@]}" -gt 0 ]
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh anonymizes interface names" {
	# Purpose: Test verifies that the anonymize-ip-rules script replaces interface names with anonymized versions
	# Expected: Script replaces all interface names in routes with anonymized interface names
	# Importance: Interface anonymization is a core feature for protecting sensitive network topology information
	local input_file="${TEST_DIR}/routes/ipv4-routes.txt"
	local output_file="${TEST_DIR}/anonymized-routes.txt"
	create_sample_ipv4_routes_file "$input_file"

	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify original interface names are not in output (except lo which is preserved)
	refute_file_contains "$output_file" "eth0"
	refute_file_contains "$output_file" "eth1"
	refute_file_contains "$output_file" "br0"
	refute_file_contains "$output_file" "wlan0"
	# Verify anonymized interface names are present (should match interface name pattern after "dev")
	run grep -oE 'dev [a-zA-Z][a-zA-Z0-9_-]+' "$output_file"
	assert_success
	# Verify at least one interface was found
	assert [ "${#lines[@]}" -gt 0 ]
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh preserves loopback interface name" {
	# Purpose: Test verifies that the anonymize-ip-rules script preserves the loopback interface name (lo)
	# Expected: Script keeps "lo" as "lo" instead of anonymizing it
	# Importance: Loopback interface is standard and doesn't reveal sensitive information
	local input_file="${TEST_DIR}/routes/ipv4-routes.txt"
	local output_file="${TEST_DIR}/anonymized-routes.txt"
	mkdir -p "$(dirname "$input_file")"
	cat >"$input_file" <<EOF
127.0.0.1 dev lo
default via 192.168.1.1 dev eth0
EOF

	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify lo is preserved
	assert_file_contains "$output_file" "dev lo"
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh anonymizes IPv6 addresses" {
	# Purpose: Test verifies that the anonymize-ip-rules script replaces IPv6 addresses with anonymized versions
	# Expected: Script replaces all IPv6 addresses in routes file with anonymized IPv6s in fc00::/7 range
	# Importance: IPv6 anonymization is a core feature for protecting sensitive network information
	local input_file="${TEST_DIR}/routes/ipv6-routes.txt"
	local output_file="${TEST_DIR}/anonymized-routes.txt"
	create_sample_ipv6_routes_file "$input_file"

	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify original IPv6 addresses are not in output
	refute_file_contains "$output_file" "fe80::1"
	refute_file_contains "$output_file" "2001:db8::"
	refute_file_contains "$output_file" "fc00::"
	# Verify anonymized IPv6 addresses are in fc00::/7 range
	run grep -oE 'fc00:[0-9a-fA-F:]+' "$output_file"
	assert_success
	# Verify at least one anonymized IPv6 was found
	assert [ "${#lines[@]}" -gt 0 ]
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh preserves IPv6 CIDR notation" {
	# Purpose: Test verifies that the anonymize-ip-rules script preserves CIDR notation when anonymizing IPv6s
	# Expected: Script replaces IPv6 addresses but preserves CIDR notation (e.g., /32, /64)
	# Importance: Preserving CIDR notation maintains the meaning of network ranges in route entries
	local input_file="${TEST_DIR}/routes/ipv6-routes.txt"
	local output_file="${TEST_DIR}/anonymized-routes.txt"
	create_sample_ipv6_routes_file "$input_file"

	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify CIDR notation is preserved (should have /32, /64, /7 in output)
	run grep -E '/(7|32|64)' "$output_file"
	assert_success
	# Verify at least one CIDR notation was found
	assert [ "${#lines[@]}" -gt 0 ]
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh handles mixed IPv4 and IPv6 routes" {
	# Purpose: Test verifies that the anonymize-ip-rules script handles both IPv4 and IPv6 addresses in same file
	# Expected: Script anonymizes both IPv4 and IPv6 addresses correctly in mixed route files
	# Importance: Real-world route files may contain both IPv4 and IPv6 routes
	local input_file="${TEST_DIR}/routes/mixed-routes.txt"
	local output_file="${TEST_DIR}/anonymized-routes.txt"
	create_sample_mixed_routes_file "$input_file"

	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify original IPv4 IPs are not in output
	refute_file_contains "$output_file" "192.168.1.1"
	refute_file_contains "$output_file" "10.0.0.0"
	# Verify original IPv6 IPs are not in output
	refute_file_contains "$output_file" "fe80::1"
	refute_file_contains "$output_file" "2001:db8::"
	# Verify anonymized IPv4 IPs are in 10.x.x.x range
	run grep -oE '\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b' "$output_file"
	assert_success
	# Verify anonymized IPv6 IPs are in fc00::/7 range
	run grep -oE 'fc00:[0-9a-fA-F:]+' "$output_file"
	assert_success
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh produces consistent anonymization" {
	# Purpose: Test verifies that the anonymize-ip-rules script produces consistent anonymization across multiple runs
	# Expected: Script produces identical anonymized output when run multiple times on the same input
	# Importance: Consistency ensures that anonymized files can be compared and analyzed reliably
	local input_file="${TEST_DIR}/routes/ipv4-routes.txt"
	local output_file1="${TEST_DIR}/anonymized-routes1.txt"
	local output_file2="${TEST_DIR}/anonymized-routes2.txt"
	create_sample_ipv4_routes_file "$input_file"

	# Run anonymization twice
	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file" -o "$output_file1"
	assert_success

	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file" -o "$output_file2"
	assert_success

	# Verify both output files exist
	assert_file_exist "$output_file1"
	assert_file_exist "$output_file2"

	# Verify outputs are identical
	run diff "$output_file1" "$output_file2"
	assert_success
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh preserves route structure" {
	# Purpose: Test verifies that the anonymize-ip-rules script preserves the structure of route entries
	# Expected: Script maintains route entry format (default via, dev, etc.) while anonymizing IPs and interfaces
	# Importance: Preserving structure ensures anonymized routes remain readable and useful
	local input_file="${TEST_DIR}/routes/ipv4-routes.txt"
	local output_file="${TEST_DIR}/anonymized-routes.txt"
	create_sample_ipv4_routes_file "$input_file"

	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify route structure keywords are preserved
	assert_file_contains "$output_file" "default"
	assert_file_contains "$output_file" "via"
	assert_file_contains "$output_file" "dev"
	# Verify number of lines is preserved (structure maintained)
	local input_lines
	local output_lines
	input_lines=$(wc -l <"$input_file")
	output_lines=$(wc -l <"$output_file")
	assert_equal "$input_lines" "$output_lines"
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh handles empty input file" {
	# Purpose: Test verifies that the anonymize-ip-rules script handles empty input files gracefully
	# Expected: Script processes empty file without errors and produces empty output
	# Importance: Ensures script robustness when processing edge cases
	local input_file="${TEST_DIR}/routes/empty-routes.txt"
	local output_file="${TEST_DIR}/anonymized-routes.txt"
	mkdir -p "$(dirname "$input_file")"
	touch "$input_file"

	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify output file is empty
	assert [ ! -s "$output_file" ]
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh outputs to stdout when output file not specified" {
	# Purpose: Test verifies that the anonymize-ip-rules script outputs to stdout when output file is not specified
	# Expected: Script writes anonymized routes to stdout instead of a file
	# Importance: Allows piping anonymized output to other commands or tools
	local input_file="${TEST_DIR}/routes/ipv4-routes.txt"
	create_sample_ipv4_routes_file "$input_file"

	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file"

	assert_success
	# Verify output contains anonymized IPs (10.x.x.x range)
	assert_output --regexp '10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
	# Verify original IPs are not in output
	refute_output --partial "192.168.1.1"
	refute_output --partial "10.0.0.0"
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh prevents overwriting input file" {
	# Purpose: Test verifies that the anonymize-ip-rules script prevents overwriting the input file
	# Expected: Script exits with error when output file is the same as input file
	# Importance: Prevents accidental data loss when anonymizing files
	local input_file="${TEST_DIR}/routes/ipv4-routes.txt"
	create_sample_ipv4_routes_file "$input_file"

	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file" -o "$input_file"

	assert_failure
	assert_output --partial "Output file cannot be the same as input file"
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh verbose mode shows progress messages" {
	# Purpose: Test verifies that the anonymize-ip-rules script displays progress messages in verbose mode
	# Expected: Script outputs progress messages indicating anonymization steps when -v flag is provided
	# Importance: Verbose mode helps users understand script progress and troubleshoot anonymization issues
	local input_file="${TEST_DIR}/routes/ipv4-routes.txt"
	local output_file="${TEST_DIR}/anonymized-routes.txt"
	create_sample_ipv4_routes_file "$input_file"

	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file" -o "$output_file" -v

	assert_success
	# Verify verbose messages are present
	assert_output --partial "Extracting IPv4 addresses"
	assert_output --partial "Extracting interface names"
	assert_output --partial "Building replacement scripts"
	assert_output --partial "Anonymizing IP rules file"
	assert_output --partial "Anonymization complete"
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh handles routes without gateway" {
	# Purpose: Test verifies that the anonymize-ip-rules script handles routes without gateway (directly connected)
	# Expected: Script anonymizes IPs and interfaces in routes that don't have a "via" gateway
	# Importance: Real-world routes may be directly connected without a gateway
	local input_file="${TEST_DIR}/routes/ipv4-routes.txt"
	local output_file="${TEST_DIR}/anonymized-routes.txt"
	mkdir -p "$(dirname "$input_file")"
	cat >"$input_file" <<EOF
192.168.1.0/24 dev eth0
10.0.0.0/8 dev br0
EOF

	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify original IPs are not in output
	refute_file_contains "$output_file" "192.168.1.0"
	refute_file_contains "$output_file" "10.0.0.0"
	# Verify anonymized IPs are present
	run grep -oE '\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b' "$output_file"
	assert_success
	# Verify "dev" keyword is preserved
	assert_file_contains "$output_file" "dev"
}

# bats test_tags=category:unit
@test "anonymize-ip-rules.sh handles default route" {
	# Purpose: Test verifies that the anonymize-ip-rules script handles default route entries correctly
	# Expected: Script anonymizes gateway IP and interface in default route while preserving "default" keyword
	# Importance: Default routes are common and important for network configuration
	local input_file="${TEST_DIR}/routes/ipv4-routes.txt"
	local output_file="${TEST_DIR}/anonymized-routes.txt"
	mkdir -p "$(dirname "$input_file")"
	cat >"$input_file" <<EOF
default via 192.168.1.1 dev eth0
EOF

	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify "default" keyword is preserved
	assert_file_contains "$output_file" "default"
	# Verify original gateway IP is not in output
	refute_file_contains "$output_file" "192.168.1.1"
	# Verify anonymized gateway IP is present
	run grep -oE '\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b' "$output_file"
	assert_success
}
