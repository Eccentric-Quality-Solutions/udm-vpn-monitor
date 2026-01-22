#!/usr/bin/env bats
#
# Tests for anonymize-ipset.sh script
# Tests ipset sets anonymization functionality, IP, set name, MAC, and hostname anonymization, and consistency
#

load test_helper

# Path to the anonymize-ipset script
ANONYMIZE_IPSET_SCRIPT="${BATS_TEST_DIRNAME}/../scripts/anonymize-ipset.sh"

# Create sample ipset save file with sets, IPs, and set names
#
# Creates an ipset save file with set names, IP addresses, and other identifiers for testing anonymization.
#
# Arguments:
#   $1: Ipset save file path
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

# bats test_tags=category:unit
@test "anonymize-ipset.sh exists and is executable" {
	# Purpose: Test verifies that the anonymize-ipset script file exists and has execute permissions
	# Expected: Anonymize-ipset script file is present and executable
	# Importance: Ensures the ipset anonymization script can be run directly for set sanitization
	assert_file_exist "$ANONYMIZE_IPSET_SCRIPT"
	assert_file_executable "$ANONYMIZE_IPSET_SCRIPT"
}

# bats test_tags=category:unit
@test "anonymize-ipset.sh shows help with --help flag" {
	# Purpose: Test verifies that the anonymize-ipset script displays usage information when --help flag is provided
	# Expected: Script outputs usage information including all available options and flags
	# Importance: Ensures users can access help documentation for script usage and available options
	run bash "$ANONYMIZE_IPSET_SCRIPT" --help
	assert_success
	assert_output --partial "Usage:"
	assert_output --partial "anonymize-ipset.sh"
	assert_output --partial "--input"
	assert_output --partial "--output"
	assert_output --partial "--mapping-file"
	assert_output --partial "--verbose"
}

# bats test_tags=category:unit
@test "anonymize-ipset.sh shows help with -h flag" {
	# Purpose: Test verifies that the anonymize-ipset script displays usage information when -h flag is provided
	# Expected: Script outputs usage information including all available options and flags
	# Importance: Ensures users can access help documentation using the short flag option
	run bash "$ANONYMIZE_IPSET_SCRIPT" -h
	assert_success
	assert_output --partial "Usage:"
}

# bats test_tags=category:unit
@test "anonymize-ipset.sh exits with error if input file not found" {
	# Purpose: Test verifies that the anonymize-ipset script validates input file existence before processing
	# Expected: Script exits with failure status and displays error message when input file doesn't exist
	# Importance: Prevents script from attempting to anonymize non-existent files and provides clear error feedback
	local input_file="${TEST_DIR}/nonexistent-ipset.txt"

	run bash "$ANONYMIZE_IPSET_SCRIPT" -i "$input_file"

	assert_failure
	assert_output --partial "Input file not found"
}

# bats test_tags=category:unit
@test "anonymize-ipset.sh anonymizes IPv4 addresses in ipset sets" {
	# Purpose: Test verifies that the anonymize-ipset script anonymizes IPv4 addresses in ipset save output
	# Expected: IPv4 addresses are replaced with anonymized addresses in the 10.x.x.x range
	# Importance: Ensures IP addresses are properly anonymized in ipset sets
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
	run grep -E '\b(192\.168|203\.0|198\.51|172\.16)' "$output_file" || true
	assert_output ""
}

# bats test_tags=category:unit
@test "anonymize-ipset.sh anonymizes set names in ipset save output" {
	# Purpose: Test verifies that the anonymize-ipset script anonymizes set names in ipset save output
	# Expected: Set names are replaced with anonymized names (SET_<number> format)
	# Importance: Ensures set names are properly anonymized for privacy
	local input_file="${TEST_DIR}/ipset/ipset-save.txt"
	local output_file="${TEST_DIR}/anonymized-ipset.txt"
	create_sample_ipset_file "$input_file"

	run bash "$ANONYMIZE_IPSET_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"

	# Verify original set names are not present
	run grep -E '(UBIOS_ALL_ADDRv4_eth8|UBIOS_ALL_NETv4_br104|ALIEN|TOR)' "$output_file" || true
	assert_output ""

	# Verify anonymized set names are present (SET_<number> format)
	run grep -E '^create SET_[0-9]+' "$output_file"
	assert_success
	run grep -E '^add SET_[0-9]+' "$output_file"
	assert_success
}

# bats test_tags=category:unit
@test "anonymize-ipset.sh anonymizes IPv6 addresses in ipset sets" {
	# Purpose: Test verifies that the anonymize-ipset script anonymizes IPv6 addresses in ipset save output
	# Expected: IPv6 addresses are replaced with anonymized addresses in the fc00::/7 range
	# Importance: Ensures IPv6 addresses are properly anonymized in ipset sets
	local input_file="${TEST_DIR}/ipset/ipset-ipv6.txt"
	local output_file="${TEST_DIR}/anonymized-ipset-ipv6.txt"
	create_sample_ipset_ipv6_file "$input_file"

	run bash "$ANONYMIZE_IPSET_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"

	# Verify original IPv6 addresses are not present
	run grep -E '(2001:db8|fe80::)' "$output_file" || true
	assert_output ""

	# Verify anonymized IPv6 addresses are present (should be in fc00::/7 range)
	run grep -E 'fc00:[0-9a-f:]+' "$output_file"
	assert_success
}

# bats test_tags=category:unit
@test "anonymize-ipset.sh anonymizes MAC addresses in ipset sets" {
	# Purpose: Test verifies that the anonymize-ipset script anonymizes MAC addresses in ipset save output
	# Expected: MAC addresses are replaced with anonymized addresses in the 02:xx:xx:xx:xx:xx range
	# Importance: Ensures MAC addresses are properly anonymized in ipset sets
	local input_file="${TEST_DIR}/ipset/ipset-mac.txt"
	local output_file="${TEST_DIR}/anonymized-ipset-mac.txt"
	create_sample_ipset_mac_file "$input_file"

	run bash "$ANONYMIZE_IPSET_SCRIPT" -i "$input_file" -o "$output_file"

	assert_success
	assert_file_exist "$output_file"

	# Verify original MAC addresses are not present
	run grep -E '(aa:bb:cc:dd:ee:ff|00:11:22:33:44:55|ff:ee:dd:cc:bb:aa)' "$output_file" || true
	assert_output ""

	# Verify anonymized MAC addresses are present (should start with 02:)
	run grep -E '02:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}' "$output_file"
	assert_success
}

# bats test_tags=category:unit
@test "anonymize-ipset.sh produces consistent anonymization across multiple runs" {
	# Purpose: Test verifies that the anonymize-ipset script produces the same anonymized output when run multiple times
	# Expected: Running the script twice on the same input produces identical output
	# Importance: Consistency ensures that anonymized sets remain understandable and comparable across runs
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

	# Verify outputs are identical
	run diff "$output_file1" "$output_file2"
	assert_success
	assert_output ""
}

# bats test_tags=category:unit
@test "anonymize-ipset.sh uses unified mapping file for consistency" {
	# Purpose: Test verifies that the anonymize-ipset script uses unified mapping file to ensure consistency
	# Expected: When using a mapping file, same IPs/set names map to same anonymized values
	# Importance: Ensures consistency across different anonymization runs and file types
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
	run diff "$output_file" "$output_file2"
	assert_success
	assert_output ""
}

# bats test_tags=category:unit
@test "anonymize-ipset.sh handles empty file gracefully" {
	# Purpose: Test verifies that the anonymize-ipset script handles empty ipset save files without errors
	# Expected: Script processes empty file successfully and produces empty output
	# Importance: Ensures script robustness when encountering empty files
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

# bats test_tags=category:unit
@test "anonymize-ipset.sh outputs to stdout when output file not specified" {
	# Purpose: Test verifies that the anonymize-ipset script outputs to stdout when output file is not specified
	# Expected: Script outputs anonymized content to stdout instead of creating a file
	# Importance: Enables piping and redirection workflows for script output
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

# bats test_tags=category:unit
@test "anonymize-ipset.sh prevents overwriting input file" {
	# Purpose: Test verifies that the anonymize-ipset script prevents overwriting the input file
	# Expected: Script exits with error when output file is the same as input file
	# Importance: Prevents accidental data loss by overwriting source files
	local input_file="${TEST_DIR}/ipset/ipset-save.txt"
	create_sample_ipset_file "$input_file"

	run bash "$ANONYMIZE_IPSET_SCRIPT" -i "$input_file" -o "$input_file"

	assert_failure
	assert_output --partial "Output file cannot be the same as input file"
}

# bats test_tags=category:unit
@test "anonymize-ipset.sh handles verbose mode" {
	# Purpose: Test verifies that the anonymize-ipset script provides verbose output when -v flag is used
	# Expected: Script outputs additional information about anonymization process when verbose mode is enabled
	# Importance: Helps users understand what anonymization is being performed
	local input_file="${TEST_DIR}/ipset/ipset-save.txt"
	local output_file="${TEST_DIR}/anonymized-ipset.txt"
	create_sample_ipset_file "$input_file"

	run bash "$ANONYMIZE_IPSET_SCRIPT" -i "$input_file" -o "$output_file" -v

	assert_success
	assert_output --partial "Extracting"
	assert_output --partial "Mapping"
	assert_output --partial "Anonymization complete"
}

# bats test_tags=category:unit
@test "anonymize-ipset.sh preserves ipset save format structure" {
	# Purpose: Test verifies that the anonymize-ipset script preserves the structure of ipset save format
	# Expected: Output maintains proper ipset save format with create/add commands
	# Importance: Ensures anonymized output can still be used with ipset restore
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
