# Troubleshooting: LOG_FILE Override Test Failure

## Problem Statement

**Test:** `LOG_FILE override in config recalculates LOGS_DIR` (test_config_loading.sh:105)

**Symptom:** Test fails with exit code 1 and no output. The script exits before creating `/tmp/custom-logs` directory.

**Expected Behavior:** 
- Script should load config with `LOG_FILE="/tmp/custom-logs/vpn-monitor.log"`
- `recalculate_log_paths()` should update `LOGS_DIR` to `/tmp/custom-logs`
- `ensure_directory_exists()` should create `/tmp/custom-logs`
- Script should exit with code 0 in `--fake` mode

**Actual Behavior:**
- Script exits with code 1
- No output (stdout or stderr)
- `/tmp/custom-logs` directory is never created

## What We Know

### Configuration Flow
1. Script processes `--fake` flag early (sets `NO_ESCALATE=1`)
2. Initial directories are created (`STATE_DIR`, `LOGS_DIR`)
3. `load_config()` is called
4. `safe_parse_config_file()` parses config file
5. For each config line:
   - `parse_assignment()` extracts variable name and value
   - `get_config_schema()` validates variable is in schema
   - `safe_set_variable()` sets the variable
6. After parsing, `recalculate_log_paths()` should update `LOGS_DIR` based on `LOG_FILE`
7. `ensure_directory_exists()` should create the new `LOGS_DIR`

### Debugging Observations
- Script reaches "Log file initialized" message
- Script calls `load_config()`
- Script calls `safe_parse_config_file()`
- Script parses first line (`EXTERNAL_PEER_IPS="192.168.1.1"`)
- Script calls `get_config_schema EXTERNAL_PEER_IPS`
- **Script stops here** - no further output

### Key Code Locations
- `vpn-monitor.sh`: `--fake` flag processing (moved earlier to set `NO_ESCALATE` before directory creation)
- `lib/config.sh:376`: `if ! get_config_schema "$var_name" >/dev/null 2>&1; then`
- `lib/config.sh:379`: `handle_config_error "Unknown configuration variable '$var_name' (not in schema whitelist)" "$line_num"`
- `lib/config.sh:163`: `handle_config_error()` calls `handle_error_or_exit_fake_mode()`
- `lib/logging.sh:269`: `handle_error_or_exit_fake_mode()` should exit with code 0 in fake mode

## What We've Tried

### 1. Fixed `--fake` Flag Timing
- **Issue:** `--fake` flag was processed after directory creation, causing early exits
- **Fix:** Moved `--fake` flag processing to occur before any directory creation
- **Result:** Script still exits with code 1

### 2. Fixed Test Helper Source Paths
- **Issue:** `create_test_vpn_monitor_script()` was generating incorrect source paths like `//lib/...`
- **Fix:** Added validation for `project_root` and conditional check for `escaped_project_root`
- **Result:** Source paths are now correct, but script still fails

### 3. Verified Schema Loading
- **Test:** Manually sourced `lib/config.sh` and checked `CONFIG_SCHEMA`
- **Result:** Schema loads correctly when sourced directly
- **Observation:** `EXTERNAL_PEER_IPS` is in the schema

### 4. Traced Execution with `bash -x`
- **Observation:** Script reaches `get_config_schema EXTERNAL_PEER_IPS` and then stops
- **Hypothesis:** `get_config_schema` might be failing silently, or the script is exiting due to `set -euo pipefail`

### 5. Added Debug Output
- **Attempt:** Added debug output after `get_config_schema` call
- **Result:** No debug output appears, suggesting script exits before reaching that point

## Current Hypothesis

**Primary Hypothesis:** The script is failing because `get_config_schema` is not finding `EXTERNAL_PEER_IPS` in the schema, causing `handle_config_error` to be called. However, `handle_config_error` should call `handle_error_or_exit_fake_mode`, which should exit with code 0 in fake mode. The fact that it exits with code 1 suggests:

1. **Schema not loaded correctly in test environment** - The `CONFIG_SCHEMA` array might be empty when `get_config_schema` is called
2. **`NO_ESCALATE` not set when error occurs** - Though we moved the flag processing earlier, there might be a timing issue
3. **`set -euo pipefail` causing immediate exit** - If `get_config_schema` fails and the error isn't caught properly, the script exits immediately

**Secondary Hypothesis:** The script might be failing due to `set -euo pipefail` when `get_config_schema` returns 1. The code uses `if ! get_config_schema "$var_name" >/dev/null 2>&1; then`, which should handle the failure, but with `set -e`, any unhandled failure causes immediate exit.

## What We've Learned

1. **`--fake` flag must be processed early** - Before any directory creation or logging initialization
2. **Test helper source path rewriting works** - After fixes, paths are correctly rewritten
3. **Schema loads correctly when sourced directly** - The issue is likely in the test environment
4. **Script execution stops at `get_config_schema` call** - This is the last point we can trace
5. **No error messages appear** - Suggests the error is being suppressed or the script exits before logging

## Solution

**Root Cause:** The `CONFIG_SCHEMA` associative array was not being populated when `config_schema.sh` was sourced. The schema file uses `declare -A CONFIG_SCHEMA=(...)` to declare and populate the array, but this wasn't working when sourced via `safe_source_lib` or even when sourced directly in the context of `config.sh`.

**Fix:** Pre-declare `CONFIG_SCHEMA` as an empty associative array in `lib/config.sh` before sourcing the schema file. This allows the schema file to populate the array correctly.

**Changes Made:**
1. **`lib/config.sh`**: Pre-declare `CONFIG_SCHEMA` as empty array before sourcing schema file
   - Changed from: `if ! safe_source_lib "${LIB_DIR}/config_schema.sh"; then declare -A CONFIG_SCHEMA=(); ...`
   - Changed to: `declare -A CONFIG_SCHEMA=(); if [[ -f "${LIB_DIR}/config_schema.sh" ]] && source "${LIB_DIR}/config_schema.sh" 2>/dev/null; then ...`
2. **`lib/common.sh`**: Improved `safe_source_lib` to check file existence before sourcing

**Key Insight:** Associative arrays in Bash need to be declared before they can be populated. When the schema file tried to declare and populate the array in one step (`declare -A CONFIG_SCHEMA=(...)`), it wasn't working in the context where `config.sh` was sourced. Pre-declaring the array as empty allows the schema file to populate it successfully.

**Test Results:** All tests in `test_config_loading.sh` now pass, including the previously failing "LOG_FILE override in config recalculates LOGS_DIR" test.

## Next Steps to Investigate (COMPLETED)

### High Priority
1. **Check if `CONFIG_SCHEMA` is populated in the actual test script**
   - Add debug output in `config.sh` after schema loading
   - Verify schema is loaded before `get_config_schema` is called

2. **Verify `NO_ESCALATE` is set when `handle_config_error` is called**
   - Add debug output in `handle_config_error` to check `NO_ESCALATE` value
   - Verify `is_fake_mode()` returns true

3. **Check if `set -euo pipefail` is causing immediate exit**
   - Temporarily disable `set -e` to see if script continues
   - Check if error is being caught properly by the `if !` statement

### Medium Priority
4. **Inspect generated test script**
   - Check if source paths are correct
   - Verify `LIB_DIR` is set correctly
   - Check if `config_schema.sh` is being sourced

5. **Test with minimal config**
   - Try with just `LOG_FILE` override (no `EXTERNAL_PEER_IPS`)
   - See if issue is specific to `EXTERNAL_PEER_IPS` validation

### Low Priority
6. **Compare with working tests**
   - Check other tests that successfully override `LOG_FILE`
   - See what's different about those tests

## Code References

- `vpn-monitor.sh`: `--fake` flag processing (lines ~80-100)
- `lib/config.sh:35`: Schema loading with `safe_source_lib`
- `lib/config.sh:376`: `get_config_schema` validation check
- `lib/config.sh:163`: `handle_config_error` function
- `lib/config.sh:497`: `recalculate_log_paths()` call after config parsing
- `lib/config.sh:516`: `ensure_directory_exists()` call after config loading
- `lib/logging.sh:269`: `handle_error_or_exit_fake_mode()` function
- `lib/logging.sh:156`: `is_fake_mode()` function

## Test Environment Details

- Test file: `tests/test_config_loading.sh:105`
- Config file content:
  ```
  EXTERNAL_PEER_IPS="192.168.1.1"
  LOG_FILE="/tmp/custom-logs/vpn-monitor.log"
  ```
- Expected directory: `/tmp/custom-logs`
- Test helper: `create_test_vpn_monitor_script()` in `tests/test_helper.bash`

## Solution

**Root Cause:** The `CONFIG_SCHEMA` associative array was not being populated when `config_schema.sh` was sourced. The schema file uses `declare -A CONFIG_SCHEMA=(...)` to declare and populate the array, but this wasn't working when sourced via `safe_source_lib`.

**Fix:** Pre-declare `CONFIG_SCHEMA` as an empty associative array in `lib/config.sh` before sourcing the schema file. This allows the schema file to populate the array correctly.

**Changes Made:**
1. **`lib/config.sh`**: Pre-declare `CONFIG_SCHEMA` as empty array before sourcing schema file
2. **`lib/common.sh`**: Improved `safe_source_lib` to check file existence before sourcing

**Key Insight:** Associative arrays in Bash need to be declared before they can be populated. When the schema file tried to declare and populate the array in one step, it wasn't working in the context where `config.sh` was sourced. Pre-declaring the array as empty allows the schema file to populate it successfully.

## Notes

- The script uses `set -euo pipefail` which causes immediate exit on any error
- Error output is redirected to `/dev/null` in the `get_config_schema` check: `>/dev/null 2>&1`
- The `--fake` flag sets `NO_ESCALATE=1` which should make `is_fake_mode()` return true
- `handle_error_or_exit_fake_mode()` should exit with code 0 in fake mode, but script exits with code 1
- **FIXED**: `CONFIG_SCHEMA` must be pre-declared as empty array before sourcing schema file