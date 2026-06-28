#!/bin/bash
# SSH ControlMaster helpers for scripts/manage/*.sh
#
# Shared: terminal colors, colored logging, ControlMaster setup/teardown,
# credential collection, and host-list config parsing.
#
# Globals read by SSH helpers (set by caller before use):
#   SSH_USERNAME, SSH_PASSWORD, SSH_PORT, SSH_TIMEOUT, BIND_IP
#   CONTROL_SOCKET (set by setup_ssh_control_master)
#   SSH_CONTROL_HOST (set by setup_ssh_control_master)
#
# Optional:
#   MANAGE_SSH_VERBOSE=1 — verbose auth messages in setup_ssh_control_master
#
# Caller may override manage_log_info / manage_log_success / manage_log_warn /
# manage_log_error / manage_log_verbose after sourcing to add file logging.

[[ -n "${MANAGE_SSH_CONTROL_SOURCED:-}" ]] && return 0
MANAGE_SSH_CONTROL_SOURCED=1

# Initialize ANSI color globals when stdout is a terminal.
#
# Returns:
#   0: Always
manage_init_terminal_colors() {
	if [[ -t 1 ]]; then
		if [[ -z "${RED:-}" ]]; then RED='\033[0;31m'; fi
		if [[ -z "${GREEN:-}" ]]; then GREEN='\033[0;32m'; fi
		if [[ -z "${YELLOW:-}" ]]; then YELLOW='\033[1;33m'; fi
		if [[ -z "${BLUE:-}" ]]; then BLUE='\033[0;34m'; fi
		if [[ -z "${NC:-}" ]]; then NC='\033[0m'; fi
	else
		if [[ -z "${RED:-}" ]]; then RED=''; fi
		if [[ -z "${GREEN:-}" ]]; then GREEN=''; fi
		if [[ -z "${YELLOW:-}" ]]; then YELLOW=''; fi
		if [[ -z "${BLUE:-}" ]]; then BLUE=''; fi
		if [[ -z "${NC:-}" ]]; then NC=''; fi
	fi
}

# Default colored log helpers (stderr). Override after sourcing to add file logging.
manage_log_info() { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
manage_log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*" >&2; }
manage_log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
manage_log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
manage_log_verbose() {
	if [[ "${MANAGE_SSH_VERBOSE:-0}" -eq 1 ]]; then
		manage_log_info "$@"
	fi
}

# Common SSH options for ControlMaster setup and multiplexed ssh/scp calls.
#
# Returns:
#   0: Always (prints options on stdout)
build_ssh_opts() {
	local opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=${SSH_TIMEOUT:-30}"
	[[ -n "${BIND_IP:-}" ]] && opts="$opts -o BindAddress=$BIND_IP"
	[[ -n "${CONTROL_SOCKET:-}" ]] && opts="$opts -o ControlPath=$CONTROL_SOCKET"
	echo "$opts"
}

# Resolve target host from argument or caller globals.
#
# Arguments:
#   $1: target_host (optional) — explicit host; else SSH_TARGET_HOST, TARGET_IP, TARGET_HOST
#
# Returns:
#   0: Host resolved (printed on stdout)
#   1: No host available
_manage_ssh_resolve_host() {
	local explicit="${1:-}"
	if [[ -n "$explicit" ]]; then
		echo "$explicit"
		return 0
	fi
	if [[ -n "${SSH_TARGET_HOST:-}" ]]; then
		echo "$SSH_TARGET_HOST"
		return 0
	fi
	if [[ -n "${TARGET_IP:-}" ]]; then
		echo "$TARGET_IP"
		return 0
	fi
	if [[ -n "${TARGET_HOST:-}" ]]; then
		echo "$TARGET_HOST"
		return 0
	fi
	return 1
}

# Establish an SSH ControlMaster (authenticate once; multiplex subsequent ssh/scp).
#
# Arguments:
#   $1: target_host (optional) — host/IP; falls back to caller globals
#
# Returns:
#   0: ControlMaster established
#   1: Failed to connect
#
# Side effects:
#   Sets CONTROL_SOCKET, SSH_CONTROL_HOST; registers EXIT trap for cleanup.
setup_ssh_control_master() {
	local target_ip
	if ! target_ip="$(_manage_ssh_resolve_host "${1:-}")"; then
		manage_log_error "SSH target host is required"
		return 1
	fi
	SSH_CONTROL_HOST="$target_ip"

	local sock_dir auth_rc=0
	sock_dir=$(mktemp -d /tmp/ssh-manage-XXXXXX)
	chmod 700 "$sock_dir"
	CONTROL_SOCKET="${sock_dir}/ctrl.sock"
	rm -f "$CONTROL_SOCKET" 2>/dev/null || true
	# shellcheck disable=SC2064
	trap "cleanup_ssh_control_master" EXIT

	local master_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=${SSH_TIMEOUT:-30}"
	master_opts="$master_opts -o ControlMaster=yes -o ControlPath=$CONTROL_SOCKET -o ControlPersist=60"
	[[ -n "${BIND_IP:-}" ]] && master_opts="$master_opts -o BindAddress=$BIND_IP"

	manage_log_info "Establishing SSH connection to ${target_ip}..."

	if command -v sshpass >/dev/null 2>&1 && [[ -n "${SSH_PASSWORD:-}" ]]; then
		manage_log_verbose "Using sshpass for ControlMaster authentication"
		# shellcheck disable=SC2086
		SSHPASS="$SSH_PASSWORD" sshpass -e ssh \
			$master_opts -p "${SSH_PORT:-22}" "${SSH_USERNAME}@${target_ip}" true || auth_rc=$?
	elif command -v expect >/dev/null 2>&1 && [[ -n "${SSH_PASSWORD:-}" ]]; then
		manage_log_verbose "Using expect for ControlMaster authentication"
		DEPLOY_PASSWORD="$SSH_PASSWORD" DEPLOY_TIMEOUT="${SSH_TIMEOUT:-30}" \
			DEPLOY_MASTER_OPTS="$master_opts" DEPLOY_PORT="${SSH_PORT:-22}" \
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
		ssh $master_opts -p "${SSH_PORT:-22}" "${SSH_USERNAME}@${target_ip}" \
			true </dev/tty 2>/dev/tty || auth_rc=$?
	fi

	if [[ $auth_rc -eq 0 ]] && ssh -o ControlPath="$CONTROL_SOCKET" -O check "${SSH_USERNAME}@${target_ip}" 2>/dev/null; then
		manage_log_success "SSH connection established (ControlMaster)"
		return 0
	fi

	manage_log_error "Failed to establish ControlMaster connection"
	if [[ $auth_rc -ne 0 ]]; then
		manage_log_error "SSH authentication exited with code $auth_rc"
	fi
	rm -f "$CONTROL_SOCKET" 2>/dev/null || true
	[[ -n "$sock_dir" ]] && [[ "$sock_dir" == /tmp/ssh-manage-* ]] && rmdir "$sock_dir" 2>/dev/null || true
	CONTROL_SOCKET=""
	SSH_CONTROL_HOST=""
	return 1
}

# Tear down ControlMaster socket and temp directory (safe inside EXIT trap).
#
# Returns:
#   0: Always
cleanup_ssh_control_master() {
	set +e
	if [[ -n "${CONTROL_SOCKET:-}" ]]; then
		local cleanup_host="${SSH_CONTROL_HOST:-}"
		[[ -z "$cleanup_host" ]] && cleanup_host="${TARGET_IP:-${TARGET_HOST:-}}"
		if [[ -e "$CONTROL_SOCKET" ]] && [[ -n "$cleanup_host" ]]; then
			ssh -o ControlPath="$CONTROL_SOCKET" -O exit "${SSH_USERNAME}@${cleanup_host}" 2>/dev/null
		fi
		local sock_dir
		sock_dir="$(dirname "$CONTROL_SOCKET" 2>/dev/null)"
		rm -f "$CONTROL_SOCKET" 2>/dev/null
		[[ -n "$sock_dir" ]] && [[ "$sock_dir" == /tmp/ssh-manage-* ]] && rmdir "$sock_dir" 2>/dev/null
	fi
	set -e
}

# Tear down SSH state between batch hosts (socket, trap, per-host overrides).
#
# Returns:
#   0: Always
reset_ssh_between_hosts() {
	cleanup_ssh_control_master
	trap - EXIT 2>/dev/null || true
	CONTROL_SOCKET=""
	SSH_CONTROL_HOST=""
	SSH_PASSWORD=""
	TARGET_HOST=""
	TARGET_IP=""
}

# Run ssh over an established ControlMaster.
#
# Arguments:
#   $1: target_host
#   $2: remote_cmd
#   $3: interactive — optional; non-empty adds -t
#
# Returns:
#   Exit code of ssh
execute_ssh_control() {
	local target_ip="$1"
	local cmd="$2"
	local interactive="${3:-}"
	local ssh_opts
	ssh_opts="$(build_ssh_opts)"
	[[ -n "$interactive" ]] && ssh_opts="$ssh_opts -t"
	# shellcheck disable=SC2086
	ssh $ssh_opts -p "${SSH_PORT:-22}" "${SSH_USERNAME}@${target_ip}" "$cmd"
}

# Run scp over an established ControlMaster.
#
# Arguments:
#   $1: target_host
#   $2: src_file
#   $3: dest_path (remote path, without user@host prefix)
#
# Returns:
#   Exit code of scp
execute_scp_control() {
	local target_ip="$1"
	local src_file="$2"
	local dest_path="$3"
	local scp_opts
	scp_opts="$(build_ssh_opts)"
	# shellcheck disable=SC2086
	scp $scp_opts -P "${SSH_PORT:-22}" "$src_file" "${SSH_USERNAME}@${target_ip}:${dest_path}"
}

# Collect SSH username/password when sshpass or expect can feed the password.
#
# Arguments:
#   $1: target_host
#
# Returns:
#   0: Credentials ready (or manual /dev/tty auth will be used)
#   1: Non-interactive use without password and without sshpass/expect
collect_ssh_credentials_if_needed() {
	local target_ip="$1"

	if [[ -z "${SSH_PASSWORD:-}" ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
		read -rp "Username for ${target_ip} [${SSH_USERNAME}]: " read_user
		if [[ -n "$read_user" ]]; then
			SSH_USERNAME="$read_user"
		fi
	fi

	local has_sshpass=0 has_expect=0
	command -v sshpass >/dev/null 2>&1 && has_sshpass=1
	command -v expect >/dev/null 2>&1 && has_expect=1

	if [[ -z "${SSH_PASSWORD:-}" ]]; then
		if [[ $has_sshpass -eq 1 ]] || [[ $has_expect -eq 1 ]]; then
			if [[ -t 0 ]] && [[ -t 1 ]]; then
				read -rsp "Password for ${SSH_USERNAME}@${target_ip}: " SSH_PASSWORD
				echo ""
			else
				SSH_PASSWORD=$(head -n 1 2>/dev/null || echo "")
			fi
			if [[ -z "$SSH_PASSWORD" ]]; then
				manage_log_error "Password is required. Run interactively or pipe password via stdin."
				return 1
			fi
		else
			if [[ ! -e /dev/tty ]]; then
				manage_log_error "No sshpass or expect installed, and no controlling terminal."
				manage_log_error "Install sshpass (apt-get install sshpass) for non-interactive use."
				return 1
			fi
			manage_log_verbose "No sshpass/expect: SSH will prompt for password during connection setup."
		fi
	fi
	return 0
}

# Read host lines from a manage config file (comments and blank lines stripped).
#
# Arguments:
#   $1: config_file
#   $2: array_name — nameref to populate
#
# Returns:
#   0: Always
read_manage_host_config() {
	local config_file="$1"
	local -n hosts_ref="$2"
	hosts_ref=()
	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line%%#*}"
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"
		[[ -z "$line" ]] && continue
		hosts_ref+=("$line")
	done <"$config_file"
}
