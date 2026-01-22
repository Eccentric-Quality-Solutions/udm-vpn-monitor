#!/usr/bin/env bats
#
# Tests for check-utilities.sh script
# Tests utility availability checking functionality

load test_helper

# Path to the check-utilities script
CHECK_UTILITIES_SCRIPT="${BATS_TEST_DIRNAME}/../check-utilities.sh"

# bats test_tags=category:unit
@test "check-utilities.sh checks available utilities successfully" {
	# Purpose: Test verifies that script successfully checks for available utilities and reports them correctly.
	# Expected: Script runs, reports available utilities with checkmark, and produces summary (exit 0 or 1 based on availability).
	# Importance: Core functionality test ensures utility checking works and correctly identifies available utilities.
	run bash "$CHECK_UTILITIES_SCRIPT"

	# Check that it produces expected output regardless of exit code
	assert_output --partial "Checking utility availability"
	assert_output --partial "Summary:"
	# Should report some utilities as available (common ones like 'date', 'grep', etc.)
	assert_output --partial "[✓]"
	# Exit code is 0 (all available) or 1 (some missing) - both are valid
	[[ $status -eq 0 || $status -eq 1 ]]
}

# bats test_tags=category:unit
@test "check-utilities.sh provides complete summary output" {
	# Purpose: Test verifies that script provides comprehensive summary output with statistics and actionable information.
	# Expected: Script outputs summary section with availability counts, missing utilities list (if any), and clear formatting.
	# Importance: Summary helps users quickly understand system state and take action on missing dependencies.
	run bash "$CHECK_UTILITIES_SCRIPT"

	# Check that output contains summary section with availability info
	assert_output --partial "Summary:"
	assert_output --partial "Available:"
	# Verify summary statistics format
	assert_output --regexp "Available: [0-9]+/[0-9]+"
	assert_output --partial "Missing:"
	# If utilities are missing, there should be an actionable list
	if [[ $status -eq 1 ]]; then
		assert_output --partial "Missing utilities:"
	fi
}

# bats test_tags=category:unit
@test "check-utilities.sh handles empty PATH gracefully" {
	# Purpose: Test verifies that script handles edge case of empty PATH.
	# Expected: Script reports all utilities as missing when PATH is empty.
	# Importance: Prevents script crashes in edge cases.
	# Use full path to bash so it can be found even with empty PATH
	local bash_path
	bash_path=$(command -v bash || echo "/bin/bash")
	PATH="" run "$bash_path" "$CHECK_UTILITIES_SCRIPT"

	# Script should run successfully and report all utilities as missing
	# Exit code should be 1 since all utilities are missing (expected behavior)
	[[ $status -eq 1 ]]
	assert_output --partial "Checking utility availability"
	assert_output --partial "Summary:"
	assert_output --partial "Available: 0/"
	# All utilities should be reported as missing
	assert_output --partial "[✗]"
}

# bats test_tags=category:unit
@test "check-utilities.sh returns correct exit code based on availability" {
	# Purpose: Test verifies that script returns correct exit code based on utility availability.
	# Expected: Script exits with code 0 when all utilities are available, 1 when some are missing.
	# Importance: Exit codes are important for scripting and automation.
	run bash "$CHECK_UTILITIES_SCRIPT"

	# Exit code must be 0 (all available) or 1 (some missing)
	[[ $status -eq 0 || $status -eq 1 ]]

	# Verify exit code matches output
	if [[ $status -eq 0 ]]; then
		assert_output --partial "All utilities are available!"
	else
		assert_output --partial "Missing utilities:"
	fi
}

# bats test_tags=category:unit
@test "check-utilities.sh handles PATH with spaces" {
	# Purpose: Test verifies that script handles PATH containing spaces.
	# Expected: Script correctly checks utilities even with spaces in PATH.
	# Importance: Prevents issues with paths containing special characters.

	# Create a temp directory with space in name and add a mock utility
	local temp_dir="${BATS_TEST_TMPDIR}/path with spaces"
	mkdir -p "$temp_dir"
	echo '#!/bin/bash' >"$temp_dir/date"
	echo 'echo "mock date"' >>"$temp_dir/date"
	chmod +x "$temp_dir/date"

	# Run with modified PATH that includes directory with spaces
	PATH="$temp_dir:$PATH" run bash "$CHECK_UTILITIES_SCRIPT"

	# Script should run successfully and find utilities
	[[ $status -eq 0 || $status -eq 1 ]]
	assert_output --partial "Summary:"
}
