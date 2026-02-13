#!/bin/bash
#
# Documentation checker for UDM VPN Monitor
# Validates that all functions have proper documentation blocks according to ADR-0007
#
# This script checks staged shell script files for function documentation compliance:
# - All functions must have documentation blocks before them (at least a brief description)
# - Non-trivial functions must include required sections: Arguments, Returns
# - Trivial functions (1-3 lines of code, simple wrappers) only need a brief description
# - Optional but recommended: Side effects, Examples, Notes
#
# Documentation requirements:
#   - Trivial functions: Brief description only (Arguments/Returns optional)
#   - Non-trivial functions: Brief description + Arguments + Returns sections required
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

# Check if a function is trivial (simple enough to allow minimal documentation)
#
# Determines if a function is trivial enough to allow minimal documentation
# (brief description only, without Arguments/Returns sections). A function is
# considered trivial if it:
# - Has a very short body (1-3 lines of actual code, excluding braces/comments)
# - Is a simple wrapper, one-liner, or self-explanatory utility
#
# Arguments:
#   $1: Path to the file containing the function
#   $2: Line number where the function is defined
#
# Returns:
#   0: Function is trivial (allows minimal documentation)
#   1: Function is not trivial (requires full documentation)
#
# Side effects:
#   None
#
# Note:
#   Reads the function body to count non-comment, non-blank, non-brace lines
#   Functions with 3 or fewer lines of actual code are considered trivial
is_trivial_function() {
	local file="$1"
	local func_line="$2"

	# Find the end of the function (next function definition or end of file)
	local total_lines
	total_lines=$(wc -l <"$file")
	local line_num=$func_line
	local brace_count=0
	local code_lines=0

	# Read forward from function definition
	while [[ $line_num -le $total_lines ]]; do
		local line_content
		line_content=$(sed -n "${line_num}p" "$file")

		# Count opening braces
		if [[ "$line_content" =~ \{ ]]; then
			brace_count=$((brace_count + 1))
		fi

		# Count closing braces
		if [[ "$line_content" =~ \} ]]; then
			brace_count=$((brace_count - 1))
			# If we've closed all braces, we've reached the end of the function
			if [[ $brace_count -le 0 ]]; then
				break
			fi
		fi

		# Count non-comment, non-blank, non-brace-only lines as code
		if [[ $line_num -gt $func_line ]]; then
			# Skip lines that are only braces, whitespace, or comments
			local stripped_line="${line_content// /}"
			stripped_line="${stripped_line//\t/}"
			if [[ -n "$stripped_line" ]] &&
				[[ ! "$stripped_line" =~ ^# ]] &&
				[[ ! "$stripped_line" =~ ^\{?[[:space:]]*\}?$ ]]; then
				code_lines=$((code_lines + 1))
			fi
		fi

		line_num=$((line_num + 1))

		# Safety limit: if we haven't found the end after 50 lines, assume it's not trivial
		if [[ $((line_num - func_line)) -gt 50 ]]; then
			return 1
		fi
	done

	# Functions with 3 or fewer lines of actual code are considered trivial
	if [[ $code_lines -le 3 ]]; then
		return 0
	fi

	return 1
}

# Check if a function has proper documentation according to ADR-0007
#
# Validates that a function has a documentation block before its definition.
# For non-trivial functions, also requires Arguments and Returns sections.
# For trivial functions (simple one-liners, wrappers), only a brief description
# is required. Reads backwards from the function definition line to find
# documentation comments.
#
# Arguments:
#   $1: Path to the file containing the function
#   $2: Line number where the function is defined
#   $3: Name of the function to check
#
# Returns:
#   0: Function has proper documentation
#   1: Function is missing documentation or required sections
#
# Side effects:
#   - Prints error messages to stdout if documentation is missing or incomplete
#   - Sets ERRORS_FOUND global variable to 1 if issues are found
#
# Examples:
#   check_function_documentation "lib/config.sh" 42 "validate_config"
#   # Checks if validate_config() at line 42 has proper documentation
#
# Note:
#   Stops reading backwards when it encounters a non-comment, non-blank line
#   (indicating another function or code block)
#   Looks for "Arguments:" and "Returns:" sections in documentation comments
#   Documentation must be in comment blocks (lines starting with #)
#   Trivial functions (1-3 lines of code) only need a brief description
check_function_documentation() {
	local file="$1"
	local func_line="$2"
	local func_name="$3"

	# Check if this is a trivial function
	local is_trivial=false
	if is_trivial_function "$file" "$func_line"; then
		is_trivial=true
	fi

	# Read lines before the function definition
	# Look for documentation block (comments starting with #)
	local has_doc=false
	local has_arguments=false
	local has_returns=false
	local doc_lines=()
	local has_description=false

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
			# Skip shebang lines (#!/bin/bash, etc.) - they're not function documentation
			if [[ "$line_content" =~ ^#! ]]; then
				break
			fi

			has_doc=true
			doc_lines=("$line_content" "${doc_lines[@]}")

			# Check for description (any non-empty comment that's not just a section header)
			# A description should have some actual text content, not just punctuation/symbols
			local stripped="${line_content#\#}"
			stripped="${stripped// /}"
			# Remove common punctuation/symbols to see if there's actual content
			local content_only="${stripped//[!a-zA-Z0-9]/}"
			if [[ -n "$content_only" ]] &&
				[[ ${#content_only} -ge 3 ]] &&
				[[ ! "$stripped" =~ ^(Arguments|Returns|Sideeffects|Examples|Note): ]]; then
				has_description=true
			fi

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
		echo "  All functions must have at least a brief description before their definition"
		ERRORS_FOUND=1
		return 1
	fi

	# For trivial functions, only require a brief description
	if [[ "$is_trivial" == true ]]; then
		if [[ "$has_description" == false ]]; then
			echo -e "${RED}ERROR${NC}: Function '${func_name}' at line ${func_line} in ${file} is missing a brief description"
			echo "  Trivial functions must have at least a brief description comment"
			ERRORS_FOUND=1
			return 1
		fi
		# Trivial functions don't require Arguments/Returns sections
		return 0
	fi

	# For non-trivial functions, require Arguments and Returns sections
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
		echo "  Non-trivial functions require Arguments and Returns sections"
		ERRORS_FOUND=1
		return 1
	fi

	return 0
}

# Check a single file for function documentation compliance
#
# Scans a shell script file for function definitions and validates that each
# function has proper documentation. Uses grep to find function definitions
# matching common patterns (function_name() { or function function_name() {),
# then checks each function's documentation.
#
# Arguments:
#   $1: Path to the shell script file to check
#
# Returns:
#   0: File has no functions or all functions have proper documentation
#   1: One or more functions are missing documentation or required sections
#
# Side effects:
#   - Prints error messages to stdout for functions with missing documentation
#   - Sets ERRORS_FOUND global variable to 1 if issues are found
#   - Skips files that don't exist (prints warning to stderr)
#
# Examples:
#   check_file "lib/config.sh"
#   # Checks all functions in lib/config.sh for documentation compliance
#
# Note:
#   Only processes files that exist
#   Handles both function definition styles: name() { and function name() {
#   Skips files with no function definitions
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
		# Use || true to prevent set -e from exiting early - we want to check all functions
		check_function_documentation "$file" "$func_line" "$func_name" || true
	done <<<"$func_defs"
}

# Main execution function
#
# Orchestrates the documentation checking process. Determines which files to
# check (either from command-line arguments or from git staged files), runs
# documentation checks on each file, and reports results. Exits with error
# code if any documentation issues are found.
#
# Arguments:
#   $@: Optional list of specific files to check. If not provided, checks all
#       staged .sh files in the git repository.
#
# Returns:
#   0: All checked functions have proper documentation
#   1: One or more functions are missing documentation or required sections
#
# Side effects:
#   - Prints check progress and results to stdout
#   - Prints colored output (green for success, red for errors)
#   - Exits script with appropriate exit code
#   - Requires git repository (if no files provided as arguments)
#
# Examples:
#   main
#   # Checks all staged .sh files in git repository
#
#   main "lib/config.sh" "lib/detection.sh"
#   # Checks only the specified files
#
# Note:
#   Requires git repository if checking staged files
#   Only processes .sh files (skips other file types)
#   If no files are provided and no staged .sh files exist, returns success
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

		# Use || true to prevent set -e from exiting early - we want to check all files
		check_file "$file" || true
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
