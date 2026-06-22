#!/usr/bin/env bats
#
# Smoke tests for scripts/update-version.sh
# Guards against sourcing/common.sh regressions (e.g. readonly color collision)

load test_helper

UPDATE_SCRIPT="${BATS_TEST_DIRNAME}/../scripts/update-version.sh"
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."

# bats test_tags=category:unit
@test "update-version.sh exists and is executable" {
	assert_file_exist "$UPDATE_SCRIPT"
	assert_file_executable "$UPDATE_SCRIPT"
}

# bats test_tags=category:unit
@test "update-version.sh --help exits successfully" {
	run bash "$UPDATE_SCRIPT" --help
	assert_success
	assert_output --partial "Usage:"
}

# bats test_tags=category:unit
@test "update-version.sh --dry-run exits successfully" {
	cd "$PROJECT_ROOT"
	run bash "$UPDATE_SCRIPT" 9.9.9 --dry-run
	assert_success
}

# bats test_tags=category:unit
@test "update-version.sh rejects invalid version format" {
	run bash "$UPDATE_SCRIPT" not-a-version --dry-run
	assert_failure
	assert_output --partial "Invalid version format"
}
