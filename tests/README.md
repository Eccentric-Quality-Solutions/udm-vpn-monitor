# UDM VPN Monitor Test Suite

This directory contains comprehensive tests for the UDM VPN Monitor scripts using [bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

## Test Structure

- `test_helper.bash` - Common test utilities and helper functions
- `test_helper_functions.sh` - Unit tests for individual helper functions in `vpn-monitor.sh`
- `test_integration.sh` - Integration tests for full monitoring flow with mock VPN states
- `test_high_risk.sh` - **High-risk tests** for critical paths and error handling scenarios (31 tests)
- `test_install.sh` - Tests for `install.sh` script
- `test_uninstall.sh` - Tests for `uninstall.sh` script
- `test_vpn_monitor.sh` - Tests for `vpn-monitor.sh` script
- `test_analyze_logs.sh` - Tests for `analyze-logs.sh` script
- `test_prepare_install_package.sh` - Tests for `prepare_install_package.sh` script
- `run_tests.sh` - Test runner script
- `generate_coverage_report.sh` - Generates test coverage reports from kcov output

## Prerequisites

### Required

- **bats-core** (version 1.x or higher)
  - Installation: See [bats-core documentation](https://github.com/bats-core/bats-core#installation)
  - macOS: `brew install bats-core`
  - Linux: Install from source or use package manager

### Optional (Recommended)

- **bats-support** - Additional assertion helpers
- **bats-assert** - More assertion functions
- **bats-file** - File system assertions

These can be installed using:
```bash
./install_bats_helpers.sh
```

## Running Tests

### Run Fast Tests (Default)

By default, slow tests are excluded to speed up local development:

```bash
./tests/run_tests.sh
```

This runs:
- `test_analyze_logs.sh`
- `test_helper_functions.sh`
- `test_install.sh`
- `test_uninstall.sh`
- `test_vpn_monitor.sh`

### Run All Tests (Including Slow Tests)

To include slow tests (integration and high-risk tests):

```bash
./tests/run_tests.sh --slow
# or
RUN_SLOW_TESTS=1 ./tests/run_tests.sh
```

Slow tests include:
- `test_integration.sh` - Integration tests for full monitoring flow
- `test_high_risk.sh` - High-risk edge case and error handling tests

### Run with Coverage

```bash
./tests/run_tests.sh --coverage          # Fast tests only
./tests/run_tests.sh --slow --coverage    # All tests with coverage
```

### Run Specific Test File

```bash
bats tests/test_install.sh
bats tests/test_uninstall.sh
bats tests/test_vpn_monitor.sh
bats tests/test_integration.sh
bats tests/test_high_risk.sh
bats tests/test_analyze_logs.sh
```

### Run High-Risk Tests

The high-risk test suite focuses on critical paths and error handling scenarios:

```bash
# Run all high-risk tests
bats tests/test_high_risk.sh

# Run via test runner (includes all tests)
./tests/run_tests.sh --slow

# Run a specific test
bats tests/test_high_risk.sh -f "lockfile cleanup"
```

## Test Categories

### Fast Tests (run by default)
- `test_analyze_logs.sh` - Log analysis script tests
- `test_helper_functions.sh` - Unit tests for helper functions
- `test_install.sh` - Installation script tests
- `test_uninstall.sh` - Uninstallation script tests
- `test_vpn_monitor.sh` - Core VPN monitor functionality tests

### Slow Tests (excluded by default)
- `test_integration.sh` - Integration tests for full monitoring flow
- `test_high_risk.sh` - High-risk edge case and error handling tests

**Note**: Slow tests are automatically included in CI/CD via the `RUN_SLOW_TESTS=1` environment variable (see `.github/workflows/tests.yml`).

### Run Specific Test

```bash
bats tests/test_install.sh -t "install.sh creates installation directory"
```

### Verbose Output

```bash
bats --verbose tests/test_*.sh
```

### Tap Format (for CI)

```bash
bats --tap tests/test_*.sh
```

### Run Tests with Coverage Reporting

```bash
# Run tests with coverage (requires kcov)
./tests/run_tests.sh --coverage

# Or use short form
./tests/run_tests.sh -c
```

Coverage reports are generated in the `coverage/` directory:
- **HTML Report**: `coverage/index.html` - Interactive coverage report
- **Summary**: `coverage/summary.txt` - Text summary of coverage
- **JSON Data**: `coverage/index.json` - Machine-readable coverage data

To generate a coverage summary report:
```bash
./tests/generate_coverage_report.sh
```

**Prerequisites for Coverage**:
- [kcov](https://github.com/SimonKagstrom/kcov) must be installed
  - macOS: `brew install kcov`
  - Ubuntu/Debian: `sudo apt-get install kcov`
  - Fedora/RHEL: `sudo dnf install kcov`
  - Or build from source (see kcov GitHub repository)

**Optional**: Install `jq` for detailed coverage statistics in summaries
- macOS: `brew install jq`
- Ubuntu/Debian: `sudo apt-get install jq`
- Fedora/RHEL: `sudo dnf install jq`

## Test Coverage

Current test coverage: **26.7%** (532/1993 lines) as of latest run.

### High-Risk Tests (test_high_risk.sh)

The `test_high_risk.sh` file contains comprehensive tests for critical paths and error handling scenarios that could cause production failures. These tests focus on areas identified as **Critical Priority** in the test coverage gaps analysis.

#### Overview

The high-risk test suite includes **31 tests** covering critical paths and error handling scenarios across 4 main categories:

#### Test Categories

**1. Lockfile Management (4 tests)**
Tests lockfile cleanup, error handling, and edge cases:
- ✅ Lockfile cleanup on script exit
- ✅ Lockfile cleanup on script error
- ✅ Lockfile contains invalid format
- ✅ Lockfile timestamp at timeout boundary

**2. Configuration Loading and Validation (7 tests)**
Tests configuration file error handling, security, and validation:
- ✅ Config file contains syntax errors
- ✅ Config file is unreadable (permission denied)
- ✅ Config file is a directory instead of file
- ✅ LOG_FILE override in config recalculates LOGS_DIR
- ✅ Negative threshold values in config
- ✅ Threshold values out of order
- ✅ Config file attempts command injection via variable

**3. VPN Status Detection (11 tests)**
Tests VPN detection edge cases, byte counter handling, and fallback mechanisms:
- ✅ xfrm SA exists but byte counter is exactly 0
- ✅ xfrm SA exists but byte counter decreases (wrap-around)
- ✅ xfrm SA exists but byte counter stays same
- ✅ Byte counter file corrupted (non-numeric)
- ✅ Byte counter file contains negative number
- ✅ Byte counter file is empty
- ✅ Byte counter file is directory
- ✅ All detection methods unavailable
- ✅ xfrm output contains multiple lifetime lines
- ✅ xfrm command fails with permission denied
- ✅ Ping check enabled but PING_TARGET_IP not set

**4. Recovery Actions (9 tests)**
Tests recovery action execution, error handling, and verification:
- ✅ Surgical cleanup with connection name configured (per-connection reload)
- ✅ Surgical cleanup without connection name (full reload)
- ✅ Surgical cleanup fails - error handling
- ✅ Surgical cleanup connection name reload fails - fallback to full reload
- ✅ Full restart with ipsec command
- ✅ Full restart fails - error handling
- ✅ Full restart when neither ipsec nor swanctl available
- ✅ Rate limit file corrupted
- ✅ Failure counter file is directory

#### Test Statistics

- **Total Tests**: 31
- **Test Categories**: 4
- **Focus Areas**: Critical error handling, edge cases, security

#### Test Results

All 31 tests pass successfully. Tests verify:
- ✅ Error handling doesn't crash the script
- ✅ Edge cases are handled gracefully
- ✅ Security concerns (command injection) are mitigated
- ✅ Recovery actions execute correctly
- ✅ Fallback mechanisms work as expected

#### CI Integration

The high-risk tests are automatically included in CI because:
1. `run_tests.sh` automatically discovers all `test_*.sh` files
2. CI runs `./tests/run_tests.sh` which includes all test files
3. No additional CI configuration needed

#### Maintenance

When adding new high-risk scenarios:
1. Add tests to `test_high_risk.sh`
2. Follow existing test patterns
3. Use helper functions from `test_helper.bash`
4. Ensure tests are isolated and don't depend on each other
5. Run tests locally before committing

For more information on test coverage gaps, see [TEST_COVERAGE_GAPS.md](../TEST_COVERAGE_GAPS.md).

### install.sh Tests

- ✅ Script existence and executability
- ✅ Help message display
- ✅ Root user requirement (non-dev mode)
- ✅ Dev mode functionality
- ✅ Installation directory creation
- ✅ Script installation
- ✅ Config file handling (create, preserve, overwrite)
- ✅ Cron job setup and skipping
- ✅ Cron schedule from config
- ✅ Installation verification
- ✅ Error handling

### uninstall.sh Tests

- ✅ Script existence and executability
- ✅ Root user requirement
- ✅ Missing installation handling
- ✅ Installation directory removal
- ✅ Cron entry removal
- ✅ Uninstallation verification
- ✅ Interactive confirmation prompts
- ✅ Non-interactive mode (`--yes` flag)
- ✅ CI environment detection
- ✅ Lockfile cleanup

### vpn-monitor.sh Tests

- ✅ Script existence and executability
- ✅ Help message display
- ✅ Configuration loading
- ✅ State file initialization
- ✅ Log file creation
- ✅ Peer IP validation
- ✅ Multiple peer IPs handling
- ✅ Failure counter management
- ✅ Cooldown period handling
- ✅ Lockfile management
- ✅ Ping check functionality
- ✅ Debug mode
- ✅ Cron persistence checking

## Writing New Tests

### Test File Structure

```bash
#!/usr/bin/env bats
#
# Description of what this test file tests

load test_helper

@test "test name" {
    # Setup
    local test_var="value"
    
    # Execute
    run bash "$SCRIPT_PATH" --flag
    
    # Assert
    assert_success
    assert_output --partial "expected output"
}
```

### Helper Functions

The `test_helper.bash` file provides many useful functions:

- `create_mock_config()` - Create a test config file
- `create_mock_vpn_monitor_script()` - Create a mock script
- `mock_root()` / `mock_non_root()` - Mock user permissions
- `mock_udm_system()` / `mock_non_udm_system()` - Mock system environment
- `assert_cron_entry_exists()` / `assert_cron_entry_not_exists()` - Check cron entries
- `assert_log_contains()` / `assert_log_not_contains()` - Check log files
- `mock_ip_xfrm_state()` - Mock `ip xfrm state` output
- `mock_ping()` - Mock ping command
- `mock_ipsec()` - Mock ipsec command

### Best Practices

1. **Use setup/teardown**: Each test gets a clean environment
2. **Isolate tests**: Tests should not depend on each other
3. **Mock external commands**: Use mock functions for system commands
4. **Clean up**: Use teardown to remove temporary files
5. **Test both success and failure cases**: Cover error paths
6. **Use descriptive test names**: Make it clear what is being tested

## Test Coverage Reporting

The test suite supports code coverage reporting using [kcov](https://github.com/SimonKagstrom/kcov).

### Running Tests with Coverage

```bash
# Enable coverage reporting
./tests/run_tests.sh --coverage
```

Coverage reports include:
- **HTML Report**: Interactive browser-based report showing line-by-line coverage
- **Text Summary**: Coverage percentages and statistics
- **JSON Data**: Machine-readable coverage data for CI/CD integration

### Coverage Reports Location

All coverage reports are generated in the `coverage/` directory:
- `coverage/index.html` - Main HTML report (open in browser)
- `coverage/summary.txt` - Text summary
- `coverage/index.json` - JSON data for programmatic access

### Generating Coverage Summary

After running tests with coverage, generate a summary report:

```bash
./tests/generate_coverage_report.sh
```

This creates a text summary with coverage percentages per file.

### Coverage in CI/CD

Example GitHub Actions workflow with coverage:

```yaml
- name: Install dependencies
  run: |
    # Install bats
    git clone https://github.com/bats-core/bats-core.git
    cd bats-core
    sudo ./install.sh /usr/local
    
    # Install kcov for coverage
    sudo apt-get update && sudo apt-get install -y kcov

- name: Run tests with coverage
  run: ./tests/run_tests.sh --coverage

- name: Upload coverage report
  uses: codecov/codecov-action@v3
  with:
    files: ./coverage/index.json
    flags: unittests
```

### What Gets Covered

Coverage reporting tracks execution of:
- `vpn-monitor.sh` - Main monitoring script
- `install.sh` - Installation script
- `uninstall.sh` - Uninstallation script
- `lib/common.sh` - Shared library functions

Test files and helper scripts are excluded from coverage reports.

## Continuous Integration

Tests can be run in CI environments. The test suite:

- Works in non-interactive mode
- Cleans up after itself
- Uses temporary directories
- Doesn't require root (for most tests)
- Can run in parallel (with proper isolation)
- Supports coverage reporting with kcov

### Example CI Configuration

```yaml
# GitHub Actions example
- name: Install bats
  run: |
    git clone https://github.com/bats-core/bats-core.git
    cd bats-core
    sudo ./install.sh /usr/local

- name: Run tests
  run: ./tests/run_tests.sh

- name: Run tests with coverage
  run: |
    sudo apt-get update && sudo apt-get install -y kcov
    ./tests/run_tests.sh --coverage
```

## Troubleshooting

### Tests Fail with Permission Errors

- Some tests require root access (install/uninstall tests)
- Run with `sudo` if needed: `sudo bats tests/test_install.sh`
- Or use `--dev` mode in tests to avoid root requirement

### Tests Fail Due to Missing Commands

- Tests use mocks for system commands
- Ensure mock functions are properly set up
- Check PATH includes test directory with mocks

### Tests Leave Temporary Files

- Tests should clean up in teardown
- Check `TEST_TMPDIR` environment variable
- Manually clean `/tmp/bats-test-*` if needed

### Bats Helpers Not Found

- Install optional helper libraries
- Or modify tests to not require them
- Tests will work without helpers but with fewer assertions

## Contributing

When adding new features:

1. Add tests for new functionality
2. Ensure all tests pass
3. Update this README if adding new test utilities
4. Follow existing test patterns and conventions

## See Also

- [bats-core documentation](https://github.com/bats-core/bats-core)
- [bats-assert documentation](https://github.com/bats-core/bats-assert)
- [bats-file documentation](https://github.com/bats-core/bats-file)

