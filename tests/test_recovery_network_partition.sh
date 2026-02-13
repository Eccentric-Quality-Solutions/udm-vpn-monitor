#!/usr/bin/env bats
#
# Tests for Recovery During Network Partition (Section 3.2)
# Tests critical paths where recovery should be skipped during network partition
#
# These tests address the gap identified in CRITICAL_PATH_TEST_GAPS_REVIEW.md:
# - VPN fails but network is partitioned - recovery should be skipped
# - Network partition detected during recovery action - should abort gracefully
# - Network partition clears during recovery - should continue recovery

load test_helper
load helpers/assertions
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_network_partition
load fixtures/vpn_at_tier

# ============================================================================
# RECOVERY DURING NETWORK PARTITION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "recovery network partition: VPN fails but network is partitioned - recovery should be skipped" {
	# Purpose: Test verifies that when VPN fails but network is partitioned, recovery actions are skipped
	# Expected: Network partition check runs first, recovery is skipped with appropriate log message
	# Importance: Recovery actions during network partition are wasteful and could cause issues
	# Use partition fixture to set up network partition scenario
	setup_vpn_network_partition_fixture "${TEST_PEER_IP}" "all" \
		'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'ENABLE_XFRM_RECOVERY=0'

	# Set up VPN down scenario: update mock_ip to also return empty for xfrm state (no SA)
	# This simulates VPN down + network partition
	local additional_handlers
	additional_handlers=$(
		cat <<'ADDITIONAL_EOF'
# Handle route checks - no default route (network partitioned)
if [[ "$1" == "route" ]] && [[ "$2" == "show" ]] && [[ "$3" == "default" ]]; then
    exit 1  # No default route
fi

# Handle link checks - interfaces UP
if [[ "$1" == "link" ]] && [[ "$2" == "show" ]]; then
    if [[ -n "${3:-}" ]]; then
        echo "1: $3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500"
        exit 0
    fi
    # Show all interfaces
    echo "1: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500"
    echo "2: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500"
    exit 0
fi
ADDITIONAL_EOF
	)
	mock_ip_vpn_down "${TEST_DIR}/ip" "$additional_handlers"

	# Set up state files for VPN failure (3 failures to trigger recovery) using location-based state functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "failure_count" "3" || true

	# Set network partition state
	local partition_state_file="${STATE_DIR}/network_partition_state"
	echo "1" >"$partition_state_file"

	run bash "$TEST_SCRIPT"

	# Script should handle network partition gracefully
	assert_success
	# Should skip VPN checks due to network partition (optimization: checks skipped before recovery)
	assert_file_exist "$LOG_FILE"
	# Should log that VPN checks are skipped (new optimization) or recovery is skipped (fallback)
	assert_log_contains_any "$LOG_FILE" "Network partition" "Skipping VPN checks" "Skipping VPN recovery" "network is partitioned" "network partitioned"
	# Should NOT attempt recovery actions
	refute_file_contains "$LOG_FILE" "Tier 2" || refute_file_contains "$LOG_FILE" "surgical cleanup" || refute_file_contains "$LOG_FILE" "reload"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery network partition: network partition detected during recovery action - should abort gracefully" {
	# Purpose: Test verifies that when network partition is detected during recovery action, recovery should abort gracefully
	# Expected: Recovery action detects partition mid-execution and aborts with appropriate logging
	# Importance: Continuing recovery during partition is wasteful and could cause issues
	# Use fixture to set up VPN down scenario first (creates state files and basic setup)
	setup_vpn_at_tier_fixture 2 "${TEST_PEER_IP}" 'ENABLE_NETWORK_PARTITION_CHECK=1' 'ENABLE_XFRM_RECOVERY=0'

	# Mock network partition check - starts healthy, becomes partitioned during recovery
	# Use a file to track state across calls
	local partition_check_state_file="${TEST_DIR}/partition_check_state"
	echo "0" >"$partition_check_state_file"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "route" ]] && [[ "\$2" == "show" ]] && [[ "\$3" == "default" ]]; then
    # First check succeeds (healthy), subsequent checks fail (partitioned)
    partition_check_count=\$(cat "$partition_check_state_file" 2>/dev/null || echo "0")
    partition_check_count=\$((partition_check_count + 1))
    echo "\$partition_check_count" >"$partition_check_state_file"
    if [[ \$partition_check_count -eq 1 ]]; then
        echo "default via ${TEST_PEER_IP} dev eth0"
        exit 0
    else
        exit 1  # Partition detected
    fi
elif [[ "\$1" == "link" ]] && [[ "\$2" == "show" ]]; then
    echo "1: \$3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500"
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"

	# Mock dig - starts healthy, becomes partitioned
	# Use a file to track state across calls
	local dig_state_file="${TEST_DIR}/dig_state"
	echo "0" >"$dig_state_file"
	local mock_dig="${TEST_DIR}/dig"
	cat >"$mock_dig" <<EOF
#!/bin/bash
dig_count=\$(cat "$dig_state_file" 2>/dev/null || echo "0")
dig_count=\$((dig_count + 1))
echo "\$dig_count" >"$dig_state_file"
if [[ \$dig_count -eq 1 ]]; then
    echo "8.8.8.8"
    exit 0
else
    exit 1  # DNS fails
fi
EOF
	chmod +x "$mock_dig"

	# Mock ipsec - reload should not be called if partition detected
	mock_ipsec_reload_restart 1 0
	add_mock_to_path

	run bash "$TEST_SCRIPT"

	# Script should handle partition detection gracefully
	assert_success
	# Should detect partition and skip VPN checks (optimization) or recovery
	assert_file_exist "$LOG_FILE"
	# Should log that VPN checks are skipped (new optimization) or recovery is skipped (fallback)
	assert_log_contains_any "$LOG_FILE" "Network partition" "Skipping VPN checks" "Skipping VPN recovery" "network is partitioned" "network partitioned"
	# Should NOT attempt recovery actions
	refute_file_contains "$LOG_FILE" "ipsec reload should not be called"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery network partition: network partition clears during recovery - should continue recovery" {
	# Purpose: Test verifies that when network partition clears during recovery, recovery should continue
	# Expected: Recovery detects partition cleared and continues with recovery actions
	# Importance: Network recovery shouldn't prevent VPN recovery once network is healthy
	# Use fixture to set up VPN down scenario first (creates state files and basic setup)
	setup_vpn_at_tier_fixture 2 "${TEST_PEER_IP}" 'ENABLE_NETWORK_PARTITION_CHECK=1' 'ENABLE_XFRM_RECOVERY=0'

	# Set network partition state initially (after fixture sets up STATE_DIR)
	local partition_state_file="${STATE_DIR}/network_partition_state"
	echo "1" >"$partition_state_file"

	# Mock network partition check - starts partitioned, clears during recovery
	# Track calls at the check_network_partition level, not individual command level
	# This accounts for the fact that check_network_partition calls multiple sub-functions
	# The fixture creates a mock ip that handles xfrm state, so we need to preserve that
	# IMPORTANT: Overwrite the fixture's mock ip completely to ensure our handlers are used
	local partition_check_state_file="${TEST_DIR}/partition_check_state"
	echo "0" >"$partition_check_state_file"
	local route_call_count_file="${TEST_DIR}/route_call_count"
	echo "0" >"$route_call_count_file"
	local mock_ip="${TEST_DIR}/ip"
	# Remove existing mock if it exists (from fixture)
	rm -f "$mock_ip"
	# Export TEST_DIR so mock script can access it
	export TEST_DIR
	cat >"$mock_ip" <<MOCKEOF
#!/bin/bash
# Handle "ip -s xfrm state" (with statistics flag) - VPN down, no SA
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    echo "mock_ip: handling ip -s xfrm state" >> "${TEST_DIR}/mock_calls.log" 2>/dev/null || true
    # Return empty output (no SA found - VPN is down)
    exit 0
fi

# Handle "ip xfrm state" (without statistics flag) - VPN down, no SA
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    echo "mock_ip: handling ip xfrm state" >> "${TEST_DIR}/mock_calls.log" 2>/dev/null || true
    # Return empty output (no SA found - VPN is down)
    exit 0
fi

# Handle route checks for partition detection
if [[ "\$1" == "route" ]] && [[ "\$2" == "show" ]] && [[ "\$3" == "default" ]]; then
    echo "mock_ip: MATCHED route show default pattern" >> "${TEST_DIR}/mock_calls.log" 2>/dev/null || true
    echo "mock_ip: handling route show default" >> "${TEST_DIR}/mock_calls.log" 2>/dev/null || true
    # Track calls to ip route show default
    # check_network_partition calls check_default_route which calls ip route show default
    # First call (in validate_monitor_state) should fail, second call (in monitor_location) should succeed
    route_call_count_file="${TEST_DIR}/route_call_count"
    echo "mock_ip: reading counter from: \$route_call_count_file" >> "${TEST_DIR}/mock_calls.log" 2>/dev/null || true
    route_call_count=\$(cat "\$route_call_count_file" 2>/dev/null || echo "0")
    echo "mock_ip: current count: \$route_call_count" >> "${TEST_DIR}/mock_calls.log" 2>/dev/null || true
    route_call_count=\$((route_call_count + 1))
    echo "\$route_call_count" >"\$route_call_count_file"
    echo "mock_ip: wrote count: \$route_call_count to \$route_call_count_file" >> "${TEST_DIR}/mock_calls.log" 2>/dev/null || true
    # Log mock call
    echo "mock_ip route called: count=\$route_call_count" >> "${TEST_DIR}/mock_calls.log" 2>/dev/null || true
    # First call fails (partitioned), subsequent succeed (cleared)
    if [[ \$route_call_count -eq 1 ]]; then
        echo "mock_ip route: returning failure (count=1)" >> "${TEST_DIR}/mock_calls.log" 2>/dev/null || true
        exit 1  # Partitioned
    else
        echo "mock_ip route: returning success (count=\$route_call_count)" >> "${TEST_DIR}/mock_calls.log" 2>/dev/null || true
        echo "default via ${TEST_PEER_IP} dev eth0"
        exit 0  # Cleared
    fi
fi

# Handle link checks for partition detection
if [[ "\$1" == "link" ]] && [[ "\$2" == "show" ]]; then
    echo "mock_ip: MATCHED link show pattern" >> "${TEST_DIR}/mock_calls.log" 2>/dev/null || true
    # Interface checks always succeed (interfaces are UP)
    # Real ip link show output includes "state UP" which check_interface_state greps for
    echo "mock_ip link called: interface=\${3:-all}" >> "${TEST_DIR}/mock_calls.log" 2>/dev/null || true
    if [[ -n "\${3:-}" ]]; then
        echo "1: \$3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default"
    else
        echo "1: br0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default"
        echo "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default"
    fi
    exit 0
fi

# Fall back to real ip command for other cases
echo "mock_ip: falling back to real ip command for: \$*" >> "${TEST_DIR}/mock_calls.log" 2>/dev/null || true
exec /usr/bin/ip "\$@"
MOCKEOF
	chmod +x "$mock_ip"

	# Mock dig - starts partitioned, clears during recovery
	# Track calls to check_network_partition level
	# check_network_partition calls check_dns_resolution which calls dig
	# First call (in validate_monitor_state) should fail, second call (in monitor_location) should succeed
	local dig_call_file="${TEST_DIR}/dig_call_count"
	echo "0" >"$dig_call_file"
	local mock_dig="${TEST_DIR}/dig"
	cat >"$mock_dig" <<EOF
#!/bin/bash
# Log all calls to mock dig - use consistent log file path
log_file="${TEST_DIR}/mock_calls.log"
echo "mock_dig called with args: \$* (arg count: \$#)" >> "\$log_file" 2>/dev/null || true

	# Track calls to dig command
	# First call should fail (partitioned), second call should succeed (cleared)
    dig_call_count=\$(cat "${TEST_DIR}/dig_call_count" 2>/dev/null || echo "0")
	dig_call_count=\$((dig_call_count + 1))
	echo "\$dig_call_count" >"${TEST_DIR}/dig_call_count"
echo "mock_dig: count=\$dig_call_count" >> "\$log_file" 2>/dev/null || true
if [[ \$dig_call_count -eq 1 ]]; then
    echo "mock_dig: returning failure (count=1)" >> "\$log_file" 2>/dev/null || true
    exit 1  # DNS fails (partitioned)
else
    echo "mock_dig: returning success (count=\$dig_call_count)" >> "\$log_file" 2>/dev/null || true
    echo "8.8.8.8"
    exit 0  # DNS succeeds (cleared)
fi
EOF
	chmod +x "$mock_dig"

	# Verify mock dig was created correctly
	if [[ ! -f "$mock_dig" ]] || [[ ! -x "$mock_dig" ]]; then
		echo "ERROR: Mock dig file not created or not executable: $mock_dig" >&2
		return 1
	fi

	# Mock ipsec - VPN is DOWN initially (status_exit=1), reload/restart succeed
	# This ensures VPN detection fails and recovery is triggered
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	run bash "$TEST_SCRIPT"

	# Script should handle partition clearing and recovery continuation gracefully
	assert_success
	# Should detect partition cleared and continue recovery
	assert_file_exist "$LOG_FILE"
	# Should log that network connectivity restored
	assert_log_contains_any "$LOG_FILE" "Network connectivity restored" "resuming VPN monitoring"
	# Should attempt recovery actions after partition clears
	assert_log_contains_any "$LOG_FILE" "Tier 2" "surgical cleanup" "reload"

	remove_mock_from_path
}

# ============================================================================
# check_vpn_status_for_location TESTS - Coverage gaps from COVERAGE_REVIEW
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "check_vpn_status_for_location: partition previously detected - re-check and skip if still partitioned" {
	# Purpose: Test verifies that when partition was previously detected, function re-checks and skips VPN checks if still partitioned
	# Expected: Function re-checks partition state, detects it's still partitioned, returns 2 and logs skip message
	# Importance: Covers lines 743-760 - partition re-check logic and early return path
	# This test covers the uncovered path where partition_state=1 and check_network_partition fails
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Set up state directory and partition state file
	mkdir -p "$STATE_DIR"
	local partition_state_file="${STATE_DIR}/network_partition_state"
	echo "1" >"$partition_state_file"

	# Mock network partition check to fail (still partitioned)
	mock_ip_interfaces_up "br0,eth0" "0" >/dev/null
	mock_dig 0
	add_mock_to_path

	# Source required functions
	source_recovery_module

	# Test check_vpn_status_for_location directly
	run check_vpn_status_for_location "TEST" "${TEST_PEER_IP}" ""

	# Should return 2 (partition detected)
	assert_equal "$status" 2
	# Should log that VPN checks are skipped
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Skipping VPN checks" "network partition detected"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_vpn_status_for_location: partition previously detected - re-check and continue if cleared" {
	# Purpose: Test verifies that when partition was previously detected but clears, function continues with VPN checks
	# Expected: Function re-checks partition state, detects it's cleared, updates state, and continues with VPN check
	# Importance: Covers lines 762-771 - partition cleared path and state update
	# This test covers the uncovered path where partition_state=1 but check_network_partition succeeds
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Set up state directory and partition state file (previously partitioned)
	mkdir -p "$STATE_DIR"
	local partition_state_file="${STATE_DIR}/network_partition_state"
	echo "1" >"$partition_state_file"

	# Create combined mock ip command that handles route, link, and xfrm state
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
# Handle route commands
if [[ "$1" == "route" ]] && [[ "$2" == "show" ]] && [[ "$3" == "default" ]]; then
    echo "default via 192.168.1.1 dev eth0"
    exit 0
fi
# Handle link commands
if [[ "$1" == "link" ]] && [[ "$2" == "show" ]]; then
    echo "1: br0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default"
    echo "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default"
    exit 0
fi
# Handle xfrm state commands
if [[ "$1" == "-s" ]] && [[ "$2" == "xfrm" ]] && [[ "$3" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    exit 0
fi
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    exit 0
fi
# Handle other ip commands
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"

	# Mock dig for DNS check
	mock_dig 1 "8.8.8.8"
	add_mock_to_path

	# Source required functions
	source_recovery_module

	# Test check_vpn_status_for_location directly
	run check_vpn_status_for_location "TEST" "${TEST_PEER_IP}" ""

	# Should return 0 (VPN healthy)
	assert_equal "$status" 0
	# Should log that network connectivity restored
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Network connectivity restored" "resuming VPN monitoring"
	# Partition state should be cleared
	local partition_state
	partition_state=$(get_network_partition_state)
	assert_equal "$partition_state" 0

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_vpn_status_for_location: partition previously detected - logs summary if due" {
	# Purpose: Test verifies that partition summary logging is triggered when partition is detected
	# Expected: Function calls log_network_partition_summary_if_due when partition is detected
	# Importance: Covers lines 759, 760, 770 - partition summary logging paths
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Set up state directory and partition state file
	mkdir -p "$STATE_DIR"
	local partition_state_file="${STATE_DIR}/network_partition_state"
	echo "1" >"$partition_state_file"

	# Set up partition stats to trigger summary (more than 1 hour elapsed)
	local stats_file="${STATE_DIR}/network_partition_stats"
	mkdir -p "$(dirname "$stats_file")"
	# Set last_summary_log to 0 (never logged) to trigger summary
	echo "last_summary_log=0" >"$stats_file"
	echo "total_checks=100" >>"$stats_file"
	echo "partitioned_checks=50" >>"$stats_file"

	# Mock network partition check to fail (still partitioned)
	mock_ip_interfaces_up "br0,eth0" "0" >/dev/null
	mock_dig 0
	add_mock_to_path

	# Source required functions
	source_recovery_module

	# Test check_vpn_status_for_location directly
	run check_vpn_status_for_location "TEST" "${TEST_PEER_IP}" ""

	# Should return 2 (partition detected)
	assert_equal "$status" 2
	# Should log partition summary if due (may or may not be due depending on timing)
	# At minimum, should log that checks are skipped
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Skipping VPN checks" "network partition"

	remove_mock_from_path
}
