#!/usr/bin/env bats
#
# Tests for escape_sed_replacement() function in lib/common.sh
# Tests string escaping functionality for sed replacement strings with comprehensive
# edge case coverage including backslashes, ampersands, pipes, custom delimiters,
# empty strings, and multi-line values

load test_helper

# Source the common library functions
# shellcheck source=../lib/common.sh
source "${BATS_TEST_DIRNAME}/../lib/common.sh"

# ============================================================================
# BASIC ESCAPING TESTS - DEFAULT DELIMITER (|)
# ============================================================================

# bats test_tags=category:unit,priority:high
@test "escape_sed_replacement: escapes backslash character" {
	# Purpose: Test that escape_sed_replacement escapes backslashes correctly
	# Expected: Backslash is escaped as double backslash
	# Importance: Backslashes must be escaped in sed replacement strings
	run escape_sed_replacement "test\\value"
	assert_success
	assert_output "test\\\\value"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_replacement: escapes ampersand character" {
	# Purpose: Test that escape_sed_replacement escapes ampersands correctly
	# Expected: Ampersand is escaped as backslash-ampersand
	# Importance: Ampersand represents matched text in sed replacement strings
	run escape_sed_replacement "test&value"
	assert_success
	assert_output "test\\&value"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_replacement: escapes pipe character" {
	# Purpose: Test that escape_sed_replacement escapes pipes correctly with default delimiter
	# Expected: Pipe is escaped as backslash-pipe
	# Importance: Pipe is the default delimiter and must be escaped in replacement strings
	run escape_sed_replacement "test|value"
	assert_success
	assert_output "test\\|value"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_replacement: escapes all special characters together" {
	# Purpose: Test that escape_sed_replacement handles multiple special characters correctly
	# Expected: All special characters (backslash, ampersand, pipe) are properly escaped
	# Importance: Real-world values often contain multiple special characters
	run escape_sed_replacement "test\\value&with|pipes"
	assert_success
	assert_output "test\\\\value\\&with\\|pipes"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_replacement: handles string with no special characters" {
	# Purpose: Test that escape_sed_replacement returns original string when no escaping needed
	# Expected: String is returned unchanged
	# Importance: Common case - most values don't need escaping
	run escape_sed_replacement "simple_value"
	assert_success
	assert_output "simple_value"
}

# bats test_tags=category:unit
@test "escape_sed_replacement: handles empty string" {
	# Purpose: Test that escape_sed_replacement handles empty string correctly
	# Expected: Returns empty string
	# Importance: Prevents errors when processing empty input
	run escape_sed_replacement ""
	assert_success
	assert_output ""
}

# bats test_tags=category:unit
@test "escape_sed_replacement: handles string with only special characters" {
	# Purpose: Test that escape_sed_replacement handles strings containing only special characters
	# Expected: All characters are properly escaped
	# Importance: Edge case for minimal input with special characters
	run escape_sed_replacement "\\&|"
	assert_success
	assert_output "\\\\\\&\\|"
}

# ============================================================================
# CUSTOM DELIMITER TESTS
# ============================================================================

# bats test_tags=category:unit,priority:high
@test "escape_sed_replacement: escapes custom delimiter (forward slash)" {
	# Purpose: Test that escape_sed_replacement escapes custom delimiter correctly
	# Expected: Forward slash is escaped as backslash-forward-slash
	# Importance: Custom delimiters are used to avoid conflicts with path separators
	run escape_sed_replacement "test/value" "/"
	assert_success
	assert_output "test\\/value"
}

# bats test_tags=category:unit
@test "escape_sed_replacement: escapes custom delimiter (hash)" {
	# Purpose: Test that escape_sed_replacement escapes hash delimiter correctly
	# Expected: Hash is escaped as backslash-hash
	# Importance: Hash is sometimes used as delimiter in sed commands
	run escape_sed_replacement "test#value" "#"
	assert_success
	assert_output "test\\#value"
}

# bats test_tags=category:unit
@test "escape_sed_replacement: escapes custom delimiter with other special chars" {
	# Purpose: Test that escape_sed_replacement handles custom delimiter with other special characters
	# Expected: Custom delimiter and other special chars are all properly escaped
	# Importance: Real-world values may contain multiple special characters with custom delimiter
	run escape_sed_replacement "test\\value&with/path" "/"
	assert_success
	assert_output "test\\\\value\\&with\\/path"
}

# bats test_tags=category:unit
@test "escape_sed_replacement: does not escape pipe when using custom delimiter" {
	# Purpose: Test that escape_sed_replacement only escapes the specified delimiter
	# Expected: Pipe is not escaped when using forward slash as delimiter
	# Importance: Only the delimiter character should be escaped, not other characters
	run escape_sed_replacement "test|value" "/"
	assert_success
	assert_output "test|value"
}

# ============================================================================
# MULTIPLE OCCURRENCES TESTS
# ============================================================================

# bats test_tags=category:unit
@test "escape_sed_replacement: escapes multiple occurrences of special characters" {
	# Purpose: Test that escape_sed_replacement escapes all occurrences of special characters, not just the first
	# Expected: All occurrences of backslashes, ampersands, and pipes are properly escaped
	# Importance: Values may contain multiple occurrences of special characters (e.g., IP lists, paths)
	# Test multiple backslashes
	run escape_sed_replacement "test\\value\\here"
	assert_success
	assert_output "test\\\\value\\\\here"

	# Test multiple ampersands
	run escape_sed_replacement "test&value&here"
	assert_success
	assert_output "test\\&value\\&here"

	# Test multiple pipes
	run escape_sed_replacement "test|value|here"
	assert_success
	assert_output "test\\|value\\|here"
}

# ============================================================================
# MULTI-LINE VALUES TESTS
# ============================================================================

# bats test_tags=category:unit
@test "escape_sed_replacement: handles multi-line values" {
	# Purpose: Test that escape_sed_replacement handles multi-line input correctly
	# Expected: Each line is processed and escaped correctly
	# Importance: Values may contain newlines (e.g., multi-line config values)
	local multiline_value
	multiline_value=$(printf 'line1\\value\nline2&value\nline3|value')
	run escape_sed_replacement "$multiline_value"
	assert_success
	assert_output "line1\\\\value
line2\\&value
line3\\|value"
}

# bats test_tags=category:unit
@test "escape_sed_replacement: handles value ending with newline" {
	# Purpose: Test that escape_sed_replacement handles trailing newline correctly
	# Expected: Trailing newline is preserved and content is escaped
	# Importance: Some values may end with newlines
	local value_with_newline
	value_with_newline=$(printf 'test\\value\n')
	run escape_sed_replacement "$value_with_newline"
	assert_success
	assert_output "test\\\\value"
}

# ============================================================================
# INTEGRATION TESTS - ACTUAL SED USAGE
# ============================================================================

# bats test_tags=category:unit,priority:high
@test "escape_sed_replacement: works correctly in sed replacement with default delimiter" {
	# Purpose: Test that escaped value works correctly in actual sed command
	# Expected: sed command succeeds and produces correct output
	# Importance: Verifies the escaping actually works in real-world usage
	local test_file="${TEST_DIR}/test_sed.txt"
	echo "VAR=old_value" >"$test_file"

	local escaped_value
	escaped_value=$(escape_sed_replacement "test|value&with\\backslash")
	sed -i "s|^VAR=.*|VAR=\"${escaped_value}\"|" "$test_file"

	assert_file_exist "$test_file"
	grep -q '^VAR="test|value&with\\backslash"$' "$test_file"
}

# bats test_tags=category:unit,priority:high
@test "escape_sed_replacement: works correctly in sed replacement with custom delimiter" {
	# Purpose: Test that escaped value works correctly in sed command with custom delimiter
	# Expected: sed command succeeds and produces correct output
	# Importance: Verifies custom delimiter escaping works in real-world usage
	local test_file="${TEST_DIR}/test_sed_custom.txt"
	echo "VAR=old_value" >"$test_file"

	local escaped_value
	escaped_value=$(escape_sed_replacement "test/value/here" "/")
	sed -i "s/^VAR=.*/VAR=\"${escaped_value}\"/" "$test_file"

	assert_file_exist "$test_file"
	grep -q '^VAR="test/value/here"$' "$test_file"
}

# bats test_tags=category:unit
@test "escape_sed_replacement: works with command substitution" {
	# Purpose: Test that escape_sed_replacement works correctly in command substitution context
	# Expected: Returns escaped value when used in variable assignment
	# Importance: Common usage pattern in scripts
	local result
	result=$(escape_sed_replacement "test\\value")
	assert [ "$result" == "test\\\\value" ]
}

# ============================================================================
# EDGE CASES AND CORNER CASES
# ============================================================================

# bats test_tags=category:unit
@test "escape_sed_replacement: handles edge cases with special characters" {
	# Purpose: Test that escape_sed_replacement handles various edge cases correctly
	# Expected: Special characters are properly escaped in edge cases (consecutive, boundaries, unicode, numeric)
	# Importance: Ensures function works correctly with real-world edge cases
	# Test consecutive special characters
	run escape_sed_replacement "test\\\\&&||"
	assert_success
	assert_output "test\\\\\\\\\\&\\&\\|\\|"

	# Test special characters at start and end (boundaries)
	run escape_sed_replacement "|test&value\\"
	assert_success
	assert_output "\\|test\\&value\\\\"

	# Test unicode characters with special characters
	run escape_sed_replacement "café\\test&value|here"
	assert_success
	assert_output "café\\\\test\\&value\\|here"

	# Test numeric values with special characters
	run escape_sed_replacement "192.168.1.1|10.0.0.1"
	assert_success
	assert_output "192.168.1.1\\|10.0.0.1"
}
