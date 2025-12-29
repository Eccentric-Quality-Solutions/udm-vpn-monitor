#!/usr/bin/env bats
#
# Tests for Rate Limiting Recovery Actions
# Tests critical paths and error handling scenarios for rate limiting

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_cooldown

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# RATE LIMITING TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "rate limiting: rate limit file corrupted" {
	setup_vpn_down_fixture "192.168.1.1" 5 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'MAX_RESTARTS_PER_HOUR=3' 'COOLDOWN_MINUTES=1'

	# Create corrupted restart file (non-numeric)
	local restart_file="${LOGS_DIR}/restart_count"
	echo "invalid-timestamp" >"$restart_file"

	# Mock ipsec
	local mock_ipsec
	mock_ipsec=$(mock_ipsec)
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT"
	assert_success

	# Should handle corrupted file gracefully
	assert_file_exist "$LOG_FILE"
	# Script should either skip rate limit check or handle error

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "rate limiting: rate limit file is empty" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local restart_file="${TEST_DIR}/logs/restart_count"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create empty restart file
	touch "$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	setup_mock_vpn_environment "192.168.1.1" 0

	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	add_mock_to_path
	run bash "$test_script"
	assert_success

	# Should handle empty file gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "rate limiting: rate limit file is a directory" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local restart_file="${TEST_DIR}/logs/restart_count"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create restart file as a directory
	rm -rf "$restart_file" 2>/dev/null || true
	mkdir -p "$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	setup_mock_vpn_environment "192.168.1.1" 0

	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	add_mock_to_path
	run bash "$test_script"
	assert_success

	# Should handle directory gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "rate limiting: restart count cleanup removes old entries after 24 hours" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local restart_file="${TEST_DIR}/logs/restart_count"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Create restart file with mix of old and recent timestamps
	local now=$base_time
	local one_day_ago=$((now - 86400))   # Exactly 24 hours ago
	local two_days_ago=$((now - 172800)) # 2 days ago
	local recent=$((now - 3600))         # 1 hour ago (recent)
	echo "$two_days_ago" >"$restart_file"
	echo "$one_day_ago" >>"$restart_file"
	echo "$recent" >>"$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	setup_mock_vpn_environment "192.168.1.1" 0

	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	add_mock_to_path
	run bash "$test_script"
	assert_success

	# After restart is recorded, old entries (>24 hours) should be cleaned up
	# File should contain recent timestamp and new restart timestamp, but not old ones
	assert_file_exist "$log_file"
	if [[ -f "$restart_file" ]]; then
		# Verify old entries are gone (two_days_ago and one_day_ago should be removed)
		# Recent entry and new restart should remain
		local file_lines
		file_lines=$(wc -l <"$restart_file" | tr -d ' ')
		# Should have at least 1 line (new restart), possibly 2 (recent + new)
		assert [ "$file_lines" -ge 1 ]
		# Verify old timestamps are not present
		if grep -q "^$two_days_ago$" "$restart_file" 2>/dev/null; then
			fail "Old timestamp (2 days ago) should have been cleaned up"
		fi
		if grep -q "^$one_day_ago$" "$restart_file" 2>/dev/null; then
			fail "Old timestamp (1 day ago) should have been cleaned up"
		fi
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "rate limiting: exactly at limit (should block)" {
	# Test verifies that rate limiting blocks restart when exactly at the limit.
	# Expected: When restart count equals MAX_RESTARTS_PER_HOUR, restart is blocked.
	# Importance: Ensures boundary condition is properly handled to prevent restart loops.
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=1
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local restart_file="${TEST_DIR}/logs/restart_count"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Create restart file with exactly MAX_RESTARTS_PER_HOUR (3) recent restarts
	local now=$base_time
	local recent=$((now - 1800)) # 30 minutes ago (within 1 hour)
	{
		echo "$recent"
		echo "$recent"
		echo "$recent"
	} >"$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Setup mock VPN environment without ipsec (we'll create custom one)
	setup_mock_vpn_environment "192.168.1.1" 0 "" "" 0

	# Create custom mock ipsec
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	run bash "$test_script"
	assert_success

	# Should block restart due to rate limit
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "Rate limit exceeded"

	# Verify restart was not recorded (file should still have 3 entries)
	if [[ -f "$restart_file" ]]; then
		local file_lines
		file_lines=$(wc -l <"$restart_file" | tr -d ' ')
		# Should still have exactly 3 entries (no new restart recorded)
		assert_equal "$file_lines" "3"
	fi

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "rate limiting: one below limit (should allow)" {
	# Test verifies that rate limiting allows restart when one below the limit.
	# Expected: When restart count is MAX_RESTARTS_PER_HOUR - 1, restart is allowed.
	# Importance: Ensures boundary condition allows legitimate recovery when just under limit.
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=1
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local restart_file="${TEST_DIR}/logs/restart_count"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Create restart file with exactly MAX_RESTARTS_PER_HOUR - 1 (2) recent restarts
	local now=$base_time
	local recent=$((now - 1800)) # 30 minutes ago (within 1 hour)
	{
		echo "$recent"
		echo "$recent"
	} >"$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Setup mock VPN environment without ipsec (we'll create custom one)
	setup_mock_vpn_environment "192.168.1.1" 0 "" "" 0

	# Create custom mock ipsec
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	run bash "$test_script"
	assert_success

	# Should allow restart (not rate limited)
	assert_file_exist "$log_file"
	# Should not contain rate limit message
	refute_file_contains "$log_file" "Rate limit exceeded"

	# Verify restart was recorded (file should have 3 entries now: 2 old + 1 new)
	if [[ -f "$restart_file" ]]; then
		local file_lines
		file_lines=$(wc -l <"$restart_file" | tr -d ' ')
		# Should have at least 3 entries (2 old + 1 new restart)
		assert [ "$file_lines" -ge 3 ]
	fi

	remove_mock_from_path
}
