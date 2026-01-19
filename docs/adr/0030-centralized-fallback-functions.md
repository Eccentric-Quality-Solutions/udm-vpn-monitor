# ADR-0030: Centralized Fallback Functions

## Status
Deprecated

**Note:** This ADR was superseded by a pragmatic engineering decision to remove the centralized fallback system. The fallback system was removed on 2026-01-18 because it addressed theoretical edge cases that are extremely unlikely in production. Modules now fail fast if dependencies can't be sourced, which is a better approach than silent degradation with minimal functionality.

**See:** `docs/reviews/fallback-system-removal-review.md` for details on the removal decision.

## Context
As the codebase evolved into a modular architecture (ADR-0005), modules became independently sourceable for testing and installation scenarios. However, when modules are sourced independently, their dependencies may not be available, leading to failures.

**Original Problem:**
- Modules needed fallback implementations when dependencies couldn't be loaded
- Each module was defining its own fallback functions inline, leading to:
  - **Code Duplication**: Same fallback functions defined in multiple files (~200+ lines of duplicate code)
  - **Inconsistent Behavior**: Different modules had slightly different fallback implementations
  - **Maintenance Burden**: Changes to fallback logic required updates in multiple places
  - **Testing Complexity**: Fallback behavior varied across modules, making testing difficult

**Example of Duplication:**
```bash
# In lib/config.sh
source "${LIB_DIR}/config_schema.sh" 2>/dev/null || {
    get_config_schema() { return 1; }
    is_config_required() { return 1; }
    get_config_default() { echo ""; }
}

# In lib/detection.sh (duplicate definitions)
source "${LIB_DIR}/config_schema.sh" 2>/dev/null || {
    get_config_schema() { return 1; }
    is_config_required() { return 1; }
    get_config_default() { echo ""; }
}
```

**Alternative Approaches Considered:**
1. **Inline fallback definitions** (original approach) - Simple but leads to duplication and inconsistency
2. **Separate fallback files per module** - Better organization but still duplicates common fallbacks
3. **Centralized fallback module** (chosen) - Single source of truth, consistent behavior, easier maintenance

## Decision
We will create a centralized `lib/fallbacks.sh` module that provides standardized fallback function definitions. Modules that need fallback functions will source `lib/fallbacks.sh` and call appropriate fallback definition functions when dependencies cannot be loaded.

**Pattern:**
- `lib/fallbacks.sh` defines fallback function generators (e.g., `define_schema_fallbacks()`, `define_logging_fallbacks()`)
- Modules source `lib/fallbacks.sh` and call the appropriate definition function when dependencies fail to load
- Fallback functions are intentionally minimal - they provide basic functionality when modules are unavailable
- Modules check file existence and readability before sourcing fallbacks to handle edge cases gracefully

## Consequences

### Positive
- **Single Source of Truth**: All fallback implementations in one file (`lib/fallbacks.sh`)
- **Consistency**: Same fallback behavior across all modules using the same fallback type
- **Maintainability**: Update fallback logic in one place, affects all modules
- **DRY Principle**: Eliminates ~200+ lines of duplicate fallback code
- **Standardization**: Clear pattern for when and how to use fallbacks
- **Graceful Degradation**: Modules can function independently when dependencies are unavailable
- **Testing**: Consistent fallback behavior makes testing more predictable

### Negative
- **Additional Dependency**: Modules must source `lib/fallbacks.sh` to use fallbacks
- **Centralization Risk**: Changes to fallbacks.sh affect all modules (mitigated by careful versioning and testing)
- **Fallback Complexity**: Must handle cases where `fallbacks.sh` itself fails to source (defensive checks)

## Implementation Details

### Fallback Function Categories

**Schema Fallbacks** (`define_schema_fallbacks()`):
- `get_config_schema()` - Returns failure (schema not available)
- `is_config_required()` - Returns failure (schema not available)
- `get_config_default()` - Returns empty string

**Logging Fallbacks** (`define_logging_fallbacks()`):
- `log_message()` - Outputs formatted message to stderr with timestamp
- `handle_error()` - Logs error and optionally exits script

**Common Utility Fallbacks** (`define_common_fallbacks()`):
- `ensure_file_exists()` - Creates file if it doesn't exist
- `try_ensure_directory_exists()` - Creates directory if it doesn't exist
- `safe_source_lib()` - Attempts to source library file
- `get_unix_timestamp()` - Returns Unix timestamp
- `check_command_available()` - Checks if command exists in PATH
- `atomic_write_file()` - Writes file atomically

**Logging Timestamp Fallback** (`define_logging_timestamp_fallback()`):
- `get_formatted_timestamp()` - Returns formatted timestamp string

### Usage Pattern

**Standard Usage:**
```bash
source "${LIB_DIR}/common.sh" 2>/dev/null || {
    # Fallback if common.sh not found - use centralized fallbacks
    if [[ -n "${LIB_DIR:-}" ]] && [[ -f "${LIB_DIR}/fallbacks.sh" ]] && [[ -r "${LIB_DIR}/fallbacks.sh" ]]; then
        source "${LIB_DIR}/fallbacks.sh" 2>/dev/null && define_common_fallbacks
    fi
}
```

**Defensive Check (Critical Paths):**
For critical paths where `fallbacks.sh` itself might fail to source:
```bash
# Source fallbacks.sh first (may fail silently)
if [[ -n "${LIB_DIR:-}" ]] && [[ -f "${LIB_DIR}/fallbacks.sh" ]] && [[ -r "${LIB_DIR}/fallbacks.sh" ]]; then
    source "${LIB_DIR}/fallbacks.sh" 2>/dev/null || true
fi

# Later, when module fails to source, check function exists before calling
if ! source "${LIB_DIR}/config_schema.sh" 2>/dev/null; then
    if declare -f define_schema_fallbacks >/dev/null 2>&1; then
        define_schema_fallbacks
    fi
fi
```

### Key Implementation Principles

1. **File Existence Checks**: Always check file existence and readability before sourcing: `[[ -f "${LIB_DIR}/fallbacks.sh" ]] && [[ -r "${LIB_DIR}/fallbacks.sh" ]]`
2. **Conditional Function Definition**: Use `&&` operator to only call define function if sourcing succeeds: `source ... && define_*_fallbacks`
3. **Defensive Programming**: For critical paths, check function existence before calling: `declare -f define_*_fallbacks >/dev/null 2>&1`
4. **Minimal Functionality**: Fallback functions are intentionally minimal - they provide basic functionality when modules are unavailable
5. **Graceful Failure**: Handle `fallbacks.sh` failure gracefully - it may fail to source, so check function existence before calling

## Related ADRs
- ADR-0005: Modular Library Architecture (enables independent module sourcing)
- ADR-0007: Comprehensive In-Code Documentation (fallback functions are fully documented)

## References
- `lib/fallbacks.sh` - Centralized fallback function definitions
- `docs/CODE_PATTERNS.md` - "Pattern: Centralized Fallback Functions" section
- `docs/ARCHITECTURE.md` - "lib/fallbacks.sh" module documentation
- CHANGELOG.md v0.6.0 - "Added lib/fallbacks.sh module" entry
