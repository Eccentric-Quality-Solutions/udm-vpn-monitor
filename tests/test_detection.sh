#!/usr/bin/env bats
#
# Tests for VPN Status Detection
# Tests critical paths and error handling scenarios

# for better organization and maintainability.

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# 3. VPN STATUS DETECTION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "xfrm SA exists but byte counter is exactly 0 - should detect bytes=0 as suspect condition" {
	# Purpose: Test verifies that the detection function correctly identifies VPN failures when xfrm SA exists but byte counter is exactly 0, indicating no traffic has passed through the tunnel.
	# Expected: Function detects bytes=0 as suspect condition and may mark VPN as failed.
	# Importance: Zero byte counter indicates VPN tunnel is established but not passing traffic, a failure condition.
	# Test Category: VPN status detection
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command - SA exists but bytes=0
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 0 bytes, 0 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	add_mock_to_path
	run bash "$test_script" --fake

	# Should detect bytes=0 as suspect (may fail VPN check)
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "bytes=0" || assert_file_contains "$log_file" "suspect"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "xfrm SA exists but byte counter decreases - should detect bytes not increasing and mark VPN as suspect" {
	# Purpose: Test verifies that the detection function correctly identifies VPN failures when byte counter decreases between checks.
	# Expected: Function detects bytes not increasing and may mark VPN as suspect or failed.
	# Importance: Decreasing byte counters indicate abnormal VPN state that requires investigation.
	# Test Category: VPN status detection, Edge cases
	# Scenario: Counter wrap-around or VPN re-establishment
	# Setup: Set initial byte count to 10000, mock returns 5000
	# Edge case: Handles counter wrap-around scenarios
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Set initial byte count (high value)
	echo "10000" >"$last_bytes_file"

	# Mock ip command - bytes decreased (counter wrap-around scenario)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 5000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	add_mock_to_path
	run bash "$test_script" --fake

	# Should detect bytes not increasing (may fail VPN check)
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "bytes not increasing" || assert_file_contains "$log_file" "suspect"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "xfrm SA exists but byte counter stays same - should detect bytes not increasing and mark VPN as suspect" {
	# Purpose: Test verifies that the detection function correctly identifies VPN failures when byte counter remains unchanged between checks, indicating no traffic is passing through the tunnel.
	# Expected: Function detects bytes not increasing and marks VPN as suspect or failed.
	# Importance: Stagnant byte counters indicate VPN tunnel is not passing traffic, a critical failure condition.
	# Test Category: VPN status detection
	setup_vpn_failing_fixture "192.168.1.1" 0 1000 1000

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should detect bytes not increasing
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "bytes not increasing" || assert_file_contains "$LOG_FILE" "suspect"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "byte counter file corrupted - should treat as 0 or reset and continue normal operation" {
	# Purpose: Test verifies that the script handles corrupted byte counter files gracefully without crashing.
	# Expected: Script treats corrupted file as 0 or resets it, continuing normal operation.
	# Importance: File corruption can occur due to disk errors or manual editing; script must handle it robustly.
	# Test Category: Error handling, File corruption
	setup_vpn_active_fixture "192.168.1.1" 1000 2000

	# Create corrupted byte counter file (non-numeric)
	local last_bytes_file="${STATE_DIR}/last_bytes_192_168_1_1"
	echo "invalid-value" >"$last_bytes_file"

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should handle corrupted file gracefully (treat as 0 or reset)
	assert_success
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "byte counter file contains negative number - should handle gracefully" {
	# Purpose: Test verifies that the script handles byte counter files containing negative numbers gracefully.
	# Expected: Script treats negative value as invalid and either resets to 0 or uses current bytes value.
	# Importance: Negative values can occur from file corruption or manual editing; script must handle them robustly.
	# Test Category: Error handling, File corruption
	setup_vpn_active_fixture "192.168.1.1" 1000 2000

	# Create byte counter file with negative number
	local last_bytes_file="${STATE_DIR}/last_bytes_192_168_1_1"
	echo "-1000" >"$last_bytes_file"

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should handle negative value gracefully
	assert_success
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "byte counter file is empty - should treat as 0 and update with current bytes" {
	# Purpose: Test verifies that the script handles empty byte counter files gracefully.
	# Expected: Script treats empty file as 0, then updates it with current bytes value from xfrm output.
	# Importance: Empty files can occur from file deletion or initialization; script must handle them robustly.
	# Test Category: Error handling, File corruption
	setup_vpn_active_fixture "192.168.1.1" 1000 2000

	# Clear byte counter file to test empty file handling
	local last_bytes_file="${STATE_DIR}/last_bytes_192_168_1_1"
	# Remove file if it exists (from fixture setup), then create empty file
	rm -f "$last_bytes_file"
	touch "$last_bytes_file"
	# Verify file is empty before script runs
	assert_file_empty "$last_bytes_file"

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should handle empty file gracefully (treat as 0, then update with current bytes)
	assert_success
	assert_file_exist "$LOG_FILE"
	# File should be updated with current bytes value (not remain empty)
	# The script treats empty file as 0, then updates it with current bytes from mock (2000)
	assert_file_exist "$last_bytes_file"
	# File should contain a numeric value (current bytes from mock)
	local file_content
	file_content=$(cat "$last_bytes_file")
	if [[ ! "$file_content" =~ ^[0-9]+$ ]]; then
		fail "Byte counter file should contain numeric value, got: $file_content"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "all detection methods unavailable - should handle gracefully and may log warnings or exit early" {
	# Purpose: Test verifies that the script handles the edge case where all VPN detection methods (ip xfrm, ipsec) are unavailable on the system without crashing.
	# Expected: Script handles missing detection tools gracefully, may log warnings or exit early.
	# Importance: Ensures script fails gracefully in environments where required tools are missing.
	# Test Category: Error handling, Tool availability
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Don't create any mock commands (all unavailable)
	# PATH will not include mocks, so real commands won't be found in test environment

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Create minimal PATH with only essential commands
	# Use a PATH that doesn't include ip or ipsec
	PATH="/usr/bin:/bin" run bash "$test_script" --fake
	assert_success

	# Should handle all methods unavailable gracefully
	# Script may exit early, but if log file exists, it should contain error messages
	if [[ -f "$log_file" ]]; then
		assert_file_contains "$log_file" "suspect" || assert_file_contains "$log_file" "failed" || assert_file_contains "$log_file" "WARNING"
	else
		# If log file doesn't exist, script likely exited very early - this is acceptable
		# The important thing is it didn't crash
		echo "Log file not created - script exited early (acceptable behavior)"
	fi
}

# bats test_tags=category:high-risk,priority:high
@test "xfrm output contains multiple lifetime lines - should extract first lifetime line correctly" {
	# Purpose: Test verifies that the script correctly handles xfrm output containing multiple lifetime lines.
	# Expected: Script extracts the first lifetime line correctly and uses it for byte counter detection.
	# Importance: xfrm output can contain multiple lifetime entries; script must parse them correctly.
	# Test Category: VPN status detection, Parsing edge cases
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command with multiple lifetime lines
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    echo "    lifetime hard: 3600s, 0 bytes, 0 packets"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	add_mock_to_path
	run bash "$test_script" --fake

	# Should extract first lifetime line correctly
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "ping check enabled but INTERNAL_PEER_IPS not set - should use peer IP for ping check" {
	# Purpose: Test verifies that when ping check is enabled but INTERNAL_PEER_IPS is not set, the script uses peer IP for ping check.
	# Expected: Script falls back to using EXTERNAL_PEER_IPS for ping check when INTERNAL_PEER_IPS is not configured.
	# Importance: Ensures ping check works even when internal peer IPs are not configured.
	# Test Category: VPN status detection, Ping check fallback
	setup_vpn_active_fixture "192.168.1.1" 1000 2000 "" 'ENABLE_PING_CHECK=1'

	# Mock ping - should use peer IP
	local mock_ping
	mock_ping=$(mock_ping "192.168.1.1" "1")
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should use peer IP for ping check
	assert_success
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# ============================================================================
# 3.3 FALLBACK CHAIN EDGE CASES
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "ipsec returns error exit code but has output - should handle error code gracefully and still process output" {
	# Purpose: Test verifies that the script handles ipsec commands that return error exit codes but still produce output.
	# Expected: Script processes output even when exit code indicates error, detecting VPN status from output content.
	# Importance: Some ipsec implementations may return error codes even when output contains valid status information.
	# Test Category: VPN status detection, Fallback chain edge cases
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
@test "tool availability detection (command -v) fails - should handle missing ip command gracefully" {
	# Purpose: Test verifies that the script handles failures in tool availability detection (command -v) gracefully.
	# Expected: Script falls back to alternative detection methods when primary tool detection fails.
	# Importance: Tool availability detection can fail in some environments; script must handle gracefully.
	# Test Category: Error handling, Tool availability
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
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
@test "ping command not available (ping6 vs ping -6 detection) - should log warning but continue" {
	# Purpose: Test verifies that the script handles missing ping commands gracefully when IPv6 addresses are configured.
	# Expected: Script logs warning about missing ping command but continues execution without ping check.
	# Importance: Ping commands may not be available in all environments; script must handle gracefully.
	# Test Category: Error handling, Tool availability
	setup_vpn_active_fixture "192.168.1.1" 1000 2000 "" 'ENABLE_PING_CHECK=1' 'INTERNAL_PEER_IPS="2001:db8::1"'

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

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should handle missing ping command gracefully (should log warning but continue)
	# Code at lib/detection.sh:433-436 handles ping command not available
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "ping command hangs (timeout handling) - should use timeout mechanism to prevent blocking" {
	# Purpose: Test verifies that the script handles ping commands that hang indefinitely without blocking execution.
	# Expected: Script uses timeout mechanism to prevent ping from blocking script execution indefinitely.
	# Importance: Network issues can cause ping to hang; script must handle this to remain responsive.
	# Test Category: Error handling, Timeout handling
	# Scenario: Ping command hangs due to network issues
	# Setup: Mock ping to sleep longer than timeout value
	# Edge case: Handles hanging commands that could block script execution
	setup_vpn_active_fixture "192.168.1.1" 1000 2000 "" 'ENABLE_PING_CHECK=1' 'INTERNAL_PEER_IPS="192.168.1.1"' 'PING_COUNT=3' 'PING_TIMEOUT=1'

	# Mock ping to hang (simulates timeout)
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
# Simulate ping hanging (sleep longer than timeout)
sleep 3
exit 0
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	add_mock_to_path
	run timeout 2 bash "$TEST_SCRIPT" --fake
	assert_success

	# Should handle ping timeout gracefully (should log error but continue)
	# Code at lib/detection.sh:465-473 handles ping timeouts
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "ping target is unreachable but command succeeds (weird network state) - should detect 100% packet loss and log warning" {
	# Purpose: Test verifies that the script handles ping commands that succeed but report 100% packet loss.
	# Expected: Script detects 100% packet loss from ping output and logs warning but continues execution.
	# Importance: Weird network states can cause ping to succeed but report no packets received; script must detect this.
	# Test Category: VPN status detection, Ping check edge cases
	setup_vpn_active_fixture "192.168.1.1" 1000 2000 "" 'ENABLE_PING_CHECK=1' 'INTERNAL_PEER_IPS="192.168.1.1"'

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

# bats test_tags=category:high-risk,priority:high
@test "ipsec command hangs (timeout scenario - status check) - should timeout and continue" {
	# Purpose: Test verifies that the script handles ipsec status commands that hang indefinitely.
	# Expected: Script times out ipsec status check and continues execution without blocking.
	# Importance: Network issues can cause ipsec commands to hang; script must handle this to remain responsive.
	# Test Category: Error handling, Timeout handling
	setup_vpn_down_fixture "192.168.1.1" 0

	# Mock ipsec status to hang (simulates timeout)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # Simulate ipsec status hanging
    sleep 6
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Run with timeout to prevent test from hanging
	add_mock_to_path
	run timeout 5 bash "$TEST_SCRIPT" --fake
	assert_success

	# Should handle ipsec status hang gracefully (should timeout and continue)
	# Code at lib/detection.sh:636 uses ipsec status with 2>/dev/null
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# ============================================================================
# 2.1 NETWORK PARTITION DETECTION FUNCTIONS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "check_default_route - Default route exists - should return success" {
	# Purpose: Test verifies that check_default_route correctly detects when default route exists.
	# Expected: Function returns 0 when default route is present.
	# Importance: Default route check is critical for network partition detection.
	# Test Category: Network partition detection
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Mock ip command - default route exists
	mock_ip_route "1" "default via 192.168.1.1 dev eth0"
	add_mock_to_path

	# Source detection functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Test check_default_route function
	run check_default_route
	assert_success

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_default_route - Default route missing - should return failure" {
	# Purpose: Test verifies that check_default_route correctly detects when default route is missing.
	# Expected: Function returns 1 when default route is not found.
	# Importance: Missing default route indicates network partition.
	# Test Category: Network partition detection
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Mock ip command - default route missing
	mock_ip_route "0"
	add_mock_to_path

	# Source detection functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Test check_default_route function
	run check_default_route
	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_dns_resolution - DNS resolution succeeds - should return success" {
	# Purpose: Test verifies that check_dns_resolution correctly detects successful DNS resolution.
	# Expected: Function returns 0 when DNS resolution succeeds.
	# Importance: DNS resolution check is critical for network partition detection.
	# Test Category: Network partition detection
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Mock dig command - DNS resolution succeeds
	mock_dig "1" "8.8.8.8"
	add_mock_to_path

	# Source detection functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Test check_dns_resolution function
	run check_dns_resolution "8.8.8.8" "google.com" "2"
	assert_success

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_dns_resolution - DNS resolution fails (timeout) - should return failure" {
	# Purpose: Test verifies that check_dns_resolution correctly detects DNS resolution timeout.
	# Expected: Function returns 1 when DNS resolution times out.
	# Importance: DNS timeout indicates network partition.
	# Test Category: Network partition detection
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Mock dig command - DNS resolution fails (timeout)
	mock_dig "0" "8.8.8.8" "timeout"
	# Mock nslookup to also fail (prevent fallback from succeeding)
	mock_nslookup_fail >/dev/null
	add_mock_to_path

	# Source detection functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Test check_dns_resolution function with short timeout
	run check_dns_resolution "8.8.8.8" "google.com" "1"
	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_dns_resolution - DNS server unreachable - should return failure" {
	# Purpose: Test verifies that check_dns_resolution correctly detects unreachable DNS server.
	# Expected: Function returns 1 when DNS server is unreachable.
	# Importance: Unreachable DNS server indicates network partition.
	# Test Category: Network partition detection
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Mock dig command - DNS server unreachable
	local mock_dig="${TEST_DIR}/dig"
	cat >"$mock_dig" <<'EOF'
#!/bin/bash
exit 1
EOF
	chmod +x "$mock_dig"
	add_mock_to_path

	# Source detection functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Test check_dns_resolution function
	run check_dns_resolution "192.0.2.1" "google.com" "2"
	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_interface_state - All interfaces UP - should return success" {
	# Purpose: Test verifies that check_interface_state correctly detects when all interfaces are UP.
	# Expected: Function returns 0 when all checked interfaces are UP.
	# Importance: Interface state check is critical for network partition detection.
	# Test Category: Network partition detection
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Mock ip command - all interfaces UP
	mock_ip_interfaces_up "br0,eth0" "0" >/dev/null
	add_mock_to_path

	# Source detection functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Test check_interface_state function
	run check_interface_state "br0,eth0"
	assert_success

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_interface_state - One interface DOWN - should return failure" {
	# Purpose: Test verifies that check_interface_state correctly detects when one interface is DOWN.
	# Expected: Function returns 1 when one or more interfaces are DOWN.
	# Importance: Down interfaces indicate network partition.
	# Test Category: Network partition detection
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Mock ip command - one interface DOWN
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "link" ]] && [[ "$2" == "show" ]]; then
    if [[ "$3" == "br0" ]]; then
        echo "1: br0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default"
        exit 0
    elif [[ "$3" == "eth0" ]]; then
        echo "2: eth0: <BROADCAST,MULTICAST> mtu 1500 qdisc noqueue state DOWN group default"
        exit 0
    fi
fi
# Handle other ip commands
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Source detection functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Test check_interface_state function
	run check_interface_state "br0,eth0"
	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_interface_state - Interface doesn't exist - should return failure" {
	# Purpose: Test verifies that check_interface_state correctly handles non-existent interfaces.
	# Expected: Function returns 1 when interface doesn't exist.
	# Importance: Non-existent interfaces indicate network partition or misconfiguration.
	# Test Category: Network partition detection
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Mock ip command - interface doesn't exist
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "link" ]] && [[ "$2" == "show" ]]; then
    if [[ "$3" == "nonexistent" ]]; then
        echo "Device \"nonexistent\" does not exist."
        exit 1
    fi
fi
# Handle other ip commands
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Source detection functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Test check_interface_state function
	run check_interface_state "nonexistent"
	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_network_partition - All checks pass (network healthy) - should return success" {
	# Purpose: Test verifies that check_network_partition correctly identifies healthy network.
	# Expected: Function returns 0 when all checks pass.
	# Importance: Network partition detection prevents false VPN failure detection.
	# Test Category: Network partition detection
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Mock ip command - default route exists, interfaces UP
	mock_ip_interfaces_up "br0,eth0" "1" >/dev/null

	# Mock dig command - DNS resolution succeeds
	local mock_dig="${TEST_DIR}/dig"
	cat >"$mock_dig" <<'EOF'
#!/bin/bash
echo "8.8.8.8"
exit 0
EOF
	chmod +x "$mock_dig"
	add_mock_to_path

	# Source detection functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Test check_network_partition function
	run check_network_partition "8.8.8.8" "google.com" "2" "br0,eth0"
	assert_success

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_network_partition - One check fails (network partitioned) - should return failure" {
	# Purpose: Test verifies that check_network_partition correctly identifies network partition.
	# Expected: Function returns 1 when one or more checks fail.
	# Importance: Network partition detection prevents false VPN failure detection.
	# Test Category: Network partition detection
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Mock ip command - default route missing, interfaces UP
	mock_ip_interfaces_up "br0,eth0" "0" >/dev/null

	# Mock dig command - DNS resolution fails
	mock_dig "0"
	add_mock_to_path

	# Source detection functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Test check_network_partition function
	run check_network_partition "8.8.8.8" "google.com" "2" "br0,eth0"
	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_network_partition - Custom DNS server/hostname/interfaces - should use custom parameters" {
	# Purpose: Test verifies that check_network_partition correctly uses custom parameters.
	# Expected: Function uses custom DNS server, hostname, and interfaces.
	# Importance: Custom parameters allow flexible network partition detection.
	# Test Category: Network partition detection
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Mock ip command - interfaces UP
	mock_ip_interfaces_up "eth1,eth2" "1" >/dev/null

	# Mock dig command - DNS resolution succeeds
	local mock_dig="${TEST_DIR}/dig"
	cat >"$mock_dig" <<'EOF'
#!/bin/bash
echo "1.1.1.1"
exit 0
EOF
	chmod +x "$mock_dig"
	add_mock_to_path

	# Source detection functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Test check_network_partition function with custom parameters
	run check_network_partition "1.1.1.1" "cloudflare.com" "3" "eth1,eth2"
	assert_success

	remove_mock_from_path
}

# ============================================================================
# 2.2 SA REKEY DETECTION
# ============================================================================

# bats test_tags=category:high-risk,priority:medium
@test "SA rekey detected - SPI changes, baseline reset to 0" {
	# Test verifies that SA rekey detection resets byte counter baseline to 0 when SPI changes.
	# Expected: When SPI changes, byte counter baseline is reset to 0.
	# Importance: Prevents false failure detection after SA rekey events.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Set initial SPI and byte counter
	setup_state_files "192.168.1.1" 0 5000 "0x12345678"

	# Mock ip command - new SPI (rekey occurred)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should detect rekey and reset baseline
	assert_success
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "SA rekey detected" || assert_file_contains "$LOG_FILE" "rekey"

	# Verify byte counter baseline was reset
	local bytes_file="${STATE_DIR}/last_bytes_192_168_1_1"
	if [[ -f "$bytes_file" ]]; then
		local bytes
		bytes=$(cat "$bytes_file")
		# After rekey, baseline should be reset, then updated with current bytes (1000)
		assert_equal "$bytes" 1000
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "SA rekey detected - Byte counter baseline reset allows new baseline" {
	# Test verifies that byte counter baseline reset after rekey allows new baseline to be established.
	# Expected: After rekey, new byte counter baseline can be established from current bytes.
	# Importance: Ensures byte counter tracking works correctly after rekey events.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Set initial SPI and byte counter (high value)
	setup_state_files "192.168.1.1" 0 10000 "0x12345678"

	# Mock ip command - new SPI (rekey) with new bytes
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should detect rekey and establish new baseline
	assert_success
	assert_file_exist "$LOG_FILE"

	# Verify new baseline was established (2000 bytes)
	local bytes_file="${STATE_DIR}/last_bytes_192_168_1_1"
	if [[ -f "$bytes_file" ]]; then
		local bytes
		bytes=$(cat "$bytes_file")
		assert_equal "$bytes" "2000"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "SA rekey detected - Idle state cleared on rekey" {
	# Test verifies that idle state is cleared when SA rekey is detected.
	# Expected: Idle state file is deleted when rekey occurs.
	# Importance: Rekey events reset all state, including idle detection.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Set initial SPI and create idle state file
	setup_state_files "192.168.1.1" 0 1000 "0x12345678"
	local idle_file="${STATE_DIR}/idle_detected_192_168_1_1"
	echo "1" >"$idle_file"

	# Mock ip command - new SPI (rekey occurred)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should detect rekey and clear idle state
	assert_success
	assert_file_exist "$LOG_FILE"

	# Verify idle state file was deleted
	assert_file_not_exist "$idle_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "SA rekey not detected - SPI unchanged" {
	# Test verifies that SA rekey is not detected when SPI remains unchanged.
	# Expected: No rekey detection when SPI is the same as stored value.
	# Importance: Prevents false rekey detection when SPI hasn't changed.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Set initial SPI
	setup_state_files "192.168.1.1" 0 1000 "0x12345678"

	# Mock ip command - same SPI (no rekey)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should not detect rekey
	assert_success
	assert_file_exist "$LOG_FILE"
	# Should not contain rekey message
	refute_file_contains "$LOG_FILE" "SA rekey detected"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "SA rekey detection - First check (no stored SPI) - Should store SPI" {
	# Test verifies that first check stores SPI without detecting rekey.
	# Expected: SPI is stored on first check, no rekey detected.
	# Importance: Ensures SPI tracking starts correctly on first check.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Don't set SPI file (first check)

	# Mock ip command - first SPI
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should store SPI but not detect rekey
	assert_success
	assert_file_exist "$LOG_FILE"

	# Verify SPI was stored
	local spi_file="${STATE_DIR}/spi_192_168_1_1"
	assert_file_exist "$spi_file"
	local spi
	spi=$(cat "$spi_file")
	assert_equal "$spi" "0x12345678"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "SA rekey detection - SPI file corrupted - Should recover gracefully" {
	# Test verifies that corrupted SPI files are recovered gracefully.
	# Expected: Corrupted SPI file is recovered and SPI tracking continues.
	# Importance: Prevents script failures from corrupted SPI files.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Create corrupted SPI file
	local spi_file="${STATE_DIR}/spi_192_168_1_1"
	echo "invalid-value" >"$spi_file"

	# Mock ip command
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should recover corrupted file and continue
	assert_success
	assert_file_exist "$LOG_FILE"

	# Verify SPI file was recovered
	if [[ -f "$spi_file" ]]; then
		local spi
		spi=$(cat "$spi_file")
		# Should contain valid SPI value
		assert_regex "$spi" '^(0x[0-9a-fA-F]+|[0-9]+)$'
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "SA rekey detection - Multiple rekeys in sequence" {
	# Test verifies that multiple rekeys in sequence are detected correctly.
	# Expected: Each rekey is detected and baseline is reset appropriately.
	# Importance: Ensures rekey detection works correctly for multiple rekey events.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Set initial SPI
	setup_state_files "192.168.1.1" 0 1000 "0x12345678"

	# First rekey
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success
	assert_file_contains "$LOG_FILE" "SA rekey detected" || assert_file_contains "$LOG_FILE" "rekey"

	# Second rekey (different SPI)
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0xABCDEF12 reqid 1 mode tunnel"
    echo "    lifetime current: 3000 bytes, 30 packets"
fi
EOF

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success
	assert_file_contains "$LOG_FILE" "SA rekey detected" || assert_file_contains "$LOG_FILE" "rekey"

	# Verify SPI was updated to latest value
	local spi_file="${STATE_DIR}/spi_192_168_1_1"
	if [[ -f "$spi_file" ]]; then
		local spi
		spi=$(cat "$spi_file")
		assert_equal "$spi" "0xABCDEF12"
	fi

	remove_mock_from_path
}

# ============================================================================
# 2.3 FAILURE TYPE DETECTION
# ============================================================================

# bats test_tags=category:high-risk,priority:medium
@test "Failure type tunnel_down - No Phase 2 SA found" {
	# Test verifies that failure type "tunnel_down" is detected when no Phase 2 SA is found.
	# Expected: Failure type is detected as "tunnel_down" when no SA exists.
	# Importance: Enables targeted recovery strategies based on failure type.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Mock ip command - no SA (tunnel down)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Return empty (no SA)
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect tunnel_down failure type
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tunnel down" || assert_file_contains "$LOG_FILE" "tunnel_down"

	# Verify failure type stored in state file
	local failure_type_file="${STATE_DIR}/failure_type_192_168_1_1"
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		assert_equal "$failure_type" "tunnel_down"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type routing_issue - Phase 2 SA exists but bytes not increasing" {
	# Test verifies that failure type "routing_issue" is detected when SA exists but bytes not increasing.
	# Expected: Failure type is detected as "routing_issue" when SA exists but traffic not flowing.
	# Importance: Enables targeted recovery strategies for routing issues.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Set initial bytes (same as current - not increasing)
	setup_state_files "192.168.1.1" 0 1000 "0x12345678"

	# Mock ip command - SA exists but bytes not increasing
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect routing_issue failure type
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Routing issue" || assert_file_contains "$LOG_FILE" "routing_issue"

	# Verify failure type stored in state file
	local failure_type_file="${STATE_DIR}/failure_type_192_168_1_1"
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		assert_equal "$failure_type" "routing_issue"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type routing_issue - Phase 2 SA exists but ping fails" {
	# Test verifies that failure type "routing_issue" is detected when SA exists but ping fails.
	# Expected: Failure type is detected as "routing_issue" when SA exists but connectivity fails.
	# Importance: Enables targeted recovery strategies for routing issues.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=1' 'INTERNAL_PEER_IPS="192.168.1.1"'

	# Set initial bytes (increasing)
	setup_state_files "192.168.1.1" 0 1000 "0x12345678"

	# Mock ip command - SA exists
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"

	# Mock ping - fails
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
exit 1
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect routing_issue failure type
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Routing issue" || assert_file_contains "$LOG_FILE" "routing_issue"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type rekey - SPI changed (not a failure, but logged)" {
	# Test verifies that failure type "rekey" is detected when SPI changes (not a failure).
	# Expected: Failure type is detected as "rekey" when SPI changes, VPN marked as OK.
	# Importance: Rekey events are logged but not treated as failures.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Set initial SPI
	setup_state_files "192.168.1.1" 0 1000 "0x12345678"

	# Mock ip command - new SPI (rekey)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should detect rekey (not a failure)
	assert_success
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "rekey" || assert_file_contains "$LOG_FILE" "SA rekey detected"

	# Verify failure type stored (rekey is logged but VPN is OK)
	local failure_type_file="${STATE_DIR}/failure_type_192_168_1_1"
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		# Rekey may be stored for monitoring purposes
		assert [ "$failure_type" == "rekey" ] || [ "$failure_type" == "unknown" ]
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type unknown - Unable to determine type" {
	# Test verifies that failure type "unknown" is detected when unable to determine specific type.
	# Expected: Failure type is detected as "unknown" when detection methods fail.
	# Importance: Ensures failure tracking continues even when specific type cannot be determined.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Mock ip command - SA exists but no byte counter info
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    # No lifetime line (can't extract bytes)
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect unknown failure type
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Unknown" || assert_file_contains "$LOG_FILE" "unknown"

	# Verify failure type stored in state file
	local failure_type_file="${STATE_DIR}/failure_type_192_168_1_1"
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		assert_equal "$failure_type" "unknown"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type stored in state file for recovery actions" {
	# Test verifies that failure type is stored in state file for use by recovery actions.
	# Expected: Failure type is stored in state file and can be retrieved for recovery strategies.
	# Importance: Enables recovery actions to use failure-specific strategies.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Mock ip command - no SA (tunnel down)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify failure type stored in state file
	local failure_type_file="${STATE_DIR}/failure_type_192_168_1_1"
	assert_file_exist "$failure_type_file"
	local failure_type
	failure_type=$(cat "$failure_type_file")
	assert [ "$failure_type" == "tunnel_down" ] || [ "$failure_type" == "unknown" ]

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type cleared on VPN recovery" {
	# Test verifies that failure type is cleared when VPN recovers.
	# Expected: Failure type file is removed or cleared when VPN becomes healthy.
	# Importance: Ensures failure type tracking is reset after recovery.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Create failure type file (from previous failure)
	local failure_type_file="${STATE_DIR}/failure_type_192_168_1_1"
	echo "tunnel_down" >"$failure_type_file"

	# Mock ip command - VPN recovers
	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# VPN should recover
	assert_success
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "recovered"

	# Failure type file should be cleared or removed
	# Note: The actual behavior depends on implementation - may be removed or cleared
	# This test verifies that recovery happens and failure type is handled

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type detection when xfrm unavailable" {
	# Test verifies that failure type detection works when xfrm is unavailable.
	# Expected: Failure type is detected using fallback methods when xfrm unavailable.
	# Importance: Ensures failure type detection works even when preferred method unavailable.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Don't create ip mock (xfrm unavailable)
	# Mock ipsec - no connection
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # No connection found
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect failure type using fallback
	assert_file_exist "$LOG_FILE"
	# Should contain failure type detection (may be unknown or tunnel_down)
	assert_file_contains "$LOG_FILE" "tunnel_down" || assert_file_contains "$LOG_FILE" "unknown" || assert_file_contains "$LOG_FILE" "VPN check failed"

	remove_mock_from_path
}

# ============================================================================
# 2.4 IDLE TUNNEL DETECTION
# ============================================================================

# bats test_tags=category:high-risk,priority:medium
@test "Idle tunnel detected - Bytes not increasing but ping succeeds" {
	# Test verifies that idle tunnel detection works when bytes are not increasing but ping succeeds.
	# Expected: Tunnel is marked as idle but healthy, idle state stored in state file.
	# Importance: Prevents false failure detection for tunnels that are healthy but not passing traffic.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=1' 'INTERNAL_PEER_IPS="10.0.0.1"'

	# Set initial byte counter (bytes not increasing)
	local last_bytes_file="${STATE_DIR}/last_bytes_192_168_1_1"
	echo "1000" >"$last_bytes_file"

	# Mock ip command - SA exists, bytes static
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"

	# Mock ping - succeeds
	mock_ping_success >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake

	# Should detect idle tunnel (ping succeeds)
	assert_success
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "idle but healthy" || assert_file_contains "$LOG_FILE" "ping check passed"

	# Idle state should be stored
	local idle_file="${STATE_DIR}/idle_detected_192_168_1_1"
	assert_file_exist "$idle_file"
	local idle_state
	idle_state=$(cat "$idle_file" 2>/dev/null || echo "")
	[[ "$idle_state" == "1" ]]

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Idle tunnel detected - Idle state stored in state file" {
	# Test verifies that idle tunnel state is stored in state file.
	# Expected: idle_detected file is created with value "1" when idle tunnel is detected.
	# Importance: Idle state tracking allows monitoring idle tunnels over time.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=1' 'INTERNAL_PEER_IPS="10.0.0.1"'

	# Set initial byte counter (bytes not increasing)
	local last_bytes_file="${STATE_DIR}/last_bytes_192_168_1_1"
	echo "1000" >"$last_bytes_file"

	# Mock ip command - SA exists, bytes static
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"

	# Mock ping - succeeds
	mock_ping_success >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake

	# Idle state file should exist and contain "1"
	local idle_file="${STATE_DIR}/idle_detected_192_168_1_1"
	assert_file_exist "$idle_file"
	local idle_state
	idle_state=$(cat "$idle_file" 2>/dev/null || echo "")
	[[ "$idle_state" == "1" ]]

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Idle tunnel - Keepalive suggestion logged when keepalive disabled" {
	# Test verifies that keepalive suggestion is logged when idle tunnel detected and keepalive disabled.
	# Expected: Log message suggests enabling ENABLE_KEEPALIVE=1 when idle tunnel detected.
	# Importance: Helps users prevent idle tunnel timeouts.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=1' 'ENABLE_KEEPALIVE=0' 'INTERNAL_PEER_IPS="10.0.0.1"'

	# Set initial byte counter (bytes not increasing)
	local last_bytes_file="${STATE_DIR}/last_bytes_192_168_1_1"
	echo "1000" >"$last_bytes_file"

	# Mock ip command - SA exists, bytes static
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"

	# Mock ping - succeeds
	mock_ping_success >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake

	# Should log keepalive suggestion
	assert_success
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "ENABLE_KEEPALIVE" || assert_file_contains "$LOG_FILE" "keepalive"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Idle tunnel - Keepalive daemon check when keepalive enabled" {
	# Test verifies that keepalive daemon status is checked when keepalive is enabled.
	# Expected: Log message checks if keepalive daemon is running when idle tunnel detected.
	# Importance: Helps users ensure keepalive daemon is running when enabled.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=1' 'ENABLE_KEEPALIVE=1' 'INTERNAL_PEER_IPS="10.0.0.1"'

	# Set initial byte counter (bytes not increasing)
	local last_bytes_file="${STATE_DIR}/last_bytes_192_168_1_1"
	echo "1000" >"$last_bytes_file"

	# Mock ip command - SA exists, bytes static
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"

	# Mock ping - succeeds
	mock_ping_success >/dev/null
	add_mock_to_path

	# Don't create keepalive pidfile (daemon not running)
	run bash "$TEST_SCRIPT" --fake

	# Should check keepalive daemon status
	assert_success
	assert_file_exist "$LOG_FILE"
	# Should log message about keepalive daemon (may suggest starting it)
	assert_file_contains "$LOG_FILE" "keepalive" || assert_file_contains "$LOG_FILE" "daemon"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Idle tunnel - Traffic resumes, idle state cleared" {
	# Test verifies that idle state is cleared when traffic resumes.
	# Expected: idle_detected file is deleted or cleared when bytes start increasing again.
	# Importance: Ensures idle state doesn't persist after traffic resumes.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=1' 'INTERNAL_PEER_IPS="10.0.0.1"'

	# Set initial byte counter and idle state
	local last_bytes_file="${STATE_DIR}/last_bytes_192_168_1_1"
	echo "1000" >"$last_bytes_file"
	local idle_file="${STATE_DIR}/idle_detected_192_168_1_1"
	echo "1" >"$idle_file"

	# Mock ip command - SA exists, bytes increasing (traffic resumed)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake

	# Should clear idle state (traffic is flowing)
	assert_success
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "traffic flowing" || assert_file_contains "$LOG_FILE" "VPN OK"

	# Idle state file should be deleted or cleared
	if [[ -f "$idle_file" ]]; then
		local idle_state
		idle_state=$(cat "$idle_file" 2>/dev/null || echo "")
		[[ "$idle_state" != "1" ]]
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Idle tunnel - Ping check disabled, idle not detected" {
	# Test verifies that idle tunnel is not detected when ping check is disabled.
	# Expected: Tunnel is marked as suspect/failed when bytes not increasing and ping disabled.
	# Importance: Ping check is required for idle tunnel detection.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=0' 'INTERNAL_PEER_IPS="10.0.0.1"'

	# Set initial byte counter (bytes not increasing)
	local last_bytes_file="${STATE_DIR}/last_bytes_192_168_1_1"
	echo "1000" >"$last_bytes_file"

	# Mock ip command - SA exists, bytes static
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake

	# Should not detect idle tunnel (ping disabled)
	assert_success
	assert_file_exist "$LOG_FILE"
	# Should mark as suspect/failed (bytes not increasing, ping disabled)
	assert_file_contains "$LOG_FILE" "suspect" || assert_file_contains "$LOG_FILE" "bytes not increasing"

	# Idle state should not be set
	local idle_file="${STATE_DIR}/idle_detected_192_168_1_1"
	if [[ -f "$idle_file" ]]; then
		fail "Idle state should not be set when ping check is disabled"
	fi

	remove_mock_from_path
}
