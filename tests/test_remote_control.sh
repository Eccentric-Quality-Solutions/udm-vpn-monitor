#!/usr/bin/env bats
#
# Tests for manage/control-remote-udm.sh

load test_helper

REMOTE_SCRIPT="${BATS_TEST_DIRNAME}/../manage/control-remote-udm.sh"

# bats test_tags=category:unit
@test "control-remote-udm.sh shows help" {
	run bash "$REMOTE_SCRIPT" --help
	assert_success
	assert_output --partial "Remote control"
}

# bats test_tags=category:unit
@test "control-remote-udm.sh requires command" {
	run bash "$REMOTE_SCRIPT" --host 192.168.1.100
	assert_failure
}

# bats test_tags=category:unit
@test "control-remote-udm.sh dry-run status on single host" {
	run bash "$REMOTE_SCRIPT" --dry-run --host 192.168.1.100 status
	assert_success
	assert_output --partial "[dry-run] 192.168.1.100"
	assert_output --partial "vpn-monitor-control.sh' status"
}

# bats test_tags=category:unit
@test "control-remote-udm.sh dry-run batch mode reads config" {
	local config_file="${BATS_TEST_TMPDIR}/hosts.conf"
	cat >"$config_file" <<EOF
192.168.1.100
192.168.1.101
EOF
	run bash "$REMOTE_SCRIPT" --dry-run --config "$config_file" status
	assert_success
	assert_output --partial "Summary: 2 succeeded, 0 failed"
}

# bats test_tags=category:unit
@test "control-remote-udm.sh dry-run batch resets bind IP per host" {
	local config_file="${BATS_TEST_TMPDIR}/hosts_bind.conf"
	cat >"$config_file" <<EOF
192.168.1.100 10.0.0.5
192.168.1.101
EOF
	run bash "$REMOTE_SCRIPT" --dry-run --config "$config_file" status
	assert_success
	assert_output --partial "[dry-run] 192.168.1.100 bind=10.0.0.5"
	assert_output --partial "[dry-run] 192.168.1.101:"
	[[ "$output" != *"192.168.1.101 bind=10.0.0.5"* ]]
}

# bats test_tags=category:unit
@test "control-remote-udm.sh dry-run forwards pause --until argument" {
	run bash "$REMOTE_SCRIPT" --dry-run --host 192.168.1.100 pause --until +30m
	assert_success
	assert_output --partial "pause"
	assert_output --partial "+30m"
}

# bats test_tags=category:unit
@test "control-remote-udm.sh fails when config missing" {
	run bash "$REMOTE_SCRIPT" --config /nonexistent/control-udms.conf status
	assert_failure
	assert_output --partial "Config file not found"
}

# bats test_tags=category:unit
@test "control-remote-udm.sh fails when config has no hosts" {
	local config_file="${BATS_TEST_TMPDIR}/empty.conf"
	touch "$config_file"
	run bash "$REMOTE_SCRIPT" --config "$config_file" status
	assert_failure
	assert_output --partial "No hosts"
}
