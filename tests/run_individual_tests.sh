#!/bin/bash
#
# Run each test case individually with timeout tracking
# Kills tests that exceed 60 seconds and records failures/timeouts
#
# IMPORTANT: When running this script, always stream output in real-time.
# Do NOT pipe to tail, head, or other commands that buffer output.
# Use: ./tests/run_individual_tests.sh
# NOT: ./tests/run_individual_tests.sh | tail
#

set -uo pipefail
# Don't use -e so we can continue on test failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Test timeout in seconds
TEST_TIMEOUT=60

# Results tracking
FAILED_TESTS=()
TIMED_OUT_TESTS=()
PASSED_TESTS=()
TOTAL_TESTS=0
FAILED_COUNT=0
TIMED_OUT_COUNT=0
PASSED_COUNT=0

# Results file
RESULTS_FILE="${PROJECT_ROOT}/test_results_$(date +%Y%m%d_%H%M%S).txt"

# Extract test names from a test file
# Outputs test names (one per line) matching @test declarations
extract_test_names() {
	local test_file="$1"
	# Extract test names from @test declarations
	# Pattern: @test "test name" { or @test 'test name' {
	# Handle both single and double quotes
	grep -E "^@test\s+[\"']" "$test_file" 2>/dev/null | sed -E "s/^@test\s+[\"']([^\"']+)[\"'].*/\1/" || true
}

# Escape special regex characters in test name for bats filter
escape_test_name_for_filter() {
	local test_name="$1"
	# Escape special regex characters: . [ ] { } ( ) + * ? ^ $ | \
	# shellcheck disable=SC2001
	echo "$test_name" | sed 's/[.[{}()*+?^$|\\]/\\&/g'
}

# Run a single test case with timeout
# Returns: 0 on success, 1 on test failure, 2 on timeout
# Output is captured and returned via stdout
run_single_test() {
	local test_file="$1"
	local test_name="$2"
	local timeout_seconds="$3"

	# Escape the test name for regex matching
	local escaped_name
	escaped_name=$(escape_test_name_for_filter "$test_name")
	local bats_args=("$test_file" "-f" "^${escaped_name}$")

	# Check if timeout command is available
	if ! command -v timeout >/dev/null 2>&1; then
		echo -e "${YELLOW}Warning: timeout command not available, running without timeout protection${NC}" >&2
		# Run without timeout
		if command -v stdbuf >/dev/null 2>&1; then
			stdbuf -oL -eL -i0 bats "${bats_args[@]}" 2>&1
			return $?
		else
			bats "${bats_args[@]}" 2>&1
			return $?
		fi
	fi

	# Run test with timeout
	local exit_code=0
	if command -v stdbuf >/dev/null 2>&1; then
		# Use stdbuf for unbuffered output streaming
		timeout --preserve-status "$timeout_seconds" stdbuf -oL -eL -i0 bats "${bats_args[@]}" 2>&1 || exit_code=$?
	else
		# Fallback without stdbuf
		timeout --preserve-status "$timeout_seconds" bats "${bats_args[@]}" 2>&1 || exit_code=$?
	fi

	if [[ $exit_code -eq 124 ]]; then
		# Test timed out
		return 2
	elif [[ $exit_code -eq 0 ]]; then
		return 0
	else
		# Other exit codes are test failures
		return 1
	fi
}

# Main execution
main() {
	cd "$PROJECT_ROOT"

	# Find all test files
	local test_files=("${SCRIPT_DIR}"/test_*.sh)

	if [[ ${#test_files[@]} -eq 0 ]]; then
		echo -e "${RED}Error: No test files found${NC}" >&2
		exit 1
	fi

	echo -e "${GREEN}Running individual test cases with ${TEST_TIMEOUT}s timeout...${NC}"
	echo "Results will be saved to: ${RESULTS_FILE}"
	echo ""

	# Initialize results file
	{
		echo "Test Results - $(date)"
		echo "================================"
		echo "Timeout: ${TEST_TIMEOUT} seconds"
		echo ""
	} >"$RESULTS_FILE"

	# Process each test file
	for test_file in "${test_files[@]}"; do
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
			TOTAL_TESTS=$((TOTAL_TESTS + 1))
			local test_id="${filename}::${test_name}"

			printf "  [%d] Running: %s..." "$TOTAL_TESTS" "$test_name"

			# Run the test, capturing output separately
			local start_time
			start_time=$(date +%s)
			local test_output
			local test_result
			# Use a temporary file to capture both output and exit code
			local temp_output
			temp_output=$(mktemp)
			run_single_test "$test_file" "$test_name" "$TEST_TIMEOUT" >"$temp_output" 2>&1
			test_result=$?
			test_output=$(cat "$temp_output")
			rm -f "$temp_output"
			local end_time
			end_time=$(date +%s)
			local duration=$((end_time - start_time))

			# Suppress bats output by redirecting to /dev/null for cleaner output
			# The test_output variable contains it if needed for debugging
			if [[ $test_result -eq 2 ]]; then
				# Timeout
				TIMED_OUT_COUNT=$((TIMED_OUT_COUNT + 1))
				TIMED_OUT_TESTS+=("$test_id")
				echo -e " ${RED}[TIMEOUT after ${duration}s]${NC}"
				echo "TIMEOUT: ${test_id} (${duration}s)" >>"$RESULTS_FILE"
			elif [[ $test_result -ne 0 ]]; then
				# Failure
				FAILED_COUNT=$((FAILED_COUNT + 1))
				FAILED_TESTS+=("$test_id")
				echo -e " ${RED}[FAILED after ${duration}s]${NC}"
				echo "FAILED: ${test_id} (${duration}s)" >>"$RESULTS_FILE"
				# Optionally save test output for failed tests
				echo "  Output:" >>"$RESULTS_FILE"
				echo "$test_output" | sed 's/^/    /' >>"$RESULTS_FILE"
			else
				# Success
				PASSED_COUNT=$((PASSED_COUNT + 1))
				PASSED_TESTS+=("$test_id")
				echo -e " ${GREEN}[PASSED in ${duration}s]${NC}"
				echo "PASSED: ${test_id} (${duration}s)" >>"$RESULTS_FILE"
			fi
		done

		echo ""
	done

	# Print summary
	echo ""
	echo -e "${GREEN}========================================${NC}"
	echo -e "${GREEN}Test Execution Summary${NC}"
	echo -e "${GREEN}========================================${NC}"
	echo -e "Total tests: ${TOTAL_TESTS}"
	echo -e "${GREEN}Passed: ${PASSED_COUNT}${NC}"
	echo -e "${RED}Failed: ${FAILED_COUNT}${NC}"
	echo -e "${YELLOW}Timed out: ${TIMED_OUT_COUNT}${NC}"
	echo ""

	# Write detailed summary to results file
	{
		echo ""
		echo "=========================================="
		echo "Summary"
		echo "=========================================="
		echo "Total tests: ${TOTAL_TESTS}"
		echo "Passed: ${PASSED_COUNT}"
		echo "Failed: ${FAILED_COUNT}"
		echo "Timed out: ${TIMED_OUT_COUNT}"
		echo ""

		if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
			echo "Failed Tests:"
			echo "-------------"
			for test in "${FAILED_TESTS[@]}"; do
				echo "  - ${test}"
			done
			echo ""
		fi

		if [[ ${#TIMED_OUT_TESTS[@]} -gt 0 ]]; then
			echo "Timed Out Tests:"
			echo "----------------"
			for test in "${TIMED_OUT_TESTS[@]}"; do
				echo "  - ${test}"
			done
			echo ""
		fi
	} >>"$RESULTS_FILE"

	# Print failed tests
	if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
		echo -e "${RED}Failed Tests:${NC}"
		for test in "${FAILED_TESTS[@]}"; do
			echo -e "  ${RED}✗${NC} ${test}"
		done
		echo ""
	fi

	# Print timed out tests
	if [[ ${#TIMED_OUT_TESTS[@]} -gt 0 ]]; then
		echo -e "${YELLOW}Timed Out Tests:${NC}"
		for test in "${TIMED_OUT_TESTS[@]}"; do
			echo -e "  ${YELLOW}⏱${NC} ${test}"
		done
		echo ""
	fi

	echo -e "Results saved to: ${RESULTS_FILE}"
	echo ""

	# Exit with error if any tests failed or timed out
	if [[ $FAILED_COUNT -gt 0 ]] || [[ $TIMED_OUT_COUNT -gt 0 ]]; then
		exit 1
	fi
}

# Run main
main "$@"
