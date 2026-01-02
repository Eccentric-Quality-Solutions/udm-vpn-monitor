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

### `vpn_rate_limited.bash` - VPN Rate Limited Scenario

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
}

@test "rate limit with specific timestamps" {
    local now=$(date +%s)
    setup_vpn_rate_limited_fixture "192.168.1.1" 3 \
        $((now - 100)) \
        $((now - 200)) \
        $((now - 300))
    run bash "$TEST_SCRIPT" --fake
    assert_file_contains "$LOG_FILE" "Rate limit exceeded"
}
```

### `vpn_network_partition.bash` - VPN Network Partition Scenario

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
}

@test "network partition - DNS failure only" {
    setup_vpn_network_partition_fixture "192.168.1.1" "dns_failure"
    # Only DNS resolution fails
    run bash "$TEST_SCRIPT" --fake
    # Should detect partition
}

@test "network partition - custom interfaces" {
    setup_vpn_network_partition_fixture "192.168.1.1" "interfaces_down" "br0,eth0"
    # Interfaces are down with custom interface list
    run bash "$TEST_SCRIPT" --fake
    # Should detect partition
}
```

### `vpn_xfrm_recovery.bash` - VPN XFRM Recovery Scenario

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
}

@test "xfrm recovery - partial failure" {
    setup_vpn_xfrm_recovery_fixture "192.168.1.1" 3 "partial_failure"
    # 3 SAs, some deletions succeed, others fail
    run bash "$TEST_SCRIPT" --fake
    # Should handle partial failures gracefully
}

@test "xfrm recovery - complete failure" {
    setup_vpn_xfrm_recovery_fixture "192.168.1.1" 2 "complete_failure"
    # 2 SAs, all deletions fail
    run bash "$TEST_SCRIPT" --fake
    # Should fall back to ipsec reload/restart
}

@test "xfrm recovery - custom config" {
    setup_vpn_xfrm_recovery_fixture "192.168.1.1" 2 "success" \
        'TIER2_THRESHOLD=5' \
        'RECOVERY_VERIFY_TIMEOUT=10'
    # Custom thresholds and timeout
    run bash "$TEST_SCRIPT" --fake
    # Should use custom config values
}
```

### `vpn_at_tier.bash` - VPN at Specific Tier Threshold

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
}

@test "tier 2: surgical cleanup" {
    setup_vpn_at_tier_fixture 2 "192.168.1.1" 'ENABLE_XFRM_RECOVERY=0'
    # VPN at Tier 2 threshold (failure_count=3, TIER2_THRESHOLD=3)
    run bash "$TEST_SCRIPT" --fake
    # Should trigger Tier 2 action (ipsec reload)
}

@test "tier 3: restart" {
    setup_vpn_at_tier_fixture 3 "192.168.1.1" 'MAX_RESTARTS_PER_HOUR=10'
    # VPN at Tier 3 threshold (failure_count=5, TIER3_THRESHOLD=5)
    run bash "$TEST_SCRIPT" --fake
    # Should trigger Tier 3 action (ipsec restart)
}
```

### `vpn_idle.bash` - VPN Idle Tunnel Scenario

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
}

@test "idle tunnel - custom bytes and IP" {
    setup_vpn_idle_fixture "192.168.1.1" 5000 "10.0.0.1"
    # Idle tunnel: bytes static at 5000, ping to 10.0.0.1 succeeds
    run bash "$TEST_SCRIPT" --fake
    # Should detect idle tunnel
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
}
```

