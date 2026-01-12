#!/usr/bin/env bash
#
# IPsec Status Output Templates
#
# Common ipsec status output patterns for different IPsec implementations.
# These templates can be used to generate mock ipsec status outputs.

# Generate libreswan ipsec status output
#
# Arguments:
#   $1: Connection name
#   $2: Peer IP address
#   $3: Local IP address (optional, defaults to TEST_LOCAL_IP if set)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints libreswan status output to stdout
generate_ipsec_status_libreswan() {
	local conn_name="$1"
	local peer_ip="$2"
	local local_ip="${3:-${TEST_LOCAL_IP:-192.168.1.1}}"

	echo "${conn_name}: ESTABLISHED 1 hour ago, ${peer_ip}...${local_ip}"
}

# Generate strongswan ipsec status output
#
# Arguments:
#   $1: Connection name
#   $2: Peer IP address
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints strongswan status output to stdout
generate_ipsec_status_strongswan() {
	local conn_name="$1"
	local peer_ip="$2"

	echo "${conn_name}: IKEv2, ESTABLISHED, ${peer_ip}"
}

# Generate default/generic ipsec status output
#
# Arguments:
#   $1: Connection name
#   $2: Peer IP address
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints generic status output to stdout
generate_ipsec_status_default() {
	local conn_name="$1"
	local peer_ip="$2"

	echo "${conn_name}: ESTABLISHED, ${peer_ip}"
}

# Generate ipsec status output based on format
#
# Arguments:
#   $1: Format type ("libreswan", "strongswan", or "default")
#   $2: Connection name
#   $3: Peer IP address
#   $4: Local IP address (optional, only used for libreswan)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints status output to stdout
generate_ipsec_status_output() {
	local format="$1"
	local conn_name="$2"
	local peer_ip="$3"
	local local_ip="$4"

	case "$format" in
	libreswan)
		generate_ipsec_status_libreswan "$conn_name" "$peer_ip" "$local_ip"
		;;
	strongswan)
		generate_ipsec_status_strongswan "$conn_name" "$peer_ip"
		;;
	default)
		generate_ipsec_status_default "$conn_name" "$peer_ip"
		;;
	*)
		echo "Unknown format: $format" >&2
		return 1
		;;
	esac
}
