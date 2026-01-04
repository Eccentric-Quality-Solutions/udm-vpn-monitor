#!/usr/bin/env bats
#
# Tests for prepare_install_package.sh script
# Tests package creation functionality, argument parsing, and file inclusion

load test_helper

# Path to the prepare install package script
PREPARE_SCRIPT="${BATS_TEST_DIRNAME}/../prepare_install_package.sh"

# Project root directory
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."

# Expected files in the package
EXPECTED_MAIN_FILES=(
	"vpn-monitor.sh"
	"install.sh"
	"uninstall.sh"
	"analyze-logs.sh"
	"vpn-monitor.conf"
)

EXPECTED_LIB_FILES=(
	"lib/common.sh"
	"lib/config.sh"
	"lib/config_schema.sh"
	"lib/constants.sh"
	"lib/detection.sh"
	"lib/lockfile.sh"
	"lib/logging.sh"
	"lib/recovery.sh"
	"lib/state.sh"
)

EXPECTED_SCRIPT_FILES=(
	"scripts/migrate-config-to-locations.sh"
	"scripts/anonymize-logs.sh"
)

# bats test_tags=category:unit
@test "prepare_install_package.sh exists and is executable" {
	# Purpose: Test verifies that the prepare_install_package script file exists and has execute permissions
	# Expected: Prepare install package script file is present and executable
	# Importance: Ensures the package preparation script can be run directly for creating distribution packages
	assert_file_exist "$PREPARE_SCRIPT"
	assert_file_executable "$PREPARE_SCRIPT"
}

# bats test_tags=category:unit
@test "prepare_install_package.sh shows help with --help flag" {
	# Purpose: Test verifies that the prepare_install_package script displays usage information when --help flag is provided
	# Expected: Script outputs usage information including all available options and package formats
	# Importance: Ensures users can access help documentation for script usage and available package formats
	run bash "$PREPARE_SCRIPT" --help
	assert_success
	assert_output --partial "Usage:"
	assert_output --partial "--tar"
	assert_output --partial "Options:"
}

# bats test_tags=category:unit
@test "prepare_install_package.sh shows help with -h flag" {
	# Purpose: Test verifies that the prepare_install_package script displays usage information when -h flag is provided
	# Expected: Script outputs usage information (short form of --help)
	# Importance: Ensures users can access help documentation using short flag syntax
	run bash "$PREPARE_SCRIPT" -h
	assert_success
	assert_output --partial "Usage:"
}

# bats test_tags=category:unit
@test "prepare_install_package.sh rejects unknown options" {
	# Purpose: Test verifies that the prepare_install_package script rejects unknown command-line options
	# Expected: Script exits with failure status and displays error message about unknown option, showing help
	# Importance: Prevents confusion from invalid options and guides users to correct usage
	run bash "$PREPARE_SCRIPT" --unknown-option
	assert_failure
	assert_output --partial "Unknown option"
	assert_output --partial "--help"
}

# bats test_tags=category:unit
@test "prepare_install_package.sh creates zip file by default" {
	# Purpose: Test verifies that the prepare_install_package script creates ZIP archive by default
	# Expected: Script creates ZIP file containing all required installation files in project root
	# Importance: ZIP format is the default distribution format for easy deployment on UDM systems
	cd "$PROJECT_ROOT"

	# Run script from project root
	run bash "$PREPARE_SCRIPT"
	assert_success

	# Check zip file was created in project root
	assert_file_exist "${PROJECT_ROOT}/udm-vpn-monitor.zip"

	# Verify zip file is not empty
	if [[ ! -s "${PROJECT_ROOT}/udm-vpn-monitor.zip" ]]; then
		fail "Zip file is empty"
	fi

	# Clean up
	rm -f "${PROJECT_ROOT}/udm-vpn-monitor.zip"
}

# bats test_tags=category:unit
@test "prepare_install_package.sh creates tar.gz file with --tar option" {
	# Purpose: Test verifies that the prepare_install_package script creates tar.gz archive when --tar option is used
	# Expected: Script creates tar.gz file instead of ZIP when --tar flag is provided
	# Importance: Provides alternative package format for systems that prefer tar.gz over ZIP archives
	cd "$PROJECT_ROOT"

	# Run script from project root with --tar option
	run bash "$PREPARE_SCRIPT" --tar
	assert_success

	# Check tar.gz file was created in project root
	assert_file_exist "${PROJECT_ROOT}/udm-vpn-monitor.tar.gz"

	# Verify tar.gz file is not empty
	if [[ ! -s "${PROJECT_ROOT}/udm-vpn-monitor.tar.gz" ]]; then
		fail "Tar.gz file is empty"
	fi

	# Verify zip file was NOT created
	if [[ -f "${PROJECT_ROOT}/udm-vpn-monitor.zip" ]]; then
		fail "Zip file should not exist when --tar option is used"
	fi

	# Clean up
	rm -f "${PROJECT_ROOT}/udm-vpn-monitor.tar.gz"
}

# bats test_tags=category:unit
@test "prepare_install_package.sh includes all required main files in zip" {
	# Purpose: Test verifies that the prepare_install_package script includes all required main files in the package
	# Expected: ZIP archive contains all main scripts (vpn-monitor.sh, install.sh, uninstall.sh, etc.)
	# Importance: Ensures installation package contains all necessary files for complete installation
	cd "$PROJECT_ROOT"

	# Run script to create zip
	run bash "$PREPARE_SCRIPT"
	assert_success

	# Extract zip and verify contents
	local extract_dir="${TEST_DIR}/extracted"
	mkdir -p "$extract_dir"
	cd "$extract_dir"
	unzip -q "${PROJECT_ROOT}/udm-vpn-monitor.zip"

	# Check all main files are present
	for file in "${EXPECTED_MAIN_FILES[@]}"; do
		assert_file_exist "${extract_dir}/${file}"
	done

	# Clean up
	rm -f "${PROJECT_ROOT}/udm-vpn-monitor.zip"
}

# bats test_tags=category:unit
@test "prepare_install_package.sh includes all required library files in zip" {
	# Purpose: Test verifies that the prepare_install_package script includes all required library files in the ZIP archive
	# Expected: ZIP archive contains all library files from lib/ directory required for script execution
	# Importance: Library file inclusion ensures installation package contains all dependencies for VPN monitor functionality
	cd "$PROJECT_ROOT"

	# Run script to create zip
	run bash "$PREPARE_SCRIPT"
	assert_success

	# Extract zip and verify contents
	local extract_dir="${TEST_DIR}/extracted"
	mkdir -p "$extract_dir"
	cd "$extract_dir"
	unzip -q "${PROJECT_ROOT}/udm-vpn-monitor.zip"

	# Check lib directory exists
	assert_dir_exist "${extract_dir}/lib"

	# Check all library files are present
	for file in "${EXPECTED_LIB_FILES[@]}"; do
		assert_file_exist "${extract_dir}/${file}"
	done

	# Clean up
	rm -f "${PROJECT_ROOT}/udm-vpn-monitor.zip"
}

# bats test_tags=category:unit
@test "prepare_install_package.sh includes all required script files in zip" {
	# Purpose: Test verifies that the prepare_install_package script includes all required script files in the ZIP archive
	# Expected: ZIP archive contains all script files from scripts/ directory required for utility functions
	# Importance: Script file inclusion ensures installation package contains migration and utility scripts
	cd "$PROJECT_ROOT"

	# Run script to create zip
	run bash "$PREPARE_SCRIPT"
	assert_success

	# Extract zip and verify contents
	local extract_dir="${TEST_DIR}/extracted-scripts"
	mkdir -p "$extract_dir"
	cd "$extract_dir"
	unzip -q "${PROJECT_ROOT}/udm-vpn-monitor.zip"

	# Check scripts directory exists
	assert_dir_exist "${extract_dir}/scripts"

	# Check all script files are present
	for file in "${EXPECTED_SCRIPT_FILES[@]}"; do
		assert_file_exist "${extract_dir}/${file}"
	done

	# Clean up
	rm -f "${PROJECT_ROOT}/udm-vpn-monitor.zip"
}

# bats test_tags=category:unit
@test "prepare_install_package.sh includes all required files in tar.gz" {
	# Purpose: Test verifies that the prepare_install_package script includes all required files when creating tar.gz archive
	# Expected: tar.gz archive contains all main files and library files, matching ZIP archive contents
	# Importance: Ensures both package formats contain complete installation files for distribution flexibility
	cd "$PROJECT_ROOT"

	# Run script with --tar option
	run bash "$PREPARE_SCRIPT" --tar
	assert_success

	# Extract tar.gz and verify contents
	local extract_dir="${TEST_DIR}/extracted-tar"
	mkdir -p "$extract_dir"
	cd "$extract_dir"
	tar -xzf "${PROJECT_ROOT}/udm-vpn-monitor.tar.gz"

	# Check all main files are present
	for file in "${EXPECTED_MAIN_FILES[@]}"; do
		assert_file_exist "${extract_dir}/${file}"
	done

	# Check lib directory exists
	assert_dir_exist "${extract_dir}/lib"

	# Check all library files are present
	for file in "${EXPECTED_LIB_FILES[@]}"; do
		assert_file_exist "${extract_dir}/${file}"
	done

	# Check scripts directory exists
	assert_dir_exist "${extract_dir}/scripts"

	# Check all script files are present
	for file in "${EXPECTED_SCRIPT_FILES[@]}"; do
		assert_file_exist "${extract_dir}/${file}"
	done

	# Clean up
	rm -f "${PROJECT_ROOT}/udm-vpn-monitor.tar.gz"
}

# bats test_tags=category:unit
@test "prepare_install_package.sh creates package with actual project files" {
	# Purpose: Test verifies that the prepare_install_package script includes actual project files (not placeholders) in the package
	# Expected: Package contains real files with actual content, not empty or placeholder files
	# Importance: Ensures distribution package contains functional files ready for installation
	cd "$PROJECT_ROOT"

	# Run script in project root (will create package there)
	run bash "$PREPARE_SCRIPT"
	assert_success

	# Check zip file was created in project root
	assert_file_exist "${PROJECT_ROOT}/udm-vpn-monitor.zip"

	# Extract and verify actual files are included
	local extract_dir="${TEST_DIR}/extracted-actual"
	mkdir -p "$extract_dir"
	cd "$extract_dir"
	unzip -q "${PROJECT_ROOT}/udm-vpn-monitor.zip"

	# Verify actual files exist and are not empty
	for file in "${EXPECTED_MAIN_FILES[@]}"; do
		assert_file_exist "${extract_dir}/${file}"
		# Check file is not just a placeholder (has reasonable size)
		if [[ ! -s "${extract_dir}/${file}" ]] || [[ $(stat -c%s "${extract_dir}/${file}" 2>/dev/null || echo 0) -lt 100 ]]; then
			fail "File ${file} appears to be empty or too small"
		fi
	done

	# Verify library files
	for file in "${EXPECTED_LIB_FILES[@]}"; do
		assert_file_exist "${extract_dir}/${file}"
		if [[ ! -s "${extract_dir}/${file}" ]] || [[ $(stat -c%s "${extract_dir}/${file}" 2>/dev/null || echo 0) -lt 100 ]]; then
			fail "File ${file} appears to be empty or too small"
		fi
	done

	# Verify script files
	for file in "${EXPECTED_SCRIPT_FILES[@]}"; do
		assert_file_exist "${extract_dir}/${file}"
		if [[ ! -s "${extract_dir}/${file}" ]] || [[ $(stat -c%s "${extract_dir}/${file}" 2>/dev/null || echo 0) -lt 100 ]]; then
			fail "File ${file} appears to be empty or too small"
		fi
	done

	# Clean up package file created during test
	rm -f "${PROJECT_ROOT}/udm-vpn-monitor.zip"
}

# bats test_tags=category:unit
@test "prepare_install_package.sh output shows correct extraction command for zip" {
	# Purpose: Test verifies that the prepare_install_package script displays correct extraction command for ZIP files
	# Expected: Script output includes unzip command with correct package filename
	# Importance: Helps users understand how to extract and use the installation package
	cd "$PROJECT_ROOT"

	run bash "$PREPARE_SCRIPT"
	assert_success

	# Use assert_line for checking specific output lines
	assert_line --partial "unzip"
	assert_line --partial "udm-vpn-monitor.zip"

	# Clean up
	rm -f "${PROJECT_ROOT}/udm-vpn-monitor.zip"
}

# bats test_tags=category:unit
@test "prepare_install_package.sh output shows correct extraction command for tar.gz" {
	# Purpose: Test verifies that the prepare_install_package script displays correct extraction command for tar.gz files
	# Expected: Script output includes tar -xzf command with correct package filename
	# Importance: Helps users understand how to extract and use the installation package in tar.gz format
	cd "$PROJECT_ROOT"

	run bash "$PREPARE_SCRIPT" --tar
	assert_success

	# Use assert_line for checking specific output lines
	assert_line --partial "tar -xzf"
	assert_line --partial "udm-vpn-monitor.tar.gz"

	# Clean up
	rm -f "${PROJECT_ROOT}/udm-vpn-monitor.tar.gz"
}
