#!/usr/bin/env bats
#
# Tests for trim() function in lib/common.sh
# Tests string trimming functionality with comprehensive edge case coverage
# including empty strings, whitespace-only strings, various whitespace characters,
# and strings with no trimming needed

load test_helper
load helpers/assertions

# Source the common library functions
# shellcheck source=../lib/common.sh
source "${BATS_TEST_DIRNAME}/../lib/common.sh"

# ============================================================================
# BASIC TRIM TESTS
# ============================================================================

# bats test_tags=category:unit
@test "trim: trims leading and trailing whitespace" {
	# Purpose: Test that trim removes leading and trailing spaces
	# Expected: Returns string with spaces removed from both ends
	# Importance: Core functionality - most common use case
	run trim "  hello world  "
	assert_success
	assert_output "hello world"
}

# bats test_tags=category:unit
@test "trim: handles empty string" {
	# Purpose: Test that trim handles empty string correctly
	# Expected: Returns empty string
	# Importance: Prevents errors when processing empty input
	test_empty_string "trim"
}

# bats test_tags=category:unit
@test "trim: handles whitespace-only string" {
	# Purpose: Test that trim returns empty string for whitespace-only input
	# Expected: Returns empty string when input is only whitespace
	# Importance: Common edge case when processing user input
	run trim "   "
	assert_success
	assert_output ""
}

# bats test_tags=category:unit
@test "trim: preserves internal spaces" {
	# Purpose: Test that trim only removes leading/trailing whitespace, not internal
	# Expected: Internal spaces are preserved
	# Importance: Ensures function doesn't modify string content incorrectly
	run trim "  hello  world  "
	assert_success
	assert_output "hello  world"
}

# bats test_tags=category:unit
@test "trim: handles single character with and without whitespace" {
	# Purpose: Test that trim works with single character strings, both with and without whitespace
	# Expected: Returns single character correctly, removing whitespace when present
	# Importance: Edge case for minimal input
	run trim "a"
	assert_success
	assert_output "a"

	run trim "  a  "
	assert_success
	assert_output "a"
}

# ============================================================================
# WHITESPACE CHARACTER TESTS
# ============================================================================

# bats test_tags=category:unit
@test "trim: handles various whitespace characters and patterns" {
	# Purpose: Test that trim removes leading and trailing whitespace including tabs, newlines, carriage returns, mixed combinations, and multiple consecutive spaces
	# Expected: Returns string with all types of whitespace removed from both ends
	# Importance: Real-world input contains various whitespace characters and patterns
	# Test tabs
	run trim $'\t'hello$'\t'
	assert_success
	assert_output "hello"

	# Test newlines
	run trim $'\n'hello$'\n'
	assert_success
	assert_output "hello"

	# Test carriage returns
	run trim $'\r'hello$'\r'
	assert_success
	assert_output "hello"

	# Test mixed whitespace (spaces, tabs, newlines)
	run trim $'\t\n 'hello$' \n\t'
	assert_success
	assert_output "hello"

	# Test multiple consecutive spaces
	run trim "     hello     "
	assert_success
	assert_output "hello"

	# Test leading-only whitespace
	run trim "  hello"
	assert_success
	assert_output "hello"

	# Test trailing-only whitespace
	run trim "hello  "
	assert_success
	assert_output "hello"
}

# ============================================================================
# EDGE CASES
# ============================================================================

# bats test_tags=category:unit
@test "trim: handles string starting and ending with same character" {
	# Purpose: Test that trim doesn't incorrectly remove content when first/last char is same
	# Expected: Returns string correctly trimmed
	# Importance: Edge case where content character might be confused with whitespace
	run trim "  aaa  "
	assert_success
	assert_output "aaa"
}

# bats test_tags=category:unit
@test "trim: handles strings with unicode, numbers, and special characters" {
	# Purpose: Test that trim works with various content types (unicode, numbers, special chars)
	# Expected: Returns string with whitespace removed, content preserved
	# Importance: Ensures function works with international characters, numeric input, and special characters
	run trim "  café  "
	assert_success
	assert_output "café"

	run trim "  123  "
	assert_success
	assert_output "123"

	run trim "  hello@world#123  "
	assert_success
	assert_output "hello@world#123"
}

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

# bats test_tags=category:unit
@test "trim: works with empty result" {
	# Purpose: Test that trim works correctly when result is empty
	# Expected: Returns empty string that can be checked with -z
	# Importance: Common pattern: if [[ -z "$(trim "$input")" ]]; then
	local result
	result=$(trim "   ")
	assert [ -z "$result" ]
}
