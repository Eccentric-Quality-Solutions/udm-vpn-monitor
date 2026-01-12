#!/bin/bash
#
# Recovery module constants for UDM VPN Monitor
# Defines recovery-specific constants used across recovery modules
#
# Version: 0.6.0
#

# shellcheck disable=SC2034
# Constants are used by files that source this file, not within this file itself

# Sleep delay (in seconds) after xfrm SA deletion to allow IKE re-establishment
# Gives strongSwan time to detect SA deletion and initiate re-establishment
# Used by both xfrm_recovery.sh and ipsec_recovery.sh
readonly XFRM_RECOVERY_SLEEP_SECONDS=3

# Maximum time (in seconds) to wait for SA re-establishment after deletion
# Verification checks are performed with retries up to this timeout
# Used by xfrm_recovery.sh
readonly XFRM_RECOVERY_VERIFY_TIMEOUT=30

# Interval (in seconds) between verification retry attempts
# Used by xfrm_recovery.sh for exponential backoff during recovery verification
readonly XFRM_RECOVERY_VERIFY_INTERVAL=2

# Maximum interval (in seconds) for exponential backoff during recovery verification
# Used to cap the exponential backoff interval growth
# Used by xfrm_recovery.sh
readonly XFRM_RECOVERY_MAX_INTERVAL=16

# Timeout (in seconds) for ipsec status command to prevent hanging
# Prevents ipsec status from blocking script execution indefinitely
# Used by recovery_verification.sh
readonly IPSEC_STATUS_TIMEOUT=5
