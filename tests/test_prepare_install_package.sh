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

@test "prepare_install_package.sh exists and is executable" {
	assert_file_exist "$PREPARE_SCRIPT"
	assert_file_executable "$PREPARE_SCRIPT"
}

@test "prepare_install_package.sh shows help with --help flag" {
	run bash "$PREPARE_SCRIPT" --help
	assert_success
	assert_output --partial "Usage:"
	assert_output --partial "--tar"
	assert_output --partial "Options:"
}

@test "prepare_install_package.sh shows help with -h flag" {
	run bash "$PREPARE_SCRIPT" -h
	assert_success
	assert_output --partial "Usage:"
}

@test "prepare_install_package.sh rejects unknown options" {
	run bash "$PREPARE_SCRIPT" --unknown-option
	assert_failure
	assert_output --partial "Unknown option"
	assert_output --partial "--help"
}

@test "prepare_install_package.sh creates zip file by default" {
	cd "$PROJECT_ROOT"
	
	# Run script from project root
	run bash "$PREPARE_SCRIPT"
	assert_success
	
	# Check zip file was created in project root
	assert_file_exist "${PROJECT_ROOT}/udm-vpn-monitor-installer.zip"
	
	# Verify zip file is not empty
	if [[ ! -s "${PROJECT_ROOT}/udm-vpn-monitor-installer.zip" ]]; then
		fail "Zip file is empty"
	fi
	
	# Clean up
	rm -f "${PROJECT_ROOT}/udm-vpn-monitor-installer.zip"
}

@test "prepare_install_package.sh creates tar.gz file with --tar option" {
	cd "$PROJECT_ROOT"
	
	# Run script from project root with --tar option
	run bash "$PREPARE_SCRIPT" --tar
	assert_success
	
	# Check tar.gz file was created in project root
	assert_file_exist "${PROJECT_ROOT}/udm-vpn-monitor-installer.tar.gz"
	
	# Verify tar.gz file is not empty
	if [[ ! -s "${PROJECT_ROOT}/udm-vpn-monitor-installer.tar.gz" ]]; then
		fail "Tar.gz file is empty"
	fi
	
	# Verify zip file was NOT created
	if [[ -f "${PROJECT_ROOT}/udm-vpn-monitor-installer.zip" ]]; then
		fail "Zip file should not exist when --tar option is used"
	fi
	
	# Clean up
	rm -f "${PROJECT_ROOT}/udm-vpn-monitor-installer.tar.gz"
}

@test "prepare_install_package.sh includes all required main files in zip" {
	cd "$PROJECT_ROOT"
	
	# Run script to create zip
	run bash "$PREPARE_SCRIPT"
	assert_success
	
	# Extract zip and verify contents
	local extract_dir="${TEST_DIR}/extracted"
	mkdir -p "$extract_dir"
	cd "$extract_dir"
	unzip -q "${PROJECT_ROOT}/udm-vpn-monitor-installer.zip"
	
	# Check all main files are present
	for file in "${EXPECTED_MAIN_FILES[@]}"; do
		assert_file_exist "${extract_dir}/${file}"
	done
	
	# Clean up
	rm -f "${PROJECT_ROOT}/udm-vpn-monitor-installer.zip"
}

@test "prepare_install_package.sh includes all required library files in zip" {
	cd "$PROJECT_ROOT"
	
	# Run script to create zip
	run bash "$PREPARE_SCRIPT"
	assert_success
	
	# Extract zip and verify contents
	local extract_dir="${TEST_DIR}/extracted"
	mkdir -p "$extract_dir"
	cd "$extract_dir"
	unzip -q "${PROJECT_ROOT}/udm-vpn-monitor-installer.zip"
	
	# Check lib directory exists
	assert_dir_exist "${extract_dir}/lib"
	
	# Check all library files are present
	for file in "${EXPECTED_LIB_FILES[@]}"; do
		assert_file_exist "${extract_dir}/${file}"
	done
	
	# Clean up
	rm -f "${PROJECT_ROOT}/udm-vpn-monitor-installer.zip"
}

@test "prepare_install_package.sh includes all required files in tar.gz" {
	cd "$PROJECT_ROOT"
	
	# Run script with --tar option
	run bash "$PREPARE_SCRIPT" --tar
	assert_success
	
	# Extract tar.gz and verify contents
	local extract_dir="${TEST_DIR}/extracted-tar"
	mkdir -p "$extract_dir"
	cd "$extract_dir"
	tar -xzf "${PROJECT_ROOT}/udm-vpn-monitor-installer.tar.gz"
	
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
	
	# Clean up
	rm -f "${PROJECT_ROOT}/udm-vpn-monitor-installer.tar.gz"
}

@test "prepare_install_package.sh creates package with actual project files" {
	cd "$PROJECT_ROOT"
	
	# Run script in project root (will create package there)
	run bash "$PREPARE_SCRIPT"
	assert_success
	
	# Check zip file was created in project root
	assert_file_exist "${PROJECT_ROOT}/udm-vpn-monitor-installer.zip"
	
	# Extract and verify actual files are included
	local extract_dir="${TEST_DIR}/extracted-actual"
	mkdir -p "$extract_dir"
	cd "$extract_dir"
	unzip -q "${PROJECT_ROOT}/udm-vpn-monitor-installer.zip"
	
	# Verify actual files exist and are not empty
	for file in "${EXPECTED_MAIN_FILES[@]}"; do
		assert_file_exist "${extract_dir}/${file}"
		# Check file is not just a placeholder (has reasonable size)
		if [[ ! -s "${extract_dir}/${file}" ]] || [[ $(stat -f%z "${extract_dir}/${file}" 2>/dev/null || stat -c%s "${extract_dir}/${file}" 2>/dev/null || echo 0) -lt 100 ]]; then
			fail "File ${file} appears to be empty or too small"
		fi
	done
	
	# Verify library files
	for file in "${EXPECTED_LIB_FILES[@]}"; do
		assert_file_exist "${extract_dir}/${file}"
		if [[ ! -s "${extract_dir}/${file}" ]] || [[ $(stat -f%z "${extract_dir}/${file}" 2>/dev/null || stat -c%s "${extract_dir}/${file}" 2>/dev/null || echo 0) -lt 100 ]]; then
			fail "File ${file} appears to be empty or too small"
		fi
	done
	
	# Clean up package file created during test
	rm -f "${PROJECT_ROOT}/udm-vpn-monitor-installer.zip"
}

@test "prepare_install_package.sh output shows correct extraction command for zip" {
	cd "$PROJECT_ROOT"
	
	run bash "$PREPARE_SCRIPT"
	assert_success
	
	assert_output --partial "unzip"
	assert_output --partial "udm-vpn-monitor-installer.zip"
	
	# Clean up
	rm -f "${PROJECT_ROOT}/udm-vpn-monitor-installer.zip"
}

@test "prepare_install_package.sh output shows correct extraction command for tar.gz" {
	cd "$PROJECT_ROOT"
	
	run bash "$PREPARE_SCRIPT" --tar
	assert_success
	
	assert_output --partial "tar -xzf"
	assert_output --partial "udm-vpn-monitor-installer.tar.gz"
	
	# Clean up
	rm -f "${PROJECT_ROOT}/udm-vpn-monitor-installer.tar.gz"
}

