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
	local external_peer_ip="$1"
	local internal_ip="${2:-$external_peer_ip}"

	cat <<EOF
LOCATION_TEST_EXTERNAL="${external_peer_ip}"
LOCATION_TEST_INTERNAL="${internal_ip}"
EOF
}

# Generate standard configuration template
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
generate_config_standard() {
	local external_peer_ip="$1"
	local internal_ip="${2:-$external_peer_ip}"

	cat <<EOF
LOCATION_TEST_EXTERNAL="${external_peer_ip}"
LOCATION_TEST_INTERNAL="${internal_ip}"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=2
TIER3_THRESHOLD=3
MAX_RESTARTS_PER_WINDOW=20
RATE_LIMIT_WINDOW_MINUTES=60
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
	local external_peer_ip="$1"
	local log_file="$2"
	local internal_ip="${3:-$external_peer_ip}"

	cat <<EOF
LOCATION_TEST_EXTERNAL="${external_peer_ip}"
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
TIER1_THRESHOLD=1
TIER2_THRESHOLD=2
TIER3_THRESHOLD=3
MAX_RESTARTS_PER_WINDOW=20
RATE_LIMIT_WINDOW_MINUTES=60
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

# Generate configuration for rate limit testing
#
# Arguments:
#   $1: External peer IP
#   $2: Max restarts per window (optional, defaults to 20)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints configuration content to stdout
generate_config_rate_limit() {
	local external_peer_ip="$1"
	local max_restarts="${2:-20}"

	cat <<EOF
LOCATION_NYC_EXTERNAL="${external_peer_ip}"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=2
TIER3_THRESHOLD=3
MAX_RESTARTS_PER_WINDOW=${max_restarts}
RATE_LIMIT_WINDOW_MINUTES=60
ENABLE_XFRM_RECOVERY=0
ENABLE_NETWORK_PARTITION_CHECK=0
ENABLE_RESOURCE_MONITORING=0
EOF
}
