#!/bin/bash
#
# Constants for UDM VPN Monitor
# Defines commonly used magic numbers as named constants for better code readability
#
# Usage Guidelines:
#   - Always use these constants instead of magic numbers in code
#   - Add new constants here when a value is used in multiple places or has semantic meaning
#   - For module-specific constants (e.g., recovery), see lib/recovery/constants.sh
#
# Sourcing:
#   This file is safe to source multiple times (idempotent).
#   Constants are only defined if not already set.
#
# Version: 0.6.0
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
# Success threshold for multiple internal IPs (0.3 = 30% must respond)
# For locations with multiple internal IPs, VPN is considered healthy if ≥30% respond to pings
# This threshold is used with ceil() rounding (e.g., 2 IPs requires 1 success, 10 IPs requires 3)
readonly PING_SUCCESS_THRESHOLD=0.3
# Adjustment value for ceiling calculation (0.999 ensures proper rounding up)
# Used in awk calculation: int((count * PING_SUCCESS_THRESHOLD) + PING_CEIL_ADJUSTMENT)
# This ensures ceil() behavior: ceil(0.3 * 2) = 1, ceil(0.3 * 10) = 3
readonly PING_CEIL_ADJUSTMENT=0.999

# xfrm output parsing constants
# Number of context lines to show after grep match when parsing xfrm state output
# Used to capture byte counter information that appears after SA entries
readonly XFRM_OUTPUT_CONTEXT_LINES=10

# Command timeout constants
# Timeout (in seconds) for ipsec status command to prevent hanging
# Prevents ipsec status from blocking script execution indefinitely
# Used across detection and recovery modules
readonly IPSEC_STATUS_TIMEOUT=5
# Timeout (in seconds) for state file read operations to prevent hanging
# Defensive timeout wrapper for file reading operations (cat, grep, wc, etc.)
# Prevents hangs from race conditions, test suite timing issues, or edge cases
# Used when reading state files even after file_exists_and_readable checks
readonly STATE_FILE_READ_TIMEOUT=1

# Error code constants
# Standard exit codes for consistent error handling throughout the codebase
# These constants should be used instead of magic numbers for better readability
# and maintainability. Always use these constants instead of hardcoded exit codes.
#
# Exit Code Meanings:
#   EXIT_SUCCESS (0)           - Successful operation, normal completion
#   EXIT_GENERAL_ERROR (1)     - General/unclassified error, catch-all for unexpected failures
#   EXIT_CONFIG_ERROR (2)      - Configuration file error (file not found, unreadable, parse error)
#   EXIT_VALIDATION_ERROR (3)  - Validation error (invalid values, missing required fields, type mismatches)
#   EXIT_PERMISSION_ERROR (4) - Permission denied (file/directory not writable, insufficient privileges)
#   EXIT_COMMAND_NOT_FOUND (5) - Required command or utility not found in PATH
#   EXIT_STATE_ERROR (6)      - State file error (corruption, unreadable, checksum failure)
#
# Usage Guidelines:
#   - Use EXIT_SUCCESS for successful completion
#   - Use EXIT_GENERAL_ERROR for unexpected errors that don't fit other categories
#   - Use EXIT_CONFIG_ERROR when config file cannot be loaded or parsed
#   - Use EXIT_VALIDATION_ERROR when config values fail validation rules
#   - Use EXIT_PERMISSION_ERROR when file/directory operations fail due to permissions
#   - Use EXIT_COMMAND_NOT_FOUND when required commands are missing
#   - Use EXIT_STATE_ERROR when state file operations fail
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_CONFIG_ERROR=2
readonly EXIT_VALIDATION_ERROR=3
readonly EXIT_PERMISSION_ERROR=4
readonly EXIT_COMMAND_NOT_FOUND=5
readonly EXIT_STATE_ERROR=6
