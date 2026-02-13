#!/usr/bin/env bash
#
# Standardized Mock Creation Patterns
#
# This module provides standardized patterns for creating mock commands in tests.
# It consolidates common mock creation patterns to reduce duplication and ensure
# consistency across test files.
#
# Usage:
#   load test_helper
#   load helpers/mocks
#
#   # Create a mock command that fails
#   mock_command_failure "mycommand" 1 "Error message"
#   add_mock_to_path
#
#   # Create a mock command with custom behavior
#   create_mock_command "mycommand" <<'EOF'
#   #!/bin/bash
#   echo "custom output"
#   exit 0
#   EOF
#   add_mock_to_path

# Create mock command that fails with specific exit code and error message
#
# Creates a mock command script that exits with the specified exit code and
# optionally prints an error message to stderr. This is useful for testing
# error handling scenarios.
#
# Arguments:
#   $1: Command name to mock
#   $2: Exit code (default: 1)
#   $3: Error message to print to stderr (optional)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints path to created mock command
#
# Side effects:
#   - Creates executable mock command script in TEST_DIR
#
# Example:
#   # Create a mock that fails with exit code 1
#   mock_command_failure "mycommand"
#   add_mock_to_path
#
#   # Create a mock that fails with exit code 2 and error message
#   mock_command_failure "mycommand" 2 "Connection refused"
#   add_mock_to_path
mock_command_failure() {
	local command_name="$1"
	local exit_code="${2:-1}"
	local error_message="${3:-}"
	local mock_command="${TEST_DIR}/${command_name}"
	cat >"$mock_command" <<EOF
#!/bin/bash
${error_message:+echo "$error_message" >&2}
exit $exit_code
EOF
	chmod +x "$mock_command"
	echo "$mock_command"
}

# Create a mock command with custom script content
#
# Creates a mock command script with the provided content. This provides a
# flexible way to create mocks with complex behavior.
#
# Arguments:
#   $1: Command name to mock
#   $2: Script content (can be provided via heredoc or as a string)
#   $3: Optional path to mock file (default: ${TEST_DIR}/${command_name})
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints path to created mock command
#
# Side effects:
#   - Creates executable mock command script
#
# Example:
#   # Using heredoc
#   create_mock_command "mycommand" <<'EOF'
#   #!/bin/bash
#   if [[ "$1" == "test" ]]; then
#       echo "test mode"
#   else
#       echo "normal mode"
#   fi
#   exit 0
#   EOF
#   add_mock_to_path
#
#   # Using string
#   create_mock_command "mycommand" '#!/bin/bash
#   echo "output"
#   exit 0'
#   add_mock_to_path
create_mock_command() {
	local command_name="$1"
	local script_content="$2"
	local mock_path="${3:-${TEST_DIR}/${command_name}}"

	cat >"$mock_path" <<EOF
$script_content
EOF
	chmod +x "$mock_path"
	echo "$mock_path"
}

# Create a mock command that passes through to the real command
#
# Creates a mock command that executes the real command with the same name.
# Useful when you want to mock some commands but pass through others.
#
# Arguments:
#   $1: Command name to mock
#   $2: Optional path to real command (default: /usr/bin/${command_name})
#   $3: Optional path to mock file (default: ${TEST_DIR}/${command_name})
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints path to created mock command
#
# Side effects:
#   - Creates executable mock command script that calls real command
#
# Example:
#   # Pass through to real command
#   create_mock_pass_through "date"
#   add_mock_to_path
#
#   # Pass through with custom path
#   create_mock_pass_through "date" "/bin/date"
#   add_mock_to_path
create_mock_pass_through() {
	local command_name="$1"
	local real_command="${2:-/usr/bin/${command_name}}"
	local mock_path="${3:-${TEST_DIR}/${command_name}}"

	cat >"$mock_path" <<EOF
#!/bin/bash
exec "$real_command" "\$@"
EOF
	chmod +x "$mock_path"
	echo "$mock_path"
}

# Create a mock command that returns specific output
#
# Creates a mock command that prints the specified output and exits successfully.
# Useful for mocking commands that return data.
#
# Arguments:
#   $1: Command name to mock
#   $2: Output to print (can be multiline)
#   $3: Optional path to mock file (default: ${TEST_DIR}/${command_name})
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints path to created mock command
#
# Side effects:
#   - Creates executable mock command script
#
# Example:
#   # Simple output
#   create_mock_output "mycommand" "output text"
#   add_mock_to_path
#
#   # Multiline output
#   create_mock_output "mycommand" "line 1
#   line 2
#   line 3"
#   add_mock_to_path
create_mock_output() {
	local command_name="$1"
	local output="$2"
	local mock_path="${3:-${TEST_DIR}/${command_name}}"

	cat >"$mock_path" <<EOF
#!/bin/bash
cat <<'OUTPUT_EOF'
$output
OUTPUT_EOF
EOF
	chmod +x "$mock_path"
	echo "$mock_path"
}

# Create a mock command that tracks calls
#
# Creates a mock command that tracks each call in a state file, allowing tests
# to verify how many times a command was called and with what arguments.
#
# Arguments:
#   $1: Command name to mock
#   $2: Optional path to call tracking file (default: ${TEST_DIR}/${command_name}_calls)
#   $3: Optional path to mock file (default: ${TEST_DIR}/${command_name})
#   $4: Optional script content to execute (default: exit 0)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints path to created mock command
#
# Side effects:
#   - Creates executable mock command script
#   - Creates call tracking file
#
# Example:
#   # Track calls with default behavior
#   create_mock_with_tracking "mycommand"
#   add_mock_to_path
#   mycommand arg1 arg2
#   # Check calls: cat ${TEST_DIR}/mycommand_calls
#
#   # Track calls with custom behavior
#   create_mock_with_tracking "mycommand" "" "" 'echo "custom output"'
#   add_mock_to_path
create_mock_with_tracking() {
	local command_name="$1"
	local tracking_file="${2:-${TEST_DIR}/${command_name}_calls}"
	local mock_path="${3:-${TEST_DIR}/${command_name}}"
	local script_content="${4:-exit 0}"

	cat >"$mock_path" <<EOF
#!/bin/bash
# Track this call
echo "\$(date +%s) \$(basename "\$0") \$*" >> "$tracking_file"
# Execute custom script content
$script_content
EOF
	chmod +x "$mock_path"
	echo "$mock_path"
}

# Get call count for a tracked mock command
#
# Returns the number of times a tracked mock command was called.
#
# Arguments:
#   $1: Command name
#   $2: Optional path to call tracking file (default: ${TEST_DIR}/${command_name}_calls)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the number of calls (0 if file doesn't exist)
#
# Example:
#   create_mock_with_tracking "mycommand"
#   add_mock_to_path
#   mycommand
#   mycommand
#   local count
#   count=$(get_mock_call_count "mycommand")
#   assert_equal "$count" 2
get_mock_call_count() {
	local command_name="$1"
	local tracking_file="${2:-${TEST_DIR}/${command_name}_calls}"

	if [[ -f "$tracking_file" ]]; then
		wc -l <"$tracking_file" | tr -d ' '
	else
		echo "0"
	fi
}

# Clear call tracking for a mock command
#
# Removes the call tracking file for a mock command, resetting the call count.
#
# Arguments:
#   $1: Command name
#   $2: Optional path to call tracking file (default: ${TEST_DIR}/${command_name}_calls)
#
# Returns:
#   0: Always succeeds
#
# Example:
#   create_mock_with_tracking "mycommand"
#   add_mock_to_path
#   mycommand
#   clear_mock_tracking "mycommand"
#   # Call count is now 0
clear_mock_tracking() {
	local command_name="$1"
	local tracking_file="${2:-${TEST_DIR}/${command_name}_calls}"

	rm -f "$tracking_file"
}

# ============================================================================
# Complex XFRM State Mock Helpers
# ============================================================================
#
# These helpers simplify creating complex xfrm state mocks for testing SA
# count mismatches, asymmetric states, timing issues, and bidirectional SAs.
# They handle state tracking, file-based flags, and complex conditional logic
# internally, making tests more maintainable and readable.
#
# Mock Behavior:
# - All mocks handle both "ip -s xfrm state" (with statistics) and "ip xfrm state"
# - Mocks track state via file-based flags (e.g., deletion flags)
# - Mocks support SA deletion via "ip xfrm state delete" command
# - Mocks pass through other ip commands to the real /usr/bin/ip
#
# State Tracking:
# - Deletion flags: Track when SAs have been deleted
# - Call counters: Track verification attempts for timing scenarios
# - SA re-establishment: Track when SAs re-establish after deletion
#
# ============================================================================

# Create mock ip command for bidirectional SA scenarios
#
# Creates a mock 'ip' command that simulates bidirectional SAs (forward and
# reverse). The mock handles SA deletion and re-establishment with proper
# state tracking.
#
# Mock Behavior:
# - Before deletion: Returns 2 SAs (forward: local→peer, reverse: peer→local)
# - After deletion: Returns SAs based on re-establishment state
# - Deletion: Handles "ip xfrm state delete" and sets deletion flag
# - Supports both "ip -s xfrm state" and "ip xfrm state" formats
#
# Arguments:
#   $1: Local IP address (default: ${TEST_LOCAL_IP})
#   $2: Peer IP address (default: ${TEST_PEER_IP})
#   $3: Forward SPI value (default: 0x12345678)
#   $4: Reverse SPI value (default: 0x87654321)
#   $5: Path to deletion flag file (default: ${TEST_DIR}/sas_deleted)
#   $6: Bytes before deletion (default: 0)
#   $7: Bytes after re-establishment (default: 1000)
#   $8: Optional path to mock ip file (default: ${TEST_DIR}/ip)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints path to created mock script
#
# Side effects:
#   - Creates executable mock ip script
#   - Creates deletion flag file when SAs are deleted
#
# Example:
#   # Basic bidirectional SA mock
#   mock_ip_xfrm_bidirectional_sa "${TEST_LOCAL_IP}" "${TEST_PEER_IP}"
#   add_mock_to_path
#
#   # Custom SPIs and bytes
#   mock_ip_xfrm_bidirectional_sa "${TEST_LOCAL_IP}" "${TEST_PEER_IP}" \
#       "0xabcdef12" "0x21fedcba" "${TEST_DIR}/deleted" 0 2000
#   add_mock_to_path
mock_ip_xfrm_bidirectional_sa() {
	local local_ip="${1:-${TEST_LOCAL_IP}}"
	local peer_ip="${2:-${TEST_PEER_IP}}"
	local forward_spi="${3:-0x12345678}"
	local reverse_spi="${4:-0x87654321}"
	local deletion_flag="${5:-${TEST_DIR}/sas_deleted}"
	local bytes_before="${6:-0}"
	local bytes_after="${7:-1000}"
	local mock_ip="${8:-${TEST_DIR}/ip}"

	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]] && [[ "\$3" == "delete" ]]; then
    # SA deletion succeeds - set flag
    touch "${deletion_flag}" 2>/dev/null || true
    touch "${TEST_DIR}/MOCK_SAS_DELETED_FILE" 2>/dev/null || true
    exit 0
elif [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # Handle "ip -s xfrm state" (with statistics flag)
    if [[ -f "${deletion_flag}" ]]; then
        # After deletion: return SAs with re-established bytes
        # Forward SA (local→peer)
        echo "src ${local_ip} dst ${peer_ip}"
        echo "    proto esp spi ${forward_spi} reqid 1 mode tunnel"
        echo "    lifetime current: ${bytes_after} bytes, 10 packets"
        # Reverse SA (peer→local)
        echo "src ${peer_ip} dst ${local_ip}"
        echo "    proto esp spi ${reverse_spi} reqid 1 mode tunnel"
        echo "    lifetime current: ${bytes_after} bytes, 10 packets"
    else
        # Before deletion: return 2 SAs with initial bytes
        # Forward SA (local→peer)
        echo "src ${local_ip} dst ${peer_ip}"
        echo "    proto esp spi ${forward_spi} reqid 1 mode tunnel"
        echo "    lifetime current: ${bytes_before} bytes, 0 packets"
        # Reverse SA (peer→local)
        echo "src ${peer_ip} dst ${local_ip}"
        echo "    proto esp spi ${reverse_spi} reqid 1 mode tunnel"
        echo "    lifetime current: ${bytes_before} bytes, 0 packets"
    fi
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Handle "ip xfrm state" (without statistics flag)
    if [[ -f "${deletion_flag}" ]]; then
        # After deletion: return SAs with re-established bytes
        # Forward SA (local→peer)
        echo "src ${local_ip} dst ${peer_ip}"
        echo "    proto esp spi ${forward_spi} reqid 1 mode tunnel"
        echo "    lifetime current: ${bytes_after} bytes, 10 packets"
        # Reverse SA (peer→local)
        echo "src ${peer_ip} dst ${local_ip}"
        echo "    proto esp spi ${reverse_spi} reqid 1 mode tunnel"
        echo "    lifetime current: ${bytes_after} bytes, 10 packets"
    else
        # Before deletion: return 2 SAs with initial bytes
        # Forward SA (local→peer)
        echo "src ${local_ip} dst ${peer_ip}"
        echo "    proto esp spi ${forward_spi} reqid 1 mode tunnel"
        echo "    lifetime current: ${bytes_before} bytes, 0 packets"
        # Reverse SA (peer→local)
        echo "src ${peer_ip} dst ${local_ip}"
        echo "    proto esp spi ${reverse_spi} reqid 1 mode tunnel"
        echo "    lifetime current: ${bytes_before} bytes, 0 packets"
    fi
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	echo "$mock_ip"
}

# Create mock ip command for SA count mismatch scenarios
#
# Creates a mock 'ip' command that simulates SA count mismatches during
# recovery. The mock returns 2 SAs before deletion, but only 1 SA after
# deletion (simulating a mismatch where only one SA re-establishes).
#
# Mock Behavior:
# - Before deletion: Returns 2 SAs (bidirectional)
# - After deletion: Returns only 1 SA (forward or reverse, based on direction)
# - Deletion: Handles "ip xfrm state delete" and sets deletion flag
# - Supports both "ip -s xfrm state" and "ip xfrm state" formats
#
# Arguments:
#   $1: Local IP address (default: ${TEST_LOCAL_IP})
#   $2: Peer IP address (default: ${TEST_PEER_IP})
#   $3: Direction of remaining SA after deletion ("forward" or "reverse", default: "forward")
#   $4: Forward SPI value (default: 0x12345678)
#   $5: Reverse SPI value (default: 0x87654321)
#   $6: Path to deletion flag file (default: ${TEST_DIR}/sas_deleted)
#   $7: Bytes before deletion (default: 0)
#   $8: Bytes after re-establishment (default: 1000)
#   $9: Optional path to mock ip file (default: ${TEST_DIR}/ip)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints path to created mock script
#
# Side effects:
#   - Creates executable mock ip script
#   - Creates deletion flag file when SAs are deleted
#
# Example:
#   # SA count mismatch: deleted 2, only forward re-establishes
#   mock_ip_xfrm_sa_count_mismatch "${TEST_LOCAL_IP}" "${TEST_PEER_IP}" "forward"
#   add_mock_to_path
#
#   # SA count mismatch: deleted 2, only reverse re-establishes
#   mock_ip_xfrm_sa_count_mismatch "${TEST_LOCAL_IP}" "${TEST_PEER_IP}" "reverse"
#   add_mock_to_path
mock_ip_xfrm_sa_count_mismatch() {
	local local_ip="${1:-${TEST_LOCAL_IP}}"
	local peer_ip="${2:-${TEST_PEER_IP}}"
	local direction="${3:-forward}"
	local forward_spi="${4:-0x12345678}"
	local reverse_spi="${5:-0x87654321}"
	local deletion_flag="${6:-${TEST_DIR}/sas_deleted}"
	local bytes_before="${7:-0}"
	local bytes_after="${8:-1000}"
	local mock_ip="${9:-${TEST_DIR}/ip}"

	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]] && [[ "\$3" == "delete" ]]; then
    # SA deletion succeeds - set flag
    touch "${deletion_flag}" 2>/dev/null || true
    touch "${TEST_DIR}/MOCK_SAS_DELETED_FILE" 2>/dev/null || true
    exit 0
elif [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # Handle "ip -s xfrm state" (with statistics flag)
    if [[ -f "${deletion_flag}" ]]; then
        # After deletion: return only 1 SA (mismatch - deleted 2, only 1 re-established)
        if [[ "${direction}" == "forward" ]]; then
            # Return forward SA only (local→peer)
            echo "src ${local_ip} dst ${peer_ip}"
            echo "    proto esp spi ${forward_spi} reqid 1 mode tunnel"
            echo "    lifetime current: ${bytes_after} bytes, 10 packets"
        else
            # Return reverse SA only (peer→local)
            echo "src ${peer_ip} dst ${local_ip}"
            echo "    proto esp spi ${reverse_spi} reqid 1 mode tunnel"
            echo "    lifetime current: ${bytes_after} bytes, 10 packets"
        fi
    else
        # Before deletion: return 2 SAs (bidirectional)
        # Forward SA (local→peer)
        echo "src ${local_ip} dst ${peer_ip}"
        echo "    proto esp spi ${forward_spi} reqid 1 mode tunnel"
        echo "    lifetime current: ${bytes_before} bytes, 0 packets"
        # Reverse SA (peer→local)
        echo "src ${peer_ip} dst ${local_ip}"
        echo "    proto esp spi ${reverse_spi} reqid 1 mode tunnel"
        echo "    lifetime current: ${bytes_before} bytes, 0 packets"
    fi
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Handle "ip xfrm state" (without statistics flag)
    if [[ -f "${deletion_flag}" ]]; then
        # After deletion: return only 1 SA (mismatch - deleted 2, only 1 re-established)
        if [[ "${direction}" == "forward" ]]; then
            # Return forward SA only (local→peer)
            echo "src ${local_ip} dst ${peer_ip}"
            echo "    proto esp spi ${forward_spi} reqid 1 mode tunnel"
            echo "    lifetime current: ${bytes_after} bytes, 10 packets"
        else
            # Return reverse SA only (peer→local)
            echo "src ${peer_ip} dst ${local_ip}"
            echo "    proto esp spi ${reverse_spi} reqid 1 mode tunnel"
            echo "    lifetime current: ${bytes_after} bytes, 10 packets"
        fi
    else
        # Before deletion: return 2 SAs (bidirectional)
        # Forward SA (local→peer)
        echo "src ${local_ip} dst ${peer_ip}"
        echo "    proto esp spi ${forward_spi} reqid 1 mode tunnel"
        echo "    lifetime current: ${bytes_before} bytes, 0 packets"
        # Reverse SA (peer→local)
        echo "src ${peer_ip} dst ${local_ip}"
        echo "    proto esp spi ${reverse_spi} reqid 1 mode tunnel"
        echo "    lifetime current: ${bytes_before} bytes, 0 packets"
    fi
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	echo "$mock_ip"
}

# Create mock ip command for asymmetric SA state scenarios
#
# Creates a mock 'ip' command that simulates asymmetric SA states (only
# forward or only reverse SA present). The mock always returns only one SA,
# never bidirectional.
#
# Mock Behavior:
# - Always returns only 1 SA (forward or reverse, based on direction)
# - Deletion: Handles "ip xfrm state delete" and sets deletion flag
# - After deletion: Returns SA with re-established bytes
# - Supports both "ip -s xfrm state" and "ip xfrm state" formats
#
# Arguments:
#   $1: Local IP address (default: ${TEST_LOCAL_IP})
#   $2: Peer IP address (default: ${TEST_PEER_IP})
#   $3: Direction of SA ("forward" or "reverse", default: "forward")
#   $4: SPI value (default: 0x12345678 for forward, 0x87654321 for reverse)
#   $5: Path to deletion flag file (default: ${TEST_DIR}/sas_deleted)
#   $6: Bytes before deletion (default: 0)
#   $7: Bytes after re-establishment (default: 1000)
#   $8: Optional path to mock ip file (default: ${TEST_DIR}/ip)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints path to created mock script
#
# Side effects:
#   - Creates executable mock ip script
#   - Creates deletion flag file when SAs are deleted
#
# Example:
#   # Asymmetric: only forward SA present
#   mock_ip_xfrm_asymmetric_sa "${TEST_LOCAL_IP}" "${TEST_PEER_IP}" "forward"
#   add_mock_to_path
#
#   # Asymmetric: only reverse SA present
#   mock_ip_xfrm_asymmetric_sa "${TEST_LOCAL_IP}" "${TEST_PEER_IP}" "reverse"
#   add_mock_to_path
mock_ip_xfrm_asymmetric_sa() {
	local local_ip="${1:-${TEST_LOCAL_IP}}"
	local peer_ip="${2:-${TEST_PEER_IP}}"
	local direction="${3:-forward}"
	local spi="${4:-}"
	local deletion_flag="${5:-${TEST_DIR}/sas_deleted}"
	local bytes_before="${6:-0}"
	local bytes_after="${7:-1000}"
	local mock_ip="${8:-${TEST_DIR}/ip}"

	# Set default SPI based on direction
	if [[ -z "$spi" ]]; then
		if [[ "$direction" == "forward" ]]; then
			spi="0x12345678"
		else
			spi="0x87654321"
		fi
	fi

	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]] && [[ "\$3" == "delete" ]]; then
    # SA deletion succeeds - set flag
    touch "${deletion_flag}" 2>/dev/null || true
    touch "${TEST_DIR}/MOCK_SAS_DELETED_FILE" 2>/dev/null || true
    exit 0
elif [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # Handle "ip -s xfrm state" (with statistics flag)
    # Always return only one SA (asymmetric - no bidirectional)
    if [[ "${direction}" == "forward" ]]; then
        # Forward SA (local→peer)
        echo "src ${local_ip} dst ${peer_ip}"
        echo "    proto esp spi ${spi} reqid 1 mode tunnel"
        if [[ -f "${deletion_flag}" ]]; then
            # After deletion: return with re-established bytes
            echo "    lifetime current: ${bytes_after} bytes, 10 packets"
        else
            # Before deletion: return with zero byte counters
            echo "    lifetime current: ${bytes_before} bytes, 0 packets"
        fi
    else
        # Reverse SA (peer→local)
        echo "src ${peer_ip} dst ${local_ip}"
        echo "    proto esp spi ${spi} reqid 1 mode tunnel"
        if [[ -f "${deletion_flag}" ]]; then
            # After deletion: return with re-established bytes
            echo "    lifetime current: ${bytes_after} bytes, 10 packets"
        else
            # Before deletion: return with zero byte counters
            echo "    lifetime current: ${bytes_before} bytes, 0 packets"
        fi
    fi
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Handle "ip xfrm state" (without statistics flag)
    # Always return only one SA (asymmetric - no bidirectional)
    if [[ "${direction}" == "forward" ]]; then
        # Forward SA (local→peer)
        echo "src ${local_ip} dst ${peer_ip}"
        echo "    proto esp spi ${spi} reqid 1 mode tunnel"
        if [[ -f "${deletion_flag}" ]]; then
            # After deletion: return with re-established bytes
            echo "    lifetime current: ${bytes_after} bytes, 10 packets"
        else
            # Before deletion: return with zero byte counters
            echo "    lifetime current: ${bytes_before} bytes, 0 packets"
        fi
    else
        # Reverse SA (peer→local)
        echo "src ${peer_ip} dst ${local_ip}"
        echo "    proto esp spi ${spi} reqid 1 mode tunnel"
        if [[ -f "${deletion_flag}" ]]; then
            # After deletion: return with re-established bytes
            echo "    lifetime current: ${bytes_after} bytes, 10 packets"
        else
            # Before deletion: return with zero byte counters
            echo "    lifetime current: ${bytes_before} bytes, 0 packets"
        fi
    fi
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	echo "$mock_ip"
}

# Create mock ip command for timing delay scenarios
#
# Creates a mock 'ip' command that simulates timing issues where the second
# SA appears after a delay. The mock returns 1 SA initially after deletion,
# then 2 SAs after a specified number of verification attempts.
#
# Mock Behavior:
# - Before deletion: Returns 2 SAs (bidirectional)
# - After deletion: Returns 1 SA for first N attempts, then 2 SAs
# - Deletion: Handles "ip xfrm state delete" and sets deletion flag
# - Tracks verification attempts via call counter file
# - Supports both "ip -s xfrm state" and "ip xfrm state" formats
#
# Arguments:
#   $1: Local IP address (default: ${TEST_LOCAL_IP})
#   $2: Peer IP address (default: ${TEST_PEER_IP})
#   $3: Delay in verification attempts before second SA appears (default: 3)
#   $4: Forward SPI value (default: 0x12345678)
#   $5: Reverse SPI value (default: 0x87654321)
#   $6: Path to deletion flag file (default: ${TEST_DIR}/sas_deleted)
#   $7: Path to call counter file (default: ${TEST_DIR}/check_count)
#   $8: Bytes before deletion (default: 0)
#   $9: Bytes after re-establishment (default: 1000)
#   $10: Optional path to mock ip file (default: ${TEST_DIR}/ip)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints path to created mock script
#
# Side effects:
#   - Creates executable mock ip script
#   - Creates deletion flag file when SAs are deleted
#   - Creates/initializes call counter file
#
# Example:
#   # Timing delay: second SA appears after 3 attempts
#   mock_ip_xfrm_timing_delay "${TEST_LOCAL_IP}" "${TEST_PEER_IP}" 3
#   add_mock_to_path
#
#   # Timing delay: second SA appears after 5 attempts
#   mock_ip_xfrm_timing_delay "${TEST_LOCAL_IP}" "${TEST_PEER_IP}" 5 \
#       "0x12345678" "0x87654321" "${TEST_DIR}/deleted" "${TEST_DIR}/counter"
#   add_mock_to_path
mock_ip_xfrm_timing_delay() {
	local local_ip="${1:-${TEST_LOCAL_IP}}"
	local peer_ip="${2:-${TEST_PEER_IP}}"
	local delay="${3:-3}"
	local forward_spi="${4:-0x12345678}"
	local reverse_spi="${5:-0x87654321}"
	local deletion_flag="${6:-${TEST_DIR}/sas_deleted}"
	local check_count_file="${7:-${TEST_DIR}/check_count}"
	local bytes_before="${8:-0}"
	local bytes_after="${9:-1000}"
	local mock_ip="${10:-${TEST_DIR}/ip}"

	# Initialize call counter
	echo "0" >"$check_count_file" 2>/dev/null || true

	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]] && [[ "\$3" == "delete" ]]; then
    # SA deletion succeeds - set flag and reset counter
    touch "${deletion_flag}" 2>/dev/null || true
    touch "${TEST_DIR}/MOCK_SAS_DELETED_FILE" 2>/dev/null || true
    echo "0" > "${check_count_file}" 2>/dev/null || true
    exit 0
elif [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # Handle "ip -s xfrm state" (with statistics flag)
    if [[ -f "${deletion_flag}" ]]; then
        # After deletion: simulate timing issue - return 1 SA initially, then 2 SAs after delay
        local check_count=0
        if [[ -f "${check_count_file}" ]]; then
            check_count=\$(cat "${check_count_file}" 2>/dev/null || echo "0")
        fi
        # Use current counter value to decide what to return (before incrementing)
        local should_return_two=0
        if [[ \$check_count -ge ${delay} ]]; then
            should_return_two=1
        fi
        # Now increment the counter for next call
        check_count=\$((check_count + 1))
        echo "\$check_count" > "${check_count_file}" 2>/dev/null || true

        if [[ \$should_return_two -eq 0 ]]; then
            # Initial checks: return only 1 SA (first SA re-established)
            echo "src ${local_ip} dst ${peer_ip}"
            echo "    proto esp spi ${forward_spi} reqid 1 mode tunnel"
            echo "    lifetime current: ${bytes_after} bytes, 10 packets"
        else
            # Later checks: return 2 SAs (second SA appears after delay)
            # Forward SA (local→peer)
            echo "src ${local_ip} dst ${peer_ip}"
            echo "    proto esp spi ${forward_spi} reqid 1 mode tunnel"
            echo "    lifetime current: ${bytes_after} bytes, 10 packets"
            # Reverse SA (peer→local) - appears after delay
            echo "src ${peer_ip} dst ${local_ip}"
            echo "    proto esp spi ${reverse_spi} reqid 1 mode tunnel"
            echo "    lifetime current: ${bytes_after} bytes, 10 packets"
        fi
    else
        # Before deletion: return 2 SAs (bidirectional)
        # Forward SA (local→peer)
        echo "src ${local_ip} dst ${peer_ip}"
        echo "    proto esp spi ${forward_spi} reqid 1 mode tunnel"
        echo "    lifetime current: ${bytes_before} bytes, 0 packets"
        # Reverse SA (peer→local)
        echo "src ${peer_ip} dst ${local_ip}"
        echo "    proto esp spi ${reverse_spi} reqid 1 mode tunnel"
        echo "    lifetime current: ${bytes_before} bytes, 0 packets"
    fi
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Handle "ip xfrm state" (without statistics flag)
    if [[ -f "${deletion_flag}" ]]; then
        # After deletion: simulate timing issue - return 1 SA initially, then 2 SAs after delay
        local check_count=0
        if [[ -f "${check_count_file}" ]]; then
            check_count=\$(cat "${check_count_file}" 2>/dev/null || echo "0")
        fi
        # Use current counter value to decide what to return (before incrementing)
        local should_return_two=0
        if [[ \$check_count -ge ${delay} ]]; then
            should_return_two=1
        fi
        # Now increment the counter for next call
        check_count=\$((check_count + 1))
        echo "\$check_count" > "${check_count_file}" 2>/dev/null || true

        if [[ \$should_return_two -eq 0 ]]; then
            # Initial checks: return only 1 SA (first SA re-established)
            echo "src ${local_ip} dst ${peer_ip}"
            echo "    proto esp spi ${forward_spi} reqid 1 mode tunnel"
            echo "    lifetime current: ${bytes_after} bytes, 10 packets"
        else
            # Later checks: return 2 SAs (second SA appears after delay)
            # Forward SA (local→peer)
            echo "src ${local_ip} dst ${peer_ip}"
            echo "    proto esp spi ${forward_spi} reqid 1 mode tunnel"
            echo "    lifetime current: ${bytes_after} bytes, 10 packets"
            # Reverse SA (peer→local) - appears after delay
            echo "src ${peer_ip} dst ${local_ip}"
            echo "    proto esp spi ${reverse_spi} reqid 1 mode tunnel"
            echo "    lifetime current: ${bytes_after} bytes, 10 packets"
        fi
    else
        # Before deletion: return 2 SAs (bidirectional)
        # Forward SA (local→peer)
        echo "src ${local_ip} dst ${peer_ip}"
        echo "    proto esp spi ${forward_spi} reqid 1 mode tunnel"
        echo "    lifetime current: ${bytes_before} bytes, 0 packets"
        # Reverse SA (peer→local)
        echo "src ${peer_ip} dst ${local_ip}"
        echo "    proto esp spi ${reverse_spi} reqid 1 mode tunnel"
        echo "    lifetime current: ${bytes_before} bytes, 0 packets"
    fi
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	echo "$mock_ip"
}
