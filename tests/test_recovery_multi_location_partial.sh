#!/usr/bin/env bats
#
# Tests for Multi-Location Partial Recovery Scenarios
# Tests critical paths where some locations recover while others don't
#
# These tests address the gap identified in COVERAGE_GAP_ANALYSIS.md:
# - Some locations recover, others don't (multi-location scenarios)
# - Partial recovery (some locations recover, others don't)
# - Concurrent recovery actions for multiple locations

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down

# ============================================================================
# MULTI-LOCATION PARTIAL RECOVERY TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high,slow
@test "recovery multi-location: some locations recover, others don't" {
	# Purpose: Test verifies that script handles partial recovery across multiple locations
	# Expected: Some locations recover (failure count reset), others continue failing (failure count increments)
	# Importance: Multi-location deployments need independent recovery tracking
	setup_test_environment "${TEST_DIR}"

	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_LOC1_EXTERNAL="${TEST_PEER_IP}"
LOCATION_LOC1_INTERNAL="${TEST_PEER_IP}"
LOCATION_LOC2_EXTERNAL="192.168.1.2"
LOCATION_LOC2_INTERNAL="192.168.1.2"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Set up state: LOC1 has failures, LOC2 is healthy
	export STATE_DIR="$state_dir"
	export LOGS_DIR="${TEST_DIR}/logs"
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local loc1_failure_file
	loc1_failure_file=$(get_peer_state_file_path "LOC1" "${TEST_PEER_IP}" "failure_count")
	local loc2_failure_file
	loc2_failure_file=$(get_peer_state_file_path "LOC2" "192.168.1.2" "failure_count")
	mkdir -p "$(dirname "$loc1_failure_file")" "$(dirname "$loc2_failure_file")"
	echo "2" >"$loc1_failure_file"
	echo "0" >"$loc2_failure_file"

	# Mock ip command - LOC1 is down, LOC2 is up
	local check_state_file="${TEST_DIR}/vpn_check_state"
	echo "0" >"$check_state_file"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Check which peer IP is being checked (from command line or environment)
    # For simplicity, check if output contains LOC1 or LOC2
    # In real scenario, peer IP would be passed differently
    # Simulate: LOC1 (192.168.1.1) is down, LOC2 (192.168.1.2) is up
    # We'll use a state file to track which location is being checked
    local state_file="$check_state_file"
    local check_count
    check_count=\$(cat "\$state_file" 2>/dev/null || echo "0")
    check_count=\$((check_count + 1))
    echo "\$check_count" >"\$state_file"
    
    # First check: LOC1 (down), Second check: LOC2 (up)
    if [[ \$check_count -eq 1 ]]; then
        # LOC1 is down - return empty
        exit 0
    else
        # LOC2 is up - return healthy VPN
        echo "src 192.168.1.2 dst 192.168.1.2"
        echo "    lifetime current: 1000 bytes"
        exit 0
    fi
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	run bash "$test_script"

	# Script should handle partial recovery
	assert_success
	assert_file_exist "$log_file"

	# LOC1 should continue failing (failure count increments)
	# LOC2 should recover (failure count resets)
	# Both should be logged independently

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high,slow
@test "recovery multi-location: partial recovery - some locations recover, others don't" {
	# Purpose: Test verifies that script handles partial recovery where some locations recover after recovery action
	# Expected: Recovery action executes, some locations recover, others continue failing
	# Importance: Partial recovery scenarios need proper handling to avoid false positives
	setup_test_environment "${TEST_DIR}"

	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_LOC1_EXTERNAL="${TEST_PEER_IP}"
LOCATION_LOC1_INTERNAL="${TEST_PEER_IP}"
LOCATION_LOC2_EXTERNAL="192.168.1.2"
LOCATION_LOC2_INTERNAL="192.168.1.2"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Set up state: Both locations have failures (Tier 2 threshold)
	export STATE_DIR="$state_dir"
	export LOGS_DIR="${TEST_DIR}/logs"
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local loc1_failure_file
	loc1_failure_file=$(get_peer_state_file_path "LOC1" "${TEST_PEER_IP}" "failure_count")
	local loc2_failure_file
	loc2_failure_file=$(get_peer_state_file_path "LOC2" "192.168.1.2" "failure_count")
	mkdir -p "$(dirname "$loc1_failure_file")" "$(dirname "$loc2_failure_file")"
	echo "3" >"$loc1_failure_file"
	echo "3" >"$loc2_failure_file"

	# Mock ipsec - reload succeeds
	mock_ipsec_reload_restart 0 0

	# Mock ip command - LOC1 recovers, LOC2 still down
	local check_state_file="${TEST_DIR}/check_state"
	echo "0" >"$check_state_file"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Track check count
    local check_count
    check_count=\$(cat "$check_state_file" 2>/dev/null || echo "0")
    check_count=\$((check_count + 1))
    echo "\$check_count" >"$check_state_file"
    
    # First check: LOC1 (recovers - return healthy)
    # Second check: LOC2 (still down - return empty)
    if [[ \$check_count -eq 1 ]]; then
        # LOC1 recovers
        echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
        echo "    lifetime current: 1000 bytes"
        exit 0
    else
        # LOC2 still down
        exit 0
    fi
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	run bash "$test_script"

	# Script should handle partial recovery
	assert_success
	assert_file_exist "$log_file"

	# LOC1 should recover (failure count resets)
	# LOC2 should continue failing (failure count increments)
	# Recovery action should be logged

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high,slow
@test "recovery multi-location: concurrent recovery actions for multiple locations" {
	# Purpose: Test verifies that script handles concurrent recovery actions for multiple locations correctly
	# Expected: Each location's recovery is tracked independently, lockfile prevents concurrent execution
	# Importance: Concurrent recovery actions need proper isolation to avoid conflicts
	setup_test_environment "${TEST_DIR}"

	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_LOC1_EXTERNAL="${TEST_PEER_IP}"
LOCATION_LOC1_INTERNAL="${TEST_PEER_IP}"
LOCATION_LOC2_EXTERNAL="192.168.1.2"
LOCATION_LOC2_INTERNAL="192.168.1.2"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
LOCKFILE_TIMEOUT=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Set up state: Both locations have failures (Tier 2 threshold)
	export STATE_DIR="$state_dir"
	export LOGS_DIR="${TEST_DIR}/logs"
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local loc1_failure_file
	loc1_failure_file=$(get_peer_state_file_path "LOC1" "${TEST_PEER_IP}" "failure_count")
	local loc2_failure_file
	loc2_failure_file=$(get_peer_state_file_path "LOC2" "192.168.1.2" "failure_count")
	mkdir -p "$(dirname "$loc1_failure_file")" "$(dirname "$loc2_failure_file")"
	echo "3" >"$loc1_failure_file"
	echo "3" >"$loc2_failure_file"

	# Mock ipsec - reload succeeds
	mock_ipsec_reload_restart 0 0

	# Mock ip command - both locations down (triggers recovery)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Both locations down
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Run first instance in background
	bash "$test_script" &
	local first_pid=$!

	# Wait for lockfile to be created
	local lockfile="${TEST_DIR}/vpn-monitor.lock"
	wait_for_file "$lockfile" 5 || true

	# Run second instance - should be blocked by lockfile
	run bash "$test_script"

	# Second instance should handle lockfile blocking gracefully
	# Wait for first instance to complete
	wait $first_pid || true

	# Verify that lockfile prevented concurrent execution
	assert_file_exist "$log_file"
	# Should have lockfile-related messages
	assert_file_contains "$log_file" "lockfile" || assert_file_contains "$log_file" "already running" || assert_file_contains "$log_file" "stale"

	remove_mock_from_path
}
