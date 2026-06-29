#!/bin/bash
#
# Push VPN Monitor config from controller working tree to UDM devices.
#
# Usage:
#   ./scripts/manage/push-config-to-udms.sh [OPTIONS]
#
# Workflow:
#   pull-config-from-udms.sh → edit configs/<host>/vpn-monitor.conf → push
#
# Examples:
#   ./scripts/manage/push-config-to-udms.sh --host 192.168.1.100
#   ./scripts/manage/push-config-to-udms.sh --config deploy-udms.conf
#   ./scripts/manage/push-config-to-udms.sh --host 192.168.1.100 --file ./my.conf --dry-run
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=lib/common.sh
if [[ -f "${REPO_ROOT}/lib/common.sh" ]]; then
	source "${REPO_ROOT}/lib/common.sh"
fi

# shellcheck source=scripts/manage/lib/ssh_control.sh
source "${SCRIPT_DIR}/lib/ssh_control.sh"
# shellcheck source=scripts/manage/lib/config_fleet_common.sh
source "${SCRIPT_DIR}/lib/config_fleet_common.sh"

manage_init_terminal_colors

CONFIG_FILE=""
CONFIG_EXPLICIT=0
CONFIG_DIR=""
CONFIG_DIR_EXPLICIT=0
LOCAL_FILE=""
LOCAL_FILE_EXPLICIT=0
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
STAT_MISSING_LOCAL=0
STAT_NOT_INSTALLED=0
STAT_UNREACHABLE=0
STAT_VALIDATION_FAILED=0
STAT_FAIL_COUNT=0

log_info() { manage_log_info "$@"; }
log_warn() { manage_log_warn "$@"; }
log_error() { manage_log_error "$@"; }

display_help() {
	cat <<EOF
Usage: $0 [OPTIONS]

Push edited vpn-monitor.conf from the controller to UDM devices.

Local layout (default --config-dir ${REPO_ROOT}/configs):
  configs/<host>/vpn-monitor.conf           working copy to push
  configs/backups/<host>/vpn-monitor.conf.<timestamp>   controller snapshot before push

Remote backups (on each UDM before overwrite):
  /data/vpn-monitor/backups/vpn-monitor.conf.<timestamp>

Push runs check-config.sh on the staged file before replacing live config.
Changes apply on the next cron cycle; this script does not restart IPsec.

Rollback: restore from remote or controller backup file, then push again.

Options:
  --host HOST       Target UDM IP or hostname (single host mode)
  --file PATH       Local config to push (requires --host; per-site values differ by UDM)
  --config FILE     Fleet config file (default: deploy-udms.conf, else control-udms.conf)
  --config-dir DIR  Controller config root (default: ${REPO_ROOT}/configs)
  --bind-ip IP      Source IP for SSH BindAddress
  --username USER   SSH username (default: root)
  --port PORT       SSH port (default: 22)
  --timeout SEC     SSH timeout seconds (default: 30)
  --dry-run         Print planned operations without modifying remote or local files
  --help            Show this help

Output columns (tab-separated):
  HOST  STATUS  REMOTE_BACKUP  CONTROLLER_BACKUP

STATUS values: ok, missing_local, not_installed, validation_failed, unreachable, error, dry-run

Fleet batch mode uses configs/<host>/vpn-monitor.conf for each host. --file is only allowed
with --host so one shared file cannot overwrite every UDM's site-specific settings.

Examples:
  $0 --host 192.168.1.100
  $0 --config deploy-udms.conf
  $0 --host 192.168.1.100 --file configs/192.168.1.100/vpn-monitor.conf --dry-run
EOF
}

# Resolve local source file for a host push.
#
# Arguments:
#   $1: host
#
# Side effects:
#   Sets RESOLVED_LOCAL_FILE
resolve_local_source_file() {
	local host="$1"
	if [[ $LOCAL_FILE_EXPLICIT -eq 1 ]]; then
		RESOLVED_LOCAL_FILE="$LOCAL_FILE"
	else
		RESOLVED_LOCAL_FILE=$(host_working_config_path "$host")
	fi
}

# Build remote command to backup live config when present.
#
# Arguments:
#   $1: timestamp
build_remote_backup_command() {
	local ts="$1"
	cat <<EOF
CONF='${REMOTE_CONFIG_FILE}'; BACKUP_DIR='${REMOTE_BACKUP_DIR}'; TS='${ts}'; if [[ -f "\$CONF" ]]; then mkdir -p "\$BACKUP_DIR" && cp "\$CONF" "\$BACKUP_DIR/vpn-monitor.conf.\$TS"; echo '__PUSH_BACKUP__=ok'; else echo '__PUSH_BACKUP__=none'; fi
EOF
}

# Build remote command to validate staged config.
build_remote_validate_command() {
	cat <<EOF
CHECK='${REMOTE_CHECK_SCRIPT}'; STAGED='${REMOTE_CONFIG_TMP}'; if [[ ! -x "\$CHECK" ]]; then echo '__PUSH_VALIDATE__=no_checker'; exit 1; fi; if "\$CHECK" --config "\$STAGED"; then echo '__PUSH_VALIDATE__=ok'; else echo '__PUSH_VALIDATE__=failed'; exit 1; fi
EOF
}

# Build remote command to commit staged config.
build_remote_commit_command() {
	cat <<EOF
STAGED='${REMOTE_CONFIG_TMP}'; LIVE='${REMOTE_CONFIG_FILE}'; mv "\$STAGED" "\$LIVE"
EOF
}

# Build remote command to remove staged config after validation failure.
build_remote_cleanup_staged_command() {
	cat <<EOF
rm -f '${REMOTE_CONFIG_TMP}'
EOF
}

# Build remote probe for monitor install presence.
build_remote_push_probe_command() {
	cat <<EOF
MONITOR='${REMOTE_MONITOR_SCRIPT}'; CHECK='${REMOTE_CHECK_SCRIPT}'; if [[ ! -f "\$MONITOR" ]] || [[ ! -x "\$CHECK" ]]; then echo '__PUSH_STATUS__=not_installed'; else echo '__PUSH_STATUS__=ok'; fi
EOF
}

print_push_row() {
	printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
}

# Push config to one host.
#
# Arguments:
#   $1: target host
collect_push_on_host() {
	local host="$1"
	local bind_label="" ts remote_backup remote_ctrl_backup="-"
	local remote_cmd probe_output status_line validate_cmd commit_cmd

	resolve_local_source_file "$host"
	ts=$(config_timestamp_utc)
	remote_backup="${REMOTE_BACKUP_DIR}/vpn-monitor.conf.${ts}"
	[[ -n "${BIND_IP:-}" ]] && bind_label=" bind=${BIND_IP}"

	if [[ ! -f "$RESOLVED_LOCAL_FILE" ]]; then
		print_push_row "$host" "missing_local" "-" "-"
		return 1
	fi

	if [[ $DRY_RUN -eq 1 ]]; then
		echo "[dry-run] ${host}${bind_label}: backup remote -> ${remote_backup}"
		echo "[dry-run] ${host}${bind_label}: backup controller -> $(host_controller_backup_path "$host" "$ts")"
		echo "[dry-run] ${host}${bind_label}: scp ${RESOLVED_LOCAL_FILE} -> ${REMOTE_CONFIG_TMP}"
		echo "[dry-run] ${host}${bind_label}: ${REMOTE_CHECK_SCRIPT} --config ${REMOTE_CONFIG_TMP}"
		echo "[dry-run] ${host}${bind_label}: mv ${REMOTE_CONFIG_TMP} ${REMOTE_CONFIG_FILE}"
		print_push_row "$host" "dry-run" "$remote_backup" "$(host_controller_backup_path "$host" "$ts")"
		return 0
	fi

	collect_ssh_credentials_if_needed "$host" || {
		print_push_row "$host" "unreachable" "-" "-"
		return 1
	}

	if ! setup_ssh_control_master "$host"; then
		print_push_row "$host" "unreachable" "-" "-"
		return 1
	fi

	remote_cmd=$(build_remote_push_probe_command)
	if ! execute_ssh_control_logged "$host" "$remote_cmd" "remote probe"; then
		print_push_row "$host" "error" "-" "-"
		return 1
	fi
	probe_output="$MANAGE_SSH_CAPTURED_OUTPUT"

	status_line=$(echo "$probe_output" | head -1)
	if [[ "$status_line" != "__PUSH_STATUS__=ok" ]]; then
		print_push_row "$host" "not_installed" "-" "-"
		return 1
	fi

	# Controller backup when remote live config exists.
	if execute_ssh_control "$host" "test -f '${REMOTE_CONFIG_FILE}'" 2>/dev/null; then
		remote_ctrl_backup=$(host_controller_backup_path "$host" "$ts")
		mkdir -p "$(dirname "$remote_ctrl_backup")"
		if ! execute_scp_pull_control_logged "$host" "$REMOTE_CONFIG_FILE" "${remote_ctrl_backup}.tmp" "controller backup download"; then
			rm -f "${remote_ctrl_backup}.tmp"
			print_push_row "$host" "error" "-" "-"
			return 1
		fi
		if ! mv "${remote_ctrl_backup}.tmp" "$remote_ctrl_backup"; then
			log_error "${host}: failed to save controller backup ${remote_ctrl_backup}"
			print_push_row "$host" "error" "-" "-"
			return 1
		fi
	else
		remote_ctrl_backup="-"
	fi

	if ! execute_ssh_control_logged "$host" "$(build_remote_backup_command "$ts")" "remote backup"; then
		print_push_row "$host" "error" "-" "${remote_ctrl_backup:--}"
		return 1
	fi

	if ! execute_scp_control_logged "$host" "$RESOLVED_LOCAL_FILE" "$REMOTE_CONFIG_TMP" "config upload"; then
		print_push_row "$host" "error" "${remote_backup}" "${remote_ctrl_backup:--}"
		return 1
	fi

	validate_cmd=$(build_remote_validate_command)
	if ! execute_ssh_control_logged "$host" "$validate_cmd" "remote validation"; then
		execute_ssh_control "$host" "$(build_remote_cleanup_staged_command)" 2>/dev/null || true
		print_push_row "$host" "validation_failed" "${remote_backup}" "${remote_ctrl_backup:--}"
		return 1
	fi

	commit_cmd=$(build_remote_commit_command)
	if ! execute_ssh_control_logged "$host" "$commit_cmd" "config commit"; then
		execute_ssh_control "$host" "$(build_remote_cleanup_staged_command)" 2>/dev/null || true
		print_push_row "$host" "error" "${remote_backup}" "${remote_ctrl_backup:--}"
		return 1
	fi

	print_push_row "$host" "ok" "${remote_backup}" "${remote_ctrl_backup:--}"
	return 0
}

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
		missing_local)
			STAT_MISSING_LOCAL=$((STAT_MISSING_LOCAL + 1))
			;;
		not_installed)
			STAT_NOT_INSTALLED=$((STAT_NOT_INSTALLED + 1))
			;;
		validation_failed)
			STAT_VALIDATION_FAILED=$((STAT_VALIDATION_FAILED + 1))
			;;
		esac
		return 0
	fi

	if [[ "$status_col" == "ok" ]]; then
		STAT_OK=$((STAT_OK + 1))
	fi
}

print_summary() {
	log_info "Summary: ${STAT_TOTAL} host(s), ${STAT_OK} pushed, ${STAT_MISSING_LOCAL} missing local file, ${STAT_NOT_INSTALLED} not installed, ${STAT_VALIDATION_FAILED} validation failed, ${STAT_UNREACHABLE} unreachable/error"
	if [[ $STAT_FAIL_COUNT -gt 0 ]]; then
		log_warn "${STAT_FAIL_COUNT} host(s) failed"
	fi
}

process_host() {
	local host="$1"
	local output row status_col host_ok=0

	if ! output=$(collect_push_on_host "$host"); then
		host_ok=1
	fi

	echo "$output"

	row=$(echo "$output" | awk -F'\t' 'NF >= 4 {line=$0} END {print line}')
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
		--file)
			LOCAL_FILE="$2"
			LOCAL_FILE_EXPLICIT=1
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

	if [[ $LOCAL_FILE_EXPLICIT -eq 1 && -z "$TARGET_HOST" ]]; then
		log_error "--file requires --host (fleet batch mode uses configs/<host>/vpn-monitor.conf per UDM)"
		exit 1
	fi

	resolve_config_dir

	local -a hosts=()

	echo -e "HOST\tSTATUS\tREMOTE_BACKUP\tCONTROLLER_BACKUP"

	if [[ -n "$TARGET_HOST" ]]; then
		process_host "$TARGET_HOST"
		echo ""
		config_fleet_finish
		return
	fi

	config_fleet_load_hosts hosts || exit 1

	log_info "Push config for ${#hosts[@]} host(s) from ${CONFIG_DIR} using ${CONFIG_FILE}"
	echo ""

	run_config_fleet_hosts
	config_fleet_finish
}

main "$@"
