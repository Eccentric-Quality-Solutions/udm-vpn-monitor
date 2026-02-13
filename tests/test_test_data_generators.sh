#!/usr/bin/env bats
#
# Tests for Test Data Generator Functions
#
# Tests the test data generator functions in tests/helpers/test_data.bash:
# - generate_xfrm_state_for_scenario() - all scenarios and formats
# - generate_config_file() - all template types
# - load_test_data_file() - success and error handling

load test_helper
load helpers/test_data

# ============================================================================
# generate_xfrm_state_for_scenario() Tests
# ============================================================================

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_xfrm_state_for_scenario - healthy scenario with defaults" {
	# Purpose: Verify generate_xfrm_state_for_scenario produces correct output for healthy scenario with default values
	# Expected: Output contains peer IP, SPI, and default healthy byte/packet counters
	local peer_ip="${TEST_PEER_IP}"
	local spi="0x12345678"
	local output
	output=$(generate_xfrm_state_for_scenario "healthy" "$peer_ip" "$spi")

	# Verify output contains expected elements
	assert_output --partial "src ${peer_ip} dst ${peer_ip}"
	assert_output --partial "proto esp spi ${spi}"
	assert_output --partial "lifetime current:"
	# Default healthy bytes should be 1000 (or from env var)
	assert_output --regexp "(1000|${XFRM_STATE_HEALTHY_BYTES:-1000}) bytes"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_xfrm_state_for_scenario - healthy scenario with overridden values" {
	# Purpose: Verify generate_xfrm_state_for_scenario allows overriding default values for healthy scenario
	# Expected: Output uses provided byte and packet counters instead of defaults
	local peer_ip="${TEST_PEER_IP}"
	local spi="0x12345678"
	local custom_bytes=5000
	local custom_packets=50
	local output
	output=$(generate_xfrm_state_for_scenario "healthy" "$peer_ip" "$spi" "$custom_bytes" "$custom_packets")

	# Verify output uses custom values
	assert_output --partial "${custom_bytes} bytes"
	assert_output --partial "${custom_packets} packets"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_xfrm_state_for_scenario - idle scenario with defaults" {
	# Purpose: Verify generate_xfrm_state_for_scenario produces correct output for idle scenario
	# Expected: Output contains zero byte and packet counters
	local peer_ip="${TEST_PEER_IP}"
	local spi="0x12345678"
	local output
	output=$(generate_xfrm_state_for_scenario "idle" "$peer_ip" "$spi")

	# Verify output contains zero counters (or from env var)
	assert_output --regexp "(0|${XFRM_STATE_IDLE_BYTES:-0}) bytes"
	assert_output --regexp "(0|${XFRM_STATE_IDLE_PACKETS:-0}) packets"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_xfrm_state_for_scenario - idle scenario with overridden values" {
	# Purpose: Verify generate_xfrm_state_for_scenario allows overriding values for idle scenario
	# Expected: Output uses provided values even for idle scenario
	local peer_ip="${TEST_PEER_IP}"
	local spi="0x12345678"
	local custom_bytes=100
	local custom_packets=5
	local output
	output=$(generate_xfrm_state_for_scenario "idle" "$peer_ip" "$spi" "$custom_bytes" "$custom_packets")

	# Verify output uses custom values
	assert_output --partial "${custom_bytes} bytes"
	assert_output --partial "${custom_packets} packets"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_xfrm_state_for_scenario - failing scenario with defaults" {
	# Purpose: Verify generate_xfrm_state_for_scenario produces correct output for failing scenario
	# Expected: Output contains default failing byte/packet counters
	local peer_ip="${TEST_PEER_IP}"
	local spi="0x12345678"
	local output
	output=$(generate_xfrm_state_for_scenario "failing" "$peer_ip" "$spi")

	# Verify output contains expected counters (or from env var)
	assert_output --regexp "(1000|${XFRM_STATE_FAILING_BYTES:-1000}) bytes"
	assert_output --regexp "(10|${XFRM_STATE_FAILING_PACKETS:-10}) packets"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_xfrm_state_for_scenario - failing scenario with overridden values" {
	# Purpose: Verify generate_xfrm_state_for_scenario allows overriding values for failing scenario
	# Expected: Output uses provided values
	local peer_ip="${TEST_PEER_IP}"
	local spi="0x12345678"
	local custom_bytes=2000
	local custom_packets=20
	local output
	output=$(generate_xfrm_state_for_scenario "failing" "$peer_ip" "$spi" "$custom_bytes" "$custom_packets")

	# Verify output uses custom values
	assert_output --partial "${custom_bytes} bytes"
	assert_output --partial "${custom_packets} packets"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_xfrm_state_for_scenario - custom scenario with defaults" {
	# Purpose: Verify generate_xfrm_state_for_scenario produces correct output for custom scenario with defaults
	# Expected: Output uses default custom values (1000 bytes, 10 packets)
	local peer_ip="${TEST_PEER_IP}"
	local spi="0x12345678"
	local output
	output=$(generate_xfrm_state_for_scenario "custom" "$peer_ip" "$spi")

	# Verify output contains default custom values
	assert_output --partial "1000 bytes"
	assert_output --partial "10 packets"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_xfrm_state_for_scenario - custom scenario with provided values" {
	# Purpose: Verify generate_xfrm_state_for_scenario uses provided values for custom scenario
	# Expected: Output uses provided byte and packet counters
	local peer_ip="${TEST_PEER_IP}"
	local spi="0x12345678"
	local custom_bytes=7500
	local custom_packets=75
	local output
	output=$(generate_xfrm_state_for_scenario "custom" "$peer_ip" "$spi" "$custom_bytes" "$custom_packets")

	# Verify output uses provided values
	assert_output --partial "${custom_bytes} bytes"
	assert_output --partial "${custom_packets} packets"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_xfrm_state_for_scenario - unknown scenario returns error" {
	# Purpose: Verify generate_xfrm_state_for_scenario handles unknown scenario correctly
	# Expected: Function returns error code and prints error message
	local peer_ip="${TEST_PEER_IP}"
	local spi="0x12345678"
	run generate_xfrm_state_for_scenario "unknown_scenario" "$peer_ip" "$spi"

	# Verify function fails
	assert_failure
	# Verify error message is printed
	assert_output --partial "Unknown scenario: unknown_scenario"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_xfrm_state_for_scenario - full format (default)" {
	# Purpose: Verify generate_xfrm_state_for_scenario produces full format output by default
	# Expected: Output includes all fields (replay-window, auth-trunc, enc, lifetime details)
	local peer_ip="${TEST_PEER_IP}"
	local spi="0x12345678"
	local output
	output=$(generate_xfrm_state_for_scenario "healthy" "$peer_ip" "$spi" "" "" "full")

	# Verify full format includes additional fields
	assert_output --partial "replay-window"
	assert_output --partial "auth-trunc"
	assert_output --partial "enc"
	assert_output --partial "lifetime hard"
	assert_output --partial "lifetime soft"
	assert_output --partial "current use"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_xfrm_state_for_scenario - minimal format" {
	# Purpose: Verify generate_xfrm_state_for_scenario produces minimal format output when requested
	# Expected: Output contains only essential fields (no replay-window, auth-trunc, etc.)
	local peer_ip="${TEST_PEER_IP}"
	local spi="0x12345678"
	local output
	output=$(generate_xfrm_state_for_scenario "healthy" "$peer_ip" "$spi" "" "" "minimal")

	# Verify minimal format excludes extra fields
	assert_output --partial "src ${peer_ip} dst ${peer_ip}"
	assert_output --partial "proto esp spi ${spi}"
	assert_output --partial "lifetime current:"
	# Minimal format should NOT include these fields
	refute_output --partial "replay-window"
	refute_output --partial "auth-trunc"
	refute_output --partial "enc"
	refute_output --partial "lifetime hard"
	refute_output --partial "lifetime soft"
	refute_output --partial "current use"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_xfrm_state_for_scenario - environment variable defaults" {
	# Purpose: Verify generate_xfrm_state_for_scenario respects environment variable defaults
	# Expected: Output uses environment variable values when set
	local peer_ip="${TEST_PEER_IP}"
	local spi="0x12345678"
	export XFRM_STATE_HEALTHY_BYTES=2500
	export XFRM_STATE_HEALTHY_PACKETS=25
	local output
	output=$(generate_xfrm_state_for_scenario "healthy" "$peer_ip" "$spi")

	# Verify output uses environment variable values
	assert_output --partial "2500 bytes"
	assert_output --partial "25 packets"

	# Clean up
	unset XFRM_STATE_HEALTHY_BYTES
	unset XFRM_STATE_HEALTHY_PACKETS
}

# ============================================================================
# generate_config_file() Tests
# ============================================================================

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_config_file - minimal template" {
	# Purpose: Verify generate_config_file creates minimal config file correctly
	# Expected: Config file contains only LOCATION_EXTERNAL and LOCATION_INTERNAL
	local config_file="${BATS_TEST_TMPDIR}/test_minimal.conf"
	local peer_ip="${TEST_PEER_IP}"
	generate_config_file "minimal" "$config_file" "$peer_ip"

	# Verify file was created
	assert_file_exist "$config_file"
	# Verify file contains expected content
	assert_file_contains "$config_file" "LOCATION_TEST_EXTERNAL=\"${peer_ip}\""
	assert_file_contains "$config_file" "LOCATION_TEST_INTERNAL=\"${peer_ip}\""
	# Verify file doesn't contain extra fields
	refute_file_contains "$config_file" "PING_COUNT"
	refute_file_contains "$config_file" "TIER1_THRESHOLD"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_config_file - minimal template with internal IP" {
	# Purpose: Verify generate_config_file minimal template accepts separate internal IP
	# Expected: Config file uses provided internal IP
	local config_file="${BATS_TEST_TMPDIR}/test_minimal_internal.conf"
	local peer_ip="${TEST_PEER_IP}"
	local internal_ip="${TEST_LOCAL_IP}"
	generate_config_file "minimal" "$config_file" "$peer_ip" "$internal_ip"

	# Verify file uses provided internal IP
	assert_file_contains "$config_file" "LOCATION_TEST_EXTERNAL=\"${peer_ip}\""
	assert_file_contains "$config_file" "LOCATION_TEST_INTERNAL=\"${internal_ip}\""
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_config_file - standard template" {
	# Purpose: Verify generate_config_file creates standard config file correctly
	# Expected: Config file contains all standard configuration fields
	local config_file="${BATS_TEST_TMPDIR}/test_standard.conf"
	local peer_ip="${TEST_PEER_IP}"
	generate_config_file "standard" "$config_file" "$peer_ip"

	# Verify file was created
	assert_file_exist "$config_file"
	# Verify file contains expected standard fields
	assert_file_contains "$config_file" "LOCATION_TEST_EXTERNAL=\"${peer_ip}\""
	assert_file_contains "$config_file" "LOCATION_TEST_INTERNAL=\"${peer_ip}\""
	assert_file_contains "$config_file" "PING_COUNT=3"
	assert_file_contains "$config_file" "TIER1_THRESHOLD=1"
	assert_file_contains "$config_file" "TIER2_THRESHOLD=3"
	assert_file_contains "$config_file" "TIER3_THRESHOLD=5"
	assert_file_contains "$config_file" "MAX_RESTARTS_PER_WINDOW=20"
	assert_file_contains "$config_file" "LOG_FILE="
	assert_file_contains "$config_file" "STATE_DIR="
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_config_file - standard template with internal IP" {
	# Purpose: Verify generate_config_file standard template accepts internal IP parameter
	# Expected: Config file uses provided parameters
	local config_file="${BATS_TEST_TMPDIR}/test_standard_internal.conf"
	local peer_ip="${TEST_PEER_IP}"
	local internal_ip="192.168.1.100"
	generate_config_file "standard" "$config_file" "$peer_ip" "$internal_ip"

	# Verify file contains location config with both external and internal IPs
	assert_file_contains "$config_file" "LOCATION_TEST_EXTERNAL"
	assert_file_contains "$config_file" "LOCATION_TEST_INTERNAL"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_config_file - custom_log template" {
	# Purpose: Verify generate_config_file creates custom_log config file correctly
	# Expected: Config file contains LOCATION fields and custom LOG_FILE
	local config_file="${BATS_TEST_TMPDIR}/test_custom_log.conf"
	local peer_ip="${TEST_PEER_IP}"
	local log_file="/tmp/custom-test.log"
	generate_config_file "custom_log" "$config_file" "$peer_ip" "$log_file"

	# Verify file was created
	assert_file_exist "$config_file"
	# Verify file contains expected fields
	assert_file_contains "$config_file" "LOCATION_TEST_EXTERNAL=\"${peer_ip}\""
	assert_file_contains "$config_file" "LOCATION_TEST_INTERNAL=\"${peer_ip}\""
	assert_file_contains "$config_file" "LOG_FILE=\"${log_file}\""
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_config_file - custom_log template with internal IP" {
	# Purpose: Verify generate_config_file custom_log template accepts internal IP
	# Expected: Config file uses provided internal IP
	local config_file="${BATS_TEST_TMPDIR}/test_custom_log_internal.conf"
	local peer_ip="${TEST_PEER_IP}"
	local log_file="/tmp/custom-test.log"
	local internal_ip="${TEST_LOCAL_IP}"
	generate_config_file "custom_log" "$config_file" "$peer_ip" "$log_file" "$internal_ip"

	# Verify file uses provided internal IP
	assert_file_contains "$config_file" "LOCATION_TEST_EXTERNAL=\"${peer_ip}\""
	assert_file_contains "$config_file" "LOCATION_TEST_INTERNAL=\"${internal_ip}\""
	assert_file_contains "$config_file" "LOG_FILE=\"${log_file}\""
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_config_file - multiple_locations template" {
	# Purpose: Verify generate_config_file creates multiple_locations config file correctly
	# Expected: Config file contains two location pairs
	local config_file="${BATS_TEST_TMPDIR}/test_multiple_locations.conf"
	local peer_ip1="${TEST_PEER_IP}"
	local peer_ip2="${TEST_PEER_IP2}"
	generate_config_file "multiple_locations" "$config_file" "$peer_ip1" "$peer_ip1" "$peer_ip2" "$peer_ip2"

	# Verify file was created
	assert_file_exist "$config_file"
	# Verify file contains both locations
	assert_file_contains "$config_file" "LOCATION_TEST_EXTERNAL=\"${peer_ip1}\""
	assert_file_contains "$config_file" "LOCATION_TEST_INTERNAL=\"${peer_ip1}\""
	assert_file_contains "$config_file" "LOCATION_TEST2_EXTERNAL=\"${peer_ip2}\""
	assert_file_contains "$config_file" "LOCATION_TEST2_INTERNAL=\"${peer_ip2}\""
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_config_file - multiple_locations template with different internal IPs" {
	# Purpose: Verify generate_config_file multiple_locations template accepts different internal IPs
	# Expected: Config file uses provided internal IPs for each location
	local config_file="${BATS_TEST_TMPDIR}/test_multiple_locations_internal.conf"
	local peer_ip1="${TEST_PEER_IP}"
	local internal_ip1="${TEST_LOCAL_IP}"
	local peer_ip2="${TEST_PEER_IP2}"
	local internal_ip2="10.0.0.2"
	generate_config_file "multiple_locations" "$config_file" "$peer_ip1" "$internal_ip1" "$peer_ip2" "$internal_ip2"

	# Verify file uses provided internal IPs
	assert_file_contains "$config_file" "LOCATION_TEST_EXTERNAL=\"${peer_ip1}\""
	assert_file_contains "$config_file" "LOCATION_TEST_INTERNAL=\"${internal_ip1}\""
	assert_file_contains "$config_file" "LOCATION_TEST2_EXTERNAL=\"${peer_ip2}\""
	assert_file_contains "$config_file" "LOCATION_TEST2_INTERNAL=\"${internal_ip2}\""
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_config_file - cooldown_rate_limit template" {
	# Purpose: Verify generate_config_file creates rate_limit config file correctly
	# Expected: Config file contains rate limit settings
	local config_file="${BATS_TEST_TMPDIR}/test_rate_limit.conf"
	local peer_ip="${TEST_PEER_IP}"
	generate_config_file "cooldown_rate_limit" "$config_file" "$peer_ip"

	# Verify file was created
	assert_file_exist "$config_file"
	# Verify file contains expected fields
	assert_file_contains "$config_file" "LOCATION_NYC_EXTERNAL=\"${peer_ip}\""
	assert_file_contains "$config_file" "MAX_RESTARTS_PER_WINDOW=20"
	assert_file_contains "$config_file" "ENABLE_XFRM_RECOVERY=0"
	assert_file_contains "$config_file" "ENABLE_NETWORK_PARTITION_CHECK=0"
	assert_file_contains "$config_file" "ENABLE_RESOURCE_MONITORING=0"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_config_file - cooldown_rate_limit template with custom values" {
	# Purpose: Verify generate_config_file rate_limit template accepts custom rate limit
	# Expected: Config file uses provided max restarts
	local config_file="${BATS_TEST_TMPDIR}/test_rate_limit_custom.conf"
	local peer_ip="${TEST_PEER_IP}"
	local max_restarts=5
	generate_config_file "cooldown_rate_limit" "$config_file" "$peer_ip" "$max_restarts"

	# Verify file uses custom values
	assert_file_contains "$config_file" "LOCATION_NYC_EXTERNAL=\"${peer_ip}\""
	assert_file_contains "$config_file" "MAX_RESTARTS_PER_WINDOW=${max_restarts}"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_config_file - unknown template type returns error" {
	# Purpose: Verify generate_config_file handles unknown template type correctly
	# Expected: Function returns error code and prints error message
	local config_file="${BATS_TEST_TMPDIR}/test_unknown.conf"
	local peer_ip="${TEST_PEER_IP}"
	run generate_config_file "unknown_template" "$config_file" "$peer_ip"

	# Verify function fails
	assert_failure
	# Verify error message is printed
	assert_output --partial "Unknown template type: unknown_template"
	# Verify file was not created
	assert_file_not_exist "$config_file"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "generate_config_file - overwrites existing file" {
	# Purpose: Verify generate_config_file overwrites existing files
	# Expected: New content replaces old content
	local config_file="${BATS_TEST_TMPDIR}/test_overwrite.conf"
	local peer_ip1="${TEST_PEER_IP}"
	local peer_ip2="${TEST_PEER_IP2}"

	# Create initial file
	generate_config_file "minimal" "$config_file" "$peer_ip1"
	assert_file_contains "$config_file" "LOCATION_TEST_EXTERNAL=\"${peer_ip1}\""

	# Overwrite with different content
	generate_config_file "minimal" "$config_file" "$peer_ip2"
	# Verify new content replaced old
	assert_file_contains "$config_file" "LOCATION_TEST_EXTERNAL=\"${peer_ip2}\""
	refute_file_contains "$config_file" "LOCATION_TEST_EXTERNAL=\"${peer_ip1}\""
}

# ============================================================================
# load_test_data_file() Tests
# ============================================================================

# bats test_tags=category:test-infrastructure,priority:low
@test "load_test_data_file - loads existing file successfully" {
	# Purpose: Verify load_test_data_file loads existing test data file correctly
	# Expected: Function returns file contents
	# Create a test data file first
	local test_data_dir="${BATS_TEST_DIRNAME}/data"
	mkdir -p "$test_data_dir"
	local test_file="${test_data_dir}/test_sample.txt"
	local test_content="Sample test data content"
	echo "$test_content" >"$test_file"

	# Load the file
	local output
	output=$(load_test_data_file "test_sample.txt")

	# Verify output matches file content
	assert_equal "$output" "$test_content"

	# Clean up
	rm -f "$test_file"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "load_test_data_file - loads file from subdirectory" {
	# Purpose: Verify load_test_data_file loads files from subdirectories
	# Expected: Function correctly resolves paths with subdirectories
	# Create a test data file in a subdirectory
	local test_data_dir="${BATS_TEST_DIRNAME}/data/mock_outputs"
	mkdir -p "$test_data_dir"
	local test_file="${test_data_dir}/test_subdir.txt"
	local test_content="Subdirectory test data"
	echo "$test_content" >"$test_file"

	# Load the file
	local output
	output=$(load_test_data_file "mock_outputs/test_subdir.txt")

	# Verify output matches file content
	assert_equal "$output" "$test_content"

	# Clean up
	rm -f "$test_file"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "load_test_data_file - returns error for non-existent file" {
	# Purpose: Verify load_test_data_file handles non-existent files correctly
	# Expected: Function returns error code and prints error message
	run load_test_data_file "nonexistent_file.txt"

	# Verify function fails
	assert_failure
	# Verify error message is printed
	assert_output --partial "Test data file not found"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "load_test_data_file - returns error for file in non-existent subdirectory" {
	# Purpose: Verify load_test_data_file handles non-existent subdirectories correctly
	# Expected: Function returns error code
	run load_test_data_file "nonexistent_dir/nonexistent_file.txt"

	# Verify function fails
	assert_failure
	# Verify error message is printed
	assert_output --partial "Test data file not found"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "load_test_data_file - loads multi-line file correctly" {
	# Purpose: Verify load_test_data_file preserves multi-line content
	# Expected: Function returns all lines of file content
	# Create a multi-line test data file
	local test_data_dir="${BATS_TEST_DIRNAME}/data"
	mkdir -p "$test_data_dir"
	local test_file="${test_data_dir}/test_multiline.txt"
	cat >"$test_file" <<EOF
Line 1
Line 2
Line 3
EOF

	# Load the file
	local output
	output=$(load_test_data_file "test_multiline.txt")

	# Verify output contains all lines
	assert_output --partial "Line 1"
	assert_output --partial "Line 2"
	assert_output --partial "Line 3"
	# Verify line count
	local line_count
	line_count=$(echo "$output" | wc -l)
	assert_equal "$line_count" 3

	# Clean up
	rm -f "$test_file"
}

# bats test_tags=category:test-infrastructure,priority:low
@test "load_test_data_file - handles empty file" {
	# Purpose: Verify load_test_data_file handles empty files correctly
	# Expected: Function returns empty string
	# Create an empty test data file
	local test_data_dir="${BATS_TEST_DIRNAME}/data"
	mkdir -p "$test_data_dir"
	local test_file="${test_data_dir}/test_empty.txt"
	touch "$test_file"

	# Load the file
	local output
	output=$(load_test_data_file "test_empty.txt")

	# Verify output is empty
	assert_equal "$output" ""

	# Clean up
	rm -f "$test_file"
}
