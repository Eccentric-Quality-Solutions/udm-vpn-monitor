# ADR-0018: Centralized Logging Module

## Status
Accepted

## Context
The monitoring system needs consistent logging across all modules:
- Timestamp formatting
- Log level management (INFO, WARN, ERROR, DEBUG)
- File and console output
- Consistent log format

Without centralized logging:
- Each module would implement its own logging logic
- Inconsistent timestamp formats
- Duplicated logging code
- Difficult to change logging behavior globally
- No centralized log level control

## Decision
We will implement a centralized logging module (`lib/logging.sh`) that provides:
- Single logging function (`log_message()`) used by all modules
- Consistent timestamp formatting
- Log level support (INFO, WARN, ERROR, DEBUG)
- File and console output support
- Centralized log level filtering

## Consequences

### Positive
- **Consistency**: All logs use the same format and timestamp style
- **Maintainability**: Logging behavior changed in one place
- **Code Reuse**: No duplicated logging code across modules
- **Centralized Control**: Log level filtering controlled in one location
- **Easier Debugging**: Consistent format makes log analysis easier
- **Future Enhancements**: Easy to add features (log rotation, remote logging, etc.)

### Negative
- **Module Dependency**: All modules depend on logging module
- **Initial Setup**: Requires logging module to be sourced before use

## Implementation Details
- **Module**: `lib/logging.sh`
- **Main Function**: `log_message(level, message)` - Logs message with level and timestamp
- **Timestamp Format**: Consistent formatting via `get_formatted_timestamp()`
- **Log Levels**: INFO, WARN, ERROR, DEBUG
- **Output**: Both file and console output support
- **Usage**: All modules source `lib/logging.sh` and use `log_message()` function
- **Dependencies**: Minimal dependencies (uses `date` command for timestamps)

## Related ADRs
- ADR-0005: Modular Library Architecture
- ADR-0007: Comprehensive In-Code Documentation

## References
- ARCHITECTURE.md: "Modular Library Architecture" section
- ARCHITECTURE.md: "lib/logging.sh" module documentation
- lib/logging.sh: Implementation details

