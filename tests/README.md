# UDM VPN Monitor Test Suite

This directory contains comprehensive tests for the UDM VPN Monitor scripts using [bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

## Test Structure

- `test_helper.bash` - Common test utilities and helper functions
- `test_helper_functions.sh` - Unit tests for individual helper functions in `vpn-monitor.sh` (119 tests)
- `test_integration.sh` - Integration tests for full monitoring flow with mock VPN states (18 tests)
- `test_high_risk.sh` - **High-risk tests** for critical paths and error handling scenarios (127 tests)
- `test_install.sh` - Tests for `install.sh` script (18 tests)
- `test_uninstall.sh` - Tests for `uninstall.sh` script (34 tests)
- `test_vpn_monitor.sh` - Tests for `vpn-monitor.sh` script (33 tests)
- `test_analyze_logs.sh` - Tests for `analyze-logs.sh` script (28 tests)
- `test_check_config.sh` - Tests for `check-config.sh` script (18 tests)
- `test_prepare_install_package.sh` - Tests for `prepare_install_package.sh` script (12 tests)
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
- `test_helper_functions.sh` (119 tests)
- `test_install.sh` (18 tests)
- `test_uninstall.sh` (34 tests)
- `test_vpn_monitor.sh` (33 tests)
- `test_prepare_install_package.sh` (12 tests)

**Total**: 262 fast tests

### Run All Tests (Including Slow Tests)

To include slow tests (integration and high-risk tests):

```bash
./tests/run_tests.sh --slow
# or
RUN_SLOW_TESTS=1 ./tests/run_tests.sh
```

Slow tests include:
- `test_integration.sh` - Integration tests for full monitoring flow (18 tests)
- `test_high_risk.sh` - High-risk edge case and error handling tests (127 tests)

**Total**: 145 slow tests

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
bats tests/test_install.sh
bats tests/test_uninstall.sh
bats tests/test_vpn_monitor.sh
bats tests/test_integration.sh
bats tests/test_high_risk.sh
bats tests/test_analyze_logs.sh
bats tests/test_check_config.sh
bats tests/test_prepare_install_package.sh
```

## Test Categories

### Fast Tests (run by default)
- `test_analyze_logs.sh` - Log analysis script tests (28 tests)
- `test_check_config.sh` - Configuration validation script tests (18 tests)
- `test_helper_functions.sh` - Unit tests for helper functions (119 tests)
- `test_install.sh` - Installation script tests (18 tests)
- `test_uninstall.sh` - Uninstallation script tests (34 tests)
- `test_vpn_monitor.sh` - Core VPN monitor functionality tests (33 tests)
- `test_prepare_install_package.sh` - Package preparation script tests (12 tests)

### Slow Tests (excluded by default)
- `test_integration.sh` - Integration tests for full monitoring flow (18 tests)
- `test_high_risk.sh` - High-risk edge case and error handling tests (127 tests)

**Total Test Count**: 389 tests across all test files

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
- Tests 1-28: `test_analyze_logs.sh`
- Tests 29-46: `test_check_config.sh`
- Tests 47-165: `test_helper_functions.sh`
- Tests 166-292: `test_high_risk.sh`
- Tests 293-310: `test_install.sh`
- Tests 311-328: `test_integration.sh`
- Tests 329-340: `test_prepare_install_package.sh`
- Tests 323-356: `test_uninstall.sh`
- Tests 357-389: `test_vpn_monitor.sh`

**Example: Run from test 147 onwards**

Test 147 is the first test in `test_high_risk.sh`. To run from test 147:

```bash
# Run test_high_risk.sh and all subsequent test files
bats tests/test_high_risk.sh tests/test_install.sh tests/test_integration.sh tests/test_prepare_install_package.sh tests/test_uninstall.sh tests/test_vpn_monitor.sh

# With parallelization (if GNU parallel is installed)
bats --jobs auto tests/test_high_risk.sh tests/test_install.sh tests/test_integration.sh tests/test_prepare_install_package.sh tests/test_uninstall.sh tests/test_vpn_monitor.sh

# Or using the test runner (includes slow tests by default)
./tests/run_tests.sh --slow --all
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

### High-Risk Tests (test_high_risk.sh)

The `test_high_risk.sh` file contains comprehensive tests for critical paths and error handling scenarios that could cause production failures. These tests focus on areas identified as **Critical Priority** in the test coverage gaps analysis.

#### Overview

The high-risk test suite includes **127 tests** covering critical paths and error handling scenarios across multiple categories:

#### Test Categories

**1. Lockfile Management (~15 tests)**
Tests lockfile cleanup, error handling, race conditions, and edge cases:
- ✅ Lockfile cleanup on script exit
- ✅ Lockfile cleanup on script error
- ✅ Lockfile cleanup on SIGTERM
- ✅ Lockfile contains invalid format
- ✅ Lockfile timestamp at timeout boundary
- ✅ Lockfile acquisition prevents concurrent execution
- ✅ Lockfile acquisition uses flock when available
- ✅ Lockfile acquisition falls back when flock unavailable
- ✅ Lockfile switching between flock and fallback modes
- ✅ Multiple processes attempting to acquire lock simultaneously
- ✅ TOCTOU race conditions
- ✅ PID reuse scenarios
- ✅ Stale lockfile detection
- ✅ Trap handlers properly clean up lockfile in all exit scenarios

**2. Configuration Loading and Validation (~10 tests)**
Tests configuration file error handling, security, and validation:
- ✅ Config file contains syntax errors
- ✅ Config file is unreadable (permission denied)
- ✅ Config file is a directory instead of file
- ✅ LOG_FILE override in config recalculates LOGS_DIR
- ✅ Negative threshold values in config
- ✅ Threshold values out of order
- ✅ Config file attempts command injection via variable
- ✅ Config file sources external commands (security risk)
- ✅ Config file contains null bytes or invalid characters
- ✅ Environment variable overrides and validation

**3. VPN Status Detection (~20 tests)**
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
- ✅ xfrm output format variations (different Linux kernel versions)
- ✅ xfrm returns multiple SAs for same peer IP
- ✅ xfrm output contains malformed byte counter line
- ✅ First check (no previous bytes) - should accept any non-zero value
- ✅ Byte counter increases but very slowly
- ✅ Byte counter jumps dramatically (counter reset on remote side)
- ✅ Ping check enabled but INTERNAL_PEER_IPS not set
- ✅ Ping command hangs (timeout handling)
- ✅ Ping target is unreachable but command succeeds

**4. Recovery Actions (~25 tests)**
Tests recovery action execution, error handling, and verification:
- ✅ Surgical cleanup uses ipsec reload (default behavior)
- ✅ Surgical cleanup fails - error handling
- ✅ Full restart with ipsec command
- ✅ Full restart fails - error handling
- ✅ Full restart when ipsec is not available
- ✅ Rate limit file corrupted
- ✅ Failure counter file is directory
- ✅ Multiple peers failing simultaneously - verify independent cleanup
- ✅ Restart succeeds but VPN doesn't recover (cooldown still set)
- ✅ Restart fails but cooldown is still set
- ✅ PIPESTATUS handling when restart command fails in pipe
- ✅ Recovery action partially succeeds
- ✅ Recovery action succeeds but VPN still fails on next check
- ✅ Recovery action fails and failure counter continues incrementing
- ✅ Multiple recovery actions triggered simultaneously
- ✅ Recovery action during cooldown period (should be prevented)
- ✅ Restart command hangs (timeout scenario)
- ✅ Recovery succeeds but byte counters do not increase immediately
- ✅ VPN fails, reaches Tier 3, restart fails, then recovers naturally

**5. State and File Management (~30 tests)**
Tests state file handling, permissions, corruption, and edge cases:
- ✅ Rate limit file corrupted
- ✅ Rate limit file is empty
- ✅ Rate limit file is a directory
- ✅ Rate limit file contains very old timestamps
- ✅ Rate limit file contains future timestamps
- ✅ Failure counter file corrupted (non-numeric)
- ✅ Failure counter file contains negative number
- ✅ Failure counter file is empty
- ✅ Cooldown file corrupted (invalid timestamp)
- ✅ State file permissions prevent write/read
- ✅ State file deleted during script execution
- ✅ State file modified during script execution
- ✅ Cache file is a directory
- ✅ Cache file corrupted (contains invalid data)
- ✅ Cache file permissions prevent write/read
- ✅ Log file is a directory
- ✅ Log file permissions prevent write
- ✅ Log directory becomes read-only during execution
- ✅ Log file becomes read-only during execution
- ✅ Log directory deleted during execution
- ✅ Disk full scenario (log write fails)
- ✅ STATE_DIR override to non-existent directory creates it
- ✅ STATE_DIR override in config updates all dependent paths
- ✅ LOG_FILE path contains symlinks
- ✅ LOG_FILE path contains special characters

**6. Configuration Validation (~15 tests)**
Tests configuration value validation and edge cases:
- ✅ Invalid COOLDOWN_MINUTES (negative, zero, very large)
- ✅ Invalid MAX_RESTARTS_PER_HOUR (negative, zero, very large)
- ✅ Invalid LOCKFILE_TIMEOUT (negative, zero)
- ✅ Invalid PING_COUNT (negative, zero, very large)
- ✅ Invalid PING_TIMEOUT (negative, zero)
- ✅ Environment variable sets invalid value
- ✅ Multiple environment variables override config

**7. System and Resource Edge Cases (~12 tests)**
Tests system-level edge cases and resource exhaustion:
- ✅ Tool availability detection (command -v) fails
- ✅ Error during state file write
- ✅ Cached connection name becomes invalid
- ✅ Cached connection name takes priority over discovery
- ✅ Connection name discovery during VPN failure (no active SA)
- ✅ Discovery happens when both config and cache unavailable
- ✅ Lockfile exists but PID belongs to different user
- ✅ Lockfile exists but PID is zombie process
- ✅ Lockfile file modification time cannot be read (permission issues)
- ✅ Script execution during system shutdown (should cleanup)
- ✅ Script execution when system resources exhausted
- ✅ Error during VPN check (should log and continue)
- ✅ Error during recovery action (should log and continue)

#### Test Statistics

- **Total Tests**: 127
- **Test Categories**: 7 main categories
- **Focus Areas**: Critical error handling, edge cases, security, race conditions, resource management

#### Test Results

All 127 tests pass successfully. Tests verify:
- ✅ Error handling doesn't crash the script
- ✅ Edge cases are handled gracefully
- ✅ Security concerns (command injection) are mitigated
- ✅ Recovery actions execute correctly
- ✅ Fallback mechanisms work as expected
- ✅ Race conditions are properly handled
- ✅ Resource exhaustion scenarios are handled
- ✅ File permission issues are handled gracefully

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

