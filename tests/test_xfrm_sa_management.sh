#!/usr/bin/env bats
#
# Tests for XFRM SA Management Functions
# Tests parse_xfrm_output_to_sa_list, delete_sas_from_list, delete_stale_sas,
# delete_xfrm_policies, and count_sas_for_peer functions
#
# These tests address the gap identified in TEST_INFRASTRUCTURE_REVIEW.md Section "Critical: Recovery Operations"
# Functions tested are core to VPN recovery but previously had no direct tests.

load test_helper
load helpers/logging

# ============================================================================
# PARSE_XFRM_OUTPUT_TO_SA_LIST TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "parse_xfrm_output_to_sa_list - parses single SA with all selectors" {
	# Purpose: Test verifies that parse_xfrm_output_to_sa_list correctly parses a single SA with all required selectors
	# Expected: Function parses SA and returns it in the sa_list array
	# Importance: SA parsing is critical for xfrm recovery - parsing errors break recovery
	source_recovery_module

	local xfrm_output="src 192.168.1.2 dst ${TEST_PEER_IP}
  proto esp spi 0x12345678
  mode tunnel
  reqid 1"

	# Call directly (not via run) because nameref doesn't cross subshell boundary
	local sa_list=()
	parse_xfrm_output_to_sa_list "$xfrm_output" "${TEST_PEER_IP}" "TEST" "sa_list"
	assert [ ${#sa_list[@]} -eq 1 ]

	# Verify SA format: "src|dst|proto|spi|mark"
	local sa_entry="${sa_list[0]}"
	IFS='|' read -r sa_src sa_dst sa_proto sa_spi sa_mark <<<"$sa_entry"
	assert_equal "$sa_src" "192.168.1.2"
	assert_equal "$sa_dst" "${TEST_PEER_IP}"
	assert_equal "$sa_proto" "esp"
	assert_equal "$sa_spi" "0x12345678"
	# Mark should be empty for this SA
	assert_equal "$sa_mark" ""
}

# bats test_tags=category:high-risk,priority:high
@test "parse_xfrm_output_to_sa_list - parses multiple SAs" {
	# Purpose: Test verifies that parse_xfrm_output_to_sa_list correctly parses multiple SAs
	# Expected: Function parses all matching SAs and returns them in the sa_list array
	# Importance: Multiple SAs are common (bidirectional tunnels, multiple subnets)
	source_recovery_module

	local xfrm_output="src 192.168.1.2 dst ${TEST_PEER_IP}
  proto esp spi 0x12345678
  mode tunnel
src ${TEST_PEER_IP} dst 192.168.1.2
  proto esp spi 0x87654321
  mode tunnel"

	# Call directly (not via run) because nameref doesn't cross subshell boundary
	local sa_list=()
	parse_xfrm_output_to_sa_list "$xfrm_output" "${TEST_PEER_IP}" "TEST" "sa_list"
	assert [ ${#sa_list[@]} -eq 2 ]

	# Verify first SA (forward)
	local sa_entry="${sa_list[0]}"
	IFS='|' read -r sa_src sa_dst sa_proto sa_spi sa_mark <<<"$sa_entry"
	assert_equal "$sa_src" "192.168.1.2"
	assert_equal "$sa_dst" "${TEST_PEER_IP}"
	assert_equal "$sa_proto" "esp"
	assert_equal "$sa_spi" "0x12345678"

	# Verify second SA (reverse)
	sa_entry="${sa_list[1]}"
	IFS='|' read -r sa_src sa_dst sa_proto sa_spi sa_mark <<<"$sa_entry"
	assert_equal "$sa_src" "${TEST_PEER_IP}"
	assert_equal "$sa_dst" "192.168.1.2"
	assert_equal "$sa_proto" "esp"
	assert_equal "$sa_spi" "0x87654321"
}

# bats test_tags=category:high-risk,priority:high
@test "parse_xfrm_output_to_sa_list - parses SA with mark selector" {
	# Purpose: Test verifies that parse_xfrm_output_to_sa_list correctly parses SAs with mark selectors
	# Expected: Function includes mark in the parsed SA entry
	# Importance: Mark is a required selector when present - must be included for successful deletion
	source_recovery_module

	local xfrm_output="src 192.168.1.2 dst ${TEST_PEER_IP}
  proto esp spi 0x12345678
  mark 0x12000000/0xfe000000
  mode tunnel"

	# Call directly (not via run) because nameref doesn't cross subshell boundary
	local sa_list=()
	parse_xfrm_output_to_sa_list "$xfrm_output" "${TEST_PEER_IP}" "TEST" "sa_list"
	assert [ ${#sa_list[@]} -eq 1 ]

	local sa_entry="${sa_list[0]}"
	IFS='|' read -r sa_src sa_dst sa_proto sa_spi sa_mark <<<"$sa_entry"
	assert_equal "$sa_src" "192.168.1.2"
	assert_equal "$sa_dst" "${TEST_PEER_IP}"
	assert_equal "$sa_proto" "esp"
	assert_equal "$sa_spi" "0x12345678"
	assert_equal "$sa_mark" "0x12000000/0xfe000000"
}

# bats test_tags=category:high-risk,priority:high
@test "parse_xfrm_output_to_sa_list - filters SAs by peer IP" {
	# Purpose: Test verifies that parse_xfrm_output_to_sa_list only includes SAs matching the target peer IP
	# Expected: Function excludes SAs for other peer IPs
	# Importance: Prevents deleting SAs for wrong locations
	source_recovery_module

	local xfrm_output="src 192.168.1.2 dst ${TEST_PEER_IP}
  proto esp spi 0x12345678
  mode tunnel
src 192.168.1.2 dst 10.0.0.1
  proto esp spi 0x11111111
  mode tunnel"

	# Call directly (not via run) because nameref doesn't cross subshell boundary
	local sa_list=()
	parse_xfrm_output_to_sa_list "$xfrm_output" "${TEST_PEER_IP}" "TEST" "sa_list"
	# Should only include SA for TEST_PEER_IP, not 10.0.0.1
	assert [ ${#sa_list[@]} -eq 1 ]

	local sa_entry="${sa_list[0]}"
	IFS='|' read -r sa_src sa_dst sa_proto sa_spi sa_mark <<<"$sa_entry"
	assert_equal "$sa_dst" "${TEST_PEER_IP}"
}

# bats test_tags=category:high-risk,priority:high
@test "parse_xfrm_output_to_sa_list - handles empty output" {
	# Purpose: Test verifies that parse_xfrm_output_to_sa_list handles empty xfrm output gracefully
	# Expected: Function returns success with empty sa_list when no SAs found
	# Importance: Empty output is valid (no SAs exist) - should not fail
	source_recovery_module

	local xfrm_output=""
	# Call directly (not via run) because nameref doesn't cross subshell boundary
	local sa_list=()
	parse_xfrm_output_to_sa_list "$xfrm_output" "${TEST_PEER_IP}" "TEST" "sa_list"
	assert [ ${#sa_list[@]} -eq 0 ]
}

# bats test_tags=category:high-risk,priority:high
@test "parse_xfrm_output_to_sa_list - rejects invalid proto" {
	# Purpose: Test verifies that parse_xfrm_output_to_sa_list rejects SAs with invalid protocol
	# Expected: Function returns failure when all SAs have invalid selectors
	# Importance: Invalid selectors should be rejected to prevent deletion failures
	source_recovery_module

	local xfrm_output="src 192.168.1.2 dst ${TEST_PEER_IP}
  proto invalid spi 0x12345678
  mode tunnel"

	# Call directly and capture return value
	local sa_list=()
	local result=0
	parse_xfrm_output_to_sa_list "$xfrm_output" "${TEST_PEER_IP}" "TEST" "sa_list" || result=$?
	# Should fail because the SA has invalid proto
	assert [ "$result" -ne 0 ]
	assert [ ${#sa_list[@]} -eq 0 ]
}

# bats test_tags=category:high-risk,priority:high
@test "parse_xfrm_output_to_sa_list - skips SAs with unparseable SPI" {
	# Purpose: Test verifies that parse_xfrm_output_to_sa_list skips SAs where SPI cannot be parsed
	# Expected: Function returns success with empty list (SA treated as incomplete, not invalid)
	# Importance: Unparseable SPI means the regex didn't match - SA is incomplete, not a parse error
	# Note: An "invalid" SPI value doesn't match the SPI regex, so the SA is never completed
	source_recovery_module

	local xfrm_output="src 192.168.1.2 dst ${TEST_PEER_IP}
  proto esp spi invalid
  mode tunnel"

	# Call directly (not via run) because nameref doesn't cross subshell boundary
	local sa_list=()
	parse_xfrm_output_to_sa_list "$xfrm_output" "${TEST_PEER_IP}" "TEST" "sa_list"
	# Function returns success but with empty list (SA was incomplete, not invalid)
	# Incomplete SAs are silently skipped, while invalid SAs (all selectors present but bad values) trigger parse errors
	assert [ ${#sa_list[@]} -eq 0 ]
}

# bats test_tags=category:high-risk,priority:high
@test "parse_xfrm_output_to_sa_list - handles proto and spi on same line" {
	# Purpose: Test verifies that parse_xfrm_output_to_sa_list handles proto and spi on the same line
	# Expected: Function correctly extracts both proto and spi from same line
	# Importance: xfrm output format varies - must handle both formats
	source_recovery_module

	local xfrm_output="src 192.168.1.2 dst ${TEST_PEER_IP}
  proto esp spi 0x12345678
  mode tunnel"

	# Call directly (not via run) because nameref doesn't cross subshell boundary
	local sa_list=()
	parse_xfrm_output_to_sa_list "$xfrm_output" "${TEST_PEER_IP}" "TEST" "sa_list"
	assert [ ${#sa_list[@]} -eq 1 ]

	local sa_entry="${sa_list[0]}"
	IFS='|' read -r sa_src sa_dst sa_proto sa_spi sa_mark <<<"$sa_entry"
	assert_equal "$sa_proto" "esp"
	assert_equal "$sa_spi" "0x12345678"
}

# bats test_tags=category:high-risk,priority:high
@test "parse_xfrm_output_to_sa_list - handles large output size limit" {
	# Purpose: Test verifies that parse_xfrm_output_to_sa_list rejects output exceeding size limit
	# Expected: Function returns failure when output exceeds XFRM_PARSE_MAX_SIZE_BYTES
	# Importance: Prevents DoS from excessive processing time
	source_recovery_module

	# Create large xfrm output (exceeds default 51200 bytes)
	local large_output=""
	local i=0
	while [[ $i -lt 10000 ]]; do
		large_output="${large_output}src 192.168.1.2 dst ${TEST_PEER_IP}
  proto esp spi 0x12345678
  mode tunnel
"
		i=$((i + 1))
	done

	# Call directly and capture return value
	local sa_list=()
	local result=0
	parse_xfrm_output_to_sa_list "$large_output" "${TEST_PEER_IP}" "TEST" "sa_list" || result=$?
	# Should fail due to size limit
	assert [ "$result" -ne 0 ]
}

# ============================================================================
# DELETE_SAS_FROM_LIST TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "delete_sas_from_list - deletes single SA successfully" {
	# Purpose: Test verifies that delete_sas_from_list successfully deletes a single SA
	# Expected: Function executes ip xfrm state delete command and returns success
	# Importance: SA deletion is core to xfrm recovery - deletion failures break recovery
	source_recovery_module

	# Create mock ip command that succeeds for delete and get
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    if [[ "$3" == "delete" ]]; then
        exit 0
    elif [[ "$3" == "get" ]]; then
        # Return mock SA output for get command
        echo "src 192.168.1.2 dst 192.168.1.1"
        echo "  proto esp spi 0x12345678"
        echo "  mode tunnel"
        exit 0
    fi
fi
exit 0
EOF
	chmod +x "$mock_ip"
	add_mock_to_path
	# Set _RECOVERY_IP_PATH to mock since get_command_path() bypasses PATH for reliability
	export _RECOVERY_IP_PATH="$mock_ip"

	local sa_list=("192.168.1.2|${TEST_PEER_IP}|esp|0x12345678|")
	local deleted_count=0
	local failed_count=0

	# Call directly (not via run) because nameref doesn't cross subshell boundary
	delete_sas_from_list "${sa_list[@]}" "${TEST_PEER_IP}" "TEST" deleted_count failed_count
	assert_equal "$deleted_count" 1
	assert_equal "$failed_count" 0

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "delete_sas_from_list - deletes SA with mark selector" {
	# Purpose: Test verifies that delete_sas_from_list includes mark selector in deletion command
	# Expected: Function includes mark value and mask in deletion command
	# Importance: Mark is required selector when present - must be included for successful deletion
	source_recovery_module

	# Create mock ip command that verifies mark is included
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    if [[ "$3" == "delete" ]]; then
        # Verify mark selector is included in command
        local found_mark=0
        for arg in "$@"; do
            if [[ "$arg" == "mark" ]]; then
                found_mark=1
                break
            fi
        done
        if [[ $found_mark -eq 0 ]]; then
            echo "ERROR: mark selector missing" >&2
            exit 1
        fi
        exit 0
    elif [[ "$3" == "get" ]]; then
        # Return mock SA output for get command
        echo "src 192.168.1.2 dst 192.168.1.1"
        echo "  proto esp spi 0x12345678"
        echo "  mark 0x12000000/0xfe000000"
        echo "  mode tunnel"
        exit 0
    fi
fi
exit 0
EOF
	chmod +x "$mock_ip"
	add_mock_to_path
	# Set _RECOVERY_IP_PATH to mock since get_command_path() bypasses PATH for reliability
	export _RECOVERY_IP_PATH="$mock_ip"

	local sa_list=("192.168.1.2|${TEST_PEER_IP}|esp|0x12345678|0x12000000/0xfe000000")
	local deleted_count=0
	local failed_count=0

	# Call directly (not via run) because nameref doesn't cross subshell boundary
	delete_sas_from_list "${sa_list[@]}" "${TEST_PEER_IP}" "TEST" deleted_count failed_count
	assert_equal "$deleted_count" 1
	assert_equal "$failed_count" 0

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "delete_sas_from_list - handles deletion failure" {
	# Purpose: Test verifies that delete_sas_from_list handles deletion failures gracefully
	# Expected: Function tracks failed_count and returns failure if all deletions fail
	# Importance: Deletion failures must be tracked and reported correctly
	source_recovery_module

	# Create mock ip command that fails for delete but handles get
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    if [[ "$3" == "delete" ]]; then
        echo "ERROR: Deletion failed" >&2
        exit 1
    elif [[ "$3" == "get" ]]; then
        # Return mock SA output for get command
        echo "src 192.168.1.2 dst 192.168.1.1"
        echo "  proto esp spi 0x12345678"
        echo "  mode tunnel"
        exit 0
    fi
fi
exit 0
EOF
	chmod +x "$mock_ip"
	add_mock_to_path
	# Set _RECOVERY_IP_PATH to mock since get_command_path() bypasses PATH for reliability
	export _RECOVERY_IP_PATH="$mock_ip"

	local sa_list=("192.168.1.2|${TEST_PEER_IP}|esp|0x12345678|")
	local deleted_count=0
	local failed_count=0

	# Call directly and capture return value
	local result=0
	delete_sas_from_list "${sa_list[@]}" "${TEST_PEER_IP}" "TEST" deleted_count failed_count || result=$?
	assert [ "$result" -ne 0 ]
	assert_equal "$deleted_count" 0
	assert_equal "$failed_count" 1

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "delete_sas_from_list - handles multiple SAs with partial failures" {
	# Purpose: Test verifies that delete_sas_from_list handles multiple SAs with some failures
	# Expected: Function tracks both deleted_count and failed_count correctly
	# Importance: Partial failures are common - must track both successes and failures
	source_recovery_module

	# Create mock ip command that fails for specific SPI
	local delete_call_count=0
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    if [[ "$3" == "delete" ]]; then
        # Count delete calls
        echo "$(( $(cat MOCK_DELETE_COUNT_FILE 2>/dev/null || echo "0") + 1 ))" > MOCK_DELETE_COUNT_FILE
        # Fail for second SA (spi 0x87654321)
        if grep -q "0x87654321" <<<"$*"; then
            echo "ERROR: Deletion failed" >&2
            exit 1
        fi
        exit 0
    elif [[ "$3" == "get" ]]; then
        # Return mock SA output for get command
        echo "src 192.168.1.2 dst 192.168.1.1"
        echo "  proto esp spi 0x12345678"
        echo "  mode tunnel"
        exit 0
    fi
fi
exit 0
EOF
	sed -i "s|MOCK_DELETE_COUNT_FILE|${TEST_DIR}/delete_count|g" "$mock_ip"
	chmod +x "$mock_ip"
	add_mock_to_path
	# Set _RECOVERY_IP_PATH to mock since get_command_path() bypasses PATH for reliability
	export _RECOVERY_IP_PATH="$mock_ip"

	local sa_list=(
		"192.168.1.2|${TEST_PEER_IP}|esp|0x12345678|"
		"${TEST_PEER_IP}|192.168.1.2|esp|0x87654321|"
	)
	local deleted_count=0
	local failed_count=0

	# Call directly (not via run) because nameref doesn't cross subshell boundary
	# Should succeed if at least one deletion succeeded
	delete_sas_from_list "${sa_list[@]}" "${TEST_PEER_IP}" "TEST" deleted_count failed_count
	assert_equal "$deleted_count" 1
	assert_equal "$failed_count" 1

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "delete_sas_from_list - handles empty SA list" {
	# Purpose: Test verifies that delete_sas_from_list handles empty SA list gracefully
	# Expected: Function returns success with zero counts when no SAs to delete
	# Importance: Empty list is valid (no SAs found) - should not fail
	source_recovery_module

	local sa_list=()
	local deleted_count=0
	local failed_count=0

	# Call directly (not via run) because nameref doesn't cross subshell boundary
	delete_sas_from_list "${sa_list[@]}" "${TEST_PEER_IP}" "TEST" deleted_count failed_count
	assert_equal "$deleted_count" 0
	assert_equal "$failed_count" 0
}

# ============================================================================
# DELETE_STALE_SAS TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "delete_stale_sas - parses and deletes SAs successfully" {
	# Purpose: Test verifies that delete_stale_sas successfully parses and deletes SAs
	# Expected: Function parses xfrm output, deletes SAs, and deletes policies
	# Importance: This is the main entry point for SA deletion - combines parsing and deletion
	source_recovery_module

	# Create mock ip command that handles state get, state delete, and policy operations
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    if [[ "$3" == "delete" ]]; then
        exit 0
    elif [[ "$3" == "get" ]]; then
        # Return mock SA output for get command
        echo "src 192.168.1.2 dst 192.168.1.1"
        echo "  proto esp spi 0x12345678"
        echo "  mode tunnel"
        exit 0
    fi
elif [[ "$1" == "xfrm" ]] && [[ "$2" == "policy" ]]; then
    if [[ "$3" == "delete" ]]; then
        exit 0
    else
        # Return empty policy list (no policies to delete)
        exit 0
    fi
fi
exit 0
EOF
	chmod +x "$mock_ip"
	add_mock_to_path
	# Set _RECOVERY_IP_PATH to mock since get_command_path() bypasses PATH for reliability
	export _RECOVERY_IP_PATH="$mock_ip"

	local xfrm_output="src 192.168.1.2 dst ${TEST_PEER_IP}
  proto esp spi 0x12345678
  mode tunnel"

	local __deleted_count=0
	local __failed_count=0

	# Call directly (not via run) because eval vars don't cross subshell boundary
	delete_stale_sas "${TEST_PEER_IP}" "TEST" "$xfrm_output" "__deleted_count" "__failed_count"

	# Verify counts were set
	assert_equal "$__deleted_count" 1
	assert_equal "$__failed_count" 0

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "delete_stale_sas - handles incomplete SA output gracefully" {
	# Purpose: Test verifies that delete_stale_sas handles incomplete SA output gracefully
	# Expected: Function returns success with zero counts when no complete SAs found
	# Importance: Incomplete SAs (missing SPI) are silently skipped, not treated as errors
	# Note: An SA without SPI is "incomplete" not "invalid" - the regex never matches
	source_recovery_module

	# Create mock ip command for policy operations
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "policy" ]]; then
    # Return empty policy list
    exit 0
fi
exit 0
EOF
	chmod +x "$mock_ip"
	add_mock_to_path
	# Set _RECOVERY_IP_PATH to mock since get_command_path() bypasses PATH for reliability
	export _RECOVERY_IP_PATH="$mock_ip"

	# Incomplete xfrm output (missing required SPI selector)
	# This SA will be silently skipped because it's incomplete, not counted as a parse error
	local xfrm_output="src 192.168.1.2 dst ${TEST_PEER_IP}
  proto esp
  mode tunnel"

	local __deleted_count=0
	local __failed_count=0

	# Call directly (not via run) because eval vars don't cross subshell boundary
	# Function returns success when no complete SAs found (nothing to delete is not an error)
	delete_stale_sas "${TEST_PEER_IP}" "TEST" "$xfrm_output" "__deleted_count" "__failed_count"

	# Verify counts were set to zero (no SAs to delete)
	assert_equal "$__deleted_count" 0
	assert_equal "$__failed_count" 0

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "delete_stale_sas - handles empty xfrm output" {
	# Purpose: Test verifies that delete_stale_sas handles empty xfrm output gracefully
	# Expected: Function returns success with zero counts when no SAs found
	# Importance: Empty output is valid (no SAs exist) - should not fail
	source_recovery_module

	# Create mock ip command for policy operations
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "policy" ]]; then
    # Return empty policy list
    exit 0
fi
exit 0
EOF
	chmod +x "$mock_ip"
	add_mock_to_path
	# Set _RECOVERY_IP_PATH to mock since get_command_path() bypasses PATH for reliability
	export _RECOVERY_IP_PATH="$mock_ip"

	local xfrm_output=""
	local __deleted_count=0
	local __failed_count=0

	# Call directly (not via run) because eval vars don't cross subshell boundary
	delete_stale_sas "${TEST_PEER_IP}" "TEST" "$xfrm_output" "__deleted_count" "__failed_count"

	# Verify counts were set to zero
	assert_equal "$__deleted_count" 0
	assert_equal "$__failed_count" 0

	remove_mock_from_path
}

# ============================================================================
# DELETE_XFRM_POLICIES TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "delete_xfrm_policies - deletes policies successfully" {
	# Purpose: Test verifies that delete_xfrm_policies successfully deletes xfrm policies
	# Expected: Function executes ip xfrm policy delete commands and returns success
	# Importance: Policy deletion failures are non-fatal but should still be tested
	source_recovery_module

	# Create mock ip command that succeeds for policy delete
	local policy_delete_called=0
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "policy" ]]; then
    if [[ "$3" == "delete" ]]; then
        # Verify correct arguments: dst <ip> dir <direction>
        echo "$(( $(cat MOCK_POLICY_DELETE_FILE 2>/dev/null || echo "0") + 1 ))" > MOCK_POLICY_DELETE_FILE
        exit 0
    elif [[ "$3" == "" ]] || [[ -z "$3" ]]; then
        # Return mock policy output with directions
        echo "src 192.168.1.0/24 dst PEER_IP dir fwd"
        echo "src 192.168.1.0/24 dst PEER_IP dir out"
    fi
fi
exec /usr/bin/ip "$@"
EOF
	sed -i "s|MOCK_POLICY_DELETE_FILE|${TEST_DIR}/policy_delete|g" "$mock_ip"
	sed -i "s|PEER_IP|${TEST_PEER_IP}|g" "$mock_ip"
	chmod +x "$mock_ip"
	add_mock_to_path

	run delete_xfrm_policies "${TEST_PEER_IP}" "TEST"
	assert_success

	# Verify policy deletion was called
	local delete_count
	delete_count=$(cat "${TEST_DIR}/policy_delete" 2>/dev/null || echo "0")
	assert [ "$delete_count" -gt 0 ]

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "delete_xfrm_policies - handles policy deletion failure gracefully" {
	# Purpose: Test verifies that delete_xfrm_policies handles deletion failures gracefully
	# Expected: Function returns success even when policy deletion fails (non-fatal)
	# Importance: Policy deletion failures are non-fatal - should not break recovery
	source_recovery_module

	# Create mock ip command that fails for policy delete
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "policy" ]]; then
    if [[ "$3" == "delete" ]]; then
        echo "ERROR: Policy deletion failed" >&2
        exit 1
    elif [[ "$3" == "" ]] || [[ -z "$3" ]]; then
        # Return mock policy output
        echo "src 192.168.1.0/24 dst PEER_IP dir fwd"
    fi
fi
exec /usr/bin/ip "$@"
EOF
	sed -i "s|PEER_IP|${TEST_PEER_IP}|g" "$mock_ip"
	chmod +x "$mock_ip"
	add_mock_to_path

	# Should still return success (non-fatal)
	run delete_xfrm_policies "${TEST_PEER_IP}" "TEST"
	assert_success

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "delete_xfrm_policies - handles no policies found" {
	# Purpose: Test verifies that delete_xfrm_policies handles case where no policies exist
	# Expected: Function returns success when no policies found
	# Importance: No policies is valid - should not fail
	source_recovery_module

	# Create mock ip command that returns empty policy output
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "policy" ]]; then
    if [[ "$3" == "delete" ]]; then
        exit 0
    elif [[ "$3" == "" ]] || [[ -z "$3" ]]; then
        # Return empty output (no policies)
        exit 0
    fi
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	run delete_xfrm_policies "${TEST_PEER_IP}" "TEST"
	assert_success

	remove_mock_from_path
}

# ============================================================================
# COUNT_SAS_FOR_PEER TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "count_sas_for_peer - counts single SA" {
	# Purpose: Test verifies that count_sas_for_peer correctly counts a single SA
	# Expected: Function returns count of 1 for single SA
	# Importance: SA counting is needed for verification and diagnostics
	source_recovery_module

	# Create mock ip command that returns xfrm state with one SA
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.2 dst PEER_IP
  proto esp spi 0x12345678
  mode tunnel"
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	sed -i "s|PEER_IP|${TEST_PEER_IP}|g" "$mock_ip"
	chmod +x "$mock_ip"
	add_mock_to_path

	run count_sas_for_peer "${TEST_PEER_IP}" "TEST"
	assert_success
	assert_output "1"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "count_sas_for_peer - counts multiple SAs" {
	# Purpose: Test verifies that count_sas_for_peer correctly counts multiple SAs
	# Expected: Function returns correct count for multiple SAs
	# Importance: Multiple SAs are common - must count all correctly
	source_recovery_module

	# Create mock ip command that returns xfrm state with multiple SAs
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.2 dst PEER_IP
  proto esp spi 0x12345678
  mode tunnel
src PEER_IP dst 192.168.1.2
  proto esp spi 0x87654321
  mode tunnel"
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	sed -i "s|PEER_IP|${TEST_PEER_IP}|g" "$mock_ip"
	chmod +x "$mock_ip"
	add_mock_to_path

	run count_sas_for_peer "${TEST_PEER_IP}" "TEST"
	assert_success
	assert_output "2"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "count_sas_for_peer - returns zero when no SAs found" {
	# Purpose: Test verifies that count_sas_for_peer returns zero when no SAs exist
	# Expected: Function returns count of 0 when no matching SAs found
	# Importance: Zero count is valid - should not fail
	source_recovery_module

	# Create mock ip command that returns empty xfrm state
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Return empty output (no SAs)
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	run count_sas_for_peer "${TEST_PEER_IP}" "TEST"
	assert_success
	assert_output "0"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "count_sas_for_peer - handles xfrm command failure" {
	# Purpose: Test verifies that count_sas_for_peer handles xfrm command failure gracefully
	# Expected: Function returns failure when xfrm command fails
	# Importance: Command failures must be handled to prevent false counts
	source_recovery_module

	# Create mock ip command that fails
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "ERROR: xfrm command failed" >&2
    exit 1
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	run count_sas_for_peer "${TEST_PEER_IP}" "TEST"
	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "count_sas_for_peer - filters SAs by peer IP" {
	# Purpose: Test verifies that count_sas_for_peer only counts SAs matching the target peer IP
	# Expected: Function excludes SAs for other peer IPs from count
	# Importance: Must only count SAs for the specified peer to avoid incorrect counts
	source_recovery_module

	# Create mock ip command that returns SAs for multiple peers
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.2 dst PEER_IP
  proto esp spi 0x12345678
  mode tunnel
src 192.168.1.2 dst 10.0.0.1
  proto esp spi 0x11111111
  mode tunnel"
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	sed -i "s|PEER_IP|${TEST_PEER_IP}|g" "$mock_ip"
	chmod +x "$mock_ip"
	add_mock_to_path

	run count_sas_for_peer "${TEST_PEER_IP}" "TEST"
	assert_success
	# Should only count SA for TEST_PEER_IP, not 10.0.0.1
	assert_output "1"

	remove_mock_from_path
}
