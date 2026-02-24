#!/bin/bash
#
# Centralize VPN Monitor logs from multiple UDMs
#
# Reads a conf file of KEY=VALUE lines. BIND=IP sets the source IP for SCP;
# NAME=IP lines are targets. For each target, fetches
# /data/vpn-monitor/logs/vpn-monitor.log into /tmp/centralize-logs/, then
# archives them to a tar.gz and removes the loose .log files.
#
# Usage:
#   ./scripts/manage/centralize-logs.sh
#
# Conf file: centralize.conf in the same directory as this script.
# Copy centralize.conf.example to centralize.conf and edit.
#
# Authentication:
#   SSH/SCP will prompt for password or SSH key passphrase as needed. Uses
#   OpenSSH ControlMaster so you are prompted once per host; both log and
#   crontab are fetched over the same connection. To avoid prompts entirely,
#   use ssh-agent and ssh-add before running this script.
#
# Conf file format:
#   Lines starting with # and blank lines are ignored.
#   BIND=IP - required; source IP for SCP (BindAddress).
#   NAME=IP - target UDM (e.g. NYC=192.168.1.1). Name is shown before each host.
#
# Output:
#   /tmp/centralize-logs/all-vpn-logs-YYYY-MM-DD-HHMMSS.tar.gz
#   /tmp/centralize-logs/still-running (one line per target: "NAME IP cron_ok" or "NAME IP reinstall_needed";
#   derived by SCP-pulling each UDM's root crontab, checking locally, then deleting the temp crontab files)
#
# Returns:
#   0: All targets fetched and archive created (or no targets)
#   1: Missing conf file, no entries, or missing BIND=IP
#   2: One or more SCP failures
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/centralize.conf"
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
		Reads centralize.conf from the script directory.
		Conf: BIND=IP (required), NAME=IP per target. Uses ControlMaster (one prompt per host).
		Requires OpenSSH client. Prompts for password or key passphrase as needed.
	EOF
	exit 1
}

# Parse conf file: strip comments and blank lines, output one line per entry.
#
# Arguments:
#   $1: conf_path (string) - path to the conf file
#
# Returns:
#   0: file exists and is readable; lines printed to stdout
#   1: file missing or unreadable
#
read_lines_from_conf() {
	local conf="$1"
	[[ -f "$conf" ]] || return 1
	grep -v '^[[:space:]]*#' "$conf" | grep -v '^[[:space:]]*$' || true
}

# Parse conf lines into bind_ip and parallel arrays target_names and target_ips.
# Only KEY=VALUE lines are used: BIND=IP sets BindAddress; any other KEY=VALUE is a target (name=KEY, ip=VALUE).
# Lines without '=' are ignored.
#
# Arguments:
#   $1: lines (string) - newline-separated lines from conf
#
# Returns:
#   0: always (caller checks bind_ip and target_ips)
#
# Globals (set by this function):
#   bind_ip: BindAddress IP or empty
#   target_names: array of display names for each target
#   target_ips: array of target IPs
#
parse_conf_entries() {
	local lines="$1"
	bind_ip=""
	target_names=()
	target_ips=()
	while IFS= read -r line; do
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"
		[[ -z "$line" ]] && continue
		[[ "$line" != *"="* ]] && continue
		local key="${line%%=*}"
		local value="${line#*=}"
		key="${key#"${key%%[![:space:]]*}"}"
		key="${key%"${key##*[![:space:]]}"}"
		value="${value#"${value%%[![:space:]]*}"}"
		value="${value%"${value##*[![:space:]]}"}"
		if [[ "${key^^}" == "BIND" ]]; then
			bind_ip="$value"
		else
			target_names+=("$key")
			target_ips+=("$value")
		fi
	done <<<"$lines"
}

# Main entry point: read conf, fetch logs from UDMs, archive results.
#
# Parses centralize.conf, fetches vpn-monitor.log from each target UDM via SCP,
# archives collected logs to /tmp/centralize-logs/all-vpn-logs-YYYY-MM-DD-HHMMSS.tar.gz,
# and removes loose .log files.
#
# Arguments:
#   $@: Command-line arguments (-h/--help triggers usage)
#
# Returns:
#   0: Success (all targets fetched or no targets)
#   1: Missing conf file, no entries, or missing BIND=IP
#   2: One or more SCP failures
#
# Side effects:
#   Creates OUTPUT_DIR, fetches files, creates tar.gz archive, removes .log files
main() {
	[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

	if [[ ! -f "$CONF_FILE" ]]; then
		echo "Error: conf file not found: $CONF_FILE" >&2
		echo "Copy centralize.conf.example to centralize.conf and edit." >&2
		exit 1
	fi

	local lines
	lines=$(read_lines_from_conf "$CONF_FILE") || true
	if [[ -z "${lines// /}" ]]; then
		echo "Error: no entries found in $CONF_FILE" >&2
		exit 1
	fi

	parse_conf_entries "$lines"

	if [[ -z "${bind_ip:-}" ]]; then
		echo "Error: BIND=IP is required in $CONF_FILE" >&2
		exit 1
	fi

	if [[ ${#target_ips[@]} -eq 0 ]]; then
		echo "No target IPs (only BIND ${bind_ip}). Nothing to fetch." >&2
		exit 0
	fi

	mkdir -p "$OUTPUT_DIR"
	{
		echo "# Crontab status per target UDM (crontab file pulled via SCP, checked locally, temp files removed)."
		echo "# Format: NAME IP cron_ok | NAME IP reinstall_needed"
	} >"$STILL_RUNNING_FILE"
	local scp_failed=0
	local ctrl_path="${OUTPUT_DIR}/.ctrl-%h-%p-%r"
	local ssh_opts=(
		-o "ConnectTimeout=$SCP_CONNECT_TIMEOUT"
		-o "StrictHostKeyChecking=ask"
		-o "BindAddress=$bind_ip"
		-o "ControlPath=${ctrl_path}"
	)

	local i
	for i in "${!target_ips[@]}"; do
		local ip="${target_ips[$i]}"
		local name="${target_names[$i]}"
		local dest="${OUTPUT_DIR}/vpn-monitor-${ip}.log"
		local crontab_local="${OUTPUT_DIR}/crontab-${ip}.tmp"
		echo "---"
		echo "Connecting to ${name} (${ip}) - enter password/passphrase when prompted."
		# Open master connection (prompts once); subsequent SCPs reuse it
		if ! ssh -M -N -f "${ssh_opts[@]}" "root@${ip}"; then
			echo "Warning: SSH failed for ${name} ($ip)" >&2
			scp_failed=1
			echo "${name} ${ip} reinstall_needed" >>"$STILL_RUNNING_FILE"
		else
			# Fetch log (separate SCP so crontab failure doesn't block log)
			if ! scp "${ssh_opts[@]}" "root@${ip}:${REMOTE_LOG_PATH}" "$dest"; then
				echo "Warning: SCP failed for log from ${name} ($ip)" >&2
				scp_failed=1
				[[ -f "$dest" ]] && rm -f "$dest"
			fi
			# Fetch crontab (can fail without losing log)
			local status="reinstall_needed"
			if scp "${ssh_opts[@]}" "root@${ip}:${REMOTE_CRONTAB_PATH}" "$crontab_local" 2>/dev/null; then
				if grep -q "vpn-monitor" "$crontab_local" 2>/dev/null; then
					status="cron_ok"
				fi
			fi
			rm -f "$crontab_local"
			echo "${name} ${ip} ${status}" >>"$STILL_RUNNING_FILE"
			# Close master
			ssh -O exit "${ssh_opts[@]}" "root@${ip}" 2>/dev/null || true
		fi
	done

	local log_count=0
	for ip in "${target_ips[@]}"; do
		[[ -f "${OUTPUT_DIR}/vpn-monitor-${ip}.log" ]] && log_count=$((log_count + 1))
	done

	if [[ $log_count -eq 0 ]]; then
		echo "No logs collected. Skipping archive." >&2
		exit 2
	fi

	local stamp
	stamp=$(date +%Y-%m-%d-%H%M%S)
	local archive_name="all-vpn-logs-${stamp}.tar.gz"
	local archive_path="${OUTPUT_DIR}/${archive_name}"

	# Create tar.gz from collected logs (tar is universally available; zip is not).
	(
		cd "$OUTPUT_DIR"
		tar czf "$archive_name" vpn-monitor-*.log
	)
	echo "Created $archive_path"
	echo "Crontab status per host: $STILL_RUNNING_FILE"

	# Remove only the collected .log files (not the archive).
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
