#!/usr/bin/env bash
#
# Test helper functions for UDM VPN Monitor tests
# Provides common utilities for test scripts

# Load bats helper libraries
# Standardize on helper library functions for consistent test patterns,
# better error messages, and easier maintenance
load "${BATS_TEST_DIRNAME}/bats-support/load.bash"
load "${BATS_TEST_DIRNAME}/bats-assert/load.bash"
load "${BATS_TEST_DIRNAME}/bats-file/load.bash"

# BATS Built-in Variables
#
# BATS provides several built-in variables that are available in tests:
#   - BATS_TEST_DIRNAME: Directory containing the test file
#   - BATS_TEST_FILENAME: Full path to the test file
#   - BATS_TEST_NAME: Name of the test (from @test annotation)
#   - BATS_TEST_NUMBER: Sequential number of the test in the file
#   - BATS_TEST_TMPDIR: Temporary directory for the test (automatically cleaned)
#
# These variables are useful for:
#   - Better error messages (using BATS_TEST_NAME)
#   - Debugging (using BATS_TEST_FILENAME and BATS_TEST_NUMBER)
#   - Test-specific temporary files (using BATS_TEST_TMPDIR)
#
# Example usage:
#   echo "Running test: ${BATS_TEST_NAME} from ${BATS_TEST_FILENAME}"
#   local debug_file="${BATS_TEST_TMPDIR}/debug.log"

# Standard Test IP Addresses
#
# Standard IP addresses for use in tests. These constants make tests easier to
# modify and understand by centralizing IP address definitions.
#
# Available constants:
#   - TEST_PEER_IP: Primary peer IP address (default: "192.168.1.1")
#   - TEST_PEER_IP2: Secondary peer IP address (default: "10.0.0.1")
#   - TEST_LOCAL_IP: Local IP address (default: "192.168.1.2")
#
# Example usage:
#   setup_location_vpn_monitor "$TEST_PEER_IP"
#   mock_ping "$TEST_PEER_IP" "1"
TEST_PEER_IP="192.168.1.1"
TEST_PEER_IP2="10.0.0.1"
TEST_LOCAL_IP="192.168.1.2"

# Export test IP constants so they're available in all tests
export TEST_PEER_IP TEST_PEER_IP2 TEST_LOCAL_IP

# Load common functions from lib
# shellcheck source=../lib/common.sh
source "${BATS_TEST_DIRNAME}/../lib/common.sh"

# Path to the VPN monitor script and modules (for source_function)
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"
LIB_DIR="${BATS_TEST_DIRNAME}/../lib"

# Setup function run before each test
#
# Bats framework calls this function automatically before each test.
# Creates a clean test environment with temporary directories and mock structures.
#
# Side effects:
#   - Creates TEST_DIR for this test using temp_make
#   - Creates MOCK_DATA_DIR and MOCK_INSTALL_DIR
#   - Saves original PWD, HOME, PATH, and all test-related environment variables
#   - Sets TEST_DIR, MOCK_DATA_DIR, MOCK_INSTALL_DIR environment variables
#
# Test Isolation:
#   This function saves all environment variables that tests might modify to ensure
#   complete isolation between tests. See teardown() for restoration logic.
setup() {
	# Save original PATH before any modifications
	# This ensures we can restore PATH in teardown even if test fails
	# PATH may be modified by add_mock_to_path() during tests
	ORIGINAL_PATH="${PATH}"
	export ORIGINAL_PATH

	# Save original paths
	ORIGINAL_PWD="$PWD"
	ORIGINAL_HOME="$HOME"

	# Save all test-related environment variables that might be modified by tests
	# This ensures complete test isolation - each test starts with a clean environment
	# Variables are saved with ORIGINAL_ prefix and restored in teardown()
	# Use a sentinel value to distinguish between unset and empty string
	# We use a special marker "__UNSET__" to track variables that were not originally set
	local var_name
	for var_name in \
		CONFIG_FILE STATE_DIR LOGS_DIR LOCKFILE LOG_FILE \
		RESTART_COUNT_FILE COOLDOWN_UNTIL_FILE \
		MOCK_IP MOCK_PING MOCK_IPSEC \
		NO_ESCALATE DEBUG BASE_TIME \
		TEST_CONFIG_FILE TEST_SCRIPT \
		MOCK_DATA_DIR MOCK_INSTALL_DIR; do
		if [[ -v "$var_name" ]]; then
			# Variable was set (even if empty), save its value
			printf -v "ORIGINAL_${var_name}" '%s' "${!var_name}"
		else
			# Variable was not set, use sentinel value
			printf -v "ORIGINAL_${var_name}" '%s' "__UNSET__"
		fi
		export "ORIGINAL_${var_name}"
	done

	# Export saved values so they're available in teardown even if test fails
	export ORIGINAL_PWD ORIGINAL_HOME

	# Create temporary directory for this test using bats-file's temp_make
	# This provides consistent temporary directory handling and better cleanup
	TEST_DIR="$(temp_make --prefix 'vpn-monitor-')"

	# Create mock directories
	MOCK_DATA_DIR="${TEST_DIR}/data"
	MOCK_INSTALL_DIR="${MOCK_DATA_DIR}/vpn-monitor"
	mkdir -p "$MOCK_INSTALL_DIR"

	# Create mock /data directory structure
	mkdir -p "${MOCK_DATA_DIR}"

	# Set test environment
	export TEST_DIR
	export MOCK_DATA_DIR
	export MOCK_INSTALL_DIR
}

# Teardown function run after each test
#
# Bats framework calls this function automatically after each test.
# Cleans up test environment and restores original state.
#
# Side effects:
#   - Restores original PATH (removes any mock PATH modifications)
#   - Restores all test-related environment variables to their original values
#   - Removes TEST_DIR and all contents using temp_del
#   - Restores original working directory
#   - Removes test cron entries containing "test-vpn-monitor"
#
# Test Isolation:
#   This function ensures complete test isolation by restoring all environment
#   variables to their original state before the test ran. This prevents test
#   pollution where one test's modifications affect subsequent tests.
#
# Note: Set BATSLIB_TEMP_PRESERVE_ON_FAILURE=1 to preserve temp directories
#       for debugging when tests fail
teardown() {
	# Always restore PATH, even if test fails
	# This ensures PATH modifications don't persist between tests
	if [[ -n "${ORIGINAL_PATH:-}" ]]; then
		export PATH="$ORIGINAL_PATH"
	fi

	# Restore all test-related environment variables to their original values
	# This ensures complete test isolation - each test starts fresh
	# Use helper function to restore variables (DRY principle)
	restore_env_var() {
		local var_name="$1"
		local original_var="ORIGINAL_${var_name}"
		if [[ "${!original_var:-}" == "__UNSET__" ]]; then
			# Variable was not originally set, unset it
			unset "$var_name"
		else
			# Variable was set (even if empty), restore its value
			export "$var_name"="${!original_var}"
		fi
	}

	# Restore all tracked environment variables
	restore_env_var CONFIG_FILE
	restore_env_var STATE_DIR
	restore_env_var LOGS_DIR
	restore_env_var LOCKFILE
	restore_env_var LOG_FILE
	restore_env_var RESTART_COUNT_FILE
	restore_env_var COOLDOWN_UNTIL_FILE
	restore_env_var MOCK_IP
	restore_env_var MOCK_PING
	restore_env_var MOCK_IPSEC
	restore_env_var NO_ESCALATE
	restore_env_var DEBUG
	restore_env_var BASE_TIME
	restore_env_var TEST_CONFIG_FILE
	restore_env_var TEST_SCRIPT
	restore_env_var MOCK_DATA_DIR
	restore_env_var MOCK_INSTALL_DIR

	# Restore HOME if it was saved
	if [[ -n "${ORIGINAL_HOME:-}" ]]; then
		export HOME="$ORIGINAL_HOME"
	fi

	# Clean up test directory using bats-file's temp_del
	# This provides better cleanup handling and respects BATSLIB_TEMP_PRESERVE_ON_FAILURE
	if [[ -n "$TEST_DIR" ]] && [[ -d "$TEST_DIR" ]]; then
		temp_del "$TEST_DIR"
	fi

	# Unset TEST_DIR after cleanup
	unset TEST_DIR

	# Restore original directory
	cd "$ORIGINAL_PWD" || true

	# Clean up any directories created from environment variable names in project root
	# This can happen if LOG_FILE or LOGS_DIR gets set to an environment variable name
	# during test execution (e.g., when tests export LOCATION_*_EXTERNAL variables).
	# Pattern: directories matching LOCATION_*_EXTERNAL=* or LOCATION_*_EXTERNAL="*"
	# This ensures test isolation - directories created accidentally are cleaned up
	if [[ -n "$ORIGINAL_PWD" ]] && [[ -d "$ORIGINAL_PWD" ]]; then
		local cleanup_dir
		# Use nullglob to avoid literal expansion if no matches
		shopt -s nullglob
		for cleanup_dir in "$ORIGINAL_PWD"/LOCATION_*_EXTERNAL*; do
			if [[ -d "$cleanup_dir" ]] && [[ "$cleanup_dir" =~ LOCATION_.*_EXTERNAL.*= ]]; then
				rm -rf "$cleanup_dir" 2>/dev/null || true
			fi
		done
		shopt -u nullglob
	fi

	# Clean up any test cron entries
	# Remove both "test-vpn-monitor" entries (created by tests) and "vpn-monitor.sh" entries
	# (created by create_test_cron_entry or install tests) to ensure complete isolation
	if command -v crontab >/dev/null 2>&1; then
		crontab -l 2>/dev/null | grep -v "test-vpn-monitor" | grep -v "vpn-monitor.sh" | crontab - || true
		# If crontab is now empty, remove it completely
		local crontab_content
		crontab_content=$(crontab -l 2>/dev/null || echo "")
		if [[ -z "$crontab_content" ]] || [[ "$crontab_content" =~ ^[[:space:]]*$ ]]; then
			crontab -r 2>/dev/null || true
		fi
	fi
}

# Create a mock config file
#
# Creates a test configuration file with default test values.
# Used by tests to set up a valid configuration without manual file creation.
#
# Arguments:
#   $1: Optional path to config file (defaults to ${MOCK_INSTALL_DIR}/vpn-monitor.conf)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created config file
create_mock_config() {
	local config_file="${1:-${MOCK_INSTALL_DIR}/vpn-monitor.conf}"
	cat >"$config_file" <<EOF
# Test configuration
LOCATION_TEST_EXTERNAL="${TEST_PEER_IP}"
LOCATION_TEST_INTERNAL="${TEST_PEER_IP}"
LOCATION_TEST2_EXTERNAL="${TEST_PEER_IP2}"
LOCATION_TEST2_INTERNAL="${TEST_PEER_IP2}"
VPN_NAME="Test VPN"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
COOLDOWN_MINUTES=15
MAX_RESTARTS_PER_HOUR=3
LOG_FILE="/data/vpn-monitor/logs/vpn-monitor.log"
STATE_DIR="/data/vpn-monitor"
CRON_SCHEDULE="*/1 * * * *"
LOCKFILE_TIMEOUT=5
ENABLE_PING_CHECK=1
PING_COUNT=3
PING_TIMEOUT=2
DEBUG=0
EOF
	echo "$config_file"
}

# Create a mock vpn-monitor.sh script
#
# Creates a simple mock script that exits successfully.
# Used for testing installation/uninstallation without requiring the full script.
#
# Arguments:
#   $1: Optional path to script file (defaults to ${MOCK_INSTALL_DIR}/vpn-monitor.sh)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created script file
create_mock_vpn_monitor_script() {
	local script_file="${1:-${MOCK_INSTALL_DIR}/vpn-monitor.sh}"
	cat >"$script_file" <<'EOF'
#!/bin/bash
# Mock VPN monitor script for testing
echo "Mock VPN monitor script"
exit 0
EOF
	chmod +x "$script_file"
	echo "$script_file"
}

# Mock root user
#
# Sets MOCK_ROOT environment variable to simulate root user.
# Note: EUID is readonly in bash, so actual root status cannot be changed.
# Tests that need root should be run with appropriate permissions or use wrapper scripts.
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Sets MOCK_ROOT=1 environment variable
mock_root() {
	export MOCK_ROOT=1
	# For tests, we'll need to either:
	# 1. Run tests with sudo
	# 2. Modify scripts to check MOCK_ROOT env var
	# 3. Use wrapper scripts
	# For now, tests that need root should be run with appropriate permissions
}

# Mock non-root user
#
# Sets MOCK_ROOT environment variable to simulate non-root user.
# Note: EUID is readonly in bash, so actual user status cannot be changed.
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Sets MOCK_ROOT=0 environment variable
mock_non_root() {
	export MOCK_ROOT=0
	# EUID is readonly, so we can't actually change it
	# Tests will need to handle this differently
}

# Mock UDM system (create /data directory)
#
# Creates mock /data directory structure to simulate UDM system.
# Sets MOCK_UDM_DATA environment variable pointing to the mock data directory.
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Creates ${MOCK_DATA_DIR} directory
#   Sets MOCK_UDM_DATA environment variable
mock_udm_system() {
	mkdir -p "${MOCK_DATA_DIR}"
	# Create symlink or mount point simulation
	if [[ ! -d "/data" ]] && [[ -w "${MOCK_DATA_DIR}" ]]; then
		# In test environment, we can't create /data, so we'll use TEST_DIR
		export MOCK_UDM_DATA="${MOCK_DATA_DIR}"
	fi
}

# Mock non-UDM system (no /data directory)
#
# Removes mock /data directory to simulate non-UDM system.
# Used to test error handling when UDM-specific directories are missing.
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Removes ${MOCK_DATA_DIR} directory if it exists
mock_non_udm_system() {
	# Ensure /data doesn't exist in test environment
	if [[ -d "${MOCK_DATA_DIR}" ]]; then
		rm -rf "${MOCK_DATA_DIR}"
	fi
}

# Custom helper: refute_file_contains
# bats-file doesn't provide this function, so we define it here
# Uses fixed string matching (grep -F) for consistency with our test patterns
if ! type refute_file_contains >/dev/null 2>&1; then
	# Refute file contains assertion
	#
	# Verifies that a file does NOT contain a specific pattern.
	# Succeeds if file doesn't exist (empty file doesn't contain pattern).
	# Fails the test if pattern is found.
	#
	# Arguments:
	#   $1: Path to file to check
	#   $2: Pattern to search for (fixed string, not regex)
	#
	# Returns:
	#   0: Pattern not found (or file doesn't exist)
	#   1: Pattern found (fails test)
	refute_file_contains() {
		local file="$1"
		local pattern="$2"
		if [[ -f "$file" ]] && grep -Fq -- "$pattern" "$file"; then
			fail "File should not contain pattern: $pattern"
		fi
	}
fi

# Create test install.sh setup with lib directory
#
# Creates a test directory structure with install.sh and the required lib directory.
# This ensures install.sh can find lib/common.sh when sourced.
#
# Arguments:
#   $1: Path to original install.sh script
#   $2: Path where test install.sh should be created (directory will be created)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created test install.sh script
#
# Side effects:
#   Creates test directory structure with install.sh and lib/ directory
create_test_install_setup() {
	local original_install="$1"
	local test_install_dir="$2"
	local project_root
	project_root=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)

	# Create test source directory
	mkdir -p "$test_install_dir"

	# Copy install.sh
	cp "$original_install" "${test_install_dir}/install.sh"
	chmod +x "${test_install_dir}/install.sh"

	# Copy lib directory
	cp -r "${project_root}/lib" "${test_install_dir}/lib"

	echo "${test_install_dir}/install.sh"
}

# Create a test version of vpn-monitor.sh with custom paths
#
# Creates a modified copy of vpn-monitor.sh with test-specific paths.
# Modifies CONFIG_FILE, STATE_DIR, LOG_FILE, and LOCKFILE variables using sed.
# This allows tests to run the actual script with test directories instead of /data/.
#
# Arguments:
#   $1: Path to original vpn-monitor.sh script
#   $2: Path where test script should be created
#   $3: Optional custom CONFIG_FILE path
#   $4: Optional custom STATE_DIR path
#   $5: Optional custom LOG_FILE path
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created test script
#
# Side effects:
#   Creates a modified copy of the original script with test paths
create_test_vpn_monitor_script() {
	local original_script="$1"
	local test_script="$2"
	local config_file="${3:-}"
	local state_dir="${4:-}"
	local log_file="${5:-}"

	# Get the project root directory (parent of tests directory)
	local project_root
	if [[ -n "${BATS_TEST_DIRNAME:-}" ]] && [[ -d "${BATS_TEST_DIRNAME}" ]]; then
		project_root=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)
	else
		# Fallback: use the directory containing test_helper.bash
		local helper_dir
		helper_dir=$(dirname "${BASH_SOURCE[0]}")
		project_root=$(cd "$helper_dir/.." && pwd)
	fi

	# Validate project_root is set and exists
	if [[ -z "$project_root" ]] || [[ ! -d "$project_root" ]] || [[ ! -d "$project_root/lib" ]]; then
		echo "Error: Failed to determine project root directory (BATS_TEST_DIRNAME=${BATS_TEST_DIRNAME:-unset}, project_root=${project_root:-unset})" >&2
		return 1
	fi

	# Copy the original script
	cp "$original_script" "$test_script"
	chmod +x "$test_script"

	# Prepare escaped values for sed (escape special characters)
	local escaped_config=""
	local escaped_state=""
	local escaped_log=""
	local escaped_project_root

	if [[ -n "$config_file" ]]; then
		escaped_config=$(escape_sed_regex "$config_file")
	fi
	if [[ -n "$state_dir" ]]; then
		escaped_state=$(escape_sed_regex "$state_dir")
	fi
	if [[ -n "$log_file" ]]; then
		escaped_log=$(escape_sed_regex "$log_file")
	fi

	# Ensure project_root is still set (defensive check)
	if [[ -z "$project_root" ]]; then
		echo "Error: project_root became empty after validation" >&2
		return 1
	fi

	escaped_project_root=$(escape_sed_regex "$project_root")

	# Validate escaped_project_root is set
	if [[ -z "$escaped_project_root" ]]; then
		echo "Error: escaped_project_root is empty (project_root='${project_root}', length=${#project_root})" >&2
		return 1
	fi

	# Build sed script with all replacements in single pass
	local sed_script=""
	if [[ -n "$escaped_config" ]]; then
		sed_script="${sed_script}s|^CONFIG_FILE=.*|CONFIG_FILE=\"${escaped_config}\"|;"
	fi
	if [[ -n "$escaped_state" ]]; then
		sed_script="${sed_script}s|^STATE_DIR=.*|STATE_DIR=\"${escaped_state}\"|;"
		sed_script="${sed_script}s|^LOCKFILE=.*|LOCKFILE=\"${escaped_state}/vpn-monitor.lock\"|;"
		sed_script="${sed_script}s|^COOLDOWN_UNTIL_FILE=.*|COOLDOWN_UNTIL_FILE=\"${escaped_state}/cooldown_until\"|;"
		sed_script="${sed_script}s|^RESTART_COUNT_FILE=.*|RESTART_COUNT_FILE=\"${escaped_state}/restart_count\"|;"
	fi
	if [[ -n "$escaped_log" ]]; then
		sed_script="${sed_script}s|^LOG_FILE=.*|LOG_FILE=\"${escaped_log}\"|;"
		# Also set LOGS_DIR to match the log file directory
		local log_dir
		log_dir=$(dirname "$escaped_log")
		local escaped_log_dir
		escaped_log_dir=$(escape_sed_regex "$log_dir")
		sed_script="${sed_script}s|^LOGS_DIR=.*|LOGS_DIR=\"${escaped_log_dir}\"|;"
	fi
	# Replace source paths - escaped_project_root is validated above
	sed_script="${sed_script}s|source \"\${SCRIPT_DIR}/lib/|source \"${escaped_project_root}/lib/|g"

	# Apply all replacements in single sed pass
	sed -i "$sed_script" "$test_script"

	echo "$test_script"
}

# Assert file exists and is executable
#
# Verifies that a file exists and has executable permissions.
# Fails the test if file doesn't exist or is not executable.
#
# Arguments:
#   $1: Path to file to check
#
# Returns:
#   0: File exists and is executable
#   1: File doesn't exist or is not executable (fails test)
assert_file_executable() {
	local file="$1"
	assert_file_exist "$file"
	if [[ ! -x "$file" ]]; then
		fail "File is not executable: $file"
	fi
}

# Assert cron entry exists
#
# Verifies that a cron entry matching the pattern exists in the crontab.
# Fails the test if pattern is not found.
#
# Arguments:
#   $1: Pattern to search for in crontab (partial match)
#
# Returns:
#   0: Cron entry found
#   1: Cron entry not found (fails test)
assert_cron_entry_exists() {
	local pattern="$1"
	run crontab -l 2>/dev/null
	assert_success
	assert_output --partial "$pattern"
}

# Assert cron entry does not exist
#
# Verifies that a cron entry matching the pattern does NOT exist in the crontab.
# Fails the test if pattern is found.
#
# Arguments:
#   $1: Pattern to search for in crontab (regex)
#
# Returns:
#   0: Cron entry not found
#   1: Cron entry found (fails test)
assert_cron_entry_not_exists() {
	local pattern="$1"
	run crontab -l 2>/dev/null
	if [[ $status -eq 0 ]]; then
		refute_output --regexp "$pattern"
	fi
}

# Create a test cron entry
#
# Adds a test cron entry to the current user's crontab.
# Used to set up test environment with cron entries.
#
# Arguments:
#   $1: Cron schedule (default: "*/1 * * * *")
#   $2: Script path (default: "/data/vpn-monitor/vpn-monitor.sh")
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Adds cron entry to current user's crontab
create_test_cron_entry() {
	local schedule="${1:-*/1 * * * *}"
	local script_path="${2:-/data/vpn-monitor/vpn-monitor.sh}"
	local cron_entry="${schedule} ${script_path} >> /tmp/test-cron.log 2>&1"
	(
		crontab -l 2>/dev/null || true
		echo "$cron_entry"
	) | crontab -
}

# Get script directory (for sourcing scripts)
#
# Returns the absolute path of the directory containing a script file.
# Useful for determining script locations in tests.
#
# Arguments:
#   $1: Path to script file
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the absolute directory path
get_script_dir() {
	local script_path="$1"
	echo "$(cd "$(dirname "$script_path")" && pwd)"
}

# Run script with captured output
#
# Executes a script in the test directory and captures its output.
# Changes to test directory before running to ensure relative paths work.
#
# Arguments:
#   $1: Path to script to run
#   $2+: Additional arguments to pass to script
#
# Returns:
#   Exit code of the script
#
# Side effects:
#   Changes working directory to TEST_DIR
#   Sets 'output' and 'status' variables (bats convention)
run_script() {
	local script="$1"
	shift
	local args=("$@")

	# Change to test directory
	cd "$TEST_DIR" || return 1

	# Run script with arguments
	run bash "$script" "${args[@]}"
}

# Assert log file contains pattern
#
# Verifies that a log file contains a specific pattern (fixed string match).
# Fails the test if pattern is not found or file doesn't exist.
#
# Arguments:
#   $1: Path to log file
#   $2: Pattern to search for (fixed string, not regex)
#
# Returns:
#   0: Pattern found in log file
#   1: Pattern not found or file doesn't exist (fails test)
#
# Note: Uses BATS_TEST_NAME for better error messages when available
assert_log_contains() {
	local log_file="$1"
	local pattern="$2"

	assert_file_exist "$log_file"

	run grep -Fq -- "$pattern" "$log_file"
	# Use BATS_TEST_NAME in error message if available for better debugging
	if [[ -n "${BATS_TEST_NAME:-}" ]]; then
		assert_success "Log file should contain '$pattern' in test '${BATS_TEST_NAME}'"
	else
		assert_success "Log file should contain: $pattern"
	fi
}

# Assert log file does not contain pattern
#
# Verifies that a log file does NOT contain a specific pattern.
# Succeeds if file doesn't exist (empty file doesn't contain pattern).
# Fails the test if pattern is found.
#
# Arguments:
#   $1: Path to log file
#   $2: Pattern to search for (fixed string, not regex)
#
# Returns:
#   0: Pattern not found (or file doesn't exist)
#   1: Pattern found (fails test)
#
# Note: Uses BATS_TEST_NAME for better error messages when available
assert_log_not_contains() {
	local log_file="$1"
	local pattern="$2"

	if [[ ! -f "$log_file" ]]; then
		return 0 # File doesn't exist, so pattern doesn't exist
	fi

	run grep -Fq -- "$pattern" "$log_file"
	# Use BATS_TEST_NAME in error message if available for better debugging
	if [[ -n "${BATS_TEST_NAME:-}" ]]; then
		assert_failure "Log file should not contain '$pattern' in test '${BATS_TEST_NAME}'"
	else
		assert_failure "Log file should not contain: $pattern"
	fi
}

# Assert log file contains one of multiple patterns
#
# Checks if log file contains at least one of the specified patterns.
# Useful for asserting log messages that may vary slightly.
#
# Arguments:
#   $1: Log file path
#   $2+: Patterns to search for (at least one must match)
#
# Returns:
#   0: At least one pattern found
#   1: No patterns found (fails test)
#
# Note: Uses BATS_TEST_NAME for better error messages when available
#
# Example:
#   assert_log_contains_any "$log_file" "ipsec reload failed" "reload failed"
assert_log_contains_any() {
	local log_file="$1"
	shift
	local patterns=("$@")

	assert_file_exist "$log_file"

	local pattern
	for pattern in "${patterns[@]}"; do
		if grep -Fq -- "$pattern" "$log_file" 2>/dev/null; then
			return 0
		fi
	done

	# No patterns found - fail the test
	local patterns_str
	patterns_str=$(
		IFS="' or '"
		echo "${patterns[*]}"
	)
	# Use BATS_TEST_NAME in error message if available for better debugging
	if [[ -n "${BATS_TEST_NAME:-}" ]]; then
		fail "Expected log to contain one of: '$patterns_str' in test '${BATS_TEST_NAME}'"
	else
		fail "Expected log to contain one of: '$patterns_str'"
	fi
	return 1
}

# Create mock ip command output
#
# Creates a mock 'ip' command that returns fake xfrm state output.
# Used to simulate VPN tunnel states in tests without requiring actual IPsec.
# Handles both "ip xfrm state" and "ip -s xfrm state" (with statistics flag) formats.
#
# Arguments:
#   $1: Peer IP address to include in mock output (destination IP)
#   $2: Byte counter value (default: 1000)
#   $3: SPI value (default: 0x12345678)
#   $4: Source IP address (default: same as peer_ip, or TEST_PEER_IP2 if peer_ip matches TEST_PEER_IP)
#   $5: Optional path to mock ip file (default: ${TEST_DIR}/ip)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script at specified path (default: ${TEST_DIR}/ip)
#
# Example:
#   # Basic usage - static bytes
#   mock_ip_xfrm_state "192.168.1.1" 1000
#   add_mock_to_path
#
#   # Custom SPI and source IP
#   mock_ip_xfrm_state "192.168.1.1" 5000 "0xabcdef12" "10.0.0.1"
mock_ip_xfrm_state() {
	local peer_ip="$1"
	local bytes="${2:-1000}"
	local spi="${3:-0x12345678}"
	local src_ip="${4:-}"
	local mock_ip="${5:-${TEST_DIR}/ip}"

	# Default source IP: use peer_ip (common pattern in tests)
	if [[ -z "$src_ip" ]]; then
		src_ip="$peer_ip"
	fi

	cat >"$mock_ip" <<EOF
#!/bin/bash
# Handle "ip -s xfrm state" (with statistics flag) - tried first by get_xfrm_state_for_peer
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    echo "src ${src_ip} dst ${peer_ip}"
    echo "    proto esp spi ${spi} reqid 1 mode tunnel"
    echo "    lifetime current: ${bytes} bytes, 10 packets"
    exit 0
fi
# Handle "ip xfrm state" (without statistics flag) - fallback used by get_xfrm_state_for_peer
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    echo "src ${src_ip} dst ${peer_ip}"
    echo "    proto esp spi ${spi} reqid 1 mode tunnel"
    echo "    lifetime current: ${bytes} bytes, 10 packets"
    exit 0
fi
# Handle other ip commands
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	echo "$mock_ip"
}

# Create a mock ip command for VPN down scenario
#
# Creates a mock ip command that returns empty output for xfrm state queries,
# simulating a VPN down scenario (no SAs found).
#
# Arguments:
#   $1: Optional path to mock ip file (default: ${TEST_DIR}/ip)
#   $2: Optional additional ip command handlers (string content)
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Creates executable mock ip script at specified path
#   - Adds mock to PATH via add_mock_to_path (if called separately)
#
# Example:
#   # Basic usage:
#   mock_ip_vpn_down
#   add_mock_to_path
#
#   # With custom path:
#   mock_ip_vpn_down "${TEST_DIR}/custom_ip"
#
#   # With additional handlers:
#   local additional_handlers
#   additional_handlers=$(cat <<'ADDITIONAL_EOF'
#   if [[ "$1" == "route" ]] && [[ "$2" == "show" ]]; then
#       exit 1
#   fi
#   ADDITIONAL_EOF
#   )
#   mock_ip_vpn_down "${TEST_DIR}/ip" "$additional_handlers"
mock_ip_vpn_down() {
	local mock_ip="${1:-${TEST_DIR}/ip}"
	local additional_handlers="${2:-}"

	cat >"$mock_ip" <<EOF
#!/bin/bash
# Handle "ip -s xfrm state" (args: -s, xfrm, state) - return empty (VPN down, no SA)
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    exit 0  # Return empty output (no SA found - VPN down)
fi
# Handle "ip xfrm state" (args: xfrm, state) - return empty (VPN down, no SA)
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    exit 0  # Return empty output (no SA found - VPN down)
fi
${additional_handlers}
# Handle other ip commands
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
}

# Create mock ip command with incrementing byte counters
#
# Creates a mock 'ip' command that returns xfrm state output with byte counters
# that increment on each call. Used for tests that need to verify byte counter
# tracking or recovery verification that checks for increasing traffic.
#
# The mock tracks call count in a file and returns byte counters that increase
# by a specified increment on each call. Supports both "ip -s xfrm state" and
# "ip xfrm state" formats.
#
# Arguments:
#   $1: Peer IP address to include in mock output (default: "192.168.1.1")
#   $2: Initial byte counter value (default: 1000)
#   $3: Byte increment per call (default: 1000)
#   $4: SPI value (default: 0x12345678)
#   $5: Optional path to state file for tracking calls (default: ${TEST_DIR}/xfrm_call_count)
#   $6: Optional source IP (default: "10.0.0.1")
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   - Creates executable mock ip script in TEST_DIR
#   - Creates state file to track call count
#
# Example:
#   # Basic usage - bytes increment by 1000 each call
#   mock_ip_xfrm_with_incrementing_bytes "192.168.1.1"
#   add_mock_to_path
#
#   # Custom initial value and increment
#   mock_ip_xfrm_with_incrementing_bytes "192.168.1.1" "5000" "2000"
#
#   # Custom state file for tracking
#   mock_ip_xfrm_with_incrementing_bytes "192.168.1.1" "1000" "1000" "0x12345678" "${TEST_DIR}/custom_state"
mock_ip_xfrm_with_incrementing_bytes() {
	local peer_ip="${1:-${TEST_PEER_IP}}"
	local initial_bytes="${2:-1000}"
	local increment="${3:-1000}"
	local spi="${4:-0x12345678}"
	local state_file="${5:-${TEST_DIR}/xfrm_call_count}"
	local src_ip="${6:-${TEST_PEER_IP2}}"

	local mock_ip="${TEST_DIR}/ip"

	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
	# Handle "ip -s xfrm state" (with statistics flag)
	verify_attempts=\$(cat "$state_file" 2>/dev/null || echo "0")
	verify_attempts=\$((verify_attempts + 1))
	echo "\$verify_attempts" > "$state_file"
	
	# Return increasing byte counter values to simulate traffic flow
	local byte_count=\$((${initial_bytes} + (\$verify_attempts - 1) * ${increment}))
	echo "src ${src_ip} dst ${peer_ip}"
	echo "  proto esp spi ${spi} reqid 1 mode tunnel"
	echo "  lifetime current:"
	echo "    \${byte_count}(bytes), 10(packets)"
	exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
	# Handle "ip xfrm state" (without statistics flag)
	verify_attempts=\$(cat "$state_file" 2>/dev/null || echo "0")
	verify_attempts=\$((verify_attempts + 1))
	echo "\$verify_attempts" > "$state_file"
	
	# Return increasing byte counter values to simulate traffic flow
	local byte_count=\$((${initial_bytes} + (\$verify_attempts - 1) * ${increment}))
	echo "src ${src_ip} dst ${peer_ip}"
	echo "  proto esp spi ${spi} reqid 1 mode tunnel"
	echo "  lifetime current:"
	echo "    \${byte_count}(bytes), 10(packets)"
	exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	echo "$mock_ip"
}

# Create mock ip command for empty xfrm state (VPN down)
#
# Creates a mock 'ip' command that returns empty output for xfrm state queries,
# simulating a VPN down scenario (no SAs found). This is a simpler wrapper
# around mock_ip_vpn_down() for cases where only xfrm state handling is needed.
#
# Arguments:
#   $1: Optional path to mock ip file (default: ${TEST_DIR}/ip)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates executable mock ip script at specified path
#
# Example:
#   # Basic usage:
#   mock_ip_xfrm_empty
#   add_mock_to_path
#
#   # With custom path:
#   mock_ip_xfrm_empty "${TEST_DIR}/custom_ip"
#
# Note:
#   For more complex scenarios with additional ip command handlers,
#   use mock_ip_vpn_down() instead.
mock_ip_xfrm_empty() {
	local mock_ip="${1:-${TEST_DIR}/ip}"

	cat >"$mock_ip" <<EOF
#!/bin/bash
# Handle "ip -s xfrm state" (with statistics flag) - tried first by get_xfrm_state_for_peer
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    exit 0  # Return empty output (no SA found - VPN down)
fi
# Handle "ip xfrm state" (without statistics flag) - fallback used by get_xfrm_state_for_peer
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    exit 0  # Return empty output (no SA found - VPN down)
fi
# Handle other ip commands
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	echo "$mock_ip"
}

# Create mock ping command
#
# Creates a mock 'ping' command that simulates successful or failed ping.
# Used to test ping connectivity checks without requiring network access.
#
# Arguments:
#   $1: Target IP address to ping
#   $2: Success flag ("1" for success, "0" for failure, default: "1")
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR
mock_ping() {
	local target_ip="$1"
	local success="${2:-1}"

	local mock_ping="${TEST_DIR}/mock_ping"
	cat >"$mock_ping" <<EOF
#!/bin/bash
# Mock ping command
if [[ "$success" == "1" ]]; then
    echo "PING ${target_ip} (${target_ip}) 56(84) bytes of data."
    echo "64 bytes from ${target_ip}: icmp_seq=1 ttl=64 time=0.123 ms"
    echo "64 bytes from ${target_ip}: icmp_seq=2 ttl=64 time=0.124 ms"
    echo "64 bytes from ${target_ip}: icmp_seq=3 ttl=64 time=0.125 ms"
    echo ""
    echo "--- ${target_ip} ping statistics ---"
    echo "3 packets transmitted, 3 received, 0% packet loss"
    exit 0
else
    echo "PING ${target_ip} (${target_ip}) 56(84) bytes of data."
    echo ""
    echo "--- ${target_ip} ping statistics ---"
    echo "3 packets transmitted, 0 received, 100% packet loss"
    exit 1
fi
EOF
	chmod +x "$mock_ping"
	echo "$mock_ping"
}

# Create mock ping command that hangs (simulates timeout)
#
# Creates a mock 'ping' command that sleeps longer than typical timeout,
# simulating a ping that hangs or times out.
#
# Arguments:
#   $1: Sleep duration in seconds (default: 2)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR
#
# Example:
#   mock_ping_hang
#   add_mock_to_path
mock_ping_hang() {
	local sleep_duration="${1:-2}"

	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<EOF
#!/bin/bash
# Simulate ping hanging (sleep longer than timeout)
sleep ${sleep_duration}
exit 0
EOF
	chmod +x "$mock_ping"
	echo "$mock_ping"
}

# Create mock ping command with 100% packet loss
#
# Creates a mock 'ping' command that returns success exit code but shows
# 100% packet loss, simulating a weird network state.
#
# Arguments:
#   $1: Target IP address (default: "192.168.1.1")
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR
#
# Example:
#   mock_ping_packet_loss "192.168.1.1"
#   add_mock_to_path
mock_ping_packet_loss() {
	local target_ip="${1:-${TEST_PEER_IP}}"

	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<EOF
#!/bin/bash
# Simulate ping command succeeds but 100% packet loss
echo "PING ${target_ip} (${target_ip}) 56(84) bytes of data."
echo ""
echo "--- ${target_ip} ping statistics ---"
echo "3 packets transmitted, 0 received, 100% packet loss"
exit 0
EOF
	chmod +x "$mock_ping"
	echo "$mock_ping"
}

# Create mock ip command that passes through to real command
#
# Creates a mock 'ip' command that simply executes the real /usr/bin/ip command.
# Used when tests need real ip command behavior but want to ensure it's in PATH.
#
# Arguments:
#   $1: Optional path to mock ip file (default: ${TEST_DIR}/ip)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates executable mock ip script at specified path
#
# Example:
#   mock_ip_pass_through
#   add_mock_to_path
mock_ip_pass_through() {
	local mock_ip="${1:-${TEST_DIR}/ip}"

	cat >"$mock_ip" <<'EOF'
#!/bin/bash
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	echo "$mock_ip"
}

# Create mock ipsec command that passes through to real command
#
# Creates a mock 'ipsec' command that simply executes the real /usr/bin/ipsec command.
# Used when tests need real ipsec command behavior but want to ensure it's in PATH.
#
# Arguments:
#   $1: Optional path to mock ipsec file (default: ${TEST_DIR}/ipsec)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates executable mock ipsec script at specified path
#
# Example:
#   mock_ipsec_pass_through
#   add_mock_to_path
mock_ipsec_pass_through() {
	local mock_ipsec="${1:-${TEST_DIR}/ipsec}"

	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
exec /usr/bin/ipsec "$@"
EOF
	chmod +x "$mock_ipsec"
	echo "$mock_ipsec"
}

# Create mock dirname command that passes through to real command
#
# Creates a mock 'dirname' command that simply executes the real /usr/bin/dirname command.
# Used when tests need real dirname behavior but want to ensure it's in PATH.
#
# Arguments:
#   $1: Optional path to mock dirname file (default: ${TEST_DIR}/dirname)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates executable mock dirname script at specified path
#
# Example:
#   mock_dirname_pass_through
#   add_mock_to_path
mock_dirname_pass_through() {
	local mock_dirname="${1:-${TEST_DIR}/dirname}"

	cat >"$mock_dirname" <<'EOF'
#!/bin/bash
exec /usr/bin/dirname "$@"
EOF
	chmod +x "$mock_dirname"
	echo "$mock_dirname"
}

# Create mock basename command that passes through to real command
#
# Creates a mock 'basename' command that simply executes the real /usr/bin/basename command.
# Used when tests need real basename behavior but want to ensure it's in PATH.
#
# Arguments:
#   $1: Optional path to mock basename file (default: ${TEST_DIR}/basename)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates executable mock basename script at specified path
#
# Example:
#   mock_basename_pass_through
#   add_mock_to_path
mock_basename_pass_through() {
	local mock_basename="${1:-${TEST_DIR}/basename}"

	cat >"$mock_basename" <<'EOF'
#!/bin/bash
exec /usr/bin/basename "$@"
EOF
	chmod +x "$mock_basename"
	echo "$mock_basename"
}

# Create mock ipsec command with simple status handler
#
# Creates a mock 'ipsec' command that handles status with a simple exit code.
# Used for tests that need ipsec status to succeed or fail without complex output.
#
# Arguments:
#   $1: Status exit code ("0" for success, "1" for failure, default: "0")
#   $2: Optional status output (default: empty)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR as "ipsec"
#
# Example:
#   # Status succeeds with no output
#   mock_ipsec_status 0
#   add_mock_to_path
#
#   # Status fails
#   mock_ipsec_status 1
#   add_mock_to_path
#
#   # Status succeeds with output
#   mock_ipsec_status 0 "192.168.1.1: ESTABLISHED"
#   add_mock_to_path
mock_ipsec_status() {
	local status_exit="${1:-0}"
	local status_output="${2:-}"

	local mock_ipsec="${TEST_DIR}/ipsec"
	if [[ -n "$status_output" ]]; then
		cat >"$mock_ipsec" <<EOF
#!/bin/bash
if [[ "\$1" == "status" ]]; then
    echo "$status_output"
    exit ${status_exit}
elif [[ "\$1" == "--help" ]] || [[ "\$1" == "--version" ]]; then
    # Handle command availability checks (used by check_command_available)
    exit 0
fi
exec /usr/bin/ipsec "\$@"
EOF
	else
		cat >"$mock_ipsec" <<EOF
#!/bin/bash
if [[ "\$1" == "status" ]]; then
    exit ${status_exit}
elif [[ "\$1" == "--help" ]] || [[ "\$1" == "--version" ]]; then
    # Handle command availability checks (used by check_command_available)
    exit 0
fi
exec /usr/bin/ipsec "\$@"
EOF
	fi
	chmod +x "$mock_ipsec"
	echo "$mock_ipsec"
}

# Create mock ipsec command
#
# Creates a mock 'ipsec' command that simulates IPsec service operations.
# Supports 'restart', 'reload', and 'status' subcommands for testing.
#
# Arguments:
#   $1: Format type ("libreswan", "strongswan", or "default", default: "default")
#   $2: Optional peer IP address for status output (default: "192.168.1.1")
#   $3: Optional connection name (default: "test-conn")
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR as "ipsec"
mock_ipsec() {
	local format="${1:-default}"
	local peer_ip="${2:-${TEST_PEER_IP}}"
	local conn_name="${3:-test-conn}"
	local mock_ipsec="${TEST_DIR}/ipsec"

	case "$format" in
	libreswan)
		cat >"$mock_ipsec" <<EOF
#!/bin/bash
if [[ "\$1" == "restart" ]]; then
    echo "Restarting IPsec..."
    echo "Stopping IPsec..."
    echo "Starting IPsec..."
    exit 0
fi
if [[ "\$1" == "reload" ]]; then
    echo "Reloading IPsec configuration..."
    exit 0
fi
if [[ "\$1" == "status" ]]; then
    echo "${conn_name}: ESTABLISHED 1 hour ago, ${peer_ip}...${TEST_LOCAL_IP}"
elif [[ "\$1" == "--help" ]] || [[ "\$1" == "--version" ]]; then
    # Handle command availability checks (used by check_command_available)
    exit 0
fi
exec /usr/bin/ipsec "\$@"
EOF
		;;
	strongswan)
		cat >"$mock_ipsec" <<EOF
#!/bin/bash
if [[ "\$1" == "restart" ]]; then
    echo "Restarting IPsec..."
    echo "Stopping IPsec..."
    echo "Starting IPsec..."
    exit 0
fi
if [[ "\$1" == "reload" ]]; then
    echo "Reloading IPsec configuration..."
    exit 0
fi
if [[ "\$1" == "status" ]]; then
    echo "${conn_name}: IKEv2, ESTABLISHED, ${peer_ip}"
elif [[ "\$1" == "--help" ]] || [[ "\$1" == "--version" ]]; then
    # Handle command availability checks (used by check_command_available)
    exit 0
fi
exec /usr/bin/ipsec "\$@"
EOF
		;;
	default)
		cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "Restarting IPsec..."
    echo "Stopping IPsec..."
    echo "Starting IPsec..."
    exit 0
fi
if [[ "$1" == "reload" ]]; then
    echo "Reloading IPsec configuration..."
    exit 0
fi
if [[ "$1" == "status" ]]; then
    echo "IPsec connections:"
    echo "  test-conn: ESTABLISHED"
elif [[ "$1" == "--help" ]] || [[ "$1" == "--version" ]]; then
    # Handle command availability checks (used by check_command_available)
    exit 0
fi
exec /usr/bin/ipsec "$@"
EOF
		;;
	esac
	chmod +x "$mock_ipsec"
	echo "$mock_ipsec"
}

# Create mock ipsec command with configurable reload/restart exit codes
#
# Creates a mock 'ipsec' command that simulates IPsec service operations
# with configurable exit codes for reload and restart subcommands.
# This allows tests to simulate various failure scenarios.
#
# Arguments:
#   $1: Reload exit code (0 = success, 1 = failure, default: 0)
#   $2: Restart exit code (0 = success, 1 = failure, default: 0)
#   $3: Status exit code (optional, default: 0)
#   $4: Format type ("libreswan", "strongswan", or "default", optional, default: "default")
#   $5: Optional peer IP address for status output (optional, default: "192.168.1.1")
#   $6: Optional connection name for status output (optional, default: "test-conn")
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR as "ipsec"
mock_ipsec_reload_restart() {
	local reload_exit="${1:-0}"
	local restart_exit="${2:-0}"
	local status_exit="${3:-0}"
	local format="${4:-default}"
	local peer_ip="${5:-${TEST_PEER_IP}}"
	local conn_name="${6:-test-conn}"
	local mock_ipsec="${TEST_DIR}/ipsec"

	case "$format" in
	libreswan)
		cat >"$mock_ipsec" <<EOF
#!/bin/bash
if [[ "\$1" == "restart" ]]; then
    echo "Restarting IPsec..."
    echo "Stopping IPsec..."
    echo "Starting IPsec..."
    exit ${restart_exit}
fi
if [[ "\$1" == "reload" ]]; then
    echo "Reloading IPsec configuration..."
    exit ${reload_exit}
fi
if [[ "\$1" == "status" ]]; then
    if [[ ${status_exit} -eq 0 ]]; then
        echo "${conn_name}: ESTABLISHED 1 hour ago, ${peer_ip}...192.168.1.2"
    fi
    exit ${status_exit}
elif [[ "\$1" == "--help" ]] || [[ "\$1" == "--version" ]]; then
    # Handle command availability checks (used by check_command_available)
    exit 0
fi
exec /usr/bin/ipsec "\$@"
EOF
		;;
	strongswan)
		cat >"$mock_ipsec" <<EOF
#!/bin/bash
if [[ "\$1" == "restart" ]]; then
    echo "Restarting IPsec..."
    echo "Stopping IPsec..."
    echo "Starting IPsec..."
    exit ${restart_exit}
fi
if [[ "\$1" == "reload" ]]; then
    echo "Reloading IPsec configuration..."
    exit ${reload_exit}
fi
if [[ "\$1" == "status" ]]; then
    if [[ ${status_exit} -eq 0 ]]; then
        echo "${conn_name}: IKEv2, ESTABLISHED, ${peer_ip}"
    fi
    exit ${status_exit}
elif [[ "\$1" == "--help" ]] || [[ "\$1" == "--version" ]]; then
    # Handle command availability checks (used by check_command_available)
    exit 0
fi
exec /usr/bin/ipsec "\$@"
EOF
		;;
	default)
		cat >"$mock_ipsec" <<EOF
#!/bin/bash
if [[ "\$1" == "restart" ]]; then
    echo "Restarting IPsec..."
    echo "Stopping IPsec..."
    echo "Starting IPsec..."
    exit ${restart_exit}
fi
if [[ "\$1" == "reload" ]]; then
    echo "Reloading IPsec configuration..."
    exit ${reload_exit}
fi
if [[ "\$1" == "status" ]]; then
    if [[ ${status_exit} -eq 0 ]]; then
        echo "IPsec connections:"
        echo "  ${conn_name}: ESTABLISHED"
    fi
    exit ${status_exit}
elif [[ "\$1" == "--help" ]] || [[ "\$1" == "--version" ]]; then
    # Handle command availability checks (used by check_command_available)
    exit 0
fi
exec /usr/bin/ipsec "\$@"
EOF
		;;
	esac
	chmod +x "$mock_ipsec"
	echo "$mock_ipsec"
}

# Add mock commands to PATH
#
# Prepends TEST_DIR to PATH so mock commands are found before real system commands.
# Must be called after creating mock commands and before running scripts that use them.
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Modifies PATH environment variable
add_mock_to_path() {
	export PATH="${TEST_DIR}:${PATH}"
}

# Remove mock commands from PATH
#
# Removes TEST_DIR from PATH to restore original command search order.
# Should be called after tests complete to clean up PATH modifications.
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Modifies PATH environment variable
remove_mock_from_path() {
	# Use bash parameter expansion instead of sed for better performance and reliability
	local new_path="${PATH//${TEST_DIR}:/}"
	export PATH="$new_path"
}

# Run code with mocks, ensuring cleanup even on failure
#
# Wrapper function that ensures mock cleanup happens even if the wrapped code fails.
# This prevents test pollution by guaranteeing mocks are removed from PATH.
#
# Arguments:
#   $1: Mock setup commands (string to be evaluated, e.g., "mock_ip_xfrm_state \"192.168.1.1\" 1000")
#   $2+: Command and arguments to execute with mocks in PATH
#
# Returns:
#   Exit code of the executed command
#
# Side effects:
#   - Evaluates mock setup commands
#   - Adds TEST_DIR to PATH
#   - Executes provided command
#   - Removes TEST_DIR from PATH (always, even on failure)
#
# Example:
#   # Basic usage with mock setup and command execution
#   with_mocks 'mock_ip_xfrm_state "${TEST_PEER_IP}" 1000' \
#       run bash "$TEST_SCRIPT"
#
#   # Multiple mock setup commands
#   with_mocks 'mock_ip_xfrm_state "${TEST_PEER_IP}" 1000; mock_ping "${TEST_PEER_IP}" 1' \
#       run bash "$TEST_SCRIPT"
#
#   # With function call
#   with_mocks 'mock_ip_xfrm_state "${TEST_PEER_IP}" 1000' \
#       check_vpn_status "${TEST_PEER_IP}"
#
# Note:
#   - Mock setup commands are evaluated in the current shell context
#   - Cleanup is guaranteed via trap-like behavior (always removes mocks)
#   - This is optional - explicit add_mock_to_path/remove_mock_from_path is still valid
#   - teardown() also restores PATH, but this ensures cleanup happens immediately
with_mocks() {
	local mock_setup="$1"
	shift
	local exit_code=0

	# Evaluate mock setup commands
	# If eval fails, we should not proceed with adding mocks to PATH
	if ! eval "$mock_setup"; then
		# Mock setup failed - return error without modifying PATH
		return 1
	fi

	# Add mocks to PATH
	add_mock_to_path

	# Execute the command(s)
	# Check if any command was provided
	if [[ $# -eq 0 ]]; then
		# No command provided - this is a usage error
		remove_mock_from_path
		return 1
	fi

	"$@"
	exit_code=$?

	# Always remove mocks from PATH, even if command failed
	remove_mock_from_path

	return $exit_code
}

# Assert state file exists and contains value
#
# Verifies that a state file exists and contains the expected value.
# Used to check failure counters, restart counts, and other state files.
#
# Arguments:
#   $1: Path to state file
#   $2: Expected value (exact match)
#
# Returns:
#   0: File exists and contains expected value
#   1: File doesn't exist or contains different value (fails test)
assert_state_file() {
	local state_file="$1"
	local expected_value="$2"

	assert_file_exist "$state_file"
	run cat "$state_file"
	assert_success
	assert_output "$expected_value"
}

# Wait for file to appear (with timeout)
#
# Polls for a file to appear, waiting up to the specified timeout.
# Useful for testing asynchronous operations that create files.
#
# Arguments:
#   $1: Path to file to wait for
#   $2: Timeout in seconds (default: 5)
#
# Returns:
#   0: File appeared within timeout
#   1: Timeout exceeded, file not found
wait_for_file() {
	local file="$1"
	local timeout="${2:-5}"
	local start_time
	local elapsed_time
	local sleep_interval=0.01 # Reduced from 0.1s to 0.01s for faster response

	# Get start time in seconds since epoch
	start_time=$(date +%s 2>/dev/null || echo "0")

	# If date command failed, use iteration-based fallback
	if [[ "$start_time" == "0" ]]; then
		# Fallback: use iteration counting (less accurate but works without date)
		local max_iterations=$((timeout * 100)) # timeout * (1 / sleep_interval) - updated for 0.01s interval
		local iterations=0
		while [[ $iterations -lt $max_iterations ]]; do
			if [[ -f "$file" ]]; then
				return 0
			fi
			sleep "$sleep_interval"
			iterations=$((iterations + 1))
		done
		return 1
	fi

	# Normal path: use time-based checking
	while true; do
		if [[ -f "$file" ]]; then
			return 0
		fi

		# Calculate elapsed time
		elapsed_time=$(($(date +%s) - start_time))
		if [[ $elapsed_time -ge $timeout ]]; then
			return 1
		fi

		sleep "$sleep_interval"
	done
}

# ============================================================================
# Test Setup Helper Functions - Reduce Duplication Across Tests
# ============================================================================

# Create a test config file with common settings (DEPRECATED - use setup_test_location_config instead)
#
# Creates a vpn-monitor.conf file with customizable settings using old EXTERNAL_PEER_IPS format.
# DEPRECATED: This function uses the deprecated EXTERNAL_PEER_IPS format which is no longer supported.
# Use setup_test_location_config() instead for location-based configuration.
#
# Arguments:
#   $1: Path to config file (default: ${TEST_DIR}/vpn-monitor.conf)
#   $2: EXTERNAL_PEER_IPS value (default: "192.168.1.1")
#   $3+: Additional config variables as KEY="VALUE" pairs
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created config file
#
# Example:
#   setup_test_config "${TEST_DIR}/vpn-monitor.conf" "192.168.1.1 10.0.0.1" 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3'
#
# Deprecated:
#   This function creates config files with EXTERNAL_PEER_IPS which is deprecated.
#   Use setup_test_location_config() instead.
setup_test_config() {
	local config_file="${1:-${TEST_DIR}/vpn-monitor.conf}"
	# Use ${2-} instead of ${2:-} to allow empty strings to pass through
	local peer_ips="${2-${TEST_PEER_IP}}"
	shift 2 || true
	local extra_config=("$@")

	mkdir -p "$(dirname "$config_file")"

	cat >"$config_file" <<EOF
EXTERNAL_PEER_IPS="${peer_ips}"
VPN_NAME="Test VPN"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
COOLDOWN_MINUTES=15
MAX_RESTARTS_PER_HOUR=3
LOG_FILE="${TEST_DIR}/logs/vpn-monitor.log"
STATE_DIR="${TEST_DIR}"
CRON_SCHEDULE="*/1 * * * *"
LOCKFILE_TIMEOUT=5
ENABLE_PING_CHECK=1
PING_COUNT=3
PING_TIMEOUT=2
ENABLE_NETWORK_PARTITION_CHECK=0
DEBUG=0
EOF

	# Add any extra config variables
	for config_var in "${extra_config[@]}"; do
		if [[ -n "$config_var" ]]; then
			# Ensure config_var is in KEY=VALUE format, not just a bare value
			if [[ "$config_var" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
				echo "$config_var" >>"$config_file"
			else
				# Skip bare values that aren't in KEY=VALUE format
				# This prevents bare IP addresses or other values from being written
				continue
			fi
		fi
	done

	echo "$config_file"
}

# Set up location-based VPN monitor test environment
#
# Creates a test VPN monitor environment using location-based configuration.
# This is similar to setup_test_vpn_monitor but uses location-based config format.
#
# Arguments:
#   $1: External IP for location (default: "192.168.1.1")
#   $2: State directory (optional, defaults to ${TEST_DIR})
#   $3+: Additional config variables as KEY="VALUE" pairs
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Creates config file with location-based format
#   - Creates test script
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR variables
#
# Example:
#   setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'TIER1_THRESHOLD=1'
setup_location_vpn_monitor() {
	local external_ip="${1:-${TEST_PEER_IP}}"
	local state_dir="${2:-${TEST_DIR}}"
	shift 2 || true
	local extra_config=("$@")

	local vpn_monitor_script="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

	# Set up environment
	setup_test_environment "$state_dir"

	# Create config file with location-based format
	TEST_CONFIG_FILE="${TEST_DIR}/vpn-monitor.conf"
	# Check if LOCATION_TEST_INTERNAL is already provided in extra_config
	local has_internal=0
	for config_var in "${extra_config[@]}"; do
		if [[ "$config_var" =~ ^LOCATION_TEST_INTERNAL= ]]; then
			has_internal=1
			break
		fi
	done

	# Only set LOCATION_TEST_INTERNAL if not already provided
	local config_args=("LOCATION_TEST_EXTERNAL=\"${external_ip}\"")
	if [[ $has_internal -eq 0 ]]; then
		config_args+=("LOCATION_TEST_INTERNAL=\"${external_ip}\"")
	fi
	config_args+=("${extra_config[@]}")

	setup_test_location_config "$TEST_CONFIG_FILE" "${config_args[@]}"

	# Create test script
	TEST_SCRIPT=$(create_test_vpn_monitor_script \
		"$vpn_monitor_script" \
		"${TEST_DIR}/vpn-monitor.sh" \
		"$TEST_CONFIG_FILE" \
		"$STATE_DIR" \
		"$LOG_FILE")

	export TEST_CONFIG_FILE TEST_SCRIPT
}

# Set up test config with recovery settings disabled
#
# Creates a test configuration file with recovery-related settings disabled.
# This is commonly needed for tests that need ipsec reload/restart to be triggered
# instead of xfrm recovery, or tests that need network partition checks disabled.
#
# Arguments:
#   $1: Config file path (optional, defaults to ${TEST_DIR}/vpn-monitor.conf)
#   $2: Peer IPs (optional, defaults to "192.168.1.1")
#   $3+: Additional config variables as KEY="VALUE" pairs
#
# Returns:
#   Prints config file path to stdout
#
# Side effects:
#   - Creates config file with ENABLE_XFRM_RECOVERY=0 and ENABLE_NETWORK_PARTITION_CHECK=0
#
# Example:
#   setup_test_config_with_recovery_disabled "${TEST_DIR}/vpn-monitor.conf" "192.168.1.1" 'TIER1_THRESHOLD=1'
setup_test_config_with_recovery_disabled() {
	local config_file="${1:-${TEST_DIR}/vpn-monitor.conf}"
	local peer_ips="${2-192.168.1.1}"
	shift 2 || true
	local extra_config=("$@")

	# Call setup_test_config with recovery settings disabled
	setup_test_config "$config_file" "$peer_ips" \
		'ENABLE_XFRM_RECOVERY=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0' \
		"${extra_config[@]}"
}

# Set up test environment variables
#
# Sets up common environment variables used by tests (LOGS_DIR, STATE_DIR, etc.).
# Creates necessary directories.
#
# Arguments:
#   $1: State directory path (default: ${TEST_DIR})
#   $2: Logs directory path (default: ${STATE_DIR}/logs)
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Creates directories
#   - Exports LOGS_DIR, STATE_DIR, LOCKFILE, LOG_FILE, RESTART_COUNT_FILE (in STATE_DIR), COOLDOWN_UNTIL_FILE
setup_test_environment() {
	local state_dir="${1:-${TEST_DIR}}"
	local logs_dir="${2:-${state_dir}/logs}"

	mkdir -p "$logs_dir"
	mkdir -p "$state_dir"

	export STATE_DIR="$state_dir"
	export LOGS_DIR="$logs_dir"
	export LOCKFILE="${state_dir}/vpn-monitor.lock"
	export LOG_FILE="${logs_dir}/vpn-monitor.log"
	export RESTART_COUNT_FILE="${state_dir}/restart_count"
	export COOLDOWN_UNTIL_FILE="${state_dir}/cooldown_until"
}

# Common detection test setup
#
# Convenience function that combines setup_vpn_active_fixture() and add_mock_to_path()
# for common detection test scenarios. This reduces duplication when tests need
# a simple active VPN setup with mocks in PATH.
#
# Note: This function requires that fixtures/vpn_active is loaded in the test file.
# Use this helper when you don't need to add additional mocks between fixture setup
# and adding mocks to PATH. For more complex scenarios, use setup_vpn_active_fixture()
# directly and add mocks before calling add_mock_to_path().
#
# Arguments:
#   $1: Peer IP address (default: "${TEST_PEER_IP}")
#   $2: Initial byte counter value (default: 1000)
#   $3: Current byte counter value (default: 2000, should be > initial)
#   $4: SPI value (default: 0x12345678)
#   $5+: Additional config variables as KEY="VALUE" pairs
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Sets up test VPN monitor environment via setup_vpn_active_fixture()
#   - Adds mock commands to PATH via add_mock_to_path()
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR variables
#
# Example:
#   # Load required fixture
#   load fixtures/vpn_active
#
#   @test "detection test" {
#       setup_detection_test "${TEST_PEER_IP}"
#       run bash "$TEST_SCRIPT" --fake
#       assert_success
#       remove_mock_from_path
#   }
#
#   # With custom byte counters
#   setup_detection_test "${TEST_PEER_IP}" 5000 6000
#
#   # With additional config
#   setup_detection_test "${TEST_PEER_IP}" 1000 2000 "" 'ENABLE_PING_CHECK=1'
setup_detection_test() {
	local peer_ip="${1:-${TEST_PEER_IP}}"
	local initial_bytes="${2:-1000}"
	local current_bytes="${3:-2000}"
	local spi="${4:-0x12345678}"
	shift 4 || true
	local extra_config=("$@")

	# Set up VPN active fixture (requires fixtures/vpn_active to be loaded)
	setup_vpn_active_fixture "$peer_ip" "$initial_bytes" "$current_bytes" "$spi" "${extra_config[@]}"

	# Add mocks to PATH
	# Note: setup_vpn_active_fixture() → setup_mock_vpn_environment() already calls add_mock_to_path(),
	# but we call it again here for defensive programming and to match the original test pattern.
	# This is harmless since add_mock_to_path() is idempotent.
	add_mock_to_path
}

# Set up complete VPN monitor test environment
#
# Creates config file, test script, and sets up environment variables.
# This is a convenience function that combines common setup steps.
#
# Arguments:
#   $1: Peer IPs (default: "192.168.1.1")
#   $2: State directory (default: ${TEST_DIR})
#   $3+: Additional config variables as KEY="VALUE" pairs
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Sets global variables: TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR
#
# Side effects:
#   - Creates config file
#   - Creates test script
#   - Sets up environment variables
setup_test_vpn_monitor() {
	# Use ${1-} instead of ${1:-} to allow empty strings to pass through
	# ${1:-default} uses default if $1 is unset OR empty
	# ${1-default} uses default only if $1 is unset (allows empty string)
	local peer_ips="${1-${TEST_PEER_IP}}"
	local state_dir="${2:-${TEST_DIR}}"
	shift 2 || true
	local extra_config=("$@")

	local vpn_monitor_script="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

	# Set up environment
	setup_test_environment "$state_dir"

	# Create config file with location-based format
	TEST_CONFIG_FILE="${TEST_DIR}/vpn-monitor.conf"

	# Convert peer IPs to location-based config variables
	local location_configs=()
	local location_num=1
	# Split peer_ips by whitespace and create location variables
	if [[ -n "$peer_ips" ]]; then
		# Handle empty strings in the middle (multiple spaces)
		# Use read -a to split properly, but also detect multiple consecutive spaces
		local ip_array
		read -ra ip_array <<<"$peer_ips" || true

		# Check if original string had multiple consecutive spaces (indicates empty IP)
		# This is a heuristic: if the string has "  " (double space), create an empty entry
		if [[ "$peer_ips" =~ [[:space:]]{2,} ]]; then
			# Found multiple spaces - create entries including an empty one in the middle
			local first_ip="${ip_array[0]:-}"
			local second_ip="${ip_array[1]:-}"

			# Create first location
			if [[ -n "$first_ip" ]]; then
				local location_name="TEST${location_num}"
				location_configs+=("LOCATION_${location_name}_EXTERNAL=\"${first_ip}\"")
				location_configs+=("LOCATION_${location_name}_INTERNAL=\"${first_ip}\"")
				location_num=$((location_num + 1))
			fi

			# Create empty location (this is what we're testing)
			local location_name="TEST${location_num}"
			location_configs+=("LOCATION_${location_name}_EXTERNAL=\"\"")
			location_configs+=("LOCATION_${location_name}_INTERNAL=\"\"")
			location_num=$((location_num + 1))

			# Create second location if it exists
			if [[ -n "$second_ip" ]]; then
				location_name="TEST${location_num}"
				location_configs+=("LOCATION_${location_name}_EXTERNAL=\"${second_ip}\"")
				location_configs+=("LOCATION_${location_name}_INTERNAL=\"${second_ip}\"")
				location_num=$((location_num + 1))
			fi
		else
			# Normal case: no multiple spaces, process all IPs
			for ip in "${ip_array[@]}"; do
				# Skip empty IPs (from trailing spaces, etc.)
				[[ -z "$ip" ]] && continue

				# Create location variable name
				local location_name="TEST${location_num}"
				location_configs+=("LOCATION_${location_name}_EXTERNAL=\"${ip}\"")
				location_configs+=("LOCATION_${location_name}_INTERNAL=\"${ip}\"")
				location_num=$((location_num + 1))
			done
		fi
	fi

	# Combine location configs with extra config
	setup_test_location_config "$TEST_CONFIG_FILE" \
		"${location_configs[@]}" \
		"${extra_config[@]}"

	# Create test script
	TEST_SCRIPT=$(create_test_vpn_monitor_script \
		"$vpn_monitor_script" \
		"${TEST_DIR}/vpn-monitor.sh" \
		"$TEST_CONFIG_FILE" \
		"$STATE_DIR" \
		"$LOG_FILE")

	export TEST_CONFIG_FILE TEST_SCRIPT
}

# Set up location-based configuration file
#
# Creates a test configuration file with location-based format (LOCATION_*_EXTERNAL/LOCATION_*_INTERNAL).
# This is similar to setup_test_config but uses the new location-based format instead of EXTERNAL_PEER_IPS.
#
# Arguments:
#   $1: Config file path (optional, defaults to ${TEST_DIR}/vpn-monitor.conf)
#   $2+: Additional config variables as KEY="VALUE" pairs (location configs should be included here)
#
# Returns:
#   Prints the path to the created config file
#
# Side effects:
#   - Creates config file with location-based format and common test settings
#
# Example:
#   setup_test_location_config "${TEST_DIR}/vpn-monitor.conf" \
#     'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
#     'LOCATION_NYC_INTERNAL="192.168.1.1"' \
#     'TIER1_THRESHOLD=1'
#
# Note:
#   Location variables (LOCATION_*_EXTERNAL/LOCATION_*_INTERNAL) should be provided as extra_config
#   This function provides the common test settings; location-specific configs are added via extra_config
setup_test_location_config() {
	local config_file="${1:-${TEST_DIR}/vpn-monitor.conf}"
	shift || true
	local extra_config=("$@")

	mkdir -p "$(dirname "$config_file")"

	cat >"$config_file" <<EOF
VPN_NAME="Test VPN"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
COOLDOWN_MINUTES=15
MAX_RESTARTS_PER_HOUR=3
LOG_FILE="${TEST_DIR}/logs/vpn-monitor.log"
STATE_DIR="${TEST_DIR}"
CRON_SCHEDULE="*/1 * * * *"
LOCKFILE_TIMEOUT=5
ENABLE_PING_CHECK=1
PING_COUNT=3
PING_TIMEOUT=2
ENABLE_NETWORK_PARTITION_CHECK=0
DEBUG=0
EOF

	# Add any extra config variables (including location configs)
	for config_var in "${extra_config[@]}"; do
		if [[ -n "$config_var" ]]; then
			# Ensure config_var is in KEY=VALUE format, not just a bare value
			if [[ "$config_var" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
				echo "$config_var" >>"$config_file"
			else
				# Skip bare values that aren't in KEY=VALUE format
				# This prevents bare IP addresses or other values from being written
				continue
			fi
		fi
	done

	echo "$config_file"
}

# Enable fake mode (non-escalating error handling)
#
# Sets NO_ESCALATE=1 to prevent functions from exiting on errors.
# This is used in tests that expect failures and want to verify error handling
# without the function exiting the script.
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Sets and exports NO_ESCALATE=1
#
# Example:
#   enable_fake_mode
#   run parse_location_config
#   assert_failure
#
# Note:
#   This should be called before functions that might exit on error
#   Standard pattern: enable_fake_mode before calling function that may fail
enable_fake_mode() {
	NO_ESCALATE=1
	export NO_ESCALATE
}

# Set up location-based configuration and load it
#
# Sets up test environment, sets CONFIG_FILE, and loads the configuration.
# This helper reduces code duplication in location-based tests.
# The config file should already exist before calling this function.
#
# Arguments:
#   $1: Config file path (required)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Sets CONFIG_FILE environment variable
#   Calls load_config() to load the configuration
#
# Side effects:
#   - Sets up test environment (calls setup_test_environment)
#   - Sets and exports CONFIG_FILE
#   - Loads configuration using load_config()
#
# Example:
#   local config_file="${TEST_DIR}/vpn-monitor.conf"
#   cat >"$config_file" <<'EOF'
#   LOCATION_NYC_EXTERNAL="203.0.113.1"
#   TIER1_THRESHOLD=1
#   EOF
#   setup_location_config_and_load "$config_file"
#
# Note:
#   Requires load_config() function to be available (from lib/config.sh)
#   Config file must exist before calling this function
#   CONFIG_FILE is always exported (standardized pattern)
setup_location_config_and_load() {
	local config_file="$1"

	# Set up test environment
	setup_test_environment

	# Set and export CONFIG_FILE (standardized: always export)
	CONFIG_FILE="$config_file"
	export CONFIG_FILE

	# Load config (requires lib/config.sh to be sourced)
	if command -v load_config >/dev/null 2>&1; then
		load_config "$config_file"
	fi
}

# Helper function to create location-based config
# Uses the shared helper from test_helper.bash to avoid code duplication
setup_location_config() {
	local config_file="${1:-${TEST_DIR}/vpn-monitor.conf}"
	shift || true
	local extra_config=("$@")

	# Use shared helper function with default location configs
	setup_test_location_config "$config_file" \
		'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
		"LOCATION_NYC_INTERNAL=\"${TEST_PEER_IP}\"" \
		'LOCATION_LA_EXTERNAL="198.51.100.1"' \
		'LOCATION_LA_INTERNAL="192.168.2.1"' \
		"${extra_config[@]}"
}

# Helper function to set up location-based test environment
# Sets up test environment, creates config file, and creates test script
setup_location_test_vpn_monitor() {
	local state_dir="${1:-${TEST_DIR}}"
	shift || true
	local extra_config=("$@")

	setup_test_environment "$state_dir"

	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_location_config "$config_file" "${extra_config[@]}"

	TEST_CONFIG_FILE="$config_file"
	TEST_SCRIPT=$(create_test_vpn_monitor_script \
		"$VPN_MONITOR_SCRIPT" \
		"${TEST_DIR}/vpn-monitor.sh" \
		"$TEST_CONFIG_FILE" \
		"$STATE_DIR" \
		"$LOG_FILE")

	export TEST_CONFIG_FILE TEST_SCRIPT
}

# Ensure state functions are loaded
#
# Sources lib/state.sh if state functions are not already available.
# This helper reduces duplication when fixtures need to use state functions.
# Safe to call multiple times (idempotent).
#
# Returns:
#   0: Always succeeds (state functions available or sourced)
#
# Side effects:
#   - Sources lib/state.sh if set_peer_state is not available
#   - Sets up required environment variables (STATE_DIR, LOGS_DIR) if not set
#
# Example:
#   ensure_state_functions_loaded
#   set_peer_state "" "192.168.1.1" "failure_count" "5"
#
# Note:
#   Uses 2>/dev/null || true to suppress errors if state.sh is not found
#   (for maximum compatibility in test environments)
ensure_state_functions_loaded() {
	# Check if state functions are already available
	if command -v set_peer_state >/dev/null 2>&1; then
		return 0
	fi

	# Set up required environment variables if not already set
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR
	LOGS_DIR="${LOGS_DIR:-${STATE_DIR}/logs}"
	export LOGS_DIR

	# Source logging.sh first (state.sh requires handle_error from logging.sh)
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true

	# Source state.sh
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
}

# Get location name from location config variable
#
# Extracts the location name from a LOCATION_*_EXTERNAL or LOCATION_*_INTERNAL
# config variable name. This reduces duplication in tests that need to extract
# location names from config variables.
#
# Arguments:
#   $1: Config variable name (e.g., "LOCATION_TEST_EXTERNAL")
#
# Returns:
#   0: Location name extracted successfully
#   1: Invalid variable name format
#
# Output:
#   Prints location name to stdout (e.g., "TEST")
#
# Example:
#   location=$(get_location_name_from_config_var "LOCATION_TEST_EXTERNAL")
#   # Returns: "TEST"
#
# Note:
#   Uses extract_location_name() from lib/config.sh if available.
#   Falls back to regex extraction if config.sh is not sourced.
get_location_name_from_config_var() {
	local var_name="$1"
	local location_name=""

	# Try using extract_location_name from lib/config.sh if available
	if command -v extract_location_name >/dev/null 2>&1; then
		if location_name=$(extract_location_name "$var_name" 2>/dev/null); then
			echo "$location_name"
			return 0
		fi
	fi

	# Fallback: Extract location name using regex
	# Pattern: LOCATION_<NAME>_EXTERNAL or LOCATION_<NAME>_INTERNAL
	if [[ "$var_name" =~ ^LOCATION_(.+)_(EXTERNAL|INTERNAL)$ ]]; then
		location_name="${BASH_REMATCH[1]}"
		echo "$location_name"
		return 0
	fi

	return 1
}

# Get failure counter path for a location config variable
#
# Helper function that extracts the location name from a config variable and
# returns the path to the failure counter file. This reduces duplication in
# tests that need to set up failure counters with location names.
#
# Arguments:
#   $1: Location config variable name (e.g., "LOCATION_TEST_EXTERNAL")
#   $2: Peer IP address (default: ${TEST_PEER_IP})
#
# Returns:
#   0: Path retrieved successfully
#   1: Invalid variable name or function unavailable
#
# Output:
#   Prints failure counter file path to stdout
#
# Side effects:
#   - Sources get_peer_state_file_path if not available
#
# Example:
#   failure_counter=$(get_failure_counter_path_for_location_var "LOCATION_TEST_EXTERNAL" "${TEST_PEER_IP}")
#   echo "5" >"$failure_counter"
#
# Note:
#   This replaces the common pattern:
#     source_function "get_peer_state_file_path"
#     # Location name is "TEST" (extracted from LOCATION_TEST_EXTERNAL)
#     failure_counter=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
get_failure_counter_path_for_location_var() {
	local var_name="$1"
	local peer_ip="${2:-${TEST_PEER_IP}}"
	local location_name
	local failure_counter_path

	# Extract location name from config variable
	if ! location_name=$(get_location_name_from_config_var "$var_name"); then
		return 1
	fi

	# Ensure get_peer_state_file_path is available
	if ! command -v get_peer_state_file_path >/dev/null 2>&1; then
		source_function "get_peer_state_file_path" || return 1
	fi

	# Get failure counter path
	failure_counter_path=$(get_peer_state_file_path "$location_name" "$peer_ip" "failure_count")
	echo "$failure_counter_path"
	return 0
}

# Set up complete mock VPN environment
#
# Creates mock ip, ipsec, and ping commands and adds them to PATH.
# This is a convenience function for tests that need multiple mocks.
#
# Arguments:
#   $1: Peer IP for ip xfrm mock (default: "192.168.1.1")
#   $2: Bytes value for ip xfrm mock (default: 1000)
#   $3: SPI value for ip xfrm mock (default: 0x12345678)
#   $4: Ping target IP (optional, creates ping mock if provided)
#   $5: Ping success flag (default: 1, set to 0 for ping failure)
#   $6: Create ipsec mock (default: 1, set to 0 to skip)
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Creates mock commands in TEST_DIR
#   - Adds TEST_DIR to PATH
#   - Sets MOCK_IP, MOCK_PING, MOCK_IPSEC variables
setup_mock_vpn_environment() {
	local peer_ip="${1:-${TEST_PEER_IP}}"
	local bytes="${2:-1000}"
	local spi="${3:-0x12345678}"
	local ping_target="${4:-}"
	local ping_success="${5:-1}"
	local create_ipsec="${6:-1}"

	# Create mock ip command
	MOCK_IP=$(mock_ip_xfrm_state "$peer_ip" "$bytes" "$spi")
	mv "$MOCK_IP" "${TEST_DIR}/ip" 2>/dev/null || true
	MOCK_IP="${TEST_DIR}/ip"

	# Create mock ping if requested
	if [[ -n "$ping_target" ]]; then
		MOCK_PING=$(mock_ping "$ping_target" "$ping_success")
		mv "$MOCK_PING" "${TEST_DIR}/ping" 2>/dev/null || true
		MOCK_PING="${TEST_DIR}/ping"
	fi

	# Create mock ipsec if requested
	if [[ "$create_ipsec" == "1" ]]; then
		MOCK_IPSEC=$(mock_ipsec "default")
	fi

	# Add mocks to PATH
	add_mock_to_path

	export MOCK_IP MOCK_PING MOCK_IPSEC
}

# Create mock ip command for route checks
#
# Creates a mock 'ip' command that handles route show default commands.
# Used for network partition detection tests.
#
# Arguments:
#   $1: Route exists flag ("1" for exists, "0" for missing, default: "1")
#   $2: Optional route output (default: "default via 192.168.1.1 dev eth0")
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR as "ip"
mock_ip_route() {
	local route_exists="${1:-1}"
	local route_output="${2:-default via ${TEST_PEER_IP} dev eth0}"

	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "route" ]] && [[ "\$2" == "show" ]] && [[ "\$3" == "default" ]]; then
    if [[ "$route_exists" == "1" ]]; then
        echo "$route_output"
        exit 0
    else
        exit 1
    fi
fi
# Handle other ip commands
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	echo "$mock_ip"
}

# Create mock ip command for interface state checks
#
# Creates a mock 'ip' command that handles link show commands.
# Used for network partition detection tests.
#
# Arguments:
#   $1: Comma-separated list of interface states ("UP" or "DOWN", default: "UP")
#   $2: Comma-separated list of interface names (default: "eth0,eth1")
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR as "ip"
mock_ip_link() {
	local states="${1:-UP,UP}"
	local interfaces="${2:-eth0,eth1}"

	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "link" ]] && [[ "\$2" == "show" ]]; then
    # Parse states and interfaces
    IFS=',' read -r -a state_array <<< "$states"
    IFS=',' read -r -a iface_array <<< "$interfaces"
    
    for i in "\${!iface_array[@]}"; do
        local iface="\${iface_array[\$i]}"
        local state="\${state_array[\$i]:-UP}"
        echo "\${i}: \${iface}: <BROADCAST,MULTICAST,\${state},LOWER_UP> mtu 1500"
    done
    exit 0
fi
# Handle other ip commands
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	echo "$mock_ip"
}

# Create mock dig command for DNS resolution checks
#
# Creates a mock 'dig' command that simulates DNS resolution.
# Used for network partition detection tests.
#
# Arguments:
#   $1: Success flag ("1" for success, "0" for failure/timeout, default: "1")
#   $2: IP address to return (default: "8.8.8.8")
#   $3: Timeout behavior ("timeout" for timeout, "unreachable" for unreachable, default: success)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR as "dig"
mock_dig() {
	local success="${1:-1}"
	local ip_address="${2:-8.8.8.8}"
	local timeout_behavior="${3:-}"

	local mock_dig="${TEST_DIR}/dig"
	cat >"$mock_dig" <<EOF
#!/bin/bash
if [[ "$success" == "1" ]]; then
    echo "$ip_address"
    exit 0
elif [[ "$timeout_behavior" == "timeout" ]]; then
    # Simulate timeout
    sleep 0.1
    exit 124
elif [[ "$timeout_behavior" == "unreachable" ]]; then
    echo ";; connection timed out; no servers could be reached"
    exit 9
else
    # General failure
    exit 1
fi
EOF
	chmod +x "$mock_dig"
	echo "$mock_dig"
}

# Create mock ping command that succeeds with proper output
#
# Creates a mock 'ping' command that always succeeds and outputs packet loss info
# in the format expected by check_ping_connectivity. Handles all common ping arguments.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR as "ping"
mock_ping_success() {
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
# Mock ping that always succeeds and outputs packet loss info
# Handle common ping arguments: -c, -W, -w, -q, -I, -6, target_ip
echo "3 packets transmitted, 3 received, 0% packet loss"
exit 0
EOF
	chmod +x "$mock_ping"
	echo "$mock_ping"
}

# Create mock ping command that fails
#
# Creates a mock 'ping' command that always fails.
# Used to test ping connectivity checks that should fail.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR as "ping"
mock_ping_failure() {
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
# Mock ping that always fails
exit 1
EOF
	chmod +x "$mock_ping"
	echo "$mock_ping"
}

# Create mock ping command that succeeds for specific IPs
#
# Creates a mock 'ping' command that succeeds only for specified IP addresses.
# Used to test ping connectivity checks with selective success/failure.
#
# Arguments:
#   $1: Space-separated list of IPs that should succeed
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR as "ping"
#
# Note:
#   Ping is called with IP as last argument: ping [args] -c count -W timeout -q target_ip
#   The mock checks all arguments for target IP and exits 0 if found in success list, 1 otherwise
mock_ping_selective() {
	local success_ips="$1"
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<EOF
#!/bin/bash
# Mock ping that succeeds for specific IPs
# Check all arguments for target IP (ping is called with IP as last argument)
for arg in "\$@"; do
	for ip in $success_ips; do
		if [[ "\$arg" == "\$ip" ]]; then
			exit 0
		fi
	done
done
exit 1
EOF
	chmod +x "$mock_ping"
	echo "$mock_ping"
}

# Create mock nslookup command that fails
#
# Creates a mock 'nslookup' command that always fails.
# Used to prevent DNS fallback from succeeding in tests.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR as "nslookup"
mock_nslookup_fail() {
	local mock_nslookup="${TEST_DIR}/nslookup"
	cat >"$mock_nslookup" <<'EOF'
#!/bin/bash
exit 1
EOF
	chmod +x "$mock_nslookup"
	echo "$mock_nslookup"
}

# Create mock check_ipsec_phase2 command
#
# Creates a mock 'check_ipsec_phase2' command for testing SA re-establishment checks.
# Used in recovery tests to simulate Phase 2 SA verification.
#
# Arguments:
#   $1: Success flag ("0" for success, "1" for failure, default: "0")
#   $2: Optional flag file path - if provided, checks for file existence and exits 0 if found, 1 otherwise
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR as "check_ipsec_phase2"
#
# Example:
#   # Always succeeds
#   mock_check_ipsec_phase2 0
#   add_mock_to_path
#
#   # Always fails
#   mock_check_ipsec_phase2 1
#   add_mock_to_path
#
#   # File-based: succeeds if flag file exists
#   mock_check_ipsec_phase2 0 "${TEST_DIR}/MOCK_SAS_DELETED_FILE"
#   add_mock_to_path
mock_check_ipsec_phase2() {
	local success="${1:-0}"
	local flag_file="${2:-}"

	local mock_check_ipsec_phase2="${TEST_DIR}/check_ipsec_phase2"

	if [[ -n "$flag_file" ]]; then
		# File-based check: exit 0 if file exists, 1 otherwise
		cat >"$mock_check_ipsec_phase2" <<EOF
#!/bin/bash
# Return success if flag file exists (simulates SA re-establishment)
if [[ -f "$flag_file" ]]; then
    exit 0
fi
exit 1
EOF
	else
		# Simple success/failure
		cat >"$mock_check_ipsec_phase2" <<EOF
#!/bin/bash
# SA re-establishment check
exit $success
EOF
	fi

	chmod +x "$mock_check_ipsec_phase2"
	echo "$mock_check_ipsec_phase2"
}

# Create mock check_ipsec_phase2 command with state transitions
#
# Creates a mock 'check_ipsec_phase2' command that returns different exit codes
# based on call count, simulating state transitions (e.g., SA deletion and
# re-establishment).
#
# Arguments:
#   $1: Comma-separated sequence of exit codes (e.g., "0,1,0" or "1,0")
#       - First value: exit code for call 1
#       - Second value: exit code for call 2
#       - Third value: exit code for call 3+
#       - If only 2 values provided, second value is used for call 2+
#   $2: Optional call count file path (default: ${TEST_DIR}/phase2_call_count)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR as "check_ipsec_phase2"
#   Creates/initializes call count file
#
# Example:
#   # Pattern: success -> failure -> success (for SA deletion/re-establishment)
#   local phase2_call_file="${TEST_DIR}/phase2_calls"
#   mock_check_ipsec_phase2_state_transition "0,1,0" "$phase2_call_file"
#   add_mock_to_path
#
#   # Pattern: failure -> success (for timeout then recovery)
#   local check_state_file="${TEST_DIR}/check_state"
#   mock_check_ipsec_phase2_state_transition "1,0" "$check_state_file"
#   add_mock_to_path
mock_check_ipsec_phase2_state_transition() {
	local states="$1"
	local call_count_file="${2:-${TEST_DIR}/phase2_call_count}"

	if [[ -z "$states" ]]; then
		echo "Error: mock_check_ipsec_phase2_state_transition requires state sequence" >&2
		return 1
	fi

	# Initialize call count file
	echo "0" >"$call_count_file"

	local mock_check_ipsec_phase2="${TEST_DIR}/check_ipsec_phase2"

	# Parse state sequence into array
	IFS=',' read -r -a state_array <<<"$states"
	local state_count=${#state_array[@]}

	# Validate we have at least one state
	if [[ $state_count -eq 0 ]]; then
		echo "Error: mock_check_ipsec_phase2_state_transition requires at least one state" >&2
		return 1
	fi

	cat >"$mock_check_ipsec_phase2" <<EOF
#!/bin/bash
# Track call count for this function
phase2_calls=\$(cat "$call_count_file" 2>/dev/null || echo "0")
phase2_calls=\$((phase2_calls + 1))
echo "\$phase2_calls" > "$call_count_file"

# Return exit code based on call number
# States: $states
if [[ \$phase2_calls -eq 1 ]]; then
	# First call: use first state
	exit ${state_array[0]}
elif [[ \$phase2_calls -eq 2 ]] && [[ $state_count -ge 2 ]]; then
	# Second call: use second state
	exit ${state_array[1]}
elif [[ $state_count -ge 3 ]]; then
	# Third+ call: use third state (if provided)
	exit ${state_array[2]}
elif [[ $state_count -ge 2 ]]; then
	# Third+ call: use second state (if only 2 states provided)
	exit ${state_array[1]}
else
	# Third+ call: use first state (if only 1 state provided)
	exit ${state_array[0]}
fi
EOF

	chmod +x "$mock_check_ipsec_phase2"
	echo "$mock_check_ipsec_phase2"
}

# Create mock date command with controllable time
#
# Creates a mock 'date' command that returns a controllable timestamp.
# Used for time-based testing of cooldowns, rate limiting, and time-sensitive operations.
# Allows tests to simulate time passing by calling this function multiple times with
# different increment values.
#
# Arguments:
#   $1: Base timestamp in Unix seconds (default: current time via date +%s)
#   $2: Increment in seconds to add to base timestamp (default: 0)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR as "date"
#   Overwrites any existing date mock in TEST_DIR
#
# Examples:
#   # Set time to specific timestamp
#   mock_date 1609459200 0  # 2021-01-01 00:00:00 UTC
#   add_mock_to_path
#
#   # Advance time by 15 minutes (900 seconds)
#   mock_date 1609459200 900
#   add_mock_to_path
#
#   # Use current time as base, advance by 1 hour
#   local base=$(date +%s)
#   mock_date "$base" 3600
#   add_mock_to_path
#
# Note:
#   Supports common date formats:
#   - date +%s: Returns Unix timestamp
#   - date '+%Y-%m-%d %H:%M:%S': Returns formatted timestamp
#   - date '+%Y-%m-%d': Returns date only
#   Other formats fall back to real date command
mock_date() {
	local base_timestamp="${1:-$(date +%s 2>/dev/null || echo 0)}"
	local increment="${2:-0}"
	local current_time=$((base_timestamp + increment))

	local mock_date="${TEST_DIR}/date"
	cat >"$mock_date" <<EOF
#!/bin/bash
# Mock date command with controllable time
# Current mock time: $current_time (Unix timestamp)

if [[ "\$1" == "+%s" ]]; then
    # Unix timestamp format
    echo "$current_time"
    exit 0
elif [[ "\$1" == "-d" ]] && [[ "\$2" =~ ^\+([0-9]+)\ (minute|minutes)$ ]] && [[ "\$3" == "+%s" ]]; then
    # Handle date -d "+N minutes" +%s format (used by get_timestamp_plus_minutes)
    local minutes="\${BASH_REMATCH[1]}"
    local future_time=\$(( $current_time + minutes * 60 ))
    echo "\$future_time"
    exit 0
elif [[ "\$1" == "-d" ]] && [[ "\$2" =~ ^\"\+([0-9]+)\ (minute|minutes)\"$ ]] && [[ "\$3" == "+%s" ]]; then
    # Handle date -d "+N minutes" +%s format with quotes (used by get_timestamp_plus_minutes)
    local minutes="\${BASH_REMATCH[1]}"
    local future_time=\$(( $current_time + minutes * 60 ))
    echo "\$future_time"
    exit 0
elif [[ "\$1" == "+%Y-%m-%d %H:%M:%S" ]] || [[ "\$1" == '+%Y-%m-%d %H:%M:%S' ]]; then
    # Formatted timestamp format (used by logging)
    # Use Linux format
    date -d "@$current_time" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "1970-01-01 00:00:00"
    exit 0
elif [[ "\$1" == "+%Y-%m-%d" ]] || [[ "\$1" == '+%Y-%m-%d' ]]; then
    # Date only format
    date -d "@$current_time" +%Y-%m-%d 2>/dev/null || echo "1970-01-01"
    exit 0
fi

# For other date formats or arguments, fall back to real date command
# This handles edge cases and formats we don't explicitly support
exec /bin/date "\$@"
EOF
	chmod +x "$mock_date"
	echo "$mock_date"
}

# Set up controllable time for testing
#
# Convenience function that sets up mock_date with a fixed base timestamp
# and adds it to PATH. This reduces duplication in tests that need controllable time.
#
# Arguments:
#   $1: Base timestamp in Unix seconds (default: 1609459200 = 2021-01-01 00:00:00 UTC)
#   $2: Increment in seconds to add to base timestamp (default: 0)
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Creates mock date command in TEST_DIR
#   - Adds TEST_DIR to PATH
#   - Sets BASE_TIME variable to the actual timestamp being used
#
# Example:
#   setup_controllable_time
#   # Time is now 1609459200
#   local now=$BASE_TIME
#
#   setup_controllable_time 1609459200 900
#   # Time is now 1609460100 (15 minutes later)
#   local now=$BASE_TIME
setup_controllable_time() {
	local base_timestamp="${1:-1609459200}" # Default: 2021-01-01 00:00:00 UTC
	local increment="${2:-0}"
	local current_time=$((base_timestamp + increment))

	mock_date "$base_timestamp" "$increment"
	add_mock_to_path

	# Export BASE_TIME for use in tests
	export BASE_TIME=$current_time
}

# Create mock ip command that shows interfaces as UP
#
# Creates a mock 'ip' command that shows specified interfaces as UP with "state UP" in output.
# Handles both "ip link show" and "ip route show default" commands.
#
# Arguments:
#   $1: Comma-separated list of interfaces to show as UP (default: "br0,eth0")
#   $2: Whether to show default route (default: "1" for yes, "0" for no)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the path to the created mock script
#
# Side effects:
#   Creates mock script in TEST_DIR as "ip"
mock_ip_interfaces_up() {
	local interfaces="${1:-br0,eth0}"
	local show_default_route="${2:-1}"

	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "route" ]] && [[ "\$2" == "show" ]] && [[ "\$3" == "default" ]]; then
    if [[ "$show_default_route" == "1" ]]; then
        echo "default via ${TEST_PEER_IP} dev eth0"
        exit 0
    else
        exit 1
    fi
elif [[ "\$1" == "link" ]] && [[ "\$2" == "show" ]]; then
    # Parse interfaces
    IFS=',' read -r -a iface_array <<< "$interfaces"
    for iface in "\${iface_array[@]}"; do
        # Trim whitespace using parameter expansion
        iface="\${iface#"\${iface%%[![:space:]]*}"}"
        iface="\${iface%"\${iface##*[![:space:]]}"}"
        if [[ -z "\$iface" ]]; then
            continue
        fi
        # Check if this is the interface being queried
        if [[ -z "\${3:-}" ]] || [[ "\$3" == "\$iface" ]]; then
            echo "1: \$iface: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default"
            exit 0
        fi
    done
    # If specific interface queried but not found, exit 1
    if [[ -n "\${3:-}" ]]; then
        exit 1
    fi
    # If no specific interface, show all
    for iface in "\${iface_array[@]}"; do
        # Trim whitespace using parameter expansion
        iface="\${iface#"\${iface%%[![:space:]]*}"}"
        iface="\${iface%"\${iface##*[![:space:]]}"}"
        [[ -z "\$iface" ]] && continue
        echo "1: \$iface: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default"
    done
    exit 0
fi
# Handle other ip commands
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	echo "$mock_ip"
}

# Run test script with mocks in PATH
#
# Convenience function that ensures mocks are in PATH and runs the script.
# This standardizes the pattern of add_mock_to_path + run bash.
#
# Note: This function is provided for convenience but is not currently used
# in the test suite. Tests typically use add_mock_to_path + run bash directly
# for clarity. This function may be useful for future refactoring or for
# tests that need to ensure mocks are in PATH before running.
#
# Arguments:
#   $1: Script path to run
#   $2+: Additional arguments to pass to script
#
# Returns:
#   Exit code of the script
#
# Side effects:
#   Sets 'output' and 'status' variables (bats convention)
#   Ensures PATH includes TEST_DIR
#
# Example:
#   setup_mock_vpn_environment "192.168.1.1" 1000
#   run_with_mocks "$test_script" --fake
run_with_mocks() {
	local script="$1"
	shift
	local args=("$@")

	# Ensure mocks are in PATH
	add_mock_to_path

	# Run the script
	run bash "$script" "${args[@]}"
}

# ============================================================================
# Test Fixtures - Reusable Test Scenarios
# ============================================================================
#
# Test fixtures provide reusable setup functions for common test scenarios.
# They combine multiple setup steps into single function calls, reducing
# duplication and ensuring consistent test environments.
#
# Available fixtures (load in tests with: load fixtures/fixture_name):
#   - fixtures/vpn_active.bash: VPN is active and healthy
#   - fixtures/vpn_down.bash: VPN is down (no SA found)
#   - fixtures/vpn_failing.bash: VPN has recorded failures
#   - fixtures/vpn_cooldown.bash: VPN is in cooldown period
#   - fixtures/vpn_rekey.bash: VPN has undergone a rekey (SPI change)
#   - fixtures/vpn_multiple_peers.bash: Multiple VPN peers scenario
#   - fixtures/vpn_recovery_disabled.bash: VPN with recovery actions disabled
#   - fixtures/vpn_at_tier.bash: VPN at specific tier threshold
#   - fixtures/vpn_idle.bash: VPN idle tunnel scenario
#
# Example usage:
#   # Load test helper (includes fixtures documentation)
#   load test_helper
#
#   # Load specific fixture
#   load fixtures/vpn_active
#
#   @test "test with active VPN" {
#       setup_vpn_active_fixture "192.168.1.1"
#       # Test code here
#   }
#
# See tests/fixtures/ directory for fixture implementations and documentation.

# Source recovery module and all dependencies
#
# Sources all required library files for testing recovery functions.
# Sets up environment variables needed by recovery functions.
#
# Side effects:
#   - Sources constants.sh, common.sh, logging.sh, state.sh, detection.sh, recovery.sh
#   - Sets up LOG_FILE, LOGS_DIR, STATE_DIR if not already set
#
# Example:
#   source_recovery_module
#   run attempt_xfrm_recovery "192.168.1.1"
source_recovery_module() {
	# Set up required environment variables if not already set
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR
	LOGS_DIR="${LOGS_DIR:-${STATE_DIR}/logs}"
	export LOGS_DIR
	LOG_FILE="${LOG_FILE:-${LOGS_DIR}/vpn-monitor.log}"
	export LOG_FILE
	mkdir -p "$LOGS_DIR"

	# Source dependencies in order
	# shellcheck source=../lib/constants.sh
	source "${BATS_TEST_DIRNAME}/../lib/constants.sh" 2>/dev/null || true
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" 2>/dev/null || true
	# shellcheck source=../lib/recovery.sh
	source "${BATS_TEST_DIRNAME}/../lib/recovery.sh" 2>/dev/null || true
}

# Source a function from the appropriate module
#
# Helper function to extract and source individual functions from module files
# for unit testing. This allows testing functions in isolation without loading
# entire modules.
#
# Arguments:
#   $1: Function name to source
#
# Returns:
#   0: Function found and sourced successfully
#   1: Function not found in any module
#
# Side effects:
#   - Sources the function and its dependencies
#   - Sets up required environment variables
#   - Exports variables needed by functions
#
# Example:
#   source_function "get_formatted_timestamp"
#   run get_formatted_timestamp
#   assert_success
#
# Note:
#   Requires LIB_DIR and VPN_MONITOR_SCRIPT to be set
#   Functions are searched in order: common.sh, logging.sh, config.sh, state.sh,
#   detection.sh, recovery.sh, lockfile.sh, vpn-monitor.sh
source_function() {
	local func_name="$1"
	local func_def=""

	# Map functions to their module files
	# Try each module file in order until we find the function
	local modules=(
		"${LIB_DIR}/common.sh"
		"${LIB_DIR}/logging.sh"
		"${LIB_DIR}/config.sh"
		"${LIB_DIR}/state.sh"
		"${LIB_DIR}/detection.sh"
		"${LIB_DIR}/recovery.sh"
		"${LIB_DIR}/lockfile.sh"
		"${VPN_MONITOR_SCRIPT}"
	)

	# Try to find the function in each module
	for module in "${modules[@]}"; do
		if [[ -f "$module" ]]; then
			# Extract function using sed, matching from function start to closing brace
			func_def=$(sed -n "/^${func_name}(/,/^}/p" "$module" 2>/dev/null)
			if [[ -n "$func_def" ]]; then
				# Set minimal required variables for functions that need them
				# Export these so they're available in subshells created by 'run'
				SCRIPT_DIR="${SCRIPT_DIR:-${BATS_TEST_DIRNAME}/..}"
				export SCRIPT_DIR
				STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
				export STATE_DIR
				LOGS_DIR="${LOGS_DIR:-${STATE_DIR}/logs}"
				export LOGS_DIR
				LOCKFILE="${LOCKFILE:-${STATE_DIR}/vpn-monitor.lock}"
				export LOCKFILE
				LOG_FILE="${LOG_FILE:-${LOGS_DIR}/vpn-monitor.log}"
				export LOG_FILE
				RESTART_COUNT_FILE="${RESTART_COUNT_FILE:-${STATE_DIR}/restart_count}"
				export RESTART_COUNT_FILE
				COOLDOWN_UNTIL_FILE="${COOLDOWN_UNTIL_FILE:-${STATE_DIR}/cooldown_until}"
				export COOLDOWN_UNTIL_FILE
				CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/vpn-monitor.conf}"
				export CONFIG_FILE
				DEBUG="${DEBUG:-0}"
				export DEBUG

				# Source required dependencies first
				case "$module" in
				"${LIB_DIR}/common.sh")
					# common.sh is standalone, no dependencies
					# Source entire common.sh to make all functions available
					# shellcheck source=/dev/null
					source "${LIB_DIR}/common.sh" 2>/dev/null || true
					# Function already sourced, skip eval below
					return 0
					;;
				"${LIB_DIR}/config.sh")
					# config.sh needs logging.sh
					if [[ -f "${LIB_DIR}/logging.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/logging.sh" 2>/dev/null || true
					fi
					;;
				"${LIB_DIR}/state.sh")
					# state.sh needs logging.sh and common.sh
					# Source entire state.sh module since functions depend on each other
					if [[ -f "${LIB_DIR}/constants.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/constants.sh" 2>/dev/null || true
					fi
					if [[ -f "${LIB_DIR}/common.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/common.sh" 2>/dev/null || true
					fi
					if [[ -f "${LIB_DIR}/logging.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/logging.sh" 2>/dev/null || true
					fi
					# Source entire state.sh to make all functions available
					if [[ -f "${LIB_DIR}/state.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/state.sh" 2>/dev/null || true
						# Function already sourced, skip eval below
						return 0
					fi
					;;
				"${LIB_DIR}/detection.sh")
					# detection.sh needs state.sh and logging.sh
					# Also source detection.sh itself to make helper functions available
					if [[ -f "${LIB_DIR}/logging.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/logging.sh" 2>/dev/null || true
					fi
					if [[ -f "${LIB_DIR}/state.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/state.sh" 2>/dev/null || true
					fi
					# Source detection.sh to make all helper functions available
					# (e.g., validate_ipv4, validate_ipv6, etc. used by validate_ip_address)
					if [[ -f "${LIB_DIR}/detection.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/detection.sh" 2>/dev/null || true
						# Function already sourced, skip eval below
						return 0
					fi
					;;
				"${LIB_DIR}/recovery.sh")
					# recovery.sh needs detection.sh, state.sh, logging.sh
					if [[ -f "${LIB_DIR}/logging.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/logging.sh" 2>/dev/null || true
					fi
					if [[ -f "${LIB_DIR}/state.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/state.sh" 2>/dev/null || true
					fi
					if [[ -f "${LIB_DIR}/detection.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/detection.sh" 2>/dev/null || true
					fi
					;;
				"${LIB_DIR}/lockfile.sh")
					# lockfile.sh needs state.sh and logging.sh
					if [[ -f "${LIB_DIR}/logging.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/logging.sh" 2>/dev/null || true
					fi
					if [[ -f "${LIB_DIR}/state.sh" ]]; then
						# shellcheck source=/dev/null
						source "${LIB_DIR}/state.sh" 2>/dev/null || true
					fi
					;;
				esac

				# Source the function
				# shellcheck source=/dev/null
				eval "$func_def"
				return 0
			fi
		fi
	done

	# Function not found
	return 1
}

# Test peer state with empty location (backward compatibility pattern)
#
# Helper function that encapsulates the common test pattern of:
# - Calling set_peer_state with empty location (for backward compatibility)
# - Getting the file path using get_peer_state_file_path
# - Asserting file existence
#
# This reduces duplication across tests that need to verify peer state file creation.
#
# Arguments:
#   $1: Peer IP address
#   $2: State key (e.g., "failure_count", "last_bytes", "spi")
#   $3: Value to set
#   $4: Optional expected value to verify (if not provided, only existence is checked)
#
# Returns:
#   0: File exists (and optionally matches expected value)
#   1: File doesn't exist or value mismatch (fails test)
#
# Side effects:
#   - Calls set_peer_state with empty location
#   - Creates state file
#   - Asserts file existence
#   - Optionally verifies file content
#
# Example:
#   # Basic usage - just verify file exists
#   source_function "set_peer_state"
#   source_function "get_peer_state_file_path"
#   test_peer_state_with_empty_location "192.168.1.1" "failure_count" "5"
#
#   # With value verification
#   source_function "set_peer_state"
#   source_function "get_peer_state_file_path"
#   test_peer_state_with_empty_location "192.168.1.1" "failure_count" "5" "5"
#
# Note:
#   Requires set_peer_state and get_peer_state_file_path functions to be sourced
#   before calling this helper. Tests should source these functions first.
test_peer_state_with_empty_location() {
	local peer_ip="$1"
	local key="$2"
	local value="$3"
	local expected_value="${4:-}"

	# Set peer state with empty location (backward compatibility)
	run set_peer_state "" "$peer_ip" "$key" "$value"
	assert_success

	# Get file path using get_peer_state_file_path
	local state_file
	state_file=$(get_peer_state_file_path "" "$peer_ip" "$key")

	# Assert file exists
	assert_file_exist "$state_file"

	# If expected value provided, verify file content
	if [[ -n "$expected_value" ]]; then
		local file_content
		file_content=$(cat "$state_file")
		assert_equal "$file_content" "$expected_value"
	fi
}

# Save permissions for a file or directory
#
# Helper function that saves the original permissions of a file or directory
# for later restoration. Automatically detects whether the path is a file or
# directory and uses appropriate default permissions if stat fails.
#
# This function is part of the permission restoration pattern used in tests
# that need to make files/directories unwritable temporarily.
#
# Arguments:
#   $1: Path to file or directory
#   $2: Optional default permissions to use if stat fails (defaults to 644 for files, 755 for directories)
#
# Returns:
#   Outputs the original permissions (octal format, e.g., "644", "755")
#   Returns 0 on success, 1 if path doesn't exist
#
# Side effects:
#   None
#
# Example:
#   local original_perms
#   original_perms=$(save_permissions_for_restore "$state_file")
#   # or with explicit default:
#   original_perms=$(save_permissions_for_restore "$state_dir" "755")
#
# Note:
#   This function is designed to work with restore_permissions_after_test()
#   to implement the common test pattern of temporarily making files/directories
#   unwritable for testing error handling.
save_permissions_for_restore() {
	local path="$1"
	local default_perms="${2:-}"

	# Auto-detect default if not provided
	if [[ -z "$default_perms" ]]; then
		if [[ -d "$path" ]]; then
			default_perms="755"
		else
			default_perms="644"
		fi
	fi

	# Save original permissions with fallback to default
	stat -c "%a" "$path" 2>/dev/null || echo "$default_perms"
}

# Restore permissions for a file or directory
#
# Helper function that restores the original permissions of a file or directory
# that was previously saved using save_permissions_for_restore().
#
# This function is part of the permission restoration pattern used in tests
# that need to make files/directories unwritable temporarily.
#
# Arguments:
#   $1: Path to file or directory
#   $2: Original permissions (octal format, e.g., "644", "755")
#
# Returns:
#   0 on success, 1 on failure (but errors are suppressed with || true pattern)
#
# Side effects:
#   Restores permissions on the specified path
#
# Example:
#   local original_perms
#   original_perms=$(save_permissions_for_restore "$state_file")
#   chmod 000 "$state_file" 2>/dev/null || true
#   # ... run test ...
#   restore_permissions_after_test "$state_file" "$original_perms"
#
# Note:
#   This function suppresses errors (using || true) to match the existing
#   test pattern where permission restoration should not fail tests even if
#   the restore operation fails.
restore_permissions_after_test() {
	local path="$1"
	local original_perms="$2"

	chmod "$original_perms" "$path" 2>/dev/null || true
}

# Get state file path with common defaults
#
# Helper function that wraps get_peer_state_file_path with sensible defaults
# to reduce repetition in tests. Uses TEST_PEER_IP as default peer IP and
# empty string for location (backward compatibility).
#
# Arguments:
#   $1: Optional location name (defaults to "" for backward compatibility)
#   $2: Optional peer IP address (defaults to TEST_PEER_IP)
#   $3: Optional state key (defaults to "failure_count")
#
# Returns:
#   Outputs the state file path
#   Returns 0 on success, 1 on failure
#
# Side effects:
#   Sources get_peer_state_file_path function if not available
#
# Example:
#   source_function "get_peer_state_file_path"
#   local failure_counter
#   failure_counter=$(get_state_file_path)
#   # or with custom values:
#   failure_counter=$(get_state_file_path "NYC" "${TEST_PEER_IP}" "last_bytes")
#
# Note:
#   Requires get_peer_state_file_path function to be available.
#   Automatically sources it if not already loaded.
get_state_file_path() {
	local location="${1:-}"
	local peer_ip="${2:-${TEST_PEER_IP}}"
	local key="${3:-failure_count}"

	# Ensure get_peer_state_file_path is available
	if ! command -v get_peer_state_file_path >/dev/null 2>&1; then
		source_function "get_peer_state_file_path" || return 1
	fi

	get_peer_state_file_path "$location" "$peer_ip" "$key"
}

# Create a corrupted state file
#
# Helper function that creates a state file with an invalid value to test
# corruption handling. Reduces repetition of the common pattern of creating
# corrupted state files in tests.
#
# Arguments:
#   $1: Optional location name (defaults to "" for backward compatibility)
#   $2: Optional peer IP address (defaults to TEST_PEER_IP)
#   $3: Optional state key (defaults to "failure_count")
#   $4: Optional invalid value to write (defaults to "invalid-value")
#
# Returns:
#   Outputs the state file path
#   Returns 0 on success, 1 on failure
#
# Side effects:
#   Creates or overwrites the state file with invalid content
#   Sources get_peer_state_file_path function if not available
#
# Example:
#   source_function "get_peer_state_file_path"
#   local failure_counter
#   failure_counter=$(create_corrupted_state_file)
#   # or with custom values:
#   local bytes_file
#   bytes_file=$(create_corrupted_state_file "NYC" "${TEST_PEER_IP}" "last_bytes" "not-a-number")
#
# Note:
#   Requires get_peer_state_file_path function to be available.
#   Automatically sources it if not already loaded.
create_corrupted_state_file() {
	local location="${1:-}"
	local peer_ip="${2:-${TEST_PEER_IP}}"
	local key="${3:-failure_count}"
	local invalid_value="${4:-invalid-value}"

	# Get the state file path
	local state_file
	state_file=$(get_state_file_path "$location" "$peer_ip" "$key") || return 1

	# Create corrupted file
	echo "$invalid_value" >"$state_file"

	# Return the path for use in tests
	echo "$state_file"
}

# Setup a read-only state file with automatic cleanup
#
# Helper function that creates a state file, sets it to read-only, and sets up
# a trap to restore permissions on EXIT. Reduces repetition of the common pattern
# of testing read-only state file handling.
#
# Arguments:
#   $1: Optional location name (defaults to "" for backward compatibility)
#   $2: Optional peer IP address (defaults to TEST_PEER_IP)
#   $3: Optional state key (defaults to "failure_count")
#   $4: Optional initial value to write (defaults to "3")
#   $5: Optional permissions to set (defaults to "444" for read-only)
#
# Returns:
#   Outputs the state file path
#   Returns 0 on success, 1 on failure
#
# Side effects:
#   Creates the state file with initial value
#   Sets file permissions to read-only (or specified permissions)
#   Sets up EXIT trap to restore original permissions
#   Sources get_peer_state_file_path function if not available
#
# Example:
#   source_function "get_peer_state_file_path"
#   local failure_counter
#   failure_counter=$(setup_readonly_state_file)
#   # File is now read-only and will be restored on test exit
#   # or with custom values:
#   local bytes_file
#   bytes_file=$(setup_readonly_state_file "NYC" "${TEST_PEER_IP}" "last_bytes" "1000" "000")
#
# Note:
#   Requires get_peer_state_file_path function to be available.
#   Automatically sources it if not already loaded.
#   The trap is set up automatically and will restore permissions even if test fails.
setup_readonly_state_file() {
	local location="${1:-}"
	local peer_ip="${2:-${TEST_PEER_IP}}"
	local key="${3:-failure_count}"
	local initial_value="${4:-3}"
	local readonly_perms="${5:-444}"

	# Get the state file path
	local state_file
	state_file=$(get_state_file_path "$location" "$peer_ip" "$key") || return 1

	# Create file with initial value
	echo "$initial_value" >"$state_file"

	# Save original permissions
	local original_perms
	original_perms=$(save_permissions_for_restore "$state_file")

	# Set read-only permissions
	chmod "$readonly_perms" "$state_file"

	# Set up trap to restore permissions on EXIT
	# Use actual path value, not variable, since trap executes after function returns
	trap "chmod $original_perms \"$state_file\" 2>/dev/null || true" EXIT

	# Return the path for use in tests
	echo "$state_file"
}
