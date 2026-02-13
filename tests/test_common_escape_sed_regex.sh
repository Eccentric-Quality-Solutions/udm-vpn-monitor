#!/usr/bin/env bats
#
# Tests for escape_sed_regex() function in lib/common.sh
# Tests string escaping functionality for sed regex patterns with comprehensive
# edge case coverage including all regex metacharacters, empty strings, and
# multi-line values

load test_helper
load helpers/assertions

# Source the common library functions
# shellcheck source=../lib/common.sh
source "${BATS_TEST_DIRNAME}/../lib/common.sh"

# ============================================================================
# BASIC ESCAPING TESTS - REGEX METACHARACTERS
# ============================================================================

# bats test_tags=category:unit,priority:high
@test "escape_sed_regex: escapes left square bracket" {
	# Purpose: Test that escape_sed_regex escapes left square bracket correctly
	# Expected: Left square bracket is escaped as backslash-left-square-bracket
	# Importance: Square brackets are regex metacharacters for character classes
	run escape_sed_regex "test[value"
	assert_success
	assert_output "test\\[value"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_regex: escapes backslash" {
	# Purpose: Test that escape_sed_regex escapes backslashes correctly
	# Expected: Backslash is escaped as double backslash
	# Importance: Backslashes are escape characters in regex
	run escape_sed_regex "test\\value"
	assert_success
	assert_output "test\\\\value"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_regex: escapes dot" {
	# Purpose: Test that escape_sed_regex escapes dots correctly
	# Expected: Dot is escaped as backslash-dot
	# Importance: Dot matches any character in regex
	run escape_sed_regex "test.value"
	assert_success
	assert_output "test\\.value"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_regex: escapes asterisk" {
	# Purpose: Test that escape_sed_regex escapes asterisks correctly
	# Expected: Asterisk is escaped as backslash-asterisk
	# Importance: Asterisk is quantifier in regex (zero or more)
	run escape_sed_regex "test*value"
	assert_success
	assert_output "test\\*value"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_regex: escapes caret" {
	# Purpose: Test that escape_sed_regex escapes carets correctly
	# Expected: Caret is escaped as backslash-caret
	# Importance: Caret matches start of line in regex
	run escape_sed_regex "test^value"
	assert_success
	assert_output "test\\^value"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_regex: escapes dollar sign" {
	# Purpose: Test that escape_sed_regex escapes dollar signs correctly
	# Expected: Dollar sign is escaped as backslash-dollar-sign
	# Importance: Dollar sign matches end of line in regex
	run escape_sed_regex "test\$value"
	assert_success
	assert_output "test\\\$value"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_regex: escapes left parenthesis" {
	# Purpose: Test that escape_sed_regex escapes left parentheses correctly
	# Expected: Left parenthesis is escaped as backslash-left-parenthesis
	# Importance: Parentheses are grouping operators in regex
	run escape_sed_regex "test(value"
	assert_success
	assert_output "test\\(value"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_regex: escapes right parenthesis" {
	# Purpose: Test that escape_sed_regex escapes right parentheses correctly
	# Expected: Right parenthesis is escaped as backslash-right-parenthesis
	# Importance: Parentheses are grouping operators in regex
	run escape_sed_regex "test)value"
	assert_success
	assert_output "test\\)value"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_regex: escapes plus sign" {
	# Purpose: Test that escape_sed_regex escapes plus signs correctly
	# Expected: Plus sign is escaped as backslash-plus-sign
	# Importance: Plus sign is quantifier in regex (one or more)
	run escape_sed_regex "test+value"
	assert_success
	assert_output "test\\+value"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_regex: escapes question mark" {
	# Purpose: Test that escape_sed_regex escapes question marks correctly
	# Expected: Question mark is escaped as backslash-question-mark
	# Importance: Question mark is quantifier in regex (zero or one)
	run escape_sed_regex "test?value"
	assert_success
	assert_output "test\\?value"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_regex: escapes left curly brace" {
	# Purpose: Test that escape_sed_regex escapes left curly braces correctly
	# Expected: Left curly brace is escaped as backslash-left-curly-brace
	# Importance: Curly braces are quantifiers in regex
	run escape_sed_regex "test{value"
	assert_success
	assert_output "test\\{value"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_regex: escapes pipe" {
	# Purpose: Test that escape_sed_regex escapes pipes correctly
	# Expected: Pipe is escaped as backslash-pipe
	# Importance: Pipe is alternation operator in regex
	run escape_sed_regex "test|value"
	assert_success
	assert_output "test\\|value"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_regex: escapes all regex metacharacters together" {
	# Purpose: Test that escape_sed_regex handles multiple regex metacharacters correctly
	# Expected: All regex metacharacters are properly escaped
	# Importance: Real-world values often contain multiple regex metacharacters
	run escape_sed_regex "test[.\\*^\$()+?{|value"
	assert_success
	assert_output "test\\[\\.\\\\\\*\\^\\$\\(\\)\\+\\?\\{\\|value"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_regex: handles string with no special characters" {
	# Purpose: Test that escape_sed_regex returns original string when no escaping needed
	# Expected: String is returned unchanged
	# Importance: Common case - most values don't need escaping
	run escape_sed_regex "simple_value"
	assert_success
	assert_output "simple_value"
}

# bats test_tags=category:unit
@test "escape_sed_regex: handles empty string" {
	# Purpose: Test that escape_sed_regex handles empty string correctly
	# Expected: Returns empty string
	# Importance: Prevents errors when processing empty input
	test_empty_string "escape_sed_regex"
}

# bats test_tags=category:unit
@test "escape_sed_regex: handles string with only regex metacharacters" {
	# Purpose: Test that escape_sed_regex handles strings containing only regex metacharacters
	# Expected: All characters are properly escaped
	# Importance: Edge case for minimal input with special characters
	run escape_sed_regex "[.\\*^\$()+?{|"
	assert_success
	assert_output "\\[\\.\\\\\\*\\^\\$\\(\\)\\+\\?\\{\\|"
}

# ============================================================================
# MULTIPLE OCCURRENCES TESTS
# ============================================================================

# bats test_tags=category:unit
@test "escape_sed_regex: escapes multiple dots" {
	# Purpose: Test that escape_sed_regex escapes all occurrences of dots
	# Expected: All dots are escaped, not just the first one
	# Importance: Values may contain multiple dots (e.g., IP addresses)
	run escape_sed_regex "192.168.1.1"
	assert_success
	assert_output "192\\.168\\.1\\.1"
}

# bats test_tags=category:unit
@test "escape_sed_regex: escapes multiple asterisks" {
	# Purpose: Test that escape_sed_regex escapes all occurrences of asterisks
	# Expected: All asterisks are escaped, not just the first one
	# Importance: Values may contain multiple asterisks
	run escape_sed_regex "test*value*here"
	assert_success
	assert_output "test\\*value\\*here"
}

# bats test_tags=category:unit
@test "escape_sed_regex: escapes multiple parentheses" {
	# Purpose: Test that escape_sed_regex escapes all occurrences of parentheses
	# Expected: All parentheses are escaped, not just the first one
	# Importance: Values may contain multiple parentheses
	run escape_sed_regex "test(value)here"
	assert_success
	assert_output "test\\(value\\)here"
}

# ============================================================================
# MULTI-LINE VALUES TESTS
# ============================================================================

# bats test_tags=category:unit
@test "escape_sed_regex: handles multi-line values" {
	# Purpose: Test that escape_sed_regex handles multi-line input correctly
	# Expected: Each line is processed and escaped correctly
	# Importance: Values may contain newlines (e.g., multi-line config values)
	local multiline_value
	multiline_value=$(printf 'line1.value\nline2*value\nline3^value')
	run escape_sed_regex "$multiline_value"
	assert_success
	assert_output "line1\\.value
line2\\*value
line3\\^value"
}

# bats test_tags=category:unit
@test "escape_sed_regex: handles value ending with newline" {
	# Purpose: Test that escape_sed_regex handles trailing newline correctly
	# Expected: Trailing newline is preserved and content is escaped
	# Importance: Some values may end with newlines
	local value_with_newline
	value_with_newline=$(printf 'test.value\n')
	run escape_sed_regex "$value_with_newline"
	assert_success
	assert_output "test\\.value"
}

# ============================================================================
# INTEGRATION TESTS - ACTUAL SED USAGE
# ============================================================================

# bats test_tags=category:unit,priority:high
@test "escape_sed_regex: works correctly in sed pattern matching" {
	# Purpose: Test that escaped value works correctly in actual sed command
	# Expected: sed command succeeds and matches literal string
	# Importance: Verifies the escaping actually works in real-world usage
	local test_file="${TEST_DIR}/test_sed_regex.txt"
	echo "VAR=test.value" >"$test_file"
	echo "VAR2=other_value" >>"$test_file"

	local escaped_pattern
	escaped_pattern=$(escape_sed_regex "test.value")
	sed -i "/^VAR=${escaped_pattern}/d" "$test_file"

	assert_file_exist "$test_file"
	# VAR=test.value should be deleted
	run grep -q '^VAR=test\.value$' "$test_file"
	assert_failure
	# VAR2 should remain
	grep -q '^VAR2=other_value$' "$test_file"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_regex: prevents regex interpretation in sed pattern" {
	# Purpose: Test that escaped value prevents regex interpretation in sed
	# Expected: sed matches literal string, not regex pattern
	# Importance: Verifies escaping prevents unintended regex matching
	local test_file="${TEST_DIR}/test_sed_regex_literal.txt"
	echo "VAR=test.value" >"$test_file"
	echo "VAR2=testXvalue" >>"$test_file"

	local escaped_pattern
	escaped_pattern=$(escape_sed_regex "test.value")
	# Should only match literal "test.value", not "testXvalue"
	sed -i "s|^VAR=${escaped_pattern}|VAR=replaced|" "$test_file"

	assert_file_exist "$test_file"
	grep -q '^VAR=replaced$' "$test_file"
	# VAR2 should remain unchanged (not matched by regex)
	grep -q '^VAR2=testXvalue$' "$test_file"
}

# ============================================================================
# EDGE CASES AND CORNER CASES
# ============================================================================

# bats test_tags=category:unit
@test "escape_sed_regex: handles consecutive regex metacharacters" {
	# Purpose: Test that escape_sed_regex handles consecutive regex metacharacters correctly
	# Expected: All consecutive metacharacters are properly escaped
	# Importance: Edge case where metacharacters appear together
	run escape_sed_regex "test..**++"
	assert_success
	assert_output "test\\.\\.\\*\\*\\+\\+"
}

# bats test_tags=category:unit
@test "escape_sed_regex: handles regex metacharacters at start and end" {
	# Purpose: Test that escape_sed_regex handles regex metacharacters at boundaries
	# Expected: Metacharacters at start and end are properly escaped
	# Importance: Edge case for boundary conditions
	run escape_sed_regex "^test.value\$"
	assert_success
	assert_output "\\^test\\.value\\\$"
}

# bats test_tags=category:unit
@test "escape_sed_regex: handles unicode and regex metacharacters together" {
	# Purpose: Test that escape_sed_regex works with unicode characters
	# Expected: Unicode characters are preserved, metacharacters are escaped
	# Importance: Ensures function works with international characters
	run escape_sed_regex "café.test*value"
	assert_success
	assert_output "café\\.test\\*value"
}

# bats test_tags=category:unit
@test "escape_sed_regex: handles IP addresses correctly" {
	# Purpose: Test that escape_sed_regex handles IP addresses correctly
	# Expected: Dots in IP addresses are escaped
	# Importance: IP addresses are common in config values
	run escape_sed_regex "192.168.1.1"
	assert_success
	assert_output "192\\.168\\.1\\.1"
}

# bats test_tags=category:unit
@test "escape_sed_regex: handles file paths correctly" {
	# Purpose: Test that escape_sed_regex handles file paths correctly
	# Expected: Dots and other metacharacters in paths are escaped
	# Importance: File paths are common in config values
	run escape_sed_regex "/path/to/file.conf"
	assert_success
	assert_output "/path/to/file\\.conf"
}
