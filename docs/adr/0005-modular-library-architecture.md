# ADR-0005: Modular Library Architecture

## Status
Accepted

## Context
The initial implementation had all functionality in a single large script (~1900 lines), which led to:
- Code duplication across installation, uninstallation, and monitoring scripts
- Difficult maintenance and testing
- Poor separation of concerns
- Hard to reuse functionality across scripts
- Difficult to test individual components

## Decision
We will refactor the codebase into a modular library architecture with dedicated modules in the `lib/` directory, each with a single, well-defined responsibility.

## Consequences

### Positive
- **Separation of Concerns**: Each module has a single responsibility
- **Code Reusability**: Shared functions can be used across multiple scripts (install, uninstall, monitor)
- **Maintainability**: Changes to one module don't affect others
- **Testability**: Each module can be tested independently
- **Reduced Complexity**: Main script reduced from ~1900 lines to ~530 lines
- **Better Organization**: Related functionality grouped together
- **Easier Onboarding**: New developers can understand individual modules

### Negative
- **Module Dependencies**: Modules may depend on each other (managed via clear dependency documentation)
- **Initial Refactoring Effort**: Required significant refactoring work
- **File Count**: More files to manage (but better organized)

## Implementation Details
- **Library Modules**:
  - `lib/common.sh` - Shared utilities (logging, validation, helpers)
  - `lib/config.sh` - Configuration loading and validation (compatibility layer)
  - `lib/config/` - Configuration module subdirectory:
    - `lib/config/config_loading.sh` - File parsing and loading
    - `lib/config/config_defaults.sh` - Default value application
    - `lib/config/config_validation.sh` - Schema validation and type checking
    - `lib/config/location_parsing.sh` - Location-based configuration parsing
  - `lib/config_schema.sh` - Configuration schema definitions and validation rules
  - `lib/constants.sh` - Named constants for magic numbers
  - `lib/detection.sh` - VPN status detection (main entry point, compatibility layer)
  - `lib/detection/` - Detection module subdirectory:
    - `lib/detection/network_validation.sh` - IP validation, route checks
    - `lib/detection/xfrm_detection.sh` - xfrm state and byte counter detection
    - `lib/detection/ping_detection.sh` - Ping-based detection
    - `lib/detection/failure_analysis.sh` - Failure type classification
  - `lib/fallbacks.sh` - Centralized fallback function definitions for graceful degradation
  - `lib/lockfile.sh` - Lockfile management (flock/atomic)
  - `lib/logging.sh` - Centralized logging functionality
  - `lib/recovery.sh` - Tiered recovery actions (compatibility layer)
  - `lib/recovery/` - Recovery module subdirectory:
    - `lib/recovery/recovery_orchestration.sh` - Recovery orchestration and coordination
    - `lib/recovery/xfrm_recovery.sh` - xfrm-based recovery operations
    - `lib/recovery/ipsec_recovery.sh` - IPsec recovery operations
    - `lib/recovery/recovery_verification.sh` - Recovery verification functions
    - `lib/recovery/recovery_state.sh` - Recovery state management
    - `lib/recovery/constants.sh` - Recovery-related constants
  - `lib/state.sh` - State file management (compatibility layer)
  - `lib/state/` - State module subdirectory:
    - `lib/state/state_paths.sh` - Path generation and sanitization
    - `lib/state/peer_state.sh` - Per-peer state operations
    - `lib/state/location_state.sh` - Per-location state operations
    - `lib/state/global_state.sh` - Global state operations
    - `lib/state/state_init.sh` - State initialization
- **Module Loading**: Modules are sourced at script startup
- **Function Documentation**: All functions include comprehensive documentation blocks
- **Dependency Management**: Clear documentation of module dependencies
- **Module Dependency Pattern**: When modules are split into subdirectories, each submodule sources its direct dependencies, making modules independently sourceable (useful for testing). The main entry point sources all modules in dependency order.
- **Compatibility Layers**: Large modules that have been split into subdirectories maintain compatibility layers (e.g., `lib/config.sh`, `lib/detection.sh`, `lib/recovery.sh`, `lib/state.sh`) that source all submodules, ensuring backward compatibility with existing code that sources the main module file.

## Related ADRs
- ADR-0007: Comprehensive In-Code Documentation
- ADR-0030: Centralized Fallback Functions (graceful degradation when modules can't be loaded)

## Change History
- **2026-01-11**: Major refactoring in v0.6.0 - All large monolithic modules split into focused subdirectories:
  - `lib/config.sh` (2365 lines) → `lib/config/` subdirectory with 4 modules
  - `lib/detection.sh` (3004 lines) → `lib/detection/` subdirectory with 4 modules
  - `lib/recovery.sh` (2633 lines) → `lib/recovery/` subdirectory with 6 modules
  - `lib/state.sh` (1421 lines) → `lib/state/` subdirectory with 5 modules
  - Added `lib/fallbacks.sh` module for centralized fallback function definitions
  - All main module files maintained as compatibility layers that source submodules
  - This demonstrates the evolution of the modular architecture principle - large modules can be further decomposed when they grow too large

## References
- ARCHITECTURE.md: "Key Design Decisions #6: Modular Library Architecture"
- ARCHITECTURE.md: "Modular Library Architecture" section
- CHANGELOG.md: "Modular Library Architecture" entry
- CODE_REVIEW_detection_split.md: Detection module split implementation details

