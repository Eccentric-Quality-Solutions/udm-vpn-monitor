#!/bin/bash
#
# Centralize VPN Monitor logs from multiple UDMs
#
# Reads a list of IPs from a conf file. The first IP is used as BindAddress
# for SCP; the remaining IPs are targets. For each target, fetches
# /data/vpn-monitor/logs/vpn-monitor.log into /tmp/centralize-logs/, then
# zips all collected logs and removes the loose .log files.
#
# Usage:
#   ./scripts/manage/centralize-logs.sh
#
# Conf file: centralize-logs-ips.conf in the same directory as this script.
# Copy centralize-logs-ips.conf.example to centralize-logs-ips.conf and edit.
#
# Authentication:
#   SCP will prompt for password or SSH key passphrase as needed. To avoid
#   repeated prompts, use ssh-agent and ssh-add before running this script.
#
# Conf file format:
#   One IP per line. Lines starting with # and blank lines are ignored.
#   First non-comment IP = BindAddress; remaining IPs = targets to fetch from.
#
# Output:
#   /tmp/centralize-logs/all-vpn-logs-YYYY-MM-DD-HHMMSS.zip
#   /tmp/centralize-logs/still-running (one line per target: "IP cron_ok" or "IP reinstall_needed";
#   derived by SCP-pulling each UDM's root crontab, checking locally, then deleting the temp crontab files)
#
# Returns:
#   0: All targets fetched and zip created (or no targets)
#   1: Missing conf file or no IPs in conf
#   2: One or more SCP failures
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/centralize-logs-ips.conf"
REMOTE_LOG_PATH="/data/vpn-monitor/logs/vpn-monitor.log"
# Root's crontab on most Linux/UDM (install.sh uses crontab - so job lives here)
REMOTE_CRONTAB_PATH="/var/spool/cron/crontabs/root"
OUTPUT_DIR="/tmp/centralize-logs"
STILL_RUNNING_FILE="${OUTPUT_DIR}/still-running"
SCP_CONNECT_TIMEOUT=30

# Print usage to stderr and exit with code 1.
#
# Arguments:
#   None
#
# Returns:
#   Does not return (exits with 1)
#
# Side effects:
#   Prints usage to stderr, then exits
usage() {
	cat <<-EOF >&2
		Usage: $(basename "$0")
		Reads centralize-logs-ips.conf from the script directory.
		First IP in conf = BindAddress; remaining IPs = UDMs to fetch logs from.
		SCP will prompt for password or key passphrase as needed.
	EOF
	exit 1
}

# Parse conf file: strip comments and blank lines, output one IP per line.
#
# Arguments:
#   $1: conf_path (string) - path to the IP list conf file
#
# Returns:
#   0: file exists and is readable; IP lines printed to stdout
#   1: file missing or unreadable
#
read_ips_from_conf() {
	local conf="$1"
	[[ -f "$conf" ]] || return 1
	grep -v '^[[:space:]]*#' "$conf" | grep -v '^[[:space:]]*$' || true
}

# Main entry point: read conf, fetch logs from UDMs, zip results.
#
# Parses centralize-logs-ips.conf, fetches vpn-monitor.log from each target UDM via SCP,
# zips collected logs to /tmp/centralize-logs/all-vpn-logs-YYYY-MM-DD-HHMMSS.zip,
# and removes loose .log files.
#
# Arguments:
#   $@: Command-line arguments (-h/--help triggers usage)
#
# Returns:
#   0: Success (all targets fetched or no targets)
#   1: Missing conf file or no IPs in conf
#   2: One or more SCP failures
#
# Side effects:
#   Creates OUTPUT_DIR, fetches files, creates zip, removes .log files
main() {
	[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

	if [[ ! -f "$CONF_FILE" ]]; then
		echo "Error: conf file not found: $CONF_FILE" >&2
		echo "Copy centralize-logs-ips.conf.example to centralize-logs-ips.conf and edit." >&2
		exit 1
	fi

	local ips
	ips=$(read_ips_from_conf "$CONF_FILE") || true
	if [[ -z "${ips// /}" ]]; then
		echo "Error: no IPs found in $CONF_FILE" >&2
		exit 1
	fi

	local bind_ip=""
	local target_ips=()
	local first=1
	while IFS= read -r line; do
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"
		[[ -z "$line" ]] && continue
		if [[ $first -eq 1 ]]; then
			bind_ip="$line"
			first=0
		else
			target_ips+=("$line")
		fi
	done <<<"$ips"

	if [[ $first -eq 1 ]]; then
		echo "Error: no valid IP in $CONF_FILE" >&2
		exit 1
	fi

	if [[ ${#target_ips[@]} -eq 0 ]]; then
		echo "No target IPs (only BindAddress $bind_ip). Nothing to fetch." >&2
		exit 0
	fi

	mkdir -p "$OUTPUT_DIR"
	{
		echo "# Crontab status per target UDM (crontab file pulled via SCP, checked locally, temp files removed)."
		echo "# Format: IP cron_ok | IP reinstall_needed"
	} >"$STILL_RUNNING_FILE"
	local scp_failed=0
	local scp_opts=(-o "ConnectTimeout=$SCP_CONNECT_TIMEOUT" -o "StrictHostKeyChecking=ask")
	[[ -n "$bind_ip" ]] && scp_opts+=(-o "BindAddress=$bind_ip")

	for ip in "${target_ips[@]}"; do
		local dest="${OUTPUT_DIR}/vpn-monitor-${ip}.log"
		echo "Fetching $REMOTE_LOG_PATH from root@${ip} -> $dest"
		if ! scp "${scp_opts[@]}" "root@${ip}:${REMOTE_LOG_PATH}" "$dest"; then
			echo "Warning: SCP failed for $ip" >&2
			scp_failed=1
			[[ -f "$dest" ]] && rm -f "$dest"
		fi
		# Pull root crontab from this UDM via SCP (no SSH command execution); check locally for vpn-monitor job.
		local crontab_local="${OUTPUT_DIR}/crontab-${ip}.tmp"
		local status="reinstall_needed"
		if scp "${scp_opts[@]}" "root@${ip}:${REMOTE_CRONTAB_PATH}" "$crontab_local" 2>/dev/null; then
			if grep -q "vpn-monitor" "$crontab_local" 2>/dev/null; then
				status="cron_ok"
			fi
		fi
		rm -f "$crontab_local"
		echo "${ip} ${status}" >>"$STILL_RUNNING_FILE"
	done

	local log_count=0
	for ip in "${target_ips[@]}"; do
		[[ -f "${OUTPUT_DIR}/vpn-monitor-${ip}.log" ]] && log_count=$((log_count + 1))
	done

	if [[ $log_count -eq 0 ]]; then
		echo "No logs collected. Skipping zip." >&2
		exit 2
	fi

	local stamp
	stamp=$(date +%Y-%m-%d-%H%M%S)
	local zip_name="all-vpn-logs-${stamp}.zip"
	local zip_path="${OUTPUT_DIR}/${zip_name}"

	# Create zip from collected logs only (cd so zip stores relative names).
	(
		cd "$OUTPUT_DIR"
		zip -q "$zip_name" vpn-monitor-*.log
	)
	echo "Created $zip_path"
	echo "Crontab status per host: $STILL_RUNNING_FILE"

	# Remove only the collected .log files (not the zip).
	for ip in "${target_ips[@]}"; do
		local f="${OUTPUT_DIR}/vpn-monitor-${ip}.log"
		[[ -f "$f" ]] && rm -f "$f"
	done

	if [[ $scp_failed -eq 1 ]]; then
		exit 2
	fi
	exit 0
}

main "$@"
