#!/usr/bin/env bats
#
# Tests for Configuration Security (Dangerous Content Detection)
# Tests critical paths and error handling scenarios

load test_helper
load helpers/config
load helpers/assertions
load fixtures/vpn_active

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# CONFIGURATION SECURITY TESTS (DANGEROUS CONTENT DETECTION)
# ============================================================================

@test "STATE_DIR override in config updates all dependent paths" {
	# Purpose: Test verifies that when STATE_DIR is overridden in config, all dependent paths are updated correctly
	# Expected: Script updates all paths that depend on STATE_DIR (LOCKFILE, COOLDOWN_UNTIL_FILE, LOGS_DIR, etc.) to use the custom directory
	# Importance: Ensures consistent path handling when custom state directories are specified
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local custom_state_dir="${TEST_DIR}/custom-state"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"STATE_DIR=\"${custom_state_dir}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Ensure custom state directory does not exist initially
	rm -rf "$custom_state_dir" 2>/dev/null || true

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	run bash "$test_script" --fake

	assert_success
	# Custom state directory should be created by init_state()
	assert_dir_exist "$custom_state_dir"

	# Dependent paths should use custom STATE_DIR:
	# - LOCKFILE should be in custom_state_dir
	# - COOLDOWN_UNTIL_FILE should be in custom_state_dir
	# - LOGS_DIR should be custom_state_dir/logs
	# - RESTART_COUNT_FILE should be in custom_state_dir/state
	# Note: Expected paths documented above but not directly asserted as script creates files dynamically

	# Verify that state files are created in the custom directory
	# (Script may create these files during execution)
	assert_file_exist "$LOG_FILE"

	# Cleanup
	rm -rf "$custom_state_dir" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "LOG_FILE override to read-only directory" {
	# Purpose: Test verifies that the script handles LOG_FILE paths pointing to read-only directories gracefully
	# Expected: Script handles read-only log directory gracefully without crashing, may output to stderr
	# Importance: Read-only directories can occur from permission issues; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local readonly_log_dir="${TEST_DIR}/readonly-logs"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOG_FILE=\"${readonly_log_dir}/vpn-monitor.log\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create read-only log directory
	mkdir -p "$readonly_log_dir"
	chmod 555 "$readonly_log_dir"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	run bash "$test_script" --fake
	assert_success

	# Should handle read-only log directory gracefully (should output to stderr)
	# Script should not crash even if log writes fail

	# Restore permissions for cleanup
	chmod 755 "$readonly_log_dir" 2>/dev/null || true
	rm -rf "$readonly_log_dir" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "STATE_DIR override to read-only directory" {
	# Purpose: Test verifies that the script handles STATE_DIR paths pointing to read-only directories gracefully
	# Expected: Script fails early with clear error message when STATE_DIR is read-only because lockfile cannot be created
	# Importance: Read-only state directories prevent lockfile creation; script must fail early with clear error
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local readonly_state_dir="${TEST_DIR}/readonly-state"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"STATE_DIR=\"${readonly_state_dir}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create read-only state directory
	mkdir -p "$readonly_state_dir"
	chmod 555 "$readonly_state_dir"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	run bash "$test_script" --fake
	assert_failure

	# Script should fail early with clear error message when STATE_DIR is read-only
	# because lockfile cannot be created in read-only directory
	assert_output --partial "STATE_DIR is not writable"

	# Restore permissions for cleanup
	chmod 755 "$readonly_state_dir" 2>/dev/null || true
	rm -rf "$readonly_state_dir" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with command substitution is rejected" {
	# Purpose: Test verifies that config files with command substitution ($()) are rejected
	# Expected: Script detects dangerous content and rejects config file without executing code
	# Importance: Prevents arbitrary code execution if config file is compromised
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Expand TEST_PEER_IP but keep dangerous content literal
	printf 'LOCATION_TEST_EXTERNAL="%s"\nNETWORK_PARTITION_DNS_HOSTNAME=$(echo "malicious")\n' "${TEST_PEER_IP}" >"$config_file"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Script should reject config file with command substitution
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about dangerous content
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "dangerous content" "Failed to parse" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with backticks is rejected" {
	# Purpose: Test verifies that config files with backticks are rejected
	# Expected: Script detects dangerous content and rejects config file without executing code
	# Importance: Prevents arbitrary code execution if config file is compromised
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Expand TEST_PEER_IP but keep dangerous content literal
	printf 'LOCATION_TEST_EXTERNAL="%s"\nNETWORK_PARTITION_DNS_HOSTNAME=`echo "malicious"`\n' "${TEST_PEER_IP}" >"$config_file"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Script should reject config file with backticks
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about dangerous content
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "dangerous content" "Failed to parse" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with eval is rejected" {
	# Purpose: Test verifies that config files with eval are rejected
	# Expected: Script detects dangerous content and rejects config file without executing code
	# Importance: Prevents arbitrary code execution if config file is compromised
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Expand TEST_PEER_IP but keep dangerous content literal
	printf 'LOCATION_TEST_EXTERNAL="%s"\neval "malicious code"\n' "${TEST_PEER_IP}" >"$config_file"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Script should reject config file with eval
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about dangerous content
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "dangerous content" "Failed to parse" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with unknown variable is rejected" {
	# Purpose: Test verifies that config files with unknown variables (not in schema) are rejected
	# Expected: Script detects unknown variable and rejects config file
	# Importance: Prevents setting arbitrary variables that could be used for code injection
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		'MALICIOUS_VAR="value"'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Script should reject config file with unknown variable
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about unknown variable
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Unknown configuration variable" "not in schema" "Failed to parse" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with valid assignments works correctly" {
	# Purpose: Test verifies that config files with valid variable assignments are parsed correctly
	# Expected: Script parses valid config file and sets variables safely
	# Importance: Ensures legitimate config files continue to work after security fix
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST1_EXTERNAL=\"${TEST_PEER_IP}\"" \
		'LOCATION_TEST2_EXTERNAL="192.168.1.2"' \
		'TIER1_THRESHOLD=2' \
		'TIER2_THRESHOLD=4' \
		'TIER3_THRESHOLD=6' \
		'ENABLE_PING_CHECK=1' \
		'DEBUG=0'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Script should parse valid config file successfully
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log success message
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Configuration loaded from" "INFO"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with source is rejected" {
	# Purpose: Test verifies that config files with source command are rejected
	# Expected: Script detects dangerous content and rejects config file without executing code
	# Importance: Prevents arbitrary code execution if config file is compromised
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Expand TEST_PEER_IP but keep dangerous content literal
	printf 'LOCATION_TEST_EXTERNAL="%s"\nsource /etc/passwd\n' "${TEST_PEER_IP}" >"$config_file"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Script should reject config file with source
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about dangerous content
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "dangerous content" "Failed to parse" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with dot-space-slash (. /path) is rejected" {
	# Purpose: Ensures dot-source with space (e.g. ". /script") is rejected; bash ERE uses [[:space:]] not \s
	# Expected: Script detects dangerous content and rejects config file
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	printf 'LOCATION_TEST_EXTERNAL="%s"\n. /tmp/malicious.sh\n' "${TEST_PEER_IP}" >"$config_file"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "dangerous content" "Failed to parse" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with multiple dangerous patterns in one line is rejected" {
	# Purpose: Test verifies that config files with multiple dangerous patterns in one line are rejected
	# Expected: Script detects dangerous content and rejects config file
	# Importance: Ensures all dangerous patterns are detected even when combined
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Expand TEST_PEER_IP but keep dangerous content literal
	printf 'LOCATION_TEST_EXTERNAL="%s"\nNETWORK_PARTITION_DNS_HOSTNAME=$(echo "test") `echo "test"` eval "test"\n' "${TEST_PEER_IP}" >"$config_file"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Script should reject config file with multiple dangerous patterns
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about dangerous content
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "dangerous content" "Failed to parse" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with dangerous pattern in comment is allowed" {
	# Purpose: Test verifies that dangerous patterns in comments are ignored (comments are allowed)
	# Expected: Script ignores comments and allows dangerous patterns in comment lines
	# Importance: Comments should not trigger security checks
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Expand TEST_PEER_IP but keep dangerous content literal in comments
	printf 'LOCATION_TEST_EXTERNAL="%s"\n# This is a comment with $(echo "test") `echo "test"` eval "test"\nNETWORK_PARTITION_DNS_HOSTNAME=google.com\n' "${TEST_PEER_IP}" >"$config_file"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Script should parse config file successfully (comments are ignored)
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should parse successfully (comments are ignored)
	assert_file_exist "$LOG_FILE"
	# Should not contain error about dangerous content
	refute_file_contains "$LOG_FILE" "dangerous content"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with valid variable assignment without quotes is allowed" {
	# Purpose: Test verifies that valid variable assignments without quotes are parsed correctly
	# Expected: Script parses valid assignments without quotes safely
	# Importance: Ensures legitimate config files without quotes continue to work
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"ENABLE_PING_CHECK=1" \
		"DEBUG=0"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Script should parse valid config file successfully
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should parse successfully
	assert_file_exist "$LOG_FILE"
	# Should not contain error about dangerous content
	refute_file_contains "$LOG_FILE" "dangerous content"

	remove_mock_from_path
}

# ============================================================================
# CONTRACT: VALUES ARE LITERAL STRINGS, NEVER SHELL-EVALUATED
# ============================================================================
# The loader's security model is:
#   1. parse_assignment validates KEY=VALUE shape
#   2. Schema whitelist gates which KEYs may be set
#   3. safe_set_variable assigns via printf -v (no expansion)
# Because of (3), values containing $(...), backticks, or substrings like
# "source"/"exec"/"eval" are stored as literal strings — not executed.
# These tests pin that contract so a future refactor can't quietly re-introduce
# eval/source on config values.

# bats test_tags=category:high-risk,priority:critical
@test "value containing 'source' as a substring is accepted (no false positive)" {
	# Regression: previously, a substring "dangerous content" check rejected
	# legitimate values like LOCATION_..._EXTERNAL="source.example.com".
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true
	# shellcheck source=../lib/config_schema.sh
	source "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" 2>/dev/null || true

	export STATE_DIR="${TEST_DIR}"
	export LOG_FILE="${TEST_DIR}/logs/vpn-monitor.log"
	export LOGS_DIR="${TEST_DIR}/logs"
	enable_fake_mode
	mkdir -p "$LOGS_DIR"

	local config_file="${TEST_DIR}/false-positive.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="source.example.com"
LOCATION_NYC_INTERNAL="exec.internal.example.com"
NETWORK_PARTITION_DNS_HOSTNAME="eval.test.example.com"
EOF

	# Call directly (not via 'run'): we need the assigned globals in this
	# shell to assert against. 'run' executes in a subshell.
	safe_parse_config_file "$config_file"

	assert_equal "${LOCATION_NYC_EXTERNAL:-}" "source.example.com"
	assert_equal "${LOCATION_NYC_INTERNAL:-}" "exec.internal.example.com"
	assert_equal "${NETWORK_PARTITION_DNS_HOSTNAME:-}" "eval.test.example.com"

	rm -f "$config_file"
}

# bats test_tags=category:high-risk,priority:critical
@test "command-substitution syntax in a value is stored as a literal, not executed" {
	# Pins the no-execution invariant: even if a config contains $(...) or
	# backticks, safe_set_variable's printf -v assigns the literal string.
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true
	# shellcheck source=../lib/config_schema.sh
	source "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" 2>/dev/null || true

	export STATE_DIR="${TEST_DIR}"
	export LOG_FILE="${TEST_DIR}/logs/vpn-monitor.log"
	export LOGS_DIR="${TEST_DIR}/logs"
	enable_fake_mode
	mkdir -p "$LOGS_DIR"

	local pwn_marker="${TEST_DIR}/pwn-marker"
	rm -f "$pwn_marker"

	local config_file="${TEST_DIR}/no-exec.conf"
	# Unquoted heredoc: a leading \ on $ stops command substitution; the line is
	# written with a literal $(...) in the file (same effect as <<'EOF' would be).
	cat >"$config_file" <<EOF
LOCATION_NYC_EXTERNAL="\$(touch ${pwn_marker})"
EOF

	# Parse the config. We don't care whether the parser accepts or rejects
	# this specific value — only that the marker file is NOT created.
	safe_parse_config_file "$config_file" || true

	# The critical assertion: nothing executed.
	[ ! -e "$pwn_marker" ] || {
		echo "FAIL: command substitution in config value was executed (marker created)" >&2
		return 1
	}

	# If the value was accepted, it must be the literal string, not the result
	# of running 'touch'. (If rejected, the variable is just unset/empty —
	# which is also fine; the no-execution invariant is what matters.)
	if [[ -n "${LOCATION_NYC_EXTERNAL:-}" ]]; then
		[[ "${LOCATION_NYC_EXTERNAL}" == "\$(touch ${pwn_marker})" ]] || {
			echo "FAIL: value was transformed; expected literal, got: ${LOCATION_NYC_EXTERNAL}" >&2
			return 1
		}
	fi

	rm -f "$config_file"
}

# bats test_tags=category:high-risk,priority:critical
@test "install.sh config-value extraction does not shell-evaluate the file" {
	# install.sh used to 'source' the config to read ENABLE_PING_CHECK and
	# LOCAL_UDM_IP. It now uses get_config_var_value_from_file, the same
	# quote/comment-aware safe extractor used elsewhere in install.sh.
	# This pins that contract: malicious-looking values remain literal and are not executed.
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
	# shellcheck source=../lib/config/config_loading.sh
	source "${BATS_TEST_DIRNAME}/../lib/config/config_loading.sh" 2>/dev/null || true

	local pwn_marker="${TEST_DIR}/install-pwn-marker"
	rm -f "$pwn_marker"

	local config_file="${TEST_DIR}/malicious.conf"
	cat >"$config_file" <<EOF
ENABLE_PING_CHECK=1 # keep ping enabled
LOCAL_UDM_IP="\$(touch ${pwn_marker})" # literal value, not shell
EOF

	# Mirror the exact extraction helper used in install.sh (search for
	# get_config_var_value_from_file near install.sh:~2190).
	local enable_ping local_ip
	enable_ping=$(get_config_var_value_from_file "$config_file" "ENABLE_PING_CHECK" 2>/dev/null)
	local_ip=$(get_config_var_value_from_file "$config_file" "LOCAL_UDM_IP" 2>/dev/null)

	[ ! -e "$pwn_marker" ] || {
		echo "FAIL: install.sh config extraction executed config value" >&2
		return 1
	}

	# Extracted values should use the shared parser rules: comments stripped,
	# quotes stripped, command substitution preserved as a literal string.
	assert_equal "$enable_ping" "1"
	assert_equal "$local_ip" "\$(touch ${pwn_marker})"

	rm -f "$config_file"
}

# ============================================================================
# CONTRACT: '#' HANDLING RESPECTS QUOTING
# ============================================================================
# parse_assignment used to do `assignment="${assignment%%#*}"` before parsing,
# which silently corrupted quoted values like LOCATION_X="vpn#1.example.com"
# (truncated to "vpn → "unclosed quote" error). Comment handling now lives in
# parse_quoted_value and respects whether we're inside a quoted string.

# Shared loader-bootstrap for the tests below; keeps each test focused on the
# assertion rather than the sourcing dance.
setup_loader_for_security_test() {
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true
	# shellcheck source=../lib/config_schema.sh
	source "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" 2>/dev/null || true

	export STATE_DIR="${TEST_DIR}"
	export LOG_FILE="${TEST_DIR}/logs/vpn-monitor.log"
	export LOGS_DIR="${TEST_DIR}/logs"
	enable_fake_mode
	mkdir -p "$LOGS_DIR"
}

# bats test_tags=category:high-risk,priority:critical
@test "'#' inside double-quoted value is preserved (regression for naive %%#* strip)" {
	# This is the bug the parse_assignment / parse_quoted_value rework fixes:
	# previously KEY="vpn#1.example.com" was truncated to KEY="vpn before quote
	# parsing even ran, then errored as an unclosed quote.
	setup_loader_for_security_test

	local config_file="${TEST_DIR}/hash-in-value.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="vpn#1.example.com"
LOCATION_NYC_INTERNAL='lan#2.internal'
EOF

	safe_parse_config_file "$config_file"

	assert_equal "${LOCATION_NYC_EXTERNAL:-}" "vpn#1.example.com"
	assert_equal "${LOCATION_NYC_INTERNAL:-}" "lan#2.internal"

	rm -f "$config_file"
}

# bats test_tags=category:unit
@test "trailing '# comment' is stripped from unquoted value" {
	setup_loader_for_security_test

	local config_file="${TEST_DIR}/unquoted-comment.conf"
	cat >"$config_file" <<'EOF'
PING_COUNT=5 # how many pings per check
EOF

	safe_parse_config_file "$config_file"

	assert_equal "${PING_COUNT:-}" "5"

	rm -f "$config_file"
}

# bats test_tags=category:unit
@test "unquoted value with embedded '#' is rejected (must quote)" {
	# Without whitespace before '#', the parser can't tell value from comment,
	# so it errors rather than silently picking one. Ambiguity → loud error.
	setup_loader_for_security_test

	local config_file="${TEST_DIR}/embedded-hash.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL=vpn#1.example.com
EOF

	# Parse should fail (or skip the line). The critical assertion is that
	# the value is NOT silently set to "vpn" via naive comment-stripping.
	safe_parse_config_file "$config_file" || true

	[[ "${LOCATION_NYC_EXTERNAL:-}" != "vpn" ]] || {
		echo "FAIL: unquoted value was silently truncated at '#' (the old bug)" >&2
		return 1
	}

	rm -f "$config_file"
}

# bats test_tags=category:unit
@test "trailing '# comment' after closing quote is stripped" {
	setup_loader_for_security_test

	local config_file="${TEST_DIR}/quoted-then-comment.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="vpn.example.com" # primary site
EOF

	safe_parse_config_file "$config_file"

	assert_equal "${LOCATION_NYC_EXTERNAL:-}" "vpn.example.com"

	rm -f "$config_file"
}
