#!/bin/bash
#
# UDM VPN Monitor Uninstallation Script
# Removes the VPN monitoring script and all associated files
#
# Designed for UniFi Dream Machine (UDM) running UniFi OS 4.3+
#
# Version: 0.4.3
#

set -euo pipefail

# Installation paths (must match install.sh)
INSTALL_DIR="/data/vpn-monitor"
CONFIG_FILE="${INSTALL_DIR}/vpn-monitor.conf"
LOGS_DIR="${INSTALL_DIR}/logs"
STATE_DIR="${INSTALL_DIR}/state"

# Flags for file handling
REMOVE_CONFIG=""       # Empty means prompt user, "yes" means remove, "no" means keep
REMOVE_LOGS=""         # Empty means prompt user, "yes" means remove, "no" means keep
REMOVE_STATE=""        # Empty means prompt user, "yes" means remove, "no" means keep
SKIP_CONFIRMATION=0    # Set to 1 if --yes flag is provided
KEEP_CONFIG_IN_PLACE=0 # Set to 1 if config file should be kept in installation directory
KEEP_LOGS_IN_PLACE=0   # Set to 1 if logs directory should be kept in installation directory
KEEP_STATE_IN_PLACE=0  # Set to 1 if state directory should be kept in installation directory

# Get script directory for sourcing common functions
UNINSTALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared common functions (logging, root check)
# shellcheck source=lib/common.sh
source "${UNINSTALL_SCRIPT_DIR}/lib/common.sh"

# Validate installation directory path is safe
#
# Validates that INSTALL_DIR is exactly the expected path to prevent
# accidental deletion of unintended files. This is a critical safety check
# that ensures we never delete files outside the intended installation directory.
#
# Returns:
#   0: INSTALL_DIR is safe (matches expected path)
#   1: INSTALL_DIR is unsafe (doesn't match expected path or is empty)
#
# Side effects:
#   Exits script with error if INSTALL_DIR is unsafe
#
# Note:
#   This prevents deletion if INSTALL_DIR has been modified or is empty
validate_install_dir_safety() {
	local expected_dir="/data/vpn-monitor"

	# Check INSTALL_DIR is not empty
	if [[ -z "$INSTALL_DIR" ]]; then
		log_error "INSTALL_DIR is empty - this is unsafe. Aborting uninstallation."
		exit 1
	fi

	# Check INSTALL_DIR matches expected path exactly
	if [[ "$INSTALL_DIR" != "$expected_dir" ]]; then
		log_error "INSTALL_DIR path mismatch detected!"
		log_error "Expected: $expected_dir"
		log_error "Actual:   $INSTALL_DIR"
		log_error "This is unsafe - aborting uninstallation to prevent accidental file deletion."
		exit 1
	fi

	# Additional safety: ensure path doesn't contain dangerous patterns
	# Check it's not root directory
	if [[ "$INSTALL_DIR" == "/" ]]; then
		log_error "INSTALL_DIR is root directory (/) - this is extremely unsafe. Aborting."
		exit 1
	fi

	return 0
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
	local crontab_content
	crontab_content=$(crontab -l 2>/dev/null || echo "")
	if echo "$crontab_content" | grep -q "vpn-monitor.sh"; then
		# Remove cron entry - only update crontab if there are other entries
		local filtered_content
		filtered_content=$(echo "$crontab_content" | grep -v "vpn-monitor.sh")
		if [ -n "$filtered_content" ]; then
			if ! echo "$filtered_content" | crontab - 2>/dev/null; then
				log_error "Failed to update crontab"
				return 1
			fi
		else
			# No other entries, clear crontab entirely
			if ! crontab -r 2>/dev/null; then
				log_warn "Failed to clear crontab (may not have permission or crontab already empty)"
				# Don't fail if crontab is already empty - verification will catch if cron still exists
			fi
		fi

		# Verify removal
		if crontab -l 2>/dev/null | grep -q "vpn-monitor.sh"; then
			log_error "Failed to remove cron job - verification check failed"
			return 1
		fi
		log_info "Cron job removed"
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

# Handle configuration file removal
#
# Prompts user whether to remove the configuration file, or uses flag value.
# If user wants to keep it, marks it to be kept in-place in the installation directory.
#
# Arguments:
#   None (uses global REMOVE_CONFIG flag)
#
# Returns:
#   0: Config file handled successfully
#   1: Failed to handle config file
#
# Side effects:
#   - May prompt user for input
#   - Sets global KEEP_CONFIG_IN_PLACE flag if config should be kept
#   - Removes config file if user chooses to remove it
#
# Note:
#   If REMOVE_CONFIG is empty, prompts user interactively
#   If REMOVE_CONFIG is "yes", removes config file
#   If REMOVE_CONFIG is "no", keeps config file in-place (sets KEEP_CONFIG_IN_PLACE=1)
handle_config_file() {
	if [[ ! -f "$CONFIG_FILE" ]]; then
		log_info "Configuration file not found: $CONFIG_FILE"
		return 0
	fi

	# Determine action based on flag or prompt user
	local should_remove=""
	if [[ -n "$REMOVE_CONFIG" ]]; then
		# Flag was set, use it
		if [[ "$REMOVE_CONFIG" == "yes" ]]; then
			should_remove="yes"
		else
			should_remove="no"
		fi
	else
		# No flag, prompt user interactively (default behavior)
		# Skip prompts only if CI env var is set or --yes flag was provided
		if [[ -n "${CI:-}" ]] || [[ $SKIP_CONFIRMATION -eq 1 ]]; then
			# CI or non-interactive mode: default to removing config
			should_remove="yes"
			if [[ -n "${CI:-}" ]]; then
				log_info "CI mode detected, removing configuration file"
			else
				log_info "Non-interactive mode detected (--yes flag), removing configuration file"
			fi
		else
			# Interactive mode (default): ask user
			echo ""
			log_info "Configuration file found: $CONFIG_FILE"
			read -p "Do you want to remove the configuration file? (yes/no) [no]: " -r
			echo ""
			if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
				should_remove="yes"
			else
				should_remove="no"
			fi
		fi
	fi

	if [[ "$should_remove" == "yes" ]]; then
		log_info "Removing configuration file: $CONFIG_FILE"
		rm -f "$CONFIG_FILE"
		if [[ -f "$CONFIG_FILE" ]]; then
			log_error "Failed to remove configuration file"
			return 1
		else
			log_info "Configuration file removed"
		fi
	else
		# Keep config file in-place
		KEEP_CONFIG_IN_PLACE=1
		log_info "Configuration file will be kept in-place: $CONFIG_FILE"
	fi

	return 0
}

# Handle logs directory removal
#
# Prompts user whether to remove the logs directory, or uses flag value.
# If user wants to keep it, marks it to be kept in-place in the installation directory.
#
# Arguments:
#   None (uses global REMOVE_LOGS flag)
#
# Returns:
#   0: Logs directory handled successfully
#   1: Failed to handle logs directory
#
# Side effects:
#   - May prompt user for input
#   - Sets global KEEP_LOGS_IN_PLACE flag if logs should be kept
#   - Removes logs directory if user chooses to remove it
#
# Note:
#   If REMOVE_LOGS is empty, prompts user interactively
#   If REMOVE_LOGS is "yes", removes logs directory
#   If REMOVE_LOGS is "no", keeps logs directory in-place (sets KEEP_LOGS_IN_PLACE=1)
handle_logs_dir() {
	if [[ ! -d "$LOGS_DIR" ]]; then
		log_info "Logs directory not found: $LOGS_DIR"
		return 0
	fi

	# Determine action based on flag or prompt user
	local should_remove=""
	if [[ -n "$REMOVE_LOGS" ]]; then
		# Flag was set, use it
		if [[ "$REMOVE_LOGS" == "yes" ]]; then
			should_remove="yes"
		else
			should_remove="no"
		fi
	else
		# No flag, prompt user interactively (default behavior)
		# Skip prompts only if CI env var is set or --yes flag was provided
		if [[ -n "${CI:-}" ]] || [[ $SKIP_CONFIRMATION -eq 1 ]]; then
			# CI or non-interactive mode: default to removing logs
			should_remove="yes"
			if [[ -n "${CI:-}" ]]; then
				log_info "CI mode detected, removing logs directory"
			else
				log_info "Non-interactive mode detected (--yes flag), removing logs directory"
			fi
		else
			# Interactive mode (default): ask user
			echo ""
			log_info "Logs directory found: $LOGS_DIR"
			read -p "Do you want to remove the logs directory? (yes/no) [no]: " -r
			echo ""
			if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
				should_remove="yes"
			else
				should_remove="no"
			fi
		fi
	fi

	if [[ "$should_remove" == "yes" ]]; then
		# Mark for removal (will be removed by remove_installation_dir)
		KEEP_LOGS_IN_PLACE=0
		log_info "Logs directory will be removed"
	else
		# Keep logs directory in-place
		KEEP_LOGS_IN_PLACE=1
		log_info "Logs directory will be kept in-place: $LOGS_DIR"
	fi

	return 0
}

# Handle state directory removal
#
# Prompts user whether to remove the state directory, or uses flag value.
# If user wants to keep it, marks it to be kept in-place in the installation directory.
#
# Arguments:
#   None (uses global REMOVE_STATE flag)
#
# Returns:
#   0: State directory handled successfully
#   1: Failed to handle state directory
#
# Side effects:
#   - May prompt user for input
#   - Sets global KEEP_STATE_IN_PLACE flag if state should be kept
#   - Removes state directory if user chooses to remove it
#
# Note:
#   If REMOVE_STATE is empty, prompts user interactively
#   If REMOVE_STATE is "yes", removes state directory
#   If REMOVE_STATE is "no", keeps state directory in-place (sets KEEP_STATE_IN_PLACE=1)
handle_state_dir() {
	if [[ ! -d "$STATE_DIR" ]]; then
		log_info "State directory not found: $STATE_DIR"
		return 0
	fi

	# Determine action based on flag or prompt user
	local should_remove=""
	if [[ -n "$REMOVE_STATE" ]]; then
		# Flag was set, use it
		if [[ "$REMOVE_STATE" == "yes" ]]; then
			should_remove="yes"
		else
			should_remove="no"
		fi
	else
		# No flag, prompt user interactively (default behavior)
		# Skip prompts only if CI env var is set or --yes flag was provided
		if [[ -n "${CI:-}" ]] || [[ $SKIP_CONFIRMATION -eq 1 ]]; then
			# CI or non-interactive mode: default to removing state
			should_remove="yes"
			if [[ -n "${CI:-}" ]]; then
				log_info "CI mode detected, removing state directory"
			else
				log_info "Non-interactive mode detected (--yes flag), removing state directory"
			fi
		else
			# Interactive mode (default): ask user
			echo ""
			log_info "State directory found: $STATE_DIR"
			read -p "Do you want to remove the state directory? (yes/no) [no]: " -r
			echo ""
			if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
				should_remove="yes"
			else
				should_remove="no"
			fi
		fi
	fi

	if [[ "$should_remove" == "yes" ]]; then
		# Mark for removal (will be removed by remove_installation_dir)
		KEEP_STATE_IN_PLACE=0
		log_info "State directory will be removed"
	else
		# Keep state directory in-place
		KEEP_STATE_IN_PLACE=1
		log_info "State directory will be kept in-place: $STATE_DIR"
	fi

	return 0
}

# Build preserved items list string for logging
#
# Converts an array of preserved item names into a comma-separated string
# for use in log messages.
#
# Arguments:
#   $@: Array of preserved item names (passed as separate arguments)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints comma-separated list of preserved items to stdout
#
# Examples:
#   preserved_list=$(build_preserved_list_string "${preserve_items[@]}")
build_preserved_list_string() {
	local preserved_list=""
	for item in "$@"; do
		if [[ -n "$preserved_list" ]]; then
			preserved_list="${preserved_list}, ${item}"
		else
			preserved_list="$item"
		fi
	done
	echo "$preserved_list"
}

# Remove installation directory
#
# Removes the installation directory and its contents.
# If config file, logs, or state directories are being kept in-place, removes all files
# except those preserved items and keeps the directory. Otherwise, removes the entire directory.
#
# Returns:
#   0: Directory/files removed successfully (or didn't exist)
#   1: Failed to remove directory/files
#
# Side effects:
#   - Displays list of files that will be removed
#   - Deletes ${INSTALL_DIR} and all contents (unless items are kept)
#   - If items are kept, removes all files except preserved items
remove_installation_dir() {
	# Safety check: re-validate INSTALL_DIR before deletion (defense in depth)
	if [[ "$INSTALL_DIR" != "/data/vpn-monitor" ]]; then
		log_error "INSTALL_DIR validation failed in remove_installation_dir - aborting"
		log_error "Expected: /data/vpn-monitor, Got: $INSTALL_DIR"
		return 1
	fi

	# Build list of items to preserve
	local preserve_items=()
	if [[ $KEEP_CONFIG_IN_PLACE -eq 1 ]]; then
		preserve_items+=("$(basename "$CONFIG_FILE")")
	fi
	if [[ $KEEP_LOGS_IN_PLACE -eq 1 ]]; then
		preserve_items+=("$(basename "$LOGS_DIR")")
	fi
	if [[ $KEEP_STATE_IN_PLACE -eq 1 ]]; then
		preserve_items+=("$(basename "$STATE_DIR")")
	fi

	if [[ ${#preserve_items[@]} -gt 0 ]]; then
		# Keep some items in-place, remove everything else
		local preserved_list
		preserved_list=$(build_preserved_list_string "${preserve_items[@]}")
		log_info "Removing files from installation directory (keeping: ${preserved_list}): $INSTALL_DIR"

		if [[ -d "$INSTALL_DIR" ]]; then
			# List what will be removed
			log_info "The following will be removed:"
			# List items that are not preserved
			for item in "$INSTALL_DIR"/*; do
				if [[ ! -e "$item" ]]; then
					continue
				fi
				local item_name
				item_name=$(basename "$item")
				local should_preserve=0
				for preserve_item in "${preserve_items[@]}"; do
					if [[ "$item_name" == "$preserve_item" ]]; then
						should_preserve=1
						break
					fi
				done
				if [[ $should_preserve -eq 0 ]]; then
					if [[ -d "$item" ]]; then
						echo "  ${item_name}/ (directory)"
					else
						ls -lh "$item" 2>/dev/null | awk '{print "  " $0}' || echo "  ${item_name}"
					fi
				fi
			done || true

			# Remove all files and directories except preserved items
			# Use a simpler approach: iterate and remove items that aren't preserved
			for item in "$INSTALL_DIR"/*; do
				if [[ ! -e "$item" ]]; then
					continue
				fi
				# Safety check: ensure item is actually within INSTALL_DIR
				# This prevents issues with symlinks or path traversal attempts
				# Use readlink -f if available to resolve symlinks, otherwise use item path directly
				local item_realpath
				if command -v readlink >/dev/null 2>&1; then
					item_realpath=$(readlink -f "$item" 2>/dev/null || echo "$item")
				else
					item_realpath="$item"
				fi
				local install_dir_realpath
				if command -v readlink >/dev/null 2>&1; then
					install_dir_realpath=$(readlink -f "$INSTALL_DIR" 2>/dev/null || echo "$INSTALL_DIR")
				else
					install_dir_realpath="$INSTALL_DIR"
				fi
				# Check that item_realpath starts with install_dir_realpath followed by /
				# This ensures the item is actually within the installation directory
				if [[ "$item_realpath" != "$install_dir_realpath"/* ]]; then
					log_warn "Skipping item outside installation directory: $item"
					continue
				fi
				local item_name
				item_name=$(basename "$item")
				local should_preserve=0
				for preserve_item in "${preserve_items[@]}"; do
					if [[ "$item_name" == "$preserve_item" ]]; then
						should_preserve=1
						break
					fi
				done
				if [[ $should_preserve -eq 0 ]]; then
					rm -rf "$item" 2>/dev/null || true
				fi
			done || true

			# Verify preserved items still exist
			local verify_errors=0
			if [[ $KEEP_CONFIG_IN_PLACE -eq 1 ]] && [[ ! -f "$CONFIG_FILE" ]]; then
				log_error "Config file was unexpectedly removed"
				verify_errors=$((verify_errors + 1))
			fi
			if [[ $KEEP_LOGS_IN_PLACE -eq 1 ]] && [[ ! -d "$LOGS_DIR" ]]; then
				log_error "Logs directory was unexpectedly removed"
				verify_errors=$((verify_errors + 1))
			fi
			if [[ $KEEP_STATE_IN_PLACE -eq 1 ]] && [[ ! -d "$STATE_DIR" ]]; then
				log_error "State directory was unexpectedly removed"
				verify_errors=$((verify_errors + 1))
			fi

			if [[ $verify_errors -eq 0 ]]; then
				log_info "Installation files removed successfully (preserved items: ${preserved_list})"
			else
				log_error "Some preserved items were unexpectedly removed"
				return 1
			fi
		else
			log_warn "Installation directory not found: $INSTALL_DIR"
		fi
	else
		# Remove entire directory including all files
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
	local pidfile="${INSTALL_DIR}/state/vpn-keepalive.pid"

	# Try to use keepalive script's stop command if available
	if [[ -f "$keepalive_script" ]] && [[ -x "$keepalive_script" ]]; then
		if "$keepalive_script" status >/dev/null 2>&1; then
			log_info "Stopping VPN keepalive daemon..."
			"$keepalive_script" stop >/dev/null 2>&1 || log_warn "Failed to stop keepalive daemon via script"
		fi
	# Fallback: check PID file directly
	elif [[ -f "$pidfile" ]] && file_exists_and_readable "$pidfile"; then
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
# Removes any stale lockfiles that may persist after file removal.
# This is a safety cleanup to ensure complete removal.
# When config is kept in-place, the find command should remove the lockfile,
# but this provides an additional safety net.
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
#   Should not normally find lockfile (file removal should have handled it)
cleanup_lockfile() {
	local lockfile="${INSTALL_DIR}/vpn-monitor.lock"
	if [[ -f "$lockfile" ]]; then
		log_warn "Found stale lockfile (should have been removed during cleanup)"
		rm -f "$lockfile" 2>/dev/null || true
	fi
}

# Verify uninstallation
#
# Verifies that the uninstallation completed successfully by checking:
#   - Installation directory no longer exists (or only preserved items remain)
#   - Cron entry no longer exists
#   - Logrotate configuration no longer exists
# Logs errors for any components that still exist unexpectedly.
#
# Returns:
#   0: Uninstallation verified successfully (all components removed or properly preserved)
#   1: Verification failed (some components still exist unexpectedly)
#
# Side effects:
#   - Logs info messages for successful removals
#   - Logs error messages for components still present unexpectedly
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
#   Verifies preserved items (config, logs, state) are still present if kept
verify_uninstallation() {
	log_info "Verifying uninstallation..."

	local errors=0

	# Build list of preserved items
	local preserved_items=()
	if [[ $KEEP_CONFIG_IN_PLACE -eq 1 ]]; then
		preserved_items+=("config file")
	fi
	if [[ $KEEP_LOGS_IN_PLACE -eq 1 ]]; then
		preserved_items+=("logs directory")
	fi
	if [[ $KEEP_STATE_IN_PLACE -eq 1 ]]; then
		preserved_items+=("state directory")
	fi

	# Check installation directory
	if [[ ${#preserved_items[@]} -gt 0 ]]; then
		# Some items are preserved, directory should exist with only preserved items
		if [[ -d "$INSTALL_DIR" ]]; then
			# Verify preserved items exist
			if [[ $KEEP_CONFIG_IN_PLACE -eq 1 ]] && [[ ! -f "$CONFIG_FILE" ]]; then
				log_error "Config file should be preserved but is missing"
				errors=$((errors + 1))
			fi
			if [[ $KEEP_LOGS_IN_PLACE -eq 1 ]] && [[ ! -d "$LOGS_DIR" ]]; then
				log_error "Logs directory should be preserved but is missing"
				errors=$((errors + 1))
			fi
			if [[ $KEEP_STATE_IN_PLACE -eq 1 ]] && [[ ! -d "$STATE_DIR" ]]; then
				log_error "State directory should be preserved but is missing"
				errors=$((errors + 1))
			fi

			# Check that only preserved items remain
			local expected_count=${#preserved_items[@]}
			local actual_count=0
			if [[ $KEEP_CONFIG_IN_PLACE -eq 1 ]] && [[ -f "$CONFIG_FILE" ]]; then
				actual_count=$((actual_count + 1))
			fi
			if [[ $KEEP_LOGS_IN_PLACE -eq 1 ]] && [[ -d "$LOGS_DIR" ]]; then
				actual_count=$((actual_count + 1))
			fi
			if [[ $KEEP_STATE_IN_PLACE -eq 1 ]] && [[ -d "$STATE_DIR" ]]; then
				actual_count=$((actual_count + 1))
			fi

			# Count top-level items in directory
			local top_level_count
			top_level_count=$(find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 | wc -l)

			# Build preserved list string for logging
			local preserved_list
			preserved_list=$(build_preserved_list_string "${preserved_items[@]}")

			if [[ $top_level_count -eq $expected_count ]] && [[ $actual_count -eq $expected_count ]]; then
				log_info "Installation directory cleaned (preserved: ${preserved_list})"
			else
				log_error "Installation directory should only contain preserved items (${preserved_list})"
				errors=$((errors + 1))
			fi
		else
			log_error "Installation directory should exist with preserved items but is missing"
			errors=$((errors + 1))
		fi
	else
		# Nothing preserved, directory should be completely gone
		if [[ -d "$INSTALL_DIR" ]]; then
			log_error "Installation directory still exists: $INSTALL_DIR"
			errors=$((errors + 1))
		else
			log_info "Installation directory removed"
		fi
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
# Lists any preserved items (config, logs, state) if they were kept.
#
# Returns:
#   0: Always succeeds
display_summary() {
	echo ""
	log_info "Uninstallation complete!"
	echo ""
	log_info "Removed:"
	echo "  - Installation files"
	if [[ $KEEP_CONFIG_IN_PLACE -eq 0 ]]; then
		echo "  - Configuration file"
	fi
	if [[ $KEEP_LOGS_IN_PLACE -eq 0 ]]; then
		echo "  - Log files"
	fi
	if [[ $KEEP_STATE_IN_PLACE -eq 0 ]]; then
		echo "  - State files"
	fi
	echo "  - Cron job entry"
	echo "  - VPN keepalive systemd service"
	echo "  - Logrotate configuration"
	echo ""

	# List preserved items
	local preserved_count=0
	if [[ $KEEP_CONFIG_IN_PLACE -eq 1 ]]; then
		preserved_count=$((preserved_count + 1))
	fi
	if [[ $KEEP_LOGS_IN_PLACE -eq 1 ]]; then
		preserved_count=$((preserved_count + 1))
	fi
	if [[ $KEEP_STATE_IN_PLACE -eq 1 ]]; then
		preserved_count=$((preserved_count + 1))
	fi

	if [[ $preserved_count -gt 0 ]]; then
		log_info "Preserved:"
		if [[ $KEEP_CONFIG_IN_PLACE -eq 1 ]]; then
			echo "  - Configuration file: $CONFIG_FILE"
		fi
		if [[ $KEEP_LOGS_IN_PLACE -eq 1 ]]; then
			echo "  - Logs directory: $LOGS_DIR"
		fi
		if [[ $KEEP_STATE_IN_PLACE -eq 1 ]]; then
			echo "  - State directory: $STATE_DIR"
		fi
		echo ""
	fi

	if [[ $preserved_count -eq 0 ]]; then
		log_info "VPN Monitor has been completely removed from your system."
	else
		log_info "VPN Monitor has been removed. Preserved items remain in: $INSTALL_DIR"
	fi
	echo ""
}

# Parse command-line arguments
#
# Parses command-line arguments and sets global flags accordingly.
#
# Arguments:
#   $@: Command-line arguments
#       --yes: Skip interactive confirmation (non-interactive mode)
#       --remove-config: Automatically remove configuration file
#       --keep-config: Automatically keep configuration file in-place
#       --remove-logs: Automatically remove logs directory
#       --keep-logs: Automatically keep logs directory in-place
#       --remove-state: Automatically remove state directory
#       --keep-state: Automatically keep state directory in-place
#
# Returns:
#   0: Success
#   1: Error (conflicting flags)
#
# Side effects:
#   Sets global REMOVE_CONFIG, REMOVE_LOGS, REMOVE_STATE flags
#   Sets global SKIP_CONFIRMATION flag if --yes is found
#   Exits script with error if conflicting flags are provided
parse_args() {
	# Default to interactive mode (prompts will be shown unless --yes flag or CI env var is set)
	SKIP_CONFIRMATION=0
	local remove_config_count=0
	local keep_config_count=0
	local remove_logs_count=0
	local keep_logs_count=0
	local remove_state_count=0
	local keep_state_count=0

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--yes)
			SKIP_CONFIRMATION=1
			shift
			;;
		--remove-config)
			REMOVE_CONFIG="yes"
			remove_config_count=$((remove_config_count + 1))
			shift
			;;
		--keep-config)
			REMOVE_CONFIG="no"
			keep_config_count=$((keep_config_count + 1))
			shift
			;;
		--remove-logs)
			REMOVE_LOGS="yes"
			remove_logs_count=$((remove_logs_count + 1))
			shift
			;;
		--keep-logs)
			REMOVE_LOGS="no"
			keep_logs_count=$((keep_logs_count + 1))
			shift
			;;
		--remove-state)
			REMOVE_STATE="yes"
			remove_state_count=$((remove_state_count + 1))
			shift
			;;
		--keep-state)
			REMOVE_STATE="no"
			keep_state_count=$((keep_state_count + 1))
			shift
			;;
		*)
			# Unknown argument, ignore
			shift
			;;
		esac
	done

	# Check for conflicting flags
	if [[ $remove_config_count -gt 0 ]] && [[ $keep_config_count -gt 0 ]]; then
		log_error "Conflicting flags: --remove-config and --keep-config cannot be used together"
		log_error "Please specify only one: --remove-config or --keep-config"
		return 1
	fi

	if [[ $remove_logs_count -gt 0 ]] && [[ $keep_logs_count -gt 0 ]]; then
		log_error "Conflicting flags: --remove-logs and --keep-logs cannot be used together"
		log_error "Please specify only one: --remove-logs or --keep-logs"
		return 1
	fi

	if [[ $remove_state_count -gt 0 ]] && [[ $keep_state_count -gt 0 ]]; then
		log_error "Conflicting flags: --remove-state and --keep-state cannot be used together"
		log_error "Please specify only one: --remove-state or --keep-state"
		return 1
	fi

	return 0
}

# Main uninstallation
#
# Main entry point for the uninstallation script.
# Orchestrates the complete uninstallation process.
#
# Arguments:
#   $@: Command-line arguments
#       --yes: Skip interactive confirmation (non-interactive mode)
#       --remove-config: Automatically remove configuration file
#       --keep-config: Automatically keep configuration file in-place
#       --remove-logs: Automatically remove logs directory
#       --keep-logs: Automatically keep logs directory in-place
#       --remove-state: Automatically remove state directory
#       --keep-state: Automatically keep state directory in-place
#
# Returns:
#   0: Uninstallation successful
#   1: Uninstallation failed
#
# Execution flow:
#   1. Parse command-line arguments
#   2. Check root privileges
#   3. Check if installation exists
#   4. Prompt for confirmation (unless --yes or CI environment)
#   5. Handle configuration file (prompt or use flag)
#   6. Handle logs directory (prompt or use flag)
#   7. Handle state directory (prompt or use flag)
#   8. Remove cron entry
#   9. Remove logrotate config
#  10. Remove keepalive service
#  11. Stop keepalive daemon
#  12. Remove installation directory (or files except preserved items if kept)
#  13. Clean up stale lockfiles
#  14. Verify uninstallation
#  15. Display summary
main() {
	log_info "UDM VPN Monitor Uninstallation"
	log_info "================================="
	echo ""

	# Parse arguments to set REMOVE_CONFIG flag
	if ! parse_args "$@"; then
		exit 1
	fi

	check_root

	# Validate INSTALL_DIR is safe before any deletion operations
	validate_install_dir_safety

	# Check if installation exists
	if ! check_installation; then
		# Still try to remove cron entry in case it exists
		remove_cron
		log_warn "No installation found, but checked for cron entries"
		exit 0
	fi

	# Confirm with user (interactive mode by default, unless CI env var or --yes flag)
	if [[ $SKIP_CONFIRMATION -eq 0 ]] && [[ -z "${CI:-}" ]]; then
		echo ""
		log_warn "This will remove:"
		echo "  - Installation directory: $INSTALL_DIR"
		echo "  - All scripts and library files"
		echo "  - Configuration file (unless you choose to keep it)"
		echo "  - Log files (unless you choose to keep them)"
		echo "  - State files (unless you choose to keep them)"
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

	# Handle configuration file (prompt or use flag)
	if ! handle_config_file; then
		log_error "Failed to handle configuration file"
		exit 1
	fi

	# Handle logs directory (prompt or use flag)
	if ! handle_logs_dir; then
		log_error "Failed to handle logs directory"
		exit 1
	fi

	# Handle state directory (prompt or use flag)
	if ! handle_state_dir; then
		log_error "Failed to handle state directory"
		exit 1
	fi

	# Remove components - continue even if individual steps fail
	# to ensure maximum cleanup is attempted
	if ! remove_cron; then
		log_warn "Failed to remove cron job, but continuing with uninstallation"
	fi
	if ! remove_logrotate_config; then
		log_warn "Failed to remove logrotate config, but continuing with uninstallation"
	fi
	if ! remove_keepalive_service; then
		log_warn "Failed to remove keepalive service, but continuing with uninstallation"
	fi
	stop_keepalive_daemon || true
	if ! remove_installation_dir; then
		log_error "Failed to remove installation directory"
		exit 1
	fi
	cleanup_lockfile || true

	if verify_uninstallation; then
		display_summary
		exit 0
	else
		log_error "Uninstallation completed with errors"
		exit 1
	fi
}

# Run main only if script is executed directly (not sourced)
# This allows the script to be sourced for testing without executing main()
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
