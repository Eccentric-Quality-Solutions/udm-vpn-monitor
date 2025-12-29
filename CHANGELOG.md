# Changelog

All notable changes to the UDM VPN Monitor project will be documented in this file.

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
