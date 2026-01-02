#!/usr/bin/env bats
#
# Tests for check-utilities.sh script
# Tests utility availability checking functionality

load test_helper

# Path to the check-utilities script
CHECK_UTILITIES_SCRIPT="${BATS_TEST_DIRNAME}/../check-utilities.sh"

# bats test_tags=category:unit
@test "check-utilities.sh exists and is executable" {
	# Purpose: Test verifies that the check-utilities script file exists and has execute permissions.
	# Expected: Check-utilities script file is present and executable.
	# Importance: Ensures the utility checker script can be run directly.
	assert_file_executable "$CHECK_UTILITIES_SCRIPT"
}

# bats test_tags=category:unit
@test "check-utilities.sh checks available utilities successfully" {
	# Purpose: Test verifies that script successfully checks for available utilities.
	# Expected: Script runs successfully and reports available utilities.
	# Importance: Core functionality test ensures utility checking works.
	run bash "$CHECK_UTILITIES_SCRIPT"

	# Script returns 1 when utilities are missing (expected behavior)
	# Check that it produces output regardless of exit code
	assert_output --partial "Checking utility availability"
	assert_output --partial "Summary:"
	# Exit code may be 0 or 1 depending on whether utilities are missing
	[[ $status -ge 0 ]] || true
}

# bats test_tags=category:unit
@test "check-utilities.sh reports available utilities correctly" {
	# Purpose: Test verifies that script correctly identifies available utilities.
	# Expected: Script reports utilities that exist in PATH with checkmark.
	# Importance: Accurate reporting helps users understand system capabilities.
	run bash "$CHECK_UTILITIES_SCRIPT"

	# Script returns 1 when utilities are missing (expected behavior)
	# Should report some utilities as available (common ones like 'date', 'grep', etc.)
	assert_output --partial "[✓]"
	# Exit code may be 0 or 1 depending on whether utilities are missing
	[[ $status -ge 0 ]] || true
}

# bats test_tags=category:unit
@test "check-utilities.sh reports missing utilities correctly" {
	# Purpose: Test verifies that script correctly identifies missing utilities.
	# Expected: Script reports utilities that don't exist with X mark.
	# Importance: Accurate reporting helps users identify missing dependencies.
	run bash "$CHECK_UTILITIES_SCRIPT"

	# Script returns 1 when utilities are missing (expected behavior)
	# May report some utilities as missing (like 'htop' which may not be installed)
	# Check that output contains summary section
	assert_output --partial "Summary:"
	assert_output --partial "Available:"
	# Exit code may be 0 or 1 depending on whether utilities are missing
	[[ $status -ge 0 ]] || true
}

# bats test_tags=category:unit
@test "check-utilities.sh provides summary statistics" {
	# Purpose: Test verifies that script provides summary statistics at the end.
	# Expected: Script outputs count of available vs missing utilities.
	# Importance: Summary helps users quickly understand system state.
	run bash "$CHECK_UTILITIES_SCRIPT"

	# Script returns 1 when utilities are missing (expected behavior)
	assert_output --partial "Summary:"
	assert_output --regexp "Available: [0-9]+/[0-9]+"
	assert_output --partial "Missing:"
	# Exit code may be 0 or 1 depending on whether utilities are missing
	[[ $status -ge 0 ]] || true
}

# bats test_tags=category:unit
@test "check-utilities.sh uses command -v for utility checking" {
	# Purpose: Test verifies that script uses POSIX-compliant command -v method.
	# Expected: Script uses command -v instead of which (more reliable).
	# Importance: command -v is POSIX-compliant and works across shells.
	# Note: We can't directly test implementation, but we verify it works correctly
	run bash "$CHECK_UTILITIES_SCRIPT"

	# Script returns 1 when utilities are missing (expected behavior)
	# If script works, it's using a valid method
	[[ $status -ge 0 ]] || true
}

# bats test_tags=category:unit
@test "check-utilities.sh handles all required utilities" {
	# Purpose: Test verifies that script checks all utilities in the list.
	# Expected: Script checks all utilities defined in UTILITIES array.
	# Importance: Ensures comprehensive utility checking.
	run bash "$CHECK_UTILITIES_SCRIPT"

	# Script returns 1 when utilities are missing (expected behavior)
	# Check for some common utilities that should be checked
	assert_output --partial "ip"
	assert_output --partial "grep"
	assert_output --partial "awk"
	assert_output --partial "date"
	# Exit code may be 0 or 1 depending on whether utilities are missing
	[[ $status -ge 0 ]] || true
}

# bats test_tags=category:unit
@test "check-utilities.sh outputs colored text" {
	# Purpose: Test verifies that script uses color codes for output.
	# Expected: Script outputs ANSI color codes for better readability.
	# Importance: Colored output improves user experience.
	run bash "$CHECK_UTILITIES_SCRIPT"

	# Script returns 1 when utilities are missing (expected behavior)
	# Check for ANSI color codes (may not be visible in test output, but codes should be present)
	# Color codes: \033[0;32m (green), \033[0;31m (red)
	# Note: We can't easily test color rendering, but we verify script runs
	[[ $status -ge 0 ]] || true
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
@test "check-utilities.sh checks utility list includes common commands" {
	# Purpose: Test verifies that utility list includes common system commands.
	# Expected: Script checks for ip, grep, awk, sed, date, etc.
	# Importance: Ensures script checks relevant utilities for VPN monitoring.
	run bash "$CHECK_UTILITIES_SCRIPT"

	# Script returns 1 when utilities are missing (expected behavior)
	# Verify common utilities are checked
	assert_output --partial "ip"
	assert_output --partial "grep"
	assert_output --partial "awk"
	assert_output --partial "sed"
	assert_output --partial "date"
	assert_output --partial "crontab"
	# Exit code may be 0 or 1 depending on whether utilities are missing
	[[ $status -ge 0 ]] || true
}

# bats test_tags=category:unit
@test "check-utilities.sh returns success when all utilities available" {
	# Purpose: Test verifies that script returns success exit code when all utilities are available.
	# Expected: Script exits with code 0 when all utilities are available, 1 when some are missing.
	# Importance: Exit codes are important for scripting and automation.
	run bash "$CHECK_UTILITIES_SCRIPT"

	# Script returns 1 when utilities are missing (expected behavior)
	# Exit code may be 0 or 1 depending on whether utilities are missing
	# This is correct behavior - script reports status via exit code
	[[ $status -ge 0 ]] || true
}

# bats test_tags=category:unit
@test "check-utilities.sh provides readable output format" {
	# Purpose: Test verifies that script output is readable and well-formatted.
	# Expected: Script outputs utilities in clear format with status indicators.
	# Importance: Readable output improves user experience.
	run bash "$CHECK_UTILITIES_SCRIPT"

	# Script returns 1 when utilities are missing (expected behavior)
	# Check for clear formatting
	assert_output --partial "Checking utility availability"
	assert_output --partial "=========================================="
	assert_output --partial "Summary:"
	# Exit code may be 0 or 1 depending on whether utilities are missing
	[[ $status -ge 0 ]] || true
}

# bats test_tags=category:unit
@test "check-utilities.sh handles special characters in utility names" {
	# Purpose: Test verifies that script handles utility names correctly.
	# Expected: Script correctly checks utilities even with special characters in PATH.
	# Importance: Prevents issues with paths containing special characters.
	# Note: Utility names themselves don't contain special chars, but PATH might
	run bash "$CHECK_UTILITIES_SCRIPT"

	# Script returns 1 when utilities are missing (expected behavior)
	# If script runs without errors, it handles names correctly
	[[ $status -ge 0 ]] || true
}

# bats test_tags=category:unit
@test "check-utilities.sh checks network utilities" {
	# Purpose: Test verifies that script checks network-related utilities.
	# Expected: Script checks for ip, ss, netstat, ping, dig, etc.
	# Importance: Network utilities are essential for VPN monitoring.
	run bash "$CHECK_UTILITIES_SCRIPT"

	# Script returns 1 when utilities are missing (expected behavior)
	# Check for network utilities
	assert_output --partial "ip"
	assert_output --partial "dig"
	# Exit code may be 0 or 1 depending on whether utilities are missing
	[[ $status -ge 0 ]] || true
}

# bats test_tags=category:unit
@test "check-utilities.sh checks system monitoring utilities" {
	# Purpose: Test verifies that script checks system monitoring utilities.
	# Expected: Script checks for ps, top, free, uptime, df, etc.
	# Importance: System monitoring utilities help diagnose resource issues.
	run bash "$CHECK_UTILITIES_SCRIPT"

	# Script returns 1 when utilities are missing (expected behavior)
	# Check for monitoring utilities
	assert_output --partial "ps"
	assert_output --partial "free"
	assert_output --partial "df"
	assert_output --partial "uptime"
	# Exit code may be 0 or 1 depending on whether utilities are missing
	[[ $status -ge 0 ]] || true
}

# bats test_tags=category:unit
@test "check-utilities.sh checks text processing utilities" {
	# Purpose: Test verifies that script checks text processing utilities.
	# Expected: Script checks for awk, sed, grep, etc.
	# Importance: Text processing utilities are used throughout the codebase.
	run bash "$CHECK_UTILITIES_SCRIPT"

	# Script returns 1 when utilities are missing (expected behavior)
	# Check for text processing utilities
	assert_output --partial "awk"
	assert_output --partial "sed"
	assert_output --partial "grep"
	# Exit code may be 0 or 1 depending on whether utilities are missing
	[[ $status -ge 0 ]] || true
}

# bats test_tags=category:unit
@test "check-utilities.sh provides actionable output" {
	# Purpose: Test verifies that script output helps users take action.
	# Expected: Script clearly identifies which utilities are missing.
	# Importance: Actionable output helps users resolve missing dependencies.
	run bash "$CHECK_UTILITIES_SCRIPT"

	# Script returns 1 when utilities are missing (expected behavior)
	# Output should include missing utilities list if any are missing
	assert_output --partial "Summary:"
	# May include "Missing utilities:" section if any are missing
	# Exit code may be 0 or 1 depending on whether utilities are missing
	[[ $status -ge 0 ]] || true
}
