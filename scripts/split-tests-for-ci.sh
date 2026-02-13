#!/bin/bash
#
# Split test files into groups for parallel CI execution
# Outputs test files for a specific group based on group number and total groups
#
# Usage:
#   ./scripts/split-tests-for-ci.sh <group_number> <total_groups>
#
# Example:
#   ./scripts/split-tests-for-ci.sh 1 4  # Get test files for group 1 of 4
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TESTS_DIR="${PROJECT_ROOT}/tests"

# Check arguments
if [[ $# -ne 2 ]]; then
	echo "Usage: $0 <group_number> <total_groups>" >&2
	echo "Example: $0 1 4  # Get test files for group 1 of 4" >&2
	exit 1
fi

GROUP_NUM="$1"
TOTAL_GROUPS="$2"

# Validate arguments
if ! [[ "$GROUP_NUM" =~ ^[0-9]+$ ]] || ! [[ "$TOTAL_GROUPS" =~ ^[0-9]+$ ]]; then
	echo "Error: Group number and total groups must be positive integers" >&2
	exit 1
fi

if [[ "$GROUP_NUM" -lt 1 ]] || [[ "$GROUP_NUM" -gt "$TOTAL_GROUPS" ]]; then
	echo "Error: Group number must be between 1 and $TOTAL_GROUPS" >&2
	exit 1
fi

if [[ "$TOTAL_GROUPS" -lt 1 ]]; then
	echo "Error: Total groups must be at least 1" >&2
	exit 1
fi

# Find all test files (matching test_*.sh pattern)
mapfile -t all_test_files < <(find "$TESTS_DIR" -name "test_*.sh" -type f | sort)

if [[ ${#all_test_files[@]} -eq 0 ]]; then
	echo "Error: No test files found in $TESTS_DIR" >&2
	exit 1
fi

# Calculate which files belong to this group
# Group numbers are 1-indexed, array indices are 0-indexed
TOTAL_TESTS=${#all_test_files[@]}
TESTS_PER_GROUP=$((TOTAL_TESTS / TOTAL_GROUPS))
REMAINDER=$((TOTAL_TESTS % TOTAL_GROUPS))

# Calculate start and end indices for this group
# Groups 1 through REMAINDER get one extra test
if [[ "$GROUP_NUM" -le "$REMAINDER" ]]; then
	START_IDX=$(((GROUP_NUM - 1) * (TESTS_PER_GROUP + 1)))
	END_IDX=$((START_IDX + TESTS_PER_GROUP))
else
	START_IDX=$((REMAINDER * (TESTS_PER_GROUP + 1) + (GROUP_NUM - REMAINDER - 1) * TESTS_PER_GROUP))
	END_IDX=$((START_IDX + TESTS_PER_GROUP - 1))
fi

# Output test files for this group
for ((i = START_IDX; i <= END_IDX && i < TOTAL_TESTS; i++)); do
	echo "${all_test_files[$i]}"
done
