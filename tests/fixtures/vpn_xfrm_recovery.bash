#!/usr/bin/env bash
#
# Test fixture: VPN XFRM Recovery Scenario
#
# Sets up a test environment for testing xfrm-based recovery operations.
# This fixture combines multiple setup steps for testing xfrm recovery scenarios.
#
# Arguments:
#   $1: Peer IP address (default: "192.168.1.1")
#   $2: SA count - number of Security Associations to simulate (default: 2)
#   $3: Recovery type (default: "success")
#       - "success": All SA deletions succeed
#       - "partial_failure": Some SA deletions succeed, others fail
#       - "complete_failure": All SA deletions fail
#   $4+: Additional config variables as KEY="VALUE" pairs
#
# Side effects:
#   - Sets up test VPN monitor environment with ENABLE_XFRM_RECOVERY=1 and TIER2_THRESHOLD=3
#   - Creates state files with failure count at Tier 2 threshold (3)
#   - Creates mock ip command that handles xfrm state show and delete based on recovery type
#   - Sets TEST_CONFIG_FILE, TEST_SCRIPT, STATE_DIR, LOGS_DIR variables
#   - Adds mock commands to PATH
#
# Example:
#   # Test with successful xfrm recovery (2 SAs, all deletions succeed)
#   setup_vpn_xfrm_recovery_fixture "192.168.1.1" 2 "success"
#
#   # Test with partial failure (3 SAs, some deletions fail)
#   setup_vpn_xfrm_recovery_fixture "192.168.1.1" 3 "partial_failure"
#
#   # Test with complete failure (2 SAs, all deletions fail)
#   setup_vpn_xfrm_recovery_fixture "192.168.1.1" 2 "complete_failure"
#
#   # Test with custom config
#   setup_vpn_xfrm_recovery_fixture "192.168.1.1" 2 "success" 'TIER2_THRESHOLD=5' 'RECOVERY_VERIFY_TIMEOUT=10'
setup_vpn_xfrm_recovery_fixture() {
	local peer_ip="${1:-192.168.1.1}"
	local sa_count="${2:-2}"
	local recovery_type="${3:-success}"
	shift 3 || true
	local extra_config=("$@")

	# Set up test VPN monitor with xfrm recovery enabled and Tier 2 threshold
	local default_config=('ENABLE_XFRM_RECOVERY=1' 'TIER2_THRESHOLD=3')
	setup_test_vpn_monitor "$peer_ip" "${TEST_DIR}" "${default_config[@]}" "${extra_config[@]}"

	# Set up state files with failure count at Tier 2 threshold (3)
	setup_state_files "$peer_ip" 3 0

	# Generate SPI values for the SAs
	# Use different SPIs for each SA to simulate multiple SAs
	local -a spi_array
	local base_spi=0x12345678
	for ((i = 0; i < sa_count; i++)); do
		# Increment SPI for each SA (simple increment by 0x10000000)
		local spi_value
		spi_value=$(printf "0x%08x" $((base_spi + i * 0x10000000)))
		spi_array+=("$spi_value")
	done

	# Create mock ip command that handles xfrm state operations
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]] && [[ "\$3" == "delete" ]]; then
    # Handle SA deletion based on recovery type
    local spi_to_delete="\$7"
EOF

	# Add deletion logic based on recovery type
	case "$recovery_type" in
	"success")
		# All deletions succeed
		cat >>"$mock_ip" <<'EOF'
    # All deletions succeed
    exit 0
EOF
		;;
	"partial_failure")
		# Some deletions succeed, others fail
		# First SA succeeds, second fails, third succeeds, etc.
		cat >>"$mock_ip" <<EOF
    # Partial failure: alternate between success and failure
    # Pattern: first succeeds, second fails, third succeeds, etc.
    local delete_count_file="${TEST_DIR}/delete_count"
    local delete_count=\$(cat "\$delete_count_file" 2>/dev/null || echo "0")
    delete_count=\$((delete_count + 1))
    echo "\$delete_count" > "\$delete_count_file"
    
    # Odd-numbered deletions succeed (1st, 3rd, 5th...), even-numbered fail (2nd, 4th, 6th...)
    if [[ \$((delete_count % 2)) -eq 1 ]]; then
        exit 0  # Success
    else
        echo "Error: Failed to delete SA with SPI \$spi_to_delete" >&2
        exit 1  # Failure
    fi
EOF
		;;
	"complete_failure")
		# All deletions fail
		cat >>"$mock_ip" <<'EOF'
    # All deletions fail
    echo "Error: Failed to delete SA" >&2
    exit 1
EOF
		;;
	*)
		echo "Warning: Unknown recovery type '$recovery_type', using 'success'" >&2
		cat >>"$mock_ip" <<'EOF'
    # Default: all succeed
    exit 0
EOF
		;;
	esac

	# Add xfrm state show handler to return multiple SAs
	cat >>"$mock_ip" <<EOF
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Return multiple SAs for the peer
    # This simulates the initial state before deletion
EOF

	# Generate SA output for each SPI
	for ((i = 0; i < sa_count; i++)); do
		local spi_value="${spi_array[$i]}"
		cat >>"$mock_ip" <<EOF
    echo "src ${peer_ip} dst ${peer_ip}"
    echo "    proto esp spi ${spi_value} reqid $((i + 1)) mode tunnel"
    echo "    replay-window 0"
    echo "    auth-trunc hmac(sha256) 0x1234567890abcdef 96"
    echo "    enc cbc(aes) 0x1234567890abcdef"
    echo "    lifetime current: $((1000 + i * 100)) bytes, $((10 + i)) packets"
    echo "    lifetime hard: 3600s, 0 bytes, 0 packets"
    echo "    lifetime soft: 2880s, 0 bytes, 0 packets"
    echo "    current use: 1"
    echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
EOF
	done

	# Handle other ip commands
	cat >>"$mock_ip" <<'EOF'
fi
# Handle other ip commands
exec /usr/bin/ip "$@"
EOF

	chmod +x "$mock_ip"

	# Add mocks to PATH
	add_mock_to_path

	export MOCK_IP="$mock_ip"
	export XFRM_RECOVERY_TYPE="$recovery_type"
	export XFRM_SA_COUNT="$sa_count"
}
