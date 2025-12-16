#!/bin/bash
#
# Constants for UDM VPN Monitor
# Defines commonly used magic numbers as named constants for better code readability
#
# Version: 0.0.1
#

# Lockfile timeout default (in seconds)
# Used to detect stale lockfiles from hung or crashed processes
readonly LOCKFILE_TIMEOUT_DEFAULT=300

# Time conversion constants (in seconds)
# Used for time-based calculations throughout the codebase
readonly SECONDS_PER_HOUR=3600
readonly SECONDS_PER_DAY=86400

# IPv6 validation constant
# Maximum number of segments allowed in an IPv6 address
readonly MAX_IPV6_SEGMENTS=8
