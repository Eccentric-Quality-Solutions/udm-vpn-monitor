#!/bin/bash
#
# Recovery module constants for UDM VPN Monitor
# Defines recovery-specific constants used across recovery modules
#
# Usage Guidelines:
#   - Always use these constants instead of magic numbers in recovery code
#   - Add new constants here when a value is used in multiple recovery modules or has semantic meaning
#   - For general application constants, see lib/constants.sh
#
# Sourcing:
#   This file is safe to source multiple times (idempotent).
#   Constants are only defined if not already set.
#
# Version: 0.8.1
#

# shellcheck disable=SC2034
# Constants are used by files that source this file, not within this file itself

# Sleep delay (in seconds) after xfrm SA deletion to allow IKE re-establishment
# Gives strongSwan time to detect SA deletion and initiate re-establishment
# Used by both xfrm_recovery.sh and ipsec_recovery.sh
[[ -z "${XFRM_RECOVERY_SLEEP_SECONDS:-}" ]] && readonly XFRM_RECOVERY_SLEEP_SECONDS=3

# Maximum time (in seconds) to wait for SA re-establishment after deletion
# Verification checks are performed with retries up to this timeout
# Used by xfrm_recovery.sh
[[ -z "${XFRM_RECOVERY_VERIFY_TIMEOUT:-}" ]] && readonly XFRM_RECOVERY_VERIFY_TIMEOUT=30

# Interval (in seconds) between verification retry attempts
# Used by xfrm_recovery.sh for exponential backoff during recovery verification
[[ -z "${XFRM_RECOVERY_VERIFY_INTERVAL:-}" ]] && readonly XFRM_RECOVERY_VERIFY_INTERVAL=2

# Maximum interval (in seconds) for exponential backoff during recovery verification
# Used to cap the exponential backoff interval growth
# Used by xfrm_recovery.sh
[[ -z "${XFRM_RECOVERY_MAX_INTERVAL:-}" ]] && readonly XFRM_RECOVERY_MAX_INTERVAL=16
