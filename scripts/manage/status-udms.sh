#!/bin/bash
#
# Fleet UDM VPN Monitor Status
# SSH to one or more UDMs and report live version, mode, cron, and registry drift.
#
# Usage:
#   ./scripts/manage/status-udms.sh [OPTIONS]
#
# Examples:
#   ./scripts/manage/status-udms.sh
#   ./scripts/manage/status-udms.sh --config deploy-udms.conf
#   ./scripts/manage/status-udms.sh --host 192.168.1.100
#   ./scripts/manage/status-udms.sh --dry-run --config control-udms.conf
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=lib/common.sh
if [[ -f "${REPO_ROOT}/lib/common.sh" ]]; then
	source "${REPO_ROOT}/lib/common.sh"
fi

# shellcheck source=scripts/manage/lib/ssh_control.sh
source "${SCRIPT_DIR}/lib/ssh_control.sh"
# shellcheck source=scripts/manage/deploy-registry.sh
source "${SCRIPT_DIR}/deploy-registry.sh"

manage_init_terminal_colors

REMOTE_INSTALL_DIR="/data/vpn-monitor"
REMOTE_MONITOR_SCRIPT="${REMOTE_INSTALL_DIR}/vpn-monitor.sh"
REMOTE_CONTROL_SCRIPT="${REMOTE_INSTALL_DIR}/vpn-monitor-control.sh"
REMOTE_CRONTAB_PATH="/var/spool/cron/crontabs/root"

CONFIG_FILE=""
CONFIG_EXPLICIT=0
TARGET_HOST=""
BIND_IP=""
SSH_USERNAME="root"
SSH_PASSWORD=""
SSH_PORT=22
SSH_TIMEOUT=30
CONTROL_SOCKET=""
DRY_RUN=0

STAT_TOTAL=0
STAT_REACHABLE=0
STAT_INSTALLED=0
STAT_NOT_INSTALLED=0
STAT_UNREACHABLE=0
STAT_REGISTRY_DRIFT=0
STAT_FAIL_COUNT=0

log_info() { manage_log_info "$@"; }
log_success() { manage_log_success "$@"; }
log_warn() { manage_log_warn "$@"; }
log_error() { manage_log_error "$@"; }

display_help() {
	cat <<EOF
Usage: $0 [OPTIONS]

Report live VPN Monitor status across UDM devices via SSH.

Options:
  --host HOST       Target UDM IP or hostname (single host mode)
  --config FILE     Fleet config file (default: deploy-udms.conf, else control-udms.conf)
  --bind-ip IP      Source IP for SSH BindAddress
  --username USER   SSH username (default: root)
  --port PORT       SSH port (default: 22)
  --timeout SEC     SSH timeout seconds (default: 30)
  --dry-run         Print remote probe commands without executing SSH
  --help            Show this help

Output columns (tab-separated):
  HOST  VERSION  MODE  CRON  REGISTRY_VERSION  REGISTRY_TIME  REGISTRY_MATCH

REGISTRY_MATCH values: match, drift, no_registry, n/a (not installed)

Examples:
  $0
  $0 --config deploy-udms.conf
  $0 --host 192.168.1.100
  $0 --dry-run --config control-udms.conf
EOF
}

# Build remote shell command that prints version, control status, and cron probe.
#
# Output:
#   Remote command string for execute_ssh_control
build_remote_probe_command() {
	cat <<EOF
MONITOR='${REMOTE_MONITOR_SCRIPT}'; CONTROL='${REMOTE_CONTROL_SCRIPT}'; CRONTAB='${REMOTE_CRONTAB_PATH}'; if [[ -f "\$MONITOR" ]]; then grep '^SCRIPT_VERSION=' "\$MONITOR" | head -1; else echo 'SCRIPT_VERSION='; fi; if [[ -x "\$CONTROL" ]]; then "\$CONTROL" status; else echo 'Operating mode: not installed'; echo 'Cron: n/a'; fi; if grep -q vpn-monitor "\$CRONTAB" 2>/dev/null; then echo 'CRON_PRESENT=yes'; else echo 'CRON_PRESENT=no'; fi
EOF
}

# Parse combined remote probe output into version, mode, and cron fields.
#
# Arguments:
#   $1: probe_output (string)
#
# Side effects:
#   Sets PARSED_VERSION, PARSED_MODE, PARSED_CRON
parse_probe_output() {
	local output="$1"
	local line version cron_present="no"

	PARSED_VERSION=""
	PARSED_MODE=""
	PARSED_CRON="no"

	while IFS= read -r line || [[ -n "$line" ]]; do
		if [[ "$line" =~ ^SCRIPT_VERSION= ]]; then
			case "$line" in
			SCRIPT_VERSION= | SCRIPT_VERSION=\"\" | SCRIPT_VERSION=\'\') ;;
			*)
				if version=$(parse_script_version_line "$line" 2>/dev/null); then
					PARSED_VERSION="$version"
				fi
				;;
			esac
		elif [[ "$line" =~ ^Operating\ mode:\ (.+)$ ]]; then
			PARSED_MODE="${BASH_REMATCH[1]}"
		elif [[ "$line" =~ ^CRON_PRESENT=(yes|no)$ ]]; then
			cron_present="${BASH_REMATCH[1]}"
		fi
	done <<<"$output"

	PARSED_CRON="$cron_present"
}

# Look up deploy registry row and compute drift marker.
#
# Arguments:
#   $1: host
#   $2: live_version (empty if not installed)
#
# Side effects:
#   Sets REGISTRY_VERSION, REGISTRY_TIME, REGISTRY_MATCH
lookup_registry_status() {
	local host="$1"
	local live_version="$2"
	local info

	REGISTRY_VERSION=""
	REGISTRY_TIME=""
	REGISTRY_MATCH="n/a"

	if [[ -z "$live_version" ]]; then
		if info=$(get_deployed_info "$host" 2>/dev/null); then
			REGISTRY_VERSION=$(echo "$info" | cut -f1)
			REGISTRY_TIME=$(echo "$info" | cut -f2)
		fi
		return 0
	fi

	if ! info=$(get_deployed_info "$host" 2>/dev/null); then
		REGISTRY_MATCH="no_registry"
		return 0
	fi

	REGISTRY_VERSION=$(echo "$info" | cut -f1)
	REGISTRY_TIME=$(echo "$info" | cut -f2)
	if [[ "$REGISTRY_VERSION" == "$live_version" ]]; then
		REGISTRY_MATCH="match"
	else
		REGISTRY_MATCH="drift"
	fi
}

# Print one tab-separated status row to stdout.
#
# Arguments:
#   $1-$7: column values
print_status_row() {
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$1" "$2" "$3" "$4" "$5" "$6" "$7"
}

# Resolve fleet config path when --config was not passed explicitly.
#
# Returns:
#   0: CONFIG_FILE set
#   1: No config available
resolve_fleet_config() {
	if [[ $CONFIG_EXPLICIT -eq 1 ]]; then
		if [[ ! -f "$CONFIG_FILE" ]]; then
			log_error "Config file not found: $CONFIG_FILE"
			return 1
		fi
		return 0
	fi

	if [[ -f "${REPO_ROOT}/deploy-udms.conf" ]]; then
		CONFIG_FILE="${REPO_ROOT}/deploy-udms.conf"
		return 0
	fi
	if [[ -f "${REPO_ROOT}/control-udms.conf" ]]; then
		CONFIG_FILE="${REPO_ROOT}/control-udms.conf"
		return 0
	fi

	log_error "No fleet config found. Create deploy-udms.conf or control-udms.conf, or pass --config FILE"
	return 1
}

# Collect status from one host; print dry-run line and table row to stdout.
#
# Arguments:
#   $1: target host
#
# Returns:
#   0: Host reachable and probe succeeded (or dry-run)
#   1: Host unreachable or probe failed
collect_status_on_host() {
	local host="$1"
	local remote_cmd probe_output bind_label=""
	local version_display mode cron

	[[ -n "${BIND_IP:-}" ]] && bind_label=" bind=${BIND_IP}"
	remote_cmd=$(build_remote_probe_command)

	if [[ $DRY_RUN -eq 1 ]]; then
		echo "[dry-run] ${host}${bind_label}: ${remote_cmd}"
		print_status_row "$host" "dry-run" "-" "-" "-" "-" "-"
		return 0
	fi

	collect_ssh_credentials_if_needed "$host" || {
		print_status_row "$host" "UNREACHABLE" "-" "-" "-" "-" "-"
		return 1
	}

	if ! setup_ssh_control_master "$host"; then
		print_status_row "$host" "UNREACHABLE" "-" "-" "-" "-" "-"
		return 1
	fi

	if ! probe_output=$(execute_ssh_control "$host" "$remote_cmd" 2>/dev/null); then
		print_status_row "$host" "ERROR" "-" "-" "-" "-" "-"
		return 1
	fi

	parse_probe_output "$probe_output"
	if [[ -n "$PARSED_VERSION" ]]; then
		version_display="$PARSED_VERSION"
	else
		version_display="not installed"
	fi
	mode="${PARSED_MODE:--}"
	cron="${PARSED_CRON:-no}"

	lookup_registry_status "$host" "$PARSED_VERSION"
	print_status_row "$host" "$version_display" "$mode" "$cron" \
		"${REGISTRY_VERSION:--}" "${REGISTRY_TIME:--}" "$REGISTRY_MATCH"
	return 0
}

# Update summary counters after processing one host row.
#
# Arguments:
#   $1: version column value
#   $2: registry_match value
#   $3: host_ok (0 success, 1 failure)
update_summary_counts() {
	local version_col="$1"
	local registry_match="$2"
	local host_ok="$3"

	STAT_TOTAL=$((STAT_TOTAL + 1))
	if [[ $host_ok -ne 0 ]]; then
		STAT_FAIL_COUNT=$((STAT_FAIL_COUNT + 1))
		if [[ "$version_col" == "UNREACHABLE" ]] || [[ "$version_col" == "ERROR" ]]; then
			STAT_UNREACHABLE=$((STAT_UNREACHABLE + 1))
		fi
		return 0
	fi

	STAT_REACHABLE=$((STAT_REACHABLE + 1))
	if [[ "$version_col" == "not installed" ]]; then
		STAT_NOT_INSTALLED=$((STAT_NOT_INSTALLED + 1))
	elif [[ "$version_col" != "dry-run" ]]; then
		STAT_INSTALLED=$((STAT_INSTALLED + 1))
	fi

	if [[ "$registry_match" == "drift" ]] || [[ "$registry_match" == "no_registry" ]]; then
		STAT_REGISTRY_DRIFT=$((STAT_REGISTRY_DRIFT + 1))
	fi
}

# Print fleet summary to stderr.
print_summary() {
	log_info "Summary: ${STAT_TOTAL} host(s), ${STAT_REACHABLE} reachable, ${STAT_INSTALLED} installed, ${STAT_NOT_INSTALLED} not installed, ${STAT_UNREACHABLE} unreachable, ${STAT_REGISTRY_DRIFT} registry drift"
	if [[ $STAT_FAIL_COUNT -gt 0 ]]; then
		log_warn "${STAT_FAIL_COUNT} host(s) failed"
	fi
}

# Process one host: collect status, print output, update counters.
#
# Arguments:
#   $1: target host
process_host() {
	local host="$1"
	local output row version_col registry_match host_ok=0

	if ! output=$(collect_status_on_host "$host"); then
		host_ok=1
	fi

	echo "$output"

	row=$(echo "$output" | awk -F'\t' 'NF >= 7 {line=$0} END {print line}')
	if [[ -n "$row" ]]; then
		version_col=$(echo "$row" | cut -f2)
		registry_match=$(echo "$row" | cut -f7)
		update_summary_counts "$version_col" "$registry_match" "$host_ok"
	fi
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--host)
			TARGET_HOST="$2"
			shift 2
			;;
		--config)
			CONFIG_FILE="$2"
			CONFIG_EXPLICIT=1
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

	local default_bind_ip="${BIND_IP:-}"
	local entry host_ip host_bind

	echo -e "HOST\tVERSION\tMODE\tCRON\tREGISTRY_VERSION\tREGISTRY_TIME\tREGISTRY_MATCH"

	if [[ -n "$TARGET_HOST" ]]; then
		process_host "$TARGET_HOST"
		echo ""
		print_summary
		[[ $STAT_FAIL_COUNT -eq 0 ]]
		return
	fi

	resolve_fleet_config || exit 1

	local -a hosts=()
	read_manage_host_config "$CONFIG_FILE" hosts

	if [[ ${#hosts[@]} -eq 0 ]]; then
		log_error "No hosts in config: $CONFIG_FILE"
		exit 1
	fi

	log_info "Fleet status for ${#hosts[@]} host(s) from ${CONFIG_FILE}"
	echo ""

	local saved_password="${SSH_PASSWORD:-}"
	local first_host="${hosts[0]%% *}"
	if [[ $DRY_RUN -eq 0 ]]; then
		collect_ssh_credentials_if_needed "$first_host" || exit 1
		saved_password="${SSH_PASSWORD:-}"
	fi

	for entry in "${hosts[@]}"; do
		host_ip="${entry%% *}"
		host_bind=""
		if [[ "$entry" == *" "* ]]; then
			host_bind="${entry#* }"
			host_bind="${host_bind%% *}"
		fi
		reset_ssh_between_hosts
		SSH_PASSWORD="$saved_password"
		if [[ -n "$host_bind" ]]; then
			BIND_IP="$host_bind"
		else
			BIND_IP="$default_bind_ip"
		fi
		process_host "$host_ip"
		echo ""
	done
	reset_ssh_between_hosts

	print_summary
	[[ $STAT_FAIL_COUNT -eq 0 ]]
}

main "$@"
