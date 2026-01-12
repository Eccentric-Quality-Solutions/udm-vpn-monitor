#!/usr/bin/env bash
#
# XFRM State Output Templates
#
# Common xfrm state output patterns for testing.
# These templates can be used to generate mock xfrm state outputs.

# Generate xfrm state output for a single SA
#
# Arguments:
#   $1: Peer IP address
#   $2: SPI (hex format, e.g., "0x12345678")
#   $3: Byte counter
#   $4: Packet counter
#   $5: ReqID (default: 1)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints xfrm state output to stdout
generate_xfrm_state_sa() {
	local peer_ip="$1"
	local spi="$2"
	local bytes="$3"
	local packets="$4"
	local reqid="${5:-1}"

	echo "src ${peer_ip} dst ${peer_ip}"
	echo "    proto esp spi ${spi} reqid ${reqid} mode tunnel"
	echo "    replay-window 0"
	echo "    auth-trunc hmac(sha256) 0x1234567890abcdef 96"
	echo "    enc cbc(aes) 0x1234567890abcdef"
	echo "    lifetime current: ${bytes} bytes, ${packets} packets"
	echo "    lifetime hard: 3600s, 0 bytes, 0 packets"
	echo "    lifetime soft: 2880s, 0 bytes, 0 packets"
	echo "    current use: 1"
	echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
}

# Generate minimal xfrm state output (used by detection code)
#
# Arguments:
#   $1: Peer IP address
#   $2: SPI (hex format)
#   $3: Byte counter
#   $4: Packet counter
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints minimal xfrm state output to stdout
generate_xfrm_state_minimal() {
	local peer_ip="$1"
	local spi="$2"
	local bytes="$3"
	local packets="$4"

	echo "src ${peer_ip} dst ${peer_ip}"
	echo "    proto esp spi ${spi} reqid 1 mode tunnel"
	echo "    lifetime current:"
	echo "      ${bytes}(bytes), ${packets}(packets)"
	echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
}

# Generate xfrm state output for multiple SAs
#
# Arguments:
#   $1: Peer IP address
#   $2: Base SPI (hex format)
#   $3: Number of SAs
#   $4: Base byte counter
#   $5: Base packet counter
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints xfrm state output for multiple SAs to stdout
generate_xfrm_state_multiple() {
	local peer_ip="$1"
	local base_spi="$2"
	local sa_count="$3"
	local base_bytes="$4"
	local base_packets="$5"

	local i
	for ((i = 0; i < sa_count; i++)); do
		local spi_value
		# Bash arithmetic can handle hex strings directly (0x prefix)
		# Calculate: base_spi + (i * 0x10000000)
		spi_value=$(printf "0x%08x" $((${base_spi} + i * 0x10000000)))
		local bytes=$((base_bytes + i * 100))
		local packets=$((base_packets + i * 10))
		generate_xfrm_state_sa "$peer_ip" "$spi_value" "$bytes" "$packets" $((i + 1))
	done
}

# Common xfrm state scenarios
XFRM_STATE_HEALTHY_BYTES=1000
XFRM_STATE_HEALTHY_PACKETS=10
XFRM_STATE_IDLE_BYTES=0
XFRM_STATE_IDLE_PACKETS=0
XFRM_STATE_FAILING_BYTES=1000
XFRM_STATE_FAILING_PACKETS=10
