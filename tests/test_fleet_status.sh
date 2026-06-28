#!/usr/bin/env bats
#
# Tests for scripts/manage/status-udms.sh

load test_helper

STATUS_SCRIPT="${BATS_TEST_DIRNAME}/../scripts/manage/status-udms.sh"
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."

# Install mock ssh/scp/sshpass that simulates fleet probe responses by target host.
#
# Returns:
#   0: Always
#
# Side effects:
#   Prepends mock bin directory to PATH
setup_fleet_status_ssh_mocks() {
	local mock_bin="${TEST_DIR}/mock_bin_fleet_status"
	mkdir -p "$mock_bin"
	cat >"${mock_bin}/ssh" <<'MOCK'
#!/bin/bash
host=""
last=""
if [[ "$*" == *"-O check"* ]] || [[ "$*" == *"-O exit"* ]]; then
	exit 0
fi
for arg in "$@"; do
	[[ "$arg" == *"@"* ]] && host="${arg#*@}"
	last="$arg"
done
if [[ "$last" == "true" ]]; then
	case "$host" in
	192.168.1.200) exit 1 ;;
	esac
	exit 0
fi
case "$host" in
192.168.1.200)
	exit 1
	;;
192.168.1.101)
	echo 'SCRIPT_VERSION='
	echo 'Operating mode: not installed'
	echo 'Cron: n/a'
	echo 'CRON_PRESENT=no'
	;;
192.168.1.102)
	echo 'SCRIPT_VERSION="0.9.0"'
	echo 'Operating mode: running'
	echo 'Cron: enabled'
	echo 'CRON_PRESENT=yes'
	;;
*)
	echo 'SCRIPT_VERSION="0.9.0"'
	echo 'Operating mode: running'
	echo 'Cron: enabled'
	echo 'Keepalive: running (systemd)'
	echo 'CRON_PRESENT=yes'
	;;
esac
exit 0
MOCK
	cat >"${mock_bin}/scp" <<'MOCK'
#!/bin/bash
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
@test "status-udms.sh shows help" {
	run bash "$STATUS_SCRIPT" --help
	assert_success
	assert_output --partial "Report live VPN Monitor status"
	assert_output --partial "REGISTRY_MATCH"
}

# bats test_tags=category:unit
@test "status-udms.sh dry-run prints remote probe command" {
	local config_file="${BATS_TEST_TMPDIR}/hosts.conf"
	echo "192.168.1.100" >"$config_file"
	run bash "$STATUS_SCRIPT" --dry-run --config "$config_file"
	assert_success
	assert_output --partial "[dry-run] 192.168.1.100"
	assert_output --partial "vpn-monitor-control.sh"
	assert_output --partial "CRON_PRESENT"
}

# bats test_tags=category:unit
@test "status-udms.sh dry-run batch resets bind IP per host" {
	local config_file="${BATS_TEST_TMPDIR}/hosts_bind.conf"
	cat >"$config_file" <<EOF
192.168.1.100 10.0.0.5
192.168.1.101
EOF
	run bash "$STATUS_SCRIPT" --dry-run --config "$config_file"
	assert_success
	assert_output --partial "[dry-run] 192.168.1.100 bind=10.0.0.5"
	assert_output --partial "[dry-run] 192.168.1.101:"
	[[ "$output" != *"192.168.1.101 bind=10.0.0.5"* ]]
}

# bats test_tags=category:unit
@test "status-udms.sh fails when explicit config missing" {
	run bash "$STATUS_SCRIPT" --config /nonexistent/deploy-udms.conf
	assert_failure
	assert_output --partial "Config file not found"
}

# bats test_tags=category:unit
@test "status-udms.sh fails when config has no hosts" {
	local config_file="${BATS_TEST_TMPDIR}/empty.conf"
	touch "$config_file"
	run bash "$STATUS_SCRIPT" --config "$config_file"
	assert_failure
	assert_output --partial "No hosts"
}

# bats test_tags=category:unit
@test "status-udms.sh fails when no default fleet config exists" {
	run bash "$STATUS_SCRIPT"
	assert_failure
	assert_output --partial "No fleet config found"
}

# bats test_tags=category:unit
@test "status-udms.sh uses deploy-udms.conf by default when present" {
	local config_file="${BATS_TEST_TMPDIR}/deploy-udms.conf"
	echo "192.168.1.100" >"$config_file"
	ln -sf "$config_file" "${PROJECT_ROOT}/deploy-udms.conf"
	run bash "$STATUS_SCRIPT" --dry-run
	assert_success
	assert_output --partial "[dry-run] 192.168.1.100"
	rm -f "${PROJECT_ROOT}/deploy-udms.conf"
}

# bats test_tags=category:unit
@test "status-udms.sh reports installed host with registry match" {
	standard_setup
	setup_fleet_status_ssh_mocks >/dev/null
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"
	export REPO_ROOT="$PROJECT_ROOT"
	printf '%s\n' $'192.168.1.100\t0.9.0\t2026-06-28T10:00:00' >"$DEPLOY_REGISTRY_FILE"
	local config_file="${BATS_TEST_TMPDIR}/one.conf"
	echo "192.168.1.100" >"$config_file"

	run bash -c "printf '%s\n' testpass | bash \"$STATUS_SCRIPT\" --config \"$config_file\"" 2>&1

	assert_success
	assert_output --partial $'192.168.1.100\t0.9.0\trunning\tyes\t0.9.0\t2026-06-28T10:00:00\tmatch'
	assert_output --partial "0 registry drift"
}

# bats test_tags=category:unit
@test "status-udms.sh reports not installed host" {
	standard_setup
	setup_fleet_status_ssh_mocks >/dev/null
	local config_file="${BATS_TEST_TMPDIR}/not_installed.conf"
	echo "192.168.1.101" >"$config_file"

	run bash -c "printf '%s\n' testpass | bash \"$STATUS_SCRIPT\" --config \"$config_file\"" 2>&1

	assert_success
	assert_output --partial $'192.168.1.101\tnot installed'
	assert_output --partial "1 not installed"
}

# bats test_tags=category:unit
@test "status-udms.sh reports registry drift" {
	standard_setup
	setup_fleet_status_ssh_mocks >/dev/null
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"
	export REPO_ROOT="$PROJECT_ROOT"
	printf '%s\n' $'192.168.1.102\t0.8.0\t2026-06-01T12:00:00' >"$DEPLOY_REGISTRY_FILE"
	local config_file="${BATS_TEST_TMPDIR}/drift.conf"
	echo "192.168.1.102" >"$config_file"

	run bash -c "printf '%s\n' testpass | bash \"$STATUS_SCRIPT\" --config \"$config_file\"" 2>&1

	assert_success
	assert_output --partial $'192.168.1.102\t0.9.0\trunning\tyes\t0.8.0\t2026-06-01T12:00:00\tdrift'
	assert_output --partial "1 registry drift"
}

# bats test_tags=category:unit
@test "status-udms.sh reports no_registry when installed but absent from registry" {
	standard_setup
	setup_fleet_status_ssh_mocks >/dev/null
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"
	export REPO_ROOT="$PROJECT_ROOT"
	: >"$DEPLOY_REGISTRY_FILE"
	local config_file="${BATS_TEST_TMPDIR}/no_reg.conf"
	echo "192.168.1.103" >"$config_file"

	run bash -c "printf '%s\n' testpass | bash \"$STATUS_SCRIPT\" --config \"$config_file\"" 2>&1

	assert_success
	assert_output --partial $'192.168.1.103\t0.9.0\trunning\tyes\t-\t-\tno_registry'
	assert_output --partial "1 registry drift"
}

# bats test_tags=category:unit
@test "status-udms.sh marks unreachable host and exits non-zero" {
	standard_setup
	setup_fleet_status_ssh_mocks >/dev/null
	local config_file="${BATS_TEST_TMPDIR}/bad.conf"
	echo "192.168.1.200" >"$config_file"

	run bash -c "printf '%s\n' testpass | bash \"$STATUS_SCRIPT\" --config \"$config_file\"" 2>&1

	assert_failure
	assert_output --partial $'192.168.1.200\tUNREACHABLE'
	assert_output --partial "1 unreachable"
	assert_output --partial "1 host(s) failed"
}

# bats test_tags=category:unit
@test "status-udms.sh summary counts multiple hosts" {
	standard_setup
	setup_fleet_status_ssh_mocks >/dev/null
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"
	export REPO_ROOT="$PROJECT_ROOT"
	printf '%s\n' $'192.168.1.100\t0.9.0\t2026-06-28T10:00:00' >"$DEPLOY_REGISTRY_FILE"
	local config_file="${BATS_TEST_TMPDIR}/multi.conf"
	cat >"$config_file" <<EOF
192.168.1.100
192.168.1.101
EOF

	run bash -c "printf '%s\n' testpass | bash \"$STATUS_SCRIPT\" --config \"$config_file\"" 2>&1

	assert_success
	assert_output --partial "2 host(s), 2 reachable, 1 installed, 1 not installed"
}
