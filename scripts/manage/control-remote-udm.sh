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

if [[ -t 1 ]]; then
	[[ -z "${RED:-}" ]] && RED='\033[0;31m'
	[[ -z "${GREEN:-}" ]] && GREEN='\033[0;32m'
	[[ -z "${YELLOW:-}" ]] && YELLOW='\033[1;33m'
	[[ -z "${BLUE:-}" ]] && BLUE='\033[0;34m'
	[[ -z "${NC:-}" ]] && NC='\033[0m'
else
	[[ -z "${RED:-}" ]] && RED=''
	[[ -z "${GREEN:-}" ]] && GREEN=''
	[[ -z "${YELLOW:-}" ]] && YELLOW=''
	[[ -z "${BLUE:-}" ]] && BLUE=''
	[[ -z "${NC:-}" ]] && NC=''
fi

log_info() { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

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

build_ssh_opts() {
	local opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=$SSH_TIMEOUT"
	[[ -n "$BIND_IP" ]] && opts="$opts -o BindAddress=$BIND_IP"
	[[ -n "$CONTROL_SOCKET" ]] && opts="$opts -o ControlPath=$CONTROL_SOCKET"
	echo "$opts"
}

setup_control_master() {
	local target_ip="$1"
	local sock_dir auth_rc=0
	sock_dir=$(mktemp -d /tmp/ssh-control-XXXXXX)
	chmod 700 "$sock_dir"
	CONTROL_SOCKET="${sock_dir}/ctrl.sock"
	rm -f "$CONTROL_SOCKET" 2>/dev/null || true
	trap cleanup_control_master EXIT

	local master_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=$SSH_TIMEOUT"
	master_opts="$master_opts -o ControlMaster=yes -o ControlPath=$CONTROL_SOCKET -o ControlPersist=60"
	[[ -n "$BIND_IP" ]] && master_opts="$master_opts -o BindAddress=$BIND_IP"

	log_info "Connecting to ${target_ip}..."

	if command -v sshpass >/dev/null 2>&1 && [[ -n "$SSH_PASSWORD" ]]; then
		# shellcheck disable=SC2086
		SSHPASS="$SSH_PASSWORD" sshpass -e ssh \
			$master_opts -p "$SSH_PORT" "${SSH_USERNAME}@${target_ip}" true || auth_rc=$?
	elif command -v expect >/dev/null 2>&1 && [[ -n "$SSH_PASSWORD" ]]; then
		DEPLOY_PASSWORD="$SSH_PASSWORD" DEPLOY_TIMEOUT="$SSH_TIMEOUT" \
			DEPLOY_MASTER_OPTS="$master_opts" DEPLOY_PORT="$SSH_PORT" \
			DEPLOY_USER="$SSH_USERNAME" DEPLOY_HOST="$target_ip" \
			expect <<'EXPECT_EOF' || auth_rc=$?
set timeout $env(DEPLOY_TIMEOUT)
spawn ssh {*}$env(DEPLOY_MASTER_OPTS) -p $env(DEPLOY_PORT) $env(DEPLOY_USER)@$env(DEPLOY_HOST) true
expect {
	"assword:" { send "$env(DEPLOY_PASSWORD)\r"; exp_continue }
	"yes/no" { send "yes\r"; exp_continue }
	eof
}
lassign [wait] pid spawnid os_error value
exit $value
EXPECT_EOF
	else
		# shellcheck disable=SC2086
		ssh $master_opts -p "$SSH_PORT" "${SSH_USERNAME}@${target_ip}" \
			true </dev/tty 2>/dev/tty || auth_rc=$?
	fi

	if [[ $auth_rc -eq 0 ]] && ssh -o ControlPath="$CONTROL_SOCKET" -O check "${SSH_USERNAME}@${target_ip}" 2>/dev/null; then
		return 0
	fi
	log_error "Failed to connect to ${target_ip}"
	rm -f "$CONTROL_SOCKET" 2>/dev/null || true
	[[ -n "$sock_dir" ]] && [[ "$sock_dir" == /tmp/ssh-control-* ]] && rmdir "$sock_dir" 2>/dev/null || true
	CONTROL_SOCKET=""
	return 1
}

cleanup_control_master() {
	set +e
	if [[ -n "${CONTROL_SOCKET:-}" ]]; then
		if [[ -e "$CONTROL_SOCKET" ]] && [[ -n "${TARGET_HOST:-}" ]]; then
			ssh -o ControlPath="$CONTROL_SOCKET" -O exit "${SSH_USERNAME}@${TARGET_HOST}" 2>/dev/null
		fi
		local sock_dir
		sock_dir="$(dirname "$CONTROL_SOCKET" 2>/dev/null)"
		rm -f "$CONTROL_SOCKET" 2>/dev/null
		[[ -n "$sock_dir" ]] && [[ "$sock_dir" == /tmp/ssh-control-* ]] && rmdir "$sock_dir" 2>/dev/null
	fi
	set -e
}

# Tear down SSH state between batch hosts (socket, trap, per-host overrides).
#
# Returns:
#   0: Always
reset_ssh_between_hosts() {
	cleanup_control_master
	trap - EXIT 2>/dev/null || true
	CONTROL_SOCKET=""
	SSH_PASSWORD=""
	TARGET_HOST=""
}

execute_remote_ssh() {
	local target_ip="$1"
	local cmd="$2"
	local ssh_opts
	ssh_opts="$(build_ssh_opts)"
	# shellcheck disable=SC2086
	ssh $ssh_opts -p "$SSH_PORT" "${SSH_USERNAME}@${target_ip}" "$cmd"
}

collect_password_if_needed() {
	local target_ip="$1"
	if [[ -n "$SSH_PASSWORD" ]]; then
		return 0
	fi
	if [[ -t 0 ]] && [[ -t 1 ]]; then
		read -rp "Username for ${target_ip} [${SSH_USERNAME}]: " read_user
		[[ -n "$read_user" ]] && SSH_USERNAME="$read_user"
	fi
	if command -v sshpass >/dev/null 2>&1 || command -v expect >/dev/null 2>&1; then
		if [[ -t 0 ]] && [[ -t 1 ]]; then
			read -rsp "Password for ${SSH_USERNAME}@${target_ip}: " SSH_PASSWORD
			echo ""
		else
			SSH_PASSWORD=$(head -n 1 2>/dev/null || echo "")
		fi
		[[ -n "$SSH_PASSWORD" ]] || {
			log_error "Password required for non-interactive SSH"
			return 1
		}
	fi
	return 0
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

	collect_password_if_needed "$host" || return 1

	if ! setup_control_master "$host"; then
		return 1
	fi

	if execute_remote_ssh "$host" "$remote_cmd"; then
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
	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line%%#*}"
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"
		[[ -z "$line" ]] && continue
		hosts+=("$line")
	done <"$CONFIG_FILE"

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
