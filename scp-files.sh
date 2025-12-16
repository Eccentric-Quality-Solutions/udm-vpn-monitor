#!/bin/bash
#
# Generate SCP command for UDM VPN Monitor files
# Provides the SCP command with specific files listed (no wildcards)
#
# Usage:
#   ./scp-files.sh [UDM_IP]
#   ./scp-files.sh 192.168.1.1
#
# If UDM_IP is not provided, outputs the command with placeholder <UDM_IP>
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# UDM IP from argument or placeholder
UDM_IP="${1:-<UDM_IP>}"
DEST_USER="${2:-root}"
DEST_PATH="${3:-/tmp}"

# Main script files
MAIN_FILES=(
	"vpn-monitor.sh"
	"install.sh"
	"uninstall.sh"
	"analyze-logs.sh"
	"vpn-monitor.conf"
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

# Build file list
FILES=()
for file in "${MAIN_FILES[@]}"; do
	if [[ -f "${SCRIPT_DIR}/${file}" ]]; then
		FILES+=("${file}")
	else
		echo "Warning: ${file} not found" >&2
	fi
done

for file in "${LIB_FILES[@]}"; do
	if [[ -f "${SCRIPT_DIR}/${file}" ]]; then
		FILES+=("${file}")
	else
		echo "Warning: ${file} not found" >&2
	fi
done

# Generate SCP command
if [[ ${#FILES[@]} -eq 0 ]]; then
	echo "Error: No files found to transfer" >&2
	exit 1
fi

# Build the command
SCP_CMD="scp"
for file in "${FILES[@]}"; do
	SCP_CMD="${SCP_CMD} ${file}"
done
SCP_CMD="${SCP_CMD} ${DEST_USER}@${UDM_IP}:${DEST_PATH}/"

# Output the command
echo "$SCP_CMD"

# If UDM_IP is a placeholder, provide usage instructions
if [[ "$UDM_IP" == "<UDM_IP>" ]]; then
	echo ""
	echo "Usage examples:"
	echo "  ./scp-files.sh 192.168.1.1"
	echo "  ./scp-files.sh 192.168.1.1 root /tmp"
	echo ""
	echo "Or copy the command above and replace <UDM_IP> with your UDM's IP address."
fi

