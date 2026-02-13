# ADR-0024: Location-Based Configuration Format

## Status
Accepted

## Context
The original configuration format used `EXTERNAL_PEER_IPS` and `INTERNAL_PEER_IPS` variables with space-separated IP addresses:
- External and internal IPs were matched by position in the arrays
- No semantic grouping of related external/internal IP pairs
- Difficult to manage when dealing with many VPN connections
- No way to identify which VPN connection corresponds to which location
- State files and logs used only IP addresses, making troubleshooting difficult
- No support for multiple internal IPs per location with flexible health determination

As deployments grew more complex:
- Managing many VPN connections became cumbersome
- Logs and state files were hard to correlate with actual locations
- Users wanted better organization and clearer identification
- Need arose for multiple internal IPs per location with threshold-based health determination

## Decision
We will implement a location-based configuration format that:
- Uses `LOCATION_<NAME>_EXTERNAL` and `LOCATION_<NAME>_INTERNAL` variable naming convention
- Groups external and internal IPs under named locations
- Extracts location names from variable names (text between `LOCATION_` and `_EXTERNAL`)
- Includes location names in state file names and logs for better identification
- Supports multiple internal IPs per location with 30% ping threshold for health determination
- Maintains independent failure tracking per location
- Provides migration script to convert from old format to new format

## Consequences

### Positive
- **Better Organization**: Related external and internal IPs grouped under meaningful location names
- **Clearer Identification**: Location names appear in logs and state files, making troubleshooting easier
- **Multiple Internal IPs**: Supports multiple internal IPs per location with flexible health determination (30% threshold)
- **Independent Tracking**: Each location has its own failure counter and state files
- **Easier Management**: Add or remove locations without affecting others
- **Migration Support**: Automated migration script helps users transition from old format
- **Backward Compatibility**: Migration script preserves existing configuration during transition

### Negative
- **Breaking Change**: Old format (`EXTERNAL_PEER_IPS`/`INTERNAL_PEER_IPS`) no longer supported
- **Migration Required**: Existing users must migrate configuration (script provided)
- **State File Migration**: Old state files not automatically migrated (new files created)
- **Configuration Complexity**: More verbose configuration format (more lines per location)
- **Location Name Validation**: Requires validation and sanitization of location names

## Implementation Details

### Configuration Format
- **Variable Naming**: `LOCATION_<NAME>_EXTERNAL` and `LOCATION_<NAME>_INTERNAL`
- **Location Name Extraction**: Extracted from variable name (text between `LOCATION_` and `_EXTERNAL`)
- **Location Name Rules**:
  - Maximum 64 characters
  - Must start with alphanumeric character (not underscore)
  - Invalid characters automatically replaced with underscores
  - Must be unique per configuration

### Multiple Internal IPs Support
- **Single Internal IP**: Requires 100% success (ping must succeed)
- **Multiple Internal IPs**: VPN considered healthy if ≥30% respond to pings (rounded up)
- **Examples**:
  - 3 internal IPs: Need at least 1 successful ping (30% of 3 = 0.9, rounded up = 1)
  - 10 internal IPs: Need at least 3 successful pings (30% of 10 = 3)

### State File Naming
- **Old Format**: `state/failure_count_203_0_113_1`
- **New Format**: `state/failure_count_NYC_203_0_113_1`
- **Format**: `state/<type>_<location>_<sanitized_ip>`
- Location name included in filename for better organization

### Migration
- **Migration Script**: `scripts/migrate-config-to-locations.sh`
- **Modes**: Interactive (prompts for location names) and CSV (bulk import)
- **Automatic Backup**: Creates backup before migration
- **Validation**: Validates configuration after migration

### Configuration Parsing
- **Module**: `lib/config.sh` - `load_location_based_config()` function
- **Storage Format**: Associative array `LOCATIONS["<name>"]="external:<ip>|internal:<ips>"`
- **Validation**: Ensures at least one location exists, validates location names

## Related ADRs
- ADR-0004: Per-Peer State Tracking (updated to use location-based naming)
- ADR-0010: Configuration Schema Validation (schema supports location-based format)
- ADR-0014: Ping Check as Supplementary Diagnostic Tool (30% threshold for multiple IPs)
- ADR-0016: State File Location (/data/vpn-monitor/) (state files include location names)

## References
- CHANGELOG.md: Version 0.4.3 - Location-Based Configuration
- docs/MIGRATION.md: Migration guide for location-based configuration
- README.md: Location-based configuration documentation
- lib/config.sh: `load_location_based_config()` implementation
- scripts/migrate-config-to-locations.sh: Migration script
