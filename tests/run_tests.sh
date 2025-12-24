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
# Stop on first failure by default (fast-fail enabled)
# Set FAST_FAIL=0 or use --all flag to disable fast-fail
FAST_FAIL="${FAST_FAIL:-0}"

# Rerun failed tests only
# Set RERUN_FAILED=1 or use --failed flag to rerun only failed tests from last run
RERUN_FAILED="${RERUN_FAILED:-0}"

# Parallel execution settings
# Number of parallel jobs (0 = disabled, auto = detect CPU cores, or specific number)
# Set PARALLEL_JOBS=0 to disable, auto to auto-detect, or a number like 4, 8, etc.
PARALLEL_JOBS="${PARALLEL_JOBS:-0}"
PARALLEL_TOOL=""

# Test timeout settings
# Timeout for individual tests in seconds (default: 120 seconds = 2 minutes)
# Tests that exceed this timeout will be skipped
TEST_TIMEOUT="${TEST_TIMEOUT:-120}"

# Show bats installation instructions
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
check_kcov() {
	if command -v kcov >/dev/null 2>&1; then
		COVERAGE_TOOL="kcov"
		return 0
	fi

	return 1
}

# Detect number of CPU cores
detect_cpu_cores() {
	# Try nproc first (Linux)
	if command -v nproc >/dev/null 2>&1; then
		nproc 2>/dev/null || echo "4"
	# Try sysctl (macOS/BSD)
	elif command -v sysctl >/dev/null 2>&1; then
		sysctl -n hw.ncpu 2>/dev/null || echo "4"
	# Fallback to default
	else
		echo "4"
	fi
}

# Check for parallel execution tools (GNU parallel or rush)
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
# Outputs filtered file list to stdout (one per line)
filter_test_files() {
	local test_files=("${SCRIPT_DIR}"/test_*.sh)

	for test_file in "${test_files[@]}"; do
		local filename
		filename=$(basename "$test_file")

		# Check if this is a slow test file
		# Slow tests are: test_integration.sh and test_high_risk.sh
		if [[ "$filename" == "test_integration.sh" ]] || [[ "$filename" == "test_high_risk.sh" ]]; then
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
# Outputs test names (one per line) matching @test declarations
extract_test_names() {
	local test_file="$1"
	# Extract test names from @test declarations
	# Pattern: @test "test name" { or @test 'test name' {
	# Handle both single and double quotes, and multi-line declarations
	grep -E "^@test\s+[\"']" "$test_file" 2>/dev/null | sed -E "s/^@test\s+[\"']([^\"']+)[\"'].*/\1/" || true
}

# Escape special regex characters in test name for bats filter
escape_test_name_for_filter() {
	local test_name="$1"
	# Escape special regex characters: . [ ] { } ( ) + * ? ^ $ | \
	# Using sed is appropriate here as we need proper regex escaping
	# shellcheck disable=SC2001
	echo "$test_name" | sed 's/[.[{}()*+?^$|\\]/\\&/g'
}

# Run a single test case with timeout
# Runs an individual test by name with timeout, skipping if it exceeds the limit
# Returns: 0 on success, 1 on test failure, 2 on timeout (caller should handle)
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
	local bats_args=("$test_file" "-f" "^${escaped_name}$")

	# Add filter for failed tests if rerun-failed is enabled
	if [[ "$RERUN_FAILED" -eq 1 ]]; then
		bats_args+=(--filter-status "failed")
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
		if command -v stdbuf >/dev/null 2>&1; then
			timeout --preserve-status "$timeout_seconds" stdbuf -oL -eL -i0 kcov "${kcov_args[@]}" "$coverage_dir" bats "${bats_args[@]}" 2>&1 || exit_code=$?
		else
			timeout --preserve-status "$timeout_seconds" kcov "${kcov_args[@]}" "$coverage_dir" bats "${bats_args[@]}" 2>&1 || exit_code=$?
		fi
	else
		# Run without coverage, with timeout
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
	else
		# Other exit codes are test failures
		return 1
	fi
}

# Run a single test file with per-test timeout
# Extracts individual tests and runs each with timeout
# Returns: 0 if all tests passed, 1 if any failed, 2 if any timed out
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

# Run tests with coverage if enabled
run_tests() {
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
	if [[ "$FAST_FAIL" -eq 0 ]]; then
		echo -e "${BLUE}Fast-fail: disabled (will run all tests)${NC}"
	fi
	if [[ "$PARALLEL_JOBS" == "0" ]]; then
		echo -e "${BLUE}Parallel execution: disabled${NC}"
	fi
	echo -e "${BLUE}Test timeout: ${TEST_TIMEOUT}s (tests exceeding this will be skipped)${NC}"
	echo ""

	cd "$PROJECT_ROOT"

	# Run with coverage if enabled
	if [[ "$COVERAGE_ENABLED" -eq 1 ]] && [[ -n "$COVERAGE_TOOL" ]]; then
		run_tests_with_coverage "${test_files[@]}"
	else
		# Run without coverage
		# Run each test file individually with timeout to ensure tests that exceed 2m are skipped
		local failed_tests=0
		local timed_out_tests=0

		for test_file in "${test_files[@]}"; do
			echo -e "${BLUE}Running: $(basename "$test_file")${NC}"

			# Run test file with timeout wrapper
			run_test_file_with_timeout "$test_file" "$TEST_TIMEOUT"
			local test_result=$?

			if [[ $test_result -eq 2 ]]; then
				# Timeout occurred
				timed_out_tests=$((timed_out_tests + 1))
			elif [[ $test_result -ne 0 ]]; then
				# Test failure
				failed_tests=$((failed_tests + 1))
				# If fast-fail is enabled, stop on first failure
				if [[ "$FAST_FAIL" -eq 1 ]]; then
					echo -e "${RED}Fast-fail enabled: stopping test execution${NC}" >&2
					exit 1
				fi
			fi
			echo ""
		done

		# Print summary
		echo -e "${GREEN}Test execution complete${NC}"
		if [[ $failed_tests -gt 0 ]]; then
			echo -e "${YELLOW}Failed test files: $failed_tests${NC}"
		fi
		if [[ $timed_out_tests -gt 0 ]]; then
			echo -e "${YELLOW}Timed out test files: $timed_out_tests${NC}"
		fi

		# Exit with error if any tests failed (unless we're in non-fast-fail mode and want to continue)
		if [[ $failed_tests -gt 0 ]] && [[ "$FAST_FAIL" -eq 1 ]]; then
			exit 1
		fi
	fi
}

# Note: run_test_file_with_coverage_timeout() has been removed.
# Coverage is now handled by run_test_file_with_timeout() with use_coverage flag.
# This ensures consistent per-test timeout behavior for both coverage and non-coverage runs.

# Run tests with kcov coverage
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
	local kcov_args=(
		"--include-path=${PROJECT_ROOT}"
		"--exclude-path=${PROJECT_ROOT}/tests"
		"--exclude-path=${PROJECT_ROOT}/coverage"
		"--exclude-path=${PROJECT_ROOT}/.git"
		"--exclude-path=/usr"
		"--exclude-path=/tmp"
	)

	# Add filter for failed tests if rerun-failed is enabled
	if [[ "$RERUN_FAILED" -eq 1 ]]; then
		echo -e "${BLUE}Rerunning only failed tests from last run...${NC}"
	fi

	# Run each test file individually with timeout and coverage
	# This ensures tests that exceed timeout are skipped and output streams properly
	local failed_tests=0
	local timed_out_tests=0

	for test_file in "${test_files[@]}"; do
		echo -e "${BLUE}Running with coverage: $(basename "$test_file")${NC}"

		# Run test file with per-test timeout and coverage
		run_test_file_with_timeout "$test_file" "$TEST_TIMEOUT" "1" "$COVERAGE_DIR" "${kcov_args[@]}"
		local test_result=$?

		if [[ $test_result -eq 2 ]]; then
			# Timeout occurred
			timed_out_tests=$((timed_out_tests + 1))
			# If fast-fail is enabled, stop on first timeout
			if [[ "$FAST_FAIL" -eq 1 ]]; then
				echo -e "${RED}Fast-fail enabled: stopping test execution${NC}" >&2
				break
			fi
		elif [[ $test_result -ne 0 ]]; then
			# Test failure
			failed_tests=$((failed_tests + 1))
			# If fast-fail is enabled, stop on first failure
			if [[ "$FAST_FAIL" -eq 1 ]]; then
				echo -e "${RED}Fast-fail enabled: stopping test execution${NC}" >&2
				break
			fi
		fi
		echo ""
	done

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
}

# Print coverage summary from kcov report
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
show_help() {
	cat <<EOF
UDM VPN Monitor Test Runner

Usage: $0 [OPTIONS]

Options:
    --coverage, -c    Enable test coverage reporting (requires kcov)
    --slow, -s        Include slow tests (integration and high-risk tests)
    --all, -a         Run all tests even if some fail (disables fast-fail)
    --failed, -f      Rerun only failed tests from the last completed run
    --jobs, -j <N>    Number of parallel jobs (auto, 0=disabled, or number)
                      Default: 0 (sequential execution, no parallelization)
    --help, -h        Show this help message

Examples:
    $0                    Run fast tests only, run all tests (no fast-fail), sequential
    $0 --slow             Run all tests including slow tests, sequential, no fast-fail
    $0 --coverage         Run fast tests with coverage reporting, sequential, no fast-fail
    $0 --slow --coverage  Run all tests with coverage reporting, sequential, no fast-fail
    $0 --all              Run all tests even if some fail (same as default)
    $0 --failed           Rerun only tests that failed in the last run
    $0 --slow --failed    Rerun only failed tests from last run (includes slow tests)
    $0 --jobs 8           Run tests with 8 parallel jobs (requires GNU parallel)
    $0 --jobs auto        Auto-detect CPU cores for parallel execution
    $0 --jobs 0           Disable parallel execution (run sequentially, default)

Test Behavior:
    By default, tests run all tests regardless of failures (fast-fail disabled).
    Tests run sequentially (no parallelization) to ensure output streams properly.
    Tests that exceed 2 minutes (120 seconds) will be skipped automatically.
    Use --all flag or set FAST_FAIL=0 to run all tests regardless of failures (default).
    
    Slow tests (test_integration.sh and test_high_risk.sh) are excluded by default.
    Use --slow flag or set RUN_SLOW_TESTS=1 to include them.
    
    Test timeout is set to 120 seconds (2 minutes) by default. Tests exceeding this
    timeout will be skipped. Set TEST_TIMEOUT environment variable to change.

Coverage Reporting:
    Coverage reports are generated in HTML format in the 'coverage' directory.
    Requires kcov to be installed. See installation instructions when running
    with --coverage if kcov is not found.

Parallel Execution:
    By default, parallel execution is disabled (sequential execution) to ensure
    output streams properly to the terminal. Parallel execution can significantly
    reduce test execution time (often 3-4x faster on multi-core systems).
    
    Parallel execution requires GNU parallel or rush to be installed. If not
    available, tests will run sequentially.
    
    Set PARALLEL_JOBS=0 to disable parallel execution (default), or use --jobs 0.
    Set PARALLEL_JOBS=auto to auto-detect CPU cores.
    Set PARALLEL_JOBS=N to use a specific number of jobs.

Test Timeout:
    Tests that exceed 2 minutes (120 seconds) will be automatically skipped.
    This prevents slow or hanging tests from blocking test execution.
    Set TEST_TIMEOUT environment variable to change the timeout (in seconds).

Performance Tips:
    - Install GNU parallel for faster test execution: brew install parallel
    - Use --jobs auto to utilize all CPU cores (disabled by default for streaming output)
    - Parallel execution works best with fast tests (exclude slow tests locally)
    - Coverage reporting may be slower with parallel execution due to kcov overhead
    - Tests run sequentially by default to ensure output streams to terminal

EOF
}

# Main execution
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
	if [[ "$COVERAGE_ENABLED" -eq 1 ]]; then
		echo -e "${BLUE}Coverage reporting: enabled${NC}"
	fi
	if [[ "$FAST_FAIL" -eq 1 ]]; then
		echo -e "${BLUE}Fast-fail: enabled (stop on first failure)${NC}"
	else
		echo -e "${BLUE}Fast-fail: disabled (run all tests)${NC}"
	fi

	# Check parallel execution status
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
	echo -e "${BLUE}Test timeout: ${TEST_TIMEOUT}s (tests exceeding this will be skipped)${NC}"
	echo ""

	run_tests
}

# Run main
main "$@"
