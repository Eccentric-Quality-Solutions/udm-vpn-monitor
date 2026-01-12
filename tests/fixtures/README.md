# Test Fixtures

Reusable test fixtures for common VPN monitoring scenarios. These fixtures combine multiple setup steps into single function calls, reducing duplication and ensuring consistent test environments.

## Quick Reference

### Available Fixtures

- `vpn_active.bash` - VPN is active and healthy (`setup_vpn_active_fixture`)
- `vpn_down.bash` - VPN is down, no SA found (`setup_vpn_down_fixture`)
- `vpn_failing.bash` - VPN has recorded failures (`setup_vpn_failing_fixture`)
- `vpn_cooldown.bash` - VPN is in cooldown period (`setup_vpn_cooldown_fixture`)
- `vpn_rekey.bash` - VPN has undergone a rekey (`setup_vpn_rekey_fixture`)
- `vpn_flapping.bash` - VPN can transition between up/down states (`setup_vpn_flapping_fixture`)
- `vpn_multiple_peers.bash` - Multiple VPN peers scenario (`setup_vpn_multiple_peers_fixture`)
- `vpn_mixed_peers.bash` - Multiple peers with mixed states (`setup_vpn_mixed_peers_fixture`)
- `vpn_recovery_disabled.bash` - Recovery actions disabled (`setup_vpn_recovery_disabled_fixture`)
- `vpn_at_tier.bash` - VPN at specific tier threshold (`setup_vpn_at_tier_fixture`)
- `vpn_idle.bash` - VPN idle tunnel scenario (`setup_vpn_idle_fixture`)
- `vpn_network_partition.bash` - Network partition scenario (`setup_vpn_network_partition_fixture`)
- `vpn_rate_limited.bash` - Rate limiting scenario (`setup_vpn_rate_limited_fixture`)
- `vpn_xfrm_recovery.bash` - XFRM recovery scenario (`setup_vpn_xfrm_recovery_fixture`)
- `vpn_bytes_zero.bash` - VPN SA exists but bytes=0 (suspect condition) (`setup_vpn_bytes_zero_fixture`)
- `vpn_recovery_test.bash` - Recovery test setup with pass-through mocks (`setup_vpn_recovery_test_fixture`)

## Basic Usage

```bash
#!/usr/bin/env bats

load test_helper
load fixtures/vpn_active

@test "VPN active test" {
    setup_vpn_active_fixture "192.168.1.1"
    run bash "$TEST_SCRIPT" --fake
    assert_success
    remove_mock_from_path
}
```

## Loading Multiple Fixtures

Tests can load multiple fixtures at once:

```bash
load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing

@test "test with multiple fixture options" {
    # Can use any of the loaded fixtures
    setup_vpn_active_fixture "192.168.1.1"
    # ... or switch to another fixture
    setup_vpn_down_fixture "192.168.1.1"
    remove_mock_from_path
}
```

## Important Notes

- **Fixtures automatically add mocks to PATH** - You don't need to call `add_mock_to_path()` after using fixtures
- Fixtures call `setup_mock_vpn_environment()` which internally calls `add_mock_to_path()`
- If you add additional mocks after a fixture, you may need to call `add_mock_to_path()` again (though it's idempotent)
- Always call `remove_mock_from_path()` for cleanup, even when using fixtures

## Fixture Details

Each fixture provides a setup function that:
- Configures the test environment (config files, state files, mocks)
- Sets up VPN monitoring state appropriate for the scenario
- Creates mock commands for system interactions
- Automatically adds mocks to PATH (no need to call `add_mock_to_path()`)

### Common Arguments

Most fixtures accept:
- **Peer IP address** (first argument, often defaults to `${TEST_PEER_IP}`)
- **Additional config variables** (as `KEY="VALUE"` pairs)

Some fixtures have additional arguments specific to their scenario (e.g., tier number, partition type, byte counters).

### Cleanup

Always call `remove_mock_from_path()` in your test teardown or at the end of each test to clean up mocks added by fixtures.

## Related Documentation

For comprehensive fixture documentation, see:

- **[Test Patterns - Test Fixtures](../../docs/testing/TEST_PATTERNS.md#4-test-fixtures)** - Complete fixture reference with all arguments, examples, and usage patterns
- **[BATS Guide - Test Fixtures](../../docs/testing/BATS_GUIDE.md#7-test-fixtures---reusable-test-scenarios)** - BATS framework usage with fixtures and advanced patterns
- **[tests/README.md](../README.md)** - Quick start guide for running tests and test suite overview

## Benefits

- **Reduced duplication**: Common setup patterns are centralized
- **Consistent setup**: All tests using the same fixture get identical environments
- **Easier maintenance**: Update fixture once, all tests benefit
- **Clear intent**: Fixture names clearly indicate test scenario
