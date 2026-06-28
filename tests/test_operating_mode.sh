#!/usr/bin/env bats
#
# Tests for operating mode control (lib/control/operating_mode.sh, vpn-monitor-control.sh)

load test_helper
load helpers/config
load helpers/logging

CONTROL_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor-control.sh"
LIB_DIR="${BATS_TEST_DIRNAME}/../lib"

setup() {
	export TEST_DIR="${BATS_TEST_TMPDIR}/operating_mode_test"
	mkdir -p "${TEST_DIR}/state" "${TEST_DIR}/logs"
	export STATE_DIR="${TEST_DIR}/state"
	export LOGS_DIR="${TEST_DIR}/logs"
	export LOG_FILE="${TEST_DIR}/logs/vpn-monitor.log"
	export INSTALL_DIR="${TEST_DIR}"
	# shellcheck source=../lib/logging.sh
	source "${LIB_DIR}/logging.sh"
	# shellcheck source=../lib/config/config_loading.sh
	source "${LIB_DIR}/config/config_loading.sh"
	# shellcheck source=../lib/control/operating_mode.sh
	source "${LIB_DIR}/control/operating_mode.sh"
	# shellcheck source=../lib/control/cron_control.sh
	source "${LIB_DIR}/control/cron_control.sh"
}

# bats test_tags=category:unit
@test "get_operating_mode defaults to running when state file missing" {
	run get_operating_mode
	assert_success
	assert_output "running"
}

# bats test_tags=category:unit
@test "set_operating_mode writes atomically and reads back" {
	set_operating_mode "stopped" "0" "test reason" "testuser"
	run get_operating_mode
	assert_success
	assert_output "stopped"
	[[ -f "${STATE_DIR}/operating_mode" ]]
	grep -q "^mode=stopped" "${STATE_DIR}/operating_mode"
	grep -q "^reason=test reason" "${STATE_DIR}/operating_mode"
}

# bats test_tags=category:unit
@test "parse_pause_until_time accepts relative duration +30m" {
	local now epoch
	now=$(date +%s)
	run parse_pause_until_time "+30m"
	assert_success
	epoch="${lines[0]}"
	[[ "$epoch" -gt "$now" ]]
	[[ "$epoch" -le $((now + 1860)) ]]
}

# bats test_tags=category:unit
@test "parse_pause_until_time rejects past epoch" {
	run parse_pause_until_time "1000"
	assert_failure
}

# bats test_tags=category:unit
@test "check_operating_mode exits early for active pause" {
	local future
	future=$(($(date +%s) + 3600))
	set_operating_mode "paused" "$future" "maintenance" "test"
	run check_operating_mode
	assert_failure
}

# bats test_tags=category:unit
@test "check_operating_mode auto-resumes expired pause" {
	local past
	past=$(($(date +%s) - 60))
	set_operating_mode "paused" "$past" "" "test"
	run check_operating_mode
	assert_success
	run get_operating_mode
	assert_output "running"
}

# bats test_tags=category:unit
@test "check_operating_mode sets NO_ESCALATE for observe-only" {
	set_operating_mode "observe-only" "0" "" "test"
	unset NO_ESCALATE
	run bash -c "source '${LIB_DIR}/logging.sh'; source '${LIB_DIR}/config/config_loading.sh'; source '${LIB_DIR}/control/operating_mode.sh'; export STATE_DIR='${STATE_DIR}'; export LOG_FILE='${LOG_FILE}'; check_operating_mode; [[ \"\${NO_ESCALATE:-0}\" -eq 1 ]]"
	assert_success
}

# bats test_tags=category:unit
@test "vpn-monitor-control.sh status shows mode" {
	# Minimal install layout for control script
	cp "${BATS_TEST_DIRNAME}/../vpn-monitor-control.sh" "${TEST_DIR}/vpn-monitor-control.sh"
	mkdir -p "${TEST_DIR}/lib/control"
	cp -r "${LIB_DIR}/control/"* "${TEST_DIR}/lib/control/"
	cp "${LIB_DIR}/control.sh" "${TEST_DIR}/lib/control.sh"
	cp "${LIB_DIR}/common.sh" "${TEST_DIR}/lib/common.sh"
	cp "${LIB_DIR}/logging.sh" "${TEST_DIR}/lib/logging.sh"
	cp "${LIB_DIR}/constants.sh" "${TEST_DIR}/lib/constants.sh"
	cp -r "${LIB_DIR}/config" "${TEST_DIR}/lib/"
	chmod +x "${TEST_DIR}/vpn-monitor-control.sh"
	set_operating_mode "observe-only" "0" "" "test"
	cd "${TEST_DIR}" || exit 1
	run bash "${TEST_DIR}/vpn-monitor-control.sh" status
	assert_success
	assert_output --partial "observe-only"
}

# bats test_tags=category:unit
@test "vpn-monitor-control.sh pause requires --until" {
	cp "${BATS_TEST_DIRNAME}/../vpn-monitor-control.sh" "${TEST_DIR}/vpn-monitor-control.sh"
	mkdir -p "${TEST_DIR}/lib/control"
	cp -r "${LIB_DIR}/control/"* "${TEST_DIR}/lib/control/"
	cp "${LIB_DIR}/control.sh" "${TEST_DIR}/lib/control.sh"
	cp "${LIB_DIR}/common.sh" "${TEST_DIR}/lib/common.sh"
	cp "${LIB_DIR}/logging.sh" "${TEST_DIR}/lib/logging.sh"
	cp "${LIB_DIR}/constants.sh" "${TEST_DIR}/lib/constants.sh"
	cp -r "${LIB_DIR}/config" "${TEST_DIR}/lib/"
	chmod +x "${TEST_DIR}/vpn-monitor-control.sh"
	cd "${TEST_DIR}" || exit 1
	run bash "${TEST_DIR}/vpn-monitor-control.sh" pause
	assert_failure
}

# bats test_tags=category:unit
@test "stop logs operating mode transition" {
	cp "${BATS_TEST_DIRNAME}/../vpn-monitor-control.sh" "${TEST_DIR}/vpn-monitor-control.sh"
	mkdir -p "${TEST_DIR}/lib/control"
	cp -r "${LIB_DIR}/control/"* "${TEST_DIR}/lib/control/"
	cp "${LIB_DIR}/control.sh" "${TEST_DIR}/lib/control.sh"
	cp "${LIB_DIR}/common.sh" "${TEST_DIR}/lib/common.sh"
	cp "${LIB_DIR}/logging.sh" "${TEST_DIR}/lib/logging.sh"
	cp "${LIB_DIR}/constants.sh" "${TEST_DIR}/lib/constants.sh"
	cp -r "${LIB_DIR}/config" "${TEST_DIR}/lib/"
	chmod +x "${TEST_DIR}/vpn-monitor-control.sh"
	set_operating_mode "running" "0" "" "test"
	cd "${TEST_DIR}" || exit 1
	run bash "${TEST_DIR}/vpn-monitor-control.sh" stop
	assert_success
	[[ -f "${LOG_FILE}" ]]
	grep -q "Operating mode changed" "${LOG_FILE}"
	run get_operating_mode
	assert_output "stopped"
}
