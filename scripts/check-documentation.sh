#!/bin/bash
#
# Documentation checker for UDM VPN Monitor
# Validates that all functions have proper documentation blocks according to ADR-0007
#
# This script checks staged shell script files for function documentation compliance:
# - All functions must have documentation blocks before them
# - Documentation must include required sections: Arguments, Returns
# - Optional but recommended: Side effects, Examples, Notes
#
# Usage:
#   check-documentation.sh [file1.sh] [file2.sh] ...
#   If no files provided, checks all staged .sh files

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Track if any errors were found
ERRORS_FOUND=0

# Function to check if a function has proper documentation
check_function_documentation() {
	local file="$1"
	local func_line="$2"
	local func_name="$3"

	# Read lines before the function definition
	# Look for documentation block (comments starting with #)
	local has_doc=false
	local has_arguments=false
	local has_returns=false
	local doc_lines=()

	# Read backwards from function definition to find documentation
	local line_num=$func_line
	while [[ $line_num -gt 1 ]]; do
		line_num=$((line_num - 1))
		local line_content
		line_content=$(sed -n "${line_num}p" "$file")

		# Stop if we hit a non-comment, non-blank line (another function or code)
		if [[ ! "$line_content" =~ ^[[:space:]]*# ]] && [[ -n "${line_content// /}" ]]; then
			break
		fi

		# Collect documentation lines
		if [[ "$line_content" =~ ^[[:space:]]*# ]]; then
			has_doc=true
			doc_lines=("$line_content" "${doc_lines[@]}")

			# Check for required sections
			# Arguments section can be "Arguments:" or "Arguments: None" or similar
			if [[ "$line_content" =~ Arguments: ]]; then
				has_arguments=true
			fi
			if [[ "$line_content" =~ Returns: ]]; then
				has_returns=true
			fi
		fi
	done

	# Check if documentation exists
	if [[ "$has_doc" == false ]]; then
		echo -e "${RED}ERROR${NC}: Function '${func_name}' at line ${func_line} in ${file} is missing documentation block"
		echo "  All functions must have documentation blocks before their definition"
		ERRORS_FOUND=1
		return 1
	fi

	# Check for required sections
	local missing_sections=()
	if [[ "$has_arguments" == false ]]; then
		missing_sections+=("Arguments")
	fi
	if [[ "$has_returns" == false ]]; then
		missing_sections+=("Returns")
	fi

	if [[ ${#missing_sections[@]} -gt 0 ]]; then
		echo -e "${RED}ERROR${NC}: Function '${func_name}' at line ${func_line} in ${file} is missing required documentation sections:"
		for section in "${missing_sections[@]}"; do
			echo "  - ${section}"
		done
		ERRORS_FOUND=1
		return 1
	fi

	return 0
}

# Function to check a single file
check_file() {
	local file="$1"

	if [[ ! -f "$file" ]]; then
		echo "Warning: File not found: $file" >&2
		return 1
	fi

	# Find all function definitions
	# Pattern 1: function_name() { (most common)
	# Pattern 2: function function_name() { (less common but valid)
	# We'll search for both patterns
	local func_defs
	func_defs=$(grep -n -E '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\)[[:space:]]*\{|^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*\(\)[[:space:]]*\{' "$file" 2>/dev/null || true)

	if [[ -z "$func_defs" ]]; then
		# No functions found, skip file
		return 0
	fi

	# Process each function definition
	while IFS= read -r func_line_info; do
		if [[ -z "$func_line_info" ]]; then
			continue
		fi

		local func_line func_def
		func_line=$(echo "$func_line_info" | cut -d: -f1)
		func_def=$(echo "$func_line_info" | cut -d: -f2-)

		# Extract function name - handle both patterns
		local func_name
		# Try pattern: function_name() {
		func_name=$(echo "$func_def" | sed -n 's/^[[:space:]]*\([a-zA-Z_][a-zA-Z0-9_]*\)()[[:space:]]*{.*/\1/p')

		# If not found, try pattern: function function_name() {
		if [[ -z "$func_name" ]]; then
			func_name=$(echo "$func_def" | sed -n 's/^[[:space:]]*function[[:space:]]\+\([a-zA-Z_][a-zA-Z0-9_]*\)()[[:space:]]*{.*/\1/p')
		fi

		if [[ -z "$func_name" ]]; then
			continue
		fi

		# Skip certain internal/helper functions that might not need full documentation
		# These are typically very simple wrappers or internal helpers
		case "$func_name" in
		# Skip if it's a simple wrapper or internal function
		# We'll check all functions for now, but can add exceptions here if needed
		esac

		# Check documentation for this function
		check_function_documentation "$file" "$func_line" "$func_name"
	done <<<"$func_defs"
}

# Main execution
main() {
	local files_to_check=()

	# If files provided as arguments, use those
	if [[ $# -gt 0 ]]; then
		files_to_check=("$@")
	else
		# Otherwise, check staged .sh files
		if ! git rev-parse --git-dir >/dev/null 2>&1; then
			echo "Error: Not in a git repository" >&2
			exit 1
		fi

		# Get staged shell script files
		mapfile -t staged_files < <(git diff --cached --name-only --diff-filter=ACM | grep -E '\.sh$' || true)

		if [[ ${#staged_files[@]} -eq 0 ]]; then
			echo "No staged shell script files to check"
			return 0
		fi

		files_to_check=("${staged_files[@]}")
	fi

	# Check each file
	local checked_count=0
	for file in "${files_to_check[@]}"; do
		# Only check shell scripts
		if [[ ! "$file" =~ \.sh$ ]]; then
			continue
		fi

		check_file "$file"
		checked_count=$((checked_count + 1))
	done

	if [[ $checked_count -eq 0 ]]; then
		echo "No shell script files to check"
		return 0
	fi

	# Report results
	echo ""
	if [[ $ERRORS_FOUND -eq 0 ]]; then
		echo -e "${GREEN}✓ Documentation check passed${NC}"
		return 0
	else
		echo -e "${RED}✗ Documentation check failed${NC}"
		echo ""
		echo "Please add or fix documentation for the functions listed above."
		echo "See docs/adr/0007-comprehensive-in-code-documentation.md for documentation standards."
		return 1
	fi
}

# Run main function
main "$@"
