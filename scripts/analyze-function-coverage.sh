#!/bin/bash
#
# Analyze test coverage for specific functions mentioned in UNTESTED_FUNCTIONS_REVIEW.md
# Runs integration tests with coverage and reports coverage gaps for target functions
#
# Usage:
#   ./scripts/analyze-function-coverage.sh [--run-tests] [--html-report]
#
# Options:
#   --run-tests      Run integration tests with coverage (default: use existing coverage)
#   --html-report    Open HTML coverage report after analysis
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COVERAGE_DIR="${PROJECT_ROOT}/coverage"
TESTS_DIR="${PROJECT_ROOT}/tests"

# Functions to analyze (from UNTESTED_FUNCTIONS_REVIEW.md)
declare -A TARGET_FUNCTIONS=(
	["check_vpn_status_for_location"]="lib/recovery/recovery_orchestration.sh:734:783"
	["update_location_state"]="lib/recovery/recovery_orchestration.sh:806:936"
	["compute_log_file_path"]="lib/config/config_loading.sh:782:841"
	["ensure_config_directories_exist"]="lib/config/config_loading.sh:865:911"
	["apply_backward_compatibility_migrations"]="lib/config/config_loading.sh:698:728"
	["validate_config_schema"]="lib/config/config_validation.sh:566:587"
)

# Integration test files that should exercise these functions
INTEGRATION_TESTS=(
	"${TESTS_DIR}/test_integration.sh"
	"${TESTS_DIR}/test_integration_location.sh"
	"${TESTS_DIR}/test_integration_e2e_recovery.sh"
	"${TESTS_DIR}/test_recovery_network_partition.sh"
	"${TESTS_DIR}/test_config_loading.sh"
	"${TESTS_DIR}/test_config_schema.sh"
)

# Parse arguments
RUN_TESTS=0
OPEN_HTML=0
while [[ $# -gt 0 ]]; do
	case $1 in
	--run-tests)
		RUN_TESTS=1
		shift
		;;
	--html-report)
		OPEN_HTML=1
		shift
		;;
	*)
		echo -e "${RED}Unknown option: $1${NC}" >&2
		echo "Usage: $0 [--run-tests] [--html-report]"
		exit 1
		;;
	esac
done

# Check if kcov is available
if ! command -v kcov >/dev/null 2>&1; then
	echo -e "${RED}Error: kcov is not installed${NC}" >&2
	echo "Install kcov to generate coverage reports"
	exit 1
fi

# Check if bats is available
if ! command -v bats >/dev/null 2>&1; then
	echo -e "${RED}Error: bats is not installed${NC}" >&2
	exit 1
fi

# Run tests with coverage if requested
if [[ $RUN_TESTS -eq 1 ]]; then
	echo -e "${BLUE}Running integration tests with coverage...${NC}"
	echo ""

	# Clean coverage directory
	if [[ -d "$COVERAGE_DIR" ]]; then
		rm -rf "$COVERAGE_DIR"
	fi
	mkdir -p "$COVERAGE_DIR"

	# Get kcov arguments (same as run_tests.sh uses)
	KCOV_ARGS=(
		"--include-path=${PROJECT_ROOT}/lib"
		"--include-path=${PROJECT_ROOT}/scripts"
		"--include-path=${PROJECT_ROOT}"
		"--exclude-path=${PROJECT_ROOT}/tests"
		"--exclude-path=${COVERAGE_DIR}"
		"--exclude-path=${PROJECT_ROOT}/.git"
		"--exclude-path=${PROJECT_ROOT}/logs"
		"--exclude-path=${PROJECT_ROOT}/state"
		"--exclude-path=${PROJECT_ROOT}/reports"
		"--exclude-path=${PROJECT_ROOT}/analyze"
		"--exclude-path=/usr"
		"--exclude-path=/tmp"
	)

	# Run each integration test file with coverage
	for test_file in "${INTEGRATION_TESTS[@]}"; do
		if [[ ! -f "$test_file" ]]; then
			echo -e "${YELLOW}Warning: Test file not found: $test_file${NC}" >&2
			continue
		fi
		echo -e "${CYAN}Running: $(basename "$test_file")${NC}"
		# Use timeout to prevent hanging (180 seconds per test file)
		if timeout 180 kcov "${KCOV_ARGS[@]}" "$COVERAGE_DIR" bats --timing "$test_file" >/dev/null 2>&1; then
			echo -e "  ${GREEN}✓ Passed${NC}"
		else
			EXIT_CODE=$?
			if [[ $EXIT_CODE -eq 124 ]]; then
				echo -e "  ${YELLOW}⚠ Timed out${NC}"
			else
				echo -e "  ${RED}✗ Failed (exit code: $EXIT_CODE)${NC}"
			fi
		fi
	done

	echo ""
	echo -e "${GREEN}Coverage data collected${NC}"
	echo ""
fi

# Check if coverage data exists
if [[ ! -f "${COVERAGE_DIR}/index.js" ]] && [[ ! -f "${COVERAGE_DIR}/index.json" ]]; then
	echo -e "${RED}Error: Coverage data not found${NC}" >&2
	echo "Run with --run-tests first, or ensure coverage data exists in: $COVERAGE_DIR"
	exit 1
fi

# Check whether kcov produced coverage data for a given source file.
#
# Looks for an HTML file under COVERAGE_DIR whose name matches the source file.
#
# Arguments:
#   $1: file_path - Relative path to the source file (e.g. lib/recovery/recovery_orchestration.sh)
#   $2: func_name - Function name (unused; for caller convenience)
#   $3: start_line - Function start line (unused)
#   $4: end_line - Function end line (unused)
#
# Returns:
#   0: Coverage data (HTML file) found for the file
#   1: No coverage data found
check_file_coverage() {
	local file_path="$1"
	local func_name="$2"
	local start_line="$3"
	local end_line="$4"

	# Find HTML file for this source file
	# kcov creates files like: lib_recovery_recovery_orchestration.sh.HASH.html
	local html_file
	html_file=$(find "$COVERAGE_DIR" -name "$(basename "$file_path")*.html" -type f | head -1)

	if [[ -z "$html_file" ]] || [[ ! -f "$html_file" ]]; then
		return 1
	fi

	# File has coverage data
	return 0
}

# Main analysis
echo -e "${BLUE}Analyzing Coverage for Target Functions${NC}"
echo "=========================================="
echo ""

# Check overall coverage first
if [[ -f "${COVERAGE_DIR}/index.js" ]]; then
	header_data=$(grep -oP 'var header = \{[^}]+\}' "${COVERAGE_DIR}/index.js" 2>/dev/null || echo "")
	if [[ -n "$header_data" ]]; then
		covered=$(echo "$header_data" | grep -oP '"covered"\s*:\s*"?\K[0-9.]+' || echo "")
		instrumented=$(echo "$header_data" | grep -oP '"instrumented"\s*:\s*"?\K[0-9.]+' || echo "")
		if [[ -n "$covered" ]] && [[ -n "$instrumented" ]] && [[ "$instrumented" != "0" ]]; then
			percent=$(awk "BEGIN {printf \"%.1f\", ($covered / $instrumented) * 100}" 2>/dev/null || echo "N/A")
			echo -e "Overall Coverage: ${GREEN}${percent}%${NC} (${covered}/${instrumented} lines)"
			echo ""
		fi
	fi
fi

# Analyze each target function
echo -e "${CYAN}Target Functions for Analysis:${NC}"
echo ""
for func_name in "${!TARGET_FUNCTIONS[@]}"; do
	IFS=':' read -r file_path start_line end_line <<<"${TARGET_FUNCTIONS[$func_name]}"
	full_path="${PROJECT_ROOT}/${file_path}"

	echo -e "  ${CYAN}${func_name}${NC}"
	echo "    File: $file_path"
	echo "    Lines: $start_line-$end_line"

	# Check if coverage data exists for this file
	if check_file_coverage "$file_path" "$func_name" "$start_line" "$end_line"; then
		echo -e "    Status: ${GREEN}✓ Coverage data available${NC}"
	else
		echo -e "    Status: ${YELLOW}⚠ No coverage data found${NC}"
		echo -e "    ${YELLOW}    (Function may not have been executed by tests)${NC}"
	fi

	echo ""
done

# Summary
echo -e "${BLUE}Summary${NC}"
echo "======="
echo ""
echo "To analyze detailed line-by-line coverage for each function:"
echo "  1. Open the HTML coverage report: ${COVERAGE_DIR}/index.html"
echo "  2. Navigate to the source file for each function"
echo "  3. Check which lines are covered (green) vs uncovered (red)"
echo ""
echo "Function locations in HTML report:"
for func_name in "${!TARGET_FUNCTIONS[@]}"; do
	IFS=':' read -r file_path start_line end_line <<<"${TARGET_FUNCTIONS[$func_name]}"
	echo "  - ${func_name}: Look for ${file_path}, lines ${start_line}-${end_line}"
done
echo ""

if [[ $OPEN_HTML -eq 1 ]]; then
	if command -v xdg-open >/dev/null 2>&1; then
		xdg-open "${COVERAGE_DIR}/index.html" 2>/dev/null &
	elif command -v open >/dev/null 2>&1; then
		open "${COVERAGE_DIR}/index.html" 2>/dev/null &
	else
		echo "Open manually: ${COVERAGE_DIR}/index.html"
	fi
fi

echo -e "${GREEN}Analysis complete${NC}"
