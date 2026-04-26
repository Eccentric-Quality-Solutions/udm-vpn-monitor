#!/usr/bin/env bats
#
# Multi-invocation (cron-cycle style) tests: shared state directory, sequential runs.

load test_helper
load helpers/assertions

# Write a mock `ip` to TEST_DIR that reads xfrm byte counter and default-route partition from control files.
#
# Arguments:
# $1: peer_ip (string) - Address echoed in xfrm state lines
# $2: bytes_file (path) - File whose contents are the "bytes" value in xfrm output
# $3: partition_file (path) - If it exists and contains 1, `ip route show default` fails
# $4: spi (string, optional) - SPI in mock xfrm output (default: 0x12345678)
#
# Returns:
# 0: mock script was written and made executable
# 1: write or chmod failed
_mock_ip_xfrm_and_route_from_files() {
	local peer_ip="$1"
	local bytes_file="$2"
	local partition_file="$3"
	local spi="${4:-0x12345678}"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
peer_ip="$peer_ip"
bytes_file="$bytes_file"
partition_file="$partition_file"
spi="$spi"
bytes=\$(cat "\$bytes_file" 2>/dev/null || echo 0)

if [[ "\$1" == "route" ]] && [[ "\$2" == "show" ]] && [[ "\$3" == "default" ]]; then
    if [[ -f "\$partition_file" ]] && [[ "\$(cat "\$partition_file" 2>/dev/null)" == "1" ]]; then
        exit 1
    fi
    echo "default via \${peer_ip} dev eth0"
    exit 0
fi

if [[ "\$1" == "link" ]] && [[ "\$2" == "show" ]] && [[ -n "\${3:-}" ]]; then
    echo "2: \$3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default"
    exit 0
fi

if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    echo "src \${peer_ip} dst \${peer_ip}"
    echo "    proto esp spi \${spi} reqid 1 mode tunnel"
    echo "    lifetime current: \${bytes} bytes, 10 packets"
    exit 0
fi
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    echo "src \${peer_ip} dst \${peer_ip}"
    echo "    proto esp spi \${spi} reqid 1 mode tunnel"
    echo "    lifetime current: \${bytes} bytes, 10 packets"
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
}

# bats test_tags=slow,category:integration,priority:high
@test "cron-cycle: five sequential runs — stuck bytes then recovery; tiers; no stale lock" {
	# Purpose: Simulate five back-to-back cron invocations with one persistent state directory.
	# Expected: Runs 1–3 escalate (Tier 1 then Tier 2); run 4 sees byte increase and resets failure count; run 5 stays healthy; lock released each time.
	# Importance: Catches cross-run bugs (state, lockfile, tier/rate-limit interaction) that single-shot tests miss.
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" \
		'STARTUP_GRACE_PERIOD=0' \
		'ENABLE_RESOURCE_MONITORING=0' \
		'ENABLE_PING_CHECK=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0' \
		'MIN_RESTART_INTERVAL_SECONDS=0' \
		'MAX_RESTARTS_PER_WINDOW=20' \
		'RATE_LIMIT_WINDOW_MINUTES=60' \
		'ENABLE_XFRM_RECOVERY=0' \
		'ENABLE_TIER2_IPSEC_RELOAD=1' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5'

	local bytes_file="${TEST_DIR}/xfrm_bytes"
	local part_file="${TEST_DIR}/partition_flag"
	echo 0 >"$part_file"
	echo 1000 >"$bytes_file"

	_mock_ip_xfrm_and_route_from_files "${TEST_PEER_IP}" "$bytes_file" "$part_file"
	mock_ipsec_reload_restart 0 0 1
	add_mock_to_path

	ensure_state_functions_loaded
	set_peer_state "TEST" "${TEST_PEER_IP}" "last_bytes" "1000" || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "spi" "0x12345678" || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "failure_count" "0" || true

	local i
	for i in 1 2 3 4 5; do
		if [[ "$i" -lt 4 ]]; then
			echo 1000 >"$bytes_file"
		elif [[ "$i" -eq 4 ]]; then
			echo 5000 >"$bytes_file"
		else
			# Run 5: keep bytes increasing so the tunnel is not classified as stuck again
			echo 6000 >"$bytes_file"
		fi
		PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake
		assert_success
		if [[ -f "$LOCKFILE" ]]; then
			local lk_pid
			lk_pid=$(cut -d: -f2 "$LOCKFILE" 2>/dev/null || echo "")
			if [[ -n "$lk_pid" ]] && kill -0 "$lk_pid" 2>/dev/null; then
				echo "Lockfile still held by PID $lk_pid after run $i" >&2
				return 1
			fi
		fi
	done

	assert_file_contains "$LOG_FILE" "Tier 1:"
	assert_file_contains "$LOG_FILE" "Tier 2:"

	local failure_counter
	failure_counter=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
	assert_file_exist "$failure_counter"
	assert_equal "$(cat "$failure_counter")" 0

	remove_mock_from_path
}

# bats test_tags=slow,category:integration,priority:high
@test "cron-cycle: network partition clears across runs — route fail then healthy VPN" {
	# Purpose: Partition skips VPN checks; after connectivity returns, monitoring resumes and logs restoration.
	# Expected: Run 1–2 log partition/skip; run 3 logs connectivity restored and processes VPN; byte mock shows healthy tunnel.
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" \
		'STARTUP_GRACE_PERIOD=0' \
		'ENABLE_RESOURCE_MONITORING=0' \
		'ENABLE_PING_CHECK=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=1' \
		'NETWORK_PARTITION_INTERFACES=br0,eth0' \
		'MIN_RESTART_INTERVAL_SECONDS=0' \
		'ENABLE_XFRM_RECOVERY=0'

	local bytes_file="${TEST_DIR}/xfrm_bytes"
	local part_file="${TEST_DIR}/partition_flag"
	echo 1 >"$part_file"
	echo 2000 >"$bytes_file"

	_mock_ip_xfrm_and_route_from_files "${TEST_PEER_IP}" "$bytes_file" "$part_file"
	mock_dig 1
	MOCK_IPSEC=$(mock_ipsec "default")
	add_mock_to_path

	ensure_state_functions_loaded
	set_peer_state "TEST" "${TEST_PEER_IP}" "last_bytes" "1000" || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "spi" "0x12345678" || true

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake
	assert_success
	assert_file_contains "$LOG_FILE" "Network partition"

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake
	assert_success

	echo 0 >"$part_file"
	echo 3000 >"$bytes_file"

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake
	assert_success
	assert_file_contains "$LOG_FILE" "Network connectivity restored"

	remove_mock_from_path
}
