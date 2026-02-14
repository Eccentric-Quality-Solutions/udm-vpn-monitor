#!/bin/bash
#
# VPN status detection for UDM VPN Monitor
# Handles VPN detection using xfrm, ipsec, and ping checks
#
# Version: 0.8.0
#
# This file sources all detection modules:
# - network_validation.sh: IP validation, route checks
# - xfrm_detection.sh: xfrm state and byte counter detection
# - ping_detection.sh: Ping-based detection
# - failure_analysis.sh: Failure type classification
# - system_wide_failure.sh: System-wide failure detection

# Determine lib directory (where this file is located)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 2>/dev/null || {
	echo "ERROR: Cannot determine lib directory from ${BASH_SOURCE[0]:-<unknown>}" >&2
	exit 1
}

# Validate LIB_DIR was set correctly
if [[ -z "${LIB_DIR:-}" ]] || [[ ! -d "${LIB_DIR}" ]]; then
	echo "ERROR: Invalid lib directory: ${LIB_DIR:-<empty>}" >&2
	exit 1
fi

# Validate detection module directory exists
DETECTION_MODULE_DIR="${LIB_DIR}/detection"
if [[ ! -d "${DETECTION_MODULE_DIR}" ]]; then
	echo "ERROR: Detection module directory does not exist: ${DETECTION_MODULE_DIR}" >&2
	exit 1
fi

# Source common utility functions (needed for log_module_error)
# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"

# Source all detection modules in dependency order
# shellcheck source=lib/detection/network_validation.sh
source "${DETECTION_MODULE_DIR}/network_validation.sh" || {
	log_module_error "Failed to source detection/network_validation.sh"
	exit 1
}

# shellcheck source=lib/detection/xfrm_detection.sh
source "${DETECTION_MODULE_DIR}/xfrm_detection.sh" || {
	log_module_error "Failed to source detection/xfrm_detection.sh"
	exit 1
}

# shellcheck source=lib/detection/ping_detection.sh
source "${DETECTION_MODULE_DIR}/ping_detection.sh" || {
	log_module_error "Failed to source detection/ping_detection.sh"
	exit 1
}

# shellcheck source=lib/detection/failure_analysis.sh
source "${DETECTION_MODULE_DIR}/failure_analysis.sh" || {
	log_module_error "Failed to source detection/failure_analysis.sh"
	exit 1
}

# shellcheck source=lib/detection/system_wide_failure.sh
source "${DETECTION_MODULE_DIR}/system_wide_failure.sh" || {
	log_module_error "Failed to source detection/system_wide_failure.sh"
	exit 1
}
