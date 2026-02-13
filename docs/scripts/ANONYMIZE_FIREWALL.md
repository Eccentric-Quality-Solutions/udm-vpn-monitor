# Firewall Rules Anonymization

The `anonymize-firewall.sh` script anonymizes IP addresses, interface names, ipset set names, and other identifiers in iptables-save output while maintaining consistency, making firewall rules safe to share for troubleshooting without exposing sensitive network information.

## Overview

The script processes firewall rules exported via `iptables-save` and replaces:
- **IPv4 addresses** with anonymized addresses in the `10.x.x.x` range
- **IPv6 addresses** with anonymized addresses in the `fc00::/7` range (ULA)
- **Interface names** with anonymized interface names (except `lo` which is preserved)
- **Ipset set names** with anonymized set names (e.g., `ALIEN` → `SET_365351`)
- **MAC addresses** with anonymized MAC addresses (if present)
- **Hostnames/FQDNs** with anonymized hostnames (if present)

All replacements are **deterministic** - the same input always produces the same output, ensuring consistency within a file and across multiple runs.

**Note:** This script is part of the [Unified Anonymization System](UNIFIED_ANONYMIZATION.md). Use the `-m, --mapping-file` option to ensure consistent anonymization across firewall rules, IP routes, ipset sets, and VPN logs.

## Usage

### Basic Usage

```bash
# Anonymize rules and save to file
/data/vpn-monitor/scripts/anonymize-firewall.sh -i /tmp/iptables-save.txt -o anonymized-rules.txt

# Anonymize rules and output to stdout
/data/vpn-monitor/scripts/anonymize-firewall.sh -i firewall-rules.txt | less

# Verbose mode (shows progress and mappings)
/data/vpn-monitor/scripts/anonymize-firewall.sh -i firewall-rules.txt -o anonymized-rules.txt -v
```

### Command Line Options

- `-i, --input FILE` - Input firewall rules file (required)
  - Must be in iptables-save format
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

#### Example 1: Anonymize and Save

```bash
# Export current firewall rules
iptables-save > /tmp/my-firewall-rules.txt

# Anonymize them
/data/vpn-monitor/scripts/anonymize-firewall.sh \
  -i /tmp/my-firewall-rules.txt \
  -o /tmp/anonymized-rules.txt

# Review the anonymized rules
cat /tmp/anonymized-rules.txt
```

#### Example 2: Pipe to Other Commands

```bash
# Anonymize and count rules
/data/vpn-monitor/scripts/anonymize-firewall.sh \
  -i firewall-rules.txt | grep -c "^\-A"

# Anonymize and search for specific patterns
/data/vpn-monitor/scripts/anonymize-firewall.sh \
  -i firewall-rules.txt | grep "ACCEPT"
```

#### Example 3: Verbose Mode for Debugging

```bash
/data/vpn-monitor/scripts/anonymize-firewall.sh \
  -i firewall-rules.txt \
  -o anonymized-rules.txt \
  -v
```

Output will show:
```
Extracting IPv4 addresses...
  Mapping 192.168.1.0/24 -> 172.31.22.20/24
  Mapping 203.0.113.1 -> 172.31.24.159
Extracted 5 unique IPv4 addresses
Extracting interface names...
  Mapping eth0 -> eth42
  Mapping wlan0 -> br10
Extracted 3 unique interface names
Anonymizing firewall rules file...
Processed 22 lines
Anonymization complete!
```

## How It Works

### Anonymization Process

1. **Extraction Phase**: The script scans the input file and extracts:
   - All IPv4 addresses (with CIDR notation preserved)
   - All IPv6 addresses (with CIDR notation preserved)
   - All interface names from `-i`, `-o`, `--in-interface`, and `--out-interface` options
   - Identifiers from comments (uppercase alphanumeric strings)

2. **Mapping Phase**: For each unique value found:
   - A deterministic hash is computed
   - The hash is used to generate a consistent anonymized value
   - The mapping is stored for reuse

3. **Replacement Phase**: The script processes the file in stages:
   - Identifiers are replaced first
   - Interfaces are replaced second
   - IPv6 addresses are replaced third
   - IPv4 addresses are replaced last
   
   This order ensures longer patterns are replaced before shorter ones to avoid partial matches.

### Anonymization Details

#### IPv4 Addresses
- **Range**: `10.0.0.0` - `10.255.255.255` (private network range)
- **CIDR Preservation**: CIDR notation (e.g., `/24`) is preserved
- **Consistency**: Same IP always maps to same anonymized IP
- **Example**: `192.168.1.0/24` → `172.31.22.20/24`

#### IPv6 Addresses
- **Range**: `fc00::/7` (Unique Local Addresses - ULA)
- **CIDR Preservation**: CIDR notation is preserved
- **Consistency**: Same IPv6 address always maps to same anonymized address
- **Example**: `2001:db8::1` → `fc00:1234:5678:9abc:def0:1234:5678:9abc`

#### Interface Names
- **Format**: Prefix + numeric suffix (e.g., `eth42`, `br10`)
- **Prefixes**: Common interface prefixes (eth, ens, enp, wlan, br, bond, etc.)
- **Special Case**: `lo` (loopback) is preserved as-is
- **Consistency**: Same interface always maps to same anonymized interface
- **Example**: `eth0` → `eth42`, `wlan0` → `br10`

#### Identifiers
- **Format**: `ID_` followed by 8 hexadecimal characters
- **Source**: Extracted from comments (uppercase alphanumeric strings)
- **Consistency**: Same identifier always maps to same anonymized identifier
- **Example**: `PRODUCTION_SERVER` → `ID_a1b2c3d4`

## Input Format

The script expects input in **iptables-save format**, which is the standard output format of the `iptables-save` command.

### Example Input

```bash
# Generated by iptables-save v1.8.7
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -i eth0 -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -s 192.168.1.0/24 -j ACCEPT
-A INPUT -s 10.0.0.5 -j ACCEPT
COMMIT

*nat
:PREROUTING ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -o eth0 -j MASQUERADE
-A POSTROUTING -s 192.168.1.0/24 -o eth0 -j SNAT --to-source 203.0.113.1
COMMIT
```

### Example Output

```bash
# Generated by iptables-save v1.8.7
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -i eth42 -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -s 172.31.22.20/24 -j ACCEPT
-A INPUT -s 172.31.18.170 -j ACCEPT
COMMIT

*nat
:PREROUTING ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -o eth42 -j MASQUERADE
-A POSTROUTING -s 172.31.22.20/24 -o eth42 -j SNAT --to-source 172.31.24.159
COMMIT
```

## What Gets Preserved

The script preserves the structure and formatting of the firewall rules:

- ✅ Table declarations (`*filter`, `*nat`, etc.)
- ✅ Chain declarations (`:INPUT DROP [0:0]`)
- ✅ Rule syntax and structure
- ✅ COMMIT statements
- ✅ Comments (with identifiers anonymized)
- ✅ CIDR notation in IP addresses
- ✅ All iptables options and targets
- ✅ Packet/byte counters (if present)

## Use Cases

### Sharing Rules for Troubleshooting

When seeking help with firewall configuration issues, you can anonymize your rules before sharing:

```bash
# Export and anonymize
iptables-save > /tmp/rules.txt
/data/vpn-monitor/scripts/anonymize-firewall.sh \
  -i /tmp/rules.txt \
  -o /tmp/anonymized.txt

# Share /tmp/anonymized.txt instead of original rules
```

### Documentation and Examples

Anonymized rules can be used in documentation, training materials, or examples without exposing real network topology:

```bash
# Create anonymized example rules
/data/vpn-monitor/scripts/anonymize-firewall.sh \
  -i production-rules.txt \
  -o docs/examples/firewall-rules-example.txt
```

### Testing and Development

Anonymized rules can be used in test environments or shared with developers:

```bash
# Anonymize production rules for testing
/data/vpn-monitor/scripts/anonymize-firewall.sh \
  -i /etc/iptables/rules.v4 \
  -o test-rules.txt
```

## Limitations

### IPv6 Support
- IPv6 address extraction uses a simplified pattern
- Compressed IPv6 notation (e.g., `::1`) may not be fully supported
- IPv6 addresses in brackets (e.g., `[2001:db8::1]`) are handled

### Interface Detection
- Only interfaces in `-i`, `-o`, `--in-interface`, and `--out-interface` options are anonymized
- Interfaces in comments or other contexts are not automatically detected
- Negated interfaces (e.g., `-i !eth0`) are supported

### Identifier Extraction
- Identifier extraction from comments is heuristic-based
- Only uppercase alphanumeric strings with underscores are extracted
- May miss some identifier formats

## Related Scripts

- **[anonymize-logs.sh](../scripts/anonymize-logs.sh)** - Anonymizes VPN monitor log files
- **[export-udm-routes-firewall.sh](../scripts/export-udm-routes-firewall.sh)** - Exports UDM firewall rules and routes

## See Also

- [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) - Troubleshooting guide
- [README.md](../README.md) - Main documentation
- [iptables-save(8)](https://manpages.debian.org/iptables-save.8) - iptables-save manual page
