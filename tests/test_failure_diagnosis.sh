#!/usr/bin/env bats
#
# Tests for Failure Diagnosis Functions
# Tests the core failure diagnosis functions used in failure type detection
#
# Functions tested:
#   - build_failure_diagnostic_message
#   - check_sa_existence_for_failure_type
#   - check_rekey_for_failure_type
#   - check_routing_issue_for_failure_type

load test_helper
load helpers/assertions

# Path to the VPN monitor script and modules
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"
LIB_DIR="${BATS_TEST_DIRNAME}/../lib"

# ============================================================================
# build_failure_diagnostic_message
# ============================================================================

# bats test_tags=category:unit,priority:medium
@test "build_failure_diagnostic_message - xfrm output unavailable" {
	# Purpose: Test verifies that diagnostic message includes "xfrm output unavailable" when xfrm_output is empty
	# Expected: Message includes "xfrm output unavailable" and other relevant diagnostic information
	# Importance: Ensures diagnostic messages accurately reflect missing xfrm output
	source_function "build_failure_diagnostic_message"

	local xfrm_output=""
	local byte_counters_available=0
	local current_bytes=""
	local last_bytes=""
	local internal_peer_ip=""
	local ping_checked=0
	local ping_failed=0
	local diagnostic_context=""

	run build_failure_diagnostic_message "$xfrm_output" "$byte_counters_available" "$current_bytes" "$last_bytes" "$internal_peer_ip" "$ping_checked" "$ping_failed" "$diagnostic_context"

	assert_success
	assert_output --partial "Phase 2 SA exists"
	assert_output --partial "xfrm output unavailable"
	assert_output --partial "internal IP not provided"
}

# bats test_tags=category:unit,priority:medium
@test "build_failure_diagnostic_message - byte counters available but no routing issue" {
	# Purpose: Test verifies that diagnostic message includes byte counter information when available
	# Expected: Message includes byte counter values and indicates no routing issue detected
	# Importance: Ensures diagnostic messages include byte counter data when available
	source_function "build_failure_diagnostic_message"

	local xfrm_output="src 192.168.1.1 dst 192.168.1.1"
	local byte_counters_available=1
	local current_bytes="2000"
	local last_bytes="1000"
	local internal_peer_ip="10.0.0.1"
	local ping_checked=1
	local ping_failed=0
	local diagnostic_context=""

	run build_failure_diagnostic_message "$xfrm_output" "$byte_counters_available" "$current_bytes" "$last_bytes" "$internal_peer_ip" "$ping_checked" "$ping_failed" "$diagnostic_context"

	assert_success
	assert_output --partial "Phase 2 SA exists"
	assert_output --partial "byte counters available (current=2000, last=1000) but no routing issue detected"
	assert_output --partial "ping check enabled and succeeded"
}

# bats test_tags=category:unit,priority:medium
@test "build_failure_diagnostic_message - byte counter extraction failed" {
	# Purpose: Test verifies that diagnostic message includes "byte counter extraction failed" when extraction fails
	# Expected: Message includes "byte counter extraction failed" when byte_counters_available=0 but xfrm_output exists
	# Importance: Ensures diagnostic messages accurately reflect byte counter extraction failures
	source_function "build_failure_diagnostic_message"

	local xfrm_output="src 192.168.1.1 dst 192.168.1.1"
	local byte_counters_available=0
	local current_bytes=""
	local last_bytes=""
	local internal_peer_ip=""
	local ping_checked=0
	local ping_failed=0
	local diagnostic_context=""

	run build_failure_diagnostic_message "$xfrm_output" "$byte_counters_available" "$current_bytes" "$last_bytes" "$internal_peer_ip" "$ping_checked" "$ping_failed" "$diagnostic_context"

	assert_success
	assert_output --partial "Phase 2 SA exists"
	assert_output --partial "byte counter extraction failed"
	assert_output --partial "internal IP not provided"
}

# bats test_tags=category:unit,priority:medium
@test "build_failure_diagnostic_message - ping check disabled" {
	# Purpose: Test verifies that diagnostic message includes "ping check disabled" when ping check is not enabled
	# Expected: Message includes "ping check disabled" when ENABLE_PING_CHECK is not set
	# Importance: Ensures diagnostic messages accurately reflect ping check status
	source_function "build_failure_diagnostic_message"

	# Ensure ENABLE_PING_CHECK is not set
	unset ENABLE_PING_CHECK

	local xfrm_output="src 192.168.1.1 dst 192.168.1.1"
	local byte_counters_available=0
	local current_bytes=""
	local last_bytes=""
	local internal_peer_ip=""
	local ping_checked=0
	local ping_failed=0
	local diagnostic_context=""

	run build_failure_diagnostic_message "$xfrm_output" "$byte_counters_available" "$current_bytes" "$last_bytes" "$internal_peer_ip" "$ping_checked" "$ping_failed" "$diagnostic_context"

	assert_success
	assert_output --partial "ping check disabled"
}

# bats test_tags=category:unit,priority:medium
@test "build_failure_diagnostic_message - with diagnostic context" {
	# Purpose: Test verifies that diagnostic message includes custom diagnostic context when provided
	# Expected: Message includes the provided diagnostic context string
	# Importance: Ensures diagnostic messages can include additional context for debugging
	source_function "build_failure_diagnostic_message"

	local xfrm_output=""
	local byte_counters_available=0
	local current_bytes=""
	local last_bytes=""
	local internal_peer_ip=""
	local ping_checked=0
	local ping_failed=0
	local diagnostic_context="VPN check failed - unable to determine specific failure type without diagnostic data"

	run build_failure_diagnostic_message "$xfrm_output" "$byte_counters_available" "$current_bytes" "$last_bytes" "$internal_peer_ip" "$ping_checked" "$ping_failed" "$diagnostic_context"

	assert_success
	assert_output --partial "$diagnostic_context"
}

# ============================================================================
# check_sa_existence_for_failure_type
# ============================================================================

# bats test_tags=category:unit,priority:high
@test "check_sa_existence_for_failure_type - primary_check_passed=1 (SA exists)" {
	# Purpose: Test verifies that function returns 0 when primary_check_passed=1 (SA exists invariant)
	# Expected: Function returns 0 (SA exists) when primary_check_passed=1
	# Importance: Tests the fundamental invariant that primary_check_passed=1 means SA exists
	source_function "check_sa_existence_for_failure_type"

	local external_peer_ip="${TEST_PEER_IP}"
	local primary_check_passed=1
	local xfrm_output=""

	run check_sa_existence_for_failure_type "$external_peer_ip" "$primary_check_passed" "$xfrm_output"

	assert_success
}

# bats test_tags=category:unit,priority:high
@test "check_sa_existence_for_failure_type - primary_check_passed=0 with valid xfrm_output" {
	# Purpose: Test verifies that function returns 0 when primary_check_passed=0 but xfrm_output contains valid SA data
	# Expected: Function extracts SPI from xfrm_output and returns 0 (SA exists)
	# Importance: Tests optimization path where xfrm_output is reused to avoid duplicate calls
	source_function "check_sa_existence_for_failure_type"
	source_function "extract_spi"

	local external_peer_ip="${TEST_PEER_IP}"
	local primary_check_passed=0
	local xfrm_output="src ${TEST_PEER_IP} dst ${TEST_PEER_IP}
    proto esp spi 0x12345678 reqid 1 mode tunnel"

	run check_sa_existence_for_failure_type "$external_peer_ip" "$primary_check_passed" "$xfrm_output"

	assert_success
}

# bats test_tags=category:unit,priority:high
@test "check_sa_existence_for_failure_type - primary_check_passed=0 with empty xfrm_output provided" {
	# Purpose: Test verifies that function returns 1 when primary_check_passed=0 and xfrm_output is empty (but parameter was provided)
	# Expected: Function returns 1 (SA doesn't exist) when xfrm_output parameter was provided but is empty
	# Importance: Tests optimization path where empty xfrm_output parameter prevents duplicate check_ipsec_phase2 call
	source_function "check_sa_existence_for_failure_type"

	local external_peer_ip="${TEST_PEER_IP}"
	local primary_check_passed=0
	local xfrm_output=""

	run check_sa_existence_for_failure_type "$external_peer_ip" "$primary_check_passed" "$xfrm_output"

	assert_failure
}

# bats test_tags=category:unit,priority:high
@test "check_sa_existence_for_failure_type - primary_check_passed=0 without xfrm_output, ipsec succeeds" {
	# Purpose: Test verifies that function calls check_ipsec_phase2 when xfrm_output not provided and ipsec succeeds
	# Expected: Function calls check_ipsec_phase2 and returns 0 (SA exists) when ipsec check succeeds
	# Importance: Tests fallback path when xfrm_output is not available
	source_function "check_sa_existence_for_failure_type"

	# Mock ip command to return xfrm state (check_ipsec_phase2 uses get_xfrm_state_for_peer which calls ip)
	mock_ip_xfrm_state "${TEST_PEER_IP}" "1000" >/dev/null
	add_mock_to_path

	local external_peer_ip="${TEST_PEER_IP}"
	local primary_check_passed=0
	# Don't provide xfrm_output parameter (third parameter not set)

	run check_sa_existence_for_failure_type "$external_peer_ip" "$primary_check_passed"

	assert_success

	remove_mock_from_path
}

# bats test_tags=category:unit,priority:high
@test "check_sa_existence_for_failure_type - primary_check_passed=0 without xfrm_output, ipsec fails" {
	# Purpose: Test verifies that function calls check_ipsec_phase2 when xfrm_output not provided and ipsec fails
	# Expected: Function calls check_ipsec_phase2 and returns 1 (SA doesn't exist) when ipsec check fails
	# Importance: Tests fallback path when xfrm_output is not available and ipsec check fails
	source_function "check_sa_existence_for_failure_type"

	# Mock ip command to return empty xfrm state (check_ipsec_phase2 uses get_xfrm_state_for_peer which calls ip)
	mock_ip_xfrm_empty >/dev/null
	add_mock_to_path

	local external_peer_ip="${TEST_PEER_IP}"
	local primary_check_passed=0
	# Don't provide xfrm_output parameter (third parameter not set)

	run check_sa_existence_for_failure_type "$external_peer_ip" "$primary_check_passed"

	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:unit,priority:medium
@test "check_sa_existence_for_failure_type - primary_check_passed=0 with xfrm_output containing invalid SPI" {
	# Purpose: Test verifies that function returns 1 when xfrm_output is provided but doesn't contain valid SPI
	# Expected: Function returns 1 (SA doesn't exist) when xfrm_output doesn't contain extractable SPI
	# Importance: Tests handling of malformed xfrm_output
	source_function "check_sa_existence_for_failure_type"

	local external_peer_ip="${TEST_PEER_IP}"
	local primary_check_passed=0
	local xfrm_output="src ${TEST_PEER_IP} dst ${TEST_PEER_IP}
    proto esp reqid 1 mode tunnel"
	# Missing SPI - extract_spi will fail

	run check_sa_existence_for_failure_type "$external_peer_ip" "$primary_check_passed" "$xfrm_output"

	assert_failure
}

# ============================================================================
# check_rekey_for_failure_type
# ============================================================================

# bats test_tags=category:unit,priority:high
@test "check_rekey_for_failure_type - rekey detected" {
	# Purpose: Test verifies that function returns 0 when SA rekey is detected (SPI changed)
	# Expected: Function returns 0 (rekey detected) when SPI has changed from baseline
	# Importance: Tests rekey detection for failure type classification
	source_function "check_rekey_for_failure_type"
	source_function "set_peer_state"

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	mkdir -p "$STATE_DIR"

	local current_spi="0x87654321"
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"

	# Set baseline SPI (different from current)
	set_peer_state "$location_name" "$external_peer_ip" "spi" "0x12345678" || true

	run check_rekey_for_failure_type "$current_spi" "$external_peer_ip" "$location_name"

	assert_success
}

# bats test_tags=category:unit,priority:high
@test "check_rekey_for_failure_type - no rekey (SPI unchanged)" {
	# Purpose: Test verifies that function returns 1 when SPI hasn't changed (no rekey)
	# Expected: Function returns 1 (no rekey) when current SPI matches baseline SPI
	# Importance: Tests that unchanged SPI is not treated as rekey
	source_function "check_rekey_for_failure_type"
	source_function "set_peer_state"

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	mkdir -p "$STATE_DIR"

	local current_spi="0x12345678"
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"

	# Set baseline SPI (same as current)
	set_peer_state "$location_name" "$external_peer_ip" "spi" "0x12345678" || true

	run check_rekey_for_failure_type "$current_spi" "$external_peer_ip" "$location_name"

	assert_failure
}

# bats test_tags=category:unit,priority:medium
@test "check_rekey_for_failure_type - empty SPI" {
	# Purpose: Test verifies that function returns 1 when SPI is empty
	# Expected: Function returns 1 (no rekey) when current SPI is empty
	# Importance: Tests handling of missing SPI data
	source_function "check_rekey_for_failure_type"

	local current_spi=""
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"

	run check_rekey_for_failure_type "$current_spi" "$external_peer_ip" "$location_name"

	assert_failure
}

# bats test_tags=category:unit,priority:medium
@test "check_rekey_for_failure_type - no baseline SPI stored" {
	# Purpose: Test verifies that function returns 1 when no baseline SPI is stored
	# Expected: Function returns 1 (no rekey) when baseline SPI doesn't exist in state
	# Importance: Tests handling of missing baseline SPI (first check scenario)
	source_function "check_rekey_for_failure_type"

	# Set up state directory (empty - no baseline SPI)
	export STATE_DIR="${TEST_DIR}"
	mkdir -p "$STATE_DIR"

	local current_spi="0x12345678"
	local external_peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"

	run check_rekey_for_failure_type "$current_spi" "$external_peer_ip" "$location_name"

	assert_failure
}

# ============================================================================
# check_routing_issue_for_failure_type
# ============================================================================

# bats test_tags=category:unit,priority:high
@test "check_routing_issue_for_failure_type - bytes not increasing (routing issue)" {
	# Purpose: Test verifies that function detects routing issue when bytes are not increasing
	# Expected: Function returns 0 (routing issue detected) and outputs flags when bytes not increasing
	# Importance: Tests core routing issue detection logic based on byte counters
	source_function "check_routing_issue_for_failure_type"
	source_function "set_peer_state"

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	mkdir -p "$STATE_DIR"

	local current_bytes="1000"
	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local internal_peer_ip=""

	# Set last_bytes to same value (bytes not increasing)
	set_peer_state "$location_name" "$external_peer_ip" "last_bytes" "1000" || true

	run check_routing_issue_for_failure_type "$current_bytes" "$location_name" "$external_peer_ip" "$internal_peer_ip"

	assert_success
	# Check output flags
	local byte_counters_available ping_checked ping_failed
	read -r byte_counters_available ping_checked ping_failed <<<"$output"
	assert_equal "$byte_counters_available" "1"
	assert_equal "$ping_checked" "0"
	assert_equal "$ping_failed" "0"
}

# bats test_tags=category:unit,priority:high
@test "check_routing_issue_for_failure_type - bytes decreasing (routing issue)" {
	# Purpose: Test verifies that function detects routing issue when bytes decrease
	# Expected: Function returns 0 (routing issue detected) when current_bytes < last_bytes
	# Importance: Tests detection of traffic flow degradation
	source_function "check_routing_issue_for_failure_type"
	source_function "set_peer_state"

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	mkdir -p "$STATE_DIR"

	local current_bytes="500"
	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local internal_peer_ip=""

	# Set last_bytes higher than current (bytes decreased)
	set_peer_state "$location_name" "$external_peer_ip" "last_bytes" "1000" || true

	run check_routing_issue_for_failure_type "$current_bytes" "$location_name" "$external_peer_ip" "$internal_peer_ip"

	assert_success
	# Check output flags
	local byte_counters_available ping_checked ping_failed
	read -r byte_counters_available ping_checked ping_failed <<<"$output"
	assert_equal "$byte_counters_available" "1"
}

# bats test_tags=category:unit,priority:high
@test "check_routing_issue_for_failure_type - bytes dropped to zero (routing issue)" {
	# Purpose: Test verifies that function detects routing issue when bytes drop to zero
	# Expected: Function returns 0 (routing issue detected) when current_bytes=0 and last_bytes>0
	# Importance: Tests detection of complete traffic loss
	source_function "check_routing_issue_for_failure_type"
	source_function "set_peer_state"

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	mkdir -p "$STATE_DIR"

	local current_bytes="0"
	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local internal_peer_ip=""

	# Set last_bytes to non-zero (bytes dropped to zero)
	set_peer_state "$location_name" "$external_peer_ip" "last_bytes" "1000" || true

	run check_routing_issue_for_failure_type "$current_bytes" "$location_name" "$external_peer_ip" "$internal_peer_ip"

	assert_success
	# Check output flags
	local byte_counters_available ping_checked ping_failed
	read -r byte_counters_available ping_checked ping_failed <<<"$output"
	assert_equal "$byte_counters_available" "1"
}

# bats test_tags=category:unit,priority:high
@test "check_routing_issue_for_failure_type - bytes increasing (no routing issue)" {
	# Purpose: Test verifies that function returns 1 when bytes are increasing normally
	# Expected: Function returns 1 (no routing issue) when current_bytes > last_bytes
	# Importance: Tests that normal traffic flow is not flagged as routing issue
	source_function "check_routing_issue_for_failure_type"
	source_function "set_peer_state"

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	mkdir -p "$STATE_DIR"

	local current_bytes="2000"
	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local internal_peer_ip=""

	# Set last_bytes lower than current (bytes increasing)
	set_peer_state "$location_name" "$external_peer_ip" "last_bytes" "1000" || true

	run check_routing_issue_for_failure_type "$current_bytes" "$location_name" "$external_peer_ip" "$internal_peer_ip"

	assert_failure
	# Check output flags
	local byte_counters_available ping_checked ping_failed
	read -r byte_counters_available ping_checked ping_failed <<<"$output"
	assert_equal "$byte_counters_available" "1"
	assert_equal "$ping_checked" "0"
	assert_equal "$ping_failed" "0"
}

# bats test_tags=category:unit,priority:high
@test "check_routing_issue_for_failure_type - ping check enabled and fails (routing issue)" {
	# Purpose: Test verifies that function detects routing issue when ping check enabled and fails
	# Expected: Function returns 0 (routing issue detected) when ping check fails
	# Importance: Tests ping-based routing issue detection
	source_function "check_routing_issue_for_failure_type"
	source_function "get_local_ip_for_ping"

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	mkdir -p "$STATE_DIR"

	# Enable ping check
	export ENABLE_PING_CHECK=1

	local current_bytes="2000"
	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local internal_peer_ip="${TEST_LOCAL_IP}"

	# Set last_bytes lower than current (bytes increasing, so no byte counter issue)
	# This ensures ping check is executed (has_routing_issue=0 before ping check)
	set_peer_state "$location_name" "$external_peer_ip" "last_bytes" "1000" || true

	# Mock ping to fail
	mock_ping_failure >/dev/null
	add_mock_to_path

	run check_routing_issue_for_failure_type "$current_bytes" "$location_name" "$external_peer_ip" "$internal_peer_ip"

	assert_success
	# Check output flags
	local byte_counters_available ping_checked ping_failed
	read -r byte_counters_available ping_checked ping_failed <<<"$output"
	assert_equal "$byte_counters_available" "1"
	assert_equal "$ping_checked" "1"
	assert_equal "$ping_failed" "1"

	remove_mock_from_path
	unset ENABLE_PING_CHECK
}

# bats test_tags=category:unit,priority:high
@test "check_routing_issue_for_failure_type - ping check enabled and succeeds (no routing issue)" {
	# Purpose: Test verifies that function returns 1 when ping check enabled and succeeds
	# Expected: Function returns 1 (no routing issue) when ping check succeeds
	# Importance: Tests that successful ping prevents false positive routing issue detection
	source_function "check_routing_issue_for_failure_type"

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	mkdir -p "$STATE_DIR"

	# Enable ping check
	export ENABLE_PING_CHECK=1

	local current_bytes="2000"
	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local internal_peer_ip="${TEST_LOCAL_IP}"

	# Set last_bytes lower than current (bytes increasing, so no byte counter issue)
	# This ensures ping check is executed (has_routing_issue=0 before ping check)
	set_peer_state "$location_name" "$external_peer_ip" "last_bytes" "1000" || true

	# Mock ping to succeed
	mock_ping_success >/dev/null
	add_mock_to_path

	run check_routing_issue_for_failure_type "$current_bytes" "$location_name" "$external_peer_ip" "$internal_peer_ip"

	assert_failure
	# Check output flags
	local byte_counters_available ping_checked ping_failed
	read -r byte_counters_available ping_checked ping_failed <<<"$output"
	assert_equal "$byte_counters_available" "1"
	assert_equal "$ping_checked" "1"
	assert_equal "$ping_failed" "0"

	remove_mock_from_path
	unset ENABLE_PING_CHECK
}

# bats test_tags=category:unit,priority:medium
@test "check_routing_issue_for_failure_type - byte counters unavailable, ping check disabled" {
	# Purpose: Test verifies that function returns 1 when byte counters unavailable and ping check disabled
	# Expected: Function returns 1 (no routing issue) when no diagnostic data available
	# Importance: Tests handling of missing diagnostic data
	source_function "check_routing_issue_for_failure_type"

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	mkdir -p "$STATE_DIR"

	# Disable ping check
	export ENABLE_PING_CHECK=0

	local current_bytes=""
	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local internal_peer_ip=""

	run check_routing_issue_for_failure_type "$current_bytes" "$location_name" "$external_peer_ip" "$internal_peer_ip"

	assert_failure
	# Check output flags
	local byte_counters_available ping_checked ping_failed
	read -r byte_counters_available ping_checked ping_failed <<<"$output"
	assert_equal "$byte_counters_available" "0"
	assert_equal "$ping_checked" "0"
	assert_equal "$ping_failed" "0"

	unset ENABLE_PING_CHECK
}

# bats test_tags=category:unit,priority:medium
@test "check_routing_issue_for_failure_type - byte counters unavailable, ping check enabled and fails" {
	# Purpose: Test verifies that function detects routing issue when byte counters unavailable but ping fails
	# Expected: Function returns 0 (routing issue detected) when byte counters unavailable but ping fails
	# Importance: Tests that ping check can detect routing issues even without byte counter data
	source_function "check_routing_issue_for_failure_type"

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	mkdir -p "$STATE_DIR"

	# Enable ping check
	export ENABLE_PING_CHECK=1

	local current_bytes=""
	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local internal_peer_ip="${TEST_LOCAL_IP}"

	# Mock ping to fail
	mock_ping_failure >/dev/null
	add_mock_to_path

	run check_routing_issue_for_failure_type "$current_bytes" "$location_name" "$external_peer_ip" "$internal_peer_ip"

	assert_success
	# Check output flags
	local byte_counters_available ping_checked ping_failed
	read -r byte_counters_available ping_checked ping_failed <<<"$output"
	assert_equal "$byte_counters_available" "0"
	assert_equal "$ping_checked" "1"
	assert_equal "$ping_failed" "1"

	remove_mock_from_path
	unset ENABLE_PING_CHECK
}

# bats test_tags=category:unit,priority:medium
@test "check_routing_issue_for_failure_type - first check (last_bytes=0, current_bytes>0)" {
	# Purpose: Test verifies that function returns 1 on first check when last_bytes=0 and current_bytes>0
	# Expected: Function returns 1 (no routing issue) on first check to avoid false positives
	# Importance: Tests that first check doesn't flag routing issue when no baseline exists
	source_function "check_routing_issue_for_failure_type"
	source_function "set_peer_state"

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	mkdir -p "$STATE_DIR"

	local current_bytes="1000"
	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local internal_peer_ip=""

	# Set last_bytes to 0 (first check scenario)
	set_peer_state "$location_name" "$external_peer_ip" "last_bytes" "0" || true

	run check_routing_issue_for_failure_type "$current_bytes" "$location_name" "$external_peer_ip" "$internal_peer_ip"

	assert_failure
	# Check output flags
	local byte_counters_available ping_checked ping_failed
	read -r byte_counters_available ping_checked ping_failed <<<"$output"
	assert_equal "$byte_counters_available" "1"
}

# bats test_tags=category:unit,priority:low
@test "check_routing_issue_for_failure_type - non-numeric bytes value" {
	# Purpose: Test verifies that function handles non-numeric bytes values gracefully
	# Expected: Function treats non-numeric bytes as unavailable (byte_counters_available=0)
	# Importance: Tests handling of malformed byte counter data
	source_function "check_routing_issue_for_failure_type"

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	mkdir -p "$STATE_DIR"

	local current_bytes="abc123"
	local location_name="TEST"
	local external_peer_ip="${TEST_PEER_IP}"
	local internal_peer_ip=""

	run check_routing_issue_for_failure_type "$current_bytes" "$location_name" "$external_peer_ip" "$internal_peer_ip"

	assert_failure
	# Check output flags - non-numeric bytes should be treated as unavailable
	local byte_counters_available ping_checked ping_failed
	read -r byte_counters_available ping_checked ping_failed <<<"$output"
	assert_equal "$byte_counters_available" "0"
}
