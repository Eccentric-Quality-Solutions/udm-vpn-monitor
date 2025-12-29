# UDM VPN Monitor Test Suite

This directory contains comprehensive tests for the UDM VPN Monitor scripts using [bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

## Test Structure

### Core Test Infrastructure
- `test_helper.bash` - Common test utilities and helper functions
- `test_helper_functions.sh` - Unit tests for individual helper functions in `vpn-monitor.sh` (118 tests)
- `run_tests.sh` - Test runner script
- `generate_coverage_report.sh` - Generates test coverage reports from kcov output

### Script-Specific Tests
- `test_install.sh` - Tests for `install.sh` script (18 tests)
- `test_uninstall.sh` - Tests for `uninstall.sh` script (34 tests)
- `test_vpn_monitor.sh` - Tests for `vpn-monitor.sh` script (33 tests)
- `test_analyze_logs.sh` - Tests for `analyze-logs.sh` script (28 tests)
- `test_check_config.sh` - Tests for `check-config.sh` script (18 tests)
- `test_check_utilities.sh` - Tests for `check-utilities.sh` script (17 tests)
- `test_vpn_keepalive.sh` - Tests for `vpn-keepalive.sh` script (18 tests)
- `test_prepare_install_package.sh` - Tests for `prepare_install_package.sh` script (12 tests)

### Integration Tests
- `test_integration.sh` - Integration tests for full monitoring flow with mock VPN states (18 tests)
- `test_integration_e2e_recovery.sh` - End-to-end recovery integration tests (6 tests)

### Configuration Tests
- `test_config.sh` - Main configuration tests (45 tests)
- `test_config_loading.sh` - Configuration loading and validation tests (6 tests)
- `test_config_validation.sh` - Configuration variable validation tests (10 tests)
- `test_config_large_values.sh` - Very large values validation tests (3 tests)
- `test_config_overrides.sh` - Path and environment variable overrides tests (4 tests)
- `test_config_security.sh` - Security-related tests (dangerous content detection) (12 tests)
- `test_config_order.sh` - Validation order dependencies tests (5 tests)
- `test_config_schema.sh` - Schema default application tests (5 tests)

### Detection Tests
- `test_detection.sh` - Main detection tests (47 tests)
- `test_detection_status.sh` - VPN status detection tests (9 tests)
- `test_detection_fallback.sh` - Fallback chain edge cases tests (6 tests)
- `test_detection_network_partition.sh` - Network partition detection tests (11 tests)
- `test_detection_rekey.sh` - SA rekey detection tests (7 tests)
- `test_detection_failure_type.sh` - Failure type detection tests (8 tests)
- `test_detection_idle.sh` - Idle tunnel detection tests (6 tests)
- `test_detection_xfrm_edge_cases.sh` - XFRM edge cases and error handling tests (13 tests)
- `test_multiple_peer_edge_cases.sh` - Multiple peer IP edge cases tests (4 tests)

### Recovery Tests
- `test_recovery.sh` - Recovery strategy selection, XFRM recovery, and fallback logic tests (17 tests)
- `test_recovery_tier1.sh` - Tier 1 (logging) recovery tests (1 test)
- `test_recovery_tier2.sh` - Tier 2 (surgical cleanup) recovery tests (7 tests)
- `test_recovery_tier3.sh` - Tier 3 (full restart) recovery tests (10 tests)
- `test_recovery_rate_limiting.sh` - Rate limiting tests (6 tests)
- `test_recovery_cooldown_rate_limit_interaction.sh` - Cooldown and rate limiting interaction tests (3 tests)
- `test_recovery_network_partition.sh` - Network partition recovery tests (3 tests)
- `test_recovery_partial_failures.sh` - Partial failure recovery tests (4 tests)

### Other High-Risk Tests
- `test_lockfile.sh` - Lockfile management tests (18 tests)
- `test_state.sh` - State file management tests (25 tests)
- `test_state_concurrent_updates.sh` - Concurrent state update tests (9 tests)
- `test_logging.sh` - Logging failure scenario tests (8 tests)
- `test_connection.sh` - Connection name discovery and caching tests (8 tests)
- `test_errors.sh` - Error handling during critical operations tests (3 tests)
- `test_main.sh` - Main execution edge cases tests (25 tests)
- `test_rapid_state_changes.sh` - Rapid state change handling tests (6 tests)
- `test_resources.sh` - Resource monitoring tests (CPU, RAM, disk) (25 tests)

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

### Performance Optimization

- **GNU parallel** or **rush** - For parallel test execution (significantly faster)
  - macOS: `brew install parallel`
  - Ubuntu/Debian: `sudo apt-get install parallel`
  - Fedora/RHEL: `sudo dnf install parallel`
  
  Parallel execution can reduce test time by 3-4x on multi-core systems. The test runner
  will automatically detect and use parallel execution if available (see [Parallel Execution](#parallel-execution) below).

## Running Tests

### Run Fast Tests (Default)

By default, slow tests are excluded to speed up local development:

```bash
./tests/run_tests.sh
```

This runs:
- `test_analyze_logs.sh` (28 tests)
- `test_check_config.sh` (18 tests)
- `test_helper_functions.sh` (118 tests)
- `test_install.sh` (18 tests)
- `test_uninstall.sh` (34 tests)
- `test_vpn_monitor.sh` (33 tests)
- `test_prepare_install_package.sh` (12 tests)
- Configuration tests (split files): `test_config_loading.sh`, `test_config_validation.sh`, `test_config_large_values.sh`, `test_config_overrides.sh`, `test_config_security.sh`, `test_config_order.sh`, `test_config_schema.sh` (45 tests)
- Detection tests (split files): `test_detection_status.sh`, `test_detection_fallback.sh`, `test_detection_network_partition.sh`, `test_detection_rekey.sh`, `test_detection_failure_type.sh`, `test_detection_idle.sh`, `test_detection_xfrm_edge_cases.sh`, `test_multiple_peer_edge_cases.sh` (58 tests)
- Recovery tests (split files): `test_recovery_tier1.sh`, `test_recovery_tier2.sh`, `test_recovery_tier3.sh`, `test_recovery_rate_limiting.sh`, `test_recovery_cooldown_rate_limit_interaction.sh`, `test_recovery_network_partition.sh`, `test_recovery_partial_failures.sh` (34 tests)
- Other tests: `test_state_concurrent_updates.sh`, `test_rapid_state_changes.sh` (15 tests)

**Total**: 419 fast tests

### Run All Tests (Including Slow Tests)

To include slow tests (integration and high-risk tests):

```bash
./tests/run_tests.sh --slow
# or
RUN_SLOW_TESTS=1 ./tests/run_tests.sh
```

Slow tests include:
- `test_integration.sh` - Integration tests for full monitoring flow (18 tests)
- `test_integration_e2e_recovery.sh` - End-to-end recovery integration tests (6 tests)
- `test_config.sh` - Main configuration tests (45 tests)
- `test_detection.sh` - Main detection tests (47 tests)
- `test_recovery.sh` - Recovery strategy selection, XFRM recovery, and fallback logic tests (17 tests)
- `test_lockfile.sh` - Lockfile management tests (18 tests)
- `test_state.sh` - State file management tests (25 tests)
- `test_logging.sh` - Logging failure scenario tests (8 tests)
- `test_connection.sh` - Connection name discovery and caching tests (8 tests)
- `test_errors.sh` - Error handling during critical operations tests (3 tests)
- `test_main.sh` - Main execution edge cases tests (25 tests)

**Total**: 220 slow tests

### Run with Coverage

```bash
./tests/run_tests.sh --coverage          # Fast tests only
./tests/run_tests.sh --slow --coverage    # All tests with coverage
```

See [Test Coverage Reporting](#test-coverage-reporting) section for details.

### Parallel Execution

The test runner supports parallel execution to significantly reduce test time. By default, parallel execution is enabled if GNU parallel or rush is installed.

```bash
# Auto-detect CPU cores (default)
./tests/run_tests.sh

# Use specific number of parallel jobs
./tests/run_tests.sh --jobs 8

# Disable parallel execution
./tests/run_tests.sh --jobs 0

# Set via environment variable
PARALLEL_JOBS=4 ./tests/run_tests.sh
```

**Performance Impact:**
- Without parallel: ~15 minutes (all tests)
- With parallel (8 jobs): ~3-5 minutes (all tests)
- With parallel (fast tests only): ~1-2 minutes

**Requirements:**
- GNU parallel or rush must be installed
- If not available, tests run sequentially (still works, just slower)

**Note:** Coverage reporting may be slower with parallel execution due to kcov overhead, but is still supported.

### Run Specific Test File

```bash
# Script-specific tests
bats tests/test_install.sh
bats tests/test_uninstall.sh
bats tests/test_vpn_monitor.sh
bats tests/test_analyze_logs.sh
bats tests/test_check_config.sh
bats tests/test_prepare_install_package.sh

# Integration tests
bats tests/test_integration.sh
bats tests/test_integration_e2e_recovery.sh

# Configuration tests
bats tests/test_config.sh
bats tests/test_config_loading.sh
bats tests/test_config_validation.sh
bats tests/test_config_security.sh
# ... or run all config tests: bats tests/test_config*.sh

# Detection tests
bats tests/test_detection.sh
bats tests/test_detection_status.sh
bats tests/test_detection_network_partition.sh
bats tests/test_detection_xfrm_edge_cases.sh
# ... or run all detection tests: bats tests/test_detection*.sh

# Recovery tests
bats tests/test_recovery.sh
bats tests/test_recovery_tier1.sh
bats tests/test_recovery_cooldown_rate_limit_interaction.sh
bats tests/test_recovery_network_partition.sh
bats tests/test_recovery_partial_failures.sh
# ... or run all recovery tests: bats tests/test_recovery*.sh

# Other high-risk tests
bats tests/test_lockfile.sh
bats tests/test_state.sh
bats tests/test_state_concurrent_updates.sh
bats tests/test_main.sh
bats tests/test_rapid_state_changes.sh
```

## Test Categories

### Fast Tests (run by default)
- `test_analyze_logs.sh` - Log analysis script tests (28 tests)
- `test_check_config.sh` - Configuration validation script tests (18 tests)
- `test_helper_functions.sh` - Unit tests for helper functions (118 tests)
- `test_install.sh` - Installation script tests (18 tests)
- `test_uninstall.sh` - Uninstallation script tests (34 tests)
- `test_vpn_monitor.sh` - Core VPN monitor functionality tests (33 tests)
- `test_prepare_install_package.sh` - Package preparation script tests (12 tests)
- Configuration tests (split files) - Configuration loading, validation, security, etc. (45 tests)
- Detection tests (split files) - VPN status detection, network partition, rekey, etc. (58 tests)
- Recovery tests (split files) - Recovery strategy, tier tests, rate limiting (34 tests)
- Other tests - State concurrent updates, rapid state changes (15 tests)

### Slow Tests (excluded by default)
- `test_integration.sh` - Integration tests for full monitoring flow (18 tests)
- `test_integration_e2e_recovery.sh` - End-to-end recovery integration tests (6 tests)
- `test_config.sh` - Main configuration tests (45 tests)
- `test_detection.sh` - Main detection tests (47 tests)
- `test_recovery.sh` - Recovery strategy selection, XFRM recovery, and fallback logic tests (17 tests)
- `test_lockfile.sh` - Lockfile management tests (18 tests)
- `test_state.sh` - State file management tests (25 tests)
- `test_logging.sh` - Logging failure scenario tests (8 tests)
- `test_connection.sh` - Connection name discovery and caching tests (8 tests)
- `test_errors.sh` - Error handling during critical operations tests (3 tests)
- `test_main.sh` - Main execution edge cases tests (25 tests)

**Total Test Count**: 639 tests across all test files

**Note**: Slow tests are automatically included in CI/CD via the `RUN_SLOW_TESTS=1` environment variable (see `.github/workflows/tests.yml`).

### Run Specific Test

```bash
bats tests/test_install.sh -t "install.sh creates installation directory"
```

### Run Tests Starting from a Specific Test Number

**Note**: BATS does not natively support starting from a specific test number. After reviewing the [official BATS documentation](https://bats-core.readthedocs.io/en/stable/) and community discussions, there is no built-in feature for this. However, there are several practical workarounds:

#### Method 1: Run Specific Test Files (Recommended)

The most straightforward approach is to run only the test files that contain tests starting from your desired test number.

**Test File Ranges:**

To find which test file contains a specific test number, use the script provided below. Test files are run in alphabetical order, so the ranges depend on the execution order.

**Example: Run from a specific test file onwards**

If you know which test file contains the test you want to start from:

```bash
# Run specific test files and all subsequent ones
bats tests/test_detection.sh tests/test_recovery.sh tests/test_state.sh

# With parallelization (if GNU parallel is installed)
bats --jobs auto tests/test_detection.sh tests/test_recovery.sh tests/test_state.sh

# Or using the test runner (includes slow tests by default)
./tests/run_tests.sh --slow
```

#### Method 2: Filter by Test Name Pattern

If your test names follow a pattern, you can use BATS' `--filter` option with regex:

```bash
# Run tests matching a pattern (regex)
bats tests/test_helper_functions.sh -f "check_xfrm_status"

# Run tests NOT matching a pattern
bats tests/test_helper_functions.sh --negative-filter "skip"

# Example: Run tests with names containing "147" or higher numbers
bats tests/test_*.sh -f "test.*(14[7-9]|1[5-9][0-9]|[2-9][0-9][0-9])"
```

#### Method 3: Use Test Tags (Requires Pre-tagging)

BATS supports tagging tests (version 1.8.0+). You can tag tests and filter by tags:

```bash
# In your test file, add tags:
# bats test_tags=number:147
@test "check_xfrm_status detects rekey when SPI changes" {
  # test code
}

# Then run with:
bats --filter-tags number:147 tests/test_helper_functions.sh
```

**Note**: This method requires manually tagging tests beforehand, which may not be practical for large test suites.

#### Method 4: Resume Failed Tests

If tests failed previously and you want to rerun only failed tests:

```bash
# Rerun only tests that failed in the last completed run
bats --filter-status failed tests/test_*.sh

# Or use the test runner
./tests/run_tests.sh --failed
```

**Finding Which Test File Contains a Specific Test Number:**

```bash
# Count tests in each file to find test ranges
total=0
for f in tests/test_*.sh; do
  count=$(grep -c '^@test' "$f" 2>/dev/null || echo 0)
  echo "$f: $count (tests $((total + 1))-$((total + count)))"
  total=$((total + count))
done
```

**References:**
- [BATS Official Documentation](https://bats-core.readthedocs.io/en/stable/)
- [BATS Writing Tests Guide](https://bats-core.readthedocs.io/en/latest/writing-tests.html)

### Verbose Output

```bash
bats --verbose tests/test_*.sh
```

### Tap Format (for CI)

```bash
bats --tap tests/test_*.sh
```

## Test Coverage

Current test coverage: **46.9%** (1141/2433 lines) as of latest run.

### High-Risk Tests

The test suite includes comprehensive tests for critical paths and error handling scenarios that could cause production failures. These tests are distributed across multiple test files for better organization:

#### Test Categories

**1. Lockfile Management** (`test_lockfile.sh` - 18 tests)
Tests lockfile cleanup, error handling, race conditions, and edge cases.

**2. Configuration Loading and Validation** (`test_config.sh` and split files - 90 tests total)
Tests configuration file error handling, security, validation, and edge cases.

**3. VPN Status Detection** (`test_detection.sh` and split files - 105 tests total)
Tests VPN detection edge cases, byte counter handling, fallback mechanisms, network partitions, rekey detection, and XFRM edge cases.

**4. Recovery Actions** (`test_recovery.sh` and split files - 51 tests total)
Tests recovery action execution, error handling, tier-based recovery, rate limiting, cooldown interactions, and partial failures.

**5. State and File Management** (`test_state.sh` and `test_state_concurrent_updates.sh` - 34 tests total)
Tests state file handling, permissions, corruption, concurrent updates, and edge cases.

**6. Logging** (`test_logging.sh` - 8 tests)
Tests logging failure scenarios and error handling.

**7. Connection Management** (`test_connection.sh` - 8 tests)
Tests connection name discovery, caching, and edge cases.

**8. Error Handling** (`test_errors.sh` - 3 tests)
Tests error handling during critical operations.

**9. Main Execution** (`test_main.sh` - 25 tests)
Tests main execution edge cases and error scenarios.

**10. Rapid State Changes** (`test_rapid_state_changes.sh` - 6 tests)
Tests handling of rapid state changes and race conditions.

#### Test Statistics

- **Total High-Risk Tests**: ~250+ tests across multiple files
- **Test Categories**: 10 main categories
- **Focus Areas**: Critical error handling, edge cases, security, race conditions, resource management

#### CI Integration

The high-risk tests are automatically included in CI when `RUN_SLOW_TESTS=1` is set because:
1. `run_tests.sh` automatically discovers all `test_*.sh` files
2. High-risk test files are marked as slow tests
3. CI runs `./tests/run_tests.sh --slow` which includes all test files

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

### vpn-keepalive.sh Tests

- ✅ Script existence and executability
- ✅ Help message display
- ✅ Version information
- ✅ Start daemon functionality
- ✅ Stop daemon functionality
- ✅ Status check functionality
- ✅ Restart functionality
- ✅ Configuration validation
- ✅ Multiple peer IPs handling
- ✅ IPv6 support
- ✅ Disabled keepalive handling
- ✅ Already running daemon handling

### check-utilities.sh Tests

- ✅ Script existence and executability
- ✅ Utility availability checking
- ✅ Available utilities reporting
- ✅ Missing utilities reporting
- ✅ Summary statistics
- ✅ Colored output
- ✅ Common utilities checking
- ✅ Network utilities checking
- ✅ System monitoring utilities checking
- ✅ Text processing utilities checking

### lib/resources.sh Tests

- ✅ Library file existence
- ✅ CPU usage calculation
- ✅ Memory usage calculation
- ✅ Disk usage calculation
- ✅ Free disk space calculation
- ✅ Resource constraint tracking
- ✅ System resource throttling
- ✅ Log file rotation on low disk
- ✅ Configuration threshold usage
- ✅ Error handling

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

- `setup_test_config()` - Create a test config file with common settings
- `create_test_vpn_monitor_script()` - Create a test version of the VPN monitor script
- `create_test_install_setup()` - Set up test installation environment
- `assert_file_executable()` - Assert that a file exists and is executable
- `create_test_cron_entry()` - Create a test cron entry
- `assert_log_contains()` / `assert_log_not_contains()` - Check log files
- `mock_ip_xfrm_state()` - Mock `ip xfrm state` output
- `mock_ping()` - Mock ping command
- `mock_ipsec()` - Mock ipsec command
- `setup_test_vpn_monitor()` - Set up complete VPN monitor test environment
- `setup_state_files()` - Set up state files for testing
- `setup_mock_vpn_environment()` - Set up mock VPN environment

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

### CI/CD Integration

Example GitHub Actions workflow:

```yaml
- name: Install bats
  run: |
    git clone https://github.com/bats-core/bats-core.git
    cd bats-core
    sudo ./install.sh /usr/local

- name: Install kcov for coverage
  run: |
    sudo apt-get update && sudo apt-get install -y kcov

- name: Run tests with coverage
  run: |
    RUN_SLOW_TESTS=1 ./tests/run_tests.sh --coverage

- name: Upload coverage report
  uses: codecov/codecov-action@v3
  with:
    files: ./coverage/index.json
    flags: unittests
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

