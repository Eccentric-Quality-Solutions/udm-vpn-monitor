#!/usr/bin/env bats
#
# Tests for deploy-to-udms.sh script
# Tests argument parsing, config file validation, config parsing (host [bind_ip]), and batch flow
#
# Critical paths covered:
# - Argument parsing and help
# - Config file required
# - Config parsing (comments, blank lines, host [bind_ip] format)
# - bind_ip from config passed to deploy-to-udm (deployment plan shows it)
# - Package creation fallback
# - Batch deploy (deploy-to-udms passes --append-missing-config to deploy-to-udm)

load test_helper

DEPLOY_SCRIPT="${BATS_TEST_DIRNAME}/../manage/deploy-to-udms.sh"
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
MANAGE_LIB="${PROJECT_ROOT}/manage/lib/ssh_control.sh"

# Minimal fake repo tree for tests that mock deploy-to-udm.sh (manage/ layout).
setup_fake_manage_repo() {
	local fake_root="$1"
	mkdir -p "${fake_root}/manage/lib" "${fake_root}/lib"
	cp "$DEPLOY_SCRIPT" "${fake_root}/manage/deploy-to-udms.sh"
	cp "$MANAGE_LIB" "${fake_root}/manage/lib/ssh_control.sh"
	cp "${PROJECT_ROOT}/lib/common.sh" "${fake_root}/lib/common.sh"
	cp "${PROJECT_ROOT}/lib/constants.sh" "${fake_root}/lib/constants.sh"
	cp "${PROJECT_ROOT}/manage/deploy-registry.sh" "${fake_root}/manage/deploy-registry.sh"
}

# bats test_tags=category:unit
@test "deploy-to-udms.sh exists and is executable" {
	assert_file_exist "$DEPLOY_SCRIPT"
	assert_file_executable "$DEPLOY_SCRIPT"
}

# bats test_tags=category:unit
@test "deploy-to-udms.sh shows help with --help flag" {
	run bash "$DEPLOY_SCRIPT" --help
	assert_success
	assert_output --partial "Usage:"
	assert_output --partial "--config"
	assert_output --partial "--file"
	assert_output --partial "--skip-tail"
	assert_output --partial "--tail-follow"
	assert_output --partial "--dry-run"
	assert_output --partial "udm-vpn-monitor.zip"
}

# bats test_tags=category:unit
@test "deploy-to-udms.sh shows help with -h flag" {
	run bash "$DEPLOY_SCRIPT" -h
	assert_success
	assert_output --partial "Usage:"
}

# bats test_tags=category:unit
@test "deploy-to-udms.sh rejects unknown options" {
	run bash "$DEPLOY_SCRIPT" --unknown-option
	assert_failure
	assert_output --partial "Unknown option"
}

# bats test_tags=category:unit
@test "deploy-to-udms.sh requires config file to exist" {
	run bash "$DEPLOY_SCRIPT" --config /nonexistent/deploy-udms.conf 2>&1
	assert_failure
	assert_output --partial "Config file not found"
	assert_output --partial "deploy-udms.conf.example"
}

# bats test_tags=category:unit
@test "deploy-to-udms.sh fails when config has no UDMs (empty after stripping comments)" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	local config_file="${TEST_DIR}/deploy-udms.conf"
	cat >"$config_file" <<'EOF'
# Comment only
# Another comment

EOF
	run bash "$DEPLOY_SCRIPT" --config "$config_file" --file "${PROJECT_ROOT}/udm-vpn-monitor.zip" 2>&1
	assert_failure
	assert_output --partial "No UDMs found"
}

# bats test_tags=category:unit
@test "deploy-to-udms.sh parses config with host and optional bind_ip" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	local config_file="${TEST_DIR}/deploy-udms.conf"
	cat >"$config_file" <<'EOF'
# UDM list
192.168.1.100
192.168.1.101 192.168.50.1
vpn-gateway.example.com 10.0.0.5
EOF

	# Use test-specific registry so we don't skip based on previous runs
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"

	# Provide username/password via stdin; deploy-to-udm will fail (no real SSH) but config parsing is tested
	run bash "$DEPLOY_SCRIPT" \
		--config "$config_file" \
		--file "${PROJECT_ROOT}/udm-vpn-monitor.zip" \
		--skip-tail \
		< <(printf '%s\n' root testpass root testpass root testpass) 2>&1

	# Config parsing: 3 UDMs parsed, deploy attempted for each
	assert_output --partial "UDMs: 3"
	assert_output --partial "Deploying to: 192.168.1.100"
	assert_output --partial "Deploying to: 192.168.1.101"
	assert_output --partial "Deploying to: vpn-gateway.example.com"
	assert_output --partial "Deployment summary"
}

# bats test_tags=category:unit
@test "deploy-to-udms.sh skips empty host lines" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	local config_file="${TEST_DIR}/deploy-udms.conf"
	cat >"$config_file" <<'EOF'
192.168.1.100

192.168.1.101
EOF

	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"

	run bash "$DEPLOY_SCRIPT" \
		--config "$config_file" \
		--file "${PROJECT_ROOT}/udm-vpn-monitor.zip" \
		--skip-tail \
		< <(printf '%s\n' root testpass root testpass) 2>&1

	# Blank line skipped; 2 UDMs parsed
	assert_output --partial "UDMs: 2"
	assert_output --partial "Deploying to: 192.168.1.100"
	assert_output --partial "Deploying to: 192.168.1.101"
}

# bats test_tags=category:unit
@test "deploy-to-udms.sh skips hosts already at package version (unless --force)" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"
	mkdir -p "$(dirname "$DEPLOY_REGISTRY_FILE")"
	# Get package version so registry matches (skip logic requires exact version match)
	local pkg_version
	pkg_version=$(parse_script_version_line "$(unzip -p "${PROJECT_ROOT}/udm-vpn-monitor.zip" vpn-monitor.sh 2>/dev/null | grep -E '^SCRIPT_VERSION=' | head -1)")
	[[ -z "$pkg_version" ]] && skip "Could not get package version"
	# Pre-populate registry: 192.168.1.100 already at package version
	echo -e "192.168.1.100\t${pkg_version}\t2025-02-14T12:00:00" >"$DEPLOY_REGISTRY_FILE"

	local config_file="${TEST_DIR}/deploy-udms.conf"
	cat >"$config_file" <<'EOF'
192.168.1.100
192.168.1.101
EOF

	run bash "$DEPLOY_SCRIPT" \
		--config "$config_file" \
		--file "${PROJECT_ROOT}/udm-vpn-monitor.zip" \
		--skip-tail \
		< <(printf '%s\n' root testpass) 2>&1

	# Skip behavior verified; deploy to 192.168.1.101 fails (no real SSH) so exit may be 1
	assert_output --partial "Skipping 192.168.1.100 (already at version ${pkg_version})"
	assert_output --partial "Deploying to: 192.168.1.101"
	assert_output --partial "1 skipped (already at version)"
}

# bats test_tags=category:unit
@test "deploy-to-udms.sh --force deploys even when host in registry at same version" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"
	mkdir -p "$(dirname "$DEPLOY_REGISTRY_FILE")"
	echo -e "192.168.1.100\t0.8.0\t2025-02-14T12:00:00" >"$DEPLOY_REGISTRY_FILE"

	local config_file="${TEST_DIR}/deploy-udms.conf"
	cat >"$config_file" <<'EOF'
192.168.1.100
EOF

	run bash "$DEPLOY_SCRIPT" \
		--config "$config_file" \
		--file "${PROJECT_ROOT}/udm-vpn-monitor.zip" \
		--skip-tail \
		--force \
		< <(printf '%s\n' root testpass) 2>&1

	# With --force, should attempt deploy (not skip)
	assert_output --partial "Deploying to: 192.168.1.100"
	refute_output --partial "Skipping 192.168.1.100"
}

# bats test_tags=category:unit
@test "deploy-to-udms.sh dry-run forwards --dry-run and skips registry version hosts" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"
	mkdir -p "$(dirname "$DEPLOY_REGISTRY_FILE")"
	local pkg_version
	pkg_version=$(parse_script_version_line "$(unzip -p "${PROJECT_ROOT}/udm-vpn-monitor.zip" vpn-monitor.sh 2>/dev/null | grep -E '^SCRIPT_VERSION=' | head -1)")
	[[ -z "$pkg_version" ]] && skip "Could not get package version"
	echo -e "192.168.1.100\t${pkg_version}\t2025-02-14T12:00:00" >"$DEPLOY_REGISTRY_FILE"

	local config_file="${TEST_DIR}/deploy-udms.conf"
	cat >"$config_file" <<'EOF'
192.168.1.100
192.168.1.101 10.0.0.5
EOF

	local capture_file="${TEST_DIR}/deploy_to_udm_args.txt"
	export DEPLOY_TO_UDM_CAPTURE_FILE="$capture_file"

	local fake_root="${TEST_DIR}/fake_repo"
	setup_fake_manage_repo "$fake_root"
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"
	cat >"${fake_root}/manage/deploy-to-udm.sh" <<'MOCK'
#!/bin/bash
echo "ARGS: $*" >> "${DEPLOY_TO_UDM_CAPTURE_FILE:-/tmp/deploy_args.txt}"
echo "[dry-run] $*"
exit 0
MOCK
	chmod +x "${fake_root}/manage/deploy-to-udm.sh"
	cp "${PROJECT_ROOT}/udm-vpn-monitor.zip" "${fake_root}/" 2>/dev/null || true
	cp "$config_file" "${fake_root}/deploy-udms.conf"

	run bash "${fake_root}/manage/deploy-to-udms.sh" \
		--dry-run \
		--config "${fake_root}/deploy-udms.conf" \
		--file "${fake_root}/udm-vpn-monitor.zip" \
		--skip-tail 2>&1

	assert_success
	assert_output --partial "[dry-run] Would skip 192.168.1.100 (already at version ${pkg_version})"
	assert_output --partial "Dry-run summary: 1 planned, 1 would skip"
	assert_file_exist "$capture_file"
	local args
	args=$(cat "$capture_file")
	[[ "$args" == *"--dry-run"* ]] || {
		echo "Expected --dry-run in deploy-to-udm args: $args"
		return 1
	}
	[[ "$args" == *"--bind-ip"* ]] && [[ "$args" == *"10.0.0.5"* ]] || {
		echo "Expected bind IP in deploy-to-udm args: $args"
		return 1
	}
	refute_output --partial "Password is required"
}

# bats test_tags=category:unit
@test "deploy-to-udms.sh dry-run default batch does not pass tail-follow" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"
	local pkg_version
	pkg_version=$(parse_script_version_line "$(unzip -p "${PROJECT_ROOT}/udm-vpn-monitor.zip" vpn-monitor.sh 2>/dev/null | grep -E '^SCRIPT_VERSION=' | head -1)")
	[[ -z "$pkg_version" ]] && skip "Could not get package version"

	local config_file="${TEST_DIR}/deploy-udms.conf"
	cat >"$config_file" <<'EOF'
192.168.1.100
EOF

	local capture_file="${TEST_DIR}/deploy_to_udm_args.txt"
	export DEPLOY_TO_UDM_CAPTURE_FILE="$capture_file"

	local fake_root="${TEST_DIR}/fake_repo"
	setup_fake_manage_repo "$fake_root"
	cat >"${fake_root}/manage/deploy-to-udm.sh" <<'MOCK'
#!/bin/bash
echo "ARGS: $*" >> "${DEPLOY_TO_UDM_CAPTURE_FILE:-/tmp/deploy_args.txt}"
exit 0
MOCK
	chmod +x "${fake_root}/manage/deploy-to-udm.sh"
	cp "${PROJECT_ROOT}/udm-vpn-monitor.zip" "${fake_root}/" 2>/dev/null || true
	cp "$config_file" "${fake_root}/deploy-udms.conf"

	run bash "${fake_root}/manage/deploy-to-udms.sh" \
		--dry-run \
		--config "${fake_root}/deploy-udms.conf" \
		--file "${fake_root}/udm-vpn-monitor.zip" 2>&1

	assert_success
	refute_output --partial "prompt to mark deployment successful"
	assert_file_exist "$capture_file"
	local args
	args=$(cat "$capture_file")
	[[ "$args" == *"--dry-run"* ]] || {
		echo "Expected --dry-run in deploy-to-udm args: $args"
		return 1
	}
	[[ "$args" != *"--no-record"* ]] || {
		echo "Did not expect --no-record in default (skip-tail) deploy args: $args"
		return 1
	}
	[[ "$args" != *"--tail-follow"* ]] || {
		echo "Did not expect --tail-follow in default deploy args: $args"
		return 1
	}
}

# bats test_tags=category:unit
@test "deploy-to-udms.sh passes --bind-ip and --append-missing-config to deploy-to-udm" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	local config_file="${TEST_DIR}/deploy-udms.conf"
	# One host with bind_ip so we can assert deploy-to-udm is called with --bind-ip
	cat >"$config_file" <<'EOF'
192.168.1.101 192.168.50.1
EOF

	local capture_file="${TEST_DIR}/deploy_to_udm_args.txt"
	export DEPLOY_TO_UDM_CAPTURE_FILE="$capture_file"

	local fake_root="${TEST_DIR}/fake_repo"
	setup_fake_manage_repo "$fake_root"
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"
	# Mock deploy-to-udm.sh to record argv for assertion
	cat >"${fake_root}/manage/deploy-to-udm.sh" <<'MOCK'
#!/bin/bash
echo "ARGS: $*" >> "${DEPLOY_TO_UDM_CAPTURE_FILE:-/tmp/deploy_args.txt}"
exit 0
MOCK
	chmod +x "${fake_root}/manage/deploy-to-udm.sh"
	cp "${PROJECT_ROOT}/udm-vpn-monitor.zip" "${fake_root}/" 2>/dev/null || true
	cp "$config_file" "${fake_root}/deploy-udms.conf"

	run bash "${fake_root}/manage/deploy-to-udms.sh" \
		--config "${fake_root}/deploy-udms.conf" \
		--file "${fake_root}/udm-vpn-monitor.zip" \
		--skip-tail 2>&1

	assert_success
	assert_output --partial "Deployment summary"
	assert_file_exist "$capture_file"
	local args
	args=$(cat "$capture_file")
	[[ "$args" == *"--append-missing-config"* ]] || {
		echo "Expected --append-missing-config in deploy-to-udm args: $args"
		return 1
	}
	[[ "$args" == *"--bind-ip"* ]] || {
		echo "Expected --bind-ip in deploy-to-udm args: $args"
		return 1
	}
	[[ "$args" == *"192.168.50.1"* ]] || {
		echo "Expected bind_ip 192.168.50.1 in deploy-to-udm args: $args"
		return 1
	}
}

# bats test_tags=category:unit
@test "deploy-to-udms.sh passes --tail-follow to deploy-to-udm when --tail-follow is set" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	local config_file="${TEST_DIR}/deploy-udms.conf"
	cat >"$config_file" <<'EOF'
192.168.1.100
EOF

	local capture_file="${TEST_DIR}/deploy_to_udm_args.txt"
	export DEPLOY_TO_UDM_CAPTURE_FILE="$capture_file"

	local fake_root="${TEST_DIR}/fake_repo"
	setup_fake_manage_repo "$fake_root"
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"
	cat >"${fake_root}/manage/deploy-to-udm.sh" <<'MOCK'
#!/bin/bash
echo "ARGS: $*" >> "${DEPLOY_TO_UDM_CAPTURE_FILE:-/tmp/deploy_args.txt}"
exit 0
MOCK
	chmod +x "${fake_root}/manage/deploy-to-udm.sh"
	cp "${PROJECT_ROOT}/udm-vpn-monitor.zip" "${fake_root}/" 2>/dev/null || true
	cp "$config_file" "${fake_root}/deploy-udms.conf"

	# With --tail-follow, batch passes --tail-follow + --no-record; pipe password + 'y' for mark successful
	run bash -c "printf 'testpass\ny\n' | \"${fake_root}/manage/deploy-to-udms.sh\" \
		--tail-follow \
		--config \"${fake_root}/deploy-udms.conf\" \
		--file \"${fake_root}/udm-vpn-monitor.zip\"" 2>&1

	assert_success
	assert_file_exist "$capture_file"
	local args
	args=$(cat "$capture_file")
	[[ "$args" == *"--tail-follow"* ]] || {
		echo "Expected --tail-follow in deploy-to-udm args: $args"
		return 1
	}
}

# bats test_tags=category:unit
@test "deploy-to-udms.sh does not record when user answers n to mark successful" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"
	mkdir -p "$(dirname "$DEPLOY_REGISTRY_FILE")"

	local config_file="${TEST_DIR}/deploy-udms.conf"
	cat >"$config_file" <<'EOF'
192.168.1.100
EOF

	local fake_root="${TEST_DIR}/fake_repo"
	setup_fake_manage_repo "$fake_root"
	# Mock deploy-to-udm to succeed (so we get to the prompt)
	cat >"${fake_root}/manage/deploy-to-udm.sh" <<'MOCK'
#!/bin/bash
exit 0
MOCK
	chmod +x "${fake_root}/manage/deploy-to-udm.sh"
	cp "${PROJECT_ROOT}/udm-vpn-monitor.zip" "${fake_root}/" 2>/dev/null || true
	cp "$config_file" "${fake_root}/deploy-udms.conf"
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"

	# Answer 'n' to "Mark as successful?"
	run bash -c "printf 'testpass\nn\n' | \"${fake_root}/manage/deploy-to-udms.sh\" \
		--config \"${fake_root}/deploy-udms.conf\" \
		--file \"${fake_root}/udm-vpn-monitor.zip\"" 2>&1

	assert_success
	# Registry should be empty or not contain 192.168.1.100 (we said n)
	[[ ! -f "$DEPLOY_REGISTRY_FILE" ]] || ! grep -q "192.168.1.100" "$DEPLOY_REGISTRY_FILE" || {
		echo "Registry should not contain 192.168.1.100 when user answered n"
		return 1
	}
}

# bats test_tags=category:unit
@test "deploy-to-udms.sh creates log file" {
	cd "$PROJECT_ROOT"
	[[ -f udm-vpn-monitor.zip ]] || ./scripts/prepare_install_package.sh >/dev/null 2>&1 || true
	[[ -f udm-vpn-monitor.zip ]] || skip "Package file not available"

	standard_setup
	local log_file="${TEST_DIR}/logs/deploy-to-udms.log"
	mkdir -p "$(dirname "$log_file")"
	export DEPLOY_REGISTRY_FILE="${TEST_DIR}/deploy-registry"
	local config_file="${TEST_DIR}/deploy-udms.conf"
	cat >"$config_file" <<'EOF'
192.168.1.100
EOF

	export DEPLOY_LOG_FILE="$log_file"

	run bash "$DEPLOY_SCRIPT" \
		--config "$config_file" \
		--file "${PROJECT_ROOT}/udm-vpn-monitor.zip" \
		--skip-tail \
		< <(printf '%s\n' root testpass) 2>&1

	# Config parsing runs; deploy may fail (no real SSH) but log file should be created
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "UDM VPN Monitor Batch Deployment"
	assert_file_contains "$log_file" "Logging to:"
}
