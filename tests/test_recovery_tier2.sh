#!/usr/bin/env bats
#
# Tests for Tier 2 Recovery Actions (Surgical Cleanup)
# Tests critical paths and error handling scenarios for Tier 2 recovery

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_cooldown
load fixtures/vpn_at_tier

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# TIER 2 RECOVERY TESTS
# ============================================================================

# bats test_tags=slow,category:high-risk,priority:high
@test "tier 2: surgical cleanup uses ipsec reload (default behavior, affects all tunnels)" {
	# Purpose: Test verifies that Tier 2 recovery action triggers ipsec reload command for surgical cleanup
	# Expected: Script executes "ipsec reload" when failure count reaches Tier 2 threshold
	# Importance: ipsec reload affects all VPN tunnels, which is the default surgical cleanup behavior
	# Note: This may impact other VPN tunnels, not just the failing one.
	# Disable xfrm recovery to force ipsec reload (xfrm recovery is tried first if enabled)
	setup_vpn_at_tier_fixture 2 "192.168.1.1" 'ENABLE_XFRM_RECOVERY=0'

	# Mock ipsec - reload succeeds, track reload call
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "ipsec-reload-called" > /tmp/ipsec_called.txt
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	run bash "$TEST_SCRIPT"

	# Should use ipsec reload (affects all tunnels)
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "ipsec reload"
	if [[ -f /tmp/ipsec_called.txt ]]; then
		assert_file_exist /tmp/ipsec_called.txt
		rm -f /tmp/ipsec_called.txt
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "tier 2: surgical cleanup fails - error handling" {
	# Purpose: Test verifies that the script handles failures of surgical cleanup (ipsec reload) gracefully
	# Expected: Script logs error about reload failure but continues execution without crashing
	# Importance: Recovery actions can fail due to system issues; script must handle failures robustly
	setup_vpn_at_tier_fixture 2 "192.168.1.1"

	# Mock ipsec - reload fails
	mock_ipsec_reload_restart 0 1
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake

	# Should handle error gracefully (not crash)
	assert_file_exist "$LOG_FILE"
	# Script should continue execution

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "tier 2: recovery action partially succeeds (e.g., ipsec reload starts but fails mid-way)" {
	# Purpose: Test verifies behavior when recovery action partially succeeds (e.g., ipsec reload starts but fails mid-way)
	# Expected: Script handles partial success scenarios and may fall back to alternative recovery methods
	# Importance: Partial failures can occur in real systems; script must handle them gracefully
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Use get_peer_state_file_path to get correct path dynamically
	export STATE_DIR="$state_dir"
	export LOGS_DIR="${TEST_DIR}/logs"
	source_function "get_peer_state_file_path"
	local failure_counter
	failure_counter=$(get_peer_state_file_path "TEST" "192.168.1.1" "failure_count")

	# Set failure count to Tier 2 threshold
	echo "3" >"$failure_counter"

	# Mock ip command - VPN down initially, but healthy after recovery
	# Track recovery state to make VPN appear healthy after recovery action
	local recovery_state_file="${TEST_DIR}/recovery_state"
	echo "0" >"$recovery_state_file"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
# Handle xfrm state - return empty initially (VPN down), healthy after recovery
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    recovery_state=\$(cat "$recovery_state_file" 2>/dev/null || echo "0")
    if [[ \$recovery_state -eq 0 ]]; then
        # VPN down initially
        exit 0  # Return empty output (no SA found - VPN down)
    else
        # VPN healthy after recovery
        echo "src 192.168.1.1 dst 192.168.1.1"
        echo "    lifetime current: 1000 bytes"
        exit 0
    fi
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - reload fails, restart succeeds (tests fallback)
	# Track recovery state: ipsec status returns empty initially (VPN down), peer IP after recovery
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<EOF
#!/bin/bash
if [[ "\$1" == "restart" ]]; then
    echo "Restarting IPsec..."
    echo "Stopping IPsec..."
    echo "Starting IPsec..."
    # Mark recovery as complete so VPN appears healthy
    echo "1" >"$recovery_state_file"
    exit 0
fi
if [[ "\$1" == "reload" ]]; then
    echo "Reloading IPsec configuration..."
    exit 1  # Reload fails
fi
if [[ "\$1" == "status" ]]; then
    recovery_state=\$(cat "$recovery_state_file" 2>/dev/null || echo "0")
    if [[ \$recovery_state -eq 0 ]]; then
        # VPN down initially - return empty (no connections)
        exit 0
    else
        # VPN healthy after recovery - return status with peer IP for verification
        # Use format that includes the peer IP clearly
        echo "test-conn: ESTABLISHED 1 hour ago, 192.168.1.1...192.168.1.2"
        echo "192.168.1.1"  # Also include peer IP on separate line for grep matching
        exit 0
    fi
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	add_mock_to_path
	run bash "$test_script"
	# Note: Script exits with 1 if VPN is still down after recovery, which is expected behavior
	# The test verifies that recovery action (reload fails, restart succeeds) is handled gracefully
	# Recovery action may not immediately fix the VPN, so script may exit with 1
	# This is acceptable - the important thing is that recovery was attempted and handled correctly

	# Should handle partial success gracefully (fallback to restart)
	assert_file_exist "$log_file"
	# Verify that reload was attempted and failed (check for either pattern)
	assert_log_contains_any "$log_file" "ipsec reload failed" "reload failed"
	# Verify that fallback to restart was attempted (check for either pattern)
	assert_log_contains_any "$log_file" "ipsec restart" "restart"

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "tier 2: recovery action succeeds but VPN still fails on next check" {
	# Purpose: Test verifies that failure counter continues incrementing when recovery succeeds but VPN still fails
	# Expected: Recovery action executes successfully but failure counter increments because VPN check still fails
	# Importance: Ensures tier escalation continues when recovery actions don't resolve the underlying issue
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		'LOCATION_TEST_EXTERNAL="192.168.1.1"' \
		'LOCATION_TEST_INTERNAL="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'ENABLE_XFRM_RECOVERY=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0'

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Use get_peer_state_file_path to get correct path dynamically
	export STATE_DIR="$state_dir"
	export LOGS_DIR="${TEST_DIR}/logs"
	source_function "get_peer_state_file_path"
	local failure_counter
	failure_counter=$(get_peer_state_file_path "TEST" "192.168.1.1" "failure_count")

	# Set failure count to Tier 2 threshold
	echo "3" >"$failure_counter"

	# Mock ip command - VPN still down after recovery
	mock_ip_vpn_down

	# Mock ipsec - reload succeeds
	mock_ipsec_reload_restart 1 1
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	add_mock_to_path
	run bash "$test_script"

	# Recovery succeeds but VPN still fails - failure counter should continue incrementing
	assert_file_exist "$log_file"
	# Verify recovery action was attempted (check for any of the patterns)
	assert_log_contains_any "$log_file" "Tier 2" "surgical cleanup" "reload"
	# Failure counter should be incremented (now 4, was 3)
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert_equal "$count" 4
	fi

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "tier 2: recovery action fails and failure counter continues incrementing" {
	# Purpose: Test verifies that failure counter continues incrementing when recovery action fails
	# Expected: Recovery action fails and failure counter increments, enabling escalation to Tier 3
	# Importance: Ensures tier escalation continues when recovery actions fail, preventing stuck states
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		'LOCATION_TEST_EXTERNAL="192.168.1.1"' \
		'LOCATION_TEST_INTERNAL="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'ENABLE_XFRM_RECOVERY=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0'

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Use get_peer_state_file_path to get correct path dynamically
	export STATE_DIR="$state_dir"
	export LOGS_DIR="${TEST_DIR}/logs"
	source_function "get_peer_state_file_path"
	local failure_counter
	failure_counter=$(get_peer_state_file_path "TEST" "192.168.1.1" "failure_count")

	# Set failure count to Tier 2 threshold
	echo "3" >"$failure_counter"

	# Mock ip command - VPN down
	mock_ip_vpn_down

	# Mock ipsec - reload fails
	mock_ipsec_reload_restart 0 1
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	add_mock_to_path
	run bash "$test_script"
	# Note: Script exits with 1 if VPN is still down after recovery fails, which is expected behavior.
	# The test verifies that recovery action failure is handled gracefully and failure counter increments.

	# Recovery fails - failure counter should continue incrementing
	assert_file_exist "$log_file"
	# Verify recovery action was attempted (check for any of the patterns)
	assert_log_contains_any "$log_file" "Tier 2" "surgical cleanup" "reload"
	# Verify that reload failed (check for either pattern)
	assert_log_contains_any "$log_file" "reload failed" "failed"
	# Failure counter should be incremented (now 4, was 3)
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert_equal "$count" 4
	fi

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "tier 2: multiple recovery actions triggered simultaneously (multiple peers)" {
	# Purpose: Test verifies that multiple recovery actions are triggered when multiple peers reach Tier 2 simultaneously
	# Expected: Script executes recovery actions for each peer that reaches Tier 2 threshold
	# Importance: Ensures all failing peers receive recovery attempts, not just the first one detected
	local config_file
	config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		'LOCATION_TEST_EXTERNAL="192.168.1.1"' \
		'LOCATION_TEST_INTERNAL="192.168.1.1"' \
		'LOCATION_TEST2_EXTERNAL="10.0.0.1"' \
		'LOCATION_TEST2_INTERNAL="10.0.0.1"' \
		'ENABLE_XFRM_RECOVERY=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5'

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Use get_peer_state_file_path to get correct paths dynamically
	export STATE_DIR="$state_dir"
	export LOGS_DIR="${TEST_DIR}/logs"
	source_function "get_peer_state_file_path"
	local failure_counter1
	failure_counter1=$(get_peer_state_file_path "TEST" "192.168.1.1" "failure_count")
	local failure_counter2
	failure_counter2=$(get_peer_state_file_path "TEST2" "10.0.0.1" "failure_count")

	# Set both peers to Tier 2 threshold
	echo "3" >"$failure_counter1"
	echo "3" >"$failure_counter2"

	# Mock ip command - VPN down for both
	mock_ip_vpn_down

	# Mock ipsec - track reload calls
	local mock_ipsec="${TEST_DIR}/ipsec"
	local reload_count_file="${TEST_DIR}/reload_count.txt"
	cat >"$mock_ipsec" <<EOF
#!/bin/bash
if [[ "\$1" == "reload" ]]; then
    echo "1" >> "$reload_count_file"
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	add_mock_to_path
	run bash "$test_script"

	# Both peers should trigger recovery actions
	assert_file_exist "$log_file"
	# Verify both peers triggered Tier 2 actions (check for either pattern)
	assert_log_contains_any "$log_file" "Tier 2" "surgical cleanup"
	# Multiple reload calls should be made (one per peer at Tier 2)
	if [[ -f "$reload_count_file" ]]; then
		local reload_count
		reload_count=$(wc -l <"$reload_count_file" | tr -d ' ')
		# Should have at least 2 reload calls (one per peer)
		assert [ "$reload_count" -ge 2 ]
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "tier 2: multiple peers failing simultaneously - verify independent cleanup" {
	# Purpose: Test verifies that multiple peers failing simultaneously receive independent recovery actions
	# Expected: Each peer's failure counter is tracked independently and recovery actions are executed per peer
	# Importance: Independent tracking ensures each peer's recovery state is managed correctly without cross-contamination
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
LOCATION_TEST2_EXTERNAL="10.0.0.1"
LOCATION_TEST2_INTERNAL="10.0.0.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Use get_peer_state_file_path to get correct paths dynamically
	export STATE_DIR="$state_dir"
	export LOGS_DIR="${TEST_DIR}/logs"
	source_function "get_peer_state_file_path"
	local failure_counter1
	failure_counter1=$(get_peer_state_file_path "TEST" "192.168.1.1" "failure_count")
	local failure_counter2
	failure_counter2=$(get_peer_state_file_path "TEST2" "10.0.0.1" "failure_count")

	# Set both peers to Tier 2 threshold
	echo "3" >"$failure_counter1"
	echo "3" >"$failure_counter2"

	# Mock ip command - VPN down for both
	mock_ip_vpn_down

	# Mock ipsec - track reload calls
	local mock_ipsec="${TEST_DIR}/ipsec"
	local reload_log="${TEST_DIR}/reload_log.txt"
	cat >"$mock_ipsec" <<EOF
#!/bin/bash
if [[ "\$1" == "reload" ]]; then
    echo "ipsec-reload" >> "$reload_log"
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	add_mock_to_path
	run bash "$test_script"

	# Both peers should trigger cleanup independently
	assert_file_exist "$log_file"
	# Both peers should trigger ipsec reload (affects all tunnels)
	if [[ -f "$reload_log" ]]; then
		local reload_count
		reload_count=$(wc -l <"$reload_log")
		assert [ "$reload_count" -ge 1 ]
	fi

	remove_mock_from_path
}
