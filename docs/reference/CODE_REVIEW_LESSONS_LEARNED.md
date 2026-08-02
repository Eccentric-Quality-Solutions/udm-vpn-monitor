# Code Review Lessons Learned

**Date:** 2025-01-15
**Last Updated:** 2026-07-19
**Context:** Comprehensive codebase review for errors, bugs, DRY violations, and bad practices

## Overview

This document captures lessons learned from conducting systematic code reviews. These patterns should be applied systematically to prevent similar issues in the future.

**Use `CODE_PATTERNS.md` for day-to-day coding and review** — search it during review, don't read linearly. This document is **historical context**: specific bugs, impact, and fixes. See also [ISSUES_AND_TECH_DECISIONS.md](../ISSUES_AND_TECH_DECISIONS.md) for a short distillation.

**Document structure:** Sections **1–29** (plus **20a**, **21a**) are full write-ups. Items **30–49** in [Summary: Key Takeaways](#summary-key-takeaways) are summary-only bullets. Bash gotchas **39–41**, **45**, **47–49** are expanded in [BASH_CODING_GUIDE.md](BASH_CODING_GUIDE.md#review-discovered-bash-gotchas); deploy/SSH patterns (**42**, **46**) and test infra (**43**, **44**) stay in summary + `CODE_PATTERNS.md`. Testing patterns live in [TEST_PATTERNS.md](../testing/TEST_PATTERNS.md).

**External style guides:** We align with [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) quoting, `[[ ]]`, ShellCheck, and `shfmt` — but **we do not follow** its advice to rewrite scripts over ~100 lines in a structured language. UDM OS constraints (no extra runtimes, cron resilience, IPsec tooling) require a large shell codebase; see [ARCHITECTURE.md](ARCHITECTURE.md) and project rules.

### Sidebar: Name operations by what `ip` actually does (2026-04)

Ensuring `LOCAL_UDM_IP` for `ping -I` uses **`ip addr add … dev <iface>`** (local address on an interface), not **`ip route add`**. Calling that a “route” in function names or logs confused it with UniFi route policy and FIB routes. Prefer names like **default LAN interface** / **ping source address** and a single constant (**`DEFAULT_LAN_INTERFACE`**, default `br0`).

---

## 1. Always Use Abstraction Layers Consistently

**Impact Level:** Critical  
**Applicability:** Project-Specific  
**Actionability:** High

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

### Related Patterns
- See `CODE_PATTERNS.md` section "State Management Patterns" → "Use Abstraction Layers for State File Paths" for the consolidated pattern
- See `lib/state/state_paths.sh:get_peer_state_file_path()` for reference implementation


---

## 2. Always Use Validation Functions Instead of Inline Regex

**Impact Level:** Critical  
**Applicability:** Universal (config/user/network input)  
**Actionability:** High

### Problem
During review, we found duplicate IP validation logic:
- `validate_ipv4()` function exists with proper validation (regex + octet range checks)
- Inline regex checks in `check_ping_connectivity()` (line 702) ✅ **FIXED**
- `check_local_ip_on_default_lan()` already uses `validate_ip_address()` ✅ **ALREADY CORRECT**

### Impact
- Inconsistent validation logic across codebase
- Maintenance burden (changes needed in multiple places)
- Potential for bugs if one location is updated but not others
- Inline regex doesn't validate octet ranges (0-255), allowing invalid IPs like "999.999.999.999"

### Lesson
**Use existing validation functions for config, user, and network input — not inline regex.** Validation functions provide range checks, edge-case handling, and a single source of truth.

**Exception — trusted structured output:** Inline regex is acceptable when parsing **kernel/tool output** (e.g. `ip xfrm state`, `ip route`) or log redaction filters, especially via shared helpers in `lib/common.sh` (`extract_spi_from_xfrm_line`, `build_xfrm_*_grep_pattern`). That is extraction/filtering, not accepting user input as valid.

### Pattern to Follow
```bash
# ✅ GOOD: Use validation function for input
if validate_ipv4 "$target_ip"; then
    # IPv4 handling
fi

# ✅ GOOD: Shared helper for structured xfrm line (not user input)
spi=$(extract_spi_from_xfrm_line "$line")

# ❌ BAD: Inline regex on config/user IP (incomplete validation)
if [[ "$target_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    # Accepts invalid octets like 999
fi
```

### Systematic Application
- Before using regex for **input** validation, check if `validate_ipv4()` or `validate_ip_address()` exists
- For **structured output**, prefer shared helpers in `CODE_PATTERNS.md` → "Shared Config and XFRM Regex Helpers"
- Do not flag intentional xfrm/route parsing regex during review if it uses centralized helpers or is clearly output extraction

### Related Patterns
- See `CODE_PATTERNS.md` section "Validation Patterns" → "Use Validation Functions Instead of Inline Regex"
- See `CODE_PATTERNS.md` → "Shared Config and XFRM Regex Helpers"
- See `lib/common.sh:validate_ipv4()` and `lib/common.sh:validate_ip_address()` for reference implementations


---

## 3. Verify Function Signatures Match Calls

**Impact Level:** Critical  
**Applicability:** Universal  
**Actionability:** High

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
- **When changing function signatures, search for ALL call sites, not just obvious ones**
- **Test function calls with missing arguments to catch signature mismatches**

### Related Issue: Prefix Parameter Bug (2026-01-04)
When `log_message` and `handle_error` were updated to require a `prefix` parameter, many call sites were missed:
- `handle_error_or_exit_fake_mode` calls missing prefix parameter (20+ instances)
- `log_message` calls missing prefix parameter (40+ instances)
- `handle_error` calls missing prefix parameter (6+ instances)

**Lesson:** When adding required parameters, use comprehensive grep patterns:
```bash
# Find all calls to function
grep -rn "function_name(" lib/ scripts/ --include="*.sh"

# Find calls missing new parameter
grep -rn "function_name.*\"[^"]*\"[^,)]*$" lib/ scripts/ --include="*.sh"
```

**Also:** Bash parameter expansion patterns like `${location_name:+ ...}${location_name:- ...}` can be buggy:
- `${var:-default}` expands to `var` if set, `default` if unset/empty
- When `var` is set, the pattern `${var:+word1}${var:-word2}` expands to `word1` + `var` (not `word1` + `word2`)
- **Fix:** Use only `${var:+word}` if `var` should always be provided, or use conditional logic


---

## 4. Remove Debug Code, Don't Just Comment It

**Impact Level:** High  
**Applicability:** Universal  
**Actionability:** High

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

**Impact Level:** Medium  
**Applicability:** Universal  
**Actionability:** Medium

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

**Impact Level:** High  
**Applicability:** Universal  
**Actionability:** Medium

### Problem
Found `sanitize_location_name()` defined in both aggregate entry files (pre-decomposition):
- `lib/config.sh` (later `lib/config/location_parsing.sh`)
- `lib/state.sh` (later `lib/state/state_paths.sh`)

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

### Related Patterns
- When consolidating, prefer `lib/common.sh` for shared utilities

### Resolution Example
When consolidating `sanitize_location_name()`:
1. ✅ Moved function to `lib/common.sh` (shared utilities)
2. ✅ Removed duplicates from config and state modules (formerly `lib/config.sh` and `lib/state.sh`)
3. ✅ Removed duplicate from `scripts/migrate-config-to-locations.sh`
4. ✅ Updated documentation to note function location
5. ✅ Verified all tests pass
6. ✅ Verified both files source `common.sh` (ensuring function availability)


---

## 7. Test Coverage Should Match Code Paths

**Impact Level:** High  
**Applicability:** Testing-Only  
**Actionability:** High

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

**Impact Level:** High  
**Applicability:** Universal  
**Actionability:** Medium

### What Worked Well
1. **Systematic file-by-file review** - Ensured comprehensive coverage
2. **Categorizing issues** - Made prioritization easier
3. **Verifying findings** - Caught false positives before documenting
4. **Cross-referencing** - Found related issues by following patterns

### Process to Follow
1. **Start with main scripts** - Understand entry points
2. **Review library modules** - Check for duplication and consistency (see [Lesson 6: Check for Code Duplication Across Files](#6-check-for-code-duplication-across-files) for detailed guidance)
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

**Impact Level:** High  
**Applicability:** Universal  
**Actionability:** Medium

### Code Duplication Patterns
**Note:** For detailed guidance on detecting and consolidating code duplication, see [Lesson 6: Check for Code Duplication Across Files](#6-check-for-code-duplication-across-files).

Common duplication patterns to watch for:
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

### Code Review Checklist Items
When reviewing code, check for:
- [ ] Convergent conditionals (all branches end with same operation) - see Lesson 23
- [ ] Code duplication across files
- [ ] Functions with identical names in multiple files
- [ ] Similar logic repeated with slight variations
- [ ] Magic numbers used in multiple places
- [ ] Error handling patterns repeated
- [ ] Function calls with wrong number of arguments
- [ ] Inconsistent use of abstraction layers
- [ ] Direct path construction instead of using helpers
- [ ] Missing input validation
- [ ] Debug code left in production
- [ ] Hardcoded paths
- [ ] Commented-out code blocks
- [ ] Inconsistent error handling
- [ ] Magic numbers without constants


---

## 10. Use Character-by-Character Parsing for Complex Syntax

**Impact Level:** Critical  
**Applicability:** Universal  
**Actionability:** High

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

### Related Patterns
- See `CODE_PATTERNS.md` section "String Parsing and Manipulation Patterns" → "Character-by-Character Parsing for Complex Syntax" for the consolidated pattern
- See `lib/config/config_loading.sh:safe_parse_config_file()` for reference implementation

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

**Impact Level:** Critical  
**Applicability:** Universal  
**Actionability:** High

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

### Related Patterns
- See `CODE_PATTERNS.md` section "State Management Patterns" → "Persist Corrected Values After Validation" for the consolidated pattern
- See `lib/config/config_validation.sh:validate_config_var()` for reference implementation

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

**Impact Level:** Critical  
**Applicability:** Bash (unreadable files hang commands)  
**Actionability:** High

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
- **Bash glob expansion** (`for file in "${DIR}"/*`) - Can hang when expanding patterns that match unreadable files. Use `find` with `-print0` and null-delimited reading instead.

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
- **Avoid bash glob expansion** (`for file in "${DIR}"/*`) when iterating over files that might be unreadable. Use `find` with `-print0` and null-delimited reading instead:
  ```bash
  # ✅ GOOD: Use find to safely enumerate files
  while IFS= read -r -d '' file; do
      if ! file_exists_and_readable "$file"; then
          continue
      fi
      # Process file
  done < <(find "$DIR" -maxdepth 1 -type f -name "pattern*" -print0 2>/dev/null)
  
  # ❌ BAD: Glob expansion can hang on unreadable files
  for file in "${DIR}"/*pattern*; do
      # Can hang if file is unreadable (chmod 000)
  done
  ```
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

**Impact Level:** Important  
**Applicability:** Project-Specific (BATS fake mode / `NO_ESCALATE`)  
**Actionability:** High

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
- Fake mode (`NO_ESCALATE=1`) logs error and returns 1 (allows caller to decide exit behavior)
- Normal mode exits with the appropriate error code
- Tests can verify error handling appropriately (see fake-mode exit behavior guidance in `docs/CODE_PATTERNS.md` and `docs/testing/TEST_PATTERNS.md` for when to exit with error code vs. code 0 in fake mode)

### Pattern to Follow
```bash
# ✅ GOOD: Respects fake mode
if [[ $is_writable -eq 0 ]]; then
    local error_msg="STATE_DIR is not writable: $lockfile_dir"
    if type handle_error_or_exit_fake_mode >/dev/null 2>&1; then
        if ! handle_error_or_exit_fake_mode "SYSTEM" "$error_msg" "${EXIT_PERMISSION_ERROR:-4}"; then
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
- See `CODE_PATTERNS.md` section "Error Handling Patterns" → "Fake Mode Support" for the consolidated pattern
- See `DEVELOPER.md` section "Error Handling Patterns" for more examples
- See `lib/config/config_loading.sh:handle_fatal_config_error()` for reference implementation
- See `lib/lockfile.sh:check_directory_writable_for_lockfile()` for fatal permission error handling example


---

## 14. Track Error State When Functions Log But Don't Exit

**Impact Level:** Important  
**Applicability:** Universal  
**Actionability:** High

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
- See `CODE_PATTERNS.md` section "Error Handling Patterns" → "Track Error State When Functions Log But Don't Exit" for the consolidated pattern
- See `lib/config/config_loading.sh:safe_parse_config_file()` for reference implementation
- See `lib/logging.sh:handle_error_or_exit_fake_mode()` for return value behavior


---

## 15. Handle Race Conditions in Process Management Operations

**Impact Level:** Important  
**Applicability:** Universal  
**Actionability:** High

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
- See `CODE_PATTERNS.md` section "Process Management Patterns" → "Handle Race Conditions in Process Management" for the consolidated pattern
- See `vpn-keepalive.sh:stop_daemon()` for reference implementation
- See `lib/lockfile.sh` for similar race condition handling in lockfile operations
- See `ACCEPTABLE_RISKS.md` for documented race conditions that are acceptable
- **PID file single-owner:** For daemon PID files (systemd Type=forking), let only the parent write; the child must not touch the PID file on exit to avoid races. `stop_daemon` and `is_running()` handle removal. (vpn-keepalive.sh fix 2026-02-23)


---

## 16. Don't Log Success When Operations Fail

**Impact Level:** Important  
**Applicability:** Testing-Only  
**Actionability:** High

**Note:** Testing-related patterns for this lesson may be found in `TEST_PATTERNS.md`. This section preserves the historical context of the bug discovery and fix.

### Problem
Functions that check for operation success but log success messages regardless of the check result create misleading logs and hide failures.

**Example Bug (historical — `set_cooldown()` removed; cooldown replaced by `MIN_RESTART_INTERVAL_SECONDS`):**
```bash
# ❌ BAD: Logs success even when write fails
set_cooldown() {
    local minutes="$1"
    local cooldown_until
    cooldown_until=$(get_timestamp_plus_minutes "$minutes")
    if ! atomic_write_file "$COOLDOWN_UNTIL_FILE" "$cooldown_until"; then
        handle_error "ERROR" "SYSTEM" "Failed to set cooldown period" 0
        # Bug: Function continues and logs success below!
    fi
    log_message "INFO" "SYSTEM" "Cooldown period set for $minutes minutes"  # Wrong! Logs even on failure
}

# ✅ GOOD: Return early on error, only log success when operation succeeds
set_cooldown() {
    local minutes="$1"
    local cooldown_until
    cooldown_until=$(get_timestamp_plus_minutes "$minutes")
    if ! atomic_write_file "$COOLDOWN_UNTIL_FILE" "$cooldown_until"; then
        handle_error "ERROR" "SYSTEM" "Failed to set cooldown period (file: $COOLDOWN_UNTIL_FILE)" 0
        return 0  # Return early - don't log success
    fi
    log_message "INFO" "SYSTEM" "Cooldown period set for $minutes minutes"  # Only logs on success
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
- See `CODE_PATTERNS.md` section "Logging Patterns" → "Don't Log Success When Operations Fail" for the consolidated pattern
- See `lib/state/peer_state.sh:set_peer_state()` for correct pattern (returns error code, doesn't log success on failure)
- See `tests/test_recovery_cascading_failures.sh` for test that verifies error handling


---

## 17. Always Sort Timestamps When Finding Min/Max Values

**Impact Level:** Important  
**Applicability:** Project-Specific  
**Actionability:** High

### Problem
During rate limiting refactoring (2026-01-12), we found that `check_rate_limit()` used `tail -n 1` to get the "most recent" restart timestamp, assuming the last line in the file was the most recent. However, `record_restart()` doesn't sort timestamps - it just appends them. If timestamps are added out of order (e.g., due to clock skew, file corruption recovery, or concurrent writes), the last line might not be the most recent timestamp.

**Original Buggy Code:**
```bash
# Assumed last line = most recent (WRONG if timestamps unsorted)
last_restart=$(tail -n 1 "$RESTART_COUNT_FILE" 2>/dev/null | grep -E '^[0-9]+$' || echo "0")
```

### Impact
- Incorrect rate limiting decisions (allowing or blocking restarts based on wrong timestamp)
- Minimum restart interval check could fail incorrectly
- Could allow rapid restarts when they should be blocked, or block restarts when they should be allowed

### Lesson
**Never assume data files are sorted. Always sort before finding min/max values.** When reading timestamps or other ordered data from files:
- Don't assume the last line is the maximum
- Don't assume the first line is the minimum
- Always sort before extracting min/max values

### Pattern to Follow
```bash
# ✅ GOOD: Sort before finding max/min
last_restart=$(grep -E '^[0-9]+$' "$RESTART_COUNT_FILE" 2>/dev/null | sort -n | tail -n 1 || echo "0")
oldest_restart=$(grep -E '^[0-9]+$' "$RESTART_COUNT_FILE" 2>/dev/null | sort -n | head -n 1 || echo "0")

# ❌ BAD: Assume last line = most recent
last_restart=$(tail -n 1 "$RESTART_COUNT_FILE" 2>/dev/null | grep -E '^[0-9]+$' || echo "0")
```

### Systematic Application
- When finding maximum timestamp: `grep | sort -n | tail -n 1`
- When finding minimum timestamp: `grep | sort -n | head -n 1`
- When counting items in a window: Sort first, then filter
- Always validate that extracted values are numeric before using them

### Related Patterns
- See Lesson 18 for timestamp arithmetic validation
- See Lesson 12 for file readability checks before operations

**References:**
- Rate limiting refactoring (2026-01-12)
- `lib/state/global_state.sh:check_rate_limit()` - Fixed to sort timestamps

---

## 18. Always Validate Timestamp Arithmetic to Prevent Overflow/Underflow

**Impact Level:** Important  
**Applicability:** Project-Specific  
**Actionability:** High

**Note:** Testing-related patterns for this lesson may be found in `TEST_PATTERNS.md`. This section preserves the historical context of the bug discovery and fix.

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
- See `CODE_PATTERNS.md` section "Arithmetic and Calculation Patterns" → "Validate Timestamp Arithmetic to Prevent Overflow/Underflow" for the consolidated pattern
- See `lib/common.sh:validate_timestamp()` for timestamp validation
- See `lib/common.sh:safe_timestamp_subtract()` for safe subtraction
- See `lib/common.sh:safe_timestamp_add()` for safe addition
- See `lib/common.sh:safe_timestamp_diff()` for safe difference calculation


---

## 19. Always Validate Arithmetic Operations and Clamp Results to Expected Ranges

**Impact Level:** Important  
**Applicability:** Project-Specific  
**Actionability:** High

**Note:** Testing-related patterns for this lesson may be found in `TEST_PATTERNS.md`. This section preserves the historical context of the bug discovery and fix.

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
- See `CODE_PATTERNS.md` section "Arithmetic and Calculation Patterns" → "Validate Arithmetic Operations and Clamp Results" for the consolidated pattern
- See `lib/resources.sh:get_cpu_usage()` for example of input validation and result clamping
- See `lib/common.sh:safe_timestamp_*()` functions for safe arithmetic patterns


---

## 20. Always Preserve Exit Codes in Cleanup Functions with EXIT Traps

**Impact Level:** Critical  
**Applicability:** Universal  
**Actionability:** High

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

### Related Patterns
- See `CODE_PATTERNS.md` section "Process Management Patterns" → "Preserve Exit Codes in Cleanup Functions with EXIT Traps" for the consolidated pattern
- See `lib/lockfile.sh:acquire_lockfile_flock()` for complete example
- See `lib/lockfile.sh:acquire_lockfile_fallback()` for fallback pattern


---

## 20a. Wrapper/Cron Scripts: Don't Swallow Child Script Exit Codes

**Impact Level:** Medium  
**Applicability:** Wrapper and cron-invoked scripts that run a child in a loop  
**Actionability:** High

### Problem
Scripts that run a child in a loop (e.g. cron wrapper running the monitor) used `child >>log 2>&1 || true`, so all child failures were silent and operators had no visibility when the child crashed or exited with an error.

### Lesson
When running a child script in a loop, capture its exit code and log non-zero exits to the same log so failures are visible. Don't use `|| true` without recording the failure.

### Pattern to Follow
```bash
# ✅ GOOD: Capture and log failure
local exit_code=0
"$MONITOR_SCRIPT" >>"$CRON_LOG" 2>&1 || exit_code=$?
if [[ $exit_code -ne 0 ]]; then
    echo "$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z'): monitor exited with code $exit_code" >>"$CRON_LOG"
fi

# ❌ BAD: Silent failure
"$MONITOR_SCRIPT" >>"$CRON_LOG" 2>&1 || true
```

**Fixed:** vpn-monitor-wrapper.sh (M10, 2026-02-14)

---

## 21. Trap Cleanup Functions Must Handle Unset Variables with `set -u`

**Impact Level:** Critical  
**Applicability:** Universal  
**Actionability:** High

### Problem
When using EXIT traps with cleanup functions that access local variables, the cleanup function may execute after the function containing those variables has returned. With `set -u` (treat unset variables as errors), this causes "unbound variable" errors.

**Example of the issue:**
```bash
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

### Impact
- Script fails with "unbound variable" errors
- Cleanup doesn't execute properly
- Temporary files may not be cleaned up
- Tests fail unexpectedly

### Lesson
**Always use default value expansion (`${var:-}`) in cleanup functions when accessing variables that might be unset.** This is especially important when:
1. Script uses `set -u` or `set -euo pipefail`
2. Cleanup function accesses local variables from a parent function
3. EXIT trap executes after function return

### Pattern to Follow
```bash
# ✅ GOOD: Uses default value expansion to handle unset variables
anonymize_log_file() {
    local location_sed_script
    local ip_sed_script
    location_sed_script=$(mktemp)
    ip_sed_script=$(mktemp)
    
    cleanup_temp_files() {
        # Use default value expansion to handle case where variables might be unset
        rm -f "${location_sed_script:-}" "${ip_sed_script:-}"
    }
    trap cleanup_temp_files EXIT
    
    # ... function code ...
}
```

### Key Principles

1. **Default Value Expansion**
   - Use `${var:-}` syntax to provide empty string default
   - Prevents "unbound variable" errors with `set -u`
   - Safe to use even when variable is set (returns actual value)

2. **EXIT Trap Timing**
   - EXIT trap executes when script exits, not when function returns
   - Local variables may be out of scope when trap executes
   - Always assume variables might be unset in cleanup functions

3. **Idempotent Cleanup**
   - Cleanup should be safe to run multiple times
   - `rm -f` with default expansion handles missing files gracefully
   - No errors if variables are unset or files don't exist

### Systematic Application
- When using EXIT traps with cleanup functions, always use default value expansion for variables
- Test cleanup functions with `set -u` enabled to catch unbound variable errors
- Prefer cleanup functions over inline trap commands for better error handling
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

## 21a. Chain EXIT Traps in Test Helpers That May Be Called Multiple Times

**Impact Level:** Medium  
**Applicability:** Test helpers that set EXIT traps  
**Actionability:** High

### Problem
`setup_readonly_state_file()` in `tests/helpers/state.bash` set `trap "chmod ..." EXIT` on every call. A second call overwrote the first trap, so only the last file had its permissions restored on exit; earlier files were left read-only and could break later tests or leave the test dir in a bad state.

### Lesson
**When a test helper sets an EXIT trap and may be invoked multiple times in one test, chain with the existing trap instead of overwriting.** Use `trap -p EXIT` to read the current trap command, then set `trap "new_cleanup; existing_command" EXIT` so all cleanups run.

### Pattern to Follow
```bash
# ✅ GOOD: Chain with existing EXIT trap
restore_cmd="chmod $perms \"$path\" 2>/dev/null || true"
existing_trap=$(trap -p EXIT 2>/dev/null) || true
if [[ -n "$existing_trap" ]]; then
  existing_cmd=${existing_trap#trap -- \'}; existing_cmd=${existing_cmd%\' EXIT}
  trap "$restore_cmd; ${existing_cmd}" EXIT
else
  trap "$restore_cmd" EXIT
fi
```

**Fixed:** tests/helpers/state.bash (T3, 2026-02-14)

---

## 22. Always Extract External IP from LOCATIONS Using Helper Function

**Impact Level:** Critical  
**Applicability:** Project-Specific  
**Actionability:** High

### Problem
During code review, found bug in `full_restart()` where external IP was incorrectly extracted from `LOCATIONS` array:
- `LOCATIONS` stores values in format: `"external:IP|internal:IPs"` (not just the IP)
- Code was using: `local external_peer_ip="${LOCATIONS[$location_name]}"` ❌ **BUG FIXED**
- This would pass the full string `"external:192.168.1.1|internal:192.168.1.1"` to verification functions
- Same pattern existed correctly in `verify_ipsec_connections_active()` ✅ **ALREADY CORRECT**

### Impact
- Byte counter verification would fail (invalid IP format passed to functions)
- Verification would silently fail or produce incorrect results
- Recovery verification wouldn't work correctly for multiple locations

### Lesson
**Always use `get_location_external_ip()` helper function to extract external IP from LOCATIONS array.** The `LOCATIONS` array stores delimited strings, not just IPs. Always use the helper function for consistency and proper parsing.

### Pattern to Follow
```bash
# ✅ GOOD: Use helper function directly
local external_peer_ip
if external_peer_ip=$(get_location_external_ip "$location_name" 2>/dev/null); then
    # Use external_peer_ip
else
    # Handle error: location not found or extraction failed
    handle_error "WARNING" "$location_name" "Failed to get external IP"
    continue  # or return, depending on context
fi

# ❌ BAD: Direct array access (gets full delimited string)
local external_peer_ip="${LOCATIONS[$location_name]}"
```

### Systematic Application
- When iterating over `LOCATIONS` array, always extract external IP using `get_location_external_ip()`
- The helper function is always available when `parse_location_config()` is available (they're in the same module)
- Always check the return value of `get_location_external_ip()` and handle errors appropriately
- Never assume `LOCATIONS[$name]` contains just the IP address
- Check existing code patterns (like `verify_ipsec_connections_active()`) for reference

### Related Patterns
- See `CODE_PATTERNS.md` section "Configuration Patterns" → "Extract External IP from LOCATIONS Using Helper Function" for the consolidated pattern
- See `lib/recovery/recovery_verification.sh:verify_ipsec_connections_active()` for correct pattern
- See `lib/recovery/recovery_orchestration.sh:full_restart()` for fixed pattern
- `LOCATIONS` format: `"external:IP|internal:IPs"` (pipe separator)
- Always validate extracted IP is non-empty before use


---

## 23. Simplify Complex Conditionals When All Branches Converge

**Note:** Testing-related patterns for this lesson may be found in `TEST_PATTERNS.md`. This section preserves the historical context of the bug discovery and fix. See also `CODE_PATTERNS.md` for the consolidated actionable pattern.

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

### Code Review Checklist
When reviewing conditionals, check for:
- [ ] All branches of if/elif/else blocks that end with the same operation
- [ ] Common operations that can be extracted outside the conditional
- [ ] Complex fallback logic that duplicates existing functionality
- [ ] Unnecessary intermediate variables or flags that can be removed
- [ ] Logic equivalence after simplification (verify with tests)

### Related Patterns
- See `CODE_PATTERNS.md` section "Error Handling Patterns" → "Simplify Complex Conditionals When All Branches Converge" for the consolidated pattern
- See `lib/config/config_loading.sh` (`compute_log_file_path()`) for simplified log path computation
- **Update 2026-01-02**: Further simplified by removing unnecessary `expected_log_file` intermediate variable and redundant `dirname` call. The original code computed `expected_log_file` just to compare it, when direct directory comparison is clearer. Also removed unreachable error handling for empty `dirname` result (dirname always returns a value, even if it's `.`).
- See `lib/state/state_init.sh` for simplified logging directory creation failure handling
- Always verify behavior is equivalent after simplification


---

## 24. Distinguish Between Script Execution Success and Recovery Success

**Impact Level:** Critical  
**Applicability:** Project-Specific  
**Actionability:** High

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
- See `CODE_PATTERNS.md` section "Error Handling Patterns" → "Distinguish Between Script Execution Success and Recovery Success" for the consolidated pattern
- See `lib/recovery/recovery_orchestration.sh:monitor_location()` for implementation
- Recovery failures are logged via `handle_error()` and `log_message()`


---

## 25. Always Re-Check Critical State Instead of Relying on Cached Values

**Impact Level:** Critical  
**Applicability:** Project-Specific  
**Actionability:** High

### Problem
Network partition check was relying on cached partition state (`get_network_partition_state()`) before re-checking. This caused issues:
- If network was partitioned but just recovered, recovery was still skipped based on stale cached state
- Partition state could be stale if state changed between when it was cached and when it was checked
- Recovery was incorrectly skipped when it shouldn't be

### Impact
- Recovery actions skipped when they shouldn't be
- Failure count didn't increment correctly when recovery was skipped
- VPN remained broken unnecessarily

### Lesson
**When making critical decisions based on state, always re-check the actual state rather than relying on cached values.** Cached state is useful for:
- Logging (showing state transitions)
- Performance optimization (avoiding expensive checks)
- But NOT for making critical decisions where stale state could cause incorrect behavior

### Pattern to Follow
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

### Systematic Application
- When making critical decisions (e.g., skip recovery, perform actions), always re-check the actual state
- Use cached state only for logging state transitions or performance optimization
- If state can change between checks, always re-check before making decisions

### Related Patterns
- See `CODE_PATTERNS.md` section "State Management Patterns" → "Always Re-Check Critical State Instead of Relying on Cached Values" for the consolidated pattern
- See `lib/recovery/recovery_orchestration.sh:monitor_location()` for implementation
- Network partition state is checked in `vpn-monitor.sh` at script start, but recovery code always re-checks
- Failure count increments before partition check to ensure accurate tracking even when recovery is skipped
- Cached state (`get_network_partition_state()`) is used only for logging state transitions, not for decision-making


---

## 26. Handle Hash Collisions in Anonymization Functions

**Impact Level:** Critical  
**Applicability:** Project-Specific  
**Actionability:** High

### Problem
The `anonymize_location()` function in `scripts/anonymize/anonymize-logs.sh` used hash-based mapping to anonymize location names:
- Hash function: `hash_string()` creates deterministic hash from location name
- Mapping: `hash % ${#CITY_NAMES[@]}` selects city name from array
- **Issue:** Multiple different location names can hash to the same city index, causing collisions

**Example:**
- Location "LOCATION_A" → hash → index 5 → "CHICAGO"
- Location "LOCATION_B" → hash → index 5 → "CHICAGO" (collision!)
- Location "LOCATION_C" → hash → index 5 → "CHICAGO" (collision!)

This caused duplicate anonymized location names in logs:
```
Found 11 location(s): LAS_VEGAS, CHICAGO, PHILADELPHIA, COLUMBUS, SACRAMENTO, CHICAGO, OMAHA, HONOLULU, SACRAMENTO, CHICAGO, OMAHA
```

### Impact
- Duplicate anonymized location names in anonymized logs
- Confusing log analysis (appears as if same location checked multiple times)
- Loss of information (can't distinguish between different original locations)
- Misleading log analysis results

### Root Cause
Hash-based mapping without collision resolution. Hash functions are designed to distribute values, but collisions are inevitable when mapping many inputs to fewer outputs (e.g., many locations to 50 city names).

### Lesson
**When using hash-based mapping to ensure uniqueness, always implement collision resolution.** Hash collisions are inevitable when mapping many inputs to fewer outputs. Collision resolution strategies:
1. **Track used values** - Maintain a set of already-assigned values
2. **Linear probing** - If hash-selected value is used, find next available
3. **Handle exhaustion** - When all values are used, append suffixes or use alternative mapping

### Pattern to Follow
```bash
# ✅ GOOD: Hash-based mapping with collision resolution
declare -A used_cities=()
while IFS= read -r location || [[ -n "$location" ]]; do
    if [[ -z "${location_map[$location]:-}" ]]; then
        # Use hash as starting point (deterministic)
        local hash
        hash=$(hash_string "$location")
        local start_index=$((hash % ${#CITY_NAMES[@]}))
        local city_index=$start_index
        local attempts=0

        # Find next available city (collision resolution)
        while [[ -n "${used_cities[${CITY_NAMES[$city_index]}]:-}" ]] && [[ $attempts -lt ${#CITY_NAMES[@]} ]]; do
            city_index=$(((city_index + 1) % ${#CITY_NAMES[@]}))
            attempts=$((attempts + 1))
        done

        # Handle exhaustion (all cities used)
        if [[ $attempts -ge ${#CITY_NAMES[@]} ]]; then
            # Append numeric suffix for uniqueness
            local suffix=1
            while [[ -n "${used_cities[${CITY_NAMES[$start_index]}_${suffix}]:-}" ]]; do
                suffix=$((suffix + 1))
            done
            anonymized_city="${CITY_NAMES[$start_index]}_${suffix}"
        else
            anonymized_city="${CITY_NAMES[$city_index]}"
        fi

        location_map["$location"]="$anonymized_city"
        used_cities["$anonymized_city"]=1
    fi
done < <(extract_locations "$input_file")

# ❌ BAD: Hash-based mapping without collision resolution
anonymize_location() {
    local original_location="$1"
    local hash
    hash=$(hash_string "$original_location")
    local city_index=$((hash % ${#CITY_NAMES[@]}))
    echo "${CITY_NAMES[$city_index]}"  # No collision checking!
}
```

### Systematic Application
- When using hash-based mapping, always check if the mapped value is already used
- Implement collision resolution (linear probing, chaining, or suffix appending)
- Track used values in an associative array or set
- Handle edge case where all values are exhausted
- Test with inputs that will cause collisions
- Ensure mapping remains deterministic (same input → same output) within a single run

### Related Patterns
- See `scripts/anonymize/anonymize-logs.sh` lines 312-325 for implementation
- Hash-based mapping is used for both IP and location anonymization
- IP anonymization doesn't have collision issues (maps to 10.x.x.x range with 256^3 possible values)
- Location anonymization needed collision resolution (maps to 50 city names)
- Determinism is maintained by using hash as starting point and processing locations in sorted order

### Notes
- **Determinism:** Mapping is deterministic within a single run because locations are sorted before processing (`extract_locations` uses `sort -u`)
- **Edge case:** When more locations than city names exist, numeric suffixes are appended (e.g., "CHICAGO_1", "CHICAGO_2")
- **Performance:** Linear probing is O(n) worst case, but acceptable for typical use (fewer than 50 locations)
- **Alternative approaches:** Could use perfect hashing or larger city name array, but current approach is pragmatic and sufficient


---

## 27. Parse All Selectors When Interacting with Kernel Interfaces

**Impact Level:** Important  
**Applicability:** Project-Specific  
**Actionability:** High

### Problem
During xfrm recovery implementation, we discovered that SA deletion was failing with "RTNETLINK answers: No such process" (exit code 2) even though the SAs existed. Root cause analysis revealed that SAs with `mark` attributes require the mark to be included as a selector in deletion commands. The code was only parsing and using `src`, `dst`, `proto`, and `spi` selectors, missing the `mark` selector.

**Status:** ✅ **FIXED** (2026-01-04) - Added mark parsing and inclusion in deletion commands. Updated (2026-01-04) - Fixed mark syntax to use "mark <value> mask <mask>" format instead of "mark <value>/<mask>"

### Impact
- xfrm recovery failed for all SAs with mark attributes
- Always fell back to full IPsec restart (more disruptive than intended)
- Error message was misleading ("No such process" suggests object doesn't exist, but it does)
- Recovery was less surgical than intended (affected all tunnels instead of just the failed one)

### Root Cause
Linux kernel interfaces (netlink, xfrm, iproute2) use selectors to identify objects. When an object has optional attributes (like `mark`), those attributes become part of the object's identity when present. To match an object for operations (get, delete, modify), ALL selectors must be provided, including optional ones that are present.

**Example:**
```bash
# SA exists with mark attribute
ip xfrm state
# Output:
# src 172.31.16.115 dst 172.31.23.27
#   proto esp spi 0x12345678
#   mark 0x12000000/0xfe000000

# ❌ BAD: Deletion without mark fails
ip xfrm state delete src 172.31.16.115 dst 172.31.23.27 proto esp spi 0x12345678
# Error: RTNETLINK answers: No such process

# ✅ GOOD: Deletion with mark succeeds (correct format: separate mark and mask parameters)
ip xfrm state delete src 172.31.16.115 dst 172.31.23.27 proto esp spi 0x12345678 mark 0x12000000 mask 0xfe000000
# Success
```

### Lesson
**When parsing structured output from kernel interfaces, parse ALL attributes that could be selectors, not just the required ones.** Optional attributes become required selectors when present. Missing selectors cause operations to fail even when the object exists.

### Pattern to Follow
```bash
# ✅ GOOD: Parse all potential selectors
parse_xfrm_sa() {
    local xfrm_output="$1"
    local src="" dst="" proto="" spi="" mark=""

    # Parse required selectors
    if [[ "$xfrm_output" =~ src[[:space:]]+([0-9.]+) ]]; then
        src="${BASH_REMATCH[1]}"
    fi
    # ... parse dst, proto, spi ...

    # Parse optional selectors (become required when present)
    if [[ "$xfrm_output" =~ mark[[:space:]]+(0x[0-9a-fA-F]+/0x[0-9a-fA-F]+) ]]; then
        mark="${BASH_REMATCH[1]}"
    fi

    # Include all selectors in operations
    # Note: Mark format in xfrm output is "0x<value>/0x<mask>", but ip xfrm commands require "mark <value> mask <mask>"
    local delete_cmd="ip xfrm state delete src \"$src\" dst \"$dst\" proto \"$proto\" spi \"$spi\""
    if [[ -n "$mark" ]]; then
        # Parse mark value and mask from format "0x<value>/0x<mask>"
        local mark_value mark_mask
        if [[ "$mark" =~ ^(0x[0-9a-fA-F]+)/(0x[0-9a-fA-F]+)$ ]]; then
            mark_value="${BASH_REMATCH[1]}"
            mark_mask="${BASH_REMATCH[2]}"
            delete_cmd="$delete_cmd mark \"$mark_value\" mask \"$mark_mask\""
        fi
    fi
    eval "$delete_cmd"
}

# ❌ BAD: Only parse required selectors
parse_xfrm_sa() {
    local xfrm_output="$1"
    local src="" dst="" proto="" spi=""

    # Parse only required selectors
    # ... parse src, dst, proto, spi ...

    # Missing: Don't parse mark (optional selector)

    # Deletion fails for SAs with mark
    ip xfrm state delete src "$src" dst "$dst" proto "$proto" spi "$spi"
    # Error: RTNETLINK answers: No such process (even though SA exists!)
}
```

### Key Principles for Kernel Interface Parsing

1. **Parse All Attributes**
   - Don't assume optional attributes are irrelevant
   - When an attribute is present, it becomes part of the object's identity
   - Parse all attributes that could be selectors

2. **Include All Selectors in Operations**
   - When performing operations (get, delete, modify), include all selectors
   - Optional selectors must be included when present
   - Missing selectors cause "No such process" errors even when object exists

3. **Handle Optional Selectors Gracefully**
   - Store optional selectors as empty strings when not present
   - Only include optional selectors in commands when they were parsed
   - Maintain backward compatibility (objects without optional selectors still work)

4. **Misleading Error Messages**
   - "No such process" (ESRCH) doesn't mean object doesn't exist
   - It means selectors don't match exactly
   - Object exists but can't be matched without all selectors

### Systematic Application
- When parsing kernel interface output (netlink, xfrm, iproute2), parse all attributes
- When performing operations on parsed objects, include all selectors
- Don't assume optional attributes are optional for matching
- Test with objects that have optional attributes to verify parsing
- Document which attributes are selectors vs. metadata

### Related Patterns
- See `lib/recovery/xfrm_recovery.sh:attempt_xfrm_recovery()` for mark selector parsing implementation
- SA **deduplication** must use composite keys (src+dst+SPI, not src+dst alone) — summary item **30**; implementation: `lib/detection/xfrm_detection.sh:deduplicate_sa_blocks()`; pattern: `CODE_PATTERNS.md` → "Extract Duplicate Awk Scripts to Helper Functions"
- Kernel interfaces that use selectors: xfrm (SAs, policies), netlink (routes, addresses), iproute2 (various)
- Error code ESRCH (No such process) often means "selector mismatch" not "object doesn't exist"

### Example: XFRM SA Parsing

**Before Fix:**
```bash
# Only parsed: src, dst, proto, spi
# Missing: mark (optional selector)
sa_list+=("$src|$dst|$proto|$spi")
# Deletion command missing mark → fails with "No such process"
ip xfrm state delete src "$src" dst "$dst" proto "$proto" spi "$spi"
```

**After Fix:**
```bash
# Parse all selectors including optional mark
sa_list+=("$src|$dst|$proto|$spi|${mark:-}")
# Deletion command includes mark when present → succeeds
if [[ -n "$mark" ]]; then
    delete_cmd="$delete_cmd mark \"$mark\""
fi
```

### Test Coverage
- ✅ Test mark parsing from xfrm output
- ✅ Test mark inclusion in deletion commands
- ✅ Test backward compatibility (SAs without marks)
- ✅ Test mixed scenarios (some SAs with mark, some without)


---

## 28. Avoid Over-Engineering Edge Case Protections and Theoretical Fallbacks

**Impact Level:** Important  
**Applicability:** Architecture/Design  
**Actionability:** Medium

### Problem (Policy deletion safeguard)
Added a safeguard to prevent policy deletion when `peer_ip` matched `LOCAL_UDM_IP`, based on theoretical concern about misconfiguration.

### Problem (Module sourcing fallbacks, 2026-01-18)
The codebase also included a centralized fallback system (`lib/fallbacks.sh`) that provided fallback implementations when core modules failed to source. This system:
- Required maintaining two implementations of the same functions (main + fallback)
- Added complexity to module sourcing (9+ files had fallback logic)
- Addressed theoretical edge cases (file corruption, syntax errors) that are extremely unlikely in production
- Created maintenance burden (keeping implementations in sync)

### Impact
- Added unnecessary complexity for edge cases that shouldn't happen
- Increased code maintenance burden
- Added test cases for scenarios that wouldn't occur in normal operation
- **Fallbacks:** Two implementations to keep in sync (~289 lines of fallback code); cognitive load for developers; risk of drift between main and fallback implementations

### Root Cause
Over-engineering based on theoretical concerns rather than practical risk assessment:
- `peer_ip` comes from `LOCATION_*_EXTERNAL` config (remote public IPs)
- `LOCAL_UDM_IP` is typically a private IP (192.168.x.x)
- These should never match in normal operation
- If misconfigured, VPN wouldn't work anyway
- Existing safeguards (fixed-string matching, exact IP match, scoped deletion) are sufficient
- If `common.sh` can't be sourced, the application is broken anyway — fail fast is better than silent degradation

### Solution
Removed the safeguard and the fallback system after pragmatic review:
- Existing protections are sufficient for policy deletion
- Edge cases are extremely unlikely and would be caught by testing/deployment
- Code is simpler and more maintainable
- **`lib/fallbacks.sh` removed** — modules source dependencies directly and fail fast

### Lesson
**Don't add safeguards or fallbacks for edge cases that:**
1. Are extremely unlikely to occur
2. Would be caught by normal testing/deployment
3. Are protected by existing safeguards
4. Add complexity without significant benefit

**When to add safeguards or fallbacks:**
- Realistic scenarios that could occur in production (e.g., xfrm → ipsec detection fallback)
- Scenarios that could cause significant harm if not prevented
- Scenarios that existing safeguards don't cover
- Optional features or command availability checks — not core module sourcing

### Pattern to Follow
```bash
# ✅ GOOD: Trust existing safeguards when they're sufficient
# peer_ip is validated, scoped deletion uses fixed-string matching
ip xfrm policy delete dst "$peer_ip" dir "$policy_dir"

# ✅ GOOD: Direct sourcing, fail fast
source "${LIB_DIR}/common.sh"

# ❌ BAD: Adding unnecessary safeguard for theoretical edge case
if [[ "$peer_ip" == "$LOCAL_UDM_IP" ]]; then
    return
fi

# ❌ BAD: Over-engineered fallback when core module fails to source
source "${LIB_DIR}/common.sh" 2>/dev/null || {
    source "${LIB_DIR}/fallbacks.sh" 2>/dev/null && define_common_fallbacks
}
```

### When Fallbacks Are Appropriate
- **Real-world alternatives:** Multiple ways to accomplish the same goal (e.g., xfrm vs ipsec)
- **Optional features:** Functionality can be disabled if dependencies are missing
- **Command availability:** Optional commands that enhance but don't require functionality

### When Fallbacks Are Over-Engineering
- **Core dependencies:** Module is essential for application operation
- **Theoretical failures:** File corruption, syntax errors — extremely unlikely in production
- **Silent degradation:** Fallback masks real problems

### Systematic Application
- Before adding edge case protections, assess likelihood, existing safeguards, actual risk, and value
- Prefer simpler code with existing safeguards over complex code with theoretical protections
- Document decisions to remove unnecessary safeguards

### References
- Implementation: `lib/recovery/xfrm_recovery.sh:delete_xfrm_policies()` (policy deletion without LOCAL_UDM_IP safeguard)
- Fallback removal: `lib/fallbacks.sh` deleted; aggregate modules (`lib/recovery.sh`, `lib/state.sh`, etc.) source `lib/*/` modules directly


---

## 29. Log Messages Must Accurately Reflect the Operation Performed

**Impact Level:** Important  
**Applicability:** Universal  
**Actionability:** High

### Problem
Log messages used terminology that didn't match the actual operation. Specifically, "Surgical cleanup completed" was logged even when using `ipsec reload` fallback, which affects all tunnels (not surgical/per-connection).

**Example of the issue:**
```bash
# ❌ BAD: Message says "surgical" but operation affects all tunnels
log_message "INFO" "$location_name" "Surgical cleanup completed for $location_name ($peer_ip) (via ipsec fallback, ...)"
# ipsec reload affects ALL tunnels, not just the failing one
```

### Impact
- Misleading log messages that don't accurately describe what happened
- Operators may misunderstand the scope of recovery operations
- Log analysis tools may incorrectly categorize recovery actions
- Documentation and troubleshooting become more difficult

### Lesson
**Log messages must accurately reflect the operation performed, not just the function name or intended behavior.** When a function has multiple code paths with different characteristics:
1. Use different terminology for different paths
2. Include context in the message (e.g., "via ipsec fallback")
3. Match terminology to actual behavior, not function name

### Pattern to Follow
```bash
# ✅ GOOD: Accurate terminology based on actual operation
if attempt_xfrm_recovery "$peer_ip" "$location_name"; then
    # xfrm recovery is surgical (per-connection)
    log_message "INFO" "$location_name" "Surgical cleanup completed for $location_name ($peer_ip) (via xfrm)"
else
    # ipsec reload affects all tunnels (not surgical)
    log_message "INFO" "$location_name" "Recovery completed for $location_name ($peer_ip) (via ipsec fallback, ...)"
fi

# ❌ BAD: Same terminology for different operations
log_message "INFO" "$location_name" "Surgical cleanup completed for $location_name ($peer_ip) (via ipsec fallback, ...)"
```

### Key Principles

1. **Terminology Must Match Behavior**
   - "Surgical" = affects only the specific connection/tunnel
   - "Recovery" = general term that can affect multiple connections
   - Use specific terms when the operation has specific characteristics

2. **Include Context in Messages**
   - Add qualifiers like "via ipsec fallback" to explain why the operation differs
   - Help operators understand the recovery path taken

3. **Function Names vs. Log Messages**
   - Function names can be aspirational (e.g., `surgical_cleanup()`)
   - Log messages must be factual (describe what actually happened)
   - Don't let function names dictate log message terminology

4. **Update Related Code**
   - When changing log messages, check:
     - Tests that assert on log messages
     - Log analysis scripts that parse messages
     - Documentation that references messages

### Systematic Application
- Review log messages for accuracy when adding fallback paths
- Use different terminology for different code paths when behavior differs
- Include context (method, scope) in log messages
- Update tests and log analysis tools when changing message formats
- Verify terminology matches actual operation, not just function intent

### References
- Implementation: `lib/recovery/ipsec_recovery.sh` (changed "Surgical cleanup completed" to "Recovery completed" for ipsec fallback)
- Test update: `tests/test_recovery_tier2.sh:602` (updated assertion for ipsec fallback path)
- Log analysis: `analyze-logs.sh:363` (updated pattern matching for new message format)


---

**Note:** Testing-specific mock and fixture patterns are documented in `docs/testing/TEST_PATTERNS.md` section 6 (Mock Setup and Cleanup), including mock command variants, test data centralization, and helper backward compatibility.

---

## Summary: Key Takeaways

These lessons should be applied systematically in future development and code reviews to prevent similar issues:

**Note:** Many of these lessons have been consolidated into actionable patterns in `CODE_PATTERNS.md`. For current coding patterns and best practices, refer to `CODE_PATTERNS.md`. This document preserves the historical context of how patterns were discovered.

**Sections 1–29** (plus **20a**, **21a**) are full write-ups above. **Items 30–49** below are summary-only; bash gotchas **39–41**, **45**, **47–49** → [BASH_CODING_GUIDE.md](BASH_CODING_GUIDE.md#review-discovered-bash-gotchas); **42**, **46** → `CODE_PATTERNS.md` (path resolution, SSH ControlMaster).

1. **Always use abstraction layers consistently** - Don't construct paths directly, use abstraction functions
2. **Always use validation functions instead of inline regex** - Validation functions provide consistent, secure validation (exception: trusted structured output — see `CODE_PATTERNS.md` XFRM regex helpers)
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
16. **Don't log success when operations fail** - Only log success when operation actually succeeds
17. **Always sort timestamps when finding min/max values** - Unsorted timestamp lists produce wrong min/max results
18. **Always validate timestamp arithmetic to prevent overflow/underflow** - Use safe timestamp functions for all timestamp calculations
19. **Always validate arithmetic operations and clamp results** - Validate inputs and clamp results to expected ranges
20. **Always preserve exit codes in cleanup functions** - Capture and preserve main function's exit code in EXIT trap handlers
20a. **Wrapper/cron scripts: don't swallow child exit codes** - Log non-zero child exits instead of `|| true` without recording failure
21. **Trap cleanup functions must handle unset variables with `set -u`** - Use default value expansion in cleanup functions
21a. **Chain EXIT traps in test helpers** - When a helper may run multiple times, chain traps instead of overwriting
22. **Always extract external IP from LOCATIONS using helper function** - LOCATIONS array stores delimited strings, not just IPs
23. **Simplify complex conditionals when all branches converge** - Extract common operations outside conditionals
24. **Distinguish between script execution success and recovery success** - Script execution success ≠ Operational success
25. **Always re-check critical state instead of relying on cached values** - Cached state can become stale, especially when state changes can occur between checks
26. **Handle hash collisions in anonymization functions** - When using hash-based mapping to ensure uniqueness, always implement collision resolution. Hash collisions are inevitable when mapping many inputs to fewer outputs. Track used values and implement linear probing or suffix appending to handle collisions and exhaustion.
27. **Parse all selectors when interacting with kernel interfaces** - When parsing structured output from kernel interfaces (netlink, xfrm, iproute2), parse ALL attributes that could be selectors, not just the required ones. Optional attributes become required selectors when present. Missing selectors cause operations to fail with "No such process" errors even when the object exists. Include all parsed selectors in operations (get, delete, modify) to ensure successful matching.
28. **Avoid over-engineering edge case protections and theoretical fallbacks** - Don't add safeguards or core-module fallbacks for edge cases that are extremely unlikely, would be caught by testing, are protected by existing safeguards, or add complexity without significant benefit (includes removal of `lib/fallbacks.sh`)
29. **Log messages must accurately reflect the operation performed** - Use different terminology for different code paths when behavior differs, include context in messages, match terminology to actual behavior not function name
30. **Include all identifying attributes in deduplication keys** - When deduplicating structured data (e.g., Security Associations), use composite keys that include all identifying attributes, not just a subset. Multiple objects can share some attributes (e.g., same src/dst IPs) but differ in others (e.g., SPI values). Deduplication based on partial keys will incorrectly treat unique objects as duplicates. Example: SA deduplication must use src+dst+SPI, not just src+dst, because multiple SAs can exist for the same peer IP with different SPI values during rekey transitions or mixed configurations.

31. **Test helpers must be module-aware when decomposing large files** - When decomposing large files into modules, test helpers that search for function definitions need to be updated to search module files, not just the main aggregate entry file. The `source_function()` helper must check module files first, then fall back to the main file. This pattern ensures tests continue to work after decomposition. Example: When `lib/state.sh` was decomposed into `lib/state/*.sh` modules, `source_function()` in `test_helper.bash` needed updates to search module files for function definitions. Same pattern applies to `lib/config.sh` (decomposed into `lib/config/*.sh` modules) and `lib/detection.sh` (decomposed into `lib/detection/*.sh` modules).

32. **Centralize test data to improve maintainability** - Extract embedded test data (mock outputs, expected values, configuration templates) from test files into a centralized `tests/data/` directory structure. Create generator functions for parameterized data patterns. This centralizes maintenance (changes in one place), ensures consistency (all tests use same format), improves discoverability (easier to find and reuse), and serves as documentation of test data patterns. Use structured bash format (functions and variables) for consistency with the codebase. Example: Created `tests/data/` with `mock_outputs/`, `configs/`, and `expected_values/` subdirectories, with generator functions in `helpers/test_data.bash` for xfrm state, ipsec status, and config templates.

33. **Avoid variable shadowing with global arrays** - When a global array exists (like `LOCATIONS`), don't create a local variable with the same name using `declare -A` inside functions. This creates a local shadow that hides the global, causing confusion and potential bugs. Instead, check if the global exists first using `declare -p`, and only populate it if needed. This pattern is more efficient (reuses existing data), avoids shadowing, and is consistent across the codebase. Example: Changed `declare -A LOCATIONS; if parse_location_config; then` to `if ! declare -p LOCATIONS &>/dev/null 2>&1; then parse_location_config 2>/dev/null || true; fi; if [[ ${#LOCATIONS[@]} -gt 0 ]]; then` in `ipsec_recovery.sh` and `recovery_verification.sh` to match the pattern in `xfrm_recovery.sh`.

34. **Path resolution in sourced bash scripts** - When writing helper modules that are sourced (not executed), be careful with path resolution. `BATS_TEST_DIRNAME` is relative to the test file, not the helper file. Use `${BASH_SOURCE[0]}` to get the helper's directory: `helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`. Also, `local` cannot be used at the top level of a sourced script (only inside functions) - use regular variables with a naming convention like `_helper_dir` to avoid namespace pollution. Example: Fixed `tests/helpers/test_data.bash` to use `_helper_dir` instead of `local helper_dir` at the top level, and to use `${BASH_SOURCE[0]}` instead of `BATS_TEST_DIRNAME` for path resolution.

35. **Error handling functions should be defensive with invalid input** - When error handling functions receive invalid input (e.g., invalid severity levels, non-numeric exit codes), they should be conservative and not cause unexpected script termination. Invalid input should not trigger exits unless an exit code was explicitly provided. This prevents accidental exits when typos or incorrect parameters are passed. Example: `handle_error()` now defaults invalid severity to ERROR but sets exit_code to 0 (no exit) unless an exit code was explicitly provided. Similarly, non-numeric last arguments are treated as part of the message with exit_code set to 0 to prevent accidental exits.

36. **Extract core test infrastructure into reusable standard functions** - When standardizing test setup/teardown patterns, extract core logic into `standard_setup()` and `standard_teardown()` functions that can be called from custom implementations. Keep default `setup()` and `teardown()` calling the standard functions to maintain backward compatibility. This pattern allows tests with custom setup/teardown to extend standard functions while ensuring consistent test isolation. Benefits: reduces duplication, ensures consistency, maintains backward compatibility, and provides clear extension points. Example: Extracted `standard_setup()` and `standard_teardown()` from `setup()` and `teardown()` in `test_helper.bash`, allowing `test_vpn_keepalive.sh` to extend standard teardown with keepalive-specific cleanup.

37. **Process cleanup in parallel test execution requires defensive programming** - When running tests in parallel with coverage tools (e.g., kcov), orphan processes can accumulate if cleanup is not handled properly. The `timeout` command with `--kill-after` helps, but additional defensive cleanup is needed. Use process group cleanup (`kill -TERM -pgid` followed by `kill -KILL -pgid`) to ensure all child processes are terminated. Add cleanup traps in parallel runner functions and explicit cleanup calls after timeout execution. This prevents resource leaks and ensures CI stability. Example: Added `cleanup_test_processes()` function that kills process groups, integrated into `run_single_test_with_timeout()` and `parallel_test_runner_with_coverage()` with cleanup traps to handle interruptions and timeouts.

38. **Signal handlers can be triggered by cleanup code, not just user interrupts** - When cleanup functions send signals (e.g., `kill -TERM`), those signals can trigger signal handlers (traps) that were set up to handle user interrupts. This causes false "interrupted" messages even when no user interruption occurred. **Always temporarily disable signal traps before calling cleanup functions that send signals**, then re-enable them immediately after. Only call cleanup functions when actually needed (e.g., on timeout), not after every operation. Example: Fixed `run_single_test_with_timeout()` to only call `cleanup_test_processes()` on timeout (exit codes 124 or 143), and to temporarily disable TERM/INT traps before cleanup to prevent false "Interrupted by user (Ctrl+C)" messages.

39. **`local` keyword cannot be used at top level of `bash -c` subshells** - The `local` keyword in bash can only be used inside functions, not at the top level of scripts or subshells. When using `bash -c "..."` to run code in a subshell (e.g., for test isolation or capturing output variables via `printf -v`), **never use `local` for variable declarations**. Use regular variable assignments instead. This bug manifests as variables appearing empty even after assignment, causing silent failures. Example: Fixed test in `test_detection_xfrm_edge_cases.sh` where `local func_exit=$?` and `local exit_code=$func_exit` in a `bash -c` subshell left variables empty, preventing exit code capture. Changed to `func_exit=$?` and `exit_code=$func_exit` (without `local`).

40. **Awk has no built-in ceil(); `-int(-x)` is wrong** - In awk, `int()` truncates toward zero (e.g. `int(-0.6)` is 0), so the common C-style ceiling trick `-int(-x)` gives 0 for `x=0.6` instead of 1. For ceiling of a positive value use: `(v==int(v)) ? int(v) : int(v)+1`. Example: Ping threshold in `lib/detection/ping_detection.sh` was changed from `int(x + 0.999)` to this explicit ceiling to avoid a magic constant and to be correct in awk.

41. **Pipeline exit code is the last command's** - In a pipeline `cmd1 | cmd2`, the pipeline's exit code is `cmd2`'s. If you need to act on `cmd1`'s success/failure (e.g. avoid masking `cmd1` failure when `cmd2` succeeds), run `cmd1` first, capture its output and exit code, then run `cmd2` on the captured output only when `cmd1` succeeded. Use `|| true` on `cmd2` when its non-zero exit (e.g. grep no match) is expected and the script uses `set -e`. Example: `lib/recovery/xfrm_recovery.sh` pre-delete diagnostic now runs `ip xfrm state` then greps its output so ip failures are not masked.

42. **Path resolution breaks when moving scripts to subdirectories** - When a script uses `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)` to find the repo root, moving the script one level deeper (e.g. from `scripts/` to `manage/`) changes the result: `dirname/..` becomes the parent of the script's directory, not the repo root. **After moving scripts, audit all path resolution**: update `REPO_ROOT` to go up the correct number of levels (`../..` for scripts in `manage/`), and replace any `dirname/..` patterns with `${REPO_ROOT}` or equivalent. Prefer using a single `REPO_ROOT` variable set at script start over repeating `dirname/..` in multiple places. Example: `manage/deploy-to-udm.sh` had `resolve_bind_ip_from_config()` using `$(dirname "${BASH_SOURCE[0]}")/..` which pointed to `scripts/` instead of repo root after the move; fixed to use `${REPO_ROOT}/vpn-monitor.conf`.

43. **When removing a script, remove or skip its tests and update all doc references** - If a script is deleted (e.g. `scripts/migrate-config-to-locations.sh`), its test file (e.g. `tests/test_migration.sh`) will fail with "Command not found" (exit 127), and any docs that tell users to run that script become broken. **Remove or skip the dedicated test file** so the suite does not run tests against a non-existent script. **Audit and update or remove references** in install.sh, config templates, README, QUICK_START, TROUBLESHOOTING, deployment checklists, ADRs, and test docs (RELEVANT_TESTS.md, BATS_GUIDE.md, tests/README.md). Leave CHANGELOG/ADR historical mentions as-is; user-facing "how to" text should not point at the missing script. Example: C4 fix removed migrate-config references from install.sh and vpn-monitor.conf; test_migration.sh was removed and test docs updated; remaining user-facing doc references are in FUTURE.md.

44. **Isolate mutable process state in tests with save + restore + EXIT trap** - When tests modify global process state (e.g. PATH for mock commands), that state can leak to later tests if an assertion fails before explicit cleanup runs. **Save the original value in setup** (e.g. `ORIGINAL_PATH="${PATH}"`), **restore it in teardown** so normal runs are isolated, and **also register an EXIT trap** in setup that restores the value so cleanup runs even when the test fails or teardown is overridden. Make add/remove helpers idempotent (e.g. don't duplicate PATH entries on double-call) and have remove restore from the saved value when available so cleanup is complete. Example: C5 fix in `test_helper.bash`—`standard_setup()` saves `ORIGINAL_PATH` and sets `trap '... export PATH="$ORIGINAL_PATH"' EXIT`; `remove_mock_from_path()` restores from `ORIGINAL_PATH` when set; `add_mock_to_path()` only prepends if `TEST_DIR` is not already at the front of PATH.

45. **Use arithmetic context for numeric comparison when value may be non-numeric** - When comparing a value from command substitution (e.g. `calculate_duration` output) with `[[ -gt ]]`, non-numeric output causes the comparison to fail silently (bash does not enter the then-branch). Prefer `(( value > limit ))`: in arithmetic context, non-numeric values are treated as 0, so behavior is deterministic (e.g. "not stale" when age is invalid). Example: `lib/lockfile.sh` `check_lockfile_stale()` changed from `[[ "$lockfile_age" -gt "$LOCKFILE_TIMEOUT" ]]` to `((lockfile_age > LOCKFILE_TIMEOUT))`.

46. **`sshpass` + `ssh -f` = hang; use `true` + `ControlPersist` instead** - `sshpass` creates a pseudo-terminal (pty) and waits for EOF. `ssh -f` forks to background but the child keeps the pty slave fd open, so sshpass blocks forever. The fix is `ssh ... true` with `ControlPersist=60`: ssh runs `true`, exits, sshpass sees EOF cleanly, and ControlPersist keeps the socket alive via OpenSSH-managed background process. Additionally: (a) `set -e` kills the script if auth fails — use `|| auth_rc=$?` to capture the exit code, (b) EXIT traps need `set +e` at the start to prevent mid-cleanup abort, (c) `mktemp -d` + `chmod 700` prevents symlink attacks on socket paths, (d) clean up temp dir explicitly in failure path before setting `CONTROL_SOCKET=""` — the EXIT trap won't do it if the variable is empty. Example: `manage/deploy-to-udm.sh` `setup_control_master()` — see `CODE_PATTERNS.md` "SSH Connection Management Patterns" for the consolidated pattern.

47. **Do not swallow sourcing failures in test helpers** - When a test helper sources production modules (e.g. `source_function()` sourcing `lib/constants.sh`, `lib/common.sh`, etc.), do **not** use `2>/dev/null || true` or `|| true` on the `source` command. Swallowing the exit code causes tests that fail to load the function under test to pass vacuously (the function was never defined, so assertions never run or run on stale definitions). Let sourcing failures propagate so the test fails with a clear error. Example: Removed `|| true` from all `source "${LIB_DIR}/...` calls inside `source_function()` in `tests/test_helper.bash` so that module load failures surface as test failures.

48. **Do not strip `#` from config RHS before quote-aware parsing** - Using `${assignment%%#*}` (or any “remove longest `#…` suffix” on the raw text after `=`) runs **before** quoted values are interpreted, so a valid line like `VAR="vpn#1.example.com"` is truncated to `"vpn` and fails as an unclosed quote; unquoted `VAR=host#1` could become `host` without error. **Handle comments inside `parse_quoted_value`**: for quoted strings, allow only whitespace and `#…` after the closing quote; for unquoted tokens, allow an optional trailing comment only as `token` + whitespace + `#` + rest (a `#` inside the token requires quoting). Example: `lib/config/config_loading.sh` `parse_assignment` passes the full RHS to `parse_quoted_value`; comment rules live there.

49. **`set -e` + `[[ ]] &&` inside sourced library functions** - Library modules sourced by `set -euo pipefail` scripts must not use `[[ condition ]] && command` when `condition` is often false (e.g. optional color init when `common.sh` already set `RED`, or `manage_log_verbose` when verbose is off). A failed `[[` as the last command in a function returns non-zero and can abort the caller. Use `if [[ condition ]]; then command; fi` instead. Same applies to `manage_init_terminal_colors()` — discovered when consolidating SSH helpers into `manage/lib/ssh_control.sh`. Related: entry scripts such as `check-config.sh` must **not** re-assign `RED`/`GREEN`/`YELLOW`/`BLUE`/`NC` after sourcing libs that pull in `common.sh` (those are `readonly`); re-assignment aborts under `set -e` even though a review may look like “colors are missing.”
50. **Interactive fleet defaults defeat automation** - Batch deploy that defaults to interactive `tail -f` plus a y/n registry prompt will hang acceptance/CI and can leave the deploy registry empty (false drift later). Prefer non-interactive batch defaults (`SKIP_TAIL=1`, auto-record) with an explicit opt-in for babysitting (`--tail-follow`). Keep a one-shot `tail -n N` snapshot after install so operators still see recent log lines without blocking the fleet loop. Example: `deploy-to-udms.sh` (2026-07-19).

51. **Document install path vs fleet-deploy path separately for state** - “Upgrade preserves X” is ambiguous when operators have both on-box `install.sh` (state often kept) and fleet `deploy-to-udms.sh` (uninstall with `--remove-state` by default). Say which path you mean. Fleet deploy that wipes `operating_mode` then reinstalls will re-apply the **install default** (now `observe-only`), which is correct for stage-1 but surprises operators who expected preserve-mode language. Example: prove-control-plane CHANGELOG / acceptance docs (2026-07-19).

52. **Shared stop helpers before destructive uninstall** - Long-running helpers (monitor wrapper) can keep executing after cron is removed if uninstall only deletes files. Stop processes that hold PID/lock files under `STATE_DIR` **before** removing the install tree; share the helper between the control CLI and uninstall so behavior does not drift. Example: `lib/control/wrapper_control.sh` + `uninstall.sh` (2026-07-19).

53. **Package/install must ship sibling libs with CLI scripts** - Relocating or listing entry scripts (e.g. `manage/deploy-to-udm.sh`) without their sourced helpers (`manage/lib/ssh_control.sh`) produces a zip that looks complete but fails at runtime when sourced. Treat controller helpers as a module directory in `prepare_install_package.sh` (`MODULE_DIRS`) and copy them in `install.sh` alongside the CLIs. Example: promote-manage-to-top-level review (2026-07-19).


