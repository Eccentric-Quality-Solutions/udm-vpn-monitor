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

1. **Custom Assertions**: Fallback implementations when helper libraries aren't available
2. **Mock Functions**: Utilities to create mock commands (`mock_ip_xfrm_state`, `mock_ping`, `mock_ipsec`)
3. **Setup Helpers**: Functions like `setup_test_vpn_monitor`, `setup_test_config`, `setup_state_files`
4. **Environment Setup**: Functions to create test directories and configure test environments

### Test Execution

Our `run_tests.sh` script provides:

- **Test Filtering**: Fast vs. slow tests (slow tests excluded by default)
- **Coverage Reporting**: Integration with kcov for code coverage
- **Parallel Execution**: Support for GNU parallel (disabled by default for output streaming)
- **Timeout Handling**: Per-test timeouts (2 minutes default)
- **Output Streaming**: Unbuffered output using `stdbuf` for real-time test results

### Current Usage Patterns

**1. Test Structure**:
```bash
#!/usr/bin/env bats
load test_helper

@test "test description" {
    setup_test_vpn_monitor "192.168.1.1"
    run bash "$TEST_SCRIPT" --flag
    assert_success
    assert_file_contains "$LOG_FILE" "expected message"
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

## Current Usage Patterns

### Strengths

1. **Comprehensive Coverage**: 389 tests covering unit, integration, and high-risk scenarios
2. **Good Isolation**: Each test gets a clean environment via `setup()`/`teardown()`
3. **Mock Infrastructure**: Well-developed mocking system for system commands
4. **Helper Functions**: Extensive custom helper functions reduce test duplication
5. **Coverage Integration**: kcov integration for code coverage reporting

### Areas for Improvement

1. **Helper Library Usage**: We have fallback implementations but could leverage more bats-assert/bats-file features
2. **Test Organization**: Some tests could benefit from better grouping/organization
3. **Parallel Execution**: Currently disabled; could be optimized for faster runs
4. **Test Tags**: Not using BATS test tags for filtering/organization
5. **Documentation**: Tests could benefit from more inline documentation

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

### 4. Optimize Parallel Execution

**Current**: Parallel execution is disabled for output streaming

**Recommendation**: Implement smart parallel execution:

```bash
# Use BATS built-in parallel execution (BATS 1.5.0+)
bats --jobs auto tests/  # Auto-detect CPU cores

# Or use per-file parallelization
bats --jobs 4 tests/test_*.sh  # 4 parallel jobs

# Combine with output buffering for better results
bats --jobs 4 --no-tempdir-cleanup tests/ | tee test-results.log
```

**Benefits**:
- Faster test execution (3-4x speedup)
- Better resource utilization
- Still maintainable with proper isolation

### 5. Use Temporary Directory Helpers

**Current**: We manually create `TEST_DIR` in `setup()`

**Recommendation**: Use bats-file's `temp_make`:

```bash
load bats-file/load.bash

setup() {
    TEST_DIR="$(temp_make --prefix 'vpn-monitor-')"
    # Use TEST_DIR
}

teardown() {
    temp_del "$TEST_DIR"
    # Or use BATSLIB_TEMP_PRESERVE_ON_FAILURE=1 for debugging
}
```

**Benefits**:
- Consistent temporary directory handling
- Better cleanup on failure (with `BATSLIB_TEMP_PRESERVE_ON_FAILURE`)
- Unique directory names per test

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

### 7. Use BATS Test Helpers More Consistently

**Recommendation**: Standardize on helper library functions:

```bash
# Instead of custom implementations, use:
load bats-assert/load.bash
load bats-file/load.bash

# Then use standard assertions consistently
assert_file_exist "$file"  # From bats-file
assert_output --partial "text"  # From bats-assert
```

**Benefits**:
- Consistent test patterns
- Better error messages
- Easier maintenance

### 8. Implement Test Fixtures

**Recommendation**: Create reusable test fixtures:

```bash
# tests/fixtures/vpn_active.bash
setup_vpn_active_fixture() {
    local peer_ip="${1:-192.168.1.1}"
    setup_mock_vpn_environment "$peer_ip" 1000
    setup_state_files "$peer_ip" 0 1000
    # Common setup for "VPN active" scenario
}

# Use in tests
@test "test with active VPN" {
    setup_vpn_active_fixture "192.168.1.1"
    # Test code
}
```

**Benefits**:
- Reduced test duplication
- Consistent test setup
- Easier to maintain test scenarios

### 9. Use BATS Extended Syntax

**BATS 1.5.0+** supports extended syntax:

```bash
# Skip tests conditionally
@test "test requiring root" {
    [[ $EUID -ne 0 ]] && skip "This test requires root"
    # test code
}

# Skip entire test file
# bats test_tags=requires:root
# Skip if not root
[[ $EUID -ne 0 ]] && exit 0
```

**Benefits**:
- Better test skipping
- Conditional test execution
- More flexible test organization

### 10. Integrate with CI/CD Better

**Recommendation**: Use BATS GitHub Action:

```yaml
# .github/workflows/tests.yml
- name: Run BATS tests
  uses: bats-core/bats-action@v1
  with:
    tests: 'tests/'
    jobs: '4'  # Parallel execution
```

**Benefits**:
- Consistent CI environment
- Automatic BATS setup
- Better CI integration

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

```bash
# Set timeout per test
bats --timing tests/  # Shows timing info

# Or use timeout in test
@test "slow test" {
    timeout 30 slow_command
}
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

BATS is a powerful testing framework for Bash scripts. Our current implementation is comprehensive with 389 tests, but we can improve by:

1. **Leveraging more helper library features** (bats-assert, bats-file)
2. **Using test tags** for better organization
3. **Optimizing parallel execution** for faster test runs
4. **Improving test documentation** for better maintainability
5. **Standardizing on helper functions** for consistency

By implementing these recommendations, we can make our test suite more maintainable, faster, and more comprehensive while following BATS best practices and community standards.

