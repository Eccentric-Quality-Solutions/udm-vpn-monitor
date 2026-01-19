#!/usr/bin/env bats
#
# Tests for update_config_value() function in lib/common.sh
# Tests variable name validation, config file updates, and edge cases
# including valid/invalid variable names, file operations, and error handling

load test_helper

# Source the common library functions
# shellcheck source=/dev/null
source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true

# ============================================================================
# VARIABLE NAME VALIDATION TESTS - VALID NAMES
# ============================================================================

# bats test_tags=category:unit,priority:high
@test "update_config_value: accepts valid variable name starting with letter" {
	# Purpose: Test that update_config_value accepts valid variable names starting with letter
	# Expected: Function succeeds and updates config file
	# Importance: Core functionality - most common variable name format
	local config_file="${TEST_DIR}/test_config.conf"
	echo "# Test config" >"$config_file"

	run update_config_value "$config_file" "VALID_NAME" "test_value"
	assert_success
	assert_file_exist "$config_file"
	grep -q '^VALID_NAME="test_value"$' "$config_file"
}

# bats test_tags=category:unit,priority:high
@test "update_config_value: accepts valid variable name starting with underscore" {
	# Purpose: Test that update_config_value accepts variable names starting with underscore
	# Expected: Function succeeds and updates config file
	# Importance: Underscore is valid first character for shell variables
	local config_file="${TEST_DIR}/test_config.conf"
	echo "# Test config" >"$config_file"

	run update_config_value "$config_file" "_valid_name" "test_value"
	assert_success
	assert_file_exist "$config_file"
	grep -q '^_valid_name="test_value"$' "$config_file"
}

# bats test_tags=category:unit,priority:high
@test "update_config_value: accepts valid variable name with numbers" {
	# Purpose: Test that update_config_value accepts variable names containing numbers
	# Expected: Function succeeds and updates config file
	# Importance: Numbers are valid in variable names after first character
	local config_file="${TEST_DIR}/test_config.conf"
	echo "# Test config" >"$config_file"

	run update_config_value "$config_file" "VAR123" "test_value"
	assert_success
	assert_file_exist "$config_file"
	grep -q '^VAR123="test_value"$' "$config_file"
}

# bats test_tags=category:unit,priority:high
@test "update_config_value: accepts valid single character variable name" {
	# Purpose: Test that update_config_value accepts single character variable names
	# Expected: Function succeeds and updates config file
	# Importance: Single character variables are valid shell identifiers
	local config_file="${TEST_DIR}/test_config.conf"
	echo "# Test config" >"$config_file"

	run update_config_value "$config_file" "a" "test_value"
	assert_success
	assert_file_exist "$config_file"
	grep -q '^a="test_value"$' "$config_file"
}

# bats test_tags=category:unit,priority:high
@test "update_config_value: accepts valid single underscore variable name" {
	# Purpose: Test that update_config_value accepts single underscore as variable name
	# Expected: Function succeeds and updates config file
	# Importance: Single underscore is a valid shell variable name
	local config_file="${TEST_DIR}/test_config.conf"
	echo "# Test config" >"$config_file"

	run update_config_value "$config_file" "_" "test_value"
	assert_success
	assert_file_exist "$config_file"
	grep -q '^_="test_value"$' "$config_file"
}

# bats test_tags=category:unit,priority:high
@test "update_config_value: accepts valid variable name with mixed case" {
	# Purpose: Test that update_config_value accepts variable names with mixed case letters
	# Expected: Function succeeds and updates config file
	# Importance: Mixed case is common in shell variable naming conventions
	local config_file="${TEST_DIR}/test_config.conf"
	echo "# Test config" >"$config_file"

	run update_config_value "$config_file" "ValidVarName" "test_value"
	assert_success
	assert_file_exist "$config_file"
	grep -q '^ValidVarName="test_value"$' "$config_file"
}

# ============================================================================
# VARIABLE NAME VALIDATION TESTS - INVALID NAMES
# ============================================================================

# bats test_tags=category:unit,priority:high
@test "update_config_value: rejects variable name starting with number" {
	# Purpose: Test that update_config_value rejects variable names starting with number
	# Expected: Function fails (returns 1) without modifying config file
	# Importance: Shell variables cannot start with numbers
	local config_file="${TEST_DIR}/test_config.conf"
	echo "# Test config" >"$config_file"
	local original_content
	original_content=$(cat "$config_file")

	run update_config_value "$config_file" "123INVALID" "test_value"
	assert_failure
	assert_equal "$(cat "$config_file")" "$original_content"
}

# bats test_tags=category:unit,priority:high
@test "update_config_value: rejects variable name with hyphen" {
	# Purpose: Test that update_config_value rejects variable names containing hyphens
	# Expected: Function fails (returns 1) without modifying config file
	# Importance: Hyphens are not valid in shell variable names
	local config_file="${TEST_DIR}/test_config.conf"
	echo "# Test config" >"$config_file"
	local original_content
	original_content=$(cat "$config_file")

	run update_config_value "$config_file" "INVALID-NAME" "test_value"
	assert_failure
	assert_equal "$(cat "$config_file")" "$original_content"
}

# bats test_tags=category:unit,priority:high
@test "update_config_value: rejects variable name with space" {
	# Purpose: Test that update_config_value rejects variable names containing spaces
	# Expected: Function fails (returns 1) without modifying config file
	# Importance: Spaces are not valid in shell variable names
	local config_file="${TEST_DIR}/test_config.conf"
	echo "# Test config" >"$config_file"
	local original_content
	original_content=$(cat "$config_file")

	run update_config_value "$config_file" "VAR NAME" "test_value"
	assert_failure
	assert_equal "$(cat "$config_file")" "$original_content"
}

# bats test_tags=category:unit,priority:high
@test "update_config_value: rejects empty variable name" {
	# Purpose: Test that update_config_value rejects empty variable names
	# Expected: Function fails (returns 1) without modifying config file
	# Importance: Empty string is not a valid variable name
	local config_file="${TEST_DIR}/test_config.conf"
	echo "# Test config" >"$config_file"
	local original_content
	original_content=$(cat "$config_file")

	run update_config_value "$config_file" "" "test_value"
	assert_failure
	assert_equal "$(cat "$config_file")" "$original_content"
}

# bats test_tags=category:unit,priority:high
@test "update_config_value: rejects variable name with special characters" {
	# Purpose: Test that update_config_value rejects variable names with special characters
	# Expected: Function fails (returns 1) without modifying config file
	# Importance: Special characters like @, #, $ are not valid in shell variable names
	local config_file="${TEST_DIR}/test_config.conf"
	echo "# Test config" >"$config_file"
	local original_content
	original_content=$(cat "$config_file")

	run update_config_value "$config_file" "VAR@NAME" "test_value"
	assert_failure
	assert_equal "$(cat "$config_file")" "$original_content"

	run update_config_value "$config_file" "VAR#NAME" "test_value"
	assert_failure
	assert_equal "$(cat "$config_file")" "$original_content"

	run update_config_value "$config_file" "VAR\$NAME" "test_value"
	assert_failure
	assert_equal "$(cat "$config_file")" "$original_content"
}

# bats test_tags=category:unit,priority:high
@test "update_config_value: rejects variable name with dot" {
	# Purpose: Test that update_config_value rejects variable names containing dots
	# Expected: Function fails (returns 1) without modifying config file
	# Importance: Dots are not valid in shell variable names
	local config_file="${TEST_DIR}/test_config.conf"
	echo "# Test config" >"$config_file"
	local original_content
	original_content=$(cat "$config_file")

	run update_config_value "$config_file" "VAR.NAME" "test_value"
	assert_failure
	assert_equal "$(cat "$config_file")" "$original_content"
}

# ============================================================================
# CONFIG FILE OPERATION TESTS
# ============================================================================

# bats test_tags=category:unit
@test "update_config_value: updates existing variable in config file" {
	# Purpose: Test that update_config_value updates existing variable values
	# Expected: Existing variable is updated with new value
	# Importance: Core functionality - updating existing config values
	local config_file="${TEST_DIR}/test_config.conf"
	echo 'EXISTING_VAR="old_value"' >"$config_file"

	run update_config_value "$config_file" "EXISTING_VAR" "new_value"
	assert_success
	grep -q '^EXISTING_VAR="new_value"$' "$config_file"
	run grep -c '^EXISTING_VAR=' "$config_file"
	assert_output "1"
}

# bats test_tags=category:unit
@test "update_config_value: adds new variable to empty config file" {
	# Purpose: Test that update_config_value adds new variable to empty config file
	# Expected: New variable is appended to file
	# Importance: Core functionality - adding new config values
	local config_file="${TEST_DIR}/test_config.conf"
	touch "$config_file"

	run update_config_value "$config_file" "NEW_VAR" "test_value"
	assert_success
	grep -q '^NEW_VAR="test_value"$' "$config_file"
}

# bats test_tags=category:unit
@test "update_config_value: adds new variable with insert_after pattern" {
	# Purpose: Test that update_config_value inserts variable after specified pattern
	# Expected: New variable is inserted after matching pattern
	# Importance: Allows controlled placement of new config values
	local config_file="${TEST_DIR}/test_config.conf"
	cat >"$config_file" <<'EOF'
FIRST_VAR="value1"
SECOND_VAR="value2"
THIRD_VAR="value3"
EOF

	run update_config_value "$config_file" "NEW_VAR" "new_value" "^SECOND_VAR="
	assert_success
	local line_num
	line_num=$(grep -n '^NEW_VAR=' "$config_file" | cut -d: -f1)
	local second_var_line
	second_var_line=$(grep -n '^SECOND_VAR=' "$config_file" | cut -d: -f1)
	assert [ "$line_num" -eq $((second_var_line + 1)) ]
}

# bats test_tags=category:unit
@test "update_config_value: handles values with special characters" {
	# Purpose: Test that update_config_value properly escapes values with special characters
	# Expected: Value is properly escaped and quoted in config file
	# Importance: Config values may contain special characters that need escaping
	local config_file="${TEST_DIR}/test_config.conf"
	echo "# Test config" >"$config_file"

	run update_config_value "$config_file" "TEST_VAR" "value/with/slashes"
	assert_success
	grep -q '^TEST_VAR="value/with/slashes"$' "$config_file"
}

# bats test_tags=category:unit
@test "update_config_value: handles empty value" {
	# Purpose: Test that update_config_value handles empty string values
	# Expected: Variable is set with empty quoted value
	# Importance: Empty values are valid and should be handled correctly
	local config_file="${TEST_DIR}/test_config.conf"
	echo "# Test config" >"$config_file"

	run update_config_value "$config_file" "EMPTY_VAR" ""
	assert_success
	grep -q '^EMPTY_VAR=""$' "$config_file"
}

# ============================================================================
# ERROR HANDLING TESTS
# ============================================================================

# bats test_tags=category:unit
@test "update_config_value: fails when config file does not exist" {
	# Purpose: Test that update_config_value fails when config file doesn't exist
	# Expected: Function fails (returns 1) without creating file
	# Importance: Should not create files implicitly
	local config_file="${TEST_DIR}/nonexistent.conf"

	run update_config_value "$config_file" "TEST_VAR" "test_value"
	assert_failure
	assert_file_not_exist "$config_file"
}

# bats test_tags=category:unit
@test "update_config_value: validation happens before file checks" {
	# Purpose: Test that variable name validation happens before file existence checks
	# Expected: Invalid variable name causes immediate failure even if file exists
	# Importance: Fail-fast behavior improves error detection
	local config_file="${TEST_DIR}/test_config.conf"
	echo "# Test config" >"$config_file"

	# Even though file exists, invalid variable name should fail immediately
	run update_config_value "$config_file" "INVALID-NAME" "test_value"
	assert_failure
}

# bats test_tags=category:unit
@test "update_config_value: fails when config file is unreadable" {
	# Purpose: Test that update_config_value fails when config file is unreadable
	# Expected: Function fails (returns 1) without modifying config file
	# Importance: Should handle permission errors gracefully and prevent hangs
	local config_file="${TEST_DIR}/test_config_unreadable.conf"
	echo "# Test config" >"$config_file"
	local original_content
	original_content=$(cat "$config_file")

	# Make file unreadable (000 permissions)
	chmod 000 "$config_file"

	run update_config_value "$config_file" "TEST_VAR" "test_value"
	assert_failure

	# Restore permissions for cleanup and verify file wasn't modified
	chmod 644 "$config_file" 2>/dev/null || true
	assert_equal "$(cat "$config_file")" "$original_content"
}

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

# bats test_tags=category:unit
@test "update_config_value: multiple valid variables can be added" {
	# Purpose: Test that multiple valid variables can be added to config file
	# Expected: All variables are added successfully
	# Importance: Real-world usage involves multiple config variables
	local config_file="${TEST_DIR}/test_config.conf"
	touch "$config_file"

	run update_config_value "$config_file" "VAR1" "value1"
	assert_success

	run update_config_value "$config_file" "VAR2" "value2"
	assert_success

	run update_config_value "$config_file" "VAR3" "value3"
	assert_success

	grep -q '^VAR1="value1"$' "$config_file"
	grep -q '^VAR2="value2"$' "$config_file"
	grep -q '^VAR3="value3"$' "$config_file"
}

# bats test_tags=category:unit
@test "update_config_value: updated config file can be sourced" {
	# Purpose: Test that config file updated by update_config_value can be safely sourced
	# Expected: Config file contains valid shell syntax that can be sourced
	# Importance: Config files are sourced by the application, must be valid shell
	local config_file="${TEST_DIR}/test_config.conf"
	touch "$config_file"

	run update_config_value "$config_file" "TEST_VAR" "test_value"
	assert_success

	# Source the config file and verify variable is set
	# shellcheck source=/dev/null
	source "$config_file"
	assert_equal "$TEST_VAR" "test_value"
}
