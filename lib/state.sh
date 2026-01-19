#!/bin/bash
#
# State file management for UDM VPN Monitor
# Handles failure counters, cooldown periods, rate limiting, and restart tracking
#
# Version: 0.6.0
#
# This file sources modular state management components:
#   - state_paths.sh: Path generation and sanitization
#   - global_state.sh: Global state (cooldown, restart count, etc.)
#   - peer_state.sh: Per-peer state operations
#   - location_state.sh: Per-location state operations
#   - state_init.sh: State initialization
#   - network_partition_stats.sh: Network partition statistics tracking
#   - resource_monitoring_stats.sh: Resource monitoring statistics tracking

# Source constants for magic numbers
# shellcheck source=lib/constants.sh
# Determine lib directory (where this file is located)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Note: safe_source_lib not available here since constants.sh is sourced before common.sh
if ! source "${LIB_DIR}/constants.sh" 2>/dev/null; then
	# Fallback if constants.sh not found (shouldn't happen in normal operation)
	# Only set if not already set (to avoid readonly variable errors)
	if [[ -z "${SECONDS_PER_MINUTE:-}" ]]; then
		readonly SECONDS_PER_MINUTE=60
	fi
	if [[ -z "${SECONDS_PER_HOUR:-}" ]]; then
		readonly SECONDS_PER_HOUR=3600
	fi
	if [[ -z "${SECONDS_PER_DAY:-}" ]]; then
		readonly SECONDS_PER_DAY=86400
	fi
fi

# Source common utility functions
# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"

# Helper function to log errors when sourcing state modules fails
#
# Uses log_message if available (from logging.sh), otherwise falls back to echo.
# This ensures errors are logged consistently when possible.
#
# Arguments:
#   $1: Error message to log
#
# Returns:
#   0: Always succeeds (logging never fails)
#
# Output:
#   - If log_message is available: logs via log_message to LOG_FILE and stderr
#   - Otherwise: prints error message to stderr
#
# Examples:
#   log_state_error "Failed to source state module: peer_state.sh"
#
# Note:
#   This function is used during module loading when log_message may not be available yet.
#   It gracefully falls back to echo if log_message is not defined.
log_state_error() {
	local message="$1"
	if type log_message >/dev/null 2>&1; then
		# log_message is available - use it (it will handle LOG_FILE not being set)
		log_message "ERROR" "SYSTEM" "$message"
	else
		# Fallback to echo if log_message not available
		echo "Error: $message" >&2
	fi
}

# Source state management modules
# Order matters: modules are sourced in dependency order
# Use STATE_MODULE_DIR for module directory to avoid overwriting STATE_DIR
# STATE_DIR should be set by the main script or config, not here
STATE_MODULE_DIR="${LIB_DIR}/state"
# shellcheck source=lib/state/state_paths.sh
source "${STATE_MODULE_DIR}/state_paths.sh" 2>/dev/null || {
	log_state_error "Failed to source state_paths.sh"
	exit 1
}
# shellcheck source=lib/state/global_state.sh
source "${STATE_MODULE_DIR}/global_state.sh" 2>/dev/null || {
	log_state_error "Failed to source global_state.sh"
	exit 1
}
# shellcheck source=lib/state/peer_state.sh
source "${STATE_MODULE_DIR}/peer_state.sh" 2>/dev/null || {
	log_state_error "Failed to source peer_state.sh"
	exit 1
}
# shellcheck source=lib/state/location_state.sh
source "${STATE_MODULE_DIR}/location_state.sh" 2>/dev/null || {
	log_state_error "Failed to source location_state.sh"
	exit 1
}
# shellcheck source=lib/state/state_init.sh
source "${STATE_MODULE_DIR}/state_init.sh" 2>/dev/null || {
	log_state_error "Failed to source state_init.sh"
	exit 1
}
# shellcheck source=lib/state/network_partition_stats.sh
source "${STATE_MODULE_DIR}/network_partition_stats.sh" 2>/dev/null || {
	log_state_error "Failed to source network_partition_stats.sh"
	exit 1
}
# shellcheck source=lib/state/resource_monitoring_stats.sh
source "${STATE_MODULE_DIR}/resource_monitoring_stats.sh" 2>/dev/null || {
	log_state_error "Failed to source resource_monitoring_stats.sh"
	exit 1
}
