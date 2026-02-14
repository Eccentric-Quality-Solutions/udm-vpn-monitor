# Test Helper Modules

This directory contains domain-specific helper modules for test files. These modules consolidate common test helper functions to reduce duplication and ensure consistency across tests.

## Available Helper Modules

### `helpers/mocks.bash` - Standardized Mock Creation Patterns

Provides standardized patterns for creating mock commands in tests.

**Key Functions:**
- `mock_command_failure()` - Create a mock that fails with specific exit code and error message
- `create_mock_command()` - Create a mock with custom script content
- `create_mock_pass_through()` - Create a mock that passes through to the real command
- `create_mock_output()` - Create a mock that returns specific output
- `create_mock_with_tracking()` - Create a mock that tracks calls
- `get_mock_call_count()` - Get call count for a tracked mock
- `clear_mock_tracking()` - Clear call tracking for a mock

**Usage:**
```bash
load test_helper
load helpers/mocks

mock_command_failure "mycommand" 1 "Error message"
add_mock_to_path
```

### `helpers/detection.bash` - Detection Test Helpers

Provides helpers for testing VPN detection functionality.

**Key Functions:**
- `setup_ping_summary_test()` - Set up test environment for ping summary tests
- `setup_mock_timestamp()` - Set up mock timestamp using mock_date
- `setup_ping_optional_test()` - Set up test environment for ping optional tests

**Usage:**
```bash
load test_helper
load helpers/detection

setup_ping_summary_test
setup_mock_timestamp 1000
```

### `helpers/recovery.bash` - Recovery Test Helpers

Provides helpers for testing VPN recovery functionality.

**Key Functions:**
- `generate_xfrm_state_for_recovery()` - Generate xfrm state output for recovery testing
- `override_calculate_duration_with_increment()` - Override calculate_duration for time-based testing
- `override_calculate_duration_always_zero()` - Override calculate_duration to simulate time calculation failure
- `setup_retry_xfrm_recovery_mocks()` - Set up common mocks for retry_xfrm_recovery tests
- `setup_date_sleep_mocks_with_increment()` - Set up date and sleep mocks with time increment file support

**Usage:**
```bash
load test_helper
load helpers/recovery

# Generate xfrm state output in a mock script
generate_xfrm_state_for_recovery 1

# Override calculate_duration for time-based testing
local time_increment_file="${TEST_DIR}/time_increment"
echo "0" >"$time_increment_file"
source_recovery_module
override_calculate_duration_with_increment "$time_increment_file"

# Set up common mocks for retry_xfrm_recovery tests
local log_file
log_file=$(setup_retry_xfrm_recovery_mocks)
add_mock_to_path
```

### `helpers/config.bash` - Config Test Helpers

Provides helpers for testing configuration functionality.

**Key Functions:**
- `create_test_config()` - Create a test config file with specified variables
- `create_valid_config()` - Create a minimal valid config file
- `create_test_lib()` - Create a test lib directory and copy the project's lib/config_schema.sh (requires run from repo root)
- `get_config_schema()` - Get configuration schema for a variable
- `get_config_default()` - Get default value for a configuration variable

**Usage:**
```bash
load test_helper
load helpers/config

create_test_config "${TEST_DIR}/config" "VAR1=value1" "VAR2=value2"
create_valid_config "${TEST_DIR}/config"
```

### `helpers/logging.bash` - Logging Test Helpers

Provides helpers for testing logging functionality.

**Key Functions:**
- `source_logging_functions()` - Source logging functions for unit testing

**Usage:**
```bash
load test_helper
load helpers/logging

source_logging_functions
run log_message "INFO" "SYSTEM" "Test message"
```

### `helpers/resources.bash` - Resources Test Helpers

Provides helpers for testing resource monitoring functionality.

**Key Functions:**
- `setup_resources_test()` - Set up test environment with mocked system commands
- `source_resources_lib()` - Source resources library with mocked /proc

**Usage:**
```bash
load test_helper
load helpers/resources

setup_resources_test
source_resources_lib
run get_cpu_usage
```

### `helpers/test_data.bash` - Test Data Management

Provides helpers for loading and generating test data from the `tests/data/` directory. This module centralizes test data that was previously embedded in test files.

**Key Functions:**
- `generate_xfrm_state_for_scenario()` - Generate xfrm state output for common scenarios
- `generate_config_file()` - Generate configuration files from templates
- `load_test_data_file()` - Load test data from files in tests/data/

**Usage:**
```bash
load test_helper
load helpers/test_data

# Generate xfrm state output
local xfrm_output
xfrm_output=$(generate_xfrm_state_for_scenario "healthy" "${TEST_PEER_IP}" "0x12345678" 1000 10)

# Generate config file
generate_config_file "standard" "${TEST_DIR}/vpn-monitor.conf" "${TEST_PEER_IP}"

# Load test data from file
local data
data=$(load_test_data_file "mock_outputs/sample_output.txt")
```

See `tests/data/README.md` for more information about the test data structure.

### `helpers/state.bash` - State Management Test Helpers

Provides helpers for testing state management functionality. It consolidates common patterns for working with state files, verifying state file contents, and setting up state-related test scenarios.

**Key Functions:**
- `assert_state_file()` - Assert state file exists and contains expected value
- `ensure_state_functions_loaded()` - Ensure state management functions are loaded
- `get_state_file_path()` - Get state file path with common defaults
- `test_peer_state()` - Test peer state with location name
- `create_corrupted_state_file()` - Create a corrupted state file for testing
- `setup_readonly_state_file()` - Setup a read-only state file with automatic cleanup

**Usage:**
```bash
load test_helper
load helpers/state

# Ensure state functions are loaded
ensure_state_functions_loaded

# Get state file path
local state_file
state_file=$(get_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")

# Assert state file exists and contains value
assert_state_file "$state_file" "5"
```

### `helpers/assertions.bash` - Assertion Test Helpers

Provides custom assertion helpers for tests. It consolidates common assertion patterns beyond the standard BATS assertions to reduce duplication and ensure consistency across tests.

**Key Functions:**
- `assert_log_contains()` - Assert log file contains pattern
- `assert_log_not_contains()` - Assert log file does not contain pattern
- `assert_log_contains_any()` - Assert log file contains one of multiple patterns
- `test_empty_string()` - Test that a function handles empty string correctly

**Usage:**
```bash
load test_helper
load helpers/assertions

# Assert log file contains pattern
assert_log_contains "${LOG_FILE}" "VPN is healthy"

# Assert log file does not contain pattern
assert_log_not_contains "${LOG_FILE}" "Error occurred"

# Assert log file contains one of multiple patterns
assert_log_contains_any "${LOG_FILE}" "ipsec reload failed" "reload failed"

# Test that a function handles empty string correctly
@test "escape_sed_regex: handles empty string" {
    test_empty_string "escape_sed_regex"
}
```

### `helpers/fixtures.bash` - Fixture Test Helpers

Provides helpers for working with test fixtures. This module is a placeholder for fixture-related helper functions that may emerge as test patterns develop. Currently, fixtures are well-organized in `tests/fixtures/` and provide their own setup functions.

**Usage:**
```bash
load test_helper
load helpers/fixtures
load fixtures/vpn_active

# Use fixture setup function
setup_vpn_active_fixture "${TEST_PEER_IP}"
```

**Note:** Most fixture functionality is provided by the fixtures themselves in `tests/fixtures/`. This module provides additional helper functions for working with fixtures that may emerge as patterns develop.

## Loading Helper Modules

Helper modules are loaded using BATS's `load` command:

```bash
load test_helper
load helpers/mocks
load helpers/detection
```

The `test_helper` module should always be loaded first, as it provides the base test infrastructure that helper modules may depend on.

## Migration from Individual Test Files

Helper functions that were previously defined in individual test files have been consolidated into these modules. When updating tests:

1. Remove local helper function definitions
2. Add `load helpers/<module>` at the top of the test file
3. Use the helper functions from the module

For example, instead of:
```bash
source_logging_functions() {
    source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
    source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
}
```

Use:
```bash
load helpers/logging
source_logging_functions
```

## Adding New Helpers

When adding new helper functions:

1. Determine which module they belong to (or create a new module if needed)
2. Add the function to the appropriate module file
3. Document the function with comments following the existing pattern
4. Update this README if adding a new module or significant functionality
