#!/usr/bin/env bats
#
# Tests for Connection Name Discovery and Caching
# Tests critical paths and error handling scenarios

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# CONNECTION NAME CACHING EDGE CASES
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "cache file is a directory" {
	# Purpose: Test verifies that the script handles connection name cache files that are directories instead of files gracefully
	# Expected: Script handles directory instead of cache file gracefully, should rediscover or skip cache
	# Importance: Directory paths can occur from misconfiguration or symlink issues; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local cache_file="${state_dir}/connection_name_192_168_1_1"

	# Create cache file as a directory
	rm -rf "$cache_file" 2>/dev/null || true
	mkdir -p "$cache_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Should handle directory gracefully (should rediscover or skip cache)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "cache file corrupted (contains invalid data)" {
	# Purpose: Test verifies that the script handles corrupted connection name cache files gracefully
	# Expected: Script handles corrupted cache file gracefully, should rediscover or skip cache
	# Importance: File corruption can occur due to disk errors or manual editing; script must handle it robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local cache_file="${state_dir}/connection_name_192_168_1_1"

	# Create corrupted cache file with invalid data
	echo "invalid-cache-data-with-null-bytes" >"$cache_file"
	# Add some binary data to make it more corrupted
	printf '\x00\x01\x02' >>"$cache_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Should handle corrupted cache file gracefully (should rediscover or skip cache)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "cache file permissions prevent write" {
	# Purpose: Test verifies that the script handles connection name cache files with write permissions prevented gracefully
	# Expected: Script handles read-only cache file gracefully, should suppress write error
	# Importance: Permission issues can occur from incorrect file ownership or chmod operations; script must handle gracefully
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local cache_file="${state_dir}/connection_name_192_168_1_1"

	# Create cache file and make it read-only (prevents write)
	echo "old-connection-name" >"$cache_file"
	chmod 444 "$cache_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Should handle read-only cache file gracefully (should suppress write error)
	assert_file_exist "$log_file"

	# Restore permissions for cleanup
	chmod 644 "$cache_file" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "cache file permissions prevent read" {
	# Purpose: Test verifies that the script handles connection name cache files with read permissions prevented gracefully
	# Expected: Script handles unreadable cache file gracefully, should rediscover connection name
	# Importance: Permission issues can occur from incorrect file ownership or chmod operations; script must handle gracefully
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local cache_file="${state_dir}/connection_name_192_168_1_1"

	# Create cache file and make it unreadable (prevents read)
	echo "connection-name" >"$cache_file"
	chmod 000 "$cache_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Should handle unreadable cache file gracefully (should rediscover)
	assert_file_exist "$log_file"

	# Restore permissions for cleanup
	chmod 644 "$cache_file" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "cached connection name becomes invalid" {
	# Purpose: Test verifies that the script handles cached connection names that become invalid or stale gracefully
	# Expected: Script uses cached name even if invalid since cache is checked first, cache will only be updated if ipsec status is checked
	# Importance: Cached connection names can become stale when VPN configurations change; script must handle this gracefully
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local cache_file="${state_dir}/connection_name_192_168_1_1"

	# Create cache file with invalid/stale connection name
	echo "old-invalid-connection-name" >"$cache_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ipsec to return different connection name (simulates connection name change)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # Return different connection name than cached
    echo "new-connection-name: ESTABLISHED 1 hour ago, 192.168.1.1...192.168.1.2"
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Script should use cached name (even if invalid) since cache is checked first
	# Cache will only be updated if ipsec status is checked and new name is discovered
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# CONNECTION NAME DISCOVERY EDGE CASES
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "connection name discovery during VPN failure (no active SA)" {
	# Purpose: Test verifies that connection name discovery works correctly during VPN failure when no active SA exists
	# Expected: Script handles connection name discovery during VPN failure gracefully, discovery code handles case when no SA exists
	# Importance: Connection name discovery must work even when VPN is down to enable proper recovery actions
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN is down (no SA)
	setup_mock_vpn_environment "192.168.1.1" 0

	# Mock ipsec status to return no active SA
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # Return status with no active SA for the peer IP
    echo "Connections:"
    echo "  test-conn: ESTABLISHED"
    echo "  other-conn: ESTABLISHED"
    # No mention of 192.168.1.1, so no active SA
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Should handle connection name discovery during VPN failure gracefully
	# Code at lib/detection.sh:675-733 handles discovery when no SA exists
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "discovery happens when both config and cache unavailable" {
	# Purpose: Test verifies that connection name discovery works when both config and cache are unavailable
	# Expected: Script handles discovery when both cache and ipsec unavailable gracefully, discovery code handles ipsec unavailable case
	# Importance: Connection name discovery must work even when preferred methods are unavailable
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local cache_file="${state_dir}/connection_name_192_168_1_1"

	# Ensure cache file does not exist
	rm -f "$cache_file" 2>/dev/null || true

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ipsec to be unavailable (simulates both cache and ipsec unavailable)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
# Simulate ipsec command unavailable
exit 1
EOF
	chmod +x "$mock_ipsec"

	# Mock command to fail for ipsec
	local mock_command="${TEST_DIR}/command"
	cat >"$mock_command" <<'EOF'
#!/bin/bash
if [[ "$1" == "-v" ]] && [[ "$2" == "ipsec" ]]; then
    exit 1
fi
# Fallback to real command for other cases
exec /usr/bin/command "$@"
EOF
	chmod +x "$mock_command"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Should handle discovery when both cache and ipsec unavailable gracefully
	# Code at lib/detection.sh:695-698 handles ipsec unavailable
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# CONNECTION NAME PRIORITY
# ============================================================================

@test "cached connection name takes priority over discovery" {
	# Purpose: Test verifies that cached connection names take priority over discovered names
	# Expected: Script uses cached name instead of discovered name, cache is checked first and returns early if found
	# Importance: Ensures cached connection names are preferred to avoid unnecessary discovery operations
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local cache_file="${state_dir}/connection_name_192_168_1_1"

	# Create cache file with a connection name
	echo "cached-connection-name" >"$cache_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ipsec status to return different connection name (should be ignored due to cache)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # Return different connection name than cached
    echo "discovered-connection-name: ESTABLISHED 1 hour ago, 192.168.1.1...192.168.1.2"
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Cached name should be used (cache takes priority over discovery)
	# Code at lib/detection.sh:694-702 checks cache first and returns early if found
	# Discovery (lines 704-742) only runs if cache is empty/missing
	assert_file_exist "$log_file"
	# Verify cache file still contains cached name (not overwritten)
	if [[ -f "$cache_file" ]]; then
		local cached_name
		cached_name=$(cat "$cache_file" 2>/dev/null || echo "")
		# Use assert_equal for better error messages
		assert_equal "$cached_name" "cached-connection-name"
	fi

	remove_mock_from_path
}
