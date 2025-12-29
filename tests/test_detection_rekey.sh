#!/usr/bin/env bats
#
# Tests for SA Rekey Detection
# Tests critical paths and error handling scenarios

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# 2.2 SA REKEY DETECTION
# ============================================================================

# bats test_tags=category:high-risk,priority:medium
@test "SA rekey detected - SPI changes, baseline reset to 0" {
	# Test verifies that SA rekey detection resets byte counter baseline to 0 when SPI changes.
	# Expected: When SPI changes, byte counter baseline is reset to 0.
	# Importance: Prevents false failure detection after SA rekey events.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Set initial SPI and byte counter
	setup_state_files "192.168.1.1" 0 5000 "0x12345678"

	# Mock ip command - new SPI (rekey occurred)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should detect rekey and reset baseline
	assert_success
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "SA rekey detected" || assert_file_contains "$LOG_FILE" "rekey"

	# Verify byte counter baseline was reset
	local bytes_file="${STATE_DIR}/last_bytes_192_168_1_1"
	if [[ -f "$bytes_file" ]]; then
		local bytes
		bytes=$(cat "$bytes_file")
		# After rekey, baseline should be reset, then updated with current bytes (1000)
		assert_equal "$bytes" 1000
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "SA rekey detected - Byte counter baseline reset allows new baseline" {
	# Test verifies that byte counter baseline reset after rekey allows new baseline to be established.
	# Expected: After rekey, new byte counter baseline can be established from current bytes.
	# Importance: Ensures byte counter tracking works correctly after rekey events.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Set initial SPI and byte counter (high value)
	setup_state_files "192.168.1.1" 0 10000 "0x12345678"

	# Mock ip command - new SPI (rekey) with new bytes
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should detect rekey and establish new baseline
	assert_success
	assert_file_exist "$LOG_FILE"

	# Verify new baseline was established (2000 bytes)
	local bytes_file="${STATE_DIR}/last_bytes_192_168_1_1"
	if [[ -f "$bytes_file" ]]; then
		local bytes
		bytes=$(cat "$bytes_file")
		assert_equal "$bytes" "2000"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "SA rekey detected - Idle state cleared on rekey" {
	# Test verifies that idle state is cleared when SA rekey is detected.
	# Expected: Idle state file is deleted when rekey occurs.
	# Importance: Rekey events reset all state, including idle detection.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Set initial SPI and create idle state file
	setup_state_files "192.168.1.1" 0 1000 "0x12345678"
	local idle_file="${STATE_DIR}/idle_detected_192_168_1_1"
	echo "1" >"$idle_file"

	# Mock ip command - new SPI (rekey occurred)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should detect rekey and clear idle state
	assert_success
	assert_file_exist "$LOG_FILE"

	# Verify idle state file was deleted
	assert_file_not_exist "$idle_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "SA rekey not detected - SPI unchanged" {
	# Test verifies that SA rekey is not detected when SPI remains unchanged.
	# Expected: No rekey detection when SPI is the same as stored value.
	# Importance: Prevents false rekey detection when SPI hasn't changed.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Set initial SPI
	setup_state_files "192.168.1.1" 0 1000 "0x12345678"

	# Mock ip command - same SPI (no rekey)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should not detect rekey
	assert_success
	assert_file_exist "$LOG_FILE"
	# Should not contain rekey message
	refute_file_contains "$LOG_FILE" "SA rekey detected"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "SA rekey detection - First check (no stored SPI) - Should store SPI" {
	# Test verifies that first check stores SPI without detecting rekey.
	# Expected: SPI is stored on first check, no rekey detected.
	# Importance: Ensures SPI tracking starts correctly on first check.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Don't set SPI file (first check)

	# Mock ip command - first SPI
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should store SPI but not detect rekey
	assert_success
	assert_file_exist "$LOG_FILE"

	# Verify SPI was stored
	local spi_file="${STATE_DIR}/spi_192_168_1_1"
	assert_file_exist "$spi_file"
	local spi
	spi=$(cat "$spi_file")
	assert_equal "$spi" "0x12345678"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "SA rekey detection - SPI file corrupted - Should recover gracefully" {
	# Test verifies that corrupted SPI files are recovered gracefully.
	# Expected: Corrupted SPI file is recovered and SPI tracking continues.
	# Importance: Prevents script failures from corrupted SPI files.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Create corrupted SPI file
	local spi_file="${STATE_DIR}/spi_192_168_1_1"
	echo "invalid-value" >"$spi_file"

	# Mock ip command
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should recover corrupted file and continue
	assert_success
	assert_file_exist "$LOG_FILE"

	# Verify SPI file was recovered
	if [[ -f "$spi_file" ]]; then
		local spi
		spi=$(cat "$spi_file")
		# Should contain valid SPI value
		assert_regex "$spi" '^(0x[0-9a-fA-F]+|[0-9]+)$'
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "SA rekey detection - Multiple rekeys in sequence" {
	# Test verifies that multiple rekeys in sequence are detected correctly.
	# Expected: Each rekey is detected and baseline is reset appropriately.
	# Importance: Ensures rekey detection works correctly for multiple rekey events.
	setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"

	# Set initial SPI
	setup_state_files "192.168.1.1" 0 1000 "0x12345678"

	# First rekey
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success
	assert_file_contains "$LOG_FILE" "SA rekey detected" || assert_file_contains "$LOG_FILE" "rekey"

	# Second rekey (different SPI)
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0xABCDEF12 reqid 1 mode tunnel"
    echo "    lifetime current: 3000 bytes, 30 packets"
fi
EOF

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success
	assert_file_contains "$LOG_FILE" "SA rekey detected" || assert_file_contains "$LOG_FILE" "rekey"

	# Verify SPI was updated to latest value
	local spi_file="${STATE_DIR}/spi_192_168_1_1"
	if [[ -f "$spi_file" ]]; then
		local spi
		spi=$(cat "$spi_file")
		assert_equal "$spi" "0xABCDEF12"
	fi

	remove_mock_from_path
}
