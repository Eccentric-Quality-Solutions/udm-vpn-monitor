#!/bin/bash
#
# Generate test coverage report from kcov output
# Processes kcov coverage data and generates summary reports
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
COVERAGE_DIR="${PROJECT_ROOT}/coverage"

# Generate text summary report
generate_text_summary() {
	local summary_file="${COVERAGE_DIR}/summary.txt"

	echo "Test Coverage Summary" >"$summary_file"
	echo "====================" >>"$summary_file"
	echo "Generated: $(date)" >>"$summary_file"
	echo "" >>"$summary_file"

	# kcov v43+ uses JavaScript file, older versions use JSON
	local js_report="${COVERAGE_DIR}/index.js"
	local json_report="${COVERAGE_DIR}/index.json"

	if [[ ! -f "$js_report" ]] && [[ ! -f "$json_report" ]]; then
		echo "Error: Coverage report not found" >>"$summary_file"
		echo "Expected: ${js_report} or ${json_report}" >>"$summary_file"
		echo "Run tests with --coverage first: ./tests/run_tests.sh --coverage" >>"$summary_file"
		return 1
	fi

	# Try to extract coverage from JavaScript file (kcov v43+)
	if [[ -f "$js_report" ]]; then
		# Extract coverage data from JavaScript file
		local header_data
		header_data=$(grep -oP 'var header = \{[^}]+\}' "$js_report" 2>/dev/null || echo "")

		if [[ -n "$header_data" ]]; then
			echo "Overall Coverage:" >>"$summary_file"
			local covered instrumented
			covered=$(echo "$header_data" | grep -oP '"covered"\s*:\s*"?\K[0-9.]+' || echo "")
			instrumented=$(echo "$header_data" | grep -oP '"instrumented"\s*:\s*"?\K[0-9.]+' || echo "")

			if [[ -n "$covered" ]] && [[ -n "$instrumented" ]] && [[ "$instrumented" != "0" ]]; then
				local percent
				percent=$(awk "BEGIN {printf \"%.1f\", ($covered / $instrumented) * 100}" 2>/dev/null || echo "N/A")
				echo "  Total: ${percent}% (${covered}/${instrumented} lines)" >>"$summary_file"
			else
				echo "  Total: N/A" >>"$summary_file"
			fi
			echo "" >>"$summary_file"
			echo "Note: Detailed file-by-file coverage available in HTML report" >>"$summary_file"
		fi
	# Fallback to JSON format (older kcov versions)
	elif [[ -f "$json_report" ]]; then
		# Check if JSON is valid (basic check)
		if ! command -v jq >/dev/null 2>&1; then
			# Without jq, we can't validate JSON, but we can check if file is readable
			if [[ ! -r "$json_report" ]]; then
				echo "Error: Coverage JSON report is not readable" >>"$summary_file"
				return 1
			fi
		else
			# Validate JSON structure with jq
			if ! jq empty "$json_report" 2>/dev/null; then
				echo "Warning: Coverage JSON report appears to be invalid or empty" >>"$summary_file"
				echo "The report may be incomplete or corrupted." >>"$summary_file"
			fi
		fi

		# Extract coverage data using jq if available
		if command -v jq >/dev/null 2>&1; then
			echo "Overall Coverage:" >>"$summary_file"
			local total_coverage
			total_coverage=$(jq -r '.merged_percent_covered' "$json_report" 2>/dev/null || echo "N/A")
			echo "  Total: ${total_coverage}%" >>"$summary_file"
			echo "" >>"$summary_file"

			echo "Coverage by File:" >>"$summary_file"
			# Extract file coverage, handling errors gracefully
			local file_coverage
			file_coverage=$(jq -r '.files[] | "  \(.file): \(.percent_covered)% (\(.covered_lines)/\(.total_lines) lines)"' "$json_report" 2>/dev/null || echo "")
			if [[ -n "$file_coverage" ]]; then
				echo "$file_coverage" >>"$summary_file"
			else
				echo "  (No file coverage data available)" >>"$summary_file"
			fi
		else
			echo "Note: Install 'jq' for detailed coverage statistics" >>"$summary_file"
			echo "View HTML report: ${COVERAGE_DIR}/index.html" >>"$summary_file"
		fi
	fi

	echo "" >>"$summary_file"
	echo "Full HTML report: ${COVERAGE_DIR}/index.html" >>"$summary_file"

	cat "$summary_file"
}

# Generate coverage badge (simple text version)
generate_badge() {
	local badge_file="${COVERAGE_DIR}/coverage-badge.txt"
	local js_report="${COVERAGE_DIR}/index.js"
	local json_report="${COVERAGE_DIR}/index.json"

	local coverage="N/A"

	# Try JavaScript format first (kcov v43+)
	if [[ -f "$js_report" ]]; then
		local header_data
		header_data=$(grep -oP 'var header = \{[^}]+\}' "$js_report" 2>/dev/null || echo "")
		if [[ -n "$header_data" ]]; then
			local covered instrumented
			covered=$(echo "$header_data" | grep -oP '"covered"\s*:\s*"?\K[0-9.]+' || echo "")
			instrumented=$(echo "$header_data" | grep -oP '"instrumented"\s*:\s*"?\K[0-9.]+' || echo "")
			if [[ -n "$covered" ]] && [[ -n "$instrumented" ]] && [[ "$instrumented" != "0" ]]; then
				coverage=$(awk "BEGIN {printf \"%.1f\", ($covered / $instrumented) * 100}" 2>/dev/null || echo "N/A")
			fi
		fi
	# Fallback to JSON format
	elif [[ -f "$json_report" ]] && command -v jq >/dev/null 2>&1; then
		coverage=$(jq -r '.merged_percent_covered' "$json_report" 2>/dev/null || echo "N/A")
	fi

	if [[ "$coverage" != "N/A" ]]; then
		echo "coverage: ${coverage}%" >"$badge_file"
	fi
}

# Main function
main() {
	if [[ ! -d "$COVERAGE_DIR" ]]; then
		echo -e "${RED}Error: Coverage directory not found: ${COVERAGE_DIR}${NC}" >&2
		echo "Run tests with --coverage first: ./tests/run_tests.sh --coverage" >&2
		exit 1
	fi

	echo -e "${GREEN}Generating coverage report...${NC}"
	echo ""

	generate_text_summary
	generate_badge

	echo ""
	echo -e "${GREEN}Coverage report generated!${NC}"
	echo -e "Summary: ${COVERAGE_DIR}/summary.txt"
	echo -e "HTML Report: ${COVERAGE_DIR}/index.html"
}

main "$@"
