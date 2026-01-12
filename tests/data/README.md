# Test Data Directory

This directory contains extracted test data (mock outputs, expected values, configuration templates) that was previously embedded in test files. This centralization improves maintainability and reduces duplication.

## Directory Structure

- `mock_outputs/` - Mock command outputs (ipsec status, xfrm state, etc.)
- `configs/` - Configuration file templates
- `expected_values/` - Expected values for assertions

## Usage

Load the test data helper module in your test file:

```bash
load test_helper
load helpers/test_data
```

Then use the helper functions to load test data:

```bash
# Load xfrm state output
load_xfrm_state_output "healthy" "${TEST_PEER_IP}" "0x12345678" 1000 10

# Load ipsec status output
load_ipsec_status_output "libreswan" "${TEST_PEER_IP}" "test-conn"

# Load config template
load_config_template "minimal" "${TEST_PEER_IP}"
```

## Data Generators

The `helpers/test_data.bash` module provides generators for common patterns:

- `generate_xfrm_state_output()` - Generate xfrm state output with configurable parameters
- `generate_ipsec_status_output()` - Generate ipsec status output in different formats
- `generate_config_template()` - Generate configuration file templates

## Adding New Test Data

1. Create data files in the appropriate subdirectory
2. Use structured bash format (variables and functions)
3. Document parameters and usage
4. Add helper functions to `helpers/test_data.bash` if needed
