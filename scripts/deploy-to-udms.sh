#!/bin/bash
#
# UDM VPN Monitor Batch Deployment Script
# Deploys the VPN monitor to multiple UDMs from a config file.
#
# For each UDM:
# 1. Calls deploy-to-udm.sh (which prompts for username/password)
# 2. SCP package, archive logs, uninstall (keep config), extract, install
# 3. Runs tail -f on vpn-monitor.log until user presses Ctrl+C (ssh may prompt for password)
# 4. Continues to next UDM
#
# Usage:
#   ./scripts/deploy-to-udms.sh [OPTIONS]
#
# Options:
#   --config FILE    Config file with UDM list (default: deploy-udms.conf)
#   --file PACKAGE   Package file to deploy (default: udm-vpn-monitor.zip)
#   --skip-tail      Skip interactive tail -f after each deployment
#   --help           Show this help message
#
# Config format (one target per line):
#   host_or_ip [bind_ip]
#
# See scripts/deploy-udms.conf.example for details.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/deploy-udms.conf"
PACKAGE_FILE="${REPO_ROOT}/udm-vpn-monitor.zip"
SKIP_TAIL=0

# Colors
if [[ -t 1 ]]; then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[1;33m'
	BLUE='\033[0;34m'
	NC='\033[0m'
else
	RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

# Logging helpers (write prefixed message to stderr).
log_info() { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
# Log success message to stderr.
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*" >&2; }
# Log warning message to stderr.
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
# Log error message to stderr.
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Resolve bind IP from LOCAL_UDM_IP in vpn-monitor.conf when not explicitly set.
#
# Arguments:
#   None (reads config paths internally).
#
# Returns:
#   0: Bind IP resolved and printed to stdout
#   1: No config found or LOCAL_UDM_IP not set
resolve_bind_ip_from_config() {
	local config_paths=(
		"/data/vpn-monitor/vpn-monitor.conf"
		"${REPO_ROOT}/vpn-monitor.conf"
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

# Print usage and options to stdout.
#
# Arguments:
#   None
#
# Returns:
#   0: Always
display_help() {
	cat <<EOF
Usage: $0 [OPTIONS]

Deploy UDM VPN Monitor to multiple UDMs from a config file.

Options:
  --config FILE    Config file with UDM list (default: deploy-udms.conf)
  --file PACKAGE   Package file to deploy (default: udm-vpn-monitor.zip)
  --skip-tail      Skip interactive tail -f after each deployment
  --help           Show this help message

Config format: host_or_ip [bind_ip]
If bind_ip omitted, uses LOCAL_UDM_IP from vpn-monitor.conf.
See scripts/deploy-udms.conf.example for details.
EOF
}

# Parse command-line arguments and set CONFIG_FILE, PACKAGE_FILE, SKIP_TAIL.
#
# Arguments:
#   $@: Command-line arguments
#
# Returns:
#   0: Success (or exits 0 on --help)
#   Exits 1 on unknown option
parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--config)
			CONFIG_FILE="$2"
			shift 2
			;;
		--file)
			PACKAGE_FILE="$2"
			shift 2
			;;
		--skip-tail)
			SKIP_TAIL=1
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

# Ensure package file exists; run prepare_install_package.sh if missing.
#
# Arguments:
#   None (uses global PACKAGE_FILE, SCRIPT_DIR, REPO_ROOT).
#
# Returns:
#   0: Package exists or was created
#   1: Package missing and could not be created
ensure_package() {
	if [[ -f "$PACKAGE_FILE" ]]; then
		return 0
	fi
	log_info "Package not found: $PACKAGE_FILE"
	if [[ -f "${SCRIPT_DIR}/prepare_install_package.sh" ]]; then
		log_info "Running prepare_install_package.sh..."
		if (cd "$REPO_ROOT" && ./scripts/prepare_install_package.sh); then
			if [[ -f "$PACKAGE_FILE" ]]; then
				log_success "Package created: $PACKAGE_FILE"
				return 0
			fi
		fi
	fi
	log_error "Package not found and could not create it: $PACKAGE_FILE"
	return 1
}

# Run tail -f on vpn-monitor.log on remote UDM (interactive until Ctrl+C).
# Uses root@host; ssh will prompt for password if needed.
#
# Arguments:
#   $1: host - Target host or IP
#   $2: bind_ip - Optional bind address for SSH
#
# Returns:
#   Exit code of ssh/tail (or 0 when user interrupts)
run_tail_f() {
	local host="$1"
	local bind_ip="$2"
	local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t"
	[[ -n "$bind_ip" ]] && ssh_opts="$ssh_opts -o BindAddress=$bind_ip"

	log_info "Tailing vpn-monitor.log on root@${host} (Ctrl+C to continue to next UDM)..."
	ssh $ssh_opts "root@${host}" "tail -f /data/vpn-monitor/logs/vpn-monitor.log 2>/dev/null || echo 'Log file not found'"
}

# Main: parse args, ensure package, deploy to each UDM from config.
#
# Arguments:
#   $@: Command-line arguments (passed to parse_args).
#
# Returns:
#   0: All deployments succeeded
#   Exits 1 on config/package error or deployment failure
main() {
	parse_args "$@"

	if [[ ! -f "$CONFIG_FILE" ]]; then
		log_error "Config file not found: $CONFIG_FILE"
		log_info "Copy scripts/deploy-udms.conf.example to deploy-udms.conf and add your UDMs"
		exit 1
	fi

	ensure_package || exit 1

	# Read UDM list (skip comments and blank lines)
	local -a udms=()
	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line%%#*}"
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"
		[[ -z "$line" ]] && continue
		udms+=("$line")
	done <"$CONFIG_FILE"

	if [[ ${#udms[@]} -eq 0 ]]; then
		log_error "No UDMs found in config: $CONFIG_FILE"
		exit 1
	fi

	log_info "UDM VPN Monitor Batch Deployment"
	log_info "=================================="
	log_info "Config: $CONFIG_FILE"
	log_info "Package: $PACKAGE_FILE"
	log_info "UDMs: ${#udms[@]}"
	echo ""

	local success_count=0
	local fail_count=0

	# Resolve default bind IP from vpn-monitor.conf (used when not in deploy config)
	local default_bind_ip=""
	default_bind_ip=$(resolve_bind_ip_from_config 2>/dev/null) || true

	for udm_line in "${udms[@]}"; do
		local host bind_ip
		read -r host bind_ip _ <<<"$udm_line" || true
		host="${host:-}"
		bind_ip="${bind_ip:-}"
		[[ -z "$host" ]] && {
			log_warn "Skipping empty host in config"
			continue
		}
		# Use LOCAL_UDM_IP from vpn-monitor.conf when bind_ip not in deploy config
		[[ -z "$bind_ip" ]] && bind_ip="$default_bind_ip"

		log_info "----------------------------------------"
		log_info "Deploying to: $host"
		echo ""

		local deploy_args=(
			--file "$PACKAGE_FILE"
			--target-ip "$host"
			--append-missing-config
		)
		[[ -n "$bind_ip" ]] && deploy_args+=(--bind-ip "$bind_ip")

		if "${SCRIPT_DIR}/deploy-to-udm.sh" "${deploy_args[@]}"; then
			success_count=$((success_count + 1))
			if [[ $SKIP_TAIL -eq 0 ]]; then
				run_tail_f "$host" "$bind_ip" || true
			fi
		else
			fail_count=$((fail_count + 1))
			log_error "Deployment failed for $host"
		fi
		echo ""
	done

	log_info "=================================="
	log_info "Deployment summary: ${success_count} succeeded, ${fail_count} failed"
	[[ $fail_count -gt 0 ]] && exit 1
	exit 0
}

main "$@"
