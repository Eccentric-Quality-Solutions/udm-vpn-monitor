#!/usr/bin/env bash
#
# Mock Cleanup Audit Script
#
# Audits test files to ensure all add_mock_to_path() calls have corresponding
# remove_mock_from_path() calls. This prevents test pollution and ensures
# test isolation.
#
# Usage:
#   ./scripts/audit_mock_cleanup.sh [test_file...]
#
# If no files are specified, audits all test files in tests/ directory.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track statistics
TOTAL_TESTS=0
TESTS_WITH_MOCKS=0
TESTS_MISSING_CLEANUP=0
TOTAL_ADD_CALLS=0
TOTAL_REMOVE_CALLS=0
ISSUES_FOUND=0

# Temporary file for storing issues
TEMP_ISSUES=$(mktemp)
trap 'rm -f "$TEMP_ISSUES" "$TEMP_ISSUES.issues"' EXIT

# Function to audit a single test file using Python
audit_test_file() {
	local test_file="$1"

	echo "Auditing: $test_file"

	# Use Python for reliable parsing
	python3 <<PYTHON_SCRIPT
import re
import sys

test_file = "$test_file"
in_test = False
test_name = ''
test_line = 0
add_count = 0
remove_count = 0
add_lines = []
remove_lines = []
file_total_tests = 0
file_tests_with_mocks = 0
file_tests_missing_cleanup = 0
file_total_add_calls = 0
file_total_remove_calls = 0
issues = []

try:
    with open(test_file, 'r') as f:
        for line_num, line in enumerate(f, 1):
            # Check for test start
            match = re.match(r'^@test\s+"(.+)"', line)
            if match:
                if in_test:
                    # Process previous test
                    file_total_tests += 1
                    if add_count > 0:
                        file_tests_with_mocks += 1
                        file_total_add_calls += add_count
                        file_total_remove_calls += remove_count
                        if remove_count < add_count:
                            file_tests_missing_cleanup += 1
                            missing = add_count - remove_count
                            add_str = ','.join(map(str, add_lines))
                            remove_str = ','.join(map(str, remove_lines)) if remove_lines else ''
                            issue = f"MISSING_CLEANUP|{test_file}|{test_line}|{test_name}|{add_count}|{remove_count}|{add_str}|{remove_str}"
                            issues.append(issue)
                            print(f"  \033[0;31m✗\033[0m Test '{test_name}' (line {test_line}): {add_count} add, {remove_count} remove")
                            print(f"    Add calls at lines: {add_str}")
                            if remove_str:
                                print(f"    Remove calls at lines: {remove_str}")
                            else:
                                print(f"    Remove calls at lines: (none)")
                        else:
                            print(f"  \033[0;32m✓\033[0m Test '{test_name}' (line {test_line}): {add_count} add, {remove_count} remove")
                
                # Start new test
                in_test = True
                test_name = match.group(1)
                test_line = line_num
                add_count = 0
                remove_count = 0
                add_lines = []
                remove_lines = []
            elif in_test:
                # Check for test end - closing brace on its own line
                if re.match(r'^\s*\}\s*$', line):
                    # Process test
                    file_total_tests += 1
                    if add_count > 0:
                        file_tests_with_mocks += 1
                        file_total_add_calls += add_count
                        file_total_remove_calls += remove_count
                        if remove_count < add_count:
                            file_tests_missing_cleanup += 1
                            missing = add_count - remove_count
                            add_str = ','.join(map(str, add_lines))
                            remove_str = ','.join(map(str, remove_lines)) if remove_lines else ''
                            issue = f"MISSING_CLEANUP|{test_file}|{test_line}|{test_name}|{add_count}|{remove_count}|{add_str}|{remove_str}"
                            issues.append(issue)
                            print(f"  \033[0;31m✗\033[0m Test '{test_name}' (line {test_line}): {add_count} add, {remove_count} remove")
                            print(f"    Add calls at lines: {add_str}")
                            if remove_str:
                                print(f"    Remove calls at lines: {remove_str}")
                            else:
                                print(f"    Remove calls at lines: (none)")
                        else:
                            print(f"  \033[0;32m✓\033[0m Test '{test_name}' (line {test_line}): {add_count} add, {remove_count} remove")
                    in_test = False
                else:
                    # Count mock calls (not in comments)
                    if not re.match(r'^\s*#', line):
                        if 'add_mock_to_path' in line:
                            add_count += 1
                            add_lines.append(line_num)
                        if 'remove_mock_from_path' in line:
                            remove_count += 1
                            remove_lines.append(line_num)
    
    # Process last test if still in progress
    if in_test:
        file_total_tests += 1
        if add_count > 0:
            file_tests_with_mocks += 1
            file_total_add_calls += add_count
            file_total_remove_calls += remove_count
            if remove_count < add_count:
                file_tests_missing_cleanup += 1
                missing = add_count - remove_count
                add_str = ','.join(map(str, add_lines))
                remove_str = ','.join(map(str, remove_lines)) if remove_lines else ''
                issue = f"MISSING_CLEANUP|{test_file}|{test_line}|{test_name}|{add_count}|{remove_count}|{add_str}|{remove_str}"
                issues.append(issue)
                print(f"  \033[0;31m✗\033[0m Test '{test_name}' (line {test_line}): {add_count} add, {remove_count} remove")
                print(f"    Add calls at lines: {add_str}")
                if remove_str:
                    print(f"    Remove calls at lines: {remove_str}")
                else:
                    print(f"    Remove calls at lines: (none)")
            else:
                print(f"  \033[0;32m✓\033[0m Test '{test_name}' (line {test_line}): {add_count} add, {remove_count} remove")
    
    # Write statistics and issues to temp file
    with open("$TEMP_ISSUES", 'a') as f:
        f.write(f"STATS|{file_total_tests}|{file_tests_with_mocks}|{file_tests_missing_cleanup}|{file_total_add_calls}|{file_total_remove_calls}\n")
        for issue in issues:
            f.write(f"{issue}\n")
except Exception as e:
    print(f"Error processing {test_file}: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT

	# Read statistics from temp file
	while IFS='|' read -r type val1 val2 val3 val4 val5; do
		if [[ "$type" == "STATS" ]]; then
			((TOTAL_TESTS += val1))
			((TESTS_WITH_MOCKS += val2))
			((TESTS_MISSING_CLEANUP += val3))
			((TOTAL_ADD_CALLS += val4))
			((TOTAL_REMOVE_CALLS += val5))
		elif [[ "$type" == "MISSING_CLEANUP" ]]; then
			((ISSUES_FOUND++))
			local test_file_path="$val1"
			local test_line_num="$val2"
			local test_name="$val3"
			local add_cnt="$val4"
			local remove_cnt="$val5"
			local missing=$((add_cnt - remove_cnt))
			local issue="MISSING CLEANUP: $test_file_path:$test_line_num - Test '$test_name' has $add_cnt add_mock_to_path() call(s) but only $remove_cnt remove_mock_from_path() call(s) (missing $missing)"
			echo "$issue" >>"$TEMP_ISSUES.issues"
		fi
	done <"$TEMP_ISSUES"

	# Clear temp file for next iteration
	>"$TEMP_ISSUES"
}

# Main execution
main() {
	local test_files=()

	if [[ $# -eq 0 ]]; then
		# Find all test files (exclude bats-file directory and fixtures)
		while IFS= read -r -d '' file; do
			# Skip bats-file directory and fixture files
			if [[ ! "$file" =~ /bats-file/ ]] && [[ ! "$file" =~ /fixtures/ ]] && [[ "$file" =~ test_.*\.sh$ ]]; then
				test_files+=("$file")
			fi
		done < <(find tests -name "*.sh" -type f -print0 | sort -z)
	else
		# Use provided files
		test_files=("$@")
	fi

	if [[ ${#test_files[@]} -eq 0 ]]; then
		echo "No test files found"
		exit 1
	fi

	# Initialize issues file
	>"$TEMP_ISSUES.issues"
	>"$TEMP_ISSUES"

	echo "=== Mock Cleanup Audit ==="
	echo "Auditing ${#test_files[@]} test file(s)"
	echo ""

	for test_file in "${test_files[@]}"; do
		if [[ ! -f "$test_file" ]]; then
			echo -e "${YELLOW}Warning: File not found: $test_file${NC}"
			continue
		fi
		audit_test_file "$test_file"
	done

	echo ""
	echo "=== Audit Summary ==="
	echo "Total tests analyzed: $TOTAL_TESTS"
	echo "Tests using mocks: $TESTS_WITH_MOCKS"
	echo "Tests missing cleanup: $TESTS_MISSING_CLEANUP"
	echo "Total add_mock_to_path() calls: $TOTAL_ADD_CALLS"
	echo "Total remove_mock_from_path() calls: $TOTAL_REMOVE_CALLS"
	echo ""

	if [[ $ISSUES_FOUND -gt 0 ]]; then
		echo -e "${RED}=== Issues Found ===${NC}"
		cat "$TEMP_ISSUES.issues"
		echo ""
		echo -e "${RED}Total issues: $ISSUES_FOUND${NC}"
		exit 1
	else
		echo -e "${GREEN}✓ All tests have proper mock cleanup!${NC}"
		exit 0
	fi
}

main "$@"
