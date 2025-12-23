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

# Main script files
MAIN_FILES=(
	"vpn-monitor.sh"
	"vpn-keepalive.sh"
	"install.sh"
	"uninstall.sh"
	"analyze-logs.sh"
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
	"lib/state.sh"
)

echo "Preparing install package..."

# Create temporary directory structure
mkdir -p "${TEMP_DIR}/lib"

# Copy main files
for file in "${MAIN_FILES[@]}"; do
	if [[ -f "${SCRIPT_DIR}/${file}" ]]; then
		cp "${SCRIPT_DIR}/${file}" "${TEMP_DIR}/${file}"
		echo "  Added: ${file}"
	else
		echo "Warning: ${file} not found, skipping" >&2
	fi
done

# Copy library files
for file in "${LIB_FILES[@]}"; do
	if [[ -f "${SCRIPT_DIR}/${file}" ]]; then
		cp "${SCRIPT_DIR}/${file}" "${TEMP_DIR}/${file}"
		echo "  Added: ${file}"
	else
		echo "Warning: ${file} not found, skipping" >&2
	fi
done

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
