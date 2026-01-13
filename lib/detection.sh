#!/bin/bash
#
# VPN status detection for UDM VPN Monitor
# Handles VPN detection using xfrm, ipsec, and ping checks
#
# Version: 0.6.0
#
# This file sources all detection modules:
# - network_validation.sh: IP validation, route checks
# - xfrm_detection.sh: xfrm state and byte counter detection
# - ping_detection.sh: Ping-based detection
# - failure_analysis.sh: Failure type classification

# Determine lib directory (where this file is located)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all detection modules in dependency order
# shellcheck source=lib/detection/network_validation.sh
source "${LIB_DIR}/detection/network_validation.sh"

# shellcheck source=lib/detection/xfrm_detection.sh
source "${LIB_DIR}/detection/xfrm_detection.sh"

# shellcheck source=lib/detection/ping_detection.sh
source "${LIB_DIR}/detection/ping_detection.sh"

# shellcheck source=lib/detection/failure_analysis.sh
source "${LIB_DIR}/detection/failure_analysis.sh"

# shellcheck source=lib/detection/system_wide_failure.sh
source "${LIB_DIR}/detection/system_wide_failure.sh"
