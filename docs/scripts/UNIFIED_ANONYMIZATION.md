# Unified Anonymization System

The UDM VPN Monitor unified anonymization system provides consistent anonymization across all exported network data (firewall rules, IP routes, ipset sets, and VPN logs) using a shared mapping file. This ensures that the same IP address, MAC address, hostname, or other identifier maps to the same anonymized value across all file types.

## Overview

The unified anonymization system consists of:

- **Shared Library** (`lib/anonymize.sh`) - Core anonymization functions and mapping management
- **Individual Scripts** - Specialized anonymizers for each file type:
  - `anonymize-firewall.sh` - Firewall rules (iptables-save format)
  - `anonymize-ip-rules.sh` - IP routes (ip route output)
  - `anonymize-ipset.sh` - Ipset sets (ipset save output)
  - `anonymize-logs.sh` - VPN monitor logs
- **Unified Command** (`anonymize-all.sh`) - Runs all anonymizers with shared mapping

## Key Features

### Unified Mapping

All anonymization scripts use the same mapping file, ensuring consistency:
- Same IP address → Same anonymized IP across all files
- Same MAC address → Same anonymized MAC across all files
- Same hostname → Same anonymized hostname across all files
- Same set name → Same anonymized set name across all files
- Same location → Same anonymized location across all files

### Deterministic Anonymization

All anonymization is deterministic - the same input always produces the same output:
- Consistent within a single file
- Consistent across multiple runs
- Consistent across different file types (when using unified mapping)

### Comprehensive Coverage

The system anonymizes all identifying information:

- **IPv4 addresses** → `10.x.x.x` range
- **IPv6 addresses** → `fc00::/7` range (ULA)
- **Interface names** → Anonymized interface names (e.g., `eth0` → `eth42`)
- **Location names** → City names (e.g., `NYC` → `ANAHEIM`)
- **Ipset set names** → `SET_<number>` format (e.g., `ALIEN` → `SET_365351`)
- **MAC addresses** → `02:xx:xx:xx:xx:xx` range (locally-administered)
- **Hostnames/FQDNs** → `host-<number>.local` format

## Quick Start

### Basic Usage

#### Directory Mode (Recommended)

The easiest way to anonymize exported files is using directory mode, which auto-detects files:

```bash
# Export network data first
./scripts/export-udm-routes-firewall.sh -o /tmp/exports

# Anonymize all detected files with unified mapping
./scripts/anonymize-all.sh \
  -d /tmp/exports \
  -l /data/vpn-monitor/vpn-monitor.log \
  -o /tmp/anonymized \
  -m /tmp/mapping.txt
```

Directory mode automatically finds:
- `firewall-rules-*.txt` (most recent)
- `routes-ipv4-*.txt` (most recent)
- `routes-ipv6-*.txt` (most recent)
- `ipset-sets-*.txt` (most recent)

#### Explicit File Mode

You can also specify files explicitly:

```bash
# Anonymize all files with unified mapping (explicit files)
./scripts/anonymize-all.sh \
  -f firewall-rules.txt \
  -r4 routes-ipv4.txt \
  -r6 routes-ipv6.txt \
  -s ipset-sets.txt \
  -l vpn-monitor.log \
  -o /tmp/anonymized \
  -m /tmp/mapping.txt
```

#### Mixed Mode

You can combine directory mode with explicit files (explicit files override auto-detection):

```bash
# Auto-detect most files, but use custom firewall file
./scripts/anonymize-all.sh \
  -d /tmp/exports \
  -f /path/to/custom-firewall.txt \
  -l vpn-monitor.log \
  -o /tmp/anonymized \
  -m /tmp/mapping.txt
```

This will:
1. Auto-detect routes and ipset files from `/tmp/exports`
2. Use the explicitly specified firewall file (overrides auto-detection)
3. Use the explicitly specified log file
4. Load existing mappings from `mapping.txt` (if it exists)
5. Anonymize all files using unified mappings
6. Save updated mappings back to `mapping.txt`
7. Write anonymized files to `/tmp/anonymized/`

### Individual Script Usage

Each script can be used independently with a mapping file:

```bash
# Anonymize firewall rules
./scripts/anonymize-firewall.sh \
  -i firewall-rules.txt \
  -o anonymized-firewall.txt \
  -m mapping.txt

# Anonymize IP routes
./scripts/anonymize-ip-rules.sh \
  -i routes-ipv4.txt \
  -o anonymized-routes.txt \
  -m mapping.txt

# Anonymize logs
./scripts/anonymize-logs.sh \
  -i vpn-monitor.log \
  -o anonymized.log \
  -m mapping.txt
```

### Standalone Usage (No Mapping File)

Scripts work without mapping files for backward compatibility:

```bash
# Anonymize without mapping file (standalone mode)
./scripts/anonymize-firewall.sh \
  -i firewall-rules.txt \
  -o anonymized-firewall.txt
```

In standalone mode, each script generates its own mappings internally, but mappings are not shared across scripts.

## Mapping File Format

The mapping file is human-readable and contains all mappings organized by type:

```
# Unified Anonymization Mapping
# Generated: 2026-01-20 14:30:00

IPv4 Addresses:
--------------------------------------------------
172.31.10.0/24 -> 172.31.20.0/24
172.31.10.2 -> 172.31.20.44
192.168.1.1 -> 172.31.14.100

IPv6 Addresses:
--------------------------------------------------
2001:db8::1 -> fc00:1234::1
fe80::1 -> fc00:5678::1

Interfaces:
--------------------------------------------------
eth8 -> eth42
br0 -> br10

Set Names:
--------------------------------------------------
UBIOS_ALL_ADDRv4_eth8 -> SET_42
UBIOS_DMZ_subnets -> SET_10
ALIEN -> SET_99

MAC Addresses:
--------------------------------------------------
aa:bb:cc:dd:ee:ff -> 02:42:ac:11:00:01
00:11:22:33:44:55 -> 02:42:ac:11:00:02

Hostnames:
--------------------------------------------------
server.example.com -> host-42.local
router.lan -> host-10.local

Locations:
--------------------------------------------------
CLEVELAND -> SEATTLE
NYC -> ANAHEIM
```

## Workflow Examples

### Example 1: First-Time Anonymization (Directory Mode)

```bash
# Export network data
./scripts/export-udm-routes-firewall.sh -o /tmp/exports

# Anonymize all files using directory mode (creates new mapping file)
./scripts/anonymize-all.sh \
  -d /tmp/exports \
  -l /data/vpn-monitor/vpn-monitor.log \
  -o /tmp/anonymized \
  -m /tmp/mapping.txt
```

Directory mode automatically finds the most recent files matching the export patterns.

### Example 2: Adding New Files to Existing Mapping

```bash
# Anonymize new firewall export using existing mapping
./scripts/anonymize-firewall.sh \
  -i /tmp/new-firewall-rules.txt \
  -o /tmp/new-anonymized-firewall.txt \
  -m /tmp/mapping.txt

# Mapping file is automatically updated with any new mappings
```

### Example 3: Incremental Anonymization

```bash
# Anonymize files one at a time, building up the mapping
./scripts/anonymize-firewall.sh -i firewall.txt -o firewall-anon.txt -m mapping.txt
./scripts/anonymize-ip-rules.sh -i routes.txt -o routes-anon.txt -m mapping.txt
./scripts/anonymize-logs.sh -i logs.txt -o logs-anon.txt -m mapping.txt

# Each script extends the mapping file, ensuring consistency
```

## Architecture

### Shared Library (`lib/anonymize.sh`)

The library provides:

**Core Functions:**
- `hash_string()` - Deterministic string hashing
- `anonymize_ipv4()` - IPv4 anonymization
- `anonymize_ipv6()` - IPv6 anonymization
- `anonymize_interface()` - Interface name anonymization
- `anonymize_location()` - Location name anonymization
- `anonymize_set_name()` - Ipset set name anonymization
- `anonymize_mac_address()` - MAC address anonymization
- `anonymize_hostname()` - Hostname/FQDN anonymization

**Mapping Management:**
- `load_mapping_file()` - Load mappings from file
- `save_mapping_file()` - Save mappings to file
- `get_or_create_*_mapping()` - Get existing or create new mapping

**Extraction Functions:**
- `extract_ipv4_from_file()` - Extract IPv4 addresses
- `extract_ipv6_from_file()` - Extract IPv6 addresses
- `extract_interfaces_from_file()` - Extract interface names
- `extract_ips_from_log()` - Extract IPs from log format
- `extract_locations_from_log()` - Extract location names
- `extract_mac_addresses_from_file()` - Extract MAC addresses
- `extract_hostnames_from_file()` - Extract hostnames/FQDNs

### Script Structure

All anonymization scripts follow the same pattern:

1. **Source library** - `source lib/anonymize.sh`
2. **Parse arguments** - Including optional `--mapping-file`
3. **Load mappings** - If mapping file provided and exists
4. **Extract identifiers** - From input file
5. **Create mappings** - For any unmapped identifiers
6. **Build replacement scripts** - Generate sed scripts for replacements
7. **Anonymize file** - Apply replacements in correct order
8. **Save mappings** - If mapping file provided

## Anonymization Details

### IPv4 Addresses
- **Range**: `10.0.0.0` - `10.255.255.255` (private network range)
- **CIDR Preservation**: CIDR notation is preserved (e.g., `/24`)
- **Network Normalization**: Network addresses (ending in `.0`) are normalized to `.0` in anonymized output

### IPv6 Addresses
- **Range**: `fc00::/7` (ULA - Unique Local Addresses)
- **CIDR Preservation**: CIDR notation is preserved
- **Compression Support**: Handles compressed notation (`::`)

### Interface Names
- **Format**: `prefixNNNN` (e.g., `eth42`, `br10`)
- **Preservation**: Loopback interface (`lo`) is preserved as-is
- **Deterministic**: Same interface name always maps to same anonymized name

### Location Names
- **Format**: City names (e.g., `HOUSTON`, `DALLAS`, `PHOENIX`)
- **Uniqueness**: Each location maps to a unique city name
- **Deterministic**: Same location always maps to same city

### Ipset Set Names
- **Format**: `SET_<number>` (e.g., `SET_42`, `SET_365351`)
- **Deterministic**: Same set name always maps to same anonymized name
- **Readable**: Numeric suffix makes sets easy to reference

### MAC Addresses
- **Range**: `02:xx:xx:xx:xx:xx` (locally-administered, unicast)
- **Format**: Standard MAC address format
- **Deterministic**: Same MAC always maps to same anonymized MAC

### Hostnames/FQDNs
- **Format**: `host-<number>.local` (e.g., `host-42.local`)
- **Deterministic**: Same hostname always maps to same anonymized hostname
- **Domain Preservation**: Domain structure is simplified to `.local`

## Best Practices

### 1. Use Unified Mapping for Consistency

Always use the `-m` flag with the same mapping file when anonymizing multiple files:

```bash
# Good: All files use same mapping
./scripts/anonymize-all.sh -f fw.txt -r4 r4.txt -m mapping.txt -o out/

# Bad: Each file gets different mappings
./scripts/anonymize-firewall.sh -i fw.txt -o fw-anon.txt  # No mapping
./scripts/anonymize-ip-rules.sh -i r4.txt -o r4-anon.txt  # No mapping
```

### 2. Keep Mapping Files Secure

Mapping files contain the relationship between real and anonymized values:
- Store mapping files securely
- Don't share mapping files with anonymized data
- Consider encrypting mapping files if storing long-term

### 3. Version Control Mapping Files

When anonymizing multiple exports over time:
- Keep separate mapping files for different time periods
- Or use a single mapping file and extend it incrementally
- Document which mapping file was used for which anonymized data

### 4. Verify Consistency

After anonymization, verify that the same identifiers map consistently:

```bash
# Check that same IP appears consistently
grep "172.31.14.100" firewall-anon.txt routes-anon.txt logs-anon.txt

# Should appear in all files if original IP was in all files
```

## Troubleshooting

### Issue: Mappings Not Consistent Across Files

**Cause**: Not using unified mapping file

**Solution**: Always use `-m mapping.txt` with the same file for all scripts

### Issue: IPv6 Addresses Not Being Anonymized

**Cause**: IPv6 extraction regex may not match compressed addresses

**Solution**: Check that IPv6 addresses are in standard format. The regex handles:
- Full addresses: `2001:db8::1`
- Compressed: `fe80::1`, `::1`
- CIDR notation: `2001:db8::/32`

### Issue: Mapping File Not Being Updated

**Cause**: Script may not have write permissions

**Solution**: Ensure script has write access to mapping file directory

### Issue: Timestamps Being Anonymized as IPv6

**Cause**: Old IPv6 regex bug (fixed in 2026-01-20)

**Solution**: Update to latest version with improved IPv6 extraction regex

## Related Documentation

- [Firewall Anonymization](ANONYMIZE_FIREWALL.md) - Detailed firewall anonymization guide
- [IP Rules Anonymization](ANONYMIZE_IP_RULES.md) - Detailed IP route anonymization guide
- [Export Scripts](../scripts/export-udm-routes-firewall.sh) - Scripts to export network data

## Version History

- **v1.0.0** (2026-01-20) - Initial unified anonymization system
  - Shared library (`lib/anonymize.sh`)
  - Unified mapping file support
  - All anonymization types (IPv4, IPv6, interfaces, locations, set names, MACs, hostnames)
  - Unified command (`anonymize-all.sh`)
  - Fixed IPv6 extraction regex to avoid timestamp false positives
