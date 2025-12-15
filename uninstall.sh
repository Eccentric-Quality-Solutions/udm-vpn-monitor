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
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Check if installation exists
check_installation() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        log_warn "Installation directory not found: $INSTALL_DIR"
        log_warn "VPN Monitor may not be installed, or was already removed"
        return 1
    fi
    return 0
}

# Remove cron entry
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

# Clean up any stale lockfiles (if directory was removed but lockfile persists)
cleanup_lockfile() {
    local lockfile="${INSTALL_DIR}/vpn-monitor.lock"
    if [[ -f "$lockfile" ]]; then
        log_warn "Found stale lockfile (should have been removed with directory)"
        rm -f "$lockfile" 2>/dev/null || true
    fi
}

# Verify uninstallation
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

