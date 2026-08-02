#!/bin/bash
#
# Pull VPN Monitor config from UDM devices to a controller working tree.
#
# Usage:
#   ./manage/pull-config-from-udms.sh [OPTIONS]
#
# Workflow:
#   pull → edit configs/<host>/vpn-monitor.conf locally → push-config-to-udms.sh
#
# Examples:
#   ./manage/pull-config-from-udms.sh --config deploy-udms.conf
#   ./manage/pull-config-from-udms.sh --host 192.168.1.100
#   ./manage/pull-config-from-udms.sh --dry-run
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=lib/common.sh
if [[ -f "${REPO_ROOT}/lib/common.sh" ]]; then
	source "${REPO_ROOT}/lib/common.sh"
fi

# shellcheck source=manage/lib/ssh_control.sh
source "${SCRIPT_DIR}/lib/ssh_control.sh"
# shellcheck source=manage/lib/config_fleet_common.sh
source "${SCRIPT_DIR}/lib/config_fleet_common.sh"

manage_init_terminal_colors

CONFIG_FILE=""
CONFIG_EXPLICIT=0
CONFIG_DIR=""
CONFIG_DIR_EXPLICIT=0
TARGET_HOST=""
BIND_IP=""
SSH_USERNAME="root"
SSH_PASSWORD=""
SSH_PORT=22
SSH_TIMEOUT=30
CONTROL_SOCKET=""
DRY_RUN=0

STAT_TOTAL=0
STAT_OK=0
STAT_NOT_INSTALLED=0
STAT_NO_REMOTE_CONFIG=0
STAT_UNREACHABLE=0
STAT_FAIL_COUNT=0

log_info() { manage_log_info "$@"; }
log_warn() { manage_log_warn "$@"; }
log_error() { manage_log_error "$@"; }

display_help() {
	cat <<EOF
Usage: $0 [OPTIONS]

Pull live vpn-monitor.conf from UDM devices to the controller for local editing.

Local layout (default --config-dir ${REPO_ROOT}/configs):
  configs/<host>/vpn-monitor.conf     working copy (pull overwrites)

Options:
  --host HOST       Target UDM IP or hostname (single host mode)
  --config FILE     Fleet config file (default: deploy-udms.conf, else control-udms.conf)
  --config-dir DIR  Controller config root (default: ${REPO_ROOT}/configs)
  --bind-ip IP      Source IP for SSH BindAddress
  --username USER   SSH username (default: root)
  --port PORT       SSH port (default: 22)
  --timeout SEC     SSH timeout seconds (default: 30)
  --dry-run         Print planned SCP operations without transferring files
  --help            Show this help

Output columns (tab-separated):
  HOST  STATUS  LOCAL_PATH

STATUS values: ok, not_installed, no_remote_config, unreachable, error, dry-run

Note: Pull overwrites the local working copy. Edit pulled files, then use
push-config-to-udms.sh to install changes (with timestamped backups).

Examples:
  $0 --config deploy-udms.conf
  $0 --host 192.168.1.100
  $0 --dry-run --config control-udms.conf
EOF
}

# Build remote probe command before SCP pull.
build_remote_pull_probe_command() {
	cat <<EOF
MONITOR='${REMOTE_MONITOR_SCRIPT}'; CONF='${REMOTE_CONFIG_FILE}'; if [[ ! -f "\$MONITOR" ]]; then echo '__PULL_STATUS__=not_installed'; elif [[ ! -f "\$CONF" ]]; then echo '__PULL_STATUS__=no_remote_config'; else echo '__PULL_STATUS__=ok'; fi
EOF
}

# Print one tab-separated pull row to stdout.
print_pull_row() {
	printf '%s\t%s\t%s\n' "$1" "$2" "$3"
}

# Pull config from one host; print dry-run line and table row to stdout.
#
# Arguments:
#   $1: target host
collect_pull_on_host() {
	local host="$1"
	local remote_cmd probe_output bind_label=""
	local local_path pull_temp status_line

	local_path=$(host_working_config_path "$host")
	[[ -n "${BIND_IP:-}" ]] && bind_label=" bind=${BIND_IP}"
	remote_cmd=$(build_remote_pull_probe_command)

	if [[ $DRY_RUN -eq 1 ]]; then
		echo "[dry-run] ${host}${bind_label}: probe then scp ${REMOTE_CONFIG_FILE} -> ${local_path}"
		print_pull_row "$host" "dry-run" "$local_path"
		return 0
	fi

	collect_ssh_credentials_if_needed "$host" || {
		print_pull_row "$host" "unreachable" "-"
		return 1
	}

	if ! setup_ssh_control_master "$host"; then
		print_pull_row "$host" "unreachable" "-"
		return 1
	fi

	if ! execute_ssh_control_logged "$host" "$remote_cmd" "remote probe"; then
		print_pull_row "$host" "error" "-"
		return 1
	fi
	probe_output="$MANAGE_SSH_CAPTURED_OUTPUT"

	status_line=$(echo "$probe_output" | head -1)
	case "$status_line" in
	__PULL_STATUS__=not_installed)
		print_pull_row "$host" "not_installed" "-"
		return 1
		;;
	__PULL_STATUS__=no_remote_config)
		print_pull_row "$host" "no_remote_config" "-"
		return 1
		;;
	__PULL_STATUS__=ok)
		pull_temp=$(mktemp "${TMPDIR:-/tmp}/vpn-monitor-pull.XXXXXX")
		if ! execute_scp_pull_control_logged "$host" "$REMOTE_CONFIG_FILE" "$pull_temp" "config download"; then
			rm -f "$pull_temp"
			print_pull_row "$host" "error" "-"
			return 1
		fi
		if ! atomic_write_local_file "$local_path" "$pull_temp"; then
			rm -f "$pull_temp"
			log_error "${host}: failed to write local config ${local_path}"
			print_pull_row "$host" "error" "-"
			return 1
		fi
		rm -f "$pull_temp"
		print_pull_row "$host" "ok" "$local_path"
		return 0
		;;
	*)
		log_error "${host}: unexpected probe response: ${status_line}"
		print_pull_row "$host" "error" "-"
		return 1
		;;
	esac
}

# Update summary counters after processing one host row.
update_summary_counts() {
	local status_col="$1"
	local host_ok="$2"

	STAT_TOTAL=$((STAT_TOTAL + 1))
	if [[ $host_ok -ne 0 ]]; then
		STAT_FAIL_COUNT=$((STAT_FAIL_COUNT + 1))
		case "$status_col" in
		unreachable | error)
			STAT_UNREACHABLE=$((STAT_UNREACHABLE + 1))
			;;
		not_installed)
			STAT_NOT_INSTALLED=$((STAT_NOT_INSTALLED + 1))
			;;
		no_remote_config)
			STAT_NO_REMOTE_CONFIG=$((STAT_NO_REMOTE_CONFIG + 1))
			;;
		esac
		return 0
	fi

	case "$status_col" in
	ok)
		STAT_OK=$((STAT_OK + 1))
		;;
	esac
}

print_summary() {
	log_info "Summary: ${STAT_TOTAL} host(s), ${STAT_OK} pulled, ${STAT_NOT_INSTALLED} not installed, ${STAT_NO_REMOTE_CONFIG} no remote config, ${STAT_UNREACHABLE} unreachable/error"
	if [[ $STAT_FAIL_COUNT -gt 0 ]]; then
		log_warn "${STAT_FAIL_COUNT} host(s) failed"
	fi
}

process_host() {
	local host="$1"
	local output row status_col host_ok=0

	if ! output=$(collect_pull_on_host "$host"); then
		host_ok=1
	fi

	echo "$output"

	row=$(echo "$output" | awk -F'\t' 'NF >= 3 {line=$0} END {print line}')
	if [[ -n "$row" ]]; then
		status_col=$(echo "$row" | cut -f2)
		update_summary_counts "$status_col" "$host_ok"
	fi
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--host | --config | --config-dir | --bind-ip | --username | --port | --timeout)
			parse_config_fleet_common_option "$1" "$2"
			shift 2
			;;
		--dry-run)
			parse_config_fleet_common_option "$1"
			shift
			;;
		--help | -h)
			display_help
			exit 0
			;;
		*)
			log_error "Unknown option: $1"
			display_help
			exit 1
			;;
		esac
	done
}

main() {
	parse_args "$@"
	resolve_config_dir

	local -a hosts=()

	echo -e "HOST\tSTATUS\tLOCAL_PATH"

	if [[ -n "$TARGET_HOST" ]]; then
		process_host "$TARGET_HOST"
		echo ""
		config_fleet_finish
		return
	fi

	config_fleet_load_hosts hosts || exit 1

	log_info "Pull config for ${#hosts[@]} host(s) from ${CONFIG_FILE} into ${CONFIG_DIR}"
	echo ""

	run_config_fleet_hosts
	config_fleet_finish
}

main "$@"
