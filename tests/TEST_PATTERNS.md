# Test Patterns and Standards

This document describes standardized patterns for writing tests in the UDM VPN Monitor test suite.

## Related Documentation

For additional test documentation, see:

- **[tests/README.md](README.md)** - Complete test suite documentation including running tests, coverage, and troubleshooting
- **[BATS Guide](../docs/BATS_GUIDE.md)** - BATS framework usage, patterns, and advanced features
- **[Test Strategy](../docs/TEST_STRATEGY.md)** - Test strategy, philosophy, and approach
- **[Test Maintenance](../docs/TEST_MAINTENANCE.md)** - Test maintenance procedures and guidelines

## Standardized Patterns

### 1. Fake Mode (Non-Escalating Error Handling)

**Pattern**: Use `enable_fake_mode()` helper function OR `--fake` flag depending on context

**When to use `enable_fake_mode()`**: Before calling individual functions that might exit on error, when you want to test error handling without the function exiting.

**When to use `--fake` flag**: When running the main script (`vpn-monitor.sh`) in test mode. This is equivalent to `NO_ESCALATE=1` but uses the script's built-in flag handling.

**Example - Testing individual functions**:
```bash
@test "test that expects failure" {
    local config_file="${TEST_DIR}/vpn-monitor.conf"
    cat >"$config_file" <<'EOF'
    LOCATION_NYC_EXTERNAL=""
    EOF
    
    setup_location_config_and_load "$config_file"
    enable_fake_mode
    
    run parse_location_config
    assert_failure
    assert_output --partial "EXTERNAL IP is required"
}
```

**Example - Running main script**:
```bash
@test "test main script execution" {
    setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"
    
    run bash "$TEST_SCRIPT" --fake
    assert_success
}
```

**Don't use**:
```bash
# ❌ Old pattern - don't use in config files
NO_ESCALATE=1
EOF

# ❌ Old pattern - don't use manual export
NO_ESCALATE=1
export NO_ESCALATE

# ❌ Old pattern - don't use in fixture config overrides
setup_vpn_rate_limited_fixture "192.168.1.1" 3 \
    'NO_ESCALATE=1'
```

**Use**:
```bash
# ✅ Standardized pattern for individual functions
enable_fake_mode
run parse_location_config

# ✅ Standardized pattern for main script execution
run bash "$TEST_SCRIPT" --fake
```

### 2. CONFIG_FILE Environment Variable

**Pattern**: Always export CONFIG_FILE explicitly when setting it manually

**When to use**: 
- When setting CONFIG_FILE manually (not using helper functions)
- Helper functions (`setup_location_config_and_load()`) already export CONFIG_FILE

**Example**:
```bash
# When setting manually (special cases)
CONFIG_FILE="${TEST_DIR}/nonexistent.conf"
export CONFIG_FILE
setup_test_environment

# When using helper (standard case)
setup_location_config_and_load "$config_file"
# CONFIG_FILE is already exported by helper
```

**Standard**: Helper functions always export CONFIG_FILE, so manual exports are only needed for special cases.

### 3. Environment Variable Inheritance

**Pattern**: Explicitly export variables that need to be inherited by subprocesses

**Standard**: 
- Helper functions export variables they set
- Tests should rely on helper functions for consistency
- Manual variable setting should always include `export` for clarity

**Example**:
```bash
# ✅ Good - helper handles export
setup_location_config_and_load "$config_file"

# ✅ Good - explicit export when needed manually
CONFIG_FILE="$config_file"
export CONFIG_FILE

# ❌ Avoid - relying on implicit inheritance
CONFIG_FILE="$config_file"  # Not exported
```

### 4. Test Fixtures

**Pattern**: Use test fixtures for common VPN state scenarios

**When to use**: When you need a complete VPN state setup (active, down, failing, cooldown, etc.)

**Available fixtures**:
- `fixtures/vpn_active` - VPN is active and healthy
- `fixtures/vpn_down` - VPN is down (no SA found)
- `fixtures/vpn_failing` - VPN has recorded failures
- `fixtures/vpn_cooldown` - VPN is in cooldown period
- `fixtures/vpn_rekey` - VPN has undergone a rekey (SPI change)
- `fixtures/vpn_multiple_peers` - Multiple VPN peers scenario
- `fixtures/vpn_recovery_disabled` - VPN with recovery actions disabled
- `fixtures/vpn_at_tier` - VPN at specific tier threshold
- `fixtures/vpn_idle` - VPN idle tunnel scenario

**Example**:
```bash
load test_helper
load fixtures/vpn_active
load fixtures/vpn_down

@test "VPN active - no action taken" {
    setup_vpn_active_fixture "192.168.1.1" 1000 2000
    # Fixture already adds mocks to PATH, no need to call add_mock_to_path
    run bash "$TEST_SCRIPT" --fake
    assert_success
    remove_mock_from_path
}
```

**Important Notes**:
- **Fixtures automatically add mocks to PATH** - You don't need to call `add_mock_to_path()` after using fixtures
- Fixtures call `setup_mock_vpn_environment()` which internally calls `add_mock_to_path()`
- If you add additional mocks after a fixture, you may need to call `add_mock_to_path()` again (though it's idempotent)
- Always call `remove_mock_from_path()` for cleanup, even when using fixtures

**Benefits**: Reduces duplication, ensures consistent test environments, easier maintenance.

### 5. Mock Setup and Cleanup

**Pattern**: Always pair `add_mock_to_path()` with `remove_mock_from_path()`

**When to use**: When creating mock commands (ip, ping, ipsec, etc.) that need to be in PATH

**Example**:
```bash
@test "test with mocks" {
    # Create mock command
    local mock_ip="${TEST_DIR}/ip"
    cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]]; then
    echo "mock output"
fi
EOF
    chmod +x "$mock_ip"
    
    # Add to PATH
    add_mock_to_path
    
    # Run test
    run bash "$test_script" --fake
    assert_success
    
    # Always cleanup
    remove_mock_from_path
}
```

**Critical Rule - `local` Keyword in Mock Scripts**:
- **NEVER use `local` keyword at the top level of mock scripts created via heredocs**
- `local` can only be used inside functions, not at script top level
- Using `local` causes the script to fail with "local: can only be used in a function" error
- Use regular variable assignment instead: `variable=$(command)` not `local variable=$(command)`

**Example of WRONG vs CORRECT**:
```bash
# WRONG - will fail:
cat >"$mock_ip" <<EOF
#!/bin/bash
local count=\$(cat "${TEST_DIR}/count" 2>/dev/null || echo "0")
if [[ \$count -eq 1 ]]; then
    exit 1
fi
EOF

# CORRECT - works:
cat >"$mock_ip" <<EOF
#!/bin/bash
count=\$(cat "${TEST_DIR}/count" 2>/dev/null || echo "0")
if [[ \$count -eq 1 ]]; then
    exit 1
fi
EOF
```

**Important Notes**:
- **Fixtures already add mocks to PATH** - When using fixtures (`setup_vpn_active_fixture`, `setup_vpn_down_fixture`, etc.), you don't need to call `add_mock_to_path()` because fixtures call `setup_mock_vpn_environment()` which adds mocks to PATH
- If you add additional mocks after a fixture, you may need to call `add_mock_to_path()` again (though it's idempotent, so calling it multiple times is harmless)
- Always call `remove_mock_from_path()` for cleanup, even when using fixtures

**Standard**: 
- Create mocks in `TEST_DIR`
- Use `add_mock_to_path()` before running tests (unless using fixtures, which handle this automatically)
- Always call `remove_mock_from_path()` in teardown or at end of test
- Use helper functions like `setup_mock_vpn_environment()` when possible
- Prefer fixtures over manual mock setup when they match your test scenario

### 6. Test Structure and Comments

**Pattern**: Use structured test comments with Purpose, Expected, and Importance

**When to use**: For all test cases to improve readability and maintainability

**Example**:
```bash
# bats test_tags=category:high-risk,priority:high
@test "parse_location_config - valid single location with external IP only" {
    # Purpose: Test parsing a single location with only external IP configured
    # Expected: parse_location_config succeeds and LOCATIONS array contains the location
    # Importance: Basic functionality - most common use case
    
    local config_file="${TEST_DIR}/vpn-monitor.conf"
    cat >"$config_file" <<'EOF'
    LOCATION_NYC_EXTERNAL="203.0.113.1"
    EOF
    
    setup_location_config_and_load "$config_file"
    run parse_location_config
    assert_success
}
```

**Standard**: 
- Include Purpose (what is being tested)
- Include Expected (what should happen)
- Include Importance (why this test matters)
- Use descriptive test names that explain the scenario

### 7. Test Tags

**Pattern**: Use test tags to categorize and prioritize tests

**When to use**: For all test cases to enable selective test execution

**Common tags**:
- `category:high-risk` - Tests critical functionality
- `category:integration` - Integration tests
- `priority:high` - High priority tests
- `slow` - Tests that take longer to run

**Example**:
```bash
# bats test_tags=category:high-risk,priority:high
@test "critical functionality test" {
    # Test code
}

# bats test_tags=category:integration,slow
@test "integration test" {
    # Test code
}
```

**Standard**: 
- Use `category:` prefix for test categories
- Use `priority:` prefix for priority levels
- Use `slow` tag for tests that take significant time
- Multiple tags can be comma-separated

### 8. Assertion Patterns

**Pattern**: Use appropriate assertion functions for different scenarios

**Common assertions**:
- `assert_success` / `assert_failure` - Check exit status
- `assert_output` / `assert_output --partial` - Check command output
- `assert_file_exist` / `assert_file_not_exist` - Check file existence
- `assert_file_contains` / `assert_log_contains` - Check file/log content
- `assert_equal` - Check exact equality
- `assert_file_permission` - Check file permissions

**Example**:
```bash
@test "test assertions" {
    run some_command
    assert_success
    assert_output --partial "expected text"
    
    assert_file_exist "$log_file"
    assert_file_contains "$log_file" "log message"
    assert_equal "$variable" "expected_value"
}
```

**Standard**: 
- Use `assert_output --partial` for substring matching (more flexible)
- Use `assert_file_contains` for log file checks (uses fixed string matching)
- Use `assert_equal` for exact value comparisons
- Prefer descriptive assertions over generic `assert`

### 9. Config Setup Patterns

**Pattern**: Use appropriate config setup helper for your test type

**When to use**:
- `setup_test_config()` - For legacy EXTERNAL_PEER_IPS format
- `setup_test_location_config()` - For location-based config format
- `setup_test_config_with_recovery_disabled()` - When recovery actions should be disabled
- `setup_location_config_and_load()` - After creating location config, to load it

**Example**:
```bash
# Legacy format
setup_test_config "${TEST_DIR}/vpn-monitor.conf" "192.168.1.1" 'TIER1_THRESHOLD=1'

# Location-based format
local config_file="${TEST_DIR}/vpn-monitor.conf"
setup_test_location_config "$config_file" \
    'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
    'LOCATION_NYC_INTERNAL="192.168.1.1"'
setup_location_config_and_load "$config_file"

# With recovery disabled
setup_test_config_with_recovery_disabled "${TEST_DIR}/vpn-monitor.conf" "192.168.1.1"
```

**Standard**: 
- Prefer location-based format for new tests
- Use helper functions instead of manual config file creation
- Always use `setup_location_config_and_load()` after creating location configs

### 10. Source Function Pattern

**Pattern**: Use `source_function()` for unit testing individual functions

**When to use**: When testing a single function in isolation without loading entire modules

**Example**:
```bash
@test "test individual function" {
    source_function "get_formatted_timestamp"
    
    run get_formatted_timestamp
    assert_success
    assert_output --regexp "^[0-9]{4}-[0-9]{2}-[0-9]{2}"
}
```

**Alternative**: Use `source_recovery_module()` or direct `source` for module-level tests

**Standard**: 
- Use `source_function()` for unit tests of individual functions
- Use direct `source` for integration tests that need full modules
- Use `source_recovery_module()` for recovery-related tests

### 11. Test File Structure

**Pattern**: Follow consistent file structure for test files

**Standard structure**:
```bash
#!/usr/bin/env bats
#
# Tests for [Component Name]
# Brief description of what this test file covers

load test_helper
load fixtures/vpn_active  # Load relevant fixtures

# Path to the VPN monitor script (if needed)
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# SECTION NAME (e.g., CONFIGURATION TESTS)
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "test name - brief description" {
    # Purpose: What is being tested
    # Expected: What should happen
    # Importance: Why this test matters
    
    # Test implementation
}
```

**Standard**: 
- Include file header with description
- Load test_helper first
- Load relevant fixtures
- Use section headers for organization
- Group related tests together

### 12. Running Tests

**Pattern**: Use `run bash` for executing scripts, `run` for functions

**When to use**:
- `run bash "$script"` - For executing shell scripts
- `run function_name` - For executing functions directly
- `run bash "$script" --fake` - For running main script in test mode

**Example**:
```bash
# Run a script
run bash "$test_script" --fake
assert_success

# Run a function
run parse_location_config
assert_success

# Run with PATH modification
PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
```

**Standard**: 
- Always use `run` to capture output and status
- Use `--fake` flag for main script execution
- Ensure mocks are in PATH before running scripts

### 13. Testing Configuration Validation and Early-Exit Scenarios

**Pattern**: Be aware of execution order when testing configuration validation failures

**When to use**: When testing configuration validation errors, especially missing required configuration

**Key Insight**: Configuration validation happens early in the script execution flow, before other checks that might exit early (like network partition checks, cooldown checks, etc.). This ensures configuration errors are caught before other conditions that might cause early exit.

**Example**:
```bash
# bats test_tags=category:unit
@test "vpn-monitor.sh exits with error if LOCATION_*_EXTERNAL not configured" {
    # Purpose: Test verifies that the script validates required configuration and exits with error
    # when LOCATION_*_EXTERNAL is missing or empty.
    # Expected: Script exits with failure status and outputs error message about missing configuration.
    # Importance: Prevents script from running with invalid configuration that would cause runtime errors.
    
    # Create temporary config without LOCATION_*_EXTERNAL
    local config_file="${TEST_DIR}/vpn-monitor.conf"
    cat >"$config_file" <<'EOF'
VPN_NAME="Test VPN"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

    # Create test version of script with custom paths
    local test_script
    test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" \
        "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

    run bash "$test_script"
    
    # Should fail with configuration error, not exit early due to other checks
    assert_failure
    assert_output --partial "No location-based configuration found"
}
```

**Important Notes**:
- Configuration validation happens **before** network partition checks, cooldown checks, and other early-exit conditions
- This ensures configuration errors are always caught, even if other conditions would cause early exit
- When testing configuration validation failures, the script should exit with the validation error, not exit early due to other checks
- If a test expects a configuration validation error but gets a different early-exit (like network partition), it may indicate the validation is happening too late in the execution flow

**Standard**: 
- Configuration validation should happen early in script execution (right after config loading)
- Tests for configuration validation should verify the script exits with the expected validation error message
- Be aware that other early-exit conditions (network partition, cooldown, etc.) happen after configuration validation

### 14. DRY Improvements During Bug Fixes

**Pattern**: When fixing bugs, look for redundant code and improve DRY (Don't Repeat Yourself)

**When to use**: When fixing bugs, especially when moving code or changing execution flow

**Key Insight**: When fixing a bug that involves moving code or changing execution order, check if the change introduces redundancy. If code is now executed multiple times unnecessarily, remove the redundant calls.

**Example**:
```bash
# Before fix: validate_config() called in process_locations()
# After fix: validate_config() called early in main()
# Result: validate_config() was being called twice - once early, once in process_locations()

# ✅ Good - Remove redundant call after moving validation earlier
process_locations() {
    # Configuration already validated early in main()
    # Just verify LOCATIONS is populated (defensive check)
    if [[ ${#LOCATIONS[@]} -eq 0 ]]; then
        handle_error_or_exit_fake_mode "No locations configured" "${EXIT_VALIDATION_ERROR:-3}"
        return 1
    fi
    # ... rest of function
}

# ❌ Avoid - Redundant validation after moving it earlier
process_locations() {
    validate_config  # Redundant - already validated earlier
    # ... rest of function
}
```

**Important Notes**:
- When moving validation or other checks earlier in execution flow, check if they're still being called later
- Remove redundant calls to improve code maintainability
- Keep defensive checks if they serve a purpose (e.g., verifying state that should already be set)
- Update function documentation to reflect changes in execution flow

**Standard**: 
- When fixing bugs that involve code movement, check for redundant calls
- Remove redundant code to improve DRY
- Update documentation to reflect new execution flow
- Keep defensive checks that verify expected state

### 15. Stateful Mocks for Testing State Transitions

**Pattern**: Use file-based counters or log file checks to create mocks that change behavior based on call count or execution phase

**When to use**: When testing scenarios where state changes during execution (e.g., partition clears during recovery, VPN comes back up during monitoring)

**Key Insight**: Some checks happen at different points in execution:
- `validate_monitor_state()` runs once at script start
- `monitor_location()` can re-check partition status during recovery
- Tests need to account for this timing difference when mocking state transitions

**Example - Call Counter Pattern**:
```bash
@test "partition clears during recovery" {
    # Set up initial state (partitioned)
    local partition_state_file="${STATE_DIR}/network_partition_state"
    echo "1" >"$partition_state_file"
    
    # Create counter file for tracking calls
    local route_call_count_file="${TEST_DIR}/route_call_count"
    echo "0" >"$route_call_count_file"
    
    # Mock ip command - returns different results based on call count
    local mock_ip="${TEST_DIR}/ip"
    cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "route" ]] && [[ "$2" == "show" ]] && [[ "$3" == "default" ]]; then
    # Read counter from file (NOT using local keyword - see pattern 5)
    route_call_count_file="${TEST_DIR}/route_call_count"
    route_call_count=$(cat "$route_call_count_file" 2>/dev/null || echo "0")
    route_call_count=$((route_call_count + 1))
    echo "$route_call_count" >"$route_call_count_file"
    
    # First call fails (partitioned), subsequent succeed (cleared)
    if [[ $route_call_count -eq 1 ]]; then
        exit 1  # Partitioned
    else
        echo "default via 192.168.1.1 dev eth0"
        exit 0  # Cleared
    fi
fi
exec /usr/bin/ip "$@"
EOF
    chmod +x "$mock_ip"
    add_mock_to_path
    
    # Test expects partition to clear during recovery
    run bash "$TEST_SCRIPT"
    assert_success
    assert_file_contains "$LOG_FILE" "Network connectivity restored"
    
    remove_mock_from_path
}
```

**Example - Log File Check Pattern**:
```bash
# Mock that checks log file to determine execution phase
cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    log_file_path="${LOG_FILE:-${TEST_DIR}/logs/vpn-monitor.log}"
    # Check if recovery has started by looking for recovery messages
    if [[ -f "$log_file_path" ]] && grep -q "Attempting xfrm-based" "$log_file_path" 2>/dev/null; then
        # Recovery phase: return SAs so they can be deleted
        echo "src 192.168.1.1 dst 192.168.1.1"
        echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
        exit 0
    else
        # Initial checks: return empty (VPN down, triggers recovery)
        exit 0
    fi
fi
exec /usr/bin/ip "$@"
EOF
```

**Important Notes**:
- **Never use `local` keyword** at top level of mock scripts (see pattern 5)
- Use file-based counters for simple state tracking (call count)
- Use log file checks for more complex state detection (execution phase)
- Export `TEST_DIR` if mock script needs to access test directory
- When overwriting fixture mocks, explicitly remove the fixture's mock first: `rm -f "${TEST_DIR}/ip"`
- Counter files should be initialized before creating the mock: `echo "0" >"$counter_file"`

**Standard**: 
- Use file-based counters for simple call-count-based state transitions
- Use log file checks for execution-phase-based state transitions
- Always initialize counter files before creating mocks
- Export TEST_DIR if mock needs to access test directory
- Remove fixture mocks before creating custom mocks if needed
- Never use `local` keyword at top level of mock scripts

### 16. Testing Partition Clearing During Recovery

**Pattern**: Test scenarios where network partition clears during recovery execution

**When to use**: When testing recovery behavior that depends on partition state changing during execution

**Key Insight**: Partition checks happen at different points:
- `validate_monitor_state()` checks partition once at script start
- `monitor_location()` can re-check partition status during recovery if state file indicates partitioned
- Tests need to mock partition clearing between these checks

**Example**:
```bash
@test "partition clears during recovery - should continue recovery" {
    # Set initial partition state
    local partition_state_file="${STATE_DIR}/network_partition_state"
    echo "1" >"$partition_state_file"
    
    # Mock partition check - first call fails (partitioned), second succeeds (cleared)
    # First call: validate_monitor_state() at script start
    # Second call: monitor_location() during recovery
    local route_call_count_file="${TEST_DIR}/route_call_count"
    echo "0" >"$route_call_count_file"
    
    local mock_ip="${TEST_DIR}/ip"
    cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "route" ]] && [[ "$2" == "show" ]] && [[ "$3" == "default" ]]; then
    route_call_count_file="${TEST_DIR}/route_call_count"
    route_call_count=$(cat "$route_call_count_file" 2>/dev/null || echo "0")
    route_call_count=$((route_call_count + 1))
    echo "$route_call_count" >"$route_call_count_file"
    
    if [[ $route_call_count -eq 1 ]]; then
        exit 1  # First call: partitioned
    else
        echo "default via 192.168.1.1 dev eth0"
        exit 0  # Second call: cleared
    fi
fi
exec /usr/bin/ip "$@"
EOF
    chmod +x "$mock_ip"
    add_mock_to_path
    
    run bash "$TEST_SCRIPT"
    
    # Should detect partition cleared and continue recovery
    assert_success
    assert_file_contains "$LOG_FILE" "Network connectivity restored"
    assert_file_contains "$LOG_FILE" "Tier 2" || assert_file_contains "$LOG_FILE" "reload"
    
    remove_mock_from_path
}
```

**Important Notes**:
- Partition state file (`network_partition_state`) tracks persistent partition state
- `validate_monitor_state()` updates state file based on current partition check
- `monitor_location()` reads state file and can re-check if state indicates partitioned
- Mock should return different results for first call (validate_monitor_state) vs second call (monitor_location)
- Test should verify both: partition clearing detection AND recovery continuation

**Standard**: 
- Set partition state file to "1" before test execution
- Mock partition check to fail on first call, succeed on second call
- Verify partition clearing message is logged
- Verify recovery actions continue after partition clears
- Use call counters to track which check is being performed

## Helper Functions

### `enable_fake_mode()`
Enables fake mode (NO_ESCALATE=1) to prevent functions from exiting on errors.

**Usage**: Call before functions that might exit on error.

### `setup_location_config_and_load(config_file)`
Sets up test environment, sets CONFIG_FILE, and loads configuration.

**Usage**: Call after creating a config file to set up environment and load config.

**Note**: Automatically exports CONFIG_FILE.

### `setup_test_location_config(config_file, ...)`
Creates a location-based config file with common test settings.

**Usage**: Call to create config file, then use `setup_location_config_and_load()` to load it.

### `setup_test_config(config_file, peer_ips, ...)`
Creates a legacy-format config file with EXTERNAL_PEER_IPS.

**Usage**: For tests using legacy configuration format.

### `setup_test_vpn_monitor(peer_ips, state_dir, ...)`
Sets up complete VPN monitor test environment (config, script, environment variables).

**Usage**: When you need a full test environment setup.

### `setup_mock_vpn_environment(peer_ip, bytes, spi, ...)`
Creates mock ip, ping, and ipsec commands and adds them to PATH.

**Usage**: When you need multiple VPN-related mocks.

### `add_mock_to_path()` / `remove_mock_from_path()`
Adds/removes TEST_DIR from PATH for mock commands.

**Usage**: Always pair these - add before test, remove after.

**Important Notes**:
- `add_mock_to_path()` is **idempotent** - calling it multiple times is harmless but unnecessary
- Each `add_mock_to_path()` call should have a corresponding `remove_mock_from_path()` call
- Use the audit script `scripts/audit_mock_cleanup.sh` to verify proper cleanup in test files
- Common mistake: Duplicate `add_mock_to_path()` calls after creating multiple mocks - only one call is needed since all mocks are in the same `TEST_DIR`


### `source_function(function_name)`
Sources a single function from its module for unit testing.

**Usage**: For testing individual functions in isolation.

### `source_recovery_module()`
Sources all recovery-related modules and dependencies.

**Usage**: For recovery-related tests that need full module context.

## Consistency Guidelines

1. **Always use helper functions** when available instead of manual setup
2. **Always export variables** explicitly when setting manually
3. **Use `enable_fake_mode()`** instead of manual `NO_ESCALATE=1` and `export`
4. **Follow existing patterns** in test_helper.bash for new helpers
5. **Use fixtures** for common VPN state scenarios
6. **Always cleanup mocks** with `remove_mock_from_path()`
7. **Include test comments** with Purpose, Expected, and Importance
8. **Use test tags** to categorize and prioritize tests
9. **Use appropriate assertions** for different scenarios
10. **Follow consistent file structure** for test files
11. **Be aware of execution order** when testing configuration validation - it happens before other early-exit checks
12. **Use stateful mocks** with call counters or log file checks when testing state transitions
13. **Account for timing differences** when testing partition clearing - checks happen at different execution points

## Migration Notes

- Old pattern `NO_ESCALATE=1; export NO_ESCALATE` → Use `enable_fake_mode()`
- Old pattern manual CONFIG_FILE setup → Use `setup_location_config_and_load()`
- Old pattern manual config creation → Use `setup_test_location_config()` or `setup_test_config()`
- Old pattern manual mock setup → Use `setup_mock_vpn_environment()` or fixtures
- Old pattern missing cleanup → Always use `remove_mock_from_path()`
