#!/usr/bin/env bats
#
# Tests for compare-config.sh script
# Tests configuration comparison functionality between template and existing config files

load test_helper

# Path to the compare-config script
COMPARE_CONFIG_SCRIPT="${BATS_TEST_DIRNAME}/../compare-config.sh"

# Create a test config file with specified variables
#
# Creates a config file with the provided variable assignments.
# Used to test various config scenarios.
#
# Arguments:
#   $1: Config file path
#   $2+: Variable assignments (e.g., "VAR1=value1" "VAR2=value2")
create_test_config() {
	local config_file="$1"
	shift
	mkdir -p "$(dirname "$config_file")"

	cat >"$config_file" <<EOF
# Test configuration file
EOF

	# Add each variable assignment
	for var_assignment in "$@"; do
		echo "$var_assignment" >>"$config_file"
	done
}

# Create a minimal valid config file
#
# Creates a config file with all required settings.
#
# Arguments:
#   $1: Config file path
create_valid_config() {
	local config_file="$1"
	create_test_config "$config_file" \
		'LOCATION_NYC_EXTERNAL="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3'
}

# bats test_tags=category:unit
@test "compare-config.sh exists and is executable" {
	# Purpose: Test verifies that the compare-config script file exists and has execute permissions
	# Expected: Compare-config script file is present and executable
	# Importance: Ensures the config comparison script can be run directly for troubleshooting
	assert_file_exist "$COMPARE_CONFIG_SCRIPT"
	assert_file_executable "$COMPARE_CONFIG_SCRIPT"
}

# bats test_tags=category:unit
@test "compare-config.sh shows help with --help flag" {
	# Purpose: Test verifies that the compare-config script displays usage information when --help flag is provided
	# Expected: Script outputs usage information including all available options and flags
	# Importance: Ensures users can access help documentation for script usage and available options
	run bash "$COMPARE_CONFIG_SCRIPT" --help
	assert_success
	assert_output --partial "Usage:"
	assert_output --partial "compare-config.sh"
	assert_output --partial "--template"
	assert_output --partial "--existing"
	assert_output --partial "--help"
}

# bats test_tags=category:unit
@test "compare-config.sh shows help with -h flag" {
	# Purpose: Test verifies that the compare-config script displays usage information when -h flag is provided
	# Expected: Script outputs usage information including all available options and flags
	# Importance: Ensures users can access help documentation using the short flag option
	run bash "$COMPARE_CONFIG_SCRIPT" -h
	assert_success
	assert_output --partial "Usage:"
}

# bats test_tags=category:unit
@test "compare-config.sh detects new fields in template" {
	# Purpose: Test verifies that the script identifies fields in template that aren't in existing config
	# Expected: Script reports new settings with their template values
	# Importance: Helps users identify what settings they should add to their config
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/template.conf"
	local existing_config="${test_dir}/existing.conf"

	# Create template with more fields
	create_test_config "$template_config" \
		'LOCATION_NYC_EXTERNAL="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3' \
		'VPN_NAME="Site-to-Site VPN"' \
		'NO_ESCALATE=0'

	# Create existing config with fewer fields (missing VPN_NAME and NO_ESCALATE)
	create_test_config "$existing_config" \
		'LOCATION_NYC_EXTERNAL="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3'

	run bash "$COMPARE_CONFIG_SCRIPT" --template "$template_config" --existing "$existing_config"

	assert_success
	assert_output --partial "New Settings in Template"
	assert_output --partial "VPN_NAME"
	assert_output --partial "NO_ESCALATE"
}

# bats test_tags=category:unit
@test "compare-config.sh detects deprecated fields in existing config" {
	# Purpose: Test verifies that the script identifies fields in existing config that aren't in template
	# Expected: Script reports deprecated settings that should be removed
	# Importance: Helps users clean up obsolete configuration settings
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/template.conf"
	local existing_config="${test_dir}/existing.conf"

	# Create template with fewer fields
	create_test_config "$template_config" \
		'LOCATION_NYC_EXTERNAL="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3'

	# Create existing config with deprecated fields
	create_test_config "$existing_config" \
		'LOCATION_NYC_EXTERNAL="192.168.1.1"' \
		'EXTERNAL_PEER_IPS="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3' \
		'PING_TARGET_IP="192.168.1.100"' \
		'OLD_DEPRECATED_SETTING="value"'

	run bash "$COMPARE_CONFIG_SCRIPT" --template "$template_config" --existing "$existing_config"

	assert_success
	assert_output --partial "Deprecated Settings in Existing Config"
	assert_output --partial "EXTERNAL_PEER_IPS"
	assert_output --partial "PING_TARGET_IP"
	assert_output --partial "OLD_DEPRECATED_SETTING"
}

# bats test_tags=category:unit
@test "compare-config.sh reports no differences when configs match" {
	# Purpose: Test verifies that the script correctly identifies when configs are identical
	# Expected: Script reports no new or deprecated settings
	# Importance: Confirms script works correctly for matching configurations
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/template.conf"
	local existing_config="${test_dir}/existing.conf"

	# Create identical configs
	create_test_config "$template_config" \
		'LOCATION_NYC_EXTERNAL="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3' \
		'VPN_NAME="Site-to-Site VPN"'

	create_test_config "$existing_config" \
		'LOCATION_NYC_EXTERNAL="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3' \
		'VPN_NAME="Site-to-Site VPN"'

	run bash "$COMPARE_CONFIG_SCRIPT" --template "$template_config" --existing "$existing_config"

	assert_success
	assert_output --partial "No new settings in template"
	assert_output --partial "No deprecated settings found"
	assert_output --partial "Your configuration file is up to date with the template!"
}

# bats test_tags=category:unit
@test "compare-config.sh exits with error if template file not found" {
	# Purpose: Test verifies that the compare-config script validates template file existence before processing
	# Expected: Script exits with failure status and displays error message when template file doesn't exist
	# Importance: Prevents script from attempting to compare non-existent files and provides clear error feedback
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local existing_config="${test_dir}/existing.conf"
	create_valid_config "$existing_config"

	run bash "$COMPARE_CONFIG_SCRIPT" --template "${test_dir}/nonexistent.conf" --existing "$existing_config"

	assert_failure
	assert_output --partial "Template config file not found"
}

# bats test_tags=category:unit
@test "compare-config.sh exits with error if existing config file not found" {
	# Purpose: Test verifies that the compare-config script validates existing config file existence before processing
	# Expected: Script exits with failure status and displays error message when existing config file doesn't exist
	# Importance: Prevents script from attempting to compare non-existent files and provides clear error feedback
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/template.conf"
	create_valid_config "$template_config"

	run bash "$COMPARE_CONFIG_SCRIPT" --template "$template_config" --existing "${test_dir}/nonexistent.conf"

	assert_failure
	assert_output --partial "Existing config file not found"
}

# bats test_tags=category:unit
@test "compare-config.sh handles empty config files gracefully" {
	# Purpose: Test verifies that the script handles empty config files without crashing
	# Expected: Script reports all template settings as new when existing config is empty
	# Importance: Ensures script works for new installations with empty configs
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/template.conf"
	local existing_config="${test_dir}/existing.conf"

	create_valid_config "$template_config"
	touch "$existing_config"

	run bash "$COMPARE_CONFIG_SCRIPT" --template "$template_config" --existing "$existing_config"

	assert_success
	assert_output --partial "New Settings in Template"
	# Should report all template variables as new
	assert_output --partial "LOCATION_NYC_EXTERNAL"
}

# bats test_tags=category:unit
@test "compare-config.sh handles empty template file gracefully" {
	# Purpose: Test verifies that the script handles empty template files without crashing
	# Expected: Script reports all existing settings as deprecated when template is empty
	# Importance: Ensures script handles edge cases gracefully
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/template.conf"
	local existing_config="${test_dir}/existing.conf"

	touch "$template_config"
	create_valid_config "$existing_config"

	run bash "$COMPARE_CONFIG_SCRIPT" --template "$template_config" --existing "$existing_config"

	assert_success
	assert_output --partial "Deprecated Settings in Existing Config"
	# Should report all existing variables as deprecated
	assert_output --partial "LOCATION_NYC_EXTERNAL"
}

# bats test_tags=category:unit
@test "compare-config.sh handles quoted values correctly" {
	# Purpose: Test verifies that the script correctly parses and compares quoted config values
	# Expected: Script correctly identifies variables with quoted values and extracts values properly
	# Importance: Ensures script works with standard config file format
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/template.conf"
	local existing_config="${test_dir}/existing.conf"

	# Create template with quoted values
	create_test_config "$template_config" \
		'LOCATION_NYC_EXTERNAL="192.168.1.1"' \
		'LOCATION_DC_EXTERNAL="10.0.0.1"' \
		'VPN_NAME="Site-to-Site VPN"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3'

	# Create existing config with same variables but different values (quoted)
	create_test_config "$existing_config" \
		'LOCATION_NYC_EXTERNAL="192.168.1.2"' \
		'LOCATION_DC_EXTERNAL="10.0.0.2"' \
		'VPN_NAME="My VPN"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3'

	run bash "$COMPARE_CONFIG_SCRIPT" --template "$template_config" --existing "$existing_config"

	assert_success
	# Should recognize all variables as common (not new or deprecated)
	assert_output --partial "Common settings:"
	# Should not report any new or deprecated settings since all variables exist in both
	assert_output --partial "No new settings in template"
	assert_output --partial "No deprecated settings found"
}

# bats test_tags=category:unit
@test "compare-config.sh handles unquoted values correctly" {
	# Purpose: Test verifies that the script correctly parses and compares unquoted config values
	# Expected: Script correctly identifies variables with unquoted values
	# Importance: Ensures script works with both quoted and unquoted formats
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/template.conf"
	local existing_config="${test_dir}/existing.conf"

	# Create template with unquoted values
	create_test_config "$template_config" \
		'LOCATION_NYC_EXTERNAL="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3' \
		'NO_ESCALATE=0' \
		'RECOVERY_VERIFY_TIMEOUT=30'

	# Create existing config with unquoted values
	create_test_config "$existing_config" \
		'LOCATION_NYC_EXTERNAL="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3' \
		'NO_ESCALATE=0' \
		'RECOVERY_VERIFY_TIMEOUT=30'

	run bash "$COMPARE_CONFIG_SCRIPT" --template "$template_config" --existing "$existing_config"

	assert_success
	# Should recognize all variables as common
	assert_output --partial "Common settings:"
	assert_output --partial "No new settings in template"
	assert_output --partial "No deprecated settings found"
}

# bats test_tags=category:unit
@test "compare-config.sh handles variables with spaces in values" {
	# Purpose: Test verifies that the script correctly handles config values containing spaces
	# Expected: Script correctly extracts and displays values with spaces, properly quoting them in recommendations
	# Importance: Ensures script works with complex config values that require quoting
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/template.conf"
	local existing_config="${test_dir}/existing.conf"

	# Create template with values containing spaces
	create_test_config "$template_config" \
		'LOCATION_NYC_EXTERNAL="192.168.1.1"' \
		'LOCATION_NYC_INTERNAL="192.168.1.1 192.168.1.2 192.168.1.3"' \
		'VPN_NAME="Site-to-Site VPN"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3'

	# Create existing config missing the internal IPs variable
	create_test_config "$existing_config" \
		'LOCATION_NYC_EXTERNAL="192.168.1.1"' \
		'VPN_NAME="Site-to-Site VPN"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3'

	run bash "$COMPARE_CONFIG_SCRIPT" --template "$template_config" --existing "$existing_config"

	assert_success
	assert_output --partial "New Settings in Template"
	assert_output --partial "LOCATION_NYC_INTERNAL"
	# Should show quoted value in recommendations
	assert_output --partial "LOCATION_NYC_INTERNAL=\"192.168.1.1 192.168.1.2 192.168.1.3\""
}

# bats test_tags=category:unit
@test "compare-config.sh detects duplicate variable names in template" {
	# Purpose: Test verifies that the script detects and reports duplicate variable names in template config
	# Expected: Script reports duplicate variables with warning message
	# Importance: Helps users identify configuration errors with duplicate settings
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/template.conf"
	local existing_config="${test_dir}/existing.conf"

	# Create template with duplicate variables
	create_test_config "$template_config" \
		'LOCATION_NYC_EXTERNAL="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER1_THRESHOLD=2' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3'

	create_valid_config "$existing_config"

	run bash "$COMPARE_CONFIG_SCRIPT" --template "$template_config" --existing "$existing_config"

	assert_success
	assert_output --partial "Duplicate Variables in Template"
	assert_output --partial "TIER1_THRESHOLD"
	assert_output --partial "appears 2 times"
}

# bats test_tags=category:unit
@test "compare-config.sh detects duplicate variable names in existing config" {
	# Purpose: Test verifies that the script detects and reports duplicate variable names in existing config
	# Expected: Script reports duplicate variables with warning message
	# Importance: Helps users identify configuration errors with duplicate settings
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/template.conf"
	local existing_config="${test_dir}/existing.conf"

	create_valid_config "$template_config"

	# Create existing config with duplicate variables
	create_test_config "$existing_config" \
		'LOCATION_NYC_EXTERNAL="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER1_THRESHOLD=2' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3'

	run bash "$COMPARE_CONFIG_SCRIPT" --template "$template_config" --existing "$existing_config"

	assert_success
	assert_output --partial "Duplicate Variables in Existing Config"
	assert_output --partial "TIER1_THRESHOLD"
	assert_output --partial "appears 2 times"
}

# bats test_tags=category:unit
@test "compare-config.sh handles config files with only comments" {
	# Purpose: Test verifies that the script correctly ignores comment-only config files
	# Expected: Script treats comment-only files as empty and reports accordingly
	# Importance: Ensures comments don't interfere with comparison
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/template.conf"
	local existing_config="${test_dir}/existing.conf"

	create_valid_config "$template_config"

	# Create existing config with only comments
	cat >"$existing_config" <<'EOF'
# This is a comment
# Another comment
# EXTERNAL_PEER_IPS="192.168.1.1"  # This is commented out
EOF

	run bash "$COMPARE_CONFIG_SCRIPT" --template "$template_config" --existing "$existing_config"

	assert_success
	assert_output --partial "New Settings in Template"
	# Should report all template variables as new
	assert_output --partial "LOCATION_NYC_EXTERNAL"
}

# bats test_tags=category:unit
@test "compare-config.sh shows template values for new settings" {
	# Purpose: Test verifies that the script displays template values for new settings to help users
	# Expected: Script shows template value and recommendation for adding new settings
	# Importance: Makes it easy for users to add new settings with correct values
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/template.conf"
	local existing_config="${test_dir}/existing.conf"

	# Create template with a new setting
	create_test_config "$template_config" \
		'LOCATION_NYC_EXTERNAL="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3' \
		'VPN_NAME="My VPN Name"'

	create_valid_config "$existing_config"

	run bash "$COMPARE_CONFIG_SCRIPT" --template "$template_config" --existing "$existing_config"

	assert_success
	assert_output --partial "VPN_NAME"
	assert_output --partial "Template value:"
	assert_output --partial "My VPN Name"
	assert_output --partial "Add to your config:"
}

# bats test_tags=category:unit
@test "compare-config.sh shows recommendations section when differences exist" {
	# Purpose: Test verifies that the script provides actionable recommendations for updating config
	# Expected: Script shows exact lines to add/remove in recommendations section
	# Importance: Makes it easy for users to update their config files
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/template.conf"
	local existing_config="${test_dir}/existing.conf"

	# Create template with new setting
	create_test_config "$template_config" \
		'LOCATION_NYC_EXTERNAL="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3' \
		'VPN_NAME="Site-to-Site VPN"'

	# Create existing config with deprecated setting
	create_test_config "$existing_config" \
		'LOCATION_NYC_EXTERNAL="192.168.1.1"' \
		'EXTERNAL_PEER_IPS="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3'

	run bash "$COMPARE_CONFIG_SCRIPT" --template "$template_config" --existing "$existing_config"

	assert_success
	assert_output --partial "Recommendations:"
	assert_output --partial "Consider adding the following"
	assert_output --partial "You may want to remove these deprecated settings"
}

# bats test_tags=category:unit
@test "compare-config.sh shows summary statistics" {
	# Purpose: Test verifies that the script provides summary statistics of config comparison
	# Expected: Script shows counts of common, new, and deprecated settings
	# Importance: Provides quick overview of config status
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/template.conf"
	local existing_config="${test_dir}/existing.conf"

	create_valid_config "$template_config"
	create_valid_config "$existing_config"

	run bash "$COMPARE_CONFIG_SCRIPT" --template "$template_config" --existing "$existing_config"

	assert_success
	assert_output --partial "Summary:"
	assert_output --partial "Common settings:"
}

# bats test_tags=category:unit
@test "compare-config.sh handles config file with trailing comments" {
	# Purpose: Test verifies that the script correctly handles config lines with inline comments
	# Expected: Script parses variable assignments correctly even with trailing comments
	# Importance: Ensures script works with commented config files
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/template.conf"
	local existing_config="${test_dir}/existing.conf"

	# Create template with inline comments
	cat >"$template_config" <<'EOF'
# Config with inline comments
LOCATION_NYC_EXTERNAL="192.168.1.1"  # External IP
TIER1_THRESHOLD=1  # Tier 1 threshold
TIER2_THRESHOLD=3  # Tier 2 threshold
TIER3_THRESHOLD=5  # Tier 3 threshold
COOLDOWN_MINUTES=15  # Cooldown period
MAX_RESTARTS_PER_HOUR=3  # Max restarts
EOF

	create_valid_config "$existing_config"

	run bash "$COMPARE_CONFIG_SCRIPT" --template "$template_config" --existing "$existing_config"

	assert_success
	# Should parse correctly despite inline comments
	assert_output --partial "Common settings:"
}

# bats test_tags=category:unit
@test "compare-config.sh auto-detects template config file in script directory" {
	# Purpose: Test verifies that the script automatically finds template config file in its directory
	# Expected: Script finds vpn-monitor.conf in the same directory as the script when --template is not provided
	# Importance: Makes script easier to use without requiring explicit template path
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/vpn-monitor.conf"
	local existing_config="${test_dir}/existing.conf"

	create_valid_config "$template_config"
	create_valid_config "$existing_config"

	# Copy script to test directory
	cp "$COMPARE_CONFIG_SCRIPT" "${test_dir}/compare-config.sh"
	chmod +x "${test_dir}/compare-config.sh"

	# Run from test directory with only --existing specified (should auto-detect template)
	run bash "${test_dir}/compare-config.sh" --existing "$existing_config"

	assert_success
	# Should find the template config file
	assert_output --partial "Template:"
	assert_output --partial "vpn-monitor.conf"
}

# bats test_tags=category:unit
@test "compare-config.sh auto-detects existing config file" {
	# Purpose: Test verifies that the script automatically finds existing config file when --existing is not provided
	# Expected: Script finds vpn-monitor.conf in script directory or /data/vpn-monitor/vpn-monitor.conf
	# Importance: Makes script easier to use without requiring explicit existing config path
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/template.conf"
	local existing_config="${test_dir}/vpn-monitor.conf"

	create_valid_config "$template_config"
	create_valid_config "$existing_config"

	# Copy script to test directory
	cp "$COMPARE_CONFIG_SCRIPT" "${test_dir}/compare-config.sh"
	chmod +x "${test_dir}/compare-config.sh"

	# Run from test directory with only --template specified (should auto-detect existing)
	run bash "${test_dir}/compare-config.sh" --template "$template_config"

	assert_success
	# Should find the existing config file
	assert_output --partial "Existing:"
	assert_output --partial "vpn-monitor.conf"
}

# bats test_tags=category:unit
@test "compare-config.sh auto-detects both template and existing config files" {
	# Purpose: Test verifies that the script automatically finds both config files when neither is specified
	# Expected: Script finds both vpn-monitor.conf files in script directory
	# Importance: Makes script easiest to use when run from installation directory
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local config_file="${test_dir}/vpn-monitor.conf"

	create_valid_config "$config_file"

	# Copy script to test directory
	cp "$COMPARE_CONFIG_SCRIPT" "${test_dir}/compare-config.sh"
	chmod +x "${test_dir}/compare-config.sh"

	# Run from test directory without any arguments (should auto-detect both)
	run bash "${test_dir}/compare-config.sh"

	assert_success
	# Should find both config files
	assert_output --partial "Template:"
	assert_output --partial "Existing:"
	assert_output --partial "vpn-monitor.conf"
}

# bats test_tags=category:unit
@test "compare-config.sh does not flag customer-specific LOCATION variables as deprecated" {
	# Purpose: Test verifies that customer-specific LOCATION variables (e.g., LOCATION_CUSTOMER1_EXTERNAL)
	# are not flagged as deprecated when template only has example locations (e.g., LOCATION_NYC_EXTERNAL)
	# Expected: Customer-specific LOCATION variables are recognized as valid pattern matches
	# Importance: Allows customers to use their own location names without false deprecation warnings
	local test_dir="${TEST_DIR}/test-compare"
	mkdir -p "$test_dir"

	local template_config="${test_dir}/template.conf"
	local existing_config="${test_dir}/existing.conf"

	# Template has example location (NYC)
	create_test_config "$template_config" \
		'LOCATION_NYC_EXTERNAL="192.168.1.1"' \
		'LOCATION_NYC_INTERNAL="192.168.1.1"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3'

	# Existing config has customer-specific locations
	create_test_config "$existing_config" \
		'LOCATION_CUSTOMER1_EXTERNAL="10.0.0.1"' \
		'LOCATION_CUSTOMER1_INTERNAL="10.0.0.1"' \
		'LOCATION_OFFICE2_EXTERNAL="10.0.0.2"' \
		'LOCATION_OFFICE2_INTERNAL="10.0.0.2"' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'COOLDOWN_MINUTES=15' \
		'MAX_RESTARTS_PER_HOUR=3' \
		'OLD_DEPRECATED_SETTING="value"'

	run bash "$COMPARE_CONFIG_SCRIPT" --template "$template_config" --existing "$existing_config"

	assert_success
	# Should NOT flag customer-specific LOCATION variables as deprecated
	assert_output --partial "Deprecated Settings in Existing Config"
	assert_output --partial "OLD_DEPRECATED_SETTING"
	# Should not include LOCATION variables in deprecated list
	refute_output --partial "LOCATION_CUSTOMER1_EXTERNAL"
	refute_output --partial "LOCATION_CUSTOMER1_INTERNAL"
	refute_output --partial "LOCATION_OFFICE2_EXTERNAL"
	refute_output --partial "LOCATION_OFFICE2_INTERNAL"
}
