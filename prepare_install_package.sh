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
#   udm-vpn-monitor-installer.zip (default) or udm-vpn-monitor-installer.tar.gz
#   Contains all required files for installation
#

set -euo pipefail

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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $USE_TAR -eq 1 ]]; then
	PACKAGE_NAME="udm-vpn-monitor-installer.tar.gz"
else
	PACKAGE_NAME="udm-vpn-monitor-installer.zip"
fi
TEMP_DIR=$(mktemp -d)

# Cleanup function
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
		if [[ -f "${source_dir}/${file}" ]]; then
			# Create destination directory if needed
			local dest_file_dir
			dest_file_dir=$(dirname "${dest_dir}/${file}")
			mkdir -p "$dest_file_dir"

			cp "${source_dir}/${file}" "${dest_dir}/${file}"
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

echo "Preparing install package..."

# Copy main files
copy_files_with_validation "$SCRIPT_DIR" "$TEMP_DIR" "${MAIN_FILES[@]}"

# Copy library files
copy_files_with_validation "$SCRIPT_DIR" "$TEMP_DIR" "${LIB_FILES[@]}"

# Create package file (zip or tar)
cd "$TEMP_DIR"
if [[ $USE_TAR -eq 1 ]]; then
	tar -czf "${SCRIPT_DIR}/${PACKAGE_NAME}" . >/dev/null
else
	zip -r "${SCRIPT_DIR}/${PACKAGE_NAME}" . >/dev/null
fi
cd "$SCRIPT_DIR"

echo ""
echo "Package created successfully: ${PACKAGE_NAME}"
echo ""
echo "Files included:"
echo "  Main files:"
for file in "${MAIN_FILES[@]}"; do
	if [[ -f "${SCRIPT_DIR}/${file}" ]]; then
		echo "    - ${file}"
	fi
done
echo "  Library files:"
for file in "${LIB_FILES[@]}"; do
	if [[ -f "${SCRIPT_DIR}/${file}" ]]; then
		echo "    - ${file}"
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
