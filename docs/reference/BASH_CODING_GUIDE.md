# Bash Coding Guide

**Date:** 2026-01-19  
**Purpose:** Project-specific guide to coding in Bash for the UDM VPN Monitor codebase

## Purpose and Scope

**This is a project-specific coding guide, not a comprehensive Bash reference.**

This guide focuses on:
- **Bash fundamentals and best practices** used in this project
- **Patterns actually used** in the UDM VPN Monitor codebase
- **Practical examples** relevant to this project's needs
- **How to write Bash code** that fits this project's conventions

**What this guide is NOT:**
- An exhaustive Bash language reference (see [References](#references) section for comprehensive documentation)
- A general-purpose Bash tutorial
- A complete guide to all Bash features

**For exhaustive Bash documentation**, see the [References](#references) section, which includes:
- GNU Bash Manual
- Bash Guide
- Advanced Bash Scripting Guide

**This guide complements existing documentation:**
- `CODE_PATTERNS.md` - Detailed project-specific patterns and codebase examples
- `DEVELOPER.md` - Development workflow and tooling
- `ARCHITECTURE.md` - System architecture and design decisions

**Note:** Project-specific patterns (e.g., safe timestamp arithmetic functions, codebase-specific validation patterns) are documented in `CODE_PATTERNS.md` rather than this guide, which focuses on Bash language fundamentals.

---

## Table of Contents

1. [Script Structure and Setup](#script-structure-and-setup)
2. [Error Handling and Strict Mode](#error-handling-and-strict-mode)
3. [Debugging Techniques](#debugging-techniques)
4. [Variable Usage and Naming](#variable-usage-and-naming)
5. [Functions](#functions)
6. [Arrays and Associative Arrays](#arrays-and-associative-arrays)
7. [String Manipulation](#string-manipulation)
8. [Command Substitution](#command-substitution)
9. [Arithmetic Operations](#arithmetic-operations)
10. [Control Flow](#control-flow)
11. [File Operations](#file-operations)
12. [Input Validation](#input-validation)
13. [Security Best Practices](#security-best-practices)
14. [Code Quality Tools](#code-quality-tools)
15. [Common Pitfalls and Gotchas](#common-pitfalls-and-gotchas)
16. [Documentation Standards](#documentation-standards)
17. [Module Sourcing](#module-sourcing)
18. [References](#references)

---

## Script Structure and Setup

### Shebang Line

Always start scripts with a shebang to specify the interpreter:

```bash
#!/bin/bash
```

**Best Practice:**
- Use `#!/bin/bash` for scripts that require Bash-specific features when you know the exact path to bash
  - More reliable when bash location is fixed (e.g., UDM OS)
  - Faster execution (no PATH lookup)
- Use `#!/usr/bin/env bash` for portability when bash location may vary
  - Finds bash in PATH, useful for cross-platform scripts
  - Slightly slower due to PATH lookup
- This project uses `#!/bin/bash` since we target UDM OS 4.3+ specifically where bash location is consistent


### Script Header

Include a descriptive header with purpose, version, and key information:

```bash
#!/bin/bash
#
# Script Name
# Brief description of what the script does
#
# Version: 1.0.0
#
```

### Directory Setup

Get script directory early for reliable path resolution:

```bash
# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.conf"
```

**Key Points:**
- Use `"${BASH_SOURCE[0]}"` instead of `$0` for sourced scripts
  - `BASH_SOURCE[0]` works correctly even when script is sourced, always pointing to the current script
  - `$0` may not work correctly when a script is sourced (it may point to the parent script or shell)
- Use `$(cd ... && pwd)` to get absolute path
- Quote all path variables to handle spaces

---

## Error Handling and Strict Mode

### Enable Strict Mode

Enable strict error handling at the start of main scripts:

```bash
set -euo pipefail
```

**What each option does:**
- `set -e` (errexit): Exit immediately if a command exits with a non-zero status
- `set -u` (nounset): Treat unset variables as an error and exit immediately
- `set -o pipefail`: Pipeline returns the exit status of the last command to exit with a non-zero status

**Example:**
```bash
#!/bin/bash
set -euo pipefail
```

**Important Notes:**
- **Main scripts**: Always use `set -euo pipefail`
- **Library modules**: Handle errors explicitly rather than relying on `set -e` (modules may be sourced by scripts with different error handling)
- **When commands are expected to fail**: Prefer using `if ! command` or `command || true` instead of temporarily disabling strict mode:
  ```bash
  # ✅ GOOD: Use if ! command pattern
  if ! command_that_may_fail; then
      handle_error
  fi
  
  # ✅ GOOD: Use || true when failure is acceptable
  output=$(command_that_may_fail 2>/dev/null || true)
  ```

### Error Handling in Library Modules

Library modules should handle errors explicitly rather than relying on `set -e`:

```bash
# Library module pattern
# Don't use set -euo pipefail in library modules
# Handle errors explicitly

process_item() {
    local item="$1"
    
    if ! validate_input "$item"; then
        echo "ERROR: Invalid input: $item" >&2
        return 1  # Return error code, don't exit
    fi
    
    # ... processing logic ...
    
    if [[ $check_passed -eq 0 ]]; then
        return 1  # Check failed
    fi
    
    return 0  # Check passed
}
```

**Why:** Library modules may be sourced by scripts with different error handling requirements. Explicit error handling is more predictable.

### Common Strict Mode Pitfalls

**Important:** `set -e` doesn't work in all contexts. Understanding these limitations helps avoid unexpected behavior.

**Pitfall 1: `set -e` is disabled in certain contexts**

`set -e` is automatically disabled in:
- `if` statements (the condition itself)
- `while` loops (the condition itself)
- Command substitutions `$()` (unless the command substitution is in a context where `set -e` applies)

```bash
set -e

# ⚠️ PROBLEMATIC: Command substitution failure can cause script exit
result=$(check_condition)  # Script exits if check_condition returns non-zero
# This line never executes if check_condition fails

# ✅ GOOD: Use || true to handle expected failures in command substitution
result=$(check_condition 2>/dev/null || true)
if [[ -z "$result" ]]; then
    handle_error
fi
```

**Pitfall 2: Functions or commands that return non-zero intentionally**

Functions or commands that return non-zero for valid reasons (e.g., "not found" is a valid result) can cause unexpected script termination:

```bash
set -e

# ❌ BAD: Script exits if grep finds nothing (even though that's a valid result)
output=$(grep "pattern" "$file")  # Script exits if pattern not found
if item_exists; then  # Script exits if item doesn't exist
    echo "Found"
fi

# ✅ GOOD: Use || true when failure is acceptable
output=$(grep "pattern" "$file" 2>/dev/null || true)
if item_exists || true; then
    echo "Found"
fi
```

**Best Practices:**
- Use `if ! command` for commands where you want to handle failure explicitly
- Use `command || true` in command substitutions when failure is acceptable
- Use explicit exit code checking (`exit_code=$?`) when you need to distinguish between different failure modes
- Avoid temporarily disabling `set -e` unless absolutely necessary (prefer the patterns above)

### Error Handling Decision Tree

Choose the appropriate error handling pattern:

- **`die()`**: Fatal errors that prevent execution (no fake mode needed)
  - Configuration file missing, critical resources unavailable, invalid arguments

- **`handle_error_or_exit_fake_mode()`**: Fatal errors that need to respect `--fake` flag
  - Directory creation failures, file write failures (allows testing without side effects)

- **`log_message "WARNING"` + return 1**: Non-fatal errors that don't stop execution
  - Optional command unavailable (fallback available), non-critical validation failures

- **Handle gracefully, don't log as error**: Expected failures that are valid results
  - "Item not found" when searching, optional feature unavailable

**Note:** For detailed error handling patterns including try-fallback, early returns, optional features, and error state tracking, see `CODE_PATTERNS.md` section on [Error Handling Patterns](CODE_PATTERNS.md#error-handling-patterns).

### Error Handling Patterns

**Fatal Errors:**
```bash
# Use die() for fatal errors (no fake mode needed)
if [[ ! -f "$CONFIG_FILE" ]] && [[ -z "${EXTERNAL_PEER_IPS:-}" ]]; then
    die "Configuration file not found and EXTERNAL_PEER_IPS not set"
fi

# Use handle_error_or_exit_fake_mode() for fatal errors that need fake mode support
if ! ensure_directory_exists "$STATE_DIR" "state"; then
    handle_error_or_exit_fake_mode "SYSTEM" "Failed to create state directory" "${EXIT_GENERAL_ERROR:-1}"
fi
```

**Non-Fatal Errors:**
```bash
# Return error codes (see "Error Handling in Library Modules" for pattern)
if ! process_item "$item"; then
    log_message "WARNING" "SYSTEM" "Processing failed for $item"
    handle_failure "$item"
fi
```

### Cleanup Functions and EXIT Traps

When using EXIT traps with cleanup functions, always use default value expansion for variables that might be unset:

```bash
# ✅ GOOD: Use default value expansion in cleanup functions
anonymize_log_file() {
    local location_sed_script
    local ip_sed_script
    location_sed_script=$(mktemp)
    ip_sed_script=$(mktemp)
    
    cleanup_temp_files() {
        # Use default value expansion to handle case where variables might be unset
        # EXIT trap executes after function returns, so local variables may be out of scope
        rm -f "${location_sed_script:-}" "${ip_sed_script:-}"
    }
    trap cleanup_temp_files EXIT
    
    # ... function code ...
}

# ❌ BAD: Fails with "unbound variable" error when set -u is enabled
anonymize_log_file() {
    local location_sed_script
    local ip_sed_script
    location_sed_script=$(mktemp)
    ip_sed_script=$(mktemp)
    
    cleanup_temp_files() {
        rm -f "$location_sed_script" "$ip_sed_script"  # Error: unbound variable
    }
    trap cleanup_temp_files EXIT
    
    # ... function code ...
    # When function returns, local variables go out of scope
    # EXIT trap executes later, variables are unbound
}
```

**Key Points:**
- EXIT traps execute when script exits, not when function returns
- Local variables may be out of scope when trap executes
- Always use `${var:-}` syntax in cleanup functions to prevent "unbound variable" errors
- This is especially important when `set -u` or `set -euo pipefail` is enabled
- Cleanup should be idempotent (safe to run multiple times)

### Signal Handling

Handle signals (SIGINT, SIGTERM) for graceful cleanup and proper exit codes:

```bash
# ✅ GOOD: Handle SIGINT (130) and SIGTERM (143) for cleanup
cleanup_on_signal() {
    [[ ${CLEANUP_DONE:-0} -eq 1 ]] && exit "${SIGNAL_EXIT_CODE:-130}"
    CLEANUP_DONE=1
    rm -f "${TEMP_FILE:-}" "${LOCKFILE:-}" 2>/dev/null || true  # Idempotent cleanup
    exit "${SIGNAL_EXIT_CODE:-130}"
}

trap 'SIGNAL_EXIT_CODE=130; cleanup_on_signal' INT   # Ctrl+C: exit 130
trap 'SIGNAL_EXIT_CODE=143; cleanup_on_signal' TERM   # SIGTERM: exit 143
trap 'cleanup_on_signal' EXIT
```

### Error Recovery and Retry Logic

Implement retry logic with exponential backoff for transient failures:

```bash
# ✅ GOOD: Retry with exponential backoff (use fixed delay by removing backoff calculation, or timeout-based by replacing max_attempts with time check)
retry_with_backoff() {
    local max_attempts="$1"
    local base_interval="$2"
    local max_interval="$3"
    shift 3
    local command="$*"
    
    local attempt=1
    local current_interval=$base_interval
    
    while [[ $attempt -le $max_attempts ]]; do
        if eval "$command"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log_message "WARNING" "SYSTEM" "Attempt $attempt failed, retrying in ${current_interval}s..."
            sleep "$current_interval"
            current_interval=$((current_interval * 2))  # Exponential backoff
            [[ $current_interval -gt $max_interval ]] && current_interval=$max_interval
        fi
        attempt=$((attempt + 1))
    done
    
    log_message "ERROR" "SYSTEM" "Command failed after $max_attempts attempts"
    return 1
}
```

**Key Points:**
- Always limit retries (max attempts or timeout) to prevent infinite loops
- Use exponential backoff for operations that may take time to recover
- Log retry attempts and failures for debugging

### Error Handling Checklist

When writing or reviewing code:
- [ ] Fatal errors use `die()` or `handle_error_or_exit_fake_mode()` with descriptive messages
- [ ] Non-fatal errors return error codes (0/1)
- [ ] Warnings are logged with `log_message "WARNING"`
- [ ] Return codes are checked by callers
- [ ] Error messages include context (peer IP, file path, etc.)
- [ ] Appropriate log levels are used (ERROR/WARNING/INFO/DEBUG)
- [ ] Cleanup functions use default value expansion `${var:-}` for variables that might be unset

---

## Debugging Techniques

The most practical way to debug Bash scripts is using trace mode, which shows each command before it executes.

### Using `set -x` for Trace Mode

Enable trace mode to see each command before it executes:

```bash
# ✅ GOOD: Enable trace mode at script start
#!/bin/bash
set -euo pipefail
set -x  # Enable trace mode - shows each command before execution

# Script execution will show:
# + echo 'Hello World'
# Hello World
# + date
# Mon Jan 17 10:30:00 UTC 2026
```

**Enable trace mode for specific sections:**

```bash
# ✅ GOOD: Enable trace mode only for problematic section
process_data() {
    set -x  # Enable trace for this function
    local data="$1"
    # ... complex processing ...
    set +x  # Disable trace after debugging
}
```

**Key Points:**
- `set -x` shows each command with `+` prefix before execution
- Shows expanded variables and command substitutions
- Can be verbose - use selectively for specific sections
- Disable with `set +x` when done debugging

### Debugging with `bash -x`

Run scripts with trace mode enabled from command line without modifying the script:

```bash
# ✅ GOOD: Run script with trace mode
bash -x script.sh

# ✅ GOOD: Save debug output to file
bash -x script.sh 2>&1 | tee debug.log
```

**Key Points:**
- Use `bash -x script.sh` to debug without modifying script
- Save output to files for analysis
- Filter output with `grep` if needed: `bash -x script.sh 2>&1 | grep "function_name"`

**Note:** For project-specific debug logging patterns and functions, see `CODE_PATTERNS.md`.

---

## Variable Usage and Naming

### Naming Conventions

Follow consistent naming conventions:

```bash
# Constants and environment variables: UPPERCASE
readonly EXIT_SUCCESS=0
readonly SECONDS_PER_MINUTE=60
CONFIG_FILE="${SCRIPT_DIR}/config.conf"

# Local variables: lowercase_with_underscores
local item="$1"
local failure_count=0
local timestamp=$(date +%s)

# Function names: lowercase_with_underscores
process_item() {
    # ...
}
```

**Example:**
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.conf"
STATE_DIR="${SCRIPT_DIR}/state"
LOGS_DIR="${SCRIPT_DIR}/logs"
LOCKFILE="${STATE_DIR}/app.lock"
LOG_FILE="${LOGS_DIR}/app.log"
```

### Always Quote Variables

**Critical:** Always quote variable expansions to prevent word splitting and globbing:

```bash
# ✅ GOOD: Always quote variables to prevent word splitting and globbing
echo "Processing file: $filename"
cp "$source_file" "$dest_file"
if [[ -f "$config_file" ]]; then
    source "$config_file"
fi
```

**Why:** Unquoted variables can cause:
- Word splitting (spaces break arguments)
- Pathname expansion (wildcards get expanded)
- Security issues (injection attacks)

### Use Local Variables in Functions

Always use `local` for function variables to avoid global scope pollution:

```bash
# ✅ GOOD: Always use local for function variables to avoid global scope pollution
process_file() {
    local filename="$1"
    local line_count=0
    local temp_file="/tmp/temp"
    # ... function logic ...
}
```

### Default Values and Parameter Expansion

Use parameter expansion for default values and safe access:

```bash
# ${var:-default} - Use default if variable is unset OR empty
local timeout="${TIMEOUT:-30}"
local log_level="${LOG_LEVEL:-INFO}"

# ${var-default} - Use default ONLY if variable is unset (allows empty string)
local config="${CONFIG_FILE-/etc/default.conf}"

# Safe access with set -u (prevents "unbound variable" errors)
local value="${BASH_REMATCH[1]:-}"  # Empty string if unset

# Check if variable is set
if [[ -n "${DEBUG:-}" ]]; then
    echo "Debug mode enabled"
fi
```

**Example:**
```bash
# Use default values for optional parameters
local config_file="${1:-$DEFAULT_CONFIG_FILE}"
local timeout="${TIMEOUT:-5}"
```

### Readonly Variables

Use `readonly` for constants that shouldn't change:

```bash
# ✅ GOOD: Readonly constants
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly SECONDS_PER_MINUTE=60

# Conditional readonly (for modules that may be sourced multiple times)
[[ -z "${IPSEC_STATUS_TIMEOUT:-}" ]] && readonly IPSEC_STATUS_TIMEOUT=5
```

**Important Limitations:**
- `readonly` prevents reassignment of the variable itself
- `readonly` does **not** prevent modification of array elements (array elements can still be modified)

```bash
readonly MY_ARRAY=(1 2 3)
MY_ARRAY[0]=99        # ✅ Allowed - modifies array element
MY_ARRAY=(4 5 6)      # ❌ Error - cannot reassign readonly array
```

---

## Functions

### Function Definition Style

Use the standard function definition style (without `function` keyword):

```bash
# ✅ GOOD: Standard style (preferred)
process_item() {
    local item="$1"
    # ... function body ...
}

# Also valid but less common:
function process_item() {
    local item="$1"
    # ... function body ...
}
```

### Function Parameters

Access parameters using positional variables:

```bash
process_config() {
    local config_file="$1"      # First parameter
    local validate="$2"         # Second parameter
    local timeout="${3:-30}"    # Third parameter with default
    
    # Use shift for remaining parameters
    shift 3
    local remaining_args="$*"   # All remaining arguments
}
```

**When to Use `shift` vs Direct Access:**

- **Use `shift`** when you need to process a variable number of remaining arguments:
  - Passing remaining arguments to another function
  - Processing all remaining arguments in a loop
  - When you don't know how many arguments there are

```bash
# ✅ GOOD: Use shift when processing variable number of arguments
process_files() {
    local output_dir="$1"
    shift 1  # Remove first argument
    # Now $@ contains only the file arguments
    for file in "$@"; do
        process_file "$file" "$output_dir"
    done
}
```

- **Use direct access (`$4`, `$5`, etc.)** when you have a fixed number of parameters:
  - When you know exactly how many parameters you need
  - When you want to access specific parameters by position
  - When you don't need to pass remaining arguments elsewhere

```bash
# ✅ GOOD: Use direct access for fixed parameters
create_user() {
    local username="$1"
    local email="$2"
    local role="$3"
    local department="$4"  # Direct access - we know this is the 4th parameter
    # ... implementation ...
}
```

### Return Values

Functions return exit codes (0 = success, non-zero = failure):

```bash
# ✅ GOOD: Return error codes
validate_input() {
    local value="$1"
    
    if [[ -z "$value" ]]; then
        return 1  # Invalid
    fi
    
    # ... validation logic ...
    
    return 0  # Valid
}

# Caller checks return code
if ! validate_input "$user_input"; then
    echo "ERROR: Invalid input: $user_input" >&2
    return 1
fi
```

**Key Points:**
- Return 0 for success, 1 (or other non-zero) for failure
- Always check return codes from functions
- Don't ignore return values

### Returning Data from Functions

When functions need to return data (not just success/failure), use one of these patterns:

```bash
# ✅ GOOD: Command substitution for single string values (preferred for simple returns)
get_script_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}
SCRIPT_DIR=$(get_script_dir)

# ✅ GOOD: Namerefs for complex data structures (arrays, associative arrays)
parse_config() {
    local config_line="$1"
    local -n result="$2"  # Nameref - caller's array name
    result["name"]="NYC"
    result["peer_ip"]="203.0.113.1"
    return 0
}
declare -A config_data
if parse_config "$line" "config_data"; then
    echo "Name: ${config_data[name]}"
fi
```

**When to Use Each:**
- **Command substitution**: Single string values (preferred for simple returns)
- **Namerefs**: Complex data structures (arrays, associative arrays), multiple values

### Function Documentation

Document all functions with comprehensive comments:

```bash
# Check if VPN peer is active
#
# Verifies VPN tunnel health by checking IPsec Security Association state.
# Uses multiple detection methods with automatic fallback.
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
#   if validate_input "user@example.com"; then
#       echo "Input is valid"
#   fi
validate_input() {
    local value="$1"
    # ... implementation ...
}
```

**Required Sections:**
- **Purpose**: What the function does
- **Arguments**: All parameters with types and descriptions
- **Returns**: Exit codes and their meanings

**Optional Sections (include when relevant):**
- **Side effects**: File operations, logging, state changes
- **Examples**: Usage examples for complex functions
- **Note**: Dependencies, requirements, or special considerations

---

## Arrays and Associative Arrays

### Regular Arrays

Use arrays instead of space-separated strings for lists:

```bash
# ✅ GOOD: Array declaration and usage
items=("item1" "item2" "item3")
# Or with explicit declaration:
declare -a items=("item1" "item2" "item3")

# Iterate over array elements
for item in "${items[@]}"; do
    process_item "$item"
done

# Iterate with index
for i in "${!items[@]}"; do
    echo "Index: $i, Item: ${items[$i]}"
done
```

**Key Points:**
- Always quote `"${array[@]}"` when iterating
- **Critical:** Use `"${array[@]}"` (not `"${array[*]}"`) for iteration
  - `"${array[@]}"` expands to all elements as separate words (preserves individual elements)
  - `"${array[*]}"` joins all elements into a single string using IFS
- Use `"${!array[@]}"` to get indices
- Check if array is empty: `[[ ${#array[@]} -eq 0 ]]`

### Associative Arrays

Use associative arrays for key-value data structures:

```bash
# ✅ GOOD: Associative array declaration
declare -A location_config=()
location_config["name"]="NYC"
location_config["peer_ip"]="203.0.113.1"
location_config["enabled"]="1"

# Access values
local name="${location_config[name]}"
local peer_ip="${location_config[peer_ip]}"

# Check if key exists
if [[ -n "${location_config[enabled]:-}" ]]; then
    echo "Location is enabled"
fi

# Iterate over keys
for key in "${!location_config[@]}"; do
    echo "Key: $key, Value: ${location_config[$key]}"
done
```

**Key Points:**
- Always declare with `declare -A` or `local -A` before use
- Use parameter expansion `${array[key]:-}` to safely check existence
- Quote key access: `"${array[$key]}"`

### Pre-Declaring Associative Arrays for Sourced Files

When an associative array will be populated by a sourced file, pre-declare it to avoid unbound variable errors with `set -u`:

```bash
# ✅ GOOD: Pre-declare associative array before sourcing file that populates it
# Pre-declare CONFIG_SCHEMA as empty array to avoid unbound variable errors with set -u
# The schema file will populate it when sourced
# Use -gA to ensure it's global (important when config.sh is sourced from within functions)
declare -gA CONFIG_SCHEMA=()

# Source file that populates CONFIG_SCHEMA
source "${LIB_DIR}/config_schema.sh"
```

**Key Points:**
- Use `declare -gA` for global arrays (needed when sourced from within functions)
- Pre-declare as empty array `=()` before sourcing files that populate it
- Prevents "unbound variable" errors when `set -u` is enabled
- The sourced file can then populate the array without declaration errors

### Passing Arrays by Reference (Namerefs)

Use namerefs to pass arrays to functions:

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

**Critical: Avoid Circular References**

When using namerefs, avoid circular references by storing the reference name in a temp variable:

```bash
# ❌ BAD: Circular reference error
local -n array_ref="$array"  # Error if $array conflicts with environment variable

# ✅ GOOD: Use temp variable to prevent circular references
local ref_name="$param_ref"
local -n array_ref="$ref_name"  # Safe - temp variable prevents conflicts
```

**Important:** When `set -u` is enabled, always store the reference name in a temp variable before creating the nameref to avoid expansion issues.

**When to Use Namerefs vs Returning Arrays:**

- **Use namerefs** when: Working with large arrays, modifying arrays in place, returning complex data structures
- **Use return values** when: Working with small arrays, creating new arrays, avoiding side effects

**Example:**
```bash
split_string_to_array() {
    local input_string="$1"
    local -n array_ref="$2"
    
    # Clear the array
    array_ref=()
    
    # Handle empty string
    if [[ -z "$input_string" ]]; then
        return 0
    fi
    
    # Split by delimiter and populate array
    IFS=',' read -ra array_ref <<<"$input_string"
    
    return 0
}
```

### Common Array Mistakes

**Note:** Array mistakes are also covered in the "Common Pitfalls and Gotchas" section. See that section for a consolidated reference.

Avoid these common pitfalls when working with arrays:

| Mistake | Bad Example | Good Example |
|---------|-------------|--------------|
| **Using `[*]` instead of `[@]`** | `for item in "${array[*]}"; do` (joins elements) | `for item in "${array[@]}"; do` (preserves elements) |
| **Unquoted expansion** | `for file in ${array[@]}; do` (word splitting) | `for file in "${array[@]}"; do` (safe) |
| **Treating array as string** | `if [[ "$array" == "item1" ]]; then` (checks first element only) | `if [[ "${array[0]}" == "item1" ]]; then` |
| **Not declaring associative arrays** | `location_config["name"]="NYC"` (error) | `declare -A location_config=()` then assign |
| **Wrong append syntax** | `array=$array"new item"` (treats as string) | `array+=("new item")` |
| **Wrong length syntax** | `length=${#array}` (first element length) | `length=${#array[@]}` (array size) |

**Key Examples:**

```bash
# ✅ GOOD: Proper array iteration
for item in "${array[@]}"; do
    echo "$item"
done

# ✅ GOOD: Check if array is empty before iteration
if [[ ${#array[@]} -gt 0 ]]; then
    for item in "${array[@]}"; do
        process "$item"
    done
fi

# ✅ GOOD: Declare associative arrays before use
declare -A location_config=()
location_config["name"]="NYC"
```

---

## String Manipulation

### Pattern Matching and Substitution

Use bash pattern substitution for string manipulation:

```bash
# Remove leading whitespace
line="${line#"${line%%[![:space:]]*}"}"

# Remove trailing whitespace
line="${line%"${line##*[![:space:]]}"}"

# Remove trailing comments
assignment="${assignment%%#*}"

# Escape special characters for sed (use character classes for * and ?)
escaped_location="${location//[*]/\\*}"   # Escape literal *
escaped_location="${escaped_location//[?]/\\?}"  # Escape literal ?

# ❌ BAD: Direct * or ? matching (matches entire string or every character!)
escaped="${location//*/\\*}"     # BUG: Matches entire string!
escaped="${escaped//?/\\?}"      # BUG: Matches every character!
```

**Important:** In bash pattern substitution, `*` and `?` are glob patterns. Use character classes `[*]` and `[?]` to match literal characters.

### Regex Matching

Use regex matching with `=~` operator:

```bash
# ✅ GOOD: Extract values using regex with BASH_REMATCH
if [[ "$line" =~ ^\[([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2})\]\ \[([A-Z]+)\]\ (.+)$ ]]; then
    local timestamp="${BASH_REMATCH[1]}"
    local level="${BASH_REMATCH[2]}"
    local message="${BASH_REMATCH[3]}"
fi

# ✅ GOOD: Safe access with set -u (use default empty string)
if [[ "$line" =~ ^src[[:space:]]+([0-9.]+)[[:space:]]+dst[[:space:]]+([0-9.]+) ]]; then
    current_src="${BASH_REMATCH[1]:-}"  # Prevents "unbound variable" errors
    current_dst="${BASH_REMATCH[2]:-}"
fi
```

**Key Points:**
- Use anchors (`^`, `$`) for precise matching
- Access capture groups via `BASH_REMATCH[1]`, `BASH_REMATCH[2]`, etc.
- Use `${BASH_REMATCH[n]:-}` to provide default empty string when `set -u` is enabled

### String Trimming and Normalization

Always trim and normalize strings from user input:

```bash
# ✅ GOOD: Parameter expansion pattern for trimming
line="${line#"${line%%[![:space:]]*}"}"  # Remove leading spaces
line="${line%"${line##*[![:space:]]}"}"  # Remove trailing spaces

# Remove trailing comments
assignment="${assignment%%#*}"  # Remove everything after first #

# Normalize whitespace before processing
if [[ -z "${line// /}" ]]; then
    continue  # Skip empty lines (after removing all spaces)
fi
```

**Key Points:**
- Use parameter expansion for trimming (efficient, no external commands)
- Handles all POSIX whitespace characters: space, tab, newline, etc.
- Pattern works in all Bash environments without dependencies

**Note:** For project-specific helper functions and patterns, see `CODE_PATTERNS.md`.

### Performance Considerations

Bash string manipulation is efficient for small to medium strings (few KB) and simple operations, but can be slow for large strings or complex operations. For large strings (hundreds of KB or more), complex pattern matching, or operations in tight loops, consider using external tools like `sed` or `awk` for better performance.

### Multi-line String Handling

Use heredocs for multi-line strings and here-strings for single-line input:

```bash
# ✅ GOOD: Heredoc with quoted delimiter (no variable expansion)
cat > "$config_file" <<'EOF'
# Configuration file
server_name=example.com
port=8080
EOF

# ✅ GOOD: Heredoc without quotes (allows variable expansion)
cat > "$template_file" <<EOF
# Generated configuration
server_name=${SERVER_NAME}
port=${PORT:-8080}
EOF

# ✅ GOOD: Here-string for single-line input
grep "pattern" <<< "$variable"
```

**Key Points:**
- Use `<<'EOF'` (quoted delimiter) to prevent variable expansion, `<<EOF` (unquoted) to allow it
- Heredocs preserve newlines and formatting (useful for configuration files, embedded scripts)
- Here-strings (`<<<`) feed single-line strings to commands

---

## Command Substitution

### Use Modern Syntax

Always use `$()` instead of backticks for command substitution:

```bash
# ✅ GOOD: Use $() syntax (modern, nestable) - avoid backticks (legacy, harder to nest)
local timestamp=$(date +%s)
local output=$(command "$(other_command)")
local lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

**Key Points:**
- Always use `$()` instead of backticks
- `$()` is nestable and easier to read
- `$()` works better with quoting
- Backticks are legacy syntax and should be avoided

### Quote Command Substitutions

Always quote command substitutions to prevent word splitting:

```bash
# ✅ GOOD: Always quote command substitutions to prevent word splitting
local output="$(command "$arg")"
local pid="$(cat "$pidfile")"
local lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

### Defensive Command Substitution

Use `|| true` when command substitution failure is acceptable:

```bash
# ✅ GOOD: Use || true when failure is acceptable
output=$(grep -F "pattern" "$file" 2>/dev/null || true)
command_output=$(timeout 5 some_command 2>/dev/null || true)
func_def=$(declare -f some_function 2>/dev/null || true)

# ❌ BAD: Command substitution failure causes script failure (if set -e is enabled)
forward_output=$(echo "$xfrm_output" | grep -F "dst ${peer_ip}" 2>/dev/null)
# If grep finds nothing, exit code is 1, which can cause script failure
```

**When to Use `|| true`:**
- `grep` commands that may not find matches (exit code 1 is normal)
- Commands where failure is expected and handled gracefully

**When NOT to Use `|| true`:**
- Commands where failure indicates a real problem
- Commands that should fail the script if they fail

**Examples:**
```bash
# ✅ GOOD: grep failure is acceptable (no matches found)
output=$(grep "pattern" "$file" 2>/dev/null || true)

# ✅ GOOD: Check exit code explicitly for critical operations
if ! result=$(critical_command 2>&1); then
    handle_error "ERROR" "SYSTEM" "Critical command failed: $result"
fi

# ✅ GOOD: Use || echo "default" when you need a specific default value
timeout=$(get_config_value "timeout" 2>/dev/null || echo "30")
```

### Performance Considerations

Command substitution creates a subshell with overhead. For simple operations, consider alternatives:

```bash
# ⚠️ SLOWER: Command substitution for simple operations
count=$(echo "$items" | wc -l)
uppercase=$(echo "$text" | tr '[:lower:]' '[:upper:]')
value=$(echo "$var")

# ✅ FASTER: Use built-in operations when possible
count=${#array[@]}              # Array length instead of wc -l
uppercase="${text^^}"            # Parameter expansion (Bash 4+)
value="$var"                     # Direct assignment

# ✅ GOOD: Command substitution is appropriate for actual commands
timestamp=$(date +%s)
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

**When to Use Command Substitution:**
- Running actual commands (date, cd, etc.)
- Complex operations requiring external tools
- When overhead is negligible compared to operation

**When to Consider Alternatives:**
- Simple string operations (use parameter expansion)
- Counting elements (use `${#array[@]}`)
- Simple variable assignments (use direct assignment)

### Trailing Newline Pitfall

**Common Pitfall:** Command substitution strips trailing newlines from command output:

```bash
# ❌ PROBLEM: Trailing newline is stripped
file_content=$(cat "$file")
# If file ends with newline, it's removed in $file_content

# ✅ SOLUTION: Append dummy character, then remove it (preserves trailing newline)
file_content=$(cat "$file"; echo x)
file_content="${file_content%x}"  # Remove the 'x', preserves trailing newline

# Alternative: Use process substitution with read loop for line-by-line processing
# Most cases: Trailing newline removal is fine - use simple command substitution
file_content=$(cat "$file")  # Usually this is what you want
```

**When This Matters:**
- When you need to preserve exact file content including trailing newlines
- When comparing file contents byte-for-byte
- When processing files where trailing newlines are significant

**When It Doesn't Matter:**
- Most text processing (trailing newline removal is usually fine)
- When you're going to add a newline anyway (e.g., `echo "$content"`)
- When processing line-by-line (each line's newline is preserved)


### Process Substitution

Use process substitution for feeding multiple commands:

```bash
# ✅ GOOD: Process substitution for feeding multiple commands
while IFS= read -r rule; do
    [[ -n "$rule" ]] && rule_array_ref+=("$rule")
done < <(echo "$rules" | awk -F'\\|\\|\\|' '{for(i=1;i<=NF;i++) print $i}')

# ✅ GOOD: Compare outputs from two commands
diff <(command1) <(command2)
```

**Key Points:**
- Use `< <()` for process substitution (input redirection)
- Use `> >()` for output process substitution
- Useful for feeding pipelines to commands that expect file input

### Background Jobs and Process Management

Use background jobs (`&`) to run commands asynchronously, then use `wait` with the process ID:

```bash
# ✅ GOOD: Run command in background, capture PID immediately, wait for completion
command &
pid=$!  # Capture immediately - $! is overwritten by next background job
# ... do other work ...
wait "$pid"  # Always quote PID variable

# ✅ GOOD: With cleanup (use || true to handle already-exited case)
(
    exec 200>"${lockfile}"
    flock -x 200
    do_work
) &
pid=$!
# ... do other work ...
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

# Multiple background processes
pids=()
for item in "${items[@]}"; do
    process_item "$item" &
    pids+=($!)
done
for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
done
```

**Key Points:**
- Capture PID immediately with `$!` (overwritten by next background job)
- Use `|| true` with `wait` if process may have already exited
- Use subshells `()` for complex background commands
- Always quote PID variable when using `wait`

**Note:** Background jobs are commonly used in test code. For production, consider cron-based execution or systemd services.

---

## Arithmetic Operations

### Arithmetic Expansion

Use `$(( ))` for arithmetic operations:

```bash
# ✅ GOOD: Use arithmetic expansion $(( )) - avoid expr (slower, less portable)
local count=$((count + 1))
local total=$((value1 + value2))
local result=$((value * 2))
```

**Key Points:**
- Use `$(( ))` for all arithmetic operations
- No quotes needed inside `$(( ))`
- Variables don't need `$` prefix inside `$(( ))` (but it's safe to include)

### Post-Increment with `set -e` Pitfall

**Important:** When using `set -e` (errexit), post-increment `((variable++))` can cause script exit if the variable starts at 0.

```bash
# ❌ BAD: With set -e, this exits when count=0
local count=0
((count++))  # Evaluates to 0 (false), script exits with set -e

# ✅ GOOD: Use pre-increment instead
local count=0
((++count))  # Evaluates to 1 (true), safe with set -e

# ✅ GOOD: Use explicit assignment
local count=0
count=$((count + 1))  # Always succeeds, safe with set -e
```

**Why:** Post-increment `((count++))` returns the value before increment. When `count=0`, it evaluates to 0 (false), which triggers `set -e` to exit the script. Pre-increment `((++count))` returns the value after increment, so it evaluates to 1 (true) when `count=0`.

**When This Matters:**
- Standalone arithmetic statements (not in conditions)
- Variables initialized to 0
- Scripts or functions called from contexts with `set -e` enabled (e.g., BATS tests)

**Note:** This doesn't apply to C-style for loops `for ((i = 0; i < 10; i++))` because `set -e` is disabled in loop conditions.

### Integer Overflow Limitations

**Important:** Bash uses signed 64-bit integers (maximum: 9,223,372,036,854,775,807). Very large numbers can overflow, and operations exceeding the maximum will wrap around with undefined behavior. For timestamp calculations, large counters, or financial calculations, validate results and consider using external tools like `bc` or `awk`. For project-specific safe timestamp arithmetic functions, see `CODE_PATTERNS.md`.

### C-Style For Loops

Use C-style for loops for arithmetic iteration:

```bash
# ✅ GOOD: C-style for loop
for ((i = 0; i < scale; i++)); do
    multiplier=$((multiplier * 10))
done

# ✅ GOOD: C-style for loop with multiple variables
for ((i = 0, j = 10; i < 10; i++, j--)); do
    echo "i=$i, j=$j"
done
```

**Key Points:**
- Use `(( ))` for C-style for loops
- No `$` prefix needed for variables inside `(( ))`
- Useful for arithmetic-based iteration

### Floating-Point Arithmetic

Bash only supports integer arithmetic. For floating-point calculations, use external tools:

**Using `awk` (recommended for most cases):**

```bash
# ✅ GOOD: Use awk for floating-point arithmetic
percentage=$(awk "BEGIN {printf \"%.2f\", ($count / $total) * 100}")
# With division by zero check:
result=$(awk -v count="$count" -v total="$total" 'BEGIN {
    if (total == 0) { printf "0" } else { printf "%.2f", (count / total) * 100 }
}')
```

**Using `bc` (for high precision or complex calculations):**

```bash
# ✅ GOOD: Use bc for high-precision calculations
result=$(echo "scale=2; $value1 / $value2" | bc)
```

**Key Points:**
- **`awk`**: Recommended for most floating-point operations (fast, widely available, supports conditional logic)
- **`bc`**: Use for high-precision or very complex calculations (arbitrary precision)
- Always check for division by zero before calculations
- Validate inputs are numeric before calculations (see Input Validation section)

---

## Control Flow

### If Statements

Use `[[ ]]` for conditional tests (preferred over `[ ]`):

```bash
# ✅ GOOD: Use [[ ]] for tests
if [[ -f "$file" ]]; then
    process_file "$file"
fi

if [[ -n "$variable" ]] && [[ -r "$file" ]]; then
    read_file "$file"
fi
```

**Key Points:**
- `[[ ]]` supports pattern matching, regex, and more operators
- **Always quote variables in `[[ ]]` tests** (prevents issues with `set -u`, spaces, and ensures consistency)
- Use `[ ]` only for POSIX compatibility when needed

### Case Statements

Use case statements for multiple value comparisons:

```bash
# ✅ GOOD: Case statement with quoted variable
case "$arg" in
    --help | -h)
        show_help
        exit 0
        ;;
    --version | -v)
        show_version
        exit 0
        ;;
    --fake)
        NO_ESCALATE=1
        export NO_ESCALATE
        ;;
    *)
        echo "Unknown option: $arg" >&2
        exit 1
        ;;
esac
```

**Key Points:**
- Quote the variable: `case "$var" in`
- Patterns don't need quotes (but can be quoted for safety)
- Use `|` to separate multiple patterns
- Always include `*)` catch-all pattern
- Use `;;` to end each pattern block

**Example:**
```bash
for arg in "$@"; do
    case "$arg" in
        --help | -h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --help     Show this help message"
            echo "  --version  Show version information"
            exit 0
            ;;
        --version | -v)
            echo "Script v${VERSION:-1.0.0}"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done
```

### Conditional Execution

Use `&&` and `||` for conditional command execution:

```bash
# ✅ GOOD: Conditional execution
[[ -f "$file" ]] && process_file "$file"
[[ ! -d "$dir" ]] && mkdir -p "$dir"

command1 && command2  # Run command2 only if command1 succeeds
command1 || command2  # Run command2 only if command1 fails

# ✅ GOOD: Combined with error handling
if ! ensure_directory_exists "$STATE_DIR" "state"; then
    handle_error_or_exit_fake_mode "SYSTEM" "Failed to create state directory" "${EXIT_GENERAL_ERROR:-1}"
fi
```

**Key Points:**
- `&&` runs second command only if first succeeds, `||` runs only if first fails

### While and Until Loops

Use while/until loops for condition-based iteration:

```bash
# ✅ GOOD: While loop with timeout
local start_time=$(date +%s)
local timeout=30
while true; do
    local elapsed=$(( $(date +%s) - start_time ))
    if [[ $elapsed -ge $timeout ]]; then
        break  # Timeout reached
    fi
    if check_condition; then
        break  # Condition met
    fi
    sleep 1
done

# ✅ GOOD: Until loop (runs until condition is true)
until check_condition; do
    sleep 1
done
```

**Key Points:**
- `while` runs while condition is true, `until` runs until condition is true
- Always include timeout or max attempts to prevent infinite loops

### Break vs Continue

Understanding when to use `break` vs `continue` is crucial for loop control:

```bash
# ✅ GOOD: Use break to exit the entire loop
for file in "${files[@]}"; do
    if [[ -f "$file" ]] && [[ -r "$file" ]]; then
        process_file "$file"
        break  # Found the file, exit loop entirely
    fi
done

# ✅ GOOD: Use continue to skip to next iteration
for file in "${files[@]}"; do
    if [[ ! -f "$file" ]]; then
        continue  # Skip this file, continue with next iteration
    fi
    if [[ ! -r "$file" ]]; then
        continue  # Skip this file, continue with next iteration
    fi
    process_file "$file"  # Only processes readable files
done
```

**When to Use:**
- `break`: Exit the entire loop (found target, error, timeout)
- `continue`: Skip current iteration but continue loop (filtering, validation failures)

### Breaking Out of Nested Loops

When you need to exit multiple nested loops, use a flag variable:

```bash
# ✅ GOOD: Use flag variable to break out of nested loops
found=0
for outer_item in "${outer_array[@]}"; do
    for inner_item in "${inner_array[@]}"; do
        if check_match "$outer_item" "$inner_item"; then
            found=1
            break  # Exit inner loop
        fi
    done
    
    # Check flag after inner loop
    if [[ $found -eq 1 ]]; then
        break  # Exit outer loop
    fi
done

# ✅ GOOD: Using function return to exit nested loops
search_nested() {
    for outer in "${outer_array[@]}"; do
        for inner in "${inner_array[@]}"; do
            if check_match "$outer" "$inner"; then
                return 0  # Exit function (and all loops)
            fi
        done
    done
    return 1  # Not found
}

# Usage:
if search_nested; then
    echo "Match found"
fi
```

**Key Points:**
- Bash doesn't support labeled breaks (like `break 2` in some languages)
- Use flag variables to break out of nested loops
- Check the flag after each inner loop completes
- Consider using functions to encapsulate nested loops (can use `return` to exit)
- Use descriptive flag names (`found`, `match_found`, `done`, etc.)

**When to Use Each Pattern:**
- **Flag variable**: When you need to break out of 2-3 levels of nesting
- **Function return**: When nesting is deep or the logic is complex enough to warrant a function
- **Restructure**: Consider if nested loops can be simplified or if a function would be clearer

---

## File Operations

### Reading Files Line by Line

Always handle files without trailing newlines:

```bash
# ✅ GOOD: Read file line by line with proper handling
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
- Use `IFS= read -r` to preserve whitespace, always use `|| [[ -n "$line" ]]` to handle files without trailing newline

### Atomic File Writes

Use atomic writes for state files to prevent corruption:

```bash
# ✅ GOOD: Atomic write pattern (use sync before mv for critical writes that must be flushed to disk)
if ! (echo "$data" > "${file}.tmp" && sync && mv "${file}.tmp" "$file"); then
    log_message "ERROR" "SYSTEM" "Failed to write state file: $file"
    return 1
fi

# ❌ BAD: Direct write (can be corrupted if script interrupted)
echo "$data" > "$file"  # Not atomic!
```

**Key Points:**
- Write to temporary file first (`${file}.tmp`), then use `mv` to atomically replace the original file
- Use `sync` before `mv` for critical writes that must be persisted to disk immediately
- The `mv` operation is atomic on the same filesystem (all-or-nothing)
- If write fails, original file remains unchanged

**Note:** For state file management patterns including using abstraction layers for state file paths, per-location state tracking, and state file format validation, see `CODE_PATTERNS.md` section on [State Management Patterns](CODE_PATTERNS.md#state-management-patterns).

### File Existence Checks

Always check file readability and directory writability before operations:

```bash
# ✅ GOOD: Check readability before reading
if [[ ! -r "$config_file" ]]; then
    log_message "ERROR" "SYSTEM" "Config file not readable: $config_file"
    return 1
fi

# ✅ GOOD: Check directory exists and is writable
if [[ ! -d "$state_dir" ]] || [[ ! -w "$state_dir" ]]; then
    log_message "ERROR" "SYSTEM" "State directory not writable: $state_dir"
    return 1
fi
```

**Note:** For detailed file operation patterns including checking readability before file operations, removing before atomic write, and handling leftover temporary files, see `CODE_PATTERNS.md` section on [File Operation Patterns](CODE_PATTERNS.md#file-operation-patterns).

### Redirection Patterns

Use proper redirection for output and errors:

```bash
# ✅ GOOD: Redirect stderr for error messages
echo "Error message" >&2

# ✅ GOOD: Redirect both stdout and stderr
command > "$log_file" 2>&1

# ✅ GOOD: Use command grouping for multiple redirects to same file (more efficient)
{
    echo "Line 1"
    echo "Line 2"
} >> "$log_file"
```

**Key Points:**
- `>&2` redirects to stderr, `2>&1` redirects stderr to stdout
- `>` truncates file, `>>` appends to file
- Use `{ cmd1; cmd2; } >> file` for multiple redirects to same file

### Temporary File Creation

Always use `mktemp` to create temporary files safely:

```bash
# ✅ GOOD: Create temporary file with mktemp and clean up with EXIT trap
temp_file=$(mktemp) || {
    log_message "ERROR" "SYSTEM" "Failed to create temporary file"
    return 1
}
cleanup_temp_file() {
    rm -f "${temp_file:-}"  # Use default value expansion for set -u
}
trap cleanup_temp_file EXIT

# ✅ GOOD: Create temporary directory or file with suffix
temp_dir=$(mktemp -d) || return 1
temp_file=$(mktemp --suffix=.tmp) || return 1
# Always use mktemp - never hardcode temporary file paths (security risk, race conditions)
```

**Key Points:**
- Always use `mktemp` (prevents race conditions and security issues)
- Use `mktemp -d` for directories, `--suffix` for file extensions
- Always clean up with EXIT trap, use `${var:-}` in cleanup functions for `set -u`
- **For sensitive data**: Use `umask 077` before `mktemp` and `chmod 600` after creation

**Example:**
```bash
temp_file1=$(mktemp)
temp_file2=$(mktemp)

# Use cleanup function to defer variable expansion until trap executes
# This satisfies shellcheck SC2064: variables expand when trap executes, not when it's set
# Use default value expansion to handle case where variables might be unset (set -u)
cleanup_temp_files() {
    rm -f "${temp_file1:-}" "${temp_file2:-}"
}
trap cleanup_temp_files EXIT
```

### File Locking

Use file locking to prevent concurrent access and race conditions:

**Using `flock` (preferred when available):**

```bash
# ✅ GOOD: Use flock for file locking (use atomic file creation as fallback when flock unavailable)
if command -v flock >/dev/null 2>&1; then
    (
        exec 9>"$lockfile"
        if ! flock -n 9; then  # -n: non-blocking (fail immediately if lock can't be acquired)
            log_message "ERROR" "SYSTEM" "Could not acquire lock: $lockfile"
            exit 1
        fi
        # Critical section - file is locked
        echo "$data" > "$target_file"
        exec 9>&-  # Lock released when file descriptor closes
    ) 9>"$lockfile"
else
    # Fallback: Atomic file creation as lock mechanism
    if (set -C; echo "$$" > "$lockfile" 2>/dev/null); then
        trap 'rm -f "$lockfile"' EXIT
        echo "$data" > "$target_file"
        rm -f "$lockfile"
        trap - EXIT
    else
        log_message "ERROR" "SYSTEM" "Could not acquire lock: $lockfile"
        return 1
    fi
fi
```

**Key Points:**
- Use `flock` when available (more reliable, automatic cleanup)
- Use atomic file creation (`set -C` with `noclobber`) as fallback
- Always clean up lockfiles (use EXIT trap)
- Use non-blocking locks (`flock -n`) to avoid hanging
- Check if lockfile is stale (process holding lock may have died)

### File Safety Patterns Summary

**Key Principles:**
- **Atomicity**: Use write-tmp-move pattern for all critical writes
- **Locking**: Use file locks for concurrent access scenarios
- **Cleanup**: Always clean up temporary files and locks
- **Validation**: Check permissions and existence before operations (use `[[ -r "$file" ]]` for reading, `[[ -w "$dir" ]]` for writing)
- **Error Handling**: Handle all failure modes gracefully

**Path Security:**
- Validate file paths exist and are readable/writable before operations
- Check for directory traversal attempts (`[[ "$file_path" =~ \.\. ]]`)
- Use `realpath` to resolve symlinks and canonicalize paths
- Validate paths are within allowed directories when restricting access

**Note:** For comprehensive file operation patterns including atomic writes, readability checks, temporary file cleanup, and state file management, see `CODE_PATTERNS.md` section on [File Operation Patterns](CODE_PATTERNS.md#file-operation-patterns).

---

## Input Validation

### Validate Function Parameters

Always validate function parameters:

```bash
# ✅ GOOD: Validate parameters
process_item() {
    local item="$1"
    
    if [[ -z "$item" ]]; then
        echo "ERROR: Item is required" >&2
        return 1
    fi
    
    if ! validate_input "$item"; then
        echo "ERROR: Invalid item format: $item" >&2
        return 1
    fi
    
    # ... rest of function ...
}
```

### Validate Script Arguments

Validate script arguments early:

```bash
# ✅ GOOD: Validate script arguments
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <source> <destination>" >&2
    exit 1
fi

source="$1"
destination="$2"

# Validate arguments are not empty
if [[ -z "$source" ]] || [[ -z "$destination" ]]; then
    echo "Error: Source and destination cannot be empty" >&2
    exit 1
fi
```

### Validate Numeric Input

Always validate numeric input before using it in calculations:

**Validate Integers:**

```bash
# ✅ GOOD: Validate integer with optional range check
validate_integer() {
    local value="$1"
    local min="${2:-}"
    local max="${3:-}"
    
    if [[ -z "$value" ]] || ! [[ "$value" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    if [[ -n "$min" ]] && [[ $value -lt $min ]]; then
        return 1
    fi
    if [[ -n "$max" ]] && [[ $value -gt $max ]]; then
        return 1
    fi
    
    return 0
}

# Usage:
if ! validate_integer "$count"; then
    log_message "ERROR" "SYSTEM" "Count must be a non-negative integer"
    return 1
fi

if ! validate_integer "$percentage" 0 100; then
    log_message "ERROR" "SYSTEM" "Percentage must be between 0 and 100"
    return 1
fi
```

**Validate Floating-Point Numbers:**

```bash
# ✅ GOOD: Validate floating-point number with optional range check
validate_float() {
    local value="$1"
    local min="${2:-}"
    local max="${3:-}"
    
    if [[ -z "$value" ]]; then
        return 1
    fi
    
    # Check if value is a valid float
    if ! [[ "$value" =~ ^[+-]?[0-9]+\.?[0-9]*$ ]] && ! [[ "$value" =~ ^[+-]?\.[0-9]+$ ]]; then
        return 1
    fi
    
    # Use awk for floating-point range comparison if needed
    if [[ -n "$min" ]] || [[ -n "$max" ]]; then
        if ! awk "BEGIN {exit !($value >= ${min:-0} && $value <= ${max:-999999999})}"; then
            return 1
        fi
    fi
    
    return 0
}

# Usage:
if ! validate_float "$ratio" 0.0 1.0; then
    log_message "ERROR" "SYSTEM" "Ratio must be between 0.0 and 1.0"
    return 1
fi
```

**Key Points:**
- Use `^[0-9]+$` for non-negative integers
- Use regex patterns for floating-point validation
- Use `awk` for floating-point range comparisons
- Always validate before using in arithmetic operations

**Example:**
```bash
validate_integer() {
    local value="$1"
    local var_name="${2:-value}"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "ERROR: $var_name must be an integer (current value: '$value')" >&2
        return 1
    fi
    
    return 0
}
```

**Note:** For security-focused validation (file paths, IP addresses, user input sanitization), see Security Checklist section.

### Common Validation Patterns

**Note:** For project-specific validation patterns including using validation functions instead of inline regex, supplementary diagnostics, and codebase-specific validation functions, see `CODE_PATTERNS.md` section on [Validation Patterns](CODE_PATTERNS.md#validation-patterns). For historical context on validation lessons learned, see `CODE_REVIEW_LESSONS_LEARNED.md` [Lesson 2: Always Use Validation Functions Instead of Inline Regex](CODE_REVIEW_LESSONS_LEARNED.md#2-always-use-validation-functions-instead-of-inline-regex).

This section provides reusable validation functions for common use cases:

```bash
# Validate non-empty string
validate_non_empty() {
    local value="$1"
    [[ -n "$value" ]]
}

# Validate integer (non-negative)
validate_integer() {
    local value="$1"
    [[ -n "$value" ]] && [[ "$value" =~ ^[0-9]+$ ]]
}

# Validate integer with range
validate_integer_range() {
    local value="$1"
    local min="$2"
    local max="$3"
    if ! validate_integer "$value"; then
        return 1
    fi
    [[ $value -ge $min ]] && [[ $value -le $max ]]
}

# Validate floating-point number
validate_float() {
    local value="$1"
    [[ -n "$value" ]] && [[ "$value" =~ ^[+-]?[0-9]+\.?[0-9]*$ ]] || [[ "$value" =~ ^[+-]?\.[0-9]+$ ]]
}

# Validate file exists and is readable
validate_file_readable() {
    local file_path="$1"
    [[ -n "$file_path" ]] && [[ -f "$file_path" ]] && [[ -r "$file_path" ]]
}

# Validate directory exists and is writable
validate_directory_writable() {
    local dir_path="$1"
    [[ -n "$dir_path" ]] && [[ -d "$dir_path" ]] && [[ -w "$dir_path" ]]
}

# Validate path doesn't contain directory traversal
validate_path_no_traversal() {
    local path="$1"
    [[ -n "$path" ]] && [[ ! "$path" =~ \.\. ]]
}

# Validate IP address format (basic check)
validate_ip_format() {
    local ip="$1"
    # Basic format check - validates structure, not valid ranges
    [[ -n "$ip" ]] && [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
}

# Note: For production code, use proper validation that checks octet ranges (0-255)
# For project-specific IP validation functions, see CODE_PATTERNS.md
```

**Usage Examples:**

```bash
# Validate function parameters
process_data() {
    local count="$1"
    local file_path="$2"
    
    # Validate count is a positive integer
    if ! validate_integer_range "$count" 1 1000; then
        log_message "ERROR" "SYSTEM" "Count must be between 1 and 1000"
        return 1
    fi
    
    # Validate file path
    if ! validate_file_readable "$file_path"; then
        log_message "ERROR" "SYSTEM" "File not readable: $file_path"
        return 1
    fi
    
    # Process data...
}
```

**Key Principles:**
- **Early Validation**: Validate inputs as early as possible (function entry, script start)
- **Defense in Depth**: Validate at multiple layers (entry point, before use)
- **Clear Error Messages**: Provide specific error messages indicating what failed and why
- **Consistent Patterns**: Use consistent validation patterns throughout your codebase
- **Reusable Functions**: Create reusable validation functions for common patterns

---


## Security Best Practices

**Note:** Security considerations are integrated throughout this guide:
- **Path validation**: See File Operations section
- **Input validation**: See Input Validation section
- **Command injection prevention**: Always quote variables (see Variable Usage section), never use `eval` with user input
- **Secure temporary files**: Use `mktemp` with restrictive permissions (`chmod 600` for sensitive data, see File Operations section)

### Security Checklist

**Input Validation:**
- [ ] All user input is validated before use
- [ ] File paths are validated to prevent directory traversal (`..` checks)
- [ ] IP addresses are validated with proper range checks (not just format)
- [ ] Numeric input is validated (integers, ranges)
- [ ] String input is sanitized (remove dangerous characters)

**Command Execution:**
- [ ] All variables are quoted in commands
- [ ] No `eval` with user input
- [ ] Command arguments use arrays when building dynamically
- [ ] Input is validated before using in command construction

**File Operations:**
- [ ] Temporary files use `mktemp` (not hardcoded paths)
- [ ] Temporary files have restrictive permissions (600 for files, 700 for directories)
- [ ] Sensitive data files have restrictive permissions (600)
- [ ] File paths are validated before operations
- [ ] Atomic file writes are used for critical files

**Sensitive Data:**
- [ ] Passwords, keys, and tokens are never logged
- [ ] Sensitive data is stored in files with restrictive permissions (600)
- [ ] Sensitive data is not passed via command-line arguments
- [ ] Sensitive variables are cleared after use
- [ ] Credentials are not stored in code or version control

**Path Security:**
- [ ] Absolute paths are used when security is critical
- [ ] Command availability is checked when portability is needed
- [ ] Directory traversal attacks are prevented (`..` checks)

**Error Handling:**
- [ ] Error messages don't leak sensitive information
- [ ] Debug output doesn't include sensitive data
- [ ] Log files don't contain passwords or keys

**General:**
- [ ] Scripts use `set -euo pipefail` for strict error handling
- [ ] All file operations check permissions before access

---

## Code Quality Tools

### ShellCheck

Use ShellCheck for static analysis:

```bash
# Check all shell scripts
shellcheck *.sh lib/*.sh tests/*.sh

# Check with specific severity
shellcheck --severity=error *.sh

# Check specific file
shellcheck vpn-monitor.sh
```

**Common ShellCheck Issues:**
- **SC2034**: Unused variable - Remove if truly unused, or mark with `# shellcheck disable=SC2034`
- **SC2155**: Declare and assign separately - Split declaration and assignment
- **SC2162**: Read without -r - Add `-r` flag to `read` commands
- **SC2129**: Multiple redirects - Use `{ cmd1; cmd2; } >> file`

**Common ShellCheck False Positives:**

Some ShellCheck warnings are false positives (the code is correct, but ShellCheck can't detect it):

**Common False Positives:**

```bash
# ⚠️ SC2064: Variables expand when trap executes (often intentional)
temp_file=$(mktemp)
trap "rm -f $temp_file" EXIT  # ShellCheck warns, but expansion is intentional

# ✅ GOOD: Use function to defer expansion (satisfies ShellCheck)
temp_file=$(mktemp)
cleanup_temp() { rm -f "${temp_file:-}"; }
trap cleanup_temp EXIT

# ⚠️ SC2154/SC1090: Variables from sourced files or dynamic paths
source "${LIB_DIR}/config.sh"
echo "$CONFIG_VALUE"  # ShellCheck can't see variable from sourced file

# ✅ GOOD: Use shellcheck source directive
# shellcheck source=lib/config.sh
source "${LIB_DIR}/config.sh"
echo "$CONFIG_VALUE"  # ShellCheck now understands the variable

# ⚠️ SC2094: File descriptor in subshell (often safe)
# shellcheck disable=SC2094
# File descriptor 9 is intentionally used for lockfile in subshell
( exec 9>"$lockfile"; flock -n 9 ) 9>"$lockfile"
```

**When to Disable ShellCheck Warnings:**

Only disable ShellCheck warnings when:
1. **The warning is a false positive** (code is correct, ShellCheck can't detect it)
2. **The code pattern is intentional** (e.g., variable expansion in trap handlers)
3. **You've verified the code is safe** (not just to silence warnings)
4. **You provide a clear explanation** (why the warning is disabled)

**Disabling Checks - Best Practices:**

```bash
# ✅ GOOD: Disable with clear explanation
# shellcheck disable=SC2034
# This variable is used by sourced scripts (not directly in this file)
CONFIG_VAR="value"

# ✅ GOOD: Disable with inline explanation
temp_file=$(mktemp)
# shellcheck disable=SC2064
# Variables expand when trap executes, not when trap is set (intentional)
trap "rm -f $temp_file" EXIT

# ❌ BAD: Disable without explanation
# shellcheck disable=SC2034
CONFIG_VAR="value"  # Why is this disabled? Unclear!

# ❌ BAD: Disable to silence real issues
# shellcheck disable=SC2162
read line  # Should use read -r, don't disable the warning!
```

**Key Principles:**
- **Always explain why** you're disabling a check
- **Verify it's a false positive** before disabling
- **Prefer fixing the code** over disabling warnings
- **Use shellcheck source directives** to help ShellCheck understand sourced files
- **Document intentional patterns** (e.g., variable expansion in traps)

**For More Information:**

- **ShellCheck Wiki**: https://github.com/koalaman/shellcheck/wiki
- **ShellCheck Documentation**: https://www.shellcheck.net/
- **Common Issues**: https://github.com/koalaman/shellcheck/wiki/SC2034
- **False Positives Guide**: See ShellCheck wiki for each specific error code

**Example:**
```bash
# Use cleanup function to defer variable expansion until trap executes
# This satisfies shellcheck SC2064: variables expand when trap executes, not when it's set
cleanup() {
    rm -f "${temp_file:-}"
}
trap cleanup EXIT
```

### shfmt

Use shfmt for consistent formatting:

```bash
# Format all shell scripts (in-place)
shfmt -w *.sh lib/*.sh tests/*.sh

# Check formatting without modifying files
shfmt -d *.sh

# Format specific file
shfmt -w script.sh
```

**Formatting Standards:**
- Use **tabs** for indentation (enforced by shfmt)
- Tab width: 8 spaces (default)

---

## Bash Version and Platform Considerations

This section covers version-specific features and platform considerations for Bash scripts.

### Bash Version Requirements

**Target Version:** Bash 4.0+ (standard on UDM OS 4.3+)

**Bash 4.0+ Features Used:**
- Associative arrays (`declare -A`)
- Namerefs (`local -n`)
- Parameter expansion enhancements (`${var,,}`, `${var^^}`)

```bash
# ✅ GOOD: Pre-declare associative arrays (Bash 4.0+)
declare -A MY_ARRAY
MY_ARRAY["key"]="value"

# ❌ BAD: Using associative arrays without declaration
MY_ARRAY["key"]="value"  # Error on Bash 3.x
```

**Key Points:**
- Always declare associative arrays before use
- This project targets Bash 4.0+ (UDM OS 4.3+ standard)
- Use `BASH_VERSION` variable to check version if needed

### Platform-Specific Considerations

**Target Platform:** UDM OS 4.3+ (Debian-based Linux)

**1. Command Availability**

```bash
# ✅ GOOD: Check command availability (PATH restrictions in cron/systemd)
if command -v timeout >/dev/null 2>&1; then
    timeout 5 some_command
else
    echo "ERROR: timeout command not available" >&2
fi

# Available: bash, ip, ipsec, ping, timeout, awk, sed, grep, cut, head, tail, date, stat
# NOT available: python3, node, jq (use awk instead)
```

**2. Linux-Specific Command Syntax**

```bash
# ✅ GOOD: Linux-specific syntax
date -d "1 hour ago"    # Linux: -d flag
stat -c "%Y" "$file"     # Linux: -c flag
ping -W 5 "$host"        # Linux: -W flag (timeout in seconds)
nproc                    # Linux: number of processors

# ❌ BAD: BSD/macOS syntax (not compatible)
date -v-1H               # BSD: -v flag (not on Linux)
stat -f "%m" "$file"     # BSD: -f flag (not on Linux)
```

**3. Environment and PATH**

```bash
# ✅ GOOD: Set PATH explicitly (cron/systemd have minimal PATH)
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ✅ GOOD: Use default value expansion for environment variables
DEBUG="${DEBUG:-0}"  # Default to 0 if not set
```

**4. Persistent Storage**

```bash
# ✅ GOOD: Use persistent storage directory
STATE_DIR="/var/lib/myapp"

# ❌ BAD: Using /tmp (cleared on reboot)
STATE_DIR="/tmp/myapp"  # Lost on reboot!
```

**5. Network Commands**

```bash
# ✅ GOOD: Always use timeout for network commands
if command -v timeout >/dev/null 2>&1; then
    output=$(timeout 5 ping -c 1 "$host" 2>&1 || true)
fi
```

**Key Points:**
- Always check command availability before use
- Use Linux-specific command syntax (not BSD/macOS)
- Set PATH explicitly in scripts run from cron/systemd
- Use default value expansion for environment variables
- Use timeout for network commands

---

## Common Mistakes

This section lists common mistakes not covered in detail elsewhere. For detailed explanations, see the referenced sections.

**Common Mistakes Covered in Other Sections:**
- **Array Iteration Mistakes**: See "Regular Arrays" and "Common Array Mistakes" sections
- **Unquoted Variable Expansions**: See "Always Quote Variables" section
- **Command Substitution Trailing Newlines**: See "Trailing Newline Pitfall" in Command Substitution section
- **Strict Mode Pitfalls**: See "Common Strict Mode Pitfalls" in Error Handling and Strict Mode section
- **Associative Array Declaration**: See "Associative Arrays" section
- **Temporary File Security**: See "Temporary File Creation" in File Operations section
- **Module Sourcing**: See "Module Sourcing" section
- **Script Directory Setup**: See "Directory Setup" in Script Structure and Setup section

### Function Return Value Mistakes

```bash
# ❌ BAD: Ignoring return values
my_function  # Return value ignored
echo "Done"   # Executes even if function failed

# ✅ GOOD: Always check return values
if ! my_function; then
    echo "ERROR: Function failed" >&2
    return 1
fi
```

### Loop Variable Scope Issues

```bash
# ❌ BAD: Loop variable not declared as local (overwrites global)
for item in "${items[@]}"; do  # Overwrites global variable!
    process_item "$item"
done

# ✅ GOOD: Declare loop variable as local
local item
for item in "${items[@]}"; do
    process_item "$item"
done
```

### Quick Reference Checklist

**Before submitting code, check:**
- [ ] Arrays use `[@]` not `[*]` for iteration
- [ ] All variables are quoted
- [ ] Command substitutions handle failures (`|| true` or `if` statement)
- [ ] Function return values are checked
- [ ] Loop variables are declared as `local` in functions
- [ ] Associative arrays are pre-declared
- [ ] Temporary files use `mktemp` (not hardcoded paths)
- [ ] Modules are idempotent (safe to source multiple times)
- [ ] Script directory uses `BASH_SOURCE[0]` not `$0`
- [ ] Commands are checked for availability before use
- [ ] Linux-specific syntax is used (not BSD/macOS)
- [ ] Network commands use timeout

---

## Documentation Standards

### Function Documentation

All functions must have documentation. Use the appropriate level of detail based on function complexity:

**Full Documentation Template (for complex functions):**

```bash
# Function name and brief description
#
# Detailed description of what the function does, including purpose, behavior,
# and any important dependencies or algorithms used.
#
# Arguments:
#   $1: Parameter name (type) - Description
#   $2: Parameter name (type) - Description
#
# Returns:
#   0: Success condition description
#   1: Failure condition description
#
# Side effects:
#   - File operations, logging, or state changes (if any)
#
# Examples:
#   if function_name "arg1"; then
#       echo "Success"
#   fi
function_name() {
    # Implementation
}
```

**Minimal Documentation Template (for simple functions):**

For simple, self-explanatory functions, use a minimal documentation format:

```bash
# Function name and brief description
#
# Arguments:
#   $1: Parameter name (type) - Description
#
# Returns:
#   0: Success
#   1: Failure
simple_function() {
    # Implementation
}
```

**When to Use Minimal vs Full Documentation:**

- **Use minimal documentation** for:
  - Simple wrapper functions
  - Self-explanatory utility functions
  - Functions with obvious behavior from the name
  - Functions with no side effects and simple logic

- **Use full documentation** for:
  - Complex functions with non-obvious behavior
  - Functions with significant side effects
  - Functions with multiple dependencies
  - Functions that are part of the public API
  - Functions with non-trivial algorithms

**Examples:**

```bash
# ✅ GOOD: Minimal documentation for simple function
# Log an informational message
#
# Arguments:
#   $@: Message text (all arguments are concatenated with spaces)
#
# Returns:
#   0: Always succeeds
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

# ✅ GOOD: Full documentation for complex function
# Check if VPN peer is active
#
# Verifies VPN tunnel health by checking IPsec Security Association state.
# Uses multiple detection methods with automatic fallback.
#
# Arguments:
#   $1: Peer IP address (external/public IP of remote VPN gateway)
#
# Returns:
#   0: Item is valid
#   1: Item validation failed
#
# Side effects:
#   - Creates/updates state file if validation succeeds
#   - Logs debug/warning messages about validation state
validate_and_process() {
    local item="$1"
    # ... implementation ...
}
```

**Required Sections:**
- **Function name and brief description**: Always required
- **Arguments**: Always required (use "None" if function takes no arguments)
- **Returns**: Always required

**Optional Sections (include when relevant):**
- **Side effects**: Include for functions that modify files, log, or change state
- **Examples**: Include for complex or commonly-used functions
- **Note**: Include for dependencies, requirements, or special considerations

### Script Documentation

Document scripts with headers explaining purpose and usage:

```bash
#!/bin/bash
#
# Script Name
# Brief description of what the script does
#
# Usage:
#   script.sh [OPTIONS] [ARGUMENTS]
#
# Options:
#   --help     Show help message
#   --version  Show version information
#
# Examples:
#   script.sh --help
#   script.sh input_file output_file
#
# Requirements:
#   - Bash 4.0+
#   - Required commands: command1, command2
#
# Version: 1.0.0
#
```

### Inline Comments

Add comments for complex logic:

```bash
# ✅ GOOD: Explain complex logic
# Use safe timestamp arithmetic to prevent underflow
# Direct arithmetic can cause infinite loops if timestamps wrap
local elapsed
elapsed=$(safe_timestamp_diff "$(get_unix_timestamp)" "$start_time" 2>/dev/null || echo "0")

# ✅ GOOD: Explain non-obvious behavior
# Character classes [*] and [?] match literal characters
# Direct * or ? would match entire string or every character
escaped="${location//[*]/\\*}"
```

### TODO and FIXME Comments

Use TODO and FIXME comments to track future improvements and known issues:

- **TODO**: Planned improvements or features to implement (new functionality, refactoring, optimizations)
- **FIXME**: Known bugs or issues that need fixing (bugs, workarounds, code needing improvement)

**Comment Format:**

```bash
# ✅ GOOD: TODO with context and priority
# TODO: Add retry logic for transient network failures (low priority)
# TODO: Refactor duplicate code in recovery functions (high priority)

# ✅ GOOD: FIXME with explanation
# FIXME: Temporary workaround for missing command
#        Remove when UDM OS includes 'jq' command
#        Current workaround: use awk for JSON parsing

# ❌ BAD: Vague TODO without context
# TODO: Fix this
# TODO: Improve later
```

**Tracking:**
- **TODO.md**: Track planned improvements and tasks (high/medium/low priority)
- **FIXME comments**: Use inline comments for known bugs (include explanation, reference issues)

**Key Principles:**
- Be specific: Include what needs to be done and why
- Include context: Explain current state and desired improvement
- Reference tracking: Link to TODO.md or issue numbers when applicable
- Prioritize: Indicate priority level (high/medium/low) when relevant

---

## Module Sourcing

Source modules safely with proper path resolution, error handling, and idempotency:

```bash
# ✅ GOOD: Safe module sourcing with path resolution
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source required module - fail fast if it can't be loaded
source "${LIB_DIR}/common.sh" || {
    echo "Error: Failed to source ${LIB_DIR}/common.sh" >&2
    exit 1
}

# ✅ GOOD: Required module with error handling
if ! source "${SCRIPT_DIR}/lib/config.sh" 2>/dev/null; then
    die "Failed to source config.sh"
fi

# ✅ GOOD: Optional module with fallback
if ! source "${LIB_DIR}/optional_module.sh" 2>/dev/null; then
    log_message "WARNING" "SYSTEM" "Optional module not found, using defaults"
    OPTIONAL_FEATURE_ENABLED=false
fi
```

**Make Modules Idempotent:**

Make modules safe to source multiple times by using conditional definitions:

```bash
# ✅ GOOD: Conditional readonly (prevents "readonly variable already set" errors)
[[ -z "${EXIT_SUCCESS:-}" ]] && readonly EXIT_SUCCESS=0

# ✅ GOOD: Conditional function definition
if ! declare -f get_unix_timestamp >/dev/null 2>&1; then
    get_unix_timestamp() {
        date +%s
    }
fi

# ❌ BAD: Non-idempotent module (fails when sourced multiple times)
readonly MODULE_VERSION="1.0.0"  # Error if sourced twice!
```

**Best Practices:**

- **Path Resolution**: Use `"${BASH_SOURCE[0]}"` to get current script path, resolve with `$(cd ... && pwd)` for absolute paths
- **Error Handling**: Required modules use `die()` on failure, optional modules provide fallbacks with warnings
- **Dependency Management**: Source modules in dependency order (constants.sh → common.sh → logging.sh → config.sh), prevent circular dependencies
- **Idempotency**: Use conditional readonly `[[ -z "${VAR:-}" ]] && readonly VAR=value` and conditional function definitions `if ! declare -f func_name >/dev/null 2>&1; then ... fi`

**Note:** For detailed module organization patterns including library module sourcing, module header documentation, module decomposition, and centralized fallback functions, see `CODE_PATTERNS.md` section on [Module Organization Patterns](CODE_PATTERNS.md#module-organization-patterns).

**Example:**
```70:107:lib/state.sh
# Source state management modules
# Order matters: modules are sourced in dependency order
# Use STATE_MODULE_DIR for module directory to avoid overwriting STATE_DIR
# STATE_DIR should be set by the main script or config, not here
STATE_MODULE_DIR="${LIB_DIR}/state"
# shellcheck source=lib/state/state_paths.sh
source "${STATE_MODULE_DIR}/state_paths.sh" 2>/dev/null || {
	log_state_error "Failed to source state_paths.sh"
	exit 1
}
# shellcheck source=lib/state/global_state.sh
source "${STATE_MODULE_DIR}/global_state.sh" 2>/dev/null || {
	log_state_error "Failed to source global_state.sh"
	exit 1
}
# shellcheck source=lib/state/peer_state.sh
source "${STATE_MODULE_DIR}/peer_state.sh" 2>/dev/null || {
	log_state_error "Failed to source peer_state.sh"
	exit 1
}
# shellcheck source=lib/state/state_init.sh
source "${STATE_MODULE_DIR}/state_init.sh" 2>/dev/null || {
	log_state_error "Failed to source state_init.sh"
	exit 1
}
# shellcheck source=lib/state/network_partition_stats.sh
source "${STATE_MODULE_DIR}/network_partition_stats.sh" 2>/dev/null || {
	log_state_error "Failed to source network_partition_stats.sh"
	exit 1
}
# shellcheck source=lib/state/resource_monitoring_stats.sh
source "${STATE_MODULE_DIR}/resource_monitoring_stats.sh" 2>/dev/null || {
```

---

## References

### Official Documentation

- **GNU Bash Manual**: https://www.gnu.org/software/bash/manual/
- **Bash Guide**: https://mywiki.wooledge.org/BashGuide
- **Advanced Bash Scripting Guide**: https://tldp.org/LDP/abs/html/

### Tools and Resources

- **ShellCheck**: https://www.shellcheck.net/ - Static analysis tool
- **shfmt**: https://github.com/mvdan/sh - Shell script formatter
- **BATS**: https://github.com/bats-core/bats-core - Testing framework

### Project-Specific Documentation

- **CODE_PATTERNS.md** - Detailed patterns used in this codebase
- **DEVELOPER.md** - Development workflow and tooling
- **ARCHITECTURE.md** - System architecture and design decisions
- **TEST_PATTERNS.md** - Testing patterns and best practices

### Best Practices Sources

The practices in this guide are based on:
- GNU Bash Manual official documentation
- ShellCheck recommendations and wiki
- Community best practices from reputable sources
- Patterns established in the UDM VPN Monitor codebase

---

## Summary

This guide covers essential Bash coding practices:

1. **Script Structure**: Use shebang, headers, and proper directory setup
2. **Error Handling**: Enable strict mode in main scripts, handle errors explicitly in libraries
3. **Variables**: Always quote, use local in functions, follow naming conventions
4. **Functions**: Document comprehensively, return error codes, validate parameters
5. **Arrays**: Use arrays for lists, namerefs for passing by reference, pre-declare arrays populated by sourced files
6. **Strings**: Trim and normalize input, use proper pattern matching
7. **Command Substitution**: Use `$()` syntax, quote results, handle failures appropriately
8. **Arithmetic**: Use safe timestamp arithmetic, validate and clamp results
9. **Control Flow**: Use `[[ ]]` for tests, case statements for multiple comparisons
10. **Files**: Use atomic writes, check readability, handle missing newlines
11. **Validation**: Validate all input, sanitize user data
12. **Module Sourcing**: Source modules safely with error handling and path resolution
13. **Security**: Sanitize paths, validate formats, avoid eval
14. **Cleanup**: Use default value expansion `${var:-}` in cleanup functions and EXIT traps
15. **Quality**: Use ShellCheck and shfmt, document thoroughly

Follow these practices to write maintainable, secure, and reliable Bash scripts.
