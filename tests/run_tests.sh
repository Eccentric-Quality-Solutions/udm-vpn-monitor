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
		bats "${test_files[@]}"
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
	kcov "${kcov_args[@]}" "$COVERAGE_DIR" bats "${test_files[@]}" || true

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
    --help, -h        Show this help message

Examples:
    $0                    Run fast tests only (excludes slow tests)
    $0 --slow             Run all tests including slow tests
    $0 --coverage         Run fast tests with coverage reporting
    $0 --slow --coverage  Run all tests with coverage reporting

Test Filtering:
    By default, slow tests (test_integration.sh and test_high_risk.sh) are excluded
    to speed up local development. Use --slow flag or set RUN_SLOW_TESTS=1 to include them.
    
    In CI/CD, set RUN_SLOW_TESTS=1 environment variable to run all tests.

Coverage Reporting:
    Coverage reports are generated in HTML format in the 'coverage' directory.
    Requires kcov to be installed. See installation instructions when running
    with --coverage if kcov is not found.

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
	echo ""

	run_tests
}

# Run main
main "$@"
