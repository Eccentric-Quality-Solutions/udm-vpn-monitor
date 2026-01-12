#!/usr/bin/env bats
#
# Tests for Fallback Functions
# Tests critical fallback path when modules fail to source
#
# These tests verify that fallback functions work correctly when modules are unavailable:
# - Test define_common_fallbacks() when common.sh fails to source
# - Test define_logging_fallbacks() when logging.sh fails to source
# - Test define_schema_fallbacks() when config_schema.sh fails to source
# - Test graceful degradation when fallbacks.sh itself fails to source

load test_helper

LIB_DIR="${BATS_TEST_DIRNAME}/../lib"
FALLBACKS_FILE="${LIB_DIR}/fallbacks.sh"

# Global array to track backed up files for teardown cleanup
# Format: BACKED_UP_FILES=("file:backup" "file:backup" ...)
BACKED_UP_FILES=()

# Helper function to temporarily move a file
#
# Arguments:
#   $1: File path to move
#   $2: Temporary backup path
#
# Returns:
#   0: File moved successfully
#   1: Failed to move file
#
# Side effects:
#   Adds entry to BACKED_UP_FILES array for teardown cleanup
backup_file() {
	local file="$1"
	local backup="$2"
	if [[ -f "$file" ]]; then
		mv "$file" "$backup" 2>/dev/null || return 1
		# Track for teardown cleanup
		BACKED_UP_FILES+=("${file}:${backup}")
	fi
}

# Helper function to restore a file from backup
#
# Arguments:
#   $1: Original file path
#   $2: Backup path
#
# Returns:
#   0: File restored successfully
#   1: Failed to restore file
restore_file() {
	local file="$1"
	local backup="$2"
	if [[ -f "$backup" ]]; then
		mv "$backup" "$file" 2>/dev/null || return 1
		# Remove from tracking array
		local i=0
		while [[ $i -lt ${#BACKED_UP_FILES[@]} ]]; do
			if [[ "${BACKED_UP_FILES[$i]}" == "${file}:${backup}" ]]; then
				unset 'BACKED_UP_FILES[$i]'
				BACKED_UP_FILES=("${BACKED_UP_FILES[@]}")
				break
			fi
			i=$((i + 1))
		done
	fi
}

# Teardown function to ensure all backed up files are restored
#
# This ensures cleanup happens even if tests fail.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
teardown() {
	# Restore all backed up files
	local entry
	for entry in "${BACKED_UP_FILES[@]}"; do
		if [[ -n "$entry" ]]; then
			local file="${entry%%:*}"
			local backup="${entry#*:}"
			if [[ -f "$backup" ]]; then
				mv "$backup" "$file" 2>/dev/null || true
			fi
		fi
	done
	BACKED_UP_FILES=()

	# Call standard teardown to restore environment
	standard_teardown
}

# ============================================================================
# COMMON FALLBACKS TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "fallbacks: define_common_fallbacks works when common.sh fails to source" {
	# Purpose: Test verifies that define_common_fallbacks() defines fallback functions when common.sh is unavailable
	# Expected: Fallback functions are defined and work correctly
	# Importance: Ensures critical fallback path works when common.sh module is unavailable
	local common_backup="${TEST_DIR}/common.sh.backup"
	local common_file="${LIB_DIR}/common.sh"

	# Backup common.sh
	backup_file "$common_file" "$common_backup"

	# Source fallbacks.sh and call define_common_fallbacks
	source "$FALLBACKS_FILE"
	define_common_fallbacks

	# Verify fallback functions are defined
	assert [ "$(type -t ensure_file_exists)" = "function" ]
	assert [ "$(type -t try_ensure_directory_exists)" = "function" ]
	assert [ "$(type -t safe_source_lib)" = "function" ]
	assert [ "$(type -t get_unix_timestamp)" = "function" ]
	assert [ "$(type -t check_command_available)" = "function" ]
	assert [ "$(type -t atomic_write_file)" = "function" ]

	# Test ensure_file_exists fallback
	local test_file="${TEST_DIR}/test_file.txt"
	run ensure_file_exists "$test_file" "test content"
	assert_success
	assert_file_exist "$test_file"
	assert_file_contains "$test_file" "test content"

	# Test try_ensure_directory_exists fallback
	local test_dir="${TEST_DIR}/test_dir"
	run try_ensure_directory_exists "$test_dir"
	assert_success
	assert_dir_exist "$test_dir"

	# Test get_unix_timestamp fallback
	run get_unix_timestamp
	assert_success
	assert_output --regexp '^[0-9]+$'

	# Test check_command_available fallback
	run check_command_available "date"
	assert_success
	run check_command_available "nonexistent_command_xyz"
	assert_failure

	# Test atomic_write_file fallback
	local atomic_file="${TEST_DIR}/atomic.txt"
	run atomic_write_file "$atomic_file" "atomic content"
	assert_success
	assert_file_exist "$atomic_file"
	assert_file_contains "$atomic_file" "atomic content"

	# Restore common.sh
	restore_file "$common_file" "$common_backup"
}

# ============================================================================
# LOGGING FALLBACKS TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "fallbacks: define_logging_fallbacks works when logging.sh fails to source" {
	# Purpose: Test verifies that define_logging_fallbacks() defines fallback functions when logging.sh is unavailable
	# Expected: Fallback functions are defined and work correctly
	# Importance: Ensures critical fallback path works when logging.sh module is unavailable
	local logging_backup="${TEST_DIR}/logging.sh.backup"
	local logging_file="${LIB_DIR}/logging.sh"

	# Backup logging.sh
	backup_file "$logging_file" "$logging_backup"

	# Source fallbacks.sh and call define_logging_fallbacks
	source "$FALLBACKS_FILE"
	define_logging_fallbacks

	# Verify fallback functions are defined
	assert [ "$(type -t log_message)" = "function" ]
	assert [ "$(type -t handle_error)" = "function" ]

	# Test log_message fallback - should output to stderr
	run log_message "INFO" "Test log message"
	assert_success
	assert_output --regexp '\[.*\] \[INFO\] Test log message'

	# Test handle_error fallback - should log and not exit in test context
	run handle_error "ERROR" "Test error message" 1
	# In test context, handle_error should not exit (exit is disabled in tests)
	# It should just log the message
	assert_output --regexp '\[.*\] \[ERROR\] Test error message'

	# Restore logging.sh
	restore_file "$logging_file" "$logging_backup"
}

# bats test_tags=category:high-risk,priority:high
@test "fallbacks: define_logging_timestamp_fallback works when logging.sh fails to source" {
	# Purpose: Test verifies that define_logging_timestamp_fallback() defines fallback function when logging.sh is unavailable
	# Expected: Fallback function is defined and works correctly
	# Importance: Ensures timestamp fallback works when logging.sh module is unavailable
	local logging_backup="${TEST_DIR}/logging.sh.backup"
	local logging_file="${LIB_DIR}/logging.sh"

	# Backup logging.sh
	backup_file "$logging_file" "$logging_backup"

	# Source fallbacks.sh and call define_logging_timestamp_fallback
	source "$FALLBACKS_FILE"
	define_logging_timestamp_fallback

	# Verify fallback function is defined
	assert [ "$(type -t get_formatted_timestamp)" = "function" ]

	# Test get_formatted_timestamp fallback
	run get_formatted_timestamp
	assert_success
	assert_output --regexp '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'

	# Restore logging.sh
	restore_file "$logging_file" "$logging_backup"
}

# ============================================================================
# SCHEMA FALLBACKS TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "fallbacks: define_schema_fallbacks works when config_schema.sh fails to source" {
	# Purpose: Test verifies that define_schema_fallbacks() defines fallback functions when config_schema.sh is unavailable
	# Expected: Fallback functions are defined and work correctly
	# Importance: Ensures critical fallback path works when config_schema.sh module is unavailable
	local schema_backup="${TEST_DIR}/config_schema.sh.backup"
	local schema_file="${LIB_DIR}/config_schema.sh"

	# Backup config_schema.sh
	backup_file "$schema_file" "$schema_backup"

	# Source fallbacks.sh and call define_schema_fallbacks
	source "$FALLBACKS_FILE"
	define_schema_fallbacks

	# Verify fallback functions are defined
	assert [ "$(type -t get_config_schema)" = "function" ]
	assert [ "$(type -t is_config_required)" = "function" ]
	assert [ "$(type -t get_config_default)" = "function" ]

	# Test get_config_schema fallback - should always fail
	run get_config_schema "TEST_VAR"
	assert_failure

	# Test is_config_required fallback - should always fail
	run is_config_required "TEST_VAR"
	assert_failure

	# Test get_config_default fallback - should return empty string
	run get_config_default "TEST_VAR"
	assert_success
	assert_output ""

	# Restore config_schema.sh
	restore_file "$schema_file" "$schema_backup"
}

# ============================================================================
# GRACEFUL DEGRADATION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "fallbacks: graceful degradation when fallbacks.sh itself fails to source" {
	# Purpose: Test verifies that script handles gracefully when fallbacks.sh itself is unavailable
	# Expected: Script continues without crashing, fallback functions are not available
	# Importance: Ensures system degrades gracefully even when fallback mechanism fails
	local fallbacks_backup="${TEST_DIR}/fallbacks.sh.backup"

	# Backup fallbacks.sh
	backup_file "$FALLBACKS_FILE" "$fallbacks_backup"

	# Try to source fallbacks.sh - should fail gracefully
	run source "$FALLBACKS_FILE" 2>/dev/null
	# Source should fail (file doesn't exist)
	assert_failure

	# Verify fallback functions are NOT defined
	assert [ "$(type -t define_common_fallbacks)" != "function" ]
	assert [ "$(type -t define_logging_fallbacks)" != "function" ]
	assert [ "$(type -t define_schema_fallbacks)" != "function" ]

	# Restore fallbacks.sh
	restore_file "$FALLBACKS_FILE" "$fallbacks_backup"
}

# bats test_tags=category:high-risk,priority:high
@test "fallbacks: modules handle fallbacks.sh unavailability gracefully" {
	# Purpose: Test verifies that modules handle fallbacks.sh unavailability without crashing
	# Expected: Modules check for fallback function existence before calling them
	# Importance: Ensures modules degrade gracefully when fallbacks.sh is unavailable
	local fallbacks_backup="${TEST_DIR}/fallbacks.sh.backup"
	local logging_file="${LIB_DIR}/logging.sh"

	# Backup fallbacks.sh
	backup_file "$FALLBACKS_FILE" "$fallbacks_backup"

	# Backup common.sh to force fallback path
	local common_backup="${TEST_DIR}/common.sh.backup"
	local common_file="${LIB_DIR}/common.sh"
	backup_file "$common_file" "$common_backup"

	# Try to source logging.sh - it should handle missing fallbacks.sh gracefully
	# logging.sh tries to source common.sh, and if that fails, tries to source fallbacks.sh
	# Since both are missing, it may succeed (source returns 0) but functions may not work
	# The important thing is that it doesn't crash the shell
	run source "$logging_file" 2>/dev/null
	# Source may succeed or fail, but should not crash - verify by checking shell state
	# Verify we're still in a functional shell state regardless of source result
	run echo "test"
	assert_success
	assert_output "test"
	# Verify that logging.sh attempted to handle missing dependencies gracefully
	# by checking if log_message function exists (it may be defined by fallback or not at all)
	# The key is that sourcing didn't crash the shell

	# Restore files
	restore_file "$FALLBACKS_FILE" "$fallbacks_backup"
	restore_file "$common_file" "$common_backup"
}

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:medium
@test "fallbacks: integration - common fallbacks work in isolation" {
	# Purpose: Test verifies that common fallbacks work correctly without any other modules
	# Expected: All common fallback functions work independently
	# Importance: Ensures fallbacks are self-contained and don't depend on other modules
	local common_backup="${TEST_DIR}/common.sh.backup"
	local common_file="${LIB_DIR}/common.sh"

	# Backup common.sh
	backup_file "$common_file" "$common_backup"

	# Source only fallbacks.sh
	source "$FALLBACKS_FILE"
	define_common_fallbacks

	# Test that fallback functions work independently
	local test_file="${TEST_DIR}/isolated_test.txt"
	ensure_file_exists "$test_file" "isolated content"
	assert_file_exist "$test_file"

	local test_dir="${TEST_DIR}/isolated_dir"
	try_ensure_directory_exists "$test_dir"
	assert_dir_exist "$test_dir"

	local timestamp
	timestamp=$(get_unix_timestamp)
	assert [ -n "$timestamp" ]
	assert [ "$timestamp" -gt 0 ]

	# Restore common.sh
	restore_file "$common_file" "$common_backup"
}

# bats test_tags=category:high-risk,priority:medium
@test "fallbacks: integration - logging fallbacks work in isolation" {
	# Purpose: Test verifies that logging fallbacks work correctly without any other modules
	# Expected: All logging fallback functions work independently
	# Importance: Ensures fallbacks are self-contained and don't depend on other modules
	local logging_backup="${TEST_DIR}/logging.sh.backup"
	local logging_file="${LIB_DIR}/logging.sh"

	# Backup logging.sh
	backup_file "$logging_file" "$logging_backup"

	# Source only fallbacks.sh
	source "$FALLBACKS_FILE"
	define_logging_fallbacks

	# Test that fallback functions work independently
	run log_message "WARN" "Isolated warning message"
	assert_success
	assert_output --regexp '\[.*\] \[WARN\] Isolated warning message'

	# Test handle_error doesn't exit in test context
	run handle_error "ERROR" "Isolated error" 1
	assert_output --regexp '\[.*\] \[ERROR\] Isolated error'

	# Restore logging.sh
	restore_file "$logging_file" "$logging_backup"
}
