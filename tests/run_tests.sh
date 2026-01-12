#!/bin/bash
#
# Test runner for UDM VPN Monitor tests
# Runs all tests using bats (Bash Automated Testing System)
# Supports test coverage reporting using kcov
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Signal handling for clean interruption
# Track if we've been interrupted to prevent cascading signals
INTERRUPTED=0

# Cleanup function for signal handlers
#
# Handles SIGINT (Ctrl+C) and SIGTERM signals to gracefully terminate test execution.
# Kills all child processes in the process group and exits with code 130 (standard for SIGINT).
#
# Arguments:
#   None
#
# Returns:
#   Exits with code 130 (standard for SIGINT)
#
cleanup_on_signal() {
	if [[ $INTERRUPTED -eq 1 ]]; then
		# Already handling interruption, force exit
		exit 130
	fi
	INTERRUPTED=1

	echo "" >&2
	echo -e "${YELLOW}Interrupted by user (Ctrl+C)${NC}" >&2
	echo -e "${YELLOW}Cleaning up and exiting...${NC}" >&2

	# Kill any child processes in the process group
	# This ensures timeout, stdbuf, bats, kcov, etc. are all terminated
	# Use process group kill to catch all descendants
	# Send SIGTERM first to allow graceful shutdown
	kill -TERM -"$$" 2>/dev/null || true

	# Exit with code 130 (standard for SIGINT)
	# Don't force kill here - let the shell handle cleanup naturally
	exit 130
}

# Set up signal handlers for SIGINT (Ctrl+C) and SIGTERM
trap cleanup_on_signal INT TERM

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Coverage settings
COVERAGE_DIR="${PROJECT_ROOT}/coverage"
COVERAGE_ENABLED=0
COVERAGE_TOOL=""

# Test filtering settings
# Slow tests are excluded by default (integration and high-risk tests)
# Set RUN_SLOW_TESTS=1 or use --slow flag to include them
RUN_SLOW_TESTS="${RUN_SLOW_TESTS:-0}"

# Fast-fail settings
# Continue running all tests by default (fast-fail disabled)
# Set FAST_FAIL=1 to stop on first failure, or use --all flag to explicitly disable fast-fail
FAST_FAIL="${FAST_FAIL:-0}"

# Rerun failed tests only
# Set RERUN_FAILED=1 or use --failed flag to rerun only failed tests from last run
RERUN_FAILED="${RERUN_FAILED:-0}"

# Parallel execution settings
# Number of parallel jobs (0 = disabled, auto = detect CPU cores, or specific number)
# Default: auto (run in batch/parallel by default if parallel tool is available)
# Set PARALLEL_JOBS=0 to disable, auto to auto-detect, or a number like 4, 8, etc.
PARALLEL_JOBS="${PARALLEL_JOBS:-auto}"
PARALLEL_TOOL=""

# Test tag filtering settings
# Filter tests by tags (e.g., "category:unit", "priority:high", "category:integration,priority:high")
# Set FILTER_TAGS to filter tests by tags using bats --filter-tags
FILTER_TAGS="${FILTER_TAGS:-}"

# Test timeout settings
# Timeout for individual tests in seconds (default: 120 seconds = 2 minutes)
# Tests that exceed this timeout will be skipped
TEST_TIMEOUT="${TEST_TIMEOUT:-120}"

# Individual test mode
# Run each test case individually with detailed per-test output
# Set INDIVIDUAL_MODE=1 or use --individual flag to enable
INDIVIDUAL_MODE="${INDIVIDUAL_MODE:-0}"

# Resume from checkpoint
# Resume tests from last checkpoint (only works in individual mode)
# Set RESUME_MODE=1 or use --resume flag to enable
RESUME_MODE="${RESUME_MODE:-0}"

# Show bats installation instructions
#
# Displays installation instructions for bats (Bash Automated Testing System).
# Shows platform-specific installation commands for macOS, Linux, Ubuntu/Debian, and Fedora/RHEL.
#
# Arguments:
#   None
#
# Returns:
#   None (outputs to stderr)
#
show_bats_instructions() {
	echo "Install bats using one of the following methods:" >&2
	echo "" >&2
	echo "  macOS (Homebrew):" >&2
	echo "    brew install bats-core" >&2
	echo "" >&2
	echo "  Linux (from source):" >&2
	echo "    git clone https://github.com/bats-core/bats-core.git" >&2
	echo "    cd bats-core" >&2
	echo "    sudo ./install.sh /usr/local" >&2
	echo "" >&2
	echo "  Ubuntu/Debian:" >&2
	echo "    sudo apt-get update && sudo apt-get install -y bats" >&2
	echo "" >&2
	echo "  Fedora/RHEL:" >&2
	echo "    sudo dnf install -y bats" >&2
	echo "" >&2
}

# Check if bats is installed
#
# Verifies that bats (Bash Automated Testing System) is installed and available.
# Checks bats version and warns if outdated. Shows installation instructions if not found.
#
# Arguments:
#   None
#
# Returns:
#   0: bats is installed and available
#   1: bats is not installed (exits script)
#
check_bats() {
	if ! command -v bats >/dev/null 2>&1; then
		echo -e "${RED}Error: bats is not installed${NC}" >&2
		echo "" >&2
		echo "bats (Bash Automated Testing System) is required to run tests." >&2
		echo "" >&2

		# Prompt user to see instructions (interactive mode only)
		if [[ -t 0 ]] && [[ -t 1 ]]; then
			echo -e "${YELLOW}Would you like to see installation instructions? (yes/no) [yes]:${NC} "
			read -r response
			response="${response:-yes}"

			if [[ "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
				echo "" >&2
				show_bats_instructions
			fi
		else
			# Non-interactive mode - always show instructions
			show_bats_instructions
		fi

		exit 1
	fi

	# Check bats version (should be 1.x or higher)
	local bats_version
	bats_version=$(bats --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "0.0")
	local major_version
	major_version=$(echo "$bats_version" | cut -d. -f1)

	if [[ $major_version -lt 1 ]]; then
		echo -e "${YELLOW}Warning: bats version $bats_version may be outdated${NC}" >&2
		echo "Consider upgrading to bats-core 1.x or higher" >&2
	fi
}

# Check for kcov (optional, for coverage reporting)
#
# Checks if kcov is installed and available for test coverage reporting.
# Sets COVERAGE_TOOL global variable if kcov is found.
#
# Arguments:
#   None
#
# Returns:
#   0: kcov is installed
#   1: kcov is not installed
#
check_kcov() {
	if command -v kcov >/dev/null 2>&1; then
		COVERAGE_TOOL="kcov"
		return 0
	fi

	return 1
}

# Detect number of CPU cores
#
# Detects the number of CPU cores available on the system.
# Uses nproc on Linux, falls back to default of 4 if nproc is unavailable.
#
# Arguments:
#   None
#
# Returns:
#   Outputs number of CPU cores to stdout (default: 4)
#
detect_cpu_cores() {
	# Use nproc (Linux)
	if command -v nproc >/dev/null 2>&1; then
		nproc 2>/dev/null || echo "4"
	# Fallback to default
	else
		echo "4"
	fi
}

# Check for parallel execution tools (GNU parallel or rush)
#
# Checks if GNU parallel or rush is available for parallel test execution.
# Sets PARALLEL_TOOL global variable if a tool is found.
#
# Arguments:
#   None
#
# Returns:
#   0: Parallel tool is available
#   1: No parallel tool is available
#
check_parallel_tool() {
	if command -v parallel >/dev/null 2>&1; then
		# Check if it's GNU parallel (not the moreutils version)
		if parallel --version 2>&1 | grep -q "GNU parallel"; then
			PARALLEL_TOOL="parallel"
			return 0
		fi
	fi

	if command -v rush >/dev/null 2>&1; then
		PARALLEL_TOOL="rush"
		return 0
	fi

	return 1
}

# Show parallel tool installation instructions
#
# Displays installation instructions for GNU parallel.
# Shows platform-specific installation commands for macOS, Ubuntu/Debian, Fedora/RHEL, and from source.
#
# Arguments:
#   None
#
# Returns:
#   None (outputs to stderr)
#
show_parallel_instructions() {
	echo "Parallel test execution requires GNU parallel or rush to be installed." >&2
	echo "" >&2
	echo "Install GNU parallel using one of the following methods:" >&2
	echo "" >&2
	echo "  macOS (Homebrew):" >&2
	echo "    brew install parallel" >&2
	echo "" >&2
	echo "  Ubuntu/Debian:" >&2
	echo "    sudo apt-get update && sudo apt-get install -y parallel" >&2
	echo "" >&2
	echo "  Fedora/RHEL:" >&2
	echo "    sudo dnf install -y parallel" >&2
	echo "" >&2
	echo "  From source:" >&2
	echo "    wget http://ftp.gnu.org/gnu/parallel/parallel-latest.tar.bz2" >&2
	echo "    tar -xjf parallel-latest.tar.bz2" >&2
	echo "    cd parallel-* && ./configure && make && sudo make install" >&2
	echo "" >&2
	echo "Note: Parallel execution is optional. Tests will run sequentially if" >&2
	echo "no parallel tool is available." >&2
	echo "" >&2
}

# Determine number of parallel jobs
#
# Determines the number of parallel jobs to use based on PARALLEL_JOBS setting.
# Supports "auto" (auto-detect CPU cores), "0" (disabled), or a specific number.
#
# Arguments:
#   None
#
# Returns:
#   Outputs number of parallel jobs to stdout (0, auto-detected number, or specified number)
#
get_parallel_jobs() {
	local jobs="$PARALLEL_JOBS"

	# If parallel execution is disabled
	if [[ "$jobs" == "0" ]]; then
		echo "0"
		return
	fi

	# Auto-detect CPU cores
	if [[ "$jobs" == "auto" ]]; then
		detect_cpu_cores
		return
	fi

	# Validate that jobs is a positive integer if it's not "auto" or "0"
	if ! [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then
		echo -e "${YELLOW}Warning: Invalid PARALLEL_JOBS value '$jobs'. Using auto-detection.${NC}" >&2
		detect_cpu_cores
		return
	fi

	# Use specified number
	echo "$jobs"
}

# Show kcov installation instructions
#
# Displays installation instructions for kcov (code coverage tool).
# Shows platform-specific installation commands for macOS, Ubuntu/Debian, Fedora/RHEL, and from source.
#
# Arguments:
#   None
#
# Returns:
#   None (outputs to stderr)
#
show_kcov_instructions() {
	echo "Install kcov using one of the following methods:" >&2
	echo "" >&2
	echo "  macOS (Homebrew):" >&2
	echo "    brew install kcov" >&2
	echo "" >&2
	echo "  Ubuntu/Debian:" >&2
	echo "    sudo apt-get update && sudo apt-get install -y kcov" >&2
	echo "" >&2
	echo "  Fedora/RHEL:" >&2
	echo "    sudo dnf install -y kcov" >&2
	echo "" >&2
	echo "  From source:" >&2
	echo "    git clone https://github.com/SimonKagstrom/kcov.git" >&2
	echo "    cd kcov" >&2
	echo "    mkdir build && cd build" >&2
	echo "    cmake .." >&2
	echo "    make" >&2
	echo "    sudo make install" >&2
	echo "" >&2
}

# Check coverage tools and enable if available
#
# Checks if coverage tools (kcov) are available when coverage is enabled.
# Shows installation instructions if kcov is not found and coverage is requested.
#
# Arguments:
#   None
#
# Returns:
#   0: Coverage tool is available or coverage is disabled
#   1: Coverage is enabled but tool is not available
#
check_coverage_tools() {
	if [[ "$COVERAGE_ENABLED" -eq 1 ]]; then
		if check_kcov; then
			echo -e "${GREEN}Coverage tool found: kcov${NC}"
			return 0
		else
			echo -e "${YELLOW}Warning: kcov not found. Coverage reporting disabled.${NC}" >&2
			echo "" >&2
			echo "Coverage reporting requires kcov to be installed." >&2
			echo "" >&2

			if [[ -t 0 ]] && [[ -t 1 ]]; then
				echo -e "${YELLOW}Would you like to see installation instructions? (yes/no) [no]:${NC} "
				read -r response
				response="${response:-no}"

				if [[ "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
					echo "" >&2
					show_kcov_instructions
				fi
			else
				show_kcov_instructions
			fi

			COVERAGE_ENABLED=0
			return 1
		fi
	fi

	return 0
}

# Check for bats-support and bats-assert (optional but recommended)
#
# Checks if optional bats helper libraries (bats-support, bats-assert, bats-file) are installed.
# Prompts user to install if missing and in interactive mode.
#
# Arguments:
#   None
#
# Returns:
#   None (warnings logged but function always succeeds)
#
check_bats_helpers() {
	local helpers_missing=0
	local missing_helpers=()

	if [[ ! -d "${SCRIPT_DIR}/bats-support" ]]; then
		echo -e "${YELLOW}Warning: bats-support not found${NC}" >&2
		helpers_missing=1
		missing_helpers+=("bats-support")
	fi

	if [[ ! -d "${SCRIPT_DIR}/bats-assert" ]]; then
		echo -e "${YELLOW}Warning: bats-assert not found${NC}" >&2
		helpers_missing=1
		missing_helpers+=("bats-assert")
	fi

	if [[ ! -d "${SCRIPT_DIR}/bats-file" ]]; then
		echo -e "${YELLOW}Warning: bats-file not found${NC}" >&2
		helpers_missing=1
		missing_helpers+=("bats-file")
	fi

	if [[ $helpers_missing -eq 1 ]]; then
		echo "" >&2
		echo "Optional bats helper libraries not found: ${missing_helpers[*]}" >&2
		echo "Tests will work but some assertions may not be available." >&2
		echo "" >&2

		# Prompt user to install
		if [[ -t 0 ]] && [[ -t 1 ]]; then
			# Interactive mode
			echo -e "${YELLOW}Would you like to install the helper libraries? (yes/no) [yes]:${NC} "
			read -r response
			response="${response:-yes}"

			if [[ "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
				echo "" >&2
				echo -e "${GREEN}Installing bats helper libraries...${NC}" >&2
				echo "" >&2

				if [[ -f "${SCRIPT_DIR}/install_bats_helpers.sh" ]]; then
					if bash "${SCRIPT_DIR}/install_bats_helpers.sh"; then
						echo "" >&2
						echo -e "${GREEN}Helper libraries installed successfully!${NC}" >&2
						echo "" >&2
					else
						echo -e "${RED}Failed to install helper libraries${NC}" >&2
						echo "You can install them manually later using:" >&2
						echo "  ${SCRIPT_DIR}/install_bats_helpers.sh" >&2
						echo "" >&2
					fi
				else
					echo -e "${RED}Install script not found: ${SCRIPT_DIR}/install_bats_helpers.sh${NC}" >&2
					echo "Please install manually or create the install script." >&2
					echo "" >&2
				fi
			else
				echo "" >&2
				echo "Skipping helper library installation." >&2
				echo "To install later, run: ${SCRIPT_DIR}/install_bats_helpers.sh" >&2
				echo "" >&2
			fi
		else
			# Non-interactive mode - just show instructions
			echo "To install helpers:" >&2
			echo "  ${SCRIPT_DIR}/install_bats_helpers.sh" >&2
			echo "" >&2
		fi
	fi
}

# Filter test files based on slow test setting
#
# Filters test files based on RUN_SLOW_TESTS setting.
# Slow tests (integration and high-risk tests) are excluded unless RUN_SLOW_TESTS=1.
# Outputs filtered file list to stdout (one per line).
#
# Arguments:
#   None
#
# Returns:
#   Outputs filtered test file paths to stdout (one per line)
#
filter_test_files() {
	local test_files=("${SCRIPT_DIR}"/test_*.sh)

	for test_file in "${test_files[@]}"; do
		local filename
		filename=$(basename "$test_file")

		# Check if this is a slow test file
		# Slow tests are: test_integration.sh and high-risk test files (test_config.sh, test_lockfile.sh, etc.)
		# These were split from test_high_risk.sh for better organization
		if [[ "$filename" == "test_integration.sh" ]] ||
			[[ "$filename" == "test_config.sh" ]] ||
			[[ "$filename" == "test_lockfile.sh" ]] ||
			[[ "$filename" == "test_detection.sh" ]] ||
			[[ "$filename" == "test_recovery.sh" ]] ||
			[[ "$filename" == "test_state.sh" ]] ||
			[[ "$filename" == "test_logging.sh" ]] ||
			[[ "$filename" == "test_connection.sh" ]] ||
			[[ "$filename" == "test_errors.sh" ]] ||
			[[ "$filename" == "test_main.sh" ]]; then
			# Include slow tests only if RUN_SLOW_TESTS is enabled
			if [[ "$RUN_SLOW_TESTS" -eq 1 ]]; then
				echo "$test_file"
				echo -e "${BLUE}Including slow test: $filename${NC}" >&2
			else
				echo -e "${YELLOW}Skipping slow test: $filename (use --slow to include)${NC}" >&2
			fi
		else
			# Always include non-slow tests
			echo "$test_file"
		fi
	done
}

# Extract test names from a test file
#
# Extracts test names from a bats test file by parsing @test declarations.
# Handles both single and double quotes in test names.
# Outputs test names (one per line) matching @test declarations.
#
# Arguments:
#   $1: Path to test file
#
# Returns:
#   Outputs test names to stdout (one per line)
#
extract_test_names() {
	local test_file="$1"
	# Extract test names from @test declarations
	# Pattern: @test "test name" { or @test 'test name' {
	# Handle both single and double quotes, and multi-line declarations
	grep -E "^@test\s+[\"']" "$test_file" 2>/dev/null | sed -E "s/^@test\s+[\"']([^\"']+)[\"'].*/\1/" || true
}

# Escape special regex characters in test name for bats filter
#
# Escapes special regex characters in test names for use with bats --filter flag.
# Escapes: . [ ] { } ( ) + * ? ^ $ | \
#
# Arguments:
#   $1: Test name to escape
#
# Returns:
#   Outputs escaped test name to stdout
#
escape_test_name_for_filter() {
	local test_name="$1"
	# Escape special regex characters: . [ ] { } ( ) + * ? ^ $ | \
	# Using sed is appropriate here as we need proper regex escaping
	# shellcheck disable=SC2001
	echo "$test_name" | sed 's/[.[{}()*+?^$|\\]/\\&/g'
}

# Get checkpoint file path
#
# Returns the path to the checkpoint file used for resuming test execution.
# Creates logs directory if it doesn't exist.
#
# Arguments:
#   None
#
# Returns:
#   Outputs checkpoint file path to stdout
#
get_checkpoint_file() {
	local logs_dir="${PROJECT_ROOT}/logs"
	mkdir -p "$logs_dir"
	echo "${logs_dir}/test_checkpoint.txt"
}

# Save test result to checkpoint file
#
# Saves test result to checkpoint file for resume functionality.
# Format: test_id|status|timestamp
#
# Arguments:
#   $1: Test ID (format: filename::test_name)
#   $2: Test status (PASSED, FAILED, or TIMEOUT)
#
# Returns:
#   None
#
save_checkpoint() {
	local test_id="$1"
	local status="$2" # PASSED, FAILED, or TIMEOUT
	local checkpoint_file
	checkpoint_file=$(get_checkpoint_file)
	# Append to checkpoint file
	echo "${test_id}|${status}|$(date +%s)" >>"$checkpoint_file"
}

# Load checkpoint and return passed test IDs
#
# Loads checkpoint file and populates CHECKPOINT_PASSED associative array with passed test IDs.
# Returns associative array of passed test IDs (via global variable CHECKPOINT_PASSED).
#
# Arguments:
#   None
#
# Returns:
#   None (populates global CHECKPOINT_PASSED array)
#
load_checkpoint() {
	local checkpoint_file
	checkpoint_file=$(get_checkpoint_file)
	declare -gA CHECKPOINT_PASSED

	if [[ ! -f "$checkpoint_file" ]]; then
		return 0
	fi

	# Read checkpoint file and store passed tests
	while IFS='|' read -r test_id status _timestamp; do
		if [[ "$status" == "PASSED" ]]; then
			CHECKPOINT_PASSED["$test_id"]=1
		fi
	done <"$checkpoint_file"
}

# Check if test should be skipped (already passed in checkpoint)
#
# Checks if a test should be skipped because it already passed in the checkpoint.
#
# Arguments:
#   $1: Test ID (format: filename::test_name)
#
# Returns:
#   0: Test should be skipped (already passed)
#   1: Test should not be skipped
#
should_skip_test() {
	local test_id="$1"
	[[ -n "${CHECKPOINT_PASSED[$test_id]:-}" ]]
}

# Clear checkpoint file
#
# Removes the checkpoint file to start a fresh test run.
#
# Arguments:
#   None
#
# Returns:
#   None
#
clear_checkpoint() {
	local checkpoint_file
	checkpoint_file=$(get_checkpoint_file)
	rm -f "$checkpoint_file"
}

# Get kcov arguments for coverage reporting
#
# Builds and returns array of kcov arguments for coverage reporting.
# Returns array of kcov arguments via global variable KCOV_ARGS.
#
# Arguments:
#   None
#
# Returns:
#   None (populates global KCOV_ARGS array)
#
get_kcov_args() {
	KCOV_ARGS=(
		"--include-path=${PROJECT_ROOT}"
		"--exclude-path=${PROJECT_ROOT}/tests"
		"--exclude-path=${PROJECT_ROOT}/coverage"
		"--exclude-path=${PROJECT_ROOT}/.git"
		"--exclude-path=${PROJECT_ROOT}/logs"
		"--exclude-path=${PROJECT_ROOT}/state"
		"--exclude-path=${PROJECT_ROOT}/reports"
		"--exclude-path=${PROJECT_ROOT}/analyze"
		"--exclude-path=/usr"
		"--exclude-path=/tmp"
		"--exclude-path=/var"
		"--exclude-path=/home/runner"
	)
}

# Run a single test case with timeout
#
# Runs an individual test by name with timeout, skipping if it exceeds the limit.
# Supports coverage reporting when enabled.
#
# Arguments:
#   $1: Test file path
#   $2: Test name
#   $3: Timeout in seconds
#   $4: Use coverage flag (0 or 1, optional, default: 0)
#   $5: Coverage directory (optional, required if coverage enabled)
#   ${@:6}: kcov arguments (optional, required if coverage enabled)
#
# Returns:
#   0: Test passed
#   1: Test failed
#   2: Test timed out
#
run_single_test_with_timeout() {
	local test_file="$1"
	local test_name="$2"
	local timeout_seconds="$3"
	local use_coverage="${4:-0}"
	local coverage_dir="${5:-}"
	local kcov_args=("${@:6}")
	# Escape the test name for regex matching
	local escaped_name
	escaped_name=$(escape_test_name_for_filter "$test_name")
	local bats_args=("--timing" "$test_file" "-f" "^${escaped_name}$")

	# Add filter for failed tests if rerun-failed is enabled
	if [[ "$RERUN_FAILED" -eq 1 ]]; then
		bats_args+=(--filter-status "failed")
	fi

	# Add tag filter if specified
	if [[ -n "$FILTER_TAGS" ]]; then
		bats_args+=(--filter-tags "$FILTER_TAGS")
	fi

	# Check if timeout command is available
	if ! command -v timeout >/dev/null 2>&1; then
		# No timeout - run without timeout protection
		if [[ $use_coverage -eq 1 ]] && [[ -n "$coverage_dir" ]]; then
			# Run with coverage
			if command -v stdbuf >/dev/null 2>&1; then
				if stdbuf -oL -eL -i0 kcov "${kcov_args[@]}" "$coverage_dir" bats "${bats_args[@]}"; then
					return 0
				else
					return 1
				fi
			else
				if kcov "${kcov_args[@]}" "$coverage_dir" bats "${bats_args[@]}"; then
					return 0
				else
					return 1
				fi
			fi
		else
			# Run without coverage
			if command -v stdbuf >/dev/null 2>&1; then
				if stdbuf -oL -eL -i0 bats "${bats_args[@]}"; then
					return 0
				else
					return 1
				fi
			else
				if bats "${bats_args[@]}"; then
					return 0
				else
					return 1
				fi
			fi
		fi
	fi

	# Run test with timeout
	local exit_code=0
	if [[ $use_coverage -eq 1 ]] && [[ -n "$coverage_dir" ]]; then
		# Run with coverage and timeout
		# Note: Use timeout without --preserve-status for kcov to ensure it exits cleanly
		# kcov can hang if the test process exits unexpectedly, so we need timeout to kill it
		if command -v stdbuf >/dev/null 2>&1; then
			timeout "$timeout_seconds" stdbuf -oL -eL -i0 kcov "${kcov_args[@]}" "$coverage_dir" bats "${bats_args[@]}" 2>&1 || exit_code=$?
		else
			timeout "$timeout_seconds" kcov "${kcov_args[@]}" "$coverage_dir" bats "${bats_args[@]}" 2>&1 || exit_code=$?
		fi
	else
		# Run without coverage, with timeout
		# Use --preserve-status for bats-only runs to preserve test exit codes
		if command -v stdbuf >/dev/null 2>&1; then
			# Use stdbuf for unbuffered output streaming
			timeout --preserve-status "$timeout_seconds" stdbuf -oL -eL -i0 bats "${bats_args[@]}" 2>&1 || exit_code=$?
		else
			# Fallback without stdbuf
			timeout --preserve-status "$timeout_seconds" bats "${bats_args[@]}" 2>&1 || exit_code=$?
		fi
	fi

	if [[ $exit_code -eq 0 ]]; then
		return 0
	elif [[ $exit_code -eq 124 ]]; then
		# Test timed out - bats will show it as skipped
		echo -e "${YELLOW}# skip Test '${test_name}' timed out after ${timeout_seconds}s${NC}" >&2
		return 2
	elif [[ $exit_code -eq 143 ]]; then
		# SIGTERM (timeout killed the process) - treat as timeout
		# This can happen with kcov when timeout kills it
		echo -e "${YELLOW}# skip Test '${test_name}' timed out after ${timeout_seconds}s${NC}" >&2
		return 2
	else
		# Other exit codes are test failures
		# For kcov runs, exit code 1 from bats is preserved, but kcov may exit with different codes
		# If exit code is 1, it's a test failure; otherwise it might be kcov cleanup
		if [[ $exit_code -eq 1 ]]; then
			return 1
		else
			# Non-zero exit that's not timeout or test failure - likely kcov issue
			# Still treat as test failure to be safe
			return 1
		fi
	fi
}

# Run a single test file with per-test timeout
#
# Extracts individual tests from a test file and runs each with timeout.
# Supports coverage reporting when enabled.
#
# Arguments:
#   $1: Test file path
#   $2: Timeout in seconds
#   $3: Use coverage flag (0 or 1, optional, default: 0)
#   $4: Coverage directory (optional, required if coverage enabled)
#   ${@:5}: kcov arguments (optional, required if coverage enabled)
#
# Returns:
#   0: All tests passed
#   1: One or more tests failed
#   2: One or more tests timed out
#
run_test_file_with_timeout() {
	local test_file="$1"
	local timeout_seconds="$2"
	local use_coverage="${3:-0}"
	local coverage_dir="${4:-}"
	local kcov_args=("${@:5}")

	# Extract test names from the file
	local test_names
	mapfile -t test_names < <(extract_test_names "$test_file")

	if [[ ${#test_names[@]} -eq 0 ]]; then
		echo -e "${YELLOW}Warning: No tests found in $(basename "$test_file")${NC}" >&2
		return 0
	fi

	# If rerun-failed is enabled, filter test names to only failed tests
	# Note: This is a simplified approach - bats' --filter-status is more accurate
	# but requires running bats first to determine which tests failed
	if [[ "$RERUN_FAILED" -eq 1 ]]; then
		# For rerun-failed, we rely on bats' --filter-status flag
		# which is handled in run_single_test_with_timeout
		:
	fi

	local failed_tests=0
	local timed_out_tests=0
	local total_tests=${#test_names[@]}

	echo -e "${BLUE}Running ${total_tests} test(s) from $(basename "$test_file")...${NC}" >&2

	# Run each test individually with timeout
	for test_name in "${test_names[@]}"; do
		if [[ $use_coverage -eq 1 ]] && [[ -n "$coverage_dir" ]]; then
			run_single_test_with_timeout "$test_file" "$test_name" "$timeout_seconds" "$use_coverage" "$coverage_dir" "${kcov_args[@]}"
		else
			run_single_test_with_timeout "$test_file" "$test_name" "$timeout_seconds"
		fi
		local test_result=$?

		if [[ $test_result -eq 2 ]]; then
			# Timeout occurred
			timed_out_tests=$((timed_out_tests + 1))
			# If fast-fail is enabled, stop on first timeout
			if [[ "$FAST_FAIL" -eq 1 ]]; then
				echo -e "${RED}Fast-fail enabled: stopping test execution${NC}" >&2
				return 2
			fi
		elif [[ $test_result -ne 0 ]]; then
			# Test failure
			failed_tests=$((failed_tests + 1))
			# If fast-fail is enabled, stop on first failure
			if [[ "$FAST_FAIL" -eq 1 ]]; then
				echo -e "${RED}Fast-fail enabled: stopping test execution${NC}" >&2
				return 1
			fi
		fi
	done

	# Return appropriate exit code
	if [[ $timed_out_tests -gt 0 ]]; then
		return 2
	elif [[ $failed_tests -gt 0 ]]; then
		return 1
	else
		return 0
	fi
}

# Run tests sequentially (without coverage)
#
# Runs test files sequentially (one at a time) without coverage reporting.
# Results are stored in global variables SEQUENTIAL_FAILED and SEQUENTIAL_TIMED_OUT.
#
# Arguments:
#   $@: Test file paths
#
# Returns:
#   0: Always succeeds (results in global variables SEQUENTIAL_FAILED and SEQUENTIAL_TIMED_OUT)
#
run_tests_sequential() {
	local test_files=("$@")
	local failed_tests=0
	local timed_out_tests=0

	for test_file in "${test_files[@]}"; do
		# Check if interrupted
		if [[ $INTERRUPTED -eq 1 ]]; then
			break
		fi

		echo -e "${BLUE}Running: $(basename "$test_file")${NC}"

		# Run test file with timeout wrapper
		# Capture exit code explicitly to prevent set -e from stopping execution
		local test_result=0
		if ! run_test_file_with_timeout "$test_file" "$TEST_TIMEOUT"; then
			test_result=$?
		fi

		# Check if interrupted (exit code 130 = SIGINT)
		if [[ $test_result -eq 130 ]] || [[ $INTERRUPTED -eq 1 ]]; then
			break
		fi

		if [[ $test_result -eq 2 ]]; then
			# Timeout occurred
			timed_out_tests=$((timed_out_tests + 1))
		elif [[ $test_result -ne 0 ]]; then
			# Test failure
			failed_tests=$((failed_tests + 1))
			# If fast-fail is enabled, stop on first failure
			if [[ "$FAST_FAIL" -eq 1 ]]; then
				echo -e "${RED}Fast-fail enabled: stopping test execution${NC}" >&2
				return 1
			fi
		fi
		echo ""
	done

	# Return results via global variables (bash limitation)
	export SEQUENTIAL_FAILED=$failed_tests
	export SEQUENTIAL_TIMED_OUT=$timed_out_tests
	return 0
}

# Run tests in parallel (without coverage)
#
# Runs test files in parallel using GNU parallel or rush.
# Results are stored in global variables PARALLEL_FAILED and PARALLEL_TIMED_OUT.
#
# Arguments:
#   $1: Number of parallel jobs
#   ${@:2}: Test file paths
#
# Returns:
#   0: Always succeeds (results in global variables PARALLEL_FAILED and PARALLEL_TIMED_OUT)
#
run_tests_parallel() {
	local num_jobs="$1"
	shift
	local test_files=("$@")
	local failed_tests=0
	local timed_out_tests=0
	local temp_dir
	temp_dir=$(mktemp -d) || {
		echo -e "${RED}Error: Failed to create temporary directory${NC}" >&2
		exit 1
	}
	local results_file="${temp_dir}/results"
	local failed_file="${temp_dir}/failed"
	local timeout_file="${temp_dir}/timeout"

	# Initialize result files
	: >"$results_file"
	: >"$failed_file"
	: >"$timeout_file"

	# Export function and variables for parallel execution
	export -f run_test_file_with_timeout
	export -f run_single_test_with_timeout
	export -f extract_test_names
	export -f escape_test_name_for_filter
	export TEST_TIMEOUT
	export RERUN_FAILED
	export FILTER_TAGS
	export PROJECT_ROOT

	# Create a function that parallel can call
	#
	# Runs a single test file with timeout and writes results to files.
	# This function is called by GNU parallel or rush for parallel execution.
	#
	# Arguments:
	#   $1: Test file path
	#
	# Returns:
	#   0: Test passed
	#   1: Test failed
	#   2: Test timed out
	#
	parallel_test_runner() {
		local test_file="$1"
		local test_name
		test_name=$(basename "$test_file")
		echo -e "${BLUE}Running: ${test_name}${NC}" >&2

		# Capture exit code explicitly to prevent set -e from stopping execution
		local test_result=0
		if ! run_test_file_with_timeout "$test_file" "$TEST_TIMEOUT"; then
			test_result=$?
		fi

		# Write result to file
		echo "${test_file}:${test_result}" >>"$results_file"

		if [[ $test_result -eq 2 ]]; then
			echo "$test_file" >>"$timeout_file"
		elif [[ $test_result -ne 0 ]]; then
			echo "$test_file" >>"$failed_file"
		fi

		return $test_result
	}
	export -f parallel_test_runner
	export results_file
	export timeout_file
	export failed_file

	# Function that parallel can call
	# Note: This function is defined inside run_tests_parallel but exported for parallel execution
	# It's documented here for completeness but the actual definition is above
	# parallel_test_runner() {
	#   Arguments:
	#     $1: Test file path
	#   Returns:
	#     0: Test passed
	#     1: Test failed
	#     2: Test timed out
	# }

	# Run tests in parallel using GNU parallel or rush
	if [[ "$PARALLEL_TOOL" == "parallel" ]]; then
		# Use GNU parallel
		# --tag: Tag output with job ID
		# --line-buffer: Print output as soon as it's available (may still be buffered)
		# --halt now,fail=1: Stop immediately if fast-fail is enabled and any job fails
		if [[ "$FAST_FAIL" -eq 1 ]]; then
			parallel --tag --line-buffer -j "$num_jobs" --halt now,fail=1 parallel_test_runner ::: "${test_files[@]}" || true
		else
			parallel --tag --line-buffer -j "$num_jobs" parallel_test_runner ::: "${test_files[@]}" || true
		fi
	elif [[ "$PARALLEL_TOOL" == "rush" ]]; then
		# Use rush
		# -j: Number of parallel jobs
		# -v: Verbose output
		# --halt now,fail=1: Stop immediately if fast-fail is enabled
		printf '%s\n' "${test_files[@]}" |
			if [[ "$FAST_FAIL" -eq 1 ]]; then
				rush -j "$num_jobs" -v 'parallel_test_runner {}' --halt now,fail=1 || true
			else
				rush -j "$num_jobs" -v 'parallel_test_runner {}' || true
			fi
	fi

	# Count results
	if [[ -f "$failed_file" ]]; then
		failed_tests=$(wc -l <"$failed_file" | tr -d ' ')
	fi
	if [[ -f "$timeout_file" ]]; then
		timed_out_tests=$(wc -l <"$timeout_file" | tr -d ' ')
	fi

	# Cleanup
	rm -rf "$temp_dir"

	# Return results via global variables
	export PARALLEL_FAILED=$failed_tests
	export PARALLEL_TIMED_OUT=$timed_out_tests
	return 0
}

# Run tests in individual mode - each test case runs separately with detailed output
#
# Runs each test case individually with detailed per-test output.
# Supports checkpoint/resume functionality and coverage reporting.
# Results are saved to logs/test_results_TIMESTAMP.txt.
#
# Arguments:
#   None
#
# Returns:
#   0: All tests passed
#   1: One or more tests failed or timed out (exits script)
#
run_tests_individual() {
	# Filter test files based on slow test setting
	local test_files
	mapfile -t test_files < <(filter_test_files)
	local test_count=${#test_files[@]}

	if [[ $test_count -eq 0 ]]; then
		echo -e "${RED}Error: No test files found${NC}" >&2
		exit 1
	fi

	# Results tracking
	local failed_tests=()
	local timed_out_tests=()
	local passed_tests=()
	local skipped_tests=()
	local total_tests=0
	local failed_count=0
	local timed_out_count=0
	local passed_count=0
	local skipped_count=0

	# Initialize checkpoint tracking
	declare -gA CHECKPOINT_PASSED

	# Load checkpoint if resuming
	local checkpoint_file
	checkpoint_file=$(get_checkpoint_file)
	if [[ "$RESUME_MODE" -eq 1 ]]; then
		if [[ -f "$checkpoint_file" ]]; then
			load_checkpoint
			local checkpoint_size
			checkpoint_size=$(wc -l <"$checkpoint_file" | tr -d ' ')
			local passed_in_checkpoint
			passed_in_checkpoint=${#CHECKPOINT_PASSED[@]}
			echo -e "${BLUE}Resuming from checkpoint: ${checkpoint_file}${NC}"
			echo -e "${BLUE}Found ${checkpoint_size} test(s) in checkpoint (${passed_in_checkpoint} passed)${NC}"
			echo ""
		else
			echo -e "${YELLOW}Warning: No checkpoint file found at ${checkpoint_file}${NC}"
			echo -e "${YELLOW}Starting fresh test run...${NC}"
			echo ""
		fi
	else
		# Clear checkpoint if not resuming
		clear_checkpoint
	fi

	# Results file
	local logs_dir="${PROJECT_ROOT}/logs"
	mkdir -p "$logs_dir"
	local results_file="${logs_dir}/test_results_$(date +%Y%m%d_%H%M%S).txt"

	echo -e "${GREEN}Running individual test cases with ${TEST_TIMEOUT}s timeout...${NC}"
	echo "Results will be saved to: ${results_file}"
	if [[ "$RESUME_MODE" -eq 1 ]]; then
		echo "Checkpoint file: ${checkpoint_file}"
	fi
	if [[ "$RUN_SLOW_TESTS" -eq 0 ]]; then
		echo -e "${YELLOW}(Slow tests excluded - use --slow to include)${NC}"
	fi
	if [[ -n "$FILTER_TAGS" ]]; then
		echo -e "${BLUE}Filtering tests by tags: ${FILTER_TAGS}${NC}"
	fi
	echo ""

	# Initialize results file
	{
		echo "Test Results - $(date)"
		echo "================================"
		echo "Timeout: ${TEST_TIMEOUT} seconds"
		if [[ "$RUN_SLOW_TESTS" -eq 0 ]]; then
			echo "Slow tests: excluded"
		else
			echo "Slow tests: included"
		fi
		if [[ -n "$FILTER_TAGS" ]]; then
			echo "Filter tags: ${FILTER_TAGS}"
		fi
		echo ""
	} >"$results_file"

	cd "$PROJECT_ROOT"

	# Set up coverage directory if coverage is enabled
	if [[ "$COVERAGE_ENABLED" -eq 1 ]] && [[ -n "$COVERAGE_TOOL" ]]; then
		# Clean or create coverage directory
		if [[ -d "$COVERAGE_DIR" ]]; then
			echo -e "${YELLOW}Cleaning existing coverage directory...${NC}"
			rm -rf "$COVERAGE_DIR"
		fi
		mkdir -p "$COVERAGE_DIR"
		echo -e "${BLUE}Coverage output directory: ${COVERAGE_DIR}${NC}"
	fi

	# Process each test file
	local should_stop=0
	for test_file in "${test_files[@]}"; do
		# Break out of outer loop if fast-fail triggered or interrupted
		if [[ $should_stop -eq 1 ]] || [[ $INTERRUPTED -eq 1 ]]; then
			break
		fi

		local filename
		filename=$(basename "$test_file")
		echo -e "${BLUE}Processing: ${filename}${NC}"

		# Extract test names from the file
		local test_names
		mapfile -t test_names < <(extract_test_names "$test_file")

		if [[ ${#test_names[@]} -eq 0 ]]; then
			echo -e "${YELLOW}  No tests found in ${filename}${NC}"
			continue
		fi

		echo -e "${BLUE}  Found ${#test_names[@]} test(s)${NC}"

		# Run each test individually
		for test_name in "${test_names[@]}"; do
			# Check if interrupted
			if [[ $INTERRUPTED -eq 1 ]]; then
				break
			fi

			total_tests=$((total_tests + 1))
			local test_id="${filename}::${test_name}"

			# Check if we should skip this test (already passed in checkpoint)
			if should_skip_test "$test_id"; then
				skipped_count=$((skipped_count + 1))
				skipped_tests+=("$test_id")
				echo "  [${total_tests}] Skipping: ${test_name}... (already passed in checkpoint)"
				echo "SKIPPED: ${test_id} (from checkpoint)" >>"$results_file"
				continue
			fi

			echo "  [${total_tests}] Running: ${test_name}..."

			# Run the test, streaming output to terminal while capturing it
			local start_time
			start_time=$(date +%s)
			local test_output
			local test_result
			# Use a temporary file to capture output while streaming to terminal
			local temp_output
			temp_output=$(mktemp)

			# Run with coverage if enabled, using unbuffered tee to stream and capture output
			# Note: run_single_test_with_timeout already uses stdbuf internally, but we ensure tee is also unbuffered
			# Use explicit error handling to prevent set -e from stopping execution
			set +e # Temporarily disable exit on error for pipeline
			if [[ "$COVERAGE_ENABLED" -eq 1 ]] && [[ -n "$COVERAGE_TOOL" ]]; then
				local kcov_args
				get_kcov_args
				kcov_args=("${KCOV_ARGS[@]}")
				if command -v stdbuf >/dev/null 2>&1; then
					run_single_test_with_timeout "$test_file" "$test_name" "$TEST_TIMEOUT" "1" "$COVERAGE_DIR" "${kcov_args[@]}" 2>&1 | stdbuf -oL -eL -i0 tee "$temp_output"
				else
					run_single_test_with_timeout "$test_file" "$test_name" "$TEST_TIMEOUT" "1" "$COVERAGE_DIR" "${kcov_args[@]}" 2>&1 | tee "$temp_output"
				fi
			else
				if command -v stdbuf >/dev/null 2>&1; then
					run_single_test_with_timeout "$test_file" "$test_name" "$TEST_TIMEOUT" 2>&1 | stdbuf -oL -eL -i0 tee "$temp_output"
				else
					run_single_test_with_timeout "$test_file" "$test_name" "$TEST_TIMEOUT" 2>&1 | tee "$temp_output"
				fi
			fi
			test_result=${PIPESTATUS[0]}
			set -e # Re-enable exit on error

			# Check if interrupted (exit code 130 = SIGINT)
			if [[ $test_result -eq 130 ]] || [[ $INTERRUPTED -eq 1 ]]; then
				rm -f "$temp_output"
				should_stop=1
				break
			fi

			test_output=$(cat "$temp_output")
			rm -f "$temp_output"
			local end_time
			end_time=$(date +%s)
			local duration=$((end_time - start_time))

			# Process results and log to file
			if [[ $test_result -eq 2 ]]; then
				# Timeout
				timed_out_count=$((timed_out_count + 1))
				timed_out_tests+=("$test_id")
				echo -e " ${RED}[TIMEOUT after ${duration}s]${NC}"
				{
					echo "TIMEOUT: ${test_id} (${duration}s)"
					echo "  Output:"
					echo "$test_output" | sed 's/^/    /'
					echo ""
				} >>"$results_file"
				# Save to checkpoint
				save_checkpoint "$test_id" "TIMEOUT"
			elif [[ $test_result -ne 0 ]]; then
				# Failure
				failed_count=$((failed_count + 1))
				failed_tests+=("$test_id")
				echo -e " ${RED}[FAILED after ${duration}s]${NC}"
				{
					echo "FAILED: ${test_id} (${duration}s)"
					echo "  Output:"
					echo "$test_output" | sed 's/^/    /'
					echo ""
				} >>"$results_file"
				# Save to checkpoint
				save_checkpoint "$test_id" "FAILED"
				# Show resume tip immediately after failure (but only once)
				if [[ "$INDIVIDUAL_MODE" -eq 1 ]] && [[ "$RESUME_MODE" -eq 0 ]] && [[ $failed_count -eq 1 ]]; then
					echo -e "${BLUE}  (Tests will continue. Use --resume to skip passed tests on next run)${NC}"
				fi
			else
				# Success
				passed_count=$((passed_count + 1))
				passed_tests+=("$test_id")
				echo -e " ${GREEN}[PASSED in ${duration}s]${NC}"
				{
					echo "PASSED: ${test_id} (${duration}s)"
					echo "  Output:"
					echo "$test_output" | sed 's/^/    /'
					echo ""
				} >>"$results_file"
				# Save to checkpoint (only passed tests are used for skipping)
				save_checkpoint "$test_id" "PASSED"
			fi

			# If fast-fail is enabled, stop on first failure or timeout
			if [[ "$FAST_FAIL" -eq 1 ]] && [[ $test_result -ne 0 ]]; then
				echo -e "${RED}Fast-fail enabled: stopping test execution${NC}" >&2
				should_stop=1
				break
			fi
		done

		echo ""
	done

	# Print summary
	echo ""
	echo -e "${GREEN}========================================${NC}"
	echo -e "${GREEN}Test Execution Summary${NC}"
	echo -e "${GREEN}========================================${NC}"
	echo -e "Total tests: ${total_tests}"
	echo -e "${GREEN}Passed: ${passed_count}${NC}"
	echo -e "${RED}Failed: ${failed_count}${NC}"
	echo -e "${YELLOW}Timed out: ${timed_out_count}${NC}"
	if [[ $skipped_count -gt 0 ]]; then
		echo -e "${BLUE}Skipped (from checkpoint): ${skipped_count}${NC}"
	fi
	echo ""

	# Write detailed summary to results file
	{
		echo ""
		echo "=========================================="
		echo "Summary"
		echo "=========================================="
		echo "Total tests: ${total_tests}"
		echo "Passed: ${passed_count}"
		echo "Failed: ${failed_count}"
		echo "Timed out: ${timed_out_count}"
		if [[ $skipped_count -gt 0 ]]; then
			echo "Skipped (from checkpoint): ${skipped_count}"
		fi
		echo ""

		if [[ ${#failed_tests[@]} -gt 0 ]]; then
			echo "Failed Tests:"
			echo "-------------"
			for test in "${failed_tests[@]}"; do
				echo "  - ${test}"
			done
			echo ""
		fi

		if [[ ${#timed_out_tests[@]} -gt 0 ]]; then
			echo "Timed Out Tests:"
			echo "----------------"
			for test in "${timed_out_tests[@]}"; do
				echo "  - ${test}"
			done
			echo ""
		fi
	} >>"$results_file"

	# Print failed tests
	if [[ ${#failed_tests[@]} -gt 0 ]]; then
		echo -e "${RED}Failed Tests:${NC}"
		for test in "${failed_tests[@]}"; do
			echo -e "  ${RED}✗${NC} ${test}"
		done
		echo ""
	fi

	# Print timed out tests
	if [[ ${#timed_out_tests[@]} -gt 0 ]]; then
		echo -e "${YELLOW}Timed Out Tests:${NC}"
		for test in "${timed_out_tests[@]}"; do
			echo -e "  ${YELLOW}⏱${NC} ${test}"
		done
		echo ""
	fi

	echo -e "Results saved to: ${results_file}"
	if [[ "$RESUME_MODE" -eq 1 ]]; then
		echo -e "Checkpoint file: ${checkpoint_file}"
		echo -e "${BLUE}To resume from this point, run: ./tests/run_tests.sh --individual --resume${NC}"
	fi

	# Show resume suggestion if tests failed and we're in individual mode
	if [[ "$INDIVIDUAL_MODE" -eq 1 ]] && [[ "$RESUME_MODE" -eq 0 ]] && ([[ $failed_count -gt 0 ]] || [[ $timed_out_count -gt 0 ]]); then
		echo ""
		echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
		echo -e "${BLUE}Tip: To resume from this point and skip already passed tests:${NC}"
		echo -e "${BLUE}  ./tests/run_tests.sh --individual --resume${NC}"
		if [[ "$RUN_SLOW_TESTS" -eq 1 ]]; then
			echo -e "${BLUE}  ./tests/run_tests.sh --individual --resume --slow${NC}"
		fi
		echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
	fi
	echo ""

	# Show coverage summary if coverage was enabled
	if [[ "$COVERAGE_ENABLED" -eq 1 ]] && [[ -n "$COVERAGE_TOOL" ]]; then
		# Check if coverage reports were generated
		if [[ -f "${COVERAGE_DIR}/index.html" ]] || [[ -f "${COVERAGE_DIR}/index.js" ]] || [[ -f "${COVERAGE_DIR}/index.json" ]]; then
			echo ""
			echo -e "${GREEN}Coverage report generated successfully!${NC}"
			echo -e "${GREEN}View HTML report: ${COVERAGE_DIR}/index.html${NC}"
			echo ""

			# Print summary if available
			print_coverage_summary
		else
			echo -e "${YELLOW}Warning: Coverage reports not found${NC}" >&2
			echo "kcov may have encountered an error. Check kcov output above." >&2
		fi
	fi

	# Exit with error if any tests failed or timed out
	# Note: This is expected behavior - the script should exit with error code when tests fail
	# but all tests have already been run (tests continue even when one fails)
	if [[ $failed_count -gt 0 ]] || [[ $timed_out_count -gt 0 ]]; then
		exit 1
	fi
}

# Run tests with coverage if enabled
#
# Main test runner function. Routes to individual mode, sequential mode, or parallel mode.
# Handles coverage reporting when enabled.
#
# Arguments:
#   None
#
# Returns:
#   0: All tests passed
#   1: One or more tests failed (exits script)
#
run_tests() {
	# Check if individual mode is enabled
	if [[ "$INDIVIDUAL_MODE" -eq 1 ]]; then
		run_tests_individual
		return
	fi

	# Filter test files based on slow test setting
	local test_files
	mapfile -t test_files < <(filter_test_files)
	local test_count=${#test_files[@]}

	if [[ $test_count -eq 0 ]]; then
		echo -e "${RED}Error: No test files found${NC}" >&2
		exit 1
	fi

	echo -e "${GREEN}Running $test_count test file(s)...${NC}"
	if [[ "$RUN_SLOW_TESTS" -eq 0 ]]; then
		echo -e "${YELLOW}(Slow tests excluded - use --slow to include)${NC}"
	fi
	if [[ "$RERUN_FAILED" -eq 1 ]]; then
		echo -e "${BLUE}Rerunning only failed tests from last run...${NC}"
	fi
	if [[ -n "$FILTER_TAGS" ]]; then
		echo -e "${BLUE}Filtering tests by tags: ${FILTER_TAGS}${NC}"
	fi
	if [[ "$FAST_FAIL" -eq 0 ]]; then
		echo -e "${BLUE}Fast-fail: disabled (will run all tests)${NC}"
	fi
	if [[ "$PARALLEL_JOBS" == "0" ]]; then
		echo -e "${BLUE}Parallel execution: disabled (sequential mode)${NC}"
	fi
	echo -e "${BLUE}Test timeout: ${TEST_TIMEOUT}s (tests exceeding this will be skipped)${NC}"
	echo ""

	cd "$PROJECT_ROOT"

	# Run with coverage if enabled
	if [[ "$COVERAGE_ENABLED" -eq 1 ]] && [[ -n "$COVERAGE_TOOL" ]]; then
		run_tests_with_coverage "${test_files[@]}"
	else
		# Run without coverage
		# Check if parallel execution should be used
		local num_jobs
		num_jobs=$(get_parallel_jobs)
		local use_parallel=0

		if [[ "$num_jobs" != "0" ]] && check_parallel_tool; then
			use_parallel=1
		fi

		local failed_tests=0
		local timed_out_tests=0

		if [[ $use_parallel -eq 1 ]]; then
			# Run tests in parallel
			run_tests_parallel "$num_jobs" "${test_files[@]}"
			failed_tests=${PARALLEL_FAILED:-0}
			timed_out_tests=${PARALLEL_TIMED_OUT:-0}
		else
			# Run tests sequentially
			run_tests_sequential "${test_files[@]}"
			failed_tests=${SEQUENTIAL_FAILED:-0}
			timed_out_tests=${SEQUENTIAL_TIMED_OUT:-0}
		fi

		# Print summary
		echo -e "${GREEN}Test execution complete${NC}"
		if [[ $failed_tests -gt 0 ]]; then
			echo -e "${YELLOW}Failed test files: $failed_tests${NC}"
		fi
		if [[ $timed_out_tests -gt 0 ]]; then
			echo -e "${YELLOW}Timed out test files: $timed_out_tests${NC}"
		fi

		# Exit with error if any tests failed
		# Note: FAST_FAIL only controls whether to stop early, not the exit code
		if [[ $failed_tests -gt 0 ]]; then
			exit 1
		fi
	fi
}

# Note: run_test_file_with_coverage_timeout() has been removed.
# Coverage is now handled by run_test_file_with_timeout() with use_coverage flag.
# This ensures consistent per-test timeout behavior for both coverage and non-coverage runs.

# Run tests sequentially (with coverage)
#
# Runs test files sequentially (one at a time) with coverage reporting.
# Results are stored in global variables SEQUENTIAL_COV_FAILED and SEQUENTIAL_COV_TIMED_OUT.
#
# Arguments:
#   $1: Coverage directory
#   $2-$N: kcov arguments (variable number: --include-path and --exclude-path args)
#   ${@:N+1}: Test file paths
#
# Returns:
#   0: Always succeeds (results in global variables SEQUENTIAL_COV_FAILED and SEQUENTIAL_COV_TIMED_OUT)
#
run_tests_sequential_with_coverage() {
	local coverage_dir="$1"
	shift
	# Collect kcov arguments until we hit a test file (arguments that don't start with --)
	local kcov_args=()
	while [[ $# -gt 0 ]] && [[ "$1" == --* ]]; do
		kcov_args+=("$1")
		shift
	done
	# Remaining arguments are test files
	local test_files=("$@")

	local failed_tests=0
	local timed_out_tests=0

	for test_file in "${test_files[@]}"; do
		echo -e "${BLUE}Running with coverage: $(basename "$test_file")${NC}"

		# Run test file with per-test timeout and coverage
		# Capture exit code explicitly to prevent set -e from stopping execution
		local test_result=0
		if ! run_test_file_with_timeout "$test_file" "$TEST_TIMEOUT" "1" "$coverage_dir" "${kcov_args[@]}"; then
			test_result=$?
		fi

		if [[ $test_result -eq 2 ]]; then
			# Timeout occurred
			timed_out_tests=$((timed_out_tests + 1))
			# If fast-fail is enabled, stop on first timeout
			if [[ "$FAST_FAIL" -eq 1 ]]; then
				echo -e "${RED}Fast-fail enabled: stopping test execution${NC}" >&2
				return 1
			fi
		elif [[ $test_result -ne 0 ]]; then
			# Test failure
			failed_tests=$((failed_tests + 1))
			# If fast-fail is enabled, stop on first failure
			if [[ "$FAST_FAIL" -eq 1 ]]; then
				echo -e "${RED}Fast-fail enabled: stopping test execution${NC}" >&2
				return 1
			fi
		fi
		echo ""
	done

	# Return results via global variables
	export SEQUENTIAL_COV_FAILED=$failed_tests
	export SEQUENTIAL_COV_TIMED_OUT=$timed_out_tests
	return 0
}

# Run tests in parallel (with coverage)
#
# Runs test files in parallel with coverage reporting using GNU parallel or rush.
# Results are stored in global variables PARALLEL_COV_FAILED and PARALLEL_COV_TIMED_OUT.
#
# Arguments:
#   $1: Number of parallel jobs
#   $2: Coverage directory
#   $3-$N: kcov arguments (variable number: --include-path and --exclude-path args)
#   ${@:N+1}: Test file paths
#
# Returns:
#   0: Always succeeds (results in global variables PARALLEL_COV_FAILED and PARALLEL_COV_TIMED_OUT)
#
run_tests_parallel_with_coverage() {
	local num_jobs="$1"
	local coverage_dir="$2"
	shift 2
	# Collect kcov arguments until we hit a test file (arguments that don't start with --)
	local kcov_args=()
	while [[ $# -gt 0 ]] && [[ "$1" == --* ]]; do
		kcov_args+=("$1")
		shift
	done
	# Remaining arguments are test files
	local test_files=("$@")
	local failed_tests=0
	local timed_out_tests=0
	local temp_dir
	temp_dir=$(mktemp -d) || {
		echo -e "${RED}Error: Failed to create temporary directory${NC}" >&2
		exit 1
	}
	local results_file="${temp_dir}/results"
	local failed_file="${temp_dir}/failed"
	local timeout_file="${temp_dir}/timeout"

	# Initialize result files
	: >"$results_file"
	: >"$failed_file"
	: >"$timeout_file"

	# Export function and variables for parallel execution
	export -f run_test_file_with_timeout
	export -f run_single_test_with_timeout
	export -f extract_test_names
	export -f escape_test_name_for_filter
	export -f get_kcov_args
	export TEST_TIMEOUT
	export RERUN_FAILED
	export FILTER_TAGS
	export PROJECT_ROOT
	export COVERAGE_DIR="$coverage_dir"

	# Create a function that parallel can call
	#
	# Runs a single test file with timeout and coverage, writing results to files.
	# This function is called by GNU parallel or rush for parallel execution with coverage.
	#
	# Arguments:
	#   $1: Test file path
	#
	# Returns:
	#   0: Test passed
	#   1: Test failed
	#   2: Test timed out
	#
	parallel_test_runner_with_coverage() {
		local test_file="$1"
		local test_name
		test_name=$(basename "$test_file")
		echo -e "${BLUE}Running with coverage: ${test_name}${NC}" >&2

		# Reconstruct kcov_args array (bash limitation with parallel)
		# Use get_kcov_args function to get the arguments
		local kcov_args_array
		get_kcov_args
		kcov_args_array=("${KCOV_ARGS[@]}")

		# Capture exit code explicitly to prevent set -e from stopping execution
		local test_result=0
		if ! run_test_file_with_timeout "$test_file" "$TEST_TIMEOUT" "1" "$COVERAGE_DIR" "${kcov_args_array[@]}"; then
			test_result=$?
		fi

		# Write result to file
		echo "${test_file}:${test_result}" >>"$results_file"

		if [[ $test_result -eq 2 ]]; then
			echo "$test_file" >>"$timeout_file"
		elif [[ $test_result -ne 0 ]]; then
			echo "$test_file" >>"$failed_file"
		fi

		return $test_result
	}
	export -f parallel_test_runner_with_coverage
	export results_file
	export timeout_file
	export failed_file

	# Function that parallel can call (with coverage)
	# Note: This function is defined inside run_tests_parallel_with_coverage but exported for parallel execution
	# It's documented here for completeness but the actual definition is above
	# parallel_test_runner_with_coverage() {
	#   Arguments:
	#     $1: Test file path
	#   Returns:
	#     0: Test passed
	#     1: Test failed
	#     2: Test timed out
	# }

	# Run tests in parallel using GNU parallel or rush
	if [[ "$PARALLEL_TOOL" == "parallel" ]]; then
		# Use GNU parallel
		if [[ "$FAST_FAIL" -eq 1 ]]; then
			parallel --tag --line-buffer -j "$num_jobs" --halt now,fail=1 parallel_test_runner_with_coverage ::: "${test_files[@]}" || true
		else
			parallel --tag --line-buffer -j "$num_jobs" parallel_test_runner_with_coverage ::: "${test_files[@]}" || true
		fi
	elif [[ "$PARALLEL_TOOL" == "rush" ]]; then
		# Use rush
		printf '%s\n' "${test_files[@]}" |
			if [[ "$FAST_FAIL" -eq 1 ]]; then
				rush -j "$num_jobs" -v 'parallel_test_runner_with_coverage {}' --halt now,fail=1 || true
			else
				rush -j "$num_jobs" -v 'parallel_test_runner_with_coverage {}' || true
			fi
	fi

	# Count results
	if [[ -f "$failed_file" ]]; then
		failed_tests=$(wc -l <"$failed_file" | tr -d ' ')
	fi
	if [[ -f "$timeout_file" ]]; then
		timed_out_tests=$(wc -l <"$timeout_file" | tr -d ' ')
	fi

	# Cleanup
	rm -rf "$temp_dir"

	# Return results via global variables
	export PARALLEL_COV_FAILED=$failed_tests
	export PARALLEL_COV_TIMED_OUT=$timed_out_tests
	return 0
}

# Run tests with kcov coverage
#
# Main test runner function for coverage mode. Routes to sequential or parallel execution with coverage.
# Generates coverage reports in HTML format.
#
# Arguments:
#   $@: Test file paths
#
# Returns:
#   0: All tests passed
#   1: One or more tests failed (exits script)
#
run_tests_with_coverage() {
	local test_files=("$@")

	# Clean or create coverage directory
	if [[ -d "$COVERAGE_DIR" ]]; then
		echo -e "${YELLOW}Cleaning existing coverage directory...${NC}"
		rm -rf "$COVERAGE_DIR"
	fi
	mkdir -p "$COVERAGE_DIR"

	echo -e "${BLUE}Running tests with coverage reporting...${NC}"
	echo -e "${BLUE}Coverage output directory: ${COVERAGE_DIR}${NC}"
	if [[ "$FAST_FAIL" -eq 0 ]]; then
		echo -e "${BLUE}Fast-fail: disabled (will run all tests)${NC}"
	fi
	echo -e "${BLUE}Test timeout: ${TEST_TIMEOUT}s (tests exceeding this will be skipped)${NC}"
	echo ""

	# kcov arguments
	# kcov traces bash script execution, so wrapping bats will capture
	# coverage for all bash scripts executed during test runs
	local kcov_args
	get_kcov_args
	kcov_args=("${KCOV_ARGS[@]}")

	# Add filter for failed tests if rerun-failed is enabled
	if [[ "$RERUN_FAILED" -eq 1 ]]; then
		echo -e "${BLUE}Rerunning only failed tests from last run...${NC}"
	fi

	# Check if parallel execution should be used
	local num_jobs
	num_jobs=$(get_parallel_jobs)
	local use_parallel=0

	if [[ "$num_jobs" != "0" ]] && check_parallel_tool; then
		use_parallel=1
	fi

	local failed_tests=0
	local timed_out_tests=0

	if [[ $use_parallel -eq 1 ]]; then
		# Run tests in parallel with coverage
		run_tests_parallel_with_coverage "$num_jobs" "$COVERAGE_DIR" "${kcov_args[@]}" "${test_files[@]}"
		failed_tests=${PARALLEL_COV_FAILED:-0}
		timed_out_tests=${PARALLEL_COV_TIMED_OUT:-0}
	else
		# Run tests sequentially with coverage
		run_tests_sequential_with_coverage "$COVERAGE_DIR" "${kcov_args[@]}" "${test_files[@]}"
		failed_tests=${SEQUENTIAL_COV_FAILED:-0}
		timed_out_tests=${SEQUENTIAL_COV_TIMED_OUT:-0}
	fi

	# Check if coverage reports were generated
	if [[ -f "${COVERAGE_DIR}/index.html" ]] || [[ -f "${COVERAGE_DIR}/index.js" ]] || [[ -f "${COVERAGE_DIR}/index.json" ]]; then
		echo ""
		echo -e "${GREEN}Coverage report generated successfully!${NC}"
		echo -e "${GREEN}View HTML report: ${COVERAGE_DIR}/index.html${NC}"
		echo ""

		# Print summary if available
		print_coverage_summary
	else
		echo -e "${YELLOW}Warning: Coverage reports not found${NC}" >&2
		echo "kcov may have encountered an error. Check kcov output above." >&2
	fi

	# Print test summary
	if [[ $failed_tests -gt 0 ]]; then
		echo -e "${YELLOW}Failed test files: $failed_tests${NC}"
	fi
	if [[ $timed_out_tests -gt 0 ]]; then
		echo -e "${YELLOW}Timed out test files: $timed_out_tests${NC}"
	fi

	# Exit with error if any tests failed
	# Note: FAST_FAIL only controls whether to stop early, not the exit code
	if [[ $failed_tests -gt 0 ]]; then
		exit 1
	fi
}

# Print coverage summary from kcov report
#
# Extracts and prints coverage summary from kcov-generated reports.
# Supports both JavaScript format (kcov v43+) and JSON format (older versions).
#
# Arguments:
#   None
#
# Returns:
#   None (outputs coverage summary to stdout)
#
print_coverage_summary() {
	# kcov v43+ uses JavaScript file with embedded JSON data
	# Older versions may use index.json
	local js_report="${COVERAGE_DIR}/index.js"
	local json_report="${COVERAGE_DIR}/index.json"

	# Try to extract coverage from JavaScript file (kcov v43+)
	if [[ -f "$js_report" ]]; then
		# Extract coverage data from JavaScript file
		# Format: var data = {files:[...], merged_files:[]}; var header = {...};
		local header_data
		header_data=$(grep -oP 'var header = \{[^}]+\}' "$js_report" 2>/dev/null || echo "")

		if [[ -n "$header_data" ]]; then
			echo -e "${BLUE}Coverage Summary:${NC}"
			echo "=================="

			# Extract coverage percentage from header
			local covered instrumented
			covered=$(echo "$header_data" | grep -oP '"covered"\s*:\s*"?\K[0-9.]+' || echo "")
			instrumented=$(echo "$header_data" | grep -oP '"instrumented"\s*:\s*"?\K[0-9.]+' || echo "")

			if [[ -n "$covered" ]] && [[ -n "$instrumented" ]] && [[ "$instrumented" != "0" ]]; then
				# Calculate percentage
				local percent
				percent=$(awk "BEGIN {printf \"%.1f\", ($covered / $instrumented) * 100}" 2>/dev/null || echo "N/A")
				echo -e "Total Coverage: ${GREEN}${percent}%${NC} (${covered}/${instrumented} lines)"
			fi

			echo ""
			echo "View detailed HTML report: ${COVERAGE_DIR}/index.html"
			echo ""
		fi
	# Fallback to JSON format (older kcov versions)
	elif [[ -f "$json_report" ]]; then
		# Try to parse JSON if jq is available
		if command -v jq >/dev/null 2>&1; then
			echo -e "${BLUE}Coverage Summary:${NC}"
			echo "=================="

			# Extract coverage percentages
			local total_coverage
			total_coverage=$(jq -r '.merged_percent_covered' "$json_report" 2>/dev/null || echo "N/A")

			if [[ "$total_coverage" != "N/A" ]] && [[ "$total_coverage" != "null" ]]; then
				echo -e "Total Coverage: ${GREEN}${total_coverage}%${NC}"
			fi

			echo ""
			echo "Detailed coverage by file:"
			# Extract file coverage, handling empty results gracefully
			local file_coverage
			file_coverage=$(jq -r '.files[] | "\(.file): \(.percent_covered)%"' "$json_report" 2>/dev/null || echo "")
			if [[ -n "$file_coverage" ]]; then
				while IFS= read -r line; do
					[[ -n "$line" ]] && echo "  $line"
				done <<<"$file_coverage"
			else
				echo "  (No file coverage data available)"
			fi

			echo ""
		else
			echo -e "${YELLOW}Note: Install 'jq' for detailed coverage summary${NC}"
			echo "View full report: ${COVERAGE_DIR}/index.html"
			echo ""
		fi
	fi
}

# Parse command line arguments
#
# Parses command-line arguments and sets corresponding global flags.
# Handles --coverage, --slow, --all, --failed, --jobs, --filter-tags, --individual, --resume, --sequential, --help.
#
# Arguments:
#   $@: Command-line arguments
#
# Returns:
#   0: Arguments parsed successfully
#   1: Invalid arguments (exits script)
#
parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--coverage | -c)
			COVERAGE_ENABLED=1
			shift
			;;
		--slow | -s)
			RUN_SLOW_TESTS=1
			shift
			;;
		--all | -a)
			FAST_FAIL=0
			shift
			;;
		--failed | -f)
			RERUN_FAILED=1
			shift
			;;
		--jobs | -j)
			if [[ -z "${2:-}" ]]; then
				echo -e "${RED}Error: --jobs requires a value${NC}" >&2
				echo "Use --jobs auto, --jobs 4, or --jobs 0 to disable" >&2
				exit 1
			fi
			# Validate the value is either "auto", "0", or a positive integer
			if [[ "$2" != "auto" ]] && [[ "$2" != "0" ]] && ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
				echo -e "${RED}Error: --jobs must be 'auto', '0', or a positive integer${NC}" >&2
				echo "Got: $2" >&2
				exit 1
			fi
			PARALLEL_JOBS="$2"
			shift 2
			;;
		--filter-tags | -t)
			if [[ -z "${2:-}" ]]; then
				echo -e "${RED}Error: --filter-tags requires a value${NC}" >&2
				echo "Use --filter-tags category:unit or --filter-tags priority:high" >&2
				exit 1
			fi
			FILTER_TAGS="$2"
			shift 2
			;;
		--individual | -i)
			INDIVIDUAL_MODE=1
			shift
			;;
		--resume | -r)
			RESUME_MODE=1
			INDIVIDUAL_MODE=1 # Resume only works in individual mode
			shift
			;;
		--sequential)
			PARALLEL_JOBS=0
			shift
			;;
		--help | -h)
			show_help
			exit 0
			;;
		*)
			echo -e "${RED}Unknown option: $1${NC}" >&2
			echo "Use --help for usage information" >&2
			exit 1
			;;
		esac
	done
}

# Show help message
#
# Displays comprehensive help message with usage information, options, and examples.
#
# Arguments:
#   None
#
# Returns:
#   None (outputs help message to stdout)
#
show_help() {
	cat <<EOF
UDM VPN Monitor Test Runner

Usage: $0 [OPTIONS]

Options:
    --coverage, -c         Enable test coverage reporting (requires kcov)
    --slow, -s             Include slow tests (integration and high-risk tests)
    --all, -a              Run all tests even if some fail (disables fast-fail)
    --failed, -f           Rerun only failed tests from the last completed run
    --jobs, -j <N>         Number of parallel jobs (auto, 0=disabled, or number)
                           Default: auto (batch/parallel execution if parallel tool available)
    --sequential           Run tests sequentially (disable parallel execution)
    --filter-tags, -t <T>  Filter tests by tags (e.g., category:unit, priority:high)
                           Supports multiple tags: category:integration,priority:high
    --individual, -i       Run each test case individually with detailed per-test output
                           Results saved to logs/test_results_TIMESTAMP.txt
    --resume, -r           Resume tests from last checkpoint (only works in individual mode)
                           Skips tests that already passed in the checkpoint
    --help, -h             Show this help message

Examples:
    $0                              Run fast tests only in batch/parallel mode (default)
    $0 --slow                       Run all tests including slow tests in batch/parallel mode
    $0 --sequential                 Run tests sequentially (disable parallel execution)
    $0 --coverage                   Run fast tests with coverage reporting in batch/parallel mode
    $0 --slow --coverage            Run all tests with coverage reporting in batch/parallel mode
    $0 --all                        Run all tests even if some fail (same as default)
    $0 --failed                     Rerun only tests that failed in the last run
    $0 --slow --failed              Rerun only failed tests from last run (includes slow tests)
    $0 --jobs 8                     Run tests with 8 parallel jobs (requires GNU parallel)
    $0 --jobs auto                  Auto-detect CPU cores for parallel execution (default)
    $0 --jobs 0                     Disable parallel execution (run sequentially)
    $0 --sequential                 Run tests sequentially (same as --jobs 0)
    $0 --filter-tags category:unit  Run only unit tests
    $0 --filter-tags priority:high  Run only high-priority tests
    $0 --filter-tags category:integration,priority:high  Run integration tests with high priority
    $0 --individual                Run each test case individually with detailed output
    $0 --individual --slow         Run all tests individually including slow tests
    $0 --individual --resume       Resume tests from checkpoint (skips already passed tests)
    $0 --individual --resume --slow Resume all tests including slow tests from checkpoint

Test Behavior:
    By default, tests run all tests regardless of failures (fast-fail disabled).
    Tests run in batch/parallel mode by default if GNU parallel or rush is available.
    Use --sequential or --jobs 0 to run tests sequentially.
    Tests that exceed 2 minutes (120 seconds) will be skipped automatically.
    Use --all flag or set FAST_FAIL=0 to run all tests regardless of failures (default).
    
    Slow tests (test_integration.sh and high-risk test files: test_config.sh, test_lockfile.sh,
    test_detection.sh, test_recovery.sh, test_state.sh, test_logging.sh, test_connection.sh,
    test_errors.sh, test_main.sh) are excluded by default.
    Use --slow flag or set RUN_SLOW_TESTS=1 to include them.
    
    Test timeout is set to 120 seconds (2 minutes) by default. Tests exceeding this
    timeout will be skipped. Set TEST_TIMEOUT environment variable to change.

Individual Mode:
    Use --individual to run each test case separately with detailed per-test output.
    This mode provides:
    - Per-test timing information
    - Detailed results saved to logs/test_results_TIMESTAMP.txt
    - Clear pass/fail/timeout status for each test
    - Useful for debugging specific test failures
    
    Individual mode runs tests sequentially (parallel execution is disabled).
    Coverage reporting is supported in individual mode.

Coverage Reporting:
    Coverage reports are generated in HTML format in the 'coverage' directory.
    Requires kcov to be installed. See installation instructions when running
    with --coverage if kcov is not found.

Parallel Execution:
    By default, tests run in batch/parallel mode (auto-detect CPU cores) if GNU parallel
    or rush is available. This significantly reduces test execution time (often 3-4x faster
    on multi-core systems).
    
    Parallel execution requires GNU parallel or rush to be installed. If not available,
    tests will automatically fall back to sequential execution.
    
    Use --sequential or --jobs 0 to disable parallel execution and run sequentially.
    Set PARALLEL_JOBS=auto to auto-detect CPU cores (default).
    Set PARALLEL_JOBS=N to use a specific number of jobs.

Test Tag Filtering:
    Tests can be filtered by tags using --filter-tags option. Tags are defined in test
    files using the format: # bats test_tags=category:unit,priority:high
    
    Available categories:
    - category:unit - Unit tests (fast tests)
    - category:integration - Integration tests
    - category:high-risk - High-risk edge case tests
    
    Available priorities:
    - priority:high - High-priority critical tests
    
    Examples:
    - Run only unit tests: --filter-tags category:unit
    - Run only high-priority tests: --filter-tags priority:high
    - Run integration tests with high priority: --filter-tags category:integration,priority:high
    - Multiple tags can be combined with commas

Test Timeout:
    Tests that exceed 2 minutes (120 seconds) will be automatically skipped.
    This prevents slow or hanging tests from blocking test execution.
    Set TEST_TIMEOUT environment variable to change the timeout (in seconds).

Performance Tips:
    - Install GNU parallel for faster test execution: brew install parallel
    - Tests run in batch/parallel mode by default (auto-detect CPU cores)
    - Use --sequential to run tests sequentially if needed
    - Parallel execution works best with fast tests (exclude slow tests locally)
    - Coverage reporting may be slower with parallel execution due to kcov overhead

EOF
}

# Main execution
#
# Main entry point for the test runner script.
# Initializes environment, checks dependencies, and runs tests.
#
# Arguments:
#   $@: Command-line arguments (passed to parse_args)
#
# Returns:
#   0: All tests passed
#   1: One or more tests failed or errors occurred (exits script)
#
main() {
	parse_args "$@"

	echo -e "${GREEN}UDM VPN Monitor Test Suite${NC}"
	echo "=========================="
	echo ""

	check_bats
	check_bats_helpers

	# Check coverage tools if coverage is enabled
	if [[ "$COVERAGE_ENABLED" -eq 1 ]]; then
		check_coverage_tools || true # Don't exit if kcov not found, just disable coverage
	fi

	echo -e "${GREEN}Starting tests...${NC}"
	if [[ "$INDIVIDUAL_MODE" -eq 1 ]]; then
		echo -e "${BLUE}Individual mode: enabled (running each test case separately)${NC}"
	fi
	if [[ "$COVERAGE_ENABLED" -eq 1 ]]; then
		echo -e "${BLUE}Coverage reporting: enabled${NC}"
	fi
	if [[ "$FAST_FAIL" -eq 1 ]]; then
		echo -e "${BLUE}Fast-fail: enabled (stop on first failure)${NC}"
	else
		echo -e "${BLUE}Fast-fail: disabled (run all tests)${NC}"
	fi

	# Check parallel execution status (disabled in individual mode)
	if [[ "$INDIVIDUAL_MODE" -eq 0 ]]; then
		local num_jobs
		num_jobs=$(get_parallel_jobs)
		if [[ "$num_jobs" != "0" ]] && check_parallel_tool; then
			echo -e "${BLUE}Parallel execution: enabled (${num_jobs} jobs using ${PARALLEL_TOOL})${NC}"
		elif [[ "$num_jobs" != "0" ]]; then
			echo -e "${YELLOW}Parallel execution: disabled (parallel tool not found)${NC}"
			echo -e "${YELLOW}Install GNU parallel for faster test execution: brew install parallel${NC}"
		else
			echo -e "${BLUE}Parallel execution: disabled${NC}"
		fi
	else
		echo -e "${BLUE}Parallel execution: disabled (not available in individual mode)${NC}"
	fi
	echo -e "${BLUE}Test timeout: ${TEST_TIMEOUT}s (tests exceeding this will be skipped)${NC}"
	echo ""

	run_tests
}

# Run main
main "$@"
