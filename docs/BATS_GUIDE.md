# BATS Testing Framework Guide

## Table of Contents

1. [Introduction](#introduction)
2. [How BATS Works](#how-bats-works)
3. [BATS Helper Libraries](#bats-helper-libraries)
4. [How We Are Using BATS](#how-we-are-using-bats)
5. [Current Usage Patterns](#current-usage-patterns)
6. [Recommendations for Better Usage](#recommendations-for-better-usage)
7. [Community Resources](#community-resources)
8. [Advanced Features](#advanced-features)

## Introduction

BATS (Bash Automated Testing System) is a testing framework for Bash scripts that enables developers to write and run unit tests in a simple, structured manner. It provides a TAP (Test Anything Protocol) compliant testing framework specifically designed for shell scripts.

BATS was originally created by Sam Stephenson and has been maintained by the bats-core community. It allows testing Bash scripts in a way similar to how other languages test their code, making it easier to ensure reliability and correctness of shell scripts.

## How BATS Works

### Core Concepts

BATS operates on a few fundamental concepts:

1. **Test Files**: Test files are Bash scripts with a `.bats` extension (though we use `.sh` with `#!/usr/bin/env bats` shebang)
2. **Test Cases**: Individual tests are defined using the `@test` annotation
3. **Setup/Teardown**: `setup()` and `teardown()` functions run before and after each test
4. **Assertions**: Tests use assertions to verify expected behavior
5. **Output Capture**: The `run` command captures command output and exit status

### Test Structure

A typical BATS test file follows this structure:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
    # Setup code runs before each test
}

teardown() {
    # Cleanup code runs after each test
}

@test "test description" {
    # Test implementation
    run command_to_test
    assert_success
    assert_output "expected output"
}
```

### How Tests Execute

1. **Test Discovery**: BATS scans for test files (files with `@test` annotations or `.bats` extension)
2. **Isolation**: Each test runs in a subshell, ensuring isolation between tests
3. **Setup**: The `setup()` function runs before each test, creating a clean environment
4. **Execution**: The test code runs, capturing output via `run`
5. **Teardown**: The `teardown()` function runs after each test, cleaning up resources
6. **Reporting**: BATS reports results in TAP format, suitable for CI/CD integration

### Key BATS Variables

BATS provides several built-in variables:

- `$BATS_TEST_DIRNAME`: Directory containing the test file
- `$BATS_TEST_FILENAME`: Full path to the test file
- `$BATS_TEST_NAME`: Name of the test (from `@test` annotation)
- `$BATS_TEST_NUMBER`: Sequential number of the test in the file
- `$BATS_TEST_TMPDIR`: Temporary directory for the test (automatically cleaned)
- `$status`: Exit status of the last `run` command
- `$output`: Output (stdout + stderr) of the last `run` command
- `$lines`: Array of output lines from the last `run` command

### The `run` Command

The `run` command is central to BATS testing:

```bash
run bash script.sh --flag
assert_success  # Checks $status == 0
assert_output "expected"  # Checks $output
```

The `run` command:
- Executes the command in a subshell
- Captures stdout and stderr to `$output`
- Captures exit status to `$status`
- Splits output into lines in `$lines` array

## BATS Helper Libraries

### bats-support

**Purpose**: Provides foundational utilities for other BATS libraries.

**Key Features**:
- Error reporting (`fail` function)
- Output formatting (two-column and multi-line formats)
- Caller detection (`batslib_is_caller`) for restricting function usage

**Usage**:
```bash
load bats-support/load.bash

@test "example" {
    fail "This test always fails"
}
```

### bats-assert

**Purpose**: Provides common assertion functions for testing.

**Key Functions**:
- `assert_success` / `assert_failure`: Check exit status
- `assert_output` / `refute_output`: Check command output (literal, partial, regex)
- `assert_line` / `refute_line`: Check specific output lines
- `assert_equal` / `assert_not_equal`: Compare values
- `assert_regex` / `refute_regex`: Pattern matching

**Usage**:
```bash
load bats-assert/load.bash

@test "example" {
    run echo "hello"
    assert_success
    assert_output "hello"
    assert_output --partial "ell"  # Partial match
    assert_output --regexp "^h.*o$"  # Regex match
}
```

**Advanced Features**:
- `--partial` flag for substring matching
- `--regexp` flag for regular expression matching
- `--index N` for `assert_line` to check specific line numbers
- Standard input support with `-` flag

**Our Usage**: We extensively use advanced bats-assert features throughout our test suite (112 instances across 6 files):
- `assert_output --regexp` for pattern matching (dates, IPs, numbers, percentages)
- `assert_line` for specific output line validation
- `assert_equal` for precise value comparisons (replacing manual if statements)
- `assert_regex` for variable pattern validation

### bats-file

**Purpose**: Provides filesystem-related assertions and utilities.

**Key Functions**:

**File/Directory Existence**:
- `assert_file_exist` / `assert_file_not_exist`
- `assert_dir_exist` / `assert_dir_not_exist`
- `assert_link_exist` / `assert_link_not_exist`
- `assert_exist` / `assert_not_exist` (generic)

**File Attributes**:
- `assert_file_executable` / `assert_file_not_executable`
- `assert_file_owner` / `assert_not_file_owner`
- `assert_file_permission`
- `assert_file_size_equals`
- `assert_size_zero` / `assert_size_not_zero`

**File Content**:
- `assert_file_empty` / `assert_file_not_empty`
- `assert_file_contains` (regex matching)
- `assert_symlink_to` / `assert_not_symlink_to`

**Temporary Directories**:
- `temp_make`: Create temporary directory
- `temp_del`: Delete temporary directory

**Usage**:
```bash
load bats-file/load.bash

@test "example" {
    assert_file_exist "/path/to/file"
    assert_file_executable "/path/to/script"
    assert_file_contains "/path/to/file" "pattern"
    
    local temp_dir
    temp_dir="$(temp_make)"
    # Use temp_dir
    temp_del "$temp_dir"
}
```

## How We Are Using BATS

### Current Test Suite Structure

Our project uses BATS extensively with **389 tests** across multiple test files:

- `test_helper_functions.sh`: 119 unit tests for helper functions
- High-risk test suite (124 tests split into modular files):
  - `test_config.sh`: 26 tests for configuration loading and validation
  - `test_lockfile.sh`: 18 tests for lockfile management
  - `test_detection.sh`: 15 tests for VPN status detection
  - `test_recovery.sh`: 36 tests for recovery actions and rate limiting
  - `test_state.sh`: 8 tests for state file management
  - `test_logging.sh`: 8 tests for logging failure scenarios
  - `test_connection.sh`: 8 tests for connection name discovery and caching
  - `test_errors.sh`: 3 tests for error handling during critical operations
  - `test_main.sh`: 2 tests for main execution edge cases
- `test_integration.sh`: 18 integration tests
- `test_vpn_monitor.sh`: 33 tests for main script
- `test_install.sh`: 18 installation tests
- `test_uninstall.sh`: 34 uninstallation tests
- `test_analyze_logs.sh`: 28 log analysis tests
- `test_prepare_install_package.sh`: 12 package preparation tests

### Test Helper Infrastructure

We have a comprehensive `test_helper.bash` file that provides:

1. **Standard Helper Libraries**: Explicitly loads bats-support, bats-assert, and bats-file for consistent test patterns. This standardization ensures all tests use well-maintained, community-supported assertion functions.

2. **Temporary Directory Management**: Uses `temp_make` and `temp_del` from bats-file for consistent temporary directory handling. The `setup()` function creates test directories using `temp_make --prefix 'vpn-monitor-'`, and `teardown()` cleans them up with `temp_del`. This approach respects `BATSLIB_TEMP_PRESERVE_ON_FAILURE` for debugging failed tests.

3. **Mock Functions**: Utilities to create mock commands (`mock_ip_xfrm_state`, `mock_ping`, `mock_ipsec`) that simulate system behavior for isolated testing.

4. **Setup Helpers**: Functions like `setup_test_vpn_monitor`, `setup_test_config`, `setup_state_files` that create consistent test environments.

5. **Environment Setup**: Functions to create test directories and configure test environments.

6. **Custom Helpers**: Project-specific helpers like `assert_log_contains` that build on standard library functions, reducing test duplication.

7. **Test Fixtures**: Reusable test fixtures in `tests/fixtures/` for common VPN scenarios (active, down, failing, cooldown) that can be loaded into tests for consistent scenario setup.

### Test Execution

Our `run_tests.sh` script provides comprehensive test execution capabilities:

- **Test Filtering**: Fast vs. slow tests (slow tests excluded by default). Fast tests (244 tests) run by default, while slow tests (142 tests including integration and high-risk scenarios) can be included with `--slow` flag. High-risk tests are split into modular files (`test_config.sh`, `test_lockfile.sh`, `test_detection.sh`, `test_recovery.sh`, `test_state.sh`, `test_logging.sh`, `test_connection.sh`, `test_errors.sh`, `test_main.sh`) for better organization and maintainability.

- **Coverage Reporting**: Integration with kcov for code coverage. Generate coverage reports with `--coverage` flag. Coverage reports are generated in HTML format in the `coverage` directory.

- **Parallel Execution**: Support for GNU parallel or rush (disabled by default for output streaming, can be enabled with `--jobs auto` or `--jobs N`). Automatically detects available parallel tools and can reduce test execution time by 3-4x on multi-core systems. Disabled by default to ensure output streams properly to terminal for real-time feedback.

- **Timeout Handling**: Per-test timeouts (2 minutes default, configurable via `TEST_TIMEOUT`). Tests that exceed the timeout are automatically skipped to prevent hanging tests from blocking execution.

- **Output Streaming**: Unbuffered output using `stdbuf` for real-time test results. This ensures test output appears immediately rather than being buffered.

- **Failed Test Rerun**: Support for rerunning only failed tests with `--failed` flag. This allows quick iteration on failing tests without rerunning the entire suite.

- **Fast-Fail Mode**: Option to stop on first failure (disabled by default). Use `--all` flag to run all tests regardless of failures.

### CI/CD Integration

We have integrated BATS testing into our CI/CD pipeline via GitHub Actions (`.github/workflows/tests.yml`). The workflow:
- Automatically runs tests on pushes and pull requests
- Includes slow tests in CI runs (via `RUN_SLOW_TESTS=1`)
- Generates coverage reports
- Provides test results in TAP format for CI integration

### Current Usage Patterns

**1. Test Structure**:
```bash
#!/usr/bin/env bats
load test_helper  # Loads bats-support, bats-assert, and bats-file

@test "test description" {
    setup_test_vpn_monitor "192.168.1.1"
    run bash "$TEST_SCRIPT" --flag
    assert_success  # From bats-assert
    assert_file_exist "$LOG_FILE"  # From bats-file
    assert_file_contains "$LOG_FILE" "expected message"  # From bats-file
}
```

**1a. Advanced Assertions**:
We use advanced bats-assert features for precise validation:
```bash
@test "analyze logs extracts failures correctly" {
    run bash "$ANALYZE_LOGS_SCRIPT" -l "$log_file" -o "$TEST_DIR"
    assert_success
    # Use regex for numeric patterns with word boundaries
    assert_output --regexp 'Total Failures: [0-9]+\b'
    # Use assert_line for specific output lines
    assert_line --partial "Analyzing log file:"
}

@test "recovery strategy selection" {
    select_recovery_strategy "203.0.113.1" 2
    # Use assert_equal for precise value comparisons
    assert_equal "$RECOVERY_STRATEGY" "xfrm"
    assert_equal "$RECOVERY_COMMAND" "attempt_xfrm_recovery"
    # Use assert_regex for pattern validation
    assert_regex "$failure_count" '^[1-9][0-9]*$'
}
```

**2. Mock Usage**:
```bash
@test "test with mocks" {
    setup_mock_vpn_environment "192.168.1.1" 1000
    run bash "$TEST_SCRIPT"
    assert_success
}
```

**3. State Management**:
```bash
@test "test with state" {
    setup_test_vpn_monitor "192.168.1.1"
    setup_state_files "192.168.1.1" 2 500  # failure_count=2, last_bytes=500
    run bash "$TEST_SCRIPT"
    # Verify behavior with existing state
}
```

**4. Conditional Skipping with BATS Extended Syntax**:
We use concise conditional skipping patterns in our tests:
```bash
@test "test requiring specific condition" {
    [[ ! -f /path/to/required/file ]] && skip "Required file not found"
    # Test implementation
}
```
This pattern is used in `test_install.sh` and `test_uninstall.sh` for tests that require specific conditions to be met.

**5. Test Tagging for High-Risk Tests**:
Our high-risk test suite uses BATS test tags to mark critical tests:
```bash
# bats test_tags=priority:high
@test "config file contains syntax errors" {
    # Test implementation for critical path
}
```
These tests are organized into modular files (`test_config.sh`, `test_lockfile.sh`, `test_detection.sh`, `test_recovery.sh`, `test_state.sh`, `test_logging.sh`, `test_connection.sh`, `test_errors.sh`, `test_main.sh`) and are recognized by the test runner as slow tests that require the `--slow` flag. This modular approach improves maintainability and makes it easier to focus on specific areas when debugging or enhancing tests.

**6. Advanced bats-assert Usage**:
Our test suite extensively uses advanced bats-assert features (112 instances across 6 files) for precise validation:
```bash
@test "validates numeric output with regex" {
    run analyze_logs.sh --log-file "$log_file"
    assert_success
    # Regex patterns for flexible matching
    assert_output --regexp 'Total Failures: [0-9]+\b'
    assert_output --regexp 'Recovery Success Rate:.*%'
}

@test "validates specific output lines" {
    run prepare_package.sh --tar
    assert_success
    # Check specific lines in output
    assert_line --partial "tar -xzf"
    assert_line --partial "udm-vpn-monitor-installer.tar.gz"
}

@test "compares values precisely" {
    select_recovery_strategy "192.168.1.1" 2
    # Precise value comparison with better error messages
    assert_equal "$RECOVERY_STRATEGY" "xfrm"
    assert_equal "$stored_spi" "0x12345678"
}

@test "validates variable patterns" {
    local count=$(grep -c "FAILURE" "$csv_file")
    # Pattern validation for variables
    assert_regex "$count" '^[1-9][0-9]*$'
    assert_output --regexp '^[0-9]+$'  # Timestamp validation
}
```
This approach provides more precise assertions, better error messages, and more maintainable test code.

**7. Comprehensive bats-file Assertions**:
Our test suite uses comprehensive bats-file assertions for thorough filesystem testing:
```bash
@test "verifies file permissions after setting them" {
    chmod 444 "$state_file"
    # Verify permissions were set correctly
    assert_file_permission 444 "$state_file"
}

@test "verifies empty files" {
    touch "$failure_counter"
    # Verify file is empty
    assert_file_empty "$failure_counter"
}

@test "verifies log files have content" {
    echo "Initial log entry" >"$log_file"
    # Verify log file has content
    assert_file_not_empty "$log_file"
}

@test "verifies installed files have correct permissions" {
    run bash "$install_script" --dev --silent --no-cron
    assert_success
    # Verify script has executable permissions (755)
    assert_file_permission 755 "${TEST_DIR}/vpn-monitor/vpn-monitor.sh"
    # Verify config file has readable permissions (644)
    assert_file_permission 644 "${TEST_DIR}/vpn-monitor/vpn-monitor.conf"
}

@test "verifies symlink targets" {
    ln -sf "$real_dir" "$symlink_dir"
    # Verify symlink points to correct target
    assert_symlink_to "$real_dir" "$symlink_dir"
}
```

We use these assertions across multiple test files:
- **Permission checks** (`assert_file_permission`): Used in `test_state.sh`, `test_logging.sh`, `test_config.sh`, `test_analyze_logs.sh`, and `test_install.sh` to verify file permissions after setting them
- **Empty file checks** (`assert_file_empty`): Used in `test_state.sh`, `test_detection.sh`, and `test_analyze_logs.sh` to verify empty files
- **Non-empty file checks** (`assert_file_not_empty`): Used in `test_logging.sh` and `test_analyze_logs.sh` to verify log files have content
- **Symlink checks** (`assert_symlink_to`): Used in `test_logging.sh` to verify symlink targets

This comprehensive approach to filesystem testing ensures better validation of file attributes and clearer test intent.

## Current Usage Patterns

### Strengths

1. **Comprehensive Coverage**: 389 tests covering unit, integration, and high-risk scenarios
2. **Good Isolation**: Each test gets a clean environment via `setup()`/`teardown()`
3. **Mock Infrastructure**: Well-developed mocking system for system commands
4. **Standard Helper Libraries**: Uses bats-support, bats-assert, and bats-file for consistent, well-maintained assertions
5. **Advanced Assertions**: Extensive use of advanced bats-assert features (112 instances) including regex matching, `assert_line`, `assert_equal`, and `assert_regex` for precise test validation and better error messages
6. **Comprehensive File Assertions**: Extensive use of bats-file assertions including `assert_file_permission`, `assert_file_empty`, `assert_file_not_empty`, and `assert_symlink_to` for thorough filesystem testing across multiple test files
7. **Custom Helper Functions**: Project-specific helpers that build on standard libraries reduce test duplication
8. **Coverage Integration**: kcov integration for code coverage reporting

### Areas for Improvement

1. **Test Organization**: ✅ **Improved** - High-risk tests have been split into modular files for better organization
2. **Parallel Execution**: ✅ **Implemented** - Available but disabled by default for output streaming; can be enabled with `--jobs` flag when needed
3. **Test Tags**: ✅ **Implemented** - High-risk tests use `bats test_tags=priority:high` for tagging
4. **Advanced bats-assert Features**: ✅ **Implemented** - 112 instances upgraded across 6 test files using regex matching, `assert_line`, `assert_equal`, and `assert_regex`
5. **Comprehensive bats-file Assertions**: ✅ **Implemented** - Enhanced file assertions added across multiple test files including permission, emptiness, and symlink checks
6. **Documentation**: Tests could benefit from more inline documentation


### 4. Parallel Execution

**Current Status**: Parallel execution is implemented and available but disabled by default (`PARALLEL_JOBS=0`) to ensure output streams properly to the terminal.

**Usage**: Parallel execution can be enabled when needed:

```bash
# Enable parallel execution with auto-detected CPU cores
./tests/run_tests.sh --jobs auto

# Use specific number of parallel jobs
./tests/run_tests.sh --jobs 8

# Disable parallel execution (default)
./tests/run_tests.sh --jobs 0
# or
PARALLEL_JOBS=0 ./tests/run_tests.sh
```

**Performance**: Parallel execution can reduce test time by 3-4x on multi-core systems:
- Without parallel: ~15 minutes (all tests)
- With parallel (8 jobs): ~3-5 minutes (all tests)
- With parallel (fast tests only): ~1-2 minutes

**Requirements**: GNU parallel or rush must be installed. The test runner automatically detects and uses available tools.

**Note**: Parallel execution is disabled by default to ensure output streams properly to the terminal for real-time feedback during development. Enable it when you need faster test runs and can tolerate buffered output.

## Community Resources

### Official Documentation

- **BATS Core**: https://bats-core.readthedocs.io/
- **BATS GitHub**: https://github.com/bats-core/bats-core
- **Writing Tests Guide**: https://bats-core.readthedocs.io/en/latest/writing-tests.html

### Helper Libraries

- **bats-assert**: https://github.com/bats-core/bats-assert
- **bats-file**: https://github.com/bats-core/bats-file
- **bats-support**: https://github.com/bats-core/bats-support

### CI/CD Integration

- **BATS GitHub Action**: https://github.com/bats-core/bats-action
- **TAP Format**: BATS outputs TAP format, compatible with most CI systems

### Community Resources

- **BATS Core Discussions**: https://github.com/bats-core/bats-core/discussions
- **BATS Examples**: Various projects using BATS (search GitHub for "bats" test files)
- **Best Practices**: Community wiki and discussions

### Learning Resources

1. **Official Documentation**: Comprehensive guides on bats-core.readthedocs.io
2. **Example Projects**: Search GitHub for projects using BATS
3. **Community Forums**: GitHub discussions and issues
4. **Blog Posts**: Various blog posts about BATS best practices

## Advanced Features

### 1. Test Filtering

```bash
# Run tests matching a pattern
bats --filter "VPN" tests/

# Run tests NOT matching a pattern
bats --negative-filter "slow" tests/

# Run tests by status (failed, passed, skipped)
bats --filter-status failed tests/
```

### 2. Output Formats

```bash
# TAP format (default)
bats tests/

# JUnit XML (for CI)
bats --formatter junit tests/ > results.xml

# Pretty format
bats --pretty tests/
```

### 3. Test Timeouts

**Our Implementation**: We use per-test timeouts (2 minutes default) via `run_test_file_with_timeout()`:

```bash
# Set timeout per test via environment variable
TEST_TIMEOUT=120 ./tests/run_tests.sh  # 120 seconds (default)

# Or use timeout in test directly
@test "slow test" {
    timeout 30 slow_command
}
```

**BATS Built-in**:
```bash
# Show timing info
bats --timing tests/
```

### 4. Debugging Tests

```bash
# Verbose output
bats --verbose tests/

# Print test names only
bats --list-tests tests/

# Preserve temp directories on failure
BATSLIB_TEMP_PRESERVE_ON_FAILURE=1 bats tests/
```

### 5. Test Reporting

```bash
# Generate coverage report
bats --coverage tests/

# Generate HTML report (with external tools)
bats --tap tests/ | tap-html > report.html
```

## Summary

BATS is a powerful testing framework for Bash scripts. Our current implementation is comprehensive with **389 tests** across multiple test files, covering unit, integration, and high-risk scenarios.

### Current Test Suite Statistics

- **Total Tests**: 389 tests
- **Test Coverage**: 46.9% (1141/2433 lines)
- **Fast Tests**: 244 tests (run by default)
- **Slow Tests**: 142 tests (integration and high-risk, excluded by default)
- **Test Files**: 16 test files covering unit, integration, and high-risk scenarios
- **High-Risk Tests**: 124 tests split across 9 modular files for better organization:
  - Configuration, lockfile, detection, recovery, state, logging, connection, errors, and main execution

### Key Features Implemented

Our test suite leverages BATS best practices and includes:

- **Standardized helper libraries** (bats-support, bats-assert, bats-file) for consistent test patterns
- **Advanced bats-assert features** - 112 instances using `assert_output --regexp`, `assert_line`, `assert_equal`, and `assert_regex` for precise assertions and better error messages
- **Comprehensive bats-file assertions** - Extensive use of `assert_file_permission`, `assert_file_empty`, `assert_file_not_empty`, and `assert_symlink_to` for thorough filesystem testing
- **Temporary directory management** using `temp_make` and `temp_del` from bats-file
- **Parallel execution support** via GNU parallel or rush (disabled by default for output streaming)
- **Per-test timeout handling** (2 minutes default) to prevent hanging tests
- **Output streaming** with unbuffered output for real-time test results
- **Failed test rerun** capability for quick iteration
- **CI/CD integration** via GitHub Actions for automatic test execution
- **Test fixtures** for reusable VPN scenario setup
- **BATS Extended Syntax** for concise conditional skipping
- **Modular test organization** with high-risk tests split into focused files for better maintainability
- **Test tagging** using `bats test_tags=priority:high` for high-risk tests

