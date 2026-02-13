#!/usr/bin/env bats
#
# Tests for safe_set_variable() function in lib/common.sh
# Tests variable name validation, safe assignment, and edge cases
# including valid/invalid variable names, code injection prevention, and error handling

load test_helper

# Source the common library functions
# shellcheck source=/dev/null
source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true

# ============================================================================
# VARIABLE NAME VALIDATION TESTS - VALID NAMES
# ============================================================================

# bats test_tags=category:unit,priority:high
@test "safe_set_variable: accepts valid variable name starting with letter" {
	# Purpose: Test that safe_set_variable accepts valid variable names starting with letter
	# Expected: Function succeeds and sets variable correctly
	# Importance: Core functionality - most common variable name format
	safe_set_variable "VALID_NAME" "test_value"
	assert [ $? -eq 0 ]
	assert_equal "${VALID_NAME}" "test_value"
}

# bats test_tags=category:unit,priority:high
@test "safe_set_variable: accepts valid variable name starting with underscore" {
	# Purpose: Test that safe_set_variable accepts variable names starting with underscore
	# Expected: Function succeeds and sets variable correctly
	# Importance: Underscore is valid first character for shell variables
	safe_set_variable "_valid_name" "test_value"
	assert [ $? -eq 0 ]
	assert_equal "${_valid_name}" "test_value"
}

# bats test_tags=category:unit,priority:high
@test "safe_set_variable: accepts valid variable name with numbers" {
	# Purpose: Test that safe_set_variable accepts variable names containing numbers
	# Expected: Function succeeds and sets variable correctly
	# Importance: Numbers are valid in variable names after first character
	safe_set_variable "VAR123" "test_value"
	assert [ $? -eq 0 ]
	assert_equal "${VAR123}" "test_value"
}

# bats test_tags=category:unit,priority:high
@test "safe_set_variable: accepts valid single character variable name" {
	# Purpose: Test that safe_set_variable accepts single character variable names
	# Expected: Function succeeds and sets variable correctly
	# Importance: Single character variables are valid shell identifiers
	safe_set_variable "a" "test_value"
	assert [ $? -eq 0 ]
	assert_equal "${a}" "test_value"
}

# bats test_tags=category:unit,priority:high
@test "safe_set_variable: accepts valid single underscore variable name" {
	# Purpose: Test that safe_set_variable accepts single underscore as variable name
	# Expected: Function succeeds (returns 0)
	# Importance: Single underscore is a valid shell variable name
	# Note: We can only test return code, not the value, because $_ is a special
	# bash variable that gets overwritten with the last argument of each command.
	# After safe_set_variable returns, bash immediately sets $_ to the script path.
	run safe_set_variable "_" "test_value"
	assert_success
}

# bats test_tags=category:unit,priority:high
@test "safe_set_variable: accepts valid variable name with mixed case" {
	# Purpose: Test that safe_set_variable accepts variable names with mixed case letters
	# Expected: Function succeeds and sets variable correctly
	# Importance: Mixed case is common in shell variable naming conventions
	safe_set_variable "ValidVarName" "test_value"
	assert [ $? -eq 0 ]
	assert_equal "${ValidVarName}" "test_value"
}

# ============================================================================
# VARIABLE NAME VALIDATION TESTS - INVALID NAMES
# ============================================================================

# bats test_tags=category:unit,priority:high
@test "safe_set_variable: rejects variable name starting with number" {
	# Purpose: Test that safe_set_variable rejects variable names starting with number
	# Expected: Function fails (returns 1) without setting variable
	# Importance: Shell variables cannot start with numbers
	unset -v 123INVALID 2>/dev/null || true
	run safe_set_variable "123INVALID" "test_value"
	assert_failure
	# Variable should not be set
	run declare -p 123INVALID 2>/dev/null
	assert_failure
}

# bats test_tags=category:unit,priority:high
@test "safe_set_variable: rejects variable name with hyphen" {
	# Purpose: Test that safe_set_variable rejects variable names containing hyphens
	# Expected: Function fails (returns 1) without setting variable
	# Importance: Hyphens are not valid in shell variable names
	unset -v INVALID-NAME 2>/dev/null || true
	run safe_set_variable "INVALID-NAME" "test_value"
	assert_failure
}

# bats test_tags=category:unit,priority:high
@test "safe_set_variable: rejects variable name with space" {
	# Purpose: Test that safe_set_variable rejects variable names containing spaces
	# Expected: Function fails (returns 1) without setting variable
	# Importance: Spaces are not valid in shell variable names
	run safe_set_variable "VAR NAME" "test_value"
	assert_failure
}

# bats test_tags=category:unit,priority:high
@test "safe_set_variable: rejects empty variable name" {
	# Purpose: Test that safe_set_variable rejects empty variable names
	# Expected: Function fails (returns 1) without setting variable
	# Importance: Empty string is not a valid variable name
	run safe_set_variable "" "test_value"
	assert_failure
}

# bats test_tags=category:unit,priority:high
@test "safe_set_variable: rejects variable name with special characters" {
	# Purpose: Test that safe_set_variable rejects variable names with special characters
	# Expected: Function fails (returns 1) without setting variable
	# Importance: Special characters like @, #, $ are not valid in shell variable names
	run safe_set_variable "VAR@NAME" "test_value"
	assert_failure

	run safe_set_variable "VAR#NAME" "test_value"
	assert_failure

	run safe_set_variable "VAR\$NAME" "test_value"
	assert_failure
}

# bats test_tags=category:unit,priority:high
@test "safe_set_variable: rejects variable name with dot" {
	# Purpose: Test that safe_set_variable rejects variable names containing dots
	# Expected: Function fails (returns 1) without setting variable
	# Importance: Dots are not valid in shell variable names
	run safe_set_variable "VAR.NAME" "test_value"
	assert_failure
}

# ============================================================================
# CODE INJECTION PREVENTION TESTS
# ============================================================================

# bats test_tags=category:unit,priority:high
@test "safe_set_variable: prevents code injection via command substitution" {
	# Purpose: Test that safe_set_variable prevents code injection via command substitution
	# Expected: Value is set literally, command is not executed
	# Importance: Security - prevents code injection attacks
	local malicious_value='$(echo "injected")'
	safe_set_variable "TEST_VAR" "$malicious_value"
	assert [ $? -eq 0 ]
	assert_equal "${TEST_VAR}" '$(echo "injected")'
	# Verify command was not executed
	assert_not_equal "${TEST_VAR}" "injected"
}

# bats test_tags=category:unit,priority:high
@test "safe_set_variable: prevents code injection via backticks" {
	# Purpose: Test that safe_set_variable prevents code injection via backticks
	# Expected: Value is set literally, command is not executed
	# Importance: Security - prevents code injection attacks
	local malicious_value='`echo "injected"`'
	safe_set_variable "TEST_VAR" "$malicious_value"
	assert [ $? -eq 0 ]
	assert_equal "${TEST_VAR}" '`echo "injected"`'
	# Verify command was not executed
	assert_not_equal "${TEST_VAR}" "injected"
}

# bats test_tags=category:unit,priority:high
@test "safe_set_variable: prevents code injection via semicolon" {
	# Purpose: Test that safe_set_variable prevents code injection via semicolon
	# Expected: Value is set literally, command is not executed
	# Importance: Security - prevents code injection attacks
	local malicious_value='value; echo "injected"'
	safe_set_variable "TEST_VAR" "$malicious_value"
	assert [ $? -eq 0 ]
	assert_equal "${TEST_VAR}" 'value; echo "injected"'
}

# bats test_tags=category:unit,priority:high
@test "safe_set_variable: handles values with special shell characters" {
	# Purpose: Test that safe_set_variable handles values containing special shell characters
	# Expected: Value is set literally with all special characters preserved
	# Importance: Config values may contain special characters that should be preserved
	local special_value='value with $variables and "quotes" and \backslashes'
	safe_set_variable "TEST_VAR" "$special_value"
	assert [ $? -eq 0 ]
	assert_equal "${TEST_VAR}" 'value with $variables and "quotes" and \backslashes'
}

# ============================================================================
# VALUE HANDLING TESTS
# ============================================================================

# bats test_tags=category:unit
@test "safe_set_variable: handles empty value" {
	# Purpose: Test that safe_set_variable handles empty string values
	# Expected: Variable is set with empty value
	# Importance: Empty values are valid and should be handled correctly
	safe_set_variable "EMPTY_VAR" ""
	assert [ $? -eq 0 ]
	assert_equal "${EMPTY_VAR}" ""
}

# bats test_tags=category:unit
@test "safe_set_variable: handles values with spaces" {
	# Purpose: Test that safe_set_variable handles values containing spaces
	# Expected: Value with spaces is set correctly
	# Importance: Config values often contain spaces
	safe_set_variable "SPACE_VAR" "value with spaces"
	assert [ $? -eq 0 ]
	assert_equal "${SPACE_VAR}" "value with spaces"
}

# bats test_tags=category:unit
@test "safe_set_variable: handles values with newlines" {
	# Purpose: Test that safe_set_variable handles values containing newlines
	# Expected: Value with newlines is set correctly
	# Importance: Config values may contain newlines
	local multiline_value
	multiline_value=$(printf 'line1\nline2\nline3')
	safe_set_variable "MULTILINE_VAR" "$multiline_value"
	assert [ $? -eq 0 ]
	assert_equal "${MULTILINE_VAR}" "$multiline_value"
}

# bats test_tags=category:unit
@test "safe_set_variable: handles numeric values" {
	# Purpose: Test that safe_set_variable handles numeric values correctly
	# Expected: Numeric value is set as string
	# Importance: Config values may be numeric
	safe_set_variable "NUM_VAR" "12345"
	assert [ $? -eq 0 ]
	assert_equal "${NUM_VAR}" "12345"
}

# bats test_tags=category:unit
@test "safe_set_variable: handles unicode characters" {
	# Purpose: Test that safe_set_variable handles unicode characters correctly
	# Expected: Unicode characters are preserved
	# Importance: Config values may contain international characters
	safe_set_variable "UNICODE_VAR" "café résumé"
	assert [ $? -eq 0 ]
	assert_equal "${UNICODE_VAR}" "café résumé"
}

# ============================================================================
# GLOBAL SCOPE TESTS
# ============================================================================

# bats test_tags=category:unit
@test "safe_set_variable: sets variable in global scope" {
	# Purpose: Test that safe_set_variable sets variable in global scope
	# Expected: Variable is accessible after function returns
	# Importance: Function uses declare -g to ensure global scope
	# Test helper function to set a global variable
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds
	set_global_var() {
		safe_set_variable "GLOBAL_VAR" "global_value"
		assert [ $? -eq 0 ]
	}
	set_global_var
	assert_equal "${GLOBAL_VAR}" "global_value"
}

# bats test_tags=category:unit
@test "safe_set_variable: overwrites existing variable" {
	# Purpose: Test that safe_set_variable overwrites existing variable values
	# Expected: Existing variable is updated with new value
	# Importance: Function should update variables, not just set new ones
	EXISTING_VAR="old_value"
	safe_set_variable "EXISTING_VAR" "new_value"
	assert [ $? -eq 0 ]
	assert_equal "${EXISTING_VAR}" "new_value"
}

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

# bats test_tags=category:unit
@test "safe_set_variable: multiple variables can be set" {
	# Purpose: Test that multiple variables can be set using safe_set_variable
	# Expected: All variables are set correctly
	# Importance: Real-world usage involves setting multiple config variables
	safe_set_variable "VAR1" "value1"
	assert [ $? -eq 0 ]
	safe_set_variable "VAR2" "value2"
	assert [ $? -eq 0 ]
	safe_set_variable "VAR3" "value3"
	assert [ $? -eq 0 ]

	assert_equal "${VAR1}" "value1"
	assert_equal "${VAR2}" "value2"
	assert_equal "${VAR3}" "value3"
}

# bats test_tags=category:unit
@test "safe_set_variable: works with indirect variable names" {
	# Purpose: Test that safe_set_variable works with variable names passed as variables
	# Expected: Variable is set correctly using indirect name
	# Importance: Common pattern in config loading code
	local var_name="INDIRECT_VAR"
	local var_value="indirect_value"
	safe_set_variable "$var_name" "$var_value"
	assert [ $? -eq 0 ]
	assert_equal "${INDIRECT_VAR}" "indirect_value"
}
