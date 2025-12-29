#!/bin/bash
#
# Version Update Script
# Updates version numbers across all files in the project
#
# Usage:
#   ./scripts/update-version.sh <new_version> [--dry-run]
#
# Examples:
#   ./scripts/update-version.sh 0.4.2
#   ./scripts/update-version.sh 0.4.2 --dry-run
#   ./scripts/update-version.sh 1.0.0
#
# Options:
#   --dry-run    Show what would be changed without making changes
#
# This script updates version numbers in:
#   - All script files (# Version: comments)
#   - vpn-monitor.sh and vpn-keepalive.sh (SCRIPT_VERSION variables)
#   - All lib/*.sh files (# Version: comments)
#   - Utility scripts (# Version: comments)

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
NEW_VERSION=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
	case $1 in
	--dry-run)
		DRY_RUN=1
		shift
		;;
	--help | -h)
		echo "Usage: $0 <new_version> [--dry-run]"
		echo ""
		echo "Updates version numbers across all project files."
		echo ""
		echo "Arguments:"
		echo "  new_version    New version number (e.g., 0.4.2, 1.0.0)"
		echo ""
		echo "Options:"
		echo "  --dry-run      Show what would be changed without making changes"
		echo "  --help, -h     Show this help message"
		echo ""
		echo "Examples:"
		echo "  $0 0.4.2"
		echo "  $0 0.4.2 --dry-run"
		echo "  $0 1.0.0"
		exit 0
		;;
	*)
		if [[ -z "$NEW_VERSION" ]]; then
			NEW_VERSION="$1"
		else
			echo -e "${RED}Error: Unknown argument: $1${NC}" >&2
			echo "Use --help for usage information" >&2
			exit 1
		fi
		shift
		;;
	esac
done

# Validate version argument provided
if [[ -z "$NEW_VERSION" ]]; then
	echo -e "${RED}Error: Version number required${NC}" >&2
	echo "Usage: $0 <new_version> [--dry-run]" >&2
	echo "Use --help for usage information" >&2
	exit 1
fi

# Validate version format (SemVer: MAJOR.MINOR.PATCH)
if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo -e "${RED}Error: Invalid version format: $NEW_VERSION${NC}" >&2
	echo "Version must be in SemVer format: MAJOR.MINOR.PATCH (e.g., 0.4.2, 1.0.0)" >&2
	exit 1
fi

# Escape string for sed regex pattern
#
# Escapes special regex characters in a string for use in sed pattern matching.
# This ensures that literal strings are matched correctly in sed regex patterns
# rather than being interpreted as regex metacharacters.
#
# Arguments:
#   $1: Value to escape
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints escaped string to stdout
escape_sed_regex() {
	local value="$1"
	# Escape regex special characters: [ \ . * ^ $ ( ) + ? { |
	# Use parameter expansion for better performance and to avoid shellcheck warnings
	local result="$value"
	result="${result//\\/\\\\}" # Escape backslashes first
	result="${result//\./\\.}"  # Escape dots
	result="${result//\[/\\[}"  # Escape [
	result="${result//\*/\\*}"  # Escape *
	result="${result//\^/\\^}"  # Escape ^
	result="${result//\$/\\$}"  # Escape $
	result="${result//\(/\\(}"  # Escape (
	result="${result//\)/\\)}"  # Escape )
	result="${result//\+/\\+}"  # Escape +
	result="${result//\?/\\?}"  # Escape ?
	result="${result//\{/\\{}"  # Escape {
	result="${result//\|/\\|}"  # Escape |
	echo "$result"
}

# Function to get current version from a file
get_current_version_from_file() {
	local file="$1"
	if [[ ! -f "$file" ]]; then
		return 1
	fi

	# Try SCRIPT_VERSION first
	local version
	version=$(grep -E '^SCRIPT_VERSION=["'\'']' "$file" 2>/dev/null | head -1 | sed -E "s/^SCRIPT_VERSION=[\"']([^\"']+)[\"'].*/\1/" | tr -d ' ')

	# Fallback to # Version: comment
	if [[ -z "$version" ]]; then
		version=$(grep -E '^# Version:' "$file" 2>/dev/null | head -1 | sed -E 's/^# Version:[[:space:]]*//' | tr -d ' ')
	fi

	if [[ -n "$version" ]]; then
		echo "$version"
		return 0
	fi

	return 1
}

# Function to update version in a file
update_version_in_file() {
	local file="$1"
	local old_version="$2"
	local new_version="$3"
	local dry_run="$4"

	if [[ ! -f "$file" ]]; then
		echo -e "${YELLOW}Warning: File not found: $file${NC}" >&2
		return 1
	fi

	local updated=0

	# Escape old_version for use in sed regex patterns (dots are special regex characters)
	# new_version doesn't need escaping for replacement string (no special chars in version numbers)
	local escaped_old_version
	escaped_old_version=$(escape_sed_regex "$old_version")

	# Update SCRIPT_VERSION variable
	if grep -q '^SCRIPT_VERSION=' "$file" 2>/dev/null; then
		if [[ $dry_run -eq 1 ]]; then
			echo -e "${BLUE}Would update${NC} SCRIPT_VERSION in $file: $old_version -> $new_version"
		else
			# Use sed to update SCRIPT_VERSION="..." or SCRIPT_VERSION='...'
			# Escape old_version for regex matching, new_version is in replacement (no escaping needed for literal replacement)
			if sed -i.tmp "s/^SCRIPT_VERSION=[\"']${escaped_old_version}[\"']/SCRIPT_VERSION=\"${new_version}\"/" "$file" 2>/dev/null; then
				rm -f "${file}.tmp" 2>/dev/null || true
				updated=1
			fi
		fi
	fi

	# Update # Version: comment
	if grep -q '^# Version:' "$file" 2>/dev/null; then
		if [[ $dry_run -eq 1 ]]; then
			if [[ $updated -eq 0 ]]; then
				echo -e "${BLUE}Would update${NC} # Version: in $file: $old_version -> $new_version"
			fi
		else
			# Escape old_version for regex matching, new_version is literal in replacement
			if sed -i.tmp "s/^# Version: ${escaped_old_version}/# Version: ${new_version}/" "$file" 2>/dev/null; then
				rm -f "${file}.tmp" 2>/dev/null || true
				updated=1
			fi
		fi
	fi

	if [[ $dry_run -eq 0 ]] && [[ $updated -eq 1 ]]; then
		echo -e "${GREEN}Updated${NC} $file"
	fi

	return 0
}

# Find all files that need version updates
find_files_with_versions() {
	local files=()

	# Main scripts with SCRIPT_VERSION
	if [[ -f "${PROJECT_ROOT}/vpn-monitor.sh" ]]; then
		files+=("${PROJECT_ROOT}/vpn-monitor.sh")
	fi
	if [[ -f "${PROJECT_ROOT}/vpn-keepalive.sh" ]]; then
		files+=("${PROJECT_ROOT}/vpn-keepalive.sh")
	fi

	# Installation scripts
	if [[ -f "${PROJECT_ROOT}/install.sh" ]]; then
		files+=("${PROJECT_ROOT}/install.sh")
	fi
	if [[ -f "${PROJECT_ROOT}/uninstall.sh" ]]; then
		files+=("${PROJECT_ROOT}/uninstall.sh")
	fi

	# Utility scripts
	for util in analyze-logs.sh check-config.sh check-utilities.sh; do
		if [[ -f "${PROJECT_ROOT}/${util}" ]]; then
			files+=("${PROJECT_ROOT}/${util}")
		fi
	done

	# Library files
	if [[ -d "${PROJECT_ROOT}/lib" ]]; then
		while IFS= read -r -d '' file; do
			files+=("$file")
		done < <(find "${PROJECT_ROOT}/lib" -name "*.sh" -type f -print0 | sort -z)
	fi

	printf '%s\n' "${files[@]}"
}

# Main execution
main() {
	echo -e "${BLUE}Version Update Script${NC}"
	echo "======================"
	echo ""

	# Get current version from vpn-monitor.sh
	local current_version
	current_version=$(get_current_version_from_file "${PROJECT_ROOT}/vpn-monitor.sh" || echo "unknown")

	if [[ "$current_version" == "unknown" ]]; then
		echo -e "${YELLOW}Warning: Could not determine current version${NC}" >&2
		echo "Proceeding with update anyway..." >&2
		echo ""
	else
		echo -e "Current version: ${GREEN}${current_version}${NC}"
		echo -e "New version:     ${GREEN}${NEW_VERSION}${NC}"
		echo ""

		if [[ "$current_version" == "$NEW_VERSION" ]]; then
			echo -e "${YELLOW}Warning: New version is the same as current version${NC}" >&2
			echo "No changes will be made." >&2
			exit 0
		fi
	fi

	# Find all files
	local files
	mapfile -t files < <(find_files_with_versions)

	if [[ ${#files[@]} -eq 0 ]]; then
		echo -e "${RED}Error: No files found to update${NC}" >&2
		exit 1
	fi

	echo -e "Files to update: ${#files[@]}"
	echo ""

	if [[ $DRY_RUN -eq 1 ]]; then
		echo -e "${YELLOW}DRY RUN MODE - No files will be modified${NC}"
		echo ""
	fi

	# Update each file
	local updated_count=0
	local failed_count=0

	for file in "${files[@]}"; do
		local file_version
		file_version=$(get_current_version_from_file "$file" || echo "")

		if [[ -n "$file_version" ]]; then
			if update_version_in_file "$file" "$file_version" "$NEW_VERSION" "$DRY_RUN"; then
				((updated_count++)) || true
			else
				((failed_count++)) || true
			fi
		else
			echo -e "${YELLOW}Warning: Could not find version in $file${NC}" >&2
		fi
	done

	echo ""

	# Summary
	if [[ $DRY_RUN -eq 1 ]]; then
		echo -e "${BLUE}Dry run complete${NC}"
		echo "Would update ${updated_count} file(s)"
	else
		if [[ $failed_count -eq 0 ]]; then
			echo -e "${GREEN}Successfully updated ${updated_count} file(s)${NC}"
		else
			echo -e "${YELLOW}Updated ${updated_count} file(s), ${failed_count} failed${NC}" >&2
			exit 1
		fi
	fi

	# Verify updates
	if [[ $DRY_RUN -eq 0 ]]; then
		echo ""
		echo "Verifying updates..."
		local verify_count=0
		for file in "${files[@]}"; do
			local file_version
			file_version=$(get_current_version_from_file "$file" || echo "")
			if [[ "$file_version" == "$NEW_VERSION" ]]; then
				((verify_count++)) || true
			fi
		done

		if [[ $verify_count -eq ${#files[@]} ]]; then
			echo -e "${GREEN}✓ All files verified: ${verify_count}/${#files[@]} have version ${NEW_VERSION}${NC}"
		else
			echo -e "${YELLOW}⚠ Verification incomplete: ${verify_count}/${#files[@]} have version ${NEW_VERSION}${NC}" >&2
			echo "Some files may need manual review." >&2
		fi
	fi
}

# Run main function
main
