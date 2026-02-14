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

DEPLOY_SCRIPT="${BATS_TEST_DIRNAME}/../scripts/deploy-to-udms.sh"
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."

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
	standard_setup
	local config_file="${TEST_DIR}/deploy-udms.conf"
	cat >"$config_file" <<'EOF'
# Comment only
# Another comment

EOF
	run bash "$DEPLOY_SCRIPT" --config "$config_file" 2>&1
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
	mkdir -p "${fake_root}/scripts"
	cp "$DEPLOY_SCRIPT" "${fake_root}/scripts/deploy-to-udms.sh"
	# Mock deploy-to-udm.sh to record argv for assertion
	cat >"${fake_root}/scripts/deploy-to-udm.sh" <<'MOCK'
#!/bin/bash
echo "ARGS: $*" >> "${DEPLOY_TO_UDM_CAPTURE_FILE:-/tmp/deploy_args.txt}"
exit 0
MOCK
	chmod +x "${fake_root}/scripts/deploy-to-udm.sh"
	cp "${PROJECT_ROOT}/udm-vpn-monitor.zip" "${fake_root}/" 2>/dev/null || true
	cp "$config_file" "${fake_root}/deploy-udms.conf"

	run bash "${fake_root}/scripts/deploy-to-udms.sh" \
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
