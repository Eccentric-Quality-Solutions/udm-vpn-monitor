#!/usr/bin/env bash
#
# Helpers for tests/test_anonymize.sh — shared assertion patterns for
# scripts/anonymize/*.sh CLIs (help, missing input, diff consistency, etc.).
#
# Usage:
#   load test_helper
#   load helpers/anonymize
#
# Requires bats-assert (via test_helper).

# Assert script path exists and is executable
#
# Arguments:
#   $1: script path
#
# Returns:
#   0: assertions pass
#   1: assertion failure (bats)
anonymize_assert_script_exists_executable() {
	assert_file_exist "$1"
	assert_file_executable "$1"
}

# After `run`, assert success and that combined output contains each substring
#
# Arguments:
#   $@: partial strings (assert_output --partial each)
#
# Returns:
#   0: success
#   1: failure
anonymize_assert_success_with_output_partials() {
	assert_success
	local p
	for p in "$@"; do
		assert_output --partial "$p"
	done
}

# After `run`, assert success and that a line matches each partial (stderr-friendly)
#
# Arguments:
#   $@: partial strings (assert_line --partial each)
#
# Returns:
#   0: success
#   1: failure
anonymize_assert_success_with_line_partials() {
	assert_success
	local p
	for p in "$@"; do
		assert_line --partial "$p"
	done
}

# Run bash SCRIPT --help; assert Usage, script name substring, and option strings
#
# Arguments:
#   $1: script path
#   $2: basename substring expected in help (e.g. anonymize-ipset.sh)
#   $3+: additional required substrings (--input, etc.)
#
# Returns:
#   0: success
#   1: failure
anonymize_assert_help() {
	local script_path="$1"
	local name_partial="$2"
	shift 2
	run bash "$script_path" --help
	assert_success
	assert_output --partial "Usage:"
	assert_output --partial "$name_partial"
	local p
	for p in "$@"; do
		assert_output --partial "$p"
	done
}

# Run bash SCRIPT -h; assert Usage appears
#
# Arguments:
#   $1: script path
#
# Returns:
#   0: success
#   1: failure
anonymize_assert_help_h() {
	local script_path="$1"
	run bash "$script_path" -h
	assert_success
	assert_output --partial "Usage:"
}

# Missing input file: expect failure and standard message
#
# Arguments:
#   $1: script path
#   $2: nonexistent path for -i
#
# Returns:
#   0: success
#   1: failure
anonymize_assert_input_file_not_found() {
	local script_path="$1"
	local bad_path="$2"
	run bash "$script_path" -i "$bad_path"
	assert_failure
	assert_output --partial "Input file not found"
}

# Input exists but is unreadable (chmod 000), then restored to 644
#
# Arguments:
#   $1: script path
#   $2: file path to create
#
# Returns:
#   0: success
#   1: failure
anonymize_assert_input_file_unreadable() {
	local script_path="$1"
	local input_file="$2"
	mkdir -p "$(dirname "$input_file")"
	touch "$input_file"
	chmod 000 "$input_file"
	run bash "$script_path" -i "$input_file"
	chmod 644 "$input_file" || true
	assert_failure
	assert_output --partial "Input file not readable"
}

# Script invoked with no -i where required
#
# Arguments:
#   $1: script path
#
# Returns:
#   0: success
#   1: failure
anonymize_assert_input_file_required() {
	local script_path="$1"
	run bash "$script_path"
	assert_failure
	assert_output --partial "Input file is required"
}

# Byte-identical files (typical duplicate-run check)
#
# Arguments:
#   $1, $2: file paths
#
# Returns:
#   0: success
#   1: failure
anonymize_assert_files_identical() {
	local a="$1"
	local b="$2"
	run diff "$a" "$b"
	assert_success
	assert_output ""
}

# -o must not equal -i
#
# Arguments:
#   $1: script path
#   $2: existing input file
#
# Returns:
#   0: success
#   1: failure
anonymize_assert_output_path_same_as_input_fails() {
	local script_path="$1"
	local input_path="$2"
	run bash "$script_path" -i "$input_path" -o "$input_path"
	assert_failure
	assert_output --partial "Output file cannot be the same as input file"
}

# No line in file may match extended regex (leak / absence check)
#
# Arguments:
#   $1: file path
#   $2: extended regex for grep -E
#
# Returns:
#   0: success
#   1: failure
anonymize_assert_eregex_no_line_in_file() {
	local f="$1"
	local re="$2"
	run grep -E "$re" "$f" || true
	assert_output ""
}
