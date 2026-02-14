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
#
# Usage:
#   ./scripts/deploy-to-udm.sh [OPTIONS]
#
# Options:
#   --file FILE              Package file to deploy (default: udm-vpn-monitor.zip)
#   --target-ip IP           Target UDM IP address (required)
#   --bind-ip IP             Source IP address for BindAddress (optional, omit for default routing)
#   --username USER          SSH username (default: root)
#   --password PASS          SSH password (required, or use --password-file)
#   --password-file FILE     File containing SSH password (alternative to --password)
#   --ssh-port PORT          SSH port (default: 22)
#   --keep-config            Keep existing config during uninstall (default: yes)
#   --remove-state           Remove state directory during uninstall (default: yes)
#   --remove-logs            Remove logs directory during uninstall (default: yes)
#   --skip-uninstall         Skip uninstall step (for fresh installs)
#   --append-missing-config  Append new config fields to existing config during install
#   --log-lines N            Number of log lines to display (default: 50)
#   --timeout SECONDS        SSH/SCP timeout in seconds (default: 30)
#   --verbose                Enable verbose output
#   --help                   Show this help message
#
# Security Notes:
# - Passwords are passed via environment variables or files to avoid process list exposure
# - Consider using SSH keys instead of passwords when possible
# - Passwords in command line arguments are visible in process lists
#
# Examples:
#   # Deploy with password from file
#   ./scripts/deploy-to-udm.sh \
#     --file udm-vpn-monitor.zip \
#     --target-ip 192.168.1.100 \
#     --bind-ip 192.168.1.50 \
#     --password-file /path/to/password.txt
#
#   # Deploy with password from environment variable
#   SSH_PASSWORD="mypass" ./scripts/deploy-to-udm.sh \
#     --file udm-vpn-monitor.zip \
#     --target-ip 192.168.1.100 \
#     --bind-ip 192.168.1.50
#
#   # Deploy with explicit password (less secure - visible in ps)
#   ./scripts/deploy-to-udm.sh \
#     --file udm-vpn-monitor.zip \
#     --target-ip 192.168.1.100 \
#     --bind-ip 192.168.1.50 \
#     --password "mypass"
#

set -euo pipefail

# Default values
PACKAGE_FILE="udm-vpn-monitor.zip"
TARGET_IP=""
BIND_IP=""
SSH_USERNAME="root"
SSH_PASSWORD=""
SSH_PASSWORD_FILE=""
SSH_PORT=22
KEEP_CONFIG="yes"
REMOVE_STATE="yes"
REMOVE_LOGS="yes"
SKIP_UNINSTALL=0
APPEND_MISSING_CONFIG=0
LOG_LINES=50
SSH_TIMEOUT=30
VERBOSE=0

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

# Logging functions (write prefixed message to stderr)
log_info() {
	echo -e "${BLUE}[INFO]${NC} $*" >&2
}
# Log success message to stderr.
log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}
# Log warning message to stderr.
log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $*" >&2
}
# Log error message to stderr.
log_error() {
	echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Log verbose message to stderr when VERBOSE=1.
log_verbose() {
	if [[ $VERBOSE -eq 1 ]]; then
		echo -e "${BLUE}[VERBOSE]${NC} $*" >&2
	fi
}

# Resolve bind IP from LOCAL_UDM_IP in vpn-monitor.conf when not explicitly set
#
# Checks /data/vpn-monitor/vpn-monitor.conf and repo vpn-monitor.conf.
# LOCAL_UDM_IP is the local system's IP, used as source for SCP/SSH when deploying.
#
# Arguments:
#   None (reads config file paths internally).
#
# Returns:
#   0: Bind IP resolved and printed to stdout
#   1: No config found or LOCAL_UDM_IP not set
resolve_bind_ip_from_config() {
	local config_paths=(
		"/data/vpn-monitor/vpn-monitor.conf"
		"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/vpn-monitor.conf"
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
# Arguments:
#   None
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
  --username USER          SSH username (default: root)
  --password PASS          SSH password (required, or use --password-file)
  --password-file FILE     File containing SSH password (alternative to --password)
  --ssh-port PORT          SSH port (default: 22)

Deployment Options:
  --keep-config            Keep existing config during uninstall (default: yes)
  --remove-state           Remove state directory during uninstall (default: yes)
  --remove-logs            Remove logs directory during uninstall (default: yes)
  --skip-uninstall         Skip uninstall step (for fresh installs)
  --append-missing-config  Append new config fields to existing config during install

Output Options:
  --log-lines N            Number of log lines to display (default: 50)
  --timeout SECONDS        SSH/SCP timeout in seconds (default: 30)
  --verbose                Enable verbose output
  --help                   Show this help message

Security Notes:
  - Passwords passed via --password are visible in process lists (ps)
  - Use --password-file or SSH_PASSWORD environment variable for better security
  - Consider using SSH keys instead of passwords when possible

Examples:
  # Deploy with password from file
  $0 --file udm-vpn-monitor.zip \\
     --target-ip 192.168.1.100 \\
     --bind-ip 192.168.1.50 \\
     --password-file /path/to/password.txt

  # Deploy with password from environment variable
  SSH_PASSWORD="mypass" $0 \\
     --file udm-vpn-monitor.zip \\
     --target-ip 192.168.1.100 \\
     --bind-ip 192.168.1.50

  # Deploy with explicit password (less secure)
  $0 --file udm-vpn-monitor.zip \\
     --target-ip 192.168.1.100 \\
     --bind-ip 192.168.1.50 \\
     --password "mypass"
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
		--password)
			SSH_PASSWORD="$2"
			shift 2
			;;
		--password-file)
			SSH_PASSWORD_FILE="$2"
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
		--timeout)
			SSH_TIMEOUT="$2"
			shift 2
			;;
		--verbose)
			VERBOSE=1
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
# Arguments:
#   None (uses global option variables).
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

	# Get password from file, environment variable, or argument
	# Priority: password file > command line argument > environment variable
	if [[ -n "$SSH_PASSWORD_FILE" ]]; then
		if [[ ! -f "$SSH_PASSWORD_FILE" ]]; then
			log_error "Password file not found: $SSH_PASSWORD_FILE"
			errors=$((errors + 1))
		else
			# Read password from file (first line only, trim whitespace)
			SSH_PASSWORD=$(head -n 1 "$SSH_PASSWORD_FILE" | tr -d '[:space:]')
			if [[ -z "$SSH_PASSWORD" ]]; then
				log_error "Password file is empty: $SSH_PASSWORD_FILE"
				errors=$((errors + 1))
			fi
		fi
	elif [[ -z "$SSH_PASSWORD" ]]; then
		# Try environment variable (may have been set before script execution)
		# Use printenv to check actual environment, not script variable
		local env_password
		env_password=$(printenv SSH_PASSWORD 2>/dev/null || echo "")
		if [[ -n "$env_password" ]]; then
			SSH_PASSWORD="$env_password"
		else
			log_error "SSH password is required (--password, --password-file, or SSH_PASSWORD env var)"
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

# Check if sshpass is available for password-based SSH/SCP.
#
# Arguments:
#   None
#
# Returns:
#   0: sshpass found
#   1: sshpass not found
check_sshpass() {
	if command -v sshpass >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

# Check if expect is available for password-based SSH/SCP fallback.
#
# Arguments:
#   None
#
# Returns:
#   0: expect found
#   1: expect not found
check_expect() {
	if command -v expect >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

# Execute SSH command with password authentication.
# Uses sshpass if available, otherwise falls back to expect or manual entry.
#
# Arguments:
#   $1: cmd - Remote shell command to run (single string).
#
# Returns:
#   Exit code of ssh (or expect) invocation.
#
# Side effects:
#   Connects to TARGET_IP, may prompt for password if no sshpass/expect.
execute_ssh() {
	local cmd="$1"
	local use_sshpass=0
	local use_expect=0

	# Try sshpass first (simplest)
	if check_sshpass; then
		use_sshpass=1
		log_verbose "Using sshpass for password authentication"
	# Try expect as fallback
	elif check_expect; then
		use_expect=1
		log_verbose "Using expect for password authentication"
	else
		log_warn "Neither sshpass nor expect found. SSH password will need to be entered manually."
		log_warn "Consider installing sshpass: apt-get install sshpass (or equivalent)"
	fi

	local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=$SSH_TIMEOUT"
	[[ -n "$BIND_IP" ]] && ssh_opts="$ssh_opts -o BindAddress=$BIND_IP"

	if [[ $use_sshpass -eq 1 ]]; then
		# Use sshpass (password passed via environment variable to avoid ps exposure)
		SSHPASS="$SSH_PASSWORD" sshpass -e ssh \
			$ssh_opts \
			-p "$SSH_PORT" \
			"${SSH_USERNAME}@${TARGET_IP}" \
			"$cmd"
	elif [[ $use_expect -eq 1 ]]; then
		# Use expect script
		expect <<EOF
set timeout $SSH_TIMEOUT
spawn ssh $ssh_opts -p $SSH_PORT ${SSH_USERNAME}@${TARGET_IP} "$cmd"
expect {
	"password:" {
		send "$SSH_PASSWORD\r"
		exp_continue
	}
	"yes/no" {
		send "yes\r"
		exp_continue
	}
	eof
}
EOF
	else
		# Manual entry fallback
		ssh \
			$ssh_opts \
			-p "$SSH_PORT" \
			"${SSH_USERNAME}@${TARGET_IP}" \
			"$cmd"
	fi
}

# Execute SCP command with password authentication.
#
# Arguments:
#   $1: src_file - Local path to file to copy
#   $2: dest_path - Remote path (user@host:path)
#
# Returns:
#   Exit code of scp (or expect) invocation.
#
# Side effects:
#   Copies file to TARGET_IP; may prompt for password if no sshpass/expect.
execute_scp() {
	local src_file="$1"
	local dest_path="$2"
	local use_sshpass=0
	local use_expect=0

	# Try sshpass first
	if check_sshpass; then
		use_sshpass=1
		log_verbose "Using sshpass for SCP password authentication"
	# Try expect as fallback
	elif check_expect; then
		use_expect=1
		log_verbose "Using expect for SCP password authentication"
	else
		log_warn "Neither sshpass nor expect found. SCP password will need to be entered manually."
	fi

	local scp_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=$SSH_TIMEOUT"
	[[ -n "$BIND_IP" ]] && scp_opts="$scp_opts -o BindAddress=$BIND_IP"

	if [[ $use_sshpass -eq 1 ]]; then
		# Use sshpass (password passed via environment variable)
		SSHPASS="$SSH_PASSWORD" sshpass -e scp \
			$scp_opts \
			-P "$SSH_PORT" \
			"$src_file" \
			"${SSH_USERNAME}@${TARGET_IP}:${dest_path}"
	elif [[ $use_expect -eq 1 ]]; then
		# Use expect script
		expect <<EOF
set timeout $SSH_TIMEOUT
spawn scp $scp_opts -P $SSH_PORT "$src_file" ${SSH_USERNAME}@${TARGET_IP}:${dest_path}
expect {
	"password:" {
		send "$SSH_PASSWORD\r"
		exp_continue
	}
	"yes/no" {
		send "yes\r"
		exp_continue
	}
	eof
}
EOF
	else
		# Manual entry fallback
		scp \
			$scp_opts \
			-P "$SSH_PORT" \
			"$src_file" \
			"${SSH_USERNAME}@${TARGET_IP}:${dest_path}"
	fi
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
	log_info "UDM VPN Monitor Deployment"
	log_info "=================================="
	echo ""

	# Parse arguments
	parse_args "$@"

	# Validate parameters
	validate_params

	# Display deployment plan
	log_info "Deployment Plan:"
	echo "  Package file:    $PACKAGE_FILE"
	echo "  Target UDM:      ${SSH_USERNAME}@${TARGET_IP}:${SSH_PORT}"
	echo "  Bind address:    ${BIND_IP:-<default>}"
	echo "  Uninstall:       $([ $SKIP_UNINSTALL -eq 1 ] && echo "Skip" || echo "Yes")"
	if [[ $SKIP_UNINSTALL -eq 0 ]]; then
		echo "    Keep config:   $KEEP_CONFIG"
		echo "    Remove state:  $REMOVE_STATE"
		echo "    Remove logs:   $REMOVE_LOGS"
	fi
	echo "  Log lines:       $LOG_LINES"
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

	# Summary
	log_success "Deployment completed successfully!"
	echo ""
	log_info "Next steps:"
	echo "  1. Verify installation: ssh ${SSH_USERNAME}@${TARGET_IP} 'ls -la /data/vpn-monitor/'"
	echo "  2. Check configuration: ssh ${SSH_USERNAME}@${TARGET_IP} 'cat /data/vpn-monitor/vpn-monitor.conf'"
	echo "  3. Monitor logs: ssh ${SSH_USERNAME}@${TARGET_IP} 'tail -f /data/vpn-monitor/logs/vpn-monitor.log'"
	echo ""
}

# Run main function
main "$@"
