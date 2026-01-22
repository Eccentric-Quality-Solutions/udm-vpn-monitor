#!/bin/bash
#
# Prepare Install Package Script
# Creates a zip or tar file containing only the files needed to run the application
#
# Usage:
#   ./prepare_install_package.sh [--tar]
#
# Options:
#   --tar    Create a tar.gz file instead of zip
#
# Output:
#   udm-vpn-monitor.zip (default) or udm-vpn-monitor.tar.gz
#   Contains all required files for installation
#

set -euo pipefail

# Source common functions for file_exists_and_readable
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Determine repo root (parent of scripts directory)
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
if [[ -f "${REPO_ROOT}/lib/common.sh" ]]; then
	source "${REPO_ROOT}/lib/common.sh"
fi

# Parse arguments
USE_TAR=0
for arg in "$@"; do
	case "$arg" in
	--tar)
		USE_TAR=1
		;;
	--help | -h)
		echo "Usage: $0 [--tar]"
		echo ""
		echo "Options:"
		echo "  --tar    Create a tar.gz file instead of zip"
		echo "  --help   Show this help message"
		exit 0
		;;
	*)
		echo "Unknown option: $arg" >&2
		echo "Use --help for usage information" >&2
		exit 1
		;;
	esac
done

# REPO_ROOT is already set above
if [[ $USE_TAR -eq 1 ]]; then
	PACKAGE_NAME="udm-vpn-monitor.tar.gz"
else
	PACKAGE_NAME="udm-vpn-monitor.zip"
fi
TEMP_DIR=$(mktemp -d)

# Cleanup function
#
# Removes the temporary directory created for package preparation.
# This function is registered as an EXIT trap to ensure cleanup happens
# even if the script exits unexpectedly.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Removes the temporary directory and all its contents
cleanup() {
	rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Copy files from source directory to destination with error handling
#
# Arguments:
#   $1: Source directory
#   $2: Destination directory
#   $3: Array of file paths (relative to source)
#
# Returns:
#   0: Always succeeds (warnings logged but don't fail)
copy_files_with_validation() {
	local source_dir="$1"
	local dest_dir="$2"
	shift 2
	local files=("$@")

	for file in "${files[@]}"; do
		local source_file="${source_dir}/${file}"
		if [[ -f "$source_file" ]]; then
			# Check source file readability before copy operation (prevents hangs on unreadable files)
			if command -v file_exists_and_readable >/dev/null 2>&1; then
				if ! file_exists_and_readable "$source_file"; then
					echo "Warning: Source file not readable, skipping: ${file}" >&2
					continue
				fi
			elif [[ ! -r "$source_file" ]]; then
				# Fallback: basic check (may hang on some systems, but function not available)
				echo "Warning: Source file not readable, skipping: ${file}" >&2
				continue
			fi
			# Create destination directory if needed
			local dest_file_dir
			dest_file_dir=$(dirname "${dest_dir}/${file}")
			mkdir -p "$dest_file_dir"

			cp "$source_file" "${dest_dir}/${file}"
			echo "  Added: ${file}"
		else
			echo "Warning: ${file} not found, skipping" >&2
		fi
	done
}

# Main script files
MAIN_FILES=(
	"vpn-monitor.sh"
	"vpn-keepalive.sh"
	"install.sh"
	"uninstall.sh"
	"analyze-logs.sh"
	"check-utilities.sh"
	"check-config.sh"
	"compare-config.sh"
	"vpn-monitor.conf"
	"vpn-keepalive.service"
)

# Library files
LIB_FILES=(
	"lib/common.sh"
	"lib/config.sh"
	"lib/config_schema.sh"
	"lib/constants.sh"
	"lib/detection.sh"
	"lib/lockfile.sh"
	"lib/logging.sh"
	"lib/recovery.sh"
	"lib/resources.sh"
	"lib/state.sh"
)

# Script files (utility scripts)
SCRIPT_FILES=(
	"scripts/migrate-config-to-locations.sh"
	"scripts/anonymize-logs.sh"
)

echo "Preparing install package..."

# Copy main files
copy_files_with_validation "$REPO_ROOT" "$TEMP_DIR" "${MAIN_FILES[@]}"

# Copy library files
copy_files_with_validation "$REPO_ROOT" "$TEMP_DIR" "${LIB_FILES[@]}"

# Copy module subdirectories
MODULE_DIRS=(
	"lib/detection"
	"lib/recovery"
	"lib/config"
	"lib/state"
)

for dir in "${MODULE_DIRS[@]}"; do
	if [[ -d "${REPO_ROOT}/${dir}" ]]; then
		mkdir -p "${TEMP_DIR}/${dir}"
		# Copy files if directory is not empty
		# Check if directory has any files before copying to avoid glob expansion issues with set -u
		if [[ -n "$(ls -A "${REPO_ROOT}/${dir}" 2>/dev/null)" ]]; then
			cp -r "${REPO_ROOT}/${dir}"/* "${TEMP_DIR}/${dir}/"
			echo "  Added directory: ${dir}/"
		else
			echo "  Warning: ${dir}/ is empty, skipping" >&2
		fi
	fi
done

# Copy script files
copy_files_with_validation "$REPO_ROOT" "$TEMP_DIR" "${SCRIPT_FILES[@]}"

# Create package file (zip or tar)
cd "$TEMP_DIR"
if [[ $USE_TAR -eq 1 ]]; then
	tar -czf "${REPO_ROOT}/${PACKAGE_NAME}" . >/dev/null
else
	zip -r "${REPO_ROOT}/${PACKAGE_NAME}" . >/dev/null
fi
cd "$REPO_ROOT"

echo ""
echo "Package created successfully: ${REPO_ROOT}/${PACKAGE_NAME}"
echo ""
echo "Files included:"
echo "  Main files:"
for file in "${MAIN_FILES[@]}"; do
	if [[ -f "${REPO_ROOT}/${file}" ]]; then
		echo "    - ${file}"
	fi
done
echo "  Library files:"
for file in "${LIB_FILES[@]}"; do
	if [[ -f "${REPO_ROOT}/${file}" ]]; then
		echo "    - ${file}"
	fi
done
echo "  Script files:"
for file in "${SCRIPT_FILES[@]}"; do
	if [[ -f "${REPO_ROOT}/${file}" ]]; then
		echo "    - ${file}"
	fi
done
echo "  Module directories:"
for dir in "${MODULE_DIRS[@]}"; do
	if [[ -d "${REPO_ROOT}/${dir}" ]]; then
		echo "    - ${dir}/"
	fi
done
echo ""
echo "To use this package:"
echo "  1. Transfer ${PACKAGE_NAME} to your UDM"
if [[ $USE_TAR -eq 1 ]]; then
	echo "  2. Extract: tar -xzf ${PACKAGE_NAME}"
else
	echo "  2. Extract: unzip ${PACKAGE_NAME}"
fi
echo "  3. Run: ./install.sh"
