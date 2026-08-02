#!/bin/bash
#
# Remote UDM VPN Monitor Uninstall
# SSH to a UDM and run uninstall.sh without transferring a package.
#
# Usage:
#   ./manage/uninstall-from-udm.sh [OPTIONS]
#
# Examples:
#   ./manage/uninstall-from-udm.sh --host 192.168.1.100 --yes
#   ./manage/uninstall-from-udm.sh --host 192.168.1.100 --keep-config --update-registry
#   ./manage/uninstall-from-udm.sh --dry-run --host 192.168.1.100
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=lib/common.sh
if [[ -f "${REPO_ROOT}/lib/common.sh" ]]; then
	source "${REPO_ROOT}/lib/common.sh"
fi

# shellcheck source=manage/deploy-registry.sh
if [[ -f "${SCRIPT_DIR}/deploy-registry.sh" ]] && [[ -f "${REPO_ROOT}/lib/common.sh" ]]; then
	source "${SCRIPT_DIR}/deploy-registry.sh"
fi

# shellcheck source=manage/lib/ssh_control.sh
source "${SCRIPT_DIR}/lib/ssh_control.sh"
manage_init_terminal_colors

REMOTE_UNINSTALL_SCRIPT="/data/vpn-monitor/uninstall.sh"
LOGS_DIR="${REPO_ROOT}/logs"
UNINSTALL_LOG_FILE="${UNINSTALL_LOG_FILE:-${LOGS_DIR}/uninstall-from-udm.log}"

TARGET_HOST=""
BIND_IP=""
SSH_USERNAME="root"
SSH_PASSWORD=""
SSH_PORT=22
SSH_TIMEOUT=30
CONTROL_SOCKET=""
DRY_RUN=0
SKIP_CONFIRMATION=0
UPDATE_REGISTRY=0

# Defaults match deploy-to-udm.sh uninstall step
KEEP_CONFIG="yes"
REMOVE_STATE="yes"
REMOVE_LOGS="yes"
KEEP_CONFIG_EXPLICIT=0
REMOVE_CONFIG_EXPLICIT=0
KEEP_STATE_EXPLICIT=0
REMOVE_STATE_EXPLICIT=0
KEEP_LOGS_EXPLICIT=0
REMOVE_LOGS_EXPLICIT=0

# Append message to uninstall log file (sanitized: no username or password).
#
# Arguments:
#   $1: level - INFO, SUCCESS, WARN, ERROR
#   $2+: message parts (concatenated)
#
# Returns:
#   0: Always (write failures are ignored)
uninstall_log_write() {
	local level="$1"
	shift
	local msg="$*"
	[[ -n "${SSH_USERNAME:-}" ]] && msg="${msg//${SSH_USERNAME}/***}"
	[[ -n "${SSH_PASSWORD:-}" ]] && msg="${msg//${SSH_PASSWORD}/***}"
	mkdir -p "$(dirname "$UNINSTALL_LOG_FILE")" 2>/dev/null || true
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $msg" >>"$UNINSTALL_LOG_FILE" 2>/dev/null || true
}

manage_log_info() {
	echo -e "${BLUE}[INFO]${NC} $*" >&2
	uninstall_log_write "INFO" "$@"
}
manage_log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
	uninstall_log_write "SUCCESS" "$@"
}
manage_log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $*" >&2
	uninstall_log_write "WARN" "$@"
}
manage_log_error() {
	echo -e "${RED}[ERROR]${NC} $*" >&2
	uninstall_log_write "ERROR" "$@"
}

log_info() { manage_log_info "$@"; }
log_success() { manage_log_success "$@"; }
log_warn() { manage_log_warn "$@"; }
log_error() { manage_log_error "$@"; }

display_help() {
	cat <<EOF
Usage: $0 [OPTIONS]

Remove VPN Monitor from a remote UDM via SSH (no package transfer).

Options:
  --host HOST         Target UDM IP or hostname (required)
  --bind-ip IP        Source IP for SSH BindAddress
  --username USER     SSH username (default: root)
  --port PORT         SSH port (default: 22)
  --timeout SEC       SSH timeout seconds (default: 30)
  --keep-config       Keep existing config during uninstall (default)
  --remove-config     Remove configuration file during uninstall
  --remove-state      Remove state directory during uninstall (default)
  --keep-state        Keep state directory during uninstall
  --remove-logs       Remove logs directory during uninstall (default)
  --keep-logs         Keep logs directory during uninstall
  --update-registry   Remove host from logs/deploy-registry after success
  --yes               Skip confirmation prompt
  --dry-run           Print remote command without executing SSH
  --help              Show this help

Examples:
  $0 --host 192.168.1.100 --yes
  $0 --host 192.168.1.100 --keep-config --update-registry --yes
  $0 --dry-run --host 192.168.1.100 --remove-config
EOF
}

# Validate mutually exclusive uninstall flag pairs.
#
# Returns:
#   0: Flags are consistent
#   1: Conflicting flags
validate_uninstall_flags() {
	if [[ $KEEP_CONFIG_EXPLICIT -eq 1 && $REMOVE_CONFIG_EXPLICIT -eq 1 ]]; then
		log_error "Conflicting flags: --keep-config and --remove-config cannot be used together"
		return 1
	fi
	if [[ $KEEP_STATE_EXPLICIT -eq 1 && $REMOVE_STATE_EXPLICIT -eq 1 ]]; then
		log_error "Conflicting flags: --remove-state and --keep-state cannot be used together"
		return 1
	fi
	if [[ $KEEP_LOGS_EXPLICIT -eq 1 && $REMOVE_LOGS_EXPLICIT -eq 1 ]]; then
		log_error "Conflicting flags: --remove-logs and --keep-logs cannot be used together"
		return 1
	fi
	return 0
}

# Build remote uninstall.sh command with forwarded flags.
#
# Output:
#   Remote shell command string
build_remote_uninstall_command() {
	local cmd="if [[ ! -f '${REMOTE_UNINSTALL_SCRIPT}' ]]; then echo 'No VPN Monitor installation found: ${REMOTE_UNINSTALL_SCRIPT}' >&2; exit 1; fi; '${REMOTE_UNINSTALL_SCRIPT}' --yes"
	if [[ "$KEEP_CONFIG" == "yes" ]]; then
		cmd+=" --keep-config"
	else
		cmd+=" --remove-config"
	fi
	if [[ "$REMOVE_STATE" == "yes" ]]; then
		cmd+=" --remove-state"
	else
		cmd+=" --keep-state"
	fi
	if [[ "$REMOVE_LOGS" == "yes" ]]; then
		cmd+=" --remove-logs"
	else
		cmd+=" --keep-logs"
	fi
	echo "$cmd"
}

# Prompt for confirmation unless --yes or --dry-run.
#
# Arguments:
#   $1: target host
#
# Returns:
#   0: Confirmed
#   1: Declined
confirm_uninstall() {
	local host="$1"
	local response

	if [[ $SKIP_CONFIRMATION -eq 1 || $DRY_RUN -eq 1 ]]; then
		return 0
	fi

	log_warn "This will uninstall VPN Monitor from ${host}"
	while true; do
		if ! read -r -p "Continue? (y/n): " response; then
			log_error "Confirmation required; use --yes for non-interactive mode"
			return 1
		fi
		if [[ "$response" =~ ^[yY] ]]; then
			return 0
		fi
		if [[ "$response" =~ ^[nN] ]]; then
			log_info "Uninstall cancelled"
			return 1
		fi
		echo "Please enter y or n."
	done
}

# Run uninstall on a single host (uses global BIND_IP when set).
#
# Arguments:
#   $1: target host
#
# Returns:
#   0: Success
#   1: Failure
run_uninstall_on_host() {
	local host="$1"
	local remote_cmd bind_label=""

	TARGET_HOST="$host"
	[[ -n "${BIND_IP:-}" ]] && bind_label=" bind=${BIND_IP}"

	remote_cmd=$(build_remote_uninstall_command)

	if [[ $DRY_RUN -eq 1 ]]; then
		echo "[dry-run] ${host}${bind_label}: ${remote_cmd}"
		log_success "${host}: uninstall (dry-run)"
		return 0
	fi

	if ! confirm_uninstall "$host"; then
		return 1
	fi

	collect_ssh_credentials_if_needed "$host" || return 1

	if ! setup_ssh_control_master "$host"; then
		return 1
	fi

	if execute_ssh_control "$host" "$remote_cmd"; then
		if [[ $UPDATE_REGISTRY -eq 1 ]] && command -v remove_registry_entry >/dev/null 2>&1; then
			if remove_registry_entry "$host"; then
				log_info "${host}: removed from deploy registry"
			else
				log_warn "${host}: uninstall succeeded but registry update failed"
			fi
		fi
		log_success "${host}: uninstall succeeded"
		return 0
	fi
	log_error "${host}: uninstall failed"
	return 1
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--host)
			TARGET_HOST="$2"
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
		--keep-config)
			KEEP_CONFIG="yes"
			KEEP_CONFIG_EXPLICIT=1
			shift
			;;
		--remove-config)
			KEEP_CONFIG="no"
			REMOVE_CONFIG_EXPLICIT=1
			shift
			;;
		--remove-state)
			REMOVE_STATE="yes"
			REMOVE_STATE_EXPLICIT=1
			shift
			;;
		--keep-state)
			REMOVE_STATE="no"
			KEEP_STATE_EXPLICIT=1
			shift
			;;
		--remove-logs)
			REMOVE_LOGS="yes"
			REMOVE_LOGS_EXPLICIT=1
			shift
			;;
		--keep-logs)
			REMOVE_LOGS="no"
			KEEP_LOGS_EXPLICIT=1
			shift
			;;
		--update-registry)
			UPDATE_REGISTRY=1
			shift
			;;
		--yes)
			SKIP_CONFIRMATION=1
			shift
			;;
		--dry-run)
			DRY_RUN=1
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

	mkdir -p "$(dirname "$UNINSTALL_LOG_FILE")" 2>/dev/null || true

	[[ -n "$TARGET_HOST" ]] || {
		log_error "--host is required"
		display_help
		exit 1
	}

	validate_uninstall_flags || exit 1

	if run_uninstall_on_host "$TARGET_HOST"; then
		exit 0
	fi
	exit 1
}

main "$@"
