#!/usr/bin/env bats
#
# Tests for manage/push-config-to-udms.sh

load test_helper

PUSH_SCRIPT="${BATS_TEST_DIRNAME}/../manage/push-config-to-udms.sh"
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."

write_local_push_config() {
	local path="$1"
	mkdir -p "$(dirname "$path")"
	cat >"$path" <<'EOF'
TIER2_THRESHOLD=5
PING_TIMEOUT=2
EOF
}

setup_push_config_ssh_mocks() {
	local validation_fail="${1:-0}"
	local mock_bin="${TEST_DIR}/mock_bin_push_config"
	mkdir -p "$mock_bin"
	cat >"${mock_bin}/ssh" <<MOCK
#!/bin/bash
host=""
validation_fail="${validation_fail}"
for arg in "\$@"; do
	[[ "\$arg" == *"@"* ]] && host="\${arg#*@}"
done
if [[ "\$*" == *"-O check"* ]] || [[ "\$*" == *"-O exit"* ]]; then
	exit 0
fi
if [[ "\${!#}" == "true" ]]; then
	case "\$host" in
	192.168.1.200) exit 1 ;;
	esac
	exit 0
fi
case "\$host" in
192.168.1.200) exit 1 ;;
192.168.1.101)
	if [[ "\$*" == *"vpn-monitor.sh"* && "\$*" == *"check-config.sh"* && "\$*" != *"--config"* ]]; then
		echo '__PUSH_STATUS__=not_installed'
		exit 0
	fi
	;;
esac
if [[ "\$*" == *"test -f"* && "\$*" == *"/data/vpn-monitor/vpn-monitor.conf"* && "\$*" != *".tmp"* ]]; then
	exit 0
fi
if [[ "\$*" == *"/data/vpn-monitor/backups"* ]]; then
	echo '__PUSH_BACKUP__=ok'
	exit 0
fi
if [[ "\$*" == *"check-config.sh"* && "\$*" == *"--config"* ]]; then
	if [[ "\$validation_fail" == "1" ]]; then
		exit 1
	fi
	exit 0
fi
if [[ "\$*" == *"vpn-monitor.conf.tmp"* && "\$*" == *"mv "* ]]; then
	exit 0
fi
if [[ "\$*" == *"rm -f"* && "\$*" == *".tmp"* ]]; then
	exit 0
fi
if [[ "\$*" == *"vpn-monitor.sh"* && "\$*" == *"check-config.sh"* ]]; then
	echo '__PUSH_STATUS__=ok'
	exit 0
fi
exit 1
MOCK
	cat >"${mock_bin}/scp" <<'MOCK'
#!/bin/bash
last="${!#}"
if [[ "$last" == *":"* ]]; then
	exit 0
fi
if [[ "$last" != *"@"* ]]; then
	cat >"$last" <<'CONF'
TIER2_THRESHOLD=1
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
@test "push-config-to-udms.sh shows help" {
	run bash "$PUSH_SCRIPT" --help
	assert_success
	assert_output --partial "Push edited vpn-monitor.conf"
	assert_output --partial "check-config.sh"
	assert_output --partial "does not restart IPsec"
}

# bats test_tags=category:unit
@test "push-config-to-udms.sh dry-run prints backup and validate steps" {
	local config_dir="${BATS_TEST_TMPDIR}/configs"
	local local_file="${config_dir}/192.168.1.100/vpn-monitor.conf"
	write_local_push_config "$local_file"
	run bash "$PUSH_SCRIPT" --dry-run --host 192.168.1.100 --config-dir "$config_dir"
	assert_success
	assert_output --partial "[dry-run] 192.168.1.100"
	assert_output --partial "backups/vpn-monitor.conf."
	assert_output --partial "check-config"
}

# bats test_tags=category:unit
@test "push-config-to-udms.sh reports missing local file" {
	standard_setup
	setup_push_config_ssh_mocks >/dev/null
	local config_dir="${TEST_DIR}/configs_empty"

	run bash -c "printf '%s\n' testpass | bash \"$PUSH_SCRIPT\" --host 192.168.1.100 --config-dir \"$config_dir\"" 2>&1

	assert_failure
	assert_output --partial $'192.168.1.100\tmissing_local'
}

# bats test_tags=category:unit
@test "push-config-to-udms.sh pushes config successfully" {
	standard_setup
	setup_push_config_ssh_mocks 0 >/dev/null
	local config_dir="${TEST_DIR}/configs"
	local local_file="${config_dir}/192.168.1.100/vpn-monitor.conf"
	write_local_push_config "$local_file"

	run bash -c "printf '%s\n' testpass | bash \"$PUSH_SCRIPT\" --host 192.168.1.100 --config-dir \"$config_dir\"" 2>&1

	assert_success
	assert_output --partial $'192.168.1.100\tok\t'
	assert_output --partial "/data/vpn-monitor/backups/vpn-monitor.conf."
	local backup_file
	backup_file=$(find "${config_dir}/backups/192.168.1.100" -name 'vpn-monitor.conf.*' 2>/dev/null | head -1)
	[[ -n "$backup_file" && -f "$backup_file" ]]
}

# bats test_tags=category:unit
@test "push-config-to-udms.sh reports validation failure" {
	standard_setup
	setup_push_config_ssh_mocks 1 >/dev/null
	local config_dir="${TEST_DIR}/configs_fail"
	local local_file="${config_dir}/192.168.1.100/vpn-monitor.conf"
	write_local_push_config "$local_file"

	run bash -c "printf '%s\n' testpass | bash \"$PUSH_SCRIPT\" --host 192.168.1.100 --config-dir \"$config_dir\"" 2>&1

	assert_failure
	assert_output --partial $'192.168.1.100\tvalidation_failed'
}

# bats test_tags=category:unit
@test "push-config-to-udms.sh reports not_installed" {
	standard_setup
	setup_push_config_ssh_mocks >/dev/null
	local config_dir="${TEST_DIR}/configs_ni"
	local local_file="${config_dir}/192.168.1.101/vpn-monitor.conf"
	write_local_push_config "$local_file"

	run bash -c "printf '%s\n' testpass | bash \"$PUSH_SCRIPT\" --host 192.168.1.101 --config-dir \"$config_dir\"" 2>&1

	assert_failure
	assert_output --partial $'192.168.1.101\tnot_installed'
}

# bats test_tags=category:unit
@test "push-config-to-udms.sh marks unreachable host" {
	standard_setup
	setup_push_config_ssh_mocks >/dev/null
	local config_dir="${TEST_DIR}/configs_bad"
	local local_file="${config_dir}/192.168.1.200/vpn-monitor.conf"
	write_local_push_config "$local_file"

	run bash -c "printf '%s\n' testpass | bash \"$PUSH_SCRIPT\" --host 192.168.1.200 --config-dir \"$config_dir\"" 2>&1

	assert_failure
	assert_output --partial $'192.168.1.200\tunreachable'
}

# bats test_tags=category:unit
@test "push-config-to-udms.sh rejects --file without --host" {
	run bash "$PUSH_SCRIPT" --file "${TEST_DIR}/custom.conf"
	assert_failure
	assert_output --partial "--file requires --host"
}

# bats test_tags=category:unit
@test "push-config-to-udms.sh accepts explicit --file" {
	standard_setup
	setup_push_config_ssh_mocks 0 >/dev/null
	local config_dir="${TEST_DIR}/configs_file"
	local custom="${TEST_DIR}/custom.conf"
	write_local_push_config "$custom"

	run bash -c "printf '%s\n' testpass | bash \"$PUSH_SCRIPT\" --host 192.168.1.100 --file \"$custom\" --config-dir \"$config_dir\"" 2>&1

	assert_success
	assert_output --partial $'192.168.1.100\tok'
}
