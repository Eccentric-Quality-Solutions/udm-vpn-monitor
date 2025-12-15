#!/bin/bash
#
# UDM VPN Monitor Installation Script
# Installs the VPN monitoring script with cron-based execution
#
# Designed for UniFi Dream Machine (UDM) running UniFi OS 4.3+
#

set -euo pipefail

# Installation paths
INSTALL_DIR="/data/vpn-monitor"
SCRIPT_NAME="vpn-monitor.sh"
CONFIG_NAME="vpn-monitor.conf"
INSTALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Flags
SKIP_CRON=0
SILENT=0
OVERWRITE_CONF=0

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

# Check if we're on a UDM
check_udm() {
    if [[ ! -d "/data" ]]; then
        log_error "This script is designed for UniFi Dream Machines"
        log_error "/data directory not found"
        exit 1
    fi
    
    log_info "Detected UDM system"
}

# Create installation directory
create_install_dir() {
    log_info "Creating installation directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
}

# Install config file (from template or create default)
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
        cat > "${INSTALL_DIR}/${CONFIG_NAME}" << 'EOF'
# UDM VPN Monitor Configuration
PEER_IPS=""
VPN_NAME="Site-to-Site VPN"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
COOLDOWN_MINUTES=15
MAX_RESTARTS_PER_HOUR=3
LOG_FILE="/data/vpn-monitor/vpn-monitor.log"
STATE_DIR="/data/vpn-monitor"
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
    echo "     tail -f ${INSTALL_DIR}/vpn-monitor.log"
    echo ""
    if [[ $SKIP_CRON -eq 1 ]]; then
        log_warn "NOTE: Cron job was not installed (--no-cron flag used)"
        echo "  - Run the script manually or set up your own scheduling"
        echo "  - To install cron later, run: ./install.sh"
        echo ""
    else
        log_warn "IMPORTANT: Persistence Notes"
        echo "  - Scripts survive reboots (stored in /data/)"
        echo "  - Cron jobs may be wiped during UniFi OS upgrades"
        echo "  - Re-run this installer after upgrades if monitoring stops"
        echo ""
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
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --no-cron         Install without setting up cron job"
                echo "  --silent          Perform installation silently (no prompts)"
                echo "  --overwrite-conf  Overwrite existing config file (only works with --silent)"
                echo "  --help            Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                                    # Interactive installation"
                echo "  $0 --silent                          # Silent installation, preserve existing config"
                echo "  $0 --silent --overwrite-conf          # Silent installation, overwrite config"
                echo "  $0 --silent --no-cron                 # Silent installation, no cron"
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
    
    # Validate flag combinations
    if [[ $OVERWRITE_CONF -eq 1 ]] && [[ $SILENT -eq 0 ]]; then
        log_warn "Warning: --overwrite-conf is only effective with --silent flag"
        log_warn "In interactive mode, you will be prompted to overwrite the config file"
    fi
}

# Main installation
main() {
    # Parse command-line arguments
    parse_args "$@"
    
    if [[ $SILENT -eq 0 ]]; then
        log_info "UDM VPN Monitor Installation"
        log_info "=============================="
        echo ""
    fi
    
    check_root
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

