#!/bin/bash
#
# State file management for UDM VPN Monitor
# Handles failure counters, rate limiting, restart tracking, and related global/per-peer state
#
# Version: 0.8.3
#
# This file sources modular state management components:
#   - state_paths.sh: Path generation and sanitization
#   - global_state.sh: Global state (restart timestamps, partition flag, etc.)
#   - peer_state.sh: Per-peer state operations
#   - state_init.sh: State initialization
#   - network_partition_stats.sh: Network partition statistics tracking
#   - resource_monitoring_stats.sh: Resource monitoring statistics tracking
#
# Sourcing prerequisites:
#   lib/constants.sh is required (bundled). Missing or unloadable constants exit
#   the shell immediately so SECONDS_* and exit codes cannot drift.

# Determine lib directory, then load constants (fail-fast; before common.sh)
# shellcheck source=lib/constants.sh
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 2>/dev/null || LIB_DIR=""
if [[ -z "${LIB_DIR:-}" ]] || [[ ! -d "${LIB_DIR}" ]]; then
	echo "ERROR: Cannot determine lib directory from ${BASH_SOURCE[0]:-<unknown>}" >&2
	exit 1
fi
if [[ ! -f "${LIB_DIR}/constants.sh" ]] || [[ ! -r "${LIB_DIR}/constants.sh" ]]; then
	echo "ERROR: Required file missing or unreadable: ${LIB_DIR}/constants.sh" >&2
	exit 1
fi
source "${LIB_DIR}/constants.sh" || {
	echo "ERROR: Failed to source lib/constants.sh" >&2
	exit 1
}

# Source common utility functions
# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"

# Source state management modules
# Order matters: modules are sourced in dependency order
# Use STATE_MODULE_DIR for module directory to avoid overwriting STATE_DIR
# STATE_DIR should be set by the main script or config, not here
STATE_MODULE_DIR="${LIB_DIR}/state"
# shellcheck source=lib/state/state_paths.sh
source "${STATE_MODULE_DIR}/state_paths.sh" 2>/dev/null || {
	log_module_error "Failed to source state_paths.sh"
	exit 1
}
# shellcheck source=lib/state/global_state.sh
source "${STATE_MODULE_DIR}/global_state.sh" 2>/dev/null || {
	log_module_error "Failed to source global_state.sh"
	exit 1
}
# shellcheck source=lib/state/peer_state.sh
source "${STATE_MODULE_DIR}/peer_state.sh" 2>/dev/null || {
	log_module_error "Failed to source peer_state.sh"
	exit 1
}
# shellcheck source=lib/state/state_init.sh
source "${STATE_MODULE_DIR}/state_init.sh" 2>/dev/null || {
	log_module_error "Failed to source state_init.sh"
	exit 1
}
# shellcheck source=lib/state/network_partition_stats.sh
source "${STATE_MODULE_DIR}/network_partition_stats.sh" 2>/dev/null || {
	log_module_error "Failed to source network_partition_stats.sh"
	exit 1
}
# shellcheck source=lib/state/resource_monitoring_stats.sh
source "${STATE_MODULE_DIR}/resource_monitoring_stats.sh" 2>/dev/null || {
	log_module_error "Failed to source resource_monitoring_stats.sh"
	exit 1
}
