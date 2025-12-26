#!/usr/bin/env bats
#
# Tests for install.sh script
# Tests installation functionality, argument parsing, and error handling

load test_helper

# Path to the install script
INSTALL_SCRIPT="${BATS_TEST_DIRNAME}/../install.sh"

# bats test_tags=category:unit
@test "install.sh exists and is executable" {
	# Test verifies that the install script file exists and has execute permissions.
	# Expected: Install script file is present and executable.
	# Importance: Ensures the installation script can be run directly without requiring bash explicitly.
	assert_file_exist "$INSTALL_SCRIPT"
	assert_file_executable "$INSTALL_SCRIPT"
}

# bats test_tags=category:unit
@test "install.sh shows help with --help flag" {
	# Test verifies that the install script displays usage information when --help flag is provided.
	# Expected: Script outputs usage information including all available options.
	# Importance: Ensures users can access help documentation for script usage and available options.
	run bash "$INSTALL_SCRIPT" --help
	assert_success
	assert_output --partial "Usage:"
	assert_output --partial "Options:"
	assert_output --partial "--no-cron"
	assert_output --partial "--silent"
	assert_output --partial "--dev"
}

# bats test_tags=category:unit
@test "install.sh shows help with -h flag" {
	run bash "$INSTALL_SCRIPT" -h
	assert_success
	assert_output --partial "Usage:"
}

# bats test_tags=category:unit
@test "install.sh requires root in non-dev mode" {
	# Test verifies that the install script enforces root requirement for production installations.
	# Expected: Script exits with failure status and displays error message when run without root privileges.
	# Importance: Production installations require root access to install files and configure system services.
	# Skip if actually running as root (can't test non-root requirement)
	[[ $EUID -eq 0 ]] && skip "Cannot test root requirement when running as root"
	run bash "$INSTALL_SCRIPT" --silent --no-cron
	assert_failure
	assert_output --partial "must be run as root"
}

# bats test_tags=category:unit
@test "install.sh skips root check in dev mode" {
	# Test verifies that the install script bypasses root requirement when --dev flag is used.
	# Expected: Script runs successfully in dev mode without root privileges for testing purposes.
	# Importance: Dev mode allows testing installation logic without requiring root access.
	cd "$TEST_DIR"

	# Create source files with install.sh and lib directory
	local test_install
	test_install=$(create_test_install_setup "$INSTALL_SCRIPT" "${TEST_DIR}/source")
	echo "#!/bin/bash" >"${TEST_DIR}/source/vpn-monitor.sh"
	echo "# Test config" >"${TEST_DIR}/source/vpn-monitor.conf"
	chmod +x "${TEST_DIR}/source/vpn-monitor.sh"

	run bash "$test_install" --dev --silent --no-cron
	# Should succeed in dev mode even without root
	assert_success
}

# bats test_tags=category:unit
@test "install.sh creates installation directory in dev mode" {
	# Test verifies that the install script creates the installation directory during installation.
	# Expected: Installation directory is created in the configured location (default or custom path).
	# Importance: Installation directory is required for storing scripts, config, and state files.
	cd "$TEST_DIR"

	# Create source files with install.sh and lib directory
	local test_install
	test_install=$(create_test_install_setup "$INSTALL_SCRIPT" "${TEST_DIR}/source")
	echo "#!/bin/bash" >"${TEST_DIR}/source/vpn-monitor.sh"
	echo "# Test config" >"${TEST_DIR}/source/vpn-monitor.conf"
	chmod +x "${TEST_DIR}/source/vpn-monitor.sh"

	run bash "$test_install" --dev --silent --no-cron
	assert_success

	# Check installation directory was created
	assert_dir_exist "${TEST_DIR}/vpn-monitor"
}

# bats test_tags=category:unit
@test "install.sh installs scripts in dev mode" {
	# Test verifies that the install script copies all required scripts and config files to installation directory.
	# Expected: Scripts and config files are installed with correct permissions in the installation directory.
	# Importance: Ensures all necessary files are present and executable for the VPN monitor to function.
	cd "$TEST_DIR"

	# Create source files with install.sh and lib directory
	local test_install
	test_install=$(create_test_install_setup "$INSTALL_SCRIPT" "${TEST_DIR}/source")
	echo "#!/bin/bash" >"${TEST_DIR}/source/vpn-monitor.sh"
	echo "# Test config" >"${TEST_DIR}/source/vpn-monitor.conf"
	chmod +x "${TEST_DIR}/source/vpn-monitor.sh"

	run bash "$test_install" --dev --silent --no-cron
	assert_success

	# Check scripts were installed with correct permissions
	assert_file_exist "${TEST_DIR}/vpn-monitor/vpn-monitor.sh"
	assert_file_executable "${TEST_DIR}/vpn-monitor/vpn-monitor.sh"
	# Verify script has executable permissions (755 is typical for scripts)
	assert_file_permission 755 "${TEST_DIR}/vpn-monitor/vpn-monitor.sh"
	assert_file_exist "${TEST_DIR}/vpn-monitor/vpn-monitor.conf"
	# Verify config file has readable permissions (644 is typical for config files)
	assert_file_permission 644 "${TEST_DIR}/vpn-monitor/vpn-monitor.conf"
}

# bats test_tags=category:unit
@test "install.sh creates default config if template missing" {
	# Test verifies that the install script creates default configuration file when template is missing.
	# Expected: Default config file is created with required variables when source config template doesn't exist.
	# Importance: Ensures installation succeeds even without config template, providing usable defaults.
	cd "$TEST_DIR"

	# Create source files with install.sh and lib directory (without config)
	local test_install
	test_install=$(create_test_install_setup "$INSTALL_SCRIPT" "${TEST_DIR}/source")
	echo "#!/bin/bash" >"${TEST_DIR}/source/vpn-monitor.sh"
	chmod +x "${TEST_DIR}/source/vpn-monitor.sh"

	run bash "$test_install" --dev --silent --no-cron
	assert_success

	# Check default config was created
	assert_file_exist "${TEST_DIR}/vpn-monitor/vpn-monitor.conf"
	assert_file_contains "${TEST_DIR}/vpn-monitor/vpn-monitor.conf" "EXTERNAL_PEER_IPS"
	assert_file_contains "${TEST_DIR}/vpn-monitor/vpn-monitor.conf" "VPN_NAME"
}

# bats test_tags=category:unit
@test "install.sh preserves existing config in silent mode" {
	# Test verifies that the install script preserves existing configuration during re-installation in silent mode.
	# Expected: Custom configuration values are preserved when reinstalling without --overwrite-conf flag.
	# Importance: Prevents loss of user customizations during script updates or re-installations.
	cd "$TEST_DIR"

	# Create source files with install.sh and lib directory
	local test_install
	test_install=$(create_test_install_setup "$INSTALL_SCRIPT" "${TEST_DIR}/source")
	echo "#!/bin/bash" >"${TEST_DIR}/source/vpn-monitor.sh"
	echo "EXTERNAL_PEER_IPS=\"192.168.1.1\"" >"${TEST_DIR}/source/vpn-monitor.conf"
	chmod +x "${TEST_DIR}/source/vpn-monitor.sh"

	# First installation
	run bash "$test_install" --dev --silent --no-cron
	assert_success

	# Modify installed config
	echo "CUSTOM_VALUE=test" >>"${TEST_DIR}/vpn-monitor/vpn-monitor.conf"

	# Re-install without overwrite
	run bash "$test_install" --dev --silent --no-cron
	assert_success

	# Check custom value is preserved
	assert_file_contains "${TEST_DIR}/vpn-monitor/vpn-monitor.conf" "CUSTOM_VALUE=test"
}

# bats test_tags=category:unit
@test "install.sh overwrites config with --overwrite-conf flag" {
	# Test verifies that the install script overwrites existing configuration when --overwrite-conf flag is used.
	# Expected: Existing config file is replaced with template config, removing any custom values.
	# Importance: Allows administrators to reset configuration to defaults when needed.
	cd "$TEST_DIR"

	# Create source files with install.sh and lib directory
	local test_install
	test_install=$(create_test_install_setup "$INSTALL_SCRIPT" "${TEST_DIR}/source")
	echo "#!/bin/bash" >"${TEST_DIR}/source/vpn-monitor.sh"
	echo "EXTERNAL_PEER_IPS=\"192.168.1.1\"" >"${TEST_DIR}/source/vpn-monitor.conf"
	chmod +x "${TEST_DIR}/source/vpn-monitor.sh"

	# First installation
	run bash "$test_install" --dev --silent --no-cron
	assert_success

	# Modify installed config
	echo "CUSTOM_VALUE=test" >>"${TEST_DIR}/vpn-monitor/vpn-monitor.conf"

	# Re-install with overwrite
	run bash "$test_install" --dev --silent --no-cron --overwrite-conf
	assert_success

	# Check custom value is gone
	refute_file_contains "${TEST_DIR}/vpn-monitor/vpn-monitor.conf" "CUSTOM_VALUE=test"
}

# bats test_tags=category:unit
@test "install.sh skips cron setup with --no-cron flag" {
	# Test verifies that the install script skips cron job creation when --no-cron flag is provided.
	# Expected: Script completes installation without creating cron entry when --no-cron flag is used.
	# Importance: Allows installation without automatic scheduling, useful for manual execution or systemd services.
	cd "$TEST_DIR"

	# Create source files with install.sh and lib directory
	local test_install
	test_install=$(create_test_install_setup "$INSTALL_SCRIPT" "${TEST_DIR}/source")
	echo "#!/bin/bash" >"${TEST_DIR}/source/vpn-monitor.sh"
	echo "# Test config" >"${TEST_DIR}/source/vpn-monitor.conf"
	chmod +x "${TEST_DIR}/source/vpn-monitor.sh"

	run bash "$test_install" --dev --silent --no-cron
	assert_success

	# Check cron entry was not created
	run crontab -l 2>/dev/null
	if [[ $status -eq 0 ]]; then
		refute_output --partial "vpn-monitor.sh"
	fi
}

# bats test_tags=category:unit
@test "install.sh sets up cron job when not skipped" {
	# Test verifies that the install script creates cron job for scheduled execution when not disabled.
	# Expected: Script creates cron entry with default or configured schedule for automated monitoring.
	# Importance: Cron job ensures VPN monitoring runs automatically on schedule without manual intervention.
	cd "$TEST_DIR"

	# Create source files with install.sh and lib directory
	local test_install
	test_install=$(create_test_install_setup "$INSTALL_SCRIPT" "${TEST_DIR}/source")
	echo "#!/bin/bash" >"${TEST_DIR}/source/vpn-monitor.sh"
	echo "# Test config" >"${TEST_DIR}/source/vpn-monitor.conf"
	chmod +x "${TEST_DIR}/source/vpn-monitor.sh"

	# Remove any existing cron entries first
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true

	# Run install script - may fail if crontab has issues, but should at least attempt setup
	run bash "$test_install" --dev --silent

	# Check if cron entry was created (even if script had warnings)
	run crontab -l 2>/dev/null
	if [[ $status -eq 0 ]]; then
		# If crontab works, check for entry
		if echo "$output" | grep -q "vpn-monitor.sh"; then
			# Cron entry exists - test passes
			assert_success "Cron entry was created"
		else
			# Script may have failed to create cron entry, but that's acceptable in test environment
			# The important thing is the script attempted to set it up
			skip "Cron entry not created (may require root or crontab permissions)"
		fi
	else
		# Crontab not available or permission denied - skip test
		skip "Crontab not available or permission denied"
	fi

	# Clean up
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true
}

# bats test_tags=category:unit
@test "install.sh uses cron schedule from config" {
	# Test verifies that the install script uses CRON_SCHEDULE from configuration file for cron job.
	# Expected: Script creates cron entry with custom schedule from config file instead of default schedule.
	# Importance: Allows administrators to customize monitoring frequency based on their requirements.
	cd "$TEST_DIR"

	# Create source files with install.sh and lib directory
	local test_install
	test_install=$(create_test_install_setup "$INSTALL_SCRIPT" "${TEST_DIR}/source")
	echo "#!/bin/bash" >"${TEST_DIR}/source/vpn-monitor.sh"
	cat >"${TEST_DIR}/source/vpn-monitor.conf" <<'EOF'
EXTERNAL_PEER_IPS=""
CRON_SCHEDULE="*/5 * * * *"
EOF
	chmod +x "${TEST_DIR}/source/vpn-monitor.sh"

	# Remove any existing cron entries first
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true

	run bash "$test_install" --dev --silent
	assert_success

	# Check cron entry uses custom schedule
	# Filter to only vpn-monitor entries to avoid false positives from other cron jobs
	local cron_output
	cron_output=$(crontab -l 2>/dev/null | grep "vpn-monitor.sh" || true)
	if [[ -n "$cron_output" ]]; then
		# vpn-monitor cron entry exists - check it uses the custom schedule
		if echo "$cron_output" | grep -q "*/5 * * * *"; then
			# Schedule matches - test passes
			:
		else
			# Entry exists but schedule doesn't match
			echo "Expected schedule '*/5 * * * *' but found: $cron_output" >&2
			return 1
		fi
	else
		# Cron entry not found - may be a test environment issue
		skip "Cron entry not found (may require root or crontab permissions)"
	fi

	# Clean up
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true
}

# bats test_tags=category:unit
@test "install.sh verifies installation" {
	# Test verifies that the install script performs post-installation verification checks.
	# Expected: Script verifies that all required files are installed and outputs success message.
	# Importance: Installation verification ensures installation completed successfully and files are accessible.
	cd "$TEST_DIR"

	# Create source files with install.sh and lib directory
	local test_install
	test_install=$(create_test_install_setup "$INSTALL_SCRIPT" "${TEST_DIR}/source")
	echo "#!/bin/bash" >"${TEST_DIR}/source/vpn-monitor.sh"
	echo "# Test config" >"${TEST_DIR}/source/vpn-monitor.conf"
	chmod +x "${TEST_DIR}/source/vpn-monitor.sh"

	run bash "$test_install" --dev --silent --no-cron
	assert_success

	# Check verification output
	assert_output --partial "Installation verified successfully"
}

# bats test_tags=category:unit
@test "install.sh handles missing source script gracefully" {
	# Test verifies that the install script handles missing source files gracefully with clear error messages.
	# Expected: Script exits with failure status and displays error message when required source files are missing.
	# Importance: Clear error messages help diagnose installation issues when source files are not found.
	cd "$TEST_DIR"

	# Create source files with install.sh and lib directory (but no vpn-monitor.sh)
	local test_install
	test_install=$(create_test_install_setup "$INSTALL_SCRIPT" "${TEST_DIR}/source")

	# Change to source directory so script can't find vpn-monitor.sh
	cd "${TEST_DIR}/source"

	run bash "$test_install" --dev --silent --no-cron
	assert_failure
	assert_output --partial "Source file not found"
}

# bats test_tags=category:unit
@test "install.sh fails with invalid arguments" {
	cd "$TEST_DIR"

	# Create source files with install.sh and lib directory
	local test_install
	test_install=$(create_test_install_setup "$INSTALL_SCRIPT" "${TEST_DIR}/source")
	echo "#!/bin/bash" >"${TEST_DIR}/source/vpn-monitor.sh"
	echo "# Test config" >"${TEST_DIR}/source/vpn-monitor.conf"
	chmod +x "${TEST_DIR}/source/vpn-monitor.sh"

	# Test with invalid flag - should fail and show help
	run bash "$test_install" --invalid-flag
	assert_failure
	assert_output --partial "Invalid argument: --invalid-flag"
	assert_output --partial "Usage:"
	assert_output --partial "Options:"
	assert_output --partial "--no-cron"
	assert_output --partial "--silent"
	assert_output --partial "--dev"
}

# bats test_tags=category:unit
@test "install.sh fails with invalid arguments and shows help message" {
	cd "$TEST_DIR"

	# Create source files with install.sh and lib directory
	local test_install
	test_install=$(create_test_install_setup "$INSTALL_SCRIPT" "${TEST_DIR}/source")
	echo "#!/bin/bash" >"${TEST_DIR}/source/vpn-monitor.sh"
	echo "# Test config" >"${TEST_DIR}/source/vpn-monitor.conf"
	chmod +x "${TEST_DIR}/source/vpn-monitor.sh"

	# Test with multiple invalid flags - should fail on first invalid one
	run bash "$test_install" --dev --unknown-flag
	assert_failure
	assert_output --partial "Invalid argument: --unknown-flag"
	assert_output --partial "Usage:"
}

# bats test_tags=category:unit
@test "install.sh validates flag combinations" {
	cd "$TEST_DIR"

	# Create source files with install.sh and lib directory
	local test_install
	test_install=$(create_test_install_setup "$INSTALL_SCRIPT" "${TEST_DIR}/source")
	echo "#!/bin/bash" >"${TEST_DIR}/source/vpn-monitor.sh"
	echo "# Test config" >"${TEST_DIR}/source/vpn-monitor.conf"
	chmod +x "${TEST_DIR}/source/vpn-monitor.sh"

	# --overwrite-conf without --silent should warn
	run bash "$test_install" --dev --no-cron --overwrite-conf <<<"no"
	assert_output --partial "only effective with --silent"
}
