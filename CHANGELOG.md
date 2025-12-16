# Changelog

All notable changes to the UDM VPN Monitor project will be documented in this file.

## [Unreleased]

### Added
- **CI/CD Pipeline**: GitHub Actions workflow for automated testing and validation
- **Log Analysis Tool**: `analyze-logs.sh` script for analyzing VPN failure patterns and recovery success rates
- **Shared Library**: `lib/common.sh` for shared logging and utility functions across scripts
- **Comprehensive Test Suite**: 
  - `test_integration.sh` - Integration tests for end-to-end scenarios
  - `test_high_risk.sh` - Tests for critical recovery actions and edge cases
  - `test_helper_functions.sh` - Unit tests for helper functions
  - `test_analyze_logs.sh` - Tests for log analysis script
- **Test Coverage Reporting**: `tests/generate_coverage_report.sh` for generating coverage reports
- **Developer Documentation**: `DEVELOPER.md` with development setup and guidelines
- **Test Documentation**: Comprehensive `tests/README.md` with testing guidelines
- **IP Address Validation**: Robust `validate_ip_address()` function supporting IPv4, IPv6, and IPv4-mapped IPv6 addresses
- **Cross-Platform Compatibility**: `get_file_mtime()` function for Linux/BSD/macOS compatibility
- **Version Information**: `--version` flag added to main script
- **Logrotate Support**: Automatic logrotate configuration during installation
- **CSV Export**: Log analysis script exports data to CSV format for spreadsheet analysis

### Changed
- **Major Code Refactoring**: 
  - Extracted 9 helper functions to reduce code duplication
  - Improved lockfile handling with dedicated helper functions
  - Enhanced error handling and logging consistency
  - Better separation of concerns
- **Per-Peer Failure Tracking**: Failure counters now tracked independently per peer IP (not shared)
- **Surgical Cleanup**: Removed ineffective `ip xfrm state delete` commands; relies on `swanctl --reload-conn` for targeted recovery
- **Installation Script**: 
  - Major refactoring with improved error handling
  - Better configuration management
  - Enhanced logging and user feedback
  - Improved dev mode support
- **Uninstallation Script**: 
  - Improved crontab removal logic (preserves other cron jobs)
  - Added logrotate configuration removal
  - Better error handling and verification
- **Lockfile Handling**: 
  - Improved stale lockfile detection
  - Better process checking
  - More robust atomic operations
- **PIPESTATUS Handling**: Fixed exit code capture in `full_restart()` function
- **Configuration**: Updated comments to reflect per-peer failure tracking
- **Documentation**: 
  - Enhanced README with more detailed explanations
  - Updated ARCHITECTURE.md with latest design decisions
  - Comprehensive ENHANCEMENTS.md with completed improvements

### Fixed
- **Security**: Added proper IP address validation to prevent injection attacks
- **Lockfile Race Conditions**: Improved atomic lockfile creation and cleanup
- **Exit Code Handling**: Fixed PIPESTATUS capture in pipe commands
- **Crontab Removal**: Fixed issue where uninstall could remove all cron jobs
- **Log Path Handling**: Improved log file path recalculation after config changes
- **Process Detection**: Better handling of stale processes and lockfiles

### Improved
- **Code Quality**: 
  - Reduced code duplication by 20+ blocks
  - Improved maintainability and readability
  - Consistent error handling patterns
  - Better function documentation
- **Test Coverage**: Significantly expanded test suite covering edge cases and high-risk scenarios
- **Error Messages**: More descriptive error messages and logging
- **Documentation**: Enhanced inline documentation and user-facing docs

### Removed
- **Dead Code**: Removed unused `LAST_RESTART_FILE` variable
- **Ineffective Operations**: Removed `ip xfrm state delete` commands that required full selectors

## [0.0.1] - 2025-12-16

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
