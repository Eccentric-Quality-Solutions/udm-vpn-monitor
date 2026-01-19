#!/bin/bash
#
# Configuration loading and validation for UDM VPN Monitor
# Handles loading configuration files and validating settings
#
# Version: 0.6.0
#
# Default Value Handling:
#   Default values are defined in lib/config_schema.sh as the single source of truth.
#   The load_config() function reads defaults from the schema using get_config_default(),
#   ensuring consistency and eliminating duplication. To change defaults, update only
#   config_schema.sh - load_config() will automatically use the updated values.
#
#   Default application logic is centralized in apply_optional_default() function, which
#   is used by apply_config_default(), validate_config_type(), and validate_config_rule()
#   to ensure consistent behavior when applying defaults for optional variables that are
#   empty or invalid. This eliminates duplication and ensures defaults are applied uniformly.
#
# Module Structure:
#   This file sources the decomposed configuration modules:
#   - config/config_loading.sh: File parsing and loading
#   - config/config_defaults.sh: Default value application
#   - config/config_validation.sh: Schema validation and type checking
#   - config/location_parsing.sh: Location-based configuration parsing

# Source constants for magic numbers
# shellcheck source=lib/constants.sh
# Determine lib directory (where this file is located)
# Always set LIB_DIR, even if empty (handles cases where BASH_SOURCE[0] resolution fails)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 2>/dev/null || LIB_DIR=""
# Note: safe_source_lib not available here since constants.sh is sourced before common.sh
source "${LIB_DIR}/constants.sh" 2>/dev/null || {
	# Fallback if constants.sh not found (shouldn't happen in normal operation)
	# Only set if not already set (to avoid readonly variable errors)
	if ! declare -p LOCKFILE_TIMEOUT_DEFAULT &>/dev/null; then
		readonly LOCKFILE_TIMEOUT_DEFAULT=300
	fi
	if ! declare -p SECONDS_PER_MINUTE &>/dev/null; then
		readonly SECONDS_PER_MINUTE=60
	fi
	if ! declare -p SECONDS_PER_HOUR &>/dev/null; then
		readonly SECONDS_PER_HOUR=3600
	fi
	if ! declare -p SECONDS_PER_DAY &>/dev/null; then
		readonly SECONDS_PER_DAY=86400
	fi
	if ! declare -p MAX_IPV6_SEGMENTS &>/dev/null; then
		readonly MAX_IPV6_SEGMENTS=8
	fi
}

# Source common utility functions
# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"

# Source configuration modules in dependency order
# shellcheck source=lib/config/config_loading.sh
source "${LIB_DIR}/config/config_loading.sh" || {
	echo "ERROR: Failed to source config/config_loading.sh" >&2
	exit 1
}

# shellcheck source=lib/config/config_defaults.sh
source "${LIB_DIR}/config/config_defaults.sh" || {
	echo "ERROR: Failed to source config/config_defaults.sh" >&2
	exit 1
}

# shellcheck source=lib/config/config_validation.sh
source "${LIB_DIR}/config/config_validation.sh" || {
	echo "ERROR: Failed to source config/config_validation.sh" >&2
	exit 1
}

# shellcheck source=lib/config/location_parsing.sh
source "${LIB_DIR}/config/location_parsing.sh" || {
	echo "ERROR: Failed to source config/location_parsing.sh" >&2
	exit 1
}
