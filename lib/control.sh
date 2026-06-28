#!/bin/bash
#
# Control module aggregate entry for UDM VPN Monitor
# Sources operating mode and cron control helpers
#
# Version: 0.8.3
#

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 2>/dev/null || LIB_DIR=""
if [[ -z "${LIB_DIR:-}" ]] || [[ ! -d "${LIB_DIR}" ]]; then
	echo "ERROR: Cannot determine lib directory from ${BASH_SOURCE[0]:-<unknown>}" >&2
	exit 1
fi

# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh" || {
	echo "ERROR: Failed to source lib/common.sh" >&2
	exit 1
}

# shellcheck source=lib/logging.sh
source "${LIB_DIR}/logging.sh" || {
	echo "ERROR: Failed to source lib/logging.sh" >&2
	exit 1
}

# shellcheck source=lib/config/config_loading.sh
source "${LIB_DIR}/config/config_loading.sh" || {
	echo "ERROR: Failed to source lib/config/config_loading.sh" >&2
	exit 1
}

CONTROL_MODULE_DIR="${LIB_DIR}/control"

# shellcheck source=lib/control/operating_mode.sh
source "${CONTROL_MODULE_DIR}/operating_mode.sh" 2>/dev/null || {
	echo "ERROR: Failed to source lib/control/operating_mode.sh" >&2
	exit 1
}

# shellcheck source=lib/control/cron_control.sh
source "${CONTROL_MODULE_DIR}/cron_control.sh" 2>/dev/null || {
	echo "ERROR: Failed to source lib/control/cron_control.sh" >&2
	exit 1
}

# shellcheck source=lib/control/keepalive_control.sh
source "${CONTROL_MODULE_DIR}/keepalive_control.sh" 2>/dev/null || {
	echo "ERROR: Failed to source lib/control/keepalive_control.sh" >&2
	exit 1
}
