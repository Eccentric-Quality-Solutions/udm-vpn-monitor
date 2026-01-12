#!/usr/bin/env bash
#
# Configuration File Templates
#
# Common configuration file templates for testing.
# These templates can be used to generate test configuration files.

# Generate minimal configuration template
#
# Arguments:
#   $1: External peer IP
#   $2: Internal peer IP (optional, defaults to external IP)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints configuration content to stdout
generate_config_minimal() {
	local external_ip="$1"
	local internal_ip="${2:-$external_ip}"

	cat <<EOF
LOCATION_TEST_EXTERNAL="${external_ip}"
LOCATION_TEST_INTERNAL="${internal_ip}"
EOF
}

# Generate standard configuration template
#
# Arguments:
#   $1: External peer IP
#   $2: Internal peer IP (optional, defaults to external IP)
#   $3: VPN name (optional, defaults to "Test VPN")
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints configuration content to stdout
generate_config_standard() {
	local external_ip="$1"
	local internal_ip="${2:-$external_ip}"
	local vpn_name="${3:-Test VPN}"

	cat <<EOF
LOCATION_TEST_EXTERNAL="${external_ip}"
LOCATION_TEST_INTERNAL="${internal_ip}"
VPN_NAME="${vpn_name}"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
COOLDOWN_MINUTES=15
MAX_RESTARTS_PER_HOUR=3
LOG_FILE="/data/vpn-monitor/logs/vpn-monitor.log"
STATE_DIR="/data/vpn-monitor"
CRON_SCHEDULE="*/1 * * * *"
LOCKFILE_TIMEOUT=60
ENABLE_PING_CHECK=1
PING_COUNT=3
PING_TIMEOUT=2
DEBUG=0
EOF
}

# Generate configuration with custom log file
#
# Arguments:
#   $1: External peer IP
#   $2: Log file path
#   $3: Internal peer IP (optional, defaults to external IP)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints configuration content to stdout
generate_config_custom_log() {
	local external_ip="$1"
	local log_file="$2"
	local internal_ip="${3:-$external_ip}"

	cat <<EOF
LOCATION_TEST_EXTERNAL="${external_ip}"
LOCATION_TEST_INTERNAL="${internal_ip}"
LOG_FILE="${log_file}"
EOF
}

# Generate configuration with multiple locations
#
# Arguments:
#   $1: First external peer IP
#   $2: First internal peer IP (optional)
#   $3: Second external peer IP
#   $4: Second internal peer IP (optional)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints configuration content to stdout
generate_config_multiple_locations() {
	local ext1="$1"
	local int1="${2:-$ext1}"
	local ext2="$3"
	local int2="${4:-$ext2}"

	cat <<EOF
LOCATION_TEST_EXTERNAL="${ext1}"
LOCATION_TEST_INTERNAL="${int1}"
LOCATION_TEST2_EXTERNAL="${ext2}"
LOCATION_TEST2_INTERNAL="${int2}"
VPN_NAME="Test VPN"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
COOLDOWN_MINUTES=15
MAX_RESTARTS_PER_HOUR=3
LOG_FILE="/data/vpn-monitor/logs/vpn-monitor.log"
STATE_DIR="/data/vpn-monitor"
CRON_SCHEDULE="*/1 * * * *"
LOCKFILE_TIMEOUT=60
ENABLE_PING_CHECK=1
PING_COUNT=3
PING_TIMEOUT=2
DEBUG=0
EOF
}

# Generate configuration for cooldown and rate limit testing
#
# Arguments:
#   $1: External peer IP
#   $2: Cooldown minutes (optional, defaults to 1)
#   $3: Max restarts per hour (optional, defaults to 3)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints configuration content to stdout
generate_config_cooldown_rate_limit() {
	local external_ip="$1"
	local cooldown_minutes="${2:-1}"
	local max_restarts="${3:-3}"

	cat <<EOF
LOCATION_NYC_EXTERNAL="${external_ip}"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
MAX_RESTARTS_PER_HOUR=${max_restarts}
COOLDOWN_MINUTES=${cooldown_minutes}
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
ENABLE_RESOURCE_MONITORING=0
EOF
}
