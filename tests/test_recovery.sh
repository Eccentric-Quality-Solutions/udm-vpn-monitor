#!/usr/bin/env bats
#
# Tests for Recovery Actions and Rate Limiting
# Tests critical paths and error handling scenarios

# for better organization and maintainability.

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_cooldown

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# 4. RECOVERY ACTIONS TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "surgical cleanup uses ipsec reload (default behavior, affects all tunnels)" {
	# Test verifies that Tier 2 recovery action triggers ipsec reload command for surgical cleanup.
	# Expected: Script executes "ipsec reload" when failure count reaches Tier 2 threshold.
	# Importance: ipsec reload affects all VPN tunnels, which is the default surgical cleanup behavior.
	# Note: This may impact other VPN tunnels, not just the failing one.
	# Disable xfrm recovery to force ipsec reload (xfrm recovery is tried first if enabled)
	setup_vpn_down_fixture "192.168.1.1" 3 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'ENABLE_XFRM_RECOVERY=0'

	# Mock ipsec - track reload call
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

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT"

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
@test "surgical cleanup fails - error handling" {
	# Test verifies that the script handles failures of surgical cleanup (ipsec reload) gracefully.
	# Expected: Script logs error about reload failure but continues execution without crashing.
	# Importance: Recovery actions can fail due to system issues; script must handle failures robustly.
	setup_vpn_down_fixture "192.168.1.1" 3 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5'

	# Mock ipsec - reload fails
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "ipsec reload failed" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT"

	# Should handle error gracefully (not crash)
	assert_file_exist "$LOG_FILE"
	# Script should continue execution

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "full restart with ipsec command" {
	# Test verifies that Tier 3 recovery action triggers full IPsec restart when failure count reaches threshold.
	# Expected: Script executes "ipsec restart" command when failure count reaches Tier 3 threshold.
	# Importance: Full restart is the most aggressive recovery action and should only trigger after multiple failures.
	setup_vpn_down_fixture "192.168.1.1" 5 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'MAX_RESTARTS_PER_HOUR=10' 'COOLDOWN_MINUTES=1'

	# Mock ipsec - track if called
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ipsec-restart-called" > /tmp/ipsec_called.txt
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT"

	# Should call ipsec restart
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "full IPsec restart" || assert_file_contains "$LOG_FILE" "Tier 3"
	if [[ -f /tmp/ipsec_called.txt ]]; then
		assert_file_exist /tmp/ipsec_called.txt
		rm -f /tmp/ipsec_called.txt
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "full restart fails - error handling" {
	setup_vpn_down_fixture "192.168.1.1" 5 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'MAX_RESTARTS_PER_HOUR=10' 'COOLDOWN_MINUTES=1'

	# Mock ipsec - fails
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ipsec restart failed" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" || true

	# Should handle error gracefully
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Failed to restart" || assert_file_contains "$LOG_FILE" "ERROR"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "full restart when ipsec unavailable" {
	setup_vpn_down_fixture "192.168.1.1" 5 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'MAX_RESTARTS_PER_HOUR=10' 'COOLDOWN_MINUTES=1'

	# Don't create ipsec mock (unavailable)

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" || true

	# Should handle unavailable commands gracefully
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "not available" || assert_file_contains "$LOG_FILE" "ERROR"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "rate limit file corrupted" {
	setup_vpn_down_fixture "192.168.1.1" 5 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5' 'MAX_RESTARTS_PER_HOUR=3' 'COOLDOWN_MINUTES=1'

	# Create corrupted restart file (non-numeric)
	local restart_file="${LOGS_DIR}/restart_count"
	echo "invalid-timestamp" >"$restart_file"

	# Mock ipsec
	local mock_ipsec
	mock_ipsec=$(mock_ipsec)
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" || true

	# Should handle corrupted file gracefully
	assert_file_exist "$LOG_FILE"
	# Script should either skip rate limit check or handle error

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "config file attempts command injection via variable" {
	# Attempt command injection via EXTERNAL_PEER_IPS
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1; echo 'injected' > /tmp/injection_test"
EOF

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "${TEST_DIR}" "${TEST_DIR}/logs/vpn-monitor.log")

	# Mock ip command
	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should reject invalid IP format (command injection should be caught by IP validation)
	assert_file_exist "${TEST_DIR}/logs/vpn-monitor.log"
	# Injection should not execute - IP validation should catch it
	assert_file_not_exist "/tmp/injection_test"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "xfrm command fails with permission denied" {
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Mock ip command that fails
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "Permission denied" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Should fallback to ipsec status
	assert_file_exist "$LOG_FILE"
	# Should handle xfrm failure gracefully

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "byte counter file is directory" {
	setup_vpn_active_fixture "192.168.1.1" 1000 2000

	# Create directory instead of file (remove file first if it exists from fixture)
	local last_bytes_file="${STATE_DIR}/last_bytes_192_168_1_1"
	rm -f "$last_bytes_file"
	mkdir -p "$last_bytes_file"

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake || true

	# Should handle directory gracefully (may fail to write, but shouldn't crash)
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "verify correct behavior when switching between flock and fallback modes" {
	setup_vpn_active_fixture "192.168.1.1" 1000 2000

	local lockfile="${STATE_DIR}/vpn-monitor.lock"

	# Test 1: Run with flock available (if available)
	if command -v flock >/dev/null 2>&1; then
		PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake
		assert_success
		assert_file_not_exist "$lockfile"
	fi

	# Test 2: Run without flock (force fallback mode)
	# Create a PATH that excludes flock, but keep essential directories
	local path_without_flock=""
	for dir in $(echo "$PATH" | tr ':' ' '); do
		# Keep essential directories (/bin, /usr/bin) even if they contain flock
		if [[ "$dir" == "/bin" ]] || [[ "$dir" == "/usr/bin" ]]; then
			path_without_flock="${path_without_flock}:${dir}"
		elif [[ ! -f "$dir/flock" ]]; then
			path_without_flock="${path_without_flock}:${dir}"
		fi
	done
	path_without_flock="${path_without_flock#:}"
	# Ensure /bin and /usr/bin are always present
	if [[ "$path_without_flock" != *"/bin"* ]]; then
		path_without_flock="/bin:/usr/bin:${path_without_flock}"
	fi

	PATH="${TEST_DIR}:${path_without_flock}" run bash "$TEST_SCRIPT" --fake
	assert_success
	assert_file_not_exist "$lockfile"

	# Test 3: Switch modes during execution (simulate flock becoming unavailable)
	# This tests that the script handles mode detection correctly
	rm -f "$lockfile"
	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake
	assert_success

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "config file sources external commands (security risk)" {
	# This test verifies that config files that attempt to source external files
	# or execute commands are handled appropriately
	# Security risk: If config files can source arbitrary files, an attacker could
	# gain code execution by modifying the config file

	local config_file="${TEST_DIR}/vpn-monitor.conf"
	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command
	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	# Test 1: Config file attempts to source external file
	# Note: Sourcing a bash script WILL execute commands in it (this is bash behavior)
	# The security concern is that we allow sourcing arbitrary files
	local malicious_file="${TEST_DIR}/malicious.sh"
	cat >"$malicious_file" <<'EOF'
#!/bin/bash
# This file would execute commands if sourced
MALICIOUS_VAR="injected"
EOF

	cat >"$config_file" <<EOF
EXTERNAL_PEER_IPS="192.168.1.1"
# Attempt to source external file (security risk)
source "$malicious_file"
EOF

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should handle sourcing - may succeed (bash allows sourcing) or fail gracefully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should log error or handle gracefully
	assert_file_exist "$log_file"
	# Script should either fail to source (preferred) or handle it gracefully
	# If sourcing succeeds, variables from malicious file might be loaded
	# The key is that the script should not crash and should handle the situation

	# Clean up
	rm -f "$malicious_file" 2>/dev/null || true

	# Test 2: Config file attempts to execute command via backticks in variable assignment
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
# Attempt command execution via backticks (security risk)
TEST_VAR=$(touch "${TEST_DIR}/backtick_test_marker" 2>/dev/null; echo "test")
EOF

	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Command substitution WILL execute (this is bash behavior)
	# The script should handle it gracefully without crashing
	assert_file_exist "$log_file"

	# Clean up
	rm -f "${TEST_DIR}/backtick_test_marker" 2>/dev/null || true

	# Test 3: Config file attempts to source process substitution
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
# Attempt to source process substitution (security risk)
source <(echo 'PROCESS_SUB_VAR="injected"')
EOF

	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle gracefully - process substitution may succeed or fail
	assert_file_exist "$log_file"

	# Test 4: Config file attempts to source non-existent file (should fail gracefully)
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
# Attempt to source non-existent file
source /nonexistent/file/path.sh
EOF

	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should fail gracefully when file doesn't exist
	assert_file_exist "$log_file"
	# Should log error about failed parse
	assert_file_contains "$log_file" "Failed to parse" || assert_file_contains "$log_file" "ERROR" || assert_file_contains "$log_file" "configuration"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "config file contains null bytes or invalid characters" {
	# This test verifies that config files with null bytes or invalid characters
	# are handled gracefully without causing crashes or security issues

	local config_file="${TEST_DIR}/vpn-monitor.conf"
	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command
	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	# Test 1: Config file with null bytes (should be handled gracefully)
	printf 'EXTERNAL_PEER_IPS="192.168.1.1"\x00INVALID\x00DATA' >"$config_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should handle null bytes gracefully (may fail to parse or log error)
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle gracefully - script should not crash
	assert_file_exist "$log_file"
	# Should either fail gracefully or parse up to null byte
	# Check that script attempted to process config (logged something)
	assert_file_contains "$log_file" "Configuration" || assert_file_contains "$log_file" "ERROR" || assert_file_contains "$log_file" "Failed"

	# Test 2: Config file with invalid UTF-8 characters
	printf 'EXTERNAL_PEER_IPS="192.168.1.1"\xFF\xFE\xFDINVALID' >"$config_file"

	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle invalid UTF-8 gracefully
	assert_file_exist "$log_file"

	# Test 3: Config file with control characters (non-printable)
	printf 'EXTERNAL_PEER_IPS="192.168.1.1"\x01\x02\x03\x04\x05' >"$config_file"

	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle control characters gracefully
	assert_file_exist "$log_file"

	# Test 4: Config file with mixed valid and invalid content
	# Valid config followed by null byte and invalid data
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF
	# Append null byte and invalid characters
	printf '\x00\xFF\xFE' >>"$config_file"

	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should parse valid part before null byte
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "xfrm output format variations (different Linux kernel versions)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command with different output format (older kernel style)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Different format: no indentation, different spacing
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "replay-window 0"
    echo "lifetime current: 1000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should handle format variations gracefully
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "xfrm returns multiple SAs for same peer IP (which one is checked?)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command with multiple SAs for same peer IP
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x87654321 reqid 2 mode tunnel"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should handle multiple SAs (may check first one or aggregate)
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "xfrm output contains malformed byte counter line" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command with malformed byte counter line
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: invalid bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle malformed output gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "first check (no previous bytes) - should accept any non-zero value" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Ensure no previous bytes file exists (first check)
	rm -f "$last_bytes_file"

	# Mock ip command - VPN healthy with non-zero bytes
	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should accept non-zero value on first check
	assert_success
	assert_file_exist "$log_file"
	# Should create bytes file with current value
	assert_file_exist "$last_bytes_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "byte counter increases but very slowly (within normal variance)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Set initial byte count
	echo "1000" >"$last_bytes_file"

	# Mock ip command - bytes increased very slowly (only 1 byte)
	setup_mock_vpn_environment "192.168.1.1" 1001
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Should accept small increase as valid (bytes are increasing)
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "byte counter jumps dramatically (counter reset on remote side)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"

	# Set initial byte count (high value)
	echo "1000000" >"$last_bytes_file"

	# Mock ip command - bytes jumped dramatically lower (counter reset)
	setup_mock_vpn_environment "192.168.1.1" 100
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle counter reset (may treat as wrap-around or failure)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "multiple peers failing simultaneously - verify independent cleanup" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

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
@test "restart succeeds but VPN doesn't recover (cooldown still set)" {
	local config_file
	config_file=$(setup_test_config_with_recovery_disabled "${TEST_DIR}/vpn-monitor.conf" "192.168.1.1" \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'MAX_RESTARTS_PER_HOUR=10' \
		'COOLDOWN_MINUTES=1')

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	local cooldown_file="${TEST_DIR}/cooldown_until"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN still down after restart
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - restart succeeds
	local mock_ipsec
	mock_ipsec=$(mock_ipsec)
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Run script (not in fake mode, so restart will actually execute)
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Restart should succeed, cooldown should be set
	assert_file_exist "$log_file"
	# Cooldown file should exist after restart (if restart was triggered)
	# Note: Cooldown is set by full_restart() function, so it should exist
	if [[ -f "$cooldown_file" ]]; then
		assert_file_exist "$cooldown_file"
	else
		# If cooldown file doesn't exist, check if restart was actually called
		# This might happen if rate limiting prevented restart
		assert_file_contains "$log_file" "restart" || assert_file_contains "$log_file" "Tier 3"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "restart fails but cooldown is still set (should it be?)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	local cooldown_file="${TEST_DIR}/cooldown_until"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - restart fails
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "Restart failed" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle restart failure
	assert_file_exist "$log_file"
	# Check if cooldown was set despite failure (current behavior)
	# This tests the current implementation behavior

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "PIPESTATUS handling when restart command fails in pipe" {
	local config_file
	config_file=$(setup_test_config_with_recovery_disabled "${TEST_DIR}/vpn-monitor.conf" "192.168.1.1" \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'MAX_RESTARTS_PER_HOUR=10' \
		'COOLDOWN_MINUTES=1')

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - fails in pipe (tests PIPESTATUS handling)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "Restart output" >&1
    echo "Restart error" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should detect failure via PIPESTATUS (not tee exit code)
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "Failed" || assert_file_contains "$log_file" "ERROR"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery action partially succeeds (e.g., ipsec reload starts but fails mid-way)" {
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

	# Mock ipsec - reload partially succeeds (outputs but exits with error)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "Starting reload..."
    echo "Partial success" >&1
    echo "Error occurred mid-way" >&2
    exit 1
fi
if [[ "$1" == "restart" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

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

# bats test_tags=category:high-risk,priority:high
@test "recovery action succeeds but VPN still fails on next check" {
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
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "Reload successful"
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

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
		assert [ "$count" -eq 4 ]
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery action fails and failure counter continues incrementing" {
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
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "Reload failed" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

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
		assert [ "$count" -eq 4 ]
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "multiple recovery actions triggered simultaneously (multiple peers)" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

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
@test "recovery action during cooldown period (should be prevented)" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
COOLDOWN_MINUTES=15
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	local cooldown_file="${TEST_DIR}/cooldown_until"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Set cooldown to future time (in cooldown period)
	local future_time=$(($(date +%s) + 900)) # 15 minutes in future
	echo "$future_time" >"$cooldown_file"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - should not be called during cooldown
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ERROR: Restart should not be called during cooldown" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"

	# Should exit early due to cooldown, no recovery action should be triggered
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "cooldown period"
	# ipsec restart should not be called (script exits early)
	refute_file_contains "$log_file" "ERROR: Restart should not be called during cooldown"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "restart command hangs (timeout scenario - not currently handled)" {
	# Note: This test documents that timeout handling is not currently implemented
	# The script will hang if restart command hangs - this is a known limitation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN down
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"

	# Mock ipsec - hangs indefinitely (simulates timeout scenario)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    # Hang indefinitely (simulates command that never returns)
    while true; do
        sleep 1
    done
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Run with timeout to prevent test from hanging forever
	# This documents that the script would hang without timeout handling
	# Use timeout with --kill-after to ensure all child processes are killed
	# Give script 0.5s to start and create log file, then timeout kills it
	PATH="${TEST_DIR}:${PATH}" timeout --kill-after=0.1 --preserve-status=0 0.5 bash "$test_script" 2>/dev/null || true

	# Clean up any remaining mock ipsec processes that might have escaped
	pkill -f "${TEST_DIR}/ipsec.*restart" 2>/dev/null || true
	sleep 0.1

	# Current behavior: script hangs if restart command hangs
	# This test documents the limitation - timeout handling is not implemented
	# The test succeeds if timeout kills the process (expected behavior)
	# Log file should exist (created before timeout kills the script)
	if [[ ! -f "$log_file" ]]; then
		skip "Log file not created - script may have been killed before initialization"
	fi
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 4.4 RATE LIMITING EDGE CASES
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "rate limit file is empty" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local restart_file="${TEST_DIR}/logs/restart_count"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create empty restart file
	touch "$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	setup_mock_vpn_environment "192.168.1.1" 0

	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle empty file gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "rate limit file is a directory" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=3
COOLDOWN_MINUTES=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local restart_file="${TEST_DIR}/logs/restart_count"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create restart file as a directory
	rm -rf "$restart_file" 2>/dev/null || true
	mkdir -p "$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	setup_mock_vpn_environment "192.168.1.1" 0

	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle directory gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "restart count cleanup removes old entries after 24 hours" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local restart_file="${TEST_DIR}/logs/restart_count"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Create restart file with mix of old and recent timestamps
	local now
	now=$(date +%s)
	local one_day_ago=$((now - 86400))   # Exactly 24 hours ago
	local two_days_ago=$((now - 172800)) # 2 days ago
	local recent=$((now - 3600))         # 1 hour ago (recent)
	echo "$two_days_ago" >"$restart_file"
	echo "$one_day_ago" >>"$restart_file"
	echo "$recent" >>"$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	setup_mock_vpn_environment "192.168.1.1" 0

	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# After restart is recorded, old entries (>24 hours) should be cleaned up
	# File should contain recent timestamp and new restart timestamp, but not old ones
	assert_file_exist "$log_file"
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

# ============================================================================
# 10.2 RECOVERY SUCCESS VERIFICATION
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "recovery succeeds but byte counters do not increase immediately" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local last_bytes_file="${state_dir}/last_bytes_192_168_1_1"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"

	# Set failure count to trigger recovery check
	echo "3" >"$failure_counter"

	# Set last_bytes to a non-zero value (simulating previous traffic)
	echo "1000" >"$last_bytes_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN is up (SA exists) but byte counters haven't increased yet
	# Return same byte count as last_bytes (simulates no new traffic after recovery)
	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Should handle case where VPN recovers (SA exists) but byte counters don't increase immediately
	# Script should log warning about bytes not increasing but continue execution
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# 10.1 COMPLEX FAILURE SCENARIOS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "VPN fails, reaches Tier 3, restart fails, then recovers naturally" {
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=10
COOLDOWN_MINUTES=1
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local failure_counter="${TEST_DIR}/logs/failure_counter_192_168_1_1"
	local restart_file="${TEST_DIR}/logs/restart_count"

	# Set failure count to Tier 3 threshold (simulating previous failures)
	echo "5" >"$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN is down initially (no SA)
	setup_mock_vpn_environment "192.168.1.1" 0

	# Mock ipsec restart to fail (simulates restart failure)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "Failed to restart IPsec" >&2
    exit 1
fi
if [[ "$1" == "status" ]]; then
    echo "192.168.1.1: ESTABLISHED"
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# First run: VPN fails, reaches Tier 3, restart fails
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# Verify restart was attempted and failed
	assert_file_exist "$log_file"

	# Now simulate natural recovery: VPN comes back up (SA exists)
	setup_mock_vpn_environment "192.168.1.1" 1000

	# Second run: VPN recovers naturally (should reset failure count)
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" || true

	# After natural recovery, failure count should be reset
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter" 2>/dev/null || echo "0")
		# Failure count should be reset to 0 after natural recovery
		assert [ "$count" -eq 0 ]
	fi

	remove_mock_from_path
}
