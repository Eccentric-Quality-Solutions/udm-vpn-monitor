#!/usr/bin/env bash
#
# Test Isolation Verification Script
#
# Verifies that tests are properly isolated and don't leave state that affects other tests.
# This script helps detect test pollution issues where one test's modifications affect
# subsequent tests.
#
# Usage:
#   ./verify_test_isolation.sh [test_file...]
#   ./verify_test_isolation.sh --slow          # Include slow tests
#   ./verify_test_isolation.sh --sample N      # Test only N random files
#
# If no test files are specified, runs verification on fast test files only (by default).
#
# Exit codes:
#   0: All tests pass isolation verification
#   1: One or more tests fail isolation verification
#
# This script works by:
#   1. Capturing environment state before and after each test
#   2. Comparing environment variables to detect modifications
#   3. Checking for files created outside TEST_DIR
#   4. Verifying PATH modifications are cleaned up
#   5. Reporting any state leakage detected
#
# Performance:
#   By default, skips slow test files to speed up verification.
#   Use --slow flag to include all tests (will take much longer).

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test-related environment variables that should be cleaned up
TEST_ENV_VARS=(
	CONFIG_FILE
	STATE_DIR
	LOGS_DIR
	LOCKFILE
	LOG_FILE
	RESTART_COUNT_FILE
	COOLDOWN_UNTIL_FILE
	MOCK_IP
	MOCK_PING
	MOCK_IPSEC
	NO_ESCALATE
	DEBUG
	BASE_TIME
	TEST_CONFIG_FILE
	TEST_SCRIPT
	MOCK_DATA_DIR
	MOCK_INSTALL_DIR
	TEST_DIR
)

# Track verification results
VERIFICATION_FAILED=0
VERIFICATION_PASSED=0
VERIFICATION_SKIPPED=0

# Options
RUN_SLOW_TESTS=0
SAMPLE_SIZE=0

# Print colored message
print_info() {
	echo -e "${GREEN}[INFO]${NC} $*"
}

print_warn() {
	echo -e "${YELLOW}[WARN]${NC} $*"
}

print_error() {
	echo -e "${RED}[ERROR]${NC} $*"
}

# Capture current environment state
capture_env_state() {
	local output_file="$1"
	local -A env_state

	# Capture all test-related environment variables
	for var in "${TEST_ENV_VARS[@]}"; do
		# Use -v to check if variable is set (works even for empty strings)
		if [[ -v "$var" ]]; then
			env_state["$var"]="${!var}"
		else
			env_state["$var"]="__UNSET__"
		fi
	done

	# Capture PATH
	env_state["PATH"]="${PATH:-}"

	# Write to file
	{
		for var in "${!env_state[@]}"; do
			echo "${var}=${env_state[$var]}"
		done
	} >"$output_file"
}

# Compare two environment state files
compare_env_states() {
	local before_file="$1"
	local after_file="$2"
	local diff_file="${3:-/dev/null}"

	# Create sorted versions for comparison
	local before_sorted
	local after_sorted
	before_sorted=$(mktemp)
	after_sorted=$(mktemp)

	sort <"$before_file" >"$before_sorted"
	sort <"$after_file" >"$after_sorted"

	# Compare and capture differences
	local differences
	differences=$(diff "$before_sorted" "$after_sorted" || true)

	rm -f "$before_sorted" "$after_sorted"

	if [[ -n "$differences" ]]; then
		if [[ "$diff_file" != "/dev/null" ]]; then
			echo "$differences" >"$diff_file"
		fi
		return 1
	fi

	return 0
}

# Check for files created outside TEST_DIR
check_files_outside_test_dir() {
	local test_dir="${TEST_DIR:-}"
	local files_found=()

	if [[ -z "$test_dir" ]]; then
		return 0
	fi

	# Check common locations where tests might create files
	local check_dirs=(
		"/tmp"
		"/var/tmp"
		"$HOME"
	)

	for check_dir in "${check_dirs[@]}"; do
		if [[ ! -d "$check_dir" ]]; then
			continue
		fi

		# Look for files with test-related names
		while IFS= read -r -d '' file; do
			# Skip if file is in TEST_DIR
			if [[ "$file" == "$test_dir"/* ]]; then
				continue
			fi

			# Check if file name suggests it's from a test
			local basename_file
			basename_file=$(basename "$file")
			if [[ "$basename_file" =~ (vpn-monitor|test|mock|\.log|\.lock|restart_count|cooldown_until) ]]; then
				files_found+=("$file")
			fi
		done < <(find "$check_dir" -maxdepth 2 -type f -name "*vpn-monitor*" -o -name "*test*" -o -name "*mock*" 2>/dev/null | head -20 | tr '\n' '\0' || true)
	done

	if [[ ${#files_found[@]} -gt 0 ]]; then
		for file in "${files_found[@]}"; do
			print_warn "File found outside TEST_DIR: $file"
		done
		return 1
	fi

	return 0
}

# Check if a test file is a slow test file
is_slow_test_file() {
	local filename="$1"
	[[ "$filename" == "test_integration.sh" ]] ||
		[[ "$filename" == "test_config.sh" ]] ||
		[[ "$filename" == "test_lockfile.sh" ]] ||
		[[ "$filename" == "test_detection.sh" ]] ||
		[[ "$filename" == "test_recovery.sh" ]] ||
		[[ "$filename" == "test_state.sh" ]] ||
		[[ "$filename" == "test_logging.sh" ]] ||
		[[ "$filename" == "test_connection.sh" ]] ||
		[[ "$filename" == "test_errors.sh" ]] ||
		[[ "$filename" == "test_main.sh" ]]
}

# Verify test isolation for a single test file
verify_test_file_isolation() {
	local test_file="$1"
	local test_name
	test_name=$(basename "$test_file")
	local file_num="${2:-}"
	local total_files="${3:-}"

	# Show progress if we have file numbers
	if [[ -n "$file_num" ]] && [[ -n "$total_files" ]]; then
		print_info "[$file_num/$total_files] Verifying isolation for: $test_name"
	else
		print_info "Verifying isolation for: $test_name"
	fi

	# Skip if file doesn't exist
	if [[ ! -f "$test_file" ]]; then
		print_warn "Test file not found: $test_file (skipping)"
		VERIFICATION_SKIPPED=$((VERIFICATION_SKIPPED + 1))
		return 0
	fi

	# Skip if not a BATS test file
	if ! grep -q "^#!/usr/bin/env bats" "$test_file" && ! grep -q "^load test_helper" "$test_file"; then
		print_warn "Not a BATS test file: $test_file (skipping)"
		VERIFICATION_SKIPPED=$((VERIFICATION_SKIPPED + 1))
		return 0
	fi

	# Create temporary directory for state capture
	local state_dir
	state_dir=$(mktemp -d)
	local before_state="${state_dir}/before.env"
	local after_state="${state_dir}/after.env"
	local diff_state="${state_dir}/diff.env"

	# Capture initial environment state
	capture_env_state "$before_state"

	# Run the test file (capture output to suppress it, we only care about environment state)
	# We intentionally don't use test_output or test_status - we only check environment state changes
	# Use timeout to prevent hanging tests (5 minutes max per test file)
	local _test_output
	local _test_status=0
	local isolation_failed=0

	if command -v timeout >/dev/null 2>&1; then
		_test_output=$(cd "$PROJECT_ROOT" && timeout 300 bats "$test_file" 2>&1) || _test_status=$?
	else
		_test_output=$(cd "$PROJECT_ROOT" && bats "$test_file" 2>&1) || _test_status=$?
	fi

	# Check if timeout occurred
	if [[ $_test_status -eq 124 ]] || [[ $_test_status -eq 143 ]]; then
		print_error "Test file timed out after 5 minutes: $test_name"
		isolation_failed=1
	fi

	# Capture environment state after test
	capture_env_state "$after_state"

	# Compare states

	if ! compare_env_states "$before_state" "$after_state" "$diff_state"; then
		print_error "Environment state leakage detected in $test_name"
		print_error "Differences:"
		cat "$diff_state" | sed 's/^/  /'
		isolation_failed=1
	fi

	# Check for files outside TEST_DIR
	if ! check_files_outside_test_dir; then
		print_error "Files created outside TEST_DIR detected in $test_name"
		isolation_failed=1
	fi

	# Cleanup
	rm -rf "$state_dir"

	# Report results
	if [[ $isolation_failed -eq 1 ]]; then
		VERIFICATION_FAILED=$((VERIFICATION_FAILED + 1))
		return 1
	else
		VERIFICATION_PASSED=$((VERIFICATION_PASSED + 1))
		return 0
	fi
}

# Parse command line arguments
# Sets RUN_SLOW_TESTS, SAMPLE_SIZE, and returns remaining args in global array
parse_args() {
	local remaining_args=()

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--slow | -s)
			RUN_SLOW_TESTS=1
			shift
			;;
		--sample)
			if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
				print_error "--sample requires a number (e.g., --sample 5)"
				exit 1
			fi
			SAMPLE_SIZE="$2"
			shift 2
			;;
		--help | -h)
			cat <<EOF
Usage: $0 [OPTIONS] [test_file...]

Options:
  --slow, -s          Include slow test files (default: skip them)
  --sample N          Test only N random test files (for quick verification)
  --help, -h           Show this help message

Examples:
  $0                          # Verify fast tests only
  $0 --slow                   # Verify all tests (including slow)
  $0 --sample 5               # Test 5 random fast test files
  $0 test_config.sh           # Verify specific test file
  $0 test_config.sh test_state.sh  # Verify specific test files

By default, slow test files are skipped for faster verification.
Slow test files: test_integration.sh, test_config.sh, test_lockfile.sh,
test_detection.sh, test_recovery.sh, test_state.sh, test_logging.sh,
test_connection.sh, test_errors.sh, test_main.sh

EOF
			exit 0
			;;
		-*)
			print_error "Unknown option: $1"
			print_error "Use --help for usage information"
			exit 1
			;;
		*)
			# Not an option, treat as test file
			remaining_args+=("$1")
			shift
			;;
		esac
	done

	# Return remaining args via global (bash doesn't have return arrays)
	PARSED_ARGS=("${remaining_args[@]}")
}

# Filter test files based on slow test setting
filter_test_files() {
	local all_files=("$@")
	local filtered_files=()

	for test_file in "${all_files[@]}"; do
		local filename
		filename=$(basename "$test_file")

		if is_slow_test_file "$filename"; then
			if [[ "$RUN_SLOW_TESTS" -eq 1 ]]; then
				filtered_files+=("$test_file")
			fi
		else
			filtered_files+=("$test_file")
		fi
	done

	printf '%s\n' "${filtered_files[@]}"
}

# Main function
main() {
	# Parse arguments
	parse_args "$@"
	local explicit_test_files=("${PARSED_ARGS[@]}")

	local test_files=()

	# If test files explicitly provided, use them
	if [[ ${#explicit_test_files[@]} -gt 0 ]]; then
		for test_file in "${explicit_test_files[@]}"; do
			# Convert to absolute path if relative
			if [[ ! "$test_file" =~ ^/ ]]; then
				test_file="$SCRIPT_DIR/$test_file"
			fi
			test_files+=("$test_file")
		done
	else
		# Find all test files
		local all_test_files=()
		while IFS= read -r -d '' file; do
			all_test_files+=("$file")
		done < <(find "$SCRIPT_DIR" -maxdepth 1 -name "test_*.sh" -type f -print0 2>/dev/null || true)

		if [[ ${#all_test_files[@]} -eq 0 ]]; then
			print_error "No test files found"
			exit 1
		fi

		# Filter based on slow test setting
		mapfile -t test_files < <(filter_test_files "${all_test_files[@]}")

		# Apply sampling if requested
		local total_before_sample=${#test_files[@]}
		if [[ "$SAMPLE_SIZE" -gt 0 ]] && [[ "$SAMPLE_SIZE" -lt ${#test_files[@]} ]]; then
			# Shuffle and take first N
			local sampled_files=()
			mapfile -t sampled_files < <(printf '%s\n' "${test_files[@]}" | shuf -n "$SAMPLE_SIZE")
			test_files=("${sampled_files[@]}")
		fi

		if [[ ${#test_files[@]} -eq 0 ]]; then
			if [[ "$RUN_SLOW_TESTS" -eq 0 ]]; then
				print_warn "No test files to verify (slow tests excluded, use --slow to include)"
			else
				print_error "No test files found"
			fi
			exit 1
		fi

		local total_files=${#test_files[@]}
		print_info "Verifying test isolation for $total_files test file(s)"
		if [[ "$RUN_SLOW_TESTS" -eq 0 ]]; then
			print_info "(Slow tests excluded - use --slow to include)"
		fi
		if [[ "$SAMPLE_SIZE" -gt 0 ]] && [[ "$SAMPLE_SIZE" -lt $total_before_sample ]]; then
			print_info "(Sampling mode: testing $SAMPLE_SIZE random files from $total_before_sample available)"
		fi
		print_info ""
	fi

	# Ensure we have test files
	if [[ ${#test_files[@]} -eq 0 ]]; then
		print_error "No test files found"
		exit 1
	fi

	# Verify each test file
	local file_num=0
	for test_file in "${test_files[@]}"; do
		file_num=$((file_num + 1))
		verify_test_file_isolation "$test_file" "$file_num" "$total_files" || true
	done

	# Print summary
	print_info ""
	print_info "Verification Summary:"
	print_info "  Passed:  $VERIFICATION_PASSED"
	print_info "  Failed:  $VERIFICATION_FAILED"
	print_info "  Skipped: $VERIFICATION_SKIPPED"

	if [[ $VERIFICATION_FAILED -gt 0 ]]; then
		print_error ""
		print_error "Test isolation verification failed!"
		print_error "Some tests are leaving state that affects other tests."
		print_error "Review the differences above and ensure teardown() properly cleans up."
		exit 1
	fi

	print_info ""
	print_info "All tests passed isolation verification!"
	exit 0
}

# Run main function
main "$@"
