#!/bin/bash
#
# UDM VPN Monitor
# Monitors Site-to-Site VPN connections using IPsec xfrm state byte counters
# Implements tiered recovery: log → surgical cleanup → full restart
#
# Designed for UniFi Dream Machine (UDM) running UniFi OS 4.3+
#

# Strict error handling: exit on error, undefined vars, pipe failures
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/vpn-monitor.conf"
STATE_DIR="${SCRIPT_DIR}"
LOGS_DIR="${STATE_DIR}/logs"
LOCKFILE="${STATE_DIR}/vpn-monitor.lock"
LOG_FILE="${LOGS_DIR}/vpn-monitor.log"

# Default configuration values
PEER_IPS=""
VPN_NAME="Site-to-Site VPN"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
COOLDOWN_MINUTES=15
MAX_RESTARTS_PER_HOUR=3
LOCKFILE_TIMEOUT=300
ENABLE_PING_CHECK=1
PING_TARGET_IP=""
PING_COUNT=3
PING_TIMEOUT=2
DEBUG=0
# Debug mode flag: when set, runs checks but doesn't escalate tiers
NO_ESCALATE=0

# Ensure state directory exists (needed before logging)
mkdir -p "$STATE_DIR" || {
    echo "ERROR: Cannot create state directory: $STATE_DIR" >&2
    exit 1
}

# Ensure logs directory exists (needed before logging)
mkdir -p "$LOGS_DIR" || {
    echo "ERROR: Cannot create logs directory: $LOGS_DIR" >&2
    exit 1
}

# State files
# Note: Failure counters are per-peer: ${LOGS_DIR}/failure_counter_<peer_ip_sanitized>
LAST_RESTART_FILE="${STATE_DIR}/last_restart"
RESTART_COUNT_FILE="${LOGS_DIR}/restart_count"
# LAST_BYTES_FILE will be per-peer: ${STATE_DIR}/last_bytes_${peer_ip_sanitized}
COOLDOWN_UNTIL_FILE="${STATE_DIR}/cooldown_until"

# Logging function (defined early so it can be used during config loading)
# Note: This function must not cause script exit even if logging fails
#
# Logs a message with timestamp and level to both log file and stderr (for errors/warnings/debug)
# This function is designed to be resilient - it will not fail the script if logging fails
#
# Arguments:
#   $1: Log level (INFO, WARNING, ERROR, DEBUG)
#   $2+: Message text (all remaining arguments are concatenated)
#
# Returns:
#   0: Always returns 0 (never fails the script)
#
# Output:
#   - Writes to LOG_FILE (append mode)
#   - Outputs ERROR/WARNING/DEBUG to stderr
#   - Creates log directory if it doesn't exist
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')
    
    # Always output to stderr first for debugging
    local log_entry="[$timestamp] [$level] $message"
    
    # Ensure log directory exists and is writable
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if [[ ! -d "$log_dir" ]]; then
        if ! mkdir -p "$log_dir" 2>/dev/null; then
            echo "$log_entry" >&2
            echo "[$timestamp] [ERROR] Cannot create log directory: $log_dir" >&2
            return 0  # Don't fail the script if logging fails
        fi
    fi
    
    # Write to log file (append, create if doesn't exist)
    # Try to write, but don't fail the script if it doesn't work
    {
        echo "$log_entry" >> "$LOG_FILE" 2>&1
    } || {
        # If write failed, at least we tried - output to stderr
        echo "$log_entry" >&2
        echo "[$timestamp] [ERROR] Failed to write to log file: $LOG_FILE" >&2
    }
    
    # Always output ERROR and WARNING to stderr, and DEBUG if enabled
    if [[ "${DEBUG:-0}" -eq 1 ]] || [[ "$level" == "ERROR" ]] || [[ "$level" == "WARNING" ]]; then
        echo "$log_entry" >&2
    fi
    
    return 0
}

# Test log file write capability early
if ! touch "$LOG_FILE" 2>/dev/null; then
    echo "ERROR: Cannot write to log file: $LOG_FILE" >&2
    echo "ERROR: Check permissions on directory: $(dirname "$LOG_FILE")" >&2
    exit 1
fi

# Verify logging works by writing a test message
# This ensures log_message function will work before we proceed
if ! echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Log file initialized" >> "$LOG_FILE" 2>/dev/null; then
    echo "ERROR: Cannot write to log file after touch test: $LOG_FILE" >&2
    exit 1
fi

# Load configuration if it exists
if [[ -f "$CONFIG_FILE" ]]; then
    # Validate config file is readable and not empty
    if [[ ! -r "$CONFIG_FILE" ]]; then
        log_message "ERROR" "Configuration file is not readable: $CONFIG_FILE"
        exit 1
    fi
    # shellcheck source=/dev/null
    # Source config file to load user-defined variables (overrides defaults)
    if ! source "$CONFIG_FILE" 2>&1; then
        log_message "ERROR" "Failed to source configuration file: $CONFIG_FILE"
        exit 1
    fi
    log_message "INFO" "Configuration loaded from: $CONFIG_FILE"
else
    log_message "WARNING" "Configuration file not found: $CONFIG_FILE"
    log_message "WARNING" "Using default configuration values"
fi

# Recalculate LOGS_DIR after config loading (in case STATE_DIR was overridden)
# If LOG_FILE was set in config, derive LOGS_DIR from LOG_FILE, otherwise use STATE_DIR/logs
if [[ "$LOG_FILE" != "${LOGS_DIR}/vpn-monitor.log" ]]; then
    # LOG_FILE was overridden in config, derive LOGS_DIR from it
    LOGS_DIR=$(dirname "$LOG_FILE")
else
    # LOG_FILE not overridden, use STATE_DIR/logs
    LOGS_DIR="${STATE_DIR}/logs"
    LOG_FILE="${LOGS_DIR}/vpn-monitor.log"
fi

# Ensure logs directory exists after config loading (in case paths changed)
mkdir -p "$LOGS_DIR" || {
    log_message "ERROR" "Cannot create logs directory: $LOGS_DIR"
    exit 1
}

# Update state file paths to use LOGS_DIR (in case STATE_DIR was overridden)
# Note: Failure counters are per-peer: ${LOGS_DIR}/failure_counter_<peer_ip_sanitized>
RESTART_COUNT_FILE="${LOGS_DIR}/restart_count"

# Initialize state files if they don't exist
#
# Creates required state files (restart_count) if they don't exist.
# Per-peer failure counter and byte counter files are created on-demand when needed.
#
# State files:
#   - RESTART_COUNT_FILE: Tracks restart timestamps for rate limiting
#   - Per-peer failure counters: Created on-demand as failure_counter_<peer_ip>
#   - Per-peer byte counters: Created on-demand as last_bytes_<peer_ip>
#
# Returns:
#   0: Always succeeds (warnings logged but don't fail)
init_state() {
    if [[ ! -f "$RESTART_COUNT_FILE" ]]; then
        echo "0" > "$RESTART_COUNT_FILE" || log_message "WARNING" "Failed to create restart count file"
    fi
    # Per-peer failure counters and byte counters are created on-demand
}

# Get current failure counter for a specific peer
#
# Reads the current consecutive failure count from the per-peer state file.
# Each peer has its own independent failure counter.
#
# Arguments:
#   $1: Peer IP address
#
# Returns:
#   Current failure count (0 if file doesn't exist or is empty)
#
# Output:
#   Prints the failure count to stdout
get_failure_count() {
    local peer_ip="$1"
    local peer_sanitized
    peer_sanitized=$(sanitize_peer_ip "$peer_ip")
    local counter_file="${LOGS_DIR}/failure_counter_${peer_sanitized}"
    
    if [[ -f "$counter_file" ]]; then
        cat "$counter_file"
    else
        echo "0"
    fi
}

# Increment failure counter for a specific peer
#
# Increments the consecutive failure counter by 1 and saves it to the per-peer state file.
# Used to track how many times in a row the VPN check has failed for this specific peer.
# Each peer has its own independent failure counter.
#
# Arguments:
#   $1: Peer IP address
#
# Returns:
#   New failure count value
#
# Output:
#   Prints the new failure count to stdout
increment_failure() {
    local peer_ip="$1"
    local peer_sanitized
    peer_sanitized=$(sanitize_peer_ip "$peer_ip")
    local counter_file="${LOGS_DIR}/failure_counter_${peer_sanitized}"
    local count
    count=$(get_failure_count "$peer_ip")
    echo $((count + 1)) > "$counter_file"
    echo $((count + 1))
}

# Reset failure counter for a specific peer
#
# Resets the consecutive failure counter to 0 for the specified peer.
# Called when VPN check succeeds after previous failures for this peer.
# Each peer has its own independent failure counter.
#
# Arguments:
#   $1: Peer IP address
#
# Returns:
#   0: Always succeeds
reset_failure_count() {
    local peer_ip="$1"
    local peer_sanitized
    peer_sanitized=$(sanitize_peer_ip "$peer_ip")
    local counter_file="${LOGS_DIR}/failure_counter_${peer_sanitized}"
    echo "0" > "$counter_file"
}

# Check if we're in cooldown period
#
# Verifies if the script is currently in a cooldown period after a restart.
# Cooldown periods prevent immediate re-restarts and allow VPN to stabilize.
#
# Returns:
#   0: Currently in cooldown period
#   1: Not in cooldown (or cooldown expired)
#
# Side effects:
#   Removes cooldown file if it has expired
check_cooldown() {
    if [[ ! -f "$COOLDOWN_UNTIL_FILE" ]]; then
        return 1  # Not in cooldown
    fi
    
    local cooldown_until
    cooldown_until=$(cat "$COOLDOWN_UNTIL_FILE")
    local now
    now=$(date +%s)
    
    if [[ $now -lt $cooldown_until ]]; then
        local remaining
        remaining=$((cooldown_until - now))
        log_message "INFO" "In cooldown period, $remaining seconds remaining"
        return 0  # In cooldown
    else
        # Cooldown expired, remove file
        rm -f "$COOLDOWN_UNTIL_FILE"
        return 1  # Not in cooldown
    fi
}

# Set cooldown period
#
# Sets a cooldown period to prevent immediate re-restarts after a full restart.
# The cooldown period is stored as a timestamp in COOLDOWN_UNTIL_FILE.
#
# Arguments:
#   $1: Cooldown duration in minutes
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Creates/updates COOLDOWN_UNTIL_FILE with expiration timestamp
set_cooldown() {
    local minutes="$1"
    local cooldown_until
    # Try Linux date format first, then BSD/macOS, fallback to manual calculation
    # +%s: output as seconds since epoch
    cooldown_until=$(date -d "+${minutes} minutes" +%s 2>/dev/null || date -v+${minutes}M +%s 2>/dev/null || echo $(( $(date +%s) + minutes * 60 )))
    echo "$cooldown_until" > "$COOLDOWN_UNTIL_FILE"
    log_message "INFO" "Cooldown period set for $minutes minutes"
}

# Check rate limiting
#
# Verifies if the maximum number of restarts per hour has been exceeded.
# Prevents restart loops by limiting how frequently full restarts can occur.
#
# Returns:
#   0: Within rate limit (restart allowed)
#   1: Rate limit exceeded (restart blocked)
#
# Note:
#   Checks RESTART_COUNT_FILE for timestamps within the last hour
check_rate_limit() {
    local now
    now=$(date +%s)
    local one_hour_ago
    one_hour_ago=$((now - 3600))
    
    # Get restart count file (format: timestamp per line)
    if [[ ! -f "$RESTART_COUNT_FILE" ]]; then
        return 0  # No previous restarts, allow
    fi
    
    # Count restarts in the last hour
    # awk filters timestamps > one_hour_ago, wc -l counts lines, tr removes whitespace
    local recent_restarts
    recent_restarts=$(awk -v cutoff="$one_hour_ago" '$1 > cutoff' "$RESTART_COUNT_FILE" 2>/dev/null | wc -l | tr -d ' ')
    
    if [[ $recent_restarts -ge $MAX_RESTARTS_PER_HOUR ]]; then
        log_message "WARNING" "Rate limit exceeded: $recent_restarts restarts in last hour (max: $MAX_RESTARTS_PER_HOUR)"
        return 1  # Rate limited
    fi
    
    return 0  # Within rate limit
}

# Record restart timestamp
#
# Records the current timestamp to RESTART_COUNT_FILE for rate limiting.
# Also cleans up old entries (older than 24 hours) to prevent file growth.
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Appends timestamp to RESTART_COUNT_FILE
#   - Updates LAST_RESTART_FILE with current timestamp
#   - Removes entries older than 24 hours from RESTART_COUNT_FILE
record_restart() {
    local timestamp
    timestamp=$(date +%s)
    echo "$timestamp" >> "$RESTART_COUNT_FILE"
    
    # Keep only last 24 hours of timestamps (cleanup old entries)
    # Prevents restart count file from growing indefinitely
    local one_day_ago
    one_day_ago=$((timestamp - 86400))
    # awk filters lines where first field (timestamp) > cutoff, writes to temp file
    awk -v cutoff="$one_day_ago" '$1 > cutoff' "$RESTART_COUNT_FILE" > "${RESTART_COUNT_FILE}.tmp" 2>/dev/null || true
    mv "${RESTART_COUNT_FILE}.tmp" "$RESTART_COUNT_FILE" 2>/dev/null || true
    
    echo "$timestamp" > "$LAST_RESTART_FILE"
}

# Sanitize peer IP for use in filenames
#
# Converts IP address characters that are unsafe for filenames to underscores.
# Used to create per-peer state files (e.g., last_bytes_192_168_1_1).
#
# Arguments:
#   $1: IP address (IPv4 or IPv6)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints sanitized IP address to stdout (dots and colons replaced with underscores)
sanitize_peer_ip() {
    local ip="$1"
    echo "$ip" | tr '.' '_' | tr ':' '_'
}

# Check connectivity via ping
#
# Verifies end-to-end connectivity through the VPN tunnel by pinging a target IP.
# This complements xfrm state checks by confirming actual traffic can flow.
#
# Arguments:
#   $1: Target IP address to ping (IPv4 or IPv6)
#
# Returns:
#   0: Ping successful (packet loss < 100%)
#   1: Ping failed (100% packet loss or command error)
#
# Configuration:
#   Uses PING_COUNT and PING_TIMEOUT from config file
#   Automatically detects IPv4 vs IPv6 and uses appropriate ping command
#
# Note:
#   Tries multiple ping command formats for compatibility (Linux/BSD)
check_ping_connectivity() {
    local target_ip="$1"
    local ping_count="${PING_COUNT:-3}"
    local ping_timeout="${PING_TIMEOUT:-2}"
    
    # Validate ping target
    if [[ -z "$target_ip" ]]; then
        log_message "WARNING" "Ping check enabled but PING_TARGET_IP not configured"
        return 1
    fi
    
    # Check if ping command is available
    if ! command -v ping >/dev/null 2>&1; then
        log_message "WARNING" "Ping check enabled but ping command not available"
        return 1
    fi
    
    # Determine ping command based on IP version
    # Some systems have separate ping6, others use ping -6
    local ping_cmd
    if [[ "$target_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # IPv4
        ping_cmd="ping"
    else
        # IPv6
        if command -v ping6 >/dev/null 2>&1; then
            ping_cmd="ping6"
        elif ping -6 >/dev/null 2>&1; then
            ping_cmd="ping -6"
        else
            log_message "WARNING" "IPv6 ping not available"
            return 1
        fi
    fi
    
    # Perform ping check
    # Try Linux-style ping first (-W for timeout), fallback to BSD-style (-w)
    # -c: count of packets, -q: quiet (summary only), -W/-w: timeout per packet
    local ping_result
    local ping_success=0
    
    # Try Linux-style ping (most common on UDM)
    if ping_result=$($ping_cmd -c "$ping_count" -W "$ping_timeout" -q "$target_ip" 2>&1); then
        ping_success=1
    # Try BSD-style ping as fallback
    elif ping_result=$($ping_cmd -c "$ping_count" -w "$ping_timeout" -q "$target_ip" 2>&1); then
        ping_success=1
    # Try without timeout flag (some systems)
    elif ping_result=$($ping_cmd -c "$ping_count" -q "$target_ip" 2>&1); then
        ping_success=1
    fi
    
    if [[ $ping_success -eq 1 ]]; then
        # Extract packet loss percentage
        local packet_loss
        packet_loss=$(echo "$ping_result" | grep -oE '[0-9]+% packet loss' | grep -oE '[0-9]+' || echo "100")
        
        if [[ "$packet_loss" -lt 100 ]]; then
            log_message "DEBUG" "Ping check OK: $target_ip (${packet_loss}% packet loss)"
            return 0
        else
            log_message "WARNING" "Ping check failed: $target_ip (100% packet loss)"
            return 1
        fi
    else
        # Ping command failed
        log_message "WARNING" "Ping check failed: $target_ip (ping command error or timeout)"
        return 1
    fi
}

# Check VPN status using ip xfrm state
#
# Verifies VPN tunnel health by checking IPsec Security Association (SA) state and byte counters.
# Uses multiple methods in order: ip xfrm state (primary), swanctl (fallback), ipsec status (fallback).
# If ping checks are enabled, also verifies end-to-end connectivity.
#
# Arguments:
#   $1: Peer IP address (external/public IP of remote VPN gateway)
#
# Returns:
#   0: VPN is healthy (SA exists, bytes increasing or non-zero)
#   1: VPN check failed (no SA found or bytes not increasing)
#
# Detection logic:
#   1. Checks ip xfrm state for SA matching peer IP
#   2. Validates byte counters are > 0 and increasing (if available)
#   3. Falls back to swanctl --list-sas if xfrm doesn't confirm
#   4. Falls back to ipsec status if swanctl doesn't confirm
#   5. Optionally performs ping check if ENABLE_PING_CHECK=1
#
# Side effects:
#   - Creates/updates per-peer last_bytes file if byte counters found
#   - Logs debug/warning messages about VPN state
check_vpn_status() {
    local peer_ip="$1"
    local vpn_ok=0
    
    # Validate peer IP format (basic check)
    # IPv4: 4 octets separated by dots (e.g., 192.168.1.1)
    # IPv6: hex digits and colons (simplified - allows :: compression)
    if [[ ! "$peer_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # Not IPv4, check if it looks like IPv6 (has colons and hex digits)
        if [[ ! "$peer_ip" =~ ^[0-9a-fA-F:]+$ ]] || [[ "$peer_ip" =~ ^:+$ ]] || [[ "$peer_ip" =~ ::: ]]; then
            log_message "ERROR" "Invalid peer IP format: $peer_ip"
            return 1
        fi
    fi
    
    # Per-peer bytes file
    local peer_sanitized
    peer_sanitized=$(sanitize_peer_ip "$peer_ip")
    local last_bytes_file="${STATE_DIR}/last_bytes_${peer_sanitized}"
    
    # Try ip xfrm state first (most reliable)
    # xfrm = Linux IPsec framework - shows Security Associations (SAs) and byte counters
    if command -v ip >/dev/null 2>&1; then
        local xfrm_output
        # Use word boundaries to avoid partial IP matches (e.g., 192.168.1.1 matching 192.168.1.10)
        # -A 10: show 10 lines after match (to get byte counter info)
        xfrm_output=$(ip xfrm state 2>/dev/null | grep -E "(^|[^0-9a-fA-F:])${peer_ip}([^0-9a-fA-F:]|$)" -A 10 || true)
        
        if [[ -n "$xfrm_output" ]]; then
            # Check if we have byte counters
            if echo "$xfrm_output" | grep -q "lifetime current:"; then
                # Extract current bytes from xfrm output
                # Format: "lifetime current: 123456 bytes, 789 packets"
                # sed extracts the number between "bytes " and next space/comma
                local current_bytes
                current_bytes=$(echo "$xfrm_output" | grep "lifetime current:" | head -1 | sed -n 's/.*bytes \([0-9]*\).*/\1/p' || echo "0")
                
                # Get last known bytes
                local last_bytes=0
                if [[ -f "$last_bytes_file" ]]; then
                    last_bytes=$(cat "$last_bytes_file" 2>/dev/null || echo "0")
                fi
                
                # Check if bytes are increasing or at least non-zero
                if [[ -n "$current_bytes" ]] && [[ "$current_bytes" -gt 0 ]]; then
                    # Bytes are non-zero, check if they're increasing
                    if [[ "$current_bytes" -gt "$last_bytes" ]] || [[ "$last_bytes" -eq 0 ]]; then
                        # Bytes are increasing or this is first check
                        echo "$current_bytes" > "$last_bytes_file"
                        vpn_ok=1
                        log_message "DEBUG" "VPN OK: SA exists, bytes=$current_bytes (was $last_bytes)"
                    else
                        log_message "WARNING" "VPN suspect: SA exists but bytes not increasing (current=$current_bytes, last=$last_bytes)"
                    fi
                else
                    log_message "WARNING" "VPN suspect: SA exists but bytes=0 or unreadable"
                fi
            else
                # SA exists but no byte counter info
                log_message "DEBUG" "VPN OK: SA exists for $peer_ip (no byte counter info)"
                vpn_ok=1
            fi
        else
            log_message "WARNING" "VPN suspect: No SA found for $peer_ip in xfrm state"
        fi
    fi
    
    # Fallback to swanctl if xfrm didn't confirm
    # swanctl = strongSwan control utility (used by UDM for IPsec management)
    if [[ $vpn_ok -eq 0 ]] && command -v swanctl >/dev/null 2>&1; then
        local swanctl_output
        swanctl_output=$(swanctl --list-sas 2>/dev/null | grep -i "$peer_ip" || true)
        
        if [[ -n "$swanctl_output" ]]; then
            log_message "DEBUG" "VPN OK: SA found via swanctl for $peer_ip"
            vpn_ok=1
        else
            log_message "WARNING" "VPN suspect: No SA found via swanctl for $peer_ip"
        fi
    fi
    
    # Fallback to ipsec status if still not confirmed
    # ipsec = legacy IPsec tools (libreswan/strongswan compatibility command)
    if [[ $vpn_ok -eq 0 ]] && command -v ipsec >/dev/null 2>&1; then
        local ipsec_output
        ipsec_output=$(ipsec status 2>/dev/null | grep -i "$peer_ip" || true)
        
        if [[ -n "$ipsec_output" ]]; then
            log_message "DEBUG" "VPN OK: Connection found via ipsec status for $peer_ip"
            vpn_ok=1
        else
            log_message "WARNING" "VPN suspect: No connection found via ipsec status for $peer_ip"
        fi
    fi
    
    # If SA exists (vpn_ok=1), verify connectivity with ping check if enabled
    if [[ $vpn_ok -eq 1 ]] && [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
        # Determine ping target: use PING_TARGET_IP if configured, otherwise use peer_ip
        local ping_target="${PING_TARGET_IP:-$peer_ip}"
        
        if ! check_ping_connectivity "$ping_target"; then
            # SA exists but ping failed - tunnel may be broken
            log_message "WARNING" "VPN SA exists but ping check failed for $ping_target - tunnel may not be routing traffic"
            # Don't fail completely - SA exists, but mark as suspect
            # This allows xfrm to pass but warns about connectivity
            # If ping keeps failing, byte counters should also stop increasing
        else
            log_message "DEBUG" "VPN connectivity verified: ping check passed for $ping_target"
        fi
    elif [[ $vpn_ok -eq 0 ]] && [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
        # SA doesn't exist, but try ping anyway to see if there's any connectivity
        local ping_target="${PING_TARGET_IP:-$peer_ip}"
        if check_ping_connectivity "$ping_target"; then
            log_message "WARNING" "Ping check passed but no SA found - tunnel may be down but connectivity exists via other route"
        fi
    fi
    
    # Return 0 if OK, 1 if failed (invert vpn_ok: 1 becomes 0, 0 becomes 1)
    return $((1 - vpn_ok))
}

# Surgical SA cleanup (Tier 2 recovery)
#
# Attempts to clean up specific Security Associations for a peer.
# This is less disruptive than a full restart but still affects all IPsec tunnels.
#
# Arguments:
#   $1: Peer IP address to clean up
#
# Returns:
#   0: Always succeeds (even if cleanup commands fail)
#
# Actions:
#   1. Attempts to delete xfrm states matching peer IP (src and dst)
#   2. Reloads swanctl configuration to re-establish connections
#
# Side effects:
#   - Calls swanctl --reload which reloads ALL IPsec connections (not just the failing peer)
#   - May temporarily disrupt all Site-to-Site and remote user VPNs
#
# Note:
#   Without full selectors (src, dst, proto, spi), deletion may not be precise.
#   swanctl --reload reloads all connections, making this less "surgical" than intended.
#   Consider this a middle ground between logging (Tier 1) and full restart (Tier 3).
surgical_cleanup() {
    local peer_ip="$1"
    log_message "INFO" "Attempting surgical SA cleanup for $peer_ip"
    
    # Try to delete specific SA states
    # Note: ip xfrm state delete requires a full selector (src, dst, proto, spi)
    # Without full selector info, deletion may not work precisely
    # We'll attempt deletion and rely on swanctl reload to handle the rest
    if command -v ip >/dev/null 2>&1; then
        # Try to delete states matching this peer IP
        # Note: This may not work without full selectors, but we try anyway
        # The swanctl reload below will handle re-establishing connections
        ip xfrm state delete src "$peer_ip" 2>/dev/null || true
        ip xfrm state delete dst "$peer_ip" 2>/dev/null || true
        
        # Try to reload/restart just this connection if swanctl available
        # swanctl --reload: reloads configuration and re-establishes connections
        if command -v swanctl >/dev/null 2>&1; then
            swanctl --reload 2>/dev/null || true
        fi
        
        log_message "INFO" "Surgical cleanup completed for $peer_ip"
    else
        log_message "WARNING" "Cannot perform surgical cleanup: ip command not available"
    fi
}

# Full VPN restart (Tier 3 recovery)
#
# Performs a full restart of the IPsec service, affecting all VPN tunnels.
# This is the most disruptive recovery action and should only be used after other methods fail.
#
# Returns:
#   0: Restart successful
#   1: Restart failed (rate limited or command error)
#
# Actions:
#   1. Checks rate limiting (prevents restart loops)
#   2. Records restart timestamp for rate limiting
#   3. Executes 'ipsec restart' or 'swanctl --reload'
#   4. Sets cooldown period to allow VPN to stabilize
#
# Side effects:
#   - Affects ALL IPsec tunnels (not just the failing peer)
#   - Temporarily disrupts all Site-to-Site and remote user VPNs
#   - Sets cooldown period (COOLDOWN_MINUTES)
#
# Warning:
#   This is disruptive and should be a last resort. Consider adjusting thresholds
#   if this triggers too frequently.
full_restart() {
    log_message "WARNING" "Performing full IPsec restart (affects all VPN tunnels)"
    
    if ! check_rate_limit; then
        log_message "ERROR" "Rate limit exceeded, skipping full restart"
        return 1
    fi
    
    # Record restart
    record_restart
    
    # Perform restart
    if command -v ipsec >/dev/null 2>&1; then
        # Use PIPESTATUS to check exit code of ipsec, not tee
        # PIPESTATUS[0] = exit code of first command in pipe (ipsec), not tee
        if ! ipsec restart 2>&1 | tee -a "$LOG_FILE"; then
            log_message "ERROR" "Failed to restart IPsec service (exit code: ${PIPESTATUS[0]})"
            return 1
        fi
    elif command -v swanctl >/dev/null 2>&1; then
        # Use PIPESTATUS to check exit code of swanctl, not tee
        # PIPESTATUS[0] = exit code of first command in pipe (swanctl), not tee
        if ! swanctl --reload 2>&1 | tee -a "$LOG_FILE"; then
            log_message "ERROR" "Failed to reload swanctl (exit code: ${PIPESTATUS[0]})"
            return 1
        fi
    else
        log_message "ERROR" "Neither ipsec nor swanctl command available"
        return 1
    fi
    
    log_message "INFO" "Full IPsec restart completed"
    set_cooldown "$COOLDOWN_MINUTES"
    return 0
}

# Main monitoring function
#
# Monitors a single VPN peer and implements tiered recovery escalation.
# Checks VPN status and escalates recovery actions based on failure count thresholds.
#
# Arguments:
#   $1: Peer IP address to monitor
#
# Returns:
#   0: VPN is healthy (or recovered)
#   1: VPN check failed (or recovery actions taken)
#
# Tier escalation:
#   - Tier 1 (TIER1_THRESHOLD): Logging only
#   - Tier 2 (TIER2_THRESHOLD): Surgical SA cleanup (affects all tunnels)
#   - Tier 3 (TIER3_THRESHOLD): Full IPsec restart (affects all tunnels)
#
# Side effects:
#   - Increments per-peer failure counter on VPN check failure
#   - Resets per-peer failure counter on VPN recovery
#   - Executes recovery actions based on failure count
#   - Logs all actions and status changes
#
# Note:
#   Each peer has its own independent failure counter tracked in:
#   ${LOGS_DIR}/failure_counter_<peer_ip_sanitized>
#   This allows independent failure tracking and recovery per peer.
monitor_peer() {
    local peer_ip="$1"
    local failure_count
    
    # Check VPN status
    if check_vpn_status "$peer_ip"; then
        # VPN is OK
        failure_count=$(get_failure_count "$peer_ip")
        if [[ $failure_count -gt 0 ]]; then
            log_message "INFO" "VPN recovered for $peer_ip after $failure_count failures"
            reset_failure_count "$peer_ip"
        fi
        return 0
    else
        # VPN check failed
        failure_count=$(increment_failure "$peer_ip")
        log_message "WARNING" "VPN check failed for $peer_ip (failure count: $failure_count)"
        
        # Tier 1: Logging (triggers when failure_count >= TIER1_THRESHOLD)
        if [[ $failure_count -ge $TIER1_THRESHOLD ]]; then
            log_message "INFO" "Tier 1: Logging failure for $peer_ip"
        fi
        
        # Tier 2: Surgical cleanup
        if [[ $failure_count -ge $TIER2_THRESHOLD ]] && [[ $failure_count -lt $TIER3_THRESHOLD ]]; then
            if [[ $NO_ESCALATE -eq 1 ]]; then
                log_message "INFO" "Tier 2: Would attempt surgical SA cleanup for $peer_ip (skipped in fake mode)"
            else
                log_message "WARNING" "Tier 2: Attempting surgical SA cleanup for $peer_ip"
                surgical_cleanup "$peer_ip"
            fi
        fi
        
        # Tier 3: Full restart
        if [[ $failure_count -ge $TIER3_THRESHOLD ]]; then
            if [[ $NO_ESCALATE -eq 1 ]]; then
                log_message "INFO" "Tier 3: Would attempt full IPsec restart (skipped in fake mode)"
            else
                log_message "ERROR" "Tier 3: Attempting full IPsec restart"
                if full_restart; then
                    reset_failure_count "$peer_ip"
                fi
            fi
        fi
        
        return 1
    fi
}

# Check cron persistence
#
# Verifies that the cron job entry still exists in the crontab.
# This helps detect if cron jobs were removed during UniFi OS upgrades.
#
# Returns:
#   0: Always succeeds (warnings logged but don't fail script)
#
# Side effects:
#   Logs warning if cron job not found
#
# Note:
#   This check is performed once per script run (tracked via .cron_checked file)
#   to avoid log spam on every execution.
check_cron_persistence() {
    if ! crontab -l 2>/dev/null | grep -q "vpn-monitor.sh"; then
        log_message "WARNING" "Cron job not found! Persistence may have been lost."
        log_message "WARNING" "Re-run install.sh to restore cron job."
    fi
}

# Parse command-line arguments
#
# Processes command-line arguments and sets corresponding global flags.
#
# Arguments:
#   $@: Command-line arguments
#
# Supported options:
#   --fake: Enable fake mode (NO_ESCALATE=1) - runs checks but doesn't escalate tiers
#   --help, -h: Display help message and exit
#
# Returns:
#   0: Always succeeds (exits with 0 for --help)
#
# Side effects:
#   Sets NO_ESCALATE flag if --fake is provided
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --fake)
                NO_ESCALATE=1
                log_message "INFO" "Fake mode enabled: tier escalation disabled"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --fake     Run checks and log failures but don't escalate tiers"
                echo "  --help     Show this help message"
                echo ""
                exit 0
                ;;
            *)
                log_message "WARNING" "Unknown argument: $1 (use --help for usage)"
                shift
                ;;
        esac
    done
}

# Main execution
#
# Main entry point for the VPN monitor script.
# Initializes state, checks cooldown, validates configuration, and monitors all configured peers.
#
# Arguments:
#   $@: Command-line arguments (passed to parse_args)
#
# Returns:
#   0: All peers healthy or checks completed successfully
#   1: One or more peers failed checks or configuration error
#
# Execution flow:
#   1. Parse command-line arguments
#   2. Initialize state files
#   3. Check cooldown period (exit if in cooldown)
#   4. Check cron persistence (once per run)
#   5. Validate PEER_IPS configuration
#   6. Monitor each configured peer IP
#   7. Exit with appropriate status code
#
# Side effects:
#   - Creates state files and directories
#   - Writes to log file
#   - May execute recovery actions (if not in fake mode)
main() {
    # Parse command-line arguments
    parse_args "$@"
    
    # Log script start
    if [[ $NO_ESCALATE -eq 1 ]]; then
        log_message "INFO" "VPN monitor script started in fake mode (PID: $$) - tier escalation disabled"
    else
        log_message "INFO" "VPN monitor script started (PID: $$)"
    fi
    
    # Debug output (only if DEBUG=1)
    if [[ "${DEBUG:-0}" -eq 1 ]]; then
        echo "DEBUG: Starting main() function, PID: $$" >&2
        echo "DEBUG: After log_message call" >&2
    fi
    
    # Initialize state
    if [[ "${DEBUG:-0}" -eq 1 ]]; then
        echo "DEBUG: Calling init_state()" >&2
    fi
    init_state
    if [[ "${DEBUG:-0}" -eq 1 ]]; then
        echo "DEBUG: After init_state()" >&2
    fi
    
    # Check cooldown
    if [[ "${DEBUG:-0}" -eq 1 ]]; then
        echo "DEBUG: Checking cooldown" >&2
    fi
    if check_cooldown; then
        if [[ "${DEBUG:-0}" -eq 1 ]]; then
            echo "DEBUG: In cooldown, exiting" >&2
        fi
        log_message "INFO" "Script exiting: in cooldown period"
        exit 0
    fi
    if [[ "${DEBUG:-0}" -eq 1 ]]; then
        echo "DEBUG: Not in cooldown, continuing" >&2
    fi
    
    # Check cron persistence (first run only, to avoid log spam)
    if [[ ! -f "${STATE_DIR}/.cron_checked" ]]; then
        if [[ "${DEBUG:-0}" -eq 1 ]]; then
            echo "DEBUG: Checking cron persistence" >&2
        fi
        check_cron_persistence
        touch "${STATE_DIR}/.cron_checked"
    fi
    
    # Validate configuration
    if [[ "${DEBUG:-0}" -eq 1 ]]; then
        echo "DEBUG: Validating PEER_IPS (value: '${PEER_IPS}')" >&2
    fi
    if [[ -z "$PEER_IPS" ]]; then
        if [[ "${DEBUG:-0}" -eq 1 ]]; then
            echo "DEBUG: PEER_IPS is empty, logging error and exiting" >&2
        fi
        log_message "ERROR" "PEER_IPS not configured. Please set PEER_IPS in $CONFIG_FILE"
        exit 1
    fi
    if [[ "${DEBUG:-0}" -eq 1 ]]; then
        echo "DEBUG: PEER_IPS is configured, continuing" >&2
    fi
    
    # Validate and process each peer IP
    local all_ok=0
    for peer_ip in $PEER_IPS; do
        # Basic validation: non-empty and doesn't contain shell metacharacters
        if [[ -z "$peer_ip" ]]; then
            log_message "WARNING" "Skipping empty peer IP"
            continue
        fi
        # Check for dangerous characters that could be used for injection
        if [[ "$peer_ip" =~ [\`\$\(\)\<\>\|\;\&\*] ]]; then
            log_message "ERROR" "Invalid characters in peer IP: $peer_ip"
            all_ok=1
            continue
        fi
        if ! monitor_peer "$peer_ip"; then
            all_ok=1
        fi
    done
    
    if [[ $all_ok -eq 0 ]]; then
        log_message "INFO" "VPN monitor check completed successfully"
    else
        log_message "WARNING" "VPN monitor check completed with warnings/errors"
    fi
    
    exit $all_ok
}

# Check if lockfile is stale (exceeded timeout)
#
# Determines if an existing lockfile is stale (older than LOCKFILE_TIMEOUT seconds).
# Stale lockfiles indicate a hung or crashed previous instance.
#
# Returns:
#   0: Lockfile is stale (exceeded timeout)
#   1: Lockfile is not stale (or doesn't exist)
#
# Note:
#   Uses stat to get file modification time, handles both Linux and BSD/macOS formats
check_lockfile_stale() {
    if [[ ! -f "$LOCKFILE" ]]; then
        return 1  # No lockfile, not stale
    fi
    
    local lockfile_age
    local lockfile_mtime
    local now
    
    now=$(date +%s)
    # Try Linux stat format first, then BSD/macOS format
    # -c %Y: Linux format, modification time as seconds since epoch
    # -f %m: BSD/macOS format, modification time as seconds since epoch
    lockfile_mtime=$(stat -c %Y "$LOCKFILE" 2>/dev/null || stat -f %m "$LOCKFILE" 2>/dev/null || echo "0")
    
    if [[ $lockfile_mtime -eq 0 ]]; then
        # Can't get mtime, assume stale if file exists but unreadable
        return 0  # Consider stale
    fi
    
    lockfile_age=$((now - lockfile_mtime))
    
    if [[ $lockfile_age -gt $LOCKFILE_TIMEOUT ]]; then
        return 0  # Stale (exceeded timeout)
    fi
    
    return 1  # Not stale
}

# Run with lockfile protection
# flock = file locking utility (prevents multiple instances from running simultaneously)
if command -v flock >/dev/null 2>&1; then
    # Use flock if available (preferred method)
    # Open lockfile for writing, acquire exclusive non-blocking lock
    # File descriptor 9 is used for the lockfile
    (
        # Set up cleanup trap to ensure lock is released
        trap 'rm -f "$LOCKFILE"; exec 9>&-' EXIT INT TERM
        
        # Check if lockfile exists and is stale before trying to acquire
        if [[ -f "$LOCKFILE" ]] && check_lockfile_stale; then
            # Lockfile is stale, remove it and log
            # Format: timestamp:pid, extract PID with cut
            local stale_pid
            stale_pid=$(cat "$LOCKFILE" 2>/dev/null | cut -d: -f2 || echo "unknown")
            rm -f "$LOCKFILE"
            echo "WARNING: Removed stale lockfile (timeout exceeded, PID was: $stale_pid)" >&2
        fi
        
        # Try to acquire lock, exit if another instance is running
        # -n: non-blocking (fail immediately if lock can't be acquired)
        if ! flock -n 9; then
            # Lock acquisition failed - another instance is running
            # Check if it's stale by file age
            if check_lockfile_stale; then
                # Lockfile is stale, force remove and try again
                rm -f "$LOCKFILE"
                if ! flock -n 9; then
                    # Try to log before exiting (may fail if lockfile issue)
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] Another instance is already running, exiting" >> "$LOG_FILE" 2>/dev/null || true
                    echo "WARNING: Another instance is already running, exiting" >&2
                    exit 0
                fi
            else
                # Lockfile is valid, another instance is actually running
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] Another instance is already running, exiting" >> "$LOG_FILE" 2>/dev/null || true
                echo "WARNING: Another instance is already running, exiting" >&2
                exit 0
            fi
        fi
        
        # Lock acquired successfully, write timestamp:pid to lockfile for timeout checking
        echo "$(date +%s):$$" > "$LOCKFILE"
        
        # Run main
        main "$@"
        
        # Explicitly close file descriptor and remove lockfile before exit
        exec 9>&-
        rm -f "$LOCKFILE"
    ) 9>"$LOCKFILE"
else
    # Fallback: simple lockfile check (less reliable but better than nothing)
    # Use atomic file creation to avoid race conditions
    # Format: timestamp:pid
    local lock_pid
    local lock_acquired=0
    
    # Check if existing lockfile is stale
    if [[ -f "$LOCKFILE" ]]; then
        if check_lockfile_stale; then
            # Lockfile is stale, remove it
            lock_pid=$(cat "$LOCKFILE" 2>/dev/null | cut -d: -f2 || echo "unknown")
            rm -f "$LOCKFILE"
            echo "WARNING: Removed stale lockfile (timeout exceeded, PID was: $lock_pid)" >&2
        else
            # Lockfile exists and not stale, check PID
            lock_pid=$(cat "$LOCKFILE" 2>/dev/null | cut -d: -f2 || echo "")
            # kill -0: check if process exists without sending signal (returns 0 if exists)
            if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
                # Process is still running
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] Another instance (PID $lock_pid) is already running, exiting" >> "$LOG_FILE" 2>/dev/null || true
                echo "WARNING: Another instance (PID $lock_pid) is already running, exiting" >&2
                exit 0
            fi
            # PID is dead but lockfile not stale (shouldn't happen often), remove it
            rm -f "$LOCKFILE"
        fi
    fi
    
    # Try to create lockfile atomically with timestamp:pid format
    # set -C: noclobber mode - prevents overwriting existing file (atomic check-and-create)
    if (set -C; echo "$(date +%s):$$" > "$LOCKFILE") 2>/dev/null; then
        # Successfully created lockfile
        lock_acquired=1
        trap "rm -f $LOCKFILE" EXIT INT TERM
    else
        # Race condition - another process got it first
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] Could not acquire lockfile, exiting" >> "$LOG_FILE" 2>/dev/null || true
        echo "WARNING: Could not acquire lockfile, exiting" >&2
        exit 0
    fi
    
    if [[ $lock_acquired -eq 1 ]]; then
        main "$@"
    fi
fi

