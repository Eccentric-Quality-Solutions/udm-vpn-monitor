# Migration Guide: Old Format to Location-Based Configuration

This guide explains how to migrate from the old `EXTERNAL_PEER_IPS`/`INTERNAL_PEER_IPS` configuration format to the new location-based configuration format.

## Overview

The location-based configuration format provides better organization for managing multiple VPN connections by grouping external and internal IPs under named locations. This makes it easier to manage configurations with many VPN tunnels and supports multiple internal IPs per location with a 30% ping threshold.

## What Changed

### Old Format
```bash
EXTERNAL_PEER_IPS="203.0.113.1 198.51.100.1"
INTERNAL_PEER_IPS="192.168.100.1 192.168.200.1"
```

### New Format
```bash
LOCATION_NYC_EXTERNAL="203.0.113.1"
LOCATION_NYC_INTERNAL="192.168.100.1"

LOCATION_DC_EXTERNAL="198.51.100.1"
LOCATION_DC_INTERNAL="192.168.200.1"
```

## Benefits of Location-Based Configuration

1. **Better Organization**: Group related external and internal IPs under named locations
2. **Multiple Internal IPs**: Support multiple internal IPs per location with 30% ping threshold
3. **Clearer Logging**: Location names appear in logs and state files for easier identification
4. **Independent Tracking**: Each location has its own failure counter and state files
5. **Easier Management**: Add or remove locations without affecting others

## Migration Methods

### Method 1: Automated Migration Script (Recommended)

The migration script automatically converts your old configuration to the new format:

1. **Backup your current config** (the script does this automatically, but it's good practice):
   ```bash
   cp /data/vpn-monitor/vpn-monitor.conf /data/vpn-monitor/vpn-monitor.conf.backup
   ```

2. **Run the migration script**:
   ```bash
   /data/vpn-monitor/scripts/migrate-config-to-locations.sh
   ```

3. **Choose location name generation method**:
   - **Default (Interactive)**: Prompts you to enter a name for each location (e.g., NYC, DC, SF)
   - **Automatic**: Use `--auto` flag to generate generic names: `LOCATION_1`, `LOCATION_2`, etc.
   - **CSV**: Use `--csv` flag to read location names from a CSV file

4. **Review the generated configuration**:
   ```bash
   nano /data/vpn-monitor/vpn-monitor.conf
   ```

5. **Validate the configuration**:
   ```bash
   /data/vpn-monitor/vpn-monitor.sh --fake
   ```

### Method 2: Manual Migration

If you prefer to migrate manually:

1. **Backup your current config**:
   ```bash
   cp /data/vpn-monitor/vpn-monitor.conf /data/vpn-monitor/vpn-monitor.conf.backup
   ```

2. **Edit the config file**:
   ```bash
   nano /data/vpn-monitor/vpn-monitor.conf
   ```

3. **Replace old format with new format**:
   ```bash
   # Old format (remove these):
   EXTERNAL_PEER_IPS="203.0.113.1 198.51.100.1"
   INTERNAL_PEER_IPS="192.168.100.1 192.168.200.1"
   
   # New format (add these):
   LOCATION_NYC_EXTERNAL="203.0.113.1"
   LOCATION_NYC_INTERNAL="192.168.100.1"
   
   LOCATION_DC_EXTERNAL="198.51.100.1"
   LOCATION_DC_INTERNAL="192.168.200.1"
   ```

4. **Choose meaningful location names**:
   - Use descriptive names like `NYC`, `DC`, `CHICAGO`, `OFFICE`, etc.
   - Location names are automatically extracted from variable names (text between `LOCATION_` and `_EXTERNAL`)
   - Invalid characters are automatically sanitized (replaced with underscores)

5. **Validate the configuration**:
   ```bash
   /data/vpn-monitor/vpn-monitor.sh --fake
   ```

## Migration Script Options

The migration script (version 1.1.0+) supports several options:

**Note**: As of version 1.1.0, the default behavior changed from automatic generation to interactive mode. This is a breaking change from earlier versions. Use the `--auto` flag if you need the old automatic behavior.

### Default Mode (Interactive - Prompts for Location Names)
```bash
/data/vpn-monitor/scripts/migrate-config-to-locations.sh
```
**Default behavior** (v1.1.0+): Prompts you to enter a name for each location (e.g., NYC, DC, SF). This allows you to use meaningful location names by default. If you press Enter without entering a name, it will use a numeric default (1, 2, etc.).

### Automatic Mode (Generic Location Names)
```bash
/data/vpn-monitor/scripts/migrate-config-to-locations.sh --auto
```
Generates location names automatically: `LOCATION_1`, `LOCATION_2`, etc. Use this flag for non-interactive migrations, automated scripts, or when you don't need custom names. This restores the pre-v1.1.0 default behavior.

### Interactive Mode (Explicit)
```bash
/data/vpn-monitor/scripts/migrate-config-to-locations.sh --interactive
```
Explicitly enables interactive mode (same as default). Prompts you to enter a name for each location.

### CSV Mode (Bulk Import)
```bash
/data/vpn-monitor/scripts/migrate-config-to-locations.sh --csv locations.csv
```
Reads location names from a CSV file. CSV format (index,name):
```csv
2,DC
3,CHICAGO
```

**Note**: The CSV file only provides location names. External and internal IPs are read from the existing `EXTERNAL_PEER_IPS` and `INTERNAL_PEER_IPS` variables in your config file. The index in the CSV corresponds to the position of the external IP in `EXTERNAL_PEER_IPS` (1 = first IP, 2 = second IP, etc.). If an index is missing from the CSV, the script will use the index number as the location name.

## Location Name Rules

- **Extraction**: Location names are extracted from variable names (text between `LOCATION_` and `_EXTERNAL`)
- **Sanitization**: Invalid characters are automatically replaced with underscores
- **Length**: Maximum 64 characters (enforced automatically)
- **Format**: Must start with alphanumeric character (not underscore)
- **Uniqueness**: Each location name must be unique

**Examples**:
- `LOCATION_NYC_EXTERNAL` → location name: `NYC`
- `LOCATION_NYC_OFFICE_EXTERNAL` → location name: `NYC_OFFICE`
- `LOCATION_DC-1_EXTERNAL` → location name: `DC_1` (dash replaced with underscore)

## Multiple Internal IPs

The new format supports multiple internal IPs per location:

```bash
LOCATION_DC_EXTERNAL="198.51.100.1"
LOCATION_DC_INTERNAL="192.168.200.1 192.168.200.2 192.168.200.3"
```

**Health Determination**:
- For locations with **multiple internal IPs**: VPN is considered healthy if ≥30% respond to pings (rounded up)
- For locations with **single internal IP**: VPN requires 100% success (ping must succeed)

**Example**:
- 3 internal IPs: Need at least 1 successful ping (30% of 3 = 0.9, rounded up = 1)
- 10 internal IPs: Need at least 3 successful pings (30% of 10 = 3)

## State Files After Migration

After migration, state files will use location-based naming:

**Old Format**:
- `state/failure_count_203_0_113_1`
- `state/last_bytes_203_0_113_1`
- `state/spi_203_0_113_1`
- `state/failure_type_203_0_113_1`
- `state/idle_detected_203_0_113_1`
- `state/last_status_log_203_0_113_1`
- `state/recovery_method_203_0_113_1`

**New Format**:
- `state/failure_count_NYC_203_0_113_1`
- `state/last_bytes_NYC_203_0_113_1`
- `state/spi_NYC_203_0_113_1`
- `state/failure_type_NYC_203_0_113_1`
- `state/idle_detected_NYC_203_0_113_1`
- `state/last_status_log_NYC_203_0_113_1`
- `state/recovery_method_NYC_203_0_113_1`

**Note**: The location name (e.g., `NYC`) is inserted between the state file type and the sanitized IP address. This allows multiple locations with the same external IP to be tracked independently (though this is uncommon).

**Important**: Old state files are **not automatically migrated**. The system will create new state files for the new configuration format. Old state files can be safely removed after verifying the new configuration works correctly.

## Verification Steps

After migration, verify the configuration:

1. **Check configuration parsing**:
   ```bash
   /data/vpn-monitor/vpn-monitor.sh --fake
   ```
   Look for any configuration errors in the output.

2. **Verify location detection**:
   Check logs for location names:
   ```bash
   tail -f /data/vpn-monitor/logs/vpn-monitor.log
   ```

3. **Test VPN checks**:
   Run a manual check:
   ```bash
   /data/vpn-monitor/vpn-monitor.sh
   ```

4. **Verify state files**:
   Check that new state files are created with location-based names:
   ```bash
   ls -la /data/vpn-monitor/state/failure_count_*
   ls -la /data/vpn-monitor/state/last_bytes_*
   ```

## Troubleshooting

### Configuration Not Found Error
If you see "No location-based configuration found":
- Ensure at least one `LOCATION_*_EXTERNAL` variable is set
- Check that variable names follow the format: `LOCATION_<NAME>_EXTERNAL`
- Verify the config file is readable: `cat /data/vpn-monitor/vpn-monitor.conf`

### Duplicate Location Names
If you see "Duplicate location name detected":
- Check that location names are unique after sanitization
- For example, `LOCATION_NYC-1` and `LOCATION_NYC_1` both become `NYC_1` (duplicate)
- Use different base names: `LOCATION_NYC_OFFICE` and `LOCATION_NYC_DATACENTER`

### Invalid Location Name
If location name validation fails:
- Ensure location names start with alphanumeric character
- Check that names don't contain only special characters
- Use descriptive names: `NYC`, `DC`, `CHICAGO`, etc.

### State Files Not Created
If state files aren't created:
- Verify configuration is valid: `/data/vpn-monitor/vpn-monitor.sh --fake`
- Check directory permissions: `ls -ld /data/vpn-monitor/logs /data/vpn-monitor/state`
- Ensure VPN checks are running: Check cron job: `crontab -l | grep vpn-monitor`

## Rollback

If you need to rollback to the old format:

1. **Restore backup**:
   ```bash
   cp /data/vpn-monitor/vpn-monitor.conf.backup /data/vpn-monitor/vpn-monitor.conf
   ```

2. **Note**: The old format is **no longer supported**. You'll need to use the migration script to convert back, or manually recreate the old format variables (not recommended).

## Additional Resources

- **Configuration Examples**: See `vpn-monitor.conf` for location-based configuration examples
- **Architecture Documentation**: See [ARCHITECTURE.md](ARCHITECTURE.md) for state file naming details
- **README**: See [README.md](../README.md) for general configuration documentation

## Support

If you encounter issues during migration:
1. Check the troubleshooting section above
2. Review logs: `tail -f /data/vpn-monitor/logs/vpn-monitor.log`
3. Run in fake mode: `/data/vpn-monitor/vpn-monitor.sh --fake`
4. Check configuration: `cat /data/vpn-monitor/vpn-monitor.conf`
