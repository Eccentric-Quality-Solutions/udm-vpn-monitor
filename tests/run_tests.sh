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
# Set RUN_ALL_TESTS=1 or use --all flag to disable fast-fail
FAST_FAIL="${FAST_FAIL:-1}"

# Rerun failed tests only
# Set RERUN_FAILED=1 or use --failed flag to rerun only failed tests from last run
RERUN_FAILED="${RERUN_FAILED:-0}"

# Parallel execution settings
# Number of parallel jobs (0 = disabled, auto = detect CPU cores, or specific number)
# Set PARALLEL_JOBS=auto to auto-detect, or a number like 4, 8, etc.
PARALLEL_JOBS="${PARALLEL_JOBS:-auto}"
PARALLEL_TOOL=""

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
	echo ""

	cd "$PROJECT_ROOT"

	# Run with coverage if enabled
	if [[ "$COVERAGE_ENABLED" -eq 1 ]] && [[ -n "$COVERAGE_TOOL" ]]; then
		run_tests_with_coverage "${test_files[@]}"
	else
		# Run without coverage
		local bats_args=("${test_files[@]}")
		if [[ "$FAST_FAIL" -eq 1 ]]; then
			bats_args+=(--abort)
		fi
		# Add filter for failed tests if rerun-failed is enabled
		if [[ "$RERUN_FAILED" -eq 1 ]]; then
			bats_args+=(--filter-status "failed")
			echo -e "${BLUE}Rerunning only failed tests from last run...${NC}"
		fi

		# Add parallel execution if enabled and tool is available
		local num_jobs
		num_jobs=$(get_parallel_jobs)
		if [[ "$num_jobs" != "0" ]] && check_parallel_tool; then
			bats_args+=(--jobs "$num_jobs")
			echo -e "${BLUE}Parallel execution: enabled (${num_jobs} jobs using ${PARALLEL_TOOL})${NC}"
		elif [[ "$num_jobs" != "0" ]]; then
			echo -e "${YELLOW}Parallel execution: disabled (parallel tool not found)${NC}"
			echo -e "${YELLOW}Install GNU parallel for faster test execution${NC}"
		fi

		# Use stdbuf to disable output buffering for real-time streaming
		# -oL: line buffered stdout, -eL: line buffered stderr
		# -i0: unbuffered stdin (not needed but doesn't hurt)
		# This ensures test output appears immediately as tests run
		if command -v stdbuf >/dev/null 2>&1; then
			# Force unbuffered output for both stdout and stderr
			# Use exec to replace current process to avoid subprocess buffering
			exec stdbuf -oL -eL -i0 bats "${bats_args[@]}"
		else
			# Fallback: use unbuffer if available (expect package)
			if command -v unbuffer >/dev/null 2>&1; then
				exec unbuffer bats "${bats_args[@]}"
			else
				# Last resort: run bats directly (may be buffered)
				# Note: Output may not stream in real-time without stdbuf/unbuffer
				exec bats "${bats_args[@]}"
			fi
		fi
	fi
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

	# Run kcov with bats
	# kcov will trace all bash scripts executed by bats
	# Note: kcov may exit with non-zero if bats tests fail, which is expected
	# We check if coverage reports were generated rather than relying on exit code
	local bats_args=("${test_files[@]}")
	if [[ "$FAST_FAIL" -eq 1 ]]; then
		bats_args+=(--abort)
	fi
	# Add filter for failed tests if rerun-failed is enabled
	if [[ "$RERUN_FAILED" -eq 1 ]]; then
		bats_args+=(--filter-status "failed")
		echo -e "${BLUE}Rerunning only failed tests from last run...${NC}"
	fi

	# Note: Parallel execution with coverage can be slower due to kcov overhead
	# but is still supported if desired
	local num_jobs
	num_jobs=$(get_parallel_jobs)
	if [[ "$num_jobs" != "0" ]] && check_parallel_tool; then
		bats_args+=(--jobs "$num_jobs")
		echo -e "${BLUE}Parallel execution: enabled (${num_jobs} jobs using ${PARALLEL_TOOL})${NC}"
		echo -e "${YELLOW}Note: Coverage reporting may be slower with parallel execution${NC}"
	fi

	# Use stdbuf to disable output buffering for real-time streaming
	# -oL: line buffered stdout, -eL: line buffered stderr
	# -i0: unbuffered stdin
	if command -v stdbuf >/dev/null 2>&1; then
		kcov "${kcov_args[@]}" "$COVERAGE_DIR" stdbuf -oL -eL -i0 bats "${bats_args[@]}" || true
	else
		# Fallback: use unbuffer if available
		if command -v unbuffer >/dev/null 2>&1; then
			kcov "${kcov_args[@]}" "$COVERAGE_DIR" unbuffer bats "${bats_args[@]}" || true
		else
			kcov "${kcov_args[@]}" "$COVERAGE_DIR" bats "${bats_args[@]}" || true
		fi
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
                      Default: auto (detects CPU cores, requires GNU parallel)
    --help, -h        Show this help message

Examples:
    $0                    Run fast tests only, stop on first failure (default)
    $0 --slow             Run all tests including slow tests, stop on first failure
    $0 --coverage         Run fast tests with coverage reporting, stop on first failure
    $0 --slow --coverage  Run all tests with coverage reporting, stop on first failure
    $0 --all              Run all tests even if some fail (useful for CI)
    $0 --failed           Rerun only tests that failed in the last run
    $0 --slow --failed    Rerun only failed tests from last run (includes slow tests)
    $0 --jobs 8           Run tests with 8 parallel jobs (requires GNU parallel)
    $0 --jobs auto        Auto-detect CPU cores for parallel execution (default)
    $0 --jobs 0           Disable parallel execution (run sequentially)

Test Behavior:
    By default, tests stop on first failure (fast-fail enabled) to speed up debugging.
    Use --all flag or set FAST_FAIL=0 to run all tests regardless of failures.
    
    Slow tests (test_integration.sh and test_high_risk.sh) are excluded by default.
    Use --slow flag or set RUN_SLOW_TESTS=1 to include them.
    
    In CI/CD, set RUN_SLOW_TESTS=1 and FAST_FAIL=0 to run all tests.

Coverage Reporting:
    Coverage reports are generated in HTML format in the 'coverage' directory.
    Requires kcov to be installed. See installation instructions when running
    with --coverage if kcov is not found.

Parallel Execution:
    By default, parallel execution is enabled (auto-detects CPU cores) if GNU
    parallel or rush is installed. This can significantly reduce test execution
    time (often 3-4x faster on multi-core systems).
    
    Parallel execution requires GNU parallel or rush to be installed. If not
    available, tests will run sequentially.
    
    Set PARALLEL_JOBS=0 to disable parallel execution, or use --jobs 0.
    Set PARALLEL_JOBS=auto (default) to auto-detect CPU cores.
    Set PARALLEL_JOBS=N to use a specific number of jobs.

Performance Tips:
    - Install GNU parallel for faster test execution: brew install parallel
    - Use --jobs auto (default) to utilize all CPU cores
    - Parallel execution works best with fast tests (exclude slow tests locally)
    - Coverage reporting may be slower with parallel execution due to kcov overhead

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
		echo -e "${BLUE}Coverage reporting: ${COVERAGE_ENABLED}${NC}"
	fi
	if [[ "$FAST_FAIL" -eq 1 ]]; then
		echo -e "${BLUE}Fast-fail: enabled (stop on first failure)${NC}"
	else
		echo -e "${YELLOW}Fast-fail: disabled (run all tests)${NC}"
	fi

	# Check parallel execution status
	local num_jobs
	num_jobs=$(get_parallel_jobs)
	if [[ "$num_jobs" != "0" ]] && check_parallel_tool; then
		echo -e "${BLUE}Parallel execution: enabled (${num_jobs} jobs using ${PARALLEL_TOOL})${NC}"
	elif [[ "$num_jobs" != "0" ]]; then
		echo -e "${YELLOW}Parallel execution: disabled (parallel tool not found)${NC}"
		echo -e "${YELLOW}Install GNU parallel for faster test execution: brew install parallel${NC}"
	fi
	echo ""

	run_tests
}

# Run main
main "$@"
