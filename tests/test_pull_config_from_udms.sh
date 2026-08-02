#!/usr/bin/env bats
#
# Tests for manage/pull-config-from-udms.sh

load test_helper

PULL_SCRIPT="${BATS_TEST_DIRNAME}/../manage/pull-config-from-udms.sh"
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."

setup_pull_config_ssh_mocks() {
	local mock_bin="${TEST_DIR}/mock_bin_pull_config"
	mkdir -p "$mock_bin"
	cat >"${mock_bin}/ssh" <<'MOCK'
#!/bin/bash
host=""
cmd=""
for arg in "$@"; do
	[[ "$arg" == *"@"* ]] && host="${arg#*@}"
done
cmd="${!#}"
if [[ "$*" == *"-O check"* ]] || [[ "$*" == *"-O exit"* ]]; then
	exit 0
fi
if [[ "$cmd" == "true" ]]; then
	case "$host" in
	192.168.1.200) exit 1 ;;
	esac
	exit 0
fi
case "$host" in
192.168.1.200) exit 1 ;;
192.168.1.101) echo '__PULL_STATUS__=not_installed' ;;
192.168.1.102) echo '__PULL_STATUS__=no_remote_config' ;;
*) echo '__PULL_STATUS__=ok' ;;
esac
exit 0
MOCK
	cat >"${mock_bin}/scp" <<'MOCK'
#!/bin/bash
local_dest="${!#}"
if [[ "$local_dest" != *"@"* ]]; then
	cat >"$local_dest" <<'CONF'
TIER2_THRESHOLD=5
PING_TIMEOUT=2
CONF
fi
exit 0
MOCK
	cat >"${mock_bin}/sshpass" <<'MOCK'
#!/bin/bash
shift 2
exec ssh "$@"
MOCK
	chmod +x "${mock_bin}/ssh" "${mock_bin}/scp" "${mock_bin}/sshpass"
	export PATH="${mock_bin}:${PATH}"
}

# bats test_tags=category:unit
@test "pull-config-from-udms.sh shows help" {
	run bash "$PULL_SCRIPT" --help
	assert_success
	assert_output --partial "Pull live vpn-monitor.conf"
	assert_output --partial "configs/<host>/vpn-monitor.conf"
}

# bats test_tags=category:unit
@test "pull-config-from-udms.sh dry-run prints planned scp" {
	local config_dir="${BATS_TEST_TMPDIR}/configs"
	local fleet="${BATS_TEST_TMPDIR}/hosts.conf"
	echo "192.168.1.100" >"$fleet"
	run bash "$PULL_SCRIPT" --dry-run --config "$fleet" --config-dir "$config_dir"
	assert_success
	assert_output --partial "[dry-run] 192.168.1.100"
	assert_output --partial "vpn-monitor.conf"
}

# bats test_tags=category:unit
@test "pull-config-from-udms.sh fails when fleet config missing" {
	local config_dir="${BATS_TEST_TMPDIR}/configs"
	run bash "$PULL_SCRIPT" --config /nonexistent.conf --config-dir "$config_dir"
	assert_failure
	assert_output --partial "Config file not found"
}

# bats test_tags=category:unit
@test "pull-config-from-udms.sh fails when no default fleet config" {
	local config_dir="${BATS_TEST_TMPDIR}/configs"
	run bash "$PULL_SCRIPT" --config-dir "$config_dir"
	assert_failure
	assert_output --partial "No fleet config found"
}

# bats test_tags=category:unit
@test "pull-config-from-udms.sh pulls config to local working path" {
	standard_setup
	setup_pull_config_ssh_mocks >/dev/null
	local config_dir="${TEST_DIR}/configs"
	local fleet="${TEST_DIR}/one.conf"
	echo "192.168.1.100" >"$fleet"

	run bash -c "printf '%s\n' testpass | bash \"$PULL_SCRIPT\" --config \"$fleet\" --config-dir \"$config_dir\"" 2>&1

	assert_success
	assert_output --partial $'192.168.1.100\tok\t'
	assert_output --partial "${config_dir}/192.168.1.100/vpn-monitor.conf"
	[[ -f "${config_dir}/192.168.1.100/vpn-monitor.conf" ]]
}

# bats test_tags=category:unit
@test "pull-config-from-udms.sh reports not_installed" {
	standard_setup
	setup_pull_config_ssh_mocks >/dev/null
	local config_dir="${TEST_DIR}/configs"
	local fleet="${TEST_DIR}/ni.conf"
	echo "192.168.1.101" >"$fleet"

	run bash -c "printf '%s\n' testpass | bash \"$PULL_SCRIPT\" --config \"$fleet\" --config-dir \"$config_dir\"" 2>&1

	assert_failure
	assert_output --partial $'192.168.1.101\tnot_installed'
}

# bats test_tags=category:unit
@test "pull-config-from-udms.sh reports no_remote_config" {
	standard_setup
	setup_pull_config_ssh_mocks >/dev/null
	local config_dir="${TEST_DIR}/configs"
	local fleet="${TEST_DIR}/noconf.conf"
	echo "192.168.1.102" >"$fleet"

	run bash -c "printf '%s\n' testpass | bash \"$PULL_SCRIPT\" --config \"$fleet\" --config-dir \"$config_dir\"" 2>&1

	assert_failure
	assert_output --partial $'192.168.1.102\tno_remote_config'
}

# bats test_tags=category:unit
@test "pull-config-from-udms.sh marks unreachable host" {
	standard_setup
	setup_pull_config_ssh_mocks >/dev/null
	local config_dir="${TEST_DIR}/configs"
	local fleet="${TEST_DIR}/bad.conf"
	echo "192.168.1.200" >"$fleet"

	run bash -c "printf '%s\n' testpass | bash \"$PULL_SCRIPT\" --config \"$fleet\" --config-dir \"$config_dir\"" 2>&1

	assert_failure
	assert_output --partial $'192.168.1.200\tunreachable'
}

# bats test_tags=category:unit
@test "pull-config-from-udms.sh dry-run batch resets bind IP per host" {
	local config_dir="${BATS_TEST_TMPDIR}/configs"
	local fleet="${BATS_TEST_TMPDIR}/bind.conf"
	cat >"$fleet" <<EOF
192.168.1.100 10.0.0.5
192.168.1.101
EOF
	run bash "$PULL_SCRIPT" --dry-run --config "$fleet" --config-dir "$config_dir"
	assert_success
	assert_output --partial "[dry-run] 192.168.1.100 bind=10.0.0.5"
	[[ "$output" != *"192.168.1.101 bind=10.0.0.5"* ]]
}
