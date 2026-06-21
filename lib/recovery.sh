#!/bin/bash
#
# Recovery actions for UDM VPN Monitor
# Implements tiered recovery: logging → surgical cleanup → full restart
#
# Version: 0.8.3
#
# Aggregate entry point: sources the decomposed recovery modules in dependency
# order. Implementation lives under lib/recovery/ for organization and testing.
#

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

# Validate recovery module directory exists
RECOVERY_DIR="${LIB_DIR}/recovery"
if [[ ! -d "${RECOVERY_DIR}" ]]; then
	echo "ERROR: Recovery module directory does not exist: ${RECOVERY_DIR}" >&2
	exit 1
fi

# Source common utility functions (needed for log_module_error)
# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"

# Source all recovery modules in dependency order
# shellcheck source=lib/recovery/recovery_verification.sh
source "${RECOVERY_DIR}/recovery_verification.sh" || {
	log_module_error "Failed to source recovery/recovery_verification.sh"
	exit 1
}

# shellcheck source=lib/recovery/recovery_state.sh
source "${RECOVERY_DIR}/recovery_state.sh" || {
	log_module_error "Failed to source recovery/recovery_state.sh"
	exit 1
}

# shellcheck source=lib/recovery/xfrm_recovery.sh
source "${RECOVERY_DIR}/xfrm_recovery.sh" || {
	log_module_error "Failed to source recovery/xfrm_recovery.sh"
	exit 1
}

# shellcheck source=lib/recovery/ipsec_recovery.sh
source "${RECOVERY_DIR}/ipsec_recovery.sh" || {
	log_module_error "Failed to source recovery/ipsec_recovery.sh"
	exit 1
}

# shellcheck source=lib/recovery/recovery_orchestration.sh
source "${RECOVERY_DIR}/recovery_orchestration.sh" || {
	log_module_error "Failed to source recovery/recovery_orchestration.sh"
	exit 1
}
