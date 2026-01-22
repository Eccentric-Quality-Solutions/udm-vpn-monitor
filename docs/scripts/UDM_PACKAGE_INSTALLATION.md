# Installing Packages on UniFi Dream Machine

**Date:** 2026-01-27  
**Purpose:** Guidance on installing custom packages (like `sshpass` and `expect`) on UDM systems

## Overview

UniFi Dream Machines run UniFi OS, which is based on Debian (OS 2.x/3.x) or Buildroot (OS 1.x). While `apt-get` is available on modern UDM OS versions, there are important considerations and risks when installing custom packages.

## Can You Install Packages on UDM?

### UDM OS 2.x/3.x (Debian-based)

**✅ Yes, with caveats:**
- `apt-get` is available and functional
- Standard Debian packages can be installed
- **Packages will NOT survive firmware updates** (system partition is overwritten)
- **Risk of system instability** if incompatible packages are installed

### UDM OS 1.x (Buildroot-based)

**❌ Limited support:**
- No standard package manager
- Manual binary installation required (not recommended)
- Higher risk of system issues

## Installing sshpass and expect

### Quick Installation

```bash
# Enter UniFi OS shell (if needed on some UDM versions)
unifi-os shell

# Update package lists
apt-get update

# Install sshpass and expect
apt-get install -y sshpass expect

# Verify installation
which sshpass expect
```

### Safety Assessment

**Risk Level: LOW to MODERATE**

**Why it's relatively safe:**
- ✅ `sshpass` and `expect` are standard Debian packages
- ✅ Lightweight utilities with minimal dependencies
- ✅ Similar to `nano` (which you've already installed successfully)
- ✅ Widely used by the community without major issues
- ✅ No kernel modifications or system-level changes

**Why there's some risk:**
- ⚠️ Not officially supported by Ubiquiti
- ⚠️ May conflict with future firmware updates
- ⚠️ Could potentially cause system instability (rare)
- ⚠️ Will be removed during firmware updates

### Community Practice

Many UDM users install standard Debian packages without issues:
- `nano` (text editor) - commonly installed
- `htop` (process monitor) - commonly installed
- `tcpdump` (packet capture) - commonly installed
- `sshpass`/`expect` - less common but used for automation

**If `nano` works on your UDM, `sshpass`/`expect` should work too.**

## Making Packages Persistent Across Firmware Updates

### The Problem

Packages installed via `apt-get` are stored on the system partition, which is overwritten during firmware updates. Only `/data` and `/etc` directories persist.

### The Solution: on-boot-script

The community-standard solution is the **on-boot-script** utility, which automatically reinstalls packages after firmware updates.

#### Installation (One-Time Setup)

**For UDM OS 2.x/3.x:**
```bash
curl -fsL "https://raw.githubusercontent.com/unifi-utilities/unifios-utilities/HEAD/on-boot-script-2.x/remote_install.sh" | /bin/bash
```

**For UDM OS 1.x (legacy):**
```bash
curl -fsL "https://raw.githubusercontent.com/unifi-utilities/unifios-utilities/HEAD/on-boot-script/remote_install.sh" | /bin/bash
```

#### Create Installation Script

Create a script in `/data/on_boot.d/` that reinstalls your packages:

```bash
# /data/on_boot.d/10-install-sshpass.sh
#!/bin/bash
# Reinstall sshpass and expect after firmware updates

apt-get update
apt-get install -y sshpass expect
```

Make it executable:
```bash
chmod +x /data/on_boot.d/10-install-sshpass.sh
```

This script will automatically run after each boot and firmware update, ensuring `sshpass` and `expect` are always available.

## Risks and Mitigations

### Risk 1: Firmware Update Wipe

**Risk:** Packages removed during firmware updates

**Mitigation:**
- Use on-boot-script to auto-reinstall
- Document which packages you've installed
- Reinstall manually if on-boot-script fails

### Risk 2: System Instability

**Risk:** Incompatible packages could cause system issues

**Mitigation:**
- Stick to standard Debian packages (like `sshpass`/`expect`)
- Avoid custom kernels or system-level modifications
- Test on non-production UDM first if possible
- Have a rollback plan (firmware reinstall)

### Risk 3: Package Conflicts

**Risk:** Packages may conflict with UniFi OS components

**Mitigation:**
- Use lightweight utilities with minimal dependencies
- Avoid packages that modify system services
- Monitor system logs after installation
- Uninstall if issues occur: `apt-get remove sshpass expect`

## Recommendations

### For Deployment Script Usage

**Option 1: Install on Source System (Recommended)**
- Install `sshpass`/`expect` on the **source system** (not UDM)
- UDM only receives deployments, doesn't run deployment script
- **Zero risk to UDM stability**
- **Best for most use cases**

**Option 2: Install on UDM (If Needed)**
- Only if you need UDM-to-UDM deployments
- Use on-boot-script for persistence
- Monitor for system issues
- **Low to moderate risk**

**Option 3: Manual Entry (Safest)**
- Don't install anything
- Use manual password entry (script falls back automatically)
- **Zero risk, but less convenient**

### Best Practices

1. **Test First:** If possible, test on a non-production UDM
2. **Use on-boot-script:** Ensure packages persist across updates
3. **Document:** Keep a list of installed packages
4. **Monitor:** Watch for system issues after installation
5. **Have a Plan:** Know how to rollback if needed

## Alternative: SSH Keys

**Best Practice:** Use SSH key authentication instead of passwords:
- More secure than password authentication
- No need for `sshpass` or `expect`
- Supported natively by SSH
- Can be configured in UniFi OS settings

However, if password authentication is required, `sshpass`/`expect` are reasonable options.

## Troubleshooting

### Package Installation Fails

```bash
# Check if apt-get is available
which apt-get

# Try updating package lists
apt-get update

# Check for errors
apt-get install -y sshpass 2>&1 | tee /tmp/install.log
```

### Package Missing After Firmware Update

```bash
# Check if on-boot-script is installed
systemctl status udm-boot

# Check boot scripts
ls -la /data/on_boot.d/

# Manually reinstall
apt-get update && apt-get install -y sshpass expect
```

### System Issues After Installation

```bash
# Remove packages
apt-get remove sshpass expect

# Check system logs
journalctl -xe

# Consider firmware reinstall if issues persist
```

## References

- [UniFi OS Utilities - on-boot-script](https://github.com/unifi-utilities/unifios-utilities/tree/main/on-boot-script-2.x)
- [UDM Firmware Upgrades Guide](https://github.com/unifi-utilities/unifios-utilities/wiki/UDM-Firmware-Upgrades)
- [Ubiquiti Community - Package Installation Discussions](https://community.ui.com/questions/Should-we-be-updating-the-OS-using-apt-get/a8ee9f67-203f-48cf-89e1-a80b3d0a7c61)
- [Deployment Analysis](./DEPLOYMENT_ANALYSIS.md)
