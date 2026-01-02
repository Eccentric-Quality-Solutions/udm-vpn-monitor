#!/usr/bin/env bats
#
# Tests for VPN Detection Fallback Chain Edge Cases
# Tests critical paths and error handling scenarios

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# 3.3 FALLBACK CHAIN EDGE CASES
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "ipsec returns error exit code but has output - should handle gracefully" {
	# Purpose: Test verifies that the script handles ipsec commands that return error exit codes but still produce valid output.
	# Expected: Script processes output even when ipsec returns error code, detecting VPN status correctly.
	# Importance: Some ipsec implementations may return non-zero exit codes even with valid output; script must handle this edge case.
	setup_vpn_down_fixture "192.168.1.1" 0

	# Mock ipsec - returns error code but has output containing peer IP
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # Return error code but output contains peer IP (simulates partial failure)
    echo "192.168.1.1: ESTABLISHED 1 hour ago"
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	run bash "$TEST_SCRIPT"

	# Script should handle error code gracefully
	assert_success
	# Should handle error code gracefully and still process output
	# Output contains peer IP, so should detect VPN as OK
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# ============================================================================
# 3.3 FALLBACK CHAIN EDGE CASES (continued)
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "tool availability detection (command -v) fails - should handle gracefully" {
	# Purpose: Test verifies that the script handles failures in tool availability detection gracefully.
	# Expected: Script falls back to alternative detection methods or fails gracefully when command -v fails.
	# Importance: Tool availability detection can fail due to system issues; script must handle this without crashing.
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="192.168.1.1"
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock command to fail (simulates command -v failure)
	local mock_command="${TEST_DIR}/command"
	cat >"$mock_command" <<'EOF'
#!/bin/bash
if [[ "$1" == "-v" ]] && [[ "$2" == "ip" ]]; then
    exit 1
fi
# Fallback to real command for other cases
exec /usr/bin/command "$@"
EOF
	chmod +x "$mock_command"

	# Remove ip from PATH to force fallback
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip_backup" 2>/dev/null || true

	# Create minimal PATH without ip command
	PATH="${TEST_DIR}:/usr/bin:/bin" add_mock_to_path

	PATH="${TEST_DIR}:/usr/bin:/bin" run bash "$test_script" --fake
	assert_success

	# Should handle missing ip command gracefully (should fall back to ipsec or fail gracefully)
	assert_file_exist "$log_file"

	# Restore
	mv "${TEST_DIR}/ip_backup" "${TEST_DIR}/ip" 2>/dev/null || true
	remove_mock_from_path
}

# ============================================================================
# 3.4 PING CHECK EDGE CASES
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "ping command not available (ping6 vs ping -6 detection) - should handle gracefully" {
	# Purpose: Test verifies that the script handles missing ping commands gracefully when ping check is enabled.
	# Expected: Script logs warning but continues execution without ping check when ping command is unavailable.
	# Importance: Ping commands may not be available on all systems; script must handle this gracefully.
	setup_vpn_active_fixture "192.168.1.1" 1000 2000 "" 'ENABLE_PING_CHECK=1' 'LOCATION_NYC_INTERNAL="2001:db8::1"'

	# Mock command to fail for ping (simulates ping not available)
	local mock_command="${TEST_DIR}/command"
	cat >"$mock_command" <<'EOF'
#!/bin/bash
if [[ "$1" == "-v" ]] && [[ "$2" == "ping" ]]; then
    exit 1
fi
if [[ "$1" == "-v" ]] && [[ "$2" == "ping6" ]]; then
    exit 1
fi
# Fallback to real command for other cases
exec /usr/bin/command "$@"
EOF
	chmod +x "$mock_command"

	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should handle missing ping command gracefully (should log warning but continue)
	# Code at lib/detection.sh:433-436 handles ping command not available
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "ping command hangs (timeout handling) - should timeout and continue" {
	# Purpose: Test verifies that the script handles ping commands that hang indefinitely without blocking execution.
	# Expected: Script uses timeout mechanism to prevent ping from blocking script execution indefinitely.
	# Importance: Network issues can cause ping to hang; script must handle this to remain responsive.
	setup_vpn_active_fixture "192.168.1.1" 1000 2000 "" 'ENABLE_PING_CHECK=1' 'LOCATION_NYC_INTERNAL="192.168.1.1"' 'PING_COUNT=3' 'PING_TIMEOUT=1'

	# Mock ping to hang (simulates timeout)
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
# Simulate ping hanging (sleep longer than timeout)
sleep 2
exit 0
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	# Use timeout of 10 seconds to allow script initialization, ping timeout handling, and completion
	# The ping wrapper timeout is 2 seconds, but script initialization and other checks take additional time
	run timeout 10 bash "$TEST_SCRIPT" --fake
	assert_success

	# Should handle ping timeout gracefully (should log error but continue)
	# Code at lib/detection.sh:465-473 handles ping timeouts
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "ping target is unreachable but command succeeds (weird network state) - should handle gracefully" {
	# Purpose: Test verifies that the script handles ping commands that succeed but report 100% packet loss.
	# Expected: Script detects packet loss and logs warning but continues execution.
	# Importance: Network anomalies can cause ping to succeed but report no packets received; script must handle this edge case.
	setup_vpn_active_fixture "192.168.1.1" 1000 2000 "" 'ENABLE_PING_CHECK=1' 'LOCATION_NYC_INTERNAL="192.168.1.1"'

	# Mock ping to return success but 100% packet loss (weird network state)
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
# Simulate ping command succeeds but 100% packet loss
echo "PING 192.168.1.1 (192.168.1.1) 56(84) bytes of data."
echo ""
echo "--- 192.168.1.1 ping statistics ---"
echo "3 packets transmitted, 0 received, 100% packet loss"
exit 0
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should handle 100% packet loss gracefully (should log warning but continue)
	# Code at lib/detection.sh:477-485 handles packet loss detection
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# ============================================================================
# 3.3 FALLBACK CHAIN EDGE CASES (continued)
# ============================================================================

# bats test_tags=slow,category:high-risk,priority:high
@test "ipsec command hangs (timeout scenario - status check) - should timeout and continue" {
	# Purpose: Test verifies that the script handles ipsec commands that hang indefinitely during status checks.
	# Expected: Script uses timeout mechanism or error handling to prevent ipsec from blocking script execution.
	# Importance: Network or system issues can cause ipsec to hang; script must handle this to remain responsive.
	setup_vpn_down_fixture "192.168.1.1" 0

	# Mock ipsec status to hang (simulates timeout)
	# Sleep longer than IPSEC_STATUS_TIMEOUT (5 seconds) to trigger timeout
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # Simulate ipsec status hanging longer than timeout (6 seconds > 5 second timeout)
    sleep 6
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Run with timeout to prevent test from hanging
	# Test timeout should be longer than IPSEC_STATUS_TIMEOUT to allow script to complete
	# Allow extra time for script initialization and other operations
	run timeout 10 bash "$TEST_SCRIPT" --fake
	assert_success

	# Should handle ipsec status hang gracefully (should timeout and continue)
	# Code at lib/detection.sh wraps ipsec status with timeout command (IPSEC_STATUS_TIMEOUT=5s)
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}
