# Code Review Lessons Learned

**Date:** 2025-01-15  
**Last Updated:** 2026-01-02  
**Context:** Comprehensive codebase review for errors, bugs, DRY violations, and bad practices

## Overview

This document captures lessons learned from conducting systematic code reviews. These patterns should be applied systematically to prevent similar issues in the future.

---

## 1. Always Use Abstraction Layers Consistently

### Problem
During review, we found inconsistent state file path construction:
- `determine_vpn_status()` constructs paths directly: `${STATE_DIR}/failure_type_${peer_sanitized}` ✅ **FIXED**
- `get_failure_type()` constructs paths directly: `${STATE_DIR}/failure_type_${location_sanitized}_${ip_sanitized}` ✅ **FIXED**
- `recovery.sh` constructs paths directly when deleting failure type files ✅ **FIXED**
- Some code uses `get_peer_state_file_path()` abstraction, others don't ✅ **FIXED** - All now use abstraction layer

### Impact
- State files stored with wrong paths
- State retrieval fails silently
- Per-location failure tracking broken

### Lesson
**When abstraction layers exist, always use them.** Don't construct paths directly even if you know the format. Abstraction layers:
- Ensure consistency across codebase
- Handle edge cases and sanitization
- Make refactoring easier
- Prevent bugs from path format changes

### Pattern to Follow
```bash
# ✅ GOOD: Use abstraction layer
state_file=$(get_peer_state_file_path "$location_name" "$peer_ip" "failure_type")
atomic_write_file "$state_file" "$value"

# ❌ BAD: Direct path construction
state_file="${STATE_DIR}/failure_type_${peer_sanitized}"
atomic_write_file "$state_file" "$value"
```

### Systematic Application
- Before writing state files, check if `get_peer_state_file_path()` supports the key
- If not, add the key to the abstraction layer
- Never construct state file paths directly

---

## 2. Always Use Validation Functions Instead of Inline Regex

### Problem
During review, we found duplicate IP validation logic:
- `validate_ipv4()` function exists with proper validation (regex + octet range checks)
- Inline regex checks in `check_ping_connectivity()` (line 702) ✅ **FIXED**
- `check_route_exists()` already uses `validate_ip_address()` ✅ **ALREADY CORRECT**

### Impact
- Inconsistent validation logic across codebase
- Maintenance burden (changes needed in multiple places)
- Potential for bugs if one location is updated but not others
- Inline regex doesn't validate octet ranges (0-255), allowing invalid IPs like "999.999.999.999"

### Lesson
**Always use existing validation functions instead of inline regex patterns.** Validation functions:
- Provide consistent validation logic
- Include proper range checks (not just format matching)
- Handle edge cases (empty strings, etc.)
- Make maintenance easier (single source of truth)
- Are more secure (proper validation prevents injection attacks)

### Pattern to Follow
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

### Systematic Application
- Before using regex for IP validation, check if `validate_ipv4()` or `validate_ip_address()` exists
- Always use validation functions instead of inline regex
- Validation functions provide stricter checks (octet ranges) than simple regex patterns

---

## 3. Verify Function Signatures Match Calls

### Problem
Found bug where `get_failure_type()` expects 2 arguments (`location_name`, `peer_ip`) but was called with only 1 (`peer_ip`):
```bash
# ❌ BUG: Missing location_name argument
failure_type=$(get_failure_type "$external_peer_ip" 2>/dev/null || echo "unknown")

# ✅ CORRECT: Both arguments provided
failure_type=$(get_failure_type "$location_name" "$external_peer_ip" 2>/dev/null || echo "unknown")
```

### Impact
- Function receives empty string for `location_name`
- State file paths constructed incorrectly
- Per-location tracking broken

### Lesson
**Always verify function signatures match calls.** This is especially critical when:
- Functions are refactored to accept additional parameters
- Location-based features are added to previously IP-only code
- State management is extended to support per-location tracking

### Pattern to Follow
```bash
# When calling functions, verify signature:
# 1. Check function documentation for required arguments
# 2. Verify all required arguments are provided
# 3. Verify argument order matches function signature
# 4. Use grep to find all call sites when refactoring signatures
```

### Systematic Application
- When adding parameters to functions, use grep to find all call sites
- Update all call sites immediately
- Add tests that verify correct arguments are passed
- Consider using shellcheck or similar tools to catch mismatched arguments

---

## 4. Remove Debug Code, Don't Just Comment It

### Problem
Found debug logging code in production:
- JSON-formatted debug logs writing to hardcoded paths
- Debug code wrapped in `# #region agent log` comments but still active
- Hardcoded absolute paths that won't work in production

### Impact
- Code clutter reduces maintainability
- Hardcoded paths break portability
- Unnecessary overhead from debug operations
- Confusion about what code is active

### Lesson
**Debug code should be removed entirely, not commented out.** Version control preserves history, so commented code serves no purpose and creates confusion.

### Pattern to Follow
```bash
# ❌ BAD: Commented debug code
# #region agent log
# echo "Debug: $value" >>/path/to/debug.log
# #endregion

# ✅ GOOD: Remove entirely, use version control for history
# If needed for debugging, use DEBUG environment variable:
if [[ "${DEBUG:-0}" -eq 1 ]]; then
    debug_log "Debug: $value"
fi
```

### Systematic Application
- Before committing, search for debug code: `grep -r "debug\.log\|#region\|#endregion"`
- Remove all hardcoded debug paths
- Use `DEBUG=1` environment variable for debug output
- Use `debug_log()` function for consistent debug logging

---

## 5. Verify Findings Before Documenting

### Problem
Initially flagged "potential division by zero" in `check_ping_multiple_ips()`, but verification showed:
- Code already handles empty input (returns early)
- Division is guarded: `if [[ $ping_total_count -gt 0 ]]`

### Impact
- Wasted time investigating non-issues
- Documentation contains incorrect information
- Loss of credibility in review findings

### Lesson
**Always verify findings before documenting them.** Read the actual code carefully, don't assume based on patterns.

### Pattern to Follow
```bash
# When finding potential issues:
# 1. Read the actual code around the issue
# 2. Trace through execution paths
# 3. Check for guards/early returns
# 4. Verify with actual test cases if possible
# 5. Only document verified issues
```

### Systematic Application
- When reviewing, read code thoroughly before flagging issues
- Use grep to find all usages of a pattern
- Check if edge cases are already handled
- Verify with code execution trace if needed

---

## 6. Check for Code Duplication Across Files

### Problem
Found `sanitize_location_name()` defined in both:
- `lib/config.sh` (lines 1516-1541)
- `lib/state.sh` (lines 146-171)

Identical implementations that could diverge over time.

**Status:** ✅ **RESOLVED** (2025-12-31) - Consolidated to `lib/common.sh`

### Impact
- Maintenance burden (changes must be made in two places)
- Risk of divergence between implementations
- Confusion about which function to use

### Lesson
**When adding utility functions, check if they already exist elsewhere.** Use grep to find duplicates before implementing.

### Pattern to Follow
```bash
# Before adding a function:
# 1. Search for similar functions: grep -r "function_name\|^function_name()"
# 2. Check if function exists in common.sh or other shared modules
# 3. If duplicate exists, consolidate to single location
# 4. Update all call sites to use consolidated version
```

### Systematic Application
- Before adding functions, search codebase for similar functionality
- Keep utility functions in `lib/common.sh` when possible
- Use grep regularly to find duplicate implementations
- Consolidate duplicates during code reviews

### Resolution Example
When consolidating `sanitize_location_name()`:
1. ✅ Moved function to `lib/common.sh` (shared utilities)
2. ✅ Removed duplicates from `lib/config.sh` and `lib/state.sh`
3. ✅ Removed duplicate from `scripts/migrate-config-to-locations.sh`
4. ✅ Updated documentation to note function location
5. ✅ Verified all tests pass
6. ✅ Verified both files source `common.sh` (ensuring function availability)

---

## 7. Test Coverage Should Match Code Paths

### Problem
Tests for failure type detection use empty location name (`""`), but production code uses location names. This means:
- Bug where `get_failure_type()` is called without `location_name` wasn't caught
- Per-location failure tracking not tested
- Tests don't match actual usage patterns

### Impact
- Bugs slip through because tests don't exercise real code paths
- False confidence in test coverage
- Production bugs that tests should have caught

### Lesson
**Tests should match actual code usage patterns.** If production code uses location names, tests should too.

### Pattern to Follow
```bash
# ✅ GOOD: Test matches production usage
@test "get_failure_type with location name" {
    local location_name="NYC"
    local peer_ip="192.168.1.1"
    run get_failure_type "$location_name" "$peer_ip"
    # ... assertions
}

# ❌ BAD: Test doesn't match production usage
@test "get_failure_type" {
    run get_failure_type "192.168.1.1"  # Missing location_name
    # ... assertions
}
```

### Systematic Application
- Review tests to ensure they match production call patterns
- When adding location-based features, update tests to use locations
- Use grep to find all call sites and ensure tests cover them
- Add integration tests that exercise full code paths

---

## 8. Systematic Code Review Process

### What Worked Well
1. **Systematic file-by-file review** - Ensured comprehensive coverage
2. **Categorizing issues** - Made prioritization easier
3. **Verifying findings** - Caught false positives before documenting
4. **Cross-referencing** - Found related issues by following patterns

### Process to Follow
1. **Start with main scripts** - Understand entry points
2. **Review library modules** - Check for duplication and consistency
3. **Look for patterns** - Similar issues often appear multiple times
4. **Verify before documenting** - Don't document assumptions
5. **Prioritize findings** - Focus on critical bugs first
6. **Document systematically** - Use consistent format for findings

### Systematic Application
- Schedule periodic code reviews (quarterly or after major features)
- Use consistent review checklist
- Document findings in structured format
- Follow up on high-priority items immediately

---

## 9. Common Patterns to Watch For

### Code Duplication Patterns
- Functions with identical names in multiple files
- Similar logic repeated with slight variations
- Magic numbers used in multiple places
- Error handling patterns repeated

### Bug Patterns
- Function calls with wrong number of arguments
- Inconsistent use of abstraction layers
- Direct path construction instead of using helpers
- Missing input validation

### Bad Practice Patterns
- Debug code left in production
- Hardcoded paths
- Commented-out code blocks
- Inconsistent error handling
- Magic numbers without constants

### Systematic Application
- Add these patterns to code review checklist
- Use grep to find patterns systematically
- Create linting rules where possible
- Document patterns in coding guidelines

---

## 10. Use Character-by-Character Parsing for Complex Syntax

### Problem
Found bug in `parse_quoted_value()` function where regex-based parsing failed on edge cases:
- Escaped quotes (`\"`) were not handled correctly
- Trailing backslashes before closing quotes caused incorrect parsing
- Unclosed quotes were not reliably detected
- Single quotes vs double quotes had different escaping rules that regex couldn't handle

**Status:** ✅ **FIXED** (2025-01-30) - Rewritten with character-by-character parsing

### Impact
- Configuration values with escaped quotes were parsed incorrectly
- Edge cases like trailing backslashes caused silent failures
- Security risk: malformed config could be accepted when it should be rejected

### Lesson
**For complex syntax parsing (quotes, escapes, nested structures), use character-by-character parsing with state tracking instead of regex.** Regex is powerful but struggles with:
- State-dependent parsing (in quotes vs out of quotes)
- Escape sequences that affect meaning of subsequent characters
- Different rules for different contexts (single quotes vs double quotes)
- Edge cases at boundaries (trailing backslashes, unclosed quotes)

### Pattern to Follow
```bash
# ✅ GOOD: Character-by-character parsing with state tracking
parse_quoted_value() {
    local assignment="$1"
    local in_quotes=false
    local quote_char=""
    local escaped=false
    local quote_closed=false
    local result=""
    
    # Track state as we parse character by character
    for ((i=0; i<${#assignment}; i++)); do
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

### Key Principles for Complex Parsing

1. **Track State Explicitly**
   - Use boolean flags for states (`in_quotes`, `escaped`, `quote_closed`)
   - Track context (`quote_char` to know if single or double quotes)
   - Validate final state before returning success

2. **Handle Edge Cases at Boundaries**
   - Trailing backslash before closing quote
   - Backslash at end of string
   - Empty quoted strings (`""` or `''`)
   - Unclosed quotes

3. **Different Rules for Different Contexts**
   - Single quotes: no escaping (everything literal except closing quote)
   - Double quotes: backslash escapes next character
   - Unquoted: no quotes allowed

4. **Test Edge Cases Comprehensively**
   - Escaped quotes (`\"`, `\'`)
   - Escaped backslashes (`\\`)
   - Trailing backslashes (`value\`)
   - Unclosed quotes
   - Empty strings
   - Mixed quotes

### Systematic Application
- When parsing syntax with escapes or quotes, use character-by-character parsing
- Track state explicitly with boolean flags
- Validate final state (e.g., ensure quotes are closed)
- Test edge cases thoroughly (trailing backslashes, unclosed quotes, empty strings)
- Document parsing rules clearly (single vs double quote behavior)

### Example: Quote Parsing Edge Cases

**Edge Cases to Handle:**
1. `VAR="value\"` - Trailing backslash escapes closing quote (unclosed quote error)
2. `VAR="value\` - Backslash at end (unclosed quote error)
3. `VAR="value with \" escaped"` - Escaped quote in middle (parsed correctly)
4. `VAR='value\'` - Single quotes don't escape (backslash is literal)
5. `VAR=""` - Empty quoted string (parsed correctly)
6. `VAR=value"with"quotes` - Quotes in unquoted value (rejected)

**Test Coverage Added:**
- ✅ Escaped quotes in double-quoted strings
- ✅ Escaped backslash in double-quoted strings
- ✅ Unclosed double quote detection
- ✅ Unclosed single quote detection
- ✅ Rejection of quotes in unquoted values
- ✅ Trailing backslash before closing quote
- ✅ Empty quoted strings (both `""` and `''`)
- ✅ Single quotes with no escaping

---

## 11. Always Persist Corrected Values After Validation

### Problem
Found bug in `validate_config_var()` where validation corrections were not persisted to global variables:
- Default values applied during validation were not saved to global variables
- Type corrections (e.g., converting strings to integers) were lost
- Rule corrections (e.g., clamping out-of-range values) were not persisted
- Local `var_value` variable had corrected value, but global variable still had original incorrect value

**Status:** ✅ **FIXED** (2025-01-30) - Added explicit global variable update at end of validation

### Impact
- Configuration corrections were silently lost
- Invalid values could persist even after validation attempted to correct them
- Inconsistent state between local variables and global variables
- Bugs that should have been caught by validation persisted

### Lesson
**When validation functions correct or transform values, always persist the corrected value to global state.** Don't assume that intermediate validation steps will persist corrections - explicitly update globals at the end of the validation chain.

### Pattern to Follow
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

### Key Principles for State Persistence

1. **Explicit Persistence at End of Chain**
   - Don't rely on intermediate functions to persist state
   - Always update global state after all transformations complete
   - Ensures consistency between local and global variables

2. **Document Side Effects**
   - Clearly document that function updates global variables
   - Note when updates occur (after successful validation)
   - Explain why persistence is necessary

3. **Handle All Code Paths**
   - Early returns: Ensure state is persisted before returning
   - Error paths: Don't persist invalid values
   - Success paths: Always persist corrected values

4. **Test State Persistence**
   - Test that corrections are persisted to global variables
   - Test that invalid values are not persisted
   - Test edge cases (empty values, defaults, type corrections)

### Edge Cases to Handle

1. **Optional Empty Variable with No Default**
   - Early return without updating global (correct behavior)
   - No default to apply, so no update needed

2. **Optional Empty Variable with Default**
   - Default applied by `apply_config_default` (which updates global)
   - Still need to ensure final value is persisted after all validations

3. **Invalid Value Corrected**
   - Validation functions correct value (e.g., clamp to range)
   - Must persist corrected value, not original invalid value

4. **Function Called with Value Parameter**
   - Even when value passed as parameter, corrections need persistence
   - Ensures consistency whether called with or without parameter

5. **Unknown Variable (Not in Schema)**
   - Early return without update (correct for backward compatibility)
   - No validation to perform, so no update needed

### Systematic Application
- When validation functions correct values, always persist corrections
- Update global state explicitly at end of validation chain
- Don't assume intermediate functions will persist state
- Document side effects (global variable updates) in function documentation
- Test that corrections are persisted to global variables
- Use safe assignment functions (`safe_set_variable`) for consistency

### Example: Validation Correction Persistence

**Scenario:** Invalid optional integer value gets corrected
```bash
# Config file has: PING_COUNT="abc" (invalid, should be integer)
# Schema defines: optional|integer|min:1,max:10|default:3

# Validation process:
# 1. apply_config_default: "abc" → "abc" (no default applied, value exists)
# 2. validate_config_type: "abc" → "3" (corrected to default, invalid type)
# 3. validate_config_rules: "3" → "3" (within range, valid)

# CRITICAL: Must persist "3" to global PING_COUNT variable
# Without fix: PING_COUNT still contains "abc" (incorrect)
# With fix: PING_COUNT contains "3" (corrected)
```

**Test Coverage:**
- ✅ Invalid optional integer value gets corrected to default
- ✅ Out-of-range value below minimum gets corrected
- ✅ Out-of-range value above maximum gets corrected
- ✅ Valid value is preserved (not overwritten)
- ✅ Global variable is updated after all corrections

---

## 12. Always Check File Readability Before File Operations

### Problem
Found 10 potential hang points where file operations could hang indefinitely on unreadable files (chmod 000):
- `cat`, `grep`, `wc`, `head`, `tail` commands hang when reading unreadable files
- `cp` and `mv` commands hang when operating on unreadable files
- Error suppression (`2>/dev/null` or `|| true`) does NOT prevent hangs
- Functions that output values must return empty strings, not just exit codes

**Status:** ✅ **FIXED** (2025-12-30) - Added readability checks before all file operations

### Impact
- Scripts could hang indefinitely when encountering unreadable files
- Tests would timeout instead of completing gracefully
- Production scripts could become unresponsive
- Functions expected to output values would return nothing instead of empty strings

### Lesson
**Always check file readability before attempting file operations.** Error suppression is not enough - commands still block even with `2>/dev/null`. Check readability BEFORE the operation, not after.

### Pattern to Follow
```bash
# ✅ GOOD: Check readability before reading
if file_exists_and_readable "$file"; then
    value=$(cat "$file" 2>/dev/null || echo "default")
else
    value="default"
fi

# ❌ BAD: Error suppression doesn't prevent hangs
value=$(cat "$file" 2>/dev/null || echo "default")  # Can still hang!

# ✅ GOOD: Remove unreadable or unwritable file before atomic write
# atomic_write_file() now handles this automatically, but if calling directly:
if [[ -f "$file" ]] && (! file_exists_and_readable "$file" || ! [[ -w "$file" ]]); then
    rm -f "$file" 2>/dev/null || true
fi
atomic_write_file "$file" "$content"

# ❌ BAD: Atomic write can hang on unreadable or unwritable target
echo "$content" > "$file.tmp"
mv "$file.tmp" "$file"  # Can hang if $file is unreadable (chmod 000) or unwritable (chmod 444)!
```

### Key Principles for File Operations

1. **Check Before Reading**
   - Use `file_exists_and_readable` before `cat`, `grep`, `wc`, `head`, `tail`
   - Provide sensible defaults when files are unreadable
   - Log warnings but don't fail the script

2. **Remove Before Writing**
   - Remove unreadable or unwritable target files before atomic writes (`mv` operations)
   - Prevents hangs when overwriting unreadable files (chmod 000) or unwritable files (chmod 444)
   - Use `rm -f` which can remove unreadable/unwritable files safely
   - `atomic_write_file()` now handles this automatically - checks both readability and writability

3. **Functions Must Output Values**
   - If function is expected to output a value, it must `echo` the value
   - Returning exit code 0 is not enough - must output empty string if no value
   - Callers expect output, not just success/failure

4. **Graceful Degradation**
   - Handle unreadable files gracefully (skip, use defaults, log warnings)
   - Don't fail the entire script due to unreadable files
   - Maintain backward compatibility

### Operations That Can Hang on Unreadable Files

**Dangerous Operations (check readability/writability first):**
- `cat` - Reading file contents (check readability)
- `grep` - Searching file contents (check readability)
- `wc` - Counting lines/words (check readability)
- `cp` - Copying files (check readability)
- `mv` - Moving/overwriting files (during atomic writes) - can hang on unreadable OR unwritable files
- `head`/`tail` - Reading file portions (check readability)

**Safe Operations (don't hang):**
- `[[ -r "$file" ]]` - Permission check (returns immediately)
- `[[ -f "$file" ]]` - File existence check
- `stat` - File metadata operations
- `rm -f` - File removal (can remove unreadable files)
- `touch` - File creation

### Systematic Application
- Before any file read operation, check `file_exists_and_readable`
- Before atomic writes, remove unreadable or unwritable target files (or use `atomic_write_file()` which handles this)
- Clean up leftover `.tmp` files before atomic writes to prevent hangs
- Functions that output values must `echo` the value (even if empty)
- Use `file_exists_and_readable` consistently across codebase
- Note: `atomic_write_file()` automatically removes unreadable/unwritable files to prevent hangs
- Test with unreadable files (`chmod 000`) in test suite
- Document why readability checks are needed

### Additional Pattern: Clean Up Leftover .tmp Files

**Issue:** Leftover `.tmp` files from previous failed atomic write attempts can cause hangs if they become unreadable or if the directory becomes unwritable.

**Solution:** Always clean up `.tmp` files before attempting atomic writes:
```bash
# ✅ GOOD: Clean up .tmp files before atomic write
if [[ -f "${file}.tmp" ]]; then
    rm -f "${file}.tmp" 2>/dev/null || true
fi
atomic_write_file "$file" "$content"
```

**Why:** If a previous atomic write failed and left a `.tmp` file, and then the directory becomes unwritable or the `.tmp` file becomes unreadable, the `mv` operation in the next atomic write attempt could hang. Cleaning up ensures we start with a clean slate.

### Example: Function Return Value Bug

**Bug:** Function returns exit code but doesn't output value
```bash
# ❌ BAD: Returns success but outputs nothing
extract_lockfile_pid() {
    local lockfile="$1"
    if ! file_exists_and_readable "$lockfile"; then
        return 0  # Bug: Caller expects empty string, gets nothing!
    fi
    cat "$lockfile" | cut -d: -f1
}

# ✅ GOOD: Outputs empty string when no PID available
extract_lockfile_pid() {
    local lockfile="$1"
    if ! file_exists_and_readable "$lockfile"; then
        echo ""  # Return empty string (no PID available)
        return 0
    fi
    cat "$lockfile" | cut -d: -f1
}
```

### Code Patterns Established

**Pattern 1: Read Before Read Operations**
```bash
if file_exists_and_readable "$file"; then
    value=$(cat "$file" 2>/dev/null || echo "default")
else
    value="default"
fi
```

**Pattern 2: Remove Before Atomic Write**
```bash
if [[ -f "$file" ]] && ! file_exists_and_readable "$file"; then
    rm -f "$file" 2>/dev/null || true
fi
atomic_write_file "$file" "$content"
```

**Pattern 3: Graceful Degradation**
```bash
if ! file_exists_and_readable "$file"; then
    handle_error "WARNING" "File is unreadable: $file" 0
    return <sensible_default>
fi
```

### Specific Fixes Applied

**10 functions fixed to prevent hangs:**
1. `backup_corrupted_state_file` - Added readability check before `cp`
2. `recover_corrupted_state_file` - Remove unreadable file before recovery
3. `atomic_write_file` - Remove unreadable target before `mv`
4. `check_cooldown` - Check readability before `cat`
5. `check_rate_limit` - Check readability before `awk`/`wc`
6. `extract_lockfile_pid` - Check readability before `cat` + output empty string
7. Keepalive PID file read - Check readability before `cat`
8. `validate_state_file` - Use `file_exists_and_readable` consistently
9. `check_resource_constrained` - Check readability before `cat`
10. Test timeout wrapper - Added timeout to prevent indefinite hangs

### Code Review Checklist

When adding new file operations, ensure:
- [ ] Readability check before `cat`, `grep`, `wc`, `head`, `tail`
- [ ] Readability check before `cp` operations
- [ ] Remove unreadable files before `mv` operations (atomic writes)
- [ ] Handle unreadable files gracefully (skip, use default, log warning)
- [ ] Functions that output values must `echo` the value (even if empty)
- [ ] Test with `chmod 000` files in test suite
- [ ] Document why readability checks are needed

### Prevention Strategies

1. **Code Patterns**
   - Always use `file_exists_and_readable` before reading files
   - Use atomic write pattern with unreadable file removal
   - Provide sensible defaults when files are unreadable
   - Log warnings but don't fail the script

2. **Testing**
   - Add tests for unreadable file scenarios
   - Test with various permission combinations (000, 100, 200, 400, etc.)
   - Test race conditions (file becomes unreadable during execution)
   - Test in different environments (BATS, direct execution, cron)

3. **Documentation**
   - Document file operation patterns in coding guidelines
   - Add comments explaining why readability checks are needed
   - Document known limitations and workarounds

### Test Coverage Recommendations

**Add tests for unreadable file scenarios:**
- Functions return empty strings (not nothing) for unreadable files
- Atomic writes remove unreadable files before writing
- All file read operations check readability first
- Graceful degradation (skip, use defaults, log warnings)

**Example test:**
```bash
@test "extract_lockfile_pid returns empty string for unreadable file" {
    local lockfile="${TEST_DIR}/unreadable.lock"
    echo "123:456" > "$lockfile"
    chmod 000 "$lockfile"
    run extract_lockfile_pid "$lockfile"
    assert_success
    assert_output ""  # Must output empty string, not nothing
}
```

### Troubleshooting Unreadable File Issues

**Symptoms:**
- Script hangs indefinitely when encountering unreadable files
- Tests timeout instead of completing gracefully
- Commands appear to execute but never return

**Debugging Steps:**
1. Check if file has `chmod 000` permissions
2. Verify readability check exists before file operation
3. Test with `strace` to see which syscall is blocking
4. Check for race conditions (file becomes unreadable between check and operation)
5. Verify error suppression (`2>/dev/null`) is not used as a substitute for readability checks

**Common Mistakes:**
- Using `2>/dev/null` or `|| true` instead of readability checks (doesn't prevent hangs)
- Forgetting to check readability before `cp` or `mv` operations
- Not outputting empty strings from functions that return values
- Assuming commands will fail fast on unreadable files (they hang instead)

---

## 13. Always Respect Fake Mode in All Error Paths

### Problem
During exit code standardization, we discovered that `lib/lockfile.sh` was using `die()` directly for permission errors, which ignored fake mode (`--fake` flag). This caused tests to fail because the script would exit with error code 4 instead of gracefully exiting with code 0 in fake mode.

**Example of the issue:**
```bash
# ❌ BAD: Doesn't respect fake mode
if [[ $is_writable -eq 0 ]]; then
    die "STATE_DIR is not writable" "${EXIT_PERMISSION_ERROR:-4}"
fi
```

### Impact
- Tests fail when using `--fake` flag
- Script exits with error codes even when errors are logged but shouldn't cause failure
- Inconsistent behavior between fake mode and normal mode

### Lesson
**All fatal error paths must respect fake mode.** When a function needs to exit on error, it should use `handle_error_or_exit_fake_mode()` instead of `die()` directly. This ensures:
- Fake mode (`NO_ESCALATE=1`) exits gracefully with code 0
- Normal mode exits with the appropriate error code
- Tests can verify error handling without causing script failures

### Pattern to Follow
```bash
# ✅ GOOD: Respects fake mode
if [[ $is_writable -eq 0 ]]; then
    local error_msg="STATE_DIR is not writable: $lockfile_dir"
    if type handle_error_or_exit_fake_mode >/dev/null 2>&1; then
        if ! handle_error_or_exit_fake_mode "$error_msg" "${EXIT_PERMISSION_ERROR:-4}"; then
            # In fake mode, exit gracefully
            exit "${EXIT_SUCCESS:-0}"
        fi
        # In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
    elif type die >/dev/null 2>&1; then
        die "$error_msg" "${EXIT_PERMISSION_ERROR:-4}"
    else
        echo "ERROR: $error_msg" >&2
        exit "${EXIT_PERMISSION_ERROR:-4}"
    fi
fi

# ❌ BAD: Doesn't respect fake mode
if [[ $is_writable -eq 0 ]]; then
    die "STATE_DIR is not writable" "${EXIT_PERMISSION_ERROR:-4}"
fi
```

### When to Use Each Pattern

**Use `handle_error_or_exit_fake_mode()` when:**
- The error is fatal and should exit the script
- The error path needs to respect fake mode (for testing)
- The error occurs in functions called from main script entry points

**Use `die()` directly when:**
- The error is truly fatal and fake mode doesn't apply (e.g., internal library errors)
- The function is only called in contexts where fake mode is irrelevant
- The error occurs in utility functions that don't need fake mode support
- **The error prevents script execution entirely** (e.g., cannot create lockfile due to read-only directory) - these must fail even in fake mode since the script cannot proceed

**Use `handle_error()` when:**
- The error is non-fatal (WARNING or INFO severity)
- The error should be logged but execution should continue
- The error doesn't require script exit

### Systematic Application
- Before using `die()`, check if the error path should respect fake mode
- If fake mode is relevant, use `handle_error_or_exit_fake_mode()` instead
- Always use exit code constants (`EXIT_*`) instead of hardcoded numbers
- Test error paths with `--fake` flag to verify graceful exit
- **Always export `NO_ESCALATE` when setting it** - Even though sourced functions should see non-exported variables, explicitly exporting ensures `is_fake_mode()` works correctly in all contexts (e.g., when called from validation functions)

### Exception: Fatal Errors That Prevent Script Execution

**Some errors are so fatal that they must fail even in fake mode** because the script cannot proceed at all. Examples:
- Cannot create lockfile (read-only STATE_DIR) - script cannot run without lockfile
- Cannot access critical system resources required for execution

For these cases, exit with error code even in fake mode, but still log the error appropriately:

```bash
# ✅ GOOD: Fatal error that prevents execution - fails even in fake mode
if [[ $is_writable -eq 0 ]]; then
    local error_msg="STATE_DIR is not writable: $dir (cannot create lockfile)"
    # Log error (respects fake mode for logging)
    if type handle_error_or_exit_fake_mode >/dev/null 2>&1; then
        handle_error_or_exit_fake_mode "$error_msg" "${EXIT_PERMISSION_ERROR:-4}" 2>/dev/null || true
    fi
    # Always exit with error - script cannot proceed without lockfile
    die "$error_msg" "${EXIT_PERMISSION_ERROR:-4}"
fi
```

### Related Patterns
- See `DEVELOPER.md` section "Error Handling Patterns" for more examples
- See `lib/config.sh:handle_fatal_config_error()` for reference implementation
- See `lib/lockfile.sh:check_directory_writable_for_lockfile()` for fatal permission error handling example

---

## 14. Track Error State When Functions Log But Don't Exit

### Problem
`safe_parse_config_file()` was calling `handle_config_error()` when parsing errors occurred, but wasn't tracking whether errors happened. The function would log errors but then return 0 (success), causing `load_config()` to think parsing succeeded even when it failed.

### Impact
- Configuration files with syntax errors appeared to parse successfully
- Errors were logged but not propagated to callers
- Tests expecting failure would pass incorrectly
- Validation would fail later with confusing error messages

### Root Cause
`handle_config_error()` logs errors and exits in normal mode, but returns 1 in fake mode. When called from within a loop or function that continues processing, the return value must be checked to track error state.

### Lesson
**When calling error handlers that may return (instead of always exiting), check their return value and track error state.**

### Pattern to Follow
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

### Key Points
- Functions that call error handlers in loops must track error state
- Check return value of `handle_config_error()` and similar functions
- Return error status at end of function if any errors occurred
- In fake mode, error handlers return 1; in normal mode they exit

### Related Patterns
- See `lib/config.sh:safe_parse_config_file()` for reference implementation
- See `lib/logging.sh:handle_error_or_exit_fake_mode()` for return value behavior

---

## 15. Handle Race Conditions in Process Management Operations

### Problem
`stop_daemon()` in `vpn-keepalive.sh` was failing when `kill -TERM` returned an error, even if the process had already exited naturally. This caused test failures due to a race condition between checking if the process is running (`is_running()`) and actually sending the termination signal.

### Impact
- Tests failed intermittently due to race conditions
- Stop command would fail even when the daemon had already stopped
- Error handling was too strict for benign race conditions

### Root Cause
Between checking `is_running()` and calling `kill -TERM`, the process could exit naturally. When `kill -TERM` failed (because the process no longer exists), the code treated it as an error and exited with status 1, even though the desired outcome (process stopped) was already achieved.

### Lesson
**When managing processes, handle race conditions gracefully. If a process operation fails, verify the actual state before treating it as an error.**

### Pattern to Follow
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

### Key Points
- Process state can change between check and operation (TOCTOU - Time-Of-Check-Time-Of-Use)
- Verify actual state after operation failures before treating as error
- Distinguish between "process already stopped" (success) and "can't stop process" (error)
- Use `kill -0` to verify process existence without side effects

### Related Patterns
- See `vpn-keepalive.sh:stop_daemon()` for reference implementation
- See `lib/lockfile.sh` for similar race condition handling in lockfile operations
- See `ACCEPTABLE_RISKS.md` for documented race conditions that are acceptable

---

## 16. Mock All Commands Used by Recovery Verification

### Problem
When testing Tier 3 recovery (`full_restart()`), tests were timing out because:
- Tests mocked `ipsec restart` to succeed
- After recovery, `verify_ipsec_connections_active()` calls `ipsec status` to verify connections
- Tests didn't mock `ipsec status`, so it fell through to `exec /usr/bin/ipsec "$@"`
- If `/usr/bin/ipsec` doesn't exist or hangs, the test times out after 120 seconds

### Impact
- Tests fail with timeout errors instead of actual test failures
- Difficult to diagnose (timeout doesn't indicate what's missing)
- Wastes CI time waiting for timeouts

### Lesson
**When testing recovery actions, mock all commands used by verification functions.** Recovery functions often call verification functions that use additional commands beyond the recovery command itself.

### Pattern to Follow
```bash
# ✅ GOOD: Mock both restart and status
local mock_ipsec="${TEST_DIR}/ipsec"
cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ipsec restart succeeded"
    exit 0
elif [[ "$1" == "status" ]]; then
    # Return status output that includes the peer IP for verification
    echo "192.168.1.1"
    exit 0
fi
exec /usr/bin/ipsec "$@"
EOF
chmod +x "$mock_ipsec"

# ❌ BAD: Only mock restart (verification will fail/hang)
local mock_ipsec="${TEST_DIR}/ipsec"
cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ipsec restart succeeded"
    exit 0
fi
exec /usr/bin/ipsec "$@"  # Falls through to real command - may hang!
EOF
```

### Verification Functions That Need Mocks
- `verify_ipsec_connections_active()` - calls `ipsec status`
- `verify_byte_counters_resume()` - calls `ip xfrm state`
- `check_ipsec_phase2()` - calls `ipsec status` or `ip xfrm state`

### Systematic Application
- When testing Tier 3 recovery, check what verification functions are called
- Mock all commands used by verification functions, not just the recovery command
- Review `lib/recovery.sh` to see what commands verification functions use
- Test with timeout to catch missing mocks early

### Related Patterns
- See `tests/test_recovery_cascading_failures.sh` for examples of complete mocking
- See `tests/test_recovery_cooldown_rate_limit_interaction.sh` for realistic ipsec status output format
- See `lib/recovery.sh:verify_ipsec_connections_active()` for verification requirements

---

## 17. Don't Log Success When Operations Fail

### Problem
Functions that check for operation success but log success messages regardless of the check result create misleading logs and hide failures.

**Example Bug:**
```bash
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
```

### Why This Matters
- **Misleading Logs**: Logs show success when operations actually failed
- **Debugging Difficulty**: Makes it hard to identify when failures occur
- **Test Failures**: Tests that check for success messages may pass incorrectly
- **Operational Confusion**: Operators may think operations succeeded when they didn't

### Pattern to Follow
1. **Check operation result first**
2. **If operation fails:**
   - Log error
   - Return early (or handle error appropriately)
   - **Do NOT log success**
3. **If operation succeeds:**
   - Log success message
   - Continue with normal flow

### Functions That Must Follow This Pattern
- Functions that perform file operations (`atomic_write_file`, `set_peer_state`, etc.)
- Functions that perform external commands (`ipsec`, `ip`, etc.)
- Functions that modify system state
- Any function that logs success messages

### Systematic Application
- When adding success logging, ensure it's inside the success branch
- When fixing error handling, verify success messages aren't logged on failure
- Review existing functions for this pattern during code reviews
- Add tests that verify success messages only appear when operations succeed

### Related Patterns
- See `lib/state.sh:set_cooldown()` for correct pattern
- See `lib/state.sh:set_peer_state()` for comparison (returns error code, doesn't log success)
- See `tests/test_recovery_cascading_failures.sh` for test that verifies error handling

---

## 18. Schema Validation Order Affects Test Expectations

### Problem
Tests expected invalid variables to be skipped during `parse_location_config()`, but schema validation rejects unknown variables during `load_config()` before `parse_location_config()` runs.

**Example:**
```bash
# Test expected this to work:
LOCATION_NYC_EXTERNAL="203.0.113.1"
INVALID_VAR="value"  # Expected to be skipped by parse_location_config
# But schema validation rejects INVALID_VAR during load_config first
```

### Impact
- Tests fail with "Unknown configuration variable" errors
- Tests need to be updated to reflect validation order
- Confusion about where validation happens

### Lesson
**When adding validation layers, update tests to reflect the new validation order.** Schema validation is now the first gate, so tests should verify schema validation behavior, not downstream parsing behavior.

### Pattern to Follow
```bash
# ✅ GOOD: Test reflects schema validation happens first
@test "invalid variables rejected by schema" {
    # Schema validation rejects unknown variables during load_config
    run load_config "$config_file"
    assert_failure
    assert_output --partial "Unknown configuration variable"
}

# ❌ BAD: Test expects downstream parsing to skip invalid vars
@test "invalid variables skipped by parse_location_config" {
    load_config "$config_file"  # Fails here, never reaches parse_location_config
    parse_location_config  # Never reached
}
```

### Systematic Application
- When adding validation layers, identify all affected tests
- Update test expectations to match validation order
- Document validation order in test comments
- Consider testing validation at each layer separately

### Related Patterns
- See `lib/config.sh:safe_parse_config_file()` for schema validation
- See `lib/config.sh:parse_location_config()` for location parsing
- See `tests/test_config_location.sh` for updated test patterns

---

## 19. Test Helper Functions Can Create Duplicate Configurations

### Problem
Test helper functions that add default configurations can create duplicates when tests add the same configurations again.

**Example:**
```bash
# setup_location_test_vpn_monitor() calls setup_location_config() which adds:
# - LOCATION_NYC_EXTERNAL="203.0.113.1"
# - LOCATION_LA_EXTERNAL="198.51.100.1"

# Test then adds:
setup_location_test_vpn_monitor "${TEST_DIR}" \
    'LOCATION_NYC_EXTERNAL="203.0.113.1"'  # Duplicate!
```

### Impact
- Tests fail with "Duplicate location name detected" errors
- Confusion about why duplicates occur
- Need to understand helper function internals

### Lesson
**When test helpers add defaults, either use the helper and accept the defaults, OR use lower-level helpers directly to avoid defaults.**

### Pattern to Follow
```bash
# ✅ GOOD: Use lower-level helper to avoid defaults
setup_test_environment "${TEST_DIR}"
local config_file="${TEST_DIR}/vpn-monitor.conf"
setup_test_location_config "$config_file" \
    'LOCATION_CUSTOM_EXTERNAL="..."' \
    'LOCATION_CUSTOM_INTERNAL="..."'
TEST_CONFIG_FILE="$config_file"
TEST_SCRIPT=$(create_test_vpn_monitor_script ...)
export TEST_CONFIG_FILE TEST_SCRIPT

# ✅ GOOD: Use helper and accept defaults
setup_location_test_vpn_monitor "${TEST_DIR}"
# Uses default NYC and LA locations

# ❌ BAD: Use helper then add same locations again
setup_location_test_vpn_monitor "${TEST_DIR}" \
    'LOCATION_NYC_EXTERNAL="..."'  # Duplicate!
```

### Systematic Application
- Document what defaults helper functions add
- When tests need custom configs, use lower-level helpers
- When tests can use defaults, use higher-level helpers
- Consider helper functions that don't add defaults for custom scenarios

### Related Patterns
- See `tests/test_helper.bash:setup_location_test_vpn_monitor()` for helper with defaults
- See `tests/test_helper.bash:setup_test_location_config()` for lower-level helper
- See `tests/test_integration_location.sh` for examples of avoiding duplicates

---

## 20. Always Validate Timestamp Arithmetic to Prevent Overflow/Underflow

### Problem
During bug review, we found multiple locations performing unsafe timestamp arithmetic:
- Direct subtraction: `one_hour_ago=$((now - SECONDS_PER_HOUR))`
- Direct subtraction in loops: `while [[ $(($(get_unix_timestamp) - verify_start_time)) -lt $verify_timeout ]]`
- No bounds checking for negative results (underflow)
- No validation that timestamps are reasonable before calculations

### Impact
- Potential integer overflow/underflow in timestamp calculations
- Negative results from subtraction could cause infinite loops
- Invalid timeout/age calculations
- Edge case failures in year 2038+ (though 64-bit handles until ~292 billion years)

### Lesson
**Always use safe timestamp arithmetic functions for any timestamp calculations.** Direct arithmetic can overflow or underflow, especially when:
- Subtracting large time periods from timestamps
- Calculating differences between timestamps
- Adding time periods to timestamps

### Pattern to Follow
```bash
# ✅ GOOD: Use safe timestamp arithmetic functions
one_hour_ago=$(safe_timestamp_subtract "$now" "$SECONDS_PER_HOUR" 2>/dev/null || echo "0")
elapsed_time=$(safe_timestamp_diff "$current_time" "$start_time" 2>/dev/null || echo "0")
future_time=$(safe_timestamp_add "$now" "$SECONDS_PER_HOUR" 2>/dev/null || echo "$now")

# ❌ BAD: Direct arithmetic without validation
one_hour_ago=$((now - SECONDS_PER_HOUR))
elapsed_time=$(($(get_unix_timestamp) - verify_start_time))
```

### Safe Functions Available
- `validate_timestamp()` - Validates timestamp is reasonable (0 to year 2100)
- `safe_timestamp_subtract()` - Safely subtracts seconds from timestamp
- `safe_timestamp_add()` - Safely adds seconds to timestamp
- `safe_timestamp_diff()` - Safely calculates difference between two timestamps

### Systematic Application
- Replace all direct timestamp arithmetic with safe functions
- Always provide fallback values (e.g., `|| echo "0"`) when using safe functions
- Validate timestamps before using them in calculations
- Handle negative results gracefully (e.g., clamp to 0)

### Related Patterns
- See `lib/common.sh:validate_timestamp()` for timestamp validation
- See `lib/common.sh:safe_timestamp_subtract()` for safe subtraction
- See `lib/common.sh:safe_timestamp_add()` for safe addition
- See `lib/common.sh:safe_timestamp_diff()` for safe difference calculation

---

## 21. Always Validate Arithmetic Operations and Clamp Results to Expected Ranges

### Problem
During bug review, we found CPU usage calculation that could produce invalid values:
- No validation that `idle_diff <= total_diff` before division
- No clamping of result to expected 0-100 range
- Could produce negative CPU usage values if `idle_diff > total_diff` (timing edge case)
- Could produce values > 100 if calculation has floating point precision issues

### Impact
- Invalid CPU usage values (negative or > 100) passed to resource monitoring
- Resource monitoring could behave unexpectedly with invalid values
- Edge cases from timing issues or counter wraparound not handled

### Lesson
**Always validate arithmetic inputs and clamp results to expected ranges.** When performing calculations that should produce values in a specific range:
1. Validate inputs before calculation (e.g., check that differences are valid)
2. Perform the calculation
3. Clamp the result to the expected range as a defensive measure
4. Document why clamping is needed (even if it "shouldn't" be necessary)

### Pattern to Follow
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

### Systematic Application
- Always validate arithmetic inputs before calculations
- Always clamp percentage results to 0-100 range
- Always clamp other bounded values (e.g., timestamps, counts) to valid ranges
- Document edge cases that could cause invalid values
- Use defensive programming: clamp even if calculation "should" be correct

### Related Patterns
- See `lib/resources.sh:get_cpu_usage()` for example of input validation and result clamping
- See `lib/common.sh:safe_timestamp_*()` functions for safe arithmetic patterns

---

## 22. Always Preserve Exit Codes in Cleanup Functions with EXIT Traps

### Problem
When using EXIT traps for cleanup, the cleanup function must preserve the exit code from the main function. If the cleanup function always exits with a fixed code (e.g., 0), the actual exit code from the main function is lost.

**Example of the issue:**
```bash
# ❌ BAD: Loses exit code from main function
(
    local signal_exit_code=0
    cleanup_and_exit() {
        rm -f "$LOCKFILE"
        exit "$signal_exit_code"  # Always 0 if no signal received!
    }
    trap 'cleanup_and_exit' EXIT
    
    main_func "$@"
    # If main_func returns 1, cleanup runs and exits with 0, losing the error code
)
```

### Impact
- Exit codes from main functions are lost
- Scripts that check exit codes fail incorrectly
- Error conditions are masked
- Tests that verify exit codes fail

### Lesson
**Always capture and preserve the exit code from the main function in cleanup handlers.** When using EXIT traps:
1. Capture the exit code from the main function
2. Use it if no signal was received (signal handlers set their own exit codes)
3. Ensure cleanup functions are idempotent (safe to call multiple times)
4. Close file descriptors before removing files (more critical operation first)

### Pattern to Follow
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

### Key Principles

1. **Capture Exit Code Before Cleanup**
   - Store main function's exit code before cleanup runs
   - Use it if no signal was received

2. **Signal Handlers Override Exit Code**
   - INT signal should exit with 130
   - TERM signal should exit with 143
   - Only use main function's exit code if no signal was received

3. **Make Cleanup Idempotent**
   - Use a flag to prevent double cleanup
   - Safe to call cleanup function multiple times
   - EXIT trap may run even after explicit cleanup

4. **Order of Operations**
   - Close file descriptors first (more critical)
   - Remove files second
   - Suppress errors from both operations

5. **Error Suppression**
   - Use `2>/dev/null || true` for operations that may fail
   - File descriptor may already be closed
   - File may already be removed

### Systematic Application
- When using EXIT traps, always capture main function's exit code
- Check if signal was received before using main function's exit code
- Make cleanup functions idempotent with a flag
- Test exit code preservation in test suite
- Close file descriptors before removing files
- Suppress errors from cleanup operations

### Example: Fixed Lockfile Cleanup
```bash
# ✅ GOOD: Complete pattern with exit code preservation
acquire_lockfile_flock() {
    (
        local signal_exit_code=0
        local lock_acquired=0
        local cleanup_done=0
        
        cleanup_and_exit() {
            if [[ $cleanup_done -eq 1 ]]; then
                exit "${signal_exit_code:-0}"
            fi
            cleanup_done=1
            exec 9>&- 2>/dev/null || true
            if [[ $lock_acquired -eq 1 ]]; then
                rm -f "$LOCKFILE" 2>/dev/null || true
            fi
            exit "${signal_exit_code:-0}"
        }
        
        trap 'signal_exit_code=130; cleanup_and_exit' INT
        trap 'signal_exit_code=143; cleanup_and_exit' TERM
        trap 'cleanup_and_exit' EXIT
        
        # ... lock acquisition ...
        
        main_func "$@"
        local main_exit_code=$?
        
        if [[ ${signal_exit_code:-0} -eq 0 ]]; then
            signal_exit_code=$main_exit_code
        fi
        
        # Explicit cleanup
        exec 9>&- 2>/dev/null || true
        if [[ $lock_acquired -eq 1 ]]; then
            rm -f "$LOCKFILE" 2>/dev/null || true
        fi
        cleanup_done=1
    ) 9>"$LOCKFILE"
}
```

### Related Patterns
- See `lib/lockfile.sh:acquire_lockfile_flock()` for complete example
- See `lib/lockfile.sh:acquire_lockfile_fallback()` for fallback pattern
- Always test exit code preservation in test suite

---

## 23. Test Setup: Heredoc Variable Expansion

### Problem
During debugging, a test was failing because the config file contained literal `${TEST_DIR}` instead of the expanded path. The test used `<<'EOF'` (single quotes) which prevents variable expansion.

### Impact
- Test config file contained literal `${TEST_DIR}/readonly-parent/readonly-logs` instead of `/tmp/test-xyz/readonly-parent/readonly-logs`
- Script tried to create directory with literal `${TEST_DIR}` in the path
- Test failed because the expected behavior didn't match actual behavior

### Lesson
**When creating test config files with heredocs, use `<<EOF` (without quotes) if you need variable expansion, or `<<'EOF'` (with quotes) if you want literal strings.**

### Pattern to Follow
```bash
# ✅ GOOD: Variable expansion needed
cat >"$config_file" <<EOF
LOGS_DIR="${TEST_DIR}/readonly-parent/readonly-logs"
EOF

# ✅ GOOD: Literal string needed
cat >"$config_file" <<'EOF'
LOGS_DIR="${TEST_DIR}/readonly-parent/readonly-logs"
EOF

# ❌ BAD: Wrong choice for the use case
cat >"$config_file" <<'EOF'
LOGS_DIR="${TEST_DIR}/readonly-parent/readonly-logs"  # Won't expand!
EOF
```

### Systematic Application
- Before writing test config files, determine if variables need expansion
- Use `<<EOF` when variables should be expanded (most common case)
- Use `<<'EOF'` only when you specifically need literal strings (rare)
- When debugging test failures, check if heredoc expansion is the issue

### Related Patterns
- See `tests/test_main.sh:923` for correct usage
- Always verify test config files contain expected values after creation
- Use `cat "$config_file"` in test debugging to verify expansion

---

## 24. Always Extract External IP from LOCATIONS Using Helper Function

### Problem
During code review, found bug in `full_restart()` where external IP was incorrectly extracted from `LOCATIONS` array:
- `LOCATIONS` stores values in format: `"external:IP|internal:IPs"` (not just the IP)
- Code was using: `local external_ip="${LOCATIONS[$location_name]}"` ❌ **BUG FIXED**
- This would pass the full string `"external:192.168.1.1|internal:192.168.1.1"` to verification functions
- Same pattern existed correctly in `verify_ipsec_connections_active()` ✅ **ALREADY CORRECT**

### Impact
- Byte counter verification would fail (invalid IP format passed to functions)
- Verification would silently fail or produce incorrect results
- Recovery verification wouldn't work correctly for multiple locations

### Lesson
**Always use `get_location_external_ip()` helper function to extract external IP from LOCATIONS array.** The `LOCATIONS` array stores delimited strings, not just IPs. Always use the helper function with fallback regex pattern for consistency.

### Pattern to Follow
```bash
# ✅ GOOD: Use helper function with fallback
local external_ip=""
if command -v get_location_external_ip >/dev/null 2>&1; then
    external_ip=$(get_location_external_ip "$location_name" 2>/dev/null || echo "")
else
    # Fallback: extract from LOCATIONS format directly
    local location_data="${LOCATIONS[$location_name]:-}"
    if [[ "$location_data" =~ external:([^|]+) ]]; then
        external_ip="${BASH_REMATCH[1]}"
    fi
fi

# ❌ BAD: Direct array access (gets full delimited string)
local external_ip="${LOCATIONS[$location_name]}"
```

### Systematic Application
- When iterating over `LOCATIONS` array, always extract external IP using `get_location_external_ip()`
- If helper function unavailable, use regex fallback: `external:([^|]+)`
- Never assume `LOCATIONS[$name]` contains just the IP address
- Check existing code patterns (like `verify_ipsec_connections_active()`) for reference

### Related Patterns
- See `lib/recovery.sh:verify_ipsec_connections_active()` for correct pattern
- See `lib/recovery.sh:full_restart()` for fixed pattern
- `LOCATIONS` format: `"external:IP|internal:IPs"` (pipe separator)
- Always validate extracted IP is non-empty before use

---

## 25. Simplify Complex Conditionals When All Branches Converge

### Problem
During code review, found overcomplicated conditional logic where all branches ended with the same operation:
- `config.sh` had three-branch if/elif/else where all branches set `LOG_FILE="${LOGS_DIR}/${log_filename}"`
- `state.sh` had complex fallback logic that duplicated functionality already in `log_message()`
- Code was harder to read and maintain due to unnecessary nesting

### Impact
- Code harder to understand and maintain
- Increased risk of bugs when modifying logic
- Unnecessary complexity without functional benefit

### Lesson
**When all branches of a conditional converge to the same operation, extract that operation outside the conditional.** Simplify conditionals by:
1. Identifying what differs between branches (the condition)
2. Moving common operations outside the conditional
3. Using simpler logic that achieves the same result

### Pattern to Follow
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

### Additional Simplification Pattern
```bash
# ❌ BAD: Complex fallback logic duplicating existing functionality
if ! try_ensure_directory_exists "$LOGS_DIR"; then
    local log_file_writable=0
    if [[ -n "${LOG_FILE:-}" ]] && touch "$LOG_FILE" 2>/dev/null; then
        log_file_writable=1
    fi
    if [[ $log_file_writable -eq 0 ]] && [[ -n "${SCRIPT_DIR:-}" ]]; then
        # ... complex fallback logic ...
    fi
fi

# ✅ GOOD: Use existing abstraction that already handles failures
if ! try_ensure_directory_exists "$LOGS_DIR"; then
    # log_message() (called by handle_error) already handles logging failures gracefully
    handle_error "WARNING" "Failed to create logs directory: $LOGS_DIR" 0
fi
```

### Systematic Application
- Before writing complex conditionals, check if all branches converge
- Extract common operations outside conditionals
- Check if existing functions already handle the error case (like `log_message()` handling logging failures)
- Simplify conditionals by removing unnecessary flags and intermediate variables
- Verify logic equivalence after simplification

### Related Patterns
- See `lib/config.sh:696-713` for simplified log path computation
- **Update 2026-01-02**: Further simplified by removing unnecessary `expected_log_file` intermediate variable and redundant `dirname` call. The original code computed `expected_log_file` just to compare it, when direct directory comparison is clearer. Also removed unreachable error handling for empty `dirname` result (dirname always returns a value, even if it's `.`).
- See `lib/state.sh:74-80` for simplified logging directory creation failure handling
- Always verify behavior is equivalent after simplification

---

## 26. Distinguish Between Script Execution Success and Recovery Success

### Problem
When recovery actions are attempted but fail, the script was returning failure (exit code 1), causing the script to appear as if it failed to execute properly. However, the script successfully completed its monitoring task - it detected the failure, attempted recovery, and logged the results. Recovery failures are operational issues, not script execution failures.

### Impact
- Script exit codes don't accurately reflect script execution success vs. operational success
- Monitoring systems may alert on script execution failures when the script actually completed successfully
- Tests expect script to succeed when recovery is attempted, even if recovery fails

### Solution
Modified `monitor_location()` to return 0 (success) when recovery is attempted (Tier 2 or Tier 3), even if recovery fails. The script only returns 1 (failure) when:
- VPN check fails and no recovery was attempted (Tier 1 or below threshold)
- There's an actual script execution error

### Pattern to Follow
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

### Key Insight
**Script execution success ≠ Operational success.** The script's job is to monitor and attempt recovery. If recovery is attempted (even if it fails), the script has successfully completed its monitoring task. Recovery failures are logged and can be detected via log monitoring, but they shouldn't cause the script to exit with failure.

### Related Patterns
- See `lib/recovery.sh:monitor_location()` lines 1514-1523 for implementation
- Recovery failures are logged via `handle_error()` and `log_message()`
- Script exit codes should reflect execution success, not operational outcomes
- Operational failures (VPN down, recovery failed) are logged but don't prevent successful script completion

---

## Summary: Key Takeaways

These lessons should be applied systematically in future development and code reviews to prevent similar issues:

1. **Always use abstraction layers consistently** - Don't construct paths directly, use abstraction functions
2. **Always use validation functions instead of inline regex** - Validation functions provide consistent, secure validation
3. **Verify function signatures match calls** - Check argument counts and types before calling functions
4. **Remove debug code, don't just comment it** - Commented code adds confusion and maintenance burden
5. **Verify findings before documenting** - Confirm issues exist before documenting them
6. **Check for code duplication across files** - Look for similar patterns that could be extracted
7. **Test coverage should match code paths** - Ensure all code paths are tested
8. **Systematic code review process** - Follow structured approach to catch issues
9. **Common patterns to watch for** - Be aware of common anti-patterns
10. **Use character-by-character parsing for complex syntax** - Avoid regex for complex parsing
11. **Always persist corrected values after validation** - Don't just validate, save corrected values
12. **Always check file readability before file operations** - Prevent hangs from unreadable files
13. **Always respect fake mode in all error paths** - Use `handle_error_or_exit_fake_mode()` for fatal errors
14. **Track error state when functions log but don't exit** - Return error codes even when logging errors
15. **Handle race conditions in process management operations** - Check process state after operations
16. **Mock all commands used by recovery verification** - Ensure tests don't depend on real system commands
17. **Don't log success when operations fail** - Only log success when operation actually succeeds
18. **Schema validation order affects test expectations** - Update tests to reflect validation order when adding validation layers
19. **Test helper functions can create duplicate configurations** - Use lower-level helpers or accept defaults to avoid duplicates
20. **Always validate timestamp arithmetic** - Use safe timestamp functions to prevent overflow/underflow
21. **Always validate arithmetic operations and clamp results** - Validate inputs and clamp results to expected ranges
22. **Always preserve exit codes in cleanup functions** - Capture and preserve main function's exit code in EXIT trap handlers
23. **Test setup: Heredoc variable expansion** - Use `<<EOF` for expansion, `<<'EOF'` for literal strings
24. **Always extract external IP from LOCATIONS using helper function** - LOCATIONS array stores delimited strings, not just IPs
25. **Simplify complex conditionals when all branches converge** - Extract common operations outside conditionals
26. **Distinguish between script execution success and recovery success** - Script execution success ≠ Operational success

---
