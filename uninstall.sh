#!/bin/bash
#
# UDM VPN Monitor Uninstallation Script
# Removes the VPN monitoring script and all associated files
#
# Designed for UniFi Dream Machine (UDM) running UniFi OS 4.3+
#
# Version: 0.4.2
#

set -euo pipefail

# Installation paths (must match install.sh)
INSTALL_DIR="/data/vpn-monitor"
SCRIPT_NAME="vpn-monitor.sh"

# Get script directory for sourcing common functions
UNINSTALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared common functions (logging, root check)
# shellcheck source=lib/common.sh
source "${UNINSTALL_SCRIPT_DIR}/lib/common.sh"

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
	local crontab_content
	crontab_content=$(crontab -l 2>/dev/null || echo "")
	if echo "$crontab_content" | grep -q "vpn-monitor.sh"; then
		# Remove cron entry - only update crontab if there are other entries
		local filtered_content
		filtered_content=$(echo "$crontab_content" | grep -v "vpn-monitor.sh")
		if [ -n "$filtered_content" ]; then
			echo "$filtered_content" | crontab -
		else
			# No other entries, clear crontab entirely
			crontab -r 2>/dev/null || true
		fi
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

# Remove logrotate configuration
#
# Removes the logrotate configuration file for application log rotation.
# Only removes if the file exists and we have write access.
#
# Returns:
#   0: Logrotate config removed successfully (or didn't exist)
#   1: Failed to remove logrotate config
#
# Side effects:
#   Removes /etc/logrotate.d/vpn-monitor if it exists
remove_logrotate_config() {
	local logrotate_config="/etc/logrotate.d/vpn-monitor"

	if [[ -f "$logrotate_config" ]]; then
		log_info "Removing logrotate configuration..."

		# Check if we have write access
		if [[ ! -w /etc/logrotate.d ]]; then
			log_warn "Cannot write to /etc/logrotate.d, skipping logrotate config removal"
			log_warn "Manual removal required: rm $logrotate_config"
			return 0
		fi

		rm -f "$logrotate_config"

		# Verify removal
		if [[ -f "$logrotate_config" ]]; then
			log_error "Failed to remove logrotate configuration: $logrotate_config"
			return 1
		else
			log_info "Logrotate configuration removed"
		fi
	else
		log_info "Logrotate configuration not found (may have been removed already)"
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

# Remove systemd service for keepalive daemon
#
# Disables, stops, and removes the systemd service file for the VPN keepalive daemon.
# Only removes if systemd is available and service exists.
#
# Returns:
#   0: Always succeeds (warnings logged but don't fail)
#
# Side effects:
#   - Disables systemd service
#   - Stops systemd service if running
#   - Removes /etc/systemd/system/vpn-keepalive.service
#   - Reloads systemd daemon
remove_keepalive_service() {
	local service_file="/etc/systemd/system/vpn-keepalive.service"

	# Check if systemd is available
	if ! command -v systemctl >/dev/null 2>&1; then
		return 0
	fi

	# Check if service file exists
	if [[ ! -f "$service_file" ]]; then
		return 0
	fi

	log_info "Removing systemd service for VPN keepalive daemon..."

	# Disable service (if enabled)
	if systemctl is-enabled vpn-keepalive >/dev/null 2>&1; then
		systemctl disable vpn-keepalive >/dev/null 2>&1 || log_warn "Failed to disable systemd service"
	fi

	# Stop service (if running)
	if systemctl is-active vpn-keepalive >/dev/null 2>&1; then
		systemctl stop vpn-keepalive >/dev/null 2>&1 || log_warn "Failed to stop systemd service"
	fi

	# Remove service file
	rm -f "$service_file" 2>/dev/null || log_warn "Failed to remove systemd service file"

	# Reload systemd daemon
	systemctl daemon-reload >/dev/null 2>&1 || log_warn "Failed to reload systemd daemon"

	return 0
}

# Stop keepalive daemon if running
#
# Stops the VPN keepalive daemon if it is running.
# This ensures the daemon is cleanly stopped before uninstallation.
#
# Returns:
#   0: Always succeeds (warnings logged but don't fail)
#
# Side effects:
#   - Stops keepalive daemon if running
#   - Removes PID file
#
# Note:
#   Uses the keepalive script's stop command if available
#   Falls back to manual PID file check and kill if script unavailable
stop_keepalive_daemon() {
	local keepalive_script="${INSTALL_DIR}/vpn-keepalive.sh"
	local pidfile="${INSTALL_DIR}/vpn-keepalive.pid"

	# Try to use keepalive script's stop command if available
	if [[ -f "$keepalive_script" ]] && [[ -x "$keepalive_script" ]]; then
		if "$keepalive_script" status >/dev/null 2>&1; then
			log_info "Stopping VPN keepalive daemon..."
			"$keepalive_script" stop >/dev/null 2>&1 || log_warn "Failed to stop keepalive daemon via script"
		fi
	# Fallback: check PID file directly
	elif [[ -f "$pidfile" ]]; then
		local pid
		pid=$(cat "$pidfile" 2>/dev/null || echo "")
		if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
			log_info "Stopping VPN keepalive daemon (PID: $pid)..."
			kill -TERM "$pid" 2>/dev/null || true
			sleep 1
			# Force kill if still running
			if kill -0 "$pid" 2>/dev/null; then
				kill -KILL "$pid" 2>/dev/null || true
			fi
			rm -f "$pidfile" 2>/dev/null || true
		fi
	fi
}

# Clean up any stale lockfiles
#
# Removes any stale lockfiles that may persist if the installation directory
# was removed but lockfile remained (shouldn't happen normally).
# This is a safety cleanup to ensure complete removal.
#
# Returns:
#   0: Always succeeds (warnings logged but don't fail)
#
# Side effects:
#   - Removes lockfile if it exists
#   - Logs warning if lockfile found (indicates unexpected state)
#
# Examples:
#   cleanup_lockfile
#   # Removes lockfile if it exists
#
# Note:
#   Lockfile path: ${INSTALL_DIR}/vpn-monitor.lock
#   Errors are silently ignored (|| true)
#   Should not normally find lockfile (directory removal should have handled it)
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
#   - Logrotate configuration no longer exists
# Logs errors for any components that still exist.
#
# Returns:
#   0: Uninstallation verified successfully (all components removed)
#   1: Verification failed (some components still exist)
#
# Side effects:
#   - Logs info messages for successful removals
#   - Logs error messages for components still present
#   - Counts errors and reports summary
#
# Examples:
#   if verify_uninstallation; then
#       echo "Uninstallation verified"
#   else
#       echo "Some components remain"
#   fi
#
# Note:
#   Checks INSTALL_DIR, crontab entries, and logrotate config
#   Uses crontab -l and grep to check for cron entries
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

	# Check logrotate config is gone
	local logrotate_config="/etc/logrotate.d/vpn-monitor"
	if [[ -f "$logrotate_config" ]]; then
		log_error "Logrotate configuration still exists: $logrotate_config"
		errors=$((errors + 1))
	else
		log_info "Logrotate configuration removed"
	fi

	# Check systemd service is gone
	local service_file="/etc/systemd/system/vpn-keepalive.service"
	if [[ -f "$service_file" ]]; then
		log_error "Systemd service still exists: $service_file"
		errors=$((errors + 1))
	else
		log_info "Systemd service removed"
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
	echo "  - VPN keepalive systemd service"
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
		echo "  - VPN keepalive daemon (if running)"
		echo "  - VPN keepalive systemd service (if installed)"
		echo "  - Logrotate configuration (if installed)"
		echo ""
		read -p "Are you sure you want to continue? (yes/no): " -r
		echo ""
		if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
			log_info "Uninstallation cancelled"
			exit 0
		fi
	fi

	remove_cron
	remove_logrotate_config
	remove_keepalive_service
	stop_keepalive_daemon
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
