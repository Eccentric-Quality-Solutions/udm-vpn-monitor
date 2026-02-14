#!/bin/bash
#
# UDM VPN Monitor Batch Deployment Script
# Deploys the VPN monitor to multiple UDMs from a config file.
#
# For each UDM:
# 1. Calls deploy-to-udm.sh (which prompts for username/password)
# 2. SCP package, archive logs, uninstall (keep config), extract, install
# 3. deploy-to-udm.sh runs tail -f on vpn-monitor.log until Ctrl+C (uses same credentials)
# 4. Continues to next UDM
# 5. Logs deployment output to REPO_ROOT/logs/deploy-to-udms.log
#
# Usage:
#   ./scripts/deploy-to-udms.sh [OPTIONS]
#
# Options:
#   --config FILE    Config file with UDM list (default: deploy-udms.conf)
#   --file PACKAGE   Package file to deploy (default: udm-vpn-monitor.zip)
#   --skip-tail      Skip interactive tail -f after each deployment
#   --force          Deploy even if registry shows host already at this version
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
LOGS_DIR="${REPO_ROOT}/logs"
DEPLOY_LOG_FILE="${DEPLOY_LOG_FILE:-${LOGS_DIR}/deploy-to-udms.log}"
CONFIG_FILE="${REPO_ROOT}/deploy-udms.conf"
PACKAGE_FILE="${REPO_ROOT}/udm-vpn-monitor.zip"
SKIP_TAIL=0
FORCE_DEPLOY=0

# Source deployment registry helpers
# shellcheck source=scripts/deploy-registry.sh
if [[ -f "${SCRIPT_DIR}/deploy-registry.sh" ]]; then
	# shellcheck source=scripts/deploy-registry.sh
	source "${SCRIPT_DIR}/deploy-registry.sh"
fi

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

# Append message to deploy log file.
#
# Arguments:
#   $1: level - INFO, SUCCESS, WARN, ERROR
#   $2+: message parts (concatenated)
#
# Returns:
#   0: Always (write failures are ignored)
deploy_log_write() {
	local level="$1"
	shift
	local msg="$*"
	mkdir -p "$(dirname "$DEPLOY_LOG_FILE")" 2>/dev/null || true
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $msg" >>"$DEPLOY_LOG_FILE" 2>/dev/null || true
}

# Logging helpers (write to stderr and append to deploy log file).
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
  --force          Deploy even if registry shows host already at this version
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
		--force)
			FORCE_DEPLOY=1
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

	mkdir -p "$(dirname "$DEPLOY_LOG_FILE")" 2>/dev/null || true

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

	# Get package version for skip/record logic
	local pkg_version=""
	if command -v get_package_version >/dev/null 2>&1; then
		pkg_version=$(get_package_version "$PACKAGE_FILE" 2>/dev/null) || true
	fi

	log_info "UDM VPN Monitor Batch Deployment"
	log_info "Logging to: $DEPLOY_LOG_FILE"
	log_info "=================================="
	log_info "Config: $CONFIG_FILE"
	log_info "Package: $PACKAGE_FILE"
	log_info "UDMs: ${#udms[@]}"
	[[ -n "$pkg_version" ]] && log_info "Package version: $pkg_version"
	echo ""

	local success_count=0
	local fail_count=0
	local skip_count=0

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

		# Skip if already at this version (unless --force)
		if [[ $FORCE_DEPLOY -eq 0 ]] && [[ -n "$pkg_version" ]] && command -v host_has_version >/dev/null 2>&1; then
			if host_has_version "$host" "$pkg_version"; then
				log_info "----------------------------------------"
				log_info "Skipping $host (already at version $pkg_version)"
				skip_count=$((skip_count + 1))
				echo ""
				continue
			fi
		fi

		log_info "----------------------------------------"
		log_info "Deploying to: $host"
		echo ""

		local deploy_args=(
			--file "$PACKAGE_FILE"
			--target-ip "$host"
			--append-missing-config
		)
		[[ -n "$bind_ip" ]] && deploy_args+=(--bind-ip "$bind_ip")

		# When tail -f will run, use --no-record and --tail-follow; we record only after user confirms
		if [[ $SKIP_TAIL -eq 0 ]]; then
			deploy_args+=(--no-record --tail-follow)
		fi

		if "${SCRIPT_DIR}/deploy-to-udm.sh" "${deploy_args[@]}"; then
			success_count=$((success_count + 1))
			if [[ $SKIP_TAIL -eq 0 ]]; then
				# Record only when user confirms yes; n = no record; invalid = re-prompt
				if [[ -n "$pkg_version" ]] && command -v record_deployment >/dev/null 2>&1; then
					echo ""
					local response
					while true; do
						if ! read -r -p "Deployment to $host completed. Mark as successful? (y/n): " response 2>/dev/null; then
							break
						fi
						if [[ "$response" =~ ^[yY] ]]; then
							record_deployment "$host" "$pkg_version" 2>/dev/null || true
							break
						fi
						if [[ "$response" =~ ^[nN] ]]; then
							break
						fi
						echo "Please enter y or n."
					done
				fi
			fi
		else
			fail_count=$((fail_count + 1))
			log_error "Deployment failed for $host"
		fi
		echo ""
	done

	log_info "=================================="
	if [[ $skip_count -gt 0 ]]; then
		log_info "Deployment summary: ${success_count} succeeded, ${fail_count} failed, ${skip_count} skipped (already at version)"
	else
		log_info "Deployment summary: ${success_count} succeeded, ${fail_count} failed"
	fi
	[[ $fail_count -gt 0 ]] && exit 1
	exit 0
}

main "$@"
