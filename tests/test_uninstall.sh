#!/usr/bin/env bats
#
# Tests for uninstall.sh script
# Tests uninstallation functionality, cleanup, and error handling

load test_helper

# Path to the uninstall script
UNINSTALL_SCRIPT="${BATS_TEST_DIRNAME}/../uninstall.sh"

@test "uninstall.sh exists and is executable" {
	assert_file_exist "$UNINSTALL_SCRIPT"
	assert_file_executable "$UNINSTALL_SCRIPT"
}

@test "uninstall.sh requires root" {
	# Skip if actually running as root (can't test root requirement)
	if [[ $EUID -eq 0 ]]; then
		skip "Cannot test root requirement when running as root"
	fi
	run bash "$UNINSTALL_SCRIPT"
	assert_failure
	assert_output --partial "must be run as root"
}

@test "uninstall.sh handles missing installation gracefully" {
	# Skip if not root (uninstall.sh requires root)
	if [[ $EUID -ne 0 ]]; then
		skip "This test requires root access"
	fi

	# Ensure installation directory doesn't exist
	rm -rf /data/vpn-monitor 2>/dev/null || true

	run bash "$UNINSTALL_SCRIPT" --yes
	# Should succeed even if nothing to uninstall
	assert_success
	assert_output --partial "Installation directory not found"
}

@test "uninstall.sh removes installation directory" {
	# Skip if not root (uninstall.sh requires root)
	if [[ $EUID -ne 0 ]]; then
		skip "This test requires root access"
	fi

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
	# Skip if not root (uninstall.sh requires root)
	if [[ $EUID -ne 0 ]]; then
		skip "This test requires root access"
	fi

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
	# Skip if not root (uninstall.sh requires root)
	if [[ $EUID -ne 0 ]]; then
		skip "This test requires root access"
	fi

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
	# Skip if not root (uninstall.sh requires root)
	if [[ $EUID -ne 0 ]]; then
		skip "This test requires root access"
	fi

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
	# Skip if not root (uninstall.sh requires root)
	if [[ $EUID -ne 0 ]]; then
		skip "This test requires root access"
	fi

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
	# Skip if not root (uninstall.sh requires root)
	if [[ $EUID -ne 0 ]]; then
		skip "This test requires root access"
	fi

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
	if [[ $EUID -ne 0 ]]; then
		skip "This test requires root access"
	fi
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
	# Skip if not root (uninstall.sh requires root)
	if [[ $EUID -ne 0 ]]; then
		skip "This test requires root access"
	fi

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
	# Skip if not root (uninstall.sh requires root)
	if [[ $EUID -ne 0 ]]; then
		skip "This test requires root access"
	fi

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
	if [[ $EUID -ne 0 ]]; then
		skip "This test requires root access"
	fi

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
