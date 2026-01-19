#!/bin/bash
#
# Recovery actions for UDM VPN Monitor
# Implements tiered recovery: logging → surgical cleanup → full restart
#
# Version: 0.6.0
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

# Verify critical recovery function is available after sourcing
# This ensures that if recovery_orchestration.sh failed to source, we fail fast
# rather than continuing and causing "command not found" errors at runtime
if ! command -v monitor_location >/dev/null 2>&1; then
	echo "ERROR: Critical recovery function monitor_location not available after sourcing recovery modules" >&2
	return 1
fi
