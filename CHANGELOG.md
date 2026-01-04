# Changelog

All notable changes to the UDM VPN Monitor project will be documented in this file.

## [Unreleased]

### Added
- **Detection Reliability Safeguard**: Added safety check that prevents recovery escalation when detection is unreliable. If failure type is "unknown" and both `ip` and `ipsec` commands are unavailable, the system cannot reliably determine if VPN is actually down, so recovery escalation (Tier 2/3) is skipped to prevent false recovery actions. Failures are still logged for monitoring, but recovery actions are not executed when detection tools are unavailable.
- **Enhanced Command Availability Checking**: Improved `check_command_available()` function in `lib/common.sh` to handle restricted PATH environments (common in cron/systemd on UDM OS):
  - Falls back to checking common system directories (`/usr/sbin`, `/usr/bin`, `/sbin`, `/bin`) when `command -v` fails
  - Handles cases where PATH doesn't include `/usr/sbin` (common in cron/systemd environments)
  - Additional fallback: attempts to execute command with `--help`/`--version` flags to verify availability
  - Better compatibility with UDM OS environments where PATH may be restricted
- **Detection Reliability Test Suite**: New `tests/test_recovery_detection_reliability.sh` test file with comprehensive tests for the detection reliability safeguard, ensuring recovery escalation is properly blocked when detection tools are unavailable
- **Installation Route Testing Enhancement**: Enhanced `check_and_setup_routes()` in `install.sh` to test ping connectivity to all internal IPs from all configured locations (not just the first IP). Uses `check_ping_connectivity()` from detection.sh which provides proper fallback logic for ping commands (ping vs ping6, timeout handling, etc.) and proper logging.
- Migration script tests for interactive mode with mocked input
- Migration script test for fallback `sanitize_location_name` when library fails to load
- Migration script test for `CONFIG_FILE` environment variable override
- Installation test for comprehensive route testing with multiple locations and IPs

### Changed
- **Migration Script Default Behavior (BREAKING CHANGE)**: The `migrate-config-to-locations.sh` script now defaults to interactive mode (prompts for location names) instead of automatic generation. Use the `--auto` flag to restore the previous automatic behavior. This change improves the user experience by allowing meaningful location names by default.
  - Default mode: Interactive (prompts for each location name)
  - Use `--auto` flag for automatic generation (LOCATION_1, LOCATION_2, etc.)
  - Use `--csv FILE` for bulk import from CSV file
  - Previous versions defaulted to automatic generation
- **Installation Route Testing**: Enhanced installation script to test ping connectivity to all internal IPs from all configured locations during route setup, instead of only testing the first internal IP. This ensures all configured VPN endpoints are properly reachable and routes are correctly configured.
- **Documentation Updates**:
  - Updated `docs/ARCHITECTURE.md` with information about detection reliability safeguard in tiered recovery system
  - Updated `docs/CODE_PATTERNS.md` with notes about PATH restrictions in cron/systemd environments and `BASH_REMATCH` safety patterns when using `set -u`
  - Updated `docs/MIGRATION.md` to reflect new default interactive behavior of migration script

### Fixed
- Fixed migration script default mode parameter mismatch in `migrate_config()` function
- Added fallback `sanitize_location_name()` function when library files fail to load
- Restored `CONFIG_FILE` environment variable override capability (needed for testing)
- **BASH_REMATCH Safety**: Fixed potential "unbound variable" errors when using `set -u` (nounset) by using `${BASH_REMATCH[n]:-}` default values in `lib/recovery.sh` when accessing regex capture groups. This prevents errors if regex doesn't match or capture group is empty.
- **External IP Extraction Safety**: Fixed potential unbound variable error in `verify_ipsec_connections_active()` function by using safe default value `${BASH_REMATCH[1]:-}` when extracting external IP from location data

## 0.4.3 - 2026-01-02

### Added
- **Location-Based Configuration**: New location-based configuration format that organizes VPN connections by named locations:
  - Format: `LOCATION_<NAME>_EXTERNAL` and `LOCATION_<NAME>_INTERNAL` variables
  - Better organization for managing multiple VPN connections
  - Clearer logging with location names in logs and state files
  - Independent tracking per location with separate failure counters and state files
  - Supports multiple internal IPs per location with 30% ping threshold for health determination
- **Configuration Migration Script**: New `scripts/migrate-config-to-locations.sh` script to automatically migrate from old `EXTERNAL_PEER_IPS`/`INTERNAL_PEER_IPS` format to new location-based format:
  - Interactive mode with prompts for location names
  - CSV mode for bulk import
  - Automatic backup creation before migration
  - Config validation after migration
- **Multiple Internal IPs Support**: Enhanced ping health determination for locations with multiple internal IPs:
  - For locations with multiple internal IPs: VPN is considered healthy if ≥30% respond to pings (rounded up)
  - For locations with single internal IP: VPN requires 100% success (ping must succeed)
  - Example: 3 internal IPs need at least 1 successful ping, 10 internal IPs need at least 3 successful pings
- **Test Infrastructure Improvements**:
  - New test fixtures: `vpn_at_tier.bash`, `vpn_idle.bash` for common test scenarios
  - New test utilities: `detect_flaky_tests.sh` for identifying flaky tests
  - New test verification: `verify_test_isolation.sh` for ensuring test isolation
  - Enhanced test helpers with better mocking and synchronization
- **Documentation Enhancements**:
  - New `docs/CODE_PATTERNS.md` - Comprehensive code patterns and best practices guide
  - New `docs/CODE_REVIEW_LESSONS_LEARNED.md` - Lessons learned from code reviews
  - New `docs/TEST_MAINTENANCE.md` - Test maintenance guidelines and patterns
  - New `docs/TEST_STRATEGY.md` - Testing strategy and approach documentation
  - New `docs/MIGRATION.md` - Migration guide for location-based configuration
  - New `tests/TEST_PATTERNS.md` - Test patterns and best practices
  - New `ACCEPTABLE_RISKS.md` - Documented acceptable risks and limitations
- **Development Tools**:
  - New `scripts/audit_mock_cleanup.sh` - Script to audit and clean up test mocks
  - New `scripts/check-documentation.sh` - Script to verify documentation completeness
  - Enhanced CI/CD workflow with improved test execution and reporting

### Changed
- **Configuration System**: Major refactoring of configuration loading and parsing:
  - New location-based configuration format replaces `EXTERNAL_PEER_IPS`/`INTERNAL_PEER_IPS` format
  - Enhanced configuration parsing with better error handling and validation
  - Improved quote handling and escaping in configuration values
  - Better handling of empty or missing configuration values
  - Enhanced location name extraction and sanitization
- **State File Management**: Updated state file naming to include location names:
  - Old format: `state/failure_counter_203_0_113_1`
  - New format: `state/failure_counter_NYC_203_0_113_1`
  - State files now include location name for better organization
- **Test Suite Expansion**: Major expansion of test coverage:
  - New test files: `test_config_location.sh`, `test_detection_error_recovery.sh`, `test_detection_ping_multiple.sh`, `test_fixtures_vpn_at_tier.sh`, `test_fixtures_vpn_idle.sh`, `test_integration_location.sh`, `test_migration.sh`, `test_recovery_cascading_failures.sh`, `test_recovery_multi_location_partial.sh`, `test_state_atomic_write_failures.sh`, `test_state_location.sh`, `test_test_isolation.sh`
  - Enhanced existing tests with better fixtures and improved test isolation
  - Improved test helpers with better synchronization and mocking capabilities
- **Detection Module**: Enhanced detection logic for location-based configuration:
  - Support for multiple internal IPs per location with 30% ping threshold
  - Improved error recovery and handling
  - Better ping health determination for multiple IPs
- **Recovery Module**: Enhanced recovery actions for location-based configuration:
  - Per-location recovery tracking and actions
  - Improved cascading failure handling
  - Better multi-location partial failure recovery
- **Test Execution**: Improved test execution and reporting:
  - Enhanced `run_tests.sh` with better test filtering and execution
  - Improved test isolation verification
  - Better flaky test detection
- **Documentation Updates**:
  - Updated `README.md` with location-based configuration documentation
  - Updated `QUICK_START.md` with migration guidance
  - Updated `DEPLOYMENT_CHECKLIST.md` with migration steps
  - Updated `DEVELOPER.md` with new development guidelines
  - Updated `TROUBLESHOOTING.md` with location-based configuration troubleshooting
  - Updated ADRs to reflect location-based configuration changes
- **Code Quality Improvements**:
  - Enhanced error handling throughout configuration and detection modules
  - Improved code organization and maintainability
  - Better separation of concerns with location-based configuration parsing
  - Enhanced validation and error messages

### Fixed
- **Configuration Parsing**: Fixed quote handling and escaping in configuration values
- **State File Operations**: Fixed state file operations for location-based configuration
- **Test Isolation**: Improved test isolation to prevent test interference
- **Error Recovery**: Enhanced error recovery in detection and configuration modules

### Removed
- **Deprecated Test File**: Removed `tests/run_individual_tests.sh` (functionality integrated into `run_tests.sh`)
- **Deprecated Documentation**: Removed `docs/TEST_REVIEW.md` and `docs/TROUBLESHOOTING_LOG_FILE_OVERRIDE.md` (replaced by new documentation)

## 0.4.2 - 2025-12-29

### Added
- **Periodic Status Logging**: New `STATUS_LOG_INTERVAL_SECONDS` configuration option to log periodic status updates for healthy VPN peers (default: 300 seconds / 5 minutes). Ensures monitoring activity is visible in logs even when VPNs are healthy. Set to 0 to disable periodic status logging.
- **Recovery Verification Timeout**: New `RECOVERY_VERIFY_TIMEOUT` configuration option (default: 30 seconds) to control maximum time to wait for recovery verification after xfrm-based recovery actions. Range: 10-300 seconds.
- **Keepalive Daemon Config Reloading**: VPN keepalive daemon now automatically reloads configuration every 10 iterations (or every 5 minutes, whichever is longer) to pick up configuration changes without requiring service restart.
- **Keepalive LOCAL_UDM_IP Support**: Keepalive daemon now supports `LOCAL_UDM_IP` configuration for proper ping source routing when using `INTERNAL_PEER_IPS`, matching the behavior of `vpn-monitor.sh` ping checks.
- **Developer Troubleshooting Documentation**: New `docs/DEV_TROUBLESHOOTING.md` with troubleshooting tips for developers, including keepalive service restart instructions.

### Changed
- **Keepalive Daemon Improvements**:
  - Enhanced error handling and logging for keepalive ping failures
  - Improved peer IP parsing with better fallback handling
  - Better route management for internal IP pings
  - More robust daemon operation with config reloading capability
- **Installation Script Improvements**:
  - Enhanced error handling for keepalive systemd service startup with detailed journal output
  - Improved error messages when keepalive service fails to start
  - Updated library file list to include `resources.sh` in error messages
- **Recovery Module Refactoring**:
  - Extracted `format_peer_display()` function for consistent peer display formatting across logging statements
  - Improved code organization and maintainability
- **Documentation Updates**:
  - Updated `README.md` with new configuration options (`STATUS_LOG_INTERVAL_SECONDS`, `RECOVERY_VERIFY_TIMEOUT`)
  - Updated ADR-0013 status to "Deprecated (Removed in v0.2.0)" in `docs/adr/README.md` and `docs/adr/0013-state-file-checksum-validation.md`
  - Added deprecation note to ADR-0013 explaining removal in v0.2.0

### Fixed
- **Config Schema**: Added missing `STATUS_LOG_INTERVAL_SECONDS` to configuration schema validation

## 0.4.1 - 2025-12-29

### Added
- **Test Coverage Expansion**: Comprehensive test suites for existing functionality:
  - `tests/test_check_utilities.sh` - Tests for utility availability checking script
  - `tests/test_resources.sh` - Tests for resource monitoring functionality (CPU, RAM, disk)
  - `tests/test_vpn_keepalive.sh` - Tests for VPN keepalive daemon (start, stop, status, restart)
- **Test Fixtures**: New reusable test fixtures for common scenarios:
  - `tests/fixtures/vpn_network_partition.bash` - Network partition detection scenarios
  - `tests/fixtures/vpn_rate_limited.bash` - Rate limiting scenarios
  - `tests/fixtures/vpn_xfrm_recovery.bash` - XFRM recovery scenarios

### Changed
- **Test Infrastructure Improvements**:
  - Moved `source_function()` helper from `test_helper_functions.sh` to `test_helper.bash` for better organization
  - Enhanced test synchronization using file-based signaling instead of sleep delays for deterministic test execution
  - Improved test helper functions with better error handling and validation
  - Enhanced `create_test_vpn_monitor_script()` with better project root detection and validation
  - Improved date command mocking to support `date -d "+N minutes" +%s` format
- **Test Suite Improvements**:
  - Updated multiple test files to use new fixtures, reducing code duplication
  - Improved test reliability with better synchronization and deterministic timing
  - Enhanced test error messages and assertions
  - Fixed race conditions in concurrent state update tests
- **Code Quality Improvements**:
  - Enhanced error handling in `vpn-monitor.sh` with better directory creation validation
  - Improved `--fake` flag handling to set `NO_ESCALATE` early for graceful error handling
  - Enhanced `vpn-keepalive.sh` daemon startup with proper PID file handling for systemd Type=forking compatibility
  - Improved lockfile acquisition tests with better race condition handling
  - Enhanced config parsing tests with better error message validation
- **Documentation Updates**:
  - Updated `DEVELOPER.md` with additional development guidelines
  - Updated `docs/ARCHITECTURE.md` with architecture improvements
  - Enhanced `tests/README.md` with comprehensive testing guidelines
  - Expanded `tests/fixtures/README.md` with fixture usage documentation

### Fixed
- **Test Reliability**: Fixed race conditions in concurrent state update tests using file-based synchronization
- **Test Timing**: Replaced sleep-based synchronization with deterministic file-based signaling
- **Config Parsing**: Improved error message validation in config schema tests
- **Daemon Startup**: Fixed PID file handling in keepalive daemon for proper systemd integration

## 0.4.0 - 2025-12-29

### Added
- **Resource Monitoring**: New `lib/resources.sh` module that monitors CPU, RAM, and disk space usage:
  - **CPU Monitoring**: Tracks CPU usage and throttles execution if CPU is pegged at threshold (default: 90%) for sustained duration (default: 60 seconds)
  - **RAM Monitoring**: Tracks RAM usage and throttles execution if RAM is at threshold (default: 90%) for sustained duration (default: 60 seconds)
  - **Disk Space Monitoring**: 
    - Logs warnings when free disk space drops below warning threshold (default: 20% free)
    - Automatically rotates log files when they exceed 10MB
    - Removes old rotated log files when disk space is critical (< 10% free)
    - Throttles execution when disk space is critically low
  - **State Tracking**: Tracks resource constraint state over time to detect sustained resource pressure
  - **Graceful Degradation**: Falls back gracefully if monitoring commands are unavailable
- **Resource Monitoring Configuration**: New configuration options in `vpn-monitor.conf`:
  - `ENABLE_RESOURCE_MONITORING` (default: 1) - Enable/disable resource monitoring
  - `RESOURCE_CPU_THRESHOLD` (default: 90) - CPU usage threshold percentage
  - `RESOURCE_CPU_DURATION` (default: 60) - CPU constraint duration in seconds
  - `RESOURCE_RAM_THRESHOLD` (default: 90) - RAM usage threshold percentage
  - `RESOURCE_RAM_DURATION` (default: 60) - RAM constraint duration in seconds
  - `RESOURCE_DISK_WARNING_THRESHOLD` (default: 20) - Disk space warning threshold (% free)
  - `RESOURCE_DISK_CRITICAL_THRESHOLD` (default: 10) - Disk space critical threshold (% free)

### Changed
- **Main Script**: Integrated resource monitoring checks into `validate_monitor_state()` function
- **Documentation**: Updated README.md with resource monitoring section, configuration table, and usage examples

## 0.3.0 - 2025-12-29

### Added
- **Deployment Checklist**: `DEPLOYMENT_CHECKLIST.md` - Comprehensive deployment checklist with pre-deployment checks, installation steps, verification procedures, and troubleshooting guidance
- **Versioning Guide**: `docs/VERSIONING.md` - Complete versioning strategy documentation following Semantic Versioning (SemVer) principles, including version update checklist and best practices
- **Comprehensive Test Suite Expansion**: Major expansion of test coverage with 40+ new and updated test files:
  - `test_config_large_values.sh` - Tests for handling large configuration values
  - `test_config_loading.sh` - Tests for configuration file loading behavior
  - `test_config_order.sh` - Tests for configuration precedence and order
  - `test_config_overrides.sh` - Tests for configuration override mechanisms
  - `test_config_schema.sh` - Tests for configuration schema validation
  - `test_config_security.sh` - Tests for configuration security and validation
  - `test_config_validation.sh` - Tests for configuration validation logic
  - `test_detection_failure_type.sh` - Tests for failure type detection
  - `test_detection_fallback.sh` - Tests for detection fallback mechanisms
  - `test_detection_idle.sh` - Tests for idle VPN detection
  - `test_detection_network_partition.sh` - Tests for network partition detection
  - `test_detection_rekey.sh` - Tests for SA rekey detection
  - `test_detection_status.sh` - Tests for VPN status detection
  - `test_detection_xfrm_edge_cases.sh` - Tests for xfrm edge cases
  - `test_integration_e2e_recovery.sh` - End-to-end recovery integration tests
  - `test_multiple_peer_edge_cases.sh` - Tests for multiple peer scenarios
  - `test_rapid_state_changes.sh` - Tests for rapid state change handling
  - `test_recovery_cooldown_rate_limit_interaction.sh` - Tests for cooldown and rate limit interactions
  - `test_recovery_network_partition.sh` - Tests for recovery during network partitions
  - `test_recovery_partial_failures.sh` - Tests for partial recovery failures
  - `test_recovery_rate_limiting.sh` - Tests for recovery rate limiting
  - `test_recovery_tier1.sh` - Tests for Tier 1 recovery actions
  - `test_recovery_tier2.sh` - Tests for Tier 2 recovery actions
  - `test_recovery_tier3.sh` - Tests for Tier 3 recovery actions
  - `test_state_concurrent_updates.sh` - Tests for concurrent state updates
- **Test Fixtures**: New test fixtures for common scenarios:
  - `tests/fixtures/vpn_multiple_peers.bash` - Multiple VPN peers scenario
  - `tests/fixtures/vpn_recovery_disabled.bash` - Recovery disabled scenario
  - `tests/fixtures/vpn_rekey.bash` - VPN rekey scenario
- **Test Infrastructure Utilities**:
  - `tests/tag_slow_tests.sh` - Utility to tag slow-running tests
  - `tests/tag_slow_tests_from_log.sh` - Utility to tag slow tests from test run logs
- **Enhanced BATS Guide**: Significantly expanded `docs/BATS_GUIDE.md` with comprehensive documentation on BATS testing framework, usage patterns, helper libraries, and best practices

### Changed
- **Test Suite Reorganization**: Major refactoring of test suite for better organization and maintainability:
  - Split large test files into focused, single-responsibility test files
  - Reorganized recovery tests into tier-specific test files (tier1, tier2, tier3)
  - Improved test fixtures usage to reduce code duplication
  - Enhanced test helpers for better test isolation and mocking
- **Documentation Improvements**:
  - Updated `README.md` with improved structure and clearer documentation references
  - Enhanced `DEVELOPER.md` with additional development guidelines
  - Expanded `tests/README.md` with comprehensive testing guidelines
  - Updated `tests/fixtures/README.md` with fixture usage documentation
- **Code Quality**: Various code improvements and refactoring across library modules for better maintainability

### Removed
- **CRITICAL_PATH_TEST_GAPS.md**: Removed outdated test gaps document

## 0.2.0 - 2025-12-26

### Changed
- **Simplified Byte Counter Detection**: Replaced complex traffic pattern analysis with simple heuristics in `check_byte_counters()`:
  - Removed historical sample storage, automatic pruning, and rate calculations
  - Now uses simple logic: bytes increasing = healthy, bytes not increasing + ping fails = broken
  - Maintains ping-based idle detection for static byte counters
  - Reduces complexity and improves maintainability for single-deployment use case

### Removed
- **State File Checksum Validation**: Removed SHA256 checksum validation for state files:
  - Removed `calculate_file_checksum()`, `store_state_file_checksum()`, and `validate_state_file_checksum()` functions
  - Removed all checksum validation calls from state file operations
  - Removed checksum file handling from `delete_peer_state()` and `backup_corrupted_state_file()`
  - State file corruption detection now relies on format validation only
  - Simplifies codebase for single-deployment scenario where checksum overhead is unnecessary
- **Traffic Pattern Analysis Functions**: Removed complex traffic pattern analysis functionality:
  - Removed `store_traffic_sample()`, `get_traffic_samples()`, and `calculate_traffic_rate()` functions
  - Removed `traffic_history` state key handling
  - Removed `TRAFFIC_PATTERN_*` constants from `lib/constants.sh`
  - Replaced with simpler byte counter heuristics (see Changed section above)

### Added
- **VPN Keepalive Daemon**: `vpn-keepalive.sh` and `vpn-keepalive.service` - Optional background daemon that sends periodic ping traffic through VPN tunnels to prevent idle timeout and keep tunnels alive
- **Architectural Review Document**: `ARCHITECTURAL_REVIEW.md` - Comprehensive architectural review with security analysis, reliability recommendations, and code quality assessments
- **Utility Availability Checker**: `check-utilities.sh` - Script to verify which Linux utilities are available on UDM OS for troubleshooting and compatibility checking
- **Pre-commit Git Hook**: `scripts/hooks/pre-commit` - Automated code quality checks (shellcheck, shfmt) and install package regeneration before commits
- **State Checksum Validation**: Added checksum validation for state files to detect corruption and ensure data integrity
- **State File Corruption Recovery**: Automatic detection and recovery of corrupted state files with safe defaults and backup creation
- **Development Environment Setup Script**: `scripts/setup-dev-env.sh` - Automatically configures PATH for development tools (shfmt, shellcheck) whether installed via apt or Homebrew
- **IPsec Fallback for Tier 2 Recovery**
- **CI/CD Pipeline**: GitHub Actions workflow for automated testing and validation
- **Log Analysis Tool**: `analyze-logs.sh` script for analyzing VPN failure patterns and recovery success rates
- **Per-Tunnel xfrm Recovery**: Per-tunnel recovery capability using xfrm (enabled by default for UDM OS 4.3+, `ENABLE_XFRM_RECOVERY=1`)
- **SA Rekey Detection**: Automatic detection of IPsec SA rekey events by tracking SPI (Security Parameter Index) changes to prevent false positives during normal rekey operations
- **Network Partition Detection**: Checks for local network connectivity issues (default route, DNS resolution, interface status) before assuming VPN failure, preventing unnecessary recovery actions during network outages
- **Traffic Pattern Analysis**: Enhanced idle VPN detection using traffic rate calculation and historical byte counter samples to distinguish healthy idle tunnels from broken tunnels
- **Automatic Route Management**: Automatically adds and re-adds routes to allow UDM pings to remote networks through VPN tunnels
- **Modular Library Architecture**: Complete refactoring into modular library components:
  - `lib/common.sh` - Shared logging and utility functions across scripts
  - `lib/config.sh` - Configuration loading and validation with schema support
  - `lib/config_schema.sh` - Configuration schema definitions and validation rules
  - `lib/constants.sh` - Named constants for magic numbers
  - `lib/detection.sh` - VPN status detection using xfrm, ipsec, and ping
  - `lib/lockfile.sh` - Lockfile management with flock and fallback mechanisms
  - `lib/logging.sh` - Centralized logging functionality with timestamp and level support
  - `lib/recovery.sh` - Tiered recovery actions (logging → surgical cleanup → full restart)
  - `lib/state.sh` - State file management (failure counters, cooldown, rate limiting)
- **Comprehensive Test Suite**: 
  - `test_integration.sh` - Integration tests for end-to-end scenarios
  - `test_high_risk.sh` - Tests for critical recovery actions and edge cases
  - `test_helper_functions.sh` - Unit tests for helper functions
  - `test_analyze_logs.sh` - Tests for log analysis script
- **Test Coverage Reporting**: `tests/generate_coverage_report.sh` for generating coverage reports
- **User Documentation**:
  - `QUICK_START.md` - 5-minute setup guide for new users
  - `TROUBLESHOOTING.md` - Comprehensive troubleshooting guide with common issues and solutions
- **Developer Documentation**: `DEVELOPER.md` with development setup and guidelines
- **Test Documentation**: Comprehensive `tests/README.md` with testing guidelines
- **BATS Testing Guide**: `docs/BATS_GUIDE.md` - Comprehensive guide to the BATS testing framework, including usage patterns, helper libraries, and best practices for writing tests
- **IP Address Validation**: Robust `validate_ip_address()` function supporting IPv4, IPv6, and IPv4-mapped IPv6 addresses
- **Cross-Platform Compatibility**: `get_file_mtime()` function for Linux/BSD/macOS compatibility
- **Version Information**: `--version` flag added to main script
- **Logrotate Support**: Automatic logrotate configuration during installation
- **CSV Export**: Log analysis script exports data to CSV format for spreadsheet analysis
- **Configuration Schema Validation**: Schema-based configuration validation with type checking, range validation, and default value application

### Changed
- **Documentation Improvements**: 
  - Deduplicated README.md by removing redundant "Install Package" section and consolidating Tier 2 recovery behavior explanations
  - Updated ARCHITECTURE.md with accurate Tier 2 recovery state diagram showing per-connection vs full reload logic and ipsec fallback
  - Clarified tool availability and fallback behavior throughout documentation
  - Updated all documentation files (README.md, QUICK_START.md, TROUBLESHOOTING.md, ARCHITECTURE.md) to use correct configuration variable names (`EXTERNAL_PEER_IPS` and `INTERNAL_PEER_IPS` instead of deprecated `PEER_IPS`)
- **Major Code Refactoring**: 
  - Complete modularization: Extracted all functionality into dedicated library modules
  - Reduced main script from ~1900 lines to ~530 lines through modularization
  - Extracted 9+ helper functions to reduce code duplication
  - Better separation of concerns with dedicated modules for each responsibility
- **Per-Peer Failure Tracking**: Failure counters now tracked independently per peer IP (not shared)
- **Installation Script**: 
  - Major refactoring with improved error handling, configuration management, and dev mode support
  - Removed file reorganization code (`reorganize_lib_files()` function) as the install package now preserves the correct directory structure automatically. The script now expects the `lib/` directory to be present from package extraction.
- **Uninstallation Script**: Improved crontab removal logic (preserves other cron jobs) and added logrotate configuration removal
- **Log Analysis Script**: Enhanced function documentation and improved error handling; removed dependency on `bc` utility (not available on UDM OS)
- **Log Rotation**: Extended logrotate configuration to rotate application logs (not just cron logs); moved cron logs into `/logs` subdirectory
- **Lockfile Handling**: Dedicated `lib/lockfile.sh` module with improved stale lockfile detection and atomic operations
- **Configuration Management**: New schema-based validation system with type checking, range validation, and default value application; centralized config values in schema
- **Recovery Selection Logic**: Centralized recovery strategy selection logic for better maintainability
- **Code Formatting**: Applied shfmt formatting to all shell scripts for consistent style
- **IP Address Matching**: Changed from regex-based to fixed-string matching (`grep -F`) for IP address handling in detection to prevent regex injection and improve performance
- **Test Execution**: Tests now fail fast and stream output to terminal for better CI/CD feedback; added ability to rerun only failing tests
- **Test Framework**: Migrated to use BATS functionality to replace custom testing functions; use test fixtures to DRY up test code; improved BATS CI integration
- **Installer Validation**: Installation script now fails immediately when executed with invalid flags instead of continuing
- **State File Parsing**: Improved safe parsing of state files with validation and error handling
- **Constants Centralization**: Consolidated magic numbers into named constants in `lib/constants.sh`

### Fixed
- **Security**: Added proper IP address validation to prevent injection attacks
- **Lockfile Race Conditions**: Improved atomic lockfile creation and cleanup; fixed additional race conditions
- **Exit Code Handling**: Fixed PIPESTATUS capture in pipe commands
- **Crontab Removal**: Fixed issue where uninstall could remove all cron jobs
- **Log Path Handling**: Improved log file path recalculation after config changes
- **Process Detection**: Better handling of stale processes and lockfiles
- **Error Handling**: Standardized error handling patterns across all modules
- **Byte Counter Detection**: Fixed bug causing byte counters to always show as none during checks
- **Detection Logic**: Fixed bug in detection logic that was causing incorrect failure detection
- **Dependency Issues**: Removed dependency on `bc` utility in `analyze-logs.sh` (not available on UDM OS)

### Improved
- **Code Quality**: Reduced code duplication by 20+ blocks, improved maintainability and readability with dedicated library modules; extracted duplicated code patterns (e.g., `file_exists_and_readable` function)
- **Modular Architecture**: Complete separation of functionality into dedicated modules with single responsibility per module
- **Test Coverage**: Significantly expanded test suite covering edge cases and high-risk scenarios; improved test helpers for better xfrm testing and per-tunnel reboot scenarios; expanded use of test fixtures to reduce code duplication and improve maintainability
- **Error Messages**: More descriptive error messages and logging throughout all modules
- **Documentation**: 
  - Enhanced all function documentation across entire codebase with consistent format (Arguments, Returns, Side effects, Examples, Notes)
  - Updated README.md, DEVELOPER.md, and ARCHITECTURE.md with improved structure and content
  - Added architectural review document with comprehensive analysis and recommendations
  - Added ADRs (Architecture Decision Records) documenting key design decisions
- **State Management**: Abstracted state file operations with improved checksum validation and atomic write patterns; added state file corruption recovery with automatic backup and safe defaults
- **Idle VPN Handling**: Enhanced idle VPN detection using traffic pattern analysis (traffic rate calculation, historical samples) to distinguish healthy idle tunnels from broken tunnels; improved ping-based verification for idle tunnels
- **False Positive Prevention**: SA rekey detection prevents false positives during normal IPsec rekey operations; network partition detection prevents unnecessary VPN recovery during local network outages
- **Recovery Verification**: Added verification of VPN recovery after restart to ensure recovery actions are effective

### Removed
- **swanctl Dependency**: Removed attempts to install unsupported swanctl utility on UDM OS
- **scp-files.sh**: Removed helper script for file transfer (replaced by install package method)
- **Dead Code**: Removed unused `LAST_RESTART_FILE` variable
- **Ineffective Operations**: Removed `ip xfrm state delete` commands that required full selectors
- **Generated Reports**: Removed generated report files from repository (reports/vpn-monitor-analysis.csv, reports/vpn-monitor-report.txt) - these are now generated on-demand by analyze-logs.sh
- **Deprecated Configuration**: Removed deprecated `PING_TARGET_IP` configuration variable (replaced by `INTERNAL_PEER_IPS`)
- **Deprecated State Files**: Removed deprecated `last_bytes_file` state file format (replaced by abstracted state management in `lib/state.sh`)

## [0.1.0] - 2025-12-15

### Added
- Initial release of UDM VPN Monitor
- VPN monitoring using IPsec xfrm state byte counters
- Optional ping connectivity verification
- Tiered recovery system (logging → surgical cleanup → full restart)
- Per-peer failure tracking and independent recovery actions
- Connection name auto-discovery for targeted recovery
- Safety controls: lockfiles, cooldown periods, rate limiting
- Comprehensive logging and state management
- Installation and uninstallation scripts
- Interactive and silent installation modes
- Configuration file with extensive documentation
- Comprehensive test suite using bats
- Log analysis script (`analyze-logs.sh`) for failure frequency and recovery success rate reporting
- CSV export functionality for spreadsheet analysis
- Comprehensive test suite for `analyze-logs.sh` script
- Documentation: README, ARCHITECTURE, ENHANCEMENTS

### Features
- **Detection**: Uses `ip xfrm state` byte counters to detect actual VPN traffic flow
- **Connectivity Verification**: Optional ping checks verify end-to-end tunnel connectivity
- **Tiered Recovery**: Escalates from logging → surgical SA cleanup → full restart
- **Safety Controls**: Lockfiles with timeout detection, cooldown timers, and rate limiting
- **Per-Peer Tracking**: Monitors multiple VPN peers independently
- **Connection Name Support**: Auto-discovers or manually configures connection names for targeted recovery
- **Persistent Logging**: Logs stored in `/data/` survive reboots
- **Cron-Based**: More resilient than long-running processes on UDM

### Documentation
- Comprehensive README with installation, configuration, and troubleshooting guides
- Architecture documentation explaining design decisions
- Code review findings and resolutions (documented in code comments and implementation)
- Future enhancement recommendations
- Test suite documentation

### Testing
- Comprehensive test suite covering installation, uninstallation, and monitoring functionality
- Test helpers for mocking system commands and environments
- CI-friendly test execution
