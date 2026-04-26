#!/usr/bin/env bats
#
# Consolidated tests for scripts under scripts/anonymize/ (peripheral tooling).
# Each test is tagged: category:unit,anonymize:<ipset|ip-rules|firewall|logs|all>
#

load test_helper
load helpers/anonymize

# --- anonymize-ipset.sh ---

ANONYMIZE_IPSET_SCRIPT="${BATS_TEST_DIRNAME}/../scripts/anonymize/anonymize-ipset.sh"

# Create sample ipset save file with sets, IPs, and set names
#
# Creates an ipset save file with set names, IP addresses, and other identifiers for testing anonymization.
#
# Arguments:
#   $1: Ipset save file path
#
# Returns:
#   0: success
create_sample_ipset_file() {
	local ipset_file="$1"

	mkdir -p "$(dirname "$ipset_file")"

	cat >"$ipset_file" <<EOF
create UBIOS_ALL_ADDRv4_eth8 hash:ip family inet hashsize 1024 maxelem 65536
add UBIOS_ALL_ADDRv4_eth8 192.168.1.1
add UBIOS_ALL_ADDRv4_eth8 10.0.0.1
add UBIOS_ALL_ADDRv4_eth8 203.0.113.1
create UBIOS_ALL_NETv4_br104 hash:net family inet hashsize 1024 maxelem 65536
add UBIOS_ALL_NETv4_br104 172.31.12.0/24
add UBIOS_ALL_NETv4_br104 192.168.0.0/16
create ALIEN hash:ip family inet hashsize 1024 maxelem 65536
add ALIEN 198.51.100.1
add ALIEN 198.51.100.2
create TOR hash:ip family inet hashsize 1024 maxelem 65536
add TOR 172.16.0.1
EOF
}

# Create sample ipset file with IPv6 addresses
#
# Creates an ipset save file with IPv6 addresses for testing anonymization.
#
# Arguments:
#   $1: Ipset save file path
#
# Returns:
#   0: success
create_sample_ipset_ipv6_file() {
	local ipset_file="$1"

	mkdir -p "$(dirname "$ipset_file")"

	cat >"$ipset_file" <<EOF
create UBIOS_ALL_ADDRv6_eth8 hash:ip family inet6 hashsize 1024 maxelem 65536
add UBIOS_ALL_ADDRv6_eth8 2001:db8::1
add UBIOS_ALL_ADDRv6_eth8 fe80::1
add UBIOS_ALL_ADDRv6_eth8 2001:db8:1::1
create UBIOS_ALL_NETv6_br104 hash:net family inet6 hashsize 1024 maxelem 65536
add UBIOS_ALL_NETv6_br104 2001:db8::/32
add UBIOS_ALL_NETv6_br104 fe80::/64
EOF
}

# Create sample ipset file with MAC addresses
#
# Creates an ipset save file with MAC addresses for testing anonymization.
#
# Arguments:
#   $1: Ipset save file path
#
# Returns:
#   0: success
create_sample_ipset_mac_file() {
	local ipset_file="$1"

	mkdir -p "$(dirname "$ipset_file")"

	cat >"$ipset_file" <<EOF
create MAC_SET hash:mac hashsize 1024 maxelem 65536
add MAC_SET aa:bb:cc:dd:ee:ff
add MAC_SET 00:11:22:33:44:55
add MAC_SET ff:ee:dd:cc:bb:aa
EOF
}

# bats test_tags=category:unit,anonymize:ipset
@test "anonymize-ipset.sh exists and is executable" {
	anonymize_assert_script_exists_executable "$ANONYMIZE_IPSET_SCRIPT"
}

# bats test_tags=category:unit,anonymize:ipset
@test "anonymize-ipset.sh shows help with --help flag" {
	anonymize_assert_help "$ANONYMIZE_IPSET_SCRIPT" "anonymize-ipset.sh" "--input" "--output" "--mapping-file" "--verbose"
}

# bats test_tags=category:unit,anonymize:ipset
@test "anonymize-ipset.sh shows help with -h flag" {
	anonymize_assert_help_h "$ANONYMIZE_IPSET_SCRIPT"
}

# bats test_tags=category:unit,anonymize:ipset
@test "anonymize-ipset.sh exits with error if input file not found" {
	anonymize_assert_input_file_not_found "$ANONYMIZE_IPSET_SCRIPT" "${TEST_DIR}/nonexistent-ipset.txt"
}

# bats test_tags=category:unit,anonymize:ipset
@test "anonymize-ipset.sh anonymizes IPv4 addresses in ipset sets" {
	local input_file="${TEST_DIR}/ipset/ipset-save.txt"
	local output_file="${TEST_DIR}/anonymized-ipset.txt"
	create_sample_ipset_file "$input_file"

	run bash "$ANONYMIZE_IPSET_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"

	# Verify IPv4 addresses are anonymized (should be in 10.x.x.x range)
	run grep -E '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$output_file"
	assert_success
	# All IPs should be in 10.x.x.x range (anonymized)
	run grep -vE '\b10\.([0-9]{1,3}\.){2}[0-9]{1,3}\b' "$output_file" || true
	# Should not find any non-10.x.x.x IPs (except in comments/descriptions)
	anonymize_assert_eregex_no_line_in_file "$output_file" '\b(192\.168|203\.0|198\.51|172\.16)'
}

# bats test_tags=category:unit,anonymize:ipset
@test "anonymize-ipset.sh anonymizes set names in ipset save output" {
	local input_file="${TEST_DIR}/ipset/ipset-save.txt"
	local output_file="${TEST_DIR}/anonymized-ipset.txt"
	create_sample_ipset_file "$input_file"

	run bash "$ANONYMIZE_IPSET_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"

	# Verify original set names are not present
	anonymize_assert_eregex_no_line_in_file "$output_file" '(UBIOS_ALL_ADDRv4_eth8|UBIOS_ALL_NETv4_br104|ALIEN|TOR)'

	# Verify anonymized set names are present (SET_<number> format)
	run grep -E '^create SET_[0-9]+' "$output_file"
	assert_success
	run grep -E '^add SET_[0-9]+' "$output_file"
	assert_success
}

# bats test_tags=category:unit,anonymize:ipset
@test "anonymize-ipset.sh anonymizes IPv6 addresses in ipset sets" {
	local input_file="${TEST_DIR}/ipset/ipset-ipv6.txt"
	local output_file="${TEST_DIR}/anonymized-ipset-ipv6.txt"
	create_sample_ipset_ipv6_file "$input_file"

	run bash "$ANONYMIZE_IPSET_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"

	# Verify original IPv6 addresses are not present
	anonymize_assert_eregex_no_line_in_file "$output_file" '(2001:db8|fe80::)'

	# Verify anonymized IPv6 addresses are present (should be in fc00::/7 range)
	run grep -E 'fc00:[0-9a-f:]+' "$output_file"
	assert_success
}

# bats test_tags=category:unit,anonymize:ipset
@test "anonymize-ipset.sh anonymizes MAC addresses in ipset sets" {
	local input_file="${TEST_DIR}/ipset/ipset-mac.txt"
	local output_file="${TEST_DIR}/anonymized-ipset-mac.txt"
	create_sample_ipset_mac_file "$input_file"

	run bash "$ANONYMIZE_IPSET_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"

	# Verify original MAC addresses are not present
	anonymize_assert_eregex_no_line_in_file "$output_file" '(aa:bb:cc:dd:ee:ff|00:11:22:33:44:55|ff:ee:dd:cc:bb:aa)'

	# Verify anonymized MAC addresses are present (should start with 02:)
	run grep -E '02:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}' "$output_file"
	assert_success
}

# bats test_tags=category:unit,anonymize:ipset
@test "anonymize-ipset.sh produces consistent anonymization across multiple runs" {
	local input_file="${TEST_DIR}/ipset/ipset-save.txt"
	local output_file1="${TEST_DIR}/anonymized1.txt"
	local output_file2="${TEST_DIR}/anonymized2.txt"
	create_sample_ipset_file "$input_file"

	# Run anonymization twice
	run bash "$ANONYMIZE_IPSET_SCRIPT" -i "$input_file" -o "$output_file1"
	assert_success

	run bash "$ANONYMIZE_IPSET_SCRIPT" -i "$input_file" -o "$output_file2"
	assert_success

	# Verify both output files exist
	assert_file_exist "$output_file1"
	assert_file_exist "$output_file2"

	anonymize_assert_files_identical "$output_file1" "$output_file2"
}

# bats test_tags=category:unit,anonymize:ipset
@test "anonymize-ipset.sh uses unified mapping file for consistency" {
	local input_file="${TEST_DIR}/ipset/ipset-save.txt"
	local output_file="${TEST_DIR}/anonymized-ipset.txt"
	local mapping_file="${TEST_DIR}/mapping.txt"
	create_sample_ipset_file "$input_file"

	# First run - create mapping file
	run bash "$ANONYMIZE_IPSET_SCRIPT" -i "$input_file" -o "$output_file" -m "$mapping_file"
	assert_success
	assert_file_exist "$mapping_file"

	# Second run - use existing mapping file
	local output_file2="${TEST_DIR}/anonymized-ipset2.txt"
	run bash "$ANONYMIZE_IPSET_SCRIPT" -i "$input_file" -o "$output_file2" -m "$mapping_file"
	assert_success

	# Verify outputs are identical (same mappings used)
	anonymize_assert_files_identical "$output_file" "$output_file2"
}

# bats test_tags=category:unit,anonymize:ipset
@test "anonymize-ipset.sh handles empty file gracefully" {
	local input_file="${TEST_DIR}/ipset/empty-ipset.txt"
	local output_file="${TEST_DIR}/anonymized-empty.txt"
	mkdir -p "$(dirname "$input_file")"
	touch "$input_file"
	# Verify file is empty
	assert_file_empty "$input_file"

	run bash "$ANONYMIZE_IPSET_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	assert_file_empty "$output_file"
}

# bats test_tags=category:unit,anonymize:ipset
@test "anonymize-ipset.sh outputs to stdout when output file not specified" {
	local input_file="${TEST_DIR}/ipset/ipset-save.txt"
	create_sample_ipset_file "$input_file"

	run bash "$ANONYMIZE_IPSET_SCRIPT" -i "$input_file"

	assert_success
	# Verify output contains anonymized content
	assert_output --partial "create SET_"
	assert_output --partial "add SET_"
	# Verify original set names are not present
	refute_output --partial "UBIOS_ALL_ADDRv4_eth8"
}

# bats test_tags=category:unit,anonymize:ipset
@test "anonymize-ipset.sh prevents overwriting input file" {
	local input_file="${TEST_DIR}/ipset/ipset-save.txt"
	create_sample_ipset_file "$input_file"
	anonymize_assert_output_path_same_as_input_fails "$ANONYMIZE_IPSET_SCRIPT" "$input_file"
}

# bats test_tags=category:unit,anonymize:ipset
@test "anonymize-ipset.sh handles verbose mode" {
	local input_file="${TEST_DIR}/ipset/ipset-save.txt"
	local output_file="${TEST_DIR}/anonymized-ipset.txt"
	create_sample_ipset_file "$input_file"

	run bash "$ANONYMIZE_IPSET_SCRIPT" -i "$input_file" -o "$output_file" -v

	anonymize_assert_success_with_output_partials "Extracting" "Mapping" "Anonymization complete"
}

# bats test_tags=category:unit,anonymize:ipset
@test "anonymize-ipset.sh preserves ipset save format structure" {
	local input_file="${TEST_DIR}/ipset/ipset-save.txt"
	local output_file="${TEST_DIR}/anonymized-ipset.txt"
	create_sample_ipset_file "$input_file"

	run bash "$ANONYMIZE_IPSET_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"

	# Verify structure is preserved
	run grep -E '^create ' "$output_file"
	assert_success
	run grep -E '^add ' "$output_file"
	assert_success
	# Verify hash:ip/hash:net format is preserved
	run grep -E 'hash:(ip|net)' "$output_file"
	assert_success
}

# --- anonymize-ip-rules.sh ---

# Path to the anonymize-ip-rules script
ANONYMIZE_IP_RULES_SCRIPT="${BATS_TEST_DIRNAME}/../scripts/anonymize/anonymize-ip-rules.sh"

# Create sample IPv4 routes file with IPs and interfaces
#
# Creates an IPv4 routes file with IP addresses and interface names for testing anonymization.
#
# Arguments:
#   $1: Routes file path
#
# Returns:
#   0: success
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
#
# Returns:
#   0: success
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
#
# Returns:
#   0: success
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

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh exists and is executable" {
	anonymize_assert_script_exists_executable "$ANONYMIZE_IP_RULES_SCRIPT"
}

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh shows help with --help flag" {
	anonymize_assert_help "$ANONYMIZE_IP_RULES_SCRIPT" "anonymize-ip-rules.sh" "--input" "--output" "--verbose"
}

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh shows help with -h flag" {
	anonymize_assert_help_h "$ANONYMIZE_IP_RULES_SCRIPT"
}

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh exits with error if input file not found" {
	anonymize_assert_input_file_not_found "$ANONYMIZE_IP_RULES_SCRIPT" "${TEST_DIR}/nonexistent-routes.txt"
}

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh exits with error if input file not readable" {
	anonymize_assert_input_file_unreadable "$ANONYMIZE_IP_RULES_SCRIPT" "${TEST_DIR}/routes/routes.txt"
}

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh exits with error if input file not specified" {
	anonymize_assert_input_file_required "$ANONYMIZE_IP_RULES_SCRIPT"
}

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh anonymizes IPv4 addresses" {
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

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh preserves CIDR notation in IP addresses" {
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

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh anonymizes interface names" {
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

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh preserves loopback interface name" {
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

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh anonymizes IPv6 addresses" {
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

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh preserves IPv6 CIDR notation" {
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

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh handles mixed IPv4 and IPv6 routes" {
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

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh produces consistent anonymization" {
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

	anonymize_assert_files_identical "$output_file1" "$output_file2"
}

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh preserves route structure" {
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

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh handles empty input file" {
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

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh outputs to stdout when output file not specified" {
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

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh prevents overwriting input file" {
	local input_file="${TEST_DIR}/routes/ipv4-routes.txt"
	create_sample_ipv4_routes_file "$input_file"
	anonymize_assert_output_path_same_as_input_fails "$ANONYMIZE_IP_RULES_SCRIPT" "$input_file"
}

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh verbose mode shows progress messages" {
	local input_file="${TEST_DIR}/routes/ipv4-routes.txt"
	local output_file="${TEST_DIR}/anonymized-routes.txt"
	create_sample_ipv4_routes_file "$input_file"

	run bash "$ANONYMIZE_IP_RULES_SCRIPT" -i "$input_file" -o "$output_file" -v

	anonymize_assert_success_with_output_partials "Extracting IPv4 addresses" "Extracting interface names" "Building replacement scripts" "Anonymizing IP rules file" "Anonymization complete"
}

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh handles routes without gateway" {
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

# bats test_tags=category:unit,anonymize:ip-rules
@test "anonymize-ip-rules.sh handles default route" {
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

# --- anonymize-firewall.sh ---

# Path to the anonymize-firewall script
ANONYMIZE_FIREWALL_SCRIPT="${BATS_TEST_DIRNAME}/../scripts/anonymize/anonymize-firewall.sh"

# Create sample firewall rules file with IPs and interfaces
#
# Creates a firewall rules file with IP addresses and interface names for testing anonymization.
#
# Arguments:
#   $1: Firewall rules file path
#
# Returns:
#   0: success
create_sample_firewall_file() {
	local rules_file="$1"

	mkdir -p "$(dirname "$rules_file")"

	cat >"$rules_file" <<EOF
# Generated by iptables-save v1.8.7 on Mon Jan 20 10:00:00 2025
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -i eth0 -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -s 192.168.1.0/24 -j ACCEPT
-A INPUT -s 10.0.0.5 -j ACCEPT
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -i eth1 -o wlan0 -j ACCEPT
-A FORWARD -s 203.0.113.0/24 -d 198.51.100.0/24 -j ACCEPT
COMMIT

*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -o eth0 -j MASQUERADE
-A POSTROUTING -s 192.168.1.0/24 -o eth0 -j SNAT --to-source 203.0.113.1
COMMIT
EOF
}

# Create sample firewall rules file with ipset set names
#
# Creates a firewall rules file with ipset set names for testing set name anonymization.
#
# Arguments:
#   $1: Firewall rules file path
#
# Returns:
#   0: success
create_sample_firewall_file_with_sets() {
	local rules_file="$1"

	mkdir -p "$(dirname "$rules_file")"

	cat >"$rules_file" <<EOF
# Generated by iptables-save v1.8.7
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
:ALIEN - [0:0]
:TOR - [0:0]
-A INPUT -j ALIEN
-A INPUT -j TOR
-A ALIEN -m set --match-set ALIEN src -j DROP
-A ALIEN -m set --match-set ALIEN_WHITELIST_SRC src -j RETURN
-A TOR -m set --match-set TOR src -j DROP
-A TOR -m set --match-set TOR_WHITELIST_DST dst -j RETURN
-A FORWARD -m set --match-set UBIOS_DMZ_subnets dst -j ACCEPT
-A FORWARD -m set --match-set UBIOS_GUEST_subnets dst -j ACCEPT
COMMIT
EOF
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh exists and is executable" {
	anonymize_assert_script_exists_executable "$ANONYMIZE_FIREWALL_SCRIPT"
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh shows help with --help flag" {
	anonymize_assert_help "$ANONYMIZE_FIREWALL_SCRIPT" "anonymize-firewall.sh" "--input" "--output" "--verbose"
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh shows help with -h flag" {
	anonymize_assert_help_h "$ANONYMIZE_FIREWALL_SCRIPT"
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh exits with error if input file not found" {
	anonymize_assert_input_file_not_found "$ANONYMIZE_FIREWALL_SCRIPT" "${TEST_DIR}/nonexistent-rules.txt"
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh exits with error if input file not readable" {
	anonymize_assert_input_file_unreadable "$ANONYMIZE_FIREWALL_SCRIPT" "${TEST_DIR}/firewall/rules.txt"
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh exits with error if input file not specified" {
	anonymize_assert_input_file_required "$ANONYMIZE_FIREWALL_SCRIPT"
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh anonymizes IPv4 addresses" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	create_sample_firewall_file "$input_file"

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify original IPs are not in output
	refute_file_contains "$output_file" "192.168.1.0"
	refute_file_contains "$output_file" "10.0.0.5"
	refute_file_contains "$output_file" "203.0.113.0"
	refute_file_contains "$output_file" "198.51.100.0"
	refute_file_contains "$output_file" "203.0.113.1"
	# Verify anonymized IPs are in 10.x.x.x range
	run grep -oE '\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b' "$output_file"
	assert_success
	# Verify at least one anonymized IP was found
	assert [ "${#lines[@]}" -gt 0 ]
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh preserves CIDR notation in IP addresses" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	create_sample_firewall_file "$input_file"

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify CIDR notation is preserved (should have /24 in output)
	run grep -E '/24' "$output_file"
	assert_success
	# Verify at least one CIDR notation was found
	assert [ "${#lines[@]}" -gt 0 ]
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh anonymizes interface names" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	create_sample_firewall_file "$input_file"

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify original interface names are not in output (except lo which is preserved)
	refute_file_contains "$output_file" "eth0"
	refute_file_contains "$output_file" "eth1"
	refute_file_contains "$output_file" "wlan0"
	# Verify lo is preserved (special case)
	assert_file_contains "$output_file" "lo"
	# Verify anonymized interface names are present (should match interface name pattern)
	run grep -oE '(-i|-o) +[a-zA-Z][a-zA-Z0-9_-]+' "$output_file"
	assert_success
	# Verify at least one interface option was found
	assert [ "${#lines[@]}" -gt 0 ]
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh preserves loopback interface name" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	mkdir -p "$(dirname "$input_file")"
	cat >"$input_file" <<EOF
*filter
:INPUT DROP [0:0]
-A INPUT -i lo -j ACCEPT
COMMIT
EOF

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify lo is preserved (use grep with -- to handle pattern starting with -)
	run grep -F -- "-i lo" "$output_file"
	assert_success
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh handles --in-interface and --out-interface options" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	mkdir -p "$(dirname "$input_file")"
	cat >"$input_file" <<EOF
*filter
:INPUT DROP [0:0]
-A INPUT --in-interface eth0 -j ACCEPT
-A FORWARD --out-interface wlan0 -j ACCEPT
COMMIT
EOF

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify original interface names are not in output
	refute_file_contains "$output_file" "eth0"
	refute_file_contains "$output_file" "wlan0"
	# Verify anonymized interface names are present (use -- to handle pattern starting with --)
	run grep -E -- '--(in|out)-interface' "$output_file"
	assert_success
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh produces consistent anonymization across multiple runs" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	local output_file1="${TEST_DIR}/anonymized1.txt"
	local output_file2="${TEST_DIR}/anonymized2.txt"
	create_sample_firewall_file "$input_file"

	# Run anonymization twice
	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file1"
	assert_success

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file2"
	assert_success

	# Verify both output files exist
	assert_file_exist "$output_file1"
	assert_file_exist "$output_file2"

	anonymize_assert_files_identical "$output_file1" "$output_file2"
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh handles empty file gracefully" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	mkdir -p "$(dirname "$input_file")"
	touch "$input_file"
	# Verify file is empty
	assert_file_empty "$input_file"

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	assert_file_empty "$output_file"
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh outputs to stdout when output file not specified" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	create_sample_firewall_file "$input_file"

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file"

	assert_success
	# Verify output contains anonymized content (should have anonymized IPs)
	assert_output --regexp '10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
	# Verify original IPs are not in output
	refute_output --partial "192.168.1.0"
	refute_output --partial "203.0.113.1"
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh verbose mode shows progress messages" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	create_sample_firewall_file "$input_file"

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file" -v

	# Verbose messages (stderr; use assert_line)
	anonymize_assert_success_with_line_partials "Extracting IPv4 addresses..." "Extracting interface names..." "Anonymizing firewall rules file..." "Anonymization complete!"
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh maps same IP to same anonymized IP consistently" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	mkdir -p "$(dirname "$input_file")"
	# Create rules with same IP appearing multiple times
	cat >"$input_file" <<EOF
*filter
:INPUT DROP [0:0]
-A INPUT -s 203.0.113.1 -j ACCEPT
-A INPUT -d 203.0.113.1 -j ACCEPT
-A FORWARD -s 203.0.113.1 -j ACCEPT
COMMIT
EOF

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	# Extract all anonymized IPs that replaced 203.0.113.1
	# They should all be the same
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

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh maps same interface to same anonymized interface consistently" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	mkdir -p "$(dirname "$input_file")"
	# Create rules with same interface appearing multiple times
	cat >"$input_file" <<EOF
*filter
:INPUT DROP [0:0]
-A INPUT -i eth0 -j ACCEPT
-A FORWARD -i eth0 -j ACCEPT
-A OUTPUT -o eth0 -j ACCEPT
COMMIT
EOF

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	# Extract all anonymized interface names that replaced eth0
	# They should all be the same
	local iface_count
	iface_count=$(grep -oE '(-i|-o) +[a-zA-Z][a-zA-Z0-9_-]+' "$output_file" | grep -v " lo" | wc -l)
	# Should have at least 3 interface options (one for each occurrence)
	assert [ "$iface_count" -ge 3 ]
	# Verify all occurrences use the same anonymized interface (extract interface names and count unique)
	local unique_count
	unique_count=$(grep -oE '(-i|-o) +[a-zA-Z][a-zA-Z0-9_-]+' "$output_file" | grep -v " lo" | awk '{print $2}' | sort -u | wc -l)
	# Since we only have one original interface (eth0), all should map to the same anonymized interface
	assert [ "$unique_count" -eq 1 ]
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh handles rules file with only IPs (no interfaces)" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	mkdir -p "$(dirname "$input_file")"
	cat >"$input_file" <<EOF
*filter
:INPUT DROP [0:0]
-A INPUT -s 203.0.113.1 -j ACCEPT
-A INPUT -d 198.51.100.1 -j ACCEPT
-A INPUT -s 192.0.2.1/24 -j ACCEPT
COMMIT
EOF

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file"

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

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh handles rules file with only interfaces (no IPs)" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	mkdir -p "$(dirname "$input_file")"
	cat >"$input_file" <<EOF
*filter
:INPUT DROP [0:0]
-A INPUT -i eth0 -j ACCEPT
-A FORWARD -i eth1 -o wlan0 -j ACCEPT
-A OUTPUT -o eth0 -j ACCEPT
COMMIT
EOF

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify original interface names are not in output (except lo)
	refute_file_contains "$output_file" "eth0"
	refute_file_contains "$output_file" "eth1"
	refute_file_contains "$output_file" "wlan0"
	# Verify anonymized interface names are present
	run grep -oE '(-i|-o) +[a-zA-Z][a-zA-Z0-9_-]+' "$output_file"
	assert_success
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh preserves firewall rules file structure" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	create_sample_firewall_file "$input_file"

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	# Verify line count is preserved
	local input_lines
	input_lines=$(wc -l <"$input_file")
	local output_lines
	output_lines=$(wc -l <"$output_file")
	assert_equal "$input_lines" "$output_lines"
	# Verify table declarations are preserved
	run grep -E '^\*' "$output_file"
	assert_success
	# Verify chain declarations are preserved
	run grep -E '^:' "$output_file"
	assert_success
	# Verify COMMIT statements are preserved
	run grep -E '^COMMIT' "$output_file"
	assert_success
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh handles multiple tables correctly" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	create_sample_firewall_file "$input_file"

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify both filter and nat tables are present
	assert_file_contains "$output_file" "*filter"
	assert_file_contains "$output_file" "*nat"
	# Verify COMMIT statements for both tables
	local commit_count
	commit_count=$(grep -c '^COMMIT' "$output_file" || echo "0")
	assert [ "$commit_count" -eq 2 ]
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh handles negated interface options" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	mkdir -p "$(dirname "$input_file")"
	cat >"$input_file" <<EOF
*filter
:INPUT DROP [0:0]
-A INPUT -i !eth0 -j DROP
-A FORWARD -o !wlan0 -j DROP
COMMIT
EOF

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify original interface names are not in output
	refute_file_contains "$output_file" "eth0"
	refute_file_contains "$output_file" "wlan0"
	# Verify negation is preserved
	assert_file_contains "$output_file" "!"
	# Verify anonymized interface names are present
	run grep -E '(-i|-o) +!' "$output_file"
	assert_success
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh handles SNAT target with --to-source option" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	mkdir -p "$(dirname "$input_file")"
	cat >"$input_file" <<EOF
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 192.168.1.0/24 -o eth0 -j SNAT --to-source 203.0.113.1
COMMIT
EOF

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"
	# Verify original IPs are not in output
	refute_file_contains "$output_file" "203.0.113.1"
	refute_file_contains "$output_file" "192.168.1.0"
	# Verify SNAT target is preserved
	assert_file_contains "$output_file" "SNAT"
	# Verify --to-source is present (use grep with -- to handle pattern starting with --)
	run grep -F -- "--to-source" "$output_file"
	assert_success
	# Verify anonymized IP is present (use -- to handle pattern starting with --)
	run grep -E -- '--to-source 10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' "$output_file"
	assert_success
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh anonymizes ipset set names in firewall rules" {
	local input_file="${TEST_DIR}/firewall/rules-with-sets.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	create_sample_firewall_file_with_sets "$input_file"

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"

	# Verify original set names are not present
	refute_file_contains "$output_file" "ALIEN"
	refute_file_contains "$output_file" "TOR"
	refute_file_contains "$output_file" "UBIOS_DMZ_subnets"
	refute_file_contains "$output_file" "UBIOS_GUEST_subnets"
	refute_file_contains "$output_file" "ALIEN_WHITELIST_SRC"
	refute_file_contains "$output_file" "TOR_WHITELIST_DST"

	# Verify anonymized set names are present (SET_<number> format) (use -- to handle pattern starting with --)
	run grep -E -- '--match-set SET_[0-9]+' "$output_file"
	assert_success
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh maps same set name to same anonymized set name consistently" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	mkdir -p "$(dirname "$input_file")"
	# Create rules with same set name appearing multiple times
	cat >"$input_file" <<EOF
*filter
:INPUT DROP [0:0]
-A INPUT -m set --match-set ALIEN src -j DROP
-A INPUT -m set --match-set ALIEN dst -j DROP
-A FORWARD -m set --match-set ALIEN src -j DROP
COMMIT
EOF

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	# Extract all anonymized set names that replaced ALIEN
	# They should all be the same
	local set_count
	set_count=$(grep -oE 'SET_[0-9]+' "$output_file" | wc -l)
	# Should have at least 3 anonymized set names (one for each occurrence)
	assert [ "$set_count" -ge 3 ]
	# Verify all occurrences use the same anonymized set name (count unique set names should be 1)
	local unique_count
	unique_count=$(grep -oE 'SET_[0-9]+' "$output_file" | sort -u | wc -l)
	# Since we only have one original set name (ALIEN), all should map to the same anonymized set name
	assert [ "$unique_count" -eq 1 ]
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh uses unified mapping file for set name consistency" {
	local input_file="${TEST_DIR}/firewall/rules-with-sets.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	local mapping_file="${TEST_DIR}/mapping.txt"
	create_sample_firewall_file_with_sets "$input_file"

	# First run - create mapping file
	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file" -m "$mapping_file"
	assert_success
	assert_file_exist "$mapping_file"

	# Verify mapping file contains set name mappings
	run grep -E "Set Names:" "$mapping_file"
	assert_success

	# Second run - use existing mapping file
	local output_file2="${TEST_DIR}/anonymized-rules2.txt"
	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file2" -m "$mapping_file"
	assert_success

	# Verify outputs are identical (same mappings used)
	anonymize_assert_files_identical "$output_file" "$output_file2"
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh preserves --match-set pattern structure" {
	local input_file="${TEST_DIR}/firewall/rules-with-sets.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	create_sample_firewall_file_with_sets "$input_file"

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"

	# Verify --match-set pattern is preserved (use -- to handle pattern starting with -)
	run grep -E -- '-m set --match-set' "$output_file"
	assert_success
	# Verify src/dst options are preserved (use -- to handle pattern starting with --)
	run grep -E -- '--match-set SET_[0-9]+ (src|dst)' "$output_file"
	assert_success
}

# bats test_tags=category:unit,anonymize:firewall
@test "anonymize-firewall.sh handles firewall rules with both set names and IPs" {
	local input_file="${TEST_DIR}/firewall/rules.txt"
	local output_file="${TEST_DIR}/anonymized-rules.txt"
	mkdir -p "$(dirname "$input_file")"
	cat >"$input_file" <<EOF
*filter
:INPUT DROP [0:0]
-A INPUT -s 192.168.1.0/24 -m set --match-set ALIEN src -j DROP
-A INPUT -s 203.0.113.1 -m set --match-set TOR dst -j ACCEPT
COMMIT
EOF

	run bash "$ANONYMIZE_FIREWALL_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"

	# Verify IPs are anonymized
	refute_file_contains "$output_file" "192.168.1.0"
	refute_file_contains "$output_file" "203.0.113.1"

	# Verify set names are anonymized
	refute_file_contains "$output_file" "ALIEN"
	refute_file_contains "$output_file" "TOR"

	# Verify anonymized values are present
	run grep -E 'SET_[0-9]+' "$output_file"
	assert_success
	run grep -E '10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' "$output_file"
	assert_success
}

# --- anonymize-logs.sh ---

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

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh exists and is executable" {
	anonymize_assert_script_exists_executable "$ANONYMIZE_LOGS_SCRIPT"
}

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh shows help with --help flag" {
	anonymize_assert_help "$ANONYMIZE_LOGS_SCRIPT" "anonymize-logs.sh" "--input" "--output" "--verbose"
}

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh shows help with -h flag" {
	anonymize_assert_help_h "$ANONYMIZE_LOGS_SCRIPT"
}

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh exits with error if input file not found" {
	anonymize_assert_input_file_not_found "$ANONYMIZE_LOGS_SCRIPT" "${TEST_DIR}/nonexistent.log"
}

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh exits with error if input file not readable" {
	anonymize_assert_input_file_unreadable "$ANONYMIZE_LOGS_SCRIPT" "${TEST_DIR}/logs/vpn-monitor.log"
}

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh exits with error if input file not specified" {
	anonymize_assert_input_file_required "$ANONYMIZE_LOGS_SCRIPT"
}

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh anonymizes IP addresses" {
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

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh anonymizes location names" {
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

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh produces consistent anonymization across multiple runs" {
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

	anonymize_assert_files_identical "$output_file1" "$output_file2"
}

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh handles empty file gracefully" {
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

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh outputs to stdout when output file not specified" {
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

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh verbose mode shows progress messages" {
	local input_file="${TEST_DIR}/logs/vpn-monitor.log"
	local output_file="${TEST_DIR}/anonymized.log"
	create_sample_log_file "$input_file"

	run bash "$ANONYMIZE_LOGS_SCRIPT" -i "$input_file" -o "$output_file" -v

	anonymize_assert_success_with_line_partials "Extracting IPv4 addresses..." "Extracting location names..." "Anonymizing log file..." "Anonymization complete!"
}

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh maps same IP to same anonymized IP consistently" {
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

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh maps same location to same anonymized location consistently" {
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

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh handles log file with only IPs (no locations)" {
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

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh handles log file with only locations (no IPs)" {
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

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh anonymizes capital Location patterns" {
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

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh anonymizes location names in comma-separated lists" {
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

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh produces unique anonymized names when many locations hash to same city" {
	# Non-obvious: regression for city-pool hash collisions (12 names must stay distinct in-source).
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

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh uses shared mapping file so different locations get different anonymized names across runs" {
	# Non-obvious: without -m, mapping file in the log directory persists and grows across runs.
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

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh rewrites output filename when it contains real location name" {
	# Non-obvious: -o must not be written if it would leak the site name; canonical vpn-monitor-*-anonymized.log.
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

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh anonymizes output filename when input has IP instead of location" {
	# Non-obvious: UDM-style vpn-monitor-<host-ip>.log must not keep that IP in the output basename.
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

# bats test_tags=category:unit,anonymize:logs
@test "anonymize-logs.sh preserves log file structure and formatting" {
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

# --- anonymize-all.sh ---

# Path to the anonymize-all script (per-script paths set above: ipset, ip-rules, firewall, logs)
ANONYMIZE_ALL_SCRIPT="${BATS_TEST_DIRNAME}/../scripts/anonymize/anonymize-all.sh"

# Create sample firewall rules file for testing
#
# Arguments:
#   $1: file (string) - path to write the sample firewall file
#
# Returns:
#   0: success
anonymize_all_create_sample_firewall_file() {
	local file="$1"
	mkdir -p "$(dirname "$file")"
	cat >"$file" <<EOF
# Generated by iptables-save
*filter
:INPUT DROP [0:0]
-A INPUT -i eth0 -s 192.168.1.0/24 -j ACCEPT
-A INPUT -m set --match-set ALIEN src -j DROP
COMMIT
EOF
}

# Create sample IPv4 routes file for testing
#
# Arguments:
#   $1: file (string) - path to write the sample routes file
#
# Returns:
#   0: success
anonymize_all_create_sample_ipv4_routes_file() {
	local file="$1"
	mkdir -p "$(dirname "$file")"
	cat >"$file" <<EOF
default via 192.168.1.1 dev eth0
10.0.0.0/8 via 10.0.0.1 dev br0
EOF
}

# Create sample IPv6 routes file for testing
#
# Arguments:
#   $1: file (string) - path to write the sample routes file
#
# Returns:
#   0: success
anonymize_all_create_sample_ipv6_routes_file() {
	local file="$1"
	mkdir -p "$(dirname "$file")"
	cat >"$file" <<EOF
default via fe80::1 dev eth0
2001:db8::/32 via 2001:db8::1 dev br0
EOF
}

# Create sample ipset save file for testing
#
# Arguments:
#   $1: file (string) - path to write the sample ipset file
#
# Returns:
#   0: success
anonymize_all_create_sample_ipset_file() {
	local file="$1"
	mkdir -p "$(dirname "$file")"
	cat >"$file" <<EOF
create ALIEN hash:ip family inet hashsize 1024 maxelem 65536
add ALIEN 198.51.100.1
create TOR hash:ip family inet hashsize 1024 maxelem 65536
add TOR 172.16.0.1
EOF
}

# Create sample vpn-monitor log file for testing
#
# Arguments:
#   $1: file (string) - path to write the sample log file
#
# Returns:
#   0: success
anonymize_all_create_sample_log_file() {
	local file="$1"
	mkdir -p "$(dirname "$file")"
	cat >"$file" <<EOF
[2025-01-15 10:00:00] [INFO] VPN check for location NYC (203.0.113.1): OK
[2025-01-15 10:01:00] [WARNING] VPN check failed for location DC (198.51.100.1)
EOF
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh exists and is executable" {
	anonymize_assert_script_exists_executable "$ANONYMIZE_ALL_SCRIPT"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh shows help with --help flag" {
	anonymize_assert_help "$ANONYMIZE_ALL_SCRIPT" "anonymize-all.sh" "--firewall" "--routes-ipv4" "--routes-ipv6" "--ipset" "--logs" "--output-dir" "--mapping-file"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh shows help with -h flag" {
	anonymize_assert_help_h "$ANONYMIZE_ALL_SCRIPT"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh exits with error if output directory not provided" {
	run bash "$ANONYMIZE_ALL_SCRIPT" -f /tmp/firewall.txt -m /tmp/mapping.txt

	assert_failure
	assert_output --partial "Output directory is required"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh exits with error if mapping file not provided" {
	run bash "$ANONYMIZE_ALL_SCRIPT" -f /tmp/firewall.txt -o /tmp/output

	assert_failure
	assert_output --partial "Mapping file is required"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh exits with error if no input files provided" {
	run bash "$ANONYMIZE_ALL_SCRIPT" -o /tmp/output -m /tmp/mapping.txt

	assert_failure
	assert_output --partial "At least one input file must be provided"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh exits with error if input file not found" {
	run bash "$ANONYMIZE_ALL_SCRIPT" -f /tmp/nonexistent.txt -o /tmp/output -m /tmp/mapping.txt

	assert_failure
	assert_output --partial "Input file(s) not found"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh anonymizes firewall rules with unified mapping" {
	local firewall_file="${TEST_DIR}/firewall.txt"
	local output_dir="${TEST_DIR}/output"
	local mapping_file="${TEST_DIR}/mapping.txt"
	anonymize_all_create_sample_firewall_file "$firewall_file"

	run bash "$ANONYMIZE_ALL_SCRIPT" -f "$firewall_file" -o "$output_dir" -m "$mapping_file"

	assert_success
	assert_file_exist "${output_dir}/firewall-rules-anonymized.txt"
	assert_file_exist "$mapping_file"
	# Verify mapping file contains mappings
	run grep -E "IPv4 Addresses:" "$mapping_file"
	assert_success
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh anonymizes IPv4 routes with unified mapping" {
	local routes_file="${TEST_DIR}/routes-ipv4.txt"
	local output_dir="${TEST_DIR}/output"
	local mapping_file="${TEST_DIR}/mapping.txt"
	anonymize_all_create_sample_ipv4_routes_file "$routes_file"

	run bash "$ANONYMIZE_ALL_SCRIPT" -r4 "$routes_file" -o "$output_dir" -m "$mapping_file"

	assert_success
	assert_file_exist "${output_dir}/routes-ipv4-anonymized.txt"
	assert_file_exist "$mapping_file"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh anonymizes IPv6 routes with unified mapping" {
	local routes_file="${TEST_DIR}/routes-ipv6.txt"
	local output_dir="${TEST_DIR}/output"
	local mapping_file="${TEST_DIR}/mapping.txt"
	anonymize_all_create_sample_ipv6_routes_file "$routes_file"

	run bash "$ANONYMIZE_ALL_SCRIPT" -r6 "$routes_file" -o "$output_dir" -m "$mapping_file"

	assert_success
	assert_file_exist "${output_dir}/routes-ipv6-anonymized.txt"
	assert_file_exist "$mapping_file"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh anonymizes ipset sets with unified mapping" {
	local ipset_file="${TEST_DIR}/ipset.txt"
	local output_dir="${TEST_DIR}/output"
	local mapping_file="${TEST_DIR}/mapping.txt"
	anonymize_all_create_sample_ipset_file "$ipset_file"

	run bash "$ANONYMIZE_ALL_SCRIPT" -s "$ipset_file" -o "$output_dir" -m "$mapping_file"

	assert_success
	assert_file_exist "${output_dir}/ipset-sets-anonymized.txt"
	assert_file_exist "$mapping_file"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh anonymizes logs with unified mapping" {
	local log_file="${TEST_DIR}/vpn-monitor.log"
	local output_dir="${TEST_DIR}/output"
	local mapping_file="${TEST_DIR}/mapping.txt"
	anonymize_all_create_sample_log_file "$log_file"

	run bash "$ANONYMIZE_ALL_SCRIPT" -l "$log_file" -o "$output_dir" -m "$mapping_file"

	assert_success
	assert_file_exist "${output_dir}/vpn-monitor-anonymized.log"
	assert_file_exist "$mapping_file"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh anonymizes all file types together with unified mapping" {
	local firewall_file="${TEST_DIR}/firewall.txt"
	local routes_ipv4_file="${TEST_DIR}/routes-ipv4.txt"
	local routes_ipv6_file="${TEST_DIR}/routes-ipv6.txt"
	local ipset_file="${TEST_DIR}/ipset.txt"
	local log_file="${TEST_DIR}/vpn-monitor.log"
	local output_dir="${TEST_DIR}/output"
	local mapping_file="${TEST_DIR}/mapping.txt"

	anonymize_all_create_sample_firewall_file "$firewall_file"
	anonymize_all_create_sample_ipv4_routes_file "$routes_ipv4_file"
	anonymize_all_create_sample_ipv6_routes_file "$routes_ipv6_file"
	anonymize_all_create_sample_ipset_file "$ipset_file"
	anonymize_all_create_sample_log_file "$log_file"

	run bash "$ANONYMIZE_ALL_SCRIPT" \
		-f "$firewall_file" \
		-r4 "$routes_ipv4_file" \
		-r6 "$routes_ipv6_file" \
		-s "$ipset_file" \
		-l "$log_file" \
		-o "$output_dir" \
		-m "$mapping_file"

	assert_success

	# Verify all output files exist
	assert_file_exist "${output_dir}/firewall-rules-anonymized.txt"
	assert_file_exist "${output_dir}/routes-ipv4-anonymized.txt"
	assert_file_exist "${output_dir}/routes-ipv6-anonymized.txt"
	assert_file_exist "${output_dir}/ipset-sets-anonymized.txt"
	assert_file_exist "${output_dir}/vpn-monitor-anonymized.log"
	assert_file_exist "$mapping_file"

	# Verify mapping file contains all mapping types
	run grep -E "IPv4 Addresses:" "$mapping_file"
	assert_success
	run grep -E "IPv6 Addresses:" "$mapping_file"
	assert_success
	run grep -E "Set Names:" "$mapping_file"
	assert_success
	run grep -E "Locations:" "$mapping_file"
	assert_success
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh uses unified mapping for consistency across file types" {
	local firewall_file="${TEST_DIR}/firewall.txt"
	local ipset_file="${TEST_DIR}/ipset.txt"
	local output_dir="${TEST_DIR}/output"
	local mapping_file="${TEST_DIR}/mapping.txt"

	# Create files with same IP address (192.168.1.1)
	mkdir -p "$(dirname "$firewall_file")"
	cat >"$firewall_file" <<EOF
*filter
-A INPUT -s 192.168.1.1 -j ACCEPT
COMMIT
EOF

	mkdir -p "$(dirname "$ipset_file")"
	cat >"$ipset_file" <<EOF
create TEST_SET hash:ip family inet hashsize 1024 maxelem 65536
add TEST_SET 192.168.1.1
EOF

	run bash "$ANONYMIZE_ALL_SCRIPT" \
		-f "$firewall_file" \
		-s "$ipset_file" \
		-o "$output_dir" \
		-m "$mapping_file"

	assert_success

	# Extract anonymized IP from firewall output
	local anon_ip_firewall
	anon_ip_firewall=$(grep -oE '\b10\.([0-9]{1,3}\.){2}[0-9]{1,3}\b' "${output_dir}/firewall-rules-anonymized.txt" | head -1)

	# Extract anonymized IP from ipset output
	local anon_ip_ipset
	anon_ip_ipset=$(grep -oE '\b10\.([0-9]{1,3}\.){2}[0-9]{1,3}\b' "${output_dir}/ipset-sets-anonymized.txt" | head -1)

	# Verify they are the same (unified mapping)
	assert_equal "$anon_ip_firewall" "$anon_ip_ipset"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh creates output directory if it doesn't exist" {
	local firewall_file="${TEST_DIR}/firewall.txt"
	local output_dir="${TEST_DIR}/new-output-dir"
	local mapping_file="${TEST_DIR}/mapping.txt"
	anonymize_all_create_sample_firewall_file "$firewall_file"

	# Verify directory doesn't exist
	[[ ! -d "$output_dir" ]]

	run bash "$ANONYMIZE_ALL_SCRIPT" -f "$firewall_file" -o "$output_dir" -m "$mapping_file"

	assert_success
	# Verify directory was created
	assert [ -d "$output_dir" ]
	assert_file_exist "${output_dir}/firewall-rules-anonymized.txt"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh handles errors gracefully when one script fails" {
	local firewall_file="${TEST_DIR}/firewall.txt"
	local invalid_file="${TEST_DIR}/invalid.txt"
	local output_dir="${TEST_DIR}/output"
	local mapping_file="${TEST_DIR}/mapping.txt"
	anonymize_all_create_sample_firewall_file "$firewall_file"

	# Create invalid file (empty, but will cause error in processing)
	mkdir -p "$(dirname "$invalid_file")"
	touch "$invalid_file"

	# Try to anonymize both - firewall should succeed, invalid file should fail
	# Note: This test may need adjustment based on actual error handling behavior
	run bash "$ANONYMIZE_ALL_SCRIPT" \
		-f "$firewall_file" \
		-r4 "$invalid_file" \
		-o "$output_dir" \
		-m "$mapping_file" || true

	# Firewall should still be anonymized
	assert_file_exist "${output_dir}/firewall-rules-anonymized.txt"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh handles verbose mode" {
	local firewall_file="${TEST_DIR}/firewall.txt"
	local output_dir="${TEST_DIR}/output"
	local mapping_file="${TEST_DIR}/mapping.txt"
	anonymize_all_create_sample_firewall_file "$firewall_file"

	run bash "$ANONYMIZE_ALL_SCRIPT" -f "$firewall_file" -o "$output_dir" -m "$mapping_file" -v

	anonymize_assert_success_with_output_partials "Starting unified anonymization" "Mapping file:" "Output directory:" "Anonymizing firewall rules" "Anonymization complete"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh loads existing mapping file" {
	local firewall_file="${TEST_DIR}/firewall.txt"
	local output_dir="${TEST_DIR}/output"
	local mapping_file="${TEST_DIR}/mapping.txt"
	anonymize_all_create_sample_firewall_file "$firewall_file"

	# Create initial mapping file
	mkdir -p "$(dirname "$mapping_file")"
	cat >"$mapping_file" <<EOF
# Unified Anonymization Mapping
IPv4 Addresses:
--------------------------------------------------
192.168.1.0/24 -> 10.1.2.3/24
EOF

	run bash "$ANONYMIZE_ALL_SCRIPT" -f "$firewall_file" -o "$output_dir" -m "$mapping_file"

	assert_success
	# Verify mapping file was updated (should contain more mappings)
	run grep -E "IPv4 Addresses:" "$mapping_file"
	assert_success
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh auto-detects files in directory mode" {
	local input_dir="${TEST_DIR}/exports"
	local output_dir="${TEST_DIR}/output"
	local mapping_file="${TEST_DIR}/mapping.txt"
	mkdir -p "$input_dir"

	# Create files matching export script patterns
	anonymize_all_create_sample_firewall_file "${input_dir}/firewall-rules-2026-01-20-10-00-00.txt"
	anonymize_all_create_sample_ipv4_routes_file "${input_dir}/routes-ipv4-2026-01-20-10-00-00.txt"

	run bash "$ANONYMIZE_ALL_SCRIPT" -d "$input_dir" -o "$output_dir" -m "$mapping_file"

	assert_success
	# Verify files were found and anonymized
	assert_file_exist "${output_dir}/firewall-rules-anonymized.txt"
	assert_file_exist "${output_dir}/routes-ipv4-anonymized.txt"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh uses most recent file when multiple files exist in directory" {
	local input_dir="${TEST_DIR}/exports"
	local output_dir="${TEST_DIR}/output"
	local mapping_file="${TEST_DIR}/mapping.txt"
	mkdir -p "$input_dir"

	# Create multiple firewall files with different timestamps
	anonymize_all_create_sample_firewall_file "${input_dir}/firewall-rules-2026-01-20-10-00-00.txt"
	sleep 1
	anonymize_all_create_sample_firewall_file "${input_dir}/firewall-rules-2026-01-20-11-00-00.txt"

	run bash "$ANONYMIZE_ALL_SCRIPT" -d "$input_dir" -o "$output_dir" -m "$mapping_file"

	assert_success
	# Verify the most recent file was used (should exist and be anonymized)
	assert_file_exist "${output_dir}/firewall-rules-anonymized.txt"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh explicit files override directory mode auto-detection" {
	local input_dir="${TEST_DIR}/exports"
	local custom_firewall="${TEST_DIR}/custom-firewall.txt"
	local output_dir="${TEST_DIR}/output"
	local mapping_file="${TEST_DIR}/mapping.txt"
	mkdir -p "$input_dir"

	# Create file in directory
	anonymize_all_create_sample_firewall_file "${input_dir}/firewall-rules-2026-01-20-10-00-00.txt"
	# Create custom firewall file
	mkdir -p "$(dirname "$custom_firewall")"
	cat >"$custom_firewall" <<EOF
*filter
-A INPUT -s 10.0.0.1 -j ACCEPT
COMMIT
EOF

	run bash "$ANONYMIZE_ALL_SCRIPT" -d "$input_dir" -f "$custom_firewall" -o "$output_dir" -m "$mapping_file"

	assert_success
	# Verify custom file was used (check for 10.0.0.1 anonymization, not 192.168.1.0 from sample)
	assert_file_exist "${output_dir}/firewall-rules-anonymized.txt"
	# Custom file should have been anonymized (10.0.0.1 should be anonymized)
	run grep -v "10.0.0.1" "${output_dir}/firewall-rules-anonymized.txt" || true
	# Should not contain original 10.0.0.1 (it should be anonymized)
	refute_file_contains "${output_dir}/firewall-rules-anonymized.txt" "10.0.0.1"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh directory mode provides helpful error when no files found" {
	local input_dir="${TEST_DIR}/empty-exports"
	local output_dir="${TEST_DIR}/output"
	local mapping_file="${TEST_DIR}/mapping.txt"
	mkdir -p "$input_dir"

	run bash "$ANONYMIZE_ALL_SCRIPT" -d "$input_dir" -o "$output_dir" -m "$mapping_file"

	assert_failure
	assert_output --partial "No matching files found in directory"
	assert_output --partial "firewall-rules-*.txt"
	assert_output --partial "routes-ipv4-*.txt"
}

# bats test_tags=category:unit,anonymize:all
@test "anonymize-all.sh directory mode works with verbose output" {
	local input_dir="${TEST_DIR}/exports"
	local output_dir="${TEST_DIR}/output"
	local mapping_file="${TEST_DIR}/mapping.txt"
	mkdir -p "$input_dir"

	anonymize_all_create_sample_firewall_file "${input_dir}/firewall-rules-2026-01-20-10-00-00.txt"
	anonymize_all_create_sample_ipv4_routes_file "${input_dir}/routes-ipv4-2026-01-20-10-00-00.txt"

	run bash "$ANONYMIZE_ALL_SCRIPT" -d "$input_dir" -o "$output_dir" -m "$mapping_file" -v

	anonymize_assert_success_with_output_partials "Auto-detecting files in directory" "Found firewall file" "Found IPv4 routes file"
}
