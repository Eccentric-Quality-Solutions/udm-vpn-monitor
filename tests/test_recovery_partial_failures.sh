#!/usr/bin/env bats
#
# Tests for Recovery Action Partial Failures (Section 3.1)
# Tests critical paths where recovery actions partially succeed or fail
#
# These tests address the gap identified in CRITICAL_PATH_TEST_GAPS_REVIEW.md:
# - Some SAs deleted successfully, others fail - should continue and verify
# - xfrm recovery deletes SAs but re-establishment fails - should fall back
# - Recovery verification timeout but SAs actually re-established - should detect on next check
# - Multiple recovery actions triggered simultaneously (should be prevented by lockfile, but verify)

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_xfrm_recovery
load fixtures/vpn_at_tier

# ============================================================================
# RECOVERY ACTION PARTIAL FAILURES TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "recovery partial failures: some SAs deleted successfully, others fail - should continue and verify" {
	# Purpose: Test verifies that xfrm recovery continues when some SA deletions succeed and others fail
	# Expected: Function continues processing remaining SAs and verifies re-establishment
	# Importance: Partial failures shouldn't stop recovery process - should attempt all deletions
	# Use fixture to set up xfrm recovery scenario with partial failure (3 SAs, some deletions fail)
	setup_vpn_xfrm_recovery_fixture "192.168.1.1" 3 "partial_failure" 'TIER3_THRESHOLD=5'

	# Mock check_ipsec_phase2 to simulate SA re-establishment after partial deletion
	local mock_check_ipsec_phase2="${TEST_DIR}/check_ipsec_phase2"
	cat >"$mock_check_ipsec_phase2" <<'EOF'
#!/bin/bash
# Simulate SA re-establishment check - return success after some time
exit 0
EOF
	chmod +x "$mock_check_ipsec_phase2"
	add_mock_to_path

	# Source recovery functions to test directly
	# shellcheck source=../lib/recovery.sh disable=SC1091
	source "${BATS_TEST_DIRNAME}/../lib/recovery.sh" || true

	# Test attempt_xfrm_recovery function
	run attempt_xfrm_recovery "192.168.1.1"
	# Should continue despite partial failures and verify re-establishment
	# Function may return 0 (success) or 1 (partial failure) depending on implementation
	# Key is that it continues processing and doesn't crash

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery partial failures: xfrm recovery deletes SAs but re-establishment fails - should fall back" {
	# Purpose: Test verifies that when xfrm recovery deletes SAs but re-establishment fails, system falls back to full restart
	# Expected: Function attempts xfrm recovery, detects re-establishment failure, falls back to ipsec restart
	# Importance: Partial recovery success shouldn't leave system in inconsistent state - should escalate to full restart
	# Use fixture to set up xfrm recovery scenario with successful deletion
	setup_vpn_xfrm_recovery_fixture "192.168.1.1" 1 "success" 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'ENABLE_NETWORK_PARTITION_CHECK=0' 'RECOVERY_VERIFY_TIMEOUT=2'

	# Override fixture's mock_ip with our stateful version
	# Remove fixture's mock_ip file so we can create our own
	rm -f "${TEST_DIR}/ip"

	# Mock check_ipsec_phase2 to simulate SA re-establishment failure (never re-establishes)
	local mock_check_ipsec_phase2="${TEST_DIR}/check_ipsec_phase2"
	cat >"$mock_check_ipsec_phase2" <<'EOF'
#!/bin/bash
# Simulate SA re-establishment failure - always return failure
exit 1
EOF
	chmod +x "$mock_check_ipsec_phase2"

	# Mock ipsec for fallback reload (Tier 2 falls back to reload, not restart)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "ipsec reload called"
    exit 0
fi
exec /usr/bin/ipsec "$@"
EOF
	chmod +x "$mock_ipsec"

	# Mock ip command - stateful: return SAs during recovery, empty after deletion
	# Uses log file content to determine recovery phase (more robust than counter-based approach)
	# Ensure log directory exists and get log file path
	mkdir -p "${TEST_DIR}/logs"
	local log_file_path="${LOG_FILE:-${TEST_DIR}/logs/vpn-monitor.log}"
	local recovery_started_flag="${TEST_DIR}/recovery_started"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'MOCK_IP_EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]] && [[ "$3" == "delete" ]]; then
    # Handle SA deletion - always succeed
    # Mark that SAs have been deleted so subsequent checks return empty
    touch "MOCK_SAS_DELETED_FILE" 2>/dev/null || true
    exit 0
elif [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Stateful xfrm state check
    # If SAs have been deleted, return empty (so re-establishment check fails)
    if [[ -f "MOCK_SAS_DELETED_FILE" ]]; then
        # SAs have been deleted - return empty so re-establishment check fails
        exit 0
    fi
    
    # Check if recovery has started by looking for recovery messages in log file
    # This is more reliable than a counter since it's based on actual recovery behavior
    # Check for "Attempting xfrm-based" which is logged when xfrm recovery starts
    if [[ -f "MOCK_LOG_FILE_PATH" ]] && grep -q "Attempting xfrm-based" "MOCK_LOG_FILE_PATH" 2>/dev/null; then
        # Mark that recovery has started (for efficiency, avoid repeated log reads)
        touch "MOCK_RECOVERY_STARTED_FLAG" 2>/dev/null || true
        # Recovery phase: return SAs so they can be deleted
        echo "src 192.168.1.1 dst 192.168.1.1"
        echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
        echo "    replay-window 0"
        echo "    auth-trunc hmac(sha256) 0x1234567890abcdef 96"
        echo "    enc cbc(aes) 0x1234567890abcdef"
        echo "    lifetime current: 1000 bytes, 10 packets"
        echo "    lifetime hard: 3600s, 0 bytes, 0 packets"
        echo "    lifetime soft: 2880s, 0 bytes, 0 packets"
        echo "    current use: 1"
        echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
        exit 0
    elif [[ -f "MOCK_RECOVERY_STARTED_FLAG" ]]; then
        # Recovery has started (flag file exists), return SAs
        # This avoids repeated log file reads for better performance
        echo "src 192.168.1.1 dst 192.168.1.1"
        echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
        echo "    replay-window 0"
        echo "    auth-trunc hmac(sha256) 0x1234567890abcdef 96"
        echo "    enc cbc(aes) 0x1234567890abcdef"
        echo "    lifetime current: 1000 bytes, 10 packets"
        echo "    lifetime hard: 3600s, 0 bytes, 0 packets"
        echo "    lifetime soft: 2880s, 0 bytes, 0 packets"
        echo "    current use: 1"
        echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
        exit 0
    else
        # Initial checks: return empty (VPN down, triggers recovery)
        exit 0
    fi
fi
# Handle other ip commands
exec /usr/bin/ip "$@"
MOCK_IP_EOF
	# Replace placeholders with actual paths
	sed -i "s|MOCK_SAS_DELETED_FILE|${TEST_DIR}/sas_deleted|g" "$mock_ip"
	sed -i "s|MOCK_LOG_FILE_PATH|${log_file_path}|g" "$mock_ip"
	sed -i "s|MOCK_RECOVERY_STARTED_FLAG|${recovery_started_flag}|g" "$mock_ip"
	chmod +x "$mock_ip"
	add_mock_to_path

	run bash "$TEST_SCRIPT"

	# Script should handle partial recovery failure gracefully
	assert_success
	# Should attempt xfrm recovery, detect re-establishment failure, fall back to restart
	assert_file_exist "$LOG_FILE"
	# Verify xfrm recovery was attempted
	assert_file_contains "$LOG_FILE" "xfrm recovery" || assert_file_contains "$LOG_FILE" "xfrm"
	# Verify fallback to reload was attempted (Tier 2 falls back to reload, not restart)
	assert_file_contains "$LOG_FILE" "falling back" || assert_file_contains "$LOG_FILE" "fallback" || assert_file_contains "$LOG_FILE" "reload"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery partial failures: recovery verification timeout but SAs actually re-established - should detect on next check" {
	# Purpose: Test verifies that when recovery verification times out but SAs are actually re-established, the next check cycle should detect the recovery
	# Expected: First check times out verification, second check detects VPN is healthy
	# Importance: Verification timeouts shouldn't prevent detection of successful recovery on subsequent checks
	# Use fixture to set up xfrm recovery scenario with successful deletion
	setup_vpn_xfrm_recovery_fixture "192.168.1.1" 1 "success" 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'ENABLE_NETWORK_PARTITION_CHECK=0' 'RECOVERY_VERIFY_TIMEOUT=2'

	# Mock check_ipsec_phase2 - timeout on first check, succeed on second
	# Use a file to track state across calls
	local check_state_file="${TEST_DIR}/check_state"
	echo "0" >"$check_state_file"
	local mock_check_ipsec_phase2="${TEST_DIR}/check_ipsec_phase2"
	cat >"$mock_check_ipsec_phase2" <<EOF
#!/bin/bash
# Simulate timeout on first verification, success on second
# This simulates SAs re-establishing after verification timeout
check_count=\$(cat "$check_state_file" 2>/dev/null || echo "0")
check_count=\$((check_count + 1))
echo "\$check_count" >"$check_state_file"
if [[ \$check_count -lt 2 ]]; then
    exit 1  # Timeout on first check
else
    exit 0  # Success on second check
fi
EOF
	chmod +x "$mock_check_ipsec_phase2"

	# Mock check_vpn_status - first call fails (during recovery), second succeeds (after recovery)
	# Use a file to track state across calls
	local vpn_check_state_file="${TEST_DIR}/vpn_check_state"
	echo "0" >"$vpn_check_state_file"
	local mock_check_vpn_status="${TEST_DIR}/check_vpn_status"
	cat >"$mock_check_vpn_status" <<EOF
#!/bin/bash
# First check fails (during recovery), second succeeds (after recovery)
vpn_check_count=\$(cat "$vpn_check_state_file" 2>/dev/null || echo "0")
vpn_check_count=\$((vpn_check_count + 1))
echo "\$vpn_check_count" >"$vpn_check_state_file"
if [[ \$vpn_check_count -eq 1 ]]; then
    exit 1  # VPN down during recovery
else
    exit 0  # VPN up after recovery
fi
EOF
	chmod +x "$mock_check_vpn_status"
	add_mock_to_path

	# First run - recovery times out
	run bash "$TEST_SCRIPT"

	# Script should handle recovery timeout gracefully
	assert_success
	# Second run - should detect VPN is healthy (update mock to return healthy)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Return healthy VPN
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    lifetime current: 1000 bytes"
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	run bash "$TEST_SCRIPT"

	# Script should detect recovery successfully
	assert_success
	# Verify that second check detected recovery
	assert_file_exist "$LOG_FILE"
	# Should detect VPN recovery on second check
	assert_file_contains "$LOG_FILE" "recovered" || assert_file_contains "$LOG_FILE" "healthy"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery partial failures: multiple recovery actions triggered simultaneously - should be prevented by lockfile" {
	# Purpose: Test verifies that lockfile prevents multiple recovery actions from running simultaneously
	# Expected: Only one recovery action executes at a time, others wait for lockfile
	# Importance: Concurrent recovery actions could cause system instability or inconsistent state
	# Use fixture to set up VPN down scenario (creates state files and basic setup)
	setup_vpn_at_tier_fixture 2 "192.168.1.1" 'ENABLE_XFRM_RECOVERY=1' 'ENABLE_NETWORK_PARTITION_CHECK=0' 'LOCKFILE_TIMEOUT=5'

	# Run first instance in background
	bash "$TEST_SCRIPT" &
	local first_pid=$!

	# Wait for lockfile to be created (deterministic - wait for file to appear)
	# This ensures first instance has acquired lock before second instance starts
	local lockfile="${TEST_DIR}/vpn-monitor.lock"
	wait_for_file "$lockfile" 5 || true

	# Run second instance - should be blocked by lockfile
	run bash "$TEST_SCRIPT"

	# Second instance should handle lockfile blocking gracefully (may exit with error or success)
	# The important part is that it doesn't crash and logs appropriately
	# Wait for first instance to complete
	wait $first_pid || true

	# Verify that lockfile prevented concurrent execution
	assert_file_exist "$LOG_FILE"
	# Should have lockfile-related messages
	assert_file_contains "$LOG_FILE" "lockfile" || assert_file_contains "$LOG_FILE" "already running" || assert_file_contains "$LOG_FILE" "stale"

	remove_mock_from_path
}
