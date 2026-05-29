#!/usr/bin/env bats
#
# Tests for regex helper functions in lib/common.sh and list_config_variable_names

load test_helper
load helpers/config

# shellcheck source=../lib/common.sh
source "${BATS_TEST_DIRNAME}/../lib/common.sh"
# shellcheck source=../lib/logging.sh
source "${BATS_TEST_DIRNAME}/../lib/logging.sh"
# shellcheck source=../lib/config/config_loading.sh
source "${BATS_TEST_DIRNAME}/../lib/config/config_loading.sh"

# bats test_tags=category:unit
@test "is_config_comment_line accepts bare and indented comments" {
	run is_config_comment_line "# comment"
	assert_success
	run is_config_comment_line "  # comment"
	assert_success
	run is_config_comment_line "VAR=value"
	assert_failure
}

# bats test_tags=category:unit
@test "config_value_needs_quoting detects whitespace and quotes" {
	run config_value_needs_quoting "hello world"
	assert_success
	run config_value_needs_quoting "say\"hi"
	assert_success
	run config_value_needs_quoting "plain_value"
	assert_failure
}

# bats test_tags=category:unit
@test "is_positive_integer rejects zero and non-digits" {
	run is_positive_integer "3"
	assert_success
	run is_positive_integer "0"
	assert_failure
	run is_positive_integer "abc"
	assert_failure
}

# bats test_tags=category:unit
@test "is_binary_flag accepts only 0 and 1" {
	run is_binary_flag "0"
	assert_success
	run is_binary_flag "1"
	assert_success
	run is_binary_flag "2"
	assert_failure
}

# bats test_tags=category:unit
@test "parse_script_version_line extracts quoted and unquoted values" {
	local v
	v=$(parse_script_version_line 'SCRIPT_VERSION="1.2.3"')
	[[ "$v" == "1.2.3" ]]
	v=$(parse_script_version_line "SCRIPT_VERSION='4.5.6'")
	[[ "$v" == "4.5.6" ]]
	run parse_script_version_line 'PING_COUNT=5'
	assert_failure
}

# bats test_tags=category:unit
@test "extract_script_version reads from file" {
	local f="${TEST_DIR}/versioned.sh"
	echo 'SCRIPT_VERSION="9.8.7"' >"$f"
	run extract_script_version "$f"
	assert_success
	assert_output "9.8.7"
}

# bats test_tags=category:unit
@test "extract_file_version_comment reads header comment" {
	local f="${TEST_DIR}/lib_sample.sh"
	echo '# Version: 0.1.2' >"$f"
	run extract_file_version_comment "$f"
	assert_success
	assert_output "0.1.2"
}

# bats test_tags=category:unit
@test "build_xfrm grep patterns escape peer IP dots" {
	local pattern
	pattern=$(build_xfrm_forward_dst_grep_pattern "192.168.1.1")
	[[ "$pattern" == *'192\.168\.1\.1'* ]]
	pattern=$(build_xfrm_reverse_src_grep_pattern "10.0.0.2")
	[[ "$pattern" == *'10\.0\.0\.2'* ]]
}

# bats test_tags=category:unit
@test "list_config_variable_names skips comments and invalid lines" {
	local cf="${TEST_DIR}/vars.conf"
	cat >"$cf" <<'EOF'
# comment
PING_COUNT=5
INVALID=bad#token
ENABLE_PING_CHECK=1
EOF
	local out
	out=$(list_config_variable_names "$cf")
	[[ "$out" == *$'PING_COUNT\nENABLE_PING_CHECK'* ]]
	[[ "$out" != *INVALID* ]]
}

# bats test_tags=category:unit
@test "list_malformed_config_lines reports assignment-looking lines that fail to parse" {
	local cf="${TEST_DIR}/malformed.conf"
	cat >"$cf" <<'EOF'
# comment
GOOD=5
BAD_SPACES=value with spaces
GOOD_QUOTED="value with spaces"
BAD_HASH=foo#bar
not an assignment line
EOF
	local out
	out=$(list_malformed_config_lines "$cf")
	# Reports the malformed value lines with their 1-based line numbers
	[[ "$out" == *"3:BAD_SPACES=value with spaces"* ]]
	[[ "$out" == *"5:BAD_HASH=foo#bar"* ]]
	# Does not report comments, valid lines (quoted or not), or non-assignment junk
	[[ "$out" != *GOOD* ]]
	[[ "$out" != *"not an assignment"* ]]
}

# bats test_tags=category:unit
@test "list_malformed_config_lines returns 1 for a missing file" {
	run list_malformed_config_lines "${TEST_DIR}/does-not-exist.conf"
	assert_failure
}
