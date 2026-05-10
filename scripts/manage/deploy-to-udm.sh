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
#   ./scripts/manage/deploy-to-udm.sh [OPTIONS]
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
#   ./scripts/manage/deploy-to-udm.sh --target-ip 192.168.1.100
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source deployment registry helpers (for record_deployment)
# shellcheck source=scripts/deploy-registry.sh
if [[ -f "${SCRIPT_DIR}/deploy-registry.sh" ]]; then
	# shellcheck source=scripts/deploy-registry.sh
	source "${SCRIPT_DIR}/deploy-registry.sh"
fi
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

# SSH ControlMaster socket (set during setup_control_master)
CONTROL_SOCKET=""

# Colors for output (if terminal supports it)
if [[ -t 1 ]]; then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[1;33m'
	BLUE='\033[0;34m'
	NC='\033[0m' # No Color
else
	RED=''
	GREEN=''
	YELLOW=''
	BLUE=''
	NC=''
fi

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

# Logging functions (write to stderr and append to deploy log file)
log_info() {
	echo -e "${BLUE}[INFO]${NC} $*" >&2
	deploy_log_write "INFO" "$*"
}
# Log success message to stderr and log file.
log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
	deploy_log_write "SUCCESS" "$*"
}
# Log warning message to stderr and log file.
log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $*" >&2
	deploy_log_write "WARN" "$*"
}
# Log error message to stderr and log file.
log_error() {
	echo -e "${RED}[ERROR]${NC} $*" >&2
	deploy_log_write "ERROR" "$*"
}

# Log verbose message to stderr and log file when VERBOSE=1.
#
# Arguments:
#   $1+: message parts (concatenated)
#
# Returns:
#   0: Always
log_verbose() {
	if [[ $VERBOSE -eq 1 ]]; then
		echo -e "${BLUE}[VERBOSE]${NC} $*" >&2
		deploy_log_write "VERBOSE" "$*"
	fi
}

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
  --help                   Show this help message

Authentication:
  Uses SSH ControlMaster: authenticates once, then multiplexes all operations.
  If sshpass is installed, password is passed automatically.
  Otherwise, prompts for the password once on the terminal.
  Receives password via stdin when piped (e.g. from deploy-to-udms.sh).

Examples:
  # Deploy (prompts for credentials)
  $0 --target-ip 192.168.1.100
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

	# Prompt for username (interactive only)
	if [[ -z "$SSH_PASSWORD" ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
		read -rp "Username for ${TARGET_IP} [${SSH_USERNAME}]: " read_user
		[[ -n "$read_user" ]] && SSH_USERNAME="$read_user"
	fi

	# Get password: needed for sshpass/expect to feed to ControlMaster.
	# When neither is available and we have a tty, ssh prompts directly — skip collection.
	local has_sshpass=0 has_expect=0
	command -v sshpass >/dev/null 2>&1 && has_sshpass=1
	command -v expect >/dev/null 2>&1 && has_expect=1

	if [[ -z "$SSH_PASSWORD" ]]; then
		if [[ $has_sshpass -eq 1 ]] || [[ $has_expect -eq 1 ]]; then
			# We can feed the password programmatically — collect it
			if [[ -t 0 ]] && [[ -t 1 ]]; then
				read -rsp "Password for ${SSH_USERNAME}@${TARGET_IP}: " SSH_PASSWORD
				echo ""
			else
				# Non-interactive: read password from stdin (first line)
				SSH_PASSWORD=$(head -n 1 2>/dev/null || echo "")
			fi
			if [[ -z "$SSH_PASSWORD" ]]; then
				log_error "Password is required. Run interactively or pipe password via stdin."
				errors=$((errors + 1))
			fi
		else
			# No sshpass/expect: ssh will prompt on /dev/tty during ControlMaster setup.
			# We still need a tty for this to work.
			if [[ ! -e /dev/tty ]]; then
				log_error "No sshpass or expect installed, and no controlling terminal."
				log_error "Install sshpass (apt-get install sshpass) for non-interactive use."
				errors=$((errors + 1))
			else
				log_verbose "No sshpass/expect: SSH will prompt for password during connection setup."
			fi
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

# Common SSH options used by ControlMaster setup and all ssh/scp calls.
# Returns the options string on stdout.
#
# Returns:
#   0: Always
build_ssh_opts() {
	local opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=$SSH_TIMEOUT"
	[[ -n "$BIND_IP" ]] && opts="$opts -o BindAddress=$BIND_IP"
	[[ -n "$CONTROL_SOCKET" ]] && opts="$opts -o ControlPath=$CONTROL_SOCKET"
	echo "$opts"
}

# Establish an SSH ControlMaster connection (authenticates once).
# All subsequent execute_ssh/execute_scp calls multiplex over this connection.
# Uses sshpass if available; falls back to expect; otherwise prompts on /dev/tty.
#
# Arguments:
#   None (reads SSH_PASSWORD, SSH_USERNAME, TARGET_IP, SSH_PORT, SSH_TIMEOUT,
#         BIND_IP globals).
#
# Arguments:
#   None (reads SSH_PASSWORD, SSH_USERNAME, TARGET_IP, SSH_PORT, SSH_TIMEOUT,
#         BIND_IP globals).
#
# Returns:
#   0: ControlMaster established
#   1: Failed to establish connection
#
# Side effects:
#   Sets CONTROL_SOCKET global, registers EXIT trap for cleanup.
setup_control_master() {
	# Create socket in a private temp directory (secure: no symlink attacks, mode 0700)
	local sock_dir
	sock_dir=$(mktemp -d /tmp/ssh-deploy-XXXXXX)
	chmod 700 "$sock_dir"
	CONTROL_SOCKET="${sock_dir}/ctrl.sock"

	# Remove stale socket if present (e.g. from a crashed previous run)
	rm -f "$CONTROL_SOCKET" 2>/dev/null || true

	# Clean up on exit (remove socket and kill master)
	# shellcheck disable=SC2064
	trap "cleanup_control_master" EXIT

	local master_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=$SSH_TIMEOUT"
	master_opts="$master_opts -o ControlMaster=yes -o ControlPath=$CONTROL_SOCKET -o ControlPersist=60"
	[[ -n "$BIND_IP" ]] && master_opts="$master_opts -o BindAddress=$BIND_IP"

	log_info "Establishing SSH connection to ${TARGET_IP}..."

	# Run a trivial remote command ("true") to establish the ControlMaster.
	# ControlPersist=60 keeps the master socket alive after "true" exits,
	# so sshpass/expect/ssh all exit cleanly (no -f backgrounding needed).
	# Each subsequent ssh/scp resets the 60-second persist timer.
	local auth_rc=0

	if command -v sshpass >/dev/null 2>&1; then
		log_verbose "Using sshpass for ControlMaster authentication"
		# sshpass -e reads password from SSHPASS env var (not visible in ps)
		# shellcheck disable=SC2086
		SSHPASS="$SSH_PASSWORD" sshpass -e ssh \
			$master_opts \
			-p "$SSH_PORT" \
			"${SSH_USERNAME}@${TARGET_IP}" \
			true || auth_rc=$?
	elif command -v expect >/dev/null 2>&1; then
		log_verbose "Using expect for ControlMaster authentication"
		# expect feeds the password to ssh's tty-based prompt, then ssh
		# runs "true" and exits cleanly.
		DEPLOY_PASSWORD="$SSH_PASSWORD" \
			DEPLOY_TIMEOUT="$SSH_TIMEOUT" \
			DEPLOY_MASTER_OPTS="$master_opts" \
			DEPLOY_PORT="$SSH_PORT" \
			DEPLOY_USER="$SSH_USERNAME" \
			DEPLOY_HOST="$TARGET_IP" \
			expect <<'EXPECT_EOF' || auth_rc=$?
set timeout $env(DEPLOY_TIMEOUT)
spawn ssh {*}$env(DEPLOY_MASTER_OPTS) -p $env(DEPLOY_PORT) $env(DEPLOY_USER)@$env(DEPLOY_HOST) true
expect {
	"assword:" {
		send "$env(DEPLOY_PASSWORD)\r"
		exp_continue
	}
	"yes/no" {
		send "yes\r"
		exp_continue
	}
	eof
}
lassign [wait] pid spawnid os_error value
exit $value
EXPECT_EOF
	else
		# Manual password entry: user types password once on /dev/tty.
		# validate_params already confirmed /dev/tty exists.
		# shellcheck disable=SC2086
		ssh $master_opts \
			-p "$SSH_PORT" \
			"${SSH_USERNAME}@${TARGET_IP}" \
			true </dev/tty 2>/dev/tty || auth_rc=$?
	fi

	# Verify the master socket is alive (ssh+true already exited; ControlPersist keeps it)
	if [[ $auth_rc -eq 0 ]] && ssh -o ControlPath="$CONTROL_SOCKET" -O check "${SSH_USERNAME}@${TARGET_IP}" 2>/dev/null; then
		log_success "SSH connection established (ControlMaster)"
		return 0
	fi

	log_error "Failed to establish ControlMaster connection"
	[[ $auth_rc -ne 0 ]] && log_error "SSH authentication exited with code $auth_rc"
	# Clean up the temp directory (socket may not have been created)
	rm -f "$CONTROL_SOCKET" 2>/dev/null || true
	[[ -n "$sock_dir" ]] && [[ "$sock_dir" == /tmp/ssh-deploy-* ]] && rmdir "$sock_dir" 2>/dev/null || true
	CONTROL_SOCKET=""
	return 1
}

# Tear down the ControlMaster connection and remove the socket/directory.
# Designed to run safely inside an EXIT trap (suppresses all errors).
#
# Arguments:
#   None (reads CONTROL_SOCKET, SSH_USERNAME, TARGET_IP globals).
#
# Arguments:
#   None (reads CONTROL_SOCKET, SSH_USERNAME, TARGET_IP globals).
#
# Returns:
#   0: Always
cleanup_control_master() {
	# Guard against set -e killing the trap mid-cleanup
	set +e
	if [[ -n "${CONTROL_SOCKET:-}" ]]; then
		if [[ -e "$CONTROL_SOCKET" ]]; then
			ssh -o ControlPath="$CONTROL_SOCKET" -O exit "${SSH_USERNAME}@${TARGET_IP}" 2>/dev/null
		fi
		# Remove the socket and its private temp directory
		local sock_dir
		sock_dir="$(dirname "$CONTROL_SOCKET" 2>/dev/null)"
		rm -f "$CONTROL_SOCKET" 2>/dev/null
		[[ -n "$sock_dir" ]] && [[ "$sock_dir" == /tmp/ssh-deploy-* ]] && rmdir "$sock_dir" 2>/dev/null
	fi
	set -e
}

# Execute SSH command over the ControlMaster connection.
# No password entry needed — authentication was handled by setup_control_master.
#
# Arguments:
#   $1: cmd - Remote shell command to run (single string).
#   $2: interactive - Optional. If non-empty, allocate a TTY (for tail -f etc.).
#
# Returns:
#   Exit code of ssh invocation.
execute_ssh() {
	local cmd="$1"
	local interactive="${2:-}"

	local ssh_opts
	ssh_opts="$(build_ssh_opts)"
	[[ -n "$interactive" ]] && ssh_opts="$ssh_opts -t"

	# shellcheck disable=SC2086
	ssh $ssh_opts \
		-p "$SSH_PORT" \
		"${SSH_USERNAME}@${TARGET_IP}" \
		"$cmd"
}

# Execute SCP command over the ControlMaster connection.
# No password entry needed — authentication was handled by setup_control_master.
#
# Arguments:
#   $1: src_file - Local path to file to copy
#   $2: dest_path - Remote destination path
#
# Returns:
#   Exit code of scp invocation.
execute_scp() {
	local src_file="$1"
	local dest_path="$2"

	local scp_opts
	scp_opts="$(build_ssh_opts)"

	# shellcheck disable=SC2086
	scp $scp_opts \
		-P "$SSH_PORT" \
		"$src_file" \
		"${SSH_USERNAME}@${TARGET_IP}:${dest_path}"
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

	# Establish ControlMaster (authenticates once, all subsequent ssh/scp reuse it)
	if ! setup_control_master; then
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
		local archive_cmd="mkdir -p /tmp/vpn-monitor-logs-archive && if [ -d /data/vpn-monitor/logs ] && [ -n \"\$(ls -A /data/vpn-monitor/logs 2>/dev/null)\" ]; then tar -czf /tmp/vpn-monitor-logs-archive/vpn-monitor-logs-\$(date +%Y%m%d-%H%M%S).tar.gz -C /data/vpn-monitor logs && echo 'Logs archived'; else echo 'No logs to archive'; fi"
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

		if execute_ssh "$uninstall_cmd"; then
			log_success "Uninstall completed"
		else
			log_warn "Uninstall may have failed, but continuing with installation"
		fi
		echo ""
	fi

	# Step 4: Extract package
	log_info "Step 4: Extracting package on target UDM..."
	local extract_cmd="cd /tmp && "
	if [[ "$PACKAGE_FILE" == *.tar.gz ]] || [[ "$PACKAGE_FILE" == *.tgz ]]; then
		extract_cmd+="tar -xzf $(basename "$PACKAGE_FILE")"
	elif [[ "$PACKAGE_FILE" == *.zip ]]; then
		extract_cmd+="unzip -o $(basename "$PACKAGE_FILE")"
	else
		log_error "Unknown package format: $PACKAGE_FILE"
		exit 1
	fi

	if execute_ssh "$extract_cmd"; then
		log_success "Package extracted successfully"
	else
		log_error "Failed to extract package"
		exit 1
	fi
	echo ""

	# Step 5: Install
	log_info "Step 5: Installing VPN Monitor..."
	local install_cmd="cd /tmp && chmod +x install.sh && ./install.sh --silent"
	[[ $APPEND_MISSING_CONFIG -eq 1 ]] && install_cmd+=" --append-missing-config"

	if execute_ssh "$install_cmd"; then
		log_success "Installation completed successfully"
	else
		log_error "Installation failed"
		exit 1
	fi
	echo ""

	# Step 6: Display recent log output
	log_info "Step 6: Displaying last $LOG_LINES lines of log file..."
	local log_cmd="tail -n $LOG_LINES /data/vpn-monitor/logs/vpn-monitor.log 2>/dev/null || echo 'Log file not found or empty'"

	if execute_ssh "$log_cmd"; then
		log_success "Log output displayed"
	else
		log_warn "Could not display log output (log file may not exist yet)"
	fi
	echo ""

	# Step 6b: Optional tail -f (interactive until Ctrl+C; uses same credentials)
	if [[ $TAIL_FOLLOW -eq 1 ]]; then
		log_info "Tailing vpn-monitor.log (Ctrl+C to exit)..."
		local tail_cmd="tail -f /data/vpn-monitor/logs/vpn-monitor.log 2>/dev/null || echo 'Log file not found'"
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
