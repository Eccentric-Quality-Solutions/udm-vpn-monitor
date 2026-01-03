# Test Patterns and Standards

This document describes standardized patterns for writing tests in the UDM VPN Monitor test suite.

## Related Documentation

For additional test documentation, see:

- **[tests/README.md](README.md)** - Quick start guide for running tests
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

Reusable test fixtures for common VPN monitoring scenarios. These fixtures combine multiple setup steps into single function calls, reducing duplication and ensuring consistent test environments.

#### Usage Pattern

1. Load `test_helper` (which provides base setup functions)
2. Load the specific fixture you need
3. Call the fixture setup function in your test
4. Write your test assertions

```bash
#!/usr/bin/env bats

load test_helper
load fixtures/vpn_active

@test "my test" {
    setup_vpn_active_fixture "192.168.1.1" 'TIER1_THRESHOLD=1'
    # Your test code here
    run bash "$TEST_SCRIPT" --fake
    assert_success
    remove_mock_from_path
}
```

#### Available Fixtures

##### `vpn_active.bash` - VPN Active and Healthy

Sets up a test environment where the VPN is active and healthy, with bytes increasing normally.

**Function**: `setup_vpn_active_fixture`

**Arguments**:
- `$1`: Peer IP address (default: "192.168.1.1")
- `$2`: Initial byte counter value (default: 1000)
- `$3`: Current byte counter value (default: 2000, should be > initial)
- `$4`: SPI value (default: 0x12345678)
- `$5+`: Additional config variables as KEY="VALUE" pairs

**Example**:
```bash
load test_helper
load fixtures/vpn_active

@test "VPN active - bytes increasing" {
    setup_vpn_active_fixture "192.168.1.1"
    # VPN is active, bytes increased from 1000 to 2000
    run bash "$TEST_SCRIPT" --fake
    assert_success
    remove_mock_from_path
}
```

##### `vpn_down.bash` - VPN Down (No SA Found)

Sets up a test environment where the VPN is down - no Security Association found.

**Function**: `setup_vpn_down_fixture`

**Arguments**:
- `$1`: Peer IP address (default: "192.168.1.1")
- `$2`: Failure count (default: 0, will be incremented when script runs)
- `$3+`: Additional config variables as KEY="VALUE" pairs

**Example**:
```bash
load test_helper
load fixtures/vpn_down

@test "VPN down - should detect failure" {
    setup_vpn_down_fixture "192.168.1.1"
    # VPN is down, no SA found
    run bash "$TEST_SCRIPT" --fake
    assert_failure
    assert_file_contains "$LOG_FILE" "Tier 1"
    remove_mock_from_path
}
```

##### `vpn_failing.bash` - VPN with Recorded Failures

Sets up a test environment where the VPN has recorded failures but is still being monitored. The VPN may be down or the byte counter may not be increasing.

**Function**: `setup_vpn_failing_fixture`

**Arguments**:
- `$1`: Peer IP address (default: "192.168.1.1")
- `$2`: Failure count (default: 3)
- `$3`: Last bytes value (default: 1000)
- `$4`: Current bytes value for mock (default: 1000, same as last - not increasing)
- `$5`: SPI value (default: 0x12345678)
- `$6+`: Additional config variables as KEY="VALUE" pairs

**Example**:
```bash
load test_helper
load fixtures/vpn_failing

@test "VPN failing - bytes not increasing" {
    setup_vpn_failing_fixture "192.168.1.1" 3
    # VPN has 3 failures, bytes stuck at 1000
    run bash "$TEST_SCRIPT" --fake
    # Should escalate to next tier
    remove_mock_from_path
}
```

##### `vpn_cooldown.bash` - VPN in Cooldown Period

Sets up a test environment where the VPN is in a cooldown period. During cooldown, the monitor should not take action even if VPN fails.

**Function**: `setup_vpn_cooldown_fixture`

**Arguments**:
- `$1`: Peer IP address (default: "192.168.1.1")
- `$2`: Failure count (default: 5, typically high enough to trigger cooldown)
- `$3`: Cooldown duration in seconds (default: 900 = 15 minutes)
- `$4+`: Additional config variables as KEY="VALUE" pairs

**Example**:
```bash
load test_helper
load fixtures/vpn_cooldown

@test "VPN in cooldown - should not take action" {
    setup_vpn_cooldown_fixture "192.168.1.1"
    # VPN in cooldown for 15 minutes
    run bash "$TEST_SCRIPT" --fake
    # Should skip action due to cooldown
    assert_file_contains "$LOG_FILE" "cooldown"
    remove_mock_from_path
}
```

##### `vpn_rekey.bash` - VPN Rekey Scenario

Sets up a test environment where the VPN has undergone a rekey (SPI change). Useful for testing rekey detection and byte counter baseline reset.

**Function**: `setup_vpn_rekey_fixture`

**Arguments**:
- `$1`: Peer IP address (default: "192.168.1.1")
- `$2`: Old SPI value (default: 0x12345678)
- `$3`: New SPI value (default: 0x87654321)
- `$4`: Old bytes value (default: 5000)
- `$5`: New bytes value (default: 1000, typically lower after rekey)
- `$6+`: Additional config variables as KEY="VALUE" pairs

**Example**:
```bash
load test_helper
load fixtures/vpn_rekey

@test "VPN rekey - SPI changes, baseline reset" {
    setup_vpn_rekey_fixture "192.168.1.1"
    # VPN has rekeyed, SPI changed from 0x12345678 to 0x87654321
    run bash "$TEST_SCRIPT" --fake
    assert_success
    assert_file_contains "$LOG_FILE" "rekey"
    remove_mock_from_path
}
```

##### `vpn_multiple_peers.bash` - VPN Multiple Peers Scenario

Sets up a test environment with multiple VPN peers for testing multi-peer scenarios.

**Function**: `setup_vpn_multiple_peers_fixture`

**Arguments**:
- `$1`: Peer IPs as space-separated string (default: "192.168.1.1 10.0.0.1 172.16.0.1")
- `$2`: Failure count for all peers (default: 0)
- `$3`: Bytes value for all peers (default: 1000)
- `$4`: SPI value for all peers (default: 0x12345678)
- `$5+`: Additional config variables as KEY="VALUE" pairs

**Example**:
```bash
load test_helper
load fixtures/vpn_multiple_peers

@test "Multiple peers - all healthy" {
    setup_vpn_multiple_peers_fixture "192.168.1.1 10.0.0.1"
    # Two peers, both healthy
    run bash "$TEST_SCRIPT" --fake
    assert_success
    remove_mock_from_path
}
```

##### `vpn_recovery_disabled.bash` - VPN with Recovery Disabled

Sets up a test environment where recovery actions are disabled. Useful for testing detection without recovery side effects.

**Function**: `setup_vpn_recovery_disabled_fixture`

**Arguments**:
- `$1`: Peer IP address (default: "192.168.1.1")
- `$2`: Failure count (default: 0)
- `$3`: Bytes value (default: 1000)
- `$4`: SPI value (default: 0x12345678)
- `$5+`: Additional config variables as KEY="VALUE" pairs

**Example**:
```bash
load test_helper
load fixtures/vpn_recovery_disabled

@test "VPN detection without recovery" {
    setup_vpn_recovery_disabled_fixture "192.168.1.1"
    # VPN with recovery disabled
    run bash "$TEST_SCRIPT" --fake
    # Should detect failures but not trigger recovery
    remove_mock_from_path
}
```

##### `vpn_rate_limited.bash` - VPN Rate Limited Scenario

Sets up a test environment where rate limiting is active. The fixture creates a `restart_count` file with recent restart timestamps and configures the environment to trigger Tier 3 recovery (which is rate limited).

**Function**: `setup_vpn_rate_limited_fixture`

**Arguments**:
- `$1`: Peer IP address (default: "192.168.1.1")
- `$2`: Number of restart timestamps to create if none provided (default: 3)
- `$3+`: Restart timestamps (epoch seconds, one per line in restart_count file). If not provided, creates timestamps relative to current time. Additional config variables as KEY="VALUE" pairs can be passed after timestamps.

**Example**:
```bash
load test_helper
load fixtures/vpn_rate_limited

@test "rate limit prevents restart" {
    # Use default: 3 restarts within last hour
    setup_vpn_rate_limited_fixture "192.168.1.1"
    run bash "$TEST_SCRIPT" --fake
    assert_file_contains "$LOG_FILE" "Rate limit exceeded"
    remove_mock_from_path
}

@test "rate limit with specific timestamps" {
    local now=$(date +%s)
    setup_vpn_rate_limited_fixture "192.168.1.1" 3 \
        $((now - 100)) \
        $((now - 200)) \
        $((now - 300))
    run bash "$TEST_SCRIPT" --fake
    assert_file_contains "$LOG_FILE" "Rate limit exceeded"
    remove_mock_from_path
}
```

##### `vpn_network_partition.bash` - VPN Network Partition Scenario

Sets up a test environment simulating network partition conditions. This fixture configures mocks for route checks, interface state checks, and DNS resolution to simulate various network partition scenarios.

**Function**: `setup_vpn_network_partition_fixture`

**Arguments**:
- `$1`: Peer IP address (default: "192.168.1.1")
- `$2`: Partition type (default: "all")
  - `"no_default_route"`: No default route available
  - `"interfaces_down"`: Network interfaces are down
  - `"dns_failure"`: DNS resolution fails
  - `"all"`: All partition conditions combined
- `$3`: Interface names as comma-separated string (default: "eth0,eth1", can be overridden via NETWORK_PARTITION_INTERFACES config)
- `$4+`: Additional config variables as KEY="VALUE" pairs

**Example**:
```bash
load test_helper
load fixtures/vpn_network_partition

@test "network partition - all conditions" {
    setup_vpn_network_partition_fixture "192.168.1.1" "all"
    # Network is partitioned: no route, interfaces down, DNS fails
    run bash "$TEST_SCRIPT" --fake
    # Should detect partition and not trigger VPN recovery
    remove_mock_from_path
}

@test "network partition - DNS failure only" {
    setup_vpn_network_partition_fixture "192.168.1.1" "dns_failure"
    # Only DNS resolution fails
    run bash "$TEST_SCRIPT" --fake
    # Should detect partition
    remove_mock_from_path
}

@test "network partition - custom interfaces" {
    setup_vpn_network_partition_fixture "192.168.1.1" "interfaces_down" "br0,eth0"
    # Interfaces are down with custom interface list
    run bash "$TEST_SCRIPT" --fake
    # Should detect partition
    remove_mock_from_path
}
```

##### `vpn_xfrm_recovery.bash` - VPN XFRM Recovery Scenario

Sets up a test environment for testing xfrm-based recovery operations. This fixture configures mocks for multiple Security Associations (SAs) and simulates different recovery scenarios (success, partial failure, complete failure).

**Function**: `setup_vpn_xfrm_recovery_fixture`

**Arguments**:
- `$1`: Peer IP address (default: "192.168.1.1")
- `$2`: SA count - number of Security Associations to simulate (default: 2)
- `$3`: Recovery type (default: "success")
  - `"success"`: All SA deletions succeed
  - `"partial_failure"`: Some SA deletions succeed, others fail (alternating pattern)
  - `"complete_failure"`: All SA deletions fail
- `$4+`: Additional config variables as KEY="VALUE" pairs

**Example**:
```bash
load test_helper
load fixtures/vpn_xfrm_recovery

@test "xfrm recovery - successful deletion" {
    setup_vpn_xfrm_recovery_fixture "192.168.1.1" 2 "success"
    # 2 SAs, all deletions succeed
    run bash "$TEST_SCRIPT" --fake
    # Should successfully delete all SAs and verify re-establishment
    remove_mock_from_path
}

@test "xfrm recovery - partial failure" {
    setup_vpn_xfrm_recovery_fixture "192.168.1.1" 3 "partial_failure"
    # 3 SAs, some deletions succeed, others fail
    run bash "$TEST_SCRIPT" --fake
    # Should handle partial failures gracefully
    remove_mock_from_path
}

@test "xfrm recovery - complete failure" {
    setup_vpn_xfrm_recovery_fixture "192.168.1.1" 2 "complete_failure"
    # 2 SAs, all deletions fail
    run bash "$TEST_SCRIPT" --fake
    # Should fall back to ipsec reload/restart
    remove_mock_from_path
}

@test "xfrm recovery - custom config" {
    setup_vpn_xfrm_recovery_fixture "192.168.1.1" 2 "success" \
        'TIER2_THRESHOLD=5' \
        'RECOVERY_VERIFY_TIMEOUT=10'
    # Custom thresholds and timeout
    run bash "$TEST_SCRIPT" --fake
    # Should use custom config values
    remove_mock_from_path
}
```

##### `vpn_at_tier.bash` - VPN at Specific Tier Threshold

Sets up a test environment where the VPN has reached a specific tier threshold. This fixture simplifies tier-specific test scenarios by automatically configuring the failure count and tier thresholds.

**Function**: `setup_vpn_at_tier_fixture`

**Arguments**:
- `$1`: Tier number (1, 2, or 3) (default: 1)
- `$2`: Peer IP address (default: "192.168.1.1")
- `$3+`: Additional config variables as KEY="VALUE" pairs

**Example**:
```bash
load test_helper
load fixtures/vpn_at_tier

@test "tier 1: logging triggered" {
    setup_vpn_at_tier_fixture 1 "192.168.1.1"
    # VPN at Tier 1 threshold (failure_count=1, TIER1_THRESHOLD=1)
    run bash "$TEST_SCRIPT" --fake
    # Should trigger Tier 1 action (logging)
    remove_mock_from_path
}

@test "tier 2: surgical cleanup" {
    setup_vpn_at_tier_fixture 2 "192.168.1.1" 'ENABLE_XFRM_RECOVERY=0'
    # VPN at Tier 2 threshold (failure_count=3, TIER2_THRESHOLD=3)
    run bash "$TEST_SCRIPT" --fake
    # Should trigger Tier 2 action (ipsec reload)
    remove_mock_from_path
}

@test "tier 3: restart" {
    setup_vpn_at_tier_fixture 3 "192.168.1.1" 'MAX_RESTARTS_PER_HOUR=10'
    # VPN at Tier 3 threshold (failure_count=5, TIER3_THRESHOLD=5)
    run bash "$TEST_SCRIPT" --fake
    # Should trigger Tier 3 action (ipsec restart)
    remove_mock_from_path
}
```

##### `vpn_idle.bash` - VPN Idle Tunnel Scenario

Sets up a test environment where the VPN tunnel is idle (bytes not increasing) but ping succeeds. This simulates a healthy tunnel that is not passing traffic.

**Function**: `setup_vpn_idle_fixture`

**Arguments**:
- `$1`: Peer IP address (default: "192.168.1.1")
- `$2`: Static bytes value (default: 1000) - bytes that don't increase
- `$3`: Internal IP for ping check (default: "10.0.0.1")
- `$4`: SPI value (default: 0x12345678)
- `$5+`: Additional config variables as KEY="VALUE" pairs

**Example**:
```bash
load test_helper
load fixtures/vpn_idle

@test "idle tunnel detected - ping succeeds" {
    setup_vpn_idle_fixture "192.168.1.1"
    # Idle tunnel: bytes static at 1000, ping succeeds
    run bash "$TEST_SCRIPT" --fake
    # Should detect idle tunnel (ping succeeds, bytes not increasing)
    assert_file_contains "$LOG_FILE" "idle but healthy"
    remove_mock_from_path
}

@test "idle tunnel - custom bytes and IP" {
    setup_vpn_idle_fixture "192.168.1.1" 5000 "10.0.0.1"
    # Idle tunnel: bytes static at 5000, ping to 10.0.0.1 succeeds
    run bash "$TEST_SCRIPT" --fake
    # Should detect idle tunnel
    remove_mock_from_path
}
```

#### Important Notes

- **Fixtures automatically add mocks to PATH** - You don't need to call `add_mock_to_path()` after using fixtures
- Fixtures call `setup_mock_vpn_environment()` which internally calls `add_mock_to_path()`
- If you add additional mocks after a fixture, you may need to call `add_mock_to_path()` again (though it's idempotent)
- Always call `remove_mock_from_path()` for cleanup, even when using fixtures

#### Benefits

- **Reduced duplication**: Common setup patterns are centralized
- **Consistent setup**: All tests using the same fixture get identical environments
- **Easier maintenance**: Update fixture once, all tests benefit
- **Clear intent**: Fixture names clearly indicate test scenario

#### Migration Guide

To migrate existing tests to use fixtures:

**Before**:
```bash
@test "VPN active test" {
    setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"
    source_function "set_peer_state"
    set_peer_state "" "192.168.1.1" "last_bytes" "1000"
    setup_mock_vpn_environment "192.168.1.1" 2000
    # Test code
}
```

**After**:
```bash
load fixtures/vpn_active

@test "VPN active test" {
    setup_vpn_active_fixture "192.168.1.1"
    # Test code
    remove_mock_from_path
}
```

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
- `assert_log_contains_any` - Check log contains at least one of multiple patterns (for variant messages)
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
- Use `assert_log_contains_any` when log messages may vary slightly (e.g., "ipsec reload failed" vs "reload failed")
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

## Test Coverage

Current test coverage: **46.9%** (1141/2433 lines) as of latest run.

### Coverage Goals

**Overall Coverage Targets**:
- **Minimum Overall Coverage**: 50% (current: 46.9%)
- **Target Overall Coverage**: 60%
- **Stretch Goal**: 70%

**Module-Specific Coverage Targets**:

| Module | Current | Minimum Target | Target | Priority |
|--------|---------|----------------|--------|----------|
| `lib/detection.sh` | - | 70% | 80% | P0 (Critical) |
| `lib/recovery.sh` | - | 70% | 80% | P0 (Critical) |
| `lib/state.sh` | - | 70% | 80% | P0 (Critical) |
| `lib/lockfile.sh` | - | 70% | 80% | P0 (Critical) |
| `lib/config.sh` | - | 60% | 70% | P1 (High) |
| `lib/config_schema.sh` | - | 60% | 70% | P1 (High) |
| `lib/logging.sh` | - | 60% | 70% | P1 (High) |
| `lib/common.sh` | - | 50% | 60% | P2 (Medium) |
| `lib/resources.sh` | - | 50% | 60% | P2 (Medium) |
| `lib/constants.sh` | - | 40% | 50% | P3 (Low) |
| `vpn-monitor.sh` | - | 60% | 70% | P1 (High) |
| `vpn-keepalive.sh` | - | 60% | 70% | P1 (High) |
| `install.sh` | - | 50% | 60% | P2 (Medium) |
| `uninstall.sh` | - | 50% | 60% | P2 (Medium) |

**Coverage Priorities**:

1. **P0 (Critical)**: Core functionality that could cause production failures
   - Detection logic
   - Recovery actions
   - State management
   - Lockfile handling

2. **P1 (High)**: Important functionality that affects reliability
   - Configuration loading and validation
   - Logging
   - Main script execution

3. **P2 (Medium)**: Supporting functionality
   - Common utilities
   - Resource monitoring
   - Installation/uninstallation

4. **P3 (Low)**: Less critical functionality
   - Constants
   - Simple utilities

**Coverage Measurement**:
- **Tool**: kcov for line coverage
- **Frequency**: Measured in CI on every commit
- **Reporting**: Coverage reports generated in `coverage/` directory
- **Review**: Coverage gaps reviewed quarterly

**Coverage Improvement Strategy**:
1. **Focus on Critical Paths First**: Prioritize P0 modules
2. **Test Error Paths**: Ensure error handling is covered
3. **Test Edge Cases**: Cover boundary conditions and edge cases
4. **Maintain Coverage**: Ensure new code has tests
5. **Regular Review**: Review coverage reports to identify gaps

**Coverage Goals Review**:
- **Quarterly**: Review and update coverage goals
- **After Major Changes**: Reassess goals when codebase changes significantly
- **When Issues Arise**: Update goals to address coverage gaps

## High-Risk Tests

The test suite includes comprehensive tests for critical paths and error handling scenarios that could cause production failures. These tests are distributed across multiple test files for better organization:

### Test Categories

**1. Lockfile Management** (`test_lockfile.sh` - 18 tests)
Tests lockfile cleanup, error handling, race conditions, and edge cases.

**2. Configuration Loading and Validation** (`test_config.sh` and split files - 120 tests total)
Tests configuration file error handling, security, validation, location-based configuration, and edge cases.

**3. VPN Status Detection** (`test_detection.sh` and split files - 105 tests total)
Tests VPN detection edge cases, byte counter handling, fallback mechanisms, network partitions, rekey detection, and XFRM edge cases.

**4. Recovery Actions** (`test_recovery.sh` and split files - 51 tests total)
Tests recovery action execution, error handling, tier-based recovery, rate limiting, cooldown interactions, and partial failures.

**5. State and File Management** (`test_state.sh`, `test_state_concurrent_updates.sh`, and `test_state_location.sh` - 56 tests total)
Tests state file handling, permissions, corruption, concurrent updates, location-based state management, and edge cases.

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

### Test Statistics

- **Total High-Risk Tests**: ~222 tests across multiple files (marked as slow tests)
- **Test Categories**: 10 main categories
- **Focus Areas**: Critical error handling, edge cases, security, race conditions, resource management

### CI Integration

The high-risk tests are automatically included in CI when `RUN_SLOW_TESTS=1` is set because:
1. `run_tests.sh` automatically discovers all `test_*.sh` files
2. High-risk test files are marked as slow tests
3. CI runs `./tests/run_tests.sh --slow` which includes all test files

For more information on test coverage gaps, see [TEST_COVERAGE_GAPS.md](../TEST_COVERAGE_GAPS.md).

## Individual Script Test Coverage

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

## Contributing

When adding new features or making changes:

1. **Add tests for new functionality** - Ensure new code has corresponding tests
2. **Ensure all tests pass** - Run the full test suite before submitting changes
3. **Follow existing test patterns** - Use standardized patterns from this document
4. **Update test documentation** - Update relevant documentation if adding new test utilities or patterns
5. **Maintain test coverage** - Aim to maintain or improve overall test coverage

### Test Coverage Requirements

- **New features**: Should include tests covering the main functionality
- **Bug fixes**: Should include tests that verify the fix and prevent regression
- **Critical paths**: Must have comprehensive test coverage (see [Test Coverage](#test-coverage) section)

### Running Tests Before Contributing

```bash
# Run fast tests (quick check)
./tests/run_tests.sh

# Run all tests including slow tests (before submitting)
./tests/run_tests.sh --slow

# Run with coverage to verify coverage goals
./tests/run_tests.sh --slow --coverage
```

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
