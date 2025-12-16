# UDM VPN Monitor Test Suite

This directory contains comprehensive tests for the UDM VPN Monitor scripts using [bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

## Test Structure

- `test_helper.bash` - Common test utilities and helper functions
- `test_install.sh` - Tests for `install.sh` script
- `test_uninstall.sh` - Tests for `uninstall.sh` script
- `test_vpn_monitor.sh` - Tests for `vpn-monitor.sh` script
- `run_tests.sh` - Test runner script

## Prerequisites

### Required

- **bats-core** (version 1.x or higher)
  - Installation: See [bats-core documentation](https://github.com/bats-core/bats-core#installation)
  - macOS: `brew install bats-core`
  - Linux: Install from source or use package manager

### Optional (Recommended)

- **bats-support** - Additional assertion helpers
- **bats-assert** - More assertion functions
- **bats-file** - File system assertions

These can be installed using:
```bash
./install_bats_helpers.sh
```

## Running Tests

### Run All Tests

```bash
./tests/run_tests.sh
```

Or directly with bats:
```bash
bats tests/test_*.sh
```

### Run Specific Test File

```bash
bats tests/test_install.sh
bats tests/test_uninstall.sh
bats tests/test_vpn_monitor.sh
```

### Run Specific Test

```bash
bats tests/test_install.sh -t "install.sh creates installation directory"
```

### Verbose Output

```bash
bats --verbose tests/test_*.sh
```

### Tap Format (for CI)

```bash
bats --tap tests/test_*.sh
```

## Test Coverage

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

## Writing New Tests

### Test File Structure

```bash
#!/usr/bin/env bats
#
# Description of what this test file tests

load test_helper

@test "test name" {
    # Setup
    local test_var="value"
    
    # Execute
    run bash "$SCRIPT_PATH" --flag
    
    # Assert
    assert_success
    assert_output --partial "expected output"
}
```

### Helper Functions

The `test_helper.bash` file provides many useful functions:

- `create_mock_config()` - Create a test config file
- `create_mock_vpn_monitor_script()` - Create a mock script
- `mock_root()` / `mock_non_root()` - Mock user permissions
- `mock_udm_system()` / `mock_non_udm_system()` - Mock system environment
- `assert_cron_entry_exists()` / `assert_cron_entry_not_exists()` - Check cron entries
- `assert_log_contains()` / `assert_log_not_contains()` - Check log files
- `mock_ip_xfrm_state()` - Mock `ip xfrm state` output
- `mock_ping()` - Mock ping command
- `mock_ipsec()` - Mock ipsec command

### Best Practices

1. **Use setup/teardown**: Each test gets a clean environment
2. **Isolate tests**: Tests should not depend on each other
3. **Mock external commands**: Use mock functions for system commands
4. **Clean up**: Use teardown to remove temporary files
5. **Test both success and failure cases**: Cover error paths
6. **Use descriptive test names**: Make it clear what is being tested

## Continuous Integration

Tests can be run in CI environments. The test suite:

- Works in non-interactive mode
- Cleans up after itself
- Uses temporary directories
- Doesn't require root (for most tests)
- Can run in parallel (with proper isolation)

### Example CI Configuration

```yaml
# GitHub Actions example
- name: Install bats
  run: |
    git clone https://github.com/bats-core/bats-core.git
    cd bats-core
    sudo ./install.sh /usr/local

- name: Run tests
  run: ./tests/run_tests.sh
```

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

## Contributing

When adding new features:

1. Add tests for new functionality
2. Ensure all tests pass
3. Update this README if adding new test utilities
4. Follow existing test patterns and conventions

## See Also

- [bats-core documentation](https://github.com/bats-core/bats-core)
- [bats-assert documentation](https://github.com/bats-core/bats-assert)
- [bats-file documentation](https://github.com/bats-core/bats-file)

