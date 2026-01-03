#!/usr/bin/env bats
#
# Tests for uninstall.sh script
# Tests uninstallation functionality, cleanup, and error handling

load test_helper

# Path to the uninstall script
UNINSTALL_SCRIPT="${BATS_TEST_DIRNAME}/../uninstall.sh"

# bats test_tags=category:unit
@test "uninstall.sh exists and is executable" {
	# Purpose: Test verifies that the uninstall script file exists and has execute permissions
	# Expected: Uninstall script file is present and executable
	# Importance: Ensures the uninstallation script can be run directly without requiring bash explicitly
	assert_file_exist "$UNINSTALL_SCRIPT"
	assert_file_executable "$UNINSTALL_SCRIPT"
}

# bats test_tags=category:unit
@test "uninstall.sh requires root" {
	# Purpose: Test verifies that the uninstall script enforces root requirement for uninstallation
	# Expected: Script exits with failure status and displays error message when run without root privileges
	# Importance: Uninstallation requires root access to remove system files and cron entries
	# Skip condition: Cannot test non-root requirement when running as root (test requires non-root user to verify root requirement)
	[[ $EUID -eq 0 ]] && skip "Cannot test root requirement when running as root (test requires non-root user to verify uninstall fails without root privileges)"
	run bash "$UNINSTALL_SCRIPT"
	assert_failure
	assert_output --partial "must be run as root"
}

# bats test_tags=category:unit
@test "uninstall.sh handles missing installation gracefully" {
	# Purpose: Test verifies that the uninstall script handles cases where installation doesn't exist gracefully
	# Expected: Script exits successfully with informative message when no installation is found
	# Importance: Prevents errors when uninstall is run multiple times or on systems without installation
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Ensure installation directory doesn't exist
	rm -rf /data/vpn-monitor 2>/dev/null || true

	run bash "$UNINSTALL_SCRIPT" --yes
	# Should succeed even if nothing to uninstall
	assert_success
	assert_output --partial "Installation directory not found"
}

# bats test_tags=category:unit
@test "uninstall.sh removes installation directory" {
	# Purpose: Test verifies that the uninstall script removes the installation directory and all its contents
	# Expected: Installation directory is completely removed during uninstallation process
	# Importance: Ensures complete removal of all installed files and directories
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"
	echo "test" >"${install_dir}/vpn-monitor.conf"

	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success

	# Check directory was removed
	assert_dir_not_exist "$install_dir"

	# Clean up if test failed
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh removes cron entry" {
	# Purpose: Test verifies that the uninstall script removes the cron job entry during uninstallation
	# Expected: Script removes vpn-monitor cron entry from crontab, preventing scheduled execution
	# Importance: Ensures complete removal of all installation components including scheduled tasks
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create test cron entry
	create_test_cron_entry "*/1 * * * *" "/data/vpn-monitor/vpn-monitor.sh"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success

	# Check cron entry was removed
	run crontab -l 2>/dev/null
	if [[ $status -eq 0 ]]; then
		refute_output --partial "vpn-monitor.sh"
	fi

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true
}

# bats test_tags=category:unit
@test "uninstall.sh removes cron entry even if installation directory missing" {
	# Purpose: Test verifies that the uninstall script removes cron entry even when installation directory is missing
	# Expected: Script removes cron entry regardless of installation directory state, ensuring complete cleanup
	# Importance: Handles partial installations where cron was created but directory was removed separately
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create test cron entry
	create_test_cron_entry "*/1 * * * *" "/data/vpn-monitor/vpn-monitor.sh"

	# Don't create installation directory

	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success

	# Check cron entry was still removed
	run crontab -l 2>/dev/null
	if [[ $status -eq 0 ]]; then
		refute_output --partial "vpn-monitor.sh"
	fi

	# Clean up
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true
}

# bats test_tags=category:unit
@test "uninstall.sh verifies uninstallation" {
	# Purpose: Test verifies that the uninstall script performs post-uninstallation verification checks
	# Expected: Script verifies that all components are removed and outputs success message
	# Importance: Verification ensures uninstallation completed successfully and no components remain
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Create test cron entry
	create_test_cron_entry "*/1 * * * *" "/data/vpn-monitor/vpn-monitor.sh"

	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success

	# Check verification output
	assert_output --partial "Uninstallation verified successfully"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true
}

# bats test_tags=category:unit
@test "uninstall.sh prompts for confirmation in interactive mode" {
	# Purpose: Test verifies that the uninstall script prompts for user confirmation before proceeding
	# Expected: Script displays confirmation prompt and cancels uninstallation when user responds "no"
	# Importance: Confirmation prompt prevents accidental uninstallation and data loss
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Test with "no" response
	run bash "$UNINSTALL_SCRIPT" <<<"no"
	assert_success
	assert_output --partial "Uninstallation cancelled"

	# Directory should still exist
	assert_dir_exist "$install_dir"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh skips prompt with --yes flag" {
	# Purpose: Test verifies that the uninstall script skips confirmation prompt when --yes flag is provided
	# Expected: Script proceeds with uninstallation immediately without prompting for confirmation
	# Importance: Allows automated uninstallation in scripts and CI/CD environments without user interaction
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success

	# Should not prompt
	refute_output --partial "Are you sure"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh skips prompt in CI environment" {
	# Purpose: Test verifies that the uninstall script skips confirmation prompt when CI environment variable is set
	# Expected: Script proceeds with uninstallation automatically without prompting when CI=1 is set
	# Importance: Allows automated uninstallation in CI/CD environments without requiring --yes flag
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"
	export CI=1

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	run bash "$UNINSTALL_SCRIPT"
	assert_success

	# Should not prompt
	refute_output --partial "Are you sure"

	# Clean up
	unset CI
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh lists files before removal" {
	# Purpose: Test verifies that the uninstall script displays list of files that will be removed before uninstallation
	# Expected: Script lists all files and directories that will be deleted, providing transparency to users
	# Importance: File listing helps users understand what will be removed and prevents accidental data loss
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory with multiple files
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test1" >"${install_dir}/vpn-monitor.sh"
	echo "test2" >"${install_dir}/vpn-monitor.conf"
	mkdir -p "${install_dir}/logs"
	echo "test3" >"${install_dir}/logs/vpn-monitor.log"

	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success

	# Should list files
	assert_output --partial "The following will be removed"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh cleans up stale lockfiles" {
	# Purpose: Test verifies that the uninstall script removes lockfiles during uninstallation cleanup
	# Expected: Script removes lockfiles along with installation directory, preventing stale lock issues
	# Importance: Lockfile cleanup ensures clean uninstallation and prevents lockfile conflicts on reinstall
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Create a lockfile (should be removed with directory)
	echo "1234567890:12345" >"${install_dir}/vpn-monitor.lock"

	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success

	# Lockfile should be gone
	assert_file_not_exist "${install_dir}/vpn-monitor.lock"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh displays summary after successful uninstall" {
	# Purpose: Test verifies that the uninstall script displays summary information after successful uninstallation
	# Expected: Script outputs summary message listing what was removed and confirming successful uninstallation
	# Importance: Summary output provides user feedback and confirmation that uninstallation completed successfully
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success

	# Check summary output
	assert_output --partial "Uninstallation complete"
	assert_output --partial "Removed:"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh removes logrotate configuration when it exists" {
	# Purpose: Test verifies that the uninstall script removes logrotate configuration file when it exists
	# Expected: Script removes logrotate configuration file from /etc/logrotate.d/ during uninstallation
	# Importance: Ensures complete cleanup of all installation components including log rotation configuration
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Create logrotate config file
	local logrotate_config="/etc/logrotate.d/vpn-monitor-cron"
	mkdir -p "$(dirname "$logrotate_config")"
	echo "# Test logrotate config" >"$logrotate_config"

	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success

	# Check logrotate config was removed
	assert_file_not_exist "$logrotate_config"
	assert_output --partial "Logrotate configuration removed"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
	rm -f "$logrotate_config" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh handles missing logrotate configuration gracefully" {
	# Purpose: Test verifies that the uninstall script handles missing logrotate configuration gracefully
	# Expected: Script continues uninstallation successfully and reports that logrotate config was not found
	# Importance: Prevents errors when logrotate config doesn't exist, allowing uninstallation to proceed normally
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Ensure logrotate config doesn't exist
	local logrotate_config="/etc/logrotate.d/vpn-monitor-cron"
	rm -f "$logrotate_config" 2>/dev/null || true

	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success

	# Should handle missing logrotate config gracefully
	assert_output --partial "Logrotate configuration not found"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh handles read-only logrotate directory gracefully" {
	# Purpose: Test verifies that the uninstall script handles read-only logrotate directory gracefully
	# Expected: Script reports that logrotate config cannot be removed and provides manual removal instructions
	# Importance: Prevents script failure when logrotate directory is read-only, allowing uninstallation to continue
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Create logrotate config file
	local logrotate_config="/etc/logrotate.d/vpn-monitor-cron"
	mkdir -p "$(dirname "$logrotate_config")"
	echo "# Test logrotate config" >"$logrotate_config"

	# Make logrotate directory read-only
	chmod 555 "$(dirname "$logrotate_config")"

	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success

	# Should handle read-only directory gracefully
	assert_output --partial "Cannot write to /etc/logrotate.d"
	assert_output --partial "Manual removal required"

	# Restore permissions and clean up
	chmod 755 "$(dirname "$logrotate_config")"
	rm -rf "$install_dir" 2>/dev/null || true
	rm -f "$logrotate_config" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh verifies uninstallation includes logrotate config check" {
	# Purpose: Test verifies that uninstallation verification includes checking for logrotate configuration removal
	# Expected: Script verifies that logrotate config was removed and includes it in verification success message
	# Importance: Ensures verification process checks all components including logrotate configuration
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Create logrotate config file
	local logrotate_config="/etc/logrotate.d/vpn-monitor-cron"
	mkdir -p "$(dirname "$logrotate_config")"
	echo "# Test logrotate config" >"$logrotate_config"

	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success

	# Verification should check logrotate config
	assert_output --partial "Logrotate configuration removed"
	assert_output --partial "Uninstallation verified successfully"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
	rm -f "$logrotate_config" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh verification fails when logrotate config still exists" {
	# Purpose: Test verifies that uninstallation verification detects when logrotate config still exists
	# Expected: Script reports verification failure when logrotate config cannot be removed (e.g., read-only file)
	# Importance: Verification failure detection alerts users to incomplete uninstallation requiring manual cleanup
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Create logrotate config file that we'll make read-only to prevent removal
	local logrotate_config="/etc/logrotate.d/vpn-monitor-cron"
	mkdir -p "$(dirname "$logrotate_config")"
	echo "# Test logrotate config" >"$logrotate_config"
	chmod 444 "$logrotate_config"

	run bash "$UNINSTALL_SCRIPT" --yes
	# Script should still succeed but verification should detect the issue
	assert_success

	# Verification should detect logrotate config still exists
	assert_output --partial "Logrotate configuration still exists"

	# Restore permissions and clean up
	chmod 644 "$logrotate_config"
	rm -rf "$install_dir" 2>/dev/null || true
	rm -f "$logrotate_config" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh check_installation returns 0 when installation exists" {
	# Purpose: Test verifies that check_installation function correctly detects when installation exists
	# Expected: Function returns success (0) and script proceeds with uninstallation when installation directory exists
	# Importance: Ensures installation detection works correctly before attempting uninstallation
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Test check_installation through main flow - should detect installation
	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success
	# Should proceed with uninstallation (not exit early)
	refute_output --partial "No installation found"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh check_installation returns 1 when installation missing" {
	# Purpose: Test verifies that check_installation function correctly detects when installation is missing
	# Expected: Function detects missing installation and script exits with informative message
	# Importance: Prevents unnecessary uninstallation attempts when no installation exists
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Ensure installation directory doesn't exist
	rm -rf /data/vpn-monitor 2>/dev/null || true

	# Test check_installation through main flow - should detect missing installation
	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success
	assert_output --partial "Installation directory not found"
	assert_output --partial "No installation found"

	# Clean up
	rm -rf /data/vpn-monitor 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh remove_cron handles crontab with only vpn-monitor entry" {
	# Purpose: Test verifies that remove_cron function handles crontab containing only vpn-monitor entry correctly
	# Expected: Function removes vpn-monitor cron entry and handles empty crontab gracefully
	# Importance: Ensures cron removal works correctly even when vpn-monitor is the only cron job
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create test cron entry (only entry)
	create_test_cron_entry "*/1 * * * *" "/data/vpn-monitor/vpn-monitor.sh"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Test remove_cron through main flow
	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success
	assert_output --partial "Cron job removed"

	# Verify cron entry was removed (crontab should be empty or not exist)
	run crontab -l 2>/dev/null
	if [[ $status -eq 0 ]]; then
		refute_output --partial "vpn-monitor.sh"
	fi

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true
}

# bats test_tags=category:unit
@test "uninstall.sh remove_cron handles missing cron entry gracefully" {
	# Purpose: Test verifies that remove_cron function handles missing cron entry gracefully
	# Expected: Function reports that cron job was not found and continues uninstallation successfully
	# Importance: Prevents errors when cron entry doesn't exist, allowing uninstallation to proceed normally
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Ensure no vpn-monitor cron entry exists
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Test remove_cron through main flow
	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success
	assert_output --partial "Cron job not found"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh remove_logrotate_config handles removal failure" {
	# Purpose: Test verifies that remove_logrotate_config function handles removal failures gracefully
	# Expected: Function reports removal failure and provides manual removal instructions when directory is read-only
	# Importance: Prevents script failure when logrotate config cannot be removed, allowing uninstallation to continue
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Create logrotate config file
	local logrotate_config="/etc/logrotate.d/vpn-monitor-cron"
	mkdir -p "$(dirname "$logrotate_config")"
	echo "# Test logrotate config" >"$logrotate_config"

	# Make logrotate directory read-only to simulate removal failure
	chmod 555 "$(dirname "$logrotate_config")"

	# Test remove_logrotate_config through main flow
	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success
	# Should handle read-only directory gracefully
	assert_output --partial "Cannot write to /etc/logrotate.d"
	assert_output --partial "Manual removal required"

	# Restore permissions and clean up
	chmod 755 "$(dirname "$logrotate_config")"
	rm -rf "$install_dir" 2>/dev/null || true
	rm -f "$logrotate_config" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh remove_installation_dir handles missing directory gracefully" {
	# Purpose: Test verifies that remove_installation_dir function handles missing directory gracefully
	# Expected: Function completes successfully even when installation directory doesn't exist
	# Importance: Prevents errors when directory is already removed, allowing uninstallation to complete normally
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create installation directory first, then remove it manually
	# to simulate it being removed before remove_installation_dir is called
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Remove directory manually before running uninstall
	rm -rf "$install_dir"

	# Run uninstall - should handle missing directory gracefully
	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success
	# Should still complete successfully even if directory already gone

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh remove_installation_dir lists files before removal" {
	# Purpose: Test verifies that remove_installation_dir function lists files before removing installation directory
	# Expected: Function displays list of files that will be removed and confirms successful directory removal
	# Importance: File listing provides transparency to users about what will be deleted during uninstallation
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory with multiple files
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test1" >"${install_dir}/vpn-monitor.sh"
	echo "test2" >"${install_dir}/vpn-monitor.conf"
	mkdir -p "${install_dir}/logs"
	echo "test3" >"${install_dir}/logs/vpn-monitor.log"

	# Test remove_installation_dir through main flow
	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success
	assert_output --partial "The following will be removed"
	assert_output --partial "Installation directory removed successfully"

	# Verify directory was removed
	assert_dir_not_exist "$install_dir"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh cleanup_lockfile handles missing lockfile" {
	# Purpose: Test verifies that cleanup_lockfile function handles missing lockfile gracefully
	# Expected: Function completes successfully without errors when lockfile doesn't exist
	# Importance: Prevents errors when lockfile is already removed or never existed
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory without lockfile
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Test cleanup_lockfile through main flow - should complete successfully
	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success
	# Should not output anything about stale lockfile when it doesn't exist

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh cleanup_lockfile removes stale lockfile" {
	# Purpose: Test verifies that cleanup_lockfile function removes stale lockfiles during uninstallation
	# Expected: Function detects and removes stale lockfile, reporting successful cleanup
	# Importance: Lockfile cleanup prevents lock conflicts on reinstallation and ensures clean uninstallation
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Create a lockfile
	echo "1234567890:12345" >"${install_dir}/vpn-monitor.lock"

	# Test cleanup_lockfile through main flow
	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success
	assert_output --partial "Found stale lockfile"

	# Verify lockfile was removed (directory should be gone too)
	assert_dir_not_exist "$install_dir"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh verify_uninstallation detects cron entry still exists" {
	# Purpose: Test verifies that verify_uninstallation function detects when cron entry still exists after uninstallation
	# Expected: Function returns failure status and reports that cron entry still exists
	# Importance: Verification failure detection alerts users to incomplete uninstallation requiring manual cleanup
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create test cron entry
	create_test_cron_entry "*/1 * * * *" "/data/vpn-monitor/vpn-monitor.sh"

	# Create and then manually remove installation directory (simulating partial removal)
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"
	rm -rf "$install_dir"

	# Create a wrapper script that calls verify_uninstallation
	# We'll simulate a failed cron removal by not removing the cron entry
	# and then calling verify_uninstallation
	local test_script="${BATS_TEST_TMPDIR}/test_verify.sh"
	cat >"$test_script" <<EOF
#!/bin/bash
source "$UNINSTALL_SCRIPT"
verify_uninstallation
EOF
	chmod +x "$test_script"

	# Test verify_uninstallation - should detect cron entry still exists
	run bash "$test_script"
	assert_failure
	assert_output --partial "Cron entry still exists"
	assert_output --partial "Uninstallation verification failed"

	# Clean up
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true
	rm -f "$test_script" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh verify_uninstallation detects installation directory still exists" {
	# Purpose: Test verifies that verify_uninstallation function detects when installation directory still exists
	# Expected: Function returns failure status and reports that installation directory still exists
	# Importance: Verification failure detection alerts users to incomplete uninstallation requiring manual cleanup
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Ensure no cron entry exists
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true

	# Create a wrapper script that calls verify_uninstallation
	local test_script="${BATS_TEST_TMPDIR}/test_verify.sh"
	cat >"$test_script" <<EOF
#!/bin/bash
source "$UNINSTALL_SCRIPT"
verify_uninstallation
EOF
	chmod +x "$test_script"

	# Test verify_uninstallation - should detect directory still exists
	run bash "$test_script"
	assert_failure
	assert_output --partial "Installation directory still exists"
	assert_output --partial "Uninstallation verification failed"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
	rm -f "$test_script" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh verify_uninstallation detects multiple remaining components" {
	# Purpose: Test verifies that verify_uninstallation function detects multiple remaining components after uninstallation
	# Expected: Function returns failure status and reports all remaining components (directory, cron, logrotate)
	# Importance: Comprehensive verification ensures all components are checked and users are informed of all issues
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Create test cron entry
	create_test_cron_entry "*/1 * * * *" "/data/vpn-monitor/vpn-monitor.sh"

	# Create logrotate config file
	local logrotate_config="/etc/logrotate.d/vpn-monitor-cron"
	mkdir -p "$(dirname "$logrotate_config")"
	echo "# Test logrotate config" >"$logrotate_config"

	# Create a wrapper script that calls verify_uninstallation
	local test_script="${BATS_TEST_TMPDIR}/test_verify.sh"
	cat >"$test_script" <<EOF
#!/bin/bash
source "$UNINSTALL_SCRIPT"
verify_uninstallation
EOF
	chmod +x "$test_script"

	# Test verify_uninstallation - should detect all components still exist
	run bash "$test_script"
	assert_failure
	assert_output --partial "Installation directory still exists"
	assert_output --partial "Cron entry still exists"
	assert_output --partial "Logrotate configuration still exists"
	# Use regex to match error count pattern
	assert_output --regexp 'Uninstallation verification failed with [0-9]+ error\(s\)'

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true
	rm -f "$logrotate_config" 2>/dev/null || true
	rm -f "$test_script" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh verify_uninstallation succeeds when all components removed" {
	# Purpose: Test verifies that verify_uninstallation function succeeds when all components are removed
	# Expected: Function returns success status and confirms all components (directory, cron, logrotate) were removed
	# Importance: Successful verification confirms complete uninstallation and provides user confidence
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Ensure all components are removed
	rm -rf /data/vpn-monitor 2>/dev/null || true
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true
	rm -f /etc/logrotate.d/vpn-monitor-cron 2>/dev/null || true

	# Create a wrapper script that calls verify_uninstallation
	local test_script="${BATS_TEST_TMPDIR}/test_verify.sh"
	cat >"$test_script" <<EOF
#!/bin/bash
source "$UNINSTALL_SCRIPT"
verify_uninstallation
EOF
	chmod +x "$test_script"

	# Test verify_uninstallation - should succeed
	run bash "$test_script"
	assert_success
	assert_output --partial "Installation directory removed"
	assert_output --partial "Cron entry removed"
	assert_output --partial "Logrotate configuration removed"
	assert_output --partial "Uninstallation verified successfully"

	# Clean up
	rm -f "$test_script" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh full uninstallation flow with all components" {
	# Purpose: Test verifies complete uninstallation flow removes all components (directory, cron, logrotate)
	# Expected: Script removes installation directory, cron entry, and logrotate config, then verifies successful removal
	# Importance: End-to-end test ensures all uninstallation components work together correctly
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create complete mock installation
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"
	echo "test" >"${install_dir}/vpn-monitor.conf"
	mkdir -p "${install_dir}/logs"
	echo "test" >"${install_dir}/logs/vpn-monitor.log"

	# Create test cron entry
	create_test_cron_entry "*/1 * * * *" "/data/vpn-monitor/vpn-monitor.sh"

	# Create logrotate config file
	local logrotate_config="/etc/logrotate.d/vpn-monitor-cron"
	mkdir -p "$(dirname "$logrotate_config")"
	echo "# Test logrotate config" >"$logrotate_config"

	# Run full uninstallation
	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success

	# Verify all components were removed
	assert_dir_not_exist "$install_dir"
	run crontab -l 2>/dev/null
	if [[ $status -eq 0 ]]; then
		refute_output --partial "vpn-monitor.sh"
	fi
	assert_file_not_exist "$logrotate_config"

	# Verify output contains success messages
	assert_output --partial "Cron job removed"
	assert_output --partial "Logrotate configuration removed"
	assert_output --partial "Installation directory removed successfully"
	assert_output --partial "Uninstallation verified successfully"
	assert_output --partial "Uninstallation complete"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true
	rm -f "$logrotate_config" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh handles interactive confirmation with yes" {
	# Purpose: Test verifies that uninstall script handles interactive confirmation when user responds "yes"
	# Expected: Script proceeds with uninstallation when user confirms with "yes" response
	# Importance: Ensures interactive mode works correctly for users who want to confirm uninstallation
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Test with "yes" response
	run bash "$UNINSTALL_SCRIPT" <<<"yes"
	assert_success
	assert_output --partial "Uninstallation complete"

	# Directory should be removed
	assert_dir_not_exist "$install_dir"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh remove_cron preserves other cron entries" {
	# Purpose: Test verifies that remove_cron function only removes vpn-monitor cron entry, preserving other entries
	# Expected: Function removes vpn-monitor cron entry while leaving other cron entries intact
	# Importance: Prevents accidental removal of unrelated cron jobs during uninstallation
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Save original crontab
	local original_crontab
	original_crontab=$(crontab -l 2>/dev/null || echo "")

	# Create test cron entries
	create_test_cron_entry "*/5 * * * *" "/some/other/script.sh"
	create_test_cron_entry "*/1 * * * *" "/data/vpn-monitor/vpn-monitor.sh"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Test remove_cron through main flow
	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success

	# Verify vpn-monitor entry was removed but other entry remains
	run crontab -l 2>/dev/null
	assert_success
	refute_output --partial "vpn-monitor.sh"
	assert_output --partial "/some/other/script.sh"

	# Restore original crontab
	if [[ -n "$original_crontab" ]]; then
		echo "$original_crontab" | crontab -
	else
		crontab -r 2>/dev/null || true
	fi

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true
}

# bats test_tags=category:unit
@test "uninstall.sh removes config file with --remove-config flag" {
	# Purpose: Test verifies that the uninstall script removes the configuration file when --remove-config flag is provided
	# Expected: Configuration file is removed during uninstallation when --remove-config flag is used
	# Importance: Ensures users can explicitly request config file removal for non-interactive uninstallation
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory with config file
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"
	echo "LOCATION_TEST_EXTERNAL=\"192.168.1.1\"" >"${install_dir}/vpn-monitor.conf"
	echo "LOCATION_TEST_INTERNAL=\"192.168.1.1\"" >>"${install_dir}/vpn-monitor.conf"

	run bash "$UNINSTALL_SCRIPT" --yes --remove-config
	assert_success

	# Check directory was removed (including config file)
	assert_dir_not_exist "$install_dir"

	# Clean up if test failed
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh keeps config file in-place with --keep-config flag" {
	# Purpose: Test verifies that the uninstall script keeps the configuration file in-place when --keep-config flag is provided
	# Expected: Configuration file is preserved at /data/vpn-monitor/vpn-monitor.conf, other files are removed
	# Importance: Ensures users can preserve their configuration during uninstallation for future reference or reuse
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory with config file and other files
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"
	mkdir -p "${install_dir}/logs"
	echo "log content" >"${install_dir}/logs/vpn-monitor.log"
	local config_content="LOCATION_TEST_EXTERNAL=\"192.168.1.1\"
LOCATION_TEST_INTERNAL=\"192.168.1.1\"
VPN_NAME=\"Test VPN\""
	echo "$config_content" >"${install_dir}/vpn-monitor.conf"

	run bash "$UNINSTALL_SCRIPT" --yes --keep-config
	assert_success

	# Check directory still exists
	assert_dir_exist "$install_dir"
	# Check config file is preserved
	assert_file_exist "${install_dir}/vpn-monitor.conf"
	# Check config content matches original
	assert_file_contains "${install_dir}/vpn-monitor.conf" "LOCATION_TEST_EXTERNAL"
	assert_file_contains "${install_dir}/vpn-monitor.conf" "VPN_NAME"
	# Check other files are removed
	assert_file_not_exist "${install_dir}/vpn-monitor.sh"
	assert_dir_not_exist "${install_dir}/logs"
	# Check output mentions config preserved
	assert_output --partial "Configuration file preserved at"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh handles missing config file gracefully" {
	# Purpose: Test verifies that the uninstall script handles cases where config file doesn't exist gracefully
	# Expected: Script continues uninstallation successfully even if config file is missing
	# Importance: Prevents errors when config file was never created or already removed
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory without config file
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"
	# Intentionally don't create config file

	run bash "$UNINSTALL_SCRIPT" --yes --keep-config
	assert_success

	# Check directory was removed (since no config file existed)
	assert_dir_not_exist "$install_dir"
	# Check output doesn't mention config preserved (since it didn't exist)
	refute_output --partial "Configuration file preserved at"

	# Clean up if test failed
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh displays config location in summary when config is kept" {
	# Purpose: Test verifies that the uninstall script displays the config file location in the summary when config file is kept
	# Expected: Summary output includes information about config file location
	# Importance: Helps users locate their preserved configuration file after uninstallation
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory with config file
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"
	echo "LOCATION_TEST_EXTERNAL=\"192.168.1.1\"" >"${install_dir}/vpn-monitor.conf"
	echo "LOCATION_TEST_INTERNAL=\"192.168.1.1\"" >>"${install_dir}/vpn-monitor.conf"

	run bash "$UNINSTALL_SCRIPT" --yes --keep-config
	assert_success

	# Check summary mentions config location
	assert_output --partial "Configuration file preserved at"
	assert_output --partial "/data/vpn-monitor/vpn-monitor.conf"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh detects conflicting config flags" {
	# Purpose: Test verifies that the uninstall script detects and errors on conflicting flags
	# Expected: Script exits with error when both --remove-config and --keep-config are provided
	# Importance: Prevents user confusion and ensures clear behavior
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"

	# Test with conflicting flags
	run bash "$UNINSTALL_SCRIPT" --yes --remove-config --keep-config
	assert_failure
	assert_output --partial "Conflicting flags"
	assert_output --partial "--remove-config and --keep-config cannot be used together"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
	rm -f /root/vpn-monitor.conf.backup* 2>/dev/null || true
}

# bats test_tags=category:unit
@test "uninstall.sh keeps config file when keeping config multiple times" {
	# Purpose: Test verifies that config file is preserved in-place when keeping config
	# Expected: Config file remains at original location after uninstall with --keep-config
	# Importance: Ensures config file is preserved correctly for reuse
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory with config file
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"
	echo "LOCATION_TEST_EXTERNAL=\"192.168.1.1\"" >"${install_dir}/vpn-monitor.conf"
	echo "LOCATION_TEST_INTERNAL=\"192.168.1.1\"" >>"${install_dir}/vpn-monitor.conf"

	# First uninstall with keep-config
	run bash "$UNINSTALL_SCRIPT" --yes --keep-config
	assert_success
	assert_file_exist "${install_dir}/vpn-monitor.conf"

	# Recreate other files
	echo "test2" >"${install_dir}/vpn-monitor.sh"
	mkdir -p "${install_dir}/logs"
	echo "log" >"${install_dir}/logs/vpn-monitor.log"

	# Second uninstall with keep-config - config should still be there
	run bash "$UNINSTALL_SCRIPT" --yes --keep-config
	assert_success
	assert_file_exist "${install_dir}/vpn-monitor.conf"
	assert_file_not_exist "${install_dir}/vpn-monitor.sh"
	assert_dir_not_exist "${install_dir}/logs"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
}

# bats test_tags=category:unit,priority:high
@test "uninstall.sh validate_install_dir_safety rejects empty INSTALL_DIR" {
	# Purpose: Test verifies that validate_install_dir_safety() rejects empty INSTALL_DIR
	# Expected: Script exits with error when INSTALL_DIR is empty
	# Importance: Prevents accidental deletion when INSTALL_DIR is unset or empty
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create a test script that sources uninstall.sh and sets INSTALL_DIR to empty
	local test_script="${TEST_DIR}/test_uninstall_safety.sh"
	cat >"$test_script" <<'EOF'
#!/bin/bash
set -euo pipefail
# Source the uninstall script functions
source "$(dirname "$0")/../uninstall.sh"
# Set INSTALL_DIR to empty to test validation
INSTALL_DIR=""
# This should exit with error
validate_install_dir_safety
EOF
	chmod +x "$test_script"

	# Run the test script - it should fail
	run bash "$test_script"
	assert_failure
	assert_output --partial "INSTALL_DIR is empty"
	assert_output --partial "unsafe"

	# Clean up
	rm -f "$test_script" 2>/dev/null || true
}

# bats test_tags=category:unit,priority:high
@test "uninstall.sh validate_install_dir_safety rejects wrong path" {
	# Purpose: Test verifies that validate_install_dir_safety() rejects incorrect INSTALL_DIR paths
	# Expected: Script exits with error when INSTALL_DIR doesn't match expected path
	# Importance: Prevents accidental deletion of files outside intended directory
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create a test script that sources uninstall.sh and sets INSTALL_DIR to wrong path
	local test_script="${TEST_DIR}/test_uninstall_safety.sh"
	cat >"$test_script" <<'EOF'
#!/bin/bash
set -euo pipefail
# Source the uninstall script functions
source "$(dirname "$0")/../uninstall.sh"
# Set INSTALL_DIR to wrong path to test validation
INSTALL_DIR="/etc/passwd"
# This should exit with error
validate_install_dir_safety
EOF
	chmod +x "$test_script"

	# Run the test script - it should fail
	run bash "$test_script"
	assert_failure
	assert_output --partial "path mismatch"
	assert_output --partial "Expected: /data/vpn-monitor"
	assert_output --partial "Actual:   /etc/passwd"
	assert_output --partial "unsafe"

	# Clean up
	rm -f "$test_script" 2>/dev/null || true
}

# bats test_tags=category:unit,priority:high
@test "uninstall.sh validate_install_dir_safety rejects root directory" {
	# Purpose: Test verifies that validate_install_dir_safety() rejects root directory (/)
	# Expected: Script exits with error when INSTALL_DIR is root directory
	# Importance: Prevents catastrophic deletion of entire filesystem
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create a test script that sources uninstall.sh and sets INSTALL_DIR to root
	local test_script="${TEST_DIR}/test_uninstall_safety.sh"
	cat >"$test_script" <<'EOF'
#!/bin/bash
set -euo pipefail
# Source the uninstall script functions
source "$(dirname "$0")/../uninstall.sh"
# Set INSTALL_DIR to root directory to test validation
INSTALL_DIR="/"
# This should exit with error
validate_install_dir_safety
EOF
	chmod +x "$test_script"

	# Run the test script - it should fail
	run bash "$test_script"
	assert_failure
	assert_output --partial "root directory"
	assert_output --partial "extremely unsafe"

	# Clean up
	rm -f "$test_script" 2>/dev/null || true
}

# bats test_tags=category:unit,priority:high
@test "uninstall.sh validate_install_dir_safety accepts correct path" {
	# Purpose: Test verifies that validate_install_dir_safety() accepts correct INSTALL_DIR path
	# Expected: Function returns successfully when INSTALL_DIR matches expected path
	# Importance: Ensures validation doesn't reject valid paths
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create a test script that sources uninstall.sh and tests with correct path
	local test_script="${TEST_DIR}/test_uninstall_safety.sh"
	cat >"$test_script" <<'EOF'
#!/bin/bash
set -euo pipefail
# Source the uninstall script functions
source "$(dirname "$0")/../uninstall.sh"
# INSTALL_DIR should already be set correctly by uninstall.sh
# This should succeed
validate_install_dir_safety
echo "Validation passed"
EOF
	chmod +x "$test_script"

	# Run the test script - it should succeed
	run bash "$test_script"
	assert_success
	assert_output --partial "Validation passed"

	# Clean up
	rm -f "$test_script" 2>/dev/null || true
}

# bats test_tags=category:unit,priority:high
@test "uninstall.sh skips symlinks pointing outside installation directory" {
	# Purpose: Test verifies that uninstall script skips symlinks pointing outside INSTALL_DIR
	# Expected: Symlinks pointing outside installation directory are skipped during deletion
	# Importance: Prevents accidental deletion of files outside intended directory via symlinks
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"
	echo "test" >"${install_dir}/vpn-monitor.conf"

	# Create a file outside the installation directory that we want to protect
	local protected_file="${TEST_DIR}/protected-file.txt"
	echo "protected content" >"$protected_file"

	# Create a symlink inside installation directory pointing to protected file
	ln -sf "$protected_file" "${install_dir}/malicious-symlink"

	# Run uninstallation
	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success

	# Verify installation directory was removed
	assert_dir_not_exist "$install_dir"

	# Verify protected file still exists (symlink was skipped, not followed)
	assert_file_exist "$protected_file"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
	rm -f "$protected_file" 2>/dev/null || true
}

# bats test_tags=category:unit,priority:high
@test "uninstall.sh removes symlinks pointing within installation directory" {
	# Purpose: Test verifies that uninstall script removes symlinks pointing within INSTALL_DIR
	# Expected: Symlinks pointing within installation directory are removed normally
	# Importance: Ensures normal symlinks are cleaned up during uninstallation
	# Skip condition: Requires root access to test uninstall functionality (uninstall.sh requires root privileges)
	[[ $EUID -ne 0 ]] && skip "This test requires root access (uninstall.sh requires root privileges to remove system files and cron entries)"

	# Create mock installation directory
	local install_dir="/data/vpn-monitor"
	mkdir -p "$install_dir"
	echo "test" >"${install_dir}/vpn-monitor.sh"
	echo "test content" >"${install_dir}/target-file.txt"

	# Create a symlink inside installation directory pointing to another file in same directory
	ln -sf "target-file.txt" "${install_dir}/normal-symlink"

	# Run uninstallation
	run bash "$UNINSTALL_SCRIPT" --yes
	assert_success

	# Verify installation directory was removed (including symlink)
	assert_dir_not_exist "$install_dir"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
}
