#!/bin/bash
#
# UDM VPN Monitor Deployment Script
# Deploys the VPN monitor to a remote UDM via SSH/SCP
#
# This script handles:
# 1. SCP file transfer with BindAddress
# 2. SSH connection to remote UDM
# 3. Unzip and uninstall (with options)
# 4. Install (with options)
# 5. Display recent log output
# 6. Optionally run tail -f on log file (interactive until Ctrl+C; uses same credentials)
# 7. Log deployment output to REPO_ROOT/logs/deploy-to-udm.log (username/password never logged)
#
# Connection: Uses SSH ControlMaster to authenticate once and multiplex all
# subsequent SSH/SCP operations over a single connection.  Password entry
# (via sshpass or manual /dev/tty prompt) happens only during master setup.
#
# Usage:
#   ./manage/deploy-to-udm.sh [OPTIONS]
#
# Options:
#   --file FILE              Package file to deploy (default: udm-vpn-monitor.zip)
#   --target-ip IP           Target UDM IP address (required)
#   --no-record              Do not record deployment in registry (used when tail -f will run)
#   --bind-ip IP             Source IP address for BindAddress (optional, omit for default routing)
#   --username USER          SSH username (default: root)
#   --ssh-port PORT          SSH port (default: 22)
#   --keep-config            Keep existing config during uninstall (default: yes)
#   --remove-state           Remove state directory during uninstall (default: yes)
#   --remove-logs            Remove logs directory during uninstall (default: yes)
#   --skip-uninstall         Skip uninstall step (for fresh installs)
#   --append-missing-config  Append new config fields to existing config during install
#   --log-lines N            Number of log lines to display (default: 50)
#   --tail-follow            After deploy, run tail -f on log file until Ctrl+C
#   --timeout SECONDS        SSH/SCP timeout in seconds (default: 30)
#   --verbose                Enable verbose output
#   --dry-run                Print planned SCP/SSH steps without connecting
#   --help                   Show this help message
#
# Security Notes:
# - Prompts for password interactively (not in process list)
# - Consider using SSH keys instead of passwords when possible
#
# Authentication:
#   Interactive: prompts for username and password.
#   Non-interactive: reads password from stdin (first line) when piped.
#
# Examples:
#   # Deploy (prompts for credentials)
#   ./manage/deploy-to-udm.sh --target-ip 192.168.1.100
#   ./manage/deploy-to-udm.sh --dry-run --target-ip 192.168.1.100
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Shared helpers (version parsing); required by deploy-registry.sh
# shellcheck source=lib/common.sh
if [[ -f "${REPO_ROOT}/lib/common.sh" ]]; then
	# shellcheck source=lib/common.sh
	source "${REPO_ROOT}/lib/common.sh"
fi

# Source deployment registry helpers (requires lib/common.sh)
# shellcheck source=manage/deploy-registry.sh
if [[ -f "${SCRIPT_DIR}/deploy-registry.sh" ]] && [[ -f "${REPO_ROOT}/lib/common.sh" ]]; then
	# shellcheck source=manage/deploy-registry.sh
	source "${SCRIPT_DIR}/deploy-registry.sh"
fi

# shellcheck source=manage/lib/ssh_control.sh
source "${SCRIPT_DIR}/lib/ssh_control.sh"
manage_init_terminal_colors

LOGS_DIR="${REPO_ROOT}/logs"
DEPLOY_LOG_FILE="${DEPLOY_LOG_FILE:-${LOGS_DIR}/deploy-to-udm.log}"

# Default values
PACKAGE_FILE="${REPO_ROOT}/udm-vpn-monitor.zip"
TARGET_IP=""
BIND_IP=""
SSH_USERNAME="root"
SSH_PASSWORD=""
SSH_PORT=22
KEEP_CONFIG="yes"
REMOVE_STATE="yes"
REMOVE_LOGS="yes"
SKIP_UNINSTALL=0
APPEND_MISSING_CONFIG=0
NO_RECORD=0
TAIL_FOLLOW=0
LOG_LINES=50
SSH_TIMEOUT=30
VERBOSE=0
DRY_RUN=0
CONTROL_SOCKET=""

# Append message to deploy log file (sanitized: no username or password).
# Writes plain text with timestamp; never logs credentials.
#
# Arguments:
#   $1: level - INFO, SUCCESS, WARN, ERROR, VERBOSE
#   $2+: message parts (concatenated)
#
# Returns:
#   0: Always (write failures are ignored to avoid breaking deployment)
deploy_log_write() {
	local level="$1"
	shift
	local msg="$*"
	# Sanitize: never log username or password
	[[ -n "${SSH_USERNAME:-}" ]] && msg="${msg//${SSH_USERNAME}/***}"
	[[ -n "${SSH_PASSWORD:-}" ]] && msg="${msg//${SSH_PASSWORD}/***}"
	mkdir -p "$(dirname "$DEPLOY_LOG_FILE")" 2>/dev/null || true
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $msg" >>"$DEPLOY_LOG_FILE" 2>/dev/null || true
}

# Logging: override manage_log_* so ssh_control.sh writes to deploy log too.
manage_log_info() {
	echo -e "${BLUE}[INFO]${NC} $*" >&2
	deploy_log_write "INFO" "$*"
}
manage_log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
	deploy_log_write "SUCCESS" "$*"
}
manage_log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $*" >&2
	deploy_log_write "WARN" "$*"
}
manage_log_error() {
	echo -e "${RED}[ERROR]${NC} $*" >&2
	deploy_log_write "ERROR" "$*"
}
manage_log_verbose() {
	if [[ $VERBOSE -eq 1 ]]; then
		echo -e "${BLUE}[VERBOSE]${NC} $*" >&2
		deploy_log_write "VERBOSE" "$*"
	fi
}

log_info() { manage_log_info "$@"; }
log_success() { manage_log_success "$@"; }
log_warn() { manage_log_warn "$@"; }
log_error() { manage_log_error "$@"; }
log_verbose() { manage_log_verbose "$@"; }

# Resolve bind IP from LOCAL_UDM_IP in vpn-monitor.conf when not explicitly set
#
# Checks /data/vpn-monitor/vpn-monitor.conf and repo vpn-monitor.conf.
# LOCAL_UDM_IP is the local system's IP, used as source for SCP/SSH when deploying.
#
# Returns:
#   0: Bind IP resolved and printed to stdout
#   1: No config found or LOCAL_UDM_IP not set
resolve_bind_ip_from_config() {
	local config_paths=(
		"/data/vpn-monitor/vpn-monitor.conf"
		"${REPO_ROOT:-}/vpn-monitor.conf"
	)
	local val
	for cfg in "${config_paths[@]}"; do
		[[ -f "$cfg" ]] || continue
		val=$(grep -E '^LOCAL_UDM_IP=' "$cfg" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'" | tr -d ' ')
		[[ -n "$val" ]] && {
			echo "$val"
			return 0
		}
	done
	return 1
}

# Display help message and usage to stdout.
#
# Returns:
#   0: Always
display_help() {
	cat <<EOF
Usage: $0 [OPTIONS]

Deploy UDM VPN Monitor to a remote UDM via SSH/SCP.

Required Options:
  --target-ip IP           Target UDM IP address

Optional Options:
  --bind-ip IP             Source IP for BindAddress (default: LOCAL_UDM_IP from vpn-monitor.conf)

Package Options:
  --file FILE              Package file to deploy (default: udm-vpn-monitor.zip)

Authentication Options:
  --username USER          SSH username (default: root; prompts if not set)
  --ssh-port PORT          SSH port (default: 22)

Deployment Options:
  --keep-config            Keep existing config during uninstall (default: yes)
  --remove-state           Remove state directory during uninstall (default: yes)
  --remove-logs            Remove logs directory during uninstall (default: yes)
  --skip-uninstall         Skip uninstall step (for fresh installs)
  --append-missing-config  Append new config fields to existing config during install

Output Options:
  --log-lines N            Number of log lines to display (default: 50)
  --tail-follow            After deploy, run tail -f on log file until Ctrl+C
  --timeout SECONDS        SSH/SCP timeout in seconds (default: 30)
  --verbose                Enable verbose output
  --no-record              Do not record deployment in registry (used when tail -f will run)
  --dry-run                Print planned SCP/SSH steps without connecting
  --help                   Show this help message

Authentication:
  Uses SSH ControlMaster: authenticates once, then multiplexes all operations.
  If sshpass is installed, password is passed automatically.
  Otherwise, prompts for the password once on the terminal.
  Receives password via stdin when piped (e.g. from deploy-to-udms.sh).

Examples:
  # Deploy (prompts for credentials)
  $0 --target-ip 192.168.1.100
  $0 --dry-run --target-ip 192.168.1.100
EOF
}

# Parse command-line arguments and set global option variables.
#
# Arguments:
#   $@: Command-line arguments (e.g. "$@")
#
# Returns:
#   0: Always (exits script on --help)
parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--file)
			PACKAGE_FILE="$2"
			shift 2
			;;
		--target-ip)
			TARGET_IP="$2"
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
		--ssh-port)
			SSH_PORT="$2"
			shift 2
			;;
		--keep-config)
			KEEP_CONFIG="yes"
			shift
			;;
		--remove-state)
			REMOVE_STATE="yes"
			shift
			;;
		--remove-logs)
			REMOVE_LOGS="yes"
			shift
			;;
		--skip-uninstall)
			SKIP_UNINSTALL=1
			shift
			;;
		--append-missing-config)
			APPEND_MISSING_CONFIG=1
			shift
			;;
		--log-lines)
			LOG_LINES="$2"
			shift 2
			;;
		--tail-follow)
			TAIL_FOLLOW=1
			shift
			;;
		--timeout)
			SSH_TIMEOUT="$2"
			shift 2
			;;
		--verbose)
			VERBOSE=1
			shift
			;;
		--no-record)
			NO_RECORD=1
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
			echo ""
			display_help
			exit 1
			;;
		esac
	done
}

# Validate required parameters and resolve bind IP from config if needed.
#
# Returns:
#   0: All validations passed
#   Exits 1 after printing errors and help if validation fails
validate_params() {
	local errors=0

	if [[ -z "$TARGET_IP" ]]; then
		log_error "Target IP address is required (--target-ip)"
		errors=$((errors + 1))
	fi

	if [[ ! -f "$PACKAGE_FILE" ]]; then
		log_error "Package file not found: $PACKAGE_FILE"
		errors=$((errors + 1))
	fi

	# Prompt for username and password (skipped in dry-run; no SSH/SCP)
	if [[ $DRY_RUN -eq 0 ]]; then
		if ! collect_ssh_credentials_if_needed "$TARGET_IP"; then
			errors=$((errors + 1))
		fi
	fi

	# Resolve bind IP from LOCAL_UDM_IP in vpn-monitor.conf when not set
	if [[ -z "$BIND_IP" ]]; then
		local resolved
		if resolved=$(resolve_bind_ip_from_config 2>/dev/null); then
			BIND_IP="$resolved"
			log_verbose "Using LOCAL_UDM_IP from vpn-monitor.conf for BindAddress: $BIND_IP"
		fi
	fi

	if [[ $errors -gt 0 ]]; then
		echo ""
		display_help
		exit 1
	fi
}

# Return remote path for the package file under /tmp.
#
# Returns:
#   0: Always; prints path to stdout
remote_package_path() {
	echo "/tmp/$(basename "$PACKAGE_FILE")"
}

# Build remote command to archive logs before uninstall.
#
# Returns:
#   0: Always; prints command to stdout
build_log_archive_cmd() {
	echo "mkdir -p /tmp/vpn-monitor-logs-archive && if [ -d /data/vpn-monitor/logs ] && [ -n \"\$(ls -A /data/vpn-monitor/logs 2>/dev/null)\" ]; then tar -czf /tmp/vpn-monitor-logs-archive/vpn-monitor-logs-\$(date +%Y%m%d-%H%M%S).tar.gz -C /data/vpn-monitor logs && echo 'Logs archived'; else echo 'No logs to archive'; fi"
}

# Build remote uninstall command (no-op when install absent).
#
# Returns:
#   0: Always; prints command to stdout
build_uninstall_cmd() {
	local uninstall_cmd="cd /tmp && if [ -f /data/vpn-monitor/uninstall.sh ]; then"
	uninstall_cmd+=" /data/vpn-monitor/uninstall.sh --yes"
	if [[ "$KEEP_CONFIG" == "yes" ]]; then
		uninstall_cmd+=" --keep-config"
	else
		uninstall_cmd+=" --remove-config"
	fi
	if [[ "$REMOVE_STATE" == "yes" ]]; then
		uninstall_cmd+=" --remove-state"
	else
		uninstall_cmd+=" --keep-state"
	fi
	if [[ "$REMOVE_LOGS" == "yes" ]]; then
		uninstall_cmd+=" --remove-logs"
	else
		uninstall_cmd+=" --keep-logs"
	fi
	uninstall_cmd+="; else echo 'No existing installation found, skipping uninstall'; fi"
	echo "$uninstall_cmd"
}

# Build remote command to extract the transferred package.
#
# Returns:
#   0: Success; prints command to stdout
#   1: Unknown package format (logs error)
build_extract_cmd() {
	local extract_cmd="cd /tmp && "
	if [[ "$PACKAGE_FILE" == *.tar.gz ]] || [[ "$PACKAGE_FILE" == *.tgz ]]; then
		extract_cmd+="tar -xzf $(basename "$PACKAGE_FILE")"
	elif [[ "$PACKAGE_FILE" == *.zip ]]; then
		extract_cmd+="unzip -o $(basename "$PACKAGE_FILE")"
	else
		log_error "Unknown package format: $PACKAGE_FILE"
		return 1
	fi
	echo "$extract_cmd"
}

# Build remote install command.
#
# Returns:
#   0: Always; prints command to stdout
build_install_cmd() {
	local install_cmd="cd /tmp && chmod +x install.sh && ./install.sh --silent"
	[[ $APPEND_MISSING_CONFIG -eq 1 ]] && install_cmd+=" --append-missing-config"
	echo "$install_cmd"
}

# Build remote command to show recent log lines.
#
# Returns:
#   0: Always; prints command to stdout
build_log_display_cmd() {
	echo "tail -n $LOG_LINES /data/vpn-monitor/logs/vpn-monitor.log 2>/dev/null || echo 'Log file not found or empty'"
}

# Build remote tail -f command.
#
# Returns:
#   0: Always; prints command to stdout
build_tail_follow_cmd() {
	echo "tail -f /data/vpn-monitor/logs/vpn-monitor.log 2>/dev/null || echo 'Log file not found'"
}

# Print bind= label for dry-run output when BIND_IP is set.
#
# Returns:
#   0: Always; prints label to stdout (may be empty)
dry_run_bind_label() {
	[[ -n "${BIND_IP:-}" ]] && echo " bind=${BIND_IP}"
}

# Print planned deploy steps without SSH/SCP or registry writes.
#
# Returns:
#   0: Always
print_dry_run_steps() {
	local bind_label remote_dest archive_cmd uninstall_cmd extract_cmd install_cmd log_cmd tail_cmd pkg_version

	bind_label=$(dry_run_bind_label)
	remote_dest=$(remote_package_path)

	echo "[dry-run] ${TARGET_IP}${bind_label}: scp ${PACKAGE_FILE} -> ${remote_dest}"

	if [[ $SKIP_UNINSTALL -eq 0 ]]; then
		archive_cmd=$(build_log_archive_cmd)
		echo "[dry-run] ${TARGET_IP}${bind_label}: ${archive_cmd}"
		uninstall_cmd=$(build_uninstall_cmd)
		echo "[dry-run] ${TARGET_IP}${bind_label}: ${uninstall_cmd}"
	fi

	extract_cmd=$(build_extract_cmd) || return 1
	echo "[dry-run] ${TARGET_IP}${bind_label}: ${extract_cmd}"

	install_cmd=$(build_install_cmd)
	echo "[dry-run] ${TARGET_IP}${bind_label}: ${install_cmd}"

	log_cmd=$(build_log_display_cmd)
	echo "[dry-run] ${TARGET_IP}${bind_label}: ${log_cmd}"

	if [[ $TAIL_FOLLOW -eq 1 ]]; then
		tail_cmd=$(build_tail_follow_cmd)
		echo "[dry-run] ${TARGET_IP}${bind_label}: ${tail_cmd} (interactive)"
	fi

	if [[ $NO_RECORD -eq 0 ]] && command -v get_package_version >/dev/null 2>&1; then
		if pkg_version=$(get_package_version "$PACKAGE_FILE" 2>/dev/null); then
			echo "[dry-run] ${TARGET_IP}${bind_label}: record deployment in registry (version ${pkg_version})"
		fi
	fi

	log_success "${TARGET_IP}: deploy (dry-run)"
	return 0
}

# Execute SSH command over the ControlMaster connection.
#
# Arguments:
#   $1: cmd - Remote shell command to run (single string).
#   $2: interactive - Optional. If non-empty, allocate a TTY (for tail -f etc.).
#
# Returns:
#   Exit code of ssh invocation.
execute_ssh() {
	execute_ssh_control "$TARGET_IP" "$1" "${2:-}"
}

# Execute SCP command over the ControlMaster connection.
#
# Arguments:
#   $1: src_file - Local path to file to copy
#   $2: dest_path - Remote destination path
#
# Returns:
#   Exit code of scp invocation.
execute_scp() {
	execute_scp_control "$TARGET_IP" "$1" "$2"
}

# Main deployment function: parse args, validate, transfer package, install on UDM.
#
# Arguments:
#   $@: Command-line arguments (passed to parse_args).
#
# Returns:
#   0: Deployment succeeded
#   Non-zero: Parse/validation/SSH/SCP or remote install failure
main() {
	mkdir -p "$(dirname "$DEPLOY_LOG_FILE")" 2>/dev/null || true
	log_info "UDM VPN Monitor Deployment"
	log_info "Logging to: $DEPLOY_LOG_FILE"
	log_info "=================================="
	echo ""

	# Parse arguments
	parse_args "$@"

	# Validate parameters
	validate_params

	# Display deployment plan
	log_info "Deployment Plan:"
	echo "  Package file:    $PACKAGE_FILE"
	deploy_log_write "INFO" "  Package file:    $PACKAGE_FILE"
	echo "  Target UDM:      ${SSH_USERNAME}@${TARGET_IP}:${SSH_PORT}"
	deploy_log_write "INFO" "  Target UDM:      ***@${TARGET_IP}:${SSH_PORT}"
	echo "  Bind address:    ${BIND_IP:-<default>}"
	deploy_log_write "INFO" "  Bind address:    ${BIND_IP:-<default>}"
	echo "  Uninstall:       $([ $SKIP_UNINSTALL -eq 1 ] && echo "Skip" || echo "Yes")"
	deploy_log_write "INFO" "  Uninstall:       $([ $SKIP_UNINSTALL -eq 1 ] && echo 'Skip' || echo 'Yes')"
	if [[ $SKIP_UNINSTALL -eq 0 ]]; then
		echo "    Keep config:   $KEEP_CONFIG"
		echo "    Remove state:  $REMOVE_STATE"
		echo "    Remove logs:   $REMOVE_LOGS"
		deploy_log_write "INFO" "    Keep config:   $KEEP_CONFIG"
		deploy_log_write "INFO" "    Remove state:  $REMOVE_STATE"
		deploy_log_write "INFO" "    Remove logs:   $REMOVE_LOGS"
	fi
	echo "  Log lines:       $LOG_LINES"
	deploy_log_write "INFO" "  Log lines:       $LOG_LINES"
	echo ""

	if [[ $DRY_RUN -eq 1 ]]; then
		log_info "Dry-run mode: no SSH/SCP operations will be performed"
		print_dry_run_steps || exit 1
		exit 0
	fi

	# Establish ControlMaster (authenticates once, all subsequent ssh/scp reuse it)
	MANAGE_SSH_VERBOSE=$VERBOSE
	if ! setup_ssh_control_master "$TARGET_IP"; then
		log_error "Could not connect to ${TARGET_IP}. Check credentials and network."
		exit 1
	fi
	echo ""

	# Step 1: Transfer package file
	log_info "Step 1: Transferring package file to target UDM..."
	if execute_scp "$PACKAGE_FILE" "/tmp/$(basename "$PACKAGE_FILE")"; then
		log_success "Package file transferred successfully"
	else
		log_error "Failed to transfer package file"
		exit 1
	fi
	echo ""

	# Step 2: Archive logs (before uninstall)
	if [[ $SKIP_UNINSTALL -eq 0 ]]; then
		log_info "Step 2: Archiving logs on target UDM (if present)..."
		local archive_cmd
		archive_cmd=$(build_log_archive_cmd)
		if execute_ssh "$archive_cmd"; then
			log_success "Log archive step completed"
		else
			log_warn "Log archive step may have failed, continuing"
		fi
		echo ""
	fi

	# Step 3: Uninstall (if not skipped)
	if [[ $SKIP_UNINSTALL -eq 0 ]]; then
		log_info "Step 3: Uninstalling existing installation (if present)..."
		local uninstall_cmd
		uninstall_cmd=$(build_uninstall_cmd)

		if execute_ssh "$uninstall_cmd"; then
			log_success "Uninstall completed"
		else
			log_warn "Uninstall may have failed, but continuing with installation"
		fi
		echo ""
	fi

	# Step 4: Extract package
	log_info "Step 4: Extracting package on target UDM..."
	local extract_cmd
	extract_cmd=$(build_extract_cmd) || exit 1

	if execute_ssh "$extract_cmd"; then
		log_success "Package extracted successfully"
	else
		log_error "Failed to extract package"
		exit 1
	fi
	echo ""

	# Step 5: Install
	log_info "Step 5: Installing VPN Monitor..."
	local install_cmd
	install_cmd=$(build_install_cmd)

	if execute_ssh "$install_cmd"; then
		log_success "Installation completed successfully"
	else
		log_error "Installation failed"
		exit 1
	fi
	echo ""

	# Step 6: Display recent log output
	log_info "Step 6: Displaying last $LOG_LINES lines of log file..."
	local log_cmd
	log_cmd=$(build_log_display_cmd)

	if execute_ssh "$log_cmd"; then
		log_success "Log output displayed"
	else
		log_warn "Could not display log output (log file may not exist yet)"
	fi
	echo ""

	# Step 6b: Optional tail -f (interactive until Ctrl+C; uses same credentials)
	if [[ $TAIL_FOLLOW -eq 1 ]]; then
		log_info "Tailing vpn-monitor.log (Ctrl+C to exit)..."
		local tail_cmd
		tail_cmd=$(build_tail_follow_cmd)
		execute_ssh "$tail_cmd" "interactive" || true
		echo ""
	fi

	# Summary
	log_success "Deployment completed successfully!"

	# Record deployment in registry (skip when --no-record, e.g. batch deploy with tail -f)
	if [[ $NO_RECORD -eq 0 ]] && [[ -n "${REPO_ROOT:-}" ]] && command -v record_deployment >/dev/null 2>&1; then
		local pkg_version
		if pkg_version=$(get_package_version "$PACKAGE_FILE" 2>/dev/null); then
			if record_deployment "$TARGET_IP" "$pkg_version" 2>/dev/null; then
				log_verbose "Recorded deployment: $TARGET_IP version $pkg_version"
			fi
		fi
	fi

	echo ""
	log_info "Next steps:"
	echo "  1. Verify installation: ssh ${SSH_USERNAME}@${TARGET_IP} 'ls -la /data/vpn-monitor/'"
	echo "  2. Check configuration: ssh ${SSH_USERNAME}@${TARGET_IP} 'cat /data/vpn-monitor/vpn-monitor.conf'"
	echo "  3. Monitor logs: ssh ${SSH_USERNAME}@${TARGET_IP} 'tail -f /data/vpn-monitor/logs/vpn-monitor.log'"
	deploy_log_write "INFO" "  1. Verify installation: ssh ***@${TARGET_IP} 'ls -la /data/vpn-monitor/'"
	deploy_log_write "INFO" "  2. Check configuration: ssh ***@${TARGET_IP} 'cat /data/vpn-monitor/vpn-monitor.conf'"
	deploy_log_write "INFO" "  3. Monitor logs: ssh ***@${TARGET_IP} 'tail -f /data/vpn-monitor/logs/vpn-monitor.log'"
	echo ""
}

# Run main function
main "$@"
