# Test Fixtures

Reusable test fixtures for common VPN monitoring scenarios. These fixtures combine multiple setup steps into single function calls, reducing duplication and ensuring consistent test environments.

## Available Fixtures

### `vpn_active.bash` - VPN Active and Healthy

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
}
```

### `vpn_down.bash` - VPN Down (No SA Found)

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
}
```

### `vpn_failing.bash` - VPN with Recorded Failures

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
}
```

### `vpn_cooldown.bash` - VPN in Cooldown Period

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
}
```

### `vpn_rekey.bash` - VPN Rekey Scenario

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
}
```

### `vpn_multiple_peers.bash` - VPN Multiple Peers Scenario

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
}
```

### `vpn_recovery_disabled.bash` - VPN with Recovery Disabled

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
}
```

## Usage Pattern

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
}
```

## Benefits

- **Reduced duplication**: Common setup patterns are centralized
- **Consistent setup**: All tests using the same fixture get identical environments
- **Easier maintenance**: Update fixture once, all tests benefit
- **Clear intent**: Fixture names clearly indicate test scenario

## Migration Guide

To migrate existing tests to use fixtures:

**Before**:
```bash
@test "VPN active test" {
    setup_test_vpn_monitor "192.168.1.1" "${TEST_DIR}"
    setup_state_files "192.168.1.1" 0 1000
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
}
```

