# ADR-0016: State File Location (/data/vpn-monitor/)

## Status
Accepted

## Context
On UniFi Dream Machine systems, different directories have different persistence characteristics:
- `/tmp/` - Temporary, cleared on reboot
- `/root/` - May be cleared during OS upgrades
- `/data/` - Persists across reboots and OS upgrades
- `/mnt/` - Mount points, may not be persistent
- `/config/` - Configuration directory, may be cleared

State files need to:
- Persist across system reboots
- Survive UniFi OS upgrades (when possible)
- Be accessible to the monitoring script
- Not interfere with system operations

## Decision
We will store all state files, logs, and configuration in `/data/vpn-monitor/` directory, with state files in a dedicated `state/` subdirectory.

## Consequences

### Positive
- **Persistence**: Files in `/data/` survive reboots
- **Upgrade Resilience**: More likely to survive UniFi OS upgrades than other locations
- **Centralized Location**: All project files in one directory
- **Easy Backup**: Single directory to backup for complete state preservation
- **Isolation**: Doesn't interfere with system directories
- **UDM Standard**: `/data/` is the standard location for persistent user data on UDM

### Negative
- **Upgrade Risk**: May still be cleared during major OS upgrades (documented limitation)
- **Directory Dependency**: Requires `/data/` directory to be writable
- **Manual Cleanup**: Users must manually remove directory for complete uninstallation

## Implementation Details
- **Installation Location**: `/data/vpn-monitor/`
- **Directory Structure**:
  - Scripts: `/data/vpn-monitor/vpn-monitor.sh`
  - Configuration: `/data/vpn-monitor/vpn-monitor.conf`
  - Library modules: `/data/vpn-monitor/lib/`
  - Logs: `/data/vpn-monitor/logs/`
  - State files: `/data/vpn-monitor/state/` (dedicated state subdirectory)
- **Installation**: Created during `install.sh` execution
- **Uninstallation**: Removed during `uninstall.sh` execution
- **Persistence Note**: Documented that files may need re-installation after major OS upgrades

## Related ADRs
- ADR-0015: File-Based State Storage
- ADR-0004: Per-Peer State Tracking

## References
- ARCHITECTURE.md: "File Structure" section
- READITURE.md: "Persistence & Upgrades" section
- install.sh: Installation script creates directory structure
- uninstall.sh: Uninstallation script removes directory

