#!/bin/bash
#
# UDM VPN Monitor Uninstallation Script
# Removes the VPN monitoring script and all associated files
#
# Designed for UniFi Dream Machine (UDM) running UniFi OS 4.3+
#

set -euo pipefail

# Installation paths (must match install.sh)
INSTALL_DIR="/data/vpn-monitor"
SCRIPT_NAME="vpn-monitor.sh"

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
# Required for removing files from /data/ and modifying crontab.
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

# Check if installation exists
#
# Verifies that the VPN monitor installation directory exists.
# Used to determine if there's anything to uninstall.
#
# Returns:
#   0: Installation directory exists
#   1: Installation directory not found
check_installation() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        log_warn "Installation directory not found: $INSTALL_DIR"
        log_warn "VPN Monitor may not be installed, or was already removed"
        return 1
    fi
    return 0
}

# Remove cron entry
#
# Removes the VPN monitor cron job entry from the root crontab.
# Filters out lines containing "vpn-monitor.sh" and updates crontab.
#
# Returns:
#   0: Cron entry removed successfully (or didn't exist)
#   1: Failed to remove cron entry
#
# Side effects:
#   Modifies root crontab
remove_cron() {
    log_info "Removing cron job..."
    
    # Check if cron entry exists
    if crontab -l 2>/dev/null | grep -q "vpn-monitor.sh"; then
        # Remove cron entry
        crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true
        log_info "Cron job removed"
        
        # Verify removal
        if crontab -l 2>/dev/null | grep -q "vpn-monitor.sh"; then
            log_error "Failed to remove cron job"
            return 1
        fi
    else
        log_warn "Cron job not found (may have been removed already)"
    fi
    
    return 0
}

# Remove installation directory
#
# Removes the entire installation directory and all its contents.
# This includes scripts, config files, log files, and state files.
#
# Returns:
#   0: Directory removed successfully (or didn't exist)
#   1: Failed to remove directory
#
# Side effects:
#   - Displays list of files that will be removed
#   - Deletes ${INSTALL_DIR} and all contents
remove_installation_dir() {
    log_info "Removing installation directory: $INSTALL_DIR"
    
    if [[ -d "$INSTALL_DIR" ]]; then
        # List what will be removed
        log_info "The following will be removed:"
        ls -lh "$INSTALL_DIR" 2>/dev/null | tail -n +2 | while read -r line; do
            echo "  $line"
        done || true
        
        # Remove directory and all contents
        rm -rf "$INSTALL_DIR"
        
        # Verify removal
        if [[ -d "$INSTALL_DIR" ]]; then
            log_error "Failed to remove installation directory"
            return 1
        else
            log_info "Installation directory removed successfully"
        fi
    else
        log_warn "Installation directory not found: $INSTALL_DIR"
    fi
    
    return 0
}

# Clean up any stale lockfiles
#
# Removes any stale lockfiles that may persist if the installation directory
# was removed but lockfile remained (shouldn't happen normally).
#
# Returns:
#   0: Always succeeds (warnings logged but don't fail)
#
# Side effects:
#   Removes lockfile if it exists
cleanup_lockfile() {
    local lockfile="${INSTALL_DIR}/vpn-monitor.lock"
    if [[ -f "$lockfile" ]]; then
        log_warn "Found stale lockfile (should have been removed with directory)"
        rm -f "$lockfile" 2>/dev/null || true
    fi
}

# Verify uninstallation
#
# Verifies that the uninstallation completed successfully by checking:
#   - Installation directory no longer exists
#   - Cron entry no longer exists
#
# Returns:
#   0: Uninstallation verified successfully
#   1: Verification failed (some components still exist)
verify_uninstallation() {
    log_info "Verifying uninstallation..."
    
    local errors=0
    
    # Check installation directory is gone
    if [[ -d "$INSTALL_DIR" ]]; then
        log_error "Installation directory still exists: $INSTALL_DIR"
        errors=$((errors + 1))
    else
        log_info "Installation directory removed"
    fi
    
    # Check cron entry is gone
    if crontab -l 2>/dev/null | grep -q "vpn-monitor.sh"; then
        log_error "Cron entry still exists"
        errors=$((errors + 1))
    else
        log_info "Cron entry removed"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_info "Uninstallation verified successfully"
        return 0
    else
        log_error "Uninstallation verification failed with $errors error(s)"
        return 1
    fi
}

# Display summary
#
# Displays a summary of what was removed during uninstallation.
# Shows confirmation that VPN Monitor has been completely removed.
#
# Returns:
#   0: Always succeeds
display_summary() {
    echo ""
    log_info "Uninstallation complete!"
    echo ""
    log_info "Removed:"
    echo "  - Installation directory: $INSTALL_DIR"
    echo "  - Cron job entry"
    echo "  - All configuration files"
    echo "  - All log files"
    echo "  - All state files"
    echo ""
    log_info "VPN Monitor has been completely removed from your system."
    echo ""
}

# Main uninstallation
#
# Main entry point for the uninstallation script.
# Orchestrates the complete uninstallation process.
#
# Arguments:
#   $@: Command-line arguments
#       --yes: Skip interactive confirmation (non-interactive mode)
#
# Returns:
#   0: Uninstallation successful
#   1: Uninstallation failed
#
# Execution flow:
#   1. Check root privileges
#   2. Check if installation exists
#   3. Prompt for confirmation (unless --yes or CI environment)
#   4. Remove cron entry
#   5. Remove installation directory
#   6. Clean up stale lockfiles
#   7. Verify uninstallation
#   8. Display summary
main() {
    log_info "UDM VPN Monitor Uninstallation"
    log_info "================================="
    echo ""
    
    check_root
    
    # Check if installation exists
    if ! check_installation; then
        # Still try to remove cron entry in case it exists
        remove_cron
        log_warn "No installation found, but checked for cron entries"
        exit 0
    fi
    
    # Confirm with user (non-interactive mode if CI or --yes flag)
    if [[ "${1:-}" != "--yes" ]] && [[ -z "${CI:-}" ]]; then
        echo ""
        log_warn "This will remove:"
        echo "  - Installation directory: $INSTALL_DIR"
        echo "  - All configuration files"
        echo "  - All log files"
        echo "  - Cron job entry"
        echo ""
        read -p "Are you sure you want to continue? (yes/no): " -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Uninstallation cancelled"
            exit 0
        fi
    fi
    
    remove_cron
    remove_installation_dir
    cleanup_lockfile
    
    if verify_uninstallation; then
        display_summary
        exit 0
    else
        log_error "Uninstallation completed with errors"
        exit 1
    fi
}

# Run main
main "$@"

