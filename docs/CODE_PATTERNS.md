# Code Patterns Documentation

**Date:** 2026-01-10  
**Purpose:** Comprehensive documentation of code patterns used throughout the UDM VPN Monitor codebase

## Overview

This document consolidates code patterns identified from:
- Code review lessons learned (`CODE_REVIEW_LESSONS_LEARNED.md`)
- Developer guidelines (`DEVELOPER.md`)
- Architecture documentation (`ARCHITECTURE.md`)
- Testing patterns (`BATS_GUIDE.md`)
- Actual codebase implementation

These patterns should be followed consistently when writing or modifying code in this project.

---

## Table of Contents

1. [Error Handling Patterns](#error-handling-patterns)
2. [File Operation Patterns](#file-operation-patterns)
3. [State Management Patterns](#state-management-patterns)
4. [Validation Patterns](#validation-patterns)
5. [Function Documentation Patterns](#function-documentation-patterns)
6. [Function Design Patterns](#function-design-patterns)
7. [Configuration Patterns](#configuration-patterns)
8. [Logging Patterns](#logging-patterns)
9. [Module Organization Patterns](#module-organization-patterns)
10. [Testing Patterns](#testing-patterns)
11. [Variable and Naming Patterns](#variable-and-naming-patterns)
12. [Arithmetic and Calculation Patterns](#arithmetic-and-calculation-patterns)
13. [Process Management Patterns](#process-management-patterns)
14. [Network Command Timeout Patterns](#network-command-timeout-patterns)
15. [Command Availability Patterns](#command-availability-patterns)
16. [String Parsing and Manipulation Patterns](#string-parsing-and-manipulation-patterns)
17. [Loop and Iteration Patterns](#loop-and-iteration-patterns)
18. [Associative Array Patterns](#associative-array-patterns)
19. [Variable Initialization Patterns](#variable-initialization-patterns)
20. [Bash Strict Mode and Safety Patterns](#bash-strict-mode-and-safety-patterns)
    - [Validate Paths Before Deletion Operations](#pattern-validate-paths-before-deletion-operations)
    - [Protect Against Symlink Attacks in Deletion Operations](#pattern-protect-against-symlink-attacks-in-deletion-operations)
    - [Defense-in-Depth for Critical Operations](#pattern-defense-in-depth-for-critical-operations)
21. [Quoting and Variable Expansion Patterns](#quoting-and-variable-expansion-patterns)
22. [UDM-Specific Constraints](#udm-specific-constraints)

---

## Error Handling Patterns

### Pattern: Fatal Errors (Script Should Exit)

**When to Use:** Configuration errors, critical system errors, security violations, missing required dependencies

**Pattern:**
```bash
# Use handle_error_or_exit_fake_mode() for fatal errors that need fake mode support
if [[ ! -f "$CONFIG_FILE" ]] && [[ -z "${EXTERNAL_PEER_IPS:-}" ]]; then
    handle_error_or_exit_fake_mode "SYSTEM" "Configuration file not found and EXTERNAL_PEER_IPS not set" "${EXIT_CONFIG_ERROR:-2}"
fi

# Use die() for truly fatal errors that prevent script execution entirely
if ! check_command_available "ip"; then
    die "Required command 'ip' not found in PATH" "${EXIT_COMMAND_NOT_FOUND:-5}"
fi
```

**Key Points:**
- Use `handle_error_or_exit_fake_mode()` when errors need fake mode support (for testing)
- Use `die()` for errors that prevent script execution entirely (even in fake mode)
- Always use exit code constants from `lib/constants.sh` (EXIT_*) instead of magic numbers
- Provide descriptive error messages that help users understand and fix issues

**Exit Code Constants:**
- `EXIT_SUCCESS=0` - Successful operation
- `EXIT_GENERAL_ERROR=1` - General/unclassified error
- `EXIT_CONFIG_ERROR=2` - Configuration file error
- `EXIT_VALIDATION_ERROR=3` - Validation error
- `EXIT_PERMISSION_ERROR=4` - Permission error
- `EXIT_COMMAND_NOT_FOUND=5` - Required command not found
- `EXIT_STATE_ERROR=6` - State file error

### Pattern: Non-Fatal Errors (Function Should Return Error Code)

**When to Use:** Validation failures, optional operations that fail, detection/check operations

**Pattern:**
```bash
check_vpn_status() {
    local peer_ip="$1"
    
    if ! validate_ip_address "$peer_ip"; then
        log_message "ERROR" "SYSTEM" "Invalid peer IP format: $peer_ip"
        return 1  # Return error code, don't die
    fi
    
    # ... check logic ...
    
    if [[ $primary_check_passed -eq 0 ]]; then
        return 1  # Primary check failed
    fi
    
    return 0  # VPN is healthy
}

# Caller handles the error:
if ! check_vpn_status "$peer_ip" "$location_name"; then
    if [[ -n "$location_name" ]]; then
        log_message "WARNING" "$location_name" "VPN check failed for $location_name ($peer_ip)"
    else
        log_message "WARNING" "SYSTEM" "VPN check failed for $peer_ip"
    fi
    increment_failure "$location_name" "$peer_ip"
fi
```

**Key Points:**
- Return 0 for success, 1 for failure
- Callers check return codes and handle errors appropriately
- Log warnings/errors but don't exit script
- Functions that can fail gracefully should return error codes

### Pattern: Warnings (Non-Fatal, Logged)

**When to Use:** Optional features unavailable, degraded functionality, recoverable errors, informational warnings

**Pattern:**
```bash
if ! check_command_or_warn "ipsec" "Checking IPsec status"; then
    log_message "WARNING" "SYSTEM" "ipsec command not available"
    # Handle missing ipsec command
fi

if [[ ! -f "$cache_file" ]]; then
    log_message "WARNING" "SYSTEM" "Cache file not found: $cache_file (will recreate)"
    # Continue and recreate cache
fi
```

**Key Points:**
- Log the warning and continue execution
- Warning alerts users to potential issues but doesn't stop script
- Use appropriate log levels: ERROR, WARNING, INFO, DEBUG

### Pattern: Fake Mode Support

**When to Use:** Fatal errors that need fake mode support for testing

**Pattern:**
```bash
# ✅ GOOD: Use handle_error_or_exit_fake_mode() with prefix
if [[ $is_writable -eq 0 ]]; then
    handle_error_or_exit_fake_mode "SYSTEM" "STATE_DIR is not writable: $lockfile_dir" "${EXIT_PERMISSION_ERROR:-4}"
fi

# ❌ BAD: Manual is_fake_mode() check
if is_fake_mode; then
    handle_error "ERROR" "Config error" 0
    exit 0
else
    die "Config error"
fi
```

**Key Points:**
- Use `handle_error_or_exit_fake_mode()` instead of manual `is_fake_mode()` checks
- Standardizes fake mode handling across codebase
- Fake mode (NO_ESCALATE=1): Logs error and returns 1 (allows caller to decide exit behavior)
- Normal mode: Logs error and exits with specified exit code

#### Fake Mode Exit Behavior (when to fail vs succeed)

- Execution-blocking and failure-focused (validation failures, route setup failures, permission errors): exit with the appropriate error code in both normal and fake mode so tests can `assert_failure`.
- Logging-focused (config parse errors, directory creation failures when testing log format): exit with the error code in normal mode but exit `0` in fake mode so tests can `assert_success` and check log output.
- Both categories are functionally blocking; the difference is what the test asserts. Document the intent in code comments when the choice is non-obvious.

**Patterns**
```bash
# Execution-blocking: fail in fake mode too
if ! validate_config; then
    exit "${EXIT_VALIDATION_ERROR:-3}"
fi

# Logging-focused: succeed in fake mode to inspect logs
if ! load_config "$CONFIG_FILE"; then
    if is_fake_mode; then
        exit "${EXIT_SUCCESS:-0}"
    fi
    exit "${EXIT_VALIDATION_ERROR:-3}"
fi
```

**Pattern: Checking Return Value in Functions**

When calling `handle_error_or_exit_fake_mode()` from a function that needs to return an error code (not exit), always check the return value:

```bash
# ✅ GOOD: Check return value when function needs to return error code
validate_config_type() {
    if [[ "$required" == "required" ]]; then
        # In fake mode, it returns 1; in normal mode it calls die() and never returns
        if ! handle_error_or_exit_fake_mode "SYSTEM" "$var_name must be an integer" "${EXIT_VALIDATION_ERROR:-3}"; then
            # In fake mode, handle_error_or_exit_fake_mode returns 1
            return 1
        fi
        # In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
    fi
}

# ✅ GOOD: Use || return 1 pattern for simple cases
if ! mkdir -p "$dir" 2>/dev/null; then
    handle_error_or_exit_fake_mode "SYSTEM" "Cannot create directory: $dir" || return 1
fi

# ❌ BAD: Don't call and then always return 1 without checking
if [[ "$required" == "required" ]]; then
    handle_error_or_exit_fake_mode "SYSTEM" "$var_name must be an integer" "${EXIT_VALIDATION_ERROR:-3}"
    return 1  # This always executes, even if function succeeded (though it never does)
fi
```

**Key Points:**
- Always check return value when function needs to return error code
- In fake mode: `handle_error_or_exit_fake_mode()` returns 1, so check with `if ! ... then return 1`
- In normal mode: `handle_error_or_exit_fake_mode()` calls `die()` and never returns
- Use `|| return 1` pattern for simple cases where you want to return immediately on error

### Pattern: Try-Fallback

**When to Use:** Operations with fallback mechanisms

**Pattern:**
```bash
if [[ "${ENABLE_XFRM_RECOVERY:-1}" -eq 1 ]]; then
    if ! attempt_xfrm_recovery "$peer_ip" "$location_name"; then
        if [[ -n "$location_name" ]]; then
            log_message "WARNING" "$location_name" "xfrm recovery failed for $location_name ($peer_ip), falling back"
        else
            log_message "WARNING" "SYSTEM" "xfrm recovery failed, falling back"
        fi
        if ! ipsec reload 2>/dev/null; then
            if [[ -n "$location_name" ]]; then
                log_message "ERROR" "$location_name" "ipsec reload also failed for $location_name ($peer_ip)"
            else
                log_message "ERROR" "SYSTEM" "ipsec reload also failed"
            fi
            return 1
        fi
    fi
else
    if ! ipsec reload 2>/dev/null; then
        if [[ -n "$location_name" ]]; then
            log_message "ERROR" "$location_name" "ipsec reload failed for $location_name ($peer_ip)"
        else
            log_message "ERROR" "SYSTEM" "ipsec reload failed"
        fi
        return 1
    fi
fi
```

**Key Points:**
- Try primary method first
- Fall back to alternative if primary fails
- Log warnings when falling back
- Return error codes, don't die

### Pattern: Error Capture for Actionable Failures Only

**When to Use:** Distinguish between failures that need detailed error messages (actionable) vs failures that can use simple fallbacks (non-actionable)

**Pattern:**
```bash
# ✅ GOOD: Capture errors for actionable failures (mkdir, source syntax)
local mkdir_error
mkdir_error=$(mkdir -p "$dir" 2>&1)
if [[ $? -ne 0 ]]; then
    local error_msg="Cannot create directory: $dir"
    if [[ -n "$mkdir_error" ]]; then
        error_msg="${error_msg} (error: ${mkdir_error})"
    fi
    handle_error_or_exit_fake_mode "SYSTEM" "$error_msg" || return 1
fi

# ✅ GOOD: Simple fallback for non-actionable failures (readlink, optional commands)
if ! command_that_might_fail 2>/dev/null; then
    # Use fallback - no need to log (error is rare, already handled)
    use_fallback_approach
fi
```

**Key Points:**
- Capture error output (`2>&1`) for failures where the error message helps diagnose the problem (mkdir failures, source syntax errors, etc.)
- Use simple fallbacks (`2>/dev/null`) for optional operations where failure is expected and already handled (readlink, optional commands)
- Only capture errors when the error message provides actionable information
- For non-actionable failures, suppress stderr and use the fallback approach without logging

### Pattern: Early Returns and Guard Clauses

**When to Use:** Functions with multiple validation checks or error conditions

**Pattern:**
```bash
# ✅ GOOD: Early returns for error conditions (guard clauses)
check_vpn_status() {
    local peer_ip="$1"
    
    # Guard clause: Validate input early
    if ! validate_ip_address "$peer_ip"; then
        log_message "ERROR" "Invalid peer IP format: $peer_ip"
        return 1
    fi
    
    # Guard clause: Check if file exists
    if ! file_exists_and_readable "$state_file"; then
        return 1
    fi
    
    # Main logic (only reached if all guards pass)
    # ... process VPN status ...
    
    return 0
}

# ✅ GOOD: Early return on success, continue on failure
process_line() {
    local line="$1"
    
    # Skip empty lines early
    [[ -z "$line" ]] && return 0
    
    # Skip comments early
    [[ "$line" =~ ^[[:space:]]*# ]] && return 0
    
    # Process line
    # ...
}

# ❌ BAD: Nested if statements (harder to read)
check_vpn_status() {
    local peer_ip="$1"
    
    if validate_ip_address "$peer_ip"; then
        if file_exists_and_readable "$state_file"; then
            # Main logic deeply nested
            # ...
        fi
    fi
}
```

**Key Points:**
- Use early returns (guard clauses) to handle error conditions first
- Validate input early and return error code if validation fails
- Reduces nesting and improves readability
- Each guard clause handles one error condition and returns early
- Main logic is at the function's natural indentation level
- Continue processing only with valid input
- Use `continue` in loops for early iteration skipping
- Use `break` in loops for early loop exit

**Avoid Braces in Conditionals:**
- Don't use command group braces `{ ... }` inside `if` conditionals - this causes bash syntax errors
- Use helper variables or separate `if`/`elif` branches instead
```bash
# ❌ BAD: Braces in conditional cause syntax error
if [[ condition1 ]] || [[ condition2 ]] || { [[ condition3 ]] && [[ condition4 ]]; }; then
    # Syntax error: "syntax error in conditional expression"
fi

# ✅ GOOD: Use helper variable for clarity
local should_do_action=0
if [[ condition1 ]] || [[ condition2 ]]; then
    should_do_action=1
elif [[ condition3 ]] && [[ condition4 ]]; then
    should_do_action=1
fi
if [[ $should_do_action -eq 1 ]]; then
    # Action
fi
```

### Pattern: Optional-Feature

**When to Use:** Optional features that can fail without affecting main functionality

**Pattern:**
```bash
if [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
    if ! check_ping_connectivity "$target_ip"; then
        log_message "WARNING" "Ping check failed (optional feature)"
        # Continue - ping is optional
    fi
fi
```

**Key Points:**
- Check if feature is enabled before using
- Log warnings but don't fail if optional feature fails
- Continue execution even if optional feature fails

### Pattern: Simplify Complex Conditionals When All Branches Converge

**When to Use:** Conditionals where all branches end with the same operation

**Pattern:**
```bash
# ❌ BAD: All branches do the same thing at the end
if [[ condition1 ]]; then
    # ... specific logic ...
    LOG_FILE="${LOGS_DIR}/${log_filename}"
elif [[ condition2 ]]; then
    # ... different logic ...
    LOG_FILE="${LOGS_DIR}/${log_filename}"
else
    # ... default logic ...
    LOG_FILE="${LOGS_DIR}/${log_filename}"
fi

# ✅ GOOD: Extract common operation
if [[ condition1 ]]; then
    # ... specific logic ...
elif [[ condition2 ]]; then
    # ... different logic ...
fi
# Common operation happens in all cases
LOG_FILE="${LOGS_DIR}/${log_filename}"
```

**Key Points:**
- When all branches converge to the same operation, extract that operation outside the conditional
- Identify what differs between branches (the condition)
- Move common operations outside the conditional
- Check if existing functions already handle the error case (like `log_message()` handling logging failures)
- Simplify conditionals by removing unnecessary flags and intermediate variables
- Verify logic equivalence after simplification

**Related Patterns:**
- See `CODE_REVIEW_LESSONS_LEARNED.md` section 25 for detailed examples and rationale

### Pattern: Distinguish Between Script Execution Success and Recovery Success

**When to Use:** Functions that attempt recovery actions and need to return appropriate exit codes

**Pattern:**
```bash
# ✅ GOOD: Distinguish execution success from operational success
if recovery_was_attempted; then
    # Script completed successfully - recovery was attempted, failures are logged
    return 0
else
    # No recovery attempted - script execution succeeded but VPN check failed
    return 1
fi

# ❌ BAD: Treat recovery failures as script execution failures
if recovery_failed; then
    return 1  # Script execution didn't fail, recovery did
fi
```

**Key Points:**
- **Script execution success ≠ Operational success**
- The script's job is to monitor and attempt recovery
- If recovery is attempted (even if it fails), the script has successfully completed its monitoring task
- Recovery failures are logged and can be detected via log monitoring, but they shouldn't cause the script to exit with failure
- Script only returns failure (1) when:
  - VPN check fails and no recovery was attempted (Tier 1 or below threshold)
  - There's an actual script execution error
- Script returns success (0) when recovery is attempted (Tier 2 or Tier 3), even if recovery fails

**Related Patterns:**
- See `CODE_REVIEW_LESSONS_LEARNED.md` section 26 for detailed rationale and examples
- Recovery failures are logged via `handle_error()` and `log_message()`
- Script exit codes should reflect execution success, not operational outcomes

### Pattern: Track Error State When Functions Log But Don't Exit

**When to Use:** Functions that call error handlers in loops or continue processing after errors

**Pattern:**
```bash
# ✅ GOOD: Track error state
local parse_error=0
if ! parse_assignment "$line" "$line_num" "parse_result"; then
    if ! handle_config_error "Parse error"; then
        # In fake mode, handle_config_error returns 1 (failure)
        parse_error=1
    fi
    continue
fi
# ... more processing ...
if [[ "$parse_error" -eq 1 ]]; then
    return 1
fi
return 0

# ❌ BAD: Don't check return value
if ! parse_assignment "$line" "$line_num" "parse_result"; then
    handle_config_error "Parse error"  # Error logged but not tracked
    continue  # Function continues and returns 0
fi
```

**Key Points:**
- Functions that call error handlers in loops must track error state
- Check return value of `handle_config_error()` and similar functions
- Return error status at end of function if any errors occurred
- In fake mode, error handlers return 1; in normal mode they exit

---

## File Operation Patterns

### Pattern: Check Readability Before File Operations

**When to Use:** Before any file read operation (`cat`, `grep`, `wc`, `head`, `tail`, `cp`)

**Pattern:**
```bash
# ✅ GOOD: Check readability before reading
if file_exists_and_readable "$file"; then
    value=$(cat "$file" 2>/dev/null || echo "default")
else
    value="default"
fi

# ❌ BAD: Error suppression doesn't prevent hangs
value=$(cat "$file" 2>/dev/null || echo "default")  # Can still hang!
```

**Key Points:**
- Always use `file_exists_and_readable` before file read operations
- Error suppression (`2>/dev/null`) does NOT prevent hangs on unreadable files
- Provide sensible defaults when files are unreadable
- Log warnings but don't fail the script

**Operations That Can Hang on Unreadable Files:**
- `cat` - Reading file contents
- `grep` - Searching file contents
- `wc` - Counting lines/words
- `cp` - Copying files
- `mv` - Moving/overwriting files (during atomic writes)
- `head`/`tail` - Reading file portions

**Safe Operations (don't hang):**
- `[[ -r "$file" ]]` - Permission check (returns immediately)
- `[[ -f "$file" ]]` - File existence check
- `stat` - File metadata operations
- `rm -f` - File removal (can remove unreadable files)
- `touch` - File creation

### Pattern: Atomic File Writes

**When to Use:** All state file writes to prevent corruption and race conditions

**Pattern:**
```bash
# ✅ GOOD: Use atomic_write_file() helper
if ! atomic_write_file "$state_file" "$value"; then
    log_message "ERROR" "SYSTEM" "Failed to write state file: $file"
    return 1
fi

# ✅ GOOD: Manual atomic write pattern
if ! (echo "$data" > "${file}.tmp" && mv "${file}.tmp" "$file"); then
    log_message "ERROR" "SYSTEM" "Failed to write state file: $file"
    return 1
fi
```

**Key Points:**
- Use write-tmp-move pattern: Write to temporary file, then atomically move to final location
- Ensures files are never partially written
- Prevents race conditions during concurrent access
- Use `atomic_write_file()` helper function when available

**Implementation:**
1. Write to temporary file (`$file.tmp`)
2. Verify write succeeded
3. Atomically move temp file to final location (`mv $file.tmp $file`)
4. Clean up temp file on success

### Pattern: Remove Before Atomic Write (Unreadable Files)

**When to Use:** Before atomic writes when target file may be unreadable or unwritable

**Note:** The `atomic_write_file()` helper function automatically handles this. This pattern is only needed if implementing atomic writes manually.

**Pattern:**
```bash
# ✅ GOOD: Remove unreadable/unwritable file before atomic write
# atomic_write_file() now handles this automatically, but if calling directly:
if [[ -f "$file" ]] && (! file_exists_and_readable "$file" || ! [[ -w "$file" ]]); then
    rm -f "$file" 2>/dev/null || true
fi
atomic_write_file "$file" "$content"

# ❌ BAD: Atomic write can hang on unreadable or unwritable target
echo "$content" > "$file.tmp"
mv "$file.tmp" "$file"  # Can hang if $file is unreadable (chmod 000) or unwritable (chmod 444)!
```

**Key Points:**
- **Prefer using `atomic_write_file()` helper** which automatically handles unreadable/unwritable files
- If implementing atomic writes manually: Remove unreadable or unwritable target files before atomic writes
- Prevents hangs when overwriting unreadable files (chmod 000) or unwritable files (chmod 444)
- Use `rm -f` which can remove unreadable/unwritable files safely
- **See "Check Readability Before File Operations" pattern** for general guidance on file readability checks

### Pattern: Clean Up Leftover .tmp Files

**When to Use:** Before atomic writes to prevent hangs from leftover temp files

**Note:** The `atomic_write_file()` helper function automatically handles this. This pattern is only needed if implementing atomic writes manually.

**Pattern:**
```bash
# ✅ GOOD: Clean up .tmp files before atomic write
# atomic_write_file() handles this automatically, but if calling directly:
if [[ -f "${file}.tmp" ]]; then
    rm -f "${file}.tmp" 2>/dev/null || true
fi
atomic_write_file "$file" "$content"
```

**Key Points:**
- **Prefer using `atomic_write_file()` helper** which automatically cleans up leftover temp files
- If implementing atomic writes manually: Clean up leftover `.tmp` files before attempting atomic writes
- Prevents hangs if previous atomic write failed and left a `.tmp` file
- Ensures clean slate for atomic write operation

### Pattern: Ensure Temporary File Cleanup on Error

**When to Use:** Atomic writes or operations that create temporary files

**Pattern:**
```bash
# ✅ GOOD: Clean up temp file even if operation fails
if ! awk -v cutoff="$one_day_ago" '$1 > cutoff' "$file" >"${file}.tmp" 2>/dev/null; then
    handle_error "WARNING" "Failed to filter file"
    rm -f "${file}.tmp" 2>/dev/null || true  # Clean up on error
    return 1
fi

# Atomic move
if ! mv "${file}.tmp" "$file" 2>/dev/null; then
    handle_error "WARNING" "Failed to update file"
    rm -f "${file}.tmp" 2>/dev/null || true  # Clean up on error
    return 1
fi

# ❌ BAD: Don't clean up temp file on error (leaves orphaned files)
if ! awk -v cutoff="$one_day_ago" '$1 > cutoff' "$file" >"${file}.tmp" 2>/dev/null; then
    handle_error "WARNING" "Failed to filter file"
    return 1  # Bug: ${file}.tmp left behind!
fi
```

**Key Points:**
- Always clean up temporary files when operations fail
- Use `rm -f "${file}.tmp" 2>/dev/null || true` to ensure cleanup happens
- Prevents accumulation of orphaned temporary files
- Apply cleanup in all error paths, not just success paths

### Pattern: Functions Must Output Values

**When to Use:** Functions that are expected to output values (not just return exit codes)

**Pattern:**
```bash
# ✅ GOOD: Outputs empty string when no value available
extract_lockfile_pid() {
    local lockfile="$1"
    if ! file_exists_and_readable "$lockfile"; then
        echo ""  # Return empty string (no PID available)
        return 0
    fi
    cat "$lockfile" | cut -d: -f1
}

# ❌ BAD: Returns success but outputs nothing
extract_lockfile_pid() {
    local lockfile="$1"
    if ! file_exists_and_readable "$lockfile"; then
        return 0  # Bug: Caller expects empty string, gets nothing!
    fi
    cat "$lockfile" | cut -d: -f1
}
```

**Key Points:**
- If function is expected to output a value, it must `echo` the value
- Returning exit code 0 is not enough - must output empty string if no value
- Callers expect output, not just success/failure

---

## State Management Patterns

### Pattern: Use Abstraction Layers for State File Paths

**When to Use:** Always when constructing state file paths

**Pattern:**
```bash
# ✅ GOOD: Use abstraction layer
state_file=$(get_peer_state_file_path "$location_name" "$peer_ip" "failure_type")
atomic_write_file "$state_file" "$value"

# ❌ BAD: Direct path construction
state_file="${STATE_DIR}/failure_type_${peer_sanitized}"
atomic_write_file "$state_file" "$value"
```

**Key Points:**
- Always use `get_peer_state_file_path()` abstraction layer
- Never construct state file paths directly
- Abstraction layers ensure consistency, handle edge cases, and make refactoring easier
- Before writing state files, check if `get_peer_state_file_path()` supports the key
- If not, add the key to the abstraction layer

**Important for Tests:**
- **Always use the abstraction layer in tests** - hardcoded paths may not match the format used by the code
- Hardcoded paths like `${STATE_DIR}/failure_type_TEST_192_168_1_1` may fail because:
  - The abstraction layer may use different sanitization (e.g., location name format)
  - Path format changes would break hardcoded paths but not abstraction layer usage
  - The code checks for files using `get_peer_state_file_path()`, so tests must use the same function
- Example test pattern:
  ```bash
  # ✅ GOOD: Use abstraction layer in tests
  source_function "get_peer_state_file_path"
  local failure_type_file
  failure_type_file=$(get_peer_state_file_path "TEST" "192.168.1.1" "failure_type")
  echo "tunnel_down" >"$failure_type_file"
  
  # ❌ BAD: Hardcoded path in test (may not match code's path format)
  echo "tunnel_down" >"${STATE_DIR}/failure_type_TEST_192_168_1_1"
  ```

**Files Intentionally Outside the Abstraction Layer:**

Some state files are intentionally **not** managed by `get_peer_state_file_path()` because they represent **global system state** rather than per-peer or per-location state.

**Evaluation Criteria:**
- The abstraction layer is designed for: per-peer state, per-location state, or per-peer/per-location state
- Files remain outside if they represent: global system state or system-wide operations that affect all tunnels/locations

1. **`RESTART_COUNT_FILE`** (`${STATE_DIR}/restart_count`)
   - **Purpose**: Tracks restart timestamps for rate limiting (prevents restart loops)
   - **Scope**: Records Tier 3 recovery actions:
     - Full IPsec restarts (`ipsec restart`) - **affects ALL tunnels**
     - Successful xfrm-based per-connection recovery (when enabled)
   - **Why Outside**: 
     - `ipsec restart` command restarts the entire IPsec service, affecting all VPN tunnels
     - Rate limiting must be global to prevent system-wide disruption from excessive restarts
     - ADR-0008 explicitly states "Per-System Limits: Rate limiting applies globally (not per-peer) to prevent system-wide disruption"
     - Even though xfrm recovery is per-connection, it's tracked globally for rate limiting
   - **Usage**: Use `RESTART_COUNT_FILE` variable directly

2. **`NETWORK_PARTITION_STATE_FILE`** (`${STATE_DIR}/network_partition_state`)
   - **Purpose**: Tracks network connectivity status (0 = healthy, 1 = partitioned)
   - **Scope**: System-wide network condition
   - **Why Outside**: 
     - Network partition affects the entire system, not just one location
     - If network is down, it affects all locations simultaneously
     - Used to skip recovery for ALL locations when network is partitioned
     - Per-location partition state would be redundant and confusing
   - **Usage**: Use `get_network_partition_state_file()` function or `NETWORK_PARTITION_STATE_FILE` variable

4. **`LOCKFILE`** (`${STATE_DIR}/vpn-monitor.lock`)
   - **Purpose**: Prevents concurrent script execution
   - **Scope**: System-wide lock
   - **Why Outside**: 
     - Only one instance of the monitoring script should run at a time
     - Protects all state files (both per-peer and global) from concurrent access
     - Per-location lockfiles would allow concurrent execution, causing conflicts
   - **Usage**: Use `LOCKFILE` variable directly

5. **`PIDFILE`** (`${STATE_DIR}/vpn-keepalive.pid`)
   - **Purpose**: PID file for VPN keepalive daemon
   - **Scope**: Single daemon process
   - **Why Outside**: 
     - There is only one keepalive daemon process
     - Not a per-peer or per-location concept
     - Standard Unix daemon pattern (single PID file)
   - **Usage**: Use `PIDFILE` variable directly

**When to Add to Abstraction Layer:**
- If a new state file is **per-peer** or **per-location**, add it to `get_peer_state_file_path()`
- If a new state file is **global** (applies to entire system), keep it outside and use a constant/variable

**Edge Case: XFRM-Based Recovery Tracking**
- XFRM-based recovery is per-connection (affects only one peer) but is tracked in the global `RESTART_COUNT_FILE`
- This is intentional per ADR-0008: even though xfrm recovery is per-connection, it's tracked globally for rate limiting
- Rationale: Prevents excessive recovery attempts even if they're per-connection

### Pattern: Per-Location State Tracking

**When to Use:** All state operations that need per-location isolation

**Pattern:**
```bash
# Get per-location state
failure_count=$(get_peer_state "$location_name" "$peer_ip" "failure_count" "0")

# Set per-location state
set_peer_state "$location_name" "$peer_ip" "failure_count" "$new_count"

# Use abstraction layer for paths
state_file=$(get_peer_state_file_path "$location_name" "$peer_ip" "failure_type")
```

**Key Points:**
- All state operations use location name and peer IP
- State files use sanitized location names and IPs in filenames
- Each location's state files are completely independent
- Format: `<key>_<location>_<peer_ip>` (e.g., `failure_counter_NYC_203_0_113_1`)

### Pattern: State File Naming Conventions

**When to Use:** Understanding how state files are named and organized

**Naming Convention Overview:**

All state files managed by the abstraction layer follow consistent naming patterns. The `get_peer_state_file_path()` function in `lib/state/state_paths.sh` handles all path construction and sanitization.

**Per-Location, Per-Peer State Files:**

These files track state for a specific location and peer IP combination. Format: `<key>_<sanitized_location>_<sanitized_peer_ip>`

**Supported Keys:**
1. **`failure_count`** → `failure_counter_<location>_<peer_ip>`
   - Example: `failure_counter_NYC_203_0_113_1`
   - Tracks consecutive failure count per location

2. **`last_bytes`** → `last_bytes_<location>_<peer_ip>`
   - Example: `last_bytes_NYC_203_0_113_1`
   - Tracks last known byte counter value per location

3. **`spi`** → `spi_<location>_<peer_ip>`
   - Example: `spi_NYC_203_0_113_1`
   - Stores SPI (Security Parameter Index) for location connection tracking

4. **`idle_detected`** → `idle_detected_<location>_<peer_ip>`
   - Example: `idle_detected_NYC_203_0_113_1`
   - Tracks idle detection state for the location

5. **`last_status_log`** → `last_status_log_<location>_<peer_ip>`
   - Example: `last_status_log_NYC_203_0_113_1`
   - Timestamp of last status log entry for the location

6. **`failure_type`** → `failure_type_<location>_<peer_ip>`
   - Example: `failure_type_NYC_203_0_113_1`
   - Tracks failure type for diagnostic purposes (cleared on recovery)

7. **`recovery_method`** → `recovery_method_<location>_<peer_ip>`
   - Example: `recovery_method_NYC_203_0_113_1`
   - Tracks recovery method used when recovery was attempted (cleared after restoration is logged)

**Per-Peer State Files (No Location):**

These files track state per peer IP only, without location context. Format: `<key>_<sanitized_peer_ip>`

1. **`connection_name`** → `connection_name_<peer_ip>`
   - Example: `connection_name_203_0_113_1`
   - Caches IPsec connection name discovered from `ipsec status` output
   - Per-peer only (no location), so empty location string is passed to abstraction layer

**Sanitization Rules:**

1. **Location Name Sanitization:**
   - Invalid filename characters are replaced with underscores
   - Maximum length: 64 characters (enforced by `sanitize_location_name()` in `lib/common.sh`)
   - Example: `NYC Office` → `NYC_Office`

2. **Peer IP Sanitization:**
   - Dots (`.`) and colons (`:`) are replaced with underscores (`_`)
   - IPv4: `192.168.1.1` → `192_168_1_1`
   - IPv6: `2001:db8::1` → `2001_db8__1`
   - Handled by `sanitize_peer_ip()` in `lib/state/state_paths.sh`

**Global State Files (Outside Abstraction Layer):**

These files are intentionally outside the abstraction layer because they represent global system state:

- `${STATE_DIR}/cooldown_until` - Cooldown expiration timestamp
- `${STATE_DIR}/restart_count` - Unix timestamps of Tier 3 recovery actions
- `${STATE_DIR}/network_partition_state` - Network partition status (0=healthy, 1=partitioned)
- `${STATE_DIR}/network_partition_dns_success_count` - DNS check success counter
- `${STATE_DIR}/network_partition_dns_fail_count` - DNS check failure counter
- `${STATE_DIR}/network_partition_route_success_count` - Route check success counter
- `${STATE_DIR}/network_partition_route_fail_count` - Route check failure counter
- `${STATE_DIR}/network_partition_interface_success_count` - Interface check success counter
- `${STATE_DIR}/network_partition_interface_fail_count` - Interface check failure counter
- `${STATE_DIR}/network_partition_summary_last_time` - Timestamp of last statistics summary
- `${STATE_DIR}/vpn-monitor.lock` - Lockfile for execution control
- `${STATE_DIR}/vpn-keepalive.pid` - PID file for VPN keepalive daemon
- `${STATE_DIR}/.cron_checked` - Flag file for cron check

**Usage Guidelines:**

1. **Always use `get_peer_state_file_path()`** for per-peer/per-location state files
   - Never construct paths directly
   - Ensures consistent sanitization and format

2. **Use `get_peer_state()` and `set_peer_state()`** for state operations
   - These functions use the abstraction layer internally
   - Provide atomic writes and validation

3. **For global state files**, use the defined constants:
   - `RESTART_COUNT_FILE`, `COOLDOWN_UNTIL_FILE`, `LOCKFILE`, etc.

4. **Adding new state keys:**
   - Add the key to the `case` statement in `get_peer_state_file_path()`
   - Follow the naming pattern: `<key>_<location>_<peer_ip>` or `<key>_<peer_ip>` for per-peer-only keys
   - Update this documentation

**Examples:**

```bash
# ✅ GOOD: Use abstraction layer
state_file=$(get_peer_state_file_path "NYC" "203.0.113.1" "failure_count")
# Returns: ${STATE_DIR}/failure_counter_NYC_203_0_113_1

# ✅ GOOD: Use state accessor functions
count=$(get_peer_state "NYC" "203.0.113.1" "failure_count" "0")
set_peer_state "NYC" "203.0.113.1" "failure_count" "5"

# ✅ GOOD: Per-peer-only state (connection_name)
conn_file=$(get_peer_state_file_path "" "203.0.113.1" "connection_name")
# Returns: ${STATE_DIR}/connection_name_203_0_113_1

# ❌ BAD: Direct path construction
state_file="${STATE_DIR}/failure_counter_${location}_${ip}"
# Problems: No sanitization, inconsistent format, breaks if naming changes
```

**Key Points:**
- All per-peer/per-location state files use the abstraction layer
- Sanitization ensures safe filenames across different location names and IP formats

### Pattern: Statistics Tracking with Periodic Summary Logging

**When to Use:** Operations that run frequently and need visibility into success/failure rates without cluttering logs

**Pattern:**
```bash
# Track individual check result
track_network_partition_check "dns" 1    # success
track_network_partition_check "dns" 0    # failure

# Log summary if interval elapsed (called periodically)
log_network_partition_summary_if_due
```

**Implementation Pattern:**
1. **Tracking Function**: Increments appropriate counter in state file
   - Uses atomic writes (ADR-0012) for state file integrity
   - Handles missing STATE_DIR gracefully
   - Validates input (check type, success flag)

2. **Summary Function**: Logs aggregated statistics when interval elapses
   - Checks if configured interval has elapsed since last summary
   - Reads all counters using `read_counter_file()` helper (validates numeric, handles errors)
   - Logs summary message with success/failure counts
   - Resets counters to 0 after logging

**State Files:**
- Success/failure counters: `${STATE_DIR}/<check_type>_success_count`, `${STATE_DIR}/<check_type>_fail_count`
- Last summary timestamp: `${STATE_DIR}/<check_type>_summary_last_time`
- Resource monitoring counters: `${STATE_DIR}/resource_<cpu|ram|disk>_check_success_count`, `${STATE_DIR}/resource_<cpu|ram|disk>_check_fail_count`, `${STATE_DIR}/resource_<cpu_constrained|ram_constrained|disk_critical>_count`
- Resource monitoring summary timestamp: `${STATE_DIR}/resource_monitoring_summary_last_time`

**Counter Reading Pattern:**
```bash
# ✅ GOOD: Use shared helper for reading counter files
local count=$(read_counter_file "$counter_file")
# Handles: missing files, unreadable files, corruption (all return "0")

# ❌ BAD: Duplicate pattern manually
local count
if file_exists_and_readable "$counter_file"; then
    count=$(cat "$counter_file" 2>/dev/null || echo "0")
else
    count="0"
fi
[[ "$count" =~ ^[0-9]+$ ]] || count=0
```

**Examples:**
- Ping check summary: `log_ping_summary_if_due()` (7-minute interval, configurable)
- Network partition check summary: `log_network_partition_summary_if_due()` (1-hour interval, fixed)
- Resource monitoring summary: `log_resource_monitoring_summary_if_due()` (1-hour interval, fixed)

**Key Points:**
- Use atomic writes for all state file operations (per ADR-0012)
- Handle missing STATE_DIR gracefully (return early, don't fail)
- Validate numeric values to handle corruption
- Only log summary when interval has elapsed (prevents log spam)
- Reset counters after logging (start fresh for next interval)
- Track both successes and failures for complete visibility
- Similar pattern can be reused for other frequent checks

**Related Patterns:**
- Atomic File Operations (ADR-0012)
- State File Management
- Periodic Status Logging
- Global state files use constants, not the abstraction layer
- Naming conventions are enforced by `get_peer_state_file_path()`
- Never construct state file paths directly - always use the abstraction layer

### Pattern: State File Format Validation

**When to Use:** Reading state files to detect corruption

**Pattern:**
```bash
# Validate state file format before reading
if ! validate_state_file "$state_file" "integer"; then
    # File is corrupted, recover with safe default
    backup_corrupted_state_file "$state_file"
    recover_corrupted_state_file "$state_file" "integer" "0"
fi

# Read validated state file
value=$(cat "$state_file" 2>/dev/null || echo "0")
```

**Key Points:**
- Validate state file format before reading (integer, timestamp, timestamp_list)
- Corrupted files are automatically detected, backed up, and recovered with safe defaults
- Format validation ensures files contain expected data types and structures
- Recovery mechanism preserves corrupted files for analysis while resetting to safe defaults

### Pattern: Handling Recovery Function Return Values

**When to Use:** Calling `recover_corrupted_state_file()` or other recovery functions

**Pattern:**
```bash
# ✅ GOOD: Check return value when recovery failure affects behavior
validate_state() {
    local validation_failed=0
    
    if ! validate_state_file "$state_file" "integer"; then
        handle_error "WARNING" "State file corrupted, recovering: $state_file" 0
        if ! recover_corrupted_state_file "$state_file" "0" "integer"; then
            # Recovery failed (e.g., backup failed), mark validation as failed
            validation_failed=1
            handle_error "ERROR" "Recovery failed, corrupted file preserved: $state_file" 0
        fi
    fi
    
    return $validation_failed
}

# ✅ ACCEPTABLE: Continue with default value if recovery fails
# This pattern is acceptable when the function can safely return a default value
get_peer_state() {
    local state_file=$(get_peer_state_file_path "$location_name" "$peer_ip" "$key")
    
    if file_exists_and_readable "$state_file"; then
        local value=$(cat "$state_file" 2>/dev/null || echo "$default_value")
        if [[ ! "$value" =~ ^[0-9]+$ ]]; then
            handle_error "WARNING" "Corrupted peer state file (recovering): $state_file" 0
            recover_corrupted_state_file "$state_file" "$default_value" "integer"
            # Continue with default value even if recovery fails
            # Corrupted file is preserved for later analysis
            echo "$default_value"
            return 0
        fi
        echo "$value"
    else
        echo "$default_value"
    fi
}
```

**Key Points:**
- `recover_corrupted_state_file()` returns 0 on success, 1 on failure
- Recovery can fail if backup fails (for readable files) - corrupted file is preserved
- Check return value when recovery failure affects function behavior (e.g., validation status)
- It's acceptable to continue with default values if recovery fails - system continues to work, corrupted file preserved
- When recovery fails, the corrupted file is preserved for later analysis
- Log errors appropriately when recovery fails to aid debugging

**When to Check Return Value:**
- **Must check:** When recovery failure affects return value or validation status
- **Should check:** When you need to track recovery success/failure for monitoring
- **Acceptable to skip:** When function can safely return default value and continue operation

### Pattern: Pattern-Based State File Validation

**When to Use:** Validating multiple state files matching a glob pattern

**Pattern:**
```bash
# Validate all state files matching a pattern
validate_state_files_by_pattern "failure_counter_*" "integer" "0" "Failure counter file" || validation_failed=1
validate_state_files_by_pattern "last_bytes_*" "integer" "0" "Byte counter file" || validation_failed=1
```

**Key Points:**
- Use `validate_state_files_by_pattern()` when validating multiple files with the same pattern
- Automatically handles glob expansion, file existence checks, and recovery
- Reduces code duplication when validating per-peer or pattern-based state files
- Returns 0 if all files are valid or successfully recovered, 1 if any file fails validation
- Always check return value and update validation_failed flag if needed

### Pattern: Always Re-Check Critical State Instead of Relying on Cached Values

**When to Use:** Making critical decisions based on state that can change

**Pattern:**
```bash
# ✅ GOOD: Always re-check critical state
if ! check_network_partition "$dns_server" "$dns_hostname" "$dns_timeout" "$interfaces"; then
    # Network is partitioned - make decision based on fresh check
    local prev_partition_state=$(get_network_partition_state)  # Only for logging
    set_network_partition_state 1
    # ... handle partition ...
fi

# ❌ BAD: Rely on cached state for critical decisions
partition_state=$(get_network_partition_state)  # Cached value
if [[ "$partition_state" -eq 1 ]]; then
    # Only re-check if cached state says partitioned - misses state changes!
    if check_network_partition ...; then
        # ...
    fi
fi
```

**Key Points:**
- When making critical decisions (e.g., skip recovery, perform actions), always re-check the actual state
- Cached state is useful for:
  - Logging (showing state transitions)
  - Performance optimization (avoiding expensive checks)
- Cached state should NOT be used for:
  - Making critical decisions where stale state could cause incorrect behavior
- If state can change between checks, always re-check before making decisions
- Use cached state only for logging state transitions or performance optimization

**Related Patterns:**
- See `CODE_REVIEW_LESSONS_LEARNED.md` section 27 for detailed examples and rationale
- Network partition state is checked in `vpn-monitor.sh` at script start, but recovery code always re-checks
- Failure count increments before partition check to ensure accurate tracking even when recovery is skipped

### Pattern: Persist Corrected Values After Validation

**When to Use:** Validation functions that correct or transform values

**Pattern:**
```bash
# ✅ GOOD: Explicitly persist corrected value after all validations
validate_config_var() {
    local var_name="$1"
    local var_value="${2:-}"
    
    # Get value if not provided
    if [[ -z "$var_value" ]]; then
        var_value="${!var_name:-}"
    fi
    
    # Apply defaults
    var_value=$(apply_config_default "$var_name" "$var_value")
    
    # Validate type
    var_value=$(validate_config_type "$var_name" "$var_value")
    
    # Validate rules
    var_value=$(validate_config_rules "$var_name" "$var_value")
    
    # CRITICAL: Persist corrected value to global variable
    # This ensures corrections (defaults, type corrections, rule corrections) are not lost
    safe_set_variable "$var_name" "$var_value"
    
    return 0
}

# ❌ BAD: Corrections lost - local variable has corrected value but global doesn't
validate_config_var() {
    local var_name="$1"
    local var_value="${2:-}"
    
    # ... validation steps that correct var_value ...
    
    # Bug: Corrected value never persisted to global variable
    return 0
}
```

**Key Points:**
- When validation functions correct or transform values, always persist the corrected value to global state
- Don't assume that intermediate validation steps will persist corrections
- Explicitly update globals at the end of the validation chain
- Ensures consistency between local and global variables

### Pattern: Handling State Information Across Function Boundaries

**When to Use:** When functions need state information that was already checked by a caller or another function

**Pattern:**
```bash
# ✅ GOOD: Pass state explicitly when needed for accurate behavior
check_ping_optional() {
    local primary_check_passed="$1"
    local external_peer_ip="$2"
    local internal_peer_ip="${3:-}"
    local location_name="${4:-}"

    # Check SA existence directly to ensure accurate messages
    # DESIGN NOTE: We check SA existence here rather than reusing primary_check_passed because:
    # 1. primary_check_passed=0 can mean "no SA" OR "SA exists but validation failed"
    # 2. We need accurate SA status for logging messages to avoid contradictions
    # 3. This ensures messages reflect actual SA state, not inferred state
    # Performance: This adds one additional SA check per cycle (~5-10ms on UDM),
    # which is acceptable for monitoring use case (runs every 30-60 seconds).
    local sa_exists=0
    if check_ipsec_phase2 "$external_peer_ip" 2>/dev/null; then
        sa_exists=1
    fi

    # Pass explicit state to downstream function
    check_ping_if_enabled "$sa_exists" "$ping_ip" "" "$location_name"
    return 0
}

# ✅ GOOD: Accept explicit state parameter when available
check_ping_if_enabled() {
    local sa_exists="$1"  # Explicit state passed from caller
    local ping_target="$2"
    # ... use sa_exists for accurate logging ...
}

# ❌ BAD: Infer state from ambiguous return value
check_ping_if_enabled() {
    local primary_check_passed="$1"  # Ambiguous: could mean "no SA" or "SA exists but failed validation"
    # ... incorrect assumption leads to contradictory log messages ...
}
```

**When to Pass State Explicitly:**
- **When state is needed for accurate behavior:** If the function's behavior (especially logging) depends on accurate state information
- **When return values are ambiguous:** If a return value can mean multiple things (e.g., `primary_check_passed=0` could mean "no SA" or "SA exists but validation failed")
- **When state is expensive to check:** If checking state is expensive and you already have the information
- **When state changes are unlikely:** If state is unlikely to change between function calls in the same execution cycle

**When Duplicate Checks Are Acceptable:**
- **When performance impact is minimal:** If the check is fast (~5-10ms) and the script runs infrequently (every 30-60 seconds)
- **When clarity is more important:** If passing state explicitly would require significant refactoring or make code less clear
- **When state can change:** If state can legitimately change between checks and you need the current state
- **When checks are idempotent:** If the check operation is safe to repeat and doesn't have side effects

**Performance vs. Clarity Trade-offs:**
- **Prefer clarity when:** Performance impact is minimal (< 10ms), script runs infrequently, or refactoring would be complex
- **Prefer performance when:** Checks are expensive (> 50ms), script runs frequently, or state is unlikely to change
- **Document the decision:** Always add comments explaining why duplicate checks are acceptable, including:
  - Why state isn't passed explicitly
  - Performance characteristics of the duplicate check
  - Future optimization path if applicable

**Key Points:**
- Explicit state passing is preferred when it improves accuracy and clarity
- Duplicate checks are acceptable when performance impact is minimal and clarity is improved
- Always document the design decision when choosing duplicate checks over explicit state passing
- Consider future refactoring opportunities to eliminate duplicate checks if they become a performance issue
- Balance between DRY principle and code clarity - sometimes a small duplicate check is better than complex state passing

**Related Patterns:**
- See `Pattern: Always Re-Check Critical State Instead of Relying on Cached Values` for when to re-check vs. use cached state
- See `analyze/CODE_REVIEW_SA_CHECK_FIX.md` for a detailed example of this pattern in practice
- See `analyze/ARCHITECTURE_REVIEW_SA_CHECK.md` for architectural analysis of state passing vs. re-checking

---

## Validation Patterns

### Pattern: Use Validation Functions Instead of Inline Regex

**When to Use:** Always when validating input (IPs, timestamps, etc.)

**Pattern:**
```bash
# ✅ GOOD: Use validation function
if validate_ipv4 "$target_ip"; then
    # IPv4 handling
fi

# ❌ BAD: Inline regex (incomplete validation)
if [[ "$target_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    # IPv4 handling (but accepts invalid octets like 999)
fi
```

**Key Points:**
- Always use existing validation functions instead of inline regex patterns
- Validation functions provide consistent validation logic
- Include proper range checks (not just format matching)
- Handle edge cases (empty strings, etc.)
- Make maintenance easier (single source of truth)
- More secure (proper validation prevents injection attacks)

**Available Validation Functions:**
- `validate_ipv4()` - Validates IPv4 addresses with octet range checks
- `validate_ip_address()` - Validates IPv4 or IPv6 addresses
- `validate_timestamp()` - Validates Unix timestamps (0 to year 2100)
- `validate_state_file()` - Validates state file format (integer, timestamp, timestamp_list)

### Pattern: Use Supplementary Diagnostics to Reduce False Positives

**When to Use:** When primary validation logic may produce false positives in edge cases, and supplementary diagnostics can help distinguish between valid and invalid states

**Pattern:**
```bash
# ✅ GOOD: Use supplementary diagnostics to reduce false positives
if [[ "$current_bytes" -eq 0 ]]; then
    if [[ "$last_bytes" -eq 0 ]]; then
        # First check with zero bytes - may be idle or broken
        # Use ping check as supplementary diagnostic to distinguish
        if [[ -n "$internal_peer_ip" ]] && [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
            local local_ip
            local_ip=$(get_local_ip_for_ping)
            if check_ping_connectivity "$internal_peer_ip" "$local_ip"; then
                # Ping succeeds - VPN is healthy but idle (newly established or idle)
                set_peer_state_non_critical "$location_name" "$peer_ip" "last_bytes" "$current_bytes"
                set_peer_state_non_critical "$location_name" "$peer_ip" "idle_detected" "1"
                log_message "INFO" "$location_name" "VPN OK: SA exists, bytes=0 (first check, idle but healthy, ping check passed)"
                return 0
            else
                # Ping fails - VPN is likely broken
                if [[ -n "$location_name" ]]; then
                    handle_error "WARNING" "$location_name" "VPN suspect: SA exists but bytes=0 (first check, ping check failed) for $location_name ($peer_ip)"
                else
                    handle_error "WARNING" "SYSTEM" "VPN suspect: SA exists but bytes=0 (first check, ping check failed)"
                fi
                return 1
            fi
        else
            # Ping check disabled or internal_peer_ip not provided - fail-safe behavior
            handle_error "WARNING" "VPN suspect: SA exists but bytes=0 (first check, may be idle, ping check disabled)"
            return 1
        fi
    else
        # Bytes dropped to zero after previously having traffic - likely broken
        handle_error "WARNING" "VPN suspect: SA exists but bytes dropped to 0 (was $last_bytes)"
        return 1
    fi
fi

# ❌ BAD: Fail immediately without supplementary diagnostics
if [[ "$current_bytes" -eq 0 ]]; then
    if [[ "$last_bytes" -eq 0 ]]; then
        # First check with zero bytes - fails immediately (false positive for idle VPNs)
        handle_error "WARNING" "VPN suspect: SA exists but bytes=0 (first check, may be idle)"
        return 1  # ← False positive for newly established idle VPNs
    fi
fi
```

**Key Points:**
- Use supplementary diagnostics (like ping checks) when primary validation may produce false positives
- Maintain fail-safe behavior: if supplementary diagnostics are unavailable, default to conservative (fail-safe) behavior
- Only use supplementary diagnostics when they provide meaningful additional information
- Log the diagnostic result clearly to help with troubleshooting

**XFRM Output Format Handling:**
- UDM OS uses `ip -s xfrm state` format where byte counters appear as `  39492(bytes)` on a separate line
- Always try `ip -s xfrm state` first (provides more detail), fall back to `ip xfrm state` if needed
- If xfrm command errors or returns empty but `ipsec status` shows a connection, log the diagnostic and continue; do not assume recovery until SAs appear in xfrm state
- Increase context lines when parsing to ensure `lifetime current:` section is captured (appears after `lifetime config:`)
- Handle both formats:
  - Single-line: `lifetime current: 123456 bytes, 789 packets`
  - Multi-line (UDM OS): `lifetime current:` followed by `  39492(bytes), 609(packets)` on next line
- When byte counter extraction fails but SA exists, fall back to ping check if enabled (treats as "idle but healthy")
- Distinguish between "uncertain but likely healthy" (idle state) and "definitely broken" states
- Update state appropriately based on diagnostic results (e.g., mark as idle but healthy)

**Real-World Example:**
In `check_byte_counters()` (`lib/detection.sh`), the first check with zero bytes could indicate either:
- A newly established VPN that hasn't passed traffic yet (healthy but idle)
- A broken VPN tunnel (unhealthy)

Using ping check as a supplementary diagnostic helps distinguish between these cases:
- Ping succeeds → VPN is healthy but idle → Pass check, mark as idle
- Ping fails → VPN is likely broken → Fail check
- Ping check unavailable → Fail-safe behavior → Fail check (conservative)

**Related Patterns:**
- See ADR-0014 for ping check design rationale
- See "Optional-Feature" pattern for handling optional diagnostics
- See "Fail-Safe Behavior" in error handling patterns

---

## Function Documentation Patterns

### Pattern: Comprehensive Function Documentation

**When to Use:** All functions (required by ADR-0007)

**Pattern:**
```bash
# Check if VPN peer is active
#
# Verifies VPN tunnel health by checking IPsec Security Association state.
# Uses multiple detection methods with automatic fallback:
#   - Primary: ip xfrm state (SA state and byte counters)
#   - Fallback: ipsec status (if xfrm unavailable)
#   - Optional: Ping connectivity check (if enabled)
#
# Arguments:
#   $1: Peer IP address (external/public IP of remote VPN gateway)
#
# Returns:
#   0: VPN is healthy (SA exists, bytes increasing or non-zero)
#   1: VPN check failed (no SA found or bytes not increasing)
#
# Side effects:
#   - Creates/updates per-peer last_bytes file if byte counters found
#   - Logs debug/warning messages about VPN state
#
# Examples:
#   if check_vpn_status "203.0.113.1"; then
#       echo "VPN is healthy"
#   fi
#
# Note:
#   Requires validate_ip_address, sanitize_peer_ip, log_message, STATE_DIR,
#   ENABLE_PING_CHECK to be set.
#   Automatically detects available tools (xfrm, ipsec) and uses
#   appropriate fallbacks for compatibility across different UDM configurations.
check_vpn_status() {
	local peer_ip="$1"
	# ... implementation ...
}
```

**Required Sections:**
- **Purpose/Description**: What the function does and how it works
- **Arguments**: Parameter descriptions with types and requirements
- **Returns**: Exit codes, return values, and what they mean
- **Side Effects**: File operations, logging, state changes, global variable modifications
- **Examples**: Usage examples for complex functions
- **Notes**: Dependencies, requirements, warnings, implementation details

**Key Points:**
- All functions must have documentation blocks before their definition
- Documentation must include required sections: Arguments, Returns
- Optional but recommended: Side effects, Examples, Notes
- Use consistent format across all functions
- Documentation is enforced by `scripts/check-documentation.sh` pre-commit hook
- The documentation checker shows all errors at once (not just the first error) for better developer experience
- Fallback functions in library files (used when primary libraries fail to load) must also be documented
- Nested functions (defined inside other functions) must be documented as they're part of the public API

---

## Function Design Patterns

### Pattern: Extract Helper Functions for Complexity Reduction

**When to Use:** When a function becomes too complex (high cyclomatic complexity, deep nesting, multiple responsibilities) and extracting helper functions would improve readability and maintainability, even if the helpers are only used once.

**Pattern:**
```bash
# ✅ GOOD: Extract helper functions to reduce complexity
detect_failure_type() {
	local external_peer_ip="$1"
	local internal_peer_ip="${2:-}"
	local location_name="$3"
	local primary_check_passed="$4"
	local xfrm_output="${5:-}"

	# Use helper functions for complex logic
	if check_sa_existence_for_failure_type "$external_peer_ip" "$primary_check_passed"; then
		ipsec_phase2_up=1
	fi

	if check_rekey_for_failure_type "$current_spi" "$external_peer_ip" "$location_name"; then
		echo "rekey"
		return 0
	fi

	if routing_flags=$(check_routing_issue_for_failure_type "$current_bytes" "$location_name" "$external_peer_ip" "$internal_peer_ip"); then
		has_routing_issue=1
	fi

	diagnostic_msg=$(build_failure_diagnostic_message "$xfrm_output" "$byte_counters_available" "$current_bytes" "$last_bytes" "$internal_peer_ip" "$ping_checked" "$ping_failed")
	# ... rest of function ...
}

# Helper functions (each has single responsibility)
check_sa_existence_for_failure_type() {
	# ... focused logic for SA existence checking ...
}

check_rekey_for_failure_type() {
	# ... focused logic for rekey detection ...
}

check_routing_issue_for_failure_type() {
	# ... focused logic for routing issue detection ...
}

build_failure_diagnostic_message() {
	# ... focused logic for diagnostic message building ...
}
```

**Key Points:**
- **Extract even for single-use functions** when they significantly reduce complexity
- **Benefits**: Reduced cyclomatic complexity, improved readability, easier maintenance, better testability
- **When to extract**: Function exceeds ~10 cyclomatic complexity, has deep nesting (4+ levels), or handles multiple distinct responsibilities
- **Naming**: Use descriptive names that clearly indicate the helper's purpose
- **Documentation**: All helper functions must be documented (see Function Documentation Patterns)
- **Trade-off**: Slight increase in function count is acceptable when complexity reduction is significant

**Example from Codebase:**
- `detect_failure_type()` was refactored from ~210 lines to 122 lines (42% reduction) by extracting 4 helper functions
- Complexity reduced from ~15 to ~8 (47% reduction)
- Each helper function has a single, clear responsibility

**Related Patterns:**
- See `CODE_REVIEW_failure_analysis_refactoring.md` for detailed refactoring example
- See Function Documentation Patterns for documenting helper functions

### Pattern: Return Code + Stdout for Multiple Return Values

**When to Use:** When a function needs to return both a status (success/failure) and multiple data values, and using namerefs or global variables would be less clear or more complex.

**Pattern:**
```bash
# ✅ GOOD: Return code for status, stdout for data
check_routing_issue_for_failure_type() {
	local current_bytes="$1"
	local location_name="$2"
	local external_peer_ip="$3"
	local internal_peer_ip="${4:-}"
	local byte_counters_available=0
	local ping_checked=0
	local ping_failed=0
	local has_routing_issue=0

	# ... logic to determine routing issue and flags ...

	# Output flags for caller (space-separated)
	echo "$byte_counters_available $ping_checked $ping_failed"

	# Return routing issue status
	if [[ $has_routing_issue -eq 1 ]]; then
		return 0  # Routing issue detected
	fi
	return 1  # No routing issue
}

# Caller usage: Capture both return code and stdout
local routing_flags
local has_routing_issue=0
if routing_flags=$(check_routing_issue_for_failure_type "$current_bytes" "$location_name" "$external_peer_ip" "$internal_peer_ip"); then
	has_routing_issue=1
fi

# Parse stdout into individual variables
local byte_counters_available ping_checked ping_failed
read -r byte_counters_available ping_checked ping_failed <<<"$routing_flags"
```

**Key Points:**
- **Return code**: Use for status/success-failure (0 = success/true, non-zero = failure/false)
- **Stdout**: Use for data values (space-separated for multiple values)
- **Documentation**: Must clearly document both return code meanings and stdout format
- **Parsing**: Use `read -r` with here-string (`<<<`) to parse space-separated values
- **When to use**: When you need both status and data, and the pattern is clearer than alternatives
- **Alternatives**: Consider namerefs for complex data structures, command substitution for single values

**Documentation Requirements:**
```bash
# Check routing issue for failure type
#
# Determines if a routing issue exists and returns diagnostic flags.
#
# Arguments:
#   $1: Current byte counter value
#   $2: Location name
#   $3: External peer IP address
#   $4: Internal peer IP address (optional)
#
# Returns:
#   0: Routing issue detected
#   1: No routing issue detected
#
# Output:
#   Prints space-separated flags to stdout: "byte_counters_available ping_checked ping_failed"
#   Each flag is 0 or 1 (0 = false, 1 = true)
#
# Example:
#   flags=$(check_routing_issue_for_failure_type "$bytes" "$loc" "$ip" "$int_ip")
#   read -r byte_counters_available ping_checked ping_failed <<< "$flags"
check_routing_issue_for_failure_type() {
	# ... implementation ...
}
```

**When NOT to Use:**
- Single return value: Use command substitution with `echo` (no return code needed)
- Complex data structures: Use namerefs for arrays/associative arrays
- When pattern would be confusing: Prefer clearer alternatives

**Example from Codebase:**
- `check_routing_issue_for_failure_type()` uses this pattern to return routing issue status (return code) and diagnostic flags (stdout)
- Caller captures both: `if routing_flags=$(check_routing_issue_for_failure_type ...); then`
- Flags are parsed: `read -r byte_counters_available ping_checked ping_failed <<<"$routing_flags"`

**Related Patterns:**
- See `lib/detection/failure_analysis.sh:check_routing_issue_for_failure_type()` for implementation
- See Function Documentation Patterns for documenting functions using this pattern
- See "Returning Data from Functions" in `BASH_CODING_GUIDE.md` for alternative patterns
- See "Using Namerefs to Return Multiple Values" pattern below for preferred alternative

---

### Pattern: Refactoring Large Functions

**When to Use:** When a function becomes too long (>200-300 lines) or handles multiple distinct responsibilities. Breaking large functions into smaller, focused functions improves maintainability, testability, and readability.

**Pattern:**
```bash
# ❌ BAD: Monolithic function handling multiple responsibilities
delete_stale_sas() {
    # 698 lines of code including:
    # - Parsing state machine
    # - SA validation and filtering  
    # - SA deletion loop
    # - Policy deletion
    # - Error handling throughout
}

# ✅ GOOD: Break into focused functions
delete_stale_sas() {
    local peer_ip="$1"
    local location_name="$2"
    local xfrm_output="$3"
    local deleted_count_var="$4"
    local failed_count_var="$5"
    
    # Parse xfrm output into SA list
    local sa_list=()
    if ! parse_xfrm_output_to_sa_list "$xfrm_output" "$peer_ip" "$location_name" "sa_list"; then
        eval "$deleted_count_var=0"
        eval "$failed_count_var=0"
        return 1
    fi
    
    # Delete SAs
    local deleted_count=0
    local failed_count=0
    delete_sas_from_list "${sa_list[@]}" "$peer_ip" "$location_name" deleted_count failed_count
    local delete_result=$?
    
    # Delete policies
    delete_xfrm_policies "$peer_ip" "$location_name"
    
    # Set output variables
    eval "$deleted_count_var=$deleted_count"
    eval "$failed_count_var=$failed_count"
    
    return 0
}

# Focused parsing function
parse_xfrm_output_to_sa_list() {
    local xfrm_output="$1"
    local peer_ip="$2"
    local location_name="$3"
    local -n sa_list_ref="$4"
    # ... parsing logic ...
}

# Focused deletion function
delete_sas_from_list() {
    # ... deletion logic ...
}

# Focused policy deletion function
delete_xfrm_policies() {
    # ... policy deletion logic ...
}
```

**Key Points:**
- **Single Responsibility**: Each extracted function should have one clear purpose
- **Clear Interfaces**: Use descriptive function names and clear parameter lists
- **Preserve Functionality**: Ensure all original behavior is maintained
- **Use Namerefs for Arrays**: When returning arrays, use namerefs (`local -n`) for clean interfaces
- **Use Namerefs or Eval for Scalars**: For scalar output parameters, use namerefs (preferred) or eval pattern
- **Maintain Error Handling**: Ensure error handling is preserved in refactored code
- **Update Tests**: Verify tests still pass after refactoring (may need mock updates)

**Benefits:**
- Improved maintainability: Easier to understand and modify individual components
- Better testability: Functions can be tested independently
- Reduced cognitive load: Smaller functions are easier to reason about
- Easier code reviews: Changes are isolated to specific functions

**Example from Codebase:**
- `delete_stale_sas()` refactored from 698 lines into 3 focused functions (2026-01-18)
- See `lib/recovery/xfrm_recovery.sh` for implementation

---

### Pattern: Using Namerefs to Return Multiple Values

**When to Use:** When a function needs to return multiple related values and you want to avoid global variables. This is the preferred pattern for returning multiple values (better than global variables or stdout parsing).

**Pattern:**
```bash
# ✅ GOOD: Use nameref associative array to return multiple values
select_recovery_strategy() {
	local peer_ip="${1:-}"
	local tier="${2:-2}"
	local result_ref_name="${3:-}"

	# Validate nameref parameter (must be done before declaring nameref)
	if [[ -z "$result_ref_name" ]]; then
		handle_error "ERROR" "SYSTEM" "select_recovery_strategy: nameref parameter is required" 0
		return 1
	fi

	local -n result="$result_ref_name"

	# Initialize return values in nameref array
	result["strategy"]=""
	result["command"]=""
	result["impact"]=""
	result["available"]=0

	# ... logic to determine strategy ...

	# Set return values
	result["strategy"]="xfrm"
	result["command"]="attempt_xfrm_recovery"
	result["impact"]="per-connection"
	result["available"]=1

	return 0
}

# Caller usage:
declare -A recovery_info
if select_recovery_strategy "$peer_ip" 2 "recovery_info"; then
	echo "Strategy: ${recovery_info[strategy]}"
	echo "Command: ${recovery_info[command]}"
	echo "Impact: ${recovery_info[impact]}"
fi
```

**Key Points:**
- **Validate nameref parameter first**: Check that the parameter is provided before declaring the nameref
- **Declare nameref after validation**: Use `local -n result="$result_ref_name"` after validating the parameter name
- **Initialize array values**: Set default values in the nameref array at the start of the function
- **Use descriptive key names**: Choose clear, consistent key names (e.g., `strategy`, `command`, `impact`)
- **Caller declares array**: The caller must declare the associative array before calling the function
- **Return code for status**: Use return code (0 = success, non-zero = failure) to indicate function success/failure
- **Array values for data**: Use the nameref array to return actual data values

**Documentation Requirements:**
```bash
# Select recovery strategy based on peer IP and tier
#
# Centralizes recovery strategy selection logic, determining the best recovery
# approach based on configuration, peer IP availability, and tier level.
# Returns recovery plan information via nameref associative array.
#
# Arguments:
#   $1: Peer IP address (optional, required for per-connection recovery)
#   $2: Tier level (2 for surgical cleanup, 3 for full restart)
#   $3: Nameref to associative array to store strategy information (required)
#
# Returns:
#   0: Strategy selected successfully
#   1: Invalid tier or no strategy available
#
# Output (via nameref associative array):
#   result["strategy"]: Strategy name ("xfrm", "ipsec_reload", "ipsec_restart", or "unavailable")
#   result["command"]: Command to execute (function name or command string)
#   result["impact"]: Impact description ("per-connection" or "all-tunnels")
#   result["available"]: Whether recovery is available (1) or not (0)
#
# Examples:
#   declare -A recovery_info
#   select_recovery_strategy "203.0.113.1" 2 "recovery_info"
#   # Result: recovery_info["strategy"]="xfrm", recovery_info["command"]="attempt_xfrm_recovery"
#   #         recovery_info["impact"]="per-connection", recovery_info["available"]=1
select_recovery_strategy() {
	# ... implementation ...
}
```

**When to Use This Pattern:**
- ✅ Returning multiple related values (2-5 values)
- ✅ When you want to avoid global variables (improves testability)
- ✅ When values have semantic meaning (better than positional stdout parsing)
- ✅ When you need to return both status and data

**When NOT to Use:**
- ❌ Single return value: Use command substitution with `echo`
- ❌ Very simple cases: Consider return code + stdout if only 2-3 simple values
- ❌ When caller needs to parse stdout anyway: Return code + stdout might be simpler

**Advantages Over Global Variables:**
- ✅ **Better testability**: No global state pollution
- ✅ **Explicit interface**: Clear what values are returned
- ✅ **No side effects**: Function doesn't modify global namespace
- ✅ **Thread-safe**: Each call uses its own array (if that matters)
- ✅ **Follows best practices**: Recommended in `BASH_CODING_GUIDE.md`

**Advantages Over Return Code + Stdout:**
- ✅ **Type safety**: No need to parse strings
- ✅ **Named values**: Keys are self-documenting
- ✅ **No parsing errors**: Can't misparse space-separated values
- ✅ **Extensible**: Easy to add more return values later

**Example from Codebase:**
- `select_recovery_strategy()` in `lib/recovery/recovery_orchestration.sh` uses this pattern to return strategy selection information
- Replaces previous global variable pattern (`RECOVERY_STRATEGY`, `RECOVERY_COMMAND`, etc.)
- All call sites updated to use `declare -A recovery_info` pattern

**Related Patterns:**
- See "Pass Arrays by Reference Using Namerefs" for modifying existing arrays
- See "Return Code + Stdout for Multiple Return Values" for simpler cases
- See "Returning Data from Functions" in `BASH_CODING_GUIDE.md` for overview
- See `lib/recovery/recovery_orchestration.sh:select_recovery_strategy()` for implementation

---

## Configuration Patterns

### Pattern: Extract External IP from LOCATIONS Using Helper Function

**When to Use:** Extracting external IP addresses from the `LOCATIONS` associative array

**Pattern:**
```bash
# ✅ GOOD: Use helper function directly
local external_ip
if external_ip=$(get_location_external_ip "$location_name" 2>/dev/null); then
    # Use external_ip
else
    # Handle error: location not found or extraction failed
    handle_error "WARNING" "$location_name" "Failed to get external IP"
    continue  # or return, depending on context
fi

# ❌ BAD: Direct array access (gets full delimited string)
local external_ip="${LOCATIONS[$location_name]}"
```

**Key Points:**
- The `LOCATIONS` array stores values in format: `"external:IP|internal:IPs"` (not just the IP)
- Always use `get_location_external_ip()` helper function to extract external IP from `LOCATIONS` array
- The helper function is always available when `parse_location_config()` is available (they're in the same module)
- Never assume `LOCATIONS[$name]` contains just the IP address
- Always check the return value of `get_location_external_ip()` and handle errors appropriately
- Direct array access returns the full delimited string, which will cause validation failures

**Related Patterns:**
- See `CODE_REVIEW_LESSONS_LEARNED.md` section 24 for detailed examples and rationale
- See `lib/recovery.sh:verify_ipsec_connections_active()` for correct pattern
- `LOCATIONS` format: `"external:IP|internal:IPs"` (pipe separator)

### Pattern: Schema-Based Configuration Validation

**When to Use:** All configuration loading and validation

**Pattern:**
```bash
# Load configuration with schema validation
load_config() {
    local config_file="$1"
    
    # Set defaults from schema (single source of truth)
    for var_name in "${!CONFIG_SCHEMA[@]}"; do
        local default_value
        default_value=$(get_config_default "$var_name")
        safe_set_variable "$var_name" "$default_value"
    done
    
    # Load and validate config file
    if file_exists_and_readable "$config_file"; then
        safe_parse_config_file "$config_file"
    fi
    
    # Validate all configuration variables
    validate_config
}
```

**Key Points:**
- Default values are defined in `lib/config_schema.sh` as single source of truth
- Schema validation happens during `load_config()`
- Unknown variables are rejected during schema validation
- Type validation and rule validation happen after loading
- Use `get_config_default()` to get defaults from schema
- **LOG_FILE preservation:** `load_config()` preserves `LOG_FILE` if it was set before calling `load_config()` AND it's not the default monitor log filename (`vpn-monitor.log`)
  - Scripts that need custom log files (e.g., `vpn-keepalive.sh`) should set `LOG_FILE` before calling `load_config()`
  - Config file `LOG_FILE` settings can override the default monitor log, but not custom log files
  - Pattern: `LOG_FILE="${LOGS_DIR}/custom-log.log"` before `load_config()` call

### Pattern: Safe Config File Parsing

**When to Use:** Parsing configuration files to prevent code injection

**Pattern:**
```bash
# ✅ GOOD: Use safe_parse_config_file() which validates syntax
if file_exists_and_readable "$config_file"; then
    if ! safe_parse_config_file "$config_file"; then
        handle_config_error "Failed to parse config file"
    fi
fi

# ❌ BAD: Direct source (allows code injection)
source "$config_file"  # Dangerous! Allows arbitrary code execution
```

**Key Points:**
- Never use `source` directly on config files (allows code injection)
- Use `safe_parse_config_file()` which validates syntax and prevents dangerous content
- Validates assignment format, quote pairing, and rejects dangerous patterns
- Uses character-by-character parsing for complex syntax (quotes, escapes)

---

## Logging Patterns

### Pattern: Use Centralized Logging Function

**When to Use:** All logging operations

**Pattern:**
```bash
# Use log_message() for all logging
# System-level messages use "SYSTEM" prefix
log_message "INFO" "SYSTEM" "VPN monitor started"
log_message "WARNING" "SYSTEM" "Config file not found:" "$config_file"
log_message "ERROR" "SYSTEM" "Failed to restart VPN"
log_message "DEBUG" "SYSTEM" "Debug information"  # Only if DEBUG=1

# Location-specific messages use location name prefix
log_message "INFO" "NYC" "VPN monitor started"
log_message "WARNING" "NYC" "VPN check failed for NYC (192.168.1.1)"
log_message "ERROR" "NYC" "Failed to restart VPN for NYC"
```

**Key Points:**
- Use `log_message()` function from `lib/logging.sh` for all logging
- Log levels: INFO, WARNING, ERROR, DEBUG
- Format: `[YYYY-MM-DD HH:MM:SS] [LEVEL] PREFIX: message`
- PREFIX is either a location name (e.g., "NYC") or "SYSTEM" for system-level messages
- All messages must have a prefix (defaults to "SYSTEM" if not provided)
- Log file write errors don't fail the script (resilient logging)
- DEBUG messages only output if DEBUG=1
- INFO messages output to stderr when running interactively (TTY attached)

### Pattern: Logging Errors During Early Initialization

**When to Use:** Error handling when sourcing modules fails during early initialization, before logging infrastructure is fully available

**Pattern:**
```bash
# Helper function to log errors when sourcing modules fails
# Uses log_message if available (from logging.sh), otherwise falls back to echo
# This ensures errors are logged consistently when possible
log_state_error() {
    local message="$1"
    if type log_message >/dev/null 2>&1; then
        # log_message is available - use it (it will handle LOG_FILE not being set)
        log_message "ERROR" "SYSTEM" "$message"
    else
        # Fallback to echo if log_message not available
        echo "Error: $message" >&2
    fi
}

# Use the helper when sourcing modules
source "${MODULE_DIR}/module.sh" 2>/dev/null || {
    log_state_error "Failed to source module.sh"
    exit 1
}
```

**Key Points:**
- Check if `log_message` is available using `type log_message`
- Use `log_message` if available (even if `LOG_FILE` isn't set yet - it will output to stderr)
- Fall back to `echo` if `log_message` isn't available (e.g., during very early initialization)
- This pattern is useful for library files that are sourced early in the initialization sequence
- Ensures errors are logged through centralized logging when possible, but still work if logging isn't available

**Example:**
- `lib/state.sh` uses this pattern when sourcing state module files fails
- When `vpn-monitor.sh` sources `state.sh` (after `logging.sh`), errors are logged via `log_message`
- If `state.sh` is sourced independently (e.g., in tests), it falls back to `echo`

### Pattern: Don't Log Success When Operations Fail

**When to Use:** Functions that check operation success but log success messages

**Pattern:**
```bash
# ✅ GOOD: Return early on error, only log success when operation succeeds
record_restart() {
    local timestamp
    timestamp=$(get_unix_timestamp)
    if ! atomic_write_file "$RESTART_COUNT_FILE" "$timestamp" "append"; then
        handle_error "ERROR" "SYSTEM" "Failed to record restart (file: $RESTART_COUNT_FILE)" 0
        return 0  # Return early - don't log success
    fi
    log_message "INFO" "SYSTEM" "Restart recorded at $timestamp"  # Only logs on success
}

# ❌ BAD: Logs success even when write fails
record_restart() {
    local timestamp
    timestamp=$(get_unix_timestamp)
    if ! atomic_write_file "$RESTART_COUNT_FILE" "$timestamp" "append"; then
        handle_error "ERROR" "SYSTEM" "Failed to record restart" 0
        # Bug: Function continues and logs success below!
    fi
    log_message "INFO" "SYSTEM" "Restart recorded at $timestamp"  # Wrong! Logs even on failure
}
```

**Key Points:**
- Check operation result first
- If operation fails: Log error, return early, do NOT log success
- If operation succeeds: Log success message, continue with normal flow
- Prevents misleading logs that show success when operations actually failed

---

## Module Organization Patterns

### Pattern: Library Module Sourcing

**When to Use:** Sourcing library modules in scripts

**Pattern:**
```bash
# Determine lib directory (where this file is located)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source constants first (no dependencies)
source "${LIB_DIR}/constants.sh" 2>/dev/null || {
    # Fallback if constants.sh not found
    readonly SECONDS_PER_MINUTE=60
}

# Source common utilities (used by other modules)
source "${LIB_DIR}/common.sh" 2>/dev/null || {
    # Fallback if common.sh not found - define minimal versions
    file_exists_and_readable() {
        [[ -f "$1" ]] && [[ -r "$1" ]]
    }
}

# Source other modules as needed
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/state.sh"
source "${LIB_DIR}/config.sh"
```

**Key Points:**
- Determine LIB_DIR using `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`
- Source constants first (no dependencies)
- Source common utilities before other modules
- Provide fallback functions if modules can't be loaded
- Use `2>/dev/null` to suppress errors when sourcing

### Pattern: Module Header Documentation

**When to Use:** All library module files

**Pattern:**
```bash
#!/bin/bash
#
# Module name for UDM VPN Monitor
# Brief description of module purpose
#
# Version: 0.4.3
#
# This module provides [description of functionality]:
# - Function 1: Brief description
# - Function 2: Brief description
# - Function 3: Brief description
#
# All modules should use shared functions from lib/common.sh instead of duplicating logic.
# See ARCHITECTURAL_REVIEW.md section 8.3 for code duplication reduction guidelines.
#
```

**Key Points:**
- Include shebang (`#!/bin/bash`)
- Include module name and purpose
- Include version number
- List key functions provided by module
- Reference shared utilities and guidelines

### Pattern: Module Decomposition for Large Modules

**When to Use:** When a module grows too large (>2000 lines) or has multiple distinct responsibilities that can be separated

**Pattern:**
```bash
# Main module file (lib/recovery.sh) - Compatibility layer
#!/bin/bash
#
# Recovery actions for UDM VPN Monitor
# This file serves as a compatibility layer that sources the decomposed
# recovery modules. All recovery functionality has been moved to lib/recovery/
# subdirectory for better organization and maintainability.
#

# Determine lib directory (where this file is located)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECOVERY_DIR="${LIB_DIR}/recovery"

# Source all recovery modules in dependency order
# shellcheck source=lib/recovery/recovery_verification.sh
source "${RECOVERY_DIR}/recovery_verification.sh" 2>/dev/null || {
    echo "Warning: Failed to source recovery_verification.sh" >&2
}

# shellcheck source=lib/recovery/recovery_state.sh
source "${RECOVERY_DIR}/recovery_state.sh" 2>/dev/null || {
    echo "Warning: Failed to source recovery_state.sh" >&2
}

# ... source other modules ...
```

**Module Structure:**
- **Main module file** (`lib/recovery.sh`): Compatibility layer that sources all submodules
- **Subdirectory** (`lib/recovery/`): Contains focused modules with single responsibilities
- **Module naming**: Use descriptive names that indicate purpose (e.g., `recovery_verification.sh`, `xfrm_recovery.sh`)

**Decomposition Guidelines:**
1. **Single Responsibility**: Each module should have one clear purpose
2. **Dependency Order**: Source modules in dependency order (dependencies first)
3. **Backward Compatibility**: Main module file serves as compatibility layer
4. **Independent Sourceability**: Each module should be independently sourceable (useful for testing)
5. **Fail Fast**: Modules should fail fast if dependencies can't be sourced - this is better than silent degradation

**Module Organization Example:**
```
lib/
├── recovery.sh                    # Compatibility layer (sources all modules)
└── recovery/                      # Recovery module subdirectory
    ├── recovery_verification.sh  # Verification functions
    ├── recovery_state.sh         # State management
    ├── xfrm_recovery.sh          # xfrm-specific recovery
    ├── ipsec_recovery.sh         # IPsec-specific recovery
    └── recovery_orchestration.sh # Orchestration functions
```

**Benefits:**
- **Maintainability**: Smaller, focused files are easier to understand and modify
- **Organization**: Related functionality grouped together
- **Testability**: Modules can be tested independently
- **Backward Compatibility**: Existing code continues to work unchanged
- **Clear Dependencies**: Module structure makes dependencies explicit

**Key Points:**
- Keep main module file as compatibility layer (don't remove it)
- Source modules in dependency order
- Use descriptive module names
- Each module should be independently sourceable
- Modules fail fast if dependencies can't be sourced (better than silent degradation)
- Document module structure in ARCHITECTURE.md

**Note on Standalone Scripts:**
- Scripts in the `scripts/` subdirectory are generally **standalone utility scripts** and do not need the full module sourcing infrastructure
- They should be able to run independently without sourcing `lib/config.sh`, `lib/detection.sh`, etc., unless they specifically need that functionality
- Keep scripts in `scripts/` as standalone as possible - only source what's actually needed
- See "Command Availability Patterns" section for guidance on command checking in standalone scripts

### Pattern: Module-Level Validation for Critical Dependencies

**When to Use:** When a module has critical dependencies (like `STATE_DIR`, `LOGS_DIR`, etc.) that must be set before functions are called, but the module is sourced early in initialization.

**Overview:**
This pattern provides fail-fast detection of missing critical dependencies at module load time, rather than discovering the issue when functions are called. It logs a warning but doesn't exit, allowing the caller to decide how to handle the missing dependency.

**Pattern:**
```bash
# At end of module file, after all functions are defined
# Module-level validation: Check that STATE_DIR is set
# This provides fail-fast detection if STATE_DIR is unset when the module loads.
# In normal operation, STATE_DIR is set during config loading before state modules are sourced.
# This check logs a warning but does not exit, allowing the caller to decide how to handle it.
if [[ -z "${STATE_DIR:-}" ]]; then
    # Use handle_error if available (from logging.sh), otherwise fall back to echo
    # This allows the module to be sourced even if logging isn't fully initialized
    if type handle_error >/dev/null 2>&1; then
        handle_error "WARNING" "SYSTEM" "STATE_DIR is not set when loading state_paths.sh - state path functions may produce invalid paths" 0
    else
        echo "Warning: STATE_DIR is not set when loading state_paths.sh" >&2
    fi
fi
```

**Key Points:**
- **Fail-fast**: Validates at module load time, not when functions are called
- **Non-breaking**: Logs warning but doesn't exit (allows caller to decide)
- **Graceful degradation**: Falls back to `echo` if logging functions not available
- **Documentation**: Document the assumption in function documentation
- **Placement**: Place validation at end of module file, after all functions are defined

**Benefits:**
- Catches issues early (at module load, not runtime)
- More efficient than per-function validation (one check vs many)
- Maintains function contracts (functions can still "always succeed")
- Better architecture (fail-fast at boundary, not defensive everywhere)

**Example Usage:**
```bash
# In lib/state/state_paths.sh
# ... function definitions ...

# Module-level validation: Check that STATE_DIR is set
if [[ -z "${STATE_DIR:-}" ]]; then
    if type handle_error >/dev/null 2>&1; then
        handle_error "WARNING" "SYSTEM" "STATE_DIR is not set when loading state_paths.sh" 0
    else
        echo "Warning: STATE_DIR is not set when loading state_paths.sh" >&2
    fi
fi
```

**Documentation in Functions:**
Functions that depend on the validated variable should document the assumption:
```bash
# Note:
#   Requires STATE_DIR to be set (validated during module load and state initialization).
#   If STATE_DIR is unset, this function will produce invalid absolute paths starting with "/".
#   The module logs a warning if STATE_DIR is unset when state_paths.sh is sourced.
```

**When NOT to Use:**
- Don't use for optional dependencies (only for critical ones)
- Don't use if the dependency is always set before module load (redundant check)
- Don't use if validation would break legitimate use cases (e.g., test environments)

**See Also:**
- `lib/state/state_paths.sh` - Example implementation
- `docs/reviews/state_paths_validation_review.md` - Review of this pattern

---

## Testing Patterns

### Pattern: Use Test Helper Functions

**When to Use:** All test files

**Pattern:**
```bash
#!/usr/bin/env bats
load test_helper  # Loads bats-support, bats-assert, and bats-file

setup() {
    # Setup code runs before each test
    setup_test_vpn_monitor "192.168.1.1"
}

teardown() {
    # Cleanup code runs after each test
    # Automatic cleanup via temp_make/temp_del
}

@test "test description" {
    run bash "$TEST_SCRIPT" --fake
    assert_success
    assert_file_contains "$LOG_FILE" "expected message"
}
```

**Key Points:**
- Always load `test_helper` which loads bats-support, bats-assert, and bats-file
- Use `setup_test_vpn_monitor()` for consistent test environment setup
- Use `temp_make` and `temp_del` for temporary directory management
- Use standard assertion functions from bats-assert and bats-file
- Use `--fake` flag for tests that shouldn't exit on errors

### Pattern: Mock System Commands

**When to Use:** Testing functions that call external commands

**Pattern:**
```bash
@test "test with mocks" {
    setup_test_vpn_monitor "192.168.1.1"
    
    # Create mock commands
    mock_ip_xfrm_state "192.168.1.1" "1000" "0x12345678"
    mock_ping "192.168.1.1" "1"  # Success
    add_mock_to_path
    
    run bash "$TEST_SCRIPT" --fake
    assert_success
    
    remove_mock_from_path
}
```

**Key Points:**
- Create mock commands in `${TEST_DIR}`
- Use helper functions like `mock_ip_xfrm_state()`, `mock_ping()`, etc.
- Call `add_mock_to_path()` after creating mocks
- Call `remove_mock_from_path()` after test
- Mock all commands used by verification functions (not just recovery commands)

### Pattern: Test Fixtures for Common Scenarios

**When to Use:** Tests that need common VPN scenarios

**Pattern:**
```bash
load test_helper
load fixtures/vpn_active
load fixtures/vpn_down

@test "VPN active test" {
    setup_vpn_active_fixture "192.168.1.1" 1000 2000 0x12345678
    run bash "$TEST_SCRIPT" --fake
    assert_success
}

@test "VPN down test" {
    setup_vpn_down_fixture "192.168.1.1" 3
    run bash "$TEST_SCRIPT" --fake
    assert_file_contains "$LOG_FILE" "Tier"
}
```

**Key Points:**
- Load fixtures at top of test file
- Use fixture setup functions for common scenarios
- Multiple fixtures can be loaded in a single test file
- Fixtures reduce duplication and ensure consistent test environments

### Pattern: Testing File Deletion Failures

**When to Use:** Testing functions that delete files and need to verify error handling when deletion fails

**Pattern:**
```bash
# ✅ GOOD: Make parent directory read-only to prevent deletion
local state_file
state_file=$(get_peer_state_file_path "" "$peer_ip" "failure_count")
mkdir -p "$(dirname "$state_file")"
echo "5" >"$state_file"

# Make parent directory read-only (not the file itself)
local state_dir
state_dir=$(dirname "$state_file")
local original_perms
original_perms=$(stat -c "%a" "$state_dir" 2>/dev/null || echo "755")

if chmod 555 "$state_dir" 2>/dev/null; then
    # Try to delete (should fail gracefully)
    run delete_peer_state "" "$peer_ip" "failure_count"
    assert_failure
    
    # Verify file still exists (deletion failed)
    assert_file_exist "$state_file"
    
    # Restore permissions for cleanup
    chmod "$original_perms" "$state_dir" 2>/dev/null || true
else
    skip "Cannot make directory read-only on this system"
fi

# ❌ BAD: Making file read-only doesn't prevent rm -f from deleting it
chmod 444 "$state_file"
run delete_peer_state "" "$peer_ip" "failure_count"
# This will succeed even though file is read-only - rm -f can delete read-only files!
```

**Key Points:**
- To test file deletion failures, make the **parent directory** read-only (chmod 555), not the file itself
- The `rm -f` command can delete read-only files but cannot delete files from a read-only directory
- Always save original permissions and restore them after the test for cleanup
- Handle cases where chmod may fail (e.g., on some systems) by skipping the test gracefully
- Verify that the file still exists after the deletion attempt fails

**Why This Works:**
- `rm -f` can delete read-only files (the `-f` flag forces removal even when files are write-protected)
- However, `rm -f` cannot delete files from a directory that doesn't have write permission
- Making the directory read-only (chmod 555) removes write permission, preventing file deletion
- This provides a reliable way to test deletion failure scenarios in BATS tests

---

## Variable and Naming Patterns

### Pattern: Variable Naming Conventions

**When to Use:** All variable declarations

**Pattern:**
```bash
# Constants and environment variables: UPPERCASE
readonly EXIT_SUCCESS=0
readonly SECONDS_PER_MINUTE=60
LOCATION_NYC_EXTERNAL="203.0.113.1"

# Local variables: lowercase_with_underscores
local peer_ip="$1"
local failure_count=0
local state_file=""

# Function names: lowercase_with_underscores
check_vpn_status() { }
increment_failure() { }
get_peer_state_file_path() { }
```

**Key Points:**
- Use `UPPERCASE` for constants and environment variables
- Use `lowercase_with_underscores` for local variables
- Use `lowercase_with_underscores` for function names
- Use descriptive names: `failure_count` not `fc`
- Use `readonly` for constants that shouldn't change

### Pattern: Safe Variable Assignment

**When to Use:** Setting global variables from untrusted input (config files)

**Pattern:**
```bash
# ✅ GOOD: Use safe_set_variable() to prevent code injection
safe_set_variable "CONFIG_VAR" "$value"

# ❌ BAD: Direct assignment (allows code injection if $value contains commands)
CONFIG_VAR="$value"  # Dangerous if $value contains $(command) or `command`
```

**Key Points:**
- Use `safe_set_variable()` for setting global variables from untrusted input
- Prevents code injection attacks via variable assignment
- Validates variable name format
- Escapes special characters in values

---

## Arithmetic and Calculation Patterns

### Pattern: Validate Timestamp Arithmetic to Prevent Overflow/Underflow

**When to Use:** Any timestamp calculations

**Pattern:**
```bash
# ✅ GOOD: Use safe timestamp arithmetic functions
one_hour_ago=$(safe_timestamp_subtract "$now" "$SECONDS_PER_HOUR" 2>/dev/null || echo "0")
elapsed_time=$(safe_timestamp_diff "$current_time" "$start_time" 2>/dev/null || echo "0")
future_time=$(safe_timestamp_add "$now" "$SECONDS_PER_HOUR" 2>/dev/null || echo "$now")

# ❌ BAD: Direct arithmetic without validation
one_hour_ago=$((now - SECONDS_PER_HOUR))
elapsed_time=$(($(get_unix_timestamp) - verify_start_time))
```

**Key Points:**
- Always use safe timestamp arithmetic functions for any timestamp calculations
- Direct arithmetic can overflow or underflow, especially when subtracting large time periods
- Always provide fallback values (e.g., `|| echo "0"`) when using safe functions
- Validate timestamps before using them in calculations
- Handle negative results gracefully (e.g., clamp to 0)

### Pattern: Validate Arithmetic Operations and Clamp Results

**When to Use:** Calculations that should produce values in a specific range

**Pattern:**
```bash
# ✅ GOOD: Validate inputs and clamp results
local diff=$((value2 - value1))
if [[ $diff -eq 0 ]]; then
    return 1  # Invalid: no change
fi
if [[ $diff -lt 0 ]]; then
    return 1  # Invalid: negative difference (if not expected)
fi

# Calculate result
local result
result=$(awk "BEGIN {printf \"%.0f\", ($diff / $total) * 100}")

# Clamp to expected range (defensive, even if shouldn't be needed)
if [[ $result -lt 0 ]]; then
    result=0
elif [[ $result -gt 100 ]]; then
    result=100
fi
```

**Key Points:**
- Always validate arithmetic inputs before calculations
- Always clamp percentage results to 0-100 range
- Always clamp other bounded values (e.g., timestamps, counts) to valid ranges
- Document edge cases that could cause invalid values
- Use defensive programming: clamp even if calculation "should" be correct

---

## Process Management Patterns

### Pattern: Handle Race Conditions in Process Management

**When to Use:** Process operations that may fail due to race conditions

**Pattern:**
```bash
# ✅ GOOD: Check actual state after operation failure
if kill -TERM "$pid" 2>/dev/null; then
    # Process was running, wait for it to exit
    # ... wait logic ...
else
    # kill -TERM failed - check if process is still running
    if ! kill -0 "$pid" 2>/dev/null; then
        # Process already exited, clean up and succeed
        rm -f "$PIDFILE"
        return 0
    else
        # Process still running but we couldn't send signal - real error
        handle_error "ERROR" "Failed to stop daemon" 1
    fi
fi

# ❌ BAD: Treat all failures as errors
if kill -TERM "$pid" 2>/dev/null; then
    # ... wait logic ...
else
    # Always fails even if process already exited
    handle_error "ERROR" "Failed to stop daemon" 1
fi
```

**Key Points:**
- Process state can change between check and operation (TOCTOU - Time-Of-Check-Time-Of-Use)
- Verify actual state after operation failures before treating as error
- Distinguish between "process already stopped" (success) and "can't stop process" (error)
- Use `kill -0` to verify process existence without side effects

### Pattern: Preserve Exit Codes in Cleanup Functions with EXIT Traps

**When to Use:** Cleanup functions that run via EXIT traps and need to preserve exit codes from main functions

**Pattern:**
```bash
# ✅ GOOD: Preserves exit code from main function
(
    local signal_exit_code=0
    local cleanup_done=0
    
    cleanup_and_exit() {
        # Prevent double cleanup
        if [[ $cleanup_done -eq 1 ]]; then
            exit "${signal_exit_code:-0}"
        fi
        cleanup_done=1
        
        # Close file descriptor first (more critical)
        exec 9>&- 2>/dev/null || true
        
        # Remove lockfile only if we acquired it
        if [[ $lock_acquired -eq 1 ]]; then
            rm -f "$LOCKFILE" 2>/dev/null || true
        fi
        
        exit "${signal_exit_code:-0}"
    }
    
    trap 'signal_exit_code=130; cleanup_and_exit' INT
    trap 'signal_exit_code=143; cleanup_and_exit' TERM
    trap 'cleanup_and_exit' EXIT
    
    # Run main function and capture exit code
    main_func "$@"
    local main_exit_code=$?
    
    # If no signal was received, use main function's exit code
    if [[ ${signal_exit_code:-0} -eq 0 ]]; then
        signal_exit_code=$main_exit_code
    fi
    
    # Explicit cleanup (EXIT trap will also run but cleanup_done prevents double cleanup)
    exec 9>&- 2>/dev/null || true
    if [[ $lock_acquired -eq 1 ]]; then
        rm -f "$LOCKFILE" 2>/dev/null || true
    fi
    cleanup_done=1
)
```

**Key Points:**
- Always capture exit code from main function before cleanup runs
- Use main function's exit code if no signal was received (signal handlers set their own codes)
- Make cleanup functions idempotent with a flag to prevent double cleanup
- Close file descriptors before removing files (more critical operation first)
- Suppress errors from cleanup operations (`2>/dev/null || true`)
- Use `"${signal_exit_code:-0}"` pattern for safe exit code handling
- INT signal should exit with 130, TERM signal should exit with 143
- EXIT trap will run even after explicit cleanup, so idempotency is critical

**Common Mistakes:**
```bash
# ❌ BAD: Loses exit code from main function
cleanup_and_exit() {
    rm -f "$LOCKFILE"
    exit 0  # Always exits with 0, losing main function's exit code!
}
trap 'cleanup_and_exit' EXIT
main_func "$@"
# If main_func returns 1, cleanup runs and exits with 0

# ❌ BAD: No idempotency check - double cleanup possible
cleanup_and_exit() {
    rm -f "$LOCKFILE"  # May try to remove twice!
    exit "$signal_exit_code"
}
trap 'cleanup_and_exit' EXIT
main_func "$@"
# Explicit cleanup + EXIT trap = double cleanup attempt
```

---

## Network Command Timeout Patterns

### Pattern: Wrap Network Commands with Timeout

**When to Use:** Network commands that may hang indefinitely (`ipsec status`, `ping`, `dig`, `nslookup`)

**Pattern:**
```bash
# ✅ GOOD: Wrap network commands with timeout (using helper function)
if check_command_available "timeout"; then
    ipsec_output=$(timeout "$IPSEC_STATUS_TIMEOUT" ipsec status 2>/dev/null)
    ipsec_exit_code=$?
    
    # Detect timeout exit code (124)
    if [[ $ipsec_exit_code -eq 124 ]]; then
        log_message "WARNING" "ipsec status timed out after ${IPSEC_STATUS_TIMEOUT} seconds"
        # Handle timeout appropriately
    fi
else
    # Fallback if timeout command not available (shouldn't happen on UDM)
    ipsec_output=$(ipsec status 2>/dev/null)
fi

# ✅ GOOD: Calculate timeout based on command parameters
# For ping: min(ping_timeout + 1, min(ping_count * ping_timeout + 1, 5))
# This ensures we catch hanging commands quickly while allowing normal pings to complete
local quick_timeout=$((ping_timeout + 1))
local normal_timeout=$((ping_count * ping_timeout + 1))
# Cap normal timeout at 5 seconds for responsiveness
if [[ $normal_timeout -gt 5 ]]; then
    normal_timeout=5
fi
# Use the smaller timeout to catch hangs quickly
local ping_wrapper_timeout
if [[ $quick_timeout -lt $normal_timeout ]]; then
    ping_wrapper_timeout=$quick_timeout
else
    ping_wrapper_timeout=$normal_timeout
fi

if check_command_available "timeout"; then
    ping_result=$(timeout "$ping_wrapper_timeout" ping -c "$ping_count" -W "$ping_timeout" "$target_ip" 2>&1)
    ping_exit_code=$?
    if [[ $ping_exit_code -eq 124 ]]; then
        log_message "WARNING" "ping command timed out after ${ping_wrapper_timeout} seconds"
    fi
fi
```

**Key Points:**
- Wrap potentially hanging network commands with `timeout` command
- Check for `timeout` command availability before using
- Use reasonable timeout values based on expected command duration
- Detect timeout exit code (124) and provide specific error messages
- Fallback: If `timeout` command unavailable, run command without wrapper (shouldn't happen on UDM)
- Calculate timeout dynamically based on command parameters (e.g., ping count * timeout)

**Timeout Constants:**
- `IPSEC_STATUS_TIMEOUT=5` - Timeout for `ipsec status` command (5 seconds)
- `XFRM_RECOVERY_VERIFY_TIMEOUT=30` - Timeout for xfrm recovery verification (30 seconds)
- `LOCKFILE_TIMEOUT=300` - Timeout for lockfile staleness detection (300 seconds)

**Commands That Should Be Wrapped:**
- `ipsec status` - Wrapped with `IPSEC_STATUS_TIMEOUT` (5 seconds)
  - **Helper function**: Use `get_ipsec_status_for_peer()` in `lib/detection.sh` for ipsec status queries
- `ping` commands - Wrapped with calculated timeout based on ping count and timeout
- `dig` and `nslookup` - Wrapped with DNS timeout in network partition checks

**Benefits:**
- Prevents script from hanging indefinitely when network commands hang due to network issues
- Ensures script remains responsive even when network is experiencing issues
- Provides specific error messages for timeout scenarios

---

## Command Availability Patterns

### Pattern: Check Command Availability Before Use

**When to Use:** Before executing commands that may not be available (optional commands, fallback commands)

**Pattern:**
```bash
# ✅ GOOD: Use check_command_available() helper for binary commands
if check_command_available "ipsec"; then
    ipsec_output=$(ipsec status 2>/dev/null)
else
    log_message "WARNING" "ipsec command not available, using fallback"
    # Use fallback method
fi

# ✅ GOOD: Use check_command_available() helper for required commands
if ! check_command_available "ip"; then
    return 1
fi

# ✅ GOOD: Use check_command_or_warn() for optional commands
if ! check_command_or_warn "ping6" "IPv6 ping check enabled"; then
    # Command not available, skip IPv6 ping
    return 0
fi

# ✅ GOOD: Direct command -v is acceptable for checking function availability
# Functions are always in the same shell context, so PATH restrictions don't apply
if command -v parse_location_config >/dev/null 2>&1; then
    config=$(parse_location_config "$location")
    # If parse_location_config is available, other functions from the same module are also available
    external_ip=$(get_location_external_ip "$location_name" 2>/dev/null || echo "")
fi

# ✅ GOOD: Only check one function from a module (others in same module are also available)
# parse_location_config, get_location_external_ip, and get_location_internal_ips are all in location_parsing.sh
if command -v parse_location_config >/dev/null 2>&1; then
    external_ip=$(get_location_external_ip "$location_name" 2>/dev/null || echo "")
    internal_ips=$(get_location_internal_ips "$location_name" 2>/dev/null || echo "")
fi

# ❌ BAD: Redundant checks for functions from the same module
if command -v get_location_external_ip >/dev/null 2>&1 && command -v parse_location_config >/dev/null 2>&1; then
    # Unnecessary: if parse_location_config is available, get_location_external_ip is also available
fi

# ❌ BAD: Direct command -v for binary commands in cron/systemd contexts
if command -v timeout >/dev/null 2>&1; then
    timeout 5 ping ...
fi

# ❌ BAD: Execute command without checking availability
ipsec_output=$(ipsec status 2>/dev/null)  # May fail if ipsec not available
```

**Key Points:**
- Always check command availability before executing optional commands
- **For binary commands in cron/systemd contexts: Use helper functions (`check_command_available()` or `check_command_or_warn()`)**
- **For function availability checks: Direct `command -v` is acceptable** (functions are in same shell context, PATH restrictions don't apply)
- **When checking functions from the same module: Only check one representative function** (if one function from a module is available, all functions from that module are available)
  - Example: `parse_location_config`, `get_location_external_ip`, and `get_location_internal_ips` are all in `lib/config/location_parsing.sh`
  - If `parse_location_config` is available, the other functions are also available - no need to check each one
- Use `check_command_available()` helper for silent checks
- Use `check_command_or_warn()` for optional commands that should log warnings
- Provide fallback mechanisms when commands are unavailable

**Command Checking Functions:**
- `check_command_available()` - Silent check, returns 0/1
  - Uses `command -v` first (POSIX compliant)
  - Falls back to checking common system directories (`/usr/sbin`, `/usr/bin`, `/sbin`, `/bin`) if PATH is restricted
  - Handles cron/systemd environments where PATH may not include `/usr/sbin` (common on UDM OS)
  - **Use this for all binary command checks in code that runs via cron/systemd**
- `check_command_or_warn()` - Checks and logs warning if unavailable
  - Wraps `check_command_available()` and adds logging
  - **Use this for optional binary commands that should log warnings when unavailable**
- `get_command_path()` - Returns full path to command, or command name if not found
  - Uses same fallback logic as `check_command_available()` but returns path
  - Returns command name if path cannot be determined (fallback to PATH at execution time)
  - **Use this when you need the full path for reliable command execution in PATH-restricted environments**
  - Example: `ipsec_cmd=$(get_command_path "ipsec"); "$ipsec_cmd" reload`
- `command -v` - POSIX compliant command availability check
  - **Acceptable for checking function availability** (functions are in same shell context)
  - **Avoid direct usage for binary commands in cron/systemd contexts** - use helper functions instead

**Important Note on PATH Restrictions:**
- Scripts run by cron or systemd often have restricted PATH that excludes `/usr/sbin`
- This is a known issue on UDM OS and other Linux systems
- `command -v` may fail to find binary commands even when they exist in system directories
- `check_command_available()` handles this by checking system directories directly when `command -v` fails
- **Always use `check_command_available()` or `check_command_or_warn()` for binary commands in code that runs via cron or systemd**
- Direct `command -v` usage for binary commands should be avoided in files like `vpn-monitor.sh`, `vpn-keepalive.sh`, `lib/detection.sh`, `lib/recovery.sh`
- **Exception: `command -v` is acceptable for checking function availability** since functions are always in the same shell context

**When to Use Each Pattern:**
- **Binary commands (ping, ip, ipsec, timeout, etc.)**: Use `check_command_available()` or `check_command_or_warn()`
- **Command execution in PATH-restricted environments**: Use `get_command_path()` to get full path before executing
  - Example: `ipsec_cmd=$(get_command_path "ipsec"); "$ipsec_cmd" reload`
  - Ensures commands execute reliably even when PATH doesn't include system directories
- **Function availability (parse_location_config, get_location_external_ip, etc.)**: Direct `command -v` is acceptable
- **Required commands**: Use `check_command_available()` and return early if unavailable
- **Optional commands**: Use `check_command_or_warn()` and handle gracefully if unavailable

**Standalone Scripts in `scripts/` Subdirectory:**
- Scripts in the `scripts/` subdirectory are generally **standalone utility scripts** that should be able to run independently
- They **do not need** the full sourcing infrastructure (sourcing `lib/config.sh`, `lib/detection.sh`, etc.) unless they specifically need that functionality
- They can use simpler patterns:
  - Direct `command -v` for binary commands is acceptable (scripts run in normal shell context, not cron/systemd)
  - Direct `command -v` for function availability checks is acceptable
  - No need for `check_command_available()` helper unless the script specifically runs in PATH-restricted environments
- **Exception**: If a script in `scripts/` is called by the main program or needs library functionality, it should source the appropriate modules
- **Guideline**: Keep scripts in `scripts/` as standalone as possible - only source what's actually needed

### Pattern: Fallback Command Execution

**When to Use:** Commands with multiple variants or fallback options

**Pattern:**
```bash
# ✅ GOOD: Try primary command, fallback to alternative (using helper functions)
local ping_cmd="ping"
if check_command_available "ping6" && [[ "$ip_version" == "6" ]]; then
    ping_cmd="ping6"
elif check_command_available "ping"; then
    ping_cmd="ping"
else
    log_message "WARNING" "Neither ping nor ping6 available"
    return 1
fi

# Execute with selected command
"$ping_cmd" -c 3 "$target_ip"
```

**Key Points:**
- Try primary command first
- Fallback to alternative if primary unavailable
- Log warnings when fallbacks are used
- Return error if no commands available

---

## String Parsing and Manipulation Patterns

### Pattern: Extract Duplicate Awk Scripts to Helper Functions

**When to Use:** When the same awk script appears multiple times in a function or across functions

**Pattern:**
```bash
# ✅ GOOD: Extract duplicate awk script to helper function
deduplicate_sa_blocks() {
    awk '
        BEGIN { in_block = 0 }
        /^src[[:space:]]+/ {
            header = $0
            if (header in seen_headers) {
                in_block = 0
                next
            }
            seen_headers[header] = 1
            in_block = 1
            print
            next
        }
        in_block == 1 {
            print
        }
    '
}

# Use helper function in multiple places
if [[ -n "$forward_output" ]] && [[ -n "$reverse_output" ]]; then
    local combined="${forward_output}"$'\n'"${reverse_output}"
    xfrm_output=$(echo "$combined" | deduplicate_sa_blocks)
fi

# ❌ BAD: Duplicate awk script in multiple places
if [[ -n "$forward_output" ]] && [[ -n "$reverse_output" ]]; then
    local combined="${forward_output}"$'\n'"${reverse_output}"
    xfrm_output=$(echo "$combined" | awk '
        BEGIN { in_block = 0 }
        /^src[[:space:]]+/ {
            # ... duplicate logic ...
        }
    ')
fi
# Later in same function:
if [[ -n "$forward_output" ]] && [[ -n "$reverse_output" ]]; then
    echo "$combined" | awk '
        BEGIN { in_block = 0 }
        /^src[[:space:]]+/ {
            # ... same logic duplicated ...
        }
    '
fi
```

**Key Points:**
- When awk scripts are duplicated, extract to a helper function
- Helper functions can be defined in the same file or in a shared module
- Use descriptive function names that explain what the awk script does
- If the awk script is only used in one function, consider using a here-document variable
- **Note:** Not critical for production - code works correctly even with duplication, but refactoring improves maintainability

**Related Patterns:**
- See `CODE_REVIEW_LESSONS_LEARNED.md` section 6 for code duplication detection patterns
- See TODO.md item 3 for current duplication in `get_xfrm_state_for_peer()`

### Pattern: Character-by-Character Parsing for Complex Syntax

**When to Use:** Parsing complex syntax with quotes, escapes, nested structures, state-dependent rules

**Pattern:**
```bash
# ✅ GOOD: Character-by-character parsing with state tracking
parse_quoted_value() {
    local assignment="$1"
    local in_quotes=false
    local quote_char=""
    local escaped=false
    local quote_closed=false
    local result=""
    local i=0
    local len=${#assignment}
    
    # Track state as we parse character by character
    while [[ $i -lt $len ]]; do
        local char="${assignment:$i:1}"
        
        if [[ "$escaped" == true ]]; then
            # Handle escaped characters based on quote type
            escaped=false
        elif [[ "$char" == "\\" ]]; then
            escaped=true
        elif [[ "$char" == "$quote_char" ]]; then
            quote_closed=true
            break
        fi
        # ... more state tracking
        i=$((i + 1))
    done
    
    # Validate final state
    if [[ "$in_quotes" == true ]] && [[ "$quote_closed" == false ]]; then
        return 1  # Unclosed quote
    fi
}

# ❌ BAD: Regex-based parsing (fails on edge cases)
parse_quoted_value() {
    if [[ "$assignment" =~ ^\"(.*)\"$ ]]; then
        # This fails on escaped quotes, trailing backslashes, etc.
        result="${BASH_REMATCH[1]}"
    fi
}
```

**Key Points:**
- Use character-by-character parsing for complex syntax (quotes, escapes, nested structures)
- Track state explicitly with boolean flags (`in_quotes`, `escaped`, `quote_closed`)
- Handle edge cases at boundaries (trailing backslashes, unclosed quotes)
- Different rules for different contexts (single quotes vs double quotes)
- Validate final state before returning success

**When to Use Character-by-Character Parsing:**
- Configuration file parsing with quotes and escapes
- Parsing strings with state-dependent rules
- Handling escape sequences that affect meaning of subsequent characters
- Parsing syntax where regex struggles (nested structures, context-dependent rules)

### Pattern: String Trimming and Normalization

**When to Use:** Processing user input, configuration values, file content

**Pattern:**
```bash
# ✅ GOOD: Trim leading and trailing whitespace
line="${line#"${line%%[![:space:]]*}"}"  # Remove leading spaces
line="${line%"${line##*[![:space:]]}"}"  # Remove trailing spaces

# ✅ GOOD: Remove trailing comments
assignment="${assignment%%#*}"  # Remove everything after first #

# ✅ GOOD: Normalize whitespace before processing
if [[ -z "${line// /}" ]]; then
    continue  # Skip empty lines (after removing all spaces)
fi
```

**Key Points:**
- Always trim leading/trailing whitespace from user input

### Pattern: Bash Pattern Substitution with Special Characters

**When to Use:** Escaping special characters in strings for use in regex patterns or sed commands

**Pattern:**
```bash
# ✅ GOOD: Use character classes [*] and [?] to match literal characters
escaped_location="${location//[*]/\\*}"   # Escape literal *
escaped_location="${escaped_location//[?]/\\?}"  # Escape literal ?

# ❌ BAD: Using * or ? directly matches any characters (glob pattern)
escaped_location="${location//*/\\*}"     # BUG: Matches entire string!
escaped_location="${escaped_location//?/\\?}"  # BUG: Matches every character!
```

**Why This Matters:**
- In bash pattern substitution `${var//pattern/replacement}`, `*` and `?` are glob patterns
- `*` matches any sequence of characters (including empty)
- `?` matches any single character
- Using them directly will replace the entire string or every character, not just literal `*` or `?`
- Character classes `[*]` and `[?]` match literal characters

**Example Bug:**
```bash
location="AUSTIN"
# Wrong approach:
escaped="${location//*/\\*}"  # Result: "\*" (entire string replaced!)
# Correct approach:
escaped="${location//[*]/\\*}"  # Result: "AUSTIN" (no * to escape)
```

**Key Points:**
- Always use character classes `[*]` and `[?]` when escaping literal `*` or `?` characters
- This applies to all bash pattern substitution operations: `${var//pattern/repl}`, `${var/#pattern/repl}`, `${var/%pattern/repl}`
- Other special regex characters (`+`, `.`, `^`, `$`, `[`, `]`, `|`, `(`, `)`) should be escaped normally
- Test escaping with strings that don't contain the special character to verify it doesn't break
- Remove comments before processing (everything after `#`)
- Normalize whitespace for consistent processing
- Handle empty strings after trimming

### Pattern: Extract Values Using Regex

**When to Use:** Parsing structured text (log entries, command output, configuration)

**Pattern:**
```bash
# ✅ GOOD: Extract values using regex with BASH_REMATCH
if [[ "$line" =~ ^\[([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2})\]\ \[([A-Z]+)\]\ (.+)$ ]]; then
    local timestamp="${BASH_REMATCH[1]}"
    local level="${BASH_REMATCH[2]}"
    local message="${BASH_REMATCH[3]}"
fi

# ✅ GOOD: Extract variable name from assignment
if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    local var_name="${BASH_REMATCH[1]}"
    local assignment="${BASH_REMATCH[2]}"
fi

# ✅ GOOD: Safe access with set -u (use default empty string)
if [[ "$line" =~ ^src[[:space:]]+([0-9.]+)[[:space:]]+dst[[:space:]]+([0-9.]+) ]]; then
    # Safe access prevents "unbound variable" errors with set -u
    current_src="${BASH_REMATCH[1]:-}"
    current_dst="${BASH_REMATCH[2]:-}"
fi
```

**Key Points:**
- Use regex with capture groups for structured text parsing
- Access captured groups via `BASH_REMATCH[1]`, `BASH_REMATCH[2]`, etc.
- **Important**: When `set -u` (nounset) is enabled, use `${BASH_REMATCH[n]:-}` to provide default empty string
- This prevents "unbound variable" errors if regex doesn't match or capture group is empty
- Validate regex match succeeded before accessing `BASH_REMATCH`
- Use anchors (`^`, `$`) for precise matching

---

## Loop and Iteration Patterns

### Pattern: Read File Line by Line

**When to Use:** Processing files line by line (config files, log files, data files)

**Pattern:**
```bash
# ✅ GOOD: Read file line by line with proper handling of files without trailing newline
while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines
    [[ -z "$line" ]] && continue
    
    # Skip comment lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Process line
    process_line "$line"
done < "$file"

# ❌ BAD: Missing || [[ -n "$line"]] - loses last line if no trailing newline
while IFS= read -r line; do
    process_line "$line"
done < "$file"
```

**Key Points:**
- Always use `|| [[ -n "$line" ]]` to handle files without trailing newline
- Use `IFS= read -r` to preserve whitespace and prevent backslash interpretation
- Skip empty lines and comments early in loop
- Process each line within the loop body

### Pattern: Iterate Over Arrays

**When to Use:** Processing arrays of values (IPs, locations, test cases)

**Pattern:**
```bash
# ✅ GOOD: Iterate over array elements
for peer_ip in "${peer_ips[@]}"; do
    check_vpn_status "$peer_ip"
done

# ✅ GOOD: Iterate with index
for i in "${!array[@]}"; do
    echo "Index: $i, Value: ${array[$i]}"
done

# ✅ GOOD: Iterate over strategy entries with parsing
for strategy_entry in "${strategies[@]}"; do
    IFS=':' read -r strategy_name strategy_command strategy_impact <<<"$strategy_entry"
    # Process parsed values
done
```

**Key Points:**
- Use `"${array[@]}"` to iterate over array elements
- Use `"${!array[@]}"` to iterate over array indices
- Use `IFS` to split delimited strings within loops
- Quote array expansions to handle spaces correctly

### Pattern: Process Until Condition Met

**When to Use:** Loops that continue until a condition is met (timeouts, retries, state changes)

**Pattern:**
```bash
# ✅ GOOD: Process until condition met with timeout (using safe timestamp arithmetic)
local start_time=$(get_unix_timestamp)
local timeout=30
while true; do
    local elapsed
    elapsed=$(safe_timestamp_diff "$(get_unix_timestamp)" "$start_time" 2>/dev/null || echo "0")
    if [[ $elapsed -ge $timeout ]]; then
        break  # Timeout reached, exit loop
    fi
    if check_condition; then
        break  # Condition met, exit loop
    fi
    sleep 1
done

# ✅ GOOD: Retry loop with max attempts
local max_attempts=3
local attempt=0
while [[ $attempt -lt $max_attempts ]]; do
    if perform_operation; then
        break  # Success, exit loop
    fi
    attempt=$((attempt + 1))
    sleep 1
done

# ❌ BAD: Direct timestamp arithmetic in loop condition (violates safe timestamp arithmetic pattern)
local start_time=$(get_unix_timestamp)
local timeout=30
while [[ $(($(get_unix_timestamp) - start_time)) -lt $timeout ]]; do
    # Direct arithmetic can underflow, causing infinite loops
    if check_condition; then
        break
    fi
    sleep 1
done
```

**Key Points:**
- Use `while` loops for condition-based iteration
- Include timeout or max attempts to prevent infinite loops
- Use `break` to exit loop early when condition met
- Use `sleep` to prevent busy-waiting
- **Always use safe timestamp arithmetic functions** (`safe_timestamp_diff()`) for timestamp calculations in loops
- Direct timestamp arithmetic can underflow, causing infinite loops or incorrect behavior

---

## Associative Array Patterns

### Pattern: Pass Arrays by Reference Using Namerefs

**When to Use:** Functions that need to modify existing associative arrays or populate arrays with data

**Note:** For returning multiple values from functions (as an alternative to global variables), see "Using Namerefs to Return Multiple Values" pattern above. This pattern focuses on modifying/populating arrays.

**Pattern:**
```bash
# ✅ GOOD: Use nameref to pass associative array by reference
parse_assignment() {
    local line="$1"
    local line_num="$2"
    local -n result_array="$3"  # Nameref - modifies caller's array
    
    # Set array elements
    result_array["name"]="VAR_NAME"
    result_array["value"]="value"
    
    return 0
}

# Caller usage:
declare -A parse_result
if parse_assignment "VAR=value" 1 "parse_result"; then
    echo "Name: ${parse_result[name]}, Value: ${parse_result[value]}"
fi
```

**Key Points:**
- Use `local -n` to create nameref (reference to caller's array)
- Nameref allows function to modify caller's associative array
- Declare associative array in caller before passing to function
- Use descriptive array names for clarity
- **Important:** Avoid circular references - nameref variable name must differ from the referenced variable name
  - ❌ BAD: `local -n array="$array"` (circular reference error)
  - ✅ GOOD: `local -n array_ref="$array"` (different name prevents circular reference)
- **Important:** When using `set -u`, store reference name in temp variable to avoid circular reference errors with environment variables
  - ❌ BAD: `local -n array_ref="$param_ref"` (may cause circular reference if environment variable conflicts)
  - ✅ GOOD: `local ref_name="$param_ref"; local -n array_ref="$ref_name"` (temp variable prevents conflicts)

### Pattern: Initialize Associative Arrays

**When to Use:** Creating associative arrays for data structures

**Pattern:**
```bash
# ✅ GOOD: Declare associative array before use
declare -A location_vars=()
declare -A seen_vars=()
local -A parse_result=()

# ✅ GOOD: Reset associative array for reuse
parse_result=()  # Clear array before reuse

# ✅ GOOD: Check if key exists before accessing
if [[ -n "${array[key]:-}" ]]; then
    value="${array[key]}"
else
    value="default"
fi
```

**Key Points:**
- Always declare associative arrays before use (`declare -A` or `local -A`)
- Reset arrays with `array=()` for reuse
- Use parameter expansion `${array[key]:-}` to check if key exists
- Initialize empty arrays with `=()` for clarity
- **For arrays populated by sourced files:** See "Pre-Declare Associative Arrays" pattern in Variable Initialization Patterns section

### Pattern: Iterate Over Associative Arrays

**When to Use:** Processing all key-value pairs in associative array

**Pattern:**
```bash
# ✅ GOOD: Iterate over associative array keys
for var_name in "${!CONFIG_SCHEMA[@]}"; do
    local default_value
    default_value=$(get_config_default "$var_name")
    safe_set_variable "$var_name" "$default_value"
done

# ✅ GOOD: Iterate with both key and value
for key in "${!array[@]}"; do
    echo "Key: $key, Value: ${array[$key]}"
done
```

**Key Points:**
- Use `"${!array[@]}"` to get all keys from associative array
- Access values using `"${array[$key]}"`
- Quote expansions to handle spaces correctly
- Use descriptive variable names for keys (`var_name`, `key`, etc.)

---

## Variable Initialization Patterns

### Pattern: Conditional Readonly Variable Initialization

**When to Use:** Constants that may be sourced multiple times or set conditionally

**Pattern:**
```bash
# ✅ GOOD: Check if variable is set before making it readonly
# Prevents "readonly variable already set" errors when sourcing multiple times
[[ -z "${SECONDS_PER_MINUTE:-}" ]] && readonly SECONDS_PER_MINUTE=60
[[ -z "${IPSEC_STATUS_TIMEOUT:-}" ]] && readonly IPSEC_STATUS_TIMEOUT=5

# ✅ GOOD: In constants file, set directly (only sourced once)
readonly EXIT_SUCCESS=0
readonly SECONDS_PER_MINUTE=60

# ❌ BAD: Setting readonly without check (fails if sourced twice)
readonly SECONDS_PER_MINUTE=60  # Error if already set!
```

**Key Points:**
- Use conditional readonly (`[[ -z "${VAR:-}" ]] && readonly VAR=value`) when modules may be sourced multiple times
- Use direct `readonly` in constants files that are only sourced once
- Prevents "readonly variable already set" errors
- Allows modules to have fallback constants if constants.sh isn't available

### Pattern: Default Parameter Values

**When to Use:** Function parameters that have sensible defaults

**Pattern:**
```bash
# ✅ GOOD: Use parameter expansion with defaults
check_lockfile() {
    local lockfile="${1:-$LOCKFILE}"  # Use $1 if provided, else $LOCKFILE
    local timeout="${2:-$LOCKFILE_TIMEOUT_DEFAULT}"  # Use $2 if provided, else default
    # ...
}

# ✅ GOOD: Use defaults for optional parameters
get_peer_state() {
    local location_name="$1"
    local peer_ip="$2"
    local key="$3"
    local default="${4:-0}"  # Default to "0" if not provided
    
    # ...
}

# ❌ BAD: No defaults, requires all parameters
check_lockfile() {
    local lockfile="$1"  # Fails if $1 is empty
    # ...
}
```

**Key Points:**
- Use `${var:-default}` to provide default values for optional parameters
- Use `${var:-$OTHER_VAR}` to fall back to another variable
- Makes functions more flexible and easier to use
- Prevents errors from missing optional parameters

### Pattern: Pre-Declare Associative Arrays to Avoid Unbound Variable Errors

**When to Use:** Associative arrays that are populated by sourced files or conditionally

**Note:** This pattern extends the general "Initialize Associative Arrays" pattern (see Associative Array Patterns section) with specific guidance for arrays populated by sourced files.

**Pattern:**
```bash
# ✅ GOOD: Pre-declare associative array before sourcing schema file
# Prevents unbound variable errors if set -u is enabled
# Also ensures array can be populated correctly by sourced file
declare -gA CONFIG_SCHEMA=()
source "${LIB_DIR}/config_schema.sh"  # Populates CONFIG_SCHEMA

# ✅ GOOD: Use -gA for global arrays when sourcing from within functions
declare -gA CONFIG_SCHEMA=()  # -g ensures global scope

# ❌ BAD: Accessing array without pre-declaration (fails with set -u)
source "${LIB_DIR}/config_schema.sh"  # Sets CONFIG_SCHEMA
# Later access fails if CONFIG_SCHEMA wasn't pre-declared and set -u is enabled
for key in "${!CONFIG_SCHEMA[@]}"; do  # Error: unbound variable

# ❌ BAD: Relying on sourced file to declare and populate array
# Even if schema file does: declare -A CONFIG_SCHEMA=(...)
# This may not work correctly when sourced in certain contexts
source "${LIB_DIR}/config_schema.sh"  # May not populate array correctly
```

**Key Points:**
- Pre-declare associative arrays before they're populated by sourced files
- Use `declare -gA` (not `declare -A`) to ensure global scope when sourcing from within functions
- Prevents "unbound variable" errors when `set -u` is enabled
- **Critical:** Associative arrays must be declared before they can be populated. Even if a sourced file tries to declare and populate an array in one step (`declare -A ARRAY=(...)`), it may not work correctly unless the array is pre-declared in the sourcing context
- Use empty array initialization `=()` for clarity
- **See "Initialize Associative Arrays" pattern** for general associative array initialization guidance

**Example: CONFIG_SCHEMA Pattern**
```bash
# In lib/config.sh - Pre-declare before sourcing schema file
declare -gA CONFIG_SCHEMA=()
if [[ -f "${LIB_DIR}/config_schema.sh" ]] && source "${LIB_DIR}/config_schema.sh" 2>/dev/null; then
    # Schema file populates CONFIG_SCHEMA successfully
    # Without pre-declaration, the array might not be populated correctly
fi
```

**Troubleshooting: CONFIG_SCHEMA Not Populating in Tests**

**Problem:** When sourcing `config.sh` in BATS tests, the `CONFIG_SCHEMA` associative array is not being populated correctly, causing `get_config_schema()` to return "not found" for valid configuration variables.

**Root Cause:** If `config.sh` declares `CONFIG_SCHEMA` as `declare -A CONFIG_SCHEMA=()` (without `-g` flag) before sourcing `config_schema.sh`, and `config.sh` is sourced from within a function (like BATS test functions), this creates a **local** variable that shadows the global `-gA` one created by `config_schema.sh`. Functions like `get_config_schema` then see the empty local variable instead of the populated global one.

**Solution:** Always use `declare -gA CONFIG_SCHEMA=()` (with `-g` flag) to ensure `CONFIG_SCHEMA` is always global, preventing scoping issues when `config.sh` is sourced from within functions.

**Test Pattern:** Tests should use the standard pattern:
```bash
source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true
source "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" 2>/dev/null || true  # Optional but recommended
```

**Key Lesson:** When a test exposes a scoping issue in production code, fix the production code rather than working around it in tests. Using `declare -gA` instead of `declare -A` ensures associative arrays are always global, which is the correct behavior for configuration schemas that need to be accessible from anywhere.

### Pattern: Always Declare Loop Variables as Local

**When to Use:** All loops within bash functions

**Pattern:**
```bash
# ✅ GOOD: Declare loop variable as local before use
verify_ipsec_connections_active() {
    local peer_ips="${1:-}"
    
    if parse_location_config; then
        local external_ips=()
        local location_name  # Declare as local before loop
        for location_name in "${!LOCATIONS[@]}"; do
            # Process location
        done
    fi
}

# ✅ GOOD: Use different variable name when loop variable conflicts with function parameter
full_restart() {
    local peer_ip="${1:-}"
    local location_name="$2"  # Function parameter
    
    # Use different variable name to avoid overwriting parameter
    local iter_location_name
    for iter_location_name in "${!LOCATIONS[@]}"; do
        # Process location using iter_location_name
    done
}

# ❌ BAD: Loop variable not declared as local (can overwrite global variables)
verify_ipsec_connections_active() {
    local peer_ips="${1:-}"
    
    if parse_location_config; then
        local external_ips=()
        # Missing: local location_name
        for location_name in "${!LOCATIONS[@]}"; do  # Overwrites global variable!
            # Process location
        done
    fi
}

# ❌ BAD: Loop variable overwrites function parameter
full_restart() {
    local peer_ip="${1:-}"
    local location_name="$2"  # Function parameter
    
    # Loop variable overwrites the parameter!
    for location_name in "${!LOCATIONS[@]}"; do  # BUG: overwrites parameter
        # Process location
    done
    # location_name is now the last location in LOCATIONS, not the original parameter!
}
```

**Key Points:**
- **Always declare loop variables as `local`** before the loop in bash functions
- Loop variables that aren't declared as `local` can overwrite global variables
- This can affect caller's local variables in unexpected ways
- When a loop variable would conflict with a function parameter, use a different variable name
- Bash doesn't have true lexical scoping - be explicit about variable scoping
- This prevents subtle bugs where loop variables leak into global scope

**Real-World Example:**
```bash
# Bug: location_name overwritten in recovery completion message
surgical_cleanup() {
    local location_name="$2"  # Function parameter
    
    # Call verify_ipsec_connections_active which iterates through locations
    if verify_ipsec_connections_active; then
        # location_name might be overwritten if loop variable wasn't declared as local!
        log_message "INFO" "$location_name" "Surgical cleanup completed for $location_name"
    fi
}
```

---

## Bash Strict Mode and Safety Patterns

### Pattern: Use Strict Mode in Main Scripts

**When to Use:** Main executable scripts (not library modules)

**Pattern:**
```bash
#!/bin/bash
set -euo pipefail

# Script continues here...
```

**Key Points:**
- `set -e`: Exit immediately if any command exits with non-zero status
- `set -u`: Treat unset variables as an error and exit immediately
- `set -o pipefail`: Pipeline returns exit status of last command to exit with non-zero status
- Use in main scripts (`install.sh`, `vpn-monitor.sh`, `run_tests.sh`)
- **Do NOT use in library modules** (`lib/*.sh`) - they are sourced and strict mode would affect caller
- Library modules should handle errors gracefully and return error codes

**When NOT to Use:**
- Library modules that are sourced (would affect caller's error handling)
- Functions that need to handle errors internally
- Code that intentionally checks for command failures

**Example:**
```bash
# ✅ GOOD: Main script with strict mode
#!/bin/bash
set -euo pipefail

# Script exits on any error
if ! check_command_available "ip"; then
    die "ip command not found"  # Script exits here if command fails
fi

# ❌ BAD: Library module with strict mode
# lib/common.sh
#!/bin/bash
set -euo pipefail  # BAD: Affects scripts that source this module!
```

### Pattern: Handle Errors Explicitly When Strict Mode Would Exit

**When to Use:** Code that needs to handle errors without exiting (even in strict mode)

**Pattern:**
```bash
# ✅ GOOD: Explicit error handling in strict mode
set -euo pipefail

# Check command availability without exiting (using helper function)
if ! check_command_or_warn "optional_cmd" "Optional feature"; then
    log_message "WARNING" "optional_cmd not available"
    # Continue execution
fi

# ✅ GOOD: Capture exit code explicitly
set -euo pipefail
if ! (command_that_might_fail 2>/dev/null); then
    handle_error "Command failed"
    # Continue execution
fi

# ❌ BAD: Relying on strict mode to handle errors silently
set -euo pipefail
command_that_might_fail 2>/dev/null  # Script exits if command fails!
```

**Key Points:**
- Use `if ! command` to check failures without exiting
- Use `|| true` or `2>/dev/null || true` to prevent exit on expected failures
- Always handle errors explicitly, don't rely on strict mode to hide them

### Pattern: Validate Paths Before Deletion Operations

**When to Use:** Scripts that perform destructive file/directory deletion operations (uninstall scripts, cleanup scripts)

**Pattern:**
```bash
# ✅ GOOD: Validate installation directory path before deletion
validate_install_dir_safety() {
    local expected_dir="/data/vpn-monitor"

    # Check INSTALL_DIR is not empty
    if [[ -z "$INSTALL_DIR" ]]; then
        log_error "INSTALL_DIR is empty - this is unsafe. Aborting uninstallation."
        exit 1
    fi

    # Check INSTALL_DIR matches expected path exactly
    if [[ "$INSTALL_DIR" != "$expected_dir" ]]; then
        log_error "INSTALL_DIR path mismatch detected!"
        log_error "Expected: $expected_dir"
        log_error "Actual:   $INSTALL_DIR"
        log_error "This is unsafe - aborting uninstallation to prevent accidental file deletion."
        exit 1
    fi

    # Additional safety: ensure path doesn't contain dangerous patterns
    if [[ "$INSTALL_DIR" == "/" ]]; then
        log_error "INSTALL_DIR is root directory (/) - this is extremely unsafe. Aborting."
        exit 1
    fi

    return 0
}

# Call validation before any deletion operations
validate_install_dir_safety
remove_installation_dir

# ❌ BAD: No validation before deletion
INSTALL_DIR="/data/vpn-monitor"  # Could be modified or empty
rm -rf "$INSTALL_DIR"  # Dangerous if INSTALL_DIR is wrong!
```

**Key Points:**
- Always validate paths before performing destructive operations (`rm -rf`, `rm -f`)
- Check that paths are not empty before use
- Validate paths match expected values exactly (exact string match, not prefix)
- Use defense-in-depth: validate at multiple points (entry point and before deletion)
- Exit immediately with clear error messages if validation fails
- Never trust hardcoded paths without validation (paths could be modified)

### Pattern: Protect Against Symlink Attacks in Deletion Operations

**When to Use:** Scripts that delete files/directories that might contain symlinks

**Pattern:**
```bash
# ✅ GOOD: Check symlinks point within intended directory before deletion
for item in "$INSTALL_DIR"/*; do
    if [[ ! -e "$item" ]]; then
        continue
    fi
    # Safety check: ensure item is actually within INSTALL_DIR
    # This prevents issues with symlinks or path traversal attempts
    local item_realpath
    if command -v readlink >/dev/null 2>&1; then
        item_realpath=$(readlink -f "$item" 2>/dev/null || echo "$item")
    else
        item_realpath="$item"
    fi
    local install_dir_realpath
    if command -v readlink >/dev/null 2>&1; then
        install_dir_realpath=$(readlink -f "$INSTALL_DIR" 2>/dev/null || echo "$INSTALL_DIR")
    else
        install_dir_realpath="$INSTALL_DIR"
    fi
    # Check that item_realpath starts with install_dir_realpath followed by /
    if [[ "$item_realpath" != "$install_dir_realpath"/* ]]; then
        log_warn "Skipping item outside installation directory: $item"
        continue
    fi
    # Safe to delete - item is within intended directory
    rm -rf "$item" 2>/dev/null || true
done

# ❌ BAD: No symlink checking - could delete files outside intended directory
for item in "$INSTALL_DIR"/*; do
    rm -rf "$item"  # Dangerous if $item is a symlink pointing outside!
done
```

**Key Points:**
- Always resolve symlinks using `readlink -f` before checking if items are within intended directory
- Check command availability before using `readlink` (may not be available on all systems)
- Use pattern matching (`"$item_realpath" != "$install_dir_realpath"/*`) to verify path is within directory
- Skip items that resolve outside the intended directory (log warning)
- Only delete items that are confirmed to be within the intended directory

### Pattern: Defense-in-Depth for Critical Operations

**When to Use:** Any script that performs critical or destructive operations

**Pattern:**
```bash
# ✅ GOOD: Validate at multiple points (defense-in-depth)
main() {
    # First validation: at script entry point
    validate_install_dir_safety

    # ... other operations ...

    # Second validation: before deletion (defense-in-depth)
    remove_installation_dir() {
        # Re-validate INSTALL_DIR before deletion
        if [[ "$INSTALL_DIR" != "/data/vpn-monitor" ]]; then
            log_error "INSTALL_DIR validation failed in remove_installation_dir - aborting"
            return 1
        fi
        # Proceed with deletion...
    }
}

# ❌ BAD: Single point of validation (could be bypassed)
main() {
    validate_install_dir_safety
    # If validation is bypassed or modified, no protection
    remove_installation_dir
}
```

**Key Points:**
- Use multiple validation points for critical operations
- Validate at script entry point (early failure)
- Re-validate before critical operations (defense-in-depth)
- Each validation point should be independent and check the same conditions
- This prevents accidental deletion even if one validation point is bypassed

---

## Quoting and Variable Expansion Patterns

### Pattern: Always Quote Variable Expansions

**When to Use:** All variable expansions to prevent word splitting and pathname expansion

**Pattern:**
```bash
# ✅ GOOD: Always quote variable expansions
local file="$1"
local count="${2:-0}"
if [[ -f "$file" ]]; then
    cat "$file"
fi

# ✅ GOOD: Quote in command substitutions
local output="$(command "$arg")"
local pid="$(cat "$pidfile")"

# ✅ GOOD: Quote array expansions
for ip in "${peer_ips[@]}"; do
    check_vpn_status "$ip"
done

# ❌ BAD: Unquoted variables (word splitting, pathname expansion)
local file=$1  # Fails if $1 contains spaces
if [[ -f $file ]]; then  # Pathname expansion if $file contains *
    cat $file  # Word splitting if $file contains spaces
fi
```

**Key Points:**
- Always quote `"$variable"` to prevent word splitting
- Always quote `"${array[@]}"` for array expansions
- Quote command substitutions: `"$(command)"`
- Quote in arithmetic contexts: `$((variable))` (no quotes needed for arithmetic)
- Exception: `[[ ]]` tests don't require quotes for simple variables, but quote for safety

**When Quoting is NOT Needed:**
- Arithmetic expansion: `$((var + 1))` (no quotes)
- Assignment: `var=$other_var` (no quotes needed, but safe to quote)
- Case statement patterns: `case "$var" in` (quote the variable, not patterns)

### Pattern: Use Modern Command Substitution Syntax

**When to Use:** All command substitutions

**Pattern:**
```bash
# ✅ GOOD: Use $() syntax (modern, nestable)
local timestamp=$(date +%s)
local output=$(command "$(other_command)")
local lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ❌ BAD: Use backticks (legacy, harder to nest)
local timestamp=`date +%s`
local output=`command \`other_command\``  # Hard to read and error-prone
```

**Key Points:**
- Always use `$()` instead of backticks
- `$()` is nestable and easier to read
- `$()` works better with quoting
- Backticks are legacy syntax and should be avoided

### Pattern: Defensive Command Substitution for Optional Failures

**When to Use:** Command substitutions where failure is acceptable and shouldn't cause script failure

**Pattern:**
```bash
# ✅ GOOD: Use || true when failure is acceptable
forward_output=$(echo "$xfrm_output" | grep -F "dst ${peer_ip}" 2>/dev/null || true)
ipsec_output=$(timeout 5 ipsec status 2>/dev/null || true)
func_def=$(declare -f check_command_available 2>/dev/null || true)

# ✅ GOOD: Use || true for mocked functions in tests that might return non-zero
_RECOVERY_IPSEC_PATH=$(get_command_path "ipsec" || true)

# ❌ BAD: Command substitution failure causes script failure (if set -e is enabled)
forward_output=$(echo "$xfrm_output" | grep -F "dst ${peer_ip}" 2>/dev/null)
# If grep finds nothing, exit code is 1, which can cause script failure
```

**Key Points:**
- Use `|| true` when command substitution failure is acceptable
- Prevents script failure when `set -e` is enabled
- Common use cases:
  - `grep` commands that may not find matches (exit code 1 is normal)
  - Functions that might return non-zero in edge cases (e.g., mocked functions in tests)
  - Commands where failure is expected and handled gracefully
- Always combine with appropriate error redirection (`2>/dev/null`) when needed
- Don't use `|| true` for commands where failure should be detected and handled explicitly

**When NOT to Use:**
- Commands where failure indicates a real problem that should be handled
- Commands where you need to check exit code explicitly
- Commands that should fail the script if they fail

**Examples:**
```bash
# ✅ GOOD: grep failure is acceptable (no matches found)
output=$(grep "pattern" "$file" 2>/dev/null || true)

# ✅ GOOD: Function might fail in test mocks
path=$(get_command_path "ipsec" || true)

# ❌ BAD: Should check exit code explicitly for critical operations
result=$(critical_command || true)  # Hides real failures!
if [[ -z "$result" ]]; then
    handle_error "ERROR" "SYSTEM" "Critical command failed"
fi

# ✅ BETTER: Check exit code explicitly
if ! result=$(critical_command 2>&1); then
    handle_error "ERROR" "SYSTEM" "Critical command failed: $result"
fi
```

### Pattern: Quote Heredoc Delimiters Appropriately

**When to Use:** Heredocs for multi-line strings

**Pattern:**
```bash
# ✅ GOOD: Quote delimiter to prevent variable expansion
cat >"$file" <<'EOF'
#!/bin/bash
# Variables like $VAR are not expanded
echo "Static content"
EOF

# ✅ GOOD: Unquoted delimiter allows variable expansion
cat >"$file" <<EOF
#!/bin/bash
# Variables like $VAR are expanded
echo "Value: $VAR"
EOF

# ✅ GOOD: Escaped variables in quoted heredoc
cat >"$file" <<'EOF'
#!/bin/bash
# Escape variables that should be expanded later
echo "Value: \$VAR"
EOF
```

**Key Points:**
- Use `<<'EOF'` (quoted delimiter) for static content
- Use `<<EOF` (unquoted delimiter) when you want variable expansion
- Escape variables with `\$VAR` in quoted heredocs if needed later
- Prefer quoted delimiters for scripts/templates to prevent accidental expansion

---

## UDM-Specific Constraints

### Pattern: UDM OS Compatibility

**When to Use:** All code that interacts with UDM system

**Pattern:**
```bash
# ✅ GOOD: Check for UDM-specific paths
if [[ -d "/data" ]]; then
    STATE_DIR="/data/vpn-monitor"
else
    # Fallback for non-UDM systems (dev mode)
    STATE_DIR="${HOME}/.vpn-monitor"
fi

# ✅ GOOD: Use UDM-available commands
# UDM OS 4.3+ includes: bash, ip, ipsec, ping, timeout, awk, sed, grep
if command -v timeout >/dev/null 2>&1; then
    timeout 5 ipsec status
fi

# ❌ BAD: Assume commands not available on UDM
# Python, Node.js, Perl may not be available
python3 script.py  # May not exist on UDM
```

**Key Points:**
- Target UDM OS 4.3+ (Debian-based, bash 4.0+, Linux-only)
- Use `/data` directory for persistent storage (UDM-specific)
- Available commands: `bash`, `ip`, `ipsec`, `ping`, `timeout`, `awk`, `sed`, `grep`, `cut`, `head`, `tail`
- Not available by default: Python, Node.js, Perl, Ruby
- Use `check_command_available()` or `check_command_or_warn()` to check command availability before use (handles PATH restrictions in cron/systemd)
- Provide fallbacks for optional commands
- **Do NOT add BSD/macOS fallbacks** - code should use Linux-specific command syntax (e.g., `date -d`, `stat -c`, `ping -W`, `nproc`)

### Pattern: UDM Path Constraints

**When to Use:** File operations on UDM systems

**Pattern:**
```bash
# ✅ GOOD: Use /data for persistent storage
STATE_DIR="/data/vpn-monitor"
LOGS_DIR="/data/vpn-monitor/logs"

# ✅ GOOD: Check directory writability
if ! directory_writable "$STATE_DIR"; then
    handle_error_or_exit_fake_mode "STATE_DIR is not writable: $STATE_DIR" "${EXIT_PERMISSION_ERROR:-4}"
fi

# ✅ GOOD: Create directories if needed
ensure_directory_exists "$STATE_DIR"
ensure_directory_exists "$LOGS_DIR"

# ❌ BAD: Use /tmp for persistent data (cleared on reboot)
STATE_DIR="/tmp/vpn-monitor"  # Data lost on reboot!
```

**Key Points:**
- Use `/data` for persistent storage (survives reboots)
- Use `/tmp` only for temporary files (cleared on reboot)
- Check directory writability before use
- Create directories with proper permissions
- `/data` is UDM-specific mount point for persistent storage

### Pattern: UDM Command Availability

**When to Use:** Before using system commands on UDM systems

**Pattern:**
```bash
# ✅ GOOD: Check for UDM-available commands (using helper functions)
# See "Command Availability Patterns" section for detailed guidance on check_command_available()
if check_command_available "ip"; then
    ip xfrm state
elif check_command_available "ipsec"; then
    ipsec status
else
    log_message "ERROR" "Neither ip nor ipsec available"
    return 1
fi

# ✅ GOOD: Use timeout wrapper (available on UDM, using helper function)
if check_command_available "timeout"; then
    timeout 5 ipsec status
else
    # Fallback (shouldn't happen on UDM, but handle gracefully)
    ipsec status
fi

# ❌ BAD: Assume commands exist
ip xfrm state  # May fail if ip not available
```

**Key Points:**
- **See "Command Availability Patterns" section for comprehensive guidance** on `check_command_available()`, `check_command_or_warn()`, and `get_command_path()`
- **UDM OS 4.3+ includes:** `bash`, `ip`, `ipsec`, `ping`, `timeout`, `awk`, `sed`, `grep`, `cut`, `head`, `tail`
- Always use helper functions (`check_command_available()` or `check_command_or_warn()`) for binary commands (handles PATH restrictions in cron/systemd)
- Provide fallbacks for optional commands
- **Exception:** Direct `command -v` is acceptable for checking function availability (functions are in same shell context)

### Pattern: Interactive User Input

**When to Use:** Scripts that prompt users for input interactively

**Pattern:**
```bash
# ✅ GOOD: Prompts go to stderr, don't interfere with stdin redirection
echo "Enter location names for each IP pair:" >&2
for ((i = 1; i <= count; i++)); do
    read -r -p "Location $i name (e.g., NYC, DC, SF): " name
    if [[ -z "$name" ]]; then
        name="$i"
    fi
    names+=("$(sanitize_location_name "$name")")
done

# ✅ GOOD: Error messages to stderr
echo "ERROR: Config file not found: $CONFIG_FILE" >&2

# ❌ BAD: Prompt to stdout interferes with stdin redirection in tests
echo "Enter location names for each IP pair:"  # Goes to stdout!
read -r -p "Location name: " name  # Prompt text may be read as input
```

**Key Points:**
- **Always redirect prompts and informational messages to stderr (`>&2`)** when using `read` to accept user input
- This prevents prompts from interfering with stdin redirection in tests (heredoc input)
- The `read -p` flag automatically writes to stderr, but any `echo` statements before `read` should also go to stderr
- Error messages should always go to stderr (`>&2`)
- User-facing informational messages can go to stdout, but prompts that precede `read` must go to stderr
- This pattern ensures scripts work correctly both interactively and when stdin is redirected (e.g., in tests)

**Why This Matters:**
- When stdin is redirected (e.g., `script.sh <<EOF\ninput\nEOF`), any output to stdout before `read` can be consumed as input

---

## Comment Patterns

### Pattern: Remove Useless Comments

**When to Use:** When reviewing code for cleanup and maintainability

**Pattern:**
```bash
# ❌ BAD: Comment just restates what the code does
local variable=""
# Set variable to empty string

# ❌ BAD: Obvious comment
if [[ $value -eq 0 ]]; then
    # Return 0 if value is zero
    return 0
fi

# ❌ BAD: Comment that's obvious from code structure
# Extract first internal IP if multiple provided (space-separated)
local internal_peer_ip=""
if [[ -n "$internal_peer_ips" ]]; then
    # ... code that extracts first IP
fi

# ✅ GOOD: Comment explains WHY, not WHAT
# Use provided SA existence state if available, otherwise check SA existence
# This optimization eliminates duplicate SA checks by reusing state from check_xfrm_status()
local ipsec_phase2_up=0
if [[ -n "$sa_exists" ]]; then
    ipsec_phase2_up=$sa_exists
fi

# ✅ GOOD: Comment provides context about non-obvious behavior
# Note: ip xfrm state returns exit code 0 even when no SAs exist (just empty output)
# So we need to check stderr for actual command errors
full_xfrm_output=$(ip -s xfrm state 2>&1)

# ✅ GOOD: Comment explains edge case or important detail
# Use fixed-string matching to prevent regex pattern injection
# Match on "dst $external_peer_ip" pattern which appears at the start of each SA entry
xfrm_output=$(get_xfrm_state_for_peer "$external_peer_ip")
```

**Key Points:**
- **Remove comments that just restate the code** - They add noise without value
- **Keep comments that explain WHY** - They provide context and reasoning
- **Keep comments about non-obvious behavior** - Edge cases, platform-specific behavior, etc.
- **Keep function documentation blocks** - Per ADR-0007, comprehensive function documentation is valuable
- **Keep shellcheck source comments** - They're necessary for linting
- **Remove obvious comments** - Comments like "# Set variable", "# Return 0", "# Check if X" that just describe what the code does

**What to Remove:**
- Comments that just restate variable assignments
- Comments that describe obvious control flow
- Comments that repeat function names or obvious operations
- Redundant comments before shellcheck directives (the shellcheck comment already identifies what's being sourced)

**What to Keep:**
- Comments explaining optimization decisions
- Comments about non-obvious platform behavior
- Comments explaining why a particular approach was chosen
- Function documentation blocks (per ADR-0007)
- Shellcheck source comments (required for linting)
- Comments that provide context about edge cases or important details

**Examples of Useless Comments to Remove:**
```bash
# ❌ Remove: Just restates the code
local diagnostic_parts=()
# Build diagnostic message explaining why we couldn't determine the type

# ❌ Remove: Obvious from code structure
# Extract first internal IP if multiple provided (space-separated)
local internal_peer_ip=""

# ❌ Remove: Just describes what the code does
# Check if we have actual output (not just empty/whitespace)
if [[ -n "${full_xfrm_output//[[:space:]]/}" ]]; then

# ❌ Remove: Redundant with shellcheck comment
# Source common utility functions
# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"
```

**Examples of Useful Comments to Keep:**
```bash
# ✅ Keep: Explains optimization
# Use provided SA existence state if available, otherwise check SA existence
# This optimization eliminates duplicate SA checks by reusing state from check_xfrm_status()

# ✅ Keep: Explains non-obvious behavior
# Note: ip xfrm state returns exit code 0 even when no SAs exist (just empty output)
# So we need to check stderr for actual command errors

# ✅ Keep: Explains security consideration
# Use fixed-string matching to prevent regex pattern injection
- Redirecting prompts to stderr keeps them visible to users while preventing them from interfering with input redirection
- This is critical for testability - tests can provide input via heredoc without the prompt text being read as input

---

## Summary

This document consolidates code patterns used throughout the UDM VPN Monitor codebase. These patterns should be followed consistently when writing or modifying code:

1. **Error Handling**: Use appropriate error handling patterns (fatal vs non-fatal, fake mode support)
2. **File Operations**: Always check readability before file operations, use atomic writes
3. **State Management**: Use abstraction layers for state file paths, track per-location state, handle recovery function return values appropriately
4. **Validation**: Use validation functions instead of inline regex, use supplementary diagnostics to reduce false positives
5. **Function Documentation**: Include comprehensive documentation blocks for all functions
6. **Configuration**: Use schema-based validation, safe config file parsing
7. **Logging**: Use centralized logging function, don't log success when operations fail
8. **Module Organization**: Follow consistent module sourcing and header patterns
9. **Testing**: Use test helper functions, mock system commands, use fixtures, test file deletion failures with read-only directories
10. **Variable Naming**: Follow naming conventions (UPPERCASE for constants, lowercase_with_underscores for locals)
11. **Arithmetic**: Use safe timestamp arithmetic, validate and clamp results
12. **Process Management**: Handle race conditions gracefully
13. **Network Commands**: Wrap network commands with timeout to prevent hanging
14. **Command Availability**: Check command availability before use, provide fallbacks
15. **String Parsing**: Use character-by-character parsing for complex syntax, trim and normalize strings
16. **Loops**: Read files line by line properly, iterate over arrays correctly
17. **Associative Arrays**: Use namerefs to pass arrays by reference, initialize properly
18. **Variable Initialization**: Use conditional readonly for multi-source modules, provide default parameter values, pre-declare arrays (use `declare -gA` for global arrays to avoid scoping issues)
19. **Comment Patterns**: Remove useless comments that just restate code, keep comments that explain why or provide context
20. **Bash Strict Mode**: Use `set -euo pipefail` in main scripts, handle errors explicitly in library modules
    - **Deletion Safety**: Validate paths before deletion operations, protect against symlink attacks, use defense-in-depth
21. **Quoting**: Always quote variable expansions, use `$()` for command substitution, quote heredoc delimiters appropriately
22. **UDM Constraints**: Target UDM OS 4.3+, use `/data` for persistent storage, check command availability, provide fallbacks
23. **Interactive Input**: Redirect prompts to stderr (`>&2`) before `read` to prevent interference with stdin redirection in tests

For more detailed information about specific patterns, see:
- `CODE_REVIEW_LESSONS_LEARNED.md` - Historical lessons learned from code reviews (includes bug context and how patterns were discovered)
- `DEVELOPER.md` - Developer guidelines and coding standards
- `ARCHITECTURE.md` - Architecture documentation and design decisions
- `BATS_GUIDE.md` - Testing framework guide and patterns

**Note:** This document (`CODE_PATTERNS.md`) consolidates actionable patterns from multiple sources, including `CODE_REVIEW_LESSONS_LEARNED.md`. For the historical context of how patterns were discovered (including specific bugs, their impact, and fixes), see `CODE_REVIEW_LESSONS_LEARNED.md`.
