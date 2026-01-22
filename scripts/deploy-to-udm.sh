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
#   --bind-ip IP             Source IP address for BindAddress (required)
#   --username USER          SSH username (default: root)
#   --password PASS          SSH password (required, or use --password-file)
#   --password-file FILE     File containing SSH password (alternative to --password)
#   --ssh-port PORT          SSH port (default: 22)
#   --keep-config            Keep existing config during uninstall (default: yes)
#   --remove-state           Remove state directory during uninstall (default: yes)
#   --remove-logs            Remove logs directory during uninstall (default: yes)
#   --skip-uninstall         Skip uninstall step (for fresh installs)
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

# Logging functions
log_info() {
	echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_verbose() {
	if [[ $VERBOSE -eq 1 ]]; then
		echo -e "${BLUE}[VERBOSE]${NC} $*" >&2
	fi
}

# Display help message
display_help() {
	cat <<EOF
Usage: $0 [OPTIONS]

Deploy UDM VPN Monitor to a remote UDM via SSH/SCP.

Required Options:
  --target-ip IP           Target UDM IP address
  --bind-ip IP             Source IP address for BindAddress

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

# Parse command-line arguments
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

# Validate required parameters
validate_params() {
	local errors=0

	if [[ -z "$TARGET_IP" ]]; then
		log_error "Target IP address is required (--target-ip)"
		errors=$((errors + 1))
	fi

	if [[ -z "$BIND_IP" ]]; then
		log_error "Bind IP address is required (--bind-ip)"
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

	if [[ $errors -gt 0 ]]; then
		echo ""
		display_help
		exit 1
	fi
}

# Check if sshpass is available
check_sshpass() {
	if command -v sshpass >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

# Check if expect is available
check_expect() {
	if command -v expect >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

# Execute SSH command with password authentication
# Uses sshpass if available, otherwise falls back to expect or manual entry
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

	if [[ $use_sshpass -eq 1 ]]; then
		# Use sshpass (password passed via environment variable to avoid ps exposure)
		SSHPASS="$SSH_PASSWORD" sshpass -e ssh \
			-o StrictHostKeyChecking=no \
			-o UserKnownHostsFile=/dev/null \
			-o ConnectTimeout="$SSH_TIMEOUT" \
			-p "$SSH_PORT" \
			"${SSH_USERNAME}@${TARGET_IP}" \
			"$cmd"
	elif [[ $use_expect -eq 1 ]]; then
		# Use expect script
		expect <<EOF
set timeout $SSH_TIMEOUT
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=$SSH_TIMEOUT -p $SSH_PORT ${SSH_USERNAME}@${TARGET_IP} "$cmd"
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
			-o StrictHostKeyChecking=no \
			-o UserKnownHostsFile=/dev/null \
			-o ConnectTimeout="$SSH_TIMEOUT" \
			-p "$SSH_PORT" \
			"${SSH_USERNAME}@${TARGET_IP}" \
			"$cmd"
	fi
}

# Execute SCP command with password authentication
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

	if [[ $use_sshpass -eq 1 ]]; then
		# Use sshpass (password passed via environment variable)
		SSHPASS="$SSH_PASSWORD" sshpass -e scp \
			-o StrictHostKeyChecking=no \
			-o UserKnownHostsFile=/dev/null \
			-o ConnectTimeout="$SSH_TIMEOUT" \
			-o BindAddress="$BIND_IP" \
			-P "$SSH_PORT" \
			"$src_file" \
			"${SSH_USERNAME}@${TARGET_IP}:${dest_path}"
	elif [[ $use_expect -eq 1 ]]; then
		# Use expect script
		expect <<EOF
set timeout $SSH_TIMEOUT
spawn scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=$SSH_TIMEOUT -o BindAddress=$BIND_IP -P $SSH_PORT "$src_file" ${SSH_USERNAME}@${TARGET_IP}:${dest_path}
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
			-o StrictHostKeyChecking=no \
			-o UserKnownHostsFile=/dev/null \
			-o ConnectTimeout="$SSH_TIMEOUT" \
			-o BindAddress="$BIND_IP" \
			-P "$SSH_PORT" \
			"$src_file" \
			"${SSH_USERNAME}@${TARGET_IP}:${dest_path}"
	fi
}

# Main deployment function
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
	echo "  Bind address:    $BIND_IP"
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

	# Step 2: Uninstall (if not skipped)
	if [[ $SKIP_UNINSTALL -eq 0 ]]; then
		log_info "Step 2: Uninstalling existing installation (if present)..."
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

	# Step 3: Extract package
	log_info "Step 3: Extracting package on target UDM..."
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

	# Step 4: Install
	log_info "Step 4: Installing VPN Monitor..."
	local install_cmd="cd /tmp && chmod +x install.sh && ./install.sh --silent"
	# Don't overwrite config if it exists (default behavior of --silent)
	# If we want to overwrite, we would use --overwrite-conf, but user requested not to

	if execute_ssh "$install_cmd"; then
		log_success "Installation completed successfully"
	else
		log_error "Installation failed"
		exit 1
	fi
	echo ""

	# Step 5: Display recent log output
	log_info "Step 5: Displaying last $LOG_LINES lines of log file..."
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
