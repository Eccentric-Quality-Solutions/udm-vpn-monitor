# ADR-0015: File-Based State Storage

## Status
Accepted

## Context
The monitoring system needs to persist state across script executions:
- Failure counters for each peer
- Byte counter values for traffic flow detection
- Cooldown periods and rate limiting timestamps
- Restart history

Alternative storage mechanisms could include:
- Database (SQLite, PostgreSQL, etc.)
- In-memory storage (lost on restart)
- System key-value stores
- Configuration management systems

## Decision
We will use file-based state storage with plain text files in `/data/vpn-monitor/state/` directory.

## Consequences

### Positive
- **Simplicity**: No database dependencies or setup required
- **Portability**: Files can be easily backed up, moved, or inspected
- **UDM Compatibility**: Works on UDM systems without additional software
- **Human Readable**: State files can be inspected and debugged manually
- **Persistence**: Files in `/data/` survive reboots on UDM systems
- **Atomic Operations**: File operations can be made atomic (write-tmp-move pattern)
- **Low Overhead**: Minimal resource usage, no database process

### Negative
- **No Transactions**: Cannot roll back multiple file operations atomically
- **Manual Parsing**: Requires parsing logic for reading/writing state
- **File System Dependency**: Relies on file system being available and writable
- **No Query Capabilities**: Cannot easily query or aggregate data across files
- **Corruption Risk**: Files can be corrupted (mitigated by format validation)

## Implementation Details
- **State File Types**:
  - Per-location, per-peer failure counters: `state/failure_count_<location>_<peer_ip>`
  - Per-location, per-peer byte counters: `state/last_bytes_<location>_<peer_ip>`
  - Per-location, per-peer SPI values: `state/spi_<location>_<peer_ip>`
  - Per-location, per-peer idle detection: `state/idle_detected_<location>_<peer_ip>`
  - Per-location, per-peer failure type: `state/failure_type_<location>_<peer_ip>`
  - Per-location, per-peer last status log: `state/last_status_log_<location>_<peer_ip>`
  - Restart timestamps: `state/restart_count` (Unix timestamps of Tier 3 recovery actions only: full IPsec restarts and successful xfrm-based per-connection recovery)
  - Cooldown expiration: `cooldown_until`
- **File Format**: Plain text with simple value storage
- **Atomic Operations**: Write-tmp-move pattern ensures atomic updates
- **Format Validation**: Files are validated for correct format (integer, timestamp, etc.) to detect corruption
- **Location**: `/data/vpn-monitor/state/` (persists across UDM reboots)
- **Module**: Implemented in `lib/state.sh` with dedicated functions for each state file type

## Related ADRs
- ADR-0004: Per-Peer State Tracking
- ADR-0012: Atomic File Operations
- ADR-0013: State File Checksum Validation (Deprecated - removed in v0.2.0, replaced with format validation)
- ADR-0016: State File Location (/data/vpn-monitor/)
- ADR-0024: Location-Based Configuration Format (location names included in state file names)

## References
- ARCHITECTURE.md: "File Structure" section
- ARCHITECTURE.md: "State Management" section
- README.md: "State Management" section
- lib/state.sh: Implementation details

