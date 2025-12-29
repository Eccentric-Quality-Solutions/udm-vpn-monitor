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
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing

# ============================================================================
# RECOVERY DURING NETWORK PARTITION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "recovery network partition: VPN fails but network is partitioned - recovery should be skipped" {
	# Test verifies that when VPN fails but network is partitioned, recovery actions are skipped.
	# Expected: Network partition check runs first, recovery is skipped with appropriate log message.
	# Importance: Recovery actions during network partition are wasteful and could cause issues.
	# Use fixture to set up VPN down scenario first (creates state files and basic setup)
	setup_vpn_down_fixture "192.168.1.1" 3 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'ENABLE_NETWORK_PARTITION_CHECK=1' 'ENABLE_XFRM_RECOVERY=0'

	# Set network partition state (after fixture sets up STATE_DIR)
	local partition_state_file="${STATE_DIR}/network_partition_state"
	echo "1" >"$partition_state_file"

	# Mock network partition check - network is partitioned
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "route" ]] && [[ "$2" == "show" ]] && [[ "$3" == "default" ]]; then
    # No default route - network partitioned
    exit 1
elif [[ "$1" == "link" ]] && [[ "$2" == "show" ]]; then
    # Interfaces may be up but no route
    echo "1: $3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500"
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"

	# Mock dig - DNS fails
	mock_dig "0"
	add_mock_to_path

	run bash "$TEST_SCRIPT"

	# Script should handle network partition gracefully
	assert_success
	# Should skip recovery due to network partition
	assert_file_exist "$LOG_FILE"
	# Should log that recovery is skipped
	assert_file_contains "$LOG_FILE" "Skipping VPN recovery" || assert_file_contains "$LOG_FILE" "network is partitioned" || assert_file_contains "$LOG_FILE" "network partitioned"
	# Should NOT attempt recovery actions
	assert_file_not_contains "$LOG_FILE" "Tier 2" || assert_file_not_contains "$LOG_FILE" "surgical cleanup" || assert_file_not_contains "$LOG_FILE" "reload"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery network partition: network partition detected during recovery action - should abort gracefully" {
	# Test verifies that when network partition is detected during recovery action,
	# recovery should abort gracefully.
	# Expected: Recovery action detects partition mid-execution and aborts with appropriate logging.
	# Importance: Continuing recovery during partition is wasteful and could cause issues.
	# Use fixture to set up VPN down scenario first (creates state files and basic setup)
	setup_vpn_down_fixture "192.168.1.1" 3 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'ENABLE_NETWORK_PARTITION_CHECK=1' 'ENABLE_XFRM_RECOVERY=0'

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
        echo "default via 192.168.1.1 dev eth0"
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
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "ipsec reload should not be called during partition"
    exit 1
fi
exec /usr/bin/ipsec "$@"
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	run bash "$TEST_SCRIPT"

	# Script should handle partition detection gracefully
	assert_success
	# Should detect partition and skip recovery
	assert_file_exist "$LOG_FILE"
	# Should log that recovery is skipped due to partition
	assert_file_contains "$LOG_FILE" "Skipping VPN recovery" || assert_file_contains "$LOG_FILE" "network is partitioned" || assert_file_contains "$LOG_FILE" "network partitioned"
	# Should NOT attempt recovery actions
	assert_file_not_contains "$LOG_FILE" "ipsec reload should not be called"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery network partition: network partition clears during recovery - should continue recovery" {
	# Test verifies that when network partition clears during recovery, recovery should continue.
	# Expected: Recovery detects partition cleared and continues with recovery actions.
	# Importance: Network recovery shouldn't prevent VPN recovery once network is healthy.
	# Use fixture to set up VPN down scenario first (creates state files and basic setup)
	setup_vpn_down_fixture "192.168.1.1" 3 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'ENABLE_NETWORK_PARTITION_CHECK=1' 'ENABLE_XFRM_RECOVERY=0'

	# Set network partition state initially (after fixture sets up STATE_DIR)
	local partition_state_file="${STATE_DIR}/network_partition_state"
	echo "1" >"$partition_state_file"

	# Mock network partition check - starts partitioned, clears during recovery
	# Use a file to track state across calls
	local partition_check_state_file="${TEST_DIR}/partition_check_state"
	echo "0" >"$partition_check_state_file"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "route" ]] && [[ "\$2" == "show" ]] && [[ "\$3" == "default" ]]; then
    # First check fails (partitioned), subsequent checks succeed (cleared)
    partition_check_count=\$(cat "$partition_check_state_file" 2>/dev/null || echo "0")
    partition_check_count=\$((partition_check_count + 1))
    echo "\$partition_check_count" >"$partition_check_state_file"
    if [[ \$partition_check_count -eq 1 ]]; then
        exit 1  # Partitioned
    else
        echo "default via 192.168.1.1 dev eth0"
        exit 0  # Cleared
    fi
elif [[ "\$1" == "link" ]] && [[ "\$2" == "show" ]]; then
    echo "1: \$3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500"
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"

	# Mock dig - starts partitioned, clears during recovery
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
    exit 1  # DNS fails (partitioned)
else
    echo "8.8.8.8"
    exit 0  # DNS succeeds (cleared)
fi
EOF
	chmod +x "$mock_dig"

	# Mock ipsec - reload should be called once partition clears
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "ipsec reload called after partition cleared"
    exit 0
fi
exec /usr/bin/ipsec "$@"
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	run bash "$TEST_SCRIPT"

	# Script should handle partition clearing and recovery continuation gracefully
	assert_success
	# Should detect partition cleared and continue recovery
	assert_file_exist "$LOG_FILE"
	# Should log that network connectivity restored
	assert_file_contains "$LOG_FILE" "Network connectivity restored" || assert_file_contains "$LOG_FILE" "resuming VPN monitoring"
	# Should attempt recovery actions after partition clears
	assert_file_contains "$LOG_FILE" "Tier 2" || assert_file_contains "$LOG_FILE" "surgical cleanup" || assert_file_contains "$LOG_FILE" "reload"

	remove_mock_from_path
}
