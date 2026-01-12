#!/usr/bin/env bats
#
# Tests for Timestamp Functions in lib/common.sh
# Tests validate_timestamp(), safe_timestamp_subtract(), safe_timestamp_add(), and safe_timestamp_diff()
# with comprehensive edge case coverage including invalid inputs, overflow, underflow, and boundary conditions

load test_helper

# Source the common library functions
# shellcheck source=../lib/common.sh
source "${BATS_TEST_DIRNAME}/../lib/common.sh"

# Constants for testing
readonly MAX_TIMESTAMP=4102444800 # Year 2100
readonly CURRENT_TIMESTAMP=$(date +%s)

# ============================================================================
# VALIDATE_TIMESTAMP TESTS
# ============================================================================

# bats test_tags=category:unit
@test "validate_timestamp: accepts valid current timestamp" {
	# Purpose: Test that validate_timestamp accepts a valid current timestamp
	# Expected: Returns success (0) for valid timestamp
	run validate_timestamp "$CURRENT_TIMESTAMP"
	assert_success
}

# bats test_tags=category:unit
@test "validate_timestamp: accepts valid zero timestamp" {
	# Purpose: Test that validate_timestamp accepts zero (epoch start)
	# Expected: Returns success (0) for zero timestamp
	run validate_timestamp "0"
	assert_success
}

# bats test_tags=category:unit
@test "validate_timestamp: accepts valid maximum timestamp (year 2100)" {
	# Purpose: Test that validate_timestamp accepts the maximum allowed timestamp
	# Expected: Returns success (0) for maximum timestamp
	run validate_timestamp "$MAX_TIMESTAMP"
	assert_success
}

# bats test_tags=category:unit
@test "validate_timestamp: accepts valid timestamp just below maximum" {
	# Purpose: Test that validate_timestamp accepts timestamp just below maximum
	# Expected: Returns success (0) for timestamp one second before maximum
	local test_timestamp=$((MAX_TIMESTAMP - 1))
	run validate_timestamp "$test_timestamp"
	assert_success
}

# bats test_tags=category:unit
@test "validate_timestamp: rejects negative timestamp" {
	# Purpose: Test that validate_timestamp rejects negative values
	# Expected: Returns failure (1) for negative timestamp
	run validate_timestamp "-1"
	assert_failure
}

# bats test_tags=category:unit
@test "validate_timestamp: rejects timestamp exceeding maximum" {
	# Purpose: Test that validate_timestamp rejects timestamps beyond year 2100
	# Expected: Returns failure (1) for timestamp exceeding maximum
	local test_timestamp=$((MAX_TIMESTAMP + 1))
	run validate_timestamp "$test_timestamp"
	assert_failure
}

# bats test_tags=category:unit
@test "validate_timestamp: rejects very large timestamp" {
	# Purpose: Test that validate_timestamp rejects very large values
	# Expected: Returns failure (1) for very large timestamp
	run validate_timestamp "99999999999"
	assert_failure
}

# bats test_tags=category:unit
@test "validate_timestamp: rejects non-numeric string" {
	# Purpose: Test that validate_timestamp rejects non-numeric strings
	# Expected: Returns failure (1) for non-numeric input
	run validate_timestamp "not_a_number"
	assert_failure
}

# bats test_tags=category:unit
@test "validate_timestamp: rejects empty string" {
	# Purpose: Test that validate_timestamp rejects empty strings
	# Expected: Returns failure (1) for empty input
	run validate_timestamp ""
	assert_failure
}

# bats test_tags=category:unit
@test "validate_timestamp: accepts string with leading zeros" {
	# Purpose: Test that validate_timestamp accepts numeric strings (even with leading zeros)
	# Expected: Returns success (0) - bash arithmetic handles leading zeros
	# Note: "000123" is valid as bash treats it as octal, but regex ^[0-9]+ matches it
	run validate_timestamp "000123"
	assert_success
}

# bats test_tags=category:unit
@test "validate_timestamp: rejects decimal number" {
	# Purpose: Test that validate_timestamp rejects decimal numbers
	# Expected: Returns failure (1) for decimal input
	run validate_timestamp "123.456"
	assert_failure
}

# bats test_tags=category:unit
@test "validate_timestamp: rejects alphanumeric string" {
	# Purpose: Test that validate_timestamp rejects strings with letters and numbers
	# Expected: Returns failure (1) for alphanumeric input
	run validate_timestamp "123abc"
	assert_failure
}

# bats test_tags=category:unit
@test "validate_timestamp: rejects string with spaces" {
	# Purpose: Test that validate_timestamp rejects strings with spaces
	# Expected: Returns failure (1) for input with spaces
	run validate_timestamp "123 456"
	assert_failure
}

# ============================================================================
# SAFE_TIMESTAMP_SUBTRACT TESTS
# ============================================================================

# bats test_tags=category:unit
@test "safe_timestamp_subtract: subtracts valid seconds from valid timestamp" {
	# Purpose: Test that safe_timestamp_subtract correctly subtracts seconds
	# Expected: Returns success (0) and outputs correct result
	local base_timestamp=1000
	local seconds=100
	run safe_timestamp_subtract "$base_timestamp" "$seconds"
	assert_success
	assert_output "900"
}

# bats test_tags=category:unit
@test "safe_timestamp_subtract: handles subtraction resulting in zero" {
	# Purpose: Test that safe_timestamp_subtract handles subtraction to zero
	# Expected: Returns success (0) and outputs zero
	local base_timestamp=100
	local seconds=100
	run safe_timestamp_subtract "$base_timestamp" "$seconds"
	assert_success
	assert_output "0"
}

# bats test_tags=category:unit
@test "safe_timestamp_subtract: handles large valid subtraction" {
	# Purpose: Test that safe_timestamp_subtract handles large but valid subtractions
	# Expected: Returns success (0) and outputs correct result
	local base_timestamp=$((MAX_TIMESTAMP - 1000))
	local seconds=500
	run safe_timestamp_subtract "$base_timestamp" "$seconds"
	assert_success
	assert_output "$((MAX_TIMESTAMP - 1500))"
}

# bats test_tags=category:unit
@test "safe_timestamp_subtract: rejects invalid base timestamp (negative)" {
	# Purpose: Test that safe_timestamp_subtract rejects negative base timestamp
	# Expected: Returns failure (1) for invalid base timestamp
	run safe_timestamp_subtract "-1" "100"
	assert_failure
}

# bats test_tags=category:unit
@test "safe_timestamp_subtract: rejects invalid base timestamp (too large)" {
	# Purpose: Test that safe_timestamp_subtract rejects base timestamp exceeding maximum
	# Expected: Returns failure (1) for invalid base timestamp
	local invalid_timestamp=$((MAX_TIMESTAMP + 1))
	run safe_timestamp_subtract "$invalid_timestamp" "100"
	assert_failure
}

# bats test_tags=category:unit
@test "safe_timestamp_subtract: rejects invalid base timestamp (non-numeric)" {
	# Purpose: Test that safe_timestamp_subtract rejects non-numeric base timestamp
	# Expected: Returns failure (1) for invalid base timestamp
	run safe_timestamp_subtract "not_a_number" "100"
	assert_failure
}

# bats test_tags=category:unit
@test "safe_timestamp_subtract: rejects invalid base timestamp (empty)" {
	# Purpose: Test that safe_timestamp_subtract rejects empty base timestamp
	# Expected: Returns failure (1) for invalid base timestamp
	run safe_timestamp_subtract "" "100"
	assert_failure
}

# bats test_tags=category:unit
@test "safe_timestamp_subtract: rejects invalid seconds (negative)" {
	# Purpose: Test that safe_timestamp_subtract rejects negative seconds
	# Expected: Returns failure (2) for invalid seconds value
	run safe_timestamp_subtract "1000" "-1"
	assert_failure
	assert [ "$status" -eq 2 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_subtract: rejects invalid seconds (non-numeric)" {
	# Purpose: Test that safe_timestamp_subtract rejects non-numeric seconds
	# Expected: Returns failure (2) for invalid seconds value
	run safe_timestamp_subtract "1000" "not_a_number"
	assert_failure
	assert [ "$status" -eq 2 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_subtract: rejects invalid seconds (empty)" {
	# Purpose: Test that safe_timestamp_subtract rejects empty seconds
	# Expected: Returns failure (2) for invalid seconds value
	run safe_timestamp_subtract "1000" ""
	assert_failure
	assert [ "$status" -eq 2 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_subtract: detects underflow (result would be negative)" {
	# Purpose: Test that safe_timestamp_subtract detects underflow
	# Expected: Returns failure (3) when result would be negative
	run safe_timestamp_subtract "100" "200"
	assert_failure
	assert [ "$status" -eq 3 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_subtract: detects underflow with zero base" {
	# Purpose: Test that safe_timestamp_subtract detects underflow from zero
	# Expected: Returns failure (3) when subtracting from zero
	run safe_timestamp_subtract "0" "1"
	assert_failure
	assert [ "$status" -eq 3 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_subtract: handles subtraction of zero seconds" {
	# Purpose: Test that safe_timestamp_subtract handles subtracting zero
	# Expected: Returns success (0) and outputs original timestamp
	local base_timestamp=1000
	run safe_timestamp_subtract "$base_timestamp" "0"
	assert_success
	assert_output "1000"
}

# bats test_tags=category:unit
@test "safe_timestamp_subtract: validates result timestamp" {
	# Purpose: Test that safe_timestamp_subtract validates the result timestamp
	# Expected: Returns failure (1) if result exceeds maximum
	# Note: This is a boundary case where result might exceed max
	local base_timestamp=$MAX_TIMESTAMP
	local seconds=1
	run safe_timestamp_subtract "$base_timestamp" "$seconds"
	# Result should be valid (MAX_TIMESTAMP - 1)
	assert_success
	assert_output "$((MAX_TIMESTAMP - 1))"
}

# ============================================================================
# SAFE_TIMESTAMP_ADD TESTS
# ============================================================================

# bats test_tags=category:unit
@test "safe_timestamp_add: adds valid seconds to valid timestamp" {
	# Purpose: Test that safe_timestamp_add correctly adds seconds
	# Expected: Returns success (0) and outputs correct result
	local base_timestamp=1000
	local seconds=100
	run safe_timestamp_add "$base_timestamp" "$seconds"
	assert_success
	assert_output "1100"
}

# bats test_tags=category:unit
@test "safe_timestamp_add: handles addition of zero seconds" {
	# Purpose: Test that safe_timestamp_add handles adding zero
	# Expected: Returns success (0) and outputs original timestamp
	local base_timestamp=1000
	run safe_timestamp_add "$base_timestamp" "0"
	assert_success
	assert_output "1000"
}

# bats test_tags=category:unit
@test "safe_timestamp_add: handles large valid addition" {
	# Purpose: Test that safe_timestamp_add handles large but valid additions
	# Expected: Returns success (0) and outputs correct result
	local base_timestamp=1000
	local seconds=1000
	run safe_timestamp_add "$base_timestamp" "$seconds"
	assert_success
	assert_output "2000"
}

# bats test_tags=category:unit
@test "safe_timestamp_add: handles addition near maximum boundary" {
	# Purpose: Test that safe_timestamp_add handles addition near maximum
	# Expected: Returns success (0) if result is within bounds
	local base_timestamp=$((MAX_TIMESTAMP - 1000))
	local seconds=500
	run safe_timestamp_add "$base_timestamp" "$seconds"
	assert_success
	assert_output "$((MAX_TIMESTAMP - 500))"
}

# bats test_tags=category:unit
@test "safe_timestamp_add: rejects invalid base timestamp (negative)" {
	# Purpose: Test that safe_timestamp_add rejects negative base timestamp
	# Expected: Returns failure (1) for invalid base timestamp
	run safe_timestamp_add "-1" "100"
	assert_failure
}

# bats test_tags=category:unit
@test "safe_timestamp_add: rejects invalid base timestamp (too large)" {
	# Purpose: Test that safe_timestamp_add rejects base timestamp exceeding maximum
	# Expected: Returns failure (1) for invalid base timestamp
	local invalid_timestamp=$((MAX_TIMESTAMP + 1))
	run safe_timestamp_add "$invalid_timestamp" "100"
	assert_failure
}

# bats test_tags=category:unit
@test "safe_timestamp_add: rejects invalid base timestamp (non-numeric)" {
	# Purpose: Test that safe_timestamp_add rejects non-numeric base timestamp
	# Expected: Returns failure (1) for invalid base timestamp
	run safe_timestamp_add "not_a_number" "100"
	assert_failure
}

# bats test_tags=category:unit
@test "safe_timestamp_add: rejects invalid base timestamp (empty)" {
	# Purpose: Test that safe_timestamp_add rejects empty base timestamp
	# Expected: Returns failure (1) for invalid base timestamp
	run safe_timestamp_add "" "100"
	assert_failure
}

# bats test_tags=category:unit
@test "safe_timestamp_add: rejects invalid seconds (negative)" {
	# Purpose: Test that safe_timestamp_add rejects negative seconds
	# Expected: Returns failure (2) for invalid seconds value
	run safe_timestamp_add "1000" "-1"
	assert_failure
	assert [ "$status" -eq 2 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_add: rejects invalid seconds (non-numeric)" {
	# Purpose: Test that safe_timestamp_add rejects non-numeric seconds
	# Expected: Returns failure (2) for invalid seconds value
	run safe_timestamp_add "1000" "not_a_number"
	assert_failure
	assert [ "$status" -eq 2 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_add: rejects invalid seconds (empty)" {
	# Purpose: Test that safe_timestamp_add rejects empty seconds
	# Expected: Returns failure (2) for invalid seconds value
	run safe_timestamp_add "1000" ""
	assert_failure
	assert [ "$status" -eq 2 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_add: detects overflow with large addition" {
	# Purpose: Test that safe_timestamp_add detects overflow with large addition
	# Expected: Returns failure (3) when result exceeds maximum
	local base_timestamp=$((MAX_TIMESTAMP - 100))
	run safe_timestamp_add "$base_timestamp" "200"
	assert_failure
	assert [ "$status" -eq 3 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_add: detects overflow at exact boundary" {
	# Purpose: Test that safe_timestamp_add detects overflow at exact boundary
	# Expected: Returns failure (3) when adding 1 to maximum
	run safe_timestamp_add "$MAX_TIMESTAMP" "1"
	assert_failure
	assert [ "$status" -eq 3 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_add: handles addition at maximum boundary" {
	# Purpose: Test that safe_timestamp_add handles addition at maximum boundary
	# Expected: Returns success (0) if result equals maximum
	# Note: This should fail because MAX_TIMESTAMP + 0 = MAX_TIMESTAMP, which is valid
	run safe_timestamp_add "$MAX_TIMESTAMP" "0"
	assert_success
	assert_output "$MAX_TIMESTAMP"
}

# ============================================================================
# SAFE_TIMESTAMP_DIFF TESTS
# ============================================================================

# bats test_tags=category:unit
@test "safe_timestamp_diff: calculates positive difference correctly" {
	# Purpose: Test that safe_timestamp_diff calculates positive difference
	# Expected: Returns success (0) and outputs positive difference
	local timestamp1=2000
	local timestamp2=1000
	run safe_timestamp_diff "$timestamp1" "$timestamp2"
	assert_success
	assert_output "1000"
}

# bats test_tags=category:unit
@test "safe_timestamp_diff: calculates negative difference correctly" {
	# Purpose: Test that safe_timestamp_diff calculates negative difference
	# Expected: Returns success (0) and outputs negative difference
	local timestamp1=1000
	local timestamp2=2000
	run safe_timestamp_diff "$timestamp1" "$timestamp2"
	assert_success
	assert_output "-1000"
}

# bats test_tags=category:unit
@test "safe_timestamp_diff: calculates zero difference correctly" {
	# Purpose: Test that safe_timestamp_diff calculates zero difference
	# Expected: Returns success (0) and outputs zero
	local timestamp=1000
	run safe_timestamp_diff "$timestamp" "$timestamp"
	assert_success
	assert_output "0"
}

# bats test_tags=category:unit
@test "safe_timestamp_diff: handles large timestamps" {
	# Purpose: Test that safe_timestamp_diff handles large valid timestamps
	# Expected: Returns success (0) and outputs correct difference
	local timestamp1=$MAX_TIMESTAMP
	local timestamp2=$((MAX_TIMESTAMP - 1000))
	run safe_timestamp_diff "$timestamp1" "$timestamp2"
	assert_success
	assert_output "1000"
}

# bats test_tags=category:unit
@test "safe_timestamp_diff: handles zero timestamps" {
	# Purpose: Test that safe_timestamp_diff handles zero timestamps
	# Expected: Returns success (0) and outputs zero
	run safe_timestamp_diff "0" "0"
	assert_success
	assert_output "0"
}

# bats test_tags=category:unit
@test "safe_timestamp_diff: rejects invalid first timestamp (negative)" {
	# Purpose: Test that safe_timestamp_diff rejects negative first timestamp
	# Expected: Returns failure (1) for invalid first timestamp
	run safe_timestamp_diff "-1" "1000"
	assert_failure
	assert [ "$status" -eq 1 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_diff: rejects invalid first timestamp (too large)" {
	# Purpose: Test that safe_timestamp_diff rejects first timestamp exceeding maximum
	# Expected: Returns failure (1) for invalid first timestamp
	local invalid_timestamp=$((MAX_TIMESTAMP + 1))
	run safe_timestamp_diff "$invalid_timestamp" "1000"
	assert_failure
	assert [ "$status" -eq 1 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_diff: rejects invalid first timestamp (non-numeric)" {
	# Purpose: Test that safe_timestamp_diff rejects non-numeric first timestamp
	# Expected: Returns failure (1) for invalid first timestamp
	run safe_timestamp_diff "not_a_number" "1000"
	assert_failure
	assert [ "$status" -eq 1 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_diff: rejects invalid first timestamp (empty)" {
	# Purpose: Test that safe_timestamp_diff rejects empty first timestamp
	# Expected: Returns failure (1) for invalid first timestamp
	run safe_timestamp_diff "" "1000"
	assert_failure
	assert [ "$status" -eq 1 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_diff: rejects invalid second timestamp (negative)" {
	# Purpose: Test that safe_timestamp_diff rejects negative second timestamp
	# Expected: Returns failure (2) for invalid second timestamp
	run safe_timestamp_diff "1000" "-1"
	assert_failure
	assert [ "$status" -eq 2 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_diff: rejects invalid second timestamp (too large)" {
	# Purpose: Test that safe_timestamp_diff rejects second timestamp exceeding maximum
	# Expected: Returns failure (2) for invalid second timestamp
	local invalid_timestamp=$((MAX_TIMESTAMP + 1))
	run safe_timestamp_diff "1000" "$invalid_timestamp"
	assert_failure
	assert [ "$status" -eq 2 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_diff: rejects invalid second timestamp (non-numeric)" {
	# Purpose: Test that safe_timestamp_diff rejects non-numeric second timestamp
	# Expected: Returns failure (2) for invalid second timestamp
	run safe_timestamp_diff "1000" "not_a_number"
	assert_failure
	assert [ "$status" -eq 2 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_diff: rejects invalid second timestamp (empty)" {
	# Purpose: Test that safe_timestamp_diff rejects empty second timestamp
	# Expected: Returns failure (2) for invalid second timestamp
	run safe_timestamp_diff "1000" ""
	assert_failure
	assert [ "$status" -eq 2 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_diff: handles very large negative difference" {
	# Purpose: Test that safe_timestamp_diff handles very large negative differences
	# Expected: Returns success (0) and outputs large negative value
	local timestamp1=1000
	local timestamp2=1000000
	run safe_timestamp_diff "$timestamp1" "$timestamp2"
	assert_success
	assert_output "-999000"
}

# bats test_tags=category:unit
@test "safe_timestamp_diff: handles very large positive difference" {
	# Purpose: Test that safe_timestamp_diff handles very large positive differences
	# Expected: Returns success (0) and outputs large positive value
	local timestamp1=1000000
	local timestamp2=1000
	run safe_timestamp_diff "$timestamp1" "$timestamp2"
	assert_success
	assert_output "999000"
}

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

# bats test_tags=category:unit
@test "timestamp functions: integration - chain operations correctly" {
	# Purpose: Test that timestamp functions work together correctly
	# Expected: Operations can be chained and produce correct results
	local base_timestamp=1000

	# Add seconds, then subtract, then calculate difference
	local added
	added=$(safe_timestamp_add "$base_timestamp" "500")
	assert [ "$added" -eq 1500 ]

	local subtracted
	subtracted=$(safe_timestamp_subtract "$added" "300")
	assert [ "$subtracted" -eq 1200 ]

	local diff
	diff=$(safe_timestamp_diff "$subtracted" "$base_timestamp")
	assert [ "$diff" -eq 200 ]
}

# bats test_tags=category:unit
@test "timestamp functions: integration - validate before operations" {
	# Purpose: Test that validate_timestamp works with other functions
	# Expected: validate_timestamp correctly identifies valid/invalid timestamps for operations
	local valid_timestamp=1000
	local invalid_timestamp=$((MAX_TIMESTAMP + 1))

	# Valid timestamp should work with all operations
	run validate_timestamp "$valid_timestamp"
	assert_success

	run safe_timestamp_add "$valid_timestamp" "100"
	assert_success

	# Invalid timestamp should fail validation
	run validate_timestamp "$invalid_timestamp"
	assert_failure

	run safe_timestamp_add "$invalid_timestamp" "100"
	assert_failure
}
