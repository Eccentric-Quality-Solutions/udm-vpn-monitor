#!/usr/bin/env bats
#
# Tests for SA Rekey Detection
# Tests critical paths and error handling scenarios

load test_helper
load helpers/assertions
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
	# Purpose: Test verifies that SA rekey detection resets byte counter baseline to 0 when SPI changes
	# Expected: When SPI changes, byte counter baseline is reset to 0
	# Importance: Prevents false failure detection after SA rekey events
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Set initial SPI and byte counter using location-based state functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	set_peer_state "TEST" "${TEST_PEER_IP}" "spi" "0x12345678" || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "last_bytes" "5000" || true

	# Mock ip command - new SPI (rekey occurred)
	mock_ip_xfrm_state "${TEST_PEER_IP}" 1000 "0x87654321" >/dev/null
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should detect rekey and reset baseline
	assert_success
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "SA rekey detected" "rekey"

	source_function "get_peer_state_file_path"

	# Verify byte counter baseline was reset - use location-based path
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local bytes_file
	bytes_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "last_bytes")
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
	# Purpose: Test verifies that byte counter baseline reset after rekey allows new baseline to be established
	# Expected: After rekey, new byte counter baseline can be established from current bytes
	# Importance: Ensures byte counter tracking works correctly after rekey events
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Set initial SPI and byte counter (high value) using location-based state functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	set_peer_state "TEST" "${TEST_PEER_IP}" "spi" "0x12345678" || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "last_bytes" "10000" || true

	# Mock ip command - new SPI (rekey) with new bytes
	mock_ip_xfrm_state "${TEST_PEER_IP}" 2000 "0x87654321" >/dev/null
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should detect rekey and establish new baseline
	assert_success
	assert_file_exist "$LOG_FILE"

	source_function "get_peer_state_file_path"

	# Verify new baseline was established (2000 bytes) - use location-based path
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local bytes_file
	bytes_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "last_bytes")
	if [[ -f "$bytes_file" ]]; then
		local bytes
		bytes=$(cat "$bytes_file")
		assert_equal "$bytes" "2000"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "SA rekey detected - Idle state cleared on rekey" {
	# Purpose: Test verifies that idle state is cleared when SA rekey is detected
	# Expected: Idle state file is deleted when rekey occurs
	# Importance: Rekey events reset all state, including idle detection
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Set initial SPI and create idle state file using location-based state functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	set_peer_state "TEST" "${TEST_PEER_IP}" "spi" "0x12345678" || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "last_bytes" "1000" || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "idle_detected" "1" || true
	source_function "get_peer_state_file_path"
	local idle_file
	idle_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "idle_detected")

	# Mock ip command - new SPI (rekey occurred)
	mock_ip_xfrm_state "${TEST_PEER_IP}" 2000 "0x87654321" >/dev/null
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
	# Purpose: Test verifies that SA rekey is not detected when SPI remains unchanged
	# Expected: No rekey detection when SPI is the same as stored value
	# Importance: Prevents false rekey detection when SPI hasn't changed
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Set initial SPI using location-based state functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	set_peer_state "TEST" "${TEST_PEER_IP}" "spi" "0x12345678" || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "last_bytes" "1000" || true

	# Mock ip command - same SPI (no rekey)
	mock_ip_xfrm_state "${TEST_PEER_IP}" 2000 "0x12345678" >/dev/null
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
	# Purpose: Test verifies that first check stores SPI without detecting rekey
	# Expected: SPI is stored on first check, no rekey detected
	# Importance: Ensures SPI tracking starts correctly on first check
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Don't set SPI file (first check)

	# Mock ip command - first SPI
	mock_ip_xfrm_state "${TEST_PEER_IP}" 1000 "0x12345678" >/dev/null
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should store SPI but not detect rekey
	assert_success
	assert_file_exist "$LOG_FILE"

	source_function "get_peer_state_file_path"

	# Verify SPI was stored - use location-based path
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local spi_file
	spi_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "spi")
	assert_file_exist "$spi_file"
	local spi
	spi=$(cat "$spi_file")
	assert_equal "$spi" "0x12345678"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "SA rekey detection - SPI file corrupted - Should recover gracefully" {
	# Purpose: Test verifies that corrupted SPI files are recovered gracefully
	# Expected: Corrupted SPI file is recovered and SPI tracking continues
	# Importance: Prevents script failures from corrupted SPI files
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	source_function "get_peer_state_file_path"

	# Create corrupted SPI file - use location-based path
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local spi_file
	spi_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "spi")
	echo "invalid-value" >"$spi_file"

	# Mock ip command
	mock_ip_xfrm_state "${TEST_PEER_IP}" 1000 "0x12345678" >/dev/null
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
	# Purpose: Test verifies that multiple rekeys in sequence are detected correctly
	# Expected: Each rekey is detected and baseline is reset appropriately
	# Importance: Ensures rekey detection works correctly for multiple rekey events
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Set initial SPI using location-based state functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	set_peer_state "TEST" "${TEST_PEER_IP}" "spi" "0x12345678" || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "last_bytes" "1000" || true

	# First rekey
	mock_ip_xfrm_state "${TEST_PEER_IP}" 2000 "0x87654321" >/dev/null
	add_mock_to_path

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success
	assert_log_contains_any "$LOG_FILE" "SA rekey detected" "rekey"

	# Second rekey (different SPI)
	mock_ip_xfrm_state "${TEST_PEER_IP}" 3000 "0xABCDEF12" >/dev/null

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success
	assert_log_contains_any "$LOG_FILE" "SA rekey detected" "rekey"

	source_function "get_peer_state_file_path"

	# Verify SPI was updated to latest value - use location-based path
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local spi_file
	spi_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "spi")
	if [[ -f "$spi_file" ]]; then
		local spi
		spi=$(cat "$spi_file")
		# SPI is normalized to lowercase hex format (0xABCDEF12 -> 0xabcdef12)
		assert_equal "$spi" "0xabcdef12"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "SA rekey detected - Rekey with zero bytes (baseline reset allows zero bytes)" {
	# Purpose: Test verifies that SA rekey detection handles rekey events when byte counters are zero
	# Expected: When rekey occurs with zero bytes, baseline is reset to 0 and VPN is treated as healthy
	# Importance: Tests edge case where rekey occurs immediately after SA establishment (zero bytes)
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Set initial SPI and byte counter using location-based state functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	set_peer_state "TEST" "${TEST_PEER_IP}" "spi" "0x12345678" || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "last_bytes" "5000" || true

	# Mock ip command - new SPI (rekey occurred) with zero bytes
	mock_ip_xfrm_state "${TEST_PEER_IP}" 0 "0x87654321" >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake

	# Should detect rekey and reset baseline
	assert_success
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "SA rekey detected" "rekey"

	source_function "get_peer_state_file_path"

	# Verify byte counter baseline was reset to 0 - use location-based path
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local bytes_file
	bytes_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "last_bytes")
	if [[ -f "$bytes_file" ]]; then
		local bytes
		bytes=$(cat "$bytes_file")
		# After rekey with zero bytes, baseline should be reset to 0
		assert_equal "$bytes" 0
	fi

	# Verify SPI was updated
	local spi_file
	spi_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "spi")
	if [[ -f "$spi_file" ]]; then
		local spi
		spi=$(cat "$spi_file")
		assert_equal "$spi" "0x87654321"
	fi

	remove_mock_from_path
}
