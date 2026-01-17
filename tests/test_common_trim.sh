#!/usr/bin/env bats
#
# Tests for trim() function in lib/common.sh
# Tests string trimming functionality with comprehensive edge case coverage
# including empty strings, whitespace-only strings, various whitespace characters,
# and strings with no trimming needed

load test_helper

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
	run trim ""
	assert_success
	assert_output ""
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
@test "trim: handles string with no trimming needed" {
	# Purpose: Test that trim works correctly when no trimming is needed
	# Expected: Returns original string unchanged
	# Importance: Ensures function doesn't modify strings unnecessarily
	run trim "hello"
	assert_success
	assert_output "hello"
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
@test "trim: handles tabs" {
	# Purpose: Test that trim removes leading and trailing tabs
	# Expected: Returns string with tabs removed from both ends
	# Importance: Tabs are common whitespace characters
	run trim $'\t'hello$'\t'
	assert_success
	assert_output "hello"
}

# bats test_tags=category:unit
@test "trim: handles newlines" {
	# Purpose: Test that trim removes leading and trailing newlines
	# Expected: Returns string with newlines removed from both ends
	# Importance: Newlines are common when processing file input
	run trim $'\n'hello$'\n'
	assert_success
	assert_output "hello"
}

# bats test_tags=category:unit
@test "trim: handles mixed whitespace characters" {
	# Purpose: Test that trim handles combination of spaces, tabs, and newlines
	# Expected: Returns string with all leading/trailing whitespace removed
	# Importance: Real-world input often contains mixed whitespace
	run trim $'\t\n 'hello$' \n\t'
	assert_success
	assert_output "hello"
}

# bats test_tags=category:unit
@test "trim: handles carriage returns" {
	# Purpose: Test that trim removes carriage returns
	# Expected: Returns string with carriage returns removed
	# Importance: Windows-style line endings contain carriage returns
	run trim $'\r'hello$'\r'
	assert_success
	assert_output "hello"
}

# ============================================================================
# EDGE CASES
# ============================================================================

# bats test_tags=category:unit
@test "trim: handles string with only leading whitespace" {
	# Purpose: Test that trim removes only leading whitespace when no trailing whitespace
	# Expected: Returns string with leading whitespace removed
	# Importance: Common case when processing left-aligned text
	run trim "  hello"
	assert_success
	assert_output "hello"
}

# bats test_tags=category:unit
@test "trim: handles string with only trailing whitespace" {
	# Purpose: Test that trim removes only trailing whitespace when no leading whitespace
	# Expected: Returns string with trailing whitespace removed
	# Importance: Common case when processing right-aligned text
	run trim "hello  "
	assert_success
	assert_output "hello"
}

# bats test_tags=category:unit
@test "trim: handles string with multiple consecutive spaces" {
	# Purpose: Test that trim removes all leading/trailing spaces, not just one
	# Expected: Returns string with all leading/trailing spaces removed
	# Importance: Ensures function removes all whitespace, not just first/last character
	run trim "     hello     "
	assert_success
	assert_output "hello"
}

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
@test "trim: works with command substitution" {
	# Purpose: Test that trim works correctly in command substitution context
	# Expected: Returns trimmed value when used in variable assignment
	# Importance: Common usage pattern in scripts
	local result
	result=$(trim "  test  ")
	assert [ "$result" == "test" ]
}

# bats test_tags=category:unit
@test "trim: works with empty result" {
	# Purpose: Test that trim works correctly when result is empty
	# Expected: Returns empty string that can be checked with -z
	# Importance: Common pattern: if [[ -z "$(trim "$input")" ]]; then
	local result
	result=$(trim "   ")
	assert [ -z "$result" ]
}

# bats test_tags=category:unit
@test "trim: preserves function return code" {
	# Purpose: Test that trim always returns success (0)
	# Expected: Function returns 0 even for edge cases
	# Importance: Ensures function doesn't fail unexpectedly
	run trim ""
	assert_success

	run trim "   "
	assert_success

	run trim "test"
	assert_success
}
