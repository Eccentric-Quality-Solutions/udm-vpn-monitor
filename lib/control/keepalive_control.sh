#!/bin/bash
#
# Keepalive daemon control for UDM VPN Monitor
# Shared by install.sh, uninstall.sh, and vpn-monitor-control.sh
#
# Version: 0.8.3
#

KEEPALIVE_SYSTEMD_UNIT="vpn-keepalive"
KEEPALIVE_SYSTEMD_UNIT_FILE="/etc/systemd/system/${KEEPALIVE_SYSTEMD_UNIT}.service"

# Check whether the keepalive systemd unit file is installed
#
# Returns:
#   0: Unit file exists
#   1: Unit file missing
keepalive_systemd_unit_installed() {
	[[ -f "$KEEPALIVE_SYSTEMD_UNIT_FILE" ]]
}

# Check whether ENABLE_KEEPALIVE=1 in a config file
#
# Arguments:
#   $1: Path to config file
#
# Returns:
#   0: Keepalive enabled
#   1: Keepalive disabled or config missing/unreadable
is_keepalive_enabled() {
	local config_file="$1"
	local enable_keepalive="0"

	if [[ -f "$config_file" ]]; then
		enable_keepalive=$(get_config_var_value_from_file "$config_file" "ENABLE_KEEPALIVE" 2>/dev/null || echo "0")
	fi

	[[ "$enable_keepalive" == "1" ]]
}

# Stop keepalive via systemd (if active) or vpn-keepalive.sh script
#
# Arguments:
#   $1: Install directory (e.g. /data/vpn-monitor)
#
# Returns:
#   0: Always (best effort)
stop_keepalive() {
	local install_dir="$1"
	local keepalive_script="${install_dir}/vpn-keepalive.sh"

	if command -v systemctl >/dev/null 2>&1; then
		if systemctl is-active "$KEEPALIVE_SYSTEMD_UNIT" >/dev/null 2>&1; then
			systemctl stop "$KEEPALIVE_SYSTEMD_UNIT" 2>/dev/null || true
			return 0
		fi
	fi

	if [[ -x "$keepalive_script" ]]; then
		"$keepalive_script" stop 2>/dev/null || true
	fi
	return 0
}

# Start keepalive via systemd (enable + restart) or vpn-keepalive.sh script
#
# Arguments:
#   $1: Install directory (e.g. /data/vpn-monitor)
#   $2: (optional) Variable name to receive systemd restart stderr/stdout
#   $3: (optional) 1 = fail if systemctl enable fails; 0 = best effort (default)
#
# Returns:
#   0: Started successfully, or script fallback used
#   1: systemctl enable or restart failed (systemd path only)
start_keepalive() {
	local install_dir="$1"
	local output_var="${2:-}"
	local strict_enable="${3:-0}"
	local keepalive_script="${install_dir}/vpn-keepalive.sh"

	if command -v systemctl >/dev/null 2>&1 && keepalive_systemd_unit_installed; then
		if [[ "$strict_enable" == "1" ]]; then
			if ! systemctl enable "$KEEPALIVE_SYSTEMD_UNIT" 2>&1; then
				return 1
			fi
		else
			systemctl enable "$KEEPALIVE_SYSTEMD_UNIT" 2>/dev/null || true
		fi

		local out=""
		local exit_code=0
		out=$(systemctl restart "$KEEPALIVE_SYSTEMD_UNIT" 2>&1) || exit_code=$?
		if [[ -n "$output_var" ]]; then
			printf -v "$output_var" '%s' "$out"
		fi
		return "$exit_code"
	fi

	if [[ -x "$keepalive_script" ]]; then
		"$keepalive_script" start 2>/dev/null || true
		return 0
	fi

	return 1
}
