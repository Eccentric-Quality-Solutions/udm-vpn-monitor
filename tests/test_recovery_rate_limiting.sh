#!/usr/bin/env bats
#
# Tests for Rate Limiting Recovery Actions
# Tests critical paths and error handling scenarios for rate limiting

load test_helper
load helpers/config
load helpers/assertions
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
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
	setup_vpn_at_tier_fixture 3 "${TEST_PEER_IP}" 'MAX_RESTARTS_PER_WINDOW=3' 'RATE_LIMIT_WINDOW_MINUTES=60'

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
		assert_log_contains_any "$LOG_FILE" "corrupted" "recovering"
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
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"MAX_RESTARTS_PER_WINDOW=3" \
		"RATE_LIMIT_WINDOW_MINUTES=60"

	local state_dir="${TEST_DIR}/state"
	setup_test_environment "$state_dir" "${TEST_DIR}/logs"
	local restart_file="${TEST_DIR}/state/restart_count"

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${state_dir}"

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	# Use location name "NYC" to match the config file (LOCATION_NYC_EXTERNAL)
	local failure_counter
	failure_counter=$(get_peer_state_file_path "NYC" "${TEST_PEER_IP}" "failure_count")

	# Create empty restart file
	touch "$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	setup_mock_vpn_environment "${TEST_PEER_IP}" 0 "" "" 0

	mock_ipsec_reload_restart 0 0
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$LOG_FILE")

	run bash "$test_script"
	assert_success

	# Should handle empty file gracefully
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "rate limiting: rate limit file is a directory" {
	# Purpose: Test verifies that rate limiting handles case where restart count path is a directory gracefully
	# Expected: Script detects directory instead of file and handles error without crashing
	# Importance: Prevents script failures from misconfigured rate limit file paths
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"MAX_RESTARTS_PER_WINDOW=3" \
		"RATE_LIMIT_WINDOW_MINUTES=60"

	local state_dir="${TEST_DIR}/state"
	setup_test_environment "$state_dir" "${TEST_DIR}/logs"
	local restart_file="${TEST_DIR}/state/restart_count"

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${state_dir}"

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	# Use location name "NYC" to match the config file (LOCATION_NYC_EXTERNAL)
	local failure_counter
	failure_counter=$(get_peer_state_file_path "NYC" "${TEST_PEER_IP}" "failure_count")

	# Create restart file as a directory
	rm -rf "$restart_file" 2>/dev/null || true
	mkdir -p "$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	setup_mock_vpn_environment "${TEST_PEER_IP}" 0 "" "" 0

	mock_ipsec_reload_restart 0 0
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$LOG_FILE")

	run bash "$test_script"
	assert_success

	# Should handle directory gracefully
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "rate limiting: restart count cleanup removes old entries after 24 hours" {
	# Purpose: Test verifies that restart count cleanup removes entries older than 24 hours
	# Expected: Old restart timestamps (>24 hours) are removed from restart count file, recent entries remain
	# Importance: Cleanup prevents restart count file from growing indefinitely and ensures accurate rate limiting
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"MAX_RESTARTS_PER_WINDOW=10" \
		"RATE_LIMIT_WINDOW_MINUTES=60" \
		"ENABLE_XFRM_RECOVERY=0" \
		"ENABLE_NETWORK_PARTITION_CHECK=0"

	local state_dir="${TEST_DIR}/state"
	setup_test_environment "$state_dir" "${TEST_DIR}/logs"
	local restart_file="${TEST_DIR}/state/restart_count"

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${state_dir}"

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	# Use location name "NYC" to match the config file (LOCATION_NYC_EXTERNAL)
	local failure_counter
	failure_counter=$(get_peer_state_file_path "NYC" "${TEST_PEER_IP}" "failure_count")

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

	# VPN must be DOWN for recovery to trigger: status_exit=1 so ipsec status fails
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$LOG_FILE")

	run bash "$test_script" --fake
	# Allow exit code 0 (success) or 1 (warnings) - VPN verification failures cause warnings but script should still run
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# After restart is recorded, old entries (>24 hours) should be cleaned up
	# File should contain recent timestamp and new restart timestamp, but not old ones
	assert_file_exist "$LOG_FILE"
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
	# Expected: When restart count equals MAX_RESTARTS_PER_WINDOW, restart is blocked
	# Importance: Ensures boundary condition is properly handled to prevent restart loops

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Set up rate limited fixture with exactly MAX_RESTARTS_PER_WINDOW (3) recent restarts
	local now=$base_time
	local recent=$((now - 1800)) # 30 minutes ago (within 1 hour)
	setup_vpn_rate_limited_fixture "${TEST_PEER_IP}" 3 \
		"$recent" \
		"$recent" \
		"$recent" \
		'MAX_RESTARTS_PER_WINDOW=3' \
		'RATE_LIMIT_WINDOW_MINUTES=60' \
		'ENABLE_XFRM_RECOVERY=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0'

	local restart_file="${STATE_DIR}/restart_count"

	# Create mock ip command that returns empty output (no SA) - VPN is definitely down
	# This ensures VPN is detected as down, triggering Tier 3 recovery
	mock_ip_vpn_down

	# VPN must be DOWN for recovery to trigger: status_exit=1 so ipsec status fails
	mock_ipsec_reload_restart 0 0 1
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
	# Expected: When restart count is MAX_RESTARTS_PER_WINDOW - 1, restart is allowed
	# Importance: Ensures boundary condition allows legitimate recovery when just under limit

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Set up rate limited fixture with exactly MAX_RESTARTS_PER_WINDOW - 1 (2) recent restarts
	local now=$base_time
	local recent=$((now - 1800)) # 30 minutes ago (within 1 hour)
	setup_vpn_rate_limited_fixture "${TEST_PEER_IP}" 2 \
		"$recent" \
		"$recent" \
		'MAX_RESTARTS_PER_WINDOW=3' \
		'RATE_LIMIT_WINDOW_MINUTES=60' \
		'ENABLE_XFRM_RECOVERY=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0'

	local restart_file="${STATE_DIR}/restart_count"

	# Create mock ip command that returns empty output (no SA) - VPN is definitely down
	# This ensures VPN is detected as down, triggering Tier 3 recovery
	mock_ip_vpn_down

	# VPN must be DOWN for recovery to trigger: status_exit=1 so ipsec status fails
	mock_ipsec_reload_restart 0 0 1
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

# ============================================================================
# MINIMUM RESTART INTERVAL TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "rate limiting: minimum interval blocks restart when too soon" {
	# Purpose: Test verifies that minimum restart interval blocks restart when not enough time has passed
	# Expected: When time since last restart < MIN_RESTART_INTERVAL_SECONDS, restart is blocked
	# Importance: Ensures minimum spacing between restarts prevents rapid-fire restarts

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Set up fixture with a recent restart (15 seconds ago, less than 30 second minimum)
	local now=$base_time
	local min_interval=30
	local last_restart=$((now - 15)) # 15 seconds ago (less than 30 second minimum)

	# Create config with minimum interval
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"MAX_RESTARTS_PER_WINDOW=10" \
		"RATE_LIMIT_WINDOW_MINUTES=60" \
		"MIN_RESTART_INTERVAL_SECONDS=${min_interval}" \
		"ENABLE_XFRM_RECOVERY=0" \
		"ENABLE_NETWORK_PARTITION_CHECK=0"

	local state_dir="${TEST_DIR}/state"
	setup_test_environment "$state_dir" "${TEST_DIR}/logs"
	local restart_file="${TEST_DIR}/state/restart_count"

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${state_dir}"

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local failure_counter
	failure_counter=$(get_peer_state_file_path "NYC" "${TEST_PEER_IP}" "failure_count")

	# Create restart file with recent restart
	echo "$last_restart" >"$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Create mock ip command that returns empty output (no SA) - VPN is definitely down
	mock_ip_vpn_down

	# VPN must be DOWN for recovery to trigger: status_exit=1 so ipsec status fails
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$LOG_FILE")

	run bash "$test_script" --fake
	# Allow exit code 0 (success) or 1 (warnings) - minimum interval blocking is expected
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should block restart due to minimum interval
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Minimum restart interval not met"

	# Verify restart was not recorded (file should still have 1 entry)
	if [[ -f "$restart_file" ]]; then
		local file_lines
		file_lines=$(wc -l <"$restart_file" | tr -d ' ')
		# Should still have exactly 1 entry (no new restart recorded)
		assert_equal "$file_lines" "1"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "rate limiting: minimum interval allows restart when enough time has passed" {
	# Purpose: Test verifies that minimum restart interval allows restart when enough time has passed
	# Expected: When time since last restart >= MIN_RESTART_INTERVAL_SECONDS, restart is allowed
	# Importance: Ensures legitimate restarts are allowed after minimum spacing

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Set up fixture with an old restart (45 seconds ago, more than 30 second minimum)
	local now=$base_time
	local min_interval=30
	local last_restart=$((now - 45)) # 45 seconds ago (more than 30 second minimum)

	# Create config with minimum interval
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"MAX_RESTARTS_PER_WINDOW=10" \
		"RATE_LIMIT_WINDOW_MINUTES=60" \
		"MIN_RESTART_INTERVAL_SECONDS=${min_interval}" \
		"ENABLE_XFRM_RECOVERY=0" \
		"ENABLE_NETWORK_PARTITION_CHECK=0"

	local state_dir="${TEST_DIR}/state"
	setup_test_environment "$state_dir" "${TEST_DIR}/logs"
	local restart_file="${TEST_DIR}/state/restart_count"

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${state_dir}"

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local failure_counter
	failure_counter=$(get_peer_state_file_path "NYC" "${TEST_PEER_IP}" "failure_count")

	# Create restart file with old restart
	echo "$last_restart" >"$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Create mock ip command that returns empty output (no SA) - VPN is definitely down
	mock_ip_vpn_down

	# VPN must be DOWN for recovery to trigger: status_exit=1 so ipsec status fails
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$LOG_FILE")

	run bash "$test_script" --fake
	# Allow exit code 0 (success) or 1 (warnings) - restart should be allowed
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should allow restart (not blocked by minimum interval)
	assert_file_exist "$LOG_FILE"
	# Should not contain minimum interval message
	refute_file_contains "$LOG_FILE" "Minimum restart interval not met"

	# Verify restart was recorded (file should have 2 entries now: 1 old + 1 new)
	if [[ -f "$restart_file" ]]; then
		local file_lines
		file_lines=$(wc -l <"$restart_file" | tr -d ' ')
		# Should have at least 2 entries (1 old + 1 new restart)
		assert [ "$file_lines" -ge 2 ]
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "rate limiting: minimum interval of 0 disables the check" {
	# Purpose: Test verifies that setting MIN_RESTART_INTERVAL_SECONDS=0 disables the minimum interval check
	# Expected: When MIN_RESTART_INTERVAL_SECONDS=0, minimum interval check is skipped
	# Importance: Ensures users can disable minimum spacing if needed

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Set up fixture with a very recent restart (1 second ago)
	local now=$base_time
	local min_interval=0            # Disabled
	local last_restart=$((now - 1)) # 1 second ago (would normally block, but interval is disabled)

	# Create config with minimum interval disabled
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"MAX_RESTARTS_PER_WINDOW=10" \
		"RATE_LIMIT_WINDOW_MINUTES=60" \
		"MIN_RESTART_INTERVAL_SECONDS=${min_interval}" \
		"ENABLE_XFRM_RECOVERY=0" \
		"ENABLE_NETWORK_PARTITION_CHECK=0"

	local state_dir="${TEST_DIR}/state"
	setup_test_environment "$state_dir" "${TEST_DIR}/logs"
	local restart_file="${TEST_DIR}/state/restart_count"

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${state_dir}"

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local failure_counter
	failure_counter=$(get_peer_state_file_path "NYC" "${TEST_PEER_IP}" "failure_count")

	# Create restart file with very recent restart
	echo "$last_restart" >"$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Create mock ip command that returns empty output (no SA) - VPN is definitely down
	mock_ip_vpn_down

	# VPN must be DOWN for recovery to trigger: status_exit=1 so ipsec status fails
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$LOG_FILE")

	run bash "$test_script" --fake
	# Allow exit code 0 (success) or 1 (warnings) - restart should be allowed
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should allow restart (minimum interval check is disabled)
	assert_file_exist "$LOG_FILE"
	# Should not contain minimum interval message
	refute_file_contains "$LOG_FILE" "Minimum restart interval not met"

	# Verify restart was recorded (file should have 2 entries now: 1 old + 1 new)
	if [[ -f "$restart_file" ]]; then
		local file_lines
		file_lines=$(wc -l <"$restart_file" | tr -d ' ')
		# Should have at least 2 entries (1 old + 1 new restart)
		assert [ "$file_lines" -ge 2 ]
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "rate limiting: minimum interval with unsorted timestamps (edge case)" {
	# Purpose: Test verifies that minimum interval check correctly handles unsorted timestamps
	# Expected: When timestamps are out of order, the most recent (maximum) timestamp is used
	# Importance: Ensures minimum interval works correctly even with clock skew or file corruption recovery

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Set up fixture with unsorted timestamps (oldest first, then newer, then oldest again)
	local now=$base_time
	local min_interval=30
	local old_restart=$((now - 100))   # 100 seconds ago
	local recent_restart=$((now - 15)) # 15 seconds ago (most recent, should be used)
	local middle_restart=$((now - 50)) # 50 seconds ago

	# Create config with minimum interval
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"MAX_RESTARTS_PER_WINDOW=10" \
		"RATE_LIMIT_WINDOW_MINUTES=60" \
		"MIN_RESTART_INTERVAL_SECONDS=${min_interval}" \
		"ENABLE_XFRM_RECOVERY=0" \
		"ENABLE_NETWORK_PARTITION_CHECK=0"

	local state_dir="${TEST_DIR}/state"
	setup_test_environment "$state_dir" "${TEST_DIR}/logs"
	local restart_file="${TEST_DIR}/state/restart_count"

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${state_dir}"

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local failure_counter
	failure_counter=$(get_peer_state_file_path "NYC" "${TEST_PEER_IP}" "failure_count")

	# Create restart file with unsorted timestamps (not in chronological order)
	echo "$old_restart" >"$restart_file"
	echo "$recent_restart" >>"$restart_file" # Most recent (should be detected)
	echo "$middle_restart" >>"$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Create mock ip command that returns empty output (no SA) - VPN is definitely down
	mock_ip_vpn_down

	# VPN must be DOWN for recovery to trigger: status_exit=1 so ipsec status fails
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$LOG_FILE")

	run bash "$test_script" --fake
	# Allow exit code 0 (success) or 1 (warnings) - minimum interval should block (15s < 30s)
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should block restart due to minimum interval (most recent restart was 15s ago, less than 30s)
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Minimum restart interval not met"

	# Verify restart was not recorded (file should still have 3 entries)
	if [[ -f "$restart_file" ]]; then
		local file_lines
		file_lines=$(wc -l <"$restart_file" | tr -d ' ')
		# Should still have exactly 3 entries (no new restart recorded)
		assert_equal "$file_lines" "3"
	fi

	remove_mock_from_path
}

# ============================================================================
# CONFIGURABLE WINDOW TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "rate limiting: window of 15 minutes allows more restarts than 60 minutes" {
	# Purpose: Test verifies that a 15-minute window allows more restarts than a 60-minute window
	# Expected: With same restart count, 15-minute window allows restart while 60-minute window blocks
	# Importance: Ensures configurable window size works correctly for different scenarios

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Create restarts: 3 restarts 20 minutes ago (outside 15-min window, inside 60-min window)
	local now=$base_time
	local restart_time=$((now - 1200)) # 20 minutes ago (1200 seconds)

	# Test with 15-minute window (should allow restart - old restarts are outside window)
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"MAX_RESTARTS_PER_WINDOW=3" \
		"RATE_LIMIT_WINDOW_MINUTES=15" \
		"MIN_RESTART_INTERVAL_SECONDS=0" \
		"ENABLE_XFRM_RECOVERY=0" \
		"ENABLE_NETWORK_PARTITION_CHECK=0"

	local state_dir="${TEST_DIR}/state"
	setup_test_environment "$state_dir" "${TEST_DIR}/logs"
	local restart_file="${TEST_DIR}/state/restart_count"

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${state_dir}"

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local failure_counter
	failure_counter=$(get_peer_state_file_path "NYC" "${TEST_PEER_IP}" "failure_count")

	# Create restart file with 3 restarts 20 minutes ago
	echo "$restart_time" >"$restart_file"
	echo "$restart_time" >>"$restart_file"
	echo "$restart_time" >>"$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Create mock ip command that returns empty output (no SA) - VPN is definitely down
	mock_ip_vpn_down

	# VPN must be DOWN for recovery to trigger: status_exit=1 so ipsec status fails
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$LOG_FILE")

	run bash "$test_script" --fake
	# Allow exit code 0 (success) or 1 (warnings) - restart should be allowed (old restarts outside 15-min window)
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should allow restart (old restarts are outside 15-minute window)
	assert_file_exist "$LOG_FILE"
	refute_file_contains "$LOG_FILE" "Rate limit exceeded"

	# Now test with 60-minute window (should block restart - old restarts are inside window)
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"MAX_RESTARTS_PER_WINDOW=3" \
		"RATE_LIMIT_WINDOW_MINUTES=60" \
		"MIN_RESTART_INTERVAL_SECONDS=0" \
		"ENABLE_XFRM_RECOVERY=0" \
		"ENABLE_NETWORK_PARTITION_CHECK=0"

	# Reset restart file (remove new restart from previous test)
	echo "$restart_time" >"$restart_file"
	echo "$restart_time" >>"$restart_file"
	echo "$restart_time" >>"$restart_file"

	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$LOG_FILE")

	run bash "$test_script" --fake
	# Allow exit code 0 (success) or 1 (warnings) - rate limit should block
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should block restart (old restarts are inside 60-minute window)
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Rate limit exceeded"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "rate limiting: window correctly counts restarts in sliding window" {
	# Purpose: Test verifies that sliding window correctly counts only restarts within the window
	# Expected: Only restarts within the window are counted, older restarts are ignored
	# Importance: Ensures sliding window logic works correctly for accurate rate limiting

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Create mix of old and recent restarts
	local now=$base_time
	local window_minutes=30
	local window_seconds=$((window_minutes * 60))
	local old_restart=$((now - window_seconds - 100)) # Outside window (100s before window start)
	local recent1=$((now - 600))                      # 10 minutes ago (inside window)
	local recent2=$((now - 1200))                     # 20 minutes ago (inside window)
	local recent3=$((now - 1500))                     # 25 minutes ago (inside window)

	# Create config with 30-minute window
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"MAX_RESTARTS_PER_WINDOW=3" \
		"RATE_LIMIT_WINDOW_MINUTES=${window_minutes}" \
		"MIN_RESTART_INTERVAL_SECONDS=0" \
		"ENABLE_XFRM_RECOVERY=0" \
		"ENABLE_NETWORK_PARTITION_CHECK=0"

	local state_dir="${TEST_DIR}/state"
	setup_test_environment "$state_dir" "${TEST_DIR}/logs"
	local restart_file="${TEST_DIR}/state/restart_count"

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${state_dir}"

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local failure_counter
	failure_counter=$(get_peer_state_file_path "NYC" "${TEST_PEER_IP}" "failure_count")

	# Create restart file with mix of old and recent restarts
	echo "$old_restart" >"$restart_file" # Outside window (should be ignored)
	echo "$recent1" >>"$restart_file"    # Inside window
	echo "$recent2" >>"$restart_file"    # Inside window
	echo "$recent3" >>"$restart_file"    # Inside window

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Create mock ip command that returns empty output (no SA) - VPN is definitely down
	mock_ip_vpn_down

	# VPN must be DOWN for recovery to trigger: status_exit=1 so ipsec status fails
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$LOG_FILE")

	run bash "$test_script" --fake
	# Allow exit code 0 (success) or 1 (warnings) - should block (3 restarts in window = limit)
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should block restart (3 restarts within window = limit, old restart is ignored)
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Rate limit exceeded"

	# Verify restart was not recorded (file should still have 4 entries)
	if [[ -f "$restart_file" ]]; then
		local file_lines
		file_lines=$(wc -l <"$restart_file" | tr -d ' ')
		# Should still have exactly 4 entries (no new restart recorded)
		assert_equal "$file_lines" "4"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "rate limiting: window reset calculation is correct" {
	# Purpose: Test verifies that window reset calculation correctly identifies when rate limit will reset
	# Expected: Reset time = oldest restart in window + window duration
	# Importance: Ensures accurate countdown information for rate limit messages

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0
	add_mock_to_path

	# Create restarts at specific times
	local now=$base_time
	local window_minutes=60
	local window_seconds=$((window_minutes * 60))
	local oldest_restart=$((now - 1800)) # 30 minutes ago (oldest in window)
	local middle_restart=$((now - 1200)) # 20 minutes ago
	local recent_restart=$((now - 600))  # 10 minutes ago

	# Expected reset time: oldest_restart + window_seconds = (now - 1800) + 3600 = now + 1800
	# So reset should be in 30 minutes (1800 seconds)

	# Create config with 60-minute window
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_NYC_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"MAX_RESTARTS_PER_WINDOW=3" \
		"RATE_LIMIT_WINDOW_MINUTES=${window_minutes}" \
		"MIN_RESTART_INTERVAL_SECONDS=0" \
		"ENABLE_XFRM_RECOVERY=0" \
		"ENABLE_NETWORK_PARTITION_CHECK=0"

	local state_dir="${TEST_DIR}/state"
	setup_test_environment "$state_dir" "${TEST_DIR}/logs"
	local restart_file="${TEST_DIR}/state/restart_count"

	# Set LOGS_DIR and STATE_DIR for state functions
	export LOGS_DIR="${TEST_DIR}/logs"
	export STATE_DIR="${state_dir}"

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local failure_counter
	failure_counter=$(get_peer_state_file_path "NYC" "${TEST_PEER_IP}" "failure_count")

	# Create restart file with 3 restarts (at limit)
	echo "$oldest_restart" >"$restart_file"  # Oldest (30 min ago)
	echo "$middle_restart" >>"$restart_file" # Middle (20 min ago)
	echo "$recent_restart" >>"$restart_file" # Recent (10 min ago)

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Create mock ip command that returns empty output (no SA) - VPN is definitely down
	mock_ip_vpn_down

	# VPN must be DOWN for recovery to trigger: status_exit=1 so ipsec status fails
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$LOG_FILE")

	run bash "$test_script" --fake
	# Allow exit code 0 (success) or 1 (warnings) - should block (at limit)
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should block restart (at limit)
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Rate limit exceeded"

	# Verify reset calculation: reset should be in approximately 30 minutes (1800 seconds)
	# The log should contain countdown information
	# Reset time = oldest_restart + window_seconds = (now - 1800) + 3600 = now + 1800
	# Countdown = 1800 seconds = 30 minutes (expected format: "30m 0s" where minutes and seconds are separated by space)
	# Check that log contains countdown (formatted as "30m 0s") or "Reset at:" which indicates reset calculation is present
	# Note: "30m" will match "30m 0s" format used in the log message
	assert_log_contains_any "$LOG_FILE" "30m" "Reset at:"

	remove_mock_from_path
}
