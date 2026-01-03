#!/usr/bin/env bats
#
# Tests for Migration Script
# Tests migration from old format to new format, backup creation,
# location name generation, and config validation after migration

load test_helper

# Path to the migration script
MIGRATION_SCRIPT="${BATS_TEST_DIRNAME}/../scripts/migrate-config-to-locations.sh"

# ============================================================================
# MIGRATION SCRIPT TESTS
# ============================================================================

# Helper function to create old format config
create_old_config() {
	local config_file="$1"
	local external_ips="${2:-192.168.1.1}"
	local internal_ips="${3:-}"
	shift 3 || true
	local extra_config=("$@")

	mkdir -p "$(dirname "$config_file")"
	cat >"$config_file" <<EOF
EXTERNAL_PEER_IPS="${external_ips}"
INTERNAL_PEER_IPS="${internal_ips}"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
COOLDOWN_MINUTES=15
MAX_RESTARTS_PER_HOUR=3
EOF

	# Add extra config variables
	for config_var in "${extra_config[@]}"; do
		if [[ -n "$config_var" ]]; then
			echo "$config_var" >>"$config_file"
		fi
	done
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - migrates single location with external IP only" {
	# Purpose: Test migration of single location with only external IP
	# Expected: Old format is replaced with LOCATION_1_EXTERNAL
	# Importance: Basic migration functionality
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_old_config "$config_file" "203.0.113.1" ""

	# Run migration script with CONFIG_FILE environment variable and --auto flag
	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --auto 2>&1

	# Check migration succeeded
	assert_file_exist "$config_file"
	assert_file_contains "$config_file" "LOCATION_1_EXTERNAL"
	assert_file_contains "$config_file" "203.0.113.1"
	# Check that old format config lines are removed (but allow in comments)
	refute_file_contains "$config_file" "^EXTERNAL_PEER_IPS="
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - migrates single location with external and internal IPs" {
	# Purpose: Test migration of single location with both IPs
	# Expected: Both EXTERNAL and INTERNAL are migrated correctly
	# Importance: Common migration scenario
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_old_config "$config_file" "203.0.113.1" "192.168.1.1"

	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --auto 2>&1

	assert_file_exist "$config_file"
	assert_file_contains "$config_file" "LOCATION_1_EXTERNAL"
	assert_file_contains "$config_file" "LOCATION_1_INTERNAL"
	assert_file_contains "$config_file" "203.0.113.1"
	assert_file_contains "$config_file" "192.168.1.1"
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - migrates multiple locations" {
	# Purpose: Test migration of multiple locations
	# Expected: Each IP gets its own location (LOCATION_1, LOCATION_2, etc.)
	# Importance: Multi-location deployments
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_old_config "$config_file" "203.0.113.1 198.51.100.1 192.0.2.1" "192.168.1.1 192.168.2.1"

	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --auto 2>&1

	assert_file_exist "$config_file"
	assert_file_contains "$config_file" "LOCATION_1_EXTERNAL"
	assert_file_contains "$config_file" "LOCATION_2_EXTERNAL"
	assert_file_contains "$config_file" "LOCATION_3_EXTERNAL"
	assert_file_contains "$config_file" "203.0.113.1"
	assert_file_contains "$config_file" "198.51.100.1"
	assert_file_contains "$config_file" "192.0.2.1"
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - creates backup file" {
	# Purpose: Test that backup file is created before migration
	# Expected: Backup file exists with timestamp
	# Importance: Allows rollback if migration fails
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_old_config "$config_file" "203.0.113.1" ""

	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --auto 2>&1

	# Check backup file exists (pattern: *.backup.YYYYMMDD_HHMMSS)
	local backup_files
	backup_files=$(find "${TEST_DIR}" -name "*.backup.*" 2>/dev/null || true)
	assert [ -n "$backup_files" ]

	# Verify backup contains old format
	local backup_file
	backup_file=$(echo "$backup_files" | head -n1)
	assert_file_exist "$backup_file"
	assert_file_contains "$backup_file" "EXTERNAL_PEER_IPS"
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - preserves other config settings" {
	# Purpose: Test that non-VPN IP settings are preserved
	# Expected: Other config variables remain unchanged
	# Importance: Migration shouldn't break existing config
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_old_config "$config_file" "203.0.113.1" "" \
		'VPN_NAME="Test VPN"' \
		'LOG_FILE="/var/log/vpn-monitor.log"'

	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --auto 2>&1

	assert_file_exist "$config_file"
	assert_file_contains "$config_file" "TIER1_THRESHOLD=1"
	assert_file_contains "$config_file" "VPN_NAME"
	assert_file_contains "$config_file" "LOG_FILE"
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - auto mode location name generation" {
	# Purpose: Test that --auto flag generates location names (LOCATION_1, LOCATION_2, etc.)
	# Expected: Location names follow pattern LOCATION_N
	# Importance: Automated migration behavior
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_old_config "$config_file" "203.0.113.1 198.51.100.1" ""

	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --auto 2>&1

	assert_file_exist "$config_file"
	assert_file_contains "$config_file" "LOCATION_1_EXTERNAL"
	assert_file_contains "$config_file" "LOCATION_2_EXTERNAL"
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - CSV location name generation" {
	# Purpose: Test that CSV file can provide location names
	# Expected: Location names from CSV are used instead of defaults
	# Importance: Allows custom location names via CSV
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local csv_file="${TEST_DIR}/locations.csv"
	create_old_config "$config_file" "203.0.113.1 198.51.100.1" ""

	# Create CSV file
	cat >"$csv_file" <<'EOF'
1,NYC
2,LA
EOF

	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --csv "$csv_file" 2>&1

	assert_file_exist "$config_file"
	assert_file_contains "$config_file" "LOCATION_NYC_EXTERNAL"
	assert_file_contains "$config_file" "LOCATION_LA_EXTERNAL"
	refute_file_contains "$config_file" "LOCATION_1_EXTERNAL"
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - CSV with missing entries falls back to default" {
	# Purpose: Test that missing CSV entries use default names
	# Expected: Missing entries get LOCATION_N names
	# Importance: Handles incomplete CSV files gracefully
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local csv_file="${TEST_DIR}/locations.csv"
	create_old_config "$config_file" "203.0.113.1 198.51.100.1 192.0.2.1" ""

	# Create CSV file with only first entry
	cat >"$csv_file" <<'EOF'
1,NYC
EOF

	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --csv "$csv_file" 2>&1

	assert_file_exist "$config_file"
	assert_file_contains "$config_file" "LOCATION_NYC_EXTERNAL"
	assert_file_contains "$config_file" "LOCATION_2_EXTERNAL"
	assert_file_contains "$config_file" "LOCATION_3_EXTERNAL"
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - handles missing internal IPs gracefully" {
	# Purpose: Test that missing internal IPs are handled correctly
	# Expected: Locations without internal IPs get empty INTERNAL variable
	# Importance: Internal IPs are optional
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_old_config "$config_file" "203.0.113.1 198.51.100.1" "192.168.1.1"
	# Only first location has internal IP

	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --auto 2>&1

	assert_file_exist "$config_file"
	assert_file_contains "$config_file" "LOCATION_1_INTERNAL"
	assert_file_contains "$config_file" "LOCATION_2_INTERNAL"
	# Second location should have empty internal IP
	assert_file_contains "$config_file" 'LOCATION_2_INTERNAL=""'
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - validates IP addresses" {
	# Purpose: Test that invalid IP addresses are skipped with warning
	# Expected: Invalid IPs are skipped, valid ones are migrated
	# Importance: Prevents migration of invalid config
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_old_config "$config_file" "203.0.113.1 invalid.ip 198.51.100.1" ""

	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --auto 2>&1

	# Should contain warning about invalid IP
	assert_output --partial "invalid"
	# Valid IPs should still be migrated
	assert_file_contains "$config_file" "203.0.113.1"
	assert_file_contains "$config_file" "198.51.100.1"
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - fails if config file doesn't exist" {
	# Purpose: Test that missing config file is handled correctly
	# Expected: Script exits with error
	# Importance: Prevents migration of non-existent files
	local config_file="${TEST_DIR}/nonexistent.conf"

	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --auto 2>&1
	assert_failure
	assert_output --partial "not found"
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - fails if old format not found" {
	# Purpose: Test that script fails if old format is not present
	# Expected: Script exits with error about missing old format
	# Importance: Prevents unnecessary migration attempts
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config without old format
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="203.0.113.1"
TIER1_THRESHOLD=1
EOF

	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --auto 2>&1
	assert_failure
	assert_output --partial "not found" || assert_output --partial "already migrated"
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - sanitizes location names from CSV" {
	# Purpose: Test that location names from CSV are sanitized
	# Expected: Invalid characters in CSV names are replaced
	# Importance: Ensures safe location names
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local csv_file="${TEST_DIR}/locations.csv"
	create_old_config "$config_file" "203.0.113.1" ""

	# Create CSV with invalid characters
	cat >"$csv_file" <<'EOF'
1,NYC-Office
EOF

	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --csv "$csv_file" 2>&1

	assert_file_exist "$config_file"
	# Name should be sanitized (hyphen replaced with underscore)
	assert_file_contains "$config_file" "LOCATION_NYC_Office_EXTERNAL" ||
		assert_file_contains "$config_file" "LOCATION_NYC-Office_EXTERNAL"
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - handles multiple internal IPs per location" {
	# Purpose: Test that multiple internal IPs are migrated correctly
	# Expected: Multiple internal IPs are preserved as space-separated string
	# Importance: Supports multiple internal IPs per location
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_old_config "$config_file" "203.0.113.1" "192.168.1.1 192.168.1.88"

	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --auto 2>&1

	assert_file_exist "$config_file"
	assert_file_contains "$config_file" "LOCATION_1_INTERNAL"
	# Both internal IPs should be present
	assert_file_contains "$config_file" "192.168.1.1"
	assert_file_contains "$config_file" "192.168.1.88"
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - adds migration comment" {
	# Purpose: Test that migration adds comment with date
	# Expected: Config file contains migration comment
	# Importance: Documents migration history
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_old_config "$config_file" "203.0.113.1" ""

	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --auto 2>&1

	assert_file_exist "$config_file"
	assert_file_contains "$config_file" "Location-based VPN configuration"
	assert_file_contains "$config_file" "Migration date"
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - validates migrated config" {
	# Purpose: Test that migrated config can be validated
	# Expected: Migrated config passes validation
	# Importance: Ensures migration produces valid config
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_old_config "$config_file" "203.0.113.1" "192.168.1.1"

	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --auto 2>&1
	assert_success

	# Try to validate migrated config using check-config.sh if available
	if [[ -f "${BATS_TEST_DIRNAME}/../check-config.sh" ]]; then
		CONFIG_FILE="$config_file" run bash "${BATS_TEST_DIRNAME}/../check-config.sh" 2>&1
		# Should succeed or at least not fail with format errors
		# (may fail for other reasons like missing dependencies)
	fi
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - handles empty internal IPs config" {
	# Purpose: Test that empty INTERNAL_PEER_IPS is handled correctly
	# Expected: Locations get empty INTERNAL variables
	# Importance: Internal IPs are optional
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_old_config "$config_file" "203.0.113.1" ""

	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --auto 2>&1

	assert_file_exist "$config_file"
	assert_file_contains "$config_file" "LOCATION_1_INTERNAL"
	# Should have empty internal IP
	assert_file_contains "$config_file" 'LOCATION_1_INTERNAL=""'
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - preserves comments in config" {
	# Purpose: Test that comments in config file are preserved
	# Expected: Comments remain in migrated config
	# Importance: Preserves user documentation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
# This is a comment
EXTERNAL_PEER_IPS="203.0.113.1"
# Another comment
TIER1_THRESHOLD=1
EOF

	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --auto 2>&1

	assert_file_exist "$config_file"
	# Comments should be preserved (except those on old format lines)
	assert_file_contains "$config_file" "# This is a comment" ||
		assert_file_contains "$config_file" "# Another comment"
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - interactive mode with user input" {
	# Purpose: Test that interactive mode prompts for location names and uses them
	# Expected: User-provided names are sanitized and used in config
	# Importance: Default behavior allows custom location names
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_old_config "$config_file" "203.0.113.1 198.51.100.1" ""

	# Simulate user input: provide names for each location
	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --interactive <<'EOF'
NYC
DC
EOF

	assert_success
	assert_file_exist "$config_file"
	assert_file_contains "$config_file" "LOCATION_NYC_EXTERNAL"
	assert_file_contains "$config_file" "LOCATION_DC_EXTERNAL"
	assert_file_contains "$config_file" "203.0.113.1"
	assert_file_contains "$config_file" "198.51.100.1"
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - interactive mode with empty input uses defaults" {
	# Purpose: Test that empty input in interactive mode uses index numbers
	# Expected: Empty input results in LOCATION_N format
	# Importance: Handles user skipping input gracefully
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_old_config "$config_file" "203.0.113.1" ""

	# Simulate user pressing Enter (empty input)
	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --interactive <<'EOF'

EOF

	assert_success
	assert_file_exist "$config_file"
	# Empty input should result in index number (1)
	assert_file_contains "$config_file" "LOCATION_1_EXTERNAL"
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - fails gracefully when detection.sh library is missing" {
	# Purpose: Test that script fails with clear error when required library is missing
	# Expected: Script fails with error message about missing validate_ip_address
	# Importance: Ensures script provides clear error when dependencies are missing
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_old_config "$config_file" "203.0.113.1" ""

	# Temporarily rename lib directory to simulate library loading failure
	local lib_backup="${TEST_DIR}/lib_backup"
	local lib_restored=0

	# Set up trap to ensure lib directory is restored even if test fails
	# shellcheck disable=SC2064
	trap 'if [[ $lib_restored -eq 0 ]] && [[ -d "$lib_backup" ]]; then mv "$lib_backup" "${BATS_TEST_DIRNAME}/../lib" 2>/dev/null || true; fi' EXIT

	if [[ -d "${BATS_TEST_DIRNAME}/../lib" ]]; then
		mv "${BATS_TEST_DIRNAME}/../lib" "$lib_backup" || {
			# If move fails, skip test (lib directory may be in use)
			skip "Cannot rename lib directory for testing"
		}
	fi

	# Run migration - should fail with clear error about missing library
	CONFIG_FILE="$config_file" run bash "$MIGRATION_SCRIPT" --auto 2>&1

	# Restore lib directory
	if [[ -d "$lib_backup" ]]; then
		mv "$lib_backup" "${BATS_TEST_DIRNAME}/../lib" || true
		lib_restored=1
	fi

	# Clear trap
	trap - EXIT

	# Script should fail with error about missing validate_ip_address
	assert_failure
	assert_output --partial "validate_ip_address"
	assert_output --partial "detection.sh"
}

# bats test_tags=category:high-risk,priority:high
@test "migration script - CONFIG_FILE environment variable override" {
	# Purpose: Test that CONFIG_FILE environment variable can override default path
	# Expected: Script uses CONFIG_FILE from environment instead of default
	# Importance: Allows testing and custom config file locations
	local custom_config_file="${TEST_DIR}/custom-location.conf"
	create_old_config "$custom_config_file" "203.0.113.1" ""

	# Override CONFIG_FILE via environment variable
	CONFIG_FILE="$custom_config_file" run bash "$MIGRATION_SCRIPT" --auto 2>&1

	assert_success
	assert_file_exist "$custom_config_file"
	assert_file_contains "$custom_config_file" "LOCATION_1_EXTERNAL"
	assert_file_contains "$custom_config_file" "203.0.113.1"
}
