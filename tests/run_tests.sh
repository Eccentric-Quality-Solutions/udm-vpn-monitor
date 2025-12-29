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

# Test tag filtering settings
# Filter tests by tags (e.g., "category:unit", "priority:high", "category:integration,priority:high")
# Set FILTER_TAGS to filter tests by tags using bats --filter-tags
FILTER_TAGS="${FILTER_TAGS:-}"

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

# Run tests sequentially (without coverage)
run_tests_sequential() {
	local test_files=("$@")
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
	parallel_test_runner() {
		local test_file="$1"
		local test_name
		test_name=$(basename "$test_file")
		echo -e "${BLUE}Running: ${test_name}${NC}" >&2

		run_test_file_with_timeout "$test_file" "$TEST_TIMEOUT"
		local test_result=$?

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
	if [[ -n "$FILTER_TAGS" ]]; then
		echo -e "${BLUE}Filtering tests by tags: ${FILTER_TAGS}${NC}"
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
run_tests_sequential_with_coverage() {
	local coverage_dir="$1"
	shift
	# kcov_args are always exactly 6 arguments: --include-path and 5 --exclude-path args
	local kcov_args=("$1" "$2" "$3" "$4" "$5" "$6")
	shift 6
	# Remaining arguments are test files
	local test_files=("$@")

	local failed_tests=0
	local timed_out_tests=0

	for test_file in "${test_files[@]}"; do
		echo -e "${BLUE}Running with coverage: $(basename "$test_file")${NC}"

		# Run test file with per-test timeout and coverage
		run_test_file_with_timeout "$test_file" "$TEST_TIMEOUT" "1" "$coverage_dir" "${kcov_args[@]}"
		local test_result=$?

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
run_tests_parallel_with_coverage() {
	local num_jobs="$1"
	local coverage_dir="$2"
	shift 2
	# kcov_args are always exactly 6 arguments: --include-path and 5 --exclude-path args
	local kcov_args=("$1" "$2" "$3" "$4" "$5" "$6")
	shift 6
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
	export TEST_TIMEOUT
	export RERUN_FAILED
	export FILTER_TAGS
	export PROJECT_ROOT
	export COVERAGE_DIR="$coverage_dir"

	# Create a function that parallel can call
	parallel_test_runner_with_coverage() {
		local test_file="$1"
		local test_name
		test_name=$(basename "$test_file")
		echo -e "${BLUE}Running with coverage: ${test_name}${NC}" >&2

		# Reconstruct kcov_args array (bash limitation with parallel)
		local kcov_args_array=(
			"--include-path=${PROJECT_ROOT}"
			"--exclude-path=${PROJECT_ROOT}/tests"
			"--exclude-path=${PROJECT_ROOT}/coverage"
			"--exclude-path=${PROJECT_ROOT}/.git"
			"--exclude-path=/usr"
			"--exclude-path=/tmp"
		)

		run_test_file_with_timeout "$test_file" "$TEST_TIMEOUT" "1" "$COVERAGE_DIR" "${kcov_args_array[@]}"
		local test_result=$?

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
		--filter-tags | -t)
			if [[ -z "${2:-}" ]]; then
				echo -e "${RED}Error: --filter-tags requires a value${NC}" >&2
				echo "Use --filter-tags category:unit or --filter-tags priority:high" >&2
				exit 1
			fi
			FILTER_TAGS="$2"
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
    --coverage, -c         Enable test coverage reporting (requires kcov)
    --slow, -s             Include slow tests (integration and high-risk tests)
    --all, -a              Run all tests even if some fail (disables fast-fail)
    --failed, -f           Rerun only failed tests from the last completed run
    --jobs, -j <N>         Number of parallel jobs (auto, 0=disabled, or number)
                           Default: 0 (sequential execution, no parallelization)
    --filter-tags, -t <T>  Filter tests by tags (e.g., category:unit, priority:high)
                           Supports multiple tags: category:integration,priority:high
    --help, -h             Show this help message

Examples:
    $0                              Run fast tests only, run all tests (no fast-fail), sequential
    $0 --slow                       Run all tests including slow tests, sequential, no fast-fail
    $0 --coverage                   Run fast tests with coverage reporting, sequential, no fast-fail
    $0 --slow --coverage            Run all tests with coverage reporting, sequential, no fast-fail
    $0 --all                        Run all tests even if some fail (same as default)
    $0 --failed                     Rerun only tests that failed in the last run
    $0 --slow --failed              Rerun only failed tests from last run (includes slow tests)
    $0 --jobs 8                     Run tests with 8 parallel jobs (requires GNU parallel)
    $0 --jobs auto                  Auto-detect CPU cores for parallel execution
    $0 --jobs 0                     Disable parallel execution (run sequentially, default)
    $0 --filter-tags category:unit  Run only unit tests
    $0 --filter-tags priority:high  Run only high-priority tests
    $0 --filter-tags category:integration,priority:high  Run integration tests with high priority

Test Behavior:
    By default, tests run all tests regardless of failures (fast-fail disabled).
    Tests run sequentially (no parallelization) to ensure output streams properly.
    Tests that exceed 2 minutes (120 seconds) will be skipped automatically.
    Use --all flag or set FAST_FAIL=0 to run all tests regardless of failures (default).
    
    Slow tests (test_integration.sh and high-risk test files: test_config.sh, test_lockfile.sh,
    test_detection.sh, test_recovery.sh, test_state.sh, test_logging.sh, test_connection.sh,
    test_errors.sh, test_main.sh) are excluded by default.
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
