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
- `test_high_risk.sh`: 127 tests for critical paths and error handling
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

- **Test Filtering**: Fast vs. slow tests (slow tests excluded by default). Fast tests (244 tests) run by default, while slow tests (145 tests including integration and high-risk scenarios) can be included with `--slow` flag.

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

## Current Usage Patterns

### Strengths

1. **Comprehensive Coverage**: 389 tests covering unit, integration, and high-risk scenarios
2. **Good Isolation**: Each test gets a clean environment via `setup()`/`teardown()`
3. **Mock Infrastructure**: Well-developed mocking system for system commands
4. **Standard Helper Libraries**: Uses bats-support, bats-assert, and bats-file for consistent, well-maintained assertions
5. **Custom Helper Functions**: Project-specific helpers that build on standard libraries reduce test duplication
6. **Coverage Integration**: kcov integration for code coverage reporting

### Areas for Improvement

1. **Test Organization**: Some tests could benefit from better grouping/organization
2. **Parallel Execution**: Implemented but disabled by default for output streaming; can be enabled with `--jobs` flag when needed
3. **Test Tags**: Not using BATS test tags for filtering/organization (available in BATS 1.8.0+)
4. **Documentation**: Tests could benefit from more inline documentation

## Recommendations for Better Usage

### 1. Leverage More bats-assert Features

**Current**: We use basic assertions (`assert_success`, `assert_output --partial`)

**Recommendation**: Use more advanced features:

```bash
# Use regex matching for flexible output validation
assert_output --regexp '^VPN monitor.*started.*\d{4}-\d{2}-\d{2}'

# Use assert_line for specific line checks
run bash script.sh
assert_line --index 0 "First line"
assert_line --partial "error"  # Check any line contains "error"

# Use assert_equal for value comparisons
assert_equal "$actual_value" "$expected_value"

# Use assert_regex for pattern matching
assert_regex "$variable" '^[0-9]+$'
```

**Benefits**:
- More precise test assertions
- Better error messages when tests fail
- More readable test code

### 2. Utilize More bats-file Assertions

**Current**: We use basic file existence checks

**Recommendation**: Use more comprehensive file assertions:

```bash
# Check file permissions
assert_file_permission 755 "/path/to/script"

# Check file ownership
assert_file_owner "root" "/path/to/file"

# Check file size
assert_file_size_equals 1024 "/path/to/file"

# Check file emptiness
assert_file_empty "/path/to/log"  # or assert_file_not_empty

# Check symlinks
assert_symlink_to "/actual/path" "/symlink/path"
```

**Benefits**:
- More thorough file system testing
- Better validation of file attributes
- Clearer test intent

### 3. Use Test Tags for Organization

**BATS 1.8.0+** supports test tags for filtering:

```bash
# bats test_tags=category:integration,priority:high
@test "critical integration test" {
    # test code
}

# Run only high-priority tests
bats --filter-tags priority:high tests/

# Run integration tests
bats --filter-tags category:integration tests/
```

**Benefits**:
- Better test organization
- Flexible test filtering
- Easier test maintenance

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

### 6. Improve Test Documentation

**Recommendation**: Add more descriptive test names and comments:

```bash
# Instead of:
@test "test function" {

# Use:
@test "check_xfrm_status detects VPN failure when byte counter stops increasing" {
    # Test verifies that the detection function correctly identifies
    # VPN failures by monitoring byte counter changes over time.
    # Expected: Function returns failure status when bytes don't increase
    # for 3 consecutive checks.
}
```

**Benefits**:
- Self-documenting tests
- Easier debugging when tests fail
- Better understanding of test intent

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
- **Slow Tests**: 145 tests (integration and high-risk, excluded by default)
- **Test Files**: 8 test files covering unit, integration, and high-risk scenarios

### Key Features Implemented

Our test suite leverages BATS best practices and includes:

- **Standardized helper libraries** (bats-support, bats-assert, bats-file) for consistent test patterns
- **Temporary directory management** using `temp_make` and `temp_del` from bats-file
- **Parallel execution support** via GNU parallel or rush (disabled by default for output streaming)
- **Per-test timeout handling** (2 minutes default) to prevent hanging tests
- **Output streaming** with unbuffered output for real-time test results
- **Failed test rerun** capability for quick iteration
- **CI/CD integration** via GitHub Actions for automatic test execution
- **Test fixtures** for reusable VPN scenario setup
- **BATS Extended Syntax** for concise conditional skipping

### Future Improvements

Areas where we can continue to enhance our test suite:

1. **Using test tags** - Implement BATS test tags (BATS 1.8.0+) for better test organization and filtering
2. **Improving test documentation** - Add more descriptive test names and inline comments for better maintainability
3. **Leveraging more bats-assert features** - Use advanced features like regex matching, `assert_line`, and `assert_equal` more extensively
4. **Utilizing more bats-file assertions** - Use file permission, ownership, and size assertions for more thorough filesystem testing

By continuing to implement these recommendations, we can make our test suite more maintainable, faster, and more comprehensive while following BATS best practices and community standards.

