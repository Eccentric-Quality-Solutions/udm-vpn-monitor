# Architecture Decision Records (ADRs)

This directory contains Architecture Decision Records (ADRs) documenting significant design decisions made during the development of the UDM VPN Monitor project.

## What are ADRs?

Architecture Decision Records are documents that capture important architectural decisions made in a project, including:
- The context and problem that led to the decision
- The decision itself
- The consequences (positive and negative) of the decision
- Related decisions and references

## ADR Index

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-0001](0001-cron-based-execution.md) | Cron-Based Execution Instead of Daemon | Accepted |
| [ADR-0002](0002-lockfile-protection-mechanism.md) | Lockfile Protection Mechanism | Accepted |
| [ADR-0003](0003-tiered-recovery-system.md) | Tiered Recovery System | Accepted |
| [ADR-0004](0004-per-peer-state-tracking.md) | Per-Peer State Tracking | Accepted |
| [ADR-0005](0005-modular-library-architecture.md) | Modular Library Architecture | Accepted |
| [ADR-0006](0006-multi-method-detection-with-fallback.md) | Multi-Method Detection with Fallback | Accepted |
| [ADR-0007](0007-comprehensive-in-code-documentation.md) | Comprehensive In-Code Documentation | Accepted |
| [ADR-0008](0008-rate-limiting-and-cooldown-periods.md) | Rate Limiting and Cooldown Periods | Accepted |
| [ADR-0009](0009-vpn-keepalive-daemon.md) | VPN Keepalive Daemon (Optional) | Accepted |
| [ADR-0010](0010-configuration-schema-validation.md) | Configuration Schema Validation | Accepted |
| [ADR-0011](0011-security-measures-ip-validation-fixed-string-matching.md) | Security Measures (IP Validation, Fixed-String Matching) | Accepted |
| [ADR-0012](0012-atomic-file-operations.md) | Atomic File Operations | Accepted |
| [ADR-0013](0013-state-file-checksum-validation.md) | State File Checksum Validation | Deprecated (Removed in v0.2.0) |
| [ADR-0014](0014-ping-check-as-supplementary-diagnostic.md) | Ping Check as Supplementary Diagnostic Tool | Accepted |
| [ADR-0015](0015-file-based-state-storage.md) | File-Based State Storage | Accepted |
| [ADR-0016](0016-state-file-location-data-vpn-monitor.md) | State File Location (/data/vpn-monitor/) | Accepted |
| [ADR-0017](0017-bash-scripting-language.md) | Bash Scripting Language | Accepted |
| [ADR-0018](0018-centralized-logging-module.md) | Centralized Logging Module | Accepted |
| [ADR-0019](0019-byte-counter-detection-method.md) | Byte Counter Detection Method | Accepted |
| [ADR-0020](0020-sa-rekey-detection-and-handling.md) | SA Rekey Detection and Handling | Accepted |
| [ADR-0021](0021-bats-testing-framework.md) | BATS Testing Framework | Accepted |
| [ADR-0022](0022-phase-1-detection-deferred.md) | Phase 1 Detection Deferred | Accepted |
| [ADR-0023](0023-resource-monitoring-and-throttling.md) | Resource Monitoring and Throttling | Accepted |
| [ADR-0024](0024-location-based-configuration.md) | Location-Based Configuration Format | Accepted |
| [ADR-0025](0025-network-partition-detection.md) | Network Partition Detection | Accepted |
| [ADR-0026](0026-detection-reliability-safeguard.md) | Detection Reliability Safeguard | Accepted |
| [ADR-0027](0027-enhanced-command-availability-checking.md) | Enhanced Command Availability Checking | Accepted |
| [ADR-0028](0028-state-passing-pattern-for-detection-functions.md) | State Passing Pattern for Detection Functions | Accepted |

## ADR Format

Each ADR follows this structure:
- **Status**: Current status of the decision (Proposed/Accepted/Deprecated/Superseded)
- **Context**: The situation and problem that led to the decision
- **Decision**: The decision that was made
- **Consequences**: Positive and negative consequences of the decision
- **Implementation Details**: How the decision was implemented
- **Related ADRs**: Links to related decisions
- **References**: Links to relevant documentation and code

## Adding New ADRs

When making a significant architectural decision:

1. Create a new ADR file following the naming convention: `NNNN-title-in-kebab-case.md`
2. Use the next sequential number
3. Follow the standard ADR format
4. Update this README with the new ADR entry
5. Link related ADRs in the "Related ADRs" section

## Status Values

- **Proposed**: Decision is under consideration
- **Accepted**: Decision has been made and implemented
- **Deprecated**: Decision has been superseded or is no longer relevant
- **Superseded**: Decision has been replaced by a newer ADR

## References

- [Architecture Documentation](../ARCHITECTURE.md) - Detailed architecture documentation
- [Architectural Review](../ARCHITECTURAL_REVIEW.md) - Comprehensive architectural review
- [Changelog](../CHANGELOG.md) - Project changelog with implementation history

