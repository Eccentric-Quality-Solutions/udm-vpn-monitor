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
  - `lib/config.sh` - Configuration loading and validation
  - `lib/config_schema.sh` - Configuration schema definitions and validation rules
  - `lib/constants.sh` - Named constants for magic numbers
  - `lib/detection.sh` - VPN status detection (xfrm, ipsec, ping)
  - `lib/lockfile.sh` - Lockfile management (flock/atomic)
  - `lib/logging.sh` - Centralized logging functionality
  - `lib/recovery.sh` - Tiered recovery actions
  - `lib/state.sh` - State file management (counters, cooldown, rate limiting)
- **Module Loading**: Modules are sourced at script startup
- **Function Documentation**: All functions include comprehensive documentation blocks
- **Dependency Management**: Clear documentation of module dependencies

## Related ADRs
- ADR-0007: Comprehensive In-Code Documentation

## References
- ARCHITECTURE.md: "Key Design Decisions #6: Modular Library Architecture"
- ARCHITECTURE.md: "Modular Library Architecture" section
- CHANGELOG.md: "Modular Library Architecture" entry

