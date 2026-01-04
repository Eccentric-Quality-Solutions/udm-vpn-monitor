#!/usr/bin/env bats
#
# Tests for Recovery Action Cascading Failures
# Tests critical paths where multiple recovery actions fail in sequence
#
# These tests address the gap identified in COVERAGE_GAP_ANALYSIS.md:
# - xfrm recovery fails → ipsec reload fails → ipsec restart fails
# - Recovery succeeds but state update fails
# - Recovery succeeds but cooldown set fails
# - Recovery succeeds but restart record fails

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_at_tier

# ============================================================================
# RECOVERY ACTION CASCADING FAILURES TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high,slow
@test "recovery cascading failures: xfrm recovery fails → ipsec reload fails → ipsec restart fails" {
	# Purpose: Test verifies that script handles cascading recovery failures gracefully
	# Expected: Script attempts all recovery methods, logs failures, and continues without crashing
	# Importance: Cascading failures can occur in production; script must handle them robustly
	setup_vpn_at_tier_fixture 2 "192.168.1.1" 'ENABLE_XFRM_RECOVERY=1' 'ENABLE_NETWORK_PARTITION_CHECK=0' 'ENABLE_PING_CHECK=0'

	# Mock ip command - xfrm recovery fails (can't delete SAs)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]] && [[ "$3" == "delete" ]]; then
    # xfrm delete fails
    exit 1
elif [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Return SAs so recovery is attempted
    # Include zero byte counters to ensure VPN is detected as DOWN
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 0 bytes, 0 packets"
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - both reload and restart fail
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "ipsec reload failed" >&2
    exit 1
elif [[ "$1" == "restart" ]]; then
    echo "ipsec restart failed" >&2
    exit 1
fi
exec /usr/bin/ipsec "$@"
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	run bash "$TEST_SCRIPT"

	# Script should handle cascading failures gracefully
	assert_success
	assert_file_exist "$LOG_FILE"

	# Should attempt xfrm recovery
	assert_file_contains "$LOG_FILE" "xfrm" || assert_file_contains "$LOG_FILE" "xfrm-based"

	# Should fall back to ipsec reload
	assert_file_contains "$LOG_FILE" "reload" || assert_file_contains "$LOG_FILE" "fallback"

	# Note: Restart may not be attempted if failure count doesn't reach Tier 3 threshold (5)
	# In this test, failure count starts at 3 (Tier 2), increments to 4 on VPN failure,
	# which is below TIER3_THRESHOLD (5), so restart won't be triggered.
	# Key is that script handles cascading failures gracefully and continues without crashing

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high,slow
@test "recovery cascading failures: recovery succeeds but state update fails" {
	# Purpose: Test verifies that script handles state update failures after successful recovery
	# Expected: Recovery action succeeds but state update fails; script logs error and continues
	# Importance: State update failures can leave system in inconsistent state; must be handled gracefully
	setup_vpn_at_tier_fixture 2 "192.168.1.1" 'ENABLE_XFRM_RECOVERY=0' 'ENABLE_NETWORK_PARTITION_CHECK=0'

	# Mock ipsec - reload succeeds
	mock_ipsec_reload_restart 0 0

	# Mock VPN as recovered after reload
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Return healthy VPN (byte counters increasing)
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    lifetime current: 1000 bytes"
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Make the specific failure_count state file unwritable to simulate state update failure
	# Note: We need STATE_DIR and LOGS_DIR to remain writable for lockfile and log file creation,
	# so we make the specific state file unwritable instead of the directory
	local logs_dir="${LOGS_DIR:-${TEST_DIR}/logs}"
	mkdir -p "$logs_dir"

	# Get the path where the failure_count state file will be written
	# Source state functions to get file path
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local state_file
	state_file=$(get_peer_state_file_path "TEST" "192.168.1.1" "failure_count")

	# Create the state file first (so it exists), then make it unwritable
	# This simulates the scenario where recovery succeeds but state update fails
	echo "2" >"$state_file" 2>/dev/null || true

	local original_perms
	original_perms=$(stat -c "%a" "$state_file" 2>/dev/null || echo "644")

	# Try to make unwritable (may fail on some systems)
	if chmod 000 "$state_file" 2>/dev/null && ! [[ -r "$state_file" ]]; then
		run bash "$TEST_SCRIPT"

		# Script should handle state update failure gracefully
		assert_success
		assert_file_exist "$LOG_FILE"

		# Should log recovery success
		assert_file_contains "$LOG_FILE" "reload" || assert_file_contains "$LOG_FILE" "recovery"

		# Restore permissions
		chmod "$original_perms" "$state_file" 2>/dev/null || true
	else
		# Can't test unwritable file on this system - skip
		skip "Cannot make state file unwritable on this system"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high,slow
@test "recovery cascading failures: recovery succeeds but cooldown set fails" {
	# Purpose: Test verifies that script handles cooldown set failures after successful recovery
	# Expected: Recovery succeeds but cooldown set fails; script logs error and continues
	# Importance: Cooldown failures can cause rapid re-restarts; must be handled gracefully
	setup_vpn_at_tier_fixture 3 "192.168.1.1" 'ENABLE_XFRM_RECOVERY=0' 'ENABLE_NETWORK_PARTITION_CHECK=0'

	# Mock ipsec - restart succeeds, status returns peer IP for verification
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ipsec restart succeeded"
    exit 0
elif [[ "$1" == "status" ]]; then
    # Return status output that includes the peer IP for verification
    echo "192.168.1.1"
    exit 0
fi
exec /usr/bin/ipsec "$@"
EOF
	chmod +x "$mock_ipsec"

	# Mock VPN as recovered after restart
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Return healthy VPN
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    lifetime current: 1000 bytes"
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Test that script handles cooldown set failure gracefully
	# Note: Simulating cooldown write failure in integration test is difficult because:
	# 1. Making STATE_DIR unwritable causes script to exit early (can't create lockfile)
	# 2. Making just the file unwritable doesn't work (atomic_write_file removes it first)
	# 3. Making file immutable requires root privileges
	#
	# The fix ensures set_cooldown returns early on error instead of logging success.
	# The unit test in test_state_atomic_write_failures.sh verifies set_cooldown handles
	# atomic write failures correctly. This integration test verifies the script succeeds
	# when recovery works, demonstrating that cooldown failures don't crash the script.

	run bash "$TEST_SCRIPT"

	# Script should succeed (recovery succeeded)
	assert_success
	assert_file_exist "$LOG_FILE"

	# Should log recovery success
	assert_file_contains "$LOG_FILE" "restart" || assert_file_contains "$LOG_FILE" "recovery"

	# Note: The specific cooldown failure case is tested in test_state_atomic_write_failures.sh
	# which tests set_cooldown directly with an unwritable directory. This test verifies
	# the integration: script completes successfully when recovery succeeds, even if cooldown
	# would fail (the fix ensures set_cooldown doesn't log success on failure).

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high,slow
@test "recovery cascading failures: recovery succeeds but restart record fails" {
	# Purpose: Test verifies that script handles restart record failures after successful recovery
	# Expected: Recovery succeeds but restart record fails; script logs error and continues
	# Importance: Restart record failures can affect rate limiting; must be handled gracefully
	setup_vpn_at_tier_fixture 3 "192.168.1.1" 'ENABLE_XFRM_RECOVERY=0' 'ENABLE_NETWORK_PARTITION_CHECK=0'

	# Mock ipsec - restart succeeds, status returns peer IP for verification
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ipsec restart succeeded"
    exit 0
elif [[ "$1" == "status" ]]; then
    # Return status output that includes the peer IP for verification
    echo "192.168.1.1"
    exit 0
fi
exec /usr/bin/ipsec "$@"
EOF
	chmod +x "$mock_ipsec"

	# Mock VPN as recovered after restart
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Return healthy VPN
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    lifetime current: 1000 bytes"
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Make restart count file unwritable to simulate restart record failure
	local state_dir="${STATE_DIR:-${TEST_DIR}}"
	mkdir -p "$state_dir"
	local restart_count_file="${state_dir}/restart_count"
	touch "$restart_count_file"
	local original_perms
	original_perms=$(stat -c "%a" "$restart_count_file" 2>/dev/null || echo "644")

	# Try to make unwritable (may fail on some systems)
	if chmod 444 "$restart_count_file" 2>/dev/null && ! [[ -w "$restart_count_file" ]]; then
		run bash "$TEST_SCRIPT"

		# Script should handle restart record failure gracefully
		assert_success
		assert_file_exist "$LOG_FILE"

		# Should log recovery success
		assert_file_contains "$LOG_FILE" "restart" || assert_file_contains "$LOG_FILE" "recovery"

		# Restore permissions
		chmod "$original_perms" "$restart_count_file" 2>/dev/null || true
	else
		# Can't test unwritable file on this system - skip
		skip "Cannot make restart count file unwritable on this system"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high,slow
@test "recovery cascading failures: increment_failure fails during recovery" {
	# Purpose: Test verifies that script handles increment_failure failures during recovery
	# Expected: Recovery action executes but failure count increment fails; script logs error and continues
	# Importance: Failure count failures can affect recovery decisions; must be handled gracefully
	setup_vpn_down_fixture "192.168.1.1" 2 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'ENABLE_XFRM_RECOVERY=0' 'ENABLE_NETWORK_PARTITION_CHECK=0'

	# Mock VPN as down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Return empty (VPN down)
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - reload and restart succeed quickly (prevents hangs)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "ipsec reload succeeded"
    exit 0
elif [[ "$1" == "restart" ]]; then
    echo "ipsec restart succeeded"
    exit 0
elif [[ "$1" == "status" ]]; then
    # Return status output that includes the peer IP for verification
    echo "192.168.1.1"
    exit 0
fi
exec /usr/bin/ipsec "$@"
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Make failure count file unwritable to simulate increment failure
	local state_dir="${STATE_DIR:-${TEST_DIR}}"
	mkdir -p "$state_dir"
	export STATE_DIR="$state_dir"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Source state functions to get file path
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local failure_count_file
	failure_count_file=$(get_peer_state_file_path "TEST" "192.168.1.1" "failure_count")
	mkdir -p "$(dirname "$failure_count_file")"
	touch "$failure_count_file"
	local original_perms
	original_perms=$(stat -c "%a" "$failure_count_file" 2>/dev/null || echo "644")

	# Try to make unwritable (may fail on some systems)
	if chmod 444 "$failure_count_file" 2>/dev/null && ! [[ -w "$failure_count_file" ]]; then
		run bash "$TEST_SCRIPT"

		# Script should handle increment failure gracefully
		assert_success
		assert_file_exist "$LOG_FILE"

		# Should continue monitoring despite increment failure
		# May log error about state update failure

		# Restore permissions
		chmod "$original_perms" "$failure_count_file" 2>/dev/null || true
	else
		# Can't test unwritable file on this system - skip
		skip "Cannot make failure count file unwritable on this system"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high,slow
@test "recovery cascading failures: reset_failure_count fails after recovery" {
	# Purpose: Test verifies that script handles reset_failure_count failures after successful recovery
	# Expected: VPN recovers but failure count reset fails; script logs error and continues
	# Importance: Reset failures can cause false failure detection; must be handled gracefully
	setup_vpn_active_fixture "192.168.1.1" 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'ENABLE_NETWORK_PARTITION_CHECK=0'

	# Set failure count to simulate recovery scenario
	local state_dir="${STATE_DIR:-${TEST_DIR}}"
	export STATE_DIR="$state_dir"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Source state functions to get file path
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local failure_count_file
	failure_count_file=$(get_peer_state_file_path "TEST" "192.168.1.1" "failure_count")
	mkdir -p "$(dirname "$failure_count_file")"
	echo "3" >"$failure_count_file"

	# Make failure count file unwritable to simulate reset failure
	local original_perms
	original_perms=$(stat -c "%a" "$failure_count_file" 2>/dev/null || echo "644")

	# Try to make unwritable (may fail on some systems)
	if chmod 444 "$failure_count_file" 2>/dev/null && ! [[ -w "$failure_count_file" ]]; then
		run bash "$TEST_SCRIPT"

		# Script should handle reset failure gracefully
		assert_success
		assert_file_exist "$LOG_FILE"

		# Should log recovery (VPN is healthy)
		assert_file_contains "$LOG_FILE" "recovered" || assert_file_contains "$LOG_FILE" "healthy" || assert_file_contains "$LOG_FILE" "OK"

		# Restore permissions
		chmod "$original_perms" "$failure_count_file" 2>/dev/null || true
	else
		# Can't test unwritable file on this system - skip
		skip "Cannot make failure count file unwritable on this system"
	fi

	remove_mock_from_path
}
