# Mock Cleanup Audit Documentation

## Overview

The Mock Cleanup Audit ensures that all test files properly clean up mock commands added to PATH. This prevents test pollution and ensures test isolation.

## Problem

Tests use `add_mock_to_path()` to prepend `TEST_DIR` to PATH so mock commands are found before real system commands. If tests don't call `remove_mock_from_path()` to clean up, PATH modifications can leak between tests, causing:
- Flaky tests
- False positives/negatives
- Test pollution
- Unreliable test results

## Solution

The `scripts/audit_mock_cleanup.sh` script systematically audits all test files to ensure:
1. Every `add_mock_to_path()` call has a corresponding `remove_mock_from_path()` call
2. The number of add calls matches the number of remove calls in each test

## Usage

### Audit All Test Files

```bash
./scripts/audit_mock_cleanup.sh
```

### Audit Specific Test Files

```bash
./scripts/audit_mock_cleanup.sh tests/test_detection.sh tests/test_recovery.sh
```

### Output

The script outputs:
- ✓ for tests with proper cleanup (matching add/remove calls)
- ✗ for tests with missing cleanup (mismatched add/remove calls)
- Summary statistics at the end

Example output:
```
✓ Test 'VPN active - no action taken' (line 21): 1 add, 1 remove
✗ Test 'ping command hangs' (line 396): 2 add, 1 remove
  Add calls at lines: 415,417
  Remove calls at lines: 427
```

## Implementation Details

### How It Works

1. Parses each test file using Python for reliable regex matching
2. Identifies `@test` function boundaries
3. Counts `add_mock_to_path()` calls (excluding comments)
4. Counts `remove_mock_from_path()` calls (excluding comments)
5. Reports mismatches with line numbers

### Key Insights

- `add_mock_to_path()` is **idempotent** - calling it multiple times is harmless but unnecessary
- All mocks in a test are typically in the same `TEST_DIR`, so only one `add_mock_to_path()` call is needed
- Common mistake: Duplicate `add_mock_to_path()` calls after creating multiple mocks or after calling helper functions that already add mocks

### Fixing Issues

When the audit finds issues:

1. **Duplicate `add_mock_to_path()` calls**: Remove the duplicate(s) since the function is idempotent
2. **Missing `remove_mock_from_path()` calls**: Add cleanup calls to match the number of add calls
3. **Multiple mocks in same test**: Only one `add_mock_to_path()` call is needed (all mocks are in `TEST_DIR`)

## Historical Context

This audit was completed in response to TEST_SUITE_REVIEW.md Section 8, Priority P0 item #1. The audit found and fixed ~37 test cases across 8 test files with missing cleanup.

## Best Practices

1. **Always pair** `add_mock_to_path()` with `remove_mock_from_path()`
2. **Only call once** per test (even if creating multiple mocks)
3. **Use fixtures** when possible - they handle mock setup/cleanup automatically
4. **Run the audit** before committing test changes
5. **Check helper functions** - some already call `add_mock_to_path()` internally

## Related Documentation

- `tests/TEST_PATTERNS.md` - Test patterns and best practices
- `tests/README.md` - Test isolation documentation
- `docs/TEST_SUITE_REVIEW.md` - Original audit requirement
