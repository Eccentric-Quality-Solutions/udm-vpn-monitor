#!/bin/bash
#
# Flaky Test Detection Script
# Runs tests multiple times and identifies tests that pass inconsistently
# This helps identify unreliable tests that need fixing
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

# Default number of test runs
DEFAULT_RUNS=3
NUM_RUNS="${NUM_RUNS:-${DEFAULT_RUNS}}"

# Minimum number of runs required to detect flakiness
MIN_RUNS=3

# Show help message
show_help() {
	cat <<EOF
Flaky Test Detection Script

Usage: $0 [OPTIONS]

This script runs the test suite multiple times and identifies tests that
pass inconsistently (flaky tests). Tests that pass in some runs but fail in
others are reported as flaky.

Options:
    --runs, -r <N>        Number of test runs to perform (default: ${DEFAULT_RUNS}, minimum: ${MIN_RUNS})
    --slow, -s            Include slow tests in flaky detection
    --help, -h            Show this help message

Environment Variables:
    NUM_RUNS              Number of test runs (overridden by --runs)
    RUN_SLOW_TESTS        Set to 1 to include slow tests

Examples:
    $0                    Run flaky test detection with ${DEFAULT_RUNS} runs (fast tests only)
    $0 --runs 5           Run flaky test detection with 5 runs
    $0 --slow             Include slow tests in flaky detection
    $0 --runs 5 --slow    Run 5 times including slow tests

Output:
    The script will report:
    - Tests that passed in all runs (stable)
    - Tests that failed in all runs (consistently failing)
    - Tests that passed in some runs but failed in others (FLAKY)

    Flaky tests are the main focus as they indicate unreliable tests that
    need fixing.

EOF
}

# Parse command line arguments
#
# Parses command line arguments and sets global variables accordingly.
# Validates argument values and handles errors appropriately.
#
# Arguments:
#   $@: Command line arguments to parse
#
# Returns:
#   0: Success
#   1: Error (invalid argument or missing value)
#
# Side Effects:
#   - Sets NUM_RUNS global variable
#   - Exports RUN_SLOW_TESTS environment variable
#   - May exit with error code 1 on invalid arguments
#   - May exit with code 0 if --help is provided
#
# Examples:
#   parse_args --runs 5 --slow
#   parse_args --help
#
parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--runs | -r)
			if [[ -z "${2:-}" ]]; then
				echo -e "${RED}Error: --runs requires a value${NC}" >&2
				exit 1
			fi
			if ! [[ "$2" =~ ^[1-9][0-9]*$ ]] || [[ "$2" -lt "$MIN_RUNS" ]]; then
				echo -e "${RED}Error: --runs must be at least ${MIN_RUNS}${NC}" >&2
				exit 1
			fi
			NUM_RUNS="$2"
			shift 2
			;;
		--slow | -s)
			export RUN_SLOW_TESTS=1
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

# Extract test results from a test run
#
# Parses the output from run_tests.sh --individual mode and extracts
# test results into a structured format. Identifies PASSED, FAILED, and
# TIMEOUT statuses for each test.
#
# Arguments:
#   $1: results_file - Path to the test run output file
#   $2: output_file - Path where extracted results will be written
#
# Returns:
#   0: Always succeeds (even if no results found)
#
# Side Effects:
#   - Creates or overwrites output_file
#   - Output format: test_id|status (one per line)
#
# Examples:
#   extract_test_results "logs/run_1.txt" "logs/run_1_extracted.txt"
#
# Note:
#   - Expects input format: "PASSED: test_file.sh::test_name (duration)"
#   - Handles lines with leading spaces
#   - Skips lines that don't match the expected format
#
extract_test_results() {
	local results_file="$1"
	local output_file="$2"

	# Clear output file
	: >"$output_file"

	# Parse results file for test results
	# Format: "PASSED: test_file.sh::test_name (duration)"
	# Format: "FAILED: test_file.sh::test_name (duration)"
	# Format: "TIMEOUT: test_file.sh::test_name (duration)"
	# Note: The line may have leading spaces, and there may be "Output:" lines after
	while IFS= read -r line; do
		# Match lines like "PASSED: test_file.sh::test_name (123s)"
		# or "  PASSED: test_file.sh::test_name (123s)" (with leading spaces)
		if [[ "$line" =~ ^[[:space:]]*(PASSED|FAILED|TIMEOUT):[[:space:]]+(.+)[[:space:]]+\([0-9]+s\)$ ]]; then
			local status="${BASH_REMATCH[1]}"
			local test_id="${BASH_REMATCH[2]}"
			# Normalize status to PASSED, FAILED, TIMEOUT
			echo "${test_id}|${status}" >>"$output_file"
		fi
	done <"$results_file"
}

# Run tests once and extract results
#
# Executes the test suite once in individual mode and extracts the results.
# Uses unbuffered output when available to ensure all output is captured.
#
# Arguments:
#   $1: run_number - The current run number (for display purposes)
#   $2: results_dir - Directory where results will be stored
#
# Returns:
#   0: Always succeeds (test failures are captured, not propagated)
#
# Side Effects:
#   - Creates run_<number>.txt with full test output
#   - Creates run_<number>_extracted.txt with parsed results
#   - Prints progress messages to stdout
#   - Runs tests via run_tests.sh --individual
#
# Examples:
#   run_tests_once 1 "logs/flaky_detection_20240101_120000"
#
# Note:
#   - Uses stdbuf if available for unbuffered output
#   - Test failures are captured but don't stop execution
#   - Relies on NUM_RUNS and RUN_SLOW_TESTS global/environment variables
#
run_tests_once() {
	local run_number="$1"
	local results_dir="$2"
	local results_file="${results_dir}/run_${run_number}.txt"

	echo -e "${BLUE}Run ${run_number}/${NUM_RUNS}: Running tests...${NC}"

	# Run tests in individual mode to get per-test results
	# Use unbuffered output to ensure we capture all results
	if command -v stdbuf >/dev/null 2>&1; then
		stdbuf -oL -eL -i0 "${SCRIPT_DIR}/run_tests.sh" --individual >"$results_file" 2>&1 || true
	else
		"${SCRIPT_DIR}/run_tests.sh" --individual >"$results_file" 2>&1 || true
	fi

	# Extract test results from the output
	local extracted_file="${results_dir}/run_${run_number}_extracted.txt"
	extract_test_results "$results_file" "$extracted_file"

	echo -e "${GREEN}Run ${run_number}/${NUM_RUNS}: Complete${NC}"
}

# Analyze test results across all runs
#
# Analyzes test results from multiple runs to identify flaky tests.
# A test is considered flaky if it passes in some runs but fails or times out
# in others. Generates a comprehensive analysis report.
#
# Arguments:
#   $1: results_dir - Directory containing extracted test result files
#
# Returns:
#   0: No flaky tests found
#   1: Flaky tests detected
#
# Side Effects:
#   - Creates flaky_analysis.txt in results_dir with detailed report
#   - Exports FLAKY_TEST_COUNT global variable
#   - Prints summary to stdout with colored output
#
# Examples:
#   analyze_results "logs/flaky_detection_20240101_120000"
#
# Note:
#   - Categorizes tests as: stable passed, stable failed, stable timeout, or flaky
#   - Flaky tests are those with mixed results (some passes, some failures/timeouts)
#   - Relies on NUM_RUNS global variable for reporting
#
analyze_results() {
	local results_dir="$1"
	local output_file="${results_dir}/flaky_analysis.txt"

	# Associative arrays to track test results
	declare -A test_passed_count
	declare -A test_failed_count
	declare -A test_timeout_count
	declare -A test_total_count
	declare -a all_test_ids

	# Collect results from all runs
	for run_file in "${results_dir}"/run_*_extracted.txt; do
		[[ -f "$run_file" ]] || continue

		while IFS='|' read -r test_id status; do
			# Skip empty lines
			[[ -z "$test_id" ]] && continue

			# Track this test ID
			if [[ -z "${test_total_count[$test_id]:-}" ]]; then
				test_total_count["$test_id"]=0
				test_passed_count["$test_id"]=0
				test_failed_count["$test_id"]=0
				test_timeout_count["$test_id"]=0
				all_test_ids+=("$test_id")
			fi

			test_total_count["$test_id"]=$((${test_total_count["$test_id"]} + 1))

			case "$status" in
			PASSED)
				test_passed_count["$test_id"]=$((${test_passed_count["$test_id"]} + 1))
				;;
			FAILED)
				test_failed_count["$test_id"]=$((${test_failed_count["$test_id"]} + 1))
				;;
			TIMEOUT)
				test_timeout_count["$test_id"]=$((${test_timeout_count["$test_id"]} + 1))
				;;
			esac
		done <"$run_file"
	done

	# Categorize tests
	local flaky_tests=()
	local stable_passed_tests=()
	local stable_failed_tests=()
	local stable_timeout_tests=()

	for test_id in "${all_test_ids[@]}"; do
		local passed=${test_passed_count["$test_id"]:-0}
		local failed=${test_failed_count["$test_id"]:-0}
		local timeout=${test_timeout_count["$test_id"]:-0}
		local total=${test_total_count["$test_id"]:-0}

		# A test is flaky if it has both passes and failures/timeouts
		if [[ $passed -gt 0 ]] && { [[ $failed -gt 0 ]] || [[ $timeout -gt 0 ]]; }; then
			flaky_tests+=("$test_id|$passed|$failed|$timeout|$total")
		elif [[ $passed -eq $total ]]; then
			stable_passed_tests+=("$test_id|$total")
		elif [[ $failed -eq $total ]]; then
			stable_failed_tests+=("$test_id|$total")
		elif [[ $timeout -eq $total ]]; then
			stable_timeout_tests+=("$test_id|$total")
		fi
	done

	# Generate analysis report
	{
		echo "Flaky Test Detection Analysis"
		echo "=============================="
		echo "Date: $(date)"
		echo "Number of runs: ${NUM_RUNS}"
		echo "Total tests analyzed: ${#all_test_ids[@]}"
		echo ""
		echo "Summary:"
		echo "--------"
		echo "Stable (passed all runs): ${#stable_passed_tests[@]}"
		echo "Stable (failed all runs): ${#stable_failed_tests[@]}"
		echo "Stable (timeout all runs): ${#stable_timeout_tests[@]}"
		echo "FLAKY (inconsistent results): ${#flaky_tests[@]}"
		echo ""

		if [[ ${#flaky_tests[@]} -gt 0 ]]; then
			echo "═══════════════════════════════════════════════════════════"
			echo "FLAKY TESTS (require attention)"
			echo "═══════════════════════════════════════════════════════════"
			echo ""
			for test_result in "${flaky_tests[@]}"; do
				IFS='|' read -r test_id passed failed timeout total <<<"$test_result"
				echo "  ${test_id}"
				echo "    Passed: ${passed}/${total} | Failed: ${failed}/${total} | Timeout: ${timeout}/${total}"
			done
			echo ""
		fi

		if [[ ${#stable_failed_tests[@]} -gt 0 ]]; then
			echo "Consistently Failing Tests (not flaky, but need fixing):"
			echo "--------------------------------------------------------"
			for test_result in "${stable_failed_tests[@]}"; do
				IFS='|' read -r test_id total <<<"$test_result"
				echo "  ${test_id} (failed ${total}/${NUM_RUNS} runs)"
			done
			echo ""
		fi

		if [[ ${#stable_timeout_tests[@]} -gt 0 ]]; then
			echo "Consistently Timing Out Tests (not flaky, but need fixing):"
			echo "------------------------------------------------------------"
			for test_result in "${stable_timeout_tests[@]}"; do
				IFS='|' read -r test_id total <<<"$test_result"
				echo "  ${test_id} (timed out ${total}/${NUM_RUNS} runs)"
			done
			echo ""
		fi

		if [[ ${#flaky_tests[@]} -eq 0 ]]; then
			echo "✅ No flaky tests detected! All tests are stable."
			echo ""
		fi
	} >"$output_file"

	# Print summary to console
	echo ""
	echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
	echo -e "${GREEN}Flaky Test Detection Summary${NC}"
	echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
	echo "Total tests analyzed: ${#all_test_ids[@]}"
	echo -e "${GREEN}Stable (passed all runs): ${#stable_passed_tests[@]}${NC}"
	if [[ ${#stable_failed_tests[@]} -gt 0 ]]; then
		echo -e "${RED}Stable (failed all runs): ${#stable_failed_tests[@]}${NC}"
	fi
	if [[ ${#stable_timeout_tests[@]} -gt 0 ]]; then
		echo -e "${YELLOW}Stable (timeout all runs): ${#stable_timeout_tests[@]}${NC}"
	fi
	if [[ ${#flaky_tests[@]} -gt 0 ]]; then
		echo -e "${RED}FLAKY (inconsistent results): ${#flaky_tests[@]}${NC}"
		echo ""
		echo -e "${RED}Flaky Tests:${NC}"
		for test_result in "${flaky_tests[@]}"; do
			IFS='|' read -r test_id passed failed timeout total <<<"$test_result"
			echo -e "  ${RED}✗${NC} ${test_id}"
			echo -e "    Passed: ${passed}/${total} | Failed: ${failed}/${total} | Timeout: ${timeout}/${total}"
		done
	else
		echo -e "${GREEN}✅ No flaky tests detected!${NC}"
	fi
	echo ""
	echo "Detailed analysis saved to: ${output_file}"
	echo ""

	# Return flaky test count via global variable for CI
	export FLAKY_TEST_COUNT=${#flaky_tests[@]}

	# Return exit code based on whether flaky tests were found
	if [[ ${#flaky_tests[@]} -gt 0 ]]; then
		return 1
	else
		return 0
	fi
}

# Main execution function
#
# Orchestrates the flaky test detection process by running tests multiple
# times and analyzing the results. Handles argument parsing, test execution,
# and result reporting.
#
# Arguments:
#   $@: Command line arguments (passed to parse_args)
#
# Returns:
#   0: No flaky tests detected
#   1: Flaky tests detected
#
# Side Effects:
#   - Creates results directory in logs/
#   - Runs test suite NUM_RUNS times
#   - Generates analysis report
#   - Sets GITHUB_OUTPUT if running in GitHub Actions
#   - Prints progress and summary to stdout
#
# Examples:
#   main --runs 5 --slow
#   main
#
# Note:
#   - Uses NUM_RUNS and RUN_SLOW_TESTS for configuration
#   - Results directory includes timestamp for uniqueness
#   - Exit code indicates presence of flaky tests
#
main() {
	parse_args "$@"

	echo -e "${GREEN}Flaky Test Detection${NC}"
	echo "======================"
	echo ""
	echo "This will run the test suite ${NUM_RUNS} times to identify flaky tests."
	if [[ "${RUN_SLOW_TESTS:-0}" -eq 1 ]]; then
		echo -e "${BLUE}Slow tests: included${NC}"
	else
		echo -e "${BLUE}Slow tests: excluded (use --slow to include)${NC}"
	fi
	echo ""

	# Create results directory
	local results_dir
	results_dir="${PROJECT_ROOT}/logs/flaky_detection_$(date +%Y%m%d_%H%M%S)"
	mkdir -p "$results_dir"

	# Run tests multiple times
	for ((run = 1; run <= NUM_RUNS; run++)); do
		run_tests_once "$run" "$results_dir"
		echo ""
	done

	# Analyze results
	echo -e "${BLUE}Analyzing results...${NC}"
	analyze_results "$results_dir"
	local exit_code=$?

	# Save summary for CI (always write, even on error, so CI can access outputs)
	if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
		echo "flaky_count=${FLAKY_TEST_COUNT:-0}" >>"$GITHUB_OUTPUT"
		echo "results_dir=${results_dir}" >>"$GITHUB_OUTPUT"
	fi

	return $exit_code
}

# Run main
main "$@"
