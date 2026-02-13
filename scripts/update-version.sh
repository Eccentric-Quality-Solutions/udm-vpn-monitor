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
#
# When the only change in a file is the version update, the file is
# automatically staged with git add.

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

# Get current version number from a file
#
# Extracts the version number from a file by checking for SCRIPT_VERSION variable
# assignments or # Version: comments. Tries SCRIPT_VERSION first (for main scripts),
# then falls back to # Version: comment (for library and utility scripts).
#
# Arguments:
#   $1: Path to the file to extract version from
#
# Returns:
#   0: Version found and printed to stdout
#   1: File doesn't exist or version not found
#
# Output:
#   Prints version number to stdout (e.g., "0.4.2") if found
#
# Side effects:
#   None
#
# Examples:
#   version=$(get_current_version_from_file "vpn-monitor.sh")
#   # Sets version to "0.4.2" if found
#
#   if get_current_version_from_file "lib/config.sh"; then
#       echo "Version found"
#   fi
#
# Note:
#   Handles both SCRIPT_VERSION="..." and SCRIPT_VERSION='...' formats
#   Handles # Version: comment format
#   Trims whitespace from extracted version
#   Returns first match if multiple version declarations exist
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

# Update version number in a file
#
# Replaces the old version number with a new version number in a file. Updates
# both SCRIPT_VERSION variable assignments and # Version: comments. Uses sed
# for in-place editing with proper regex escaping to handle version numbers
# containing dots.
#
# Arguments:
#   $1: Path to the file to update
#   $2: Old version number to replace (e.g., "0.4.1")
#   $3: New version number to set (e.g., "0.4.2")
#   $4: Dry run flag (1 for dry run, 0 for actual update)
#
# Returns:
#   0: File updated successfully (or would be updated in dry run)
#   1: File not found or update failed
#
# Side effects:
#   - Modifies file in-place if dry_run is 0 (creates .tmp backup, then removes it)
#   - Prints update status to stdout (colored output)
#   - Prints warning to stderr if file not found
#
# Examples:
#   update_version_in_file "vpn-monitor.sh" "0.4.1" "0.4.2" 0
#   # Updates version in vpn-monitor.sh
#
#   update_version_in_file "lib/config.sh" "0.4.1" "0.4.2" 1
#   # Shows what would be updated without making changes
#
# Note:
#   Escapes old_version for sed regex patterns (dots are special characters)
#   new_version doesn't need escaping (used in replacement string)
#   Updates SCRIPT_VERSION="..." or SCRIPT_VERSION='...' formats
#   Updates # Version: comment format
#   Creates temporary .tmp file during update, then removes it
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

# Check if the only changes in a file are version number updates
#
# Uses git diff to verify that every changed line is a version update
# (old_version -> new_version). If the diff contains any other changes,
# returns 1. Only runs when in a git repo and file is tracked.
#
# Arguments:
#   $1: Path to the file to check
#   $2: Old version number that was replaced
#   $3: New version number that was set
#
# Returns:
#   0: Only version changes in the diff; safe to stage
#   1: Other changes present, not a git repo, or file not tracked
#
# Side effects:
#   None
is_only_version_change_in_file() {
	local file="$1"
	local old_version="$2"
	local new_version="$3"

	# Must be in a git repo
	if ! git -C "${PROJECT_ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
		return 1
	fi

	# File must be tracked
	if ! git -C "${PROJECT_ROOT}" ls-files --error-unmatch "$file" >/dev/null 2>&1; then
		return 1
	fi

	# Get diff lines that are additions or removals (exclude --- and +++ headers)
	local diff_lines
	diff_lines=$(git -C "${PROJECT_ROOT}" diff --no-color "$file" 2>/dev/null | grep -E '^[\+\-]' | grep -v -E '^[\+\-]{3}' || true)

	# No diff means nothing to stage
	[[ -z "$diff_lines" ]] && return 1

	# Every removed line must contain old_version, every added line must contain new_version
	local line
	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		if [[ "$line" == \-* ]]; then
			[[ "$line" == *"$old_version"* ]] || return 1
		elif [[ "$line" == \+* ]]; then
			[[ "$line" == *"$new_version"* ]] || return 1
		fi
	done <<<"$diff_lines"

	return 0
}

# Stage a file with git add
#
# Arguments:
#   $1: Path to the file to stage
#
# Returns:
#   0: Success
#   1: Failure (e.g., not in git repo)
#
# Side effects:
#   Stages the file in the git index
stage_file() {
	local file="$1"
	if git -C "${PROJECT_ROOT}" add "$file" 2>/dev/null; then
		echo -e "  ${GREEN}Staged${NC} $file"
		return 0
	fi
	return 1
}

# Find all files in the project that contain version numbers
#
# Discovers all files that should have version numbers updated, including:
# main scripts (vpn-monitor.sh, vpn-keepalive.sh), installation scripts
# (install.sh, uninstall.sh), utility scripts (analyze-logs.sh, etc.),
# and all library files in lib/ directory.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints file paths to stdout, one per line
#
# Side effects:
#   None
#
# Examples:
#   mapfile -t files < <(find_files_with_versions)
#   # Collects all files with versions into array
#
#   for file in $(find_files_with_versions); do
#       echo "Found: $file"
#   done
#
# Note:
#   Only includes files that actually exist
#   Searches lib/ directory recursively for .sh files
#   Includes specific utility scripts by name
#   Files are sorted alphabetically
find_files_with_versions() {
	local files=()

	# Main scripts with SCRIPT_VERSION or # Version:
	if [[ -f "${PROJECT_ROOT}/vpn-monitor.sh" ]]; then
		files+=("${PROJECT_ROOT}/vpn-monitor.sh")
	fi
	if [[ -f "${PROJECT_ROOT}/vpn-keepalive.sh" ]]; then
		files+=("${PROJECT_ROOT}/vpn-keepalive.sh")
	fi
	if [[ -f "${PROJECT_ROOT}/vpn-monitor-wrapper.sh" ]]; then
		files+=("${PROJECT_ROOT}/vpn-monitor-wrapper.sh")
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

# Main execution function
#
# Orchestrates the version update process. Validates the new version format,
# determines the current version from vpn-monitor.sh, finds all files that
# need updates, updates each file, and verifies the updates were successful.
# Supports dry-run mode to preview changes without modifying files.
#
# Arguments:
#   None (uses global NEW_VERSION and DRY_RUN variables set by argument parsing)
#
# Returns:
#   0: All files updated successfully
#   1: Update failed or validation error
#
# Side effects:
#   - Modifies version numbers in multiple project files (unless dry run)
#   - Stages files with git add when the only change is the version update
#   - Prints progress and results to stdout (colored output)
#   - Prints warnings/errors to stderr
#   - Exits script with appropriate exit code
#
# Examples:
#   NEW_VERSION="0.4.2" DRY_RUN=0 main
#   # Updates all files to version 0.4.2
#
#   NEW_VERSION="1.0.0" DRY_RUN=1 main
#   # Shows what would be updated without making changes
#
# Note:
#   Requires NEW_VERSION and DRY_RUN to be set before calling
#   Validates version format (SemVer: MAJOR.MINOR.PATCH)
#   Gets current version from vpn-monitor.sh as reference
#   Verifies all files were updated correctly after changes
#   Exits early if new version matches current version
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
				# If we actually updated (version changed) and the only diff is the version change, stage the file
				if [[ $DRY_RUN -eq 0 ]] && [[ "$file_version" != "$NEW_VERSION" ]]; then
					local current_after
					current_after=$(get_current_version_from_file "$file" || echo "")
					if [[ "$current_after" == "$NEW_VERSION" ]] && is_only_version_change_in_file "$file" "$file_version" "$NEW_VERSION"; then
						stage_file "$file" || true
					fi
				fi
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
