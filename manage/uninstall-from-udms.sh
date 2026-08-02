#!/bin/bash
#
# Remote UDM VPN Monitor Batch Uninstall
# SSH to multiple UDMs and run uninstall.sh without transferring a package.
#
# Usage:
#   ./manage/uninstall-from-udms.sh [OPTIONS]
#
# Examples:
#   ./manage/uninstall-from-udms.sh --config deploy-udms.conf --yes
#   ./manage/uninstall-from-udms.sh --yes --keep-config --update-registry
#   ./manage/uninstall-from-udms.sh --dry-run --config deploy-udms.conf
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOGS_DIR="${REPO_ROOT}/logs"
UNINSTALL_LOG_FILE="${UNINSTALL_LOG_FILE:-${LOGS_DIR}/uninstall-from-udms.log}"

# shellcheck source=manage/lib/ssh_control.sh
source "${SCRIPT_DIR}/lib/ssh_control.sh"
manage_init_terminal_colors

CONFIG_FILE="${REPO_ROOT}/deploy-udms.conf"
SKIP_CONFIRMATION=0
DRY_RUN=0
UPDATE_REGISTRY=0

# Forwarded to uninstall-from-udm.sh
UNINSTALL_ARGS=()

# Append message to batch uninstall log file.
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

Remove VPN Monitor from multiple remote UDMs via SSH (no package transfer).

Options:
  --config FILE       Config file with UDM list (default: deploy-udms.conf)
  --keep-config       Keep existing config during uninstall (default)
  --remove-config     Remove configuration file during uninstall
  --remove-state      Remove state directory during uninstall (default)
  --keep-state        Keep state directory during uninstall
  --remove-logs       Remove logs directory during uninstall (default)
  --keep-logs         Keep logs directory during uninstall
  --update-registry   Remove each host from logs/deploy-registry after success
  --yes               Skip batch confirmation prompt
  --dry-run           Print remote commands without executing SSH
  --help              Show this help

Config format: host_or_ip [bind_ip]
See manage/deploy-udms.conf.example for details.

Examples:
  $0 --config deploy-udms.conf --yes
  $0 --yes --keep-config --update-registry
  $0 --dry-run --config deploy-udms.conf
EOF
}

# Prompt once for batch confirmation unless --yes or --dry-run.
#
# Arguments:
#   $@: host list
#
# Returns:
#   0: Confirmed
#   1: Declined
confirm_batch_uninstall() {
	local -a hosts=("$@")
	local response

	if [[ $SKIP_CONFIRMATION -eq 1 || $DRY_RUN -eq 1 ]]; then
		return 0
	fi

	log_warn "This will uninstall VPN Monitor from ${#hosts[@]} host(s):"
	for host in "${hosts[@]}"; do
		echo "  - ${host%% *}"
	done
	while true; do
		if ! read -r -p "Continue? (y/n): " response; then
			log_error "Confirmation required; use --yes for non-interactive mode"
			return 1
		fi
		if [[ "$response" =~ ^[yY] ]]; then
			return 0
		fi
		if [[ "$response" =~ ^[nN] ]]; then
			log_info "Batch uninstall cancelled"
			return 1
		fi
		echo "Please enter y or n."
	done
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--config)
			CONFIG_FILE="$2"
			shift 2
			;;
		--keep-config)
			UNINSTALL_ARGS+=(--keep-config)
			shift
			;;
		--remove-config)
			UNINSTALL_ARGS+=(--remove-config)
			shift
			;;
		--remove-state)
			UNINSTALL_ARGS+=(--remove-state)
			shift
			;;
		--keep-state)
			UNINSTALL_ARGS+=(--keep-state)
			shift
			;;
		--remove-logs)
			UNINSTALL_ARGS+=(--remove-logs)
			shift
			;;
		--keep-logs)
			UNINSTALL_ARGS+=(--keep-logs)
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

	if [[ ! -f "$CONFIG_FILE" ]]; then
		log_error "Config file not found: $CONFIG_FILE"
		log_info "Copy manage/deploy-udms.conf.example to deploy-udms.conf and add your UDMs"
		exit 1
	fi

	local -a hosts=()
	read_manage_host_config "$CONFIG_FILE" hosts

	if [[ ${#hosts[@]} -eq 0 ]]; then
		log_error "No hosts in config: $CONFIG_FILE"
		exit 1
	fi

	confirm_batch_uninstall "${hosts[@]}" || exit 1

	log_info "Remote uninstall on ${#hosts[@]} host(s)"
	log_info "Logging to: $UNINSTALL_LOG_FILE"
	echo ""

	local success_count=0 fail_count=0
	local per_host_args=("${UNINSTALL_ARGS[@]}")
	[[ $UPDATE_REGISTRY -eq 1 ]] && per_host_args+=(--update-registry)
	# Batch already confirmed (or --yes/--dry-run skipped confirm); avoid per-host prompts.
	per_host_args+=(--yes)
	[[ $DRY_RUN -eq 1 ]] && per_host_args+=(--dry-run)

	local entry host_ip host_bind
	for entry in "${hosts[@]}"; do
		host_ip="${entry%% *}"
		host_bind=""
		if [[ "$entry" == *" "* ]]; then
			host_bind="${entry#* }"
			host_bind="${host_bind%% *}"
		fi
		[[ -z "$host_ip" ]] && continue

		local host_args=(--host "$host_ip" "${per_host_args[@]}")
		[[ -n "$host_bind" ]] && host_args=(--bind-ip "$host_bind" "${host_args[@]}")

		if UNINSTALL_LOG_FILE="$UNINSTALL_LOG_FILE" "${SCRIPT_DIR}/uninstall-from-udm.sh" "${host_args[@]}"; then
			success_count=$((success_count + 1))
		else
			fail_count=$((fail_count + 1))
		fi
		echo ""
	done

	log_info "Summary: ${success_count} succeeded, ${fail_count} failed"
	[[ $fail_count -eq 0 ]]
}

main "$@"
