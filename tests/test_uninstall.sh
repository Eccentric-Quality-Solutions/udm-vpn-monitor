#!/usr/bin/env bats
#
# Tests for uninstall.sh script
# Tests uninstallation functionality, cleanup, and error handling

load test_helper

# Path to the uninstall script
UNINSTALL_SCRIPT="${BATS_TEST_DIRNAME}/../uninstall.sh"

@test "uninstall.sh exists and is executable" {
	# Test verifies that the uninstall script file exists and has execute permissions.
	# Expected: Uninstall script file is present and executable.
	# Importance: Ensures the uninstallation script can be run directly without requiring bash explicitly.
	assert_file_exist "$UNINSTALL_SCRIPT"
	assert_file_executable "$UNINSTALL_SCRIPT"
}

@test "uninstall.sh requires root" {
	# Test verifies that the uninstall script enforces root requirement for uninstallation.
	# Expected: Script exits with failure status and displays error message when run without root privileges.
	# Importance: Uninstallation requires root access to remove system files and cron entries.
	# Skip if actually running as root (can't test root requirement)
	[[ $EUID -eq 0 ]] && skip "Cannot test root requirement when running as root"
	run bash "$UNINSTALL_SCRIPT"
	assert_failure
	assert_output --partial "must be run as root"
}

@test "uninstall.sh handles missing installation gracefully" {
	# Test verifies that the uninstall script handles cases where installation doesn't exist gracefully.
	# Expected: Script exits successfully with informative message when no installation is found.
	# Importance: Prevents errors when uninstall is run multiple times or on systems without installation.
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

	# Ensure installation directory doesn't exist
	rm -rf /data/vpn-monitor 2>/dev/null || true

	run bash "$UNINSTALL_SCRIPT" --yes
	# Should succeed even if nothing to uninstall
	assert_success
	assert_output --partial "Installation directory not found"
}

@test "uninstall.sh removes installation directory" {
	# Test verifies that the uninstall script removes the installation directory and all its contents.
	# Expected: Installation directory is completely removed during uninstallation process.
	# Importance: Ensures complete removal of all installed files and directories.
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh removes cron entry" {
	# Test verifies that the uninstall script removes the cron job entry during uninstallation.
	# Expected: Script removes vpn-monitor cron entry from crontab, preventing scheduled execution.
	# Importance: Ensures complete removal of all installation components including scheduled tasks.
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh removes cron entry even if installation directory missing" {
	# Test verifies that the uninstall script removes cron entry even when installation directory is missing.
	# Expected: Script removes cron entry regardless of installation directory state, ensuring complete cleanup.
	# Importance: Handles partial installations where cron was created but directory was removed separately.
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh verifies uninstallation" {
	# Test verifies that the uninstall script performs post-uninstallation verification checks.
	# Expected: Script verifies that all components are removed and outputs success message.
	# Importance: Verification ensures uninstallation completed successfully and no components remain.
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh prompts for confirmation in interactive mode" {
	# Test verifies that the uninstall script prompts for user confirmation before proceeding.
	# Expected: Script displays confirmation prompt and cancels uninstallation when user responds "no".
	# Importance: Confirmation prompt prevents accidental uninstallation and data loss.
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh skips prompt with --yes flag" {
	# Test verifies that the uninstall script skips confirmation prompt when --yes flag is provided.
	# Expected: Script proceeds with uninstallation immediately without prompting for confirmation.
	# Importance: Allows automated uninstallation in scripts and CI/CD environments without user interaction.
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh skips prompt in CI environment" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"
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

@test "uninstall.sh lists files before removal" {
	# Test verifies that the uninstall script displays list of files that will be removed before uninstallation.
	# Expected: Script lists all files and directories that will be deleted, providing transparency to users.
	# Importance: File listing helps users understand what will be removed and prevents accidental data loss.
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh cleans up stale lockfiles" {
	# Test verifies that the uninstall script removes lockfiles during uninstallation cleanup.
	# Expected: Script removes lockfiles along with installation directory, preventing stale lock issues.
	# Importance: Lockfile cleanup ensures clean uninstallation and prevents lockfile conflicts on reinstall.
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh displays summary after successful uninstall" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh removes logrotate configuration when it exists" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh handles missing logrotate configuration gracefully" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh handles read-only logrotate directory gracefully" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh verifies uninstallation includes logrotate config check" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh verification fails when logrotate config still exists" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh check_installation returns 0 when installation exists" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh check_installation returns 1 when installation missing" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh remove_cron handles crontab with only vpn-monitor entry" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh remove_cron handles missing cron entry gracefully" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh remove_logrotate_config handles removal failure" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh remove_installation_dir handles missing directory gracefully" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh remove_installation_dir lists files before removal" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh cleanup_lockfile handles missing lockfile" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh cleanup_lockfile removes stale lockfile" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh verify_uninstallation detects cron entry still exists" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh verify_uninstallation detects installation directory still exists" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh verify_uninstallation detects multiple remaining components" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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
	assert_output --partial "Uninstallation verification failed with 3 error(s)"

	# Clean up
	rm -rf "$install_dir" 2>/dev/null || true
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true
	rm -f "$logrotate_config" 2>/dev/null || true
	rm -f "$test_script" 2>/dev/null || true
}

@test "uninstall.sh verify_uninstallation succeeds when all components removed" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh full uninstallation flow with all components" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh handles interactive confirmation with yes" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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

@test "uninstall.sh remove_cron preserves other cron entries" {
	# Skip if not root (uninstall.sh requires root)
	[[ $EUID -ne 0 ]] && skip "This test requires root access"

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
