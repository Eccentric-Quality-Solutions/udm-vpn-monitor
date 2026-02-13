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
@test "validate_timestamp: accepts valid timestamps" {
	# Purpose: Test that validate_timestamp accepts various valid timestamps
	# Expected: Returns success (0) for all valid timestamps
	# Importance: Ensures function accepts valid inputs across the valid range
	# Test current timestamp
	run validate_timestamp "$CURRENT_TIMESTAMP"
	assert_success

	# Test zero (epoch start)
	run validate_timestamp "0"
	assert_success

	# Test maximum timestamp (year 2100)
	run validate_timestamp "$MAX_TIMESTAMP"
	assert_success

	# Test timestamp just below maximum
	local test_timestamp=$((MAX_TIMESTAMP - 1))
	run validate_timestamp "$test_timestamp"
	assert_success
}

# bats test_tags=category:unit
@test "validate_timestamp: rejects invalid input values" {
	# Purpose: Test that validate_timestamp rejects various invalid input formats
	# Expected: Returns failure (1) for all invalid inputs
	# Importance: Comprehensive validation ensures only valid timestamps are accepted
	# Test negative values
	run validate_timestamp "-1"
	assert_failure

	# Test timestamps exceeding maximum
	local test_timestamp=$((MAX_TIMESTAMP + 1))
	run validate_timestamp "$test_timestamp"
	assert_failure

	# Test very large values
	run validate_timestamp "99999999999"
	assert_failure

	# Test non-numeric strings
	run validate_timestamp "not_a_number"
	assert_failure

	# Test empty string
	run validate_timestamp ""
	assert_failure

	# Test decimal numbers
	run validate_timestamp "123.456"
	assert_failure

	# Test alphanumeric strings
	run validate_timestamp "123abc"
	assert_failure

	# Test strings with spaces
	run validate_timestamp "123 456"
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
@test "safe_timestamp_subtract: rejects invalid base timestamp" {
	# Purpose: Test that safe_timestamp_subtract rejects various invalid base timestamp formats
	# Expected: Returns failure (1) for all invalid base timestamp inputs
	# Importance: Ensures function validates base timestamp before processing
	# Test negative base timestamp
	run safe_timestamp_subtract "-1" "100"
	assert_failure

	# Test base timestamp exceeding maximum
	local invalid_timestamp=$((MAX_TIMESTAMP + 1))
	run safe_timestamp_subtract "$invalid_timestamp" "100"
	assert_failure

	# Test non-numeric base timestamp
	run safe_timestamp_subtract "not_a_number" "100"
	assert_failure

	# Test empty base timestamp
	run safe_timestamp_subtract "" "100"
	assert_failure
}

# bats test_tags=category:unit
@test "safe_timestamp_subtract: rejects invalid seconds parameter" {
	# Purpose: Test that safe_timestamp_subtract rejects various invalid seconds formats
	# Expected: Returns failure (2) for all invalid seconds inputs
	# Importance: Ensures function validates seconds parameter before processing
	# Test negative seconds
	run safe_timestamp_subtract "1000" "-1"
	assert_failure
	assert [ "$status" -eq 2 ]

	# Test non-numeric seconds
	run safe_timestamp_subtract "1000" "not_a_number"
	assert_failure
	assert [ "$status" -eq 2 ]

	# Test empty seconds
	run safe_timestamp_subtract "1000" ""
	assert_failure
	assert [ "$status" -eq 2 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_subtract: detects underflow" {
	# Purpose: Test that safe_timestamp_subtract detects underflow in various scenarios
	# Expected: Returns failure (3) when result would be negative
	# Importance: Prevents invalid negative timestamps
	# Test underflow with positive base
	run safe_timestamp_subtract "100" "200"
	assert_failure
	assert [ "$status" -eq 3 ]

	# Test underflow with zero base
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
@test "safe_timestamp_add: rejects invalid base timestamp" {
	# Purpose: Test that safe_timestamp_add rejects various invalid base timestamp formats
	# Expected: Returns failure (1) for all invalid base timestamp inputs
	# Importance: Ensures function validates base timestamp before processing
	# Test negative base timestamp
	run safe_timestamp_add "-1" "100"
	assert_failure

	# Test base timestamp exceeding maximum
	local invalid_timestamp=$((MAX_TIMESTAMP + 1))
	run safe_timestamp_add "$invalid_timestamp" "100"
	assert_failure

	# Test non-numeric base timestamp
	run safe_timestamp_add "not_a_number" "100"
	assert_failure

	# Test empty base timestamp
	run safe_timestamp_add "" "100"
	assert_failure
}

# bats test_tags=category:unit
@test "safe_timestamp_add: rejects invalid seconds parameter" {
	# Purpose: Test that safe_timestamp_add rejects various invalid seconds formats
	# Expected: Returns failure (2) for all invalid seconds inputs
	# Importance: Ensures function validates seconds parameter before processing
	# Test negative seconds
	run safe_timestamp_add "1000" "-1"
	assert_failure
	assert [ "$status" -eq 2 ]

	# Test non-numeric seconds
	run safe_timestamp_add "1000" "not_a_number"
	assert_failure
	assert [ "$status" -eq 2 ]

	# Test empty seconds
	run safe_timestamp_add "1000" ""
	assert_failure
	assert [ "$status" -eq 2 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_add: detects overflow" {
	# Purpose: Test that safe_timestamp_add detects overflow in various scenarios
	# Expected: Returns failure (3) when result exceeds maximum
	# Importance: Prevents invalid timestamps beyond maximum
	# Test overflow with large addition
	local base_timestamp=$((MAX_TIMESTAMP - 100))
	run safe_timestamp_add "$base_timestamp" "200"
	assert_failure
	assert [ "$status" -eq 3 ]

	# Test overflow at exact boundary
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
@test "safe_timestamp_diff: rejects invalid first timestamp" {
	# Purpose: Test that safe_timestamp_diff rejects various invalid first timestamp formats
	# Expected: Returns failure (1) for all invalid first timestamp inputs
	# Importance: Ensures function validates first timestamp before processing
	# Test negative first timestamp
	run safe_timestamp_diff "-1" "1000"
	assert_failure
	assert [ "$status" -eq 1 ]

	# Test first timestamp exceeding maximum
	local invalid_timestamp=$((MAX_TIMESTAMP + 1))
	run safe_timestamp_diff "$invalid_timestamp" "1000"
	assert_failure
	assert [ "$status" -eq 1 ]

	# Test non-numeric first timestamp
	run safe_timestamp_diff "not_a_number" "1000"
	assert_failure
	assert [ "$status" -eq 1 ]

	# Test empty first timestamp
	run safe_timestamp_diff "" "1000"
	assert_failure
	assert [ "$status" -eq 1 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_diff: rejects invalid second timestamp" {
	# Purpose: Test that safe_timestamp_diff rejects various invalid second timestamp formats
	# Expected: Returns failure (2) for all invalid second timestamp inputs
	# Importance: Ensures function validates second timestamp before processing
	# Test negative second timestamp
	run safe_timestamp_diff "1000" "-1"
	assert_failure
	assert [ "$status" -eq 2 ]

	# Test second timestamp exceeding maximum
	local invalid_timestamp=$((MAX_TIMESTAMP + 1))
	run safe_timestamp_diff "1000" "$invalid_timestamp"
	assert_failure
	assert [ "$status" -eq 2 ]

	# Test non-numeric second timestamp
	run safe_timestamp_diff "1000" "not_a_number"
	assert_failure
	assert [ "$status" -eq 2 ]

	# Test empty second timestamp
	run safe_timestamp_diff "1000" ""
	assert_failure
	assert [ "$status" -eq 2 ]
}

# bats test_tags=category:unit
@test "safe_timestamp_diff: handles very large differences" {
	# Purpose: Test that safe_timestamp_diff handles very large positive and negative differences
	# Expected: Returns success (0) and outputs correct large difference values
	# Importance: Ensures function works correctly with large timestamp differences
	# Test very large negative difference
	local timestamp1=1000
	local timestamp2=1000000
	run safe_timestamp_diff "$timestamp1" "$timestamp2"
	assert_success
	assert_output "-999000"

	# Test very large positive difference
	timestamp1=1000000
	timestamp2=1000
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
