#!/bin/bash
#
# Cron job management for UDM VPN Monitor
# Shared by install.sh and vpn-monitor-control.sh
#
# Version: 0.8.3
#

# Parse and validate cron schedule from config file
#
# Arguments:
#   $1: Path to config file
#
# Returns:
#   0: Valid cron schedule found
#   1: Invalid or missing schedule
#
# Output:
#   Prints validated cron schedule
parse_cron_schedule_from_config() {
	local config_file="$1"
	local schedule=""

	if [[ ! -f "$config_file" ]] || ! file_exists_and_readable "$config_file"; then
		return 1
	fi

	if ! schedule=$(get_config_var_value_from_file "$config_file" "CRON_SCHEDULE" 2>/dev/null); then
		return 1
	fi

	schedule=$(trim "$schedule")
	[[ -z "$schedule" ]] && return 1
	[[ ! "$schedule" =~ [0-9*] ]] && return 1

	local IFS=' '
	local -a fields
	read -ra fields <<<"$schedule"
	[[ ${#fields[@]} -ne 5 ]] && return 1

	local field
	for field in "${fields[@]}"; do
		[[ ! "$field" =~ ^[0-9*,\-/\]+$ ]] && return 1
	done

	echo "$schedule"
	return 0
}

# Check if vpn-monitor cron entry exists
#
# Returns:
#   0: Cron entry present
#   1: No vpn-monitor cron entry
has_vpn_monitor_cron_entry() {
	local crontab_content
	crontab_content=$(crontab -l 2>/dev/null || echo "")
	echo "$crontab_content" | grep -q "vpn-monitor"
}

# Remove vpn-monitor cron entries from crontab
#
# Returns:
#   0: Always (best effort)
remove_vpn_monitor_cron() {
	local crontab_content filtered_content
	crontab_content=$(crontab -l 2>/dev/null || echo "")
	if ! echo "$crontab_content" | grep -q "vpn-monitor"; then
		return 0
	fi
	filtered_content=$(echo "$crontab_content" | grep -v "vpn-monitor" || true)
	if [[ -n "$filtered_content" ]]; then
		echo "$filtered_content" | crontab -
	else
		crontab -r 2>/dev/null || true
	fi
	log_message "INFO" "SYSTEM" "Removed vpn-monitor cron entry"
	return 0
}

# Install or update vpn-monitor cron entry from config
#
# Arguments:
#   $1: install directory (e.g. /data/vpn-monitor)
#
# Returns:
#   0: Cron installed or updated
#   1: install_dir missing or invalid
install_vpn_monitor_cron() {
	local install_dir="$1"
	local config_file cron_schedule enable_wrapper=0 cron_entry script_name

	if [[ -z "$install_dir" ]] || [[ ! -d "$install_dir" ]]; then
		log_message "ERROR" "SYSTEM" "install_vpn_monitor_cron: invalid install directory"
		return 1
	fi

	config_file="${install_dir}/vpn-monitor.conf"
	script_name="vpn-monitor.sh"
	cron_schedule="*/1 * * * *"

	if [[ -f "$config_file" ]]; then
		local config_schedule val
		if config_schedule=$(parse_cron_schedule_from_config "$config_file"); then
			cron_schedule="$config_schedule"
		fi
		if val=$(get_config_var_value_from_file "$config_file" "ENABLE_MONITOR_WRAPPER" 2>/dev/null); then
			[[ "$val" == "1" ]] && enable_wrapper=1
		else
			enable_wrapper=1
		fi
	else
		enable_wrapper=1
	fi

	if [[ $enable_wrapper -eq 1 ]]; then
		cron_entry="${cron_schedule} ${install_dir}/vpn-monitor-wrapper.sh >> ${install_dir}/logs/cron.log 2>&1 &"
	else
		cron_entry="${cron_schedule} ${install_dir}/${script_name} >> ${install_dir}/logs/cron.log 2>&1"
	fi

	remove_vpn_monitor_cron

	(
		crontab -l 2>/dev/null || true
		echo "$cron_entry"
	) | crontab -

	if [[ $enable_wrapper -eq 1 ]]; then
		log_message "INFO" "SYSTEM" "Cron job installed: wrapper (sub-minute execution)"
	else
		log_message "INFO" "SYSTEM" "Cron job installed: direct (${cron_schedule})"
	fi
	return 0
}
