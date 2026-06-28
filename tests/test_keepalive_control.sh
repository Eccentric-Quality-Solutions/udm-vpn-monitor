#!/usr/bin/env bats
#
# Tests for keepalive control (lib/control/keepalive_control.sh)

load test_helper
load helpers/config

LIB_DIR="${BATS_TEST_DIRNAME}/../lib"

setup() {
	export TEST_DIR="${BATS_TEST_TMPDIR}/keepalive_control_test"
	mkdir -p "${TEST_DIR}/state" "${TEST_DIR}/logs"
	export INSTALL_DIR="${TEST_DIR}"
	# shellcheck source=../lib/config/config_loading.sh
	source "${LIB_DIR}/config/config_loading.sh"
	# shellcheck source=../lib/control/keepalive_control.sh
	source "${LIB_DIR}/control/keepalive_control.sh"
}

# bats test_tags=category:unit
@test "is_keepalive_enabled returns true when ENABLE_KEEPALIVE=1" {
	cat >"${TEST_DIR}/vpn-monitor.conf" <<'EOF'
ENABLE_KEEPALIVE=1
EOF
	run is_keepalive_enabled "${TEST_DIR}/vpn-monitor.conf"
	assert_success
}

# bats test_tags=category:unit
@test "is_keepalive_enabled returns false when ENABLE_KEEPALIVE=0" {
	cat >"${TEST_DIR}/vpn-monitor.conf" <<'EOF'
ENABLE_KEEPALIVE=0
EOF
	run is_keepalive_enabled "${TEST_DIR}/vpn-monitor.conf"
	assert_failure
}

# bats test_tags=category:unit
@test "is_keepalive_enabled returns false when config missing" {
	run is_keepalive_enabled "${TEST_DIR}/missing.conf"
	assert_failure
}

# bats test_tags=category:unit
@test "stop_keepalive invokes script stop when systemd inactive" {
	cat >"${TEST_DIR}/vpn-keepalive.sh" <<EOF
#!/bin/bash
case "\$1" in
stop) echo "stopped" >"${TEST_DIR}/state/stop-called" ;;
esac
exit 0
EOF
	chmod +x "${TEST_DIR}/vpn-keepalive.sh"
	stop_keepalive "$TEST_DIR"
	[[ -f "${TEST_DIR}/state/stop-called" ]]
}

# bats test_tags=category:unit
@test "start_keepalive invokes script start when no systemd unit" {
	cat >"${TEST_DIR}/vpn-keepalive.sh" <<EOF
#!/bin/bash
case "\$1" in
start) echo "started" >"${TEST_DIR}/state/start-called" ;;
esac
exit 0
EOF
	chmod +x "${TEST_DIR}/vpn-keepalive.sh"
	run start_keepalive "$TEST_DIR"
	assert_success
	[[ -f "${TEST_DIR}/state/start-called" ]]
}

# bats test_tags=category:unit
@test "start_keepalive returns failure when no backend available" {
	run start_keepalive "$TEST_DIR"
	assert_failure
}
