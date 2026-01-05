#!/usr/bin/env bash
#
# Check for mock creation without PATH addition
#
# This script audits test files to find instances where mocks are created
# but add_mock_to_path is not called within a reasonable distance.
#
# Usage:
#   ./scripts/check-mock-path.sh [test_file...]
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

# Pattern to match mock creation
# Matches: cat >"$mock_*" or cat >"${TEST_DIR}/*" or similar patterns
mock_pattern='cat\s+>.*mock_|cat\s+>.*\$\{TEST_DIR\}/(ip|ipsec|ping|command|df|free|date|stat|kill|sleep|timeout|cat|dig|nslookup|check_ipsec_phase2)'

# Pattern to match add_mock_to_path
path_pattern='add_mock_to_path|with_mocks\s*\(|setup_mock_vpn_environment'

echo "Checking for mock creation without PATH addition..."
echo "=================================================="
echo ""

for test_file in "${test_files[@]}"; do
	if [[ ! -f "$test_file" ]]; then
		echo -e "${YELLOW}Warning: File not found: $test_file${NC}" >&2
		warnings_found=$((warnings_found + 1))
		continue
	fi

	# Read file into array (one line per element)
	mapfile -t lines <"$test_file"

	# Track mock creation lines and check for add_mock_to_path
	i=0
	while [[ $i -lt ${#lines[@]} ]]; do
		line="${lines[$i]}"
		line_num=$((i + 1))

		# Check if this line creates a mock
		if echo "$line" | grep -qE "$mock_pattern"; then
			# Found mock creation - check if add_mock_to_path appears within next 30 lines
			found_path_add=false
			check_end=$((i + 30))
			[[ $check_end -gt ${#lines[@]} ]] && check_end=${#lines[@]}

			for ((j = i + 1; j < check_end; j++)); do
				if echo "${lines[$j]}" | grep -qE "$path_pattern"; then
					found_path_add=true
					break
				fi
			done

			# Also check if this is inside a helper function (setup_mock_vpn_environment, etc.)
			# by checking if we're inside a function definition
			for ((k = i; k >= 0 && k >= i - 50; k--)); do
				if echo "${lines[$k]}" | grep -qE '^\s*(function\s+)?[a-zA-Z_][a-zA-Z0-9_]*\s*\(|^\s*setup_mock_vpn_environment|^\s*mock_[a-zA-Z_]+\(\)'; then
					# Check if function ends before our mock creation
					func_end=$i
					# Look for function end (next function, or closing brace at start of line)
					for ((l = k + 1; l < i; l++)); do
						if echo "${lines[$l]}" | grep -qE '^\s*\}\s*$|^\s*(function\s+)?[a-zA-Z_][a-zA-Z0-9_]*\s*\('; then
							func_end=$l
							break
						fi
					done
					# If we're still in the function (no function end found before mock creation),
					# check if it calls add_mock_to_path
					# func_end == i means no function end was found, so we're still in the function
					if [[ $func_end -eq $i ]]; then
						for ((m = i + 1; m < i + 50 && m < ${#lines[@]}; m++)); do
							if echo "${lines[$m]}" | grep -qE "$path_pattern"; then
								found_path_add=true
								break 2
							fi
							# Stop if we hit the function end
							if echo "${lines[$m]}" | grep -qE '^\s*\}\s*$|^\s*(function\s+)?[a-zA-Z_][a-zA-Z0-9_]*\s*\('; then
								break
							fi
						done
					fi
					break
				fi
			done

			if [[ "$found_path_add" == "false" ]]; then
				# Extract mock name for better error message
				mock_name="unknown"
				if echo "$line" | grep -qoE 'mock_[a-zA-Z_]+|\$\{TEST_DIR\}/([a-zA-Z_]+)'; then
					mock_name=$(echo "$line" | grep -oE 'mock_[a-zA-Z_]+|\$\{TEST_DIR\}/([a-zA-Z_]+)' | head -1)
				fi

				echo -e "${RED}Issue found in $test_file:${NC}"
				echo -e "  Line $line_num: Mock created ($mock_name) but add_mock_to_path not found within 30 lines"
				echo "  Mock creation line:"
				echo "    $line"
				echo ""

				issues_found=$((issues_found + 1))
			fi
		fi

		i=$((i + 1))
	done
done

echo "=================================================="
if [[ $issues_found -eq 0 ]]; then
	echo -e "${GREEN}✓ No issues found - all mocks appear to have add_mock_to_path calls${NC}"
	exit 0
else
	echo -e "${RED}✗ Found $issues_found potential issue(s)${NC}"
	echo ""
	echo "Note: Some false positives may occur if:"
	echo "  - Mock is created in a helper function that calls add_mock_to_path"
	echo "  - Mock is created but intentionally not added to PATH"
	echo "  - Mock is added to PATH via a different mechanism"
	exit 1
fi
