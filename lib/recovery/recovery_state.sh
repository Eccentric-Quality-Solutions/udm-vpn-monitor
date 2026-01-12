#!/bin/bash
#
# Recovery state management functions for UDM VPN Monitor
# Manages recovery method tracking and peer display formatting
#
# Version: 0.5.0
#

# Store recovery method used for a location
#
# Stores the recovery method that was used when recovery was attempted.
# This allows the "VPN restored" message to include which recovery method succeeded.
#
# Arguments:
#   $1: Location name (required, sanitized)
#   $2: External peer IP address
#   $3: Recovery method name ("xfrm", "ipsec_reload", "ipsec_restart")
#
# Returns:
#   0: Always succeeds (errors are non-critical)
#
# Side effects:
#   - Creates/updates recovery method state file using abstraction layer
#
# Examples:
#   store_recovery_method "NYC" "203.0.113.1" "xfrm"
#   store_recovery_method "NYC" "203.0.113.1" "ipsec_reload"
#
# Note:
#   Requires set_peer_state_non_critical from state.sh
#   Uses "recovery_method" as the state key
store_recovery_method() {
	local location_name="$1"
	local peer_ip="$2"
	local recovery_method="$3"

	# Validate recovery method
	if [[ -z "$recovery_method" ]]; then
		return 0
	fi

	# Store using abstraction layer (non-critical - failures are logged but don't interrupt)
	if command -v set_peer_state_non_critical >/dev/null 2>&1; then
		set_peer_state_non_critical "$location_name" "$peer_ip" "recovery_method" "$recovery_method"
	fi

	return 0
}

# Get recovery method used for a location
#
# Retrieves the recovery method that was stored when recovery was attempted.
# Returns empty string if no recovery method was stored.
#
# Arguments:
#   $1: Location name (required, sanitized)
#   $2: External peer IP address
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints recovery method to stdout if found, empty string otherwise
#
# Examples:
#   method=$(get_recovery_method "NYC" "203.0.113.1")
#   if [[ -n "$method" ]]; then
#       echo "Recovery method: $method"
#   fi
#
# Note:
#   Requires get_peer_state from state.sh
#   Uses "recovery_method" as the state key
get_recovery_method() {
	local location_name="$1"
	local peer_ip="$2"
	local recovery_method=""

	if command -v get_peer_state >/dev/null 2>&1; then
		recovery_method=$(get_peer_state "$location_name" "$peer_ip" "recovery_method" "")
	fi

	echo "$recovery_method"
	return 0
}

# Clear recovery method for a location
#
# Removes the stored recovery method after it has been logged.
# This prevents stale recovery method information from being displayed.
#
# Arguments:
#   $1: Location name (required, sanitized)
#   $2: External peer IP address
#
# Returns:
#   0: Always succeeds (errors are non-critical)
#
# Side effects:
#   - Deletes recovery method state file using abstraction layer
#
# Examples:
#   clear_recovery_method "NYC" "203.0.113.1"
#
# Note:
#   Requires delete_peer_state from state.sh
#   Uses "recovery_method" as the state key
clear_recovery_method() {
	local location_name="$1"
	local peer_ip="$2"

	if command -v delete_peer_state >/dev/null 2>&1; then
		delete_peer_state "$location_name" "$peer_ip" "recovery_method" || true
	fi

	return 0
}

# Format recovery method for display
#
# Formats a recovery method name for display in log messages.
# Converts internal method names to user-friendly descriptions.
#
# Arguments:
#   $1: Recovery method name ("xfrm", "ipsec_reload", "ipsec_restart")
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints formatted recovery method description to stdout
#
# Examples:
#   display=$(format_recovery_method "xfrm")
#   # Returns: "xfrm-based recovery"
#
# Note:
#   Returns "unknown recovery method" for unrecognized methods
format_recovery_method() {
	local method="$1"

	case "$method" in
	"xfrm")
		echo "xfrm-based recovery"
		;;
	"ipsec_reload")
		echo "ipsec reload"
		;;
	"ipsec_restart")
		echo "ipsec restart"
		;;
	*)
		if [[ -n "$method" ]]; then
			echo "$method"
		else
			echo "unknown recovery method"
		fi
		;;
	esac

	return 0
}

# Format peer display name with optional connection name
#
# Formats a peer IP address for display, optionally including the connection name
# if discoverable. This provides consistent formatting across logging statements.
#
# Arguments:
#   $1: External peer IP address
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints formatted peer display string to stdout
#
# Examples:
#   display=$(format_peer_display "203.0.113.1")
#   # Returns: "203.0.113.1" or "203.0.113.1 (conn: site-a)" if connection name found
#
# Note:
#   Requires discover_connection_name to be available (from detection.sh)
#   Falls back to just the IP address if connection name cannot be discovered
format_peer_display() {
	local external_peer_ip="$1"
	local conn_name=""
	local peer_display="$external_peer_ip"

	# Try to discover connection name for better logging (optional, for debugging)
	if command -v discover_connection_name >/dev/null 2>&1; then
		conn_name=$(discover_connection_name "$external_peer_ip" 2>/dev/null || echo "")
	fi

	if [[ -n "$conn_name" ]]; then
		peer_display="$external_peer_ip (conn: $conn_name)"
	fi

	echo "$peer_display"
}
