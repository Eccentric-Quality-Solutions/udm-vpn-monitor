#!/usr/bin/env bats
#
# Tests for Network Partition Detection Functions
# Tests critical paths and error handling scenarios

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_network_partition

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# 2.1 NETWORK PARTITION DETECTION FUNCTIONS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "check_default_route - Default route exists" {
	# Purpose: Test verifies that check_default_route correctly detects when default route exists
	# Expected: Function returns 0 when default route is present
	# Importance: Default route check is critical for network partition detection
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Mock ip command - default route exists
	mock_ip_route "1" "default via ${TEST_PEER_IP} dev eth0"
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
@test "check_default_route - Default route missing" {
	# Purpose: Test verifies that check_default_route correctly detects when default route is missing
	# Expected: Function returns 1 when default route is not found
	# Importance: Missing default route indicates network partition
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

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
@test "check_dns_resolution - DNS resolution succeeds" {
	# Purpose: Test verifies that check_dns_resolution correctly detects successful DNS resolution
	# Expected: Function returns 0 when DNS resolution succeeds
	# Importance: DNS resolution check is critical for network partition detection
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

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
@test "check_dns_resolution - DNS resolution fails (timeout)" {
	# Purpose: Test verifies that check_dns_resolution correctly detects DNS resolution timeout
	# Expected: Function returns 1 when DNS resolution times out
	# Importance: DNS timeout indicates network partition
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

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
@test "check_dns_resolution - DNS server unreachable" {
	# Purpose: Test verifies that check_dns_resolution correctly detects unreachable DNS server
	# Expected: Function returns 1 when DNS server is unreachable
	# Importance: Unreachable DNS server indicates network partition
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Mock dig command - DNS server unreachable
	mock_dig 0
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
@test "check_interface_state - All interfaces UP" {
	# Purpose: Test verifies that check_interface_state correctly detects when all interfaces are UP
	# Expected: Function returns 0 when all checked interfaces are UP
	# Importance: Interface state check is critical for network partition detection
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

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
@test "check_interface_state - One interface DOWN" {
	# Purpose: Test verifies that check_interface_state correctly detects when one interface is DOWN
	# Expected: Function returns 1 when one or more interfaces are DOWN
	# Importance: Down interfaces indicate network partition
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Mock ip command - one interface DOWN
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "link" ]] && [[ "$2" == "show" ]]; then
    if [[ "$3" == "br0" ]]; then
        echo "1: br0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500"
        exit 0
    elif [[ "$3" == "eth0" ]]; then
        echo "2: eth0: <BROADCAST,MULTICAST> mtu 1500"
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
@test "check_interface_state - Interface doesn't exist" {
	# Purpose: Test verifies that check_interface_state correctly handles non-existent interfaces
	# Expected: Function returns 1 when interface doesn't exist
	# Importance: Non-existent interfaces indicate network partition or misconfiguration
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

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
@test "check_network_partition - All checks pass (network healthy)" {
	# Purpose: Test verifies that check_network_partition correctly identifies healthy network
	# Expected: Function returns 0 when all checks pass
	# Importance: Network partition detection prevents false VPN failure detection
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Mock ip command - default route exists, interfaces UP
	mock_ip_interfaces_up "br0,eth0" "1" >/dev/null

	# Mock dig command - DNS resolution succeeds
	mock_dig 1 "8.8.8.8"
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
@test "check_network_partition - One check fails (network partitioned)" {
	# Purpose: Test verifies that check_network_partition correctly identifies network partition
	# Expected: Function returns 1 when one or more checks fail
	# Importance: Network partition detection prevents false VPN failure detection
	setup_vpn_network_partition_fixture "${TEST_PEER_IP}" "no_default_route" "br0,eth0"

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
@test "check_network_partition - Custom DNS server/hostname/interfaces" {
	# Purpose: Test verifies that check_network_partition correctly uses custom parameters
	# Expected: Function uses custom DNS server, hostname, and interfaces
	# Importance: Custom parameters allow flexible network partition detection
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'

	# Mock ip command - interfaces UP
	mock_ip_interfaces_up "eth1,eth2" "1" >/dev/null

	# Mock dig command - DNS resolution succeeds
	mock_dig 1 "1.1.1.1"
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
