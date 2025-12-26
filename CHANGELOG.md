# Changelog

All notable changes to the UDM VPN Monitor project will be documented in this file.

## [Unreleased] - 2025-12-23

### Added
- **VPN Keepalive Daemon**: `vpn-keepalive.sh` and `vpn-keepalive.service` - Optional background daemon that sends periodic ping traffic through VPN tunnels to prevent idle timeout and keep tunnels alive
- **Architectural Review Document**: `ARCHITECTURAL_REVIEW.md` - Comprehensive architectural review with security analysis, reliability recommendations, and code quality assessments
- **Utility Availability Checker**: `check-utilities.sh` - Script to verify which Linux utilities are available on UDM OS for troubleshooting and compatibility checking
- **Pre-commit Git Hook**: `scripts/hooks/pre-commit` - Automated code quality checks (shellcheck, shfmt) and install package regeneration before commits
- **State Checksum Validation**: Added checksum validation for state files to detect corruption and ensure data integrity
- **Development Environment Setup Script**: `scripts/setup-dev-env.sh` - Automatically configures PATH for development tools (shfmt, shellcheck) whether installed via apt or Homebrew
- **IPsec Fallback for Tier 2 Recovery**
- **CI/CD Pipeline**: GitHub Actions workflow for automated testing and validation
- **Log Analysis Tool**: `analyze-logs.sh` script for analyzing VPN failure patterns and recovery success rates
- **Per-Tunnel xfrm Recovery**: Per-tunnel recovery capability using xfrm (enabled by default for UDM OS 4.3+, `ENABLE_XFRM_RECOVERY=1`)
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
- **Log Analysis Script**: Enhanced function documentation and improved error handling
- **Lockfile Handling**: Dedicated `lib/lockfile.sh` module with improved stale lockfile detection and atomic operations
- **Configuration Management**: New schema-based validation system with type checking, range validation, and default value application
- **Code Formatting**: Applied shfmt formatting to all shell scripts for consistent style
- **IP Address Matching**: Changed from regex-based to fixed-string matching (`grep -F`) for IP address handling in detection to prevent regex injection and improve performance
- **Test Execution**: Tests now fail fast and stream output to terminal for better CI/CD feedback; added ability to rerun only failing tests
- **Installer Validation**: Installation script now fails immediately when executed with invalid flags instead of continuing

### Fixed
- **Security**: Added proper IP address validation to prevent injection attacks
- **Lockfile Race Conditions**: Improved atomic lockfile creation and cleanup; fixed additional race conditions
- **Exit Code Handling**: Fixed PIPESTATUS capture in pipe commands
- **Crontab Removal**: Fixed issue where uninstall could remove all cron jobs
- **Log Path Handling**: Improved log file path recalculation after config changes
- **Process Detection**: Better handling of stale processes and lockfiles
- **Error Handling**: Standardized error handling patterns across all modules

### Improved
- **Code Quality**: Reduced code duplication by 20+ blocks, improved maintainability and readability with dedicated library modules
- **Modular Architecture**: Complete separation of functionality into dedicated modules with single responsibility per module
- **Test Coverage**: Significantly expanded test suite covering edge cases and high-risk scenarios
- **Error Messages**: More descriptive error messages and logging throughout all modules
- **Documentation**: 
  - Enhanced all function documentation across entire codebase with consistent format (Arguments, Returns, Side effects, Examples, Notes)
  - Updated README.md, DEVELOPER.md, and ARCHITECTURE.md with improved structure and content
  - Added architectural review document with comprehensive analysis and recommendations
- **State Management**: Abstracted state file operations with improved checksum validation and atomic write patterns
- **Test Quality**: Improved test helper functions for better xfrm testing and per-tunnel reboot scenarios

### Removed
- **swanctl Dependency**: Removed attempts to install unsupported swanctl utility on UDM OS
- **scp-files.sh**: Removed helper script for file transfer (replaced by install package method)
- **Dead Code**: Removed unused `LAST_RESTART_FILE` variable
- **Ineffective Operations**: Removed `ip xfrm state delete` commands that required full selectors
- **Generated Reports**: Removed generated report files from repository (reports/vpn-monitor-analysis.csv, reports/vpn-monitor-report.txt) - these are now generated on-demand by analyze-logs.sh

## [0.0.1] - 2025-12-15

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
