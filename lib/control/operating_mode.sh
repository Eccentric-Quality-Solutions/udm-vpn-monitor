#!/bin/bash
#
# Operating mode state management for UDM VPN Monitor
# Persists running/stopped/paused/observe-only modes in state/operating_mode
#
# Version: 0.8.3
#

# Valid operating mode values
OPERATING_MODE_RUNNING="running"
OPERATING_MODE_STOPPED="stopped"
OPERATING_MODE_PAUSED="paused"
OPERATING_MODE_OBSERVE_ONLY="observe-only"

# Get path to operating_mode state file
#
# Returns:
#   0: Always
#
# Output:
#   Prints absolute path to operating_mode file
get_operating_mode_file_path() {
	local state_dir="${STATE_DIR:-}"
	if [[ -z "$state_dir" ]]; then
		echo ""
		return 1
	fi
	echo "${state_dir}/operating_mode"
}

# Get default operating mode when no state file exists
#
# Output:
#   Prints default mode (running)
get_default_operating_mode() {
	echo "$OPERATING_MODE_RUNNING"
}

# Read a key=value field from operating_mode file
#
# Arguments:
#   $1: file path
#   $2: field name
#
# Output:
#   Field value or empty string
_read_operating_mode_field() {
	local file="$1"
	local field="$2"
	local line value
	if [[ ! -f "$file" ]] || ! file_exists_and_readable "$file"; then
		return 1
	fi
	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ "$line" =~ ^[[:space:]]*# ]] && continue
		[[ "$line" != *"="* ]] && continue
		if [[ "${line%%=*}" == "$field" ]]; then
			value="${line#*=}"
			echo "$(trim "$value")"
			return 0
		fi
	done <"$file"
	return 1
}

# Read current operating mode from state file
#
# Output:
#   Prints mode string (defaults to running)
#
# Returns:
#   0: Always
get_operating_mode() {
	local file mode
	file=$(get_operating_mode_file_path) || {
		get_default_operating_mode
		return 0
	}
	if mode=$(_read_operating_mode_field "$file" "mode" 2>/dev/null); then
		case "$mode" in
		"$OPERATING_MODE_RUNNING" | "$OPERATING_MODE_STOPPED" | "$OPERATING_MODE_PAUSED" | "$OPERATING_MODE_OBSERVE_ONLY")
			echo "$mode"
			return 0
			;;
		esac
	fi
	get_default_operating_mode
}

# Read paused_until epoch from state file
#
# Output:
#   Prints epoch seconds or 0
get_operating_mode_paused_until() {
	local file val
	file=$(get_operating_mode_file_path) || {
		echo "0"
		return 0
	}
	if val=$(_read_operating_mode_field "$file" "paused_until" 2>/dev/null); then
		if is_non_negative_integer "$val"; then
			echo "$val"
			return 0
		fi
	fi
	echo "0"
}

# Write operating mode state atomically
#
# Arguments:
#   $1: mode (running|stopped|paused|observe-only)
#   $2: paused_until epoch (optional, required when mode=paused)
#   $3: reason (optional)
#   $4: set_by identity (optional)
#
# Returns:
#   0: Success
#   1: Invalid mode or write failure
set_operating_mode() {
	local mode="$1"
	local paused_until="${2:-0}"
	local reason="${3:-}"
	local set_by="${4:-}"
	local file content now

	case "$mode" in
	"$OPERATING_MODE_RUNNING" | "$OPERATING_MODE_STOPPED" | "$OPERATING_MODE_PAUSED" | "$OPERATING_MODE_OBSERVE_ONLY") ;;
	*)
		log_message "ERROR" "SYSTEM" "Invalid operating mode: $mode"
		return 1
		;;
	esac

	if [[ "$mode" == "$OPERATING_MODE_PAUSED" ]]; then
		if ! is_non_negative_integer "$paused_until" || [[ "$paused_until" -le 0 ]]; then
			log_message "ERROR" "SYSTEM" "paused_until required for pause mode"
			return 1
		fi
	else
		paused_until="0"
	fi

	file=$(get_operating_mode_file_path) || {
		log_message "ERROR" "SYSTEM" "STATE_DIR not set; cannot write operating mode"
		return 1
	}

	now=$(get_unix_timestamp)
	[[ -z "$set_by" ]] && set_by="${USER:-unknown}"

	content="mode=${mode}
paused_until=${paused_until}
set_at=${now}
set_by=${set_by}"
	if [[ -n "$reason" ]]; then
		content="${content}
reason=${reason}"
	fi

	if ! atomic_write_file "$file" "$content"; then
		log_message "ERROR" "SYSTEM" "Failed to write operating mode to $file"
		return 1
	fi
	return 0
}

# Ensure operating_mode file exists with default running mode
#
# Returns:
#   0: Success
ensure_operating_mode_initialized() {
	local file
	file=$(get_operating_mode_file_path) || return 1
	if [[ ! -f "$file" ]]; then
		set_operating_mode "$OPERATING_MODE_RUNNING" "0" "" "system"
	fi
	return 0
}

# Parse --until time specification to Unix epoch
#
# Arguments:
#   $1: time spec — epoch seconds, +30m/+2h/+1d, or YYYY-MM-DDTHH:MM:SS
#
# Output:
#   Epoch seconds on success
#
# Returns:
#   0: Parsed successfully
#   1: Invalid or past time
parse_pause_until_time() {
	local spec="$1"
	local now epoch offset unit num

	spec=$(trim "$spec")
	[[ -z "$spec" ]] && return 1

	now=$(get_unix_timestamp)

	# Absolute epoch
	if is_non_negative_integer "$spec"; then
		epoch="$spec"
		if [[ "$epoch" -le "$now" ]]; then
			log_message "ERROR" "SYSTEM" "Pause end time must be in the future (got epoch $epoch, now $now)"
			return 1
		fi
		echo "$epoch"
		return 0
	fi

	# Relative duration: +30m, +2h, +1d
	if [[ "$spec" =~ ^\+([0-9]+)([mhd])$ ]]; then
		num="${BASH_REMATCH[1]}"
		unit="${BASH_REMATCH[2]}"
		offset=0
		case "$unit" in
		m) offset=$((num * 60)) ;;
		h) offset=$((num * 3600)) ;;
		d) offset=$((num * 86400)) ;;
		esac
		epoch=$((now + offset))
		echo "$epoch"
		return 0
	fi

	# Local datetime YYYY-MM-DDTHH:MM:SS
	if [[ "$spec" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
		if ! epoch=$(date -d "$spec" +%s 2>/dev/null); then
			log_message "ERROR" "SYSTEM" "Invalid datetime format: $spec"
			return 1
		fi
		if [[ "$epoch" -le "$now" ]]; then
			log_message "ERROR" "SYSTEM" "Pause end time must be in the future (got $spec)"
			return 1
		fi
		echo "$epoch"
		return 0
	fi

	log_message "ERROR" "SYSTEM" "Invalid --until time format: $spec (use epoch, +30m/+2h/+1d, or YYYY-MM-DDTHH:MM:SS)"
	return 1
}

# Format epoch as human-readable local time
#
# Arguments:
#   $1: epoch seconds
#
# Output:
#   Human-readable timestamp
format_pause_until_display() {
	local epoch="$1"
	if [[ -z "$epoch" ]] || [[ "$epoch" == "0" ]]; then
		echo "n/a"
		return 0
	fi
	date -d "@${epoch}" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date -r "$epoch" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "@${epoch}"
}

# Check operating mode at monitor startup
#
# Sets NO_ESCALATE=1 when mode is observe-only.
# Auto-resumes from expired pause to running.
#
# Returns:
#   0: Continue monitor execution
#   1: Exit early (active pause or stopped)
check_operating_mode() {
	local mode paused_until now prev_mode

	mode=$(get_operating_mode)
	paused_until=$(get_operating_mode_paused_until)
	now=$(get_unix_timestamp)

	case "$mode" in
	"$OPERATING_MODE_STOPPED")
		log_message "INFO" "SYSTEM" "Monitor is stopped; skipping execution"
		return 1
		;;
	"$OPERATING_MODE_PAUSED")
		if [[ "$paused_until" -gt "$now" ]]; then
			log_message "INFO" "SYSTEM" "Monitor is paused until $(format_pause_until_display "$paused_until"); skipping execution"
			return 1
		fi
		# Expired pause — auto-resume
		prev_mode="$mode"
		if set_operating_mode "$OPERATING_MODE_RUNNING" "0" "" "auto-resume"; then
			log_message "INFO" "SYSTEM" "Pause expired; operating mode changed from ${prev_mode} to ${OPERATING_MODE_RUNNING}"
		fi
		mode="$OPERATING_MODE_RUNNING"
		;;
	"$OPERATING_MODE_OBSERVE_ONLY")
		export NO_ESCALATE=1
		log_message "INFO" "SYSTEM" "Observe-only mode: detection and logging enabled; recovery actions suppressed"
		return 0
		;;
	esac

	return 0
}

# Log operating mode transition
#
# Arguments:
#   $1: previous mode
#   $2: new mode
#   $3: optional reason
log_operating_mode_transition() {
	local prev="$1"
	local new="$2"
	local reason="${3:-}"
	local msg="Operating mode changed: ${prev} -> ${new}"
	[[ -n "$reason" ]] && msg="${msg} (reason: ${reason})"
	log_message "INFO" "SYSTEM" "$msg"
}
