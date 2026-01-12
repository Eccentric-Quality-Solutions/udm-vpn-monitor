#!/usr/bin/env bash
#
# Check for missing prefix parameters in log_message and handle_error calls
#
# This script searches for calls to log_message and handle_error that are missing
# the required prefix parameter (location name or "SYSTEM").
#
# A correct call should have: function "LEVEL" "PREFIX" "message..." [exit_code]
# An incorrect call has: function "LEVEL" "message..." [exit_code] (missing prefix)
#
# Exit code:
#   0: No issues found
#   1: Issues found

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Find all shell script files
# Exclude test files and coverage directory
mapfile -t script_files < <(find . -type f \( -name "*.sh" -o -name "*.bash" \) \
	-not -path "./tests/*" \
	-not -path "./coverage/*" \
	-not -path "./.git/*" \
	-not -name "check-logging-prefix.sh" |
	sort)

issues_found=0
files_with_issues=()

echo "Checking for missing prefix parameters in log_message and handle_error calls..."
echo ""

for file in "${script_files[@]}"; do
	# Skip if file doesn't exist (might be deleted)
	[[ ! -f "$file" ]] && continue

	file_issues=0

	# Find all log_message and handle_error calls
	# Process each matching line
	# grep -n outputs "line_num:content", so we need to split on first colon only
	while IFS= read -r grep_line; do
		# Split on first colon only to get line number and content
		line_num="${grep_line%%:*}"
		line_content="${grep_line#*:}"
		# Skip comment lines
		if [[ "$line_content" =~ ^[[:space:]]*# ]]; then
			continue
		fi

		# Check if line contains log_message or handle_error
		if [[ ! "$line_content" =~ (log_message|handle_error) ]]; then
			continue
		fi

		# Extract function call: function "LEVEL" "SECOND_ARG"
		# Use regex to match: function "LEVEL" "ARG2"
		if [[ "$line_content" =~ (log_message|handle_error)[[:space:]]+\"(INFO|WARNING|ERROR|DEBUG)\"[[:space:]]+\"([^\"]+)\" ]]; then
			func_name="${BASH_REMATCH[1]}"
			level="${BASH_REMATCH[2]}"
			second_arg="${BASH_REMATCH[3]}"

			# Check if second_arg is a valid prefix
			is_valid_prefix=0

			# Check for exact "SYSTEM"
			if [[ "$second_arg" == "SYSTEM" ]]; then
				is_valid_prefix=1
			# Check for variable patterns like "${location_name:-SYSTEM}" or "$location_name"
			elif [[ "$second_arg" =~ ^\$\{.*\}$ ]] || [[ "$second_arg" =~ ^\$[A-Za-z_][A-Za-z0-9_]*$ ]]; then
				is_valid_prefix=1
			# Check for short uppercase location names (1-10 chars, all caps, no spaces, no colons)
			elif [[ ${#second_arg} -le 10 ]] && [[ "$second_arg" =~ ^[A-Z_]+$ ]] && [[ ! "$second_arg" =~ [[:space:]:] ]]; then
				is_valid_prefix=1
			fi

			# If not a valid prefix, check if it looks like a message
			if [[ $is_valid_prefix -eq 0 ]]; then
				# Check if it looks like a message
				looks_like_message=0

				# Has spaces or colons?
				if [[ "$second_arg" =~ [[:space:]:] ]]; then
					looks_like_message=1
				# Is longer than 15 characters?
				elif [[ ${#second_arg} -gt 15 ]]; then
					looks_like_message=1
				# Has lowercase letters (and not a variable pattern)?
				elif [[ "$second_arg" =~ [a-z] ]] && [[ ! "$second_arg" =~ \$\{.*\} ]]; then
					looks_like_message=1
				fi

				if [[ $looks_like_message -eq 1 ]]; then
					echo -e "${RED}ERROR${NC}: $file:$line_num"
					echo "  Missing prefix parameter in $func_name call"
					echo "  Line: $line_content"
					echo "  Second argument '$second_arg' appears to be a message, not a prefix"
					echo "  Expected: $func_name \"$level\" \"SYSTEM\" \"...\" or $func_name \"$level\" \"LOCATION\" \"...\""
					echo ""
					((file_issues++))
					((issues_found++))
				fi
			fi
		fi
	done < <(grep -n -E "(log_message|handle_error)\s+\"(INFO|WARNING|ERROR|DEBUG)\"" "$file" 2>/dev/null || true)

	if [[ $file_issues -gt 0 ]]; then
		files_with_issues+=("$file")
	fi
done

echo "=========================================="
if [[ $issues_found -eq 0 ]]; then
	echo -e "${GREEN}✓ No issues found${NC}"
	echo "All log_message and handle_error calls have the required prefix parameter."
	exit 0
else
	echo -e "${RED}✗ Found $issues_found issue(s) in ${#files_with_issues[@]} file(s)${NC}"
	echo ""
	echo "Files with issues:"
	for file in "${files_with_issues[@]}"; do
		echo "  - $file"
	done
	echo ""
	echo "Each issue shows a call where the prefix parameter (SYSTEM or location name) is missing."
	echo "The second argument after the log level should be the prefix, not the message."
	exit 1
fi
