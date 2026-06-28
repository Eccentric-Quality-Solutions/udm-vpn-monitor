#!/bin/bash
#
# Remote UDM VPN Monitor Control
# SSH to one or more UDMs and run vpn-monitor-control.sh
#
# Usage:
#   ./scripts/manage/control-remote-udm.sh [OPTIONS] COMMAND [ARGS]
#
# Commands: start | stop | pause | observe-only | status
# Options for pause: --until TIME [--reason TEXT]
#
# Examples:
#   ./scripts/manage/control-remote-udm.sh --host 192.168.1.100 status
#   ./scripts/manage/control-remote-udm.sh --host 192.168.1.100 pause --until +2h
#   ./scripts/manage/control-remote-udm.sh --config control-udms.conf stop
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
manage_init_terminal_colors

REMOTE_INSTALL_DIR="/data/vpn-monitor"
REMOTE_CONTROL_SCRIPT="${REMOTE_INSTALL_DIR}/vpn-monitor-control.sh"

CONFIG_FILE="${REPO_ROOT}/control-udms.conf"
TARGET_HOST=""
BIND_IP=""
SSH_USERNAME="root"
SSH_PASSWORD=""
SSH_PORT=22
SSH_TIMEOUT=30
CONTROL_SOCKET=""
REMOTE_COMMAND=""
REMOTE_ARGS=()
DRY_RUN=0

log_info() { manage_log_info "$@"; }
log_success() { manage_log_success "$@"; }
log_warn() { manage_log_warn "$@"; }
log_error() { manage_log_error "$@"; }

display_help() {
	cat <<EOF
Usage: $0 [OPTIONS] COMMAND [ARGS]

Remote control of VPN Monitor on UDM devices via SSH.

Options:
  --host HOST       Target UDM IP or hostname (single host mode)
  --config FILE     Batch config file (default: control-udms.conf)
  --bind-ip IP      Source IP for SSH BindAddress
  --username USER   SSH username (default: root)
  --port PORT       SSH port (default: 22)
  --timeout SEC     SSH timeout seconds (default: 30)
  --dry-run         Print remote commands without executing SSH
  --help            Show this help

Commands:
  start             Restore normal monitoring
  stop              Halt monitoring on target
  pause             Pause until time (--until required on target)
  observe-only      Log only, no recovery
  status            Show operating mode on target

Examples:
  $0 --host 192.168.1.100 status
  $0 --host 192.168.1.100 pause --until +30m --reason maintenance
  $0 --config control-udms.conf stop
EOF
}

# Build remote shell command string
#
# Output:
#   Remote command to run on target UDM
build_remote_command() {
	local remote_cmd args_quoted="" arg
	remote_cmd="if [[ ! -x '${REMOTE_CONTROL_SCRIPT}' ]]; then echo 'Control script not found: ${REMOTE_CONTROL_SCRIPT}' >&2; exit 1; fi; '${REMOTE_CONTROL_SCRIPT}' ${REMOTE_COMMAND}"
	for arg in "${REMOTE_ARGS[@]}"; do
		args_quoted="${args_quoted} $(printf '%q' "$arg")"
	done
	echo "${remote_cmd}${args_quoted}"
}

# Run control command on a single host (uses global BIND_IP when set).
#
# Arguments:
#   $1: target host
#
# Returns:
#   0: Success
#   1: Failure
run_on_host() {
	local host="$1"
	local remote_cmd bind_label=""

	TARGET_HOST="$host"
	[[ -n "${BIND_IP:-}" ]] && bind_label=" bind=${BIND_IP}"

	remote_cmd=$(build_remote_command)

	if [[ $DRY_RUN -eq 1 ]]; then
		echo "[dry-run] ${host}${bind_label}: ${remote_cmd}"
		log_success "${host}: ${REMOTE_COMMAND} (dry-run)"
		return 0
	fi

	collect_ssh_credentials_if_needed "$host" || return 1

	if ! setup_ssh_control_master "$host"; then
		return 1
	fi

	if execute_ssh_control "$host" "$remote_cmd"; then
		log_success "${host}: ${REMOTE_COMMAND} succeeded"
		return 0
	fi
	log_error "${host}: ${REMOTE_COMMAND} failed"
	return 1
}

parse_args() {
	local parsing_cmd=0
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--host)
			TARGET_HOST="$2"
			shift 2
			;;
		--config)
			CONFIG_FILE="$2"
			shift 2
			;;
		--bind-ip)
			BIND_IP="$2"
			shift 2
			;;
		--username)
			SSH_USERNAME="$2"
			shift 2
			;;
		--port)
			SSH_PORT="$2"
			shift 2
			;;
		--timeout)
			SSH_TIMEOUT="$2"
			shift 2
			;;
		--dry-run)
			DRY_RUN=1
			shift
			;;
		--help | -h)
			display_help
			exit 0
			;;
		start | stop | pause | observe-only | status)
			parsing_cmd=1
			REMOTE_COMMAND="$1"
			shift
			;;
		*)
			if [[ $parsing_cmd -eq 1 ]]; then
				REMOTE_ARGS+=("$1")
				shift
			else
				log_error "Unknown option: $1"
				display_help
				exit 1
			fi
			;;
		esac
	done

	[[ -n "$REMOTE_COMMAND" ]] || {
		log_error "COMMAND required (start|stop|pause|observe-only|status)"
		display_help
		exit 1
	}
}

main() {
	parse_args "$@"

	local success_count=0 fail_count=0
	local default_bind_ip="${BIND_IP:-}"

	if [[ -n "$TARGET_HOST" ]]; then
		if run_on_host "$TARGET_HOST"; then
			exit 0
		fi
		exit 1
	fi

	if [[ ! -f "$CONFIG_FILE" ]]; then
		log_error "Config file not found: $CONFIG_FILE (use --host or --config)"
		exit 1
	fi

	local -a hosts=()
	read_manage_host_config "$CONFIG_FILE" hosts

	if [[ ${#hosts[@]} -eq 0 ]]; then
		log_error "No hosts in config: $CONFIG_FILE"
		exit 1
	fi

	log_info "Remote control: ${REMOTE_COMMAND} on ${#hosts[@]} host(s)"
	echo ""

	local entry host_ip host_bind
	for entry in "${hosts[@]}"; do
		host_ip="${entry%% *}"
		host_bind=""
		if [[ "$entry" == *" "* ]]; then
			host_bind="${entry#* }"
			host_bind="${host_bind%% *}"
		fi
		reset_ssh_between_hosts
		if [[ -n "$host_bind" ]]; then
			BIND_IP="$host_bind"
		else
			BIND_IP="$default_bind_ip"
		fi
		if run_on_host "$host_ip"; then
			success_count=$((success_count + 1))
		else
			fail_count=$((fail_count + 1))
		fi
		echo ""
	done
	reset_ssh_between_hosts

	log_info "Summary: ${success_count} succeeded, ${fail_count} failed"
	[[ $fail_count -eq 0 ]]
}

main "$@"
