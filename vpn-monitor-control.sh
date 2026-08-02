#!/bin/bash
#
# UDM VPN Monitor Control
# Manage operating mode: start, stop, pause, observe-only, status
#
# Designed for UniFi Dream Machine (UDM) running UniFi OS 4.3+
#
# Version: 0.8.3
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$SCRIPT_DIR"
CONFIG_FILE="${INSTALL_DIR}/vpn-monitor.conf"
STATE_DIR="${INSTALL_DIR}/state"
LOGS_DIR="${INSTALL_DIR}/logs"
LOG_FILE="${LOGS_DIR}/vpn-monitor.log"

# shellcheck source=lib/control.sh
source "${SCRIPT_DIR}/lib/control.sh"

COMMAND=""
PAUSE_UNTIL=""
REASON=""

# Show usage information
#
# Returns:
#   Exits 0
show_help() {
	cat <<EOF
Usage: $0 <command> [options]

Manage VPN Monitor operating mode on this UDM.

Commands:
  start          Restore normal operation (cron + keepalive if configured)
  stop           Halt monitoring (remove cron, stop wrapper and keepalive)
  pause          Pause until --until TIME, or indefinitely if --until omitted
  observe-only   Run detection and logging; suppress all recovery actions
  status         Show current operating mode and service state

Options (pause):
  --until TIME   End time: epoch, +30m/+2h/+1d, or YYYY-MM-DDTHH:MM:SS
                 Omit for indefinite pause (until start/observe-only/stop)

Options (pause, observe-only):
  --reason TEXT  Optional reason recorded in state and logs

Examples:
  $0 stop
  $0 pause --reason "hold until operator resumes"
  $0 pause --until +2h --reason "IPsec maintenance"
  $0 observe-only --reason "Investigating false positives"
  $0 start
  $0 status

EOF
	exit "${EXIT_SUCCESS:-0}"
}

# Parse command-line arguments
#
# Arguments:
#   $@: Command-line arguments
#
# Returns:
#   0: Parsed successfully
#   1: Invalid arguments
parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--help | -h)
			show_help
			;;
		--until)
			shift
			[[ $# -eq 0 ]] && die "Missing value for --until" "${EXIT_VALIDATION_ERROR:-3}"
			PAUSE_UNTIL="$1"
			shift
			;;
		--reason)
			shift
			[[ $# -eq 0 ]] && die "Missing value for --reason" "${EXIT_VALIDATION_ERROR:-3}"
			REASON="$1"
			shift
			;;
		start | stop | pause | observe-only | status)
			if [[ -n "$COMMAND" ]]; then
				die "Multiple commands specified" "${EXIT_VALIDATION_ERROR:-3}"
			fi
			COMMAND="$1"
			shift
			;;
		*)
			die "Unknown argument: $1" "${EXIT_VALIDATION_ERROR:-3}"
			;;
		esac
	done

	[[ -n "$COMMAND" ]] || show_help
}

# Stop keepalive daemon (systemd or script)
#
# Returns:
#   0: Always (best effort)
stop_keepalive_service() {
	local was_systemd=0
	if command -v systemctl >/dev/null 2>&1 && systemctl is-active vpn-keepalive >/dev/null 2>&1; then
		was_systemd=1
	fi
	stop_keepalive "$INSTALL_DIR"
	if [[ $was_systemd -eq 1 ]]; then
		log_message "INFO" "SYSTEM" "Stopped vpn-keepalive systemd service"
	fi
	return 0
}

# Start keepalive when enabled in config
#
# Returns:
#   0: Always (best effort)
start_keepalive_if_enabled() {
	if ! is_keepalive_enabled "$CONFIG_FILE"; then
		return 0
	fi
	if start_keepalive "$INSTALL_DIR"; then
		if command -v systemctl >/dev/null 2>&1 && keepalive_systemd_unit_installed; then
			log_message "INFO" "SYSTEM" "Started vpn-keepalive systemd service"
		fi
	fi
	return 0
}

# Execute start command
#
# Returns:
#   0: Success
cmd_start() {
	local prev
	prev=$(get_operating_mode)
	mkdir -p "$STATE_DIR" "$LOGS_DIR"
	if ! set_operating_mode "$OPERATING_MODE_RUNNING" "0" "$REASON" "${USER:-local}"; then
		return 1
	fi
	log_operating_mode_transition "$prev" "$OPERATING_MODE_RUNNING" "$REASON"
	install_vpn_monitor_cron "$INSTALL_DIR"
	start_keepalive_if_enabled
	echo "Monitor started (mode: running)"
	return 0
}

# Execute stop command
#
# Returns:
#   0: Success
cmd_stop() {
	local prev
	prev=$(get_operating_mode)
	mkdir -p "$STATE_DIR" "$LOGS_DIR"
	stop_monitor_wrapper
	stop_keepalive_service
	remove_vpn_monitor_cron
	if ! set_operating_mode "$OPERATING_MODE_STOPPED" "0" "$REASON" "${USER:-local}"; then
		return 1
	fi
	log_operating_mode_transition "$prev" "$OPERATING_MODE_STOPPED" "$REASON"
	echo "Monitor stopped"
	return 0
}

# Execute pause command
#
# Without --until: indefinite pause (paused_until=0) until start/observe-only/stop.
# With --until: timed pause; expired timed pause auto-resumes to running.
#
# Returns:
#   0: Success
#   1: Invalid --until
cmd_pause() {
	local prev epoch=0
	if [[ -n "$PAUSE_UNTIL" ]]; then
		if ! epoch=$(parse_pause_until_time "$PAUSE_UNTIL"); then
			return 1
		fi
	fi
	prev=$(get_operating_mode)
	mkdir -p "$STATE_DIR" "$LOGS_DIR"
	install_vpn_monitor_cron "$INSTALL_DIR"
	if ! set_operating_mode "$OPERATING_MODE_PAUSED" "$epoch" "$REASON" "${USER:-local}"; then
		return 1
	fi
	log_operating_mode_transition "$prev" "$OPERATING_MODE_PAUSED" "$REASON"
	if [[ "$epoch" -eq 0 ]]; then
		echo "Monitor paused indefinitely (resume with start or observe-only)"
	else
		echo "Monitor paused until $(format_pause_until_display "$epoch")"
	fi
	return 0
}

# Execute observe-only command
#
# Returns:
#   0: Success
cmd_observe_only() {
	local prev
	prev=$(get_operating_mode)
	mkdir -p "$STATE_DIR" "$LOGS_DIR"
	install_vpn_monitor_cron "$INSTALL_DIR"
	if ! set_operating_mode "$OPERATING_MODE_OBSERVE_ONLY" "0" "$REASON" "${USER:-local}"; then
		return 1
	fi
	log_operating_mode_transition "$prev" "$OPERATING_MODE_OBSERVE_ONLY" "$REASON"
	echo "Monitor in observe-only mode (logging enabled, recovery suppressed)"
	return 0
}

# Execute status command
#
# Returns:
#   0: Always
cmd_status() {
	local mode paused_until cron_status keepalive_status
	mode=$(get_operating_mode)
	paused_until=$(get_operating_mode_paused_until)

	if has_vpn_monitor_cron_entry; then
		cron_status="enabled"
	else
		cron_status="disabled"
	fi

	keepalive_status="not running"
	if command -v systemctl >/dev/null 2>&1 && systemctl is-active vpn-keepalive >/dev/null 2>&1; then
		keepalive_status="running (systemd)"
	elif [[ -x "${INSTALL_DIR}/vpn-keepalive.sh" ]] && "${INSTALL_DIR}/vpn-keepalive.sh" status >/dev/null 2>&1; then
		keepalive_status="running"
	fi

	echo "Operating mode: ${mode}"
	if [[ "$mode" == "$OPERATING_MODE_PAUSED" ]]; then
		if [[ "$paused_until" -eq 0 ]]; then
			echo "Paused until: indefinite"
		elif [[ "$paused_until" -gt 0 ]]; then
			echo "Paused until: $(format_pause_until_display "$paused_until")"
		fi
	fi
	echo "Cron: ${cron_status}"
	echo "Keepalive: ${keepalive_status}"
	return 0
}

# Main entry point
main() {
	parse_args "$@"
	mkdir -p "$STATE_DIR" "$LOGS_DIR"

	case "$COMMAND" in
	start) cmd_start ;;
	stop) cmd_stop ;;
	pause) cmd_pause ;;
	observe-only) cmd_observe_only ;;
	status) cmd_status ;;
	*)
		die "Unknown command: $COMMAND" "${EXIT_VALIDATION_ERROR:-3}"
		;;
	esac
}

main "$@"
