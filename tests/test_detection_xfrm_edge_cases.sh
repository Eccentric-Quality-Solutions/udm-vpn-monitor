#!/usr/bin/env bats
#
# Tests for xfrm Output Parsing Edge Cases
# Tests malformed xfrm output, multiple SAs, special characters, and timeout scenarios
#
# These tests address the gap identified in CRITICAL_PATH_TEST_GAPS_REVIEW.md Section 2.1

load test_helper

# ============================================================================
# XFRM OUTPUT PARSING EDGE CASES TESTS
# ============================================================================

# bats test_tags=category:detection,priority:medium
@test "extract_byte_counter handles malformed byte counter line - missing bytes keyword" {
	# Purpose: Test verifies that extract_byte_counter handles malformed xfrm output gracefully.
	# Expected: Function returns failure (exit code 1) when byte counter line is malformed.
	# Importance: Malformed xfrm output could cause false positives/negatives if not handled properly.
	source_function "extract_byte_counter"

	local xfrm_output="src 192.168.1.1 dst 192.168.1.1
    proto esp spi 0x12345678 reqid 1 mode tunnel
    lifetime current: 123456"
	# Missing "bytes" keyword

	run extract_byte_counter "$xfrm_output"
	assert_failure
	assert_output ""
}

# bats test_tags=category:detection,priority:medium
@test "extract_byte_counter handles malformed byte counter line - non-numeric bytes value" {
	# Purpose: Test verifies that extract_byte_counter rejects non-numeric byte counter values.
	# Expected: Function returns failure when bytes value is not numeric.
	# Importance: Invalid byte counter values could cause false positives/negatives.
	source_function "extract_byte_counter"

	local xfrm_output="src 192.168.1.1 dst 192.168.1.1
    proto esp spi 0x12345678 reqid 1 mode tunnel
    lifetime current: abc123 bytes, 10 packets"

	run extract_byte_counter "$xfrm_output"
	assert_failure
	assert_output ""
}

# bats test_tags=category:detection,priority:medium
@test "extract_byte_counter handles malformed byte counter line - negative bytes value" {
	# Purpose: Test verifies that extract_byte_counter rejects negative byte counter values.
	# Expected: Function returns failure when bytes value is negative.
	# Importance: Negative byte counters are invalid and should be rejected.
	source_function "extract_byte_counter"

	local xfrm_output="src 192.168.1.1 dst 192.168.1.1
    proto esp spi 0x12345678 reqid 1 mode tunnel
    lifetime current: -100 bytes, 10 packets"

	run extract_byte_counter "$xfrm_output"
	assert_failure
	assert_output ""
}

# bats test_tags=category:detection,priority:medium
@test "extract_spi handles malformed SPI line - missing SPI value" {
	# Purpose: Test verifies that extract_spi handles malformed xfrm output gracefully.
	# Expected: Function returns failure when SPI value is missing.
	# Importance: Malformed SPI output could cause rekey detection failures.
	local xfrm_output="src 192.168.1.1 dst 192.168.1.1
    proto esp spi reqid 1 mode tunnel
    lifetime current: 123456 bytes, 10 packets"

	run extract_spi "$xfrm_output"
	assert_failure
	assert_output ""
}

# bats test_tags=category:detection,priority:medium
@test "extract_spi handles malformed SPI line - invalid SPI format" {
	# Purpose: Test verifies that extract_spi rejects invalid SPI formats.
	# Expected: Function returns failure when SPI format is invalid.
	# Importance: Invalid SPI formats could cause rekey detection failures.
	local xfrm_output="src 192.168.1.1 dst 192.168.1.1
    proto esp spi invalid_spi reqid 1 mode tunnel
    lifetime current: 123456 bytes, 10 packets"

	run extract_spi "$xfrm_output"
	assert_failure
	assert_output ""
}

# bats test_tags=category:detection,priority:medium
@test "check_xfrm_status handles multiple SAs with same peer IP gracefully" {
	# Purpose: Test verifies that check_xfrm_status handles multiple SAs for the same peer IP.
	# Expected: Function should handle multiple SAs gracefully and extract byte counter from first match.
	# Importance: Multiple SAs with same peer IP can occur during rekey transitions.
	setup_test_environment "${TEST_DIR}"
	local peer_ip="192.168.1.1"

	# Mock ip command with multiple SAs for same peer IP
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # First SA (old, lower bytes)
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x11111111 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 5 packets"
    echo ""
    # Second SA (new, higher bytes) - same peer IP
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x22222222 reqid 1 mode tunnel"
    echo "    lifetime current: 5000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Initialize state
	setup_state_files "$peer_ip" 0

	# Source required functions
	source_function "check_xfrm_status"
	source_function "check_byte_counters"
	source_function "get_peer_state"
	source_function "set_peer_state"

	# Should handle multiple SAs gracefully
	run check_xfrm_status "$peer_ip" ""
	# Should succeed (SA found) - may use first or second SA
	# The function uses grep -F "dst $peer_ip" -A 10, so it will get the first match
	assert_success

	remove_mock_from_path
}

# bats test_tags=category:detection,priority:medium
@test "check_xfrm_status handles special characters in IP addresses" {
	# Purpose: Test verifies that check_xfrm_status handles IP addresses with special characters correctly.
	# Expected: Function should handle IPv6 addresses and IPv4-mapped IPv6 addresses correctly.
	# Importance: Special characters in IP addresses could cause parsing failures if not handled properly.
	setup_test_environment "${TEST_DIR}"
	local peer_ip="2001:db8::1"

	# Mock ip command with IPv6 address
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 2001:db8::1 dst 2001:db8::1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 123456 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Initialize state
	setup_state_files "$peer_ip" 0

	# Source required functions
	source_function "check_xfrm_status"
	source_function "check_byte_counters"
	source_function "get_peer_state"
	source_function "set_peer_state"

	# Should handle IPv6 address correctly
	run check_xfrm_status "$peer_ip" ""
	assert_success

	remove_mock_from_path
}

# bats test_tags=category:detection,priority:medium
@test "check_xfrm_status handles IPv4-mapped IPv6 addresses" {
	# Purpose: Test verifies that check_xfrm_status handles IPv4-mapped IPv6 addresses correctly.
	# Expected: Function should handle ::ffff:x.x.x.x format addresses correctly.
	# Importance: IPv4-mapped IPv6 addresses contain special characters that could cause parsing failures.
	setup_test_environment "${TEST_DIR}"
	local peer_ip="::ffff:192.168.1.1"

	# Mock ip command with IPv4-mapped IPv6 address
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src ::ffff:192.168.1.1 dst ::ffff:192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 123456 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Initialize state
	setup_state_files "$peer_ip" 0

	# Source required functions
	source_function "check_xfrm_status"
	source_function "check_byte_counters"
	source_function "get_peer_state"
	source_function "set_peer_state"

	# Should handle IPv4-mapped IPv6 address correctly
	run check_xfrm_status "$peer_ip" ""
	assert_success

	remove_mock_from_path
}

# bats test_tags=category:detection,priority:medium
@test "check_ipsec_status works as fallback when xfrm fails" {
	# Purpose: Test verifies that check_ipsec_status works as fallback when xfrm command fails.
	# Expected: Function should succeed when ipsec status shows connection exists.
	# Importance: xfrm command failure could cause false negatives if ipsec fallback doesn't work.
	# Note: The actual fallback from check_xfrm_status to check_ipsec_status happens in
	# check_vpn_status, not within check_xfrm_status itself. This test verifies that
	# check_ipsec_status works correctly as a fallback mechanism.
	setup_test_environment "${TEST_DIR}"
	local peer_ip="192.168.1.1"

	# Mock ip command that fails (simulating xfrm failure)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Return empty output (simulating failure)
    exit 1
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Mock ipsec command that succeeds
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    echo "test-conn: ESTABLISHED 1 hour ago, 192.168.1.1...192.168.1.2"
    exit 0
fi
exit 1
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Initialize state
	setup_state_files "$peer_ip" 0

	# Source required functions
	source_function "check_ipsec_status"

	# Test that check_ipsec_status works as fallback when xfrm fails
	run check_ipsec_status "$peer_ip"
	assert_success

	remove_mock_from_path
}

# bats test_tags=category:detection,priority:medium
@test "extract_byte_counter handles empty xfrm output" {
	# Purpose: Test verifies that extract_byte_counter handles empty xfrm output gracefully.
	# Expected: Function returns failure when xfrm output is empty.
	# Importance: Empty xfrm output could cause false negatives if not handled properly.
	source_function "extract_byte_counter"

	local xfrm_output=""

	run extract_byte_counter "$xfrm_output"
	assert_failure
	assert_output ""
}

# bats test_tags=category:detection,priority:medium
@test "extract_spi handles empty xfrm output" {
	# Purpose: Test verifies that extract_spi handles empty xfrm output gracefully.
	# Expected: Function returns failure when xfrm output is empty.
	# Importance: Empty xfrm output could cause rekey detection failures.
	local xfrm_output=""

	run extract_spi "$xfrm_output"
	assert_failure
	assert_output ""
}

# bats test_tags=category:detection,priority:medium
@test "extract_byte_counter handles xfrm output with multiple lifetime lines" {
	# Purpose: Test verifies that extract_byte_counter extracts bytes from first lifetime line.
	# Expected: Function extracts bytes from first "lifetime current:" line found.
	# Importance: Multiple lifetime lines could cause incorrect byte extraction if not handled properly.
	source_function "extract_byte_counter"

	local xfrm_output="src 192.168.1.1 dst 192.168.1.1
    proto esp spi 0x12345678 reqid 1 mode tunnel
    lifetime current: 123456 bytes, 10 packets
    lifetime hard: 3600s, 0 bytes, 0 packets
    lifetime soft: 2880s, 0 bytes, 0 packets"

	run extract_byte_counter "$xfrm_output"
	assert_success
	assert_output "123456"
}

# bats test_tags=category:detection,priority:medium
@test "extract_spi handles xfrm output with multiple SPI lines" {
	# Purpose: Test verifies that extract_spi extracts SPI from first SPI line found.
	# Expected: Function extracts SPI from first SPI line found.
	# Importance: Multiple SPI lines could cause incorrect SPI extraction if not handled properly.
	local xfrm_output="src 192.168.1.1 dst 192.168.1.1
    proto esp spi 0x12345678 reqid 1 mode tunnel
    proto ah spi 0x87654321 reqid 2 mode tunnel
    lifetime current: 123456 bytes, 10 packets"

	run extract_spi "$xfrm_output"
	assert_success
	# Should extract first SPI (0x12345678)
	assert_output "0x12345678"
}
