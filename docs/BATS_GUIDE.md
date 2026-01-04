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

For complete test suite structure, organization, and current test counts, see:

- **[Test Structure](../tests/README.md#test-structure)** - Test file organization overview
- **[Test Categories](#test-categories)** - Fast vs. slow tests and categorization

**Summary**: Our project uses BATS extensively with tests organized by functionality. See [Test Categories](#test-categories) for current test counts and organization.

### Test Helper Infrastructure

We have a comprehensive `test_helper.bash` file that provides:

1. **Standard Helper Libraries**: Explicitly loads bats-support, bats-assert, and bats-file for consistent test patterns. This standardization ensures all tests use well-maintained, community-supported assertion functions.

2. **Temporary Directory Management**: Uses `temp_make` and `temp_del` from bats-file for consistent temporary directory handling. The `setup()` function creates test directories using `temp_make --prefix 'vpn-monitor-'`, and `teardown()` cleans them up with `temp_del`. This approach respects `BATSLIB_TEMP_PRESERVE_ON_FAILURE` for debugging failed tests.

3. **Mock Functions**: Utilities to create mock commands (`mock_ip_xfrm_state`, `mock_ping`, `mock_ipsec`) that simulate system behavior for isolated testing.

4. **Setup Helpers**: Functions like `setup_test_vpn_monitor`, `setup_test_config` that create consistent test environments. For state files, use `set_peer_state` directly.

5. **Environment Setup**: Functions to create test directories and configure test environments.

6. **Custom Helpers**: Project-specific helpers like `assert_log_contains` that build on standard library functions, reducing test duplication.

7. **Test Fixtures**: Reusable test fixtures in `tests/fixtures/` for common VPN scenarios (active, down, failing, cooldown) that can be loaded into tests for consistent scenario setup. Multiple fixtures can be loaded in a single test file.

8. **Library Module Sourcing**: Helper function `source_recovery_module()` that sources all recovery dependencies (constants.sh, common.sh, logging.sh, state.sh, detection.sh, recovery.sh) for testing recovery functions directly.

9. **Advanced Mock Functions**: Specialized mock functions for network testing including `mock_ip_route`, `mock_ip_link`, `mock_dig`, `mock_nslookup_fail`, `mock_ip_interfaces_up`, and `mock_ping_success` for comprehensive network partition and interface state testing.

### Test Execution

The `run_tests.sh` script provides comprehensive test execution capabilities including test filtering (fast vs. slow), coverage reporting (kcov), parallel execution (GNU parallel/rush), timeout handling, output streaming, failed test rerun, checkpoint/resume, and fast-fail mode.

For detailed test execution documentation, see [Running Tests](#running-tests) section below.

### CI/CD Integration

BATS testing is integrated into our CI/CD pipeline via GitHub Actions. The workflow automatically runs tests on pushes and pull requests, includes slow tests in CI runs, generates coverage reports, and provides test results in TAP format for CI integration.

For detailed CI/CD integration information, see [CI/CD Integration](#cicd-integration) section below.

### Usage Pattern Examples

> **Note**: For standardized patterns and best practices, see **[Test Patterns](../tests/TEST_PATTERNS.md)**. The examples below demonstrate common usage patterns.

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
    # Use set_peer_state directly (setup_state_files has been removed)
    source_function "set_peer_state"
    set_peer_state "" "192.168.1.1" "failure_count" "2"
    set_peer_state "" "192.168.1.1" "last_bytes" "500"
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
Our high-risk test suite uses BATS test tags to mark critical tests. For comprehensive tagging documentation including tag categories, usage patterns, and slow test tagging, see:

- **[Test Categories](#test-categories)** - Test categorization and tagging
- **[BATS Guide - Test Tagging](#test-tagging)** - Tag format and common tags (see Quick Reference section below)

**Quick Example**:
```bash
# bats test_tags=category:high-risk,priority:high
@test "config file contains syntax errors" {
    # Test implementation for critical path
}
```

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
    assert_line --partial "udm-vpn-monitor.tar.gz"
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

**7. Test Fixtures - Reusable Test Scenarios**:
Our test suite uses fixtures to reduce duplication and ensure consistent test environments. Fixtures combine multiple setup steps into single function calls.

**Loading Multiple Fixtures**: Tests can load multiple fixtures at once:
```bash
load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing

@test "test with multiple fixture options" {
    # Can use any of the loaded fixtures
    setup_vpn_active_fixture "192.168.1.1"
    # or
    setup_vpn_down_fixture "192.168.1.1"
}
```

**Available Fixtures**:
- `fixtures/vpn_active.bash` - VPN is active and healthy (`setup_vpn_active_fixture`)
- `fixtures/vpn_down.bash` - VPN is down, no SA found (`setup_vpn_down_fixture`)
- `fixtures/vpn_failing.bash` - VPN has recorded failures (`setup_vpn_failing_fixture`)
- `fixtures/vpn_cooldown.bash` - VPN is in cooldown period (`setup_vpn_cooldown_fixture`)
- `fixtures/vpn_rekey.bash` - VPN has undergone a rekey (`setup_vpn_rekey_fixture`)
- `fixtures/vpn_multiple_peers.bash` - Multiple VPN peers scenario (`setup_vpn_multiple_peers_fixture`)
- `fixtures/vpn_recovery_disabled.bash` - Recovery actions disabled (`setup_vpn_recovery_disabled_fixture`)
- `fixtures/vpn_at_tier.bash` - VPN at specific tier threshold (`setup_vpn_at_tier_fixture`)
- `fixtures/vpn_idle.bash` - VPN idle tunnel scenario (`setup_vpn_idle_fixture`)
- `fixtures/vpn_network_partition.bash` - Network partition scenario (`setup_vpn_network_partition_fixture`)
- `fixtures/vpn_rate_limited.bash` - Rate limiting scenario (`setup_vpn_rate_limited_fixture`)
- `fixtures/vpn_xfrm_recovery.bash` - XFRM recovery scenario (`setup_vpn_xfrm_recovery_fixture`)

**Example Usage**:
```bash
load test_helper
load fixtures/vpn_active

@test "VPN active test" {
    setup_vpn_active_fixture "192.168.1.1" 1000 2000 0x12345678 'TIER1_THRESHOLD=1'
    # VPN is active, bytes increased from 1000 to 2000
    run bash "$TEST_SCRIPT" --fake
    assert_success
}
```

See [Test Patterns - Test Fixtures](../docs/TEST_PATTERNS.md#4-test-fixtures) for detailed fixture documentation with all arguments, examples, and usage patterns.

**8. Direct Library Function Testing**:
For testing library functions directly (unit testing), source the library files in your test:
```bash
@test "test detection function directly" {
    setup_test_vpn_monitor "192.168.1.1"
    
    # Source library files to test functions directly
    # shellcheck source=../lib/logging.sh
    source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
    # shellcheck source=../lib/detection.sh
    source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true
    
    # Test function directly
    run check_vpn_status "192.168.1.1"
    assert_success
}
```

**Helper Function for Recovery Module**: Use `source_recovery_module()` to source all recovery dependencies:
```bash
@test "test recovery function" {
    setup_test_vpn_monitor "192.168.1.1"
    source_recovery_module  # Sources all dependencies automatically
    
    run attempt_xfrm_recovery "192.168.1.1"
    assert_success
}
```

This pattern is useful for unit testing individual functions without running the full script.

**9. Helper Functions for Test Setup**:

Several helper functions simplify test setup and configuration:

**`enable_fake_mode()`**: Enables fake mode for testing (sets `NO_ESCALATE=1` and exports it). This prevents actual system commands from executing during tests:
```bash
@test "test with fake mode" {
    enable_fake_mode
    # NO_ESCALATE=1 is now set and exported
    run bash "$TEST_SCRIPT" --fake
    assert_success
}
```

**`setup_test_location_config(config_file, ...)`**: Creates a location-based config file with common test settings. Takes the config file path and variable assignments as arguments:
```bash
@test "test with location config" {
    local config_file="${TEST_DIR}/vpn-monitor.conf"
    setup_test_location_config "$config_file" \
        'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
        'LOCATION_NYC_INTERNAL="192.168.1.1"'
    # Config file created with location-based format
}
```

**`setup_location_config_and_load(config_file)`**: Sets up test environment, sets `CONFIG_FILE`, and loads configuration. Automatically exports `CONFIG_FILE`. Call this after creating a config file:
```bash
@test "test with loaded location config" {
    local config_file="${TEST_DIR}/vpn-monitor.conf"
    setup_test_location_config "$config_file" \
        'LOCATION_NYC_EXTERNAL="203.0.113.1"'
    setup_location_config_and_load "$config_file"
    # CONFIG_FILE is now set and exported, config is loaded
    run bash "$TEST_SCRIPT" --fake
    assert_success
}
```

**10. Test Documentation Best Practices**:
Our tests include detailed comments explaining purpose, expected behavior, and importance:
```bash
# bats test_tags=category:high-risk,priority:high
@test "check_default_route - Default route exists" {
    # Test verifies that check_default_route correctly detects when default route exists.
    # Expected: Function returns 0 when default route is present.
    # Importance: Default route check is critical for network partition detection.
    setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'
    # ... test implementation
}
```

This documentation helps maintainers understand test intent and importance, especially for high-risk tests.

**11. Advanced Mock Command Patterns**:
Beyond basic mocks, we have specialized mock functions for network and system testing:

**Network Partition Mocks**:
```bash
# Mock ip route command
mock_ip_route "1" "default via 192.168.1.1 dev eth0"  # Route exists
mock_ip_route "0"  # Route missing

# Mock ip link command for interface state
mock_ip_link "UP,UP" "eth0,eth1"  # Multiple interfaces UP

# Mock DNS resolution
mock_dig "1" "8.8.8.8"  # DNS succeeds
mock_dig "0" "8.8.8.8" "timeout"  # DNS timeout
mock_nslookup_fail  # Prevent DNS fallback

# Mock interfaces as UP
mock_ip_interfaces_up "br0,eth0" "1"  # Interfaces UP, default route exists
```

**Specialized Ping Mocks**:
```bash
# Mock ping that always succeeds with proper output format
mock_ping_success  # Always succeeds, outputs packet loss info
```

These mocks enable comprehensive testing of network partition detection and interface state checks.

**12. Comprehensive bats-file Assertions**:
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

1. **Comprehensive Coverage**: See [Test Categories](#test-categories) for current test counts covering unit, integration, and high-risk scenarios
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
3. **Test Tags**: ✅ **Implemented** - High-risk tests use multi-tag patterns (`bats test_tags=category:high-risk,priority:high`) with automatic slow test tagging
4. **Advanced bats-assert Features**: ✅ **Implemented** - 112 instances upgraded across 6 test files using regex matching, `assert_line`, `assert_equal`, and `assert_regex`
5. **Comprehensive bats-file Assertions**: ✅ **Implemented** - Enhanced file assertions added across multiple test files including permission, emptiness, and symlink checks
6. **Test Documentation**: ✅ **Improved** - Tests now include detailed comments explaining purpose, expected behavior, and importance, especially for high-risk tests
7. **Test Fixtures**: ✅ **Implemented** - Reusable fixtures available for common scenarios with support for loading multiple fixtures
8. **Direct Library Testing**: ✅ **Implemented** - Pattern established for testing library functions directly by sourcing library files

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

BATS provides several ways to filter which tests run:

**Filter by Test Name Pattern** (most common):
```bash
# Run tests matching a pattern in the test name
bats tests/test_analyze_logs.sh -f "calculates"

# Run multiple specific tests using regex
bats tests/test_analyze_logs.sh -f "calculates.*(recovery success rate|tier success rates|failures per day)"

# Filter tests in a specific file
bats tests/test_config.sh -f "config file"

# Filter across all test files
bats tests/ -f "VPN"
```

**Negative Filter** (exclude tests):
```bash
# Run tests NOT matching a pattern
bats tests/ --negative-filter "slow"

# Exclude specific test categories
bats tests/ --negative-filter "integration"
```

**Filter by Status** (from previous run):
```bash
# Run only tests that failed in the last run
bats --filter-status failed tests/

# Run only tests that passed
bats --filter-status passed tests/

# Run only tests that were skipped
bats --filter-status skipped tests/
```

**Practical Examples**:
```bash
# Run only calculation-related tests after refactoring floating point logic
bats tests/test_analyze_logs.sh -f "calculates.*(recovery success rate|tier success rates|failures per day)"

# Run all tests related to a specific feature
bats tests/ -f "config file"

# Run tests excluding slow/integration tests
bats tests/ --negative-filter "integration|slow"

# Quick verification of specific functionality
bats tests/test_analyze_logs.sh -f "calculates"
```

**Note**: The `-f` flag uses regex pattern matching, so you can use regex patterns for flexible filtering. When running specific test cases, use `-f` with a pattern that matches the test name from the `@test` annotation.

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

### 5. Slow Test Tagging

We have a script to automatically identify and tag slow tests:

```bash
# Run all tests with timing and tag slow tests (default threshold: 5 seconds)
./tests/tag_slow_tests.sh

# Use custom threshold (in seconds)
SLOW_THRESHOLD=10 ./tests/tag_slow_tests.sh
```

The script:
- Runs all tests with timing enabled
- Identifies tests exceeding the threshold
- Automatically adds `slow` tag to test tags (preserving existing tags)
- Updates test files in place

**Example**: If a test takes 7 seconds and threshold is 5 seconds:
```bash
# Before
# bats test_tags=category:high-risk,priority:high
@test "slow test" {
    # ...
}

# After (automatically updated)
# bats test_tags=slow,category:high-risk,priority:high
@test "slow test" {
    # ...
}
```

This ensures slow tests are properly tagged and can be excluded from fast test runs.

### 6. Test Reporting

```bash
# Generate coverage report
bats --coverage tests/

# Generate HTML report (with external tools)
bats --tap tests/ | tap-html > report.html
```

### 7. Complete Test Example

Here's a complete example showing multiple patterns together:

```bash
#!/usr/bin/env bats
#
# Tests for Network Partition Detection Functions
# Tests critical paths and error handling scenarios

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down

# bats test_tags=category:high-risk,priority:high
@test "check_default_route - Default route exists" {
    # Test verifies that check_default_route correctly detects when default route exists.
    # Expected: Function returns 0 when default route is present.
    # Importance: Default route check is critical for network partition detection.
    
    setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'
    
    # Mock ip command - default route exists
    mock_ip_route "1" "default via 192.168.1.1 dev eth0"
    add_mock_to_path
    
    # Source detection functions to test directly
    # shellcheck source=../lib/logging.sh
    source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
    # shellcheck source=../lib/detection.sh
    source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true
    
    # Test check_default_route function
    run check_default_route
    assert_success
    
    remove_mock_from_path
}

# bats test_tags=slow,category:integration,priority:medium
@test "VPN flapping scenario with fixtures" {
    # Purpose: Test verifies VPN flapping within cooldown period is handled correctly.
    # Expected: Cooldown should prevent excessive recovery actions.
    
    # Use fixture for initial VPN state
    setup_vpn_active_fixture "192.168.1.1"
    
    # Run script - VPN is active
    run bash "$TEST_SCRIPT" --fake
    assert_success
    
    # Change to VPN down state using fixture
    setup_vpn_down_fixture "192.168.1.1"
    
    # Run script - VPN fails, triggers recovery
    run bash "$TEST_SCRIPT" --fake
    assert_file_contains "$LOG_FILE" "Tier 3" || assert_file_contains "$LOG_FILE" "cooldown"
}
```

This example demonstrates:
- Loading multiple fixtures
- Using test tags with multiple categories
- Direct library function testing
- Advanced mock usage
- Test documentation comments
- Combining fixtures with manual setup

## Summary

BATS is a powerful testing framework for Bash scripts. Our current implementation is comprehensive with tests covering unit, integration, and high-risk scenarios.

For current test suite statistics including test counts, coverage, and organization, see:

- **[Test Categories](#test-categories)** - Current test counts and organization
- **[Test Coverage](../docs/TEST_PATTERNS.md#test-coverage)** - Current coverage statistics and goals

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
- **Test fixtures** for reusable VPN scenario setup with support for loading multiple fixtures
- **BATS Extended Syntax** for concise conditional skipping
- **Modular test organization** with high-risk tests split into focused files for better maintainability
- **Test tagging** using multi-tag patterns (`bats test_tags=category:high-risk,priority:high,slow`) for test categorization and filtering
- **Slow test auto-tagging** via `tag_slow_tests.sh` script that automatically identifies and tags slow tests
- **Direct library function testing** by sourcing library files to test individual functions in isolation
- **Advanced mock patterns** for network partition detection, DNS resolution, and interface state testing
- **Test documentation** with detailed comments explaining purpose, expected behavior, and importance

## Quick Reference

This section provides quick access to the most common patterns and commands used in our BATS test suite.

> **Note**: For standardized patterns and best practices, see **[Test Patterns](../tests/TEST_PATTERNS.md)**. This Quick Reference is for quick lookup of common syntax and patterns.

### Essential Test Structure

```bash
#!/usr/bin/env bats
load test_helper

# bats test_tags=category:high-risk,priority:high
@test "test description" {
    setup_test_vpn_monitor "192.168.1.1"
    run bash "$TEST_SCRIPT" --fake
    assert_success
    assert_file_contains "$LOG_FILE" "expected message"
}
```

### Common Setup Patterns

**Basic VPN Monitor Setup**:
```bash
setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"
```

**With Custom Config**:
```bash
setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'TIER1_THRESHOLD=1' 'ENABLE_PING_CHECK=0'
```

**Location-Based Config**:
```bash
local config_file="${TEST_DIR}/vpn-monitor.conf"
setup_test_location_config "$config_file" \
    'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
    'LOCATION_NYC_INTERNAL="192.168.1.1"'
setup_location_config_and_load "$config_file"
```

**Using Fixtures**:
```bash
load fixtures/vpn_active
setup_vpn_active_fixture "192.168.1.1"
```

**With State Files** (⚠️ Preferred approach):
```bash
source_function "set_peer_state"
set_peer_state "" "192.168.1.1" "failure_count" "2"
set_peer_state "" "192.168.1.1" "last_bytes" "500"
```

### Common Assertions

**Exit Status**:
```bash
assert_success
assert_failure
```

**Output Matching**:
```bash
assert_output "exact match"
assert_output --partial "partial match"
assert_output --regexp 'pattern.*match'
assert_line --partial "line content"
```

**File Checks**:
```bash
assert_file_exist "$file"
assert_file_not_exist "$file"
assert_file_empty "$file"
assert_file_not_empty "$file"
assert_file_contains "$file" "pattern"
assert_file_permission 755 "$file"
```

**Log Checks**:
```bash
assert_log_contains "$LOG_FILE" "message"
assert_log_not_contains "$LOG_FILE" "message"
```

**Value Comparisons**:
```bash
assert_equal "$var" "expected"
assert_regex "$var" '^pattern$'
```

### Common Mock Patterns

**VPN Environment**:
```bash
setup_mock_vpn_environment "192.168.1.1" 1000 0x12345678
add_mock_to_path
```

**Network Partition**:
```bash
mock_ip_route "1" "default via 192.168.1.1 dev eth0"  # Route exists
mock_dig "1" "8.8.8.8"  # DNS succeeds
mock_ip_interfaces_up "br0,eth0" "1"
add_mock_to_path
```

**Ping**:
```bash
mock_ping "192.168.1.1" "1"  # Success
mock_ping_success  # Always succeeds
add_mock_to_path
```

**IPsec (Simple Scenarios)**:
```bash
# Both reload and restart succeed
mock_ipsec_reload_restart 0 0
add_mock_to_path

# Reload fails, restart succeeds (tests fallback)
mock_ipsec_reload_restart 1 0
add_mock_to_path

# Both fail (tests error handling)
mock_ipsec_reload_restart 1 1
add_mock_to_path
```

**IPsec (Custom Scenarios)**:
```bash
# For custom behavior (file tracking, specific status output, etc.), create custom mock:
local mock_ipsec="${TEST_DIR}/ipsec"
cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "ipsec-reload-called" > /tmp/ipsec_called.txt
    exit 0
fi
EOF
chmod +x "$mock_ipsec"
add_mock_to_path
```

### Direct Library Function Testing

**Test Detection Functions**:
```bash
source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true
run check_vpn_status "192.168.1.1"
assert_success
```

**Test Recovery Functions**:
```bash
source_recovery_module
run attempt_xfrm_recovery "192.168.1.1"
assert_success
```

### Test Tagging

**Tag Format**:
```bash
# bats test_tags=category:high-risk,priority:high
# bats test_tags=slow,category:integration,priority:medium
```

**Common Tags**:
- `category:high-risk` - Critical path tests
- `category:integration` - Integration tests
- `category:unit` - Unit tests
- `priority:high` - High priority
- `priority:medium` - Medium priority
- `slow` - Slow tests (>5 seconds)

### Running Tests

**Fast Tests Only** (default):
```bash
./tests/run_tests.sh
```

**Include Slow Tests**:
```bash
./tests/run_tests.sh --slow
```

**Specific Test File**:
```bash
bats tests/test_detection.sh
```

**Filter by Name**:
```bash
bats tests/ -f "VPN status"
```

**Failed Tests Only**:
```bash
./tests/run_tests.sh --failed
```

**With Coverage**:
```bash
./tests/run_tests.sh --coverage
```

### Helper Functions Quick Reference

**Setup Functions**:
- `setup_test_vpn_monitor` - Complete VPN monitor setup
- `setup_test_config` - Create config file (legacy format)
- `setup_test_location_config` - Create location-based config file
- `setup_location_config_and_load` - Create and load location config
- `setup_mock_vpn_environment` - Setup mocks
- `enable_fake_mode` - Enable fake mode (NO_ESCALATE=1)
- `setup_vpn_active_fixture` - VPN active fixture
- `setup_vpn_down_fixture` - VPN down fixture

**State Management**:
- Use `set_peer_state` directly for creating state files (see examples below)

**Mock Functions**:
- `mock_ip_xfrm_state` - Mock ip xfrm state
- `mock_ping` - Mock ping command
- `mock_ipsec` - Mock ipsec command (basic)
- `mock_ipsec_reload_restart` - Mock ipsec with configurable reload/restart exit codes (preferred for simple scenarios)
- `mock_ip_route` - Mock ip route
- `mock_dig` - Mock DNS resolution
- `add_mock_to_path` - Add mocks to PATH
- `remove_mock_from_path` - Remove mocks from PATH

**Assertion Functions**:
- `assert_log_contains` - Check log content
- `assert_log_not_contains` - Check log doesn't contain
- `assert_log_contains_any` - Check log contains at least one of multiple patterns
- `assert_file_executable` - Check file is executable
- `assert_state_file` - Check state file value

### Common Patterns by Test Type

**Unit Test** (testing functions directly):
```bash
source_recovery_module
run attempt_xfrm_recovery "192.168.1.1"
assert_success
```

**Integration Test** (testing full script):
```bash
setup_test_vpn_monitor "192.168.1.1"
run bash "$TEST_SCRIPT" --fake
assert_success
```

**Network Partition Test**:
```bash
setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_NETWORK_PARTITION_CHECK=1'
mock_ip_route "0"  # No route
mock_dig "0" "8.8.8.8" "timeout"
add_mock_to_path
source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true
run check_network_partition "192.168.1.1"
assert_success
```

**State Management Test** (⚠️ Preferred approach):
```bash
setup_test_vpn_monitor "192.168.1.1"
source_function "set_peer_state"
set_peer_state "" "192.168.1.1" "failure_count" "3"
set_peer_state "" "192.168.1.1" "last_bytes" "1000"
run bash "$TEST_SCRIPT" --fake
assert_file_contains "$LOG_FILE" "Tier"
```

### Troubleshooting

**Preserve Temp Directories on Failure**:
```bash
BATSLIB_TEMP_PRESERVE_ON_FAILURE=1 bats tests/
```

**Verbose Output**:
```bash
bats --verbose tests/
```

**List All Tests**:
```bash
bats --list-tests tests/
```

**Tag Slow Tests**:
```bash
./tests/tag_slow_tests.sh
SLOW_THRESHOLD=10 ./tests/tag_slow_tests.sh  # Custom threshold
```

**Debugging Test Hangs (Unreadable Files)**:

If tests hang indefinitely, check for unreadable file issues:

1. **Check for unreadable files in test**:
   ```bash
   # Look for chmod 000 or permission issues
   find "${TEST_DIR}" -type f ! -perm 644 ! -perm 755
   ```

2. **Use timeout wrapper**:
   ```bash
   run timeout 15 bash "$TEST_SCRIPT"
   if [[ "$status" -eq 124 ]]; then
       echo "ERROR: Test script hung (timeout after 15 seconds)" >&2
       false
   fi
   ```

3. **Check for file operations without readability checks**:
   - Search for `cat`, `grep`, `wc`, `cp`, `mv` operations
   - Verify each has `file_exists_and_readable` check before use
   - Remember: `2>/dev/null` does NOT prevent hangs

4. **Debug with strace**:
   ```bash
   strace -e trace=openat,read,write,stat,access,newfstatat -f bash "$TEST_SCRIPT" 2>&1 | \
       grep -E "(EACCES|EAGAIN|ETIMEDOUT)"
   ```

5. **Check for race conditions**:
   - File becomes unreadable between check and operation
   - Multiple processes accessing same file
   - Timing-dependent behavior in BATS environment

**Common Causes of Test Hangs**:
- Unreadable files (`chmod 000`) without readability checks
- Missing `file_exists_and_readable` before file operations
- Using `2>/dev/null` instead of readability checks
- Functions that should output values but only return exit codes
- Race conditions with file permissions

**Common Pitfalls**:

1. **XFRM Mock Format Requirements**: When mocking `ip xfrm state` output, you must include the complete xfrm format including the `lifetime current:` line with byte counters. The `extract_byte_counter()` function requires this format to extract bytes. Use the `mock_ip_xfrm_state` helper function instead of manually creating mocks to ensure proper format:
   ```bash
   # ✅ Correct: Use helper function
   mock_ip_xfrm_state "203.0.113.1" "3000" "0x12345678" >/dev/null
   mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
   
   # ❌ Incorrect: Missing lifetime line - byte extraction will fail
   cat >"$mock_ip" <<'EOF'
   #!/bin/bash
   if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
       echo "src 192.168.1.1 dst 203.0.113.1"
       exit 0
   fi
   EOF
   ```

2. **Byte Counter Comparison**: When testing recovery scenarios, ensure byte counters are increasing (current > last) to pass the byte counter validation. Mock the `last_bytes` state file with a lower value than the xfrm output:
   ```bash
   # Mock xfrm shows 3000 bytes
   mock_ip_xfrm_state "203.0.113.1" "3000" >/dev/null
   mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
   
   # Mock last_bytes file shows 2000 (lower value = increasing traffic)
   local mock_cat="${TEST_DIR}/cat"
   cat >"$mock_cat" <<'EOF'
   #!/bin/bash
   if [[ "$1" =~ last_bytes ]]; then
       echo "2000"
   else
       /bin/cat "$@"
   fi
   EOF
   chmod +x "$mock_cat"
   add_mock_to_path
   ```

3. **The `local` Keyword Trap in Mock Scripts**: ⚠️ **CRITICAL** - Never use `local` keyword at the top level of mock scripts created via heredocs. The `local` keyword can only be used inside functions, not at script top level. This causes the script to fail silently with "local: can only be used in a function" error.
   ```bash
   # ❌ WRONG - Script will fail silently:
   cat >"$mock_ip" <<EOF
   #!/bin/bash
   local count=\$(cat "${TEST_DIR}/count" 2>/dev/null || echo "0")
   if [[ \$count -eq 1 ]]; then
       exit 1
   fi
   EOF
   
   # ✅ CORRECT - Use regular variable assignment:
   cat >"$mock_ip" <<EOF
   #!/bin/bash
   count=\$(cat "${TEST_DIR}/count" 2>/dev/null || echo "0")
   if [[ \$count -eq 1 ]]; then
       exit 1
   fi
   EOF
   ```
   **Why This Matters**: Mock scripts appear to exist and be executable, `command -v` finds them correctly, PATH is set correctly, but the script never executes because it fails immediately on the `local` line. Always add a simple `echo` statement at the very beginning of mock scripts to verify execution.

4. **Mock Command Resolution Order**: Mock commands must be created BEFORE `add_mock_to_path()` is called. Commands executed via `timeout` (e.g., `timeout dig`) still use PATH resolution, so PATH must be set before script execution.
   ```bash
   # ✅ CORRECT order:
   local mock_ip="${TEST_DIR}/ip"
   cat >"$mock_ip" <<'EOF'
   #!/bin/bash
   # ... mock implementation ...
   EOF
   chmod +x "$mock_ip"
   add_mock_to_path  # Must be called AFTER creating mocks
   run bash "$TEST_SCRIPT"  # PATH is set before script runs
   ```

5. **Fixture Mock Overwriting**: Test fixtures (e.g., `setup_vpn_down_fixture`) create their own mock commands. Tests that need different mock behavior must properly overwrite these. Use `rm -f "$mock_ip"` before creating new mock to ensure clean overwrite.
   ```bash
   # Fixture creates mock ip with only xfrm handler
   setup_vpn_down_fixture "192.168.1.1" 3
   
   # Test needs to overwrite with route/link handlers
   local mock_ip="${TEST_DIR}/ip"
   rm -f "$mock_ip"  # Remove fixture's mock
   cat >"$mock_ip" <<EOF
   #!/bin/bash
   # Handle xfrm (preserve fixture behavior)
   if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
       exit 0
   fi
   # Add route handler
   if [[ "\$1" == "route" ]] && [[ "\$2" == "show" ]] && [[ "\$3" == "default" ]]; then
       # ... route logic ...
   fi
   exec /usr/bin/ip "\$@"  # Fallback
   EOF
   chmod +x "$mock_ip"
   ```

6. **Mock Output Format Must Match Real Commands**: Mock commands must produce output that matches what the real commands produce, otherwise parsing/grepping fails.
   ```bash
   # ❌ WRONG - missing "state UP"
   echo "1: br0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500"
   
   # ✅ CORRECT - includes "state UP"
   echo "1: br0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default"
   ```

7. **Variable Expansion in Heredocs**: Variables in heredocs need careful handling - use `<<EOF` (not `<<'EOF'`) for expansion, escape `$` for shell variables.
   ```bash
   local test_dir="${TEST_DIR}"
   cat >"$mock_ip" <<EOF
   #!/bin/bash
   # ${test_dir} expands at heredoc creation time
   # \$1, \$2 are shell variables (escaped for mock script)
   count=\$(cat "${test_dir}/count" 2>/dev/null || echo "0")
   if [[ \$count -eq 1 ]]; then
       exit 1
   fi
   EOF
   ```

8. **State Tracking Across Multiple Calls**: Mocks need to track state across multiple calls to the same command (e.g., first call fails, second succeeds). Use files in `${TEST_DIR}` to track state, initialize state files before creating mocks.
   ```bash
   # Initialize state file
   local route_call_count_file="${TEST_DIR}/route_call_count"
   echo "0" >"$route_call_count_file"
   
   # In mock script:
   route_call_count=\$(cat "${route_call_count_file}" 2>/dev/null || echo "0")
   route_call_count=\$((route_call_count + 1))
   echo "\$route_call_count" >"${route_call_count_file}"
   if [[ \$route_call_count -eq 1 ]]; then
       exit 1  # First call fails
   else
       exit 0  # Subsequent calls succeed
   fi
   ```

### Mock Setup Debugging Checklist

When mocks aren't working, use this checklist:

1. ✅ **Verify mock script executes at all**: Add `echo "Mock script is running" >&2` at the very beginning of the mock script
2. ✅ **Check for `local` keyword misuse**: Search for `local` in mock scripts - it can only be used inside functions
3. ✅ **Verify mock files exist**: `ls -la "${TEST_DIR}/ip" "${TEST_DIR}/dig"`
4. ✅ **Verify mocks are executable**: `test -x "${TEST_DIR}/ip"`
5. ✅ **Verify `add_mock_to_path()` is called AFTER creating mocks**
6. ✅ **Verify PATH includes TEST_DIR**: `echo "$PATH" | grep -q "${TEST_DIR}"`
7. ✅ **Add logging to mocks**: `echo "mock_ip called with args: \$*" >> "${TEST_DIR}/mock_calls.log"`
8. ✅ **Check mock output format matches real command output**
9. ✅ **Verify state files are initialized before mocks are created**
10. ✅ **Check if fixture mocks need to be overwritten**
11. ✅ **Verify heredoc variable expansion is correct**
12. ✅ **Check if commands are resolved before PATH is modified**
13. ✅ **Test mock script directly**: `bash "${TEST_DIR}/ip" route show default` to verify it works

---

## Test Environment Requirements

This section documents the complete requirements for running the test suite. The test suite is designed to work on both development machines (Linux, macOS) and CI/CD environments.

### System Requirements

**Operating System:**
- **Linux**: Ubuntu 18.04+, Debian 10+, Fedora 30+, or similar distributions
- **macOS**: macOS 10.15+ (Catalina or later)
- **CI/CD**: Ubuntu 20.04+ (GitHub Actions default)

**Shell:**
- **bash** version 4.0 or higher (required for test execution)
- Most modern Linux distributions and macOS include compatible bash versions

**Disk Space:**
- **Minimum**: 100 MB free space for test execution
- **Recommended**: 500 MB+ for coverage reports and test artifacts
- Coverage reports can generate significant data (HTML reports, JSON data)

**Memory:**
- **Minimum**: 512 MB RAM
- **Recommended**: 1 GB+ RAM for parallel test execution
- Coverage reporting (kcov) requires additional memory

**CPU:**
- Single core works but is slow
- **Recommended**: Multi-core CPU for parallel test execution
- Parallel execution can reduce test time by 3-4x on multi-core systems

### Required Tools

#### bats-core

**Version**: 1.x or higher

**Installation:**

**macOS (Homebrew):**
```bash
brew install bats-core
```

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y bats
```

**Fedora/RHEL:**
```bash
sudo dnf install -y bats
```

**From Source:**
```bash
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

**Verification:**
```bash
bats --version
```

**Note**: The test suite requires bats-core 1.x. Older versions (0.x) are not supported.

### Optional Tools (Recommended)

#### BATS Helper Libraries

These libraries provide additional assertion functions and utilities that improve test readability and maintainability:

- **bats-support** - Output and error handling helpers
- **bats-assert** - Additional assertion functions
- **bats-file** - File system assertions

**Installation:**
```bash
cd tests
./tests/install_bats_helpers.sh
```

This script automatically installs the helper libraries to the `tests/` directory. The test suite will work without these helpers, but some tests may be less readable.

#### GNU parallel or rush

**Purpose**: Parallel test execution (significantly faster)

**GNU parallel Installation:**

**macOS:**
```bash
brew install parallel
```

**Ubuntu/Debian:**
```bash
sudo apt-get install parallel
```

**Fedora/RHEL:**
```bash
sudo dnf install parallel
```

**rush Installation:**
```bash
# rush is a Rust-based alternative to GNU parallel
cargo install rush
# or download from: https://github.com/shenwei356/rush
```

**Performance Impact:**
- Without parallel: ~15 minutes (all tests)
- With parallel (8 jobs): ~3-5 minutes (all tests)
- With parallel (fast tests only): ~1-2 minutes

The test runner automatically detects and uses parallel execution if available (see [Parallel Execution](#parallel-execution) below).

### Coverage Reporting Tools

#### kcov

**Purpose**: Code coverage reporting for bash scripts

**Installation:**

**macOS (Homebrew):**
```bash
brew install kcov
```

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y kcov
```

**Fedora/RHEL:**
```bash
sudo dnf install -y kcov
```

**From Source (if package not available):**

kcov requires build dependencies:
```bash
# Install build dependencies
sudo apt-get install -y \
  cmake \
  build-essential \
  libcurl4-openssl-dev \
  libelf-dev \
  libdw-dev \
  binutils-dev \
  libiberty-dev \
  zlib1g-dev \
  git

# Build and install kcov
git clone https://github.com/SimonKagstrom/kcov.git
cd kcov
mkdir build && cd build
cmake ..
make -j$(nproc)
sudo make install
```

**Verification:**
```bash
kcov --version
```

**Note**: Coverage reporting is optional. Tests can run without kcov, but coverage reports will not be generated.

### Development Environment Requirements

For contributing to the project, additional tools are recommended:

#### ShellCheck

**Purpose**: Static analysis for shell scripts

**Installation:**

**macOS:**
```bash
brew install shellcheck
```

**Ubuntu/Debian:**
```bash
sudo apt-get install -y shellcheck
```

**Fedora/RHEL:**
```bash
sudo dnf install -y ShellCheck
```

#### shfmt

**Purpose**: Shell script formatter

**Installation:**

**macOS:**
```bash
brew install shfmt
```

**From Source:**
```bash
# Download pre-built binary from releases
# https://github.com/mvdan/sh/releases
```

**Note**: shfmt is not available in most Linux package managers. Use Homebrew on Linux or download from releases.

**Setup Script:**
```bash
# Configure PATH for development tools
./scripts/setup-dev-env.sh
```

This script automatically detects tools installed via `apt` or Homebrew and configures your PATH accordingly.

### CI/CD Environment Requirements

The test suite is designed to work in CI/CD environments (GitHub Actions, GitLab CI, etc.). Additional requirements for CI/CD:

**Required:**
- `bats` - Test framework
- `bash` - Shell interpreter
- `jq` - JSON processor (for coverage extraction in CI)

**Optional:**
- `kcov` - For coverage reporting
- `parallel` or `rush` - For parallel execution
- `bats-support`, `bats-assert`, `bats-file` - Helper libraries

**CI/CD Setup Example:**

See `.github/workflows/ci.yml` for a complete CI/CD setup example. The workflow:
1. Installs bats and GNU parallel from package manager
2. Installs bats helper libraries
3. Optionally builds and installs kcov from source
4. Runs tests with parallel execution enabled (4 jobs) and appropriate environment variables

### Environment Variables

The test suite respects the following environment variables:

**Test Execution:**
- `RUN_SLOW_TESTS` - Set to `1` to include slow tests (default: `0`)
- `PARALLEL_JOBS` - Number of parallel jobs (default: `auto` = batch/parallel mode)
- `TEST_TIMEOUT` - Timeout for individual tests in seconds (default: `120`)
- `FAST_FAIL` - Set to `1` to stop on first failure (default: `0`)

**Coverage:**
- Coverage is enabled via `--coverage` flag, not environment variable

### Verification

To verify your test environment is properly configured:

```bash
# Check required tools
bats --version

# Check optional tools
command -v parallel >/dev/null && echo "GNU parallel: installed" || echo "GNU parallel: not installed"
command -v kcov >/dev/null && echo "kcov: installed" || echo "kcov: not installed"

# Run a simple test
bats tests/test_helper_functions.sh -t "test_helper_functions.sh exists"
```

## Running Tests

### Run Fast Tests (Default)

By default, slow tests are excluded to speed up local development:

```bash
./tests/run_tests.sh
```

This runs all test files except the slow test files listed below. Fast tests include:
- Script-specific tests: `test_analyze_logs.sh`, `test_check_config.sh`, `test_check_utilities.sh`, `test_helper_functions.sh`, `test_install.sh`, `test_uninstall.sh`, `test_vpn_monitor.sh`, `test_prepare_install_package.sh`, `test_vpn_keepalive.sh`, `test_migration.sh`
- Configuration tests (split files): `test_config_loading.sh`, `test_config_validation.sh`, `test_config_large_values.sh`, `test_config_overrides.sh`, `test_config_security.sh`, `test_config_order.sh`, `test_config_schema.sh`, `test_config_location.sh`
- Detection tests (split files): `test_detection_status.sh`, `test_detection_fallback.sh`, `test_detection_network_partition.sh`, `test_detection_rekey.sh`, `test_detection_failure_type.sh`, `test_detection_idle.sh`, `test_detection_xfrm_edge_cases.sh`, `test_detection_ping_multiple.sh`, `test_multiple_peer_edge_cases.sh`
- Recovery tests (split files): `test_recovery_tier1.sh`, `test_recovery_tier2.sh`, `test_recovery_tier3.sh`, `test_recovery_rate_limiting.sh`, `test_recovery_cooldown_rate_limit_interaction.sh`, `test_recovery_network_partition.sh`, `test_recovery_partial_failures.sh`
- Integration tests: `test_integration_e2e_recovery.sh`, `test_integration_location.sh`
- Other tests: `test_state_concurrent_updates.sh`, `test_state_location.sh`, `test_rapid_state_changes.sh`, `test_resources.sh`

**Total**: ~605 fast tests

### Run All Tests (Including Slow Tests)

To include slow tests (integration and high-risk tests):

```bash
./tests/run_tests.sh --slow
# or
RUN_SLOW_TESTS=1 ./tests/run_tests.sh
```

Slow tests include:
- `test_integration.sh` - Integration tests for full monitoring flow (18 tests)
- `test_config.sh` - Main configuration tests (53 tests)
- `test_detection.sh` - Main detection tests (47 tests)
- `test_recovery.sh` - Recovery strategy selection, XFRM recovery, and fallback logic tests (17 tests)
- `test_lockfile.sh` - Lockfile management tests (18 tests)
- `test_state.sh` - State file management tests (25 tests)
- `test_logging.sh` - Logging failure scenario tests (8 tests)
- `test_connection.sh` - Connection name discovery and caching tests (8 tests)
- `test_errors.sh` - Error handling during critical operations tests (3 tests)
- `test_main.sh` - Main execution edge cases tests (25 tests)

**Total**: ~222 slow tests

### Run with Coverage

```bash
./tests/run_tests.sh --coverage          # Fast tests only
./tests/run_tests.sh --slow --coverage    # All tests with coverage
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

### Run Tests Individually

Run each test case separately with detailed per-test output. This mode is useful for debugging specific test failures and provides timing information for each test:

```bash
./tests/run_tests.sh --individual                # Fast tests only, individual mode
./tests/run_tests.sh --individual --slow          # All tests including slow tests
./tests/run_tests.sh --individual --coverage      # With coverage reporting
```

Individual mode provides:
- Per-test timing information
- Detailed results saved to `logs/test_results_TIMESTAMP.txt`
- Clear pass/fail/timeout status for each test
- Useful for debugging specific test failures
- **Checkpoint/resume support** - Automatically saves progress and can resume from where you left off

**Note:** Individual mode runs tests sequentially (parallel execution is disabled in this mode).

#### Checkpoint and Resume

When running tests individually, the test runner automatically saves a checkpoint file (`logs/test_checkpoint.txt`) after each test completes. This allows you to resume test execution from where you left off if tests fail or are interrupted.

**How it works:**
- Each test result (PASSED, FAILED, TIMEOUT) is saved to the checkpoint file
- When resuming, tests that already passed are automatically skipped
- Failed and timed-out tests are re-run when resuming
- Checkpoint persists between terminal sessions

**Usage:**

```bash
# Run tests normally (checkpoint is saved automatically)
./tests/run_tests.sh --individual

# If tests fail or are interrupted, resume from checkpoint
./tests/run_tests.sh --individual --resume

# Resume with slow tests included
./tests/run_tests.sh --individual --resume --slow

# Resume with coverage reporting
./tests/run_tests.sh --individual --resume --coverage
```

**Checkpoint file format:**
- Location: `logs/test_checkpoint.txt`
- Format: `test_file::test_name|status|timestamp`
- Example: `test_config.sh::config file contains syntax errors|PASSED|1234567890`

**Benefits:**
- **Time savings**: Skip tests that already passed, only re-run failures
- **Resilience**: Resume after interruptions without losing progress
- **Debugging**: Focus on fixing failures without re-running successful tests
- **Long test suites**: Especially useful for large test suites that take a long time

**Clearing checkpoint:**
The checkpoint is automatically cleared when you start a fresh run (without `--resume`). To manually clear it:

```bash
rm logs/test_checkpoint.txt
```

### Parallel Execution

The test runner supports parallel execution to significantly reduce test time. By default, tests run in batch/parallel mode (auto-detect CPU cores) if GNU parallel or rush is installed.

```bash
# Auto-detect CPU cores (default - batch/parallel mode)
./tests/run_tests.sh

# Use specific number of parallel jobs
./tests/run_tests.sh --jobs 8

# Run tests sequentially (disable parallel execution)
./tests/run_tests.sh --sequential
# or
./tests/run_tests.sh --jobs 0

# Set via environment variable
PARALLEL_JOBS=4 ./tests/run_tests.sh
```

**Performance Impact:**
- Without parallel: ~15 minutes (all tests)
- With parallel (8 jobs): ~3-5 minutes (all tests)
- With parallel (fast tests only): ~1-2 minutes

**Requirements:**
- GNU parallel or rush must be installed for parallel execution
- If not available, tests automatically fall back to sequential execution (still works, just slower)

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

### Run Specific Test

```bash
bats tests/test_install.sh -t "install.sh creates installation directory"
```

### Run Tests Starting from a Specific Test Number

**Note**: BATS does not natively support starting from a specific test number. After reviewing the [official BATS documentation](https://bats-core.readthedocs.io/en/stable/) and community discussions, there is no built-in feature for this. However, there are several practical workarounds:

#### Method 1: Run Specific Test Files (Recommended)

The most straightforward approach is to run only the test files that contain tests starting from your desired test number.

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

**Note:** For individual test mode, the `--resume` flag provides a more robust checkpoint-based resume mechanism that automatically skips passed tests and re-runs failures. See [Checkpoint and Resume](#checkpoint-and-resume) section above for details.

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

### Verbose Output

```bash
bats --verbose tests/test_*.sh
```

### Tap Format (for CI)

```bash
bats --tap tests/test_*.sh
```

## Test Categories

### Fast Tests (run by default)

Fast tests include all test files except the slow test files listed below. This includes:
- Script-specific tests: `test_analyze_logs.sh`, `test_check_config.sh`, `test_check_utilities.sh`, `test_helper_functions.sh`, `test_install.sh`, `test_uninstall.sh`, `test_vpn_monitor.sh`, `test_prepare_install_package.sh`, `test_vpn_keepalive.sh`, `test_migration.sh`
- Configuration tests (split files): `test_config_loading.sh`, `test_config_validation.sh`, `test_config_large_values.sh`, `test_config_overrides.sh`, `test_config_security.sh`, `test_config_order.sh`, `test_config_schema.sh`, `test_config_location.sh`
- Detection tests (split files): `test_detection_status.sh`, `test_detection_fallback.sh`, `test_detection_network_partition.sh`, `test_detection_rekey.sh`, `test_detection_failure_type.sh`, `test_detection_idle.sh`, `test_detection_xfrm_edge_cases.sh`, `test_detection_ping_multiple.sh`, `test_multiple_peer_edge_cases.sh`
- Recovery tests (split files): `test_recovery_tier1.sh`, `test_recovery_tier2.sh`, `test_recovery_tier3.sh`, `test_recovery_rate_limiting.sh`, `test_recovery_cooldown_rate_limit_interaction.sh`, `test_recovery_network_partition.sh`, `test_recovery_partial_failures.sh`
- Integration tests: `test_integration_e2e_recovery.sh`, `test_integration_location.sh`
- Other tests: `test_state_concurrent_updates.sh`, `test_state_location.sh`, `test_rapid_state_changes.sh`, `test_resources.sh`

**Total**: ~605 fast tests

### Slow Tests (excluded by default)

Slow tests are high-risk tests and integration tests that take longer to run:
- `test_integration.sh` - Integration tests for full monitoring flow (18 tests)
- `test_config.sh` - Main configuration tests (53 tests)
- `test_detection.sh` - Main detection tests (47 tests)
- `test_recovery.sh` - Recovery strategy selection, XFRM recovery, and fallback logic tests (17 tests)
- `test_lockfile.sh` - Lockfile management tests (18 tests)
- `test_state.sh` - State file management tests (25 tests)
- `test_logging.sh` - Logging failure scenario tests (8 tests)
- `test_connection.sh` - Connection name discovery and caching tests (8 tests)
- `test_errors.sh` - Error handling during critical operations tests (3 tests)
- `test_main.sh` - Main execution edge cases tests (25 tests)

**Total Test Count**: 827 tests across all test files (~605 fast, ~222 slow)

**Note**: Slow tests are automatically included in CI/CD via the `RUN_SLOW_TESTS=1` environment variable (see `.github/workflows/tests.yml`).

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

### Coverage Reporting Fails

- Verify kcov is installed: `kcov --version`
- Check kcov build dependencies if building from source
- Coverage is optional - tests can run without it

### Parallel Execution Not Working

- Verify GNU parallel or rush is installed
- Check PATH includes the tool: `which parallel` or `which rush`
- Parallel execution is optional - tests will run sequentially if not available

### Tests Leave Temporary Files

- Tests should clean up automatically
- Check `/tmp/bats-test-*` directories if cleanup fails
- Manually clean if needed: `rm -rf /tmp/bats-test-*`

## CI/CD Integration

Tests can be run in CI environments. The test suite:

- Works in non-interactive mode
- Cleans up after itself
- Uses temporary directories
- Doesn't require root (for most tests)
- Can run in parallel (with proper isolation)
- Complete test isolation - each test gets a fresh environment

### Example GitHub Actions Workflow

```yaml
- name: Install dependencies
  run: |
    sudo apt-get update
    sudo apt-get install -y bats parallel

- name: Install kcov for coverage
  run: |
    sudo apt-get update && sudo apt-get install -y kcov

- name: Run tests with coverage
  env:
    PARALLEL_JOBS: 4
  run: |
    RUN_SLOW_TESTS=1 ./tests/run_tests.sh --coverage

- name: Upload coverage report
  uses: codecov/codecov-action@v3
  with:
    files: ./coverage/index.json
    flags: unittests
```

## Flaky Test Detection

The test suite includes automated flaky test detection to identify tests that pass inconsistently. Flaky tests are tests that pass in some runs but fail in others, indicating unreliable tests that need fixing.

### Running Flaky Test Detection

```bash
# Run flaky test detection with default settings (3 runs, fast tests only)
./tests/detect_flaky_tests.sh

# Run with more iterations for better detection
./tests/detect_flaky_tests.sh --runs 5

# Include slow tests in detection
./tests/detect_flaky_tests.sh --slow

# Combine options
./tests/detect_flaky_tests.sh --runs 5 --slow
```

### How It Works

The flaky test detection script:
1. Runs the test suite multiple times (default: 3 runs)
2. Tracks test results across all runs
3. Identifies tests with inconsistent results (flaky tests)
4. Generates a detailed analysis report

### Output

The script generates:
- **Console Summary**: Colored summary showing stable and flaky tests
- **Analysis Report**: Detailed report saved to `logs/flaky_detection_<timestamp>/flaky_analysis.txt`
- **CI Integration**: Automatically runs on pull requests in CI

### CI Integration

Flaky test detection runs automatically on pull requests via GitHub Actions. When flaky tests are detected:
- A warning is posted in the workflow
- Results are uploaded as artifacts
- A comment is posted on the PR with details

## Test Isolation

The test suite implements **complete test isolation** to ensure tests don't affect each other. This prevents flaky tests and makes debugging easier.

### How It Works

Each test runs in a completely isolated environment:

1. **Fresh Environment Variables**: All test-related environment variables are saved before each test and restored after each test
2. **Isolated Test Directory**: Each test gets its own temporary directory (`TEST_DIR`) that is automatically cleaned up
3. **PATH Restoration**: Mock commands added to PATH are automatically removed after each test
4. **State Cleanup**: All state files, log files, and temporary files are cleaned up

### Environment Variables Tracked

The following environment variables are automatically saved and restored for each test:

- `CONFIG_FILE` - Configuration file path
- `STATE_DIR` - State directory path
- `LOGS_DIR` - Logs directory path
- `LOCKFILE` - Lockfile path
- `LOG_FILE` - Log file path
- `RESTART_COUNT_FILE` - Restart count file path
- `COOLDOWN_UNTIL_FILE` - Cooldown file path
- `MOCK_IP`, `MOCK_PING`, `MOCK_IPSEC` - Mock command paths
- `NO_ESCALATE` - Error handling flag
- `DEBUG` - Debug mode flag
- `BASE_TIME` - Controllable time for testing
- `TEST_CONFIG_FILE`, `TEST_SCRIPT` - Test-specific paths
- `MOCK_DATA_DIR`, `MOCK_INSTALL_DIR` - Mock directory paths
- `TEST_DIR` - Test temporary directory
- `PATH` - Command search path

### Verifying Test Isolation

Use the test isolation verification script to detect if any tests are leaving state:

```bash
# Verify all test files
./tests/verify_test_isolation.sh

# Verify specific test files
./tests/verify_test_isolation.sh test_config.sh test_detection.sh
```

The verification script:
- Captures environment state before and after each test
- Compares environment variables to detect modifications
- Checks for files created outside `TEST_DIR`
- Reports any state leakage detected

### Best Practices

To maintain test isolation:

1. **Use Helper Functions**: Use `setup_test_environment()`, `setup_test_vpn_monitor()`, etc. instead of manually setting environment variables
2. **Clean Up in Tests**: If your test creates files outside `TEST_DIR`, clean them up explicitly
3. **Don't Modify Global State**: Avoid modifying system-wide configuration or files outside `TEST_DIR`
4. **Use Mocks**: Use mock commands instead of modifying system commands
5. **Verify Isolation**: Run `verify_test_isolation.sh` periodically to catch isolation issues early

## Document Organization

This document covers BATS framework usage and patterns for our test suite. For related documentation, see:

- **[Test Patterns](../tests/TEST_PATTERNS.md)** - Standardized test patterns, best practices, test coverage, and high-risk tests
- **[tests/README.md](../tests/README.md)** - Quick start guide for running tests
- **[Test Strategy](TEST_STRATEGY.md)** - Test strategy and approach
- **[Test Maintenance](TEST_MAINTENANCE.md)** - Test maintenance procedures

**Document Organization:**
- **tests/README.md** - Minimal quick-start guide with basic commands and test structure overview
- **docs/BATS_GUIDE.md** (this document) - Complete BATS framework guide, test environment setup, running tests, and advanced features
- **docs/TEST_PATTERNS.md** - Standardized patterns for writing tests, test coverage goals, and high-risk test details

The Quick Reference section below provides quick access to common patterns. For comprehensive documentation, see the cross-referenced documents above.
