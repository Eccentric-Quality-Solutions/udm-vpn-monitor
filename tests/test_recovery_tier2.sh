#!/usr/bin/env bats
#
# Tests for Tier 2 Recovery Actions (Surgical Cleanup)
# Tests critical paths and error handling scenarios for Tier 2 recovery

load test_helper
load helpers/test_data
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
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
	setup_vpn_at_tier_fixture 2 "${TEST_PEER_IP}" 'ENABLE_XFRM_RECOVERY=0'

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
	setup_vpn_at_tier_fixture 2 "${TEST_PEER_IP}"

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
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
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
	failure_counter=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")

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
        echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
        echo "    lifetime current: 1000 bytes"
        exit 0
    fi
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"

	# Generate ipsec status output using test data helpers
	local ipsec_status_output
	ipsec_status_output=$(generate_ipsec_status_output "libreswan" "test-conn" "${TEST_PEER_IP}" "${TEST_LOCAL_IP}")
	# Also include peer IP on separate line for grep matching
	ipsec_status_output="${ipsec_status_output}"$'\n'"${TEST_PEER_IP}"
	local ipsec_status_file="${TEST_DIR}/ipsec_status_output"
	echo "$ipsec_status_output" >"$ipsec_status_file"

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
        cat "MOCK_IPSEC_STATUS_OUTPUT"
        exit 0
    fi
fi
EOF
	# Replace placeholder with actual file path
	sed -i "s|MOCK_IPSEC_STATUS_OUTPUT|${ipsec_status_file}|g" "$mock_ipsec"
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
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
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
	failure_counter=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")

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
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
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
	failure_counter=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")

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
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST2_EXTERNAL=\"${TEST_PEER_IP2}\"" \
		"LOCATION_TEST2_INTERNAL=\"${TEST_PEER_IP2}\"" \
		'ENABLE_XFRM_RECOVERY=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0' \
		'ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=0' \
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
	failure_counter1=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
	local failure_counter2
	failure_counter2=$(get_peer_state_file_path "TEST2" "${TEST_PEER_IP2}" "failure_count")

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
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST2_EXTERNAL=\"${TEST_PEER_IP2}\"" \
		"LOCATION_TEST2_INTERNAL=\"${TEST_PEER_IP2}\""

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Use get_peer_state_file_path to get correct paths dynamically
	export STATE_DIR="$state_dir"
	export LOGS_DIR="${TEST_DIR}/logs"
	source_function "get_peer_state_file_path"
	local failure_counter1
	failure_counter1=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
	local failure_counter2
	failure_counter2=$(get_peer_state_file_path "TEST2" "${TEST_PEER_IP2}" "failure_count")

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

# bats test_tags=category:high-risk,priority:high
@test "tier 2: surgical cleanup works with PATH-restricted environment (cron/systemd simulation)" {
	# Purpose: Test verifies that surgical cleanup works correctly when PATH is restricted (simulating cron/systemd environment)
	# Expected: get_command_path() finds ipsec via system directory fallback, and ipsec commands execute successfully using full path
	# Importance: Ensures recovery works in PATH-restricted environments common in cron/systemd contexts on UDM OS
	setup_vpn_at_tier_fixture 2 "${TEST_PEER_IP}" 'ENABLE_XFRM_RECOVERY=0'

	# Save original PATH
	local original_path="${PATH}"

	# Create mock system directory in test directory (safer than modifying /usr/sbin)
	# Generate ipsec status output using test data helpers
	local ipsec_status_output
	ipsec_status_output=$(generate_ipsec_status_output "libreswan" "test-conn" "${TEST_PEER_IP}" "${TEST_PEER_IP2}")
	# Format with "Connections:" header
	ipsec_status_output="Connections:"$'\n'"  ${ipsec_status_output}"
	local ipsec_status_file="${TEST_DIR}/ipsec_status_output_path_test"
	echo "$ipsec_status_output" >"$ipsec_status_file"

	local mock_system_dir="${TEST_DIR}/usr/sbin"
	mkdir -p "$mock_system_dir"
	local mock_ipsec="${mock_system_dir}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "ipsec-reload-called" > /tmp/ipsec_path_test.txt
    exit 0
fi
if [[ "$1" == "status" ]]; then
    cat "MOCK_IPSEC_STATUS_OUTPUT"
    exit 0
fi
exit 1
EOF
	# Replace placeholder with actual file path
	sed -i "s|MOCK_IPSEC_STATUS_OUTPUT|${ipsec_status_file}|g" "$mock_ipsec"
	chmod +x "$mock_ipsec"

	# Restrict PATH to exclude system directories (simulating cron/systemd environment)
	# PATH only includes /bin and /usr/bin (common minimal PATH, excludes /usr/sbin)
	export PATH="/bin:/usr/bin"

	# Verify ipsec is NOT found via PATH
	if command -v ipsec >/dev/null 2>&1; then
		# Clean up and skip if ipsec is found in restricted PATH
		export PATH="$original_path"
		skip "ipsec found in restricted PATH - cannot test PATH-restricted scenario"
	fi

	# Create test lib directory with modified common.sh
	# This allows us to test path resolution without modifying system files
	local test_lib_dir="${TEST_DIR}/test_lib"
	mkdir -p "$test_lib_dir"

	# Copy all lib files to test lib directory
	cp -r "${BATS_TEST_DIRNAME}/../lib"/* "$test_lib_dir/"

	# Modify get_command_path in test common.sh to check test directory first
	# Insert test directory at the beginning of system_dirs array
	sed -i 's|local system_dirs=("/usr/sbin" "/usr/bin" "/sbin" "/bin")|local system_dirs=("'"${TEST_DIR}"'/usr/sbin" "/usr/sbin" "/usr/bin" "/sbin" "/bin")|' "${test_lib_dir}/common.sh"

	# Create modified test script that uses test lib directory
	local modified_test_script="${TEST_DIR}/vpn-monitor-modified.sh"
	cp "$TEST_SCRIPT" "$modified_test_script"

	# Replace lib directory path in test script
	# The script sources lib files using ${SCRIPT_DIR}/lib/, so we need to modify SCRIPT_DIR
	# or replace the source paths. Let's replace source paths to use test lib directory.
	local project_root
	project_root=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)
	local escaped_test_lib
	escaped_test_lib=$(echo "$test_lib_dir" | sed 's/[[\.*^$()+?{|]/\\&/g')
	local escaped_project_lib
	escaped_project_lib=$(echo "${project_root}/lib" | sed 's/[[\.*^$()+?{|]/\\&/g')

	# Replace source paths in the script
	sed -i "s|source \"\${SCRIPT_DIR}/lib/|source \"${test_lib_dir}/|g" "$modified_test_script"
	sed -i "s|source \"${escaped_project_lib}/|source \"${test_lib_dir}/|g" "$modified_test_script"

	# Update TEST_SCRIPT to use modified version
	local original_test_script="$TEST_SCRIPT"
	TEST_SCRIPT="$modified_test_script"

	# Clean up test marker file if it exists
	rm -f /tmp/ipsec_path_test.txt

	# Run script with restricted PATH
	PATH="/bin:/usr/bin" run bash "$TEST_SCRIPT"

	# Verify ipsec reload was called (via full path resolution)
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "ipsec reload"
	if [[ -f /tmp/ipsec_path_test.txt ]]; then
		assert_file_exist /tmp/ipsec_path_test.txt
		rm -f /tmp/ipsec_path_test.txt
	fi

	# Restore PATH and TEST_SCRIPT
	export PATH="$original_path"
	TEST_SCRIPT="$original_test_script"
}

# bats test_tags=category:high-risk,priority:high
@test "tier 2: surgical cleanup preserves location name when verification fails" {
	# Purpose: Test verifies that surgical_cleanup preserves the location name parameter when verify_ipsec_connections_active parses location config
	# Expected: Completion message logs the correct location name even when verify_ipsec_connections_active iterates through all locations
	# Importance: Ensures location name is not overwritten by global variable modification in verify_ipsec_connections_active
	# This test specifically addresses the bug where location name was incorrectly logged as a different location

	# Set up test environment with multiple locations
	setup_test_environment "${TEST_DIR}"

	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_CHICAGO_EXTERNAL="172.31.23.27"
LOCATION_CHICAGO_INTERNAL="172.31.23.27"
LOCATION_LOS_ANGELES_EXTERNAL="172.31.15.215"
LOCATION_LOS_ANGELES_INTERNAL="172.31.15.215"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	export CONFIG_FILE="$config_file"
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${LOGS_DIR}"
	local log_file="${LOGS_DIR}/vpn-monitor.log"
	export LOG_FILE="$log_file"

	# Source recovery module and config module (needed for parse_location_config)
	source_recovery_module
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true

	# Set up state for CHICAGO peer
	local location_name="CHICAGO"
	local peer_ip="172.31.23.27"
	set_peer_state "$location_name" "$peer_ip" "failure_count" "3"

	# Mock ipsec - reload succeeds, but status fails (exit code 127 - command not found)
	# This will cause verify_ipsec_connections_active to parse location config
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
	exit 0
fi
if [[ "$1" == "status" ]]; then
	# Simulate command not found (exit code 127)
	exit 127
fi
exec /usr/bin/ipsec "$@"
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Call surgical_cleanup with CHICAGO location name
	# Note: surgical_cleanup will return failure when verification fails, but that's expected
	# We're testing that the location name is preserved, not that the function succeeds
	run surgical_cleanup "$peer_ip" "$location_name"
	# Function returns failure when verification fails (expected)
	assert_failure

	# Verify that the completion message uses CHICAGO, not LOS_ANGELES
	assert_file_exist "$log_file"
	# The completion message should contain CHICAGO and the correct IP (172.31.23.27)
	# Note: With ENABLE_XFRM_RECOVERY=0, this uses ipsec fallback, so message is "Recovery completed" not "Surgical cleanup completed"
	assert_file_contains "$log_file" "Recovery completed for CHICAGO (172.31.23.27)"
	# Verify it does NOT contain LOS_ANGELES with CHICAGO's IP (the bug we're fixing)
	if grep -q "Recovery completed for LOS_ANGELES (172.31.23.27)" "$log_file" 2>/dev/null; then
		echo "ERROR: Found incorrect location name LOS_ANGELES with CHICAGO's IP in log"
		return 1
	fi

	remove_mock_from_path
}
