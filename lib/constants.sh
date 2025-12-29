#!/bin/bash
#
# Constants for UDM VPN Monitor
# Defines commonly used magic numbers as named constants for better code readability
#
# Version: 0.4.0
#

# Lockfile timeout default (in seconds)
# Used to detect stale lockfiles from hung or crashed processes
readonly LOCKFILE_TIMEOUT_DEFAULT=300

# Time conversion constants (in seconds)
# Used for time-based calculations throughout the codebase
readonly SECONDS_PER_MINUTE=60
readonly SECONDS_PER_HOUR=3600
readonly SECONDS_PER_DAY=86400

# IPv6 validation constants
# Maximum number of segments allowed in an IPv6 address
readonly MAX_IPV6_SEGMENTS=8
# Minimum hex digits per IPv6 segment (RFC 4291)
readonly MIN_IPV6_SEGMENT_HEX_DIGITS=1
# Maximum hex digits per IPv6 segment (RFC 4291)
readonly MAX_IPV6_SEGMENT_HEX_DIGITS=4

# IPv4 validation constants
# Maximum value for an IPv4 octet (0-255)
readonly MAX_IPV4_OCTET=255
# Number of octets in an IPv4 address
readonly IPV4_OCTET_COUNT=4
# CIDR notation for single host (used when adding IP addresses to interfaces)
readonly IPV4_CIDR_SINGLE_HOST=32

# Ping check constants
# Packet loss threshold for ping failure (100% = complete failure)
readonly PING_PACKET_LOSS_THRESHOLD=100

# xfrm output parsing constants
# Number of context lines to show after grep match when parsing xfrm state output
# Used to capture byte counter information that appears after SA entries
readonly XFRM_OUTPUT_CONTEXT_LINES=10

# Recovery constants
# Sleep delay (in seconds) after xfrm SA deletion to allow IKE re-establishment
# Gives strongSwan time to detect SA deletion and initiate re-establishment
readonly XFRM_RECOVERY_SLEEP_SECONDS=3
# Maximum time (in seconds) to wait for SA re-establishment after deletion
# Verification checks are performed with retries up to this timeout
readonly XFRM_RECOVERY_VERIFY_TIMEOUT=30
# Interval (in seconds) between verification retry attempts
readonly XFRM_RECOVERY_VERIFY_INTERVAL=2
# Maximum interval (in seconds) for exponential backoff during recovery verification
# Used to cap the exponential backoff interval growth
readonly XFRM_RECOVERY_MAX_INTERVAL=16
