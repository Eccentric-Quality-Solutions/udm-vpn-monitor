# IPsec Guide

A comprehensive guide to understanding and using IPsec (Internet Protocol Security) for VPN monitoring and management on UDM OS.

## Table of Contents

1. [Overview](#overview)
2. [IPsec Architecture](#ipsec-architecture)
3. [Key Concepts](#key-concepts)
4. [Linux Kernel IPsec (XFRM)](#linux-kernel-ipsec-xfrm)
5. [User-Space IPsec Tools](#user-space-ipsec-tools)
6. [Common Commands](#common-commands)
7. [Practical Examples](#practical-examples)
8. [Troubleshooting](#troubleshooting)
9. [References](#references)

## Overview

IPsec (Internet Protocol Security) is a suite of protocols designed to secure IP communications by authenticating and encrypting each IP packet in a data stream. It operates at the network layer (Layer 3), providing end-to-end security for data transmitted over IP networks.

### Key Benefits

- **Confidentiality**: Encrypts data to prevent eavesdropping
- **Integrity**: Ensures data hasn't been tampered with in transit
- **Authentication**: Verifies the identity of communicating parties
- **Anti-replay**: Prevents attackers from replaying captured packets

## IPsec Architecture

### Components

IPsec consists of three main components:

1. **Authentication Header (AH)**
   - Provides data integrity and authenticity
   - Does NOT provide encryption (data remains visible)
   - Adds cryptographic checksum to each packet
   - Protects against tampering but not interception

2. **Encapsulating Security Payload (ESP)**
   - Provides confidentiality through encryption
   - Also provides data integrity and authenticity
   - Most commonly used in VPN implementations
   - Can operate in two modes:
     - **Transport Mode**: Encrypts only the payload (used for host-to-host)
     - **Tunnel Mode**: Encrypts entire IP packet (used for VPNs)

3. **Internet Key Exchange (IKE)**
   - Protocol for establishing Security Associations (SAs)
   - Negotiates cryptographic keys and algorithms
   - Operates in two phases:
     - **Phase 1 (IKE SA)**: Establishes secure authenticated channel
     - **Phase 2 (IPsec SA)**: Negotiates SAs for actual data transfer

### Modes of Operation

**Transport Mode**
- Encrypts only the payload of the IP packet
- Original IP header remains intact
- Typically used for end-to-end communication between hosts
- Lower overhead, but original source/destination visible

**Tunnel Mode**
- Encrypts the entire IP packet
- Encapsulates it within a new IP packet with new header
- Commonly used for VPNs (site-to-site, remote access)
- Hides original source/destination addresses
- Higher overhead but better security

## Key Concepts

### Security Associations (SAs)

A Security Association (SA) is a set of parameters that define how IPsec will secure traffic between two peers. Each SA includes:

- **Security Parameters Index (SPI)**: Unique identifier for the SA
- **Destination IP address**: Where the SA applies
- **Security protocol**: AH or ESP
- **Encryption algorithm**: e.g., AES-256, AES-128
- **Authentication algorithm**: e.g., SHA-256, SHA-1
- **Keys**: Encryption and authentication keys
- **Lifetime**: How long the SA is valid (time or byte count)

SAs are unidirectional - you need one SA for each direction (inbound and outbound).

### Security Policies (SPs)

Security Policies define which traffic should be protected by IPsec. They specify:

- Source and destination IP addresses/networks
- Protocol and ports
- Action: protect (apply IPsec), bypass, or discard
- Direction: inbound (in) or outbound (out)

### IKE Phases

**IKE Phase 1 (IKE SA)**
- Establishes a secure, authenticated channel between peers
- Authenticates peers (using pre-shared keys or certificates)
- Negotiates encryption and authentication algorithms
- Creates a secure channel for Phase 2 negotiations
- Can use Main Mode or Aggressive Mode

**IKE Phase 2 (IPsec SA)**
- Negotiates the actual SAs for data protection
- Uses the secure channel from Phase 1
- Can create multiple SAs (e.g., for different subnets)
- Typically uses Quick Mode
- Rekeys periodically to maintain security

## Linux Kernel IPsec (XFRM)

Linux implements IPsec in the kernel using the XFRM (Transform) framework. XFRM provides:

- **XFRM State**: Stores Security Associations (SAs)
- **XFRM Policy**: Stores Security Policies (SPs)

### XFRM State (Security Associations)

XFRM state represents the actual SAs in the kernel. Each SA includes:
- Source and destination IP addresses
- Protocol (ESP or AH)
- SPI (Security Parameters Index)
- Encryption/authentication algorithms
- Keys
- Lifetime (time and byte counters)

### XFRM Policy (Security Policies)

XFRM policies define which traffic should be protected:
- Source and destination addresses
- Protocol and ports
- Direction (inbound/outbound/forward)
- Action (protect, bypass, discard)
- Template (which SA to use)

### Key Commands

**View all Security Associations:**
```bash
ip xfrm state
# or
ip xfrm state show
# (both are equivalent)
```

**View Security Associations with statistics:**
```bash
ip -s xfrm state
# or
ip -s xfrm state show
# (both are equivalent)
```

**View Security Policies:**
```bash
ip xfrm policy
```

**Get specific SA:**
```bash
ip xfrm state get src <source_ip> dst <dest_ip> proto <protocol> spi <spi>
```

**Delete specific SA:**
```bash
ip xfrm state delete src <source_ip> dst <dest_ip> proto <protocol> spi <spi>
```

**Delete all policies for a destination:**
```bash
ip xfrm policy delete dst <peer_ip> dir <direction>
```

### XFRM Output Format

The `ip xfrm state` command output typically looks like:

```
src <source_ip> dst <dest_ip>
	proto esp spi <spi> reqid <reqid> mode tunnel
	replay-window <window>
	auth-trunc hmac(sha256) <auth_key> <trunc_len>
	aead rfc4106(gcm(aes)) <enc_key> <salt> <icv_len>
	lifetime config:
		limit: soft <soft_limit>bytes, hard <hard_limit>bytes
		limit: soft <soft_limit>packets, hard <hard_limit>packets
		limit: soft <soft_limit>add, hard <hard_limit>use
	lifetime current:
		<bytes>(bytes), <packets>(packets)
		add <timestamp> use <timestamp>
	stats:
		replay-window <window>
		replay <replay_count>
		failed <failed_count>
```

Key fields:
- **src/dst**: Source and destination IP addresses
- **proto**: Protocol (esp or ah)
- **spi**: Security Parameters Index (unique identifier)
- **lifetime current**: Current byte and packet counters
- **lifetime config**: Configured limits for SA lifetime

## User-Space IPsec Tools

While the kernel handles packet processing, user-space tools manage configuration and key exchange. Common implementations:

### strongSwan

strongSwan is a popular open-source IPsec implementation for Linux. It provides:

- IKEv1 and IKEv2 support
- Certificate-based authentication
- Pre-shared key authentication
- X.509 certificate management
- Configuration via `/etc/ipsec.conf` and `/etc/ipsec.secrets`

**Common strongSwan commands:**
```bash
ipsec status          # Show connection status
ipsec statusall        # Show detailed status (strongSwan specific)
ipsec reload           # Reload configuration
ipsec restart          # Restart IPsec service
ipsec up <conn_name>   # Bring up a connection
ipsec down <conn_name> # Bring down a connection
```

**Note:** The VPN monitor primarily uses `ipsec status` (with timeout). The `statusall` command is implementation-specific and may not be available on all systems.

### Libreswan

Libreswan is a fork of Openswan, another popular IPsec implementation. It provides:

- IKEv1 and IKEv2 support
- Similar command interface to strongSwan
- Configuration via `/etc/ipsec.conf` and `/etc/ipsec.secrets`

**Common Libreswan commands:**
```bash
ipsec status           # Show connection status
ipsec statusall        # Show detailed status (Libreswan format, may vary)
ipsec reload           # Reload configuration
ipsec restart          # Restart IPsec service
ipsec auto --up <conn> # Bring up a connection
ipsec auto --down <conn> # Bring down a connection
```

**Note:** The VPN monitor primarily uses `ipsec status` (with timeout). The `statusall` command output format may differ between implementations.

### Command Differences

Both strongSwan and Libreswan use the `ipsec` command, but output formats differ:

**strongSwan status output:**
```
Security Associations (1 up, 0 connecting):
  conn-name[1]: ESTABLISHED 1 hour ago, <peer_ip>...<local_ip>
```

**Libreswan status output:**
```
conn-name: ESTABLISHED 1 hour ago, <peer_ip>...<local_ip>
```

## Common Commands

### Command Availability Checking

Before using IPsec commands, always check if they're available:

```bash
# Check if ipsec command exists
if command -v ipsec >/dev/null 2>&1; then
    ipsec status
else
    echo "ipsec command not available"
fi

# Check if ip command supports xfrm
if ip xfrm help >/dev/null 2>&1; then
    ip xfrm state show
else
    echo "ip xfrm not available"
fi
```

**Note:** The VPN monitor uses `check_command_available()` function for this purpose.

### Checking VPN Status

**1. Check XFRM State (Kernel-level, most reliable):**

The XFRM state command is the most reliable method for checking VPN status. Always try with statistics first, then fall back to basic command:

```bash
# Try with statistics first (provides byte counters)
# Note: The codebase uses 'ip xfrm state' (without 'show' - both work)
if ip -s xfrm state 2>/dev/null; then
    # Statistics available
    ip -s xfrm state
else
    # Fallback to basic command
    ip xfrm state
fi

# Filter for specific peer (with context lines for multi-line output)
ip xfrm state | grep -A 20 "dst <peer_ip>"

# Count SAs for a peer
ip xfrm state | grep -c "dst <peer_ip>"
```

**Important:** The `-s` flag may not be available on all systems. Always have a fallback.

**2. Check IPsec Status (User-space):**

The `ipsec status` command can hang indefinitely, so always use a timeout:

```bash
# With timeout (recommended - 5 seconds default)
if command -v timeout >/dev/null 2>&1; then
    ipsec_output=$(timeout 5 ipsec status 2>/dev/null || true)
    exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
        echo "ipsec status timed out"
    fi
else
    # Fallback if timeout not available
    ipsec_output=$(ipsec status 2>/dev/null || true)
fi

# View detailed status (implementation-specific, may not be available)
# strongSwan: ipsec statusall
# Libreswan: ipsec statusall (format may differ)
# Note: The VPN monitor primarily uses 'ipsec status' with timeout
```

**Note:** The VPN monitor uses `IPSEC_STATUS_TIMEOUT=5` seconds by default.

**3. Check XFRM Policies:**
```bash
# View all policies
ip xfrm policy
# or
ip xfrm policy show
# (both are equivalent)

# Filter for specific peer
ip xfrm policy | grep -A 5 "dst <peer_ip>"
```

### Recovery Operations

**1. Reload IPsec Configuration (Preferred Method):**

Always try reload first as it's less disruptive:

# Use full path if available, otherwise rely on PATH
# Note: In the codebase, this is _RECOVERY_IPSEC_PATH (internal variable)
ipsec_cmd="${_RECOVERY_IPSEC_PATH:-ipsec}"

# Attempt reload
if "$ipsec_cmd" reload >/dev/null 2>&1; then
    echo "Reload successful"
    # Wait for connections to re-establish
    sleep 3
    # Verify connections restored
    if ip xfrm state show | grep -q "dst <peer_ip>"; then
        echo "Connection verified"
    fi
else
    reload_exit_code=$?
    echo "Reload failed (exit code: $reload_exit_code), trying restart"
    # Fall through to restart
fi
```

**Characteristics:**
- Reloads configuration files without dropping existing connections
- Preferred method when possible (less disruptive)
- May not work if connections are in a bad state
- Exit code 0 on success, non-zero on failure

**2. Restart IPsec Service (Fallback Method):**

Use when reload fails:

```bash
# Note: In the codebase, this uses _RECOVERY_IPSEC_PATH (internal variable)
ipsec_cmd="ipsec"

if "$ipsec_cmd" restart >/dev/null 2>&1; then
    echo "Restart successful"
    # Wait for connections to re-establish
    sleep 3
    # Verify connections restored
    if ip xfrm state show | grep -q "dst <peer_ip>"; then
        echo "Connection verified"
    fi
else
    restart_exit_code=$?
    echo "Restart failed (exit code: $restart_exit_code)"
fi
```

**Characteristics:**
- Stops and restarts the IPsec service
- Drops all existing connections (affects ALL tunnels)
- More disruptive but more reliable for recovery
- Use when `ipsec reload` fails
- Always verify connections after restart

**3. Recovery Pattern (Reload with Restart Fallback):**

The VPN monitor uses this pattern:

```bash
# Note: In the codebase, this uses _RECOVERY_IPSEC_PATH (internal variable)
ipsec_cmd="ipsec"
recovery_method="ipsec_reload"

# Try reload first
if "$ipsec_cmd" reload >/dev/null 2>&1; then
    recovery_method="ipsec_reload"
    echo "Reload succeeded"
else
    reload_exit_code=$?
    echo "Reload failed (exit code: $reload_exit_code), trying restart"
    recovery_method="ipsec_restart"
    
    if "$ipsec_cmd" restart >/dev/null 2>&1; then
        echo "Restart succeeded"
    else
        restart_exit_code=$?
        echo "Both reload and restart failed"
        exit 1
    fi
fi

# Wait for connections to re-establish
sleep 3

# Verify connections are active
if ! ip xfrm state show | grep -q "dst <peer_ip>"; then
    echo "Warning: Recovery completed but SA not found"
fi
```

**4. Manual SA Deletion (XFRM Recovery):**

For surgical recovery of specific SAs:

```bash
# Delete specific SA (must include all selectors if present)
ip xfrm state delete src <src_ip> dst <dst_ip> proto esp spi <spi>

# If SA has a mark selector, include it:
ip xfrm state delete src <src_ip> dst <dst_ip> proto esp spi <spi> mark <value>/<mask>

# Get SA details first to see all selectors
ip xfrm state get src <src_ip> dst <dst_ip> proto esp spi <spi>
```

**Warning:** Manual SA deletion may trigger automatic rekeying by the IPsec daemon. See [IP_XFRM_GUIDE.md](IP_XFRM_GUIDE.md) for detailed XFRM operations.

### Monitoring and Diagnostics

**1. Monitor Byte Counters:**
```bash
# Watch byte counters change (indicates active traffic)
watch -n 1 'ip xfrm state -s | grep -A 5 "lifetime current"'
```

**2. Check for SA Rekey:**
```bash
# Compare current SPI with previous
current_spi=$(ip xfrm state | grep -A 1 "dst <peer_ip>" | grep "spi" | awk '{print $4}')
# Compare with stored value
```

**3. Verify Connection Health:**
```bash
# Check if SA exists
ip xfrm state | grep "dst <peer_ip>"

# Check if byte counters are increasing
ip xfrm state -s | grep -A 2 "lifetime current" | grep bytes
```

## Practical Examples

### Example 1: Check if VPN is Active

```bash
#!/bin/bash
PEER_IP="203.0.113.1"

# Method 1: Check XFRM state (most reliable)
if ip xfrm state | grep -q "dst $PEER_IP"; then
    echo "VPN active: SA found in kernel"
else
    echo "VPN inactive: No SA found"
fi

# Method 2: Check IPsec status (user-space)
if ipsec status | grep -q "$PEER_IP"; then
    echo "VPN active: Connection found in IPsec status"
else
    echo "VPN inactive: No connection found"
fi
```

### Example 2: Extract Byte Counter

The byte counter format on UDM OS 4.3+ is:
```
lifetime current:
  39492(bytes), 609(packets)
  add 2026-01-03 12:19:25 use 2026-01-03 12:19:34
```

**Robust extraction method (matches codebase pattern):**

```bash
#!/bin/bash
PEER_IP="203.0.113.1"

# Try with statistics first, fallback to basic
# Note: 'show' is optional - 'ip xfrm state' works the same
if ip -s xfrm state 2>/dev/null; then
    xfrm_output=$(ip -s xfrm state | grep -A 20 "dst $PEER_IP")
else
    xfrm_output=$(ip xfrm state | grep -A 20 "dst $PEER_IP")
fi

# Get lifetime section with context lines
lifetime_section=$(echo "$xfrm_output" | grep -A 5 "lifetime current:" | head -6)

if [[ -z "$lifetime_section" ]]; then
    echo "Byte counter not found: No lifetime section"
    exit 1
fi

# Extract bytes from line with "(bytes)" pattern
bytes_line=$(echo "$lifetime_section" | grep -E "[0-9]+\(bytes\)" | head -1)

if [[ -n "$bytes_line" ]]; then
    # Extract number before "(bytes)" using regex
    if [[ "$bytes_line" =~ ([0-9]+)\(bytes\) ]]; then
        bytes="${BASH_REMATCH[1]}"
    fi
fi

# Validate extracted value
if [[ -z "$bytes" ]] || [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
    echo "Byte counter not found: Invalid format"
    exit 1
fi

echo "$bytes"
```

**Simpler method (if format is consistent):**

```bash
#!/bin/bash
PEER_IP="203.0.113.1"

# Get xfrm output for peer with context
xfrm_output=$(ip -s xfrm state 2>/dev/null | grep -A 20 "dst $PEER_IP" || \
              ip xfrm state | grep -A 20 "dst $PEER_IP")

# Extract byte counter from "lifetime current:" section
bytes=$(echo "$xfrm_output" | grep -A 2 "lifetime current:" | grep "bytes" | \
        sed -n 's/.*\([0-9]*\)(bytes).*/\1/p')

if [[ -n "$bytes" ]] && [[ "$bytes" =~ ^[0-9]+$ ]]; then
    echo "Byte counter: $bytes"
else
    echo "Byte counter not found"
    exit 1
fi
```

### Example 3: Extract SPI

SPI can be in hex format (0x12345678) or decimal format (12345678). Handle both:

```bash
#!/bin/bash
PEER_IP="203.0.113.1"

# Get xfrm output for peer
xfrm_output=$(ip xfrm state | grep -A 10 "dst $PEER_IP")

# Find line containing "spi"
spi_line=$(echo "$xfrm_output" | grep -i "spi" | head -1)

if [[ -z "$spi_line" ]]; then
    echo "SPI not found"
    exit 1
fi

# Extract SPI (handles both hex 0x... and decimal formats)
if [[ "$spi_line" =~ ^[[:space:]]*proto[[:space:]]+[a-zA-Z0-9]+[[:space:]]+spi[[:space:]]+(0x[0-9a-fA-F]+|[0-9]+) ]]; then
    spi="${BASH_REMATCH[1]}"
elif [[ "$spi_line" =~ ^[[:space:]]*spi[[:space:]]+(0x[0-9a-fA-F]+|[0-9]+) ]]; then
    spi="${BASH_REMATCH[1]}"
else
    # Fallback: use awk (less reliable)
    spi=$(echo "$spi_line" | awk '{for(i=1;i<=NF;i++) if($i=="spi") print $(i+1)}')
fi

# Validate format
if [[ -z "$spi" ]] || [[ ! "$spi" =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]]; then
    echo "SPI not found: Invalid format"
    exit 1
fi

echo "$spi"
```

**Simpler method (if format is consistent):**

```bash
#!/bin/bash
PEER_IP="203.0.113.1"

# Get SPI from xfrm state (assumes consistent format)
spi=$(ip xfrm state | grep -A 1 "dst $PEER_IP" | grep "spi" | awk '{print $4}')

# Validate format
if [[ -n "$spi" ]] && [[ "$spi" =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]]; then
    echo "SPI: $spi"
else
    echo "SPI not found"
    exit 1
fi
```

### Example 4: Detect SA Rekey

```bash
#!/bin/bash
PEER_IP="203.0.113.1"
STORED_SPI_FILE="/tmp/stored_spi_${PEER_IP}"

# Get current SPI
current_spi=$(ip xfrm state | grep -A 1 "dst $PEER_IP" | grep "spi" | awk '{print $4}')

if [[ -z "$current_spi" ]]; then
    echo "No SA found"
    exit 1
fi

# Compare with stored SPI
if [[ -f "$STORED_SPI_FILE" ]]; then
    stored_spi=$(cat "$STORED_SPI_FILE")
    if [[ "$current_spi" != "$stored_spi" ]]; then
        echo "Rekey detected: $stored_spi -> $current_spi"
        echo "$current_spi" > "$STORED_SPI_FILE"
    else
        echo "No rekey: SPI unchanged ($current_spi)"
    fi
else
    echo "Storing initial SPI: $current_spi"
    echo "$current_spi" > "$STORED_SPI_FILE"
fi
```

### Example 5: Recovery via IPsec Reload (with Fallback)

This example matches the pattern used in the VPN monitor:

```bash
#!/bin/bash
PEER_IP="203.0.113.1"
LOCATION="NYC"
# Note: In the codebase, this uses _RECOVERY_IPSEC_PATH (internal variable)
# For examples, we use a simple variable name
ipsec_cmd="ipsec"
SLEEP_SECONDS=3  # Matches XFRM_RECOVERY_SLEEP_SECONDS in codebase

# Store recovery method
recovery_method="ipsec_reload"
command_succeeded=0
reload_exit_code=""
restart_exit_code=""

echo "Attempting ipsec reload for $LOCATION ($PEER_IP)"

# Try reload first
if "$ipsec_cmd" reload >/dev/null 2>&1; then
    command_succeeded=1
    recovery_method="ipsec_reload"
    echo "Successfully reloaded IPsec connections"
else
    reload_exit_code=$?
    echo "ipsec reload failed (exit code: $reload_exit_code), attempting restart"
    
    # Fallback to restart
    recovery_method="ipsec_restart"
    if "$ipsec_cmd" restart >/dev/null 2>&1; then
        command_succeeded=1
        echo "Successfully restarted IPsec service"
    else
        restart_exit_code=$?
        echo "ipsec restart also failed (exit code: $restart_exit_code)"
        exit 1
    fi
fi

# Wait for connections to re-establish
if [[ $command_succeeded -eq 1 ]]; then
    sleep "$SLEEP_SECONDS"
    
    # Verify connection restored
    if ip xfrm state | grep -q "dst $PEER_IP"; then
        echo "Recovery completed via $recovery_method: Connection verified (SA exists)"
    else
        echo "Warning: Recovery completed via $recovery_method but SA not found"
        exit 1
    fi
fi
```

**Key points:**
- Always try reload first (less disruptive)
- Fall back to restart if reload fails
- Capture exit codes for debugging
- Wait for connections to re-establish (3 seconds typical)
- Verify connections after recovery
- Note that reload/restart affects ALL tunnels, not just one peer

## Output Format Details

### XFRM State Output Format

The `ip xfrm state` output format on UDM OS 4.3+:

**Basic format:**
```
src 10.0.0.1 dst 10.0.0.2
    proto esp spi 0x00000100 reqid 1 mode tunnel
    replay-window 0
    auth-trunc hmac(sha256) <key> 96
    enc cbc(aes) <key>
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

**Key parsing points:**
- Byte counter is on the line after "lifetime current:" with format: `N(bytes), M(packets)`
- SPI can be hex (0x00000100) or decimal format
- Multiple SAs may exist for the same peer (different SPIs)
- Mark selectors may be present: `mark 0x1/0xffffffff`

For detailed XFRM command reference, see [IP_XFRM_GUIDE.md](IP_XFRM_GUIDE.md).

### IPsec Status Output Format

**strongSwan format:**
```
Security Associations (1 up, 0 connecting):
  conn-name[1]: ESTABLISHED 1 hour ago, 203.0.113.1...192.168.1.1
  conn-name[2]: ESTABLISHED 2 hours ago, 203.0.113.2...192.168.1.1
```

**Libreswan format:**
```
conn-name: ESTABLISHED 1 hour ago, 203.0.113.1...192.168.1.1
conn-name2: ESTABLISHED 2 hours ago, 203.0.113.2...192.168.1.1
```

**Parsing tips:**
- Use fixed-string matching (`grep -F`) for peer IP addresses
- Connection names may differ between implementations
- Status can show "ESTABLISHED", "CONNECTING", or connection name only

## Troubleshooting

### Common Issues

**1. SA exists but byte counters not increasing**

**Symptoms:**
- `ip xfrm state` shows SA exists
- Byte counters remain unchanged
- VPN appears "stuck" or "idle"

**Possible causes:**
- No traffic flowing through tunnel
- Routing issue preventing traffic
- Firewall blocking traffic
- Network partition

**Diagnosis:**
```bash
# Check if SA exists
ip xfrm state | grep "dst <peer_ip>"

# Check byte counters
ip xfrm state -s | grep -A 2 "lifetime current"

# Check routing
ip route | grep <peer_ip>

# Test connectivity (if internal IP known)
ping <internal_peer_ip>
```

**2. SA missing but IPsec status shows connection**

**Symptoms:**
- `ipsec status` shows connection established
- `ip xfrm state` shows no SA
- VPN appears down

**Possible causes:**
- SA expired and not rekeyed
- Kernel state out of sync with user-space
- IKE Phase 2 failed

**Diagnosis:**
```bash
# Check IPsec status
ipsec status

# Check XFRM state
ip xfrm state

# Check for errors in logs
journalctl -u ipsec | tail -50
```

**3. IPsec reload/restart fails**

**Symptoms:**
- `ipsec reload` or `ipsec restart` returns error
- Service may be hung or corrupted

**Possible causes:**
- Configuration file errors
- Service process hung
- Resource exhaustion

**Diagnosis:**
```bash
# Check service status
systemctl status ipsec

# Check for configuration errors
ipsec checkconfig

# Check process
ps aux | grep ipsec

# Check logs
journalctl -u ipsec | tail -100
```

**4. SA rekey issues**

**Symptoms:**
- SPI changes frequently
- Connections drop during rekey
- Rekey fails

**Possible causes:**
- IKE Phase 2 rekey timeout
- Key lifetime too short
- Network issues during rekey

**Diagnosis:**
```bash
# Monitor SPI changes
watch -n 1 'ip xfrm state | grep spi'

# Check rekey timing
ip xfrm state -s | grep lifetime
```

### Diagnostic Commands

**Check command availability:**
```bash
# Check if ipsec command exists
command -v ipsec

# Check if ip command supports xfrm
ip xfrm help

# Check IPsec service status
systemctl status ipsec
```

**Get detailed connection info:**
```bash
# strongSwan detailed status
ipsec statusall

# Libreswan detailed status  
ipsec statusall

# XFRM state with statistics
ip xfrm state -s
```

**Check for errors:**
```bash
# System logs
journalctl -u ipsec | grep -i error

# Kernel messages
dmesg | grep -i xfrm

# IPsec logs (location varies by implementation)
tail -f /var/log/ipsec.log

# Check XFRM kernel statistics
cat /proc/net/xfrm_stat
```

### Error Handling Patterns

**1. Command Timeout Handling:**

Network commands that interact with the kernel (via netlink sockets) can hang indefinitely. Always use timeouts:

**ipsec status:**
```bash
IPSEC_STATUS_TIMEOUT=5  # Default in codebase

if command -v timeout >/dev/null 2>&1; then
    ipsec_output=$(timeout "$IPSEC_STATUS_TIMEOUT" ipsec status 2>/dev/null || true)
    exit_code=$?
    
    # Timeout exit code is 124
    if [[ $exit_code -eq 124 ]]; then
        echo "ipsec status timed out after ${IPSEC_STATUS_TIMEOUT} seconds"
        # Handle timeout appropriately
    elif [[ $exit_code -ne 0 ]]; then
        echo "ipsec status failed with exit code: $exit_code"
    fi
else
    # Fallback if timeout not available (shouldn't happen on UDM)
    ipsec_output=$(ipsec status 2>/dev/null || true)
fi
```

**ip xfrm state:**
```bash
XFRM_STATE_TIMEOUT=5  # Default in codebase

if check_command_available "timeout"; then
    xfrm_output=$(timeout "${XFRM_STATE_TIMEOUT:-5}" ip -s xfrm state 2>&1)
    exit_code=$?
    
    # Timeout exit code is 124
    if [[ $exit_code -eq 124 ]]; then
        echo "ip xfrm state timed out after ${XFRM_STATE_TIMEOUT} seconds"
        # Handle timeout appropriately (fall back to ipsec status)
    elif [[ $exit_code -ne 0 ]]; then
        echo "ip xfrm state failed with exit code: $exit_code"
    fi
else
    # Fallback if timeout not available (shouldn't happen on UDM)
    xfrm_output=$(ip -s xfrm state 2>&1)
    exit_code=$?
fi
```

**Note:** Both `ipsec status` and `ip xfrm state` use netlink sockets which can hang during system stress (netlink socket timeouts, lock contention). Timeout protection is essential for production reliability.

**2. Reload with Restart Fallback:**

Always implement fallback pattern for recovery:

```bash
# Note: In the codebase, this uses _RECOVERY_IPSEC_PATH (internal variable)
ipsec_cmd="ipsec"
reload_exit_code=""
restart_exit_code=""

# Try reload first
if "$ipsec_cmd" reload >/dev/null 2>&1; then
    echo "Reload succeeded"
else
    reload_exit_code=$?
    echo "Reload failed (exit code: $reload_exit_code), trying restart"
    
    # Fallback to restart
    if "$ipsec_cmd" restart >/dev/null 2>&1; then
        echo "Restart succeeded"
    else
        restart_exit_code=$?
        echo "Both reload and restart failed"
        echo "Exit codes: reload=$reload_exit_code, restart=$restart_exit_code"
        exit 1
    fi
fi
```

**3. Output Parsing with Error Handling:**

Always handle empty or malformed output:

```bash
# Get xfrm output
xfrm_output=$(ip -s xfrm state show 2>/dev/null || ip xfrm state show 2>/dev/null)

# Check if output is empty
if [[ -z "$xfrm_output" ]]; then
    echo "No xfrm output - command may have failed or no SAs exist"
    exit 1
fi

# Filter for peer
peer_output=$(echo "$xfrm_output" | grep -A 20 "dst $PEER_IP")

# Check if peer found
if [[ -z "$peer_output" ]]; then
    echo "No SA found for peer $PEER_IP"
    exit 1
fi

# Extract value with validation
bytes=$(extract_byte_counter "$peer_output")
if [[ $? -ne 0 ]] || [[ -z "$bytes" ]]; then
    echo "Failed to extract byte counter"
    exit 1
fi
```

**4. Command Availability Checking:**

Always check if commands exist before using them:

```bash
# Check command availability
if ! command -v ipsec >/dev/null 2>&1; then
    echo "ipsec command not available"
    exit 1
fi

if ! command -v ip >/dev/null 2>&1; then
    echo "ip command not available"
    exit 1
fi

# Check if ip supports xfrm
if ! ip xfrm help >/dev/null 2>&1; then
    echo "ip xfrm not supported"
    exit 1
fi
```

## References

### Official Documentation

- **NIST Guide to IPsec VPNs**: Comprehensive guide to IPsec architecture and implementation
  - https://www.nist.gov/publications/guide-ipsec-vpns

- **Linux Kernel IPsec Documentation**: Kernel-level IPsec implementation details
  - https://docs.kernel.org/networking/ipsec.html

- **strongSwan Documentation**: User documentation for strongSwan
  - https://wiki.strongswan.org/projects/strongswan/wiki/UserDocumentation
  - https://www.strongswan.org/documentation.html

- **Libreswan Wiki**: Documentation for Libreswan
  - https://libreswan.org/wiki/

### RFCs

- **RFC 4301**: Security Architecture for the Internet Protocol
- **RFC 4302**: IP Authentication Header (AH)
- **RFC 4303**: IP Encapsulating Security Payload (ESP)
- **RFC 7296**: Internet Key Exchange Protocol Version 2 (IKEv2) - Current standard
- **RFC 4306**: Internet Key Exchange (IKEv2) Protocol - Obsoleted by RFC 7296
- **RFC 2409**: The Internet Key Exchange (IKE) - IKEv1

### Related Tools

- **iproute2**: Linux networking utilities (includes `ip xfrm`)
  - Documentation: `man ip-xfrm`

- **strongSwan**: Open-source IPsec implementation
  - Website: https://www.strongswan.org

- **Libreswan**: IPsec implementation for Linux
  - Website: https://libreswan.org

### UDM-Specific Notes

On UDM OS 4.3+, IPsec is typically managed through:
- User-space tools (strongSwan or Libreswan) via `ipsec` command
- Kernel XFRM framework via `ip xfrm` commands
- Configuration files: `/etc/ipsec.conf` and `/etc/ipsec.secrets`

The VPN monitor application uses both methods:
- **XFRM state** (`ip xfrm state`) for reliable SA detection and byte counter monitoring
- **IPsec status** (`ipsec status`) as a fallback when XFRM queries fail

### Best Practices from Codebase

**1. Always Use Timeouts for Network Commands:**
```bash
# ipsec status can hang - always use timeout
if command -v timeout >/dev/null 2>&1; then
    ipsec_output=$(timeout 5 ipsec status 2>/dev/null || true)
else
    ipsec_output=$(ipsec status 2>/dev/null || true)
fi
```

**2. Check Command Availability:**
```bash
# Before using commands, check if they exist
if ! command -v ipsec >/dev/null 2>&1; then
    echo "ipsec command not available"
    exit 1
fi
```

**3. Handle Both XFRM Command Variants:**
```bash
# Try with statistics first, fallback to basic
# Note: 'show' is optional - 'ip xfrm state' works the same
if ip -s xfrm state 2>/dev/null; then
    xfrm_output=$(ip -s xfrm state)
else
    xfrm_output=$(ip xfrm state)
fi
```

**4. Use Context Lines for Multi-line Parsing:**
```bash
# Get context lines to capture multi-line sections
xfrm_output=$(ip xfrm state | grep -A 20 "dst $PEER_IP")
lifetime_section=$(echo "$xfrm_output" | grep -A 5 "lifetime current:")
```

**5. Validate Extracted Values:**
```bash
# Always validate extracted values
if [[ -z "$bytes" ]] || [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
    echo "Invalid byte counter"
    exit 1
fi
```

**6. Reload Before Restart:**
```bash
# Always try reload first (less disruptive)
if ipsec reload >/dev/null 2>&1; then
    # Success
else
    # Fallback to restart
    ipsec restart
fi
```

**7. Verify After Recovery:**
```bash
# Always verify connections after recovery operations
sleep 3  # Wait for connections to re-establish (matches XFRM_RECOVERY_SLEEP_SECONDS)
if ip xfrm state | grep -q "dst $PEER_IP"; then
    echo "Recovery verified"
else
    echo "Warning: Recovery completed but SA not found"
fi
```

### Related Documentation

- **[IP_XFRM_GUIDE.md](IP_XFRM_GUIDE.md)**: Detailed guide to `ip xfrm` commands
- **[CODE_PATTERNS.md](../CODE_PATTERNS.md)**: Code patterns used in the VPN monitor
- **[DEVELOPER.md](../DEVELOPER.md)**: Development guidelines

---

**Last Updated**: 2026-01-13  
**Version**: 1.1
