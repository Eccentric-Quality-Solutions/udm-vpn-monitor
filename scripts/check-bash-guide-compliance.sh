#!/bin/bash
#
# Check Bash Coding Guide Compliance
#
# This script checks all shell script files (including tests) for compliance
# with patterns and best practices documented in docs/BASH_CODING_GUIDE.md
#
# Checks performed:
#   1. Array iteration using [*] instead of [@] (ISSUE)
#   2. Using $0 instead of BASH_SOURCE[0] for script directory (WARNING)
#   3. Array emptiness checks using wrong syntax (WARNING)
#   4. Missing 'local' declarations in functions (WARNING)
#   5. Associative arrays used without declaration (ISSUE)
#
# Note: Unquoted variable checks are skipped - use ShellCheck for that.
#
# Usage:
#   ./scripts/check-bash-guide-compliance.sh [file1.sh] [file2.sh] ...
#   If no files provided, checks all .sh files in the repository
#
# Exit codes:
#   0: All checks passed (or only warnings found)
#   1: One or more issues found

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track issues
ISSUES_FOUND=0
WARNINGS_FOUND=0
FILES_CHECKED=0

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Check for array iteration using [*] instead of [@]
#
# Arguments:
#   $1: File path
#   $2: Line number
#   $3: Line content
#
# Returns:
#   0: No issue found
#   1: Issue found (increments ISSUES_FOUND)
check_array_iteration() {
	local file="$1"
	local line_num="$2"
	local line="$3"

	# Check for "${array[*]}" in for loops (common mistake)
	if echo "$line" | grep -qE 'for\s+\w+\s+in\s+"\$\{[^}]+\[\*\]"'; then
		echo -e "${RED}Issue in $file:${NC}"
		echo -e "  Line $line_num: ${RED}Using [*] instead of [@] for array iteration${NC}"
		echo "  ${line}"
		echo "  Use \"\${array[@]}\" to preserve individual elements"
		echo ""
		ISSUES_FOUND=$((ISSUES_FOUND + 1))
		return 1
	fi

	return 0
}

# Check for unquoted variable expansions
#
# Note: This is a simplified check that focuses on obvious cases.
# Full unquoted variable detection is complex and best handled by ShellCheck.
#
# Arguments:
#   $1: File path
#   $2: Line number
#   $3: Line content
#
# Returns:
#   0: No issue found
#   1: Issue found (increments WARNINGS_FOUND)
check_unquoted_variables() {
	local file="$1"
	local line_num="$2"
	local line="$3"

	# Skip comments and shebang
	if echo "$line" | grep -qE '^\s*#|^#!/'; then
		return 0
	fi

	# Skip lines that are clearly in strings or documentation
	if echo "$line" | grep -qE 'echo.*"\$|printf.*"\$|#.*\$|here-doc|<<'; then
		return 0
	fi

	# Check for very obvious cases: command followed by $VAR without quotes
	# Pattern: spaces, then $VAR_NAME (uppercase, typical for constants) not in quotes
	# Focus on common commands that take file paths
	if echo "$line" | grep -qE '\s(cp|mv|rm|cat|grep|sed|awk|test|\[\[)\s+[^"]*\$[A-Z_][A-Z0-9_]+[^"]'; then
		# Check if it's actually unquoted (simple check)
		# Look for $VAR not immediately after a quote
		if echo "$line" | grep -qE '[^"]\s+\$[A-Z_][A-Z0-9_]+[^"]'; then
			# Make sure it's not part of "${VAR}" or "$VAR"
			if ! echo "$line" | grep -qE '"\$[A-Z_]|\$\{[A-Z_][A-Z0-9_]*\}'; then
				echo -e "${YELLOW}Warning in $file:${NC}"
				echo -e "  Line $line_num: ${YELLOW}Possible unquoted variable expansion${NC}"
				echo "  ${line}"
				echo "  Consider quoting variables: \"\${VAR}\""
				echo "  Note: Use ShellCheck for comprehensive variable quoting checks"
				echo ""
				WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
				return 1
			fi
		fi
	fi

	return 0
}

# Check for using $0 instead of BASH_SOURCE[0] for script directory
#
# Arguments:
#   $1: File path
#   $2: Line number
#   $3: Line content
#
# Returns:
#   0: No issue found
#   1: Issue found (increments WARNINGS_FOUND)
check_script_directory() {
	local file="$1"
	local line_num="$2"
	local line="$3"

	# Check for dirname "$0" pattern (should use BASH_SOURCE[0] for sourced scripts)
	if echo "$line" | grep -qE 'dirname\s+"?\$0"?'; then
		echo -e "${YELLOW}Warning in $file:${NC}"
		echo -e "  Line $line_num: ${YELLOW}Using \$0 instead of BASH_SOURCE[0]${NC}"
		echo "  ${line}"
		echo "  Use \"\${BASH_SOURCE[0]}\" for sourced scripts (works correctly when sourced)"
		echo ""
		WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
		return 1
	fi

	return 0
}

# Check for missing local declarations in functions
#
# Arguments:
#   $1: File path
#   $2: Line number
#   $3: Line content
#   $4: Array of lines (for context)
#   $5: Current index in array
#   $6: Function start line (cached)
#
# Returns:
#   0: No issue found
#   1: Issue found (increments WARNINGS_FOUND)
check_missing_local() {
	local file="$1"
	local line_num="$2"
	local line="$3"
	local -n lines_ref="$4"
	local idx="$5"
	local func_start_line="${6:-0}"

	# Only check inside functions - use cached function start if provided
	local in_function=false
	if [[ $func_start_line -gt 0 ]] && [[ $line_num -gt $func_start_line ]]; then
		in_function=true
	else
		# Look backwards to see if we're in a function (limit to 20 lines for performance)
		local i=$idx
		local lookback=0
		while [[ $i -ge 0 ]] && [[ $lookback -lt 20 ]]; do
			if echo "${lines_ref[$i]}" | grep -qE '^\s*[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)\s*\{|^\s*function\s+'; then
				in_function=true
				break
			fi
			# Stop if we hit another function or top-level code
			if [[ $i -lt $idx ]] && echo "${lines_ref[$i]}" | grep -qE '^\s*[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)\s*\{|^\s*function\s+'; then
				break
			fi
			i=$((i - 1))
			lookback=$((lookback + 1))
		done
	fi

	if [[ "$in_function" != "true" ]]; then
		return 0
	fi

	# Check for variable assignments without 'local' in functions
	# Pattern: VAR_NAME=value (not local VAR_NAME=value)
	# Exclude: readonly, declare, export, typeset
	# Exclude: function parameters $1, $2, etc.
	# Exclude: already declared with local/declare/readonly
	if echo "$line" | grep -qE '^\s*[A-Z_][A-Z0-9_]*='; then
		# Check if it's already declared
		if echo "$line" | grep -qE '^\s*(local|declare|readonly|export|typeset)\s+'; then
			return 0
		fi
		# Check if it's a function parameter
		if echo "$line" | grep -qE '=\$\{?[0-9]'; then
			return 0
		fi
		# Extract variable name
		local var_name
		var_name=$(echo "$line" | sed -E 's/^\s*([A-Z_][A-Z0-9_]*)=.*/\1/')
		# Check if it's a constant (all caps with underscores)
		if echo "$var_name" | grep -qE '^[A-Z_][A-Z0-9_]*$'; then
			# This might be intentional (global constant), but warn
			echo -e "${YELLOW}Warning in $file:${NC}"
			echo -e "  Line $line_num: ${YELLOW}Variable assignment in function without 'local': $var_name${NC}"
			echo "  ${line}"
			echo "  Consider using 'local $var_name=...' to avoid global scope pollution"
			echo ""
			WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
			return 1
		fi
	fi

	return 0
}

# Check for array emptiness checks
#
# Arguments:
#   $1: File path
#   $2: Line number
#   $3: Line content
#
# Returns:
#   0: No issue found
#   1: Issue found (increments WARNINGS_FOUND)
check_array_empty() {
	local file="$1"
	local line_num="$2"
	local line="$3"

	# Check for incorrect array length checks
	# Pattern: ${#array} instead of ${#array[@]}
	if echo "$line" | grep -qE '\$\{#\w+\[@\]\}' && echo "$line" | grep -qE '\[@\]\s*-eq\s*0|\[@\]\s*-gt\s*0'; then
		# This is correct, skip
		return 0
	fi

	# Check for ${#array} (without [@]) - this gives length of first element, not array size
	if echo "$line" | grep -qE '\$\{#\w+\}\s*-eq\s*0|\$\{#\w+\}\s*-gt\s*0'; then
		# Check if it's actually an array (has [@] or [*] somewhere nearby)
		if echo "$line" | grep -qE '\[@\]|\[\*\]'; then
			echo -e "${YELLOW}Warning in $file:${NC}"
			echo -e "  Line $line_num: ${YELLOW}Possible incorrect array length check${NC}"
			echo "  ${line}"
			echo "  Use \${#array[@]} for array length, not \${#array}"
			echo ""
			WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
			return 1
		fi
	fi

	return 0
}

# Check for missing associative array declarations
#
# Arguments:
#   $1: File path
#   $2: Line number
#   $3: Line content
#   $4: Array of lines (for context)
#   $5: Current index in array
#
# Returns:
#   0: No issue found
#   1: Issue found (increments ISSUES_FOUND)
check_associative_array_declaration() {
	local file="$1"
	local line_num="$2"
	local line="$3"
	local -n lines_ref="$4"
	local idx="$5"

	# Check for array[key]=value pattern
	if echo "$line" | grep -qE '\w+\[["'\''][^"'\'']+["'\'']\]\s*='; then
		# Extract array name
		local array_name
		array_name=$(echo "$line" | sed -E 's/^[^[]*([A-Za-z_][A-Za-z0-9_]*)\[.*/\1/')
		
		# Look backwards for declare -A or local -A (limit to 30 lines for performance)
		local found_declare=false
		local i=$idx
		local lookback=0
		while [[ $i -ge 0 ]] && [[ $lookback -lt 30 ]]; do
			if echo "${lines_ref[$i]}" | grep -qE "(declare|local)\s+-[aA]\s+${array_name}|declare\s+-[aA]\s+${array_name}|local\s+-[aA]\s+${array_name}"; then
				found_declare=true
				break
			fi
			# Stop if we hit a function boundary
			if [[ $i -lt $idx ]] && echo "${lines_ref[$i]}" | grep -qE '^\s*[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)\s*\{|^\s*function\s+'; then
				break
			fi
			i=$((i - 1))
			lookback=$((lookback + 1))
		done

		if [[ "$found_declare" != "true" ]]; then
			echo -e "${RED}Issue in $file:${NC}"
			echo -e "  Line $line_num: ${RED}Associative array '$array_name' used without declaration${NC}"
			echo "  ${line}"
			echo "  Add: declare -A $array_name=() or local -A $array_name=() before use"
			echo ""
			ISSUES_FOUND=$((ISSUES_FOUND + 1))
			return 1
		fi
	fi

	return 0
}

# Check a single file for compliance
#
# Arguments:
#   $1: File path to check
#
# Returns:
#   0: File checked successfully
#   1: File not found or error
check_file() {
	local file="$1"

	if [[ ! -f "$file" ]]; then
		echo -e "${YELLOW}Warning: File not found: $file${NC}" >&2
		return 1
	fi

	# Skip very large files (likely generated or not source code)
	local file_size
	file_size=$(wc -l <"$file" 2>/dev/null || echo "0")
	if [[ $file_size -gt 2000 ]]; then
		# Skip silently for large files to speed up
		return 0
	fi

	# Read file into array
	mapfile -t lines <"$file"

	# Pre-scan for function boundaries to optimize checks
	declare -A func_starts=()
	local i=0
	while [[ $i -lt ${#lines[@]} ]]; do
		if echo "${lines[$i]}" | grep -qE '^\s*[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)\s*\{|^\s*function\s+'; then
			func_starts[$i]=$((i + 1))
		fi
		i=$((i + 1))
	done

	# Check each line
	i=0
	local current_func_start=0
	while [[ $i -lt ${#lines[@]} ]]; do
		local line="${lines[$i]}"
		local line_num=$((i + 1))

		# Update current function start if we hit a new function
		if [[ -n "${func_starts[$i]:-}" ]]; then
			current_func_start=$line_num
		fi

		# Skip empty lines for some checks
		if [[ -z "${line// /}" ]]; then
			i=$((i + 1))
			continue
		fi

		# Run fast checks on every line
		check_array_iteration "$file" "$line_num" "$line" || true
		check_script_directory "$file" "$line_num" "$line" || true
		check_array_empty "$file" "$line_num" "$line" || true
		
		# Run expensive checks only on non-empty, non-comment lines
		# and only if we haven't found too many issues
		if [[ $ISSUES_FOUND -lt 50 ]] && [[ $WARNINGS_FOUND -lt 200 ]]; then
			if [[ ! "$line" =~ ^[[:space:]]*# ]] && [[ -n "${line// /}" ]]; then
				# Skip unquoted variables check - ShellCheck does this better
				# check_unquoted_variables "$file" "$line_num" "$line" || true
				
				# Only check missing local and associative arrays on lines that look relevant
				if echo "$line" | grep -qE '^\s*[A-Z_][A-Z0-9_]*='; then
					check_missing_local "$file" "$line_num" "$line" "lines" "$i" "$current_func_start" || true
				fi
				if echo "$line" | grep -qE '\[["'\''][^"'\'']+["'\'']\]\s*='; then
					check_associative_array_declaration "$file" "$line_num" "$line" "lines" "$i" || true
				fi
			fi
		fi

		i=$((i + 1))
	done

	return 0
}

# Main function
#
# Arguments:
#   $@: Optional list of files to check
#
# Returns:
#   0: All checks passed
#   1: Issues found
main() {
	local files_to_check=()

	# If files provided as arguments, use those
	if [[ $# -gt 0 ]]; then
		files_to_check=("$@")
	else
		# Find all .sh files in the repository, excluding generated/coverage directories
		while IFS= read -r -d '' file; do
			files_to_check+=("$file")
		done < <(find "$REPO_ROOT" -type f -name "*.sh" \
			-not -path "*/\.*" \
			-not -path "*/coverage/*" \
			-not -path "*/logs/*" \
			-not -path "*/analyze/*" \
			-not -path "*/reports/*" \
			-print0 | sort -z)
	fi

	if [[ ${#files_to_check[@]} -eq 0 ]]; then
		echo "No shell script files found to check"
		return 0
	fi

	echo -e "${BLUE}Checking Bash Coding Guide compliance...${NC}"
	echo "Found ${#files_to_check[@]} shell script files to check"
	echo "=================================================="
	echo ""

	# Check each file
	local file_count=0
	for file in "${files_to_check[@]}"; do
		# Make path relative to repo root for cleaner output
		local rel_file="${file#$REPO_ROOT/}"
		if [[ "$rel_file" == "$file" ]]; then
			rel_file="$file"
		fi

		# Skip if not a shell script
		if [[ ! "$file" =~ \.sh$ ]]; then
			continue
		fi

		file_count=$((file_count + 1))
		# Show progress every 10 files
		if [[ $((file_count % 10)) -eq 0 ]]; then
			echo -e "${BLUE}Progress: $file_count/${#files_to_check[@]} files checked...${NC}" >&2
		fi

		check_file "$file" || true
		FILES_CHECKED=$((FILES_CHECKED + 1))
	done

	echo "=================================================="
	echo "Summary:"
	echo "  Files checked: $FILES_CHECKED"
	echo "  Issues found: $ISSUES_FOUND"
	echo "  Warnings: $WARNINGS_FOUND"
	echo ""

	if [[ $ISSUES_FOUND -eq 0 ]] && [[ $WARNINGS_FOUND -eq 0 ]]; then
		echo -e "${GREEN}✓ All checks passed${NC}"
		return 0
	elif [[ $ISSUES_FOUND -eq 0 ]]; then
		echo -e "${YELLOW}⚠ Some warnings found (non-critical)${NC}"
		echo "  Review warnings above and consider fixing them"
		return 0
	else
		echo -e "${RED}✗ Found $ISSUES_FOUND issue(s)${NC}"
		echo "  Please review and fix the issues listed above"
		echo "  See docs/BASH_CODING_GUIDE.md for best practices"
		return 1
	fi
}

# Run main function
main "$@"
