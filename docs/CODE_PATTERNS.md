# Code Patterns Documentation

**Date:** 2025-01-15  
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
6. [Configuration Patterns](#configuration-patterns)
7. [Logging Patterns](#logging-patterns)
8. [Module Organization Patterns](#module-organization-patterns)
9. [Testing Patterns](#testing-patterns)
10. [Variable and Naming Patterns](#variable-and-naming-patterns)
11. [Arithmetic and Calculation Patterns](#arithmetic-and-calculation-patterns)
12. [Process Management Patterns](#process-management-patterns)
13. [Network Command Timeout Patterns](#network-command-timeout-patterns)
14. [Command Availability Patterns](#command-availability-patterns)
15. [String Parsing and Manipulation Patterns](#string-parsing-and-manipulation-patterns)
16. [Loop and Iteration Patterns](#loop-and-iteration-patterns)
17. [Associative Array Patterns](#associative-array-patterns)
18. [Variable Initialization Patterns](#variable-initialization-patterns)
19. [Bash Strict Mode and Safety Patterns](#bash-strict-mode-and-safety-patterns)
20. [Quoting and Variable Expansion Patterns](#quoting-and-variable-expansion-patterns)
21. [UDM-Specific Constraints](#udm-specific-constraints)

---

## Error Handling Patterns

### Pattern: Fatal Errors (Script Should Exit)

**When to Use:** Configuration errors, critical system errors, security violations, missing required dependencies

**Pattern:**
```bash
# Use handle_error_or_exit_fake_mode() for fatal errors that need fake mode support
if [[ ! -f "$CONFIG_FILE" ]] && [[ -z "${EXTERNAL_PEER_IPS:-}" ]]; then
    handle_error_or_exit_fake_mode "Configuration file not found and EXTERNAL_PEER_IPS not set" "${EXIT_CONFIG_ERROR:-2}"
fi

# Use die() for truly fatal errors that prevent script execution entirely
if ! command -v ip >/dev/null 2>&1; then
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
        log_message "ERROR" "Invalid peer IP format: $peer_ip"
        return 1  # Return error code, don't die
    fi
    
    # ... check logic ...
    
    if [[ $vpn_ok -eq 0 ]]; then
        return 1  # VPN check failed
    fi
    
    return 0  # VPN is healthy
}

# Caller handles the error:
if ! check_vpn_status "$peer_ip"; then
    log_message "WARNING" "VPN check failed for $peer_ip"
    increment_failure "$peer_ip"
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
if ! command -v ipsec >/dev/null 2>&1; then
    log_message "WARNING" "ipsec command not available"
    # Handle missing ipsec command
fi

if [[ ! -f "$cache_file" ]]; then
    log_message "WARNING" "Cache file not found: $cache_file (will recreate)"
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
# ✅ GOOD: Use handle_error_or_exit_fake_mode()
if [[ $is_writable -eq 0 ]]; then
    handle_error_or_exit_fake_mode "STATE_DIR is not writable: $lockfile_dir" "${EXIT_PERMISSION_ERROR:-4}"
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
- Fake mode (NO_ESCALATE=1): Logs error and exits with code 0
- Normal mode: Logs error and exits with specified exit code

### Pattern: Try-Fallback

**When to Use:** Operations with fallback mechanisms

**Pattern:**
```bash
if [[ "${ENABLE_XFRM_RECOVERY:-1}" -eq 1 ]]; then
    if ! attempt_xfrm_recovery "$peer_ip"; then
        log_message "WARNING" "xfrm recovery failed, falling back"
        if ! ipsec reload 2>/dev/null; then
            log_message "ERROR" "ipsec reload also failed"
            return 1
        fi
    fi
else
    if ! ipsec reload 2>/dev/null; then
        log_message "ERROR" "ipsec reload failed"
        return 1
    fi
fi
```

**Key Points:**
- Try primary method first
- Fall back to alternative if primary fails
- Log warnings when falling back
- Return error codes, don't die

### Pattern: Validate-Continue

**When to Use:** Input validation before processing

**Pattern:**
```bash
if ! validate_ip_address "$peer_ip"; then
    log_message "ERROR" "Invalid peer IP: $peer_ip"
    return 1  # Return error, don't die
fi
# Continue with validated input
```

**Key Points:**
- Validate input early
- Return error code if validation fails
- Continue processing only with valid input

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
- Reduces nesting and improves readability
- Each guard clause handles one error condition and returns early
- Main logic is at the function's natural indentation level
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
    log_message "ERROR" "Failed to write state file: $file"
    return 1
fi

# ✅ GOOD: Manual atomic write pattern
if ! (echo "$data" > "${file}.tmp" && mv "${file}.tmp" "$file"); then
    log_message "ERROR" "Failed to write state file: $file"
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
- Remove unreadable or unwritable target files before atomic writes
- Prevents hangs when overwriting unreadable files (chmod 000) or unwritable files (chmod 444)
- Use `rm -f` which can remove unreadable/unwritable files safely
- `atomic_write_file()` automatically handles this

### Pattern: Clean Up Leftover .tmp Files

**When to Use:** Before atomic writes to prevent hangs from leftover temp files

**Pattern:**
```bash
# ✅ GOOD: Clean up .tmp files before atomic write
if [[ -f "${file}.tmp" ]]; then
    rm -f "${file}.tmp" 2>/dev/null || true
fi
atomic_write_file "$file" "$content"
```

**Key Points:**
- Clean up leftover `.tmp` files before attempting atomic writes
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

---

## Configuration Patterns

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
log_message "INFO" "VPN monitor started"
log_message "WARNING" "Config file not found:" "$config_file"
log_message "ERROR" "Failed to restart VPN"
log_message "DEBUG" "Debug information"  # Only if DEBUG=1
```

**Key Points:**
- Use `log_message()` function from `lib/logging.sh` for all logging
- Log levels: INFO, WARNING, ERROR, DEBUG
- Format: `[YYYY-MM-DD HH:MM:SS] [LEVEL] message`
- Log file write errors don't fail the script (resilient logging)
- DEBUG messages only output if DEBUG=1
- INFO messages output to stderr when running interactively (TTY attached)

### Pattern: Don't Log Success When Operations Fail

**When to Use:** Functions that check operation success but log success messages

**Pattern:**
```bash
# ✅ GOOD: Return early on error, only log success when operation succeeds
set_cooldown() {
    local minutes="$1"
    local cooldown_until
    cooldown_until=$(get_timestamp_plus_minutes "$minutes")
    if ! atomic_write_file "$COOLDOWN_UNTIL_FILE" "$cooldown_until"; then
        handle_error "ERROR" "Failed to set cooldown period (file: $COOLDOWN_UNTIL_FILE)" 0
        return 0  # Return early - don't log success
    fi
    log_message "INFO" "Cooldown period set for $minutes minutes"  # Only logs on success
}

# ❌ BAD: Logs success even when write fails
set_cooldown() {
    local minutes="$1"
    local cooldown_until
    cooldown_until=$(get_timestamp_plus_minutes "$minutes")
    if ! atomic_write_file "$COOLDOWN_UNTIL_FILE" "$cooldown_until"; then
        handle_error "ERROR" "Failed to set cooldown period" 0
        # Bug: Function continues and logs success below!
    fi
    log_message "INFO" "Cooldown period set for $minutes minutes"  # Wrong! Logs even on failure
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
# ✅ GOOD: Wrap network commands with timeout
if command -v timeout >/dev/null 2>&1; then
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
local ping_wrapper_timeout
local quick_timeout=$((ping_timeout + 1))
local normal_timeout=$((ping_count * ping_timeout + 1))
if [[ $normal_timeout -gt 5 ]]; then
    normal_timeout=5
fi
if [[ $quick_timeout -lt $normal_timeout ]]; then
    ping_wrapper_timeout=$quick_timeout
else
    ping_wrapper_timeout=$normal_timeout
fi

if command -v timeout >/dev/null 2>&1; then
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
# ✅ GOOD: Check command availability before use
if command -v ipsec >/dev/null 2>&1; then
    ipsec_output=$(ipsec status 2>/dev/null)
else
    log_message "WARNING" "ipsec command not available, using fallback"
    # Use fallback method
fi

# ✅ GOOD: Use check_command_available() helper
if ! check_command_available "ip"; then
    return 1
fi

# ✅ GOOD: Use check_command_or_warn() for optional commands
if ! check_command_or_warn "ping6" "IPv6 ping check enabled"; then
    # Command not available, skip IPv6 ping
    return 0
fi

# ❌ BAD: Execute command without checking availability
ipsec_output=$(ipsec status 2>/dev/null)  # May fail if ipsec not available
```

**Key Points:**
- Always check command availability before executing optional commands
- Use `command -v` for command availability checks (POSIX compliant)
- Use `check_command_available()` helper for silent checks
- Use `check_command_or_warn()` for optional commands that should log warnings
- Provide fallback mechanisms when commands are unavailable

**Command Checking Functions:**
- `check_command_available()` - Silent check, returns 0/1
- `check_command_or_warn()` - Checks and logs warning if unavailable
- `command -v` - POSIX compliant command availability check

### Pattern: Fallback Command Execution

**When to Use:** Commands with multiple variants or fallback options

**Pattern:**
```bash
# ✅ GOOD: Try primary command, fallback to alternative
local ping_cmd="ping"
if command -v ping6 >/dev/null 2>&1 && [[ "$ip_version" == "6" ]]; then
    ping_cmd="ping6"
elif command -v ping >/dev/null 2>&1; then
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
```

**Key Points:**
- Use regex with capture groups for structured text parsing
- Access captured groups via `BASH_REMATCH[1]`, `BASH_REMATCH[2]`, etc.
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

**When to Use:** Functions that need to modify associative arrays or return multiple values

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
- Use `declare -gA` to ensure global scope when sourcing from within functions
- Prevents "unbound variable" errors when `set -u` is enabled
- **Critical:** Associative arrays must be declared before they can be populated. Even if a sourced file tries to declare and populate an array in one step (`declare -A ARRAY=(...)`), it may not work correctly unless the array is pre-declared in the sourcing context
- Use empty array initialization `=()` for clarity

**Example: CONFIG_SCHEMA Pattern**
```bash
# In lib/config.sh - Pre-declare before sourcing schema file
declare -gA CONFIG_SCHEMA=()
if [[ -f "${LIB_DIR}/config_schema.sh" ]] && source "${LIB_DIR}/config_schema.sh" 2>/dev/null; then
    # Schema file populates CONFIG_SCHEMA successfully
    # Without pre-declaration, the array might not be populated correctly
fi
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
if ! command -v ip >/dev/null 2>&1; then
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

# Check command availability without exiting
if ! command -v optional_cmd >/dev/null 2>&1; then
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
- Use `command -v` to check command availability before use
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

**When to Use:** Before using system commands

**Pattern:**
```bash
# ✅ GOOD: Check for UDM-available commands
if command -v ip >/dev/null 2>&1; then
    ip xfrm state
elif command -v ipsec >/dev/null 2>&1; then
    ipsec status
else
    log_message "ERROR" "Neither ip nor ipsec available"
    return 1
fi

# ✅ GOOD: Use timeout wrapper (available on UDM)
if command -v timeout >/dev/null 2>&1; then
    timeout 5 ipsec status
else
    # Fallback (shouldn't happen on UDM, but handle gracefully)
    ipsec status
fi

# ❌ BAD: Assume commands exist
ip xfrm state  # May fail if ip not available
```

**Key Points:**
- Always check command availability with `command -v`
- Provide fallbacks for optional commands
- UDM OS 4.3+ includes: `bash`, `ip`, `ipsec`, `ping`, `timeout`, `awk`, `sed`, `grep`
- Log warnings when optional commands unavailable
- Return errors when required commands missing

---

## Summary

This document consolidates code patterns used throughout the UDM VPN Monitor codebase. These patterns should be followed consistently when writing or modifying code:

1. **Error Handling**: Use appropriate error handling patterns (fatal vs non-fatal, fake mode support)
2. **File Operations**: Always check readability before file operations, use atomic writes
3. **State Management**: Use abstraction layers for state file paths, track per-location state
4. **Validation**: Use validation functions instead of inline regex
5. **Function Documentation**: Include comprehensive documentation blocks for all functions
6. **Configuration**: Use schema-based validation, safe config file parsing
7. **Logging**: Use centralized logging function, don't log success when operations fail
8. **Module Organization**: Follow consistent module sourcing and header patterns
9. **Testing**: Use test helper functions, mock system commands, use fixtures
10. **Variable Naming**: Follow naming conventions (UPPERCASE for constants, lowercase_with_underscores for locals)
11. **Arithmetic**: Use safe timestamp arithmetic, validate and clamp results
12. **Process Management**: Handle race conditions gracefully
13. **Network Commands**: Wrap network commands with timeout to prevent hanging
14. **Command Availability**: Check command availability before use, provide fallbacks
15. **String Parsing**: Use character-by-character parsing for complex syntax, trim and normalize strings
16. **Loops**: Read files line by line properly, iterate over arrays correctly
17. **Associative Arrays**: Use namerefs to pass arrays by reference, initialize properly
18. **Variable Initialization**: Use conditional readonly for multi-source modules, provide default parameter values, pre-declare arrays
19. **Bash Strict Mode**: Use `set -euo pipefail` in main scripts, handle errors explicitly in library modules
20. **Quoting**: Always quote variable expansions, use `$()` for command substitution, quote heredoc delimiters appropriately
21. **UDM Constraints**: Target UDM OS 4.3+, use `/data` for persistent storage, check command availability, provide fallbacks

For more detailed information about specific patterns, see:
- `CODE_REVIEW_LESSONS_LEARNED.md` - Lessons learned from code reviews
- `DEVELOPER.md` - Developer guidelines and coding standards
- `ARCHITECTURE.md` - Architecture documentation and design decisions
- `BATS_GUIDE.md` - Testing framework guide and patterns
