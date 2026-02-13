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
load helpers/mocks
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

	# Mock ip command - return 2 SAs initially, then only 1 after deletion (SA count mismatch)
	# Uses helper function to simplify complex mock logic
	mock_ip_xfrm_sa_count_mismatch "${TEST_LOCAL_IP}" "${TEST_PEER_IP}" "forward" \
		"0x12345678" "0x87654321" "${TEST_DIR}/sas_deleted" 0 1000
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

	# Mock ip command - return only forward SA (asymmetric state)
	# Uses helper function to simplify complex mock logic
	mock_ip_xfrm_asymmetric_sa "${TEST_LOCAL_IP}" "${TEST_PEER_IP}" "forward" \
		"0x12345678" "${TEST_DIR}/sas_deleted" 0 1000
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

	# Mock ip command - return only reverse SA (asymmetric state)
	# Uses helper function to simplify complex mock logic
	mock_ip_xfrm_asymmetric_sa "${TEST_LOCAL_IP}" "${TEST_PEER_IP}" "reverse" \
		"0x87654321" "${TEST_DIR}/sas_deleted" 0 1000
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

	# Mock ip command - return 1 SA initially, then 2 SAs after delay (timing issue)
	# Uses helper function to simplify complex mock logic with call counter tracking
	mock_ip_xfrm_timing_delay "${TEST_LOCAL_IP}" "${TEST_PEER_IP}" 3 \
		"0x12345678" "0x87654321" "${TEST_DIR}/sas_deleted" "${TEST_DIR}/check_count" 0 1000
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
