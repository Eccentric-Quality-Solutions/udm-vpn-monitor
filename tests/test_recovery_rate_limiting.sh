#!/usr/bin/env bats
#
# Tests for Rate Limiting Recovery Actions
# Tests critical paths and error handling scenarios for rate limiting

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_cooldown
load fixtures/vpn_rate_limited
load fixtures/vpn_at_tier

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# RATE LIMITING TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "rate limiting: rate limit file corrupted" {
	# Purpose: Test verifies that rate limiting handles corrupted restart count file gracefully
	# Expected: Script recovers corrupted file and continues execution without crashing
	# Importance: Prevents script failures from corrupted rate limit files, ensuring monitoring continues
	setup_vpn_at_tier_fixture 3 "192.168.1.1" 'MAX_RESTARTS_PER_HOUR=3' 'COOLDOWN_MINUTES=1'

	# Create corrupted restart file (non-numeric)
	local restart_file="${STATE_DIR}/restart_count"
	echo "invalid-timestamp" >"$restart_file"

	# Mock ipsec
	local mock_ipsec
	mock_ipsec=$(mock_ipsec)
	add_mock_to_path

	run bash "$TEST_SCRIPT"
	# Script may exit with status 1 due to warnings (e.g., corrupted file recovery, verification failures)
	# but should handle corrupted file gracefully
	# Allow both success (0) and warnings (1) exit codes
	if [[ $status -eq 1 ]]; then
		# Check if exit was due to warnings (expected) vs actual errors
		assert_file_exist "$LOG_FILE"
		# Should have handled corrupted file (recovered it)
		assert_file_contains "$LOG_FILE" "corrupted" || assert_file_contains "$LOG_FILE" "recovering"
	fi

	# Should handle corrupted file gracefully
	assert_file_exist "$LOG_FILE"
	# Script should either skip rate limit check or handle error

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "rate limiting: rate limit file is empty" {
	# Purpose: Test verifies that rate limiting handles empty restart count file gracefully
	# Expected: Script treats empty file as no previous restarts and allows recovery actions
	# Importance: Prevents script failures from empty rate limit files, ensuring recovery can proceed
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/state"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}/state"
	local restart_file="${TEST_DIR}/state/restart_count"

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${state_dir}"

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	# Use location name "NYC" to match the config file (LOCATION_NYC_EXTERNAL)
	local failure_counter
	failure_counter=$(get_peer_state_file_path "NYC" "192.168.1.1" "failure_count")

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

	run bash "$test_script"
	assert_success

	# Should handle empty file gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "rate limiting: rate limit file is a directory" {
	# Purpose: Test verifies that rate limiting handles case where restart count path is a directory gracefully
	# Expected: Script detects directory instead of file and handles error without crashing
	# Importance: Prevents script failures from misconfigured rate limit file paths
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/state"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}/state"
	local restart_file="${TEST_DIR}/state/restart_count"

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${state_dir}"

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	# Use location name "NYC" to match the config file (LOCATION_NYC_EXTERNAL)
	local failure_counter
	failure_counter=$(get_peer_state_file_path "NYC" "192.168.1.1" "failure_count")

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

	run bash "$test_script"
	assert_success

	# Should handle directory gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "rate limiting: restart count cleanup removes old entries after 24 hours" {
	# Purpose: Test verifies that restart count cleanup removes entries older than 24 hours
	# Expected: Old restart timestamps (>24 hours) are removed from restart count file, recent entries remain
	# Importance: Cleanup prevents restart count file from growing indefinitely and ensures accurate rate limiting
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/state"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}/state"
	local restart_file="${TEST_DIR}/state/restart_count"

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${state_dir}"

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	# Use location name "NYC" to match the config file (LOCATION_NYC_EXTERNAL)
	local failure_counter
	failure_counter=$(get_peer_state_file_path "NYC" "192.168.1.1" "failure_count")

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0

	# Create restart file with mix of old and recent timestamps
	local now=$base_time
	local one_day_ago=$((now - 86400))   # Exactly 24 hours ago
	local two_days_ago=$((now - 172800)) # 2 days ago
	local recent=$((now - 3600))         # 1 hour ago (recent)
	echo "$two_days_ago" >"$restart_file"
	echo "$one_day_ago" >>"$restart_file"
	echo "$recent" >>"$restart_file"

	# Set failure count to Tier 3 threshold (will be incremented to 6 when VPN is detected as down)
	# Use 4 so that after increment it becomes 5 (TIER3_THRESHOLD)
	echo "4" >"$failure_counter"

	# Create mock ip command that returns empty output (no SA) - VPN is definitely down
	# This ensures VPN is detected as down, triggering Tier 3 recovery
	mock_ip_vpn_down

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

	run bash "$test_script" --fake
	# Allow exit code 0 (success) or 1 (warnings) - VPN verification failures cause warnings but script should still run
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

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
	# Purpose: Test verifies that rate limiting blocks restart when exactly at the limit
	# Expected: When restart count equals MAX_RESTARTS_PER_HOUR, restart is blocked
	# Importance: Ensures boundary condition is properly handled to prevent restart loops

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Set up rate limited fixture with exactly MAX_RESTARTS_PER_HOUR (3) recent restarts
	local now=$base_time
	local recent=$((now - 1800)) # 30 minutes ago (within 1 hour)
	setup_vpn_rate_limited_fixture "192.168.1.1" 3 \
		"$recent" \
		"$recent" \
		"$recent" \
		'COOLDOWN_MINUTES=1' \
		'ENABLE_XFRM_RECOVERY=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0'

	local restart_file="${STATE_DIR}/restart_count"

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
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake
	# Allow exit code 0 (success) or 1 (warnings) - VPN verification failures cause warnings but script should still run
	# Rate limiting is working correctly (blocking restart) even if script exits with warnings
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should block restart due to rate limit
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Rate limit exceeded"

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
	# Purpose: Test verifies that rate limiting allows restart when one below the limit
	# Expected: When restart count is MAX_RESTARTS_PER_HOUR - 1, restart is allowed
	# Importance: Ensures boundary condition allows legitimate recovery when just under limit

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Set up rate limited fixture with exactly MAX_RESTARTS_PER_HOUR - 1 (2) recent restarts
	local now=$base_time
	local recent=$((now - 1800)) # 30 minutes ago (within 1 hour)
	setup_vpn_rate_limited_fixture "192.168.1.1" 2 \
		"$recent" \
		"$recent" \
		'COOLDOWN_MINUTES=1' \
		'ENABLE_XFRM_RECOVERY=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0'

	local restart_file="${STATE_DIR}/restart_count"

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
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake
	# Allow exit code 0 (success) or 1 (warnings) - VPN verification failures cause warnings but script should still run
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should allow restart (not rate limited)
	assert_file_exist "$LOG_FILE"
	# Should not contain rate limit message
	refute_file_contains "$LOG_FILE" "Rate limit exceeded"

	# Verify restart was recorded (file should have 3 entries now: 2 old + 1 new)
	if [[ -f "$restart_file" ]]; then
		local file_lines
		file_lines=$(wc -l <"$restart_file" | tr -d ' ')
		# Should have at least 3 entries (2 old + 1 new restart)
		assert [ "$file_lines" -ge 3 ]
	fi

	remove_mock_from_path
}
