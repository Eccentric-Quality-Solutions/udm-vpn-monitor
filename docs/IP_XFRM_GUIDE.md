# IP XFRM Command Guide

A comprehensive guide to using the `ip` command, with special focus on the `xfrm` subcommand for managing IPsec (Internet Protocol Security) on Linux systems, particularly UDM OS 4.3+.

## Table of Contents

1. [Overview](#overview)
2. [Quick Reference](#quick-reference)
3. [The IP Command](#the-ip-command)
4. [Understanding XFRM](#understanding-xfrm)
5. [Security Policies (SPs)](#security-policies-sps)
6. [Security Associations (SAs)](#security-associations-sas)
7. [Common Operations](#common-operations)
8. [Output Format Reference](#output-format-reference)
9. [Advanced Features](#advanced-features)
10. [Troubleshooting](#troubleshooting)
11. [Best Practices](#best-practices)
12. [References](#references)

## Overview

The `ip` command is part of the `iproute2` suite and is the modern replacement for legacy networking tools like `ifconfig`, `route`, and `netstat`. The `xfrm` (transform) subcommand specifically manages IPsec configurations through the Linux kernel's XFRM framework.

**Key Points:**
- Requires root privileges to execute
- Part of the `iproute2` package (standard on UDM OS 4.3+)
- Directly interfaces with the Linux kernel's XFRM subsystem
- Used by IPsec daemons (StrongSwan, Libreswan) under the hood
- Provides low-level control over IPsec policies and states

## Quick Reference

### Most Common Commands

```bash
# List all Security Associations (SAs)
ip xfrm state show

# List SAs with statistics (byte/packet counters)
ip -s xfrm state show

# List all Security Policies
ip xfrm policy show

# Monitor XFRM events in real-time
ip xfrm monitor
```

### Critical Gotchas

1. **Mark Format Difference:**
   - **In output:** `mark 0x1/0xffffffff` (combined format)
   - **In commands:** `mark 0x1 mask 0xffffffff` (separate parameters)
   - Always use separate `mark` and `mask` parameters in `get` and `delete` commands

2. **Exit Code Behavior:**
   - `ip xfrm state` returns exit code 0 even when no SAs exist (empty output)
   - Check for error messages in output to detect actual failures

3. **Statistics Flag:**
   - Always try `ip -s xfrm state show` first (more detail)
   - Fall back to `ip xfrm state show` if `-s` not supported

4. **SA Deletion:**
   - Must include ALL selectors used when creating the SA
   - If SA has mark, deletion requires: `mark <value> mask <mask>` (separate parameters)
   - Missing selectors cause silent failures

5. **Multi-line Output:**
   - `lifetime current:` section spans multiple lines
   - Use context lines (`grep -A 5`) to capture complete sections
   - Bytes appear on line AFTER `lifetime current:`

### Common Patterns

```bash
# Check if SA exists for peer
ip xfrm state show | grep -q "dst 10.0.0.2" && echo "SA exists"

# Extract byte counter
ip -s xfrm state show | grep -A 5 "lifetime current:" | grep -E "[0-9]+\(bytes\)"

# Delete SA with mark (parse from output first)
mark_info=$(ip xfrm state show | grep "mark" | head -1)
if [[ "$mark_info" =~ mark[[:space:]]+(0x[0-9a-fA-F]+)/(0x[0-9a-fA-F]+) ]]; then
    ip xfrm state delete src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100 \
        mark "${BASH_REMATCH[1]}" mask "${BASH_REMATCH[2]}"
fi
```

## The IP Command

### General Syntax

```bash
ip [ OPTIONS ] OBJECT { COMMAND | help }
```

**Common Objects:**
- `link` - Network interfaces
- `addr` - IP addresses
- `route` - Routing tables
- `xfrm` - IPsec transform framework (our focus)
- `tunnel` - Tunnels
- `rule` - Routing rules

**Common Options:**
- `-s`, `-stats`, `-statistics` - Show statistics
- `-d`, `-details` - Show detailed information
- `-f`, `-family` - Specify address family (inet, inet6)
- `-4` - IPv4 only
- `-6` - IPv6 only

### Getting Help

```bash
ip help                    # General help
ip xfrm help              # XFRM-specific help
ip xfrm state help        # State command help
ip xfrm policy help       # Policy command help
```

## Understanding XFRM

XFRM (Transform) is a framework within the Linux kernel that handles packet transformation, primarily for IPsec operations. It manages two critical components:

### Security Policies (SPs)

Security Policies define **which traffic** should be protected by IPsec. They specify:
- Source and destination addresses/networks
- Protocols and ports
- Direction (inbound, outbound, forward)
- Required IPsec action (encrypt, authenticate, bypass, discard)
- Template matching for SA selection

### Security Associations (SAs)

Security Associations define **how** traffic is secured. They specify:
- Cryptographic algorithms (encryption, authentication)
- Keys for encryption and authentication
- Security Parameter Index (SPI) - unique identifier
- Mode (transport or tunnel)
- Lifetime and byte/packet counters
- Optional selectors (mark, reqid, etc.)

**Relationship:**
- Policies select traffic that needs protection
- SAs provide the cryptographic parameters for that protection
- Multiple policies can reference the same SA
- SAs are typically established via IKE (Internet Key Exchange) protocols

## Security Policies (SPs)

### Basic Syntax

```bash
ip xfrm policy { add | update | delete | get | flush | list | show | monitor } [ OPTIONS ]
```

### Adding a Policy

```bash
ip xfrm policy add src <SRC> dst <DST> dir <DIR> [ OPTIONS ]
```

**Required Parameters:**
- `src <SRC>` - Source address/network (e.g., `192.168.1.0/24` or `192.168.1.1`)
- `dst <DST>` - Destination address/network
- `dir <DIR>` - Direction: `in`, `out`, or `fwd`

**Common Options:**
- `tmpl src <TUNNEL_SRC> dst <TUNNEL_DST> proto <PROTO> mode <MODE>` - Template for SA matching
  - `proto esp` or `proto ah` - Protocol (ESP or AH)
  - `mode tunnel` or `mode transport` - IPsec mode
- `priority <PRIORITY>` - Policy priority (lower number = higher priority)
- `action <ACTION>` - Action: `allow`, `block`, `ipsec`
- `sel <SELECTOR>` - Additional selectors (protocol, ports, etc.)

**Example - Outbound Policy:**

```bash
ip xfrm policy add \
    src 192.168.1.0/24 \
    dst 192.168.2.0/24 \
    dir out \
    tmpl src 10.0.0.1 dst 10.0.0.2 proto esp mode tunnel
```

**Example - Inbound Policy:**

```bash
ip xfrm policy add \
    src 192.168.2.0/24 \
    dst 192.168.1.0/24 \
    dir in \
    tmpl src 10.0.0.2 dst 10.0.0.1 proto esp mode tunnel
```

### Listing Policies

```bash
ip xfrm policy list        # List all policies
ip xfrm policy show        # Same as list
ip xfrm policy show src 192.168.1.0/24  # Filter by source
ip xfrm policy show dst 192.168.2.0/24  # Filter by destination
```

### Deleting a Policy

```bash
ip xfrm policy delete src <SRC> dst <DST> dir <DIR>
# Or simplified form (when matching by destination and direction only):
ip xfrm policy delete dst <DST> dir <DIR>
```

**Examples:**

```bash
# Full form (matches specific source and destination)
ip xfrm policy delete src 192.168.1.0/24 dst 192.168.2.0/24 dir out

# Simplified form (matches any source for the destination and direction)
ip xfrm policy delete dst 192.168.2.0/24 dir out
```

**Note:** The simplified form (`dst` and `dir` only) is useful when you want to delete all policies matching a destination and direction, regardless of source. The full form is more specific and only deletes policies matching all specified selectors.

### Flushing Policies

```bash
ip xfrm policy flush       # Delete all policies
```

**Warning:** This removes ALL policies. Use with extreme caution in production.

## Security Associations (SAs)

### Basic Syntax

```bash
ip xfrm state { add | update | delete | get | flush | list | show | monitor } [ OPTIONS ]
```

### Adding a State (SA)

```bash
ip xfrm state add src <SRC> dst <DST> proto <PROTO> spi <SPI> [ OPTIONS ]
```

**Required Parameters:**
- `src <SRC>` - Source IP address
- `dst <DST>` - Destination IP address
- `proto <PROTO>` - Protocol: `esp` or `ah`
- `spi <SPI>` - Security Parameter Index (hex format: `0x12345678` or decimal)

**Common Options:**
- `mode <MODE>` - `tunnel` or `transport`
- `auth <ALGO> <KEY>` - Authentication algorithm and key
  - Examples: `hmac(sha1)`, `hmac(sha256)`, `hmac(sha512)`
- `enc <ALGO> <KEY>` - Encryption algorithm and key
  - Examples: `cbc(aes)`, `ctr(aes)`, `gcm(aes)`
- `aead <ALGO> <KEY> <ICV_LEN>` - Authenticated encryption (combined auth+enc)
  - Example: `aead 'rfc4106(gcm(aes))' <KEY> 128`
- `mark <VALUE>/<MASK>` - Mark selector (for policy matching)
- `reqid <ID>` - Request ID (links SA to policy template)
- `replay-window <SIZE>` - Anti-replay window size
- `lifetime <TYPE> <VALUE>` - Lifetime limits
  - Types: `soft`, `hard`, `current`
  - Values: `bytes <COUNT>`, `packets <COUNT>`, `time <SECONDS>`

**Example - ESP with Separate Auth and Enc:**

```bash
ip xfrm state add \
    src 10.0.0.1 \
    dst 10.0.0.2 \
    proto esp \
    spi 0x100 \
    mode tunnel \
    auth hmac(sha256) 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef \
    enc cbc(aes) 0xabcdef1234567890abcdef1234567890
```

**Example - ESP with AEAD (GCM):**

```bash
ip xfrm state add \
    src 10.0.0.1 \
    dst 10.0.0.2 \
    proto esp \
    spi 0x100 \
    mode tunnel \
    aead 'rfc4106(gcm(aes))' 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef 128
```

**Example - With Mark Selector:**

```bash
ip xfrm state add \
    src 10.0.0.1 \
    dst 10.0.0.2 \
    proto esp \
    spi 0x100 \
    mode tunnel \
    mark 0x1/0xffffffff \
    auth hmac(sha256) <KEY> \
    enc cbc(aes) <KEY>
```

### Listing States

```bash
ip xfrm state list         # List all SAs
ip xfrm state show         # Same as list
ip xfrm state show src 10.0.0.1  # Filter by source
ip xfrm state show dst 10.0.0.2  # Filter by destination
```

**With Statistics:**

```bash
ip -s xfrm state show      # Include statistics (byte/packet counters)
ip -s xfrm state list     # Same as above
```

The `-s` flag provides additional information including:
- Byte counters (current, soft limit, hard limit)
- Packet counters (current, soft limit, hard limit)
- Time-based lifetime information
- Replay window statistics

**Note:** On some systems, the `-s` flag may not be supported or may behave differently. Always have a fallback:

```bash
# Try with statistics first, fall back to regular output
if ! ip -s xfrm state show 2>/dev/null; then
    ip xfrm state show
fi
```

**Exit Code Behavior:** `ip xfrm state` returns exit code 0 even when no SAs exist (just empty output). To detect actual command errors, check for error messages in the output:

```bash
output=$(ip xfrm state 2>&1)
if echo "$output" | grep -qE "(error|Error|ERROR|failed|Failed|FAILED|No such|Permission denied)"; then
    echo "Command failed"
fi
```

### Getting a Specific State

```bash
ip xfrm state get src <SRC> dst <DST> proto <PROTO> spi <SPI> [ mark <VALUE> mask <MASK> ]
```

**Example:**

```bash
ip xfrm state get src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100
```

**Note:** If the SA has a mark selector, you must include it in the get command using **separate `mark` and `mask` parameters**:

```bash
ip xfrm state get src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100 mark 0x1 mask 0xffffffff
```

**Important:** The mark format in `ip xfrm` output shows as `mark 0x<value>/0x<mask>`, but when using it in commands (`get`, `delete`), you must use separate parameters: `mark <value> mask <mask>`, not `mark <value>/<mask>`.

### Deleting a State

```bash
ip xfrm state delete src <SRC> dst <DST> proto <PROTO> spi <SPI> [ mark <VALUE> mask <MASK> ]
```

**Example:**

```bash
ip xfrm state delete src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100
```

**Important:** If the SA was created with a mark selector, you **must** include it in the delete command using **separate `mark` and `mask` parameters**, otherwise deletion will fail silently or return an error:

```bash
# Correct format: separate mark and mask parameters
ip xfrm state delete src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100 mark 0x1 mask 0xffffffff

# ❌ WRONG: Combined format will fail
ip xfrm state delete src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100 mark 0x1/0xffffffff
```

**Note:** The mark format in `ip xfrm state show` output appears as `mark 0x<value>/0x<mask>`, but commands require the format `mark <value> mask <mask>` (separate parameters).

### Flushing States

```bash
ip xfrm state flush        # Delete all SAs
```

**Warning:** This removes ALL SAs. This will break all active IPsec connections. Use with extreme caution.

## Common Operations

### Checking VPN Status

**List all SAs:**

```bash
ip xfrm state show
```

**List SAs with statistics (preferred for monitoring):**

```bash
ip -s xfrm state show
```

**Filter by peer IP (forward SAs):**

```bash
ip xfrm state show | grep -A 20 "dst 10.0.0.2"
```

**Filter by peer IP (reverse SAs):**

```bash
ip xfrm state show | grep -A 20 "^src 10.0.0.2"
```

**Get all SAs for a peer (both directions):**

```bash
# Using fixed-string matching for safety (validated IP)
ip xfrm state show | grep -F "dst 10.0.0.2" -A 20
ip xfrm state show | grep -E "^src 10.0.0.2" -A 20
```

**Count SAs for a peer:**

```bash
# Count by destination (forward SAs)
ip xfrm state show | grep -c "dst 10.0.0.2"

# Count by source (reverse SAs)  
ip xfrm state show | grep -c "^src 10.0.0.2"
```

**Check if SA exists (robust method):**

```bash
# Check both forward and reverse, handle empty output
output=$(ip xfrm state show 2>&1)
if echo "$output" | grep -qE "(error|Error|ERROR|failed|Failed|FAILED)"; then
    echo "Command failed"
elif echo "$output" | grep -q "dst 10.0.0.2"; then
    echo "SA exists"
else
    echo "No SA found"
fi
```

### Monitoring XFRM Events

```bash
ip xfrm monitor
```

This command runs continuously and displays real-time events:
- SA additions
- SA deletions
- SA updates
- Policy changes

Press `Ctrl+C` to stop monitoring.

### Checking Policies

**List all policies:**

```bash
ip xfrm policy show
```

**Count policies:**

```bash
ip xfrm policy show | grep -c "^src"
```

### Combining Commands

**Check if SA exists for a peer:**

```bash
if ip xfrm state show | grep -q "dst 10.0.0.2"; then
    echo "SA exists"
else
    echo "No SA found"
fi
```

**Extract byte counter for a specific SA:**

```bash
ip -s xfrm state show | grep -A 10 "dst 10.0.0.2" | grep "lifetime current:" -A 2 | grep bytes
```

## Output Format Reference

### State (SA) Output Format

**Basic format (`ip xfrm state show`):**

```
src 10.0.0.1 dst 10.0.0.2
    proto esp spi 0x00000100 reqid 1 mode tunnel
    replay-window 0
    mark 0x1/0xffffffff
    auth-trunc hmac(sha256) 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef 96
    enc cbc(aes) 0xabcdef1234567890abcdef1234567890
    anti-replay context: seq 0x0, oseq 0x0, bitmap 0x00000000
    lifetime config:
       limit: soft (INF)(bytes), hard (INF)(bytes)
       limit: soft (INF)(packets), hard (INF)(packets)
       add 2026-01-03 12:19:25 use 2026-01-03 12:19:34
    lifetime current:
      39492(bytes), 609(packets)
      add 2026-01-03 12:19:25 use 2026-01-03 12:19:34
    stats:
      replay-window 0 replay 0 failed 0
```

**Key Fields:**
- `src` / `dst` - Source and destination IP addresses
- `proto` - Protocol (esp or ah)
- `spi` - Security Parameter Index (hex format)
- `reqid` - Request ID (links to policy template)
- `mode` - `tunnel` or `transport`
- `mark` - Mark selector (if present)
- `auth-trunc` or `auth` - Authentication algorithm
- `enc` - Encryption algorithm
- `lifetime config:` - Configured lifetime limits
- `lifetime current:` - Current usage (bytes, packets, timestamps)
- `stats:` - Statistics (replay window, replay events, failures)

**With Statistics (`ip -s xfrm state show`):**

The `-s` flag adds the same information but may provide additional detail in the statistics section.

### Policy Output Format

**Basic format (`ip xfrm policy show`):**

```
src 192.168.1.0/24 dst 192.168.2.0/24
    dir out priority 0 ptype main
    tmpl src 10.0.0.1 dst 10.0.0.2
        proto esp reqid 1 mode tunnel
    mark 0x1/0xffffffff
```

**Key Fields:**
- `src` / `dst` - Source and destination networks/addresses
- `dir` - Direction (`in`, `out`, `fwd`)
- `priority` - Policy priority (lower = higher priority)
- `ptype` - Policy type (`main` or `sub`)
- `tmpl` - Template for SA matching
  - `src` / `dst` - Tunnel endpoints
  - `proto` - Protocol (esp or ah)
  - `reqid` - Request ID (must match SA reqid)
  - `mode` - `tunnel` or `transport`
- `mark` - Mark selector (if present)
- `action` - Policy action (if specified)

### Parsing Tips

**Extract byte counter:**

The byte counter appears in the `lifetime current:` section. On UDM OS 4.3+, the format is:

```
lifetime current:
  39492(bytes), 609(packets)
  add 2026-01-03 12:19:25 use 2026-01-03 12:19:34
```

The bytes value is the number before `(bytes)` on the line following `lifetime current:`. Use `grep` with context lines to capture this multi-line format:

```bash
# Get context lines to capture the bytes line (appears after "lifetime current:")
ip -s xfrm state show | grep -A 5 "lifetime current:" | grep -E "[0-9]+\(bytes\)"
```

**Parsing Pattern:** The bytes value appears on the line immediately following `lifetime current:`, with indentation. Use regex to extract: `([0-9]+)\(bytes\)`.

**Extract SPI:**

The SPI appears on the same line as `proto` and `spi`. SPI can be in hex format (`0x12345678`) or decimal format (`12345678`):

```bash
# Extract SPI (handles both hex and decimal)
ip xfrm state show | grep -i "spi" | head -1 | sed -n 's/.*[[:space:]]spi[[:space:]]*\(0x[0-9a-fA-F]\+\|[0-9]\+\)[[:space:]].*/\1/p'
```

**Extract mark (if present):**

The mark appears on its own line (may be indented). Format: `mark 0x<value>/0x<mask>`:

```bash
# Extract mark value and mask (format: "mark 0x1/0xffffffff")
ip xfrm state show | grep "mark" | head -1 | sed -n 's/.*mark[[:space:]]*\(0x[0-9a-fA-F]\+\)\/\(0x[0-9a-fA-F]\+\)/\1 \2/p'
```

**Extract all SA selectors (src, dst, proto, spi, mark):**

```bash
# Parse complete SA block
ip xfrm state show | awk '
    /^src/ {src=$2; dst=$4; next}
    /proto.*spi/ {proto=$2; spi=$4; next}
    /mark/ {mark=$2; next}
    /^src/ && src && dst && proto && spi {print src, dst, proto, spi, (mark ? mark : "none"); src=dst=proto=spi=mark=""}
'
```

## Advanced Features

### Mark Selectors

Marks are 32-bit values used to tag packets and SAs for policy matching. They're useful for:
- Multi-tenant VPN configurations
- Policy-based routing
- Differentiating between multiple VPN connections

**Adding mark to SA:**

```bash
ip xfrm state add \
    src 10.0.0.1 dst 10.0.0.2 \
    proto esp spi 0x100 \
    mark 0x1/0xffffffff \
    mode tunnel \
    auth hmac(sha256) <KEY> \
    enc cbc(aes) <KEY>
```

**Important Format Difference:** When a SA has a mark, you **must** include it in `get` and `delete` commands, but use **separate parameters**:

- **In output:** `mark 0x1/0xffffffff` (combined format)
- **In commands:** `mark 0x1 mask 0xffffffff` (separate parameters)

**Examples:**

```bash
# Get SA with mark (use separate mark and mask)
ip xfrm state get src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100 mark 0x1 mask 0xffffffff

# Delete SA with mark (use separate mark and mask)
ip xfrm state delete src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100 mark 0x1 mask 0xffffffff
```

**Parsing Mark from Output:** When parsing mark from `ip xfrm state show` output, extract the combined format `0x<value>/0x<mask>`, then split it for use in commands:

```bash
# Extract mark from output (format: "mark 0x1/0xffffffff")
mark_line=$(ip xfrm state show | grep "mark" | head -1)
if [[ "$mark_line" =~ mark[[:space:]]+(0x[0-9a-fA-F]+)/(0x[0-9a-fA-F]+) ]]; then
    mark_value="${BASH_REMATCH[1]}"  # 0x1
    mark_mask="${BASH_REMATCH[2]}"   # 0xffffffff
    # Use in command: mark "$mark_value" mask "$mark_mask"
fi
```

### Request IDs (reqid)

Request IDs link policies to SAs. When a policy template specifies a `reqid`, only SAs with matching `reqid` values will be used.

**Setting reqid on SA:**

```bash
ip xfrm state add \
    src 10.0.0.1 dst 10.0.0.2 \
    proto esp spi 0x100 \
    reqid 1 \
    mode tunnel \
    auth hmac(sha256) <KEY> \
    enc cbc(aes) <KEY>
```

**Matching policy template:**

```bash
ip xfrm policy add \
    src 192.168.1.0/24 dst 192.168.2.0/24 \
    dir out \
    tmpl src 10.0.0.1 dst 10.0.0.2 proto esp reqid 1 mode tunnel
```

### Policy Priorities

Policies are evaluated in priority order (lower number = higher priority). When multiple policies match, the one with the highest priority (lowest number) is used.

**Setting priority:**

```bash
ip xfrm policy add \
    src 192.168.1.0/24 dst 192.168.2.0/24 \
    dir out \
    priority 100 \
    tmpl src 10.0.0.1 dst 10.0.0.2 proto esp mode tunnel
```

### Lifetime Management

SAs have configurable lifetimes based on:
- Bytes transferred
- Packets transferred
- Time elapsed

**Setting byte limit:**

```bash
ip xfrm state add \
    src 10.0.0.1 dst 10.0.0.2 \
    proto esp spi 0x100 \
    mode tunnel \
    lifetime soft bytes 1000000 \
    lifetime hard bytes 2000000 \
    auth hmac(sha256) <KEY> \
    enc cbc(aes) <KEY>
```

**Setting time limit:**

```bash
ip xfrm state add \
    src 10.0.0.1 dst 10.0.0.2 \
    proto esp spi 0x100 \
    mode tunnel \
    lifetime soft time 3600 \
    lifetime hard time 7200 \
    auth hmac(sha256) <KEY> \
    enc cbc(aes) <KEY>
```

When soft limits are reached, the SA is marked for rekeying. When hard limits are reached, the SA expires and is removed.

### Anti-Replay Protection

Anti-replay protection prevents replay attacks by tracking sequence numbers.

**Setting replay window:**

```bash
ip xfrm state add \
    src 10.0.0.1 dst 10.0.0.2 \
    proto esp spi 0x100 \
    mode tunnel \
    replay-window 32 \
    auth hmac(sha256) <KEY> \
    enc cbc(aes) <KEY>
```

The replay window size determines how many out-of-order packets are accepted.

## Troubleshooting

### Common Issues

**1. SA deletion fails silently**

**Problem:** `ip xfrm state delete` returns success but SA still exists.

**Solution:** Check if the SA has a mark selector. If so, include it in the delete command using **separate `mark` and `mask` parameters**:

```bash
# Check for mark in output (format: "mark 0x1/0xffffffff")
mark_info=$(ip xfrm state show | grep -A 5 "dst 10.0.0.2" | grep "mark" | head -1)

# Parse mark value and mask
if [[ "$mark_info" =~ mark[[:space:]]+(0x[0-9a-fA-F]+)/(0x[0-9a-fA-F]+) ]]; then
    mark_value="${BASH_REMATCH[1]}"
    mark_mask="${BASH_REMATCH[2]}"
    # Delete with mark (use separate parameters)
    ip xfrm state delete src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100 mark "$mark_value" mask "$mark_mask"
else
    # Delete without mark
    ip xfrm state delete src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100
fi
```

**2. No SAs found but VPN should be active**

**Possible causes:**
- SAs haven't been established yet (IKE negotiation in progress)
- SAs exist but with different selectors (check mark, reqid)
- Wrong IP address (check both tunnel endpoints)

**Debugging:**

```bash
# Check all SAs
ip xfrm state show

# Check policies
ip xfrm policy show

# Check IKE status (if using StrongSwan/Libreswan)
ipsec status
```

**3. Byte counters not incrementing**

**Possible causes:**
- No traffic flowing through the SA
- SA is not being used (policy mismatch)
- SA expired or removed

**Debugging:**

```bash
# Check current byte counters
ip -s xfrm state show | grep -A 5 "lifetime current:"

# Monitor for changes
watch -n 1 'ip -s xfrm state show | grep -A 5 "lifetime current:"'
```

**4. Policy not matching traffic**

**Possible causes:**
- Wrong source/destination in policy selector
- Wrong direction (in vs out)
- Priority too low (another policy matches first)
- Missing or incorrect template
- Mark selector mismatch (policy has mark but SA doesn't, or vice versa)

**Debugging:**

```bash
# List all policies with details
ip xfrm policy show -d

# Check policy priority
ip xfrm policy show | grep -A 10 "dst 192.168.2.0/24"

# Check for mark selectors in policies
ip xfrm policy show | grep -B 5 -A 10 "mark"

# Verify policy template matches SA reqid
ip xfrm policy show | grep "reqid"
ip xfrm state show | grep "reqid"
```

### Diagnostic Commands

**Check XFRM statistics:**

```bash
cat /proc/net/xfrm_stat
```

This shows kernel-level XFRM statistics including:
- Policy lookups
- Policy misses
- SA lookups
- SA misses
- Various error counters
- Replay window violations
- Authentication failures
- Encryption failures

**Interpretation:** High miss counts indicate policies/SAs not matching traffic. High error counts indicate configuration or key issues.

**Check system logs:**

```bash
dmesg | grep xfrm
journalctl -k | grep xfrm
```

**Verify command availability:**

```bash
which ip
ip -V  # Version information
```

## Best Practices

### 1. Always Use Statistics Flag for Monitoring

When checking SA status for monitoring purposes, use the `-s` flag to get byte/packet counters:

```bash
ip -s xfrm state show
```

### 2. Handle Both Command Variants

Some systems may not support `-s` flag. Always have a fallback. Also check for error messages in output, as `ip xfrm state` returns exit code 0 even when no SAs exist:

```bash
# Try with statistics first
output=$(ip -s xfrm state 2>&1)
exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    # Check for error messages in output (command may succeed but return errors)
    if echo "$output" | grep -qE "(error|Error|ERROR|failed|Failed|FAILED|No such|Permission denied)"; then
        # Command failed - try without -s flag
        output=$(ip xfrm state 2>&1)
    fi
    # Check if we have actual output (not just empty/whitespace)
    if [[ -n "${output//[[:space:]]/}" ]]; then
        echo "$output"
    fi
else
    # Try without -s flag
    ip xfrm state
fi
```

### 3. Parse Output Robustly

The output format can vary slightly between kernel versions. Use flexible parsing with context lines to capture multi-line sections:

```bash
# Get context lines to capture multi-line sections (lifetime current: appears on one line, bytes on next)
ip -s xfrm state show | grep -A 5 "lifetime current:"

# Extract bytes with regex (handles various formats)
ip -s xfrm state show | grep -A 5 "lifetime current:" | grep -E "[0-9]+\(bytes\)" | head -1

# Validate extracted value is numeric
bytes=$(ip -s xfrm state show | grep -A 5 "lifetime current:" | grep -oE "[0-9]+\(bytes\)" | grep -oE "^[0-9]+")
if [[ -n "$bytes" ]] && [[ "$bytes" =~ ^[0-9]+$ ]]; then
    echo "Byte counter: $bytes"
fi
```

**UDM OS 4.3+ Format:** The `lifetime current:` section uses this multi-line format:
```
lifetime current:
  39492(bytes), 609(packets)
  add 2026-01-03 12:19:25 use 2026-01-03 12:19:34
```

Always use context lines (e.g., `grep -A 5`) to capture the bytes line that appears after `lifetime current:`.

### 4. Include All Selectors When Deleting

When deleting SAs, always include all selectors (especially mark) that were used when creating the SA. **Remember to use separate `mark` and `mask` parameters in commands:**

```bash
# First, get the exact SA to see all selectors
ip xfrm state get src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100

# Parse mark from output if present (format: "mark 0x1/0xffffffff")
mark_line=$(ip xfrm state show | grep -A 5 "dst 10.0.0.2" | grep "mark" | head -1)
if [[ "$mark_line" =~ mark[[:space:]]+(0x[0-9a-fA-F]+)/(0x[0-9a-fA-F]+) ]]; then
    mark_value="${BASH_REMATCH[1]}"
    mark_mask="${BASH_REMATCH[2]}"
    # Delete with mark (separate parameters)
    ip xfrm state delete src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100 mark "$mark_value" mask "$mark_mask"
else
    # Delete without mark
    ip xfrm state delete src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x100
fi
```

### 5. Filter Output Carefully

When filtering by IP address, be aware that:
- IPv6 addresses may appear in different formats (compressed or expanded)
- Tunnel endpoints may differ from policy selectors
- Multiple SAs may exist for the same peer (different SPIs, especially during rekeying)
- SAs are bidirectional - check both `src` and `dst` for a peer IP

```bash
# Filter by destination (tunnel endpoint) - forward SAs
ip xfrm state show | grep "dst 10.0.0.2" -A 20

# Filter by source (tunnel endpoint) - reverse SAs
ip xfrm state show | grep "^src 10.0.0.2" -A 20

# Get all SAs for a peer (both forward and reverse)
ip xfrm state show | grep -E "(src|dst) 10.0.0.2" -A 20

# Count SAs (each SA block starts with "^src")
ip xfrm state show | grep -c "^src"

# Deduplicate SA blocks (important when querying both forward and reverse)
# Multiple SAs can have same src/dst but different SPIs
ip xfrm state show | awk '/^src/ {print; getline; while (/^[[:space:]]/) {print; getline}}'
```

### 6. Don't Flush in Production

Never use `ip xfrm state flush` or `ip xfrm policy flush` in production without understanding the impact. These commands remove ALL SAs/policies and will break all active IPsec connections.

### 7. Use Monitoring for Debugging

When troubleshooting, use `ip xfrm monitor` to see real-time changes:

```bash
ip xfrm monitor
```

This helps identify when SAs are added/removed and can reveal timing issues.

### 8. Coordinate with IPsec Daemons

If using StrongSwan, Libreswan, or other IPsec daemons:
- They manage SAs automatically via IKE (Internet Key Exchange)
- Manual SA deletion may trigger rekeying (daemon detects SA missing and re-establishes)
- Check daemon status: `ipsec status` or `strongswan status`
- Daemons will recreate SAs after manual deletion (usually within seconds)
- Use `ip xfrm monitor` to watch SA lifecycle during daemon operations

### 9. Handle IPv6 Addresses

IPv6 addresses can appear in different formats (compressed or expanded). When filtering or parsing:

```bash
# Use fixed-string matching when possible (after IP validation)
ip xfrm state show | grep -F "dst 2001:db8::1"

# For regex matching, validate IP first to prevent injection
if validate_ipv6 "$peer_ip"; then
    ip xfrm state show | grep -E "dst $peer_ip"
fi
```

### 10. Deduplicate SA Blocks

When querying both forward and reverse SAs for a peer, you may get duplicate SA blocks. Deduplicate using a composite key (src+dst+spi):

```bash
# Deduplicate by src+dst+spi (not just src+dst)
ip xfrm state show | awk '
    /^src/ {key=$0; spi=""; next}
    /spi/ {if (spi=="") {match($0, /spi[[:space:]]+(0x[0-9a-fA-F]+|[0-9]+)/); spi=substr($0, RSTART, RLENGTH); gsub(/^spi[[:space:]]+/, "", spi)}}
    /^src/ && key && spi {seen[key"|"spi]++; if (seen[key"|"spi]==1) print key}
'
```

## References

### Official Documentation

- **ip-xfrm man page:** `man ip-xfrm` or [man7.org](https://man7.org/linux/man-pages/man8/ip-xfrm.8.html)
- **iproute2 documentation:** [wiki.linuxfoundation.org](https://wiki.linuxfoundation.org/networking/iproute2)
- **Linux Kernel XFRM documentation:** [kernel.org](https://www.kernel.org/doc/html/latest/networking/xfrm_proc.html)

### Related Commands

- `ipsec status` - Check IPsec daemon status (StrongSwan/Libreswan)
- `strongswan statusall` - Detailed StrongSwan status
- `cat /proc/net/xfrm_stat` - Kernel XFRM statistics

### Additional Resources

- **IPsec Protocol:** RFC 4301 (Security Architecture), RFC 4303 (ESP), RFC 4302 (AH)
- **IKE Protocol:** RFC 7296 (IKEv2)
- **XFRM Framework:** Linux kernel source documentation

---

**Last Updated:** 2026-01-03  
**Tested On:** UDM OS 4.3+  
**iproute2 Version:** Varies by UDM OS version
