#!/bin/bash
#
# Recovery actions for UDM VPN Monitor
# Implements tiered recovery: logging → surgical cleanup → full restart
#
# Version: 0.5.0
#
# This file now serves as a compatibility layer that sources the decomposed
# recovery modules. All recovery functionality has been moved to lib/recovery/
# subdirectory for better organization and maintainability.
#

# Determine lib directory (where this file is located)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECOVERY_DIR="${LIB_DIR}/recovery"

# Source all recovery modules
# shellcheck source=lib/recovery/recovery_verification.sh
source "${RECOVERY_DIR}/recovery_verification.sh" 2>/dev/null || {
	echo "Warning: Failed to source recovery_verification.sh" >&2
}

# shellcheck source=lib/recovery/recovery_state.sh
source "${RECOVERY_DIR}/recovery_state.sh" 2>/dev/null || {
	echo "Warning: Failed to source recovery_state.sh" >&2
}

# shellcheck source=lib/recovery/xfrm_recovery.sh
source "${RECOVERY_DIR}/xfrm_recovery.sh" 2>/dev/null || {
	echo "Warning: Failed to source xfrm_recovery.sh" >&2
}

# shellcheck source=lib/recovery/ipsec_recovery.sh
source "${RECOVERY_DIR}/ipsec_recovery.sh" 2>/dev/null || {
	echo "Warning: Failed to source ipsec_recovery.sh" >&2
}

# shellcheck source=lib/recovery/recovery_orchestration.sh
source "${RECOVERY_DIR}/recovery_orchestration.sh" 2>/dev/null || {
	echo "Warning: Failed to source recovery_orchestration.sh" >&2
}
