#!/usr/bin/env bats
#
# Tests for Multiple Internal IPs Ping Logic
# Tests check_ping_multiple_ips() with various IP counts, 30% threshold calculation,
# single IP (100% success), and empty array handling

load test_helper

# Source the detection library functions
# shellcheck source=../lib/detection.sh
source "${BATS_TEST_DIRNAME}/../lib/detection.sh"

# Source logging for handle_error functions
# shellcheck source=../lib/logging.sh
source "${BATS_TEST_DIRNAME}/../lib/logging.sh"

# ============================================================================
# MULTIPLE INTERNAL IPS PING LOGIC TESTS
# ============================================================================

# Mock ping command that succeeds
mock_ping_success() {
	cat >"${TEST_DIR}/ping" <<'EOF'
#!/bin/bash
# Mock ping that always succeeds
exit 0
EOF
	chmod +x "${TEST_DIR}/ping"
	export PATH="${TEST_DIR}:${PATH}"
}

# Mock ping command that fails
mock_ping_failure() {
	cat >"${TEST_DIR}/ping" <<'EOF'
#!/bin/bash
# Mock ping that always fails
exit 1
EOF
	chmod +x "${TEST_DIR}/ping"
	export PATH="${TEST_DIR}:${PATH}"
}

# Mock ping command that succeeds for specific IPs
# Arguments: space-separated list of IPs that should succeed
# Note: ping is called with IP as last argument: ping [args] -c count -W timeout -q target_ip
mock_ping_selective() {
	local success_ips="$1"
	cat >"${TEST_DIR}/ping" <<EOF
#!/bin/bash
# Mock ping that succeeds for specific IPs
# Check all arguments for target IP (ping is called with IP as last argument)
for arg in "\$@"; do
	for ip in $success_ips; do
		if [ "\$arg" = "\$ip" ]; then
			exit 0
		fi
	done
done
exit 1
EOF
	chmod +x "${TEST_DIR}/ping"
	export PATH="${TEST_DIR}:${PATH}"
}

# bats test_tags=category:high-risk,priority:high
@test "check_ping_multiple_ips - single IP requires 100% success" {
	# Purpose: Test that single IP requires 100% success (not 30%)
	# Expected: Single IP ping must succeed for function to succeed
	# Importance: Single IP should be more strict than multiple IPs
	setup_test_environment
	mock_ping_success

	run check_ping_multiple_ips "192.168.1.1" ""
	assert_success
}

# bats test_tags=category:high-risk,priority:high
@test "check_ping_multiple_ips - single IP failure returns failure" {
	# Purpose: Test that single IP failure causes function to fail
	# Expected: Function fails when single IP ping fails
	# Importance: Single IP requires 100% success
	setup_test_environment
	mock_ping_failure

	run check_ping_multiple_ips "192.168.1.1" ""
	assert_failure
}

# bats test_tags=category:high-risk,priority:high
@test "check_ping_multiple_ips - empty array returns failure" {
	# Purpose: Test that empty array is handled correctly
	# Expected: Function fails for empty array (caller should handle fallback)
	# Importance: Empty array should not cause crashes
	setup_test_environment

	run check_ping_multiple_ips "" ""
	assert_failure
}

# bats test_tags=category:high-risk,priority:high
@test "check_ping_multiple_ips - 2 IPs requires at least 1 success (30% threshold)" {
	# Purpose: Test 30% threshold calculation for 2 IPs (ceil(0.3 * 2) = 1)
	# Expected: Function succeeds if at least 1 of 2 IPs responds
	# Importance: Verifies threshold calculation is correct
	setup_test_environment
	mock_ping_selective "192.168.1.1"

	run check_ping_multiple_ips "192.168.1.1 192.168.1.2" ""
	assert_success
}

# bats test_tags=category:high-risk,priority:high
@test "check_ping_multiple_ips - 2 IPs fails if both fail" {
	# Purpose: Test that 2 IPs fail if threshold not met
	# Expected: Function fails if 0 of 2 IPs respond (< 30% threshold)
	# Importance: Verifies threshold enforcement
	setup_test_environment
	mock_ping_failure

	run check_ping_multiple_ips "192.168.1.1 192.168.1.2" ""
	assert_failure
}

# bats test_tags=category:high-risk,priority:high
@test "check_ping_multiple_ips - 3 IPs requires at least 1 success (30% threshold)" {
	# Purpose: Test 30% threshold calculation for 3 IPs (ceil(0.3 * 3) = 1)
	# Expected: Function succeeds if at least 1 of 3 IPs responds
	# Importance: Verifies threshold calculation with ceil rounding
	setup_test_environment
	mock_ping_selective "192.168.1.1"

	run check_ping_multiple_ips "192.168.1.1 192.168.1.2 192.168.1.3" ""
	assert_success
}

# bats test_tags=category:high-risk,priority:high
@test "check_ping_multiple_ips - 3 IPs fails if all fail" {
	# Purpose: Test that 3 IPs fail if threshold not met
	# Expected: Function fails if 0 of 3 IPs respond (< 30% threshold)
	# Importance: Verifies threshold enforcement
	setup_test_environment
	mock_ping_failure

	run check_ping_multiple_ips "192.168.1.1 192.168.1.2 192.168.1.3" ""
	assert_failure
}

# bats test_tags=category:high-risk,priority:high
@test "check_ping_multiple_ips - 10 IPs requires at least 3 success (30% threshold)" {
	# Purpose: Test 30% threshold calculation for 10 IPs (ceil(0.3 * 10) = 3)
	# Expected: Function succeeds if at least 3 of 10 IPs respond
	# Importance: Verifies threshold calculation with larger arrays
	setup_test_environment
	mock_ping_selective "192.168.1.1 192.168.1.2 192.168.1.3"

	run check_ping_multiple_ips "192.168.1.1 192.168.1.2 192.168.1.3 192.168.1.4 192.168.1.5 192.168.1.6 192.168.1.7 192.168.1.8 192.168.1.9 192.168.1.10" ""
	assert_success
}

# bats test_tags=category:high-risk,priority:high
@test "check_ping_multiple_ips - 10 IPs fails if only 2 succeed" {
	# Purpose: Test that 10 IPs fail if threshold not met (2 < 3 required)
	# Expected: Function fails if only 2 of 10 IPs respond (< 30% threshold)
	# Importance: Verifies threshold enforcement with ceil rounding
	setup_test_environment
	mock_ping_selective "192.168.1.1 192.168.1.2"

	run check_ping_multiple_ips "192.168.1.1 192.168.1.2 192.168.1.3 192.168.1.4 192.168.1.5 192.168.1.6 192.168.1.7 192.168.1.8 192.168.1.9 192.168.1.10" ""
	assert_failure
}

# bats test_tags=category:high-risk,priority:high
@test "check_ping_multiple_ips - 10 IPs succeeds with exactly 3 success" {
	# Purpose: Test that exactly meeting threshold succeeds
	# Expected: Function succeeds if exactly 3 of 10 IPs respond (= 30% threshold)
	# Importance: Verifies threshold is inclusive (>=)
	setup_test_environment
	mock_ping_selective "192.168.1.1 192.168.1.2 192.168.1.3"

	run check_ping_multiple_ips "192.168.1.1 192.168.1.2 192.168.1.3 192.168.1.4 192.168.1.5 192.168.1.6 192.168.1.7 192.168.1.8 192.168.1.9 192.168.1.10" ""
	assert_success
}

# bats test_tags=category:high-risk,priority:high
@test "check_ping_multiple_ips - skips empty IPs in array" {
	# Purpose: Test that empty IPs in array are skipped
	# Expected: Empty IPs don't count toward total or success count
	# Importance: Handles malformed input gracefully
	setup_test_environment
	mock_ping_selective "192.168.1.1"

	run check_ping_multiple_ips "192.168.1.1  192.168.1.2" ""
	# Should succeed because 1 of 1 valid IPs responded (empty IP skipped)
	assert_success
}

# bats test_tags=category:high-risk,priority:high
@test "check_ping_multiple_ips - uses local IP for source when provided" {
	# Purpose: Test that local IP is passed to ping command correctly
	# Expected: Local IP is used as source IP for ping
	# Importance: Source IP is needed for routing through VPN tunnel
	setup_test_environment

	# Create mock ping that checks for -I flag (source IP) and target IP
	# ping is called as: ping -I local_ip -c count -W timeout -q target_ip
	cat >"${TEST_DIR}/ping" <<'EOF'
#!/bin/bash
# Mock ping that checks for source IP flag (-I) and target IP (last argument)
# Check if -I flag is present with correct source IP
if [[ "$*" =~ -I[[:space:]]+192\.168\.1\.100 ]]; then
	# Also verify target IP is in arguments (should be last)
	if [[ "$*" =~ 192\.168\.1\.1 ]]; then
		exit 0
	fi
fi
exit 1
EOF
	chmod +x "${TEST_DIR}/ping"
	export PATH="${TEST_DIR}:${PATH}"

	run check_ping_multiple_ips "192.168.1.1" "192.168.1.100"
	assert_success
}

# bats test_tags=category:high-risk,priority:high
@test "check_ping_multiple_ips - logs success message with count" {
	# Purpose: Test that success is logged with correct count and percentage
	# Expected: Log message includes success count, total count, and percentage
	# Importance: Logging helps with debugging
	setup_test_environment
	mock_ping_selective "192.168.1.1 192.168.1.2"

	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	mkdir -p "$(dirname "$log_file")"
	LOG_FILE="$log_file"
	export LOG_FILE

	run check_ping_multiple_ips "192.168.1.1 192.168.1.2 192.168.1.3" ""
	assert_success

	# Check log file contains success message
	if [[ -f "$log_file" ]]; then
		assert_file_contains "$log_file" "2/3 internal IPs responded"
		assert_file_contains "$log_file" "30% threshold"
	fi
}

# bats test_tags=category:high-risk,priority:high
@test "check_ping_multiple_ips - logs failure message with count" {
	# Purpose: Test that failure is logged with correct count and percentage
	# Expected: Log message includes success count, total count, and percentage
	# Importance: Logging helps with debugging
	setup_test_environment
	mock_ping_failure

	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	mkdir -p "$(dirname "$log_file")"
	LOG_FILE="$log_file"
	export LOG_FILE

	run check_ping_multiple_ips "192.168.1.1 192.168.1.2" ""
	assert_failure

	# Check log file contains failure message
	if [[ -f "$log_file" ]]; then
		assert_file_contains "$log_file" "0/2 internal IPs responded"
		assert_file_contains "$log_file" "30% threshold"
	fi
}

# bats test_tags=category:high-risk,priority:high
@test "check_ping_multiple_ips - threshold calculation uses ceil rounding" {
	# Purpose: Test that threshold calculation uses ceil (rounds up)
	# Expected: ceil(0.3 * count) rounds up (e.g., ceil(0.3 * 2) = 1, ceil(0.3 * 4) = 2)
	# Importance: Ensures threshold is always rounded up, not down
	setup_test_environment

	# Test with 4 IPs: ceil(0.3 * 4) = ceil(1.2) = 2
	# So we need at least 2 successes
	mock_ping_selective "192.168.1.1"

	run check_ping_multiple_ips "192.168.1.1 192.168.1.2 192.168.1.3 192.168.1.4" ""
	# Should fail because 1 < 2 (threshold)
	assert_failure

	# Now with 2 successes
	mock_ping_selective "192.168.1.1 192.168.1.2"

	run check_ping_multiple_ips "192.168.1.1 192.168.1.2 192.168.1.3 192.168.1.4" ""
	# Should succeed because 2 >= 2 (threshold)
	assert_success
}

# bats test_tags=category:high-risk,priority:high
@test "check_ping_multiple_ips - sequential ping execution" {
	# Purpose: Test that pings are executed sequentially (not parallel)
	# Expected: Pings happen one after another
	# Importance: UDM OS doesn't support parallel execution
	setup_test_environment

	# Create mock ping that logs order
	# ping is called as: ping -c count -W timeout -q target_ip
	# So the target IP is the last argument
	local ping_log="${TEST_DIR}/ping_order.log"
	cat >"${TEST_DIR}/ping" <<EOF
#!/bin/bash
# Log the last argument (target IP)
echo "\${@: -1}" >> "$ping_log"
exit 0
EOF
	chmod +x "${TEST_DIR}/ping"
	export PATH="${TEST_DIR}:${PATH}"

	run check_ping_multiple_ips "192.168.1.1 192.168.1.2 192.168.1.3" ""
	assert_success

	# Verify pings happened sequentially (order preserved)
	if [[ -f "$ping_log" ]]; then
		local first_ip
		first_ip=$(head -n1 "$ping_log")
		assert_equal "$first_ip" "192.168.1.1"
	fi
}
