#!/usr/bin/env bash
#
# Validate test tag consistency
#
# This script checks that all BATS tests have consistent tag formatting
# and required tags.
#
# Usage:
#   ./scripts/check-test-tags.sh [test_file...]
#
# If no files are specified, checks all test files in tests/ directory.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Default to checking all test files if none specified
if [[ $# -eq 0 ]]; then
	# Find all test files
	mapfile -t test_files < <(find tests -name "*.sh" -type f | sort)
else
	test_files=("$@")
fi

# Track issues
issues_found=0
warnings_found=0
tests_without_tags=0
tests_with_tags=0

# Standard tag format: # bats test_tags=tag1,tag2,tag3
# Acceptable formats:
#   # bats test_tags=category:high-risk,priority:high
#   # bats test_tags=slow,category:high-risk,priority:high
#   # bats test_tags=category:unit
tag_pattern='#\s*bats\s+test_tags='

echo "Checking test tag consistency..."
echo "=================================================="
echo ""

for test_file in "${test_files[@]}"; do
	if [[ ! -f "$test_file" ]]; then
		echo -e "${YELLOW}Warning: File not found: $test_file${NC}" >&2
		warnings_found=$((warnings_found + 1))
		continue
	fi

	# Read file into array
	mapfile -t lines <"$test_file"

	# Find all @test declarations
	i=0
	while [[ $i -lt ${#lines[@]} ]]; do
		line="${lines[$i]}"
		line_num=$((i + 1))

		# Check if this is a test declaration
		if echo "$line" | grep -qE '^\s*@test\s+'; then
			test_name=$(echo "$line" | sed -E 's/^\s*@test\s+"([^"]+)".*/\1/')
			if [[ -z "$test_name" ]]; then
				test_name=$(echo "$line" | sed -E 's/^\s*@test\s+([^\s]+).*/\1/')
			fi

			# Look for test_tags in the test (check up to 10 lines after @test)
			found_tags=false
			tag_line=""

			for ((j = i + 1; j < i + 10 && j < ${#lines[@]}; j++)); do
				if echo "${lines[$j]}" | grep -qE "$tag_pattern"; then
					found_tags=true
					tag_line="${lines[$j]}"
					break
				fi
				# Stop if we hit another @test or function definition
				if echo "${lines[$j]}" | grep -qE '^\s*@test\s+|^\s*(function\s+)?[a-zA-Z_][a-zA-Z0-9_]*\s*\('; then
					break
				fi
			done

			if [[ "$found_tags" == "false" ]]; then
				echo -e "${YELLOW}Warning in $test_file:${NC}"
				echo -e "  Test at line $line_num: '$test_name'"
				echo -e "  ${YELLOW}No test_tags found${NC}"
				echo ""
				tests_without_tags=$((tests_without_tags + 1))
				warnings_found=$((warnings_found + 1))
			else
				tests_with_tags=$((tests_with_tags + 1))

				# Extract tags
				tags=$(echo "$tag_line" | sed -E 's/.*test_tags=([^\s]+).*/\1/')

				# Validate tag format (should be comma-separated)
				if echo "$tags" | grep -qE '^[a-zA-Z0-9_:,-]+$'; then
					# Check for common issues
					# 1. Check for spaces (should be commas)
					if echo "$tags" | grep -qE '\s'; then
						echo -e "${RED}Issue in $test_file:${NC}"
						echo -e "  Test at line $line_num: '$test_name'"
						echo -e "  ${RED}Tags contain spaces (should use commas): $tags${NC}"
						echo "  Tag line: $tag_line"
						echo ""
						issues_found=$((issues_found + 1))
					fi

					# 2. Check for duplicate tags
					IFS=',' read -ra tag_array <<<"$tags"
					declare -A seen_tags
					for tag in "${tag_array[@]}"; do
						tag=$(echo "$tag" | xargs) # trim whitespace
						if [[ -n "${seen_tags[$tag]:-}" ]]; then
							echo -e "${YELLOW}Warning in $test_file:${NC}"
							echo -e "  Test at line $line_num: '$test_name'"
							echo -e "  ${YELLOW}Duplicate tag: $tag${NC}"
							echo "  Tag line: $tag_line"
							echo ""
							warnings_found=$((warnings_found + 1))
						fi
						seen_tags[$tag]=1
					done
					unset seen_tags

					# Note: We don't validate for missing category/priority tags as they may not be required for all tests
				else
					echo -e "${RED}Issue in $test_file:${NC}"
					echo -e "  Test at line $line_num: '$test_name'"
					echo -e "  ${RED}Invalid tag format: $tags${NC}"
					echo "  Tag line: $tag_line"
					echo ""
					issues_found=$((issues_found + 1))
				fi
			fi
		fi

		i=$((i + 1))
	done
done

echo "=================================================="
echo "Summary:"
echo "  Tests with tags: $tests_with_tags"
echo "  Tests without tags: $tests_without_tags"
echo "  Issues found: $issues_found"
echo "  Warnings: $warnings_found"
echo ""

if [[ $issues_found -eq 0 ]] && [[ $tests_without_tags -eq 0 ]]; then
	echo -e "${GREEN}✓ All tests have properly formatted tags${NC}"
	exit 0
elif [[ $issues_found -eq 0 ]]; then
	echo -e "${YELLOW}⚠ Some tests are missing tags (warnings only)${NC}"
	echo "  Consider adding tags to improve test organization"
	exit 0
else
	echo -e "${RED}✗ Found $issues_found issue(s) with test tags${NC}"
	exit 1
fi
