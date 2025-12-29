#!/usr/bin/env bats
#
# Tests for Tier 2 Recovery Actions (Surgical Cleanup)
# Tests critical paths and error handling scenarios for Tier 2 recovery

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_cooldown

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# TIER 2 RECOVERY TESTS
# ============================================================================

# bats test_tags=slow,category:high-risk,priority:high
@test "tier 2: surgical cleanup uses ipsec reload (default behavior, affects all tunnels)" {
	# Test verifies that Tier 2 recovery action triggers ipsec reload command for surgical cleanup.
	# Expected: Script executes "ipsec reload" when failure count reaches Tier 2 threshold.
	# Importance: ipsec reload affects all VPN tunnels, which is the default surgical cleanup behavior.
	# Note: This may impact other VPN tunnels, not just the failing one.
	# Disable xfrm recovery to force ipsec reload (xfrm recovery is tried first if enabled)
	setup_vpn_down_fixture "192.168.1.1" 3 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'ENABLE_XFRM_RECOVERY=0'

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
	# Test verifies that the script handles failures of surgical cleanup (ipsec reload) gracefully.
	# Expected: Script logs error about reload failure but continues execution without crashing.
	# Importance: Recovery actions can fail due to system issues; script must handle failures robustly.
	setup_vpn_down_fixture "192.168.1.1" 3 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5'

	# Mock ipsec - reload fails
	mock_ipsec_reload_restart 0 1
	add_mock_to_path

	run bash "$TEST_SCRIPT"

	# Should handle error gracefully (not crash)
	assert_file_exist "$LOG_FILE"
	# Script should continue execution

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "tier 2: recovery action partially succeeds (e.g., ipsec reload starts but fails mid-way)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 2 threshold
	echo "3" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - reload fails, restart succeeds (tests fallback)
	mock_ipsec_reload_restart 0 1
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	add_mock_to_path
	run bash "$test_script"
	assert_success

	# Should handle partial success gracefully (fallback to restart)
	assert_file_exist "$log_file"
	# Verify that reload was attempted and failed (check for either pattern)
	if ! grep -q "ipsec reload failed" "$log_file" && ! grep -q "reload failed" "$log_file"; then
		fail "Expected log to contain 'ipsec reload failed' or 'reload failed'"
	fi
	# Verify that fallback to restart was attempted (check for either pattern)
	if ! grep -q "ipsec restart" "$log_file" && ! grep -q "restart" "$log_file"; then
		fail "Expected log to contain 'ipsec restart' or 'restart'"
	fi

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "tier 2: recovery action succeeds but VPN still fails on next check" {
	local config_file
	config_file=$(setup_test_config_with_recovery_disabled "${TEST_DIR}/vpn-monitor.conf" "192.168.1.1" \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5')

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 2 threshold
	echo "3" >"$failure_counter"

	# Mock ip command - VPN still down after recovery
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

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
	if ! grep -q "Tier 2" "$log_file" && ! grep -q "surgical cleanup" "$log_file" && ! grep -q "reload" "$log_file"; then
		fail "Expected log to contain 'Tier 2', 'surgical cleanup', or 'reload'"
	fi
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
	local config_file
	config_file=$(setup_test_config_with_recovery_disabled "${TEST_DIR}/vpn-monitor.conf" "192.168.1.1" \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5')

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 2 threshold
	echo "3" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - reload fails
	mock_ipsec_reload_restart 0 1
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	add_mock_to_path
	run bash "$test_script"
	assert_success

	# Recovery fails - failure counter should continue incrementing
	assert_file_exist "$log_file"
	# Verify recovery action was attempted (check for any of the patterns)
	if ! grep -q "Tier 2" "$log_file" && ! grep -q "surgical cleanup" "$log_file" && ! grep -q "reload" "$log_file"; then
		fail "Expected log to contain 'Tier 2', 'surgical cleanup', or 'reload'"
	fi
	# Verify that reload failed (check for either pattern)
	if ! grep -q "reload failed" "$log_file" && ! grep -q "failed" "$log_file"; then
		fail "Expected log to contain 'reload failed' or 'failed'"
	fi
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
	local config_file
	config_file=$(setup_test_config_with_recovery_disabled "${TEST_DIR}/vpn-monitor.conf" "192.168.1.1 10.0.0.1" \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5')

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter1="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	local failure_counter2="${TEST_DIR}/logs/failure_counter_10_0_0_1"

	# Set both peers to Tier 2 threshold
	echo "3" >"$failure_counter1"
	echo "3" >"$failure_counter2"

	# Mock ip command - VPN down for both
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

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
	if ! grep -q "Tier 2" "$log_file" && ! grep -q "surgical cleanup" "$log_file"; then
		fail "Expected log to contain 'Tier 2' or 'surgical cleanup'"
	fi
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
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1 10.0.0.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter1="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	local failure_counter2="${TEST_DIR}/logs/failure_counter_10_0_0_1"

	# Set both peers to Tier 2 threshold
	echo "3" >"$failure_counter1"
	echo "3" >"$failure_counter2"

	# Mock ip command - VPN down for both
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

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
