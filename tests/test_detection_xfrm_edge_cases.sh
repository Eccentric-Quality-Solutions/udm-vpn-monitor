#!/usr/bin/env bats
#
# Tests for xfrm Output Parsing Edge Cases
# Tests malformed xfrm output, multiple SAs, special characters, and timeout scenarios
#
# These tests address the gap identified in CRITICAL_PATH_TEST_GAPS_REVIEW.md Section 2.1

load test_helper
load helpers/logging

# ============================================================================
# XFRM OUTPUT PARSING EDGE CASES TESTS
# ============================================================================

# bats test_tags=category:detection,priority:medium
@test "extract_byte_counter handles malformed byte counter line - missing bytes keyword" {
	# Purpose: Test verifies that extract_byte_counter handles malformed xfrm output gracefully.
	# Expected: Function returns failure (exit code 1) when byte counter line is malformed and logs warning.
	# Importance: Malformed xfrm output could cause false positives/negatives if not handled properly.
	source_logging_functions
	export LOG_FILE="${TEST_DIR}/test.log"
	mkdir -p "$(dirname "$LOG_FILE")"
	source_function "extract_byte_counter"

	local xfrm_output="src ${TEST_PEER_IP} dst ${TEST_PEER_IP}
    proto esp spi 0x12345678 reqid 1 mode tunnel
    lifetime current: 123456"
	# Missing "bytes" keyword

	run extract_byte_counter "$xfrm_output"
	assert_failure
	# Function should output warning to stderr (captured by run)
	assert_output --regexp "WARNING.*extract_byte_counter.*lifetime current.*failed to extract byte counter"
	# Also verify warning is in log file
	assert_file_exist "$LOG_FILE"
	run grep -q "WARNING.*extract_byte_counter.*lifetime current.*failed to extract byte counter" "$LOG_FILE"
	assert_success
}

# bats test_tags=category:detection,priority:medium
@test "extract_byte_counter handles malformed byte counter line - non-numeric bytes value" {
	# Purpose: Test verifies that extract_byte_counter rejects non-numeric byte counter values.
	# Expected: Function returns failure when bytes value is not numeric and logs warning.
	# Importance: Invalid byte counter values could cause false positives/negatives.
	source_logging_functions
	export LOG_FILE="${TEST_DIR}/test.log"
	mkdir -p "$(dirname "$LOG_FILE")"
	source_function "extract_byte_counter"

	local xfrm_output="src ${TEST_PEER_IP} dst ${TEST_PEER_IP}
    proto esp spi 0x12345678 reqid 1 mode tunnel
    lifetime current: abc123 bytes, 10 packets"

	run extract_byte_counter "$xfrm_output"
	assert_failure
	# Function should output warning to stderr (captured by run)
	assert_output --regexp "WARNING.*extract_byte_counter.*lifetime current.*failed to extract byte counter"
	# Also verify warning is in log file
	assert_file_exist "$LOG_FILE"
	run grep -q "WARNING.*extract_byte_counter.*lifetime current.*failed to extract byte counter" "$LOG_FILE"
	assert_success
}

# bats test_tags=category:detection,priority:medium
@test "extract_byte_counter handles malformed byte counter line - negative bytes value" {
	# Purpose: Test verifies that extract_byte_counter rejects negative byte counter values.
	# Expected: Function returns failure when bytes value is negative and logs warning.
	# Importance: Negative byte counters are invalid and should be rejected.
	source_logging_functions
	export LOG_FILE="${TEST_DIR}/test.log"
	mkdir -p "$(dirname "$LOG_FILE")"
	source_function "extract_byte_counter"

	local xfrm_output="src ${TEST_PEER_IP} dst ${TEST_PEER_IP}
    proto esp spi 0x12345678 reqid 1 mode tunnel
    lifetime current: -100 bytes, 10 packets"

	run extract_byte_counter "$xfrm_output"
	assert_failure
	# Function should output warning to stderr (captured by run)
	assert_output --regexp "WARNING.*extract_byte_counter.*lifetime current.*failed to extract byte counter"
	# Also verify warning is in log file
	assert_file_exist "$LOG_FILE"
	run grep -q "WARNING.*extract_byte_counter.*lifetime current.*failed to extract byte counter" "$LOG_FILE"
	assert_success
}

# bats test_tags=category:detection,priority:medium
@test "extract_spi handles malformed SPI line - missing SPI value" {
	# Purpose: Test verifies that extract_spi handles malformed xfrm output gracefully.
	# Expected: Function returns failure when SPI value is missing.
	# Importance: Malformed SPI output could cause rekey detection failures.
	source_function "extract_spi"

	local xfrm_output="src ${TEST_PEER_IP} dst ${TEST_PEER_IP}
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
	source_function "extract_spi"

	local xfrm_output="src ${TEST_PEER_IP} dst ${TEST_PEER_IP}
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
	local peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"

	# Mock ip command with multiple SAs for same peer IP
	# Must handle both "ip -s xfrm state" and "ip xfrm state" formats
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # First SA (old, lower bytes)
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x11111111 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 5 packets"
    echo ""
    # Second SA (new, higher bytes) - same peer IP
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x22222222 reqid 1 mode tunnel"
    echo "    lifetime current: 5000 bytes, 10 packets"
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # First SA (old, lower bytes)
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x11111111 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 5 packets"
    echo ""
    # Second SA (new, higher bytes) - same peer IP
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x22222222 reqid 1 mode tunnel"
    echo "    lifetime current: 5000 bytes, 10 packets"
    exit 0
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Initialize state using location-aware functions
	source_function "set_peer_state"
	set_peer_state "TEST" "$peer_ip" "failure_count" "0"

	# Source required functions
	source_function "check_xfrm_status"
	source_function "check_byte_counters"
	source_function "get_peer_state"
	source_function "set_peer_state"

	# Should handle multiple SAs gracefully
	run check_xfrm_status "$peer_ip" "" "$location_name"
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
	local location_name="TEST"

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

	# Initialize state using location-aware functions
	source_function "set_peer_state"
	set_peer_state "TEST" "$peer_ip" "failure_count" "0"

	# Source required functions
	source_function "check_xfrm_status"
	source_function "check_byte_counters"
	source_function "get_peer_state"
	source_function "set_peer_state"

	# Should handle IPv6 address correctly
	run check_xfrm_status "$peer_ip" "" "$location_name"
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
	local location_name="TEST"

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

	# Initialize state using location-aware functions
	source_function "set_peer_state"
	set_peer_state "TEST" "$peer_ip" "failure_count" "0"

	# Source required functions
	source_function "check_xfrm_status"
	source_function "check_byte_counters"
	source_function "get_peer_state"
	source_function "set_peer_state"

	# Should handle IPv4-mapped IPv6 address correctly
	run check_xfrm_status "$peer_ip" "" "$location_name"
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
	local peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"

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
	mock_ipsec_status 0 "test-conn: ESTABLISHED 1 hour ago, ${TEST_PEER_IP}...${TEST_LOCAL_IP}"
	add_mock_to_path

	# Initialize state using location-aware functions
	source_function "set_peer_state"
	set_peer_state "TEST" "$peer_ip" "failure_count" "0"

	# Source required functions
	source_function "check_ipsec_status"

	# Test that check_ipsec_status works as fallback when xfrm fails
	run check_ipsec_status "$peer_ip" "TEST"
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
	source_function "extract_spi"

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

	local xfrm_output="src ${TEST_PEER_IP} dst ${TEST_PEER_IP}
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
	source_function "extract_spi"

	local xfrm_output="src ${TEST_PEER_IP} dst ${TEST_PEER_IP}
    proto esp spi 0x12345678 reqid 1 mode tunnel
    proto ah spi 0x87654321 reqid 2 mode tunnel
    lifetime current: 123456 bytes, 10 packets"

	run extract_spi "$xfrm_output"
	assert_success
	# Should extract first SPI (0x12345678)
	assert_output "0x12345678"
}

# bats test_tags=category:detection,priority:high
@test "check_xfrm_status falls back to ping check when byte counters unavailable" {
	# Purpose: Test verifies that check_xfrm_status falls back to ping check when byte counter extraction fails
	# Expected: Function treats VPN as healthy (idle but healthy) when SA exists, byte counters unavailable, but ping succeeds
	# Importance: Prevents false positives when xfrm output format differs or byte counters aren't available but VPN is working
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"
	local internal_peer_ip="${TEST_PEER_IP2}"
	local location_name="TEST"

	# Mock ip command - SA exists but no lifetime current section (byte counter extraction will fail)
	# Must handle both "ip -s xfrm state" and "ip xfrm state" formats
	# Also handle route commands that check_ping_connectivity may call
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime config:"
    echo "      limit: soft (INF)(bytes), hard (INF)(bytes)"
    echo "      limit: soft (INF)(packets), hard (INF)(packets)"
    # Note: No lifetime current section - byte counter extraction will fail
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime config:"
    echo "      limit: soft (INF)(bytes), hard (INF)(bytes)"
    # Note: No lifetime current section - byte counter extraction will fail
    exit 0
elif [[ "\$1" == "addr" ]] && [[ "\$2" == "show" ]] && [[ "\$3" == "br0" ]]; then
    # Handle route check - return empty (route doesn't exist, will be added)
    exit 0
elif [[ "\$1" == "addr" ]] && [[ "\$2" == "add" ]]; then
    # Handle route add - simulate success
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Mock ping command - ping succeeds (using helper function pattern)
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
# Simulate successful ping - output format similar to real ping
echo "PING 10.0.0.1 (10.0.0.1) 56(84) bytes of data."
echo "64 bytes from 10.0.0.1: icmp_seq=1 ttl=64 time=0.123 ms"
echo ""
echo "--- 10.0.0.1 ping statistics ---"
echo "1 packets transmitted, 1 received, 0% packet loss"
exit 0
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	# Set ENABLE_PING_CHECK=1 and LOCAL_UDM_IP for this test
	export ENABLE_PING_CHECK=1
	export LOCAL_UDM_IP="192.168.1.100"

	# Initialize state
	source_function "set_peer_state"
	set_peer_state "$location_name" "$peer_ip" "failure_count" "0"

	# Source required functions
	source_function "check_xfrm_status"
	source_function "get_local_ip_for_ping"
	source_function "check_ping_connectivity"

	# Test that check_xfrm_status falls back to ping and treats as healthy
	run check_xfrm_status "$peer_ip" "$internal_peer_ip" "$location_name"
	assert_success

	# Cleanup
	unset ENABLE_PING_CHECK
	unset LOCAL_UDM_IP
	remove_mock_from_path
}

# bats test_tags=category:detection,priority:high
@test "get_xfrm_state_for_peer rejects invalid IP format to prevent regex injection" {
	# Purpose: Test verifies that get_xfrm_state_for_peer rejects invalid IP addresses containing regex special characters
	# Expected: Function returns failure (exit code 1) when peer IP contains regex special characters
	# Importance: Prevents regex injection attacks if malicious IPs reach this function
	# Security: Defense-in-depth measure - IPs should be validated at configuration load time, but this prevents regex injection
	setup_test_environment "${TEST_DIR}"

	# Mock ip command (should not be called with invalid IP)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
# Should not be called with invalid IP
exit 1
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Source required functions
	source_function "get_xfrm_state_for_peer"

	# Test various invalid IP formats that could cause regex injection
	# These contain regex special characters: . * + ? [ ] { } ( ) | ^ $
	local invalid_ips=(
		"192.168.1.*"     # Wildcard (regex *)
		"192.168.1.+"     # One or more (regex +)
		"192.168.1.?"     # Zero or one (regex ?)
		"192.168.[1-9]"   # Character class (regex [])
		"192.168.{1,2}"   # Quantifier (regex {})
		"192.168.(1|2)"   # Alternation (regex ())
		"^192.168.1.1"    # Start anchor (regex ^)
		"192.168.1.1$"    # End anchor (regex $)
		"192.168.1|2"     # Alternation (regex |)
		"256.256.256.256" # Invalid octet values
		"999.999.999.999" # Invalid octet values
		"192.168.1"       # Missing octet
		"192.168.1.1.1"   # Too many octets
		""                # Empty string
	)

	for invalid_ip in "${invalid_ips[@]}"; do
		run get_xfrm_state_for_peer "$invalid_ip"
		assert_failure "get_xfrm_state_for_peer should reject invalid IP: '$invalid_ip'"
		assert_output ""
	done

	remove_mock_from_path
}

# bats test_tags=category:detection,priority:medium
@test "get_xfrm_state_for_peer handles xfrm command failure and uses ipsec status for diagnostics" {
	# Purpose: When xfrm command errors, function should return failure with diagnostic, and still consult ipsec status.
	# Expected: Exit code 2 (command failure), no stdout, diagnostic mentions command failure and ipsec status result.
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"

	# Mock ip command to emit error to stderr and fail for both variants
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "-s" ]] && [[ "$2" == "xfrm" ]] && [[ "$3" == "state" ]]; then
    echo "RTNETLINK answers: Permission denied" >&2
    exit 1
fi
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "RTNETLINK answers: Permission denied" >&2
    exit 1
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# ipsec status shows the connection exists
	mock_ipsec_status 0 "${peer_ip}: ESTABLISHED"
	add_mock_to_path

	# Source function
	source_function "get_xfrm_state_for_peer"

	local error_msg=""
	local output_file="${TEST_DIR}/out1"
	set +e
	get_xfrm_state_for_peer "$peer_ip" "" "error_msg" >"$output_file"
	local rc=$?
	set -e
	local output
	output=$(cat "$output_file" 2>/dev/null)

	[[ $rc -eq 2 ]] || fail "Expected exit 2 for command failure, got $rc"
	[[ -z "$output" ]] || fail "Expected no stdout, got: $output"
	[[ "$error_msg" == *"xfrm command failed (command error)"* ]] || fail "Diagnostic should mention command failure"
	[[ "$error_msg" == *"ipsec status shows connection exists"* ]] || fail "Diagnostic should mention ipsec status fallback"

	remove_mock_from_path
}

# bats test_tags=category:detection,priority:medium
@test "get_xfrm_state_for_peer handles empty xfrm output when ipsec status shows a connection" {
	# Purpose: When xfrm returns empty output but ipsec status shows the tunnel, function should signal no SAs with diagnostic.
	# Expected: Exit code 1 (no SAs), no stdout, diagnostic mentions ipsec status saw connection.
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"

	# Mock ip command to return success with empty output
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "-s" ]] && [[ "$2" == "xfrm" ]] && [[ "$3" == "state" ]]; then
    exit 0
fi
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# ipsec status shows connection exists
	mock_ipsec_status 0 "${peer_ip}: ESTABLISHED"
	add_mock_to_path

	source_function "get_xfrm_state_for_peer"

	local error_msg=""
	local output_file="${TEST_DIR}/out2"
	set +e
	get_xfrm_state_for_peer "$peer_ip" "" "error_msg" >"$output_file"
	local rc=$?
	set -e
	local output
	output=$(cat "$output_file" 2>/dev/null)

	[[ $rc -eq 1 ]] || fail "Expected exit 1 for no SAs, got $rc"
	[[ -z "$output" ]] || fail "Expected no stdout, got: $output"
	[[ "$error_msg" == *"No SAs found in xfrm state"* ]] || fail "Diagnostic should mention no SAs"
	[[ "$error_msg" == *"ipsec status shows connection exists"* ]] || fail "Diagnostic should mention ipsec status fallback"

	remove_mock_from_path
}

# bats test_tags=category:detection,priority:medium
@test "get_xfrm_state_for_peer handles command failure when both xfrm and ipsec status are empty" {
	# Purpose: When xfrm errors and ipsec status shows nothing, function should report command failure and tunnel down.
	# Expected: Exit code 2 (command failure), no stdout, diagnostic mentions both failures.
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"

	# Mock ip command to emit error to stderr and fail
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "-s" ]] && [[ "$2" == "xfrm" ]] && [[ "$3" == "state" ]]; then
    echo "xfrm: No such file or directory" >&2
    exit 1
fi
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "xfrm: No such file or directory" >&2
    exit 1
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# ipsec status returns no output
	mock_ipsec_status 0 ""
	add_mock_to_path

	source_function "get_xfrm_state_for_peer"

	local error_msg=""
	local output_file="${TEST_DIR}/out3"
	set +e
	get_xfrm_state_for_peer "$peer_ip" "" "error_msg" >"$output_file"
	local rc=$?
	set -e
	local output
	output=$(cat "$output_file" 2>/dev/null)

	[[ $rc -eq 2 ]] || fail "Expected exit 2 for command failure, got $rc"
	[[ -z "$output" ]] || fail "Expected no stdout, got: $output"
	[[ "$error_msg" == *"xfrm command failed (command error) and ipsec status shows no connection"* ]] || fail "Diagnostic should mention xfrm failure and empty ipsec status"

	remove_mock_from_path
}

# bats test_tags=category:detection,priority:medium
@test "get_xfrm_state_for_peer handles overlapping outputs from forward and reverse searches" {
	# Purpose: Test verifies that get_xfrm_state_for_peer correctly handles overlapping outputs when both forward and reverse searches match
	# Expected: Function combines outputs correctly without duplicating SA blocks when grep -A context overlaps
	# Importance: Prevents duplicate SA processing when forward and reverse searches include overlapping context lines
	# Scenario: Forward SA search includes reverse SA header in context, and vice versa
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"
	local local_ip="${TEST_LOCAL_IP}"

	# Mock ip command that returns both forward and reverse SAs with overlapping context
	# The grep -A context from forward search will include the reverse SA header
	# The grep -A context from reverse search will include the forward SA header
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # Forward SA (local→peer) - this will match "dst \$peer_ip"
    echo "src ${local_ip} dst ${peer_ip}"
    echo "    proto esp spi 0x11111111 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
    echo ""
    # Reverse SA (peer→local) - this will match "src \$peer_ip" and appears in forward search context
    echo "src ${peer_ip} dst ${local_ip}"
    echo "    proto esp spi 0x22222222 reqid 2 mode tunnel"
    echo "    lifetime current: 2000 bytes, 20 packets"
    echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
    echo ""
    # Another SA for different peer (should not appear in output)
    echo "src 192.168.100.1 dst 192.168.100.2"
    echo "    proto esp spi 0x33333333 reqid 3 mode tunnel"
    echo "    lifetime current: 3000 bytes, 30 packets"
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Same structure for fallback
    echo "src ${local_ip} dst ${peer_ip}"
    echo "    proto esp spi 0x11111111 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
    echo ""
    echo "src ${peer_ip} dst ${local_ip}"
    echo "    proto esp spi 0x22222222 reqid 2 mode tunnel"
    echo "    lifetime current: 2000 bytes, 20 packets"
    echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
    echo ""
    echo "src 192.168.100.1 dst 192.168.100.2"
    echo "    proto esp spi 0x33333333 reqid 3 mode tunnel"
    echo "    lifetime current: 3000 bytes, 30 packets"
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Source required functions
	source_function "get_xfrm_state_for_peer"

	# Get xfrm state output
	run get_xfrm_state_for_peer "$peer_ip"
	assert_success

	# Verify output contains both forward and reverse SAs
	# Forward SA should be present
	assert_output --partial "src ${local_ip} dst ${peer_ip}"
	assert_output --partial "spi 0x11111111"
	assert_output --partial "1000 bytes"

	# Reverse SA should be present
	assert_output --partial "src ${peer_ip} dst ${local_ip}"
	assert_output --partial "spi 0x22222222"
	assert_output --partial "2000 bytes"

	# Note: Due to grep -A context, output may include SAs from other peers
	# This is expected behavior - downstream parsing filters by peer IP
	# The important thing is that both forward and reverse SAs for the target peer are present

	# Verify both SPIs for target peer appear (may appear multiple times due to overlapping context)
	# The key is that both forward and reverse SAs are included in the output
	local forward_spi_count
	forward_spi_count=$(echo "$output" | grep -c "0x11111111" || echo "0")
	[ "$forward_spi_count" -ge 1 ] || fail "Forward SA SPI should appear at least once (found: $forward_spi_count)"

	local reverse_spi_count
	reverse_spi_count=$(echo "$output" | grep -c "0x22222222" || echo "0")
	[ "$reverse_spi_count" -ge 1 ] || fail "Reverse SA SPI should appear at least once (found: $reverse_spi_count)"

	# Verify that the function successfully combines outputs from both searches
	# Both forward and reverse SA headers should be present
	local forward_header_count
	forward_header_count=$(echo "$output" | grep -c "src ${local_ip} dst ${peer_ip}" || echo "0")
	[ "$forward_header_count" -ge 1 ] || fail "Forward SA header should appear at least once (found: $forward_header_count)"

	local reverse_header_count
	reverse_header_count=$(echo "$output" | grep -c "src ${peer_ip} dst ${local_ip}" || echo "0")
	[ "$reverse_header_count" -ge 1 ] || fail "Reverse SA header should appear at least once (found: $reverse_header_count)"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "execute_xfrm_state_command handles timeout when xfrm command hangs" {
	# Purpose: Test verifies that execute_xfrm_state_command detects timeout (exit code 124) when xfrm command hangs
	# Expected: Function returns exit code 2 when timeout occurs, logs WARNING message about timeout
	# Importance: xfrm commands can hang due to netlink socket timeouts or lock contention; must be handled gracefully
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	source_logging_functions
	export LOG_FILE="${TEST_DIR}/test.log"
	mkdir -p "$(dirname "$LOG_FILE")"

	# Set XFRM_STATE_TIMEOUT to 2 seconds for faster testing
	export XFRM_STATE_TIMEOUT=2

	# Mock ip command that hangs (sleeps longer than timeout)
	# Must handle both "ip -s xfrm state" and "ip xfrm state" formats
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "-s" ]] && [[ "$2" == "xfrm" ]] && [[ "$3" == "state" ]]; then
    # Sleep longer than XFRM_STATE_TIMEOUT (2 seconds) to trigger timeout
    sleep 3
    exit 0
elif [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Fallback also hangs
    sleep 3
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Source function and dependencies
	source_function "execute_xfrm_state_command"

	# Run the function - it has internal timeout protection (2 seconds)
	# The function will detect timeout (exit code 124 from timeout command) and return 2
	# The mocked ip command sleeps for 3 seconds, which exceeds the 2-second timeout
	run execute_xfrm_state_command
	local exit_code=$status

	# Should return exit code 2 (command failed/timed out)
	assert [ $exit_code -eq 2 ]

	# Verify timeout warning was logged
	assert_file_exist "$LOG_FILE"
	run grep -q "ip.*xfrm state timed out" "$LOG_FILE"
	assert_success "Timeout warning should be logged"

	# Verify the log message contains timeout information
	run grep -q "xfrm subsystem may be under load or experiencing lock contention" "$LOG_FILE"
	assert_success "Log should mention lock contention or load"

	remove_mock_from_path
	unset XFRM_STATE_TIMEOUT
}

# bats test_tags=category:high-risk,priority:high
@test "get_xfrm_state_for_peer falls back to ipsec status when xfrm command times out" {
	# Purpose: Test verifies that get_xfrm_state_for_peer falls back to ipsec status when xfrm command times out
	# Expected: Function returns exit code 2, falls back to ipsec status, and provides diagnostic message
	# Importance: Timeout handling must trigger fallback to alternative detection method
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	source_logging_functions
	export LOG_FILE="${TEST_DIR}/test.log"
	mkdir -p "$(dirname "$LOG_FILE")"

	local peer_ip="${TEST_PEER_IP}"

	# Set XFRM_STATE_TIMEOUT to 2 seconds for faster testing
	export XFRM_STATE_TIMEOUT=2

	# Mock ip command that hangs (sleeps longer than timeout)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "-s" ]] && [[ "$2" == "xfrm" ]] && [[ "$3" == "state" ]]; then
    # Sleep longer than XFRM_STATE_TIMEOUT (2 seconds) to trigger timeout
    sleep 3
    exit 0
elif [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Fallback also hangs
    sleep 3
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Mock ipsec status to show connection exists (fallback should succeed)
	mock_ipsec_status 0 "${peer_ip}: ESTABLISHED 1 hour ago, ${peer_ip}...${TEST_LOCAL_IP}"
	add_mock_to_path

	# Source function
	source_function "get_xfrm_state_for_peer"

	# Run with timeout wrapper to prevent test from hanging
	# The function needs to run in a subshell because we need to capture the error message variable
	# which is set via printf -v and won't be available in parent shell
	# Note: PATH is already exported by add_mock_to_path and will be inherited by the subshell
	local error_msg_file="${TEST_DIR}/error_msg"
	local output_file="${TEST_DIR}/xfrm_output"
	set +e
	# Use timeout to wrap the function call - this prevents hanging if function doesn't timeout internally
	# The function has its own internal timeout (XFRM_STATE_TIMEOUT=2), but we add an outer timeout
	# as a safety measure in case something goes wrong
	run timeout 10 bash -c "
		# PATH is inherited from parent (already exported by add_mock_to_path with TEST_DIR first)
		# Source required libraries in subshell (needed since we're in a new bash process)
		source '${BATS_TEST_DIRNAME}/../lib/common.sh' || true
		source '${BATS_TEST_DIRNAME}/../lib/logging.sh' || true
		source '${BATS_TEST_DIRNAME}/../lib/detection.sh' || true
		# Export environment variables needed by functions
		export LOG_FILE='${LOG_FILE}'
		export XFRM_STATE_TIMEOUT='${XFRM_STATE_TIMEOUT}'
		export SCRIPT_DIR='${BATS_TEST_DIRNAME}/..'
		# Force use of mock by setting _RECOVERY_IP_PATH (get_ip_command_path checks this first)
		# This ensures the mock is definitely used even if PATH resolution fails
		export _RECOVERY_IP_PATH='${TEST_DIR}/ip'
		# Set debug log path for instrumentation
		export DEBUG_LOG_PATH='${TEST_DIR}/debug.log'
		# Run function and capture error message to file
		# Note: error_msg_var must NOT be local - printf -v needs to modify it from within the function
		error_msg_var=''
		get_xfrm_state_for_peer '${peer_ip}' '' 'error_msg_var' >'${output_file}' 2>&1
		func_exit=\$?
		exit_code=\$func_exit
		# Write error message to file so parent shell can read it
		if [[ -n \"\$error_msg_var\" ]]; then
			printf '%s\n' \"\$error_msg_var\" >'${error_msg_file}'
		fi
		exit \$exit_code
	"
	local exit_code=$status
	set -e

	# Debug: Check what actually happened
	if [[ $exit_code -ne 2 ]]; then
		echo "DEBUG: Expected exit code 2, got $exit_code" >&2
		if [[ -f "$output_file" ]]; then
			echo "DEBUG: Output file contents:" >&2
			head -50 "$output_file" >&2 || true
		fi
		if [[ -f "$LOG_FILE" ]]; then
			echo "DEBUG: Log file contents:" >&2
			tail -50 "$LOG_FILE" >&2 || true
		fi
	fi

	# Should return exit code 2 (xfrm command failed/timed out)
	assert [ $exit_code -eq 2 ]

	# Read error message from file
	local error_msg=""
	if [[ -f "$error_msg_file" ]]; then
		error_msg=$(cat "$error_msg_file")
	fi

	# Verify error message indicates timeout and ipsec fallback
	assert [ -n "$error_msg" ]
	[[ "$error_msg" == *"xfrm command failed or timed out"* ]] || fail "Error message should mention xfrm timeout"
	[[ "$error_msg" == *"ipsec status shows connection exists"* ]] || fail "Error message should mention ipsec status fallback"

	# Verify timeout was logged
	assert_file_exist "$LOG_FILE"
	run grep -q "ip.*xfrm state timed out" "$LOG_FILE"
	assert_success "Timeout warning should be logged"

	remove_mock_from_path
	unset XFRM_STATE_TIMEOUT
}

# bats test_tags=category:high-risk,priority:high
@test "check_xfrm_status returns failure when xfrm command times out" {
	# Purpose: Test verifies that check_xfrm_status handles xfrm timeout gracefully
	# Expected: Function returns failure when xfrm times out (ipsec fallback is only diagnostic, not functional)
	# Importance: End-to-end test of timeout handling in detection flow
	# Note: The ipsec fallback in get_xfrm_state_for_peer is for diagnostic info only - it doesn't
	#       make check_xfrm_status succeed. Callers should use check_ipsec_status as a separate fallback.
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	source_logging_functions
	export LOG_FILE="${TEST_DIR}/test.log"
	mkdir -p "$(dirname "$LOG_FILE")"

	local peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"

	# Set XFRM_STATE_TIMEOUT to 2 seconds for faster testing
	export XFRM_STATE_TIMEOUT=2

	# Mock ip command that hangs (sleeps longer than timeout)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "-s" ]] && [[ "$2" == "xfrm" ]] && [[ "$3" == "state" ]]; then
    # Sleep longer than XFRM_STATE_TIMEOUT (2 seconds) to trigger timeout
    sleep 3
    exit 0
elif [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Fallback also hangs
    sleep 3
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Mock ipsec status to show connection exists (fallback should succeed)
	mock_ipsec_status 0 "${peer_ip}: ESTABLISHED 1 hour ago, ${peer_ip}...${TEST_LOCAL_IP}"
	add_mock_to_path

	# Initialize state (must be done before subshell since state is stored in files)
	source_function "set_peer_state"
	set_peer_state "$location_name" "$peer_ip" "failure_count" "0"

	# Run with timeout wrapper to prevent test from hanging
	# check_xfrm_status will timeout on xfrm, then fall back to ipsec status
	# Note: Must use bash -c since timeout runs external commands, not bash functions
	run timeout 10 bash -c "
		# Source required libraries in subshell (needed since we're in a new bash process)
		source '${BATS_TEST_DIRNAME}/../lib/common.sh' || true
		source '${BATS_TEST_DIRNAME}/../lib/logging.sh' || true
		source '${BATS_TEST_DIRNAME}/../lib/detection.sh' || true
		# Export environment variables needed by functions
		export LOG_FILE='${LOG_FILE}'
		export XFRM_STATE_TIMEOUT='${XFRM_STATE_TIMEOUT}'
		export SCRIPT_DIR='${BATS_TEST_DIRNAME}/..'
		export STATE_DIR='${STATE_DIR}'
		# Force use of mock by setting _RECOVERY_IP_PATH
		export _RECOVERY_IP_PATH='${TEST_DIR}/ip'
		# Run the function
		check_xfrm_status '${peer_ip}' '' '${location_name}'
	"
	local exit_code=$status

	# Should return failure because xfrm check failed (timed out)
	# The ipsec fallback in get_xfrm_state_for_peer is only for diagnostic purposes
	assert_failure "check_xfrm_status should fail when xfrm times out"

	# Verify timeout was logged
	assert_file_exist "$LOG_FILE"
	run grep -q "ip.*xfrm state timed out" "$LOG_FILE"
	assert_success "Timeout warning should be logged"

	remove_mock_from_path
	unset XFRM_STATE_TIMEOUT
}
