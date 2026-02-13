#!/usr/bin/env bash
#
# Test Data Helpers
#
# This module provides helpers for loading and generating test data from
# the tests/data/ directory. It consolidates common patterns for accessing
# test data that was previously embedded in test files.
#
# Usage:
#   load test_helper
#   load helpers/test_data
#
#   # Load xfrm state output
#   local xfrm_output
#   xfrm_output=$(generate_xfrm_state_for_scenario "healthy" "${TEST_PEER_IP}" "0x12345678" 1000 10)
#
#   # Load ipsec status output (use template function directly)
#   local ipsec_output
#   ipsec_output=$(generate_ipsec_status_output "libreswan" "test-conn" "${TEST_PEER_IP}")
#
#   # Generate config file
#   generate_config_file "standard" "${TEST_DIR}/vpn-monitor.conf" "${TEST_PEER_IP}"

# Source data templates
# Use the helper's directory to find data files (not BATS_TEST_DIRNAME which is relative to test file)
# Note: Cannot use 'local' here as this is top-level code in a sourced script
_helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${_helper_dir}/../data/mock_outputs/xfrm_state_templates.sh" ]]; then
	# shellcheck source=../data/mock_outputs/xfrm_state_templates.sh
	source "${_helper_dir}/../data/mock_outputs/xfrm_state_templates.sh"
fi

if [[ -f "${_helper_dir}/../data/mock_outputs/ipsec_status_templates.sh" ]]; then
	# shellcheck source=../data/mock_outputs/ipsec_status_templates.sh
	source "${_helper_dir}/../data/mock_outputs/ipsec_status_templates.sh"
fi

if [[ -f "${_helper_dir}/../data/configs/config_templates.sh" ]]; then
	# shellcheck source=../data/configs/config_templates.sh
	source "${_helper_dir}/../data/configs/config_templates.sh"
fi

# Generate xfrm state output for common scenarios
#
# Generates xfrm state output for common test scenarios (healthy, idle, failing).
# This is a convenience wrapper around the template functions.
#
# Arguments:
#   $1: Scenario type ("healthy", "idle", "failing", or "custom")
#   $2: Peer IP address
#   $3: SPI (hex format, e.g., "0x12345678")
#   $4: Byte counter (optional, used for "custom" or overrides defaults)
#   $5: Packet counter (optional, used for "custom" or overrides defaults)
#   $6: Output format ("full" or "minimal", default: "full")
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints xfrm state output to stdout
#
# Example:
#   # Generate healthy VPN output
#   generate_xfrm_state_for_scenario "healthy" "${TEST_PEER_IP}" "0x12345678"
#
#   # Generate custom output with specific counters
#   generate_xfrm_state_for_scenario "custom" "${TEST_PEER_IP}" "0x12345678" 2000 20
generate_xfrm_state_for_scenario() {
	local scenario="$1"
	local peer_ip="$2"
	local spi="$3"
	local bytes="$4"
	local packets="$5"
	local format="${6:-full}"

	case "$scenario" in
	healthy)
		# Use provided values if given, otherwise use scenario defaults
		# This allows overriding defaults: generate_xfrm_state_for_scenario "healthy" "$ip" "$spi" 2000 20
		bytes="${bytes:-${XFRM_STATE_HEALTHY_BYTES:-1000}}"
		packets="${packets:-${XFRM_STATE_HEALTHY_PACKETS:-10}}"
		;;
	idle)
		# Use provided values if given, otherwise use scenario defaults
		bytes="${bytes:-${XFRM_STATE_IDLE_BYTES:-0}}"
		packets="${packets:-${XFRM_STATE_IDLE_PACKETS:-0}}"
		;;
	failing)
		# Use provided values if given, otherwise use scenario defaults
		bytes="${bytes:-${XFRM_STATE_FAILING_BYTES:-1000}}"
		packets="${packets:-${XFRM_STATE_FAILING_PACKETS:-10}}"
		;;
	custom)
		# Use provided values or defaults
		bytes="${bytes:-1000}"
		packets="${packets:-10}"
		;;
	*)
		echo "Unknown scenario: $scenario" >&2
		return 1
		;;
	esac

	if [[ "$format" == "minimal" ]]; then
		generate_xfrm_state_minimal "$peer_ip" "$spi" "$bytes" "$packets"
	else
		generate_xfrm_state_sa "$peer_ip" "$spi" "$bytes" "$packets"
	fi
}

# Generate config file from template
#
# Generates a configuration file using a template from tests/data/configs/.
#
# Arguments:
#   $1: Template type ("minimal", "standard", "custom_log", "multiple_locations")
#   $2: Output file path
#   $3+: Template-specific arguments (see template functions for details)
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Creates or overwrites the specified config file
#
# Example:
#   # Generate standard config
#   generate_config_file "standard" "${TEST_DIR}/vpn-monitor.conf" "${TEST_PEER_IP}"
#
#   # Generate config with custom log file
#   generate_config_file "custom_log" "${TEST_DIR}/vpn-monitor.conf" "${TEST_PEER_IP}" "/tmp/custom.log"
generate_config_file() {
	local template_type="$1"
	local output_file="$2"
	shift 2 || true
	local template_args=("$@")

	case "$template_type" in
	minimal)
		generate_config_minimal "${template_args[@]}" >"$output_file"
		;;
	standard)
		generate_config_standard "${template_args[@]}" >"$output_file"
		;;
	custom_log)
		generate_config_custom_log "${template_args[@]}" >"$output_file"
		;;
	multiple_locations)
		generate_config_multiple_locations "${template_args[@]}" >"$output_file"
		;;
	cooldown_rate_limit)
		generate_config_rate_limit "${template_args[@]}" >"$output_file"
		;;
	*)
		echo "Unknown template type: $template_type" >&2
		return 1
		;;
	esac
}

# Load test data from file
#
# Loads test data from a file in the tests/data/ directory.
# This is useful for complex test data that doesn't fit the generator pattern.
#
# Arguments:
#   $1: Relative path from tests/data/ (e.g., "mock_outputs/sample_output.txt")
#
# Returns:
#   0: Success
#   1: File not found
#
# Output:
#   Prints file contents to stdout
#
# Example:
#   local data
#   data=$(load_test_data_file "mock_outputs/sample_output.txt")
load_test_data_file() {
	local data_path="$1"
	# Use the helper's directory to find data files (not BATS_TEST_DIRNAME which is relative to test file)
	local helper_dir
	helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	local full_path="${helper_dir}/../data/${data_path}"

	if [[ ! -f "$full_path" ]]; then
		echo "Test data file not found: $full_path" >&2
		return 1
	fi

	cat "$full_path"
}
