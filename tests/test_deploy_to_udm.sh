#!/usr/bin/env bats
#
# Tests for deploy-to-udm.sh script
# Tests argument parsing, validation, resolve_bind_ip_from_config, and deployment flow with mocked SSH/SCP
#
# Critical paths covered:
# - Argument parsing and help
# - Required parameter validation (target-ip, password via stdin or interactive, package file)
# - resolve_bind_ip_from_config (LOCAL_UDM_IP from vpn-monitor.conf)
# - --bind-ip explicit and from config
# - --append-missing-config
# - Log archive before uninstall (Step 2); skipped when --skip-uninstall
# - Full deploy flow with mocked ssh/scp/sshpass

load test_helper

DEPLOY_SCRIPT="${BATS_TEST_DIRNAME}/../scripts/deploy-to-udm.sh"
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."

# bats test_tags=category:unit
@test "deploy-to-udm.sh exists and is executable" {
	assert_file_exist "$DEPLOY_SCRIPT"
	assert_file_executable "$DEPLOY_SCRIPT"
}

# bats test_tags=category:unit
@test "deploy-to-udm.sh shows help with --help flag" {
	run bash "$DEPLOY_SCRIPT" --help
	assert_success
	assert_output --partial "Usage:"
	assert_output --partial "--target-ip"
	assert_output --partial "--bind-ip"
	assert_output --partial "--username"
}

# bats test_tags=category:unit
@test "deploy-to-udm.sh shows help with -h flag" {
	run bash "$DEPLOY_SCRIPT" -h
	assert_success
	assert_output --partial "Usage:"
}

# bats test_tags=category:unit
@test "deploy-to-udm.sh rejects unknown options" {
	run bash "$DEPLOY_SCRIPT" --unknown-option
	assert_failure
	assert_output --partial "Unknown option"
}

# bats test_tags=category:unit
@test "deploy-to-udm.sh requires --target-ip" {
	run bash "$DEPLOY_SCRIPT" --file /nonexistent.zip </dev/null 2>&1
	assert_failure
	assert_output --partial "Target IP address is required"
}

# bats test_tags=category:unit
@test "deploy-to-udm.sh requires password when not interactive and stdin empty" {
	# Non-interactive with empty stdin: must pipe password or run interactively
	run bash "$DEPLOY_SCRIPT" \
		--target-ip 192.168.1.100 \
		--file "${PROJECT_ROOT}/udm-vpn-monitor.zip" </dev/null 2>&1
	assert_failure
	assert_output --partial "password"
}

# bats test_tags=category:unit
@test "deploy-to-udm.sh resolve_bind_ip_from_config uses LOCAL_UDM_IP from repo vpn-monitor.conf" {
	# Create package file for validation
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	# Ensure repo vpn-monitor.conf has LOCAL_UDM_IP
	local orig_conf="${PROJECT_ROOT}/vpn-monitor.conf"
	local backup_conf="${PROJECT_ROOT}/vpn-monitor.conf.bak.deploy-test"
	[[ -f "$orig_conf" ]] && cp "$orig_conf" "$backup_conf" || true
	# Prepend so it's found first; use unique IP for test
	{
		echo 'LOCAL_UDM_IP="172.31.17.77"'
		[[ -f "$orig_conf" ]] && cat "$orig_conf"
	} >"${orig_conf}.tmp" 2>/dev/null && mv "${orig_conf}.tmp" "$orig_conf" || echo 'LOCAL_UDM_IP="172.31.17.77"' >"$orig_conf"

	standard_setup
	local mock_bin="${TEST_DIR}/mock_bin"
	mkdir -p "$mock_bin"
	cat >"${mock_bin}/ssh" <<'MOCK'
#!/bin/bash
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

	# Run deploy without --bind-ip; should use LOCAL_UDM_IP from config
	run bash -c "printf '%s\n' testpass | \"$DEPLOY_SCRIPT\" \
		--target-ip 192.168.1.100 \
		--file \"${PROJECT_ROOT}/udm-vpn-monitor.zip\" \
		--verbose" 2>&1

	# Restore config
	if [[ -f "$backup_conf" ]]; then
		mv "$backup_conf" "$orig_conf"
	else
		rm -f "$orig_conf"
	fi

	assert_success
	assert_output --partial "172.31.17.77"
}

# bats test_tags=category:unit
@test "deploy-to-udm.sh uses explicit --bind-ip when provided" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	local mock_bin="${TEST_DIR}/mock_bin"
	mkdir -p "$mock_bin"
	cat >"${mock_bin}/ssh" <<'MOCK'
#!/bin/bash
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

	run bash -c "printf '%s\n' testpass | \"$DEPLOY_SCRIPT\" \
		--target-ip 192.168.1.100 \
		--bind-ip 192.168.50.1 \
		--file \"${PROJECT_ROOT}/udm-vpn-monitor.zip\"" 2>&1

	assert_success
	assert_output --partial "192.168.50.1"
}

# bats test_tags=category:unit
@test "deploy-to-udm.sh full deploy flow succeeds with mocked ssh/scp/sshpass" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	local mock_bin="${TEST_DIR}/mock_bin"
	mkdir -p "$mock_bin"
	cat >"${mock_bin}/ssh" <<'MOCK'
#!/bin/bash
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

	run bash -c "printf '%s\n' testpass | \"$DEPLOY_SCRIPT\" \
		--target-ip 192.168.1.100 \
		--file \"${PROJECT_ROOT}/udm-vpn-monitor.zip\"" 2>&1

	assert_success
	assert_output --partial "Deployment completed successfully"
	assert_output --partial "Package file transferred"
	assert_output --partial "Installation completed"
}

# bats test_tags=category:unit
@test "deploy-to-udm.sh --append-missing-config completes successfully" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	local mock_bin="${TEST_DIR}/mock_bin"
	mkdir -p "$mock_bin"
	cat >"${mock_bin}/ssh" <<'MOCK'
#!/bin/bash
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

	run bash -c "printf '%s\n' testpass | \"$DEPLOY_SCRIPT\" \
		--target-ip 192.168.1.100 \
		--file \"${PROJECT_ROOT}/udm-vpn-monitor.zip\" \
		--append-missing-config" 2>&1

	# --append-missing-config is passed to install.sh in Step 5; deploy completes
	assert_success
	assert_output --partial "Installation completed"
}

# bats test_tags=category:unit
@test "deploy-to-udm.sh --tail-follow runs tail -f after deploy (uses same credentials)" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	local mock_bin="${TEST_DIR}/mock_bin"
	mkdir -p "$mock_bin"
	cat >"${mock_bin}/ssh" <<'MOCK'
#!/bin/bash
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

	run bash -c "printf '%s\n' testpass | \"$DEPLOY_SCRIPT\" \
		--target-ip 192.168.1.100 \
		--file \"${PROJECT_ROOT}/udm-vpn-monitor.zip\" \
		--tail-follow" 2>&1

	assert_success
	assert_output --partial "Tailing vpn-monitor.log"
	assert_output --partial "Deployment completed successfully"
}

# bats test_tags=category:unit
@test "deploy-to-udm.sh runs log archive step before uninstall when uninstall is not skipped" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	local mock_bin="${TEST_DIR}/mock_bin"
	mkdir -p "$mock_bin"
	cat >"${mock_bin}/ssh" <<'MOCK'
#!/bin/bash
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

	run bash -c "printf '%s\n' testpass | \"$DEPLOY_SCRIPT\" \
		--target-ip 192.168.1.100 \
		--file \"${PROJECT_ROOT}/udm-vpn-monitor.zip\"" 2>&1

	assert_success
	# Step 2 (log archive) runs before Step 3 (uninstall)
	assert_output --partial "Step 2: Archiving logs on target UDM"
	assert_output --partial "Step 3: Uninstalling existing installation"
	# Archive step completes (either logs archived or none to archive)
	assert_output --regexp "(Log archive step completed|No logs to archive)"
}

# bats test_tags=category:unit
@test "deploy-to-udm.sh skips log archive step when --skip-uninstall is set" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	local mock_bin="${TEST_DIR}/mock_bin"
	mkdir -p "$mock_bin"
	cat >"${mock_bin}/ssh" <<'MOCK'
#!/bin/bash
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

	run bash -c "printf '%s\n' testpass | \"$DEPLOY_SCRIPT\" \
		--target-ip 192.168.1.100 \
		--file \"${PROJECT_ROOT}/udm-vpn-monitor.zip\" \
		--skip-uninstall" 2>&1

	assert_success
	# Log archive runs only when uninstall runs; with --skip-uninstall it is skipped
	refute_output --partial "Step 2: Archiving logs on target UDM"
	assert_output --partial "Step 4: Extracting package"
}

# bats test_tags=category:unit
@test "deploy-to-udm.sh creates log file and does not log username or password" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	local log_file="${TEST_DIR}/logs/deploy-to-udm.log"
	mkdir -p "$(dirname "$log_file")"
	local mock_bin="${TEST_DIR}/mock_bin"
	mkdir -p "$mock_bin"
	cat >"${mock_bin}/ssh" <<'MOCK'
#!/bin/bash
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
	export DEPLOY_LOG_FILE="$log_file"

	run bash -c "printf '%s\n' secretpassword123 | \"$DEPLOY_SCRIPT\" \
		--target-ip 192.168.1.100 \
		--username myuser \
		--file \"${PROJECT_ROOT}/udm-vpn-monitor.zip\"" 2>&1

	assert_success
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "Deployment completed successfully"
	assert_file_contains "$log_file" "Package file transferred"
	# Username and password must NOT appear in log file
	refute_file_contains "$log_file" "myuser"
	refute_file_contains "$log_file" "secretpassword123"
	# Sanitized form should appear (*** instead of username)
	assert_file_contains "$log_file" "***@192.168.1.100"
}

# bats test_tags=category:unit
@test "deploy-to-udm.sh records deployment in registry on success" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	mkdir -p "$(dirname "${TEST_DIR}/deploy-registry")"

	local mock_bin="${TEST_DIR}/mock_bin"
	mkdir -p "$mock_bin"
	cat >"${mock_bin}/ssh" <<'MOCK'
#!/bin/bash
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
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"

	run bash -c "printf '%s\n' testpass | \"$DEPLOY_SCRIPT\" \
		--target-ip 192.168.1.100 \
		--file \"${PROJECT_ROOT}/udm-vpn-monitor.zip\"" 2>&1

	assert_success
	local reg_file="${TEST_DIR}/deploy-registry"
	assert_file_exist "$reg_file"
	assert_file_contains "$reg_file" "192.168.1.100"
	assert_file_contains "$reg_file" "0.8.0"
}

# bats test_tags=category:unit
@test "deploy-registry record_deployment uses exact host match (no substring removal)" {
	# Regression: grep -v -F "192.168.1.10" would incorrectly remove 192.168.1.100
	standard_setup
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"
	export REPO_ROOT="$PROJECT_ROOT"
	mkdir -p "$(dirname "$DEPLOY_REGISTRY_FILE")"

	# Pre-populate: 192.168.1.100 exists
	echo -e "192.168.1.100\t0.8.0\t2025-02-14T12:00:00" >"$DEPLOY_REGISTRY_FILE"

	# Source and call record_deployment for 192.168.1.10 (substring of 192.168.1.100)
	source "${PROJECT_ROOT}/scripts/deploy-registry.sh"
	record_deployment "192.168.1.10" "0.8.0" "2025-02-14T12:01:00"

	# 192.168.1.100 must still exist; 192.168.1.10 must be added
	grep -q $'192.168.1.100\t' "$DEPLOY_REGISTRY_FILE" || {
		echo "192.168.1.100 should not have been removed when recording 192.168.1.10"
		return 1
	}
	grep -q $'192.168.1.10\t' "$DEPLOY_REGISTRY_FILE" || {
		echo "192.168.1.10 should have been added"
		return 1
	}
}
