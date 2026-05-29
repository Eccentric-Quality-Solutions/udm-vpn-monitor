# ADR-0017: Bash Scripting Language

## Status
Accepted

## Context
The monitoring system needs to run on UniFi Dream Machine (UDM) systems, which have specific constraints:
- Limited software availability (no Python, Node.js, etc. by default)
- Bash is universally available on UDM systems
- System commands (`ip`, `ipsec`, `ping`) are accessible from shell scripts
- Cron jobs can easily execute shell scripts
- UDM OS is based on Debian/Ubuntu, ensuring bash availability

Alternative languages could include:
- Python (not available by default, requires installation)
- Perl (may not be available)
- Go (requires compilation and binary distribution)
- Node.js (not available by default)

## Decision
We will implement the monitoring system using Bash shell scripting.

## Consequences

### Positive
- **Universal Availability**: Bash is available on all UDM systems without installation
- **System Integration**: Easy integration with system commands (`ip`, `ipsec`, `ping`)
- **Cron Compatibility**: Cron jobs naturally execute shell scripts
- **No Dependencies**: No external runtime or interpreter installation required
- **Familiar to Sysadmins**: Shell scripts are familiar to system administrators
- **Lightweight**: Minimal resource usage, no runtime overhead

### Negative
- **Limited Language Features**: Bash lacks advanced data structures and libraries
- **Error Handling**: More complex error handling compared to modern languages
- **Testing Complexity**: Requires specialized testing frameworks (bats)
- **Code Organization**: Less structured than object-oriented languages
- **String Handling**: More complex string manipulation compared to modern languages
- **Maintainability**: Can become complex for large codebases (mitigated by modular architecture)

## Implementation Details
- **Shebang**: `#!/bin/bash` for all scripts
- **Bash Version**: Compatible with bash 4.0+ (standard on UDM systems)
- **Modular Architecture**: Organized into library modules to manage complexity
- **Error Handling**: Uses `set -euo pipefail` for strict error handling
- **Testing**: Uses bats (Bash Automated Testing System) for testing
- **Code Quality**: ShellCheck and shfmt for linting and formatting

### UDM platform constraints (short)

Bash is chosen partly because common alternatives and utilities are **not available on UDM OS** without fragile post-upgrade package installs. In practice:

- **No** Python, Node.js, jq, Perl, or Ruby — use shell plus awk/sed/grep for text processing
- **`bc` not packaged** — use `awk` for numeric calculations
- **`zip` not on UDM** — on-device install packages use **tar.gz**; zip is optional for dev-only workflows

See [UDM-Linux-Tools.md](../../UDM-Linux-Tools.md) for the canonical tool list.

## Related ADRs
- ADR-0005: Modular Library Architecture
- ADR-0001: Cron-Based Execution Instead of Daemon

## References
- README.md: "Requirements" section
- DEVELOPER.md: "Development Tooling" section
- [UDM-Linux-Tools.md](../../UDM-Linux-Tools.md): Available and unavailable tools on UDM OS
- All source files: Bash implementation

