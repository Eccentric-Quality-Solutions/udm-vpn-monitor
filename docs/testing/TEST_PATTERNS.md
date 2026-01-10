# Test Patterns and Standards

This document describes standardized patterns for writing tests in the UDM VPN Monitor test suite.

## Related Documentation

For additional test documentation, see:

- **[tests/README.md](../tests/README.md)** - Quick start guide for running tests and test suite overview
- **[tests/fixtures/README.md](../tests/fixtures/README.md)** - Reusable test fixtures for common VPN monitoring scenarios
- **[BATS Guide](BATS_GUIDE.md)** - BATS framework usage, patterns, and advanced features
- **[Test Strategy](TEST_STRATEGY.md)** - Test strategy, philosophy, and approach
- **[Test Maintenance](TEST_MAINTENANCE.md)** - Test maintenance procedures and guidelines

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

**Note**: When testing VPN down scenarios with `setup_mock_vpn_environment` using `bytes=0`, you must set `last_bytes > 0` first. This ensures bytes=0 is detected as "bytes dropped to 0" (a failure) rather than "first check with bytes=0" (which may be treated as idle if ping succeeds). Example:
```bash
# Set last_bytes > 0 so bytes=0 is detected as failure (bytes dropped)
ensure_state_functions_loaded
set_peer_state "TEST1" "192.168.1.1" "last_bytes" "1000" || true
setup_mock_vpn_environment "192.168.1.1" 0
```

**Note for Recovery Detection Tests**: When testing VPN recovery scenarios (where VPN transitions from failed to healthy), you must set up both `last_bytes` and `spi` state files before setting up the mock VPN environment. This ensures the byte counter check can properly detect recovery (bytes increasing). Example:
```bash
# Step 1: VPN fails (creates failure_count)
setup_vpn_down_fixture "192.168.1.1" 0
run bash "$TEST_SCRIPT" --fake
# Verify failure_count was incremented...

# Step 2: VPN recovers - set up state files for byte counter check
ensure_state_functions_loaded
set_peer_state "TEST" "192.168.1.1" "last_bytes" "1000" || true
set_peer_state "TEST" "192.168.1.1" "spi" "0x12345678" || true
setup_mock_vpn_environment "192.168.1.1" 2000  # Bytes increasing = recovery
run bash "$TEST_SCRIPT" --fake
# Should detect recovery and log recovery message
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

##### `vpn_flapping.bash` - VPN Flapping Scenario

Sets up a test environment where the VPN can transition between up/down states during test execution. Provides helper functions to switch states dynamically, making it ideal for testing VPN flapping scenarios.

**Function**: `setup_vpn_flapping_fixture`

**Arguments**:
- `$1`: Peer IP address (default: "192.168.1.1")
- `$2`: Initial state ("up" or "down", default: "up")
- `$3`: Initial byte counter value (default: 1000, used when initial state is "up")
- `$4`: Current byte counter value (default: 2000, used when initial state is "up")
- `$5`: SPI value (default: 0x12345678)
- `$6+`: Additional config variables as KEY="VALUE" pairs

**Helper Functions** (available after calling `setup_vpn_flapping_fixture`):
- `switch_vpn_to_up([bytes] [spi])` - Switch VPN to up state
  - Optional `bytes`: Byte counter value (default: uses value from fixture setup)
  - Optional `spi`: SPI value (default: uses value from fixture setup)
- `switch_vpn_to_down()` - Switch VPN to down state

**Example**:
```bash
load test_helper
load fixtures/vpn_flapping

@test "VPN flapping - state transitions" {
    setup_vpn_flapping_fixture "192.168.1.1" "up"
    # VPN starts up

    # Run - VPN is up, should succeed
    run bash "$TEST_SCRIPT" --fake
    assert_success

    # Switch VPN to down
    switch_vpn_to_down

    # Run - VPN is down, should detect failure
    run bash "$TEST_SCRIPT" --fake
    assert_failure

    # Switch VPN back to up
    switch_vpn_to_up

    # Run - VPN recovered, should succeed
    run bash "$TEST_SCRIPT" --fake
    assert_success

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

##### `vpn_mixed_peers.bash` - VPN Mixed Peers Scenario

Sets up a test environment with multiple VPN peers where some are up and some are down. This fixture allows testing independent peer state tracking and per-peer recovery actions.

**Function**: `setup_vpn_mixed_peers_fixture`

**Arguments**:
- `$1`: Peer IPs as space-separated string (default: "192.168.1.1 10.0.0.1 172.16.0.1")
- `$2`: States as space-separated string ("up" or "down" for each peer, default: "up up up")
- `$3`: Bytes value for peers that are "up" (default: 1000)
- `$4`: SPI value for all peers (default: 0x12345678)
- `$5+`: Additional config variables as KEY="VALUE" pairs

**Example**:
```bash
load test_helper
load fixtures/vpn_mixed_peers

@test "Multiple peers with mixed states" {
    setup_vpn_mixed_peers_fixture "192.168.1.1 192.168.1.2 192.168.1.3" "up down up"
    # Sets peer 1 up, peer 2 down, peer 3 up
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
    remove_mock_from_path
}
```

##### `vpn_bytes_zero.bash` - VPN with Bytes=0 (Suspect Condition)

Sets up a test environment where the VPN SA exists but byte counter is exactly 0, indicating a suspect condition (tunnel established but not passing traffic). This fixture is useful for testing detection of this specific failure scenario.

**Function**: `setup_vpn_bytes_zero_fixture`

**Arguments**:
- `$1`: Peer IP address (default: "192.168.1.1")
- `$2`: SPI value (default: 0x12345678)
- `$3+`: Additional config variables as KEY="VALUE" pairs

**Example**:
```bash
load test_helper
load fixtures/vpn_bytes_zero

@test "detect bytes=0 as suspect condition" {
    setup_vpn_bytes_zero_fixture "192.168.1.1" "0x12345678" 'ENABLE_NETWORK_PARTITION_CHECK=0'
    # VPN SA exists but bytes=0 (suspect condition)
    run bash "$TEST_SCRIPT" --fake
    assert_file_contains "$LOG_FILE" "bytes=0" || assert_file_contains "$LOG_FILE" "suspect"
    remove_mock_from_path
}
```

##### `vpn_recovery_test.bash` - Recovery Test Setup

Sets up a test environment for recovery tests with pass-through mocks. This fixture is designed for recovery strategy selection and recovery mechanism tests that need ip/ipsec commands to pass through to real commands. The fixture automatically sets `ENABLE_XFRM_RECOVERY=1` unless explicitly overridden.

**Function**: `setup_vpn_recovery_test_fixture`

**Arguments**:
- `$1`: Peer IP address (default: "192.168.1.1")
- `$2+`: Additional config variables as KEY="VALUE" pairs (can override `ENABLE_XFRM_RECOVERY` if needed)

**Example**:
```bash
load test_helper
load fixtures/vpn_recovery_test

@test "recovery strategy selection" {
    setup_vpn_recovery_test_fixture "192.168.1.1"
    # Recovery test setup with pass-through mocks, ENABLE_XFRM_RECOVERY=1 by default
    source_recovery_module
    select_recovery_strategy "192.168.1.1" 2
    assert_equal "$RECOVERY_STRATEGY" "xfrm"
    remove_mock_from_path
}

@test "recovery test with custom config" {
    setup_vpn_recovery_test_fixture "192.168.1.1" 'TIER1_THRESHOLD=1'
    # Recovery test setup with custom config
    remove_mock_from_path
}
```

**Note**: This fixture creates pass-through mocks that allow real commands to be called. For tests that need xfrm unavailable, you can remove the ip mock: `rm -f "${TEST_DIR}/ip"` after calling the fixture.

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

**CRITICAL REQUIREMENT: Always Handle Both `ip -s xfrm state` and `ip xfrm state` Formats**

When creating mocks for the `ip` command that handle `xfrm state` queries, **you must handle both command variants**:

1. **`ip -s xfrm state`** (with statistics flag) - tried first by `get_xfrm_state_for_peer()`
2. **`ip xfrm state`** (without statistics flag) - fallback used by `get_xfrm_state_for_peer()`

**Why this is required**: The `get_xfrm_state_for_peer()` function in `lib/detection.sh` tries `ip -s xfrm state` first (line 591), then falls back to `ip xfrm state` if the first call fails or returns empty (line 600). If your mock only handles one variant, tests may fail when the code calls the other variant first.

**Standard Pattern**:
```bash
# ✅ CORRECT: Handle both formats
local mock_ip="${TEST_DIR}/ip"
cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # Handle "ip -s xfrm state" (with statistics flag) - tried first by get_xfrm_state_for_peer
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Handle "ip xfrm state" (without statistics flag) - fallback used by get_xfrm_state_for_peer
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
chmod +x "$mock_ip"
add_mock_to_path
```

**❌ INCORRECT: Only handling one format**
```bash
# ❌ WRONG: Only handles ip xfrm state (without -s)
# This will fail when get_xfrm_state_for_peer calls ip -s xfrm state first
cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
```

**Helper Functions**: The helper functions in `test_helper.bash` already handle both formats correctly:
- `mock_ip_xfrm_state()` - handles both formats
- `mock_ip_vpn_down()` - handles both formats
- `mock_ip_xfrm_empty()` - handles both formats
- `mock_ip_xfrm_with_incrementing_bytes()` - handles both formats

**When to use helpers vs inline mocks**:
- **Use helpers** for simple static cases (see `docs/INLINE_MOCKS_AUDIT.md`)
- **Use inline mocks** for complex scenarios with state tracking, conditional behavior, or special edge cases
- **Always handle both formats** regardless of which approach you use

**Related Patterns**:
- See pattern 21 (Byte Counter Increment Pattern) for examples with both formats
- See pattern 18 (Mock All Commands Used by Recovery Verification) for complete mocking examples

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
- **Fixtures and mocks**: See Pattern 4 (Test Fixtures) for details on how fixtures automatically add mocks to PATH
- If you add additional mocks after a fixture, you may need to call `add_mock_to_path()` again (though it's idempotent, so calling it multiple times is harmless)

**Standard**:
- Create mocks in `TEST_DIR`
- Use `add_mock_to_path()` before running tests (unless using fixtures, which handle this automatically - see Pattern 4)
- Always call `remove_mock_from_path()` in teardown or at end of test (even when using fixtures - see Pattern 4)
- Use helper functions like `setup_mock_vpn_environment()` when possible
- Prefer fixtures over manual mock setup when they match your test scenario

**Escape Variables in Heredocs When Creating Mock Scripts**

**Pattern**: When using `<<EOF` (without quotes) to create mock scripts, always escape script arguments like `\$1`, `\$2`, `\$@` so they're evaluated when the mock script runs, not when the test creates the script.

**When to use**: When creating mock scripts using heredoc syntax without quotes (`<<EOF`).

**Key Insight**: Variables like `$1`, `$2`, `$@` are expanded during test execution (when the heredoc is created), not when the mock script runs. This causes the mock script to receive incorrect values or fail to match arguments correctly.

**Related**: See Pattern 21 for similar heredoc variable expansion patterns when creating config files (with additional security considerations).

**Example**:
```bash
# ✅ GOOD: Escape variables in heredoc
cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF

# ❌ BAD: Unescaped variables (expanded during test execution)
cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "$1" == "-s" ]] && [[ "$2" == "xfrm" ]] && [[ "$3" == "state" ]]; then
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    exit 0
fi
exec /usr/bin/ip "$@"
EOF

# ✅ ALTERNATIVE: Use quoted heredoc to prevent all expansion
cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
```

**Important Notes**:
- When creating mock scripts with `<<EOF` (without quotes), escape all script arguments: `\$1`, `\$2`, `\$3`, `\$@`
- Variables from the test environment (like `${TEST_PEER_IP}`) should NOT be escaped - they should expand during test execution
- Alternatively, use `<<'EOF'` (with quotes) to prevent all expansion, but then you can't use test variables
- Check existing mocks in `test_helper.bash` for correct patterns (e.g., `mock_ip_xfrm_state()`)

**Standard**:
- Always escape script arguments (`\$1`, `\$2`, `\$@`) in unquoted heredocs
- Don't escape test environment variables (they should expand during test execution)
- Use quoted heredocs (`<<'EOF'`) only when you don't need variable expansion

**Mock Commands Must Handle Command Availability Checks**

**Pattern**: When mocking commands, handle command availability check arguments (`--help` and `--version`) in addition to the actual command subcommands.

**When to use**: When creating mocks for commands that are checked by `check_command_available()` or `check_command_or_warn()`.

**Key Insight**: The `check_command_available()` function uses multiple fallback mechanisms:
1. First tries `command -v` (checks PATH)
2. Falls back to checking system directories
3. Falls back to executing command with `--help` or `--version` flags

Mocks that only handle specific subcommands (e.g., `status`, `reload`) will fail when `check_command_available()` tries to verify the command exists via the `--help`/`--version` fallback.

**Example**:
```bash
# ✅ GOOD: Explicitly handle command availability checks
cat >"$mock_ipsec" <<EOF
#!/bin/bash
if [[ "\$1" == "status" ]]; then
    echo "test-conn: ESTABLISHED 1 hour ago, 192.168.1.1...192.168.1.2"
    exit 0
elif [[ "\$1" == "--help" ]] || [[ "\$1" == "--version" ]]; then
    # Handle command availability checks
    exit 0
fi
exit 1
EOF

# ✅ GOOD: Use exec fallback (works if real command exists)
cat >"$mock_ipsec" <<EOF
#!/bin/bash
if [[ "\$1" == "status" ]]; then
    echo "test-conn: ESTABLISHED 1 hour ago, 192.168.1.1...192.168.1.2"
    exit 0
fi
exec /usr/bin/ipsec "\$@"
EOF

# ❌ BAD: Only handle specific subcommand (fails availability check)
cat >"$mock_ipsec" <<EOF
#!/bin/bash
if [[ "\$1" == "status" ]]; then
    echo "test-conn: ESTABLISHED 1 hour ago, 192.168.1.1...192.168.1.2"
    exit 0
fi
exit 1
EOF
```

**Important Notes**:
- Before creating mocks, check if the code calls `check_command_available()` or `check_command_or_warn()` for the command
- If so, ensure the mock handles `--help` and `--version` arguments
- Prefer explicit handling over `exec` fallback for test reliability (real command may not exist in test environment)
- Update helper functions (e.g., `mock_ipsec_status()`) to handle availability checks for consistency

**Standard**:
- Check if commands are validated by `check_command_available()` before creating mocks
- Always handle `--help` and `--version` arguments in mocks
- Prefer explicit handling over `exec` fallback for test reliability

**When Refactoring Helper Functions, Maintain Backward Compatibility or Update All Callers**

**Pattern**: When changing default behavior of helper functions (e.g., default file paths), either maintain backward compatibility or update all callers.

**When to use**: When refactoring test helper functions that have default parameters or behavior.

**Key Insight**: Tests with special requirements may need explicit parameters. Default paths should match the most common usage pattern to minimize required changes.

**Example**:
```bash
# ✅ GOOD: Maintain backward compatibility
setup_test_environment() {
    local test_dir="${1:-${TEST_DIR}}"
    local state_dir="${2:-${test_dir}/state}"
    # ... rest of function
}

# ✅ GOOD: Update all callers when changing defaults
# Update all test files that use the helper to pass explicit parameters

# ❌ BAD: Change defaults without updating callers
setup_test_environment() {
    local test_dir="${1:-/tmp/new-default}"  # Breaks existing tests
    # ... rest of function
}
```

**Standard**:
- When changing defaults, either maintain backward compatibility or update all callers
- Default paths should match the most common usage pattern
- Document changes in helper function behavior

**Fixtures Can Export Helper Functions for Dynamic Test Behavior**

**Pattern**: When fixtures need to provide dynamic behavior during test execution (e.g., switching VPN states), define helper functions inside the fixture and export them using `export -f`.

**When to use**: When fixtures need to provide both initial setup and runtime helpers for testing state transitions.

**Key Insight**: This pattern allows fixtures to provide both initial setup and runtime helpers. Helper functions should use exported variables (e.g., `VPN_FLAPPING_PEER_IP`) to access fixture state. This pattern is useful for testing state transitions and flapping scenarios where the test needs to modify the environment during execution.

**Example**:
```bash
# In fixture file (e.g., fixtures/vpn_flapping.bash)
setup_vpn_flapping_fixture() {
    local peer_ip="${1:-192.168.1.1}"
    export VPN_FLAPPING_PEER_IP="$peer_ip"
    # ... setup code ...

    # Export helper function for runtime state changes
    switch_vpn_to_up() {
        # Use exported variable to access fixture state
        local peer_ip="${VPN_FLAPPING_PEER_IP}"
        # ... switch VPN to up state ...
    }
    export -f switch_vpn_to_up
}

# In test file
load fixtures/vpn_flapping

@test "VPN flapping test" {
    setup_vpn_flapping_fixture "192.168.1.1"
    # Initial state is up

    # Use exported helper to change state during test
    switch_vpn_to_up
    run bash "$TEST_SCRIPT" --fake
    assert_success

    switch_vpn_to_down
    run bash "$TEST_SCRIPT" --fake
    assert_failure
}
```

**Important Notes**:
- Helper functions should use exported variables to access fixture state
- Use `export -f` to make helper functions available to tests
- This pattern is useful for testing state transitions and flapping scenarios

**Standard**:
- Define helper functions inside fixtures when dynamic behavior is needed
- Export helper functions using `export -f`
- Use exported variables to share fixture state with helper functions

**Override Functions, Not Just Commands, When Testing Recovery**

**Pattern**: When testing recovery functions that call other functions (not just commands), override the function directly in the test.

**When to use**: When testing recovery functions that call other functions from `lib/detection.sh` or `lib/recovery.sh` that need to be mocked.

**Key Insight**: Functions are invoked directly, not through PATH lookup. Simply creating a mock command file won't work because the code calls the function directly, not via `command -v`.

**Example**:
```bash
# ✅ GOOD: Override function to use mock command
local mock_check_ipsec_phase2="${TEST_DIR}/check_ipsec_phase2"
cat >"$mock_check_ipsec_phase2" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$mock_check_ipsec_phase2"
add_mock_to_path

source_recovery_module

# Override the function to use mock
check_ipsec_phase2() {
    "$mock_check_ipsec_phase2" "$@"
}

# ❌ BAD: Only create mock command (function won't use it)
local mock_check_ipsec_phase2="${TEST_DIR}/check_ipsec_phase2"
cat >"$mock_check_ipsec_phase2" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$mock_check_ipsec_phase2"
add_mock_to_path
# Missing: Function override - check_ipsec_phase2() will use original function, not mock
```

**Functions That Need Overriding**:
- `check_ipsec_phase2()` - Function from `detection.sh`, used by `attempt_xfrm_recovery()` for verification
- `verify_byte_counters_resume()` - Function from `recovery.sh`, used for byte counter verification
- `count_sas_for_peer()` - Function from `recovery.sh`, used for SA counting

**Commands vs Functions**:
- **Commands** (e.g., `ip`, `ipsec`): Mock by creating executable file in PATH
- **Functions** (e.g., `check_ipsec_phase2`, `verify_byte_counters_resume`): Override function definition after sourcing module

**Systematic Application**:
- When testing recovery functions, identify which functions they call
- Check if those functions are commands (use PATH mock) or functions (override definition)
- Review `lib/recovery.sh` and `lib/detection.sh` to see function dependencies
- Override functions after sourcing modules, before calling recovery functions

**Related Patterns**:
- See `tests/test_recovery_method_tracking.sh` for examples of function overriding
- See `tests/test_recovery.sh` lines 987-990 for another example
- See `lib/recovery.sh:attempt_xfrm_recovery()` for function usage

**Standard**:
- When testing recovery functions, identify which functions they call
- Check if those functions are commands (use PATH mock) or functions (override definition)
- Override functions after sourcing modules, before calling recovery functions

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
- Use `assert_file_contains` for log file checks (uses regex matching - escape special characters like `\[` and `\]`)
- Use `assert_log_contains_any` when log messages may vary slightly (e.g., "ipsec reload failed" vs "reload failed")
- Use `assert_equal` for exact value comparisons
- Prefer descriptive assertions over generic `assert`

### 9. Recovery Message Patterns

**Pattern**: When checking for VPN recovery messages in logs, account for both "recovered" and "restored" message formats.

**When to use**: When writing tests that verify VPN recovery detection and logging.

**Key Insight**: The system uses different message formats depending on whether a recovery method was tracked:
- **"recovered"** - Used when no recovery method was stored (VPN recovered naturally or recovery method wasn't tracked)
- **"restored"** - Used when a recovery method was stored (a recovery action like xfrm, ipsec_reload, or ipsec_restart was attempted)

**Recovery Method Tracking**:
- Recovery methods are stored when recovery actions are attempted (e.g., `store_recovery_method()` is called in `surgical_cleanup()` or `full_restart()`)
- When VPN is detected as healthy, if a recovery method exists, the message says "restored" with the method; otherwise it says "recovered"
- Recovery methods are cleared after being logged to prevent stale information

**Example - Correct Pattern**:
```bash
@test "VPN recovery detection" {
    setup_vpn_xfrm_recovery_fixture "${TEST_PEER_IP}" 1 "success"

    # ... test setup that triggers recovery ...

    run bash "$TEST_SCRIPT"
    assert_success

    # ✅ GOOD: Check for both message formats
    # Note: Message may say "recovered" (no recovery method) or "restored" (with recovery method)
    assert_file_contains "$LOG_FILE" "recovered" || \
        assert_file_contains "$LOG_FILE" "restored" || \
        assert_file_contains "$LOG_FILE" "healthy"

    remove_mock_from_path
}
```

**Example - When Recovery Method is Explicitly Cleared**:
```bash
@test "VPN recovery without recovery method" {
    setup_location_test_vpn_monitor

    # Set failure count
    ensure_state_functions_loaded
    set_peer_state "NYC" "203.0.113.1" "failure_count" "3" || true

    # Explicitly ensure no recovery method is stored
    delete_peer_state "NYC" "203.0.113.1" "recovery_method" || true

    # Mock VPN as recovered
    setup_mock_vpn_environment "203.0.113.1" 2000

    run bash "$TEST_SCRIPT" --fake
    assert_success

    # Should log "recovered" (not "restored") since no recovery method was used
    assert_file_contains "$LOG_FILE" "recovered"

    remove_mock_from_path
}
```

**Example - When Recovery Method is Present**:
```bash
@test "VPN recovery with recovery method" {
    setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_XFRM_RECOVERY=1'

    # Perform recovery (stores recovery method)
    ensure_state_functions_loaded
    set_peer_state "TEST" "${TEST_PEER_IP}" "failure_count" "3"
    surgical_cleanup "${TEST_PEER_IP}" "TEST"

    # Mock VPN as recovered
    setup_mock_vpn_environment "${TEST_PEER_IP}" 2000

    run bash "$TEST_SCRIPT" --fake
    assert_success

    # Should log "restored" with recovery method
    assert_file_contains "$LOG_FILE" "VPN restored"
    assert_file_contains "$LOG_FILE" "recovery method: xfrm-based recovery"

    remove_mock_from_path
}
```

**Message Format Details**:
- With recovery method: `"VPN restored for LOCATION (IP) after N failures (recovery method: METHOD)"` or `"VPN restored for LOCATION (IP) (recovery method: METHOD)"`
- Without recovery method: `"VPN recovered for LOCATION (IP) after N failures"` or `"VPN recovered for LOCATION (IP)"`
- The "after N failures" part is included when `failure_count > 0`

**Important Notes**:
- Recovery methods are stored when recovery actions are attempted (Tier 2 or Tier 3)
- Recovery methods are cleared after being logged
- If a test explicitly clears the recovery method before recovery detection, the message will say "recovered"
- If a test performs recovery actions that store a recovery method, the message will say "restored"
- Tests that don't perform recovery actions may see either format depending on test setup

**Standard**:
- Always check for both "recovered" OR "restored" when testing recovery detection
- Optionally check for "healthy" as a fallback (used in some status messages)
- Use `delete_peer_state()` to clear recovery method if you want to test "recovered" format specifically
- Use recovery actions (like `surgical_cleanup()`) if you want to test "restored" format specifically

### 10. Config Setup Patterns

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

### 11. Source Function Pattern

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

### 12. Test File Structure

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

### 13. Running Tests

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

### 14. Testing Configuration Validation and Early-Exit Scenarios

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

### 15. DRY Improvements During Bug Fixes

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

### 16. Stateful Mocks for Testing State Transitions

**Pattern**: Use file-based counters or log file checks to create mocks that change behavior based on call count or execution phase

**When to use**: When testing scenarios where state changes during execution (e.g., partition clears during recovery, VPN comes back up during monitoring)

**Key Insight**: Some checks happen at different points in execution:
- `validate_monitor_state()` runs once at script start
- `monitor_location()` can re-check partition status during recovery if state file indicates partitioned
- Tests need to account for this timing difference when mocking state transitions

**Example - Partition Clearing During Recovery (Call Counter Pattern)**:
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

**Important Notes for Partition Clearing Tests**:
- Partition state file (`network_partition_state`) tracks persistent partition state
- `validate_monitor_state()` updates state file based on current partition check
- `monitor_location()` reads state file and can re-check if state indicates partitioned
- Mock should return different results for first call (validate_monitor_state) vs second call (monitor_location)
- Test should verify both: partition clearing detection AND recovery continuation
- Set partition state file to "1" before test execution
- Verify partition clearing message is logged
- Verify recovery actions continue after partition clears

**Standard**:
- Use file-based counters for simple call-count-based state transitions
- Use log file checks for execution-phase-based state transitions
- Always initialize counter files before creating mocks
- Export TEST_DIR if mock needs to access test directory
- Remove fixture mocks before creating custom mocks if needed
- Never use `local` keyword at top level of mock scripts

### 18. Mock All Commands Used by Recovery Verification

**Pattern**: When testing recovery actions, mock all commands used by verification functions, not just the recovery command itself.

**When to use**: When testing Tier 2 or Tier 3 recovery actions that include verification steps. Recovery functions often call verification functions that use additional commands beyond the recovery command.

**Key Insight**: Recovery functions call verification functions after performing recovery actions. These verification functions use additional commands (e.g., `ipsec status`, `ip xfrm state`) that must also be mocked. If verification commands aren't mocked, tests may timeout or fail unexpectedly.

**Example**:
```bash
@test "Tier 3 recovery - mock restart and status" {
    # ✅ GOOD: Mock both restart and status
    local mock_ipsec="${TEST_DIR}/ipsec"
    cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ipsec restart succeeded"
    exit 0
elif [[ "$1" == "status" ]]; then
    # Return status output that includes the peer IP for verification
    echo "192.168.1.1"
    exit 0
fi
exec /usr/bin/ipsec "$@"
EOF
    chmod +x "$mock_ipsec"
    add_mock_to_path

    # Test recovery
    run bash "$TEST_SCRIPT" --fake
    assert_success

    remove_mock_from_path
}

# ❌ BAD: Only mock restart (verification will fail/hang)
# If ipsec status isn't mocked, it falls through to exec /usr/bin/ipsec "$@"
# which may hang or fail, causing test timeout
```

**Verification Functions That Need Mocks**:
- `verify_ipsec_connections_active()` - calls `ipsec status`
- `verify_byte_counters_resume()` - calls `ip xfrm state`
- `check_ipsec_phase2()` - calls `ipsec status` or `ip xfrm state`

**Systematic Application**:
- When testing Tier 2 or Tier 3 recovery, check what verification functions are called
- Mock all commands used by verification functions, not just the recovery command
- Review `lib/recovery.sh` to see what commands verification functions use
- Test with timeout to catch missing mocks early

**Related Patterns**:
- See `tests/test_recovery_cascading_failures.sh` for examples of complete mocking
- See `tests/test_recovery_cooldown_rate_limit_interaction.sh` for realistic ipsec status output format
- See `lib/recovery.sh:verify_ipsec_connections_active()` for verification requirements

### 19. Schema Validation Order Affects Test Expectations

**Pattern**: When adding validation layers, update tests to reflect the new validation order.

**When to use**: When adding new validation layers (e.g., schema validation) that run before existing validation or parsing logic.

**Key Insight**: Validation happens in a specific order. Schema validation runs during `load_config()` before `parse_location_config()` runs. Tests that expect invalid variables to be skipped by downstream parsing will fail because schema validation rejects them first.

**Example**:
```bash
# ✅ GOOD: Test reflects schema validation happens first
@test "invalid variables rejected by schema" {
    # Schema validation rejects unknown variables during load_config
    local config_file="${TEST_DIR}/vpn-monitor.conf"
    cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="203.0.113.1"
INVALID_VAR="value"
EOF

    run load_config "$config_file"
    assert_failure
    assert_output --partial "Unknown configuration variable"
}

# ❌ BAD: Test expects downstream parsing to skip invalid vars
@test "invalid variables skipped by parse_location_config" {
    # This test will fail because load_config fails first
    load_config "$config_file"  # Fails here, never reaches parse_location_config
    parse_location_config  # Never reached
}
```

**Systematic Application**:
- When adding validation layers, identify all affected tests
- Update test expectations to match validation order
- Document validation order in test comments
- Consider testing validation at each layer separately

**Related Patterns**:
- See `lib/config.sh:safe_parse_config_file()` for schema validation
- See `lib/config.sh:parse_location_config()` for location parsing
- See `tests/test_config_location.sh` for updated test patterns

### 20. Test Helper Functions Can Create Duplicate Configurations

**Pattern**: When test helpers add default configurations, either use the helper and accept the defaults, OR use lower-level helpers directly to avoid defaults.

**When to use**: When test helper functions automatically add default configurations (e.g., default location names) and your test needs custom configurations.

**Key Insight**: High-level helper functions (like `setup_location_test_vpn_monitor()`) add default configurations. If your test then adds the same configurations again, you'll get duplicate configuration errors. Use lower-level helpers when you need custom configurations.

**Example**:
```bash
# ✅ GOOD: Use lower-level helper to avoid defaults
setup_test_environment "${TEST_DIR}"
local config_file="${TEST_DIR}/vpn-monitor.conf"
setup_test_location_config "$config_file" \
    'LOCATION_CUSTOM_EXTERNAL="..."' \
    'LOCATION_CUSTOM_INTERNAL="..."'
TEST_CONFIG_FILE="$config_file"
TEST_SCRIPT=$(create_test_vpn_monitor_script ...)
export TEST_CONFIG_FILE TEST_SCRIPT

# ✅ GOOD: Use helper and accept defaults
setup_location_test_vpn_monitor "${TEST_DIR}"
# Uses default NYC and LA locations - don't add them again

# ❌ BAD: Use helper then add same locations again
setup_location_test_vpn_monitor "${TEST_DIR}" \
    'LOCATION_NYC_EXTERNAL="..."'  # Duplicate! Helper already added this
```

**Systematic Application**:
- Document what defaults helper functions add
- When tests need custom configs, use lower-level helpers
- When tests can use defaults, use higher-level helpers
- Consider helper functions that don't add defaults for custom scenarios

**Related Patterns**:
- See `tests/test_helper.bash:setup_location_test_vpn_monitor()` for helper with defaults
- See `tests/test_helper.bash:setup_test_location_config()` for lower-level helper
- See `tests/test_integration_location.sh` for examples of avoiding duplicates

### 21. Test Setup: Heredoc Variable Expansion

**Pattern**: When creating test config files with heredocs, use `<<EOF` (without quotes) if you need variable expansion, or `<<'EOF'` (with quotes) if you want literal strings.

**When to use**: When creating test configuration files or other test files using heredoc syntax.

**Key Insight**: Heredoc syntax with quotes (`<<'EOF'`) prevents variable expansion, while without quotes (`<<EOF`) allows expansion. This is a common source of test failures when variables like `${TEST_DIR}` don't expand.

**Important Security Note**: The config parser rejects variable references like `${VAR}` or `$(command)` as dangerous content (security feature to prevent code injection). When writing test config files, you **must** expand variables before writing them to the config file. Use `<<EOF` (without quotes) to allow variable expansion.

**Related**: See Pattern 5 for similar heredoc variable expansion patterns when creating mock scripts (where script arguments like `\$1` must be escaped).

**Example**:
```bash
# ✅ GOOD: Variable expansion needed (config parser rejects ${TEST_PEER_IP} as literal)
local config_file="${TEST_DIR}/vpn-monitor.conf"
cat >"$config_file" <<EOF
LOCATION_TEST_EXTERNAL="${TEST_PEER_IP}"
LOCATION_TEST_INTERNAL="${TEST_PEER_IP}"
EOF
# ${TEST_PEER_IP} expands to "192.168.1.1" before being written to config file

# ❌ BAD: Literal variable reference (config parser rejects as dangerous content)
cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="${TEST_PEER_IP}"
LOCATION_TEST_INTERNAL="${TEST_PEER_IP}"
EOF
# Config parser rejects this because it contains ${TEST_PEER_IP} (contains $ and ())

# ✅ GOOD: Literal string needed (no variable references)
cat >"$config_file" <<'EOF'
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="192.168.1.1"
EOF
# No variable references, so quoted heredoc is fine

# ❌ BAD: Wrong choice for the use case
cat >"$config_file" <<'EOF'
LOGS_DIR="${TEST_DIR}/readonly-parent/readonly-logs"  # Won't expand!
EOF
# Test fails because script tries to create directory with literal "${TEST_DIR}" in path
```

**Systematic Application**:
- Before writing test config files, determine if variables need expansion
- Use `<<EOF` when variables should be expanded (most common case for test IPs)
- **Always expand variables before writing to config files** - the config parser rejects variable references as dangerous content
- Use `<<'EOF'` only when you truly want literal strings with no variable expansion (rare)
- When debugging test failures, check if heredoc expansion is the issue
- Use `cat "$config_file"` in test debugging to verify expansion

**Related Patterns**:
- See `tests/test_main.sh:923` for correct usage
- Always verify test config files contain expected values after creation

### 22. Byte Counter Increment Pattern for XFRM Recovery Verification

**Pattern**: Mock `ip` command to return increasing byte counter values when testing xfrm recovery verification

**When to use**: When testing xfrm-based recovery that includes byte counter verification. The `verify_byte_counters_increment()` function requires byte counters to increase from an initial baseline value to verify that traffic is flowing through the tunnel after SA re-establishment.

**Key Insight**:
- `verify_byte_counters_increment()` captures an initial byte counter value when SA re-establishment is detected
- It then checks that byte counters have increased from this initial value
- Static byte counter values will cause verification to fail
- Byte counters must increase over time to simulate traffic flow

**Example - Basic Byte Counter Increment**:
```bash
@test "xfrm recovery - byte counter verification succeeds" {
    setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}" \
        'ENABLE_XFRM_RECOVERY=1' 'TIER2_THRESHOLD=3'

    # Track verification attempts for byte counter increment
    local verify_attempt_file="${TEST_DIR}/verify_attempts"
    echo "0" >"$verify_attempt_file"

    # Mock ip command - returns increasing byte counter values
    local mock_ip="${TEST_DIR}/ip"
    cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # Handle "ip -s xfrm state" (with statistics flag)
    verify_attempts=\$(cat "$verify_attempt_file" 2>/dev/null || echo "0")
    verify_attempts=\$((verify_attempts + 1))
    echo "\$verify_attempts" > "$verify_attempt_file"

    # Return increasing byte counter values to simulate traffic flow
    # Initial value: 1000, then increase by 1000 each call
    byte_count=\$((1000 + (\$verify_attempts - 1) * 1000))
    echo "src 10.0.0.1 dst 192.168.1.1"
    echo "  proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "  lifetime current:"
    echo "    \${byte_count}(bytes), 10(packets)"
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Handle "ip xfrm state" (without statistics flag)
    verify_attempts=\$(cat "$verify_attempt_file" 2>/dev/null || echo "0")
    verify_attempts=\$((verify_attempts + 1))
    echo "\$verify_attempts" > "$verify_attempt_file"

    # Return increasing byte counter values
    byte_count=\$((1000 + (\$verify_attempts - 1) * 1000))
    echo "src 10.0.0.1 dst 192.168.1.1"
    echo "  proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "  lifetime current:"
    echo "    \${byte_count}(bytes), 10(packets)"
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
    chmod +x "$mock_ip"
    add_mock_to_path

    # Mock check_ipsec_phase2 to simulate SA lifecycle
    local phase2_call_file="${TEST_DIR}/phase2_calls"
    echo "0" >"$phase2_call_file"

    local mock_check_ipsec_phase2="${TEST_DIR}/check_ipsec_phase2"
    cat >"$mock_check_ipsec_phase2" <<EOF
#!/bin/bash
phase2_calls=\$(cat "$phase2_call_file" 2>/dev/null || echo "0")
phase2_calls=\$((phase2_calls + 1))
echo "\$phase2_calls" > "$phase2_call_file"

# Initially: SAs exist (first call) - return success
# After deletion check: SAs deleted (2nd call) - return failure
# During verification: SAs re-established (3rd+ call) - return success
if [[ \$phase2_calls -eq 1 ]]; then
    exit 0  # Initial check: SAs exist
elif [[ \$phase2_calls -eq 2 ]]; then
    exit 1  # After deletion: SAs don't exist yet
else
    exit 0  # After re-establishment: SAs exist again
fi
EOF
    chmod +x "$mock_check_ipsec_phase2"
    add_mock_to_path

    source_recovery_module
    check_ipsec_phase2() {
        "$mock_check_ipsec_phase2" "$@"
    }

    # Set up failure count at Tier 2 threshold
    local location_name="TEST"
    local peer_ip="192.168.1.1"
    set_peer_state "$location_name" "$peer_ip" "failure_count" "3"

    # Call surgical_cleanup - should succeed with byte counter verification
    run surgical_cleanup "$peer_ip" "$location_name"
    assert_success

    remove_mock_from_path
}
```

**Important Notes**:
- **Byte counters must increase**: The mock must return different byte counter values on each call, not static values
- **Handle both `ip -s xfrm state` and `ip xfrm state`**: See Pattern 5 for details on handling both command formats (required for all `ip xfrm state` mocks)
- **Coordinate with `check_ipsec_phase2` mock**: Use separate counter files for `ip` calls vs `check_ipsec_phase2` calls to properly simulate SA lifecycle
- **Initial value matters**: The first byte counter value becomes the baseline; subsequent values must be higher
- **Increment amount**: Use reasonable increments (e.g., 1000 bytes per call) to simulate realistic traffic flow
- **Never use `local` keyword**: At top level of mock scripts (see Pattern 5)

**Common Mistakes**:
```bash
# ❌ WRONG - Static byte counter (verification will fail)
cat >"$mock_ip" <<'EOF'
#!/bin/bash
echo "    lifetime current: 1000(bytes), 10(packets)"
EOF

# ✅ CORRECT - Increasing byte counter
cat >"$mock_ip" <<EOF
#!/bin/bash
verify_attempts=\$(cat "$verify_attempt_file" 2>/dev/null || echo "0")
verify_attempts=\$((verify_attempts + 1))
echo "\$verify_attempts" > "$verify_attempt_file"
byte_count=\$((1000 + (\$verify_attempts - 1) * 1000))
echo "    lifetime current: \${byte_count}(bytes), 10(packets)"
EOF
```

**Standard**:
- Use file-based counters to track `ip` command calls
- Return increasing byte counter values (initial + (attempt - 1) * increment)
- Handle both `ip -s xfrm state` and `ip xfrm state` command formats (see Pattern 5 for details)
- Coordinate `check_ipsec_phase2` mock separately using its own counter file
- Initialize counter files before creating mocks: `echo "0" >"$counter_file"`
- Use reasonable increment values (1000-10000 bytes per call) to simulate realistic traffic

### 23. Mock Counter Design: Account for All Phases When Testing Specific Behavior

**Pattern**: When designing mocks with counters that span multiple phases, account for all calls that occur before the phase you're testing.

**When to use**: When creating stateful mocks with counters that need to change behavior at specific thresholds, especially when testing behavior in later phases of execution (e.g., verification loops after deletion phases).

**Key Insight**: Mock counters increment across all phases of execution, not just the phase being tested. If you're testing behavior in a later phase (e.g., exponential backoff in verification loop), the counter may already be high from earlier phases (e.g., deletion phase). Set thresholds that account for all phases.

**Example**:
```bash
@test "exponential backoff in verification loop" {
    # Mock counter increments during:
    # 1. Initial SA fetch (before deletion) - ~2 calls
    # 2. Deletion verification calls - ~2 calls
    # 3. Post-deletion SA check - ~2 calls
    # 4. Verification loop calls - 2 calls per iteration (ip -s xfrm state + ip xfrm state fallback)

    # ✅ GOOD: Account for all phases when setting mock thresholds
    # Deletion phase: ~6 calls total
    # Verification phase: 2 calls per iteration
    # Need 2+ iterations to test exponential backoff: 2 iterations × 2 calls = 4 calls
    # Total: 6 + 4 = 10, threshold > 10 (use 12 for safety margin)
    local verify_attempt_file="${TEST_DIR}/verify_attempts"
    echo "0" >"$verify_attempt_file"

    local mock_ip="${TEST_DIR}/ip"
    cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    verify_attempts=\$(cat "$verify_attempt_file" 2>/dev/null || echo "0")
    verify_attempts=\$((verify_attempts + 1))
    echo "\$verify_attempts" > "$verify_attempt_file"

    # Return SA re-established after threshold accounts for all phases
    if [[ \$verify_attempts -le 12 ]]; then
        :  # Return empty (SA deleted, verification loop continues)
    else
        echo "src 10.0.0.1 dst 192.168.1.1"
        echo "  proto esp spi 0x12345678 reqid 1 mode tunnel"
        exit 0  # SA re-established
    fi
fi
exec /usr/bin/ip "\$@"
EOF
    chmod +x "$mock_ip"
    add_mock_to_path

    # Test should show multiple sleep calls (exponential backoff)
    run bash "$TEST_SCRIPT" --fake
    assert_success

    remove_mock_from_path
}

# ❌ BAD: Threshold too low, doesn't account for earlier phases
# If threshold is 7, but deletion phase already used 6-8 calls,
# verification loop exits immediately without testing exponential backoff
elif [[ \$verify_attempts -le 7 ]]; then
    :  # Returns SA too early, before verification loop can test exponential backoff
fi
```

**Key Considerations**:
- **Trace all code paths**: Count calls in all phases, not just the one being tested
- **Multiple calls per iteration**: Some functions make multiple mock calls per iteration (e.g., `check_ipsec_phase2` calls both `ip -s xfrm state` and `ip xfrm state`)
- **Safety margin**: Add a safety margin to account for implementation details and edge cases
- **Document calculation**: Add comments explaining how the threshold was calculated

**Systematic Application**:
- When creating mocks with counters, trace through all code paths that call the mock
- Document expected call counts for each phase
- Set thresholds that account for all phases, not just the one being tested
- Add comments explaining the threshold calculation
- Consider resetting counters between phases if testing specific phase behavior

**Related Patterns**:
- See Pattern 16 (Stateful Mocks for Testing State Transitions) for call counter patterns
- See Pattern 22 (Byte Counter Increment Pattern) for incrementing counter patterns
- Each `check_ipsec_phase2` call results in 2 mock calls (`ip -s xfrm state` + `ip xfrm state` fallback)

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


### `save_permissions_for_restore(path, [default_perms])` / `restore_permissions_after_test(path, original_perms)`

Helper functions for temporarily making files or directories unwritable during tests.

**Usage**: Use when testing error handling for permission-related failures (e.g., atomic write failures, state update failures).

**Pattern with trap (recommended)**:
```bash
# Save original permissions
local original_perms
original_perms=$(stat -c %a "$file_or_dir")

# Make unwritable for testing
chmod 444 "$file_or_dir"  # or 000, 555, etc.
# Use trap to ensure cleanup even on errors
trap "chmod $original_perms \"\$file_or_dir\" 2>/dev/null || true" EXIT

# Run test that should handle permission failure gracefully
run some_function_that_writes_to_file

# Restore permissions for cleanup
chmod 644 "$file_or_dir" 2>/dev/null || true
# Clear trap after successful restore
trap - EXIT
```

**Pattern with helper functions (alternative)**:
```bash
# Save original permissions
local original_perms
original_perms=$(save_permissions_for_restore "$file_or_dir")

# Make unwritable (may fail on some systems)
if chmod 000 "$file_or_dir" 2>/dev/null; then
    # Use trap to ensure cleanup even on errors
    trap "restore_permissions_after_test \"\$file_or_dir\" \"\$original_perms\"" EXIT

    # Run test that should handle permission failure gracefully
    run some_function_that_writes_to_file

    # Restore permissions
    restore_permissions_after_test "$file_or_dir" "$original_perms"
    # Clear trap after successful restore
    trap - EXIT
else
    skip "Cannot make file/directory unwritable on this system"
fi
```

**Important Notes**:
- **Always use trap**: Use `trap` with EXIT to ensure permissions are restored even if the test fails or errors occur before manual restore.
- **Variable expansion in trap**: Use escaped variables (`\"\$variable\"`) in trap commands so they expand when the trap fires, not when it's set. The permission value should be expanded when trap is set (no escape).
- **Path must exist**: The file or directory must exist before calling `save_permissions_for_restore()` or `stat -c %a`. The helper function auto-detects whether the path is a file (defaults to 644) or directory (defaults to 755) if `stat` fails, but this detection only works if the path exists.
- **Auto-detection**: If no default is provided, the function automatically detects file vs directory and uses appropriate defaults (644 for files, 755 for directories).
- **Explicit defaults**: You can provide an explicit default if needed: `save_permissions_for_restore "$path" "755"`.
- **Always restore**: Always restore permissions and clear the trap after successful test completion.
- **Error suppression**: Both patterns suppress errors (using `|| true`) to match the existing test pattern where permission restoration should not fail tests.

**When to use**: Tests that verify graceful handling of:
- Atomic write failures (state file updates)
- Permission errors during state operations
- Disk full scenarios (simulated by making directories read-only)
- File deletion failures due to permissions

**Example**:
```bash
@test "state atomic write failures: increment_failure fails due to atomic write failure" {
    setup_test_environment "${TEST_DIR}"
    local state_file="${TEST_DIR}/state/failure_count"
    mkdir -p "$(dirname "$state_file")"
    echo "5" >"$state_file"

    # Save permissions
    local original_perms
    original_perms=$(save_permissions_for_restore "$(dirname "$state_file")")

    # Make directory unwritable
    if chmod 555 "$(dirname "$state_file")" 2>/dev/null; then
        run increment_failure "" "$peer_ip"
        # Function should handle failure gracefully

        # Restore permissions
        restore_permissions_after_test "$(dirname "$state_file")" "$original_perms"
    else
        skip "Cannot make directory unwritable on this system"
    fi
}
```

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
14. **Use location name helpers** when setting up failure counters - use `get_failure_counter_path_for_location_var()` instead of manually extracting location names from config variables

### 24. Location Name Extraction from Config Variables

**Pattern**: Use helper functions to extract location names from config variables instead of hardcoding them.

**When to use**: When setting up failure counters or other state files that require location names extracted from `LOCATION_*_EXTERNAL` or `LOCATION_*_INTERNAL` config variables.

**Key Insight**: Location names are embedded in config variable names (e.g., `LOCATION_TEST_EXTERNAL` contains location name "TEST"). Instead of manually extracting and hardcoding the location name, use helper functions that extract it dynamically.

**Example**:
```bash
# ✅ GOOD: Use helper function to extract location name
local failure_counter
failure_counter=$(get_failure_counter_path_for_location_var "LOCATION_TEST_EXTERNAL" "${TEST_PEER_IP}")
echo "5" >"$failure_counter"

# ❌ BAD: Manually extract and hardcode location name
source_function "get_peer_state_file_path"
# Location name is "TEST" (extracted from LOCATION_TEST_EXTERNAL)
failure_counter=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
echo "5" >"$failure_counter"
```

**Available Helpers**:
- `get_location_name_from_config_var()` - Extracts location name from config variable name
- `get_failure_counter_path_for_location_var()` - Gets failure counter path for a location config variable (handles extraction and sourcing automatically)

**Standard**:
- Use `get_failure_counter_path_for_location_var()` when setting up failure counters
- Use `get_location_name_from_config_var()` when you need the location name for other purposes
- Helper functions handle sourcing of required functions automatically
- Helper functions have fallback regex extraction if `extract_location_name()` from lib/config.sh is not available

## Migration Notes

- Old pattern `NO_ESCALATE=1; export NO_ESCALATE` → Use `enable_fake_mode()`
- Old pattern manual CONFIG_FILE setup → Use `setup_location_config_and_load()`
- Old pattern manual config creation → Use `setup_test_location_config()` or `setup_test_config()`
- Old pattern manual mock setup → Use `setup_mock_vpn_environment()` or fixtures
- Old pattern missing cleanup → Always use `remove_mock_from_path()`
- Old pattern manual location name extraction → Use `get_failure_counter_path_for_location_var()` or `get_location_name_from_config_var()`