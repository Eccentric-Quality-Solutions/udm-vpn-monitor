#!/usr/bin/env bats
#
# Tests for scripts/manage/uninstall-from-udm.sh and uninstall-from-udms.sh

load test_helper

SINGLE_SCRIPT="${BATS_TEST_DIRNAME}/../scripts/manage/uninstall-from-udm.sh"
BATCH_SCRIPT="${BATS_TEST_DIRNAME}/../scripts/manage/uninstall-from-udms.sh"
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."

# bats test_tags=category:unit
@test "uninstall-from-udm.sh shows help" {
	run bash "$SINGLE_SCRIPT" --help
	assert_success
	assert_output --partial "Remove VPN Monitor from a remote UDM"
}

# bats test_tags=category:unit
@test "uninstall-from-udm.sh requires --host" {
	run bash "$SINGLE_SCRIPT"
	assert_failure
	assert_output --partial "--host is required"
}

# bats test_tags=category:unit
@test "uninstall-from-udm.sh dry-run default uninstall flags" {
	run bash "$SINGLE_SCRIPT" --dry-run --host 192.168.1.100
	assert_success
	assert_output --partial "[dry-run] 192.168.1.100"
	assert_output --partial "uninstall.sh' --yes --keep-config --remove-state --remove-logs"
}

# bats test_tags=category:unit
@test "uninstall-from-udm.sh dry-run forwards flag overrides" {
	run bash "$SINGLE_SCRIPT" --dry-run --host 192.168.1.100 --remove-config --keep-state --keep-logs
	assert_success
	assert_output --partial "--remove-config --keep-state --keep-logs"
}

# bats test_tags=category:unit
@test "uninstall-from-udm.sh rejects conflicting config flags" {
	run bash "$SINGLE_SCRIPT" --host 192.168.1.100 --keep-config --remove-config
	assert_failure
	assert_output --partial "Conflicting flags"
}

# bats test_tags=category:unit
@test "uninstall-from-udm.sh dry-run reports missing install path" {
	run bash "$SINGLE_SCRIPT" --dry-run --host 192.168.1.100
	assert_success
	assert_output --partial "No VPN Monitor installation found"
}

# bats test_tags=category:unit
@test "uninstall-from-udm.sh dry-run does not transfer a package" {
	run bash "$SINGLE_SCRIPT" --dry-run --host 192.168.1.100
	assert_success
	[[ "$output" != *"scp"* ]]
	[[ "$output" != *"unzip"* ]]
	[[ "$output" != *"udm-vpn-monitor.zip"* ]]
}

# bats test_tags=category:unit
@test "deploy-registry remove_registry_entry uses exact host match" {
	standard_setup
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"
	export REPO_ROOT="$PROJECT_ROOT"
	mkdir -p "$(dirname "$DEPLOY_REGISTRY_FILE")"
	printf '%s\n' $'192.168.1.100\t0.8.0\t2025-02-14T12:00:00' $'192.168.1.10\t0.8.0\t2025-02-14T12:01:00' >"$DEPLOY_REGISTRY_FILE"

	# shellcheck source=scripts/manage/deploy-registry.sh
	source "${PROJECT_ROOT}/scripts/manage/deploy-registry.sh"
	remove_registry_entry "192.168.1.10"

	grep -q $'192.168.1.100\t' "$DEPLOY_REGISTRY_FILE" || {
		echo "192.168.1.100 should remain when removing 192.168.1.10"
		return 1
	}
	if grep -q $'192.168.1.10\t' "$DEPLOY_REGISTRY_FILE"; then
		echo "192.168.1.10 should have been removed"
		return 1
	fi
}

# bats test_tags=category:unit
@test "deploy-registry remove_registry_entry succeeds when host absent" {
	standard_setup
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"
	export REPO_ROOT="$PROJECT_ROOT"
	mkdir -p "$(dirname "$DEPLOY_REGISTRY_FILE")"
	printf '%s\n' $'192.168.1.100\t0.8.0\t2025-02-14T12:00:00' >"$DEPLOY_REGISTRY_FILE"

	# shellcheck source=scripts/manage/deploy-registry.sh
	source "${PROJECT_ROOT}/scripts/manage/deploy-registry.sh"
	remove_registry_entry "192.168.1.200"

	grep -q $'192.168.1.100\t' "$DEPLOY_REGISTRY_FILE" || {
		echo "existing registry entry should remain"
		return 1
	}
}

# bats test_tags=category:unit
@test "uninstall-from-udms.sh shows help" {
	run bash "$BATCH_SCRIPT" --help
	assert_success
	assert_output --partial "multiple remote UDMs"
}

# bats test_tags=category:unit
@test "uninstall-from-udms.sh dry-run batch reads config" {
	local config_file="${BATS_TEST_TMPDIR}/hosts.conf"
	cat >"$config_file" <<EOF
192.168.1.100
192.168.1.101
EOF
	run bash "$BATCH_SCRIPT" --dry-run --config "$config_file"
	assert_success
	assert_output --partial "Summary: 2 succeeded, 0 failed"
}

# bats test_tags=category:unit
@test "uninstall-from-udms.sh dry-run batch forwards bind IP per host" {
	local config_file="${BATS_TEST_TMPDIR}/hosts_bind.conf"
	cat >"$config_file" <<EOF
192.168.1.100 10.0.0.5
192.168.1.101
EOF
	run bash "$BATCH_SCRIPT" --dry-run --config "$config_file"
	assert_success
	assert_output --partial "[dry-run] 192.168.1.100 bind=10.0.0.5"
	assert_output --partial "[dry-run] 192.168.1.101:"
	[[ "$output" != *"192.168.1.101 bind=10.0.0.5"* ]]
}

# bats test_tags=category:unit
@test "uninstall-from-udms.sh fails when config missing" {
	run bash "$BATCH_SCRIPT" --config /nonexistent/deploy-udms.conf
	assert_failure
	assert_output --partial "Config file not found"
}

# bats test_tags=category:unit
@test "uninstall-from-udms.sh fails when config has no hosts" {
	local config_file="${BATS_TEST_TMPDIR}/empty.conf"
	touch "$config_file"
	run bash "$BATCH_SCRIPT" --config "$config_file"
	assert_failure
	assert_output --partial "No hosts"
}
