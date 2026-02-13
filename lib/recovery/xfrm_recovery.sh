#!/bin/bash
#
# xfrm-based recovery functions for UDM VPN Monitor
# Implements per-connection recovery using Linux kernel xfrm framework
#
# Version: 0.7.0
#

# Source recovery constants for magic numbers
# shellcheck source=lib/recovery/constants.sh
RECOVERY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${RECOVERY_DIR}/constants.sh"

# shellcheck source=lib/constants.sh
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! source "${LIB_DIR}/constants.sh" 2>/dev/null; then
	[[ -z "${XFRM_OUTPUT_CONTEXT_LINES:-}" ]] && readonly XFRM_OUTPUT_CONTEXT_LINES=10
	[[ -z "${XFRM_PARSE_MAX_SIZE_BYTES:-}" ]] && readonly XFRM_PARSE_MAX_SIZE_BYTES=51200
	[[ -z "${XFRM_PARSE_MAX_LINES:-}" ]] && readonly XFRM_PARSE_MAX_LINES=5000
fi

# shellcheck source=lib/recovery/recovery_state.sh
source "${RECOVERY_DIR}/recovery_state.sh" 2>/dev/null || {
	# Clear recovery method for a location (fallback stub)
	#
	# Fallback stub function when recovery_state.sh cannot be sourced.
	# Always succeeds silently since state clearing is non-critical.
	#
	# Arguments:
	#   $1: Location name (ignored in fallback)
	#   $2: External peer IP address (ignored in fallback)
	#
	# Returns:
	#   0: Always succeeds (recovery_state.sh unavailable, but non-critical)
	#
	# Note:
	#   This is a fallback stub. The real implementation is in recovery_state.sh.
	clear_recovery_method() { return 0; }
}

# shellcheck source=lib/detection.sh
source "${LIB_DIR}/detection.sh" 2>/dev/null || {
	# Check for IPsec Phase 2 Security Association (fallback stub)
	#
	# Fallback stub function when detection.sh cannot be sourced.
	# Always returns failure since detection functionality is unavailable.
	#
	# Arguments:
	#   $1: Peer IP address (ignored in fallback)
	#
	# Returns:
	#   1: Always returns failure (detection.sh unavailable)
	#
	# Note:
	#   This is a fallback stub. The real implementation is in detection/xfrm_detection.sh.
	check_ipsec_phase2() { return 1; }
	# Extract byte counter from xfrm output (fallback stub)
	#
	# Fallback stub function when detection.sh cannot be sourced.
	# Always returns failure since detection functionality is unavailable.
	#
	# Arguments:
	#   $1: xfrm output text (ignored in fallback)
	#
	# Returns:
	#   1: Always returns failure (detection.sh unavailable)
	#
	# Note:
	#   This is a fallback stub. The real implementation is in detection/xfrm_detection.sh.
	extract_byte_counter() { return 1; }
	# Get xfrm state for peer (fallback stub)
	#
	# Fallback stub function when detection.sh cannot be sourced.
	# Always returns failure since detection functionality is unavailable.
	#
	# Arguments:
	#   $1: Peer IP address (ignored in fallback)
	#   $2: Context lines for output (optional, ignored in fallback)
	#
	# Returns:
	#   1: Always returns failure (detection.sh unavailable)
	#
	# Note:
	#   This is a fallback stub. The real implementation is in detection/xfrm_detection.sh.
	get_xfrm_state_for_peer() { return 1; }
}

# Source recovery verification functions
# shellcheck source=lib/recovery/recovery_verification.sh
# RECOVERY_DIR already defined above
source "${RECOVERY_DIR}/recovery_verification.sh" 2>/dev/null || {
	# Fallback stubs if recovery_verification.sh not available
	# Count Security Associations for a peer IP (fallback stub)
	#
	# Fallback stub function when recovery_verification.sh cannot be sourced.
	# Always returns failure since verification functionality is unavailable.
	#
	# Arguments:
	#   $1: Peer IP address to count SAs for (ignored in fallback)
	#   $2: Optional location name for diagnostic logging (ignored in fallback)
	#
	# Returns:
	#   1: Always returns failure (recovery_verification.sh unavailable)
	#
	# Note:
	#   This is a fallback stub. The real implementation is in recovery_verification.sh.
	count_sas_for_peer() { return 1; }
	# Verify byte counters increment after SA re-establishment (fallback stub)
	#
	# Fallback stub function when recovery_verification.sh cannot be sourced.
	# Always returns failure since verification functionality is unavailable.
	#
	# Arguments:
	#   $1: Peer IP address to verify (ignored in fallback)
	#   $2: Initial byte counter value (baseline, ignored in fallback)
	#   $3: Optional location name for logging context (ignored in fallback)
	#
	# Returns:
	#   1: Always returns failure (recovery_verification.sh unavailable)
	#
	# Note:
	#   This is a fallback stub. The real implementation is in recovery_verification.sh.
	verify_byte_counters_increment() { return 1; }
}

# Extract SA block from xfrm output
#
# Extracts the Security Association (SA) block for a specific src/dst pair from xfrm output.
# The SA block includes the header line (src ... dst ...) and all continuation lines until
# the next SA block starts (indicated by a new line starting with "src").
#
# Arguments:
#   $1: xfrm output text (read from stdin if not provided)
#   $2: Source IP address (required)
#   $3: Destination IP address (required)
#   $4: Maximum number of lines to extract (optional, default: 20)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the extracted SA block to stdout
#
# Example:
#   sa_block=$(extract_sa_block "$xfrm_output" "192.0.2.1" "192.0.2.2" 15)
extract_sa_block() {
	local xfrm_output="${1:-}"
	local sa_src="$2"
	local sa_dst="$3"
	local max_lines="${4:-20}"

	if [[ -z "$sa_src" ]] || [[ -z "$sa_dst" ]]; then
		return 0
	fi

	# If xfrm_output is provided as argument, use it; otherwise read from stdin
	if [[ -n "$xfrm_output" ]]; then
		echo "$xfrm_output" | awk '
			/^src '"$sa_src"'[[:space:]]+dst '"$sa_dst"'/ {found=1; print; next}
			found && /^src/ {found=0}
			found {print}
		' | head -"$max_lines"
	else
		awk '
			/^src '"$sa_src"'[[:space:]]+dst '"$sa_dst"'/ {found=1; print; next}
			found && /^src/ {found=0}
			found {print}
		' | head -"$max_lines"
	fi
}

# Delete Security Associations for a specific peer using xfrm
#
# Attempts per-connection recovery by deleting SAs for a specific peer IP using the Linux kernel's
# xfrm framework. This provides surgical recovery for per-connection recovery.
#
# After deleting SAs, verifies that new SAs are re-established before reporting success.
# This ensures recovery actually worked and the tunnel is functional.
#
# Arguments:
#   $1: Peer IP address to clean up
#   $2: Location name (required for logging context)
#
# Returns:
#   0: SAs deleted successfully and re-established (or no SAs found for this peer)
#   1: Failed to delete SAs, parsing error, or SAs did not re-establish within timeout
#
# Side effects:
#   - Deletes xfrm state entries (SAs) for the peer IP
#   - Deletes xfrm policies for the peer IP
#   - Verifies SA re-establishment after deletion
#   - Logs all actions and results
#
# Algorithm Overview:
#   This function implements a multi-phase recovery process:
#   1. Query Phase: Retrieve all xfrm state entries from the kernel
#   2. Filter Phase: Extract only entries matching the target peer IP
#   3. Parse Phase: Extract SA selectors (src, dst, proto, spi) from filtered output
#   4. Delete Phase: Delete each parsed SA using ip xfrm state delete
#   5. Verify Phase: Wait for SA re-establishment with exponential backoff
#
# Parsing Algorithm Details:
#   The xfrm state output format on UDM OS 4.3+ follows this structure:
#     src <source_ip> dst <dest_ip>
#       proto <protocol> spi <spi_value>
#       [additional SA attributes...]
#
#   Parsing assumptions:
#   - Each SA block starts with a line matching: "^src <ip> dst <ip>"
#   - The proto and spi values appear on continuation lines (may be indented)
#   - Proto can appear on the same line as spi: "proto esp spi 0x12345678"
#   - Proto and spi can also appear on separate lines
#   - Valid protocols: "esp" or "ah" (case-insensitive, normalized to lowercase)
#   - Valid SPI formats: hex (0x12345678) or decimal (12345678)
#
#   Parsing state machine:
#   - State: in_sa_block (boolean) - tracks if we're currently parsing an SA block
#   - State: current_src, current_dst, current_proto, current_spi - current SA selectors
#   - Transition: When we see "^src ... dst ..." line:
#       * If in_sa_block=1 and all selectors complete, save previous SA to list
#       * Start new SA block, extract src and dst from regex match
#       * Reset proto and spi to empty
#   - Transition: When in_sa_block=1 and line matches "proto ...":
#       * Extract protocol name, normalize to lowercase
#       * Check if "spi" appears on same line, extract if present
#   - Transition: When in_sa_block=1 and line matches "spi ...":
#       * Extract SPI value (overwrites any previously extracted SPI)
#   - Finalization: After processing all lines, save last SA if complete
#
#   Edge cases handled:
#   - Empty xfrm output: Returns success if no SAs exist (may already be down)
#   - Partial SA blocks: Only saves SAs with all four selectors (src, dst, proto, spi)
#   - Invalid selectors: Validates proto (esp/ah) and spi (hex/decimal) before saving
#   - Parse errors: Tracks parse_errors count, fails if errors exist and no valid SAs found
#   - Multiple SAs: Processes all matching SAs, deletes each individually
#
# Filtering Algorithm:
#   Uses grep -F (fixed-string matching) with "dst $external_peer_ip" pattern to:
#   - Prevent regex pattern injection (treats IP as literal string)
#   - Provide natural word boundaries (exact match prevents partial IP matches)
#   - Example: "dst 192.168.1.1" won't match "dst 192.168.1.10" due to exact matching
#   - Includes context lines (-A) to capture complete SA blocks after match line
#
# Verification Algorithm:
#   After deletion, waits for SA re-establishment using exponential backoff:
#   - Initial interval: XFRM_RECOVERY_VERIFY_INTERVAL (default: 2 seconds)
#   - Backoff: Doubles interval each attempt (2s → 4s → 8s → 16s)
#   - Maximum interval: XFRM_RECOVERY_MAX_INTERVAL (default: 16 seconds)
#   - Timeout: RECOVERY_VERIFY_TIMEOUT or XFRM_RECOVERY_VERIFY_TIMEOUT (default: 30 seconds)
#   - Verification checks:
#     * SA existence via check_ipsec_phase2()
#     * SA count via count_sas_for_peer()
#     * Byte counter increment via verify_byte_counters_increment()
#       - Captures initial byte counter value when SA is first re-established (may be zero)
#       - Checks for counter increment from initial value (indicates traffic is flowing)
#       - Handles case where counters reset to zero after SA deletion/re-establishment
#
# Assumptions:
#   - UDM OS 4.3+ uses consistent xfrm output format (tested format)
#   - strongSwan will automatically re-establish SAs after deletion
#   - Re-establishment typically occurs within 30 seconds
#   - Byte counters may reset to zero after SA deletion/re-establishment (handled by increment check)
#   - Verification checks for counter increment rather than absolute non-zero value
#   - Multiple SAs may exist for a single peer (common with multiple subnets)
#
# Error Handling:
#   - Query failure: Returns error immediately (can't proceed without xfrm state)
#   - Empty output: Returns failure if no SAs exist (xfrm recovery cannot help, triggers fallback)
#     * If no SAs exist, xfrm recovery cannot recover the VPN, so fallback to ipsec reload/restart is needed
#   - Parse errors: Fails only if no valid SAs found (partial success allowed)
#   - Delete failures: Tracks failed_count, fails if all deletions failed
#   - Re-establishment timeout: Returns error to trigger fallback recovery strategy
#   - Byte counter verification failure: Returns error if SA re-established but byte counters don't increment within timeout
#
# Examples:
#   # Delete and re-establish SAs for peer 203.0.113.1
#   if attempt_xfrm_recovery "203.0.113.1" "NYC"; then
#       echo "Recovery successful"
#   else
#       echo "Recovery failed, will fall back to ipsec reload"
#   fi
#
#   # Example xfrm output format being parsed:
#   # src 192.168.1.1 dst 203.0.113.1
#   #   proto esp spi 0x12345678
#   #   mode tunnel
#   #   ...
#
# Note:
#   This function parses 'ip xfrm state' output to extract SA selectors (src, dst, proto, spi, mark).
#   Mark selector is optional - when present, it must be included in deletion commands for successful deletion.
#   Parsing is optimized for UDM OS 4.3+ format. Supports both IPv4 and IPv6 addresses.
#   Requires 'ip' command and root privileges.
#   Uses check_ipsec_phase2() from detection.sh to verify SA re-establishment.

# Parse xfrm output to extract Security Association list
#
# Parses xfrm state output using a state machine to extract complete SA entries.
# Each SA is stored as a delimited string: "src|dst|proto|spi|mark"
#
# Arguments:
#   $1: xfrm output to parse (from get_xfrm_state_for_peer)
#   $2: Peer IP address (for filtering matching SAs)
#   $3: Location name (required for logging context)
#   $4: Variable name to set with sa_list array (output parameter, nameref)
#
# Returns:
#   0: Success (parsed SAs or no SAs found)
#   1: Failure (parsing errors and no valid SAs found)
#
# Side effects:
#   - Sets the array variable specified in $4 with parsed SA entries
#   - Logs parsing progress and errors
#
# Note:
#   Only includes SAs that match the peer IP (forward SA: dst=$external_peer_ip, reverse SA: src=$external_peer_ip)
#   Validates proto (esp/ah) and spi (hex/decimal) before adding to list
parse_xfrm_output_to_sa_list() {
	local xfrm_output="$1"
	local external_peer_ip="$2"
	local location_name="$3"
	local -n sa_list_ref="$4"

	local parse_errors=0

	# Format IP display once for reuse
	local ip_display
	ip_display=$(format_peer_ip_display "$external_peer_ip" "")

	# Input validation: Check size and prevent DoS/excessive processing time
	# The parsing loop will always terminate, but large input can cause slow processing
	# and memory issues. These limits prevent DoS while allowing normal operation.
	local xfrm_output_size=${#xfrm_output}
	if [[ $xfrm_output_size -gt ${XFRM_PARSE_MAX_SIZE_BYTES:-51200} ]]; then
		handle_error "WARNING" "$location_name" "xfrm recovery: xfrm output too large ($xfrm_output_size bytes, limit=${XFRM_PARSE_MAX_SIZE_BYTES:-51200}), skipping parse for $ip_display"
		return 1
	fi

	# Parse xfrm output to extract SAs
	# Format: Each SA block starts with "src <ip> dst <ip>" followed by "proto <proto> spi <spi>"
	# UDM OS 4.3+ uses consistent format: src and dst on first line, proto and spi on continuation lines
	# Mark attribute (optional): "mark 0x<value>/0x<mask>" appears on continuation lines
	#
	# Parsing state variables:
	#   current_src, current_dst: Source and destination IPs (extracted from SA header line)
	#   current_proto, current_spi: Protocol and SPI (extracted from continuation lines)
	#   current_mark: Mark selector (extracted from continuation lines, optional)
	#   in_sa_block: Boolean flag indicating we're currently parsing an SA block
	#   sa_list: Array of complete SA entries in format "src|dst|proto|spi|mark" (mark may be empty)
	local current_src=""
	local current_dst=""
	local current_proto=""
	local current_spi=""
	local current_mark=""
	local in_sa_block=0
	sa_list_ref=()

	log_message "DEBUG" "$location_name" "xfrm recovery: Parsing xfrm output for $ip_display"

	# Check if SA block has all required selectors
	#
	# Determines if a Security Association block has all required selectors (src, dst, proto, spi)
	# for a complete SA entry. Used to validate SA completeness before saving to the list.
	#
	# Arguments:
	#   $1: in_sa_block flag (0 or 1)
	#   $2: current_src value
	#   $3: current_dst value
	#   $4: current_proto value
	#   $5: current_spi value
	#
	# Returns:
	#   0: SA is complete (all selectors present)
	#   1: SA is incomplete (missing one or more selectors)
	#
	# Note:
	#   This function extracts the duplicate 5-condition boolean check to improve readability
	#   and maintainability. The check appears in two places: before starting a new SA block
	#   and when finalizing the last SA block.
	is_sa_complete() {
		local in_block="$1"
		local src="$2"
		local dst="$3"
		local proto="$4"
		local spi="$5"

		if [[ $in_block -eq 1 ]] && [[ -n "$src" ]] && [[ -n "$dst" ]] && [[ -n "$proto" ]] && [[ -n "$spi" ]]; then
			return 0
		fi
		return 1
	}

	# Parse loop: Process each line of xfrm output
	# State machine transitions:
	#   1. New SA block detected (line starts with "src ... dst ..."):
	#      - Save previous SA if complete (all selectors present)
	#      - Start new SA block, extract src and dst
	#      - Reset proto, spi, and mark (will be extracted from continuation lines)
	#   2. Continuation line (within SA block):
	#      - Extract proto if present (may be on same line as spi)
	#      - Extract spi if present (may be on same line as proto or separate line)
	#      - Extract mark if present (format: "mark 0x<value>/0x<mask>")
	#      - Note: Later spi match overwrites earlier one (handles both formats)
	local line_count=0
	while IFS= read -r line || [[ -n "$line" ]]; do
		line_count=$((line_count + 1))
		# Line count protection: prevent excessive processing time
		# The loop will always terminate, but this prevents DoS from extremely large input
		if [[ $line_count -gt ${XFRM_PARSE_MAX_LINES:-5000} ]]; then
			handle_error "WARNING" "$location_name" "xfrm recovery: xfrm output has too many lines ($line_count, limit=${XFRM_PARSE_MAX_LINES:-5000}), stopping parse for $ip_display"
			return 1
		fi
		# Skip empty lines (don't affect parsing state)
		[[ -z "$line" ]] && continue

		# State transition: New SA block detected
		# Regex matches: "src <ipv4_or_ipv6> dst <ipv4_or_ipv6>"
		# Try IPv4 first (more specific pattern to avoid matching hex digits from SPI values)
		# Then fall back to IPv6 pattern if IPv4 doesn't match
		local sa_header_match=0
		local extracted_src=""
		local extracted_dst=""
		if [[ "$line" =~ ^src[[:space:]]+([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})[[:space:]]+dst[[:space:]]+([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}) ]]; then
			# IPv4 addresses matched
			extracted_src="${BASH_REMATCH[1]:-}"
			extracted_dst="${BASH_REMATCH[2]:-}"
			sa_header_match=1
		elif [[ "$line" =~ ^src[[:space:]]+([0-9a-fA-F:]+)[[:space:]]+dst[[:space:]]+([0-9a-fA-F:]+) ]]; then
			# IPv6 addresses matched (fallback)
			extracted_src="${BASH_REMATCH[1]:-}"
			extracted_dst="${BASH_REMATCH[2]:-}"
			sa_header_match=1
		fi

		if [[ $sa_header_match -eq 1 ]]; then
			# Before starting new SA, save previous SA if it's complete
			# Complete SA requires: src, dst, proto, and spi all present
			# This handles the case where we've finished parsing one SA and found the next
			if is_sa_complete "$in_sa_block" "$current_src" "$current_dst" "$current_proto" "$current_spi"; then
				# CRITICAL: Verify that the SA matches the target peer IP (forward SA: dst=$external_peer_ip, reverse SA: src=$external_peer_ip)
				# This prevents deleting SAs for wrong locations when grep -A includes subsequent SA blocks
				# Accept both forward SAs (dst=$external_peer_ip) and reverse SAs (src=$external_peer_ip) to handle asymmetric SA state
				if [[ "$current_dst" == "$external_peer_ip" ]] || [[ "$current_src" == "$external_peer_ip" ]]; then
					# Validate selectors before adding to list
					# Proto must be "esp" or "ah" (case-insensitive, already normalized)
					# SPI must be hex (0x...) or decimal format
					if [[ "$current_proto" =~ ^(esp|ah)$ ]] && validate_spi_format "$current_spi"; then
						# Store complete SA as delimited string for later processing
						# Format: "src|dst|proto|spi|mark" (pipe separator avoids IP address conflicts)
						# Mark is optional - may be empty for SAs without mark selectors
						sa_list_ref+=("$current_src|$current_dst|$current_proto|$current_spi|${current_mark:-}")
						log_message "DEBUG" "$location_name" "xfrm recovery: Parsed SA: src=$current_src dst=$current_dst proto=$current_proto spi=$current_spi mark=${current_mark:-<none>} for $ip_display"
					else
						# Invalid selectors: log warning but continue parsing (may have valid SAs later)
						handle_error "WARNING" "$location_name" "xfrm recovery: Invalid SA selectors: src=$current_src dst=$current_dst proto=$current_proto spi=$current_spi for $ip_display"
						parse_errors=$((parse_errors + 1))
					fi
				else
					# SA doesn't match target peer IP (neither dst nor src matches) - skip this SA
					# This can happen when grep -A includes subsequent SA blocks from other locations
					log_message "DEBUG" "$location_name" "xfrm recovery: Skipping SA with src=$current_src dst=$current_dst (does not match target external_peer_ip=$ip_display)"
				fi
			fi

			# CRITICAL: Only start parsing this SA block if it matches target peer IP (forward SA: dst=$external_peer_ip, reverse SA: src=$external_peer_ip)
			# This prevents parsing SAs for wrong locations when grep -A includes subsequent SA blocks
			# Accept both forward SAs (dst=$external_peer_ip) and reverse SAs (src=$external_peer_ip) to handle asymmetric SA state
			if [[ "$extracted_dst" == "$external_peer_ip" ]] || [[ "$extracted_src" == "$external_peer_ip" ]]; then
				# Start new SA block: extract src and dst from regex match
				current_src="$extracted_src"
				current_dst="$extracted_dst"
				current_proto="" # Will be extracted from continuation lines
				current_spi=""   # Will be extracted from continuation lines
				current_mark=""  # Will be extracted from continuation lines (optional)
				in_sa_block=1    # Mark that we're now parsing an SA block
			else
				# SA doesn't match target peer IP (neither dst nor src matches) - skip this SA block entirely
				# Reset parsing state to skip all continuation lines for this SA
				in_sa_block=0
				current_src=""
				current_dst=""
				current_proto=""
				current_spi=""
				current_mark=""
				log_message "DEBUG" "$location_name" "xfrm recovery: Skipping SA block with src=$extracted_src dst=$extracted_dst (does not match target external_peer_ip=$ip_display)"
			fi

		# State: Continuation line (within an SA block)
		# Extract proto and spi from indented continuation lines
		elif [[ $in_sa_block -eq 1 ]]; then
			# Look for "proto <protocol>" line (may be indented with spaces/tabs)
			# Regex allows optional leading whitespace, captures protocol name
			# Also handles case where "spi" appears on same line: "proto esp spi 0x12345678"
			if [[ "$line" =~ ^[[:space:]]*proto[[:space:]]+([a-zA-Z0-9]+) ]]; then
				# Use default empty string to handle set -u safely (shouldn't happen if regex matches, but defensive)
				current_proto="${BASH_REMATCH[1]:-}"
				# Normalize to lowercase for consistency (xfrm uses lowercase internally)
				current_proto=$(echo "$current_proto" | tr '[:upper:]' '[:lower:]')
				# Check if "spi" is on the same line as "proto" (common format)
				# If found, extract SPI immediately (avoids needing separate line)
				if [[ "$line" =~ [[:space:]]+spi[[:space:]]+(0x[0-9a-fA-F]+|[0-9]+) ]]; then
					current_spi="${BASH_REMATCH[1]:-}"
				fi
			fi
			# Look for "spi <spi_value>" on its own line (alternative format)
			# This regex runs after proto check, so it will overwrite SPI if proto line had SPI
			# This is intentional: handles both "proto esp spi 0x123" and separate "spi 0x123" lines
			# Supports hex (0x12345678) and decimal (12345678) formats
			if [[ "$line" =~ ^[[:space:]]*spi[[:space:]]+(0x[0-9a-fA-F]+|[0-9]+) ]]; then
				current_spi="${BASH_REMATCH[1]:-}"
			fi
			# Look for "mark <value>/<mask>" line (optional selector, format: "mark 0x<value>/0x<mask>")
			# Mark is a required selector when present - must be included in deletion commands
			# Format examples: "mark 0x12000000/0xfe000000" or "mark 0x12345678/0xffffffff"
			if [[ "$line" =~ ^[[:space:]]*mark[[:space:]]+(0x[0-9a-fA-F]+/0x[0-9a-fA-F]+) ]]; then
				current_mark="${BASH_REMATCH[1]:-}"
			fi
		fi
	done <<<"$xfrm_output"

	# Finalization: Process the last SA block if parsing ended mid-block
	# This handles the case where the last SA in the output doesn't have a following "src ... dst ..." line
	# to trigger the save logic in the main loop
	if is_sa_complete "$in_sa_block" "$current_src" "$current_dst" "$current_proto" "$current_spi"; then
		# CRITICAL: Verify that the SA matches the target peer IP (forward SA: dst=$external_peer_ip, reverse SA: src=$external_peer_ip)
		# This prevents deleting SAs for wrong locations when grep -A includes subsequent SA blocks
		# Accept both forward SAs (dst=$external_peer_ip) and reverse SAs (src=$external_peer_ip) to handle asymmetric SA state
		if [[ "$current_dst" == "$external_peer_ip" ]] || [[ "$current_src" == "$external_peer_ip" ]]; then
			# Validate selectors before adding to list (same validation as in main loop)
			if [[ "$current_proto" =~ ^(esp|ah)$ ]] && validate_spi_format "$current_spi"; then
				sa_list_ref+=("$current_src|$current_dst|$current_proto|$current_spi|${current_mark:-}")
				log_message "DEBUG" "$location_name" "xfrm recovery: Parsed SA: src=$current_src dst=$current_dst proto=$current_proto spi=$current_spi mark=${current_mark:-<none>} for $ip_display"
			else
				handle_error "WARNING" "$location_name" "xfrm recovery: Invalid SA selectors: src=$current_src dst=$current_dst proto=$current_proto spi=$current_spi for $ip_display"
				parse_errors=$((parse_errors + 1))
			fi
		else
			# SA doesn't match target peer IP (neither dst nor src matches) - skip this SA
			# This can happen when grep -A includes subsequent SA blocks from other locations
			log_message "DEBUG" "$location_name" "xfrm recovery: Skipping final SA with src=$current_src dst=$current_dst (does not match target external_peer_ip=$ip_display)"
		fi
	fi

	# Error handling: If parsing produced errors but no valid SAs, fail immediately
	# This indicates a fundamental parsing problem (e.g., format changed, corrupted output)
	# If we have some valid SAs, we continue (partial success is acceptable)
	if [[ $parse_errors -gt 0 ]] && [[ ${#sa_list_ref[@]} -eq 0 ]]; then
		handle_error "WARNING" "$location_name" "xfrm recovery: Parsing failed for $ip_display (found $parse_errors invalid SA(s))"
		return 1
	fi

	return 0
}

# Delete Security Associations from a list
#
# Deletes each SA in the provided list using ip xfrm state delete commands.
# Includes comprehensive diagnostics and error handling.
#
# Arguments:
#   $1-$N: SA entries in format "src|dst|proto|spi|mark" (variable number)
#   $N-3: Peer IP address
#   $N-2: Location name (required for logging context)
#   $N-1: Variable name to set with deleted_count (output parameter, nameref)
#   $N: Variable name to set with failed_count (output parameter, nameref)
#
# Returns:
#   0: Success (at least one SA deleted or no SAs in list)
#   1: Failure (all deletions failed)
#
# Side effects:
#   - Sets variables specified in $N-1 and $N with deletion counts via nameref
#   - Deletes xfrm state entries (SAs)
#   - Logs all actions and results
delete_sas_from_list() {
	# Extract arguments: sa_list entries are all but last 4 args
	local sa_list=()
	local arg_count=$#
	local sa_count=$((arg_count - 4))

	# Extract SA list entries
	local i=1
	while [[ $i -le $sa_count ]]; do
		sa_list+=("${!i}")
		i=$((i + 1))
	done

	# Extract last 4 arguments using eval for arithmetic in indirect reference
	local external_peer_ip_idx=$((arg_count - 3))
	local location_name_idx=$((arg_count - 2))
	local deleted_count_var_idx=$((arg_count - 1))
	local failed_count_var_idx=$arg_count

	local external_peer_ip="${!external_peer_ip_idx}"
	local location_name="${!location_name_idx}"
	local deleted_count_var_name="${!deleted_count_var_idx}"
	local failed_count_var_name="${!failed_count_var_idx}"

	# Get full path to ip command for reliable execution in PATH-restricted environments (cron/systemd)
	# Use _RECOVERY_IP_PATH if available (set by recovery orchestration), otherwise resolve via get_command_path()
	local ip_cmd
	ip_cmd=$(get_ip_command_path)

	# Use namerefs for output variables (cleaner than eval)
	local -n deleted_count_ref="$deleted_count_var_name"
	local -n failed_count_ref="$failed_count_var_name"

	# IMPORTANT: Use different names for internal counters to avoid nameref shadowing
	# If we used "deleted_count" here, the nameref would point to this local variable
	# instead of the caller's variable (bash nameref shadowing bug)
	local _deleted_count=0
	local _failed_count=0

	# Format IP display once for reuse
	local ip_display
	ip_display=$(format_peer_ip_display "$external_peer_ip" "")

	# Enhanced diagnostics: Log summary of all SAs found before attempting deletion
	# This provides visibility into what we're about to delete and helps identify parsing issues
	# Includes direction information to diagnose asymmetric SA state (only one direction present)
	log_message "INFO" "$location_name" "xfrm recovery: Found ${#sa_list[@]} SA(s) to delete for $ip_display"
	if [[ ${#sa_list[@]} -gt 0 ]]; then
		local sa_summary=""
		local sa_idx=0
		local forward_count=0
		local reverse_count=0
		for sa_entry in "${sa_list[@]}"; do
			IFS='|' read -r sa_src sa_dst sa_proto sa_spi sa_mark <<<"$sa_entry"
			sa_idx=$((sa_idx + 1))
			# Determine direction for diagnostic clarity (helps identify asymmetric SA state)
			local direction="unknown"
			if [[ "$sa_src" == "$external_peer_ip" ]]; then
				direction="reverse (peer→local)"
				reverse_count=$((reverse_count + 1))
			elif [[ "$sa_dst" == "$external_peer_ip" ]]; then
				direction="forward (local→peer)"
				forward_count=$((forward_count + 1))
			fi
			if [[ -n "$sa_mark" ]]; then
				sa_summary="${sa_summary}SA${sa_idx}: src=$sa_src dst=$sa_dst [$direction] proto=$sa_proto spi=$sa_spi mark=$sa_mark; "
			else
				sa_summary="${sa_summary}SA${sa_idx}: src=$sa_src dst=$sa_dst [$direction] proto=$sa_proto spi=$sa_spi (no mark); "
			fi
		done
		log_message "INFO" "$location_name" "xfrm recovery: SA summary: ${sa_summary% }"
		# Log bidirectional state diagnostic (helps identify asymmetric SA state)
		if [[ $forward_count -eq 0 ]] || [[ $reverse_count -eq 0 ]]; then
			log_message "INFO" "$location_name" "xfrm recovery: SA bidirectional state diagnostic for $ip_display: forward=$forward_count, reverse=$reverse_count (expected: 1 each for bidirectional tunnel)"
		fi
	fi

	# Delete each parsed SA
	for sa_entry in "${sa_list[@]}"; do
		IFS='|' read -r sa_src sa_dst sa_proto sa_spi sa_mark <<<"$sa_entry"
		log_message "DEBUG" "$location_name" "xfrm recovery: Processing SA: src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi mark=${sa_mark:-<none>}"

		# Parse mark value and mask if present (format: "0x<value>/0x<mask>")
		# Mark format: ip xfrm expects "mark <value> mask <mask>"
		local mark_value=""
		local mark_mask=""
		if [[ -n "$sa_mark" ]]; then
			if [[ "$sa_mark" =~ ^(0x[0-9a-fA-F]+)/(0x[0-9a-fA-F]+)$ ]]; then
				mark_value="${BASH_REMATCH[1]}"
				mark_mask="${BASH_REMATCH[2]}"
				# Enhanced diagnostics: Log mark parsing details
				log_message "INFO" "$location_name" "xfrm recovery: Parsed mark for SA src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi: raw=$sa_mark, value=$mark_value, mask=$mark_mask"
			else
				# Fallback: if format doesn't match expected pattern, log warning
				handle_error "WARNING" "$location_name" "xfrm recovery: Invalid mark format: $sa_mark (expected format: 0x<value>/0x<mask>) for SA src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi"
			fi
		fi

		# Enhanced diagnostics: Query xfrm state right before deletion to check for race conditions
		# and to capture the exact format the kernel sees
		local pre_delete_xfrm_output
		local pre_delete_query_success=0
		if pre_delete_xfrm_output=$("$ip_cmd" xfrm state 2>/dev/null | grep -F "dst $sa_dst" -A 20 2>/dev/null); then
			pre_delete_query_success=1
			# Check if this specific SA (with all selectors) appears in the output
			# Include mark in check if present (mark is a required selector when present)
			local sa_match=1
			if [[ "$pre_delete_xfrm_output" == *"src $sa_src"* ]] &&
				[[ "$pre_delete_xfrm_output" == *"dst $sa_dst"* ]] &&
				[[ "$pre_delete_xfrm_output" == *"proto $sa_proto"* ]] &&
				[[ "$pre_delete_xfrm_output" == *"spi $sa_spi"* ]]; then
				# If mark is present, verify it matches too
				if [[ -n "$sa_mark" ]]; then
					# Mark format in output: "mark 0x<value>/0x<mask>"
					if [[ ! "$pre_delete_xfrm_output" == *"mark $sa_mark"* ]]; then
						sa_match=0
					fi
				fi
				if [[ $sa_match -eq 1 ]]; then
					# Extract the exact SA block for this specific SA to see what the kernel sees
					# This helps identify if there are additional attributes we're missing
					local exact_sa_block
					exact_sa_block=$(extract_sa_block "$pre_delete_xfrm_output" "$sa_src" "$sa_dst" 20)
					# Enhanced diagnostics: Always log full SA block (not just DEBUG mode)
					# This is critical for debugging deletion failures
					local mark_info=""
					[[ -n "$sa_mark" ]] && mark_info=" mark=$sa_mark"
					log_message "INFO" "$location_name" "xfrm recovery: Pre-delete SA block for src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi${mark_info}:\n$exact_sa_block"
					# Enhanced diagnostics: Extract and log all attributes found in SA block
					# This helps identify any selectors we might be missing (e.g., reqid, mode, etc.)
					local all_attrs=""
					if [[ "$exact_sa_block" =~ reqid[[:space:]]+([0-9]+) ]]; then
						all_attrs="${all_attrs}reqid=${BASH_REMATCH[1]}; "
					fi
					if [[ "$exact_sa_block" =~ mode[[:space:]]+([a-z]+) ]]; then
						all_attrs="${all_attrs}mode=${BASH_REMATCH[1]}; "
					fi
					if [[ "$exact_sa_block" =~ replay-window[[:space:]]+([0-9]+) ]]; then
						all_attrs="${all_attrs}replay-window=${BASH_REMATCH[1]}; "
					fi
					if [[ "$exact_sa_block" =~ flag[[:space:]]+([a-z-]+) ]]; then
						all_attrs="${all_attrs}flag=${BASH_REMATCH[1]}; "
					fi
					if [[ -n "$all_attrs" ]]; then
						log_message "INFO" "$location_name" "xfrm recovery: Additional SA attributes found: ${all_attrs% }"
					fi
				fi
			fi
		fi

		# Build deletion command with all selectors (including mark if present)
		# Mark is a required selector when present - must be included for successful deletion
		# Use full path to ip command for reliable execution in PATH-restricted environments
		local delete_cmd_args=("$ip_cmd" "xfrm" "state" "delete" "src" "$sa_src" "dst" "$sa_dst" "proto" "$sa_proto" "spi" "$sa_spi")
		if [[ -n "$mark_value" ]] && [[ -n "$mark_mask" ]]; then
			delete_cmd_args+=("mark" "$mark_value" "mask" "$mark_mask")
		fi

		# Try to query the exact SA using ip xfrm state get to see what the kernel expects
		# This helps identify if we need additional selectors
		# Note: We capture output with 2>&1 - on success (exit 0), output is stdout (SA details)
		# On failure (non-zero exit), output is stderr (error message)
		# Use full path to ip command for reliable execution in PATH-restricted environments
		local get_sa_cmd_args=("$ip_cmd" "xfrm" "state" "get" "src" "$sa_src" "dst" "$sa_dst" "proto" "$sa_proto" "spi" "$sa_spi")
		if [[ -n "$mark_value" ]] && [[ -n "$mark_mask" ]]; then
			get_sa_cmd_args+=("mark" "$mark_value" "mask" "$mark_mask")
		fi
		local get_sa_output=""
		local get_sa_stderr=""
		local get_sa_exit_code=0
		local get_sa_timer
		get_sa_timer=$(start_timer)
		# Use || to prevent set -e from triggering on command failure
		get_sa_output=$("${get_sa_cmd_args[@]}" 2>&1) || get_sa_exit_code=$?
		local get_sa_duration
		get_sa_duration=$(stop_timer "$get_sa_timer")
		# Separate stdout from stderr based on exit code
		if [[ $get_sa_exit_code -ne 0 ]]; then
			# On failure, the captured output is stderr
			get_sa_stderr="$get_sa_output"
			get_sa_output=""
		fi
		# Enhanced diagnostics: Always log the exact commands we're executing (not just DEBUG mode)
		# This is critical for debugging deletion failures
		log_message "INFO" "$location_name" "xfrm recovery: Executing delete command: ${delete_cmd_args[*]}"
		if [[ $get_sa_exit_code -eq 0 ]] && [[ -n "$get_sa_output" ]]; then
			log_message "INFO" "$location_name" "xfrm recovery: Kernel SA get succeeded (${get_sa_duration}s) for src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi mark=${sa_mark:-<none>}:\n$get_sa_output"
			# Enhanced diagnostics: Compare parsed selectors vs what kernel returns
			# Extract all attributes from kernel output to identify any we're missing
			local kernel_attrs=""
			if [[ "$get_sa_output" =~ mark[[:space:]]+(0x[0-9a-fA-F]+/0x[0-9a-fA-F]+) ]]; then
				kernel_attrs="${kernel_attrs}mark=${BASH_REMATCH[1]}; "
			fi
			if [[ -n "$kernel_attrs" ]]; then
				log_message "INFO" "$location_name" "xfrm recovery: Kernel SA attributes: ${kernel_attrs% }"
			fi
		elif [[ -n "$get_sa_stderr" ]]; then
			log_message "INFO" "$location_name" "xfrm recovery: Kernel SA get failed (exit_code=$get_sa_exit_code, ${get_sa_duration}s) for src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi mark=${sa_mark:-<none>}: $get_sa_stderr"
		fi

		# Capture stderr and exit code for diagnostic purposes
		# Enhanced diagnostics: Add timing information for deletion operations
		local delete_stderr=""
		local delete_exit_code=0
		local delete_timer
		delete_timer=$(start_timer)
		# Use || to prevent set -e from triggering on command failure
		delete_stderr=$("${delete_cmd_args[@]}" 2>&1) || delete_exit_code=$?
		local delete_duration
		delete_duration=$(stop_timer "$delete_timer")

		local mark_info=""
		[[ -n "$sa_mark" ]] && mark_info=" mark=$sa_mark"

		if [[ $delete_exit_code -eq 0 ]]; then
			# Enhanced diagnostics: Include timing information in success messages
			log_message "INFO" "$location_name" "xfrm recovery: Deleted SA: src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi${mark_info} for $ip_display (duration: ${delete_duration}s)"
			_deleted_count=$((_deleted_count + 1))
		else
			# Deletion failed - gather comprehensive diagnostic information
			# Enhanced diagnostics: Include timing information in failure diagnostics
			local diagnostic_info="exit_code=$delete_exit_code, duration=${delete_duration}s"

			# Add stderr output if present
			if [[ -n "$delete_stderr" ]]; then
				diagnostic_info="$diagnostic_info, stderr=\"$delete_stderr\""
			fi

			# Add mark information if present
			if [[ -n "$sa_mark" ]]; then
				diagnostic_info="$diagnostic_info, mark=$sa_mark"
			fi

			# Add information about pre-delete query
			if [[ $pre_delete_query_success -eq 1 ]]; then
				# Check if SA still exists (could indicate race condition or permissions issue)
				# Query xfrm state for this peer and check if the specific SA (src+dst+proto+spi) still exists
				# Use get_xfrm_state_for_peer to get full SA blocks, then check if all selectors appear together
				local peer_xfrm_output
				if peer_xfrm_output=$(get_xfrm_state_for_peer "$sa_dst" 2>/dev/null); then
					# Check if all selectors appear in the output (they may be on different lines)
					# This is a simple check - if all selectors are present, the SA likely still exists
					# Include mark in check if present (mark is a required selector when present)
					local sa_exists_check=1
					if [[ "$peer_xfrm_output" == *"src $sa_src"* ]] &&
						[[ "$peer_xfrm_output" == *"dst $sa_dst"* ]] &&
						[[ "$peer_xfrm_output" == *"proto $sa_proto"* ]] &&
						[[ "$peer_xfrm_output" == *"spi $sa_spi"* ]]; then
						# If mark is present, verify it matches too
						if [[ -n "$sa_mark" ]]; then
							# Mark format in output: "mark 0x<value>/0x<mask>"
							if [[ ! "$peer_xfrm_output" == *"mark $sa_mark"* ]]; then
								sa_exists_check=0
							fi
						fi
						if [[ $sa_exists_check -eq 1 ]]; then
							diagnostic_info="$diagnostic_info, sa_still_exists=true"
							# If SA exists but deletion failed, extract the exact SA block for detailed logging
							# This helps identify if there are additional attributes we're missing
							local sa_block_details
							sa_block_details=$(extract_sa_block "$peer_xfrm_output" "$sa_src" "$sa_dst" 15)
							# Log the exact SA block separately to avoid breaking log message formatting
							# Only log if we have block details (avoids empty logs)
							if [[ -n "$sa_block_details" ]]; then
								log_message "INFO" "$location_name" "xfrm recovery: SA block that exists but couldn't be deleted for src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi${mark_info}:\n$sa_block_details"
							fi
						else
							diagnostic_info="$diagnostic_info, sa_still_exists=false"
						fi
					else
						diagnostic_info="$diagnostic_info, sa_still_exists=false"
					fi
				else
					# Failed to query xfrm state - can't determine if SA exists
					diagnostic_info="$diagnostic_info, sa_still_exists=unknown"
				fi
			else
				diagnostic_info="$diagnostic_info, pre_delete_query_failed=true"
			fi

			# Add information about get command attempt
			if [[ $get_sa_exit_code -eq 0 ]] && [[ -n "$get_sa_output" ]]; then
				diagnostic_info="$diagnostic_info, get_sa_succeeded=true"
			elif [[ -n "$get_sa_stderr" ]]; then
				diagnostic_info="$diagnostic_info, get_sa_failed=\"$get_sa_stderr\""
			fi

			# Log comprehensive diagnostic information
			handle_error "WARNING" "$location_name" "xfrm recovery: Failed to delete SA: src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi${mark_info} for $ip_display ($diagnostic_info)"

			# Log the raw xfrm output we parsed (helps identify parsing issues vs kernel state)
			# Only log once per recovery attempt to avoid excessive logging
			# Note: We don't have access to xfrm_output here, so we skip this logging
			# It will be logged by the caller if needed
			_failed_count=$((_failed_count + 1))
		fi
	done

	# Enhanced diagnostics: Log summary of deletion results
	if [[ $_deleted_count -gt 0 ]] || [[ $_failed_count -gt 0 ]]; then
		log_message "INFO" "$location_name" "xfrm recovery: Deletion summary for $ip_display: ${_deleted_count} succeeded, ${_failed_count} failed out of ${#sa_list[@]} total SA(s)"
	fi

	# Set output variables via nameref (sets variables in caller's scope)
	deleted_count_ref=$_deleted_count
	failed_count_ref=$_failed_count

	# Return success if at least one SA was deleted, or if no SAs were in the list
	if [[ $_deleted_count -gt 0 ]]; then
		return 0
	elif [[ ${#sa_list[@]} -eq 0 ]]; then
		return 0
	else
		# All deletions failed
		return 1
	fi
}

# Delete xfrm policies for a specific peer
#
# Deletes xfrm policies for the specified peer IP in all directions (in, out, fwd).
# Policy deletion failures are non-fatal and don't affect recovery success.
#
# Arguments:
#   $1: Peer IP address
#   $2: Location name (required for logging context)
#
# Returns:
#   0: Always succeeds (policy deletion failures are non-fatal)
#
# Side effects:
#   - Deletes xfrm policies for the peer IP
#   - Logs all actions and results
#
# Note:
#   Policies are automatically recreated by strongSwan when SAs re-establish
delete_xfrm_policies() {
	local external_peer_ip="$1"
	local location_name="$2"

	# Get full path to ip command for reliable execution in PATH-restricted environments (cron/systemd)
	# Use _RECOVERY_IP_PATH if available (set by recovery orchestration), otherwise resolve via get_command_path()
	local ip_cmd
	ip_cmd=$(get_ip_command_path)

	# Also delete policies for this peer (less critical, but helps cleanup)
	# Policies require DIR (direction) parameter for deletion: in, out, or fwd
	# Query existing policies first to determine which directions exist, then delete each
	# Enhanced diagnostics: Add timing and more detailed policy deletion diagnostics
	#
	# Safety: Policy deletion is scoped to ONLY the failing peer IP:
	#   - Uses fixed-string matching (grep -F) to prevent regex injection
	#   - Matches exact "dst $external_peer_ip" pattern (space after "dst " provides natural boundary)
	#   - Only deletes policies for the specific peer IP that triggered recovery
	#   - Policies are automatically recreated by strongSwan when SAs re-establish
	#   - Policy deletion failures are non-fatal and don't affect recovery success
	#
	# When policies are deleted:
	#   - Only during xfrm recovery for a specific failing peer IP
	#   - Only after SAs for that peer IP have been deleted
	#   - Only policies matching dst=$external_peer_ip (exact match, not partial)
	#   - Policies for other peer IPs are never touched
	#
	# Note: external_peer_ip is the external IP of remote locations (from LOCATION_*_EXTERNAL config)
	local existing_policies
	existing_policies=$("$ip_cmd" xfrm policy 2>/dev/null | grep -F "dst $external_peer_ip" -A 5 2>/dev/null || echo "")

	local policy_deleted_count=0
	local policy_failed_count=0
	local policy_directions=()

	# Parse directions from existing policies
	# Policy format: "src <ip> dst <ip> dir <direction> ..."
	# Directions can be: in, out, fwd
	if [[ -n "$existing_policies" ]]; then
		while IFS= read -r policy_line || [[ -n "$policy_line" ]]; do
			# Extract direction from policy line (format: "dir <direction>")
			if [[ "$policy_line" =~ dir[[:space:]]+([a-z]+) ]]; then
				local dir="${BASH_REMATCH[1]}"
				# Validate direction is one of the expected values
				if [[ "$dir" == "in" ]] || [[ "$dir" == "out" ]] || [[ "$dir" == "fwd" ]]; then
					# Add to array if not already present (avoid duplicates)
					local dir_exists=0
					for existing_dir in "${policy_directions[@]}"; do
						if [[ "$existing_dir" == "$dir" ]]; then
							dir_exists=1
							break
						fi
					done
					if [[ $dir_exists -eq 0 ]]; then
						policy_directions+=("$dir")
					fi
				fi
			fi
		done <<<"$existing_policies"
	fi

	# If no directions found in existing policies, try deleting for all common directions
	# This handles cases where policy format may differ or policies exist but weren't parsed
	if [[ ${#policy_directions[@]} -eq 0 ]]; then
		# Try common directions: fwd (most common for VPN tunnels), out, in
		policy_directions=("fwd" "out" "in")
		log_message "INFO" "$location_name" "xfrm recovery: No policy directions parsed for dst=$external_peer_ip, attempting deletion for common directions (fwd, out, in)"
	else
		log_message "INFO" "$location_name" "xfrm recovery: Found policy directions for dst=$external_peer_ip: ${policy_directions[*]}"
	fi

	# Delete policies for each direction found
	for policy_dir in "${policy_directions[@]}"; do
		local policy_stderr=""
		local policy_exit_code=0
		local policy_timer
		policy_timer=$(start_timer)
		# Use full path to ip command for reliable execution in PATH-restricted environments
		local policy_cmd_args=("$ip_cmd" "xfrm" "policy" "delete" "dst" "$external_peer_ip" "dir" "$policy_dir")
		log_message "INFO" "$location_name" "xfrm recovery: Executing policy deletion command: ${policy_cmd_args[*]}"
		# Use || to prevent set -e from triggering on command failure
		policy_stderr=$("${policy_cmd_args[@]}" 2>&1) || policy_exit_code=$?
		local policy_duration
		policy_duration=$(stop_timer "$policy_timer")

		if [[ $policy_exit_code -eq 0 ]]; then
			policy_deleted_count=$((policy_deleted_count + 1))
			# Note: delete_xfrm_policies doesn't have access to internal_peer_ip, so we only show external IP
			log_message "INFO" "$location_name" "xfrm recovery: Deleted xfrm policy for dst=$external_peer_ip dir=$policy_dir (duration: ${policy_duration}s)"
		else
			# Policy deletion failed - log diagnostic info (non-fatal, so use INFO level)
			# Enhanced diagnostics: Always log policy deletion failures (not just DEBUG mode)
			policy_failed_count=$((policy_failed_count + 1))
			local policy_diagnostic="exit_code=$policy_exit_code, duration=${policy_duration}s"
			if [[ -n "$policy_stderr" ]]; then
				policy_diagnostic="$policy_diagnostic, stderr=\"$policy_stderr\""
			fi
			# Note: delete_xfrm_policies doesn't have access to internal_peer_ip, so we only show external IP
			log_message "INFO" "$location_name" "xfrm recovery: Failed to delete xfrm policy for dst=$external_peer_ip dir=$policy_dir ($policy_diagnostic) - non-fatal, continuing"
		fi
	done

	# Log summary of policy deletion results
	if [[ $policy_deleted_count -gt 0 ]] || [[ $policy_failed_count -gt 0 ]]; then
		if [[ $policy_deleted_count -gt 0 ]] && [[ $policy_failed_count -eq 0 ]]; then
			# Note: delete_xfrm_policies doesn't have access to internal_peer_ip, so we only show external IP
			log_message "INFO" "$location_name" "xfrm recovery: Policy deletion summary for dst=$external_peer_ip: ${policy_deleted_count} succeeded, 0 failed"
		elif [[ $policy_deleted_count -eq 0 ]] && [[ $policy_failed_count -gt 0 ]]; then
			# Note: delete_xfrm_policies doesn't have access to internal_peer_ip, so we only show external IP
			log_message "INFO" "$location_name" "xfrm recovery: Policy deletion summary for dst=$external_peer_ip: 0 succeeded, ${policy_failed_count} failed (non-fatal)"
		else
			# Note: delete_xfrm_policies doesn't have access to internal_peer_ip, so we only show external IP
			log_message "INFO" "$location_name" "xfrm recovery: Policy deletion summary for dst=$external_peer_ip: ${policy_deleted_count} succeeded, ${policy_failed_count} failed (non-fatal)"
		fi
	fi

	# Enhanced diagnostics: Log existing policies if deletion failed for all directions
	if [[ $policy_deleted_count -eq 0 ]] && [[ -n "$existing_policies" ]]; then
		log_message "INFO" "$location_name" "xfrm recovery: Existing policies for dst=$external_peer_ip:\n$existing_policies"
	fi

	return 0
}

# Delete stale Security Associations for a specific peer using xfrm
#
# Parses xfrm output to extract SAs, deletes each SA, and also deletes associated policies.
# This function encapsulates the SA deletion logic extracted from attempt_xfrm_recovery().
#
# Arguments:
#   $1: Peer IP address
#   $2: Location name (required for logging context)
#   $3: xfrm output to parse (from get_xfrm_state_for_peer)
#   $4: Variable name to set with deleted_count (output parameter)
#   $5: Variable name to set with failed_count (output parameter)
#
# Returns:
#   0: Success (at least one SA deleted or no SAs found)
#   1: Failure (parsing failed or all deletions failed)
#
# Side effects:
#   - Sets variables specified in $4 and $5 with deletion counts
#   - Deletes xfrm state entries (SAs) for the peer IP
#   - Deletes xfrm policies for the peer IP
#   - Logs all actions and results
delete_stale_sas() {
	local external_peer_ip="$1"
	local location_name="$2"
	local xfrm_output="$3"
	local deleted_count_var="$4"
	local failed_count_var="$5"

	# Format IP display once for reuse
	local ip_display
	ip_display=$(format_peer_ip_display "$external_peer_ip" "")

	# Parse xfrm output into SA list
	local sa_list=()
	if ! parse_xfrm_output_to_sa_list "$xfrm_output" "$external_peer_ip" "$location_name" "sa_list"; then
		eval "$deleted_count_var=0"
		eval "$failed_count_var=0"
		return 1
	fi

	# Delete SAs
	# Initialize counters - delete_sas_from_list will update them via nameref
	local deleted_count=0
	local failed_count=0
	delete_sas_from_list "${sa_list[@]}" "$external_peer_ip" "$location_name" deleted_count failed_count
	local delete_result=$?

	if [[ $delete_result -ne 0 ]]; then
		# If deletion failed completely, check if we had any SAs to delete
		if [[ ${#sa_list[@]} -eq 0 ]]; then
			log_message "INFO" "$location_name" "xfrm recovery: No SAs found to delete for $ip_display"
			eval "$deleted_count_var=0"
			eval "$failed_count_var=0"
			return 0
		else
			handle_error "WARNING" "$location_name" "xfrm recovery: Parsed ${#sa_list[@]} SA(s) but failed to delete any for $ip_display"
			eval "$deleted_count_var=$deleted_count"
			eval "$failed_count_var=$failed_count"
			return 1
		fi
	fi

	# Delete policies
	delete_xfrm_policies "$external_peer_ip" "$location_name"

	# Set output variables
	eval "$deleted_count_var=$deleted_count"
	eval "$failed_count_var=$failed_count"

	# If no SAs were deleted, check if any existed
	if [[ $deleted_count -eq 0 ]] && [[ $failed_count -eq 0 ]]; then
		if [[ ${#sa_list[@]} -eq 0 ]]; then
			log_message "INFO" "$location_name" "xfrm recovery: No SAs found to delete for $ip_display"
			return 0
		else
			handle_error "WARNING" "$location_name" "xfrm recovery: Parsed ${#sa_list[@]} SA(s) but failed to delete any for $ip_display"
			return 1
		fi
	fi

	return 0
}

# Retry xfrm recovery with exponential backoff
#
# Waits for SA re-establishment after deletion using exponential backoff polling.
# Verifies SA existence, SA count, and byte counter increment.
# Captures initial byte counter when SA is first re-established.
#
# Arguments:
#   $1: Peer IP address
#   $2: Location name (required for logging context)
#   $3: Number of SAs deleted (for logging/diagnostics)
#
# Returns:
#   0: Success (SA re-established and byte counters verified)
#   1: Failure (timeout or verification failed)
#
# Side effects:
#   - Polls for SA re-establishment with exponential backoff
#   - Captures initial byte counter when SA is first re-established
#   - Verifies byte counter increment
#   - Logs verification progress and results
retry_xfrm_recovery() {
	local external_peer_ip="$1"
	local location_name="$2"
	local deleted_count="$3"
	local initial_byte_counter=""
	local initial_byte_counter_set=0
	local ping_skip_logged=0

	# Format IP display once for reuse
	local ip_display
	ip_display=$(format_peer_ip_display "$external_peer_ip" "")

	# Verification Phase: Wait for SA re-establishment with exponential backoff
	# After deletion, strongSwan needs time to detect SA removal and re-establish new SAs
	# We poll periodically using exponential backoff to balance responsiveness and efficiency
	#
	# Backoff algorithm:
	#   - Start with base_interval (default: 2 seconds)
	#   - Double interval each attempt: 2s → 4s → 8s → 16s
	#   - Cap at max_interval (default: 16 seconds) to prevent excessive delays
	#   - Continue until timeout reached or SA re-established
	#
	# Rationale: Early checks are frequent (quick detection), later checks are spaced out
	# (reduces CPU usage for slow re-establishments)
	local verify_timeout="${RECOVERY_VERIFY_TIMEOUT:-${XFRM_RECOVERY_VERIFY_TIMEOUT:-30}}"
	local base_interval="${XFRM_RECOVERY_VERIFY_INTERVAL:-2}"
	local max_interval="${XFRM_RECOVERY_MAX_INTERVAL:-16}"
	local current_interval=$base_interval

	# Calculate maximum iterations as a safety mechanism in case time calculation fails
	# Worst case: all iterations use max_interval, add 50% buffer for safety
	# This provides defense-in-depth if calculate_duration fails or returns incorrect values
	local max_iterations=$(((verify_timeout / max_interval) + (verify_timeout / max_interval / 2) + 5))
	# Ensure minimum iterations (at least 10 for very short timeouts)
	[[ $max_iterations -lt 10 ]] && max_iterations=10
	# Cap at reasonable maximum (prevent excessive iterations)
	[[ $max_iterations -gt 200 ]] && max_iterations=200

	log_message "INFO" "$location_name" "xfrm recovery: Waiting for SA re-establishment for $ip_display (timeout: ${verify_timeout}s)"
	local verify_start_time
	verify_start_time=$(start_timer)
	local sa_reestablished=0
	local verify_attempt=0
	local iteration=0
	local elapsed_time
	local sa_count=0
	local initial_sa_count=0
	local initial_sa_count_set=0
	local sa_count_checks_after_reestablish=0
	local max_sa_count_checks=3
	local byte_counter_status="unknown"

	# Verification loop: Poll until SA re-established or timeout
	# Timeout check: Compare elapsed time against configured timeout
	# Iteration check: Secondary safety mechanism if time calculation fails
	while true; do
		# Increment iteration counter (safety mechanism)
		iteration=$((iteration + 1))
		if [[ $iteration -gt $max_iterations ]]; then
			handle_error "ERROR" "$location_name" "xfrm recovery: Maximum iterations reached ($max_iterations) for $ip_display - time calculation may have failed (elapsed_time=${elapsed_time:-unknown}, verify_timeout=${verify_timeout}s)"
			break
		fi

		# Calculate elapsed time at start of each iteration
		elapsed_time=$(stop_timer "$verify_start_time")

		# Check timeout condition
		if [[ $elapsed_time -ge $verify_timeout ]]; then
			break
		fi

		verify_attempt=$((verify_attempt + 1))

		# Check if SA is re-established using detection function
		# This checks both xfrm state and ipsec status for comprehensive verification
		if command -v check_ipsec_phase2 >/dev/null 2>&1; then
			if check_ipsec_phase2 "$external_peer_ip"; then
				# SA re-established - perform additional verification checks
				sa_reestablished=1

				# Count SAs for logging (may have multiple SAs for one peer)
				# This provides visibility into how many SAs were re-established
				# Pass location_name for enhanced diagnostic logging
				if sa_count=$(count_sas_for_peer "$external_peer_ip" "$location_name" 2>/dev/null); then
					# Track initial SA count when first re-established (helps detect timing issues)
					if [[ $initial_sa_count_set -eq 0 ]]; then
						initial_sa_count=$sa_count
						initial_sa_count_set=1
						log_message "INFO" "$location_name" "xfrm recovery: SA re-established for $ip_display after ${elapsed_time}s (attempt $verify_attempt, SA count: $sa_count, deleted: $deleted_count)"
						# Check if SA count mismatch (deleted more than re-established)
						if [[ $deleted_count -gt 0 ]] && [[ $sa_count -lt $deleted_count ]]; then
							log_message "INFO" "$location_name" "xfrm recovery: SA count mismatch detected for $ip_display: deleted=$deleted_count, re-established=$sa_count (will continue checking for additional SAs)"
						fi
					else
						# SA already re-established - check if count has increased (second SA appeared)
						if [[ $sa_count -gt $initial_sa_count ]]; then
							log_message "INFO" "$location_name" "xfrm recovery: SA count increased for $ip_display: initial=$initial_sa_count, current=$sa_count (second SA appeared after ${elapsed_time}s)"
							initial_sa_count=$sa_count
						elif [[ $sa_count_checks_after_reestablish -lt $max_sa_count_checks ]]; then
							# Continue checking SA count for a few more iterations to catch second SA
							sa_count_checks_after_reestablish=$((sa_count_checks_after_reestablish + 1))
							log_message "DEBUG" "$location_name" "xfrm recovery: Checking SA count again for $ip_display (check $sa_count_checks_after_reestablish/$max_sa_count_checks, current=$sa_count, deleted=$deleted_count)"
						fi
					fi
				else
					if [[ $initial_sa_count_set -eq 0 ]]; then
						log_message "INFO" "$location_name" "xfrm recovery: SA re-established for $ip_display after ${elapsed_time}s (attempt $verify_attempt, SA count unavailable)"
					fi
				fi

				# Capture initial byte counter value when SA is first re-established
				# Byte counters may reset to zero after SA deletion/re-establishment, so we
				# need to track the baseline and check for increment rather than absolute value
				if [[ $initial_byte_counter_set -eq 0 ]]; then
					local xfrm_output
					xfrm_output=$(get_xfrm_state_for_peer "$external_peer_ip" 2>/dev/null)
					if [[ -n "$xfrm_output" ]] && command -v extract_byte_counter >/dev/null 2>&1; then
						if initial_byte_counter=$(extract_byte_counter "$xfrm_output" 2>/dev/null); then
							# Validate initial_byte_counter is numeric (default to 0 if not)
							if [[ ! "$initial_byte_counter" =~ ^[0-9]+$ ]]; then
								initial_byte_counter=0
							fi
							initial_byte_counter_set=1
							log_message "INFO" "$location_name" "xfrm recovery: Captured initial byte counter for $ip_display (initial=$initial_byte_counter)"
						else
							# Byte counters not available - set to 0 and mark as set
							initial_byte_counter=0
							initial_byte_counter_set=1
							log_message "INFO" "$location_name" "xfrm recovery: Byte counters not available for $ip_display (using initial=0)"
						fi
					else
						# Failed to get xfrm output - set to 0 and mark as set
						initial_byte_counter=0
						initial_byte_counter_set=1
						log_message "INFO" "$location_name" "xfrm recovery: Failed to get initial byte counter for $ip_display (using initial=0)"
					fi

					# Enhancement: If counters are zero, ping internal IP to generate traffic, then check again
					# This actively verifies the tunnel can pass traffic rather than waiting passively
					if [[ "$initial_byte_counter" -eq 0 ]]; then
						if [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
							# Get internal IPs for this location to ping (resolved from DNS if needed)
							local internal_ips=""
							# parse_location_config and get_location_internal_ips_resolved are in the same module,
							# so checking for parse_location_config is sufficient
							if command -v parse_location_config >/dev/null 2>&1; then
								# Ensure location config is parsed (may not be if called directly)
								if ! declare -p LOCATIONS &>/dev/null 2>&1; then
									parse_location_config 2>/dev/null || true
								fi
								# Use resolved version to handle DNS names
								internal_ips=$(get_location_internal_ips_resolved "$location_name" 2>/dev/null || echo "")
							fi

							# If we have internal IPs, ping the first one to generate traffic
							if [[ -n "$internal_ips" ]]; then
								local first_internal_ip
								first_internal_ip=$(echo "$internal_ips" | awk '{print $1}')
								if [[ -n "$first_internal_ip" ]] && command -v check_ping_connectivity >/dev/null 2>&1; then
									local local_ip
									local_ip=$(get_local_ip_for_ping 2>/dev/null || echo "")
									local ip_display_with_internal
									ip_display_with_internal=$(format_peer_ip_display "$external_peer_ip" "$first_internal_ip")
									log_message "INFO" "$location_name" "xfrm recovery: Byte counters are zero, pinging internal IP $first_internal_ip to generate traffic for $ip_display_with_internal"
									# Ping to generate traffic (ignore ping result - we only care about byte counter increment)
									check_ping_connectivity "$first_internal_ip" "$local_ip" "$location_name" >/dev/null 2>&1 || true
									# Small delay to allow counters to update
									sleep 1
								else
									# Ping function not available - log at debug level (non-critical)
									log_message "DEBUG" "$location_name" "xfrm recovery: Ping function not available, skipping ping-based traffic generation for $ip_display"
								fi
							else
								# No internal IPs configured - log at info level (helpful for debugging, only once)
								if [[ $ping_skip_logged -eq 0 ]]; then
									log_message "INFO" "$location_name" "xfrm recovery: Byte counters are zero but no internal IPs configured for $ip_display, waiting for natural traffic flow"
									ping_skip_logged=1
								fi
							fi
						else
							# Ping check disabled - log at info level (helpful for debugging, only once)
							if [[ $ping_skip_logged -eq 0 ]]; then
								log_message "INFO" "$location_name" "xfrm recovery: Byte counters are zero but ping check is disabled (ENABLE_PING_CHECK=0) for $ip_display, waiting for natural traffic flow"
								ping_skip_logged=1
							fi
						fi
					fi
				fi

				# Verify byte counters increment from initial value (indicates tunnel is passing traffic)
				# This handles the case where byte counters reset to zero after SA deletion/re-establishment
				# We check for increment rather than absolute non-zero value to verify traffic is flowing
				if verify_byte_counters_increment "$external_peer_ip" "$initial_byte_counter" "$location_name" 2>/dev/null; then
					byte_counter_status="resumed"
					log_message "INFO" "$location_name" "xfrm recovery: Verification complete for $ip_display (duration: ${elapsed_time}s, SA count: ${sa_count}, byte counters: ${byte_counter_status})"
					break # Exit verification loop on success (SA re-established AND byte counters verified)
				else
					byte_counter_status="zero_or_unavailable"
					# Log warning but continue waiting - byte counters may resume shortly
					# Only break if timeout occurs (handled by timeout check at start of loop)
					handle_error "WARNING" "$location_name" "xfrm recovery: SA re-established but byte counters not verified for $ip_display (will continue waiting)"
				fi
			fi
		fi

		log_message "DEBUG" "$location_name" "xfrm recovery: Verification attempt $verify_attempt for $ip_display (elapsed: ${elapsed_time}s/${verify_timeout}s, next interval: ${current_interval}s)"

		# Exponential backoff: Sleep before next check
		# Interval doubles each attempt, capped at max_interval
		# This reduces CPU usage for slow re-establishments while maintaining responsiveness
		sleep "$current_interval"
		current_interval=$((current_interval * 2))
		if [[ $current_interval -gt $max_interval ]]; then
			current_interval=$max_interval # Cap at maximum to prevent excessive delays
		fi
	done

	# Final SA count check: Log warning if we deleted multiple SAs but only one re-established
	# This helps diagnose asymmetric SA state or timing issues where second SA takes longer
	if [[ $sa_reestablished -eq 1 ]] && [[ $deleted_count -gt 1 ]] && [[ $initial_sa_count_set -eq 1 ]]; then
		# Get final SA count for comparison
		local final_sa_count
		if final_sa_count=$(count_sas_for_peer "$external_peer_ip" "$location_name" 2>/dev/null); then
			if [[ $final_sa_count -lt $deleted_count ]]; then
				log_message "INFO" "$location_name" "xfrm recovery: SA count mismatch persists for $ip_display: deleted=$deleted_count, final_count=$final_sa_count (may indicate asymmetric SA state or incomplete re-establishment)"
			fi
		fi
	fi

	if [[ $sa_reestablished -eq 0 ]]; then
		elapsed_time=$(stop_timer "$verify_start_time")
		handle_error "WARNING" "$location_name" "xfrm recovery: SA did not re-establish within ${verify_timeout}s for $ip_display (verification duration: ${elapsed_time}s, attempts: $verify_attempt, iterations: $iteration)"
		handle_error "WARNING" "$location_name" "xfrm recovery: Partial success - deleted SAs but re-establishment timeout for $ip_display, will fall back to alternative recovery"
		# Clear recovery method since verification failed (prevents stale recovery method from being logged if VPN recovers naturally later)
		if command -v clear_recovery_method >/dev/null 2>&1; then
			clear_recovery_method "$location_name" "$external_peer_ip"
		fi
		return 1
	fi

	# SA was re-established - check if byte counters were verified
	if [[ "$byte_counter_status" != "resumed" ]]; then
		elapsed_time=$(stop_timer "$verify_start_time")
		handle_error "WARNING" "$location_name" "xfrm recovery: SA re-established but byte counter verification failed within ${verify_timeout}s for $ip_display (verification duration: ${elapsed_time}s, attempts: $verify_attempt, iterations: $iteration)"
		# Byte counter verification failed - clear recovery method and return error to trigger fallback recovery
		# This prevents stale recovery method from being logged if VPN recovers naturally later
		if command -v clear_recovery_method >/dev/null 2>&1; then
			clear_recovery_method "$location_name" "$external_peer_ip"
		fi
		return 1
	fi

	return 0
}

# Attempt xfrm-based recovery for a specific peer
#
# Attempts per-connection recovery by deleting Security Associations (SAs) for a specific peer IP
# using the Linux kernel's xfrm framework. This provides surgical recovery for per-connection recovery.
#
# After deleting SAs, verifies that new SAs are re-established and byte counters resume before
# reporting success. This ensures recovery actually worked and the tunnel is functional.
#
# Arguments:
#   $1: Peer IP address to recover
#   $2: Location name (required for logging context)
#
# Returns:
#   0: Recovery succeeded (SAs deleted and re-established, byte counters verified)
#   1: Recovery failed (no SAs found, deletion failed, or re-establishment timeout)
#
# Side effects:
#   - Deletes xfrm state entries (SAs) for the peer IP
#   - Deletes xfrm policies for the peer IP
#   - Verifies SA re-establishment after deletion
#   - Logs all actions and results
#
# Note:
#   Requires 'ip' command to be available
#   Uses fixed-string matching to prevent regex pattern injection
#   Falls back to alternative recovery methods if xfrm recovery fails
attempt_xfrm_recovery() {
	local external_peer_ip="$1"
	local location_name="$2"
	local deleted_count=0
	local failed_count=0

	if ! check_command_or_warn "ip" "xfrm recovery"; then
		return 1
	fi

	# Validate peer IP before proceeding
	if [[ -z "$external_peer_ip" ]]; then
		handle_error "ERROR" "$location_name" "xfrm recovery: External peer IP not provided" 0
		return 1
	fi

	# Format IP display once for reuse
	local ip_display
	ip_display=$(format_peer_ip_display "$external_peer_ip" "")

	# Enhanced diagnostics: Log system/kernel information that may affect xfrm operations
	# This helps identify version-specific issues or permission problems
	local kernel_version=""
	local ip_version=""
	if kernel_version=$(uname -r 2>/dev/null); then
		log_message "INFO" "$location_name" "xfrm recovery: Starting recovery for $ip_display - kernel: $kernel_version"
	fi
	# Get full path to ip command for reliable execution in PATH-restricted environments (cron/systemd)
	# Use _RECOVERY_IP_PATH if available (set by recovery orchestration), otherwise resolve via get_command_path()
	local ip_cmd
	ip_cmd=$(get_ip_command_path)
	if ip_version=$("$ip_cmd" -Version 2>&1 | head -1); then
		log_message "INFO" "$location_name" "xfrm recovery: ip command version: $ip_version"
	fi

	# Get all xfrm state entries for this peer IP
	# Match on "dst $external_peer_ip" pattern which appears at the start of each SA entry
	# This ensures we capture complete SA blocks for proper deletion
	# Use fixed-string matching to prevent regex pattern injection
	# Word boundary protection: The "dst " prefix and space after IP provide natural boundaries
	# (e.g., "dst 192.168.1.1" won't match "dst 192.168.1.10" due to exact string matching)
	local xfrm_output
	local xfrm_result
	local xfrm_error_msg=""
	xfrm_output=$(get_xfrm_state_for_peer "$external_peer_ip" "" "xfrm_error_msg")
	xfrm_result=$?

	# Check if helper function failed - distinguish between different failure types
	if [[ $xfrm_result -eq 2 ]]; then
		# Command failed (xfrm query error)
		if [[ -n "$xfrm_error_msg" ]]; then
			handle_error "WARNING" "$location_name" "xfrm recovery: $xfrm_error_msg"
		else
			handle_error "WARNING" "$location_name" "xfrm recovery: xfrm command failed (command error) for $ip_display"
		fi
		return 1
	elif [[ $xfrm_result -ne 0 ]]; then
		# No SAs found (tunnel down or SAs not in xfrm state)
		if [[ -n "$xfrm_error_msg" ]]; then
			handle_error "WARNING" "$location_name" "xfrm recovery: $xfrm_error_msg"
		else
			handle_error "WARNING" "$location_name" "xfrm recovery: No SAs found in xfrm state for $ip_display - tunnel may be down"
		fi
		return 1
	fi

	# Note: get_xfrm_state_for_peer() now handles empty output and provides detailed error messages
	# including alternative query methods (ipsec status). If we get here with empty output,
	# it means the function succeeded but returned empty (shouldn't happen with new implementation,
	# but kept for safety). The error message above should have already been logged.
	if [[ -z "$xfrm_output" ]]; then
		# This case should be rare now since get_xfrm_state_for_peer() handles empty output
		# But kept as a safety check
		log_message "INFO" "$location_name" "xfrm recovery: No SAs found for $ip_display in xfrm state (tunnel appears to be down)"
		# No SAs exist - xfrm recovery cannot accomplish the recovery goal (bringing the VPN back up)
		# since there's nothing to delete/re-establish. Return failure to trigger fallback to ipsec reload/restart.
		return 1
	fi

	# Delete stale SAs using extracted function
	local deleted_count_var="__deleted_count"
	local failed_count_var="__failed_count"
	if ! delete_stale_sas "$external_peer_ip" "$location_name" "$xfrm_output" "$deleted_count_var" "$failed_count_var"; then
		# Parsing failed or all deletions failed
		return 1
	fi
	# Read the counts set by delete_stale_sas
	eval "deleted_count=\$$deleted_count_var"
	eval "failed_count=\$$failed_count_var"

	# Old parsing and deletion code removed - now handled by delete_stale_sas()
	# All parsing, SA deletion, and policy deletion is now in delete_stale_sas()

	# Check if deletion was successful
	if [[ $deleted_count -eq 0 ]] && [[ $failed_count -eq 0 ]]; then
		log_message "INFO" "$location_name" "xfrm recovery: No SAs found to delete for $ip_display"
		return 0
	fi

	# If we deleted SAs, verify they're gone and wait for re-establishment
	if [[ $deleted_count -gt 0 ]]; then
		log_message "INFO" "$location_name" "xfrm recovery: Deleted $deleted_count SA(s) for $ip_display"
		# Wait a moment for strongSwan to detect SA deletion
		sleep "$XFRM_RECOVERY_SLEEP_SECONDS"

		# Verify SAs were deleted
		if command -v check_ipsec_phase2 >/dev/null 2>&1; then
			if check_ipsec_phase2 "$external_peer_ip"; then
				handle_error "WARNING" "$location_name" "xfrm recovery: SAs still exist after deletion attempt for $ip_display"
				# Continue anyway - may have deleted some but not all
			fi
		fi

		# Retry recovery with exponential backoff
		# Note: Byte counter capture happens inside retry_xfrm_recovery when SA is first re-established
		if ! retry_xfrm_recovery "$external_peer_ip" "$location_name" "$deleted_count"; then
			return 1
		fi

		return 0
	elif [[ $failed_count -gt 0 ]]; then
		handle_error "WARNING" "$location_name" "xfrm recovery: Failed to delete $failed_count SA(s) for $ip_display"
		return 1
	fi

	# Should not reach here, but handle gracefully
	return 1
}
