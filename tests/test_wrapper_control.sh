#!/usr/bin/env bats
#
# Tests for wrapper control (lib/control/wrapper_control.sh)

load test_helper

LIB_DIR="${BATS_TEST_DIRNAME}/../lib"

setup() {
	export TEST_DIR="${BATS_TEST_TMPDIR}/wrapper_control_test"
	mkdir -p "${TEST_DIR}/state"
	export STATE_DIR="${TEST_DIR}/state"
	# shellcheck source=../lib/common.sh
	source "${LIB_DIR}/common.sh"
	# shellcheck source=../lib/control/wrapper_control.sh
	source "${LIB_DIR}/control/wrapper_control.sh"
}

# bats test_tags=category:unit
@test "get_wrapper_pidfile_path uses STATE_DIR" {
	run get_wrapper_pidfile_path
	assert_success
	assert_output "${STATE_DIR}/vpn-monitor-wrapper.pid"
}

# bats test_tags=category:unit
@test "stop_monitor_wrapper removes pidfile and stops process" {
	local pidfile child_pid
	pidfile=$(get_wrapper_pidfile_path)
	# Long sleep as stand-in for wrapper
	sleep 60 &
	child_pid=$!
	echo "$child_pid" >"$pidfile"
	mkdir -p "${STATE_DIR}/.wrapper.lock"

	stop_monitor_wrapper

	# Bats: use `run !` so process-gone (non-zero kill -0) is a real assertion
	run ! kill -0 "$child_pid" 2>/dev/null
	[[ ! -f "$pidfile" ]]
	[[ ! -d "${STATE_DIR}/.wrapper.lock" ]]
}

# bats test_tags=category:unit
@test "stop_monitor_wrapper succeeds when nothing running" {
	run stop_monitor_wrapper
	assert_success
}
