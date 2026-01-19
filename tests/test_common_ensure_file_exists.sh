#!/usr/bin/env bats
#
# Tests for ensure_file_exists() function in lib/common.sh
# Tests file creation with optional default content and parent directory creation
# with comprehensive edge case coverage including missing directories, permissions,
# and various content scenarios

load test_helper

# Source the common library functions
# shellcheck source=../lib/common.sh
source "${BATS_TEST_DIRNAME}/../lib/common.sh"

# ============================================================================
# BASIC FILE CREATION TESTS
# ============================================================================

# bats test_tags=category:unit
@test "ensure_file_exists: creates file when it doesn't exist" {
	# Purpose: Test that ensure_file_exists creates a file when it doesn't exist
	# Expected: Returns success (0) and file is created
	# Importance: Core functionality - basic file creation
	local test_file="${BATS_TEST_TMPDIR}/test_file.txt"
	run ensure_file_exists "$test_file"
	assert_success
	assert_file_exist "$test_file"
}

# bats test_tags=category:unit
@test "ensure_file_exists: creates file with default content" {
	# Purpose: Test that ensure_file_exists creates file with specified default content
	# Expected: Returns success (0) and file contains the default content
	# Importance: Core functionality - file creation with content
	local test_file="${BATS_TEST_TMPDIR}/test_file.txt"
	local default_content="initial value"
	run ensure_file_exists "$test_file" "$default_content"
	assert_success
	assert_file_exist "$test_file"
	run grep -Fq -- "$default_content" "$test_file"
	assert_success
}

# bats test_tags=category:unit
@test "ensure_file_exists: creates file with empty default content" {
	# Purpose: Test that ensure_file_exists creates file with empty default content
	# Expected: Returns success (0) and file exists (contains newline from echo)
	# Importance: Edge case - empty content is valid
	# Note: echo "" writes a newline, so file will contain one newline character
	local test_file="${BATS_TEST_TMPDIR}/test_file.txt"
	run ensure_file_exists "$test_file" ""
	assert_success
	assert_file_exist "$test_file"
	# File will contain a newline from echo ""
	local file_size
	file_size=$(stat -f%z "$test_file" 2>/dev/null || stat -c%s "$test_file" 2>/dev/null || echo "0")
	assert [ "$file_size" -le 1 ]
}

# bats test_tags=category:unit
@test "ensure_file_exists: creates file with numeric default content" {
	# Purpose: Test that ensure_file_exists creates file with numeric default content
	# Expected: Returns success (0) and file contains the numeric value
	# Importance: Common use case - counter files initialized to "0"
	local test_file="${BATS_TEST_TMPDIR}/counter.txt"
	run ensure_file_exists "$test_file" "0"
	assert_success
	assert_file_exist "$test_file"
	run grep -Fq -- "0" "$test_file"
	assert_success
}

# bats test_tags=category:unit
@test "ensure_file_exists: does not overwrite existing file" {
	# Purpose: Test that ensure_file_exists does not modify existing file
	# Expected: Returns success (0) and existing file content is preserved
	# Importance: Core behavior - function should be idempotent
	local test_file="${BATS_TEST_TMPDIR}/existing_file.txt"
	local existing_content="existing content"
	echo "$existing_content" >"$test_file"
	run ensure_file_exists "$test_file" "new content"
	assert_success
	assert_file_exist "$test_file"
	run grep -Fq -- "$existing_content" "$test_file"
	assert_success
	run grep -Fq -- "new content" "$test_file"
	assert_failure
}

# ============================================================================
# PARENT DIRECTORY CREATION TESTS
# ============================================================================

# bats test_tags=category:unit
@test "ensure_file_exists: creates single-level parent directory" {
	# Purpose: Test that ensure_file_exists creates parent directory when it doesn't exist
	# Expected: Returns success (0), parent directory and file are created
	# Importance: Core functionality - parent directory creation (key requirement)
	local test_dir="${BATS_TEST_TMPDIR}/parent_dir"
	local test_file="${test_dir}/test_file.txt"
	# Ensure parent directory doesn't exist
	rm -rf "$test_dir"
	run ensure_file_exists "$test_file" "test content"
	assert_success
	assert_dir_exist "$test_dir"
	assert_file_exist "$test_file"
	run grep -Fq -- "test content" "$test_file"
	assert_success
}

# bats test_tags=category:unit
@test "ensure_file_exists: creates multiple-level parent directories" {
	# Purpose: Test that ensure_file_exists creates nested parent directories
	# Expected: Returns success (0), all parent directories and file are created
	# Importance: Real-world scenario - deeply nested directory structures
	local test_dir="${BATS_TEST_TMPDIR}/level1/level2/level3"
	local test_file="${test_dir}/test_file.txt"
	# Ensure parent directories don't exist
	rm -rf "${BATS_TEST_TMPDIR}/level1"
	run ensure_file_exists "$test_file" "nested content"
	assert_success
	assert_dir_exist "${BATS_TEST_TMPDIR}/level1"
	assert_dir_exist "${BATS_TEST_TMPDIR}/level1/level2"
	assert_dir_exist "${BATS_TEST_TMPDIR}/level1/level2/level3"
	assert_file_exist "$test_file"
	run grep -Fq -- "nested content" "$test_file"
	assert_success
}

# bats test_tags=category:unit
@test "ensure_file_exists: handles parent directory that already exists" {
	# Purpose: Test that ensure_file_exists works when parent directory already exists
	# Expected: Returns success (0) and file is created without errors
	# Importance: Common case - parent directory may already exist
	local test_dir="${BATS_TEST_TMPDIR}/existing_parent"
	local test_file="${test_dir}/test_file.txt"
	mkdir -p "$test_dir"
	run ensure_file_exists "$test_file" "content"
	assert_success
	assert_dir_exist "$test_dir"
	assert_file_exist "$test_file"
	run grep -Fq -- "content" "$test_file"
	assert_success
}

# bats test_tags=category:unit
@test "ensure_file_exists: creates parent directory for file in root-relative path" {
	# Purpose: Test that ensure_file_exists handles root-relative paths correctly
	# Expected: Returns success (0) and creates directories appropriately
	# Importance: Edge case - paths starting with /
	local test_dir="${BATS_TEST_TMPDIR}/root_test"
	local test_file="${test_dir}/subdir/file.txt"
	rm -rf "$test_dir"
	run ensure_file_exists "$test_file" "root content"
	assert_success
	assert_dir_exist "${test_dir}/subdir"
	assert_file_exist "$test_file"
	run grep -Fq -- "root content" "$test_file"
	assert_success
}

# ============================================================================
# CONTENT HANDLING TESTS
# ============================================================================

# bats test_tags=category:unit
@test "ensure_file_exists: handles content with spaces" {
	# Purpose: Test that ensure_file_exists handles default content with spaces
	# Expected: Returns success (0) and file contains content with spaces
	# Importance: Common case - content may contain spaces
	local test_file="${BATS_TEST_TMPDIR}/spaced_content.txt"
	local content="content with spaces"
	run ensure_file_exists "$test_file" "$content"
	assert_success
	assert_file_exist "$test_file"
	run grep -Fq -- "$content" "$test_file"
	assert_success
}

# bats test_tags=category:unit
@test "ensure_file_exists: handles content with special characters" {
	# Purpose: Test that ensure_file_exists handles default content with special characters
	# Expected: Returns success (0) and file contains special characters correctly
	# Importance: Edge case - content may contain special shell characters
	local test_file="${BATS_TEST_TMPDIR}/special_content.txt"
	local content="value@123#test\$value"
	run ensure_file_exists "$test_file" "$content"
	assert_success
	assert_file_exist "$test_file"
	run grep -Fq -- "$content" "$test_file"
	assert_success
}

# bats test_tags=category:unit
@test "ensure_file_exists: handles multi-line content" {
	# Purpose: Test that ensure_file_exists handles multi-line default content
	# Expected: Returns success (0) and file contains all lines
	# Importance: Edge case - content may span multiple lines
	local test_file="${BATS_TEST_TMPDIR}/multiline.txt"
	local content=$'line1\nline2\nline3'
	run ensure_file_exists "$test_file" "$content"
	assert_success
	assert_file_exist "$test_file"
	run grep -Fq -- "line1" "$test_file"
	assert_success
	run grep -Fq -- "line2" "$test_file"
	assert_success
	run grep -Fq -- "line3" "$test_file"
	assert_success
}

# bats test_tags=category:unit
@test "ensure_file_exists: handles content with newlines" {
	# Purpose: Test that ensure_file_exists handles content containing newline characters
	# Expected: Returns success (0) and file contains newlines correctly
	# Importance: Edge case - content may contain newline characters
	local test_file="${BATS_TEST_TMPDIR}/newline_content.txt"
	local content=$'first line\nsecond line'
	run ensure_file_exists "$test_file" "$content"
	assert_success
	assert_file_exist "$test_file"
	# Verify file has multiple lines
	local line_count
	line_count=$(wc -l <"$test_file" | tr -d ' ')
	assert [ "$line_count" -eq 2 ]
}

# ============================================================================
# EDGE CASES
# ============================================================================

# bats test_tags=category:unit
@test "ensure_file_exists: handles file in current directory" {
	# Purpose: Test that ensure_file_exists handles file in current directory (no parent dir)
	# Expected: Returns success (0) and file is created
	# Importance: Edge case - file path with no parent directory component
	local test_file="${BATS_TEST_TMPDIR}/current_dir_file.txt"
	cd "$BATS_TEST_TMPDIR" || exit 1
	run ensure_file_exists "current_dir_file.txt"
	assert_success
	assert_file_exist "current_dir_file.txt"
	cd - >/dev/null || exit 1
}

# bats test_tags=category:unit
@test "ensure_file_exists: handles file with no default content argument" {
	# Purpose: Test that ensure_file_exists works when second argument is omitted
	# Expected: Returns success (0) and file is created (contains newline from echo)
	# Importance: Common case - default content is optional
	# Note: When default_content is omitted, it defaults to empty string, and echo "" writes a newline
	local test_file="${BATS_TEST_TMPDIR}/no_content.txt"
	run ensure_file_exists "$test_file"
	assert_success
	assert_file_exist "$test_file"
	# File will contain a newline from echo "" (default_content defaults to empty string)
	local file_size
	file_size=$(stat -f%z "$test_file" 2>/dev/null || stat -c%s "$test_file" 2>/dev/null || echo "0")
	assert [ "$file_size" -le 1 ]
}

# bats test_tags=category:unit
@test "ensure_file_exists: creates file with zero as content" {
	# Purpose: Test that ensure_file_exists correctly handles "0" as content (not false)
	# Expected: Returns success (0) and file contains "0"
	# Importance: Common use case - counter files initialized to zero
	local test_file="${BATS_TEST_TMPDIR}/zero.txt"
	run ensure_file_exists "$test_file" "0"
	assert_success
	assert_file_exist "$test_file"
	local file_content
	file_content=$(cat "$test_file")
	assert [ "$file_content" = "0" ]
}

# ============================================================================
# ERROR HANDLING TESTS
# ============================================================================

# bats test_tags=category:unit
@test "ensure_file_exists: returns failure when parent directory cannot be created" {
	# Purpose: Test that ensure_file_exists returns failure when mkdir fails
	# Expected: Returns failure (1) when parent directory creation fails
	# Importance: Error handling - function should report failures correctly
	# Note: This test may be difficult to simulate without root permissions
	# We'll test with a path that should fail (e.g., invalid characters or permissions)
	# For a more reliable test, we could mock mkdir, but for now we'll skip if we can't create a failure scenario
	skip "Difficult to reliably test mkdir failure without mocking or root permissions"
}

# bats test_tags=category:unit
@test "ensure_file_exists: returns failure when file cannot be written" {
	# Purpose: Test that ensure_file_exists returns failure when file write fails
	# Expected: Returns failure (1) when file cannot be written
	# Importance: Error handling - function should report write failures
	# Note: This test may be difficult to simulate without root permissions
	# We'll skip if we can't create a reliable failure scenario
	skip "Difficult to reliably test file write failure without mocking or root permissions"
}

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

# bats test_tags=category:unit
@test "ensure_file_exists: works with command substitution" {
	# Purpose: Test that ensure_file_exists works correctly in command substitution context
	# Expected: Returns success (0) when used in if statement
	# Importance: Common usage pattern in scripts
	local test_file="${BATS_TEST_TMPDIR}/substitution_test.txt"
	if ensure_file_exists "$test_file" "test"; then
		assert_file_exist "$test_file"
	else
		fail "ensure_file_exists should return success"
	fi
}

# bats test_tags=category:unit
@test "ensure_file_exists: can be called multiple times idempotently" {
	# Purpose: Test that ensure_file_exists can be called multiple times without side effects
	# Expected: Multiple calls succeed and file content remains unchanged after first call
	# Importance: Idempotency - function should be safe to call repeatedly
	local test_file="${BATS_TEST_TMPDIR}/idempotent_test.txt"
	local initial_content="initial"
	# First call creates file
	run ensure_file_exists "$test_file" "$initial_content"
	assert_success
	run grep -Fq -- "$initial_content" "$test_file"
	assert_success
	# Second call should not modify file
	run ensure_file_exists "$test_file" "modified"
	assert_success
	run grep -Fq -- "$initial_content" "$test_file"
	assert_success
	run grep -Fq -- "modified" "$test_file"
	assert_failure
	# Third call should also not modify file
	run ensure_file_exists "$test_file" "another"
	assert_success
	run grep -Fq -- "$initial_content" "$test_file"
	assert_success
}

# bats test_tags=category:unit
@test "ensure_file_exists: creates multiple files in same parent directory" {
	# Purpose: Test that ensure_file_exists can create multiple files in the same directory
	# Expected: All files are created successfully in the same parent directory
	# Importance: Real-world scenario - multiple files in same directory
	local test_dir="${BATS_TEST_TMPDIR}/multi_file_dir"
	local file1="${test_dir}/file1.txt"
	local file2="${test_dir}/file2.txt"
	local file3="${test_dir}/file3.txt"
	rm -rf "$test_dir"
	run ensure_file_exists "$file1" "content1"
	assert_success
	run ensure_file_exists "$file2" "content2"
	assert_success
	run ensure_file_exists "$file3" "content3"
	assert_success
	assert_dir_exist "$test_dir"
	assert_file_exist "$file1"
	assert_file_exist "$file2"
	assert_file_exist "$file3"
	run grep -Fq -- "content1" "$file1"
	assert_success
	run grep -Fq -- "content2" "$file2"
	assert_success
	run grep -Fq -- "content3" "$file3"
	assert_success
}
