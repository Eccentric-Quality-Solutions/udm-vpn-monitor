#!/bin/bash
# Shared fleet config pull/push helpers for manage/*-config-*-udms.sh
#
# Caller must set REPO_ROOT and source ssh_control.sh first.
# Caller defines: process_host(), print_summary(), log_* wrappers, and script-specific globals.

[[ -n "${CONFIG_FLEET_COMMON_SOURCED:-}" ]] && return 0
CONFIG_FLEET_COMMON_SOURCED=1

REMOTE_INSTALL_DIR="/data/vpn-monitor"
REMOTE_MONITOR_SCRIPT="${REMOTE_INSTALL_DIR}/vpn-monitor.sh"
REMOTE_CONFIG_FILE="${REMOTE_INSTALL_DIR}/vpn-monitor.conf"
REMOTE_CONFIG_TMP="${REMOTE_INSTALL_DIR}/vpn-monitor.conf.tmp"
REMOTE_CHECK_SCRIPT="${REMOTE_INSTALL_DIR}/check-config.sh"
REMOTE_BACKUP_DIR="${REMOTE_INSTALL_DIR}/backups"

# Resolve controller config root directory.
resolve_config_dir() {
	if [[ ${CONFIG_DIR_EXPLICIT:-0} -eq 1 ]]; then
		CONFIG_DIR="${CONFIG_DIR%/}"
		return 0
	fi
	CONFIG_DIR="${REPO_ROOT}/configs"
}

# Path to local working config for a host.
#
# Arguments:
#   $1: host
host_working_config_path() {
	local host="$1"
	echo "${CONFIG_DIR}/${host}/vpn-monitor.conf"
}

# Resolve fleet config path when --config was not passed explicitly.
#
# Returns:
#   0: CONFIG_FILE set
#   1: No config available
resolve_fleet_config() {
	if [[ ${CONFIG_EXPLICIT:-0} -eq 1 ]]; then
		if [[ ! -f "$CONFIG_FILE" ]]; then
			log_error "Config file not found: $CONFIG_FILE"
			return 1
		fi
		return 0
	fi

	if [[ -f "${REPO_ROOT}/deploy-udms.conf" ]]; then
		CONFIG_FILE="${REPO_ROOT}/deploy-udms.conf"
		return 0
	fi
	if [[ -f "${REPO_ROOT}/control-udms.conf" ]]; then
		CONFIG_FILE="${REPO_ROOT}/control-udms.conf"
		return 0
	fi

	log_error "No fleet config found. Create deploy-udms.conf or control-udms.conf, or pass --config FILE"
	return 1
}

# Load host list from fleet config into caller's hosts array (nameref).
#
# Arguments:
#   $1: nameref to hosts array
config_fleet_load_hosts() {
	local -n _fleet_hosts="$1"
	local array_name="$1"

	_fleet_hosts=()
	resolve_fleet_config || return 1
	read_manage_host_config "$CONFIG_FILE" "$array_name"
	if [[ ${#_fleet_hosts[@]} -eq 0 ]]; then
		log_error "No hosts in config: $CONFIG_FILE"
		return 1
	fi
	return 0
}

# Write local file atomically.
#
# Arguments:
#   $1: destination path
#   $2: source path
atomic_write_local_file() {
	local dest="$1"
	local src="$2"
	local dest_dir
	dest_dir=$(dirname "$dest")
	mkdir -p "$dest_dir"
	if ! (cp "$src" "${dest}.tmp" && mv "${dest}.tmp" "$dest"); then
		rm -f "${dest}.tmp"
		return 1
	fi
	return 0
}

# UTC timestamp for backup filenames.
config_timestamp_utc() {
	date -u +%Y-%m-%dT%H%M%SZ
}

# Controller backup path for a host at a given timestamp.
#
# Arguments:
#   $1: host
#   $2: timestamp
host_controller_backup_path() {
	local host="$1"
	local ts="$2"
	echo "${CONFIG_DIR}/backups/${host}/vpn-monitor.conf.${ts}"
}

# Parse one shared fleet CLI option; caller handles script-specific flags.
#
# Arguments:
#   $1: option name
#   $2: option value (when option takes an argument)
#
# Returns:
#   0: Option consumed (shift caller args accordingly)
#   1: Not a shared option
parse_config_fleet_common_option() {
	case "$1" in
	--host)
		TARGET_HOST="$2"
		return 0
		;;
	--config)
		CONFIG_FILE="$2"
		CONFIG_EXPLICIT=1
		return 0
		;;
	--config-dir)
		CONFIG_DIR="$2"
		CONFIG_DIR_EXPLICIT=1
		return 0
		;;
	--bind-ip)
		BIND_IP="$2"
		return 0
		;;
	--username)
		SSH_USERNAME="$2"
		return 0
		;;
	--port)
		SSH_PORT="$2"
		return 0
		;;
	--timeout)
		SSH_TIMEOUT="$2"
		return 0
		;;
	--dry-run)
		DRY_RUN=1
		return 0
		;;
	esac
	return 1
}

# Iterate fleet hosts with per-entry bind IP and SSH credential reuse.
#
# Side effects:
#   Calls process_host for each entry; uses hosts[] from caller scope.
run_config_fleet_hosts() {
	local default_bind_ip="${BIND_IP:-}"
	local entry host_ip host_bind

	local saved_password="${SSH_PASSWORD:-}"
	local first_host="${hosts[0]%% *}"
	if [[ ${DRY_RUN:-0} -eq 0 ]]; then
		collect_ssh_credentials_if_needed "$first_host" || exit 1
		saved_password="${SSH_PASSWORD:-}"
	fi

	for entry in "${hosts[@]}"; do
		host_ip="${entry%% *}"
		host_bind=""
		if [[ "$entry" == *" "* ]]; then
			host_bind="${entry#* }"
			host_bind="${host_bind%% *}"
		fi
		reset_ssh_between_hosts
		SSH_PASSWORD="$saved_password"
		if [[ -n "$host_bind" ]]; then
			BIND_IP="$host_bind"
		else
			BIND_IP="$default_bind_ip"
		fi
		process_host "$host_ip"
		echo ""
	done
	reset_ssh_between_hosts
}

# Exit according to dry-run and failure count after print_summary().
config_fleet_finish() {
	print_summary
	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		exit 0
	fi
	[[ ${STAT_FAIL_COUNT:-0} -eq 0 ]]
}
