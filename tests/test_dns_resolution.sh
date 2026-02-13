#!/usr/bin/env bats
#
# Tests for DNS Resolution Functions
# Tests resolve_dns() and validate_ip_or_dns() functions used for location configuration

load test_helper

# Source the detection library functions
# shellcheck source=../lib/detection.sh
source "${BATS_TEST_DIRNAME}/../lib/detection.sh"

# Source logging for handle_error functions
# shellcheck source=../lib/logging.sh
source "${BATS_TEST_DIRNAME}/../lib/logging.sh"

# ============================================================================
# RESOLVE_DNS TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "resolve_dns - valid DNS name resolves successfully" {
	# Purpose: Test that resolve_dns() successfully resolves a valid DNS name
	# Expected: Function returns 0 and outputs resolved IP address
	# Importance: Core functionality for DNS name support in location config
	local test_hostname="test.example.com"
	local expected_ip="192.168.1.100"

	# Mock getent to succeed
	mock_getent "1" "$expected_ip" "$test_hostname"
	add_mock_to_path

	# Test resolve_dns function
	run resolve_dns "$test_hostname"
	assert_success
	assert_output "$expected_ip"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "resolve_dns - IP address returns unchanged" {
	# Purpose: Test that resolve_dns() returns IP addresses unchanged
	# Expected: Function returns 0 and outputs the same IP address
	# Importance: Ensures IP addresses still work (backward compatibility)
	local test_ip="192.168.1.50"

	# No mocks needed - IP addresses bypass DNS resolution
	run resolve_dns "$test_ip"
	assert_success
	assert_output "$test_ip"
}

# bats test_tags=category:high-risk,priority:high
@test "resolve_dns - invalid DNS name format fails gracefully" {
	# Purpose: Test that resolve_dns() fails gracefully for invalid DNS name format
	# Expected: Function returns 1 and logs warning
	# Importance: Error handling for malformed DNS names
	local invalid_dns="-invalid.com"

	# No mocks needed - validation happens before DNS resolution
	run resolve_dns "$invalid_dns"
	assert_failure
}

# bats test_tags=category:high-risk,priority:high
@test "resolve_dns - DNS resolution failure handled gracefully" {
	# Purpose: Test that resolve_dns() handles DNS resolution failures gracefully
	# Expected: Function returns 1 and logs warning when DNS resolution fails
	# Importance: Error handling for DNS resolution failures (network issues, invalid hostname)
	local test_hostname="nonexistent.example.com"

	# Mock getent to fail, host to fail (no fallback)
	mock_getent "0" "" "$test_hostname"
	mock_host "0" "" "$test_hostname"
	add_mock_to_path

	# Test resolve_dns function
	run resolve_dns "$test_hostname"
	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "resolve_dns - fallback to host command when getent unavailable" {
	# Purpose: Test that resolve_dns() falls back to host command when getent is unavailable
	# Expected: Function succeeds using host command fallback
	# Importance: Ensures DNS resolution works on systems without getent
	local test_hostname="test.example.com"
	local expected_ip="10.0.0.5"

	# Mock getent to be unavailable (don't create it), host to succeed
	mock_host "1" "$expected_ip" "$test_hostname"
	add_mock_to_path

	# Test resolve_dns function
	run resolve_dns "$test_hostname"
	assert_success
	assert_output "$expected_ip"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "resolve_dns - empty input fails" {
	# Purpose: Test that resolve_dns() fails for empty input
	# Expected: Function returns 1
	# Importance: Input validation
	run resolve_dns ""
	assert_failure
}

# ============================================================================
# VALIDATE_IP_OR_DNS TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "validate_ip_or_dns - valid IP address succeeds" {
	# Purpose: Test that validate_ip_or_dns() accepts valid IP addresses
	# Expected: Function returns 0
	# Importance: Backward compatibility - IP addresses must still work
	run validate_ip_or_dns "192.168.1.1"
	assert_success
}

# bats test_tags=category:high-risk,priority:high
@test "validate_ip_or_dns - valid DNS name succeeds" {
	# Purpose: Test that validate_ip_or_dns() accepts valid DNS names
	# Expected: Function returns 0
	# Importance: Core functionality - DNS names must be accepted
	run validate_ip_or_dns "example.com"
	assert_success
}

# bats test_tags=category:high-risk,priority:high
@test "validate_ip_or_dns - invalid input fails" {
	# Purpose: Test that validate_ip_or_dns() rejects invalid input
	# Expected: Function returns 1
	# Importance: Input validation prevents configuration errors
	# Use a string that's clearly not a valid DNS name (starts with hyphen)
	run validate_ip_or_dns "-invalid.com"
	assert_failure
}

# bats test_tags=category:high-risk,priority:high
@test "validate_ip_or_dns - empty input fails" {
	# Purpose: Test that validate_ip_or_dns() fails for empty input
	# Expected: Function returns 1
	# Importance: Input validation
	run validate_ip_or_dns ""
	assert_failure
}
