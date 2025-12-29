#!/bin/bash
#
# Script to run all tests with timing and tag slow tests
# Tests taking longer than SLOW_THRESHOLD seconds will be tagged as slow
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Threshold for slow tests (in seconds)
SLOW_THRESHOLD="${SLOW_THRESHOLD:-5}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Temporary file for test output
TEMP_OUTPUT=$(mktemp)
trap 'rm -f "$TEMP_OUTPUT"' EXIT

echo -e "${GREEN}Running all tests with timing enabled...${NC}"
echo -e "${BLUE}Slow test threshold: ${SLOW_THRESHOLD}s${NC}"
echo ""

# Run all tests with timing and capture output
cd "$PROJECT_ROOT"
RUN_SLOW_TESTS=1 FAST_FAIL=0 stdbuf -oL -eL -i0 ./tests/run_tests.sh --slow --all 2>&1 | tee "$TEMP_OUTPUT" || true

echo ""
echo -e "${GREEN}Analyzing test timing...${NC}"

# Parse timing output and identify slow tests
# Format: ok 1 test name in 1234ms
# or: ok 1 test name in 1.234s
# Also track which test file we're currently in
declare -A slow_tests # test_file -> "test_name1|test_name2|..."
current_test_file=""

while IFS= read -r line; do
	# Track current test file from "Running: test_file.sh" messages
	if [[ "$line" =~ Running:\ (.+)$ ]]; then
		test_filename="${BASH_REMATCH[1]}"
		current_test_file="${SCRIPT_DIR}/${test_filename}"
		continue
	fi

	# Match timing output: ok N test name in XXXms or XXXs
	# Also match "not ok" for failed tests with timing
	if [[ "$line" =~ ^(ok|not ok)\ [0-9]+\ (.+)\ in\ ([0-9.]+)(ms|s)$ ]]; then
		test_name="${BASH_REMATCH[2]}"
		duration="${BASH_REMATCH[3]}"
		unit="${BASH_REMATCH[4]}"

		# Convert to seconds
		if [[ "$unit" == "ms" ]]; then
			duration_seconds=$(awk "BEGIN {printf \"%.3f\", $duration / 1000}")
		else
			duration_seconds="$duration"
		fi

		# Check if test is slow
		if (($(awk "BEGIN {print ($duration_seconds > $SLOW_THRESHOLD)}"))); then
			# Use current_test_file if available, otherwise search
			test_file="$current_test_file"
			if [[ -z "$test_file" ]] || [[ ! -f "$test_file" ]]; then
				# Fallback: search for test in all test files
				for tf in "${SCRIPT_DIR}"/test_*.sh; do
					if grep -q "@test.*\"${test_name}\"" "$tf" 2>/dev/null ||
						grep -q "@test.*'${test_name}'" "$tf" 2>/dev/null; then
						test_file="$tf"
						break
					fi
				done
			fi

			if [[ -n "$test_file" ]] && [[ -f "$test_file" ]]; then
				existing_tests="${slow_tests[$test_file]:-}"
				if [[ -z "$existing_tests" ]]; then
					slow_tests[$test_file]="$test_name"
				else
					# Check if already in list
					if [[ "$existing_tests" != *"$test_name"* ]]; then
						slow_tests[$test_file]="${existing_tests}|$test_name"
					fi
				fi
				echo -e "${YELLOW}Slow test found: ${test_name} (${duration_seconds}s) in $(basename "$test_file")${NC}"
			fi
		fi
	fi
done <"$TEMP_OUTPUT"

# Update test files with slow tags
if [[ ${#slow_tests[@]} -eq 0 ]]; then
	echo -e "${GREEN}No slow tests found (threshold: ${SLOW_THRESHOLD}s)${NC}"
	exit 0
fi

echo ""
echo -e "${BLUE}Updating test files with slow tags...${NC}"

for test_file in "${!slow_tests[@]}"; do
	test_names="${slow_tests[$test_file]}"
	IFS='|' read -ra names_array <<<"$test_names"

	for test_name in "${names_array[@]}"; do
		# Escape special characters in test name for sed
		escaped_name=$(printf '%s\n' "$test_name" | sed 's/[[\.*^$()+?{|]/\\&/g')

		# Find the line with @test declaration
		# Look for the test and add slow tag if not already present
		if grep -q "@test.*\"${escaped_name}\"" "$test_file" 2>/dev/null ||
			grep -q "@test.*'${escaped_name}'" "$test_file" 2>/dev/null; then

			# Find the line number of the @test declaration
			test_line=$(grep -n "@test.*[\"']${escaped_name}[\"']" "$test_file" | head -1 | cut -d: -f1)

			if [[ -n "$test_line" ]]; then
				# Check if there's already a test_tags line before this test
				# Look backwards from test_line for test_tags
				tags_line=""
				for ((i = $test_line - 1; i > 0 && i > $test_line - 10; i--)); do
					line_content=$(sed -n "${i}p" "$test_file")
					if [[ "$line_content" =~ ^#\ bats\ test_tags= ]]; then
						tags_line=$i
						break
					fi
					# Stop if we hit another @test or blank line followed by non-comment
					if [[ "$line_content" =~ ^@test ]] ||
						([[ "$line_content" =~ ^$ ]] && [[ $(sed -n "$((i - 1))p" "$test_file") =~ ^[^#] ]]); then
						break
					fi
				done

				# Check if slow tag already exists
				if [[ -n "$tags_line" ]]; then
					existing_tags=$(sed -n "${tags_line}p" "$test_file")
					if [[ "$existing_tags" =~ slow ]]; then
						echo -e "${BLUE}  Test '${test_name}' already has slow tag${NC}"
						continue
					fi
					# Add slow to existing tags
					new_tags=$(echo "$existing_tags" | sed 's/# bats test_tags=/&slow,/')
					sed -i "${tags_line}s|.*|$new_tags|" "$test_file"
					echo -e "${GREEN}  Added slow tag to '${test_name}' in $(basename "$test_file")${NC}"
				else
					# Insert new test_tags line before @test
					sed -i "${test_line}i# bats test_tags=slow" "$test_file"
					echo -e "${GREEN}  Added slow tag line for '${test_name}' in $(basename "$test_file")${NC}"
				fi
			fi
		fi
	done
done

echo ""
echo -e "${GREEN}Done! Updated ${#slow_tests[@]} test file(s) with slow tags.${NC}"
