# UDM Linux Tools Reference

This document lists Linux utilities available on UniFi Dream Machine (UDM) running OS 4.3+ that are used by the VPN monitor project.

## Available Tools

### Network Tools
- **ip** - Required for VPN detection (xfrm state checks) and network configuration
- **ss** - Socket statistics (alternative to netstat)
- **ipsec** - Required for recovery actions (Tier 2/3)
- **tcpdump** - Packet capture (for debugging)
- **netstat** - Network connections and statistics
- **ping** - Connectivity checks (IPv4)
- **ping6** - IPv6 connectivity checks (or use `ping -6`)

### System Monitoring
- **ps** - Process status
- **top** - Process monitor
- **htop** - Interactive process monitor (if available)
- **free** - Memory usage
- **uptime** - System uptime and load
- **df** - Disk space usage
- **nproc** - Number of processing units (CPU cores)

### DNS and Network Resolution
- **dig** - DNS lookup tool
- **nslookup** - DNS lookup (legacy)
- **getent** - Get entries from Name Service Switch libraries

### Text Processing
- **awk** - Pattern scanning and processing (used for floating-point math instead of bc)
- **sed** - Stream editor
- **grep** - Pattern matching
- **cut** - Extract columns from text
- **head** - Display first lines
- **tail** - Display last lines
- **sort** - Sort lines
- **uniq** - Remove duplicate lines

### System Utilities
- **date** - Date and time operations (supports `-d` flag for date arithmetic)
- **expr** - Evaluate expressions
- **stat** - File status (supports `-c` flag for format strings)
- **timeout** - Run command with timeout
- **watch** - Execute program periodically
- **dmesg** - Kernel ring buffer messages
- **crontab** - Cron job management
- **systemctl** - Systemd service management
- **systemd** - System and service manager

### Firewall and Security
- **iptables** - IPv4 firewall rules
- **iptables-save** - Save iptables rules

### Logging
- **logrotate** - Log rotation utility
- **journalctl** - Systemd journal viewer (for keepalive daemon logs)

## Tools NOT Available

These tools are **not** available on UDM OS 4.3+ and should not be used:

- **logread** - Not available (use `journalctl` or `dmesg` instead)
- **swanctl** - StrongSwan control utility (not available, use `ipsec` instead)
- **bc** - Calculator (use `awk` for floating-point math instead)

## Command-Specific Notes

### ping vs ping6
- Some systems have separate `ping6` command
- Others use `ping -6` for IPv6
- The codebase handles both cases with fallback logic

### date Command
- Supports `-d` flag for date arithmetic (Linux-specific)
- Format: `date -d "1 hour ago" +%s`
- **Note**: This is Linux-specific syntax, not POSIX

### stat Command
- Supports `-c` flag for custom format strings (Linux-specific)
- Format: `stat -c %Y <file>` for modification time
- **Note**: This is Linux-specific syntax, not POSIX

### PATH Restrictions
- In cron/systemd environments, PATH may be restricted
- Commands may not be in standard PATH locations
- The codebase includes fallback logic to check common system directories (`/usr/sbin`, `/usr/bin`, `/sbin`, `/bin`)

## Usage in Codebase

The VPN monitor project uses these tools for:

- **VPN Detection**: `ip xfrm state`, `ipsec status`
- **Connectivity Checks**: `ping`, `ping6` (with IPv4/IPv6 detection)
- **Resource Monitoring**: `free`, `df`, `nproc`, `ps`
- **Network Partition Detection**: `ip route`, `dig`, `ip link`
- **State Management**: `stat`, `date`, `awk`
- **Logging**: `tail`, `grep`, `journalctl`
- **Service Management**: `systemctl` (for keepalive daemon)