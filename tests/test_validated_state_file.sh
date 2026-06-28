#!/usr/bin/env bats
#
# Tests for read_validated_state_file and write_validated_state_file helpers

load test_helper

setup() {
	standard_setup
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true
}

# bats test_tags=category:unit
@test "read_validated_state_file returns default when file missing" {
	local state_file="${TEST_DIR}/missing_binary_state"
	local value
	value=$(read_validated_state_file "$state_file" "0" "Test state file" "binary")
	assert_equal "$value" "0"
}

# bats test_tags=category:unit
@test "read_validated_state_file returns default when path is empty" {
	local value
	value=$(read_validated_state_file "" "0" "Test state file" "binary")
	assert_equal "$value" "0"
}

# bats test_tags=category:unit
@test "read_validated_state_file reads valid binary value" {
	local state_file="${TEST_DIR}/binary_state"
	echo "1" >"$state_file"
	local value
	value=$(read_validated_state_file "$state_file" "0" "Test state file" "binary")
	assert_equal "$value" "1"
}

# bats test_tags=category:unit
@test "read_validated_state_file recovers corrupted binary file" {
	local state_file="${TEST_DIR}/binary_state_corrupt"
	echo "invalid" >"$state_file"
	local value
	value=$(read_validated_state_file "$state_file" "0" "Test state file" "binary")
	assert_equal "$value" "0"
	assert_equal "$(cat "$state_file")" "0"
}

# bats test_tags=category:unit
@test "read_validated_state_file reads valid integer value" {
	local state_file="${TEST_DIR}/integer_state"
	echo "1700000000" >"$state_file"
	local value
	value=$(read_validated_state_file "$state_file" "0" "Test timestamp file" "integer")
	assert_equal "$value" "1700000000"
}

# bats test_tags=category:unit
@test "read_validated_state_file recovers corrupted integer file" {
	local state_file="${TEST_DIR}/integer_state_corrupt"
	echo "not-a-number" >"$state_file"
	local value
	value=$(read_validated_state_file "$state_file" "0" "Test timestamp file" "integer")
	assert_equal "$value" "0"
	assert_equal "$(cat "$state_file")" "0"
}

# bats test_tags=category:unit
@test "write_validated_state_file writes binary value" {
	local state_file="${TEST_DIR}/binary_write_state"
	run write_validated_state_file "$state_file" "1" "test state" "binary"
	assert_success
	assert_equal "$(cat "$state_file")" "1"
}

# bats test_tags=category:unit
@test "write_validated_state_file rejects invalid binary value" {
	local state_file="${TEST_DIR}/binary_write_invalid"
	run write_validated_state_file "$state_file" "2" "test state" "binary"
	assert_failure
	[[ ! -f "$state_file" ]]
}

# bats test_tags=category:unit
@test "write_validated_state_file fails on empty path" {
	run write_validated_state_file "" "0" "test state" "binary"
	assert_failure
}

# bats test_tags=category:unit
@test "write_validated_state_file writes integer value" {
	local state_file="${TEST_DIR}/integer_write_state"
	run write_validated_state_file "$state_file" "1700000001" "test timestamp" "integer"
	assert_success
	assert_equal "$(cat "$state_file")" "1700000001"
}

# bats test_tags=category:unit
@test "write_validated_state_file rejects invalid integer value" {
	local state_file="${TEST_DIR}/integer_write_invalid"
	run write_validated_state_file "$state_file" "invalid" "test timestamp" "integer"
	assert_failure
	[[ ! -f "$state_file" ]]
}
