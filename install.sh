#!/bin/bash
#
# UDM VPN Monitor Installation Script
# Installs the VPN monitoring script with cron-based execution
#
# Designed for UniFi Dream Machine (UDM) running UniFi OS 4.3+
#

set -euo pipefail

# Installation paths
SCRIPT_NAME="vpn-monitor.sh"
CONFIG_NAME="vpn-monitor.conf"
INSTALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# INSTALL_DIR will be set based on DEV_MODE flag
INSTALL_DIR=""

# Flags
SKIP_CRON=0
SILENT=0
OVERWRITE_CONF=0
DEV_MODE=0

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

# Check if we're on a UDM
#
# Verifies that the system is a UniFi Dream Machine by checking for /data directory.
# Skips check if DEV_MODE is enabled (for testing on non-UDM systems).
#
# Returns:
#   0: UDM detected or dev mode enabled
#   1: Not a UDM system (exits script with error)
check_udm() {
    if [[ $DEV_MODE -eq 1 ]]; then
        log_info "Dev mode enabled, skipping UDM check"
        return 0
    fi
    
    if [[ ! -d "/data" ]]; then
        log_error "This script is designed for UniFi Dream Machines"
        log_error "/data directory not found"
        exit 1
    fi
    
    log_info "Detected UDM system"
}

# Create installation directory
#
# Creates the installation directory (INSTALL_DIR) if it doesn't exist.
# In production mode: /data/vpn-monitor
# In dev mode: ./vpn-monitor (current working directory)
#
# Returns:
#   0: Always succeeds (exits script on failure)
create_install_dir() {
    log_info "Creating installation directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    log_info "Creating logs directory: ${INSTALL_DIR}/logs"
    mkdir -p "${INSTALL_DIR}/logs"
}

# Install config file (from template or create default)
#
# Installs the configuration file to the installation directory.
# If a config template exists in the source directory, copies it.
# Otherwise, creates a default configuration file.
#
# Arguments:
#   $1: Optional message to display before installation
#
# Returns:
#   0: Always succeeds (exits script on failure)
#
# Side effects:
#   Creates or overwrites ${INSTALL_DIR}/${CONFIG_NAME}
install_config_file() {
    local overwrite_msg="$1"
    
    if [[ -n "$overwrite_msg" ]]; then
        log_info "$overwrite_msg"
    fi
    
    if [[ -f "${INSTALL_SCRIPT_DIR}/${CONFIG_NAME}" ]]; then
        cp "${INSTALL_SCRIPT_DIR}/${CONFIG_NAME}" "${INSTALL_DIR}/${CONFIG_NAME}"
        log_info "Installed ${CONFIG_NAME} (please customize it)"
    else
        log_warn "Config template not found, creating default"
        cat > "${INSTALL_DIR}/${CONFIG_NAME}" << EOF
# UDM VPN Monitor Configuration
PEER_IPS=""
VPN_NAME="Site-to-Site VPN"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
COOLDOWN_MINUTES=15
MAX_RESTARTS_PER_HOUR=3
LOG_FILE="${INSTALL_DIR}/logs/vpn-monitor.log"
STATE_DIR="${INSTALL_DIR}"
CRON_SCHEDULE="*/1 * * * *"
LOCKFILE_TIMEOUT=300
ENABLE_PING_CHECK=1
PING_TARGET_IP=""
PING_COUNT=3
PING_TIMEOUT=2
DEBUG=0
EOF
    fi
}

# Install scripts
#
# Copies the main VPN monitor script and configuration file to the installation directory.
# Handles existing config files based on SILENT and OVERWRITE_CONF flags.
#
# Returns:
#   0: Always succeeds (exits script on failure)
#
# Side effects:
#   - Copies vpn-monitor.sh to installation directory
#   - Sets executable permissions on vpn-monitor.sh
#   - Installs config file (may prompt user in interactive mode)
install_scripts() {
    log_info "Installing scripts..."
    
    # Copy main script
    if [[ -f "${INSTALL_SCRIPT_DIR}/${SCRIPT_NAME}" ]]; then
        cp "${INSTALL_SCRIPT_DIR}/${SCRIPT_NAME}" "${INSTALL_DIR}/${SCRIPT_NAME}"
        chmod +x "${INSTALL_DIR}/${SCRIPT_NAME}"
        log_info "Installed ${SCRIPT_NAME}"
    else
        log_error "Source file not found: ${INSTALL_SCRIPT_DIR}/${SCRIPT_NAME}"
        exit 1
    fi
    
    # Handle config file installation
    if [[ -f "${INSTALL_DIR}/${CONFIG_NAME}" ]]; then
        # Config file already exists
        if [[ $SILENT -eq 1 ]]; then
            # Silent mode: only overwrite if explicitly requested
            if [[ $OVERWRITE_CONF -eq 1 ]]; then
                install_config_file "Overwriting existing config file (--overwrite-conf flag)"
            else
                log_info "Config file already exists, preserving: ${INSTALL_DIR}/${CONFIG_NAME}"
            fi
        else
            # Interactive mode: ask user
            echo ""
            log_warn "Config file already exists: ${INSTALL_DIR}/${CONFIG_NAME}"
            read -p "Overwrite existing config file? (yes/no) [no]: " -r
            echo ""
            if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                install_config_file "Overwriting existing config file"
            else
                log_info "Preserving existing config file: ${INSTALL_DIR}/${CONFIG_NAME}"
            fi
        fi
    else
        # Config file doesn't exist, install it
        install_config_file "Installing config file"
    fi
}

# Setup cron job
#
# Adds a cron job entry to run the VPN monitor script on a schedule.
# Reads CRON_SCHEDULE from config file if available, otherwise uses default (*/1 * * * *).
# Skips if cron entry already exists (to avoid duplicates).
#
# Returns:
#   0: Always succeeds (warnings logged but don't fail)
#
# Side effects:
#   - Adds cron entry to root crontab
#   - Displays current cron entries
#
# Note:
#   Cron schedule format: minute hour day month weekday
#   Example: "*/1 * * * *" = every 1 minute
setup_cron() {
    log_info "Setting up cron job..."
    
    # Load cron schedule from config if it exists, otherwise use default
    local cron_schedule="*/1 * * * *"
    if [[ -f "${INSTALL_DIR}/${CONFIG_NAME}" ]]; then
        # Try to extract CRON_SCHEDULE from config file
        # Handle both quoted (single or double) and unquoted values
        local config_schedule
        # Try double-quoted value first
        config_schedule=$(grep "^CRON_SCHEDULE=" "${INSTALL_DIR}/${CONFIG_NAME}" 2>/dev/null | sed -n 's/^CRON_SCHEDULE="\(.*\)"/\1/p' | head -1)
        # If empty, try single-quoted
        if [[ -z "$config_schedule" ]]; then
            config_schedule=$(grep "^CRON_SCHEDULE=" "${INSTALL_DIR}/${CONFIG_NAME}" 2>/dev/null | sed -n "s/^CRON_SCHEDULE='\(.*\)'/\1/p" | head -1)
        fi
        # If still empty, try unquoted
        if [[ -z "$config_schedule" ]]; then
            config_schedule=$(grep "^CRON_SCHEDULE=" "${INSTALL_DIR}/${CONFIG_NAME}" 2>/dev/null | sed 's/^CRON_SCHEDULE=//' | sed 's/^["'\'']//' | sed 's/["'\'']$//' | tr -d ' ' | head -1)
        fi
        # Validate it looks like a cron schedule (contains * or numbers)
        if [[ -n "$config_schedule" ]] && [[ "$config_schedule" =~ [\*0-9] ]]; then
            cron_schedule="$config_schedule"
            log_info "Using cron schedule from config: $cron_schedule"
        else
            log_info "Using default cron schedule: $cron_schedule"
        fi
    else
        log_info "Using default cron schedule: $cron_schedule"
    fi
    
    local cron_entry
    cron_entry="${cron_schedule} ${INSTALL_DIR}/${SCRIPT_NAME} >> ${INSTALL_DIR}/cron.log 2>&1"
    
    # Check if cron entry already exists
    if crontab -l 2>/dev/null | grep -q "vpn-monitor.sh"; then
        log_warn "Cron job already exists, skipping..."
        log_info "To update the cron schedule:"
        log_info "  1. Edit ${INSTALL_DIR}/${CONFIG_NAME} and set CRON_SCHEDULE"
        log_info "  2. Remove old cron entry: crontab -e"
        log_info "  3. Re-run install.sh to install new schedule"
    else
        # Add cron entry
        (crontab -l 2>/dev/null || true; echo "$cron_entry") | crontab -
        log_info "Cron job installed with schedule: $cron_schedule"
    fi
    
    # Display current cron entries
    log_info "Current cron entries:"
    crontab -l 2>/dev/null | grep -E "(vpn-monitor|^#)" || log_warn "No cron entries found"
}

# Verify installation
#
# Verifies that the installation completed successfully by checking:
#   - Script file exists and is executable
#   - Config file exists
#   - Cron entry exists (if cron setup was not skipped)
#
# Returns:
#   0: Installation verified successfully
#   1: Verification failed (errors found)
verify_installation() {
    log_info "Verifying installation..."
    
    local errors=0
    
    # Check script exists and is executable
    if [[ ! -f "${INSTALL_DIR}/${SCRIPT_NAME}" ]]; then
        log_error "Script not found: ${INSTALL_DIR}/${SCRIPT_NAME}"
        errors=$((errors + 1))
    elif [[ ! -x "${INSTALL_DIR}/${SCRIPT_NAME}" ]]; then
        log_error "Script is not executable: ${INSTALL_DIR}/${SCRIPT_NAME}"
        errors=$((errors + 1))
    else
        log_info "Script verified: ${INSTALL_DIR}/${SCRIPT_NAME}"
    fi
    
    # Check config exists
    if [[ ! -f "${INSTALL_DIR}/${CONFIG_NAME}" ]]; then
        log_error "Config not found: ${INSTALL_DIR}/${CONFIG_NAME}"
        errors=$((errors + 1))
    else
        log_info "Config verified: ${INSTALL_DIR}/${CONFIG_NAME}"
    fi
    
    # Check cron entry (only if cron setup was not skipped)
    if [[ $SKIP_CRON -eq 0 ]]; then
        if ! crontab -l 2>/dev/null | grep -q "vpn-monitor.sh"; then
            log_warn "Cron entry not found (may have been skipped if already exists)"
        else
            log_info "Cron entry verified"
        fi
    else
        log_info "Cron setup skipped (--no-cron flag used)"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_info "Installation verified successfully"
        return 0
    else
        log_error "Installation verification failed with $errors error(s)"
        return 1
    fi
}

# Display next steps
#
# Displays post-installation instructions to the user.
# Shows configuration file location, testing instructions, and persistence notes.
# Skips output in silent mode.
#
# Returns:
#   0: Always succeeds
display_next_steps() {
    if [[ $SILENT -eq 1 ]]; then
        # Silent mode: minimal output
        return 0
    fi
    
    echo ""
    log_info "Installation complete!"
    echo ""
    log_info "Next steps:"
    echo "  1. Edit the configuration file:"
    echo "     ${INSTALL_DIR}/${CONFIG_NAME}"
    echo ""
    echo "  2. Set PEER_IPS to your remote VPN endpoint IP address(es)"
    echo ""
    echo "  3. Test the script manually:"
    echo "     ${INSTALL_DIR}/${SCRIPT_NAME}"
    echo ""
    echo "  4. Monitor the log file:"
    echo "     tail -f ${INSTALL_DIR}/logs/vpn-monitor.log"
    echo ""
    if [[ $SKIP_CRON -eq 1 ]]; then
        log_warn "NOTE: Cron job was not installed (--no-cron flag used)"
        echo "  - Run the script manually or set up your own scheduling"
        echo "  - To install cron later, run: ./install.sh"
        echo ""
    else
        if [[ $DEV_MODE -eq 1 ]]; then
            log_warn "NOTE: Dev mode installation"
            echo "  - Files installed to: ${INSTALL_DIR}"
            echo "  - Cron job installed (if not skipped)"
            echo ""
        else
            log_warn "IMPORTANT: Persistence Notes"
            echo "  - Scripts survive reboots (stored in /data/)"
            echo "  - Cron jobs may be wiped during UniFi OS upgrades"
            echo "  - Re-run this installer after upgrades if monitoring stops"
            echo ""
        fi
    fi
    log_info "To uninstall, run:"
    echo "  ./uninstall.sh"
    echo ""
    echo "  Or manually remove:"
    echo "  - ${INSTALL_DIR}/"
    if [[ $SKIP_CRON -eq 0 ]]; then
        echo "  - Cron entry (crontab -e)"
    fi
    echo ""
}

# Parse command-line arguments
#
# Processes command-line arguments and sets corresponding global flags.
# Also determines INSTALL_DIR based on DEV_MODE flag.
#
# Arguments:
#   $@: Command-line arguments
#
# Supported options:
#   --no-cron: Skip cron job setup
#   --silent: Perform installation silently (no prompts)
#   --overwrite-conf: Overwrite existing config file (only with --silent)
#   --dev: Install to current directory instead of /data/vpn-monitor
#   --help, -h: Display help message and exit
#
# Returns:
#   0: Always succeeds (exits with 0 for --help)
#
# Side effects:
#   Sets global flags: SKIP_CRON, SILENT, OVERWRITE_CONF, DEV_MODE
#   Sets INSTALL_DIR based on DEV_MODE
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-cron)
                SKIP_CRON=1
                if [[ $SILENT -eq 0 ]]; then
                    log_info "Cron setup will be skipped (--no-cron flag)"
                fi
                shift
                ;;
            --silent)
                SILENT=1
                shift
                ;;
            --overwrite-conf)
                OVERWRITE_CONF=1
                shift
                ;;
            --dev)
                DEV_MODE=1
                if [[ $SILENT -eq 0 ]]; then
                    log_info "Dev mode enabled - installing to current working directory"
                fi
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --no-cron         Install without setting up cron job"
                echo "  --silent          Perform installation silently (no prompts)"
                echo "  --overwrite-conf  Overwrite existing config file (only works with --silent)"
                echo "  --dev             Install to current working directory (dev mode)"
                echo "  --help            Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                                    # Interactive installation"
                echo "  $0 --silent                          # Silent installation, preserve existing config"
                echo "  $0 --silent --overwrite-conf          # Silent installation, overwrite config"
                echo "  $0 --silent --no-cron                 # Silent installation, no cron"
                echo "  $0 --dev                              # Install to current directory (dev mode)"
                echo "  $0 --dev --silent --no-cron           # Dev mode, silent, no cron"
                echo "  $0 --silent --no-cron --overwrite-conf  # Silent installation, no cron, overwrite config"
                echo ""
                exit 0
                ;;
            *)
                log_warn "Unknown argument: $1 (use --help for usage)"
                shift
                ;;
        esac
    done
    
    # Set INSTALL_DIR based on DEV_MODE
    if [[ $DEV_MODE -eq 1 ]]; then
        INSTALL_DIR="$(pwd)/vpn-monitor"
    else
        INSTALL_DIR="/data/vpn-monitor"
    fi
    
    # Validate flag combinations
    if [[ $OVERWRITE_CONF -eq 1 ]] && [[ $SILENT -eq 0 ]]; then
        log_warn "Warning: --overwrite-conf is only effective with --silent flag"
        log_warn "In interactive mode, you will be prompted to overwrite the config file"
    fi
}

# Main installation
#
# Main entry point for the installation script.
# Orchestrates the complete installation process.
#
# Arguments:
#   $@: Command-line arguments (passed to parse_args)
#
# Returns:
#   0: Installation successful
#   1: Installation failed
#
# Execution flow:
#   1. Parse command-line arguments
#   2. Check root privileges (unless dev mode)
#   3. Check UDM system (unless dev mode)
#   4. Create installation directory
#   5. Install scripts and config
#   6. Setup cron job (unless skipped)
#   7. Verify installation
#   8. Display next steps
main() {
    # Parse command-line arguments
    parse_args "$@"
    
    if [[ $SILENT -eq 0 ]]; then
        log_info "UDM VPN Monitor Installation"
        log_info "=============================="
        if [[ $DEV_MODE -eq 1 ]]; then
            log_info "Dev mode: Installing to ${INSTALL_DIR}"
        fi
        echo ""
    fi
    
    # Skip root check in dev mode
    if [[ $DEV_MODE -eq 0 ]]; then
        check_root
    fi
    check_udm
    create_install_dir
    install_scripts
    
    # Setup cron only if not skipped
    if [[ $SKIP_CRON -eq 0 ]]; then
        setup_cron
    else
        log_info "Skipping cron setup (--no-cron flag used)"
    fi
    
    if verify_installation; then
        display_next_steps
        exit 0
    else
        log_error "Installation completed with errors"
        exit 1
    fi
}

# Run main
main "$@"

