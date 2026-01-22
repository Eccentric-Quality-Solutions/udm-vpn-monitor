# IP Rules Anonymization

The `anonymize-ip-rules.sh` script anonymizes IP addresses and interface names in `ip route` output while maintaining consistency, making route information safe to share for troubleshooting without exposing sensitive network information.

## Overview

The script processes IP route entries exported via `ip route` or `ip -6 route` and replaces:
- **IPv4 addresses** with anonymized addresses in the `10.x.x.x` range
- **IPv6 addresses** with anonymized addresses in the `fc00::/7` range (ULA)
- **Interface names** with anonymized interface names (except `lo` which is preserved)
- **MAC addresses** with anonymized MAC addresses (if present in link-layer info)
- **Hostnames/FQDNs** with anonymized hostnames (if present)

All replacements are **deterministic** - the same input always produces the same output, ensuring consistency within a file and across multiple runs.

**Note:** This script is part of the [Unified Anonymization System](UNIFIED_ANONYMIZATION.md). Use the `-m, --mapping-file` option to ensure consistent anonymization across firewall rules, IP routes, ipset sets, and VPN logs.

## Usage

### Basic Usage

```bash
# Anonymize routes and save to file
/data/vpn-monitor/scripts/anonymize-ip-rules.sh -i /tmp/ip-route.txt -o anonymized-routes.txt

# Anonymize routes and output to stdout
/data/vpn-monitor/scripts/anonymize-ip-rules.sh -i routes-ipv4.txt | less

# Verbose mode (shows progress and mappings)
/data/vpn-monitor/scripts/anonymize-ip-rules.sh -i routes-ipv4.txt -o anonymized-routes.txt -v
```

### Command Line Options

- `-i, --input FILE` - Input IP rules file (required)
  - Must be in `ip route` or `ip -6 route` format
  - File must exist and be readable

- `-o, --output FILE` - Output file for anonymized rules (optional)
  - If not specified, output is written to stdout
  - If specified, anonymized rules are written to this file

- `-m, --mapping-file FILE` - Mapping file for unified anonymization (optional)
  - If provided, loads existing mappings and saves updated mappings
  - Ensures consistent anonymization across all file types
  - See [Unified Anonymization System](UNIFIED_ANONYMIZATION.md) for details

- `-v, --verbose` - Verbose output
  - Shows progress messages during anonymization
  - Displays mapping of original values to anonymized values
  - Useful for debugging and verification

- `-h, --help` - Show help message
  - Displays usage information and exits

### Examples

#### Example 1: Anonymize IPv4 Routes

```bash
# Export current IPv4 routes
ip route > /tmp/my-ipv4-routes.txt

# Anonymize them
/data/vpn-monitor/scripts/anonymize-ip-rules.sh \
  -i /tmp/my-ipv4-routes.txt \
  -o /tmp/anonymized-ipv4-routes.txt

# View anonymized routes
cat /tmp/anonymized-ipv4-routes.txt
```

#### Example 2: Anonymize IPv6 Routes

```bash
# Export current IPv6 routes
ip -6 route > /tmp/my-ipv6-routes.txt

# Anonymize them
/data/vpn-monitor/scripts/anonymize-ip-rules.sh \
  -i /tmp/my-ipv6-routes.txt \
  -o /tmp/anonymized-ipv6-routes.txt \
  -v
```

#### Example 3: Anonymize and Pipe to Another Command

```bash
# Anonymize routes and search for specific patterns
/data/vpn-monitor/scripts/anonymize-ip-rules.sh \
  -i routes.txt | grep "default"
```

#### Example 4: Using with Export Script

```bash
# Export routes and firewall rules
/data/vpn-monitor/scripts/export-udm-routes-firewall.sh \
  -o /tmp/udm-export

# Anonymize the exported routes
/data/vpn-monitor/scripts/anonymize-ip-rules.sh \
  -i /tmp/udm-export/routes-ipv4-*.txt \
  -o /tmp/udm-export/routes-ipv4-anonymized.txt

/data/vpn-monitor/scripts/anonymize-ip-rules.sh \
  -i /tmp/udm-export/routes-ipv6-*.txt \
  -o /tmp/udm-export/routes-ipv6-anonymized.txt
```

## Input Format

The script expects input in the format produced by `ip route` or `ip -6 route` commands:

### IPv4 Route Format

```
default via 192.168.1.1 dev eth0
10.0.0.0/8 via 10.0.0.1 dev br0
192.168.1.0/24 dev eth0
172.16.0.0/16 via 172.16.0.1 dev eth1
```

### IPv6 Route Format

```
default via fe80::1 dev eth0
2001:db8::/32 via 2001:db8::1 dev br0
2001:db8:1::/64 dev eth0
fc00::/7 via fc00::1 dev eth1
```

### Mixed Format

The script can handle files containing both IPv4 and IPv6 routes:

```
default via 192.168.1.1 dev eth0
10.0.0.0/8 via 10.0.0.1 dev br0
default via fe80::1 dev eth0
2001:db8::/32 via 2001:db8::1 dev br0
```

## Anonymization Details

### IPv4 Address Anonymization

- **Original Range**: Any valid IPv4 address
- **Anonymized Range**: `10.x.x.x` (10.0.0.0 - 10.255.255.255)
- **CIDR Preservation**: CIDR notation (e.g., `/24`, `/8`) is preserved
- **Network Address Normalization**: Network addresses ending in `.0` with non-host CIDR are normalized to `.0` in the anonymized version (e.g., `192.168.1.0/24` → `10.x.x.0/24`)

### IPv6 Address Anonymization

- **Original Range**: Any valid IPv6 address
- **Anonymized Range**: `fc00::/7` (ULA - Unique Local Addresses)
- **CIDR Preservation**: CIDR notation (e.g., `/32`, `/64`) is preserved
- **Compressed Notation**: Compressed IPv6 addresses (e.g., `fe80::1`) are expanded to full format in anonymized output

### Interface Name Anonymization

- **Original**: Any interface name (e.g., `eth0`, `br0`, `wlan0`)
- **Anonymized**: Deterministic anonymized names using common interface prefixes (e.g., `eth1234`, `br5678`)
- **Special Case**: `lo` (loopback) is preserved as-is since it's standard and doesn't reveal sensitive information

### Deterministic Mapping

All anonymization uses deterministic hashing, ensuring:
- The same input always produces the same output
- Consistency across multiple runs
- Ability to compare anonymized files reliably

## Output Format

The anonymized output maintains the same structure as the input, with only IP addresses and interface names replaced:

### Example Input

```
default via 192.168.1.1 dev eth0
10.0.0.0/8 via 10.0.0.1 dev br0
192.168.1.0/24 dev eth0
```

### Example Output

```
default via 10.123.45.67 dev eth1234
10.234.56.0/8 via 10.234.56.78 dev br5678
10.345.67.0/24 dev eth1234
```

## Use Cases

### Troubleshooting

Share route information for troubleshooting without exposing:
- Internal network topology
- Gateway IP addresses
- Interface names that reveal network structure

### Documentation

Create anonymized route examples for:
- Documentation
- Training materials
- Bug reports

### Analysis

Compare anonymized route files from different systems or time periods while maintaining privacy.

## Integration with Export Script

The anonymize-ip-rules script works seamlessly with the `export-udm-routes-firewall.sh` script:

```bash
# Step 1: Export routes and firewall rules
/data/vpn-monitor/scripts/export-udm-routes-firewall.sh \
  -o /tmp/udm-export

# Step 2: Anonymize the exported routes
for file in /tmp/udm-export/routes-*.txt; do
  /data/vpn-monitor/scripts/anonymize-ip-rules.sh \
    -i "$file" \
    -o "${file%.txt}-anonymized.txt"
done
```

## Limitations

1. **Route Structure**: The script preserves route structure but does not validate route syntax. Invalid routes in input will produce invalid anonymized routes.

2. **IPv6 Compression**: Compressed IPv6 addresses (e.g., `fe80::1`) are expanded to full format in anonymized output. This is intentional for consistency.

3. **Comments**: The script does not handle comments in route files (though `ip route` output typically doesn't include comments).

4. **Other Identifiers**: The script only anonymizes IP addresses and interface names. Other identifiers (e.g., table names, route metrics) are not anonymized.

## Related Documentation

- [Firewall Rules Anonymization](ANONYMIZE_FIREWALL.md) - Similar anonymization for firewall rules
- [Export Script Documentation](../scripts/export-udm-routes-firewall.sh) - Script for exporting routes and firewall rules

## See Also

- `scripts/anonymize-ip-rules.sh` - The anonymization script
- `scripts/export-udm-routes-firewall.sh` - Export script for routes and firewall rules
- `scripts/anonymize-firewall.sh` - Firewall rules anonymization script
