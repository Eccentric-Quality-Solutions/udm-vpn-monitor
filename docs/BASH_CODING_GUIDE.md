# Bash Coding Guide

**Date:** 2026-01-10  
**Purpose:** Comprehensive guide to coding in Bash with focus on best practices and patterns used in the UDM VPN Monitor codebase

## Overview

This guide provides a comprehensive reference for writing Bash scripts, combining:
- Industry best practices from reputable sources (GNU Bash Manual, ShellCheck, community standards)
- Patterns and conventions used in the UDM VPN Monitor codebase
- Practical examples from real code

This guide complements existing documentation:
- `CODE_PATTERNS.md` - Detailed patterns used in this codebase
- `DEVELOPER.md` - Development workflow and tooling
- `ARCHITECTURE.md` - System architecture and design decisions

---

## Table of Contents

1. [Script Structure and Setup](#script-structure-and-setup)
2. [Error Handling and Strict Mode](#error-handling-and-strict-mode)
3. [Variable Usage and Naming](#variable-usage-and-naming)
4. [Functions](#functions)
5. [Arrays and Associative Arrays](#arrays-and-associative-arrays)
6. [String Manipulation](#string-manipulation)
7. [Command Substitution](#command-substitution)
8. [Arithmetic Operations](#arithmetic-operations)
9. [Control Flow](#control-flow)
10. [File Operations](#file-operations)
11. [Input Validation](#input-validation)
12. [Error Handling Patterns](#error-handling-patterns)
13. [Module Sourcing](#module-sourcing)
14. [Security Best Practices](#security-best-practices)
15. [Code Quality Tools](#code-quality-tools)
16. [Documentation Standards](#documentation-standards)
17. [References](#references)

---

## Script Structure and Setup

### Shebang Line

Always start scripts with a shebang to specify the interpreter:

```bash
#!/bin/bash
```

**Best Practice:**
- Use `#!/bin/bash` for scripts that require Bash-specific features
- Use `#!/usr/bin/env bash` for portability (finds bash in PATH)
- This project uses `#!/bin/bash` since we target UDM OS 4.3+ specifically

**Example from codebase:**
```1:1:vpn-monitor.sh
#!/bin/bash
```

### Script Header

Include a descriptive header with purpose, version, and key information:

```bash
#!/bin/bash
#
# UDM VPN Monitor
# Monitors Site-to-Site VPN connections using IPsec xfrm state byte counters
# Implements tiered recovery: log → surgical cleanup → full restart
#
# Designed for UniFi Dream Machine (UDM) running UniFi OS 4.3+
#
# Version: 0.6.0
#
```

### Directory Setup

Get script directory early for reliable path resolution:

```bash
# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/vpn-monitor.conf"
```

**Key Points:**
- Use `"${BASH_SOURCE[0]}"` instead of `$0` for sourced scripts
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

**Example from codebase:**
```13:13:vpn-monitor.sh
set -euo pipefail
```

**Important Notes:**
- **Main scripts**: Always use `set -euo pipefail`
- **Library modules**: Handle errors explicitly rather than relying on `set -e` (modules may be sourced by scripts with different error handling)
- **When to disable**: Temporarily disable for commands that are expected to fail:
  ```bash
  set +e
  command_that_may_fail
  exit_code=$?
  set -e
  if [[ $exit_code -ne 0 ]]; then
      handle_error
  fi
  ```

### Error Handling in Library Modules

Library modules should handle errors explicitly rather than relying on `set -e`:

```bash
# Library module pattern
# Don't use set -euo pipefail in library modules
# Handle errors explicitly

check_vpn_status() {
    local peer_ip="$1"
    
    if ! validate_ip_address "$peer_ip"; then
        log_message "ERROR" "SYSTEM" "Invalid peer IP format: $peer_ip"
        return 1  # Return error code, don't exit
    fi
    
    # ... check logic ...
    
    if [[ $vpn_ok -eq 0 ]]; then
        return 1  # VPN check failed
    fi
    
    return 0  # VPN is healthy
}
```

**Why:** Library modules may be sourced by scripts with different error handling requirements. Explicit error handling is more predictable.

---

## Variable Usage and Naming

### Naming Conventions

Follow consistent naming conventions:

```bash
# Constants and environment variables: UPPERCASE
readonly EXIT_SUCCESS=0
readonly SECONDS_PER_MINUTE=60
CONFIG_FILE="${SCRIPT_DIR}/vpn-monitor.conf"

# Local variables: lowercase_with_underscores
local peer_ip="$1"
local failure_count=0
local timestamp=$(get_unix_timestamp)

# Function names: lowercase_with_underscores
check_vpn_status() {
    # ...
}
```

**Example from codebase:**
```16:22:vpn-monitor.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/vpn-monitor.conf"
STATE_DIR="${SCRIPT_DIR}/state"
LOGS_DIR="${SCRIPT_DIR}/logs"
# shellcheck disable=SC2034
LOCKFILE="${STATE_DIR}/vpn-monitor.lock"
LOG_FILE="${LOGS_DIR}/vpn-monitor.log"
```

### Always Quote Variables

**Critical:** Always quote variable expansions to prevent word splitting and globbing:

```bash
# ✅ GOOD: Quoted variables
echo "Processing file: $filename"
cp "$source_file" "$dest_file"
if [[ -f "$config_file" ]]; then
    source "$config_file"
fi

# ❌ BAD: Unquoted variables (breaks with spaces, special chars)
echo Processing file: $filename
cp $source_file $dest_file
if [[ -f $config_file ]]; then
    source $config_file
fi
```

**Why:** Unquoted variables can cause:
- Word splitting (spaces break arguments)
- Pathname expansion (wildcards get expanded)
- Security issues (injection attacks)

### Use Local Variables in Functions

Always use `local` for function variables to avoid global scope pollution:

```bash
# ✅ GOOD: Local variables
process_file() {
    local filename="$1"
    local line_count=0
    local temp_file="/tmp/temp"
    # ... function logic ...
}

# ❌ BAD: Global variables (pollutes global scope)
process_file() {
    filename="$1"  # Global variable!
    line_count=0   # Global variable!
    # ...
}
```

### Default Values and Parameter Expansion

Use parameter expansion for default values and safe access:

```bash
# Default value if variable is unset or empty
local timeout="${TIMEOUT:-30}"
local log_level="${LOG_LEVEL:-INFO}"

# Default value if variable is unset (but allow empty string)
local config="${CONFIG_FILE:-/etc/default.conf}"

# Safe access with set -u (prevents "unbound variable" errors)
local value="${BASH_REMATCH[1]:-}"  # Empty string if unset

# Check if variable is set
if [[ -n "${DEBUG:-}" ]]; then
    echo "Debug mode enabled"
fi
```

**Example from codebase:**
```bash
# From lib/config.sh
local config_file="${1:-$CONFIG_FILE}"
local timeout="${IPSEC_STATUS_TIMEOUT:-5}"
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

**Pattern for Multi-Source Modules:**
```bash
# Prevents "readonly variable already set" errors when sourced multiple times
[[ -z "${CONSTANT_NAME:-}" ]] && readonly CONSTANT_NAME=value
```

---

## Functions

### Function Definition Style

Use the standard function definition style (without `function` keyword):

```bash
# ✅ GOOD: Standard style (preferred in this codebase)
check_vpn_status() {
    local peer_ip="$1"
    # ... function body ...
}

# Also valid but less common:
function check_vpn_status() {
    local peer_ip="$1"
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

### Return Values

Functions return exit codes (0 = success, non-zero = failure):

```bash
# ✅ GOOD: Return error codes
validate_ip_address() {
    local ip="$1"
    
    if [[ -z "$ip" ]]; then
        return 1  # Invalid
    fi
    
    # ... validation logic ...
    
    return 0  # Valid
}

# Caller checks return code
if ! validate_ip_address "$peer_ip"; then
    log_message "ERROR" "SYSTEM" "Invalid IP: $peer_ip"
    return 1
fi
```

**Key Points:**
- Return 0 for success, 1 (or other non-zero) for failure
- Always check return codes from functions
- Don't ignore return values

### Function Documentation

Document all functions with comprehensive comments:

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

**Documentation Sections:**
- **Purpose**: What the function does
- **Arguments**: All parameters with types and descriptions
- **Returns**: Exit codes and their meanings
- **Side effects**: File operations, logging, state changes
- **Examples**: Usage examples for complex functions
- **Note**: Dependencies, requirements, special considerations

---

## Arrays and Associative Arrays

### Regular Arrays

Use arrays instead of space-separated strings for lists:

```bash
# ✅ GOOD: Array declaration and usage
peer_ips=("203.0.113.1" "203.0.113.2" "203.0.113.3")
# Or with explicit declaration:
declare -a peer_ips=("203.0.113.1" "203.0.113.2" "203.0.113.3")

# Iterate over array elements
for peer_ip in "${peer_ips[@]}"; do
    check_vpn_status "$peer_ip"
done

# Iterate with index
for i in "${!peer_ips[@]}"; do
    echo "Index: $i, IP: ${peer_ips[$i]}"
done

# ❌ BAD: Space-separated string (breaks with spaces, harder to manage)
peer_ips="203.0.113.1 203.0.113.2 203.0.113.3"
for peer_ip in $peer_ips; do  # Word splitting issues!
    check_vpn_status "$peer_ip"
done
```

**Key Points:**
- Always quote `"${array[@]}"` when iterating
- Use `"${!array[@]}"` to get indices
- Arrays can be declared with `array=()` or explicitly with `declare -a array=()` or `local -a array=()`

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
```bash
# ❌ BAD: Circular reference error
local -n array_ref="$array"  # Error if $array conflicts with environment variable

# ✅ GOOD: Use temp variable to prevent circular references
local ref_name="$param_ref"
local -n array_ref="$ref_name"  # Safe - temp variable prevents conflicts
```

**Example from codebase:**
```300:329:lib/config/config_validation.sh
split_rules_string() {
	local rules="$1"
	local -n rule_array_ref="$2"

	# Clear the array
	rule_array_ref=()

	# Handle empty rules string
	if [[ -z "$rules" ]]; then
		return 0
	fi

	# Split rules by ||| separator (used to avoid conflicts with commas in values: rules)
	# Fallback to comma for backward compatibility with old format
	# Special case: if rules is a single values: rule (e.g., "values:0,1"), don't split it
	if [[ "$rules" == *"|||"* ]]; then
		# Use awk to split by ||| since IFS doesn't support multi-character separators
		while IFS= read -r rule; do
			[[ -n "$rule" ]] && rule_array_ref+=("$rule")
		done < <(echo "$rules" | awk -F'\\|\\|\\|' '{for(i=1;i<=NF;i++) print $i}')
	elif [[ "$rules" =~ ^values: ]]; then
		# Single values: rule - don't split (comma is part of the rule value)
		rule_array_ref=("$rules")
	else
		# Old format: comma-separated (for backward compatibility)
		IFS=',' read -ra rule_array_ref <<<"$rules"
	fi

	return 0
}
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
# Trim leading and trailing whitespace
line="${line#"${line%%[![:space:]]*}"}"  # Remove leading spaces
line="${line%"${line##*[![:space:]]}"}"  # Remove trailing spaces

# Remove trailing comments
assignment="${assignment%%#*}"  # Remove everything after first #

# Normalize whitespace before processing
if [[ -z "${line// /}" ]]; then
    continue  # Skip empty lines (after removing all spaces)
fi
```

---

## Command Substitution

### Use Modern Syntax

Always use `$()` instead of backticks for command substitution:

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

### Quote Command Substitutions

Always quote command substitutions to prevent word splitting:

```bash
# ✅ GOOD: Quoted command substitution
local output="$(command "$arg")"
local pid="$(cat "$pidfile")"
local lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ❌ BAD: Unquoted command substitution (word splitting issues)
local output=$(command $arg)  # Breaks if $arg contains spaces
```

### Defensive Command Substitution

Use `|| true` when command substitution failure is acceptable:

```bash
# ✅ GOOD: Use || true when failure is acceptable
forward_output=$(echo "$xfrm_output" | grep -F "dst ${peer_ip}" 2>/dev/null || true)
ipsec_output=$(timeout 5 ipsec status 2>/dev/null || true)
func_def=$(declare -f check_command_available 2>/dev/null || true)

# ❌ BAD: Command substitution failure causes script failure (if set -e is enabled)
forward_output=$(echo "$xfrm_output" | grep -F "dst ${peer_ip}" 2>/dev/null)
# If grep finds nothing, exit code is 1, which can cause script failure
```

**When to Use `|| true`:**
- `grep` commands that may not find matches (exit code 1 is normal)
- Functions that might return non-zero in edge cases (e.g., mocked functions in tests)
- Commands where failure is expected and handled gracefully

**When NOT to Use `|| true`:**
- Commands where failure indicates a real problem
- Commands where you need to check exit code explicitly
- Commands that should fail the script if they fail

**Example:**
```bash
# ✅ GOOD: grep failure is acceptable (no matches found)
output=$(grep "pattern" "$file" 2>/dev/null || true)

# ✅ BETTER: Check exit code explicitly for critical operations
if ! result=$(critical_command 2>&1); then
    handle_error "ERROR" "SYSTEM" "Critical command failed: $result"
fi
```

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

---

## Arithmetic Operations

### Arithmetic Expansion

Use `$(( ))` for arithmetic operations:

```bash
# ✅ GOOD: Arithmetic expansion
local count=$((count + 1))
local total=$((value1 + value2))
local result=$((value * 2))

# ❌ BAD: Using expr (slower, less portable)
local count=$(expr $count + 1)
```

**Key Points:**
- Use `$(( ))` for all arithmetic operations
- No quotes needed inside `$(( ))`
- Variables don't need `$` prefix inside `$(( ))` (but it's safe to include)

### Safe Timestamp Arithmetic

Always use safe timestamp arithmetic functions to prevent overflow/underflow:

```bash
# ✅ GOOD: Use safe timestamp arithmetic functions
one_hour_ago=$(safe_timestamp_subtract "$now" "$SECONDS_PER_HOUR" 2>/dev/null || echo "0")
elapsed_time=$(safe_timestamp_diff "$current_time" "$start_time" 2>/dev/null || echo "0")
future_time=$(safe_timestamp_add "$now" "$SECONDS_PER_HOUR" 2>/dev/null || echo "$now")

# ❌ BAD: Direct arithmetic without validation
one_hour_ago=$((now - SECONDS_PER_HOUR))  # Can underflow!
elapsed_time=$(($(get_unix_timestamp) - verify_start_time))  # Can cause infinite loops!
```

**Why:** Direct timestamp arithmetic can overflow or underflow, especially when:
- Subtracting large time periods from timestamps
- Calculating differences between timestamps
- Adding time periods to timestamps

**Pattern:** Always provide fallback values (e.g., `|| echo "0"`) when using safe functions.

### Validate and Clamp Arithmetic Results

Always validate arithmetic inputs and clamp results to expected ranges:

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
- Use defensive programming: clamp even if calculation "should" be correct

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

# ❌ BAD: Use [ ] (less features, more error-prone)
if [ -f "$file" ]; then
    process_file "$file"
fi
```

**Key Points:**
- `[[ ]]` supports pattern matching, regex, and more operators
- `[[ ]]` doesn't require quoting for simple variables (but quote for safety)
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

**Example from codebase:**
```45:66:vpn-monitor.sh
for arg in "$@"; do
	case "$arg" in
	--help | -h)
		echo "Usage: $0 [OPTIONS]"
		echo ""
		echo "UDM VPN Monitor v${SCRIPT_VERSION:-0.0.1}"
		echo "Monitors Site-to-Site VPN connections using IPsec xfrm state byte counters."
		echo "Implements tiered recovery: log → surgical cleanup → full restart"
		echo ""
		echo "Options:"
		echo "  --fake     Run checks and log failures but don't escalate tiers"
		echo "  --help     Show this help message"
		echo "  --version  Show version information"
		echo ""
		exit "${EXIT_SUCCESS:-0}"
		;;
	--version | -v)
		echo "UDM VPN Monitor v${SCRIPT_VERSION:-0.0.1}"
		exit "${EXIT_SUCCESS:-0}"
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
- `&&` runs second command only if first succeeds
- `||` runs second command only if first fails
- Useful for concise conditional execution
- Can be combined with `!` for negation

### While and Until Loops

Use while/until loops for condition-based iteration:

```bash
# ✅ GOOD: While loop with timeout
local start_time=$(get_unix_timestamp)
local timeout=30
while true; do
    local elapsed
    elapsed=$(safe_timestamp_diff "$(get_unix_timestamp)" "$start_time" 2>/dev/null || echo "0")
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
- Use `while` for loops that run while condition is true
- Use `until` for loops that run until condition is true
- Always include timeout or max attempts to prevent infinite loops
- Use `break` to exit loop early

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
- Use `IFS= read -r` to preserve whitespace and prevent backslash interpretation
- Always use `|| [[ -n "$line" ]]` to handle files without trailing newline
- Skip empty lines and comments early in loop

### Atomic File Writes

Use atomic writes for state files to prevent corruption:

```bash
# ✅ GOOD: Atomic write pattern
if ! (echo "$data" > "${file}.tmp" && mv "${file}.tmp" "$file"); then
    log_message "ERROR" "SYSTEM" "Failed to write state file: $file"
    return 1
fi

# ❌ BAD: Direct write (can be corrupted if script interrupted)
echo "$data" > "$file"  # Not atomic!
```

**Why:** Atomic writes ensure file integrity. If script is interrupted, the original file remains intact.

### File Existence Checks

Always check file readability before operations:

```bash
# ✅ GOOD: Check readability before reading
if [[ ! -r "$config_file" ]]; then
    log_message "ERROR" "SYSTEM" "Config file not readable: $config_file"
    return 1
fi

# Read file
while IFS= read -r line || [[ -n "$line" ]]; do
    # ...
done < "$config_file"

# ✅ GOOD: Check directory exists and is writable
if [[ ! -d "$state_dir" ]] || [[ ! -w "$state_dir" ]]; then
    log_message "ERROR" "SYSTEM" "State directory not writable: $state_dir"
    return 1
fi
```

### Redirection Patterns

Use proper redirection for output and errors:

```bash
# ✅ GOOD: Redirect stderr for error messages
echo "Error message" >&2
log_message "ERROR" "SYSTEM" "Failed to process file" >&2

# ✅ GOOD: Redirect both stdout and stderr
command > "$log_file" 2>&1

# ✅ GOOD: Redirect stderr to /dev/null when errors are expected
output=$(command 2>/dev/null || true)

# ✅ GOOD: Multiple redirects using command grouping
{
    echo "Line 1"
    echo "Line 2"
} >> "$log_file"

# ❌ BAD: Multiple redirects without grouping (ShellCheck SC2129)
echo "Line 1" >> "$log_file"
echo "Line 2" >> "$log_file"  # Inefficient, opens file twice
```

**Key Points:**
- Use `>&2` to redirect to stderr (for error messages)
- Use `2>&1` to redirect stderr to stdout
- Use `2>/dev/null` to suppress stderr when errors are expected
- Use `{ cmd1; cmd2; } >> file` for multiple redirects to same file
- Redirect prompts to stderr before `read` to prevent interference with stdin redirection in tests

---

## Input Validation

### Validate Function Parameters

Always validate function parameters:

```bash
# ✅ GOOD: Validate parameters
check_vpn_status() {
    local peer_ip="$1"
    
    if [[ -z "$peer_ip" ]]; then
        log_message "ERROR" "SYSTEM" "Peer IP is required"
        return 1
    fi
    
    if ! validate_ip_address "$peer_ip"; then
        log_message "ERROR" "SYSTEM" "Invalid peer IP format: $peer_ip"
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

### Sanitize User Input

Sanitize all user input to prevent injection attacks:

```bash
# ✅ GOOD: Validate and sanitize input
if [[ "$user_input" =~ ^[a-zA-Z0-9_]+$ ]]; then
    # Safe to proceed
    process_input "$user_input"
else
    log_message "ERROR" "SYSTEM" "Invalid input format"
    return 1
fi

# ✅ GOOD: Sanitize location names (alphanumeric and underscores only)
sanitize_location_name() {
    local name="$1"
    # Remove invalid characters, keep only alphanumeric and underscores
    echo "${name//[^a-zA-Z0-9_]/_}"
}
```

---

## Error Handling Patterns

### Fatal Errors

Use `die()` or `handle_error_or_exit_fake_mode()` for fatal errors:

```bash
# ✅ GOOD: Fatal error handling
if [[ ! -f "$CONFIG_FILE" ]] && [[ -z "${EXTERNAL_PEER_IPS:-}" ]]; then
    die "Configuration file not found and EXTERNAL_PEER_IPS not set"
fi

# ✅ GOOD: Fatal error with fake mode support
if ! ensure_directory_exists "$STATE_DIR" "state"; then
    handle_error_or_exit_fake_mode "SYSTEM" "Failed to create state directory" "${EXIT_GENERAL_ERROR:-1}"
fi
```

### Non-Fatal Errors

Return error codes for non-fatal errors:

```bash
# ✅ GOOD: Return error codes
check_vpn_status() {
    local peer_ip="$1"
    
    if ! validate_ip_address "$peer_ip"; then
        log_message "ERROR" "SYSTEM" "Invalid peer IP format: $peer_ip"
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
    log_message "WARNING" "SYSTEM" "VPN check failed for $peer_ip"
    increment_failure "$peer_ip"
fi
```

### Warnings

Use `log_message "WARNING"` for non-fatal issues:

```bash
# ✅ GOOD: Log warnings for non-fatal issues
if ! command -v ipsec >/dev/null 2>&1; then
    log_message "WARNING" "SYSTEM" "ipsec command not available, using fallback"
    # Continue with fallback
fi
```

### Error Handling Checklist

When writing or reviewing code:
- [ ] Fatal errors use `die()` or `handle_error_or_exit_fake_mode()` with descriptive messages
- [ ] Non-fatal errors return error codes (0/1)
- [ ] Warnings are logged with `log_message "WARNING"`
- [ ] Return codes are checked by callers
- [ ] Error messages include context (peer IP, file path, etc.)
- [ ] Appropriate log levels are used (ERROR/WARNING/INFO/DEBUG)

---

## Security Best Practices

### Use Absolute Paths for Commands

When possible, use absolute paths to prevent PATH manipulation attacks:

```bash
# ✅ GOOD: Absolute paths (when security is critical)
/bin/rm -rf /tmp/old_files

# ✅ GOOD: Check command availability first
if ! command -v ip >/dev/null 2>&1; then
    die "Required command 'ip' not found"
fi
ip xfrm state show
```

**Note:** In this codebase, we check command availability and provide fallbacks rather than using absolute paths, as commands may be in different locations on different systems.

### Sanitize File Paths

Validate and sanitize file paths to prevent directory traversal:

```bash
# ✅ GOOD: Validate paths
if [[ "$file_path" =~ \.\. ]]; then
    log_message "ERROR" "SYSTEM" "Invalid path: contains .."
    return 1
fi

# ✅ GOOD: Use realpath to resolve paths
canonical_path=$(realpath "$file_path" 2>/dev/null || echo "$file_path")
```

### Validate Input Format

Always validate input format before processing:

```bash
# ✅ GOOD: Validate IP address format
if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    log_message "ERROR" "SYSTEM" "Invalid IP address format: $ip"
    return 1
fi

# ✅ GOOD: Validate location name (alphanumeric and underscores only)
if ! [[ "$location" =~ ^[a-zA-Z0-9_]+$ ]]; then
    log_message "ERROR" "SYSTEM" "Invalid location name: $location"
    return 1
fi
```

### Avoid Eval and Unsafe Expansion

Avoid `eval` and unsafe variable expansion:

```bash
# ❌ BAD: eval is dangerous (code injection risk)
eval "command $user_input"

# ❌ BAD: Unsafe expansion
command $user_input

# ✅ GOOD: Validate and quote
if validate_input "$user_input"; then
    command "$user_input"
fi
```

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

**Disabling Checks:**
Use sparingly and document why:

```bash
# shellcheck disable=SC2034
# This variable is used by sourced scripts
CONFIG_VAR="value"
```

### shfmt

Use shfmt for consistent formatting:

```bash
# Format all shell scripts (in-place)
shfmt -w *.sh lib/*.sh tests/*.sh

# Check formatting without modifying files
shfmt -d *.sh

# Format specific file
shfmt -w vpn-monitor.sh
```

**Formatting Standards:**
- Use **tabs** for indentation (enforced by shfmt)
- Tab width: 8 spaces (default)

---

## Documentation Standards

### Function Documentation

All functions must have comprehensive documentation:

```bash
# Function name and brief description
#
# Detailed description of what the function does.
# Include information about:
#   - Purpose and behavior
#   - Algorithm or approach used
#   - Dependencies on other functions or global variables
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
#   - File operations (creates, modifies, deletes files)
#   - Logging (what gets logged and when)
#   - State changes (modifies global state, etc.)
#
# Examples:
#   function_name "arg1" "arg2"
#   if function_name "arg1"; then
#       echo "Success"
#   fi
#
# Note:
#   - Special considerations
#   - Dependencies
#   - Known limitations
function_name() {
    # Implementation
}
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

---

## Module Sourcing

### Safe Module Sourcing

Source modules with error handling and path resolution:

```bash
# ✅ GOOD: Safe module sourcing with path resolution
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LIB_DIR}/common.sh" 2>/dev/null || {
    # Fallback if common.sh not found
    if [[ -n "${LIB_DIR:-}" ]] && [[ -f "${LIB_DIR}/fallbacks.sh" ]] && [[ -r "${LIB_DIR}/fallbacks.sh" ]]; then
        source "${LIB_DIR}/fallbacks.sh" 2>/dev/null && define_common_fallbacks
    fi
}

# ✅ GOOD: Source with error handling
if ! source "${SCRIPT_DIR}/lib/config.sh" 2>/dev/null; then
    die "Failed to source config.sh"
fi
```

**Key Points:**
- Use `"${BASH_SOURCE[0]}"` to get current script path
- Resolve paths with `$(cd ... && pwd)` for absolute paths
- Handle sourcing failures gracefully with fallbacks
- Redirect stderr (`2>/dev/null`) when sourcing may fail

### ShellCheck Directives

Use shellcheck directives to suppress false positives:

```bash
# ✅ GOOD: ShellCheck source directive
# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"

# ✅ GOOD: Disable specific checks with explanation
# shellcheck disable=SC2034
# This variable is used by sourced scripts
CONFIG_VAR="value"
```

**Key Points:**
- Use `# shellcheck source=path` to help ShellCheck understand sourced files
- Use `# shellcheck disable=CODE` sparingly and document why
- Always provide explanation when disabling checks

### Conditional Sourcing

Handle modules that may not exist:

```bash
# ✅ GOOD: Conditional sourcing with fallback
if ! source "${LIB_DIR}/constants.sh" 2>/dev/null; then
    # Fallback if constants.sh not found (shouldn't happen in normal operation)
    readonly EXIT_SUCCESS=0
    readonly EXIT_GENERAL_ERROR=1
fi
```

**Key Points:**
- Check if module exists before sourcing when appropriate
- Provide fallback values when modules may not be available
- Log warnings when fallbacks are used

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
5. **Arrays**: Use arrays for lists, namerefs for passing by reference
6. **Strings**: Trim and normalize input, use proper pattern matching
7. **Command Substitution**: Use `$()` syntax, quote results, handle failures appropriately
8. **Arithmetic**: Use safe timestamp arithmetic, validate and clamp results
9. **Control Flow**: Use `[[ ]]` for tests, case statements for multiple comparisons
10. **Files**: Use atomic writes, check readability, handle missing newlines
11. **Validation**: Validate all input, sanitize user data
12. **Module Sourcing**: Source modules safely with error handling and path resolution
13. **Security**: Sanitize paths, validate formats, avoid eval
14. **Quality**: Use ShellCheck and shfmt, document thoroughly

Follow these practices to write maintainable, secure, and reliable Bash scripts.
