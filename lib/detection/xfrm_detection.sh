#!/bin/bash
#
# XFRM detection functions for UDM VPN Monitor
# Handles xfrm state parsing, byte counter detection, and SA checking
#
# Version: 0.6.0
#

# Source constants for magic numbers
# shellcheck source=lib/constants.sh
if [[ -z "${LIB_DIR:-}" ]]; then
	LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
if ! source "${LIB_DIR}/constants.sh" 2>/dev/null; then
	[[ -z "${MAX_IPV6_SEGMENTS:-}" ]] && readonly MAX_IPV6_SEGMENTS=8
	[[ -z "${MIN_IPV6_SEGMENT_HEX_DIGITS:-}" ]] && readonly MIN_IPV6_SEGMENT_HEX_DIGITS=1
	[[ -z "${MAX_IPV6_SEGMENT_HEX_DIGITS:-}" ]] && readonly MAX_IPV6_SEGMENT_HEX_DIGITS=4
	[[ -z "${MAX_IPV4_OCTET:-}" ]] && readonly MAX_IPV4_OCTET=255
	[[ -z "${IPV4_OCTET_COUNT:-}" ]] && readonly IPV4_OCTET_COUNT=4
	[[ -z "${IPV4_CIDR_SINGLE_HOST:-}" ]] && readonly IPV4_CIDR_SINGLE_HOST=32
	[[ -z "${PING_PACKET_LOSS_THRESHOLD:-}" ]] && readonly PING_PACKET_LOSS_THRESHOLD=100
	[[ -z "${PING_SUCCESS_THRESHOLD:-}" ]] && readonly PING_SUCCESS_THRESHOLD=0.3
	[[ -z "${PING_CEIL_ADJUSTMENT:-}" ]] && readonly PING_CEIL_ADJUSTMENT=0.999
	[[ -z "${XFRM_OUTPUT_CONTEXT_LINES:-}" ]] && readonly XFRM_OUTPUT_CONTEXT_LINES=10
	[[ -z "${IPSEC_STATUS_TIMEOUT:-}" ]] && readonly IPSEC_STATUS_TIMEOUT=5
fi

# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"

# shellcheck source=lib/logging.sh
if ! source "${LIB_DIR}/logging.sh" 2>/dev/null; then
	# shellcheck source=lib/fallbacks.sh
	if [[ -n "${LIB_DIR:-}" ]] && [[ -f "${LIB_DIR}/fallbacks.sh" ]] && [[ -r "${LIB_DIR}/fallbacks.sh" ]]; then
		source "${LIB_DIR}/fallbacks.sh" 2>/dev/null && define_logging_fallbacks
	fi
fi

# shellcheck source=lib/detection/network_validation.sh
source "${LIB_DIR}/detection/network_validation.sh"

# Extract byte counter from xfrm output
#
# Parses the output of 'ip xfrm state' to extract the current byte counter value.
# Handles various formats and edge cases robustly.
# Looks for "lifetime current:" line and extracts the number before "bytes".
#
# Arguments:
#   $1: xfrm output text (from 'ip xfrm state' command, may be multi-line)
#
# Returns:
#   0: Byte counter successfully extracted and printed
#   1: Byte counter not found or invalid format
#
# Output:
#   Prints the byte counter value (integer) to stdout if found
#
# Examples:
#   bytes=$(extract_byte_counter "$xfrm_output")
#   if [[ $? -eq 0 ]]; then
#       echo "Byte count: $bytes"
#   fi
#
# Note:
#   Uses regex pattern matching to extract bytes from "lifetime current:" line
#   Falls back to sed pattern if regex fails
#   Validates extracted value is numeric and non-negative
extract_byte_counter() {
	local xfrm_output="$1"
	local bytes=""

	# UDM OS format: lifetime current: appears after lifetime config:, with bytes on next line
	# Format: "lifetime current:" followed by "  39492(bytes), 609(packets)" on next line
	# Example:
	#   lifetime current:
	#     39492(bytes), 609(packets)
	#     add 2026-01-03 12:19:25 use 2026-01-03 12:19:34

	# Find "lifetime current:" section (get context lines for multi-line format)
	local lifetime_section
	lifetime_section=$(echo "$xfrm_output" | grep -A 5 "lifetime current:" | head -6)

	if [[ -z "$lifetime_section" ]]; then
		# No lifetime section found - log debug info if enabled
		log_message "DEBUG" "SYSTEM" "extract_byte_counter: No 'lifetime current:' section found in xfrm output for peer"
		return 1
	fi

	# Debug: log the lifetime section if DEBUG enabled
	log_message "DEBUG" "SYSTEM" "extract_byte_counter: Found lifetime section: $(echo "$lifetime_section" | head -3 | tr '\n' ' ')"

	# Primary method: UDM OS format - look for line with "N(bytes)" after "lifetime current:"
	# This handles the format: "  39492(bytes), 609(packets)"
	local bytes_line
	bytes_line=$(echo "$lifetime_section" | grep -E "[0-9]+\(bytes\)" | head -1)
	if [[ -n "$bytes_line" ]]; then
		# Extract number before "(bytes)" - format: "  39492(bytes)" or "  0(bytes)"
		if [[ "$bytes_line" =~ ([0-9]+)\(bytes\) ]]; then
			bytes="${BASH_REMATCH[1]}"
		fi
	fi

	# Fallback: Single-line format "lifetime current: 123456 bytes" (in case format differs)
	if [[ -z "$bytes" ]] || [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
		local lifetime_line
		lifetime_line=$(echo "$lifetime_section" | grep "lifetime current:" | head -1)
		if [[ -n "$lifetime_line" ]]; then
			# Extract the number before "bytes" that comes after "lifetime current:"
			if [[ "$lifetime_line" =~ lifetime[[:space:]]+current:[[:space:]]+([0-9]+)[[:space:]]+bytes ]]; then
				bytes="${BASH_REMATCH[1]}"
			fi
		fi
	fi

	# Validate extracted value
	if [[ -z "$bytes" ]] || [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
		# Lifetime section was found but byte counter extraction failed
		# This may indicate an unexpected xfrm output format change
		log_message "WARNING" "SYSTEM" "extract_byte_counter: Found 'lifetime current:' section but failed to extract byte counter. xfrm format may have changed."
		return 1
	fi

	# Additional validation: ensure it's a reasonable number (not empty, not negative)
	if [[ "$bytes" -lt 0 ]]; then
		return 1
	fi

	echo "$bytes"
	return 0
}

# Extract SPI (Security Parameter Index) from xfrm output
#
# Parses the output of 'ip xfrm state' to extract the SPI value.
# SPI uniquely identifies a Security Association and changes when SA rekeys.
# Handles hex format (0x12345678) and decimal format.
#
# Arguments:
#   $1: xfrm output text (from 'ip xfrm state' command, may be multi-line)
#
# Returns:
#   0: SPI successfully extracted and printed
#   1: SPI not found or invalid format
#
# Output:
#   Prints the SPI value to stdout if found (hex format preserved, e.g., "0x12345678" or "12345678")
#
# Examples:
#   spi=$(extract_spi "$xfrm_output")
#   if [[ $? -eq 0 ]]; then
#       echo "SPI: $spi"
#   fi
#
# Note:
#   Uses regex pattern matching to extract SPI from "proto <proto> spi <spi>" line
#   SPI format can be hex (0x12345678) or decimal (12345678)
#   Returns SPI in original format (hex or decimal)
extract_spi() {
	local xfrm_output="$1"
	local spi=""

	# Find the line containing "spi" (may be indented)
	# Format examples:
	#   "    proto esp spi 0x12345678 reqid 1 mode tunnel"
	#   "    proto esp spi 12345678 reqid 1 mode tunnel"
	local spi_line
	spi_line=$(echo "$xfrm_output" | grep -i "spi" | head -1)

	if [[ -z "$spi_line" ]]; then
		return 1
	fi

	# Extract SPI value (hex format: 0x[0-9a-fA-F]+ or decimal: [0-9]+)
	# Pattern matches: optional whitespace, "spi", whitespace, then hex or decimal value
	if [[ "$spi_line" =~ ^[[:space:]]*proto[[:space:]]+[a-zA-Z0-9]+[[:space:]]+spi[[:space:]]+(0x[0-9a-fA-F]+|[0-9]+) ]]; then
		spi="${BASH_REMATCH[1]}"
	elif [[ "$spi_line" =~ ^[[:space:]]*spi[[:space:]]+(0x[0-9a-fA-F]+|[0-9]+) ]]; then
		# Fallback: match "spi" directly if proto pattern doesn't match
		spi="${BASH_REMATCH[1]}"
	else
		# Fallback: try sed pattern matching
		spi=$(echo "$spi_line" | sed -n 's/.*[[:space:]]spi[[:space:]]*\(0x[0-9a-fA-F]\+\|[0-9]\+\)[[:space:]].*/\1/p' 2>/dev/null || echo "")
	fi

	# Validate extracted value
	if [[ -z "$spi" ]]; then
		return 1
	fi

	# Validate format: must be hex (0x...) or decimal (all digits)
	if [[ ! "$spi" =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]]; then
		return 1
	fi

	echo "$spi"
	return 0
}

# Execute xfrm state command
#
# Executes the xfrm state command, trying with statistics first (ip -s xfrm state)
# and falling back to regular ip xfrm state if the first attempt fails or returns empty.
#
# Arguments:
#   None
#
# Returns:
#   0: Success (output printed to stdout)
#   1: Failed to query xfrm state or command unavailable
#
# Output:
#   Prints full xfrm state output to stdout
#
# Note:
#   Requires ip command to be available
execute_xfrm_state_command() {
	if ! check_command_available "ip"; then
		return 1
	fi

	# Try with statistics first (ip -s xfrm state) which may show more detail
	local full_xfrm_output
	local xfrm_stderr
	local xfrm_exit_code

	# Capture both stdout and stderr to distinguish command failure from empty output
	# Note: ip xfrm state returns exit code 0 even when no SAs exist (just empty output)
	# So we need to check stderr for actual command errors
	full_xfrm_output=$(ip -s xfrm state 2>&1)
	xfrm_exit_code=$?

	if [[ $xfrm_exit_code -eq 0 ]]; then
		# Command succeeded - check if output contains error messages in stderr
		if echo "$full_xfrm_output" | grep -qE "(error|Error|ERROR|failed|Failed|FAILED|No such|Permission denied)"; then
			return 2
		fi
		# Check if we have actual output (not just empty/whitespace)
		if [[ -n "${full_xfrm_output//[[:space:]]/}" ]]; then
			echo "$full_xfrm_output"
			return 0
		fi
	elif [[ $xfrm_exit_code -ne 0 ]]; then
		# Command failed with non-zero exit code - this is a command failure
		return 2
	fi

	# Fall back to regular ip xfrm state (without -s)
	full_xfrm_output=$(ip xfrm state 2>&1)
	xfrm_exit_code=$?

	if [[ $xfrm_exit_code -eq 0 ]]; then
		if echo "$full_xfrm_output" | grep -qE "(error|Error|ERROR|failed|Failed|FAILED|No such|Permission denied)"; then
			return 2
		fi
		# Check if we have actual output
		if [[ -n "${full_xfrm_output//[[:space:]]/}" ]]; then
			echo "$full_xfrm_output"
			return 0
		fi
		return 1
	elif [[ $xfrm_exit_code -ne 0 ]]; then
		return 2
	fi

	return 1
}

# Deduplicate SA blocks from xfrm output
#
# Deduplicates Security Association (SA) blocks from xfrm output using a composite key
# of header (src ... dst ...) + SPI value. This handles the edge case where multiple SAs
# can have the same src/dst IP addresses but different SPI values (e.g., during rekey
# transitions or mixed SA configurations). Using only the header line for deduplication
# would incorrectly treat such SAs as duplicates and skip them.
#
# Arguments:
#   None (reads from stdin)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints deduplicated SA blocks to stdout
#
# Note:
#   Reads xfrm output from stdin and writes deduplicated output to stdout
#   Uses awk script to identify unique SA blocks by src+dst+spi combination
deduplicate_sa_blocks() {
	# Awk script to deduplicate SA blocks by src+dst+spi (not just src+dst)
	# Multiple SAs can have the same src/dst but different SPI values
	local dedupe_awk_script='
		BEGIN { in_block = 0; current_header = ""; current_spi = "" }
		/^src[[:space:]]+/ {
			# New SA block detected - save previous block if unique
			if (in_block == 1 && current_header != "" && current_spi != "") {
				# Create unique key from header + SPI
				sa_key = current_header "|" current_spi
				if (!(sa_key in seen_sas)) {
					seen_sas[sa_key] = 1
					# Print the saved block
					print saved_block
				}
			}
			# Start new block
			current_header = $0
			current_spi = ""
			saved_block = $0
			in_block = 1
			next
		}
		in_block == 1 {
			# Continuation line - look for SPI value
			if (current_spi == "" && /[[:space:]]+spi[[:space:]]+(0x[0-9a-fA-F]+|[0-9]+)/) {
				# Extract SPI value (hex or decimal)
				if (match($0, /spi[[:space:]]+(0x[0-9a-fA-F]+|[0-9]+)/)) {
					# Extract matched portion and remove "spi" prefix and whitespace
					current_spi = substr($0, RSTART, RLENGTH)
					gsub(/^spi[[:space:]]+/, "", current_spi)
				}
			}
			saved_block = saved_block "\n" $0
		}
		END {
			# Handle last block
			if (in_block == 1 && current_header != "" && current_spi != "") {
				sa_key = current_header "|" current_spi
				if (!(sa_key in seen_sas)) {
					print saved_block
				}
			}
		}
	'
	awk "$dedupe_awk_script"
}

# Get xfrm state output for a peer IP
#
# Retrieves xfrm state output filtered for a specific peer IP address.
# Finds both forward SAs (dst=$peer_ip) and reverse SAs (src=$peer_ip) to handle asymmetric SA state.
# Uses fixed-string matching for forward SAs and anchored regex for reverse SAs (safe due to IP validation).
# IP address is validated before use to prevent regex injection attacks.
#
# When xfrm query fails, attempts alternative query method using ipsec status to confirm tunnel state.
#
# Deduplication Logic:
#   When both forward and reverse outputs exist, deduplicates SA blocks using a composite key
#   of header (src ... dst ...) + SPI value. This handles the edge case where multiple SAs
#   can have the same src/dst IP addresses but different SPI values (e.g., during rekey
#   transitions or mixed SA configurations). Using only the header line for deduplication
#   would incorrectly treat such SAs as duplicates and skip them.
#
# Arguments:
#   $1: Peer IP address to filter for (must be valid IPv4 or IPv6)
#   $2: Optional number of context lines to include after match (default: XFRM_OUTPUT_CONTEXT_LINES)
#   $3: Optional error message variable name (if provided, stores detailed error information)
#
# Returns:
#   0: Success (output printed to stdout)
#   1: No SAs found for peer IP (tunnel may be down)
#   2: xfrm command failed (command error)
#
# Output:
#   Prints filtered xfrm state output to stdout
#   If error variable name provided, stores error message in that variable
#
# Security:
#   - Validates peer IP format before use to prevent regex injection
#   - Forward SA search uses fixed-string matching (grep -F)
#   - Reverse SA search uses anchored regex (grep -E) but is safe due to IP validation
get_xfrm_state_for_peer() {
	local peer_ip="$1"
	local context_lines="${2:-${XFRM_OUTPUT_CONTEXT_LINES:-10}}"
	local error_msg_var="${3:-}"

	# Validate peer IP format to prevent regex injection and ensure safe matching
	# This is a defense-in-depth measure - IPs should be validated at configuration load time,
	# but we validate here to prevent regex injection if invalid IPs reach this function
	if [[ -z "$peer_ip" ]] || ! validate_ip_address "$peer_ip"; then
		if [[ -n "$error_msg_var" ]]; then
			printf -v "$error_msg_var" "%s" "Invalid peer IP address: ${peer_ip:-<empty>}"
		fi
		return 1
	fi

	# Get full xfrm state output
	local full_xfrm_output
	local xfrm_result
	full_xfrm_output=$(execute_xfrm_state_command)
	xfrm_result=$?

	# Handle different failure types
	if [[ $xfrm_result -eq 2 ]]; then
		# Command failed - try alternative method (ipsec status) to confirm tunnel state
		local ipsec_status_output
		local ipsec_status_result
		ipsec_status_output=$(get_ipsec_status_for_peer "$peer_ip" 2>/dev/null || true)
		ipsec_status_result=$?

		if [[ -n "$ipsec_status_output" ]]; then
			# ipsec status shows connection exists - xfrm query failed but tunnel may be up
			if [[ -n "$error_msg_var" ]]; then
				printf -v "$error_msg_var" "%s" "xfrm command failed (command error), but ipsec status shows connection exists for $peer_ip - xfrm query may be unavailable"
			fi
			return 2
		else
			# Both xfrm and ipsec status failed - tunnel is likely down
			if [[ -n "$error_msg_var" ]]; then
				printf -v "$error_msg_var" "%s" "xfrm command failed (command error) and ipsec status shows no connection for $peer_ip - tunnel appears to be down"
			fi
			return 2
		fi
	elif [[ $xfrm_result -ne 0 ]]; then
		# Empty output - no SAs found in kernel, try ipsec status to confirm
		local ipsec_status_output
		ipsec_status_output=$(get_ipsec_status_for_peer "$peer_ip" 2>/dev/null || true)

		if [[ -n "$ipsec_status_output" ]]; then
			# ipsec status shows connection exists - SAs may exist but not in xfrm state
			if [[ -n "$error_msg_var" ]]; then
				printf -v "$error_msg_var" "%s" "No SAs found in xfrm state for $peer_ip, but ipsec status shows connection exists - SAs may not be in kernel state"
			fi
			return 1
		else
			# Both show no connection - tunnel is down
			if [[ -n "$error_msg_var" ]]; then
				printf -v "$error_msg_var" "%s" "No SAs found in xfrm state for $peer_ip and ipsec status shows no connection - tunnel is down"
			fi
			return 1
		fi
	fi

	if [[ -z "$full_xfrm_output" ]]; then
		# Empty output after successful command - try ipsec status to confirm
		local ipsec_status_output
		ipsec_status_output=$(get_ipsec_status_for_peer "$peer_ip" 2>/dev/null || true)

		if [[ -n "$ipsec_status_output" ]]; then
			if [[ -n "$error_msg_var" ]]; then
				printf -v "$error_msg_var" "%s" "xfrm state query returned empty output for $peer_ip, but ipsec status shows connection exists"
			fi
			return 1
		else
			if [[ -n "$error_msg_var" ]]; then
				printf -v "$error_msg_var" "%s" "No SAs found in xfrm state for $peer_ip and ipsec status shows no connection - tunnel is down"
			fi
			return 1
		fi
	fi

	# Increase context lines to ensure we capture lifetime current section which may appear after lifetime config
	# lifetime config section can be long, so we need more lines to get to lifetime current
	local extended_context=$((context_lines + 10))
	local forward_output=""
	local reverse_output=""

	# Find forward SAs (dst=$peer_ip) - matches forward SA header lines "src <local_ip> dst $peer_ip"
	forward_output=$(echo "$full_xfrm_output" | grep -F "dst ${peer_ip}" -A "${extended_context}" 2>/dev/null || true)
	# Find reverse SAs (src=$peer_ip) - matches reverse SA header lines "src $peer_ip dst <local_ip>"
	# Use grep -E with anchored pattern to match lines starting with "src $peer_ip"
	# Safe because peer_ip is validated above to prevent regex injection
	# The pattern "^[[:space:]]*src $peer_ip[[:space:]]" matches SA header lines for reverse SAs
	reverse_output=$(echo "$full_xfrm_output" | grep -E "^[[:space:]]*src ${peer_ip}[[:space:]]" -A "${extended_context}" 2>/dev/null || true)

	# Combine outputs if both exist (they represent different SAs in a bidirectional tunnel)
	# If only one exists, use it (asymmetric SA state)
	# Note: Deduplicate by SA header lines (src ... dst ...) to avoid duplicates when
	# reverse SA appears in forward_output context lines (grep -A includes context)
	# Multiple SAs can have the same src/dst but different SPI values, so we include SPI in uniqueness check
	if [[ -n "$forward_output" ]] && [[ -n "$reverse_output" ]]; then
		# Both exist - combine them, but deduplicate SA blocks
		# Multiple SAs can have the same src/dst but different SPI values
		# So we need to include SPI in the uniqueness check, not just the header line
		local combined="${forward_output}"$'\n'"${reverse_output}"
		echo "$combined" | deduplicate_sa_blocks
		return 0
	elif [[ -n "$forward_output" ]]; then
		echo "$forward_output"
		return 0
	elif [[ -n "$reverse_output" ]]; then
		echo "$reverse_output"
		return 0
	fi

	# No SAs found for this peer IP - try ipsec status to confirm
	local ipsec_status_output
	ipsec_status_output=$(get_ipsec_status_for_peer "$peer_ip" 2>/dev/null || true)

	if [[ -n "$ipsec_status_output" ]]; then
		# ipsec status shows connection exists but xfrm doesn't - SAs may exist but not match our query
		if [[ -n "$error_msg_var" ]]; then
			printf -v "$error_msg_var" "%s" "No SAs found in xfrm state for $peer_ip (no matching src/dst), but ipsec status shows connection exists - SAs may exist with different addresses"
		fi
		return 1
	else
		# Both show no connection - tunnel is down
		if [[ -n "$error_msg_var" ]]; then
			printf -v "$error_msg_var" "%s" "No SAs found in xfrm state for $peer_ip and ipsec status shows no connection - tunnel is down"
		fi
		return 1
	fi
}

# Get ipsec status output for a peer IP
#
# Retrieves ipsec status output filtered for a specific peer IP address.
# Uses timeout to prevent hanging and fixed-string matching for safety.
#
# Arguments:
#   $1: Peer IP address to filter for (optional, if empty returns full output)
#
# Returns:
#   0: Success (output printed to stdout)
#   1: Failed to query ipsec status or command unavailable
#
# Output:
#   Prints filtered ipsec status output to stdout (or full output if no peer IP)
get_ipsec_status_for_peer() {
	local peer_ip="${1:-}"
	local ipsec_output

	if ! check_command_available "ipsec"; then
		return 1
	fi

	# Get ipsec status with timeout
	if check_command_available "timeout"; then
		ipsec_output=$(timeout "${IPSEC_STATUS_TIMEOUT:-5}" ipsec status 2>/dev/null || true)
	else
		ipsec_output=$(ipsec status 2>/dev/null || true)
	fi

	# Filter by peer IP if provided
	if [[ -n "$peer_ip" ]]; then
		echo "$ipsec_output" | grep -F "$peer_ip" || true
	else
		echo "$ipsec_output"
	fi
}

# Check if SA rekey occurred (read-only check)
#
# Checks if IPsec SA rekey occurred by comparing current SPI with stored SPI.
# This is a read-only check that does not modify state.
# Used for failure type detection without side effects.
#
# Arguments:
#   $1: Current SPI value (from xfrm output, hex or decimal format)
#   $2: Peer IP address (used for state lookup)
#   $3: Location name (required, used for state file naming)
#
# Returns:
#   0: Rekey detected (SPI changed)
#   1: No rekey (SPI unchanged or first check)
#
# Side effects:
#   None (read-only check)
#
# Examples:
#   if check_sa_rekey_occurred "$current_spi" "$peer_ip" "$location_name"; then
#       echo "SA rekey occurred"
#   fi
#
# Note:
#   Requires get_peer_state from state.sh
#   This function does NOT reset byte counter baseline or update SPI
#   Use detect_sa_rekey() if you need to handle rekey (reset baseline, update SPI)
check_sa_rekey_occurred() {
	local current_spi="$1"
	local peer_ip="$2"
	local location_name="$3"

	# Validate SPI format
	if [[ -z "$current_spi" ]] || [[ ! "$current_spi" =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]]; then
		return 1
	fi

	# Validate location_name is provided
	if [[ -z "$location_name" ]]; then
		handle_error "ERROR" "SYSTEM" "check_sa_rekey_occurred: location_name is required" 0
		return 1
	fi

	# Get last known SPI using abstraction layer
	# Check if the file exists first for efficiency (avoid unnecessary function call)
	local last_spi
	local spi_file
	spi_file=$(get_peer_state_file_path "$location_name" "$peer_ip" "spi")
	if [[ ! -f "$spi_file" ]]; then
		# No SPI file exists - no rekey
		return 1
	fi
	last_spi=$(get_peer_state "$location_name" "$peer_ip" "spi" "")

	# If last_spi is empty or "0" and file doesn't exist, no rekey
	# But we already checked file existence above, so if we get here, SPI exists
	if [[ -z "$last_spi" ]] || [[ "$last_spi" == "0" ]]; then
		# SPI file exists but value is empty/0 - treat as no stored SPI
		return 1
	fi

	# Compare SPI values
	if [[ "$current_spi" != "$last_spi" ]]; then
		# SPI changed - rekey occurred
		return 0
	fi

	# SPI unchanged - no rekey
	return 1
}

# Detect SA rekey event
#
# Detects IPsec SA rekey by comparing current SPI with stored SPI.
# When SA rekeys, SPI changes but peer IP remains the same.
# On rekey detection, resets byte counter baseline to prevent false positives.
#
# Arguments:
#   $1: Current SPI value (from xfrm output, hex or decimal format)
#   $2: Peer IP address (used for state management and logging)
#   $3: Location name (required, used for state file naming)
#
# Returns:
#   0: Rekey detected (SPI changed)
#   1: No rekey (SPI unchanged or first check)
#
# Side effects:
#   - Updates stored SPI if different from current
#   - Resets byte counter baseline to 0 on rekey detection
#   - Logs rekey events for monitoring
#
# Examples:
#   if detect_sa_rekey "$current_spi" "$peer_ip" "$location_name"; then
#       echo "SA rekey detected"
#   fi
#
# Note:
#   Requires get_peer_state and set_peer_state from state.sh
#   First check (no stored SPI) always returns 1 (no rekey)
#   When SPI changes, resets last_bytes to 0 to allow new baseline
detect_sa_rekey() {
	local current_spi="$1"
	local peer_ip="$2"
	local location_name="$3"

	# Validate SPI format
	if [[ -z "$current_spi" ]] || [[ ! "$current_spi" =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]]; then
		return 1
	fi

	# Validate location_name is provided
	if [[ -z "$location_name" ]]; then
		handle_error "ERROR" "SYSTEM" "detect_sa_rekey: location_name is required" 0
		return 1
	fi

	# Get last known SPI using abstraction layer
	# Check if SPI file exists first to distinguish between "no file" and "file with value"
	local last_spi
	local spi_file
	spi_file=$(get_peer_state_file_path "$location_name" "$peer_ip" "spi")
	if [[ ! -f "$spi_file" ]]; then
		# No SPI file exists - store current SPI and return (no rekey)
		set_peer_state_non_critical "$location_name" "$peer_ip" "spi" "$current_spi"
		return 1
	fi
	last_spi=$(get_peer_state "$location_name" "$peer_ip" "spi" "")

	# Validate stored SPI format - if corrupted, recover by storing current SPI
	if [[ -n "$last_spi" ]] && [[ "$last_spi" != "0" ]] && [[ ! "$last_spi" =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]]; then
		# Stored SPI is corrupted - recover by storing current SPI
		set_peer_state_non_critical "$location_name" "$peer_ip" "spi" "$current_spi"
		return 1
	fi

	# If last_spi is empty or "0", treat as no stored SPI (shouldn't happen if file exists, but be safe)
	if [[ -z "$last_spi" ]] || [[ "$last_spi" == "0" ]]; then
		set_peer_state_non_critical "$location_name" "$peer_ip" "spi" "$current_spi"
		return 1
	fi

	# Compare SPI values
	if [[ "$current_spi" != "$last_spi" ]]; then
		# SPI changed - rekey detected
		local ip_display
		ip_display=$(format_peer_ip_display "$peer_ip" "")
		log_message "INFO" "$location_name" "SA rekey detected for $ip_display: SPI changed from $last_spi to $current_spi"

		# Reset byte counter baseline to 0 (allows new baseline after rekey)
		set_peer_state_non_critical "$location_name" "$peer_ip" "last_bytes" "0"
		set_peer_state_non_critical "$location_name" "$peer_ip" "spi" "$current_spi"

		return 0
	fi

	# SPI unchanged - no rekey
	return 1
}

# Check byte counters for VPN status
#
# Validates that byte counters indicate healthy VPN tunnel using simple heuristics.
# Uses simple logic: bytes increasing = healthy, bytes not increasing + ping fails = broken.
# Updates the last_bytes file with current byte count if valid.
# Detects SA rekey events before checking bytes to prevent false positives.
#
# Arguments:
#   $1: Location name (required, sanitized, must not be empty)
#   $2: Current byte count (integer from xfrm state)
#   $3: Peer IP address (used for state management and logging)
#   $4: Current SPI value (optional, used for rekey detection)
#   $5: Internal peer IP address (optional, used for ping checks on idle detection)
#   $6: Diagnostic variable name (optional, if provided, detailed failure reason is stored here)
#
# Returns:
#   0: Byte counters are valid (traffic flowing, idle but healthy, first check, or after rekey)
#   1: Byte counters are invalid (zero or broken tunnel)
#
# Side effects:
#   - Updates last_bytes state using abstraction layer if bytes are valid
#   - Detects SA rekey if SPI provided and resets byte counter baseline
#   - Marks idle tunnels and suggests keepalive if needed
#   - Logs INFO messages for valid counters
#   - Logs warning messages for invalid counters (unless diagnostic variable is provided)
#   - If diagnostic variable name is provided, stores detailed failure reason in that variable instead of logging
#
# Examples:
#   if check_byte_counters "NYC" "$current_bytes" "$peer_ip" "$current_spi"; then
#       echo "VPN is passing traffic"
#   fi
#   # With diagnostic variable:
#   local diagnostic=""
#   if ! check_byte_counters "NYC" "$current_bytes" "$peer_ip" "$current_spi" "" "diagnostic"; then
#       echo "Failure reason: $diagnostic"
#   fi
#
# Note:
#   Requires get_peer_state, set_peer_state from state.sh
#   Requires check_ping_connectivity from detection.sh
#   Uses simple heuristics: bytes increasing = healthy, bytes not increasing + ping fails = broken
#   If rekey detected, byte counter baseline is reset and check passes
#   Uses abstraction layer for state management
check_byte_counters() {
	local location_name="$1"
	local current_bytes="$2"
	local peer_ip="$3"
	local current_spi="${4:-}"
	local internal_peer_ip="${5:-}"
	local diagnostic_var="${6:-}"

	# Validate location_name is provided (required for state file operations)
	if [[ -z "$location_name" ]]; then
		handle_error "ERROR" "SYSTEM" "check_byte_counters: location_name is required" 0
		return 1
	fi

	# Check for SA rekey if SPI is provided
	if [[ -n "$current_spi" ]]; then
		if detect_sa_rekey "$current_spi" "$peer_ip" "$location_name"; then
			# Rekey detected - byte counter baseline was reset to 0
			# Clear idle state (rekey resets everything)
			delete_peer_state "$location_name" "$peer_ip" "idle_detected" || true
			# Treat this as first check (allow any non-zero bytes)
			local last_bytes
			last_bytes=$(get_peer_state "$location_name" "$peer_ip" "last_bytes" "0")
			if [[ "$current_bytes" -gt 0 ]]; then
				# Bytes are non-zero after rekey - update baseline
				local ip_display
				ip_display=$(format_peer_ip_display "$peer_ip" "$internal_peer_ip")
				if set_peer_state "$location_name" "$peer_ip" "last_bytes" "$current_bytes"; then
					log_message "INFO" "$location_name" "VPN OK: SA rekeyed, bytes=$current_bytes (baseline reset) for $ip_display"
					return 0
				else
					log_message "INFO" "$location_name" "VPN OK: SA rekeyed, bytes=$current_bytes (baseline reset, state update failed) for $ip_display"
					return 0
				fi
			fi
			# If bytes are 0 after rekey, continue to normal check below
		fi
	fi

	# Get last known bytes using abstraction layer
	local last_bytes
	last_bytes=$(get_peer_state "$location_name" "$peer_ip" "last_bytes" "0")

	# Check if bytes are zero
	if [[ "$current_bytes" -eq 0 ]]; then
		# Zero bytes - check if this is first check or if we've had traffic before
		if [[ "$last_bytes" -eq 0 ]]; then
			# First check with zero bytes - may be idle or broken
			# If ping check is enabled, use it to determine if VPN is healthy
			if [[ -n "$internal_peer_ip" ]] && [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
				local local_ip
				local_ip=$(get_local_ip_for_ping)
				# Check ping connectivity to determine if VPN is healthy despite zero bytes
				# Errors are logged by check_ping_connectivity, so we don't suppress stderr
				if check_ping_connectivity "$internal_peer_ip" "$local_ip"; then
					# Ping succeeds - VPN is healthy but idle (newly established or idle)
					set_peer_state_non_critical "$location_name" "$peer_ip" "last_bytes" "$current_bytes"
					set_peer_state_non_critical "$location_name" "$peer_ip" "idle_detected" "1"
					local ip_display
					ip_display=$(format_peer_ip_display "$peer_ip" "$internal_peer_ip")
					log_message "INFO" "$location_name" "VPN OK: SA exists, bytes=0 (first check, idle but healthy, ping check passed) for $ip_display"
					return 0
				else
					# Ping fails - VPN is likely broken
					local failure_reason="bytes=0 (first check, ping check failed)"
					local ip_display
					ip_display=$(format_peer_ip_display "$peer_ip" "$internal_peer_ip")
					if [[ -n "$diagnostic_var" ]]; then
						printf -v "$diagnostic_var" "%s" "$failure_reason"
					else
						handle_error "WARNING" "$location_name" "VPN suspect: SA exists but $failure_reason for $ip_display"
					fi
					return 1
				fi
			else
				# Ping check disabled or internal_peer_ip not provided - fail-safe behavior
				local failure_reason="bytes=0 (first check, may be idle, ping check disabled)"
				local ip_display
				ip_display=$(format_peer_ip_display "$peer_ip" "")
				if [[ -n "$diagnostic_var" ]]; then
					printf -v "$diagnostic_var" "%s" "$failure_reason"
				else
					handle_error "WARNING" "$location_name" "VPN suspect: SA exists but $failure_reason for $ip_display"
				fi
				return 1
			fi
		else
			# Bytes dropped to zero after previously having traffic - likely broken
			local failure_reason="bytes dropped to 0 (was $last_bytes)"
			local ip_display
			ip_display=$(format_peer_ip_display "$peer_ip" "")
			if [[ -n "$diagnostic_var" ]]; then
				printf -v "$diagnostic_var" "%s" "$failure_reason"
			else
				handle_error "WARNING" "$location_name" "VPN suspect: SA exists but $failure_reason for $ip_display"
			fi
			return 1
		fi
	fi

	# Bytes are non-zero - check if increasing
	if [[ "$current_bytes" -gt "$last_bytes" ]] || [[ "$last_bytes" -eq 0 ]]; then
		# Bytes are increasing or this is first check - check ping if enabled
		# Even if bytes are increasing, ping failure indicates a routing issue
		if [[ -n "$internal_peer_ip" ]] && [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
			local local_ip
			local_ip=$(get_local_ip_for_ping)
			# Check ping connectivity
			# Errors are logged by check_ping_connectivity, so we don't suppress stderr
			if ! check_ping_connectivity "$internal_peer_ip" "$local_ip"; then
				# Ping fails even though bytes are increasing - routing issue
				local failure_reason="bytes increasing ($current_bytes, was $last_bytes) but ping check failed"
				local ip_display
				ip_display=$(format_peer_ip_display "$peer_ip" "$internal_peer_ip")
				if [[ -n "$diagnostic_var" ]]; then
					printf -v "$diagnostic_var" "%s" "$failure_reason"
				else
					handle_error "WARNING" "$location_name" "VPN suspect: SA exists, $failure_reason for $ip_display"
				fi
				return 1
			fi
		fi
		# Bytes are increasing and ping check passed (or disabled) - definitely healthy
		local ip_display
		ip_display=$(format_peer_ip_display "$peer_ip" "$internal_peer_ip")
		if set_peer_state "$location_name" "$peer_ip" "last_bytes" "$current_bytes"; then
			# Clear idle state if set (traffic is flowing again)
			delete_peer_state "$location_name" "$peer_ip" "idle_detected" || true
			log_message "INFO" "$location_name" "VPN OK: SA exists, bytes=$current_bytes (was $last_bytes, traffic flowing) for $ip_display"
			return 0
		else
			log_message "INFO" "$location_name" "VPN OK: SA exists, bytes=$current_bytes (was $last_bytes, state update failed) for $ip_display"
			return 0
		fi
	fi

	# Edge case: bytes are static (current_bytes == last_bytes and last_bytes > 0)
	# This could be a healthy idle VPN or a broken one - use ping to determine
	if [[ "$current_bytes" -eq "$last_bytes" ]] && [[ "$last_bytes" -gt 0 ]]; then
		if [[ -n "$internal_peer_ip" ]] && [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
			local local_ip
			local_ip=$(get_local_ip_for_ping)
			# Check ping connectivity
			# Errors are logged by check_ping_connectivity, so we don't suppress stderr
			if check_ping_connectivity "$internal_peer_ip" "$local_ip"; then
				# Ping succeeds - tunnel is idle but healthy
				set_peer_state_non_critical "$location_name" "$peer_ip" "last_bytes" "$current_bytes"
				set_peer_state_non_critical "$location_name" "$peer_ip" "idle_detected" "1"
				local ip_display
				ip_display=$(format_peer_ip_display "$peer_ip" "$internal_peer_ip")
				log_message "INFO" "$location_name" "VPN OK: SA exists, bytes=$current_bytes (static, idle but healthy, ping check passed) for $ip_display"
				# Populate diagnostic variable if provided (for failure type detection)
				# Even though this is a success case, diagnostic info is useful for monitoring
				if [[ -n "$diagnostic_var" ]]; then
					local warning_msg="bytes not increasing (current=$current_bytes, last=$last_bytes, ping check passed)"
					printf -v "$diagnostic_var" "%s" "$warning_msg"
				fi
				# Check keepalive status and suggest action if needed
				if [[ "${ENABLE_KEEPALIVE:-0}" -ne 1 ]]; then
					log_message "INFO" "$location_name" "Consider enabling ENABLE_KEEPALIVE=1 in config to prevent idle tunnel timeouts for $ip_display"
				else
					# Keepalive is enabled - check if daemon is running
					local keepalive_pidfile="${STATE_DIR:-/data/vpn-monitor}/vpn-keepalive.pid"
					if [[ ! -f "$keepalive_pidfile" ]] || ! file_exists_and_readable "$keepalive_pidfile" || ! kill -0 "$(cat "$keepalive_pidfile" 2>/dev/null)" 2>/dev/null; then
						# Note: location_name is already in log prefix, so we remove redundant location name
						log_message "INFO" "$location_name" "Keepalive is enabled but daemon is not running - consider starting: vpn-keepalive.sh start"
					fi
				fi
				return 0
			else
				# Ping fails - bytes are static and ping check failed, VPN is likely broken
				local failure_reason="bytes not increasing (current=$current_bytes, last=$last_bytes, ping check failed)"
				local ip_display
				ip_display=$(format_peer_ip_display "$peer_ip" "$internal_peer_ip")
				if [[ -n "$diagnostic_var" ]]; then
					printf -v "$diagnostic_var" "%s" "$failure_reason"
				else
					handle_error "WARNING" "$location_name" "VPN suspect: SA exists but $failure_reason for $ip_display"
				fi
				return 1
			fi
		else
			# Ping check disabled - cannot determine if healthy idle or broken
			# Mark as suspect since we can't verify health without ping check
			# Return success (0) to avoid false positives on healthy idle VPNs, but populate diagnostic
			# so that routing_issue can still be detected in determine_vpn_status
			local ip_display
			ip_display=$(format_peer_ip_display "$peer_ip" "$internal_peer_ip")
			local warning_msg="bytes not increasing (current=$current_bytes, last=$last_bytes, ping check disabled)"
			# Always populate diagnostic variable if provided (for failure type detection)
			if [[ -n "$diagnostic_var" ]]; then
				printf -v "$diagnostic_var" "%s" "$warning_msg"
			fi
			# Also log warning directly (even if diagnostic_var is provided) since it's a suspect condition
			handle_error "WARNING" "$location_name" "VPN suspect: SA exists but $warning_msg for $ip_display"
			# Update state but don't mark as idle (ping check required for idle detection)
			set_peer_state_non_critical "$location_name" "$peer_ip" "last_bytes" "$current_bytes"
			return 0
		fi
	fi

	# Bytes are not increasing (decreased) - use ping to check if healthy
	# Special case: If bytes decreased significantly, log it explicitly
	if [[ "$current_bytes" -lt "$last_bytes" ]]; then
		# Bytes decreased - this is abnormal and should be logged
		# Note: This is logged separately from the final failure message below
		# We still need to check ping to determine if it's actually broken
		if [[ -z "$diagnostic_var" ]]; then
			local ip_display
			ip_display=$(format_peer_ip_display "$peer_ip" "${internal_peer_ip:-}")
			handle_error "WARNING" "$location_name" "VPN suspect: SA exists but bytes decreased (current=$current_bytes, last=$last_bytes) - bytes not increasing for $ip_display"
		fi
	fi

	if [[ -n "$internal_peer_ip" ]] && [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
		local local_ip
		local_ip=$(get_local_ip_for_ping)
		# Check ping connectivity
		# Errors are logged by check_ping_connectivity, so we don't suppress stderr
		if check_ping_connectivity "$internal_peer_ip" "$local_ip"; then
			# Ping succeeds - tunnel is idle but healthy
			set_peer_state_non_critical "$location_name" "$peer_ip" "last_bytes" "$current_bytes"
			set_peer_state_non_critical "$location_name" "$peer_ip" "idle_detected" "1"
			local ip_display
			ip_display=$(format_peer_ip_display "$peer_ip" "$internal_peer_ip")
			log_message "INFO" "$location_name" "VPN OK: SA exists, bytes=$current_bytes (idle but healthy, ping check passed) for $ip_display"
			# Check keepalive status and suggest action if needed
			if [[ "${ENABLE_KEEPALIVE:-0}" -ne 1 ]]; then
				log_message "INFO" "$location_name" "Consider enabling ENABLE_KEEPALIVE=1 in config to prevent idle tunnel timeouts for $ip_display"
			else
				# Keepalive is enabled - check if daemon is running
				local keepalive_pidfile="${STATE_DIR:-/data/vpn-monitor}/vpn-keepalive.pid"
				if [[ ! -f "$keepalive_pidfile" ]] || ! file_exists_and_readable "$keepalive_pidfile" || ! kill -0 "$(cat "$keepalive_pidfile" 2>/dev/null)" 2>/dev/null; then
					# Note: location_name is already in log prefix, so we remove redundant location name
					log_message "INFO" "$location_name" "Keepalive is enabled but daemon is not running - consider starting: vpn-keepalive.sh start"
				fi
			fi
			return 0
		fi
	fi

	# Bytes not increasing and ping failed (or ping check disabled) - likely broken
	local ping_status="disabled"
	if [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
		ping_status="failed"
	fi
	local failure_reason="bytes not increasing (current=$current_bytes, last=$last_bytes, ping check: $ping_status)"
	if [[ "$current_bytes" -lt "$last_bytes" ]]; then
		failure_reason="bytes decreased (current=$current_bytes, last=$last_bytes, ping check: $ping_status)"
	fi
	if [[ -n "$diagnostic_var" ]]; then
		printf -v "$diagnostic_var" "%s" "$failure_reason"
	else
		local ip_display
		ip_display=$(format_peer_ip_display "$peer_ip" "${internal_peer_ip:-}")
		handle_error "WARNING" "$location_name" "VPN suspect: SA exists but $failure_reason for $ip_display"
	fi
	return 1
}

# Check VPN status using ip xfrm state
#
# Checks for Security Association (SA) existence using ip xfrm state command.
# Validates byte counters if available using simple heuristics.
#
# Arguments:
#   $1: External peer IP address (used for xfrm state checks)
#   $2: Internal peer IP address (optional, used for ping checks in idle detection)
#   $3: Location name (required, used for state file naming and passed to check_byte_counters)
#   $4: Diagnostic variable name (optional, if provided, diagnostic message is stored here instead of logging)
#   $5: SA existence output variable name (optional, if provided, SA existence state (0 or 1) is stored here)
#   $6: XFRM output variable name (optional, if provided, xfrm state output is stored here for reuse)
#
# Returns:
#   0: SA found and valid (byte counters validated successfully, or byte counters unavailable but ping check succeeds)
#   1: SA not found, invalid, or byte counters unavailable (and ping check fails or disabled)
#
# Side effects:
#   - Logs debug/warning messages (unless diagnostic variable name is provided)
#   - When byte counters unavailable: falls back to ping check if enabled (treats as "idle but healthy" if ping succeeds)
#   - Returns failure (1) when byte counters cannot be extracted and ping check unavailable/fails, allowing
#     determine_vpn_status to detect failure type as "unknown"
#   - If diagnostic variable name is provided, stores diagnostic message in that variable instead of logging
#   - If SA existence output variable name is provided, stores SA existence state (0 or 1) in that variable
#   - If XFRM output variable name is provided, stores xfrm state output in that variable for reuse (optimization)
check_xfrm_status() {
	local peer_ip="$1"
	local internal_peer_ip="${2:-}"
	local location_name="$3"
	local diagnostic_var="${4:-}"
	local sa_exists_var="${5:-}"
	local xfrm_output_var="${6:-}"

	# Validate location_name is provided (required for check_byte_counters and state operations)
	if [[ -z "$location_name" ]]; then
		handle_error "ERROR" "SYSTEM" "check_xfrm_status: location_name is required" 0
		return 1
	fi

	# Try ip xfrm state first (most reliable)
	# xfrm = Linux IPsec framework - shows Security Associations (SAs) and byte counters
	if ! check_command_or_warn "ip" "Checking xfrm status"; then
		# Set SA existence to 0 if output variable provided
		if [[ -n "$sa_exists_var" ]]; then
			printf -v "$sa_exists_var" "%s" "0"
		fi
		return 1
	fi

	local xfrm_output
	# Use fixed-string matching to prevent regex pattern injection and avoid partial IP matches
	# Match on "dst $peer_ip" pattern which appears at the start of each SA entry
	# This ensures we capture the complete SA block including lifetime information
	xfrm_output=$(get_xfrm_state_for_peer "$peer_ip")

	# Store xfrm_output in output variable if provided (for reuse by downstream functions)
	if [[ -n "$xfrm_output_var" ]]; then
		printf -v "$xfrm_output_var" "%s" "$xfrm_output"
	fi

	if [[ -z "$xfrm_output" ]]; then
		# Set SA existence to 0 if output variable provided
		if [[ -n "$sa_exists_var" ]]; then
			printf -v "$sa_exists_var" "%s" "0"
		fi
		local diagnostic_msg="Detection method: xfrm (ip xfrm state) - No SA found for $peer_ip in xfrm state"
		if [[ -n "$diagnostic_var" ]]; then
			printf -v "$diagnostic_var" "%s" "$diagnostic_msg"
		else
			local ip_display
			ip_display=$(format_peer_ip_display "$peer_ip" "$internal_peer_ip")
			handle_error "WARNING" "$location_name" "VPN suspect: No SA found for $ip_display in xfrm state"
		fi
		return 1
	fi

	# SA exists - set output variable if provided
	if [[ -n "$sa_exists_var" ]]; then
		printf -v "$sa_exists_var" "%s" "1"
	fi

	# Extract SPI for rekey detection
	local current_spi=""
	current_spi=$(extract_spi "$xfrm_output" 2>/dev/null || echo "")

	# Check if we have byte counters
	local current_bytes
	if current_bytes=$(extract_byte_counter "$xfrm_output"); then
		# Successfully extracted byte counter - validate it using simple heuristics
		# Pass location_name, SPI and internal IP to check_byte_counters for rekey detection and idle detection
		# Also pass diagnostic variable to capture detailed failure reason
		local byte_counter_diagnostic=""
		if check_byte_counters "$location_name" "$current_bytes" "$peer_ip" "$current_spi" "$internal_peer_ip" "byte_counter_diagnostic"; then
			# Update stored SPI if we have it (even if rekey not detected)
			if [[ -n "$current_spi" ]]; then
				set_peer_state_non_critical "$location_name" "$peer_ip" "spi" "$current_spi"
			fi
			return 0
		else
			# SA exists but byte counters are suspect
			if [[ -n "$diagnostic_var" ]]; then
				local diagnostic_msg="Detection method: xfrm (ip xfrm state) - SA exists for $peer_ip but byte counter validation failed"
				if [[ -n "$byte_counter_diagnostic" ]]; then
					diagnostic_msg="Detection method: xfrm (ip xfrm state) - SA exists for $peer_ip but $byte_counter_diagnostic"
				fi
				printf -v "$diagnostic_var" "%s" "$diagnostic_msg"
			fi
			return 1
		fi
	else
		# SA exists but no byte counter info (or extraction failed)
		# Still update SPI if available for tracking
		if [[ -n "$current_spi" ]]; then
			set_peer_state_non_critical "$location_name" "$peer_ip" "spi" "$current_spi"
		fi

		# When byte counters are unavailable, fall back to ping check if enabled
		# This handles cases where xfrm output format differs or byte counters aren't available
		if [[ -n "$internal_peer_ip" ]] && [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
			local local_ip
			local_ip=$(get_local_ip_for_ping)
			# Check ping connectivity to determine if VPN is healthy despite missing byte counters
			if check_ping_connectivity "$internal_peer_ip" "$local_ip" 2>/dev/null; then
				# Ping succeeds - VPN is likely healthy but byte counters unavailable
				# Treat as "idle but healthy" similar to check_byte_counters logic
				set_peer_state_non_critical "$location_name" "$peer_ip" "idle_detected" "1"
				local ip_display
				ip_display=$(format_peer_ip_display "$peer_ip" "$internal_peer_ip")
				log_message "INFO" "$location_name" "VPN OK: SA exists for $ip_display, byte counters unavailable but ping check passed (treating as idle but healthy)"
				return 0
			else
				# Ping fails - cannot verify VPN health
				local diagnostic_msg="Detection method: xfrm (ip xfrm state) - SA exists for $peer_ip but byte counter info unavailable and ping check failed"
				if [[ -n "$diagnostic_var" ]]; then
					printf -v "$diagnostic_var" "%s" "$diagnostic_msg"
				else
					local ip_display
					ip_display=$(format_peer_ip_display "$peer_ip" "$internal_peer_ip")
					handle_error "WARNING" "$location_name" "VPN suspect: SA exists for $ip_display but byte counter info unavailable and ping check failed"
				fi
				return 1
			fi
		else
			# Ping check disabled or internal IP not provided - cannot verify VPN health
			# Log debug info about why byte counter extraction failed
			local ip_display
			ip_display=$(format_peer_ip_display "$peer_ip" "")
			log_message "DEBUG" "$location_name" "Byte counter extraction failed for $ip_display - xfrm output format may differ. Consider enabling ENABLE_PING_CHECK=1 for fallback verification."
			local reason="ping check disabled"
			if [[ -z "$internal_peer_ip" ]]; then
				reason="internal IP not provided"
			fi
			local diagnostic_msg="Detection method: xfrm (ip xfrm state) - SA exists for $peer_ip but byte counter info unavailable ($reason)"
			if [[ -n "$diagnostic_var" ]]; then
				printf -v "$diagnostic_var" "%s" "$diagnostic_msg"
			else
				local ip_display
				ip_display=$(format_peer_ip_display "$peer_ip" "")
				handle_error "WARNING" "$location_name" "VPN suspect: SA exists for $ip_display but byte counter info unavailable (ping check disabled or internal IP not provided)"
			fi
			return 1
		fi
	fi
}

# Check VPN status using ipsec status
#
# Checks for connection existence using ipsec status command.
#
# Arguments:
#   $1: Peer IP address
#   $2: Location name (required, used for logging)
#   $3: Diagnostic variable name (optional, if provided, diagnostic message is stored here instead of logging)
#
# Returns:
#   0: Connection found
#   1: Connection not found
#
# Side effects:
#   - Logs debug/warning messages (unless diagnostic variable name is provided)
#   - If diagnostic variable name is provided, stores diagnostic message in that variable instead of logging
check_ipsec_status() {
	local peer_ip="$1"
	local location_name="$2"
	local diagnostic_var="${3:-}"

	# Validate location_name is provided (required for logging)
	if [[ -z "$location_name" ]]; then
		handle_error "ERROR" "SYSTEM" "check_ipsec_status: location_name is required" 0
		return 1
	fi

	# ipsec = legacy IPsec tools (libreswan/strongswan compatibility command)
	if ! check_command_or_warn "ipsec" "Checking IPsec status"; then
		return 1
	fi

	local ipsec_output
	# Use fixed-string matching (-F) for consistency and safety (IP addresses don't need case-insensitive matching)
	# Wrap ipsec status with timeout to prevent hanging
	# Note: get_ipsec_status_for_peer handles command availability check, but we already checked above
	# If it fails, output will be empty which is handled below
	ipsec_output=$(get_ipsec_status_for_peer "$peer_ip" || true)

	if [[ -n "$ipsec_output" ]]; then
		local ip_display
		ip_display=$(format_peer_ip_display "$peer_ip" "")
		log_message "INFO" "$location_name" "VPN OK: Connection found via ipsec status for $ip_display"
		return 0
	else
		local diagnostic_msg="Detection method: ipsec status - No connection found via ipsec status for $peer_ip"
		if [[ -n "$diagnostic_var" ]]; then
			printf -v "$diagnostic_var" "%s" "$diagnostic_msg"
		else
			local ip_display
			ip_display=$(format_peer_ip_display "$peer_ip" "")
			handle_error "WARNING" "$location_name" "VPN suspect: No connection found via ipsec status for $ip_display"
		fi
		return 1
	fi
}

# Discover connection name from ipsec status
#
# Attempts to discover the IPsec connection name associated with a peer IP
# by parsing ipsec status output. Connection names are cached to avoid
# repeated parsing. This is for logging/debugging purposes only - recovery
# actions use ipsec reload which affects all connections.
#
# Arguments:
#   $1: Peer IP address (external/public IP)
#
# Returns:
#   0: Always succeeds (function never fails, returns empty string if not found)
#
# Output:
#   Prints connection name to stdout if found, empty string otherwise
#
# Side effects:
#   - Caches connection name using abstraction layer (set_peer_state_non_critical)
#   - Cache file: ${STATE_DIR}/connection_name_<sanitized_peer_ip>
#   - Uses atomic writes for consistency with other state files
#   - Logs debug messages if DEBUG=1
#
# Examples:
#   conn_name=$(discover_connection_name "192.168.1.1")
#   # Returns: "site-a" or empty string
#
# Note:
#   Requires get_peer_state_file_path and set_peer_state_non_critical (from state.sh), STATE_DIR, and log_message to be set
#   Uses abstraction layer for consistent state file path management and atomic writes
#   ipsec command is optional - cached values can be retrieved even if ipsec is unavailable
#   Connection names are for logging only - recovery uses ipsec reload (all connections)
#   connection_name is per-peer only (no location), so empty location is passed to abstraction layer
discover_connection_name() {
	local peer_ip="$1"
	local connection_name=""

	# Check cache first - use cached value if available, even if ipsec is not available
	# Get cache file path using abstraction layer for consistency
	# connection_name is per-peer only (no location), so pass empty string for location
	local cache_file
	cache_file=$(get_peer_state_file_path "" "$peer_ip" "connection_name")
	if file_exists_and_readable "$cache_file"; then
		connection_name=$(cat "$cache_file" 2>/dev/null || echo "")
		if [[ -n "$connection_name" ]]; then
			log_message "DEBUG" "SYSTEM" "Using cached connection name '$connection_name' for $peer_ip"
			echo "$connection_name"
			return 0
		fi
	fi

	# Check if ipsec command is available (only needed if cache miss)
	if ! check_command_available "ipsec"; then
		echo ""
		return 0
	fi

	# Get ipsec status output
	# Wrap ipsec status with timeout to prevent hanging
	local ipsec_output
	ipsec_output=$(get_ipsec_status_for_peer "") || ipsec_output=""

	if [[ -z "$ipsec_output" ]]; then
		echo ""
		return 0
	fi

	# Parse ipsec status output to find connection name
	# Common formats:
	# - libreswan: "conn-name: ESTABLISHED 1 hour ago, 192.168.1.1...192.168.1.2"
	# - strongswan: "conn-name: IKEv1, ESTABLISHED, 192.168.1.1"
	# Look for lines containing the peer IP and extract connection name (text before colon)
	local IFS=$'\n'
	for line in $ipsec_output; do
		# Check if line contains peer IP
		if echo "$line" | grep -qF "$peer_ip"; then
			# Extract connection name (everything before first colon, trimmed)
			connection_name=$(echo "$line" | sed -n 's/^[[:space:]]*\([^:]*\):.*/\1/p')
			connection_name=$(trim "$connection_name")
			if [[ -n "$connection_name" ]]; then
				# Cache the result using abstraction layer for atomic write consistency
				# connection_name is per-peer only (no location), so pass empty string for location
				set_peer_state_non_critical "" "$peer_ip" "connection_name" "$connection_name"
				log_message "DEBUG" "SYSTEM" "Discovered connection name '$connection_name' for $peer_ip"
				echo "$connection_name"
				return 0
			fi
		fi
	done

	# Not found - return empty string
	echo ""
	return 0
}

# Check for IPsec Phase 2 Security Association
#
# Checks if IPsec Phase 2 SA (ESP/AH SA) exists for a peer using xfrm.
# IPsec Phase 2 establishes the actual encrypted tunnel for data transfer.
# If Phase 2 is down but Phase 1 is up, the tunnel is partially established but cannot pass traffic.
#
# Arguments:
#   $1: Peer IP address to check
#
# Returns:
#   0: IPsec Phase 2 SA found
#   1: IPsec Phase 2 SA not found or xfrm unavailable
#
# Side effects:
#   - Logs debug messages about IPsec SA status
#
# Note:
#   Uses ip xfrm state which shows IPsec SAs (Phase 2).
#   xfrm shows ESP/AH SAs that are used for actual data encryption.
#   Requires ip command to be available
check_ipsec_phase2() {
	local peer_ip="$1"

	if ! check_command_or_warn "ip" "Checking IPsec Phase 2"; then
		return 1
	fi

	local xfrm_output
	# Use fixed-string matching to prevent regex pattern injection and avoid partial IP matches
	# Match on "dst $peer_ip" pattern which appears at the start of each SA entry
	# This ensures we match the complete SA entry and avoid partial IP matches
	# Note: check_ipsec_phase2 doesn't need context lines, so we pass 0
	xfrm_output=$(get_xfrm_state_for_peer "$peer_ip" 0)

	if [[ -n "$xfrm_output" ]]; then
		return 0
	fi

	return 1
}

# Check VPN status using xfrm (primary method)
#
# Checks VPN status using the primary xfrm method, which is the most reliable.
#
# Arguments:
#   $1: External peer IP address (external/public IP of remote VPN gateway)
#   $2: Internal peer IP address (optional, used for idle detection via ping checks)
#   $3: Location name (required, used for state file naming and passed to check_xfrm_status)
#   $4: Diagnostic variable name (optional, if provided, diagnostic message is stored here instead of logging)
#   $5: SA existence output variable name (optional, if provided, SA existence state (0 or 1) is stored here)
#   $6: XFRM output variable name (optional, if provided, xfrm state output is stored here for reuse)
#
# Returns:
#   0: VPN is healthy (SA exists and valid)
#   1: VPN check failed (no SA found or invalid)
#
# Side effects:
#   - Logs debug/warning messages (unless diagnostic variable name is provided)
#   - If diagnostic variable name is provided, stores diagnostic message in that variable instead of logging
#   - If SA existence output variable name is provided, stores SA existence state (0 or 1) in that variable
#   - If XFRM output variable name is provided, stores xfrm state output in that variable for reuse (optimization)
check_xfrm_primary() {
	local external_peer_ip="$1"
	local internal_peer_ip="${2:-}"
	local location_name="$3"
	local diagnostic_var="${4:-}"
	local sa_exists_var="${5:-}"
	local xfrm_output_var="${6:-}"

	# Validate location_name is provided (required for check_xfrm_status)
	if [[ -z "$location_name" ]]; then
		handle_error "ERROR" "SYSTEM" "check_xfrm_primary: location_name is required" 0
		return 1
	fi

	# Try detection using xfrm (most reliable method)
	# Pass internal IP and location_name to check_xfrm_status for idle detection via ping checks
	# Also pass SA existence output variable to expose SA state separately
	# Pass xfrm_output_var to expose xfrm state output for reuse by downstream functions (optimization)
	check_xfrm_status "$external_peer_ip" "$internal_peer_ip" "$location_name" "$diagnostic_var" "$sa_exists_var" "$xfrm_output_var"
}

# Check VPN status using ipsec (fallback method)
#
# Checks VPN status using the fallback ipsec method when xfrm check fails.
#
# Arguments:
#   $1: External peer IP address (external/public IP of remote VPN gateway)
#   $2: Location name (required, used for logging)
#   $3: Diagnostic variable name (optional, if provided, diagnostic message is stored here instead of logging)
#
# Returns:
#   0: VPN is healthy (connection found)
#   1: VPN check failed (no connection found)
#
# Side effects:
#   - Logs debug/warning messages (unless diagnostic variable name is provided)
#   - If diagnostic variable name is provided, stores diagnostic message in that variable instead of logging
check_ipsec_fallback() {
	local external_peer_ip="$1"
	local location_name="$2"
	local diagnostic_var="${3:-}"

	# Validate location_name is provided (required for check_ipsec_status)
	if [[ -z "$location_name" ]]; then
		handle_error "ERROR" "SYSTEM" "check_ipsec_fallback: location_name is required" 0
		return 1
	fi

	# Fallback to ipsec status check if xfrm didn't confirm
	check_ipsec_status "$external_peer_ip" "$location_name" "$diagnostic_var"
}
