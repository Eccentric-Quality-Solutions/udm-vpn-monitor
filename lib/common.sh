#!/bin/bash
#
# Common functions for UDM VPN Monitor installation/uninstallation scripts
# Shared logging and utility functions
#
# Version: 0.0.1
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
#
# Logs an informational message with green [INFO] prefix.
#
# Arguments:
#   $@: Message text (all arguments are concatenated)
#
# Returns:
#   0: Always succeeds
log_info() {
	echo -e "${GREEN}[INFO]${NC} $*"
}

# Log a warning message
#
# Logs a warning message with yellow [WARN] prefix.
#
# Arguments:
#   $@: Message text (all arguments are concatenated)
#
# Returns:
#   0: Always succeeds
log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $*"
}

# Log an error message
#
# Logs an error message with red [ERROR] prefix.
#
# Arguments:
#   $@: Message text (all arguments are concatenated)
#
# Returns:
#   0: Always succeeds
log_error() {
	echo -e "${RED}[ERROR]${NC} $*"
}

# Check if running as root
#
# Verifies that the script is running with root privileges.
# Required for installing to /data/ and modifying crontab.
#
# Returns:
#   0: Running as root
#   1: Not running as root (exits script with error)
check_root() {
	if [[ $EUID -ne 0 ]]; then
		log_error "This script must be run as root"
		exit 1
	fi
}
