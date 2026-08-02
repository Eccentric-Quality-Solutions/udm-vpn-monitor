#!/bin/bash
#
# Monitor wrapper process control for UDM VPN Monitor
# Shared by uninstall.sh and vpn-monitor-control.sh
#
# Version: 0.8.3
#

# Path to wrapper PID file under STATE_DIR
#
# Output:
#   Absolute path, or empty if STATE_DIR unset
#
# Returns:
#   0: Path printed
#   1: STATE_DIR unset
get_wrapper_pidfile_path() {
	if [[ -z "${STATE_DIR:-}" ]]; then
		echo ""
		return 1
	fi
	echo "${STATE_DIR}/vpn-monitor-wrapper.pid"
}

# Stop monitor wrapper process if running
#
# Best-effort: TERM, wait up to 5s, then KILL. Removes pidfile and lock dir.
#
# Returns:
#   0: Always
stop_monitor_wrapper() {
	local pid="" pidfile lockdir
	pidfile=$(get_wrapper_pidfile_path) || true
	lockdir="${STATE_DIR:-}/.wrapper.lock"

	if [[ -n "$pidfile" ]] && file_exists_and_readable "$pidfile"; then
		pid=$(cat "$pidfile" 2>/dev/null || echo "")
	fi
	if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
		kill -TERM "$pid" 2>/dev/null || true
		local count=0
		while kill -0 "$pid" 2>/dev/null && [[ $count -lt 5 ]]; do
			sleep 1
			count=$((count + 1))
		done
		if kill -0 "$pid" 2>/dev/null; then
			kill -KILL "$pid" 2>/dev/null || true
		fi
		if command -v log_message >/dev/null 2>&1; then
			log_message "INFO" "SYSTEM" "Stopped monitor wrapper (PID: $pid)"
		fi
	fi
	[[ -n "$pidfile" ]] && rm -f "$pidfile" 2>/dev/null || true
	[[ -n "${STATE_DIR:-}" ]] && rm -rf "$lockdir" 2>/dev/null || true
	return 0
}
