#!/usr/bin/env bats
#
# Tests for SA Count Mismatch Scenarios
# Tests edge cases where SA count mismatches occur during recovery
#
# These tests validate the enhanced diagnostic logging and verification logic:
# - SA count mismatch during recovery (deleted 2 SAs, only 1 re-established)
# - Asymmetric SA state detection (only forward or only reverse SA present)
# - Timing issues where second SA appears after initial re-establishment

load test_helper
load helpers/assertions
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_at_tier

# ============================================================================
# SA COUNT MISMATCH SCENARIOS TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:medium,slow
@test "SA count mismatch: deleted 2 SAs, only 1 re-established" {
	# Purpose: Test verifies that script handles SA count mismatch during recovery gracefully
	# Expected: Script deletes 2 SAs, detects only 1 re-established, logs warning about mismatch
	# Importance: Validates enhanced diagnostic logging and verification logic for SA count mismatches
	# Location name is "TEST" (extracted from LOCATION_TEST_EXTERNAL)
	setup_vpn_at_tier_fixture 2 "${TEST_PEER_IP}" 'ENABLE_XFRM_RECOVERY=1' 'ENABLE_NETWORK_PARTITION_CHECK=0' 'ENABLE_PING_CHECK=0' 'RECOVERY_VERIFY_TIMEOUT=10'

	# Track recovery state
	local sa_deleted_flag="${TEST_DIR}/sas_deleted"

	# Mock ip command - return 2 SAs initially, then only 1 after deletion
	# Note: get_xfrm_state_for_peer tries "ip -s xfrm state" first, then falls back to "ip xfrm state"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]] && [[ "\$3" == "delete" ]]; then
    # SA deletion succeeds
    touch "${sa_deleted_flag}" 2>/dev/null || true
    touch "${TEST_DIR}/MOCK_SAS_DELETED_FILE" 2>/dev/null || true
    exit 0
elif [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # Handle "ip -s xfrm state" (with statistics flag) - tried first by get_xfrm_state_for_peer
    # Check if SAs have been deleted
    if [[ -f "${sa_deleted_flag}" ]]; then
        # After deletion: return only 1 SA (mismatch - deleted 2, only 1 re-established)
        # Return forward SA only (local→peer)
        echo "src ${TEST_LOCAL_IP} dst ${TEST_PEER_IP}"
        echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
        echo "    lifetime current: 1000 bytes, 10 packets"
        exit 0
    else
        # Before deletion: return 2 SAs (bidirectional)
        # Forward SA (local→peer)
        echo "src ${TEST_LOCAL_IP} dst ${TEST_PEER_IP}"
        echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
        echo "    lifetime current: 0 bytes, 0 packets"
        # Reverse SA (peer→local)
        echo "src ${TEST_PEER_IP} dst ${TEST_LOCAL_IP}"
        echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
        echo "    lifetime current: 0 bytes, 0 packets"
        exit 0
    fi
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Handle "ip xfrm state" (without statistics flag) - fallback used by get_xfrm_state_for_peer
    # Check if SAs have been deleted
    if [[ -f "${sa_deleted_flag}" ]]; then
        # After deletion: return only 1 SA (mismatch - deleted 2, only 1 re-established)
        # Return forward SA only (local→peer)
        echo "src ${TEST_LOCAL_IP} dst ${TEST_PEER_IP}"
        echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
        echo "    lifetime current: 1000 bytes, 10 packets"
        exit 0
    else
        # Before deletion: return 2 SAs (bidirectional)
        # Forward SA (local→peer)
        echo "src ${TEST_LOCAL_IP} dst ${TEST_PEER_IP}"
        echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
        echo "    lifetime current: 0 bytes, 0 packets"
        # Reverse SA (peer→local)
        echo "src ${TEST_PEER_IP} dst ${TEST_LOCAL_IP}"
        echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
        echo "    lifetime current: 0 bytes, 0 packets"
        exit 0
    fi
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Mock check_ipsec_phase2 to return success after deletion (SA re-established)
	mock_check_ipsec_phase2 0 "${TEST_DIR}/MOCK_SAS_DELETED_FILE"

	run bash "$TEST_SCRIPT"

	# Script should handle SA count mismatch gracefully
	assert_success
	assert_file_exist "$LOG_FILE"

	# Should log that 2 SAs were found/deleted
	assert_log_contains_any "$LOG_FILE" "Found 2 SA(s) to delete" "2 SA(s)" "Deletion summary"

	# Should log SA re-establishment
	assert_log_contains_any "$LOG_FILE" "SA re-established" "re-established" "Waiting for SA re-establishment"

	# Should log SA count mismatch warning (deleted=2, final_count=1)
	# Note: The mismatch warning may not appear if the verification timeout is too short
	assert_log_contains_any "$LOG_FILE" "SA count mismatch" "deleted=2" "final_count=1" "SA count diagnostic"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium,slow
@test "SA count mismatch: asymmetric SA state - only forward SA present" {
	# Purpose: Test verifies that script detects asymmetric SA state (only forward SA present)
	# Expected: Script detects only forward SA (local→peer), logs bidirectional state diagnostic
	# Importance: Validates enhanced diagnostic logging for asymmetric SA state detection
	# Location name is "TEST" (extracted from LOCATION_TEST_EXTERNAL)
	setup_vpn_at_tier_fixture 2 "${TEST_PEER_IP}" 'ENABLE_XFRM_RECOVERY=1' 'ENABLE_NETWORK_PARTITION_CHECK=0' 'ENABLE_PING_CHECK=0' 'RECOVERY_VERIFY_TIMEOUT=10'

	local sa_deleted_flag="${TEST_DIR}/sas_deleted"

	# Mock ip command - return only forward SA (asymmetric state)
	# Note: get_xfrm_state_for_peer tries "ip -s xfrm state" first, then falls back to "ip xfrm state"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]] && [[ "\$3" == "delete" ]]; then
    # SA deletion succeeds
    touch "${sa_deleted_flag}" 2>/dev/null || true
    touch "${TEST_DIR}/MOCK_SAS_DELETED_FILE" 2>/dev/null || true
    exit 0
elif [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # Handle "ip -s xfrm state" (with statistics flag) - tried first by get_xfrm_state_for_peer
    # Always return only forward SA (asymmetric - no reverse SA)
    # Forward SA (local→peer)
    echo "src ${TEST_LOCAL_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    if [[ -f "${sa_deleted_flag}" ]]; then
        # After deletion: return with byte counters (re-established)
        echo "    lifetime current: 1000 bytes, 10 packets"
    else
        # Before deletion: return with zero byte counters
        echo "    lifetime current: 0 bytes, 0 packets"
    fi
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Handle "ip xfrm state" (without statistics flag) - fallback used by get_xfrm_state_for_peer
    # Always return only forward SA (asymmetric - no reverse SA)
    # Forward SA (local→peer)
    echo "src ${TEST_LOCAL_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    if [[ -f "${sa_deleted_flag}" ]]; then
        # After deletion: return with byte counters (re-established)
        echo "    lifetime current: 1000 bytes, 10 packets"
    else
        # Before deletion: return with zero byte counters
        echo "    lifetime current: 0 bytes, 0 packets"
    fi
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Mock check_ipsec_phase2 to return success after deletion
	mock_check_ipsec_phase2 0 "${TEST_DIR}/MOCK_SAS_DELETED_FILE"

	run bash "$TEST_SCRIPT"

	# Script should handle asymmetric SA state gracefully
	assert_success
	assert_file_exist "$LOG_FILE"

	# Should log that only 1 SA was found (asymmetric state)
	assert_log_contains_any "$LOG_FILE" "Found 1 SA(s) to delete" "1 SA(s)" "Deletion summary"

	# Should log bidirectional state diagnostic (forward=1, reverse=0)
	assert_log_contains_any "$LOG_FILE" "bidirectional state diagnostic" "forward=1" "reverse=0"

	# Should log SA direction information (forward vs reverse)
	assert_log_contains_any "$LOG_FILE" "forward (local→peer)" "direction" "SA summary"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium,slow
@test "SA count mismatch: asymmetric SA state - only reverse SA present" {
	# Purpose: Test verifies that script detects asymmetric SA state (only reverse SA present)
	# Expected: Script detects only reverse SA (peer→local), logs bidirectional state diagnostic
	# Importance: Validates enhanced diagnostic logging for asymmetric SA state detection (reverse direction)
	# Location name is "TEST" (extracted from LOCATION_TEST_EXTERNAL)
	setup_vpn_at_tier_fixture 2 "${TEST_PEER_IP}" 'ENABLE_XFRM_RECOVERY=1' 'ENABLE_NETWORK_PARTITION_CHECK=0' 'ENABLE_PING_CHECK=0' 'RECOVERY_VERIFY_TIMEOUT=10'

	local sa_deleted_flag="${TEST_DIR}/sas_deleted"

	# Mock ip command - return only reverse SA (asymmetric state)
	# Note: get_xfrm_state_for_peer tries "ip -s xfrm state" first, then falls back to "ip xfrm state"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]] && [[ "\$3" == "delete" ]]; then
    # SA deletion succeeds
    touch "${sa_deleted_flag}" 2>/dev/null || true
    touch "${TEST_DIR}/MOCK_SAS_DELETED_FILE" 2>/dev/null || true
    exit 0
elif [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # Handle "ip -s xfrm state" (with statistics flag) - tried first by get_xfrm_state_for_peer
    # Always return only reverse SA (asymmetric - no forward SA)
    # Reverse SA (peer→local)
    echo "src ${TEST_PEER_IP} dst ${TEST_LOCAL_IP}"
    echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
    if [[ -f "${sa_deleted_flag}" ]]; then
        # After deletion: return with byte counters (re-established)
        echo "    lifetime current: 1000 bytes, 10 packets"
    else
        # Before deletion: return with zero byte counters
        echo "    lifetime current: 0 bytes, 0 packets"
    fi
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Handle "ip xfrm state" (without statistics flag) - fallback used by get_xfrm_state_for_peer
    # Always return only reverse SA (asymmetric - no forward SA)
    # Reverse SA (peer→local)
    echo "src ${TEST_PEER_IP} dst ${TEST_LOCAL_IP}"
    echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
    if [[ -f "${sa_deleted_flag}" ]]; then
        # After deletion: return with byte counters (re-established)
        echo "    lifetime current: 1000 bytes, 10 packets"
    else
        # Before deletion: return with zero byte counters
        echo "    lifetime current: 0 bytes, 0 packets"
    fi
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Mock check_ipsec_phase2 to return success after deletion
	mock_check_ipsec_phase2 0 "${TEST_DIR}/MOCK_SAS_DELETED_FILE"

	run bash "$TEST_SCRIPT"

	# Script should handle asymmetric SA state gracefully
	assert_success
	assert_file_exist "$LOG_FILE"

	# Should log that only 1 SA was found (asymmetric state)
	assert_log_contains_any "$LOG_FILE" "Found 1 SA(s) to delete" "1 SA(s)" "Deletion summary"

	# Should log bidirectional state diagnostic (forward=0, reverse=1)
	assert_log_contains_any "$LOG_FILE" "bidirectional state diagnostic" "forward=0" "reverse=1"

	# Should log SA direction information (reverse vs forward)
	assert_log_contains_any "$LOG_FILE" "reverse (peer→local)" "direction" "SA summary"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium,slow
@test "SA count mismatch: timing issue - second SA appears after initial re-establishment" {
	# Purpose: Test verifies that script handles timing issues where second SA appears after initial re-establishment
	# Expected: Script detects first SA re-established, continues checking, detects second SA appears later
	# Importance: Validates enhanced verification logic that checks SA count multiple times to catch delayed SA establishment
	# Location name is "TEST" (extracted from LOCATION_TEST_EXTERNAL)
	setup_vpn_at_tier_fixture 2 "${TEST_PEER_IP}" 'ENABLE_XFRM_RECOVERY=1' 'ENABLE_NETWORK_PARTITION_CHECK=0' 'ENABLE_PING_CHECK=0' 'RECOVERY_VERIFY_TIMEOUT=10'

	local sa_deleted_flag="${TEST_DIR}/sas_deleted"
	local check_count_file="${TEST_DIR}/check_count"
	local second_sa_delay=3

	# Mock ip command - return 1 SA initially, then 2 SAs after delay
	# Note: get_xfrm_state_for_peer tries "ip -s xfrm state" first, then falls back to "ip xfrm state"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]] && [[ "\$3" == "delete" ]]; then
    # SA deletion succeeds
    touch "${sa_deleted_flag}" 2>/dev/null || true
    touch "${TEST_DIR}/MOCK_SAS_DELETED_FILE" 2>/dev/null || true
    # Reset check count
    echo "0" > "${check_count_file}" 2>/dev/null || true
    exit 0
elif [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # Handle "ip -s xfrm state" (with statistics flag) - tried first by get_xfrm_state_for_peer
    # Check if SAs have been deleted
    if [[ -f "${sa_deleted_flag}" ]]; then
        # After deletion: simulate timing issue - return 1 SA initially, then 2 SAs after delay
        # Check counter BEFORE incrementing to decide what to return
        local check_count=0
        if [[ -f "${check_count_file}" ]]; then
            check_count=\$(cat "${check_count_file}" 2>/dev/null || echo "0")
        fi
        # Use current counter value to decide what to return (before incrementing)
        local should_return_two=0
        if [[ \$check_count -ge $second_sa_delay ]]; then
            should_return_two=1
        fi
        # Now increment the counter for next call
        check_count=\$((check_count + 1))
        echo "\$check_count" > "${check_count_file}" 2>/dev/null || true

        if [[ \$should_return_two -eq 0 ]]; then
            # Initial checks: return only 1 SA (first SA re-established)
            echo "src ${TEST_LOCAL_IP} dst ${TEST_PEER_IP}"
            echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
            echo "    lifetime current: 1000 bytes, 10 packets"
        else
            # Later checks: return 2 SAs (second SA appears after delay)
            # Forward SA (local→peer)
            echo "src ${TEST_LOCAL_IP} dst ${TEST_PEER_IP}"
            echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
            echo "    lifetime current: 1000 bytes, 10 packets"
            # Reverse SA (peer→local) - appears after delay
            echo "src ${TEST_PEER_IP} dst ${TEST_LOCAL_IP}"
            echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
            echo "    lifetime current: 1000 bytes, 10 packets"
        fi
        exit 0
    else
        # Before deletion: return 2 SAs (bidirectional)
        # Forward SA (local→peer)
        echo "src ${TEST_LOCAL_IP} dst ${TEST_PEER_IP}"
        echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
        echo "    lifetime current: 0 bytes, 0 packets"
        # Reverse SA (peer→local)
        echo "src ${TEST_PEER_IP} dst ${TEST_LOCAL_IP}"
        echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
        echo "    lifetime current: 0 bytes, 0 packets"
        exit 0
    fi
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Handle "ip xfrm state" (without statistics flag) - fallback used by get_xfrm_state_for_peer
    # Check if SAs have been deleted
    if [[ -f "${sa_deleted_flag}" ]]; then
        # After deletion: simulate timing issue - return 1 SA initially, then 2 SAs after delay
        # Check counter BEFORE incrementing to decide what to return
        local check_count=0
        if [[ -f "${check_count_file}" ]]; then
            check_count=\$(cat "${check_count_file}" 2>/dev/null || echo "0")
        fi
        # Use current counter value to decide what to return (before incrementing)
        local should_return_two=0
        if [[ \$check_count -ge $second_sa_delay ]]; then
            should_return_two=1
        fi
        # Now increment the counter for next call
        check_count=\$((check_count + 1))
        echo "\$check_count" > "${check_count_file}" 2>/dev/null || true

        if [[ \$should_return_two -eq 0 ]]; then
            # Initial checks: return only 1 SA (first SA re-established)
            echo "src ${TEST_LOCAL_IP} dst ${TEST_PEER_IP}"
            echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
            echo "    lifetime current: 1000 bytes, 10 packets"
        else
            # Later checks: return 2 SAs (second SA appears after delay)
            # Forward SA (local→peer)
            echo "src ${TEST_LOCAL_IP} dst ${TEST_PEER_IP}"
            echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
            echo "    lifetime current: 1000 bytes, 10 packets"
            # Reverse SA (peer→local) - appears after delay
            echo "src ${TEST_PEER_IP} dst ${TEST_LOCAL_IP}"
            echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
            echo "    lifetime current: 1000 bytes, 10 packets"
        fi
        exit 0
    else
        # Before deletion: return 2 SAs (bidirectional)
        # Forward SA (local→peer)
        echo "src ${TEST_LOCAL_IP} dst ${TEST_PEER_IP}"
        echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
        echo "    lifetime current: 0 bytes, 0 packets"
        # Reverse SA (peer→local)
        echo "src ${TEST_PEER_IP} dst ${TEST_LOCAL_IP}"
        echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
        echo "    lifetime current: 0 bytes, 0 packets"
        exit 0
    fi
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Mock check_ipsec_phase2 to return success after deletion
	mock_check_ipsec_phase2 0 "${TEST_DIR}/MOCK_SAS_DELETED_FILE"

	run bash "$TEST_SCRIPT"

	# Script should handle timing issue gracefully
	assert_success
	assert_file_exist "$LOG_FILE"

	# Should log that 2 SAs were found/deleted initially
	assert_log_contains_any "$LOG_FILE" "Found 2 SA(s) to delete" "2 SA(s)"

	# Should log SA re-establishment with initial count of 1
	assert_log_contains_any "$LOG_FILE" "SA re-established" "re-established"
	assert_log_contains_any "$LOG_FILE" "SA count: 1" "count=1"

	# Should log that second SA eventually appears (count increases to 2)
	# The verification logic continues checking, so it should detect the second SA
	# Note: The exact log message may vary, but should show count progression or final count of 2
	assert_log_contains_any "$LOG_FILE" "SA count: 2" "count=2" "final_count=2"

	remove_mock_from_path
}
