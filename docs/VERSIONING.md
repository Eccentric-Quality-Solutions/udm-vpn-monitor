# Versioning Guide

This document describes the versioning strategy used for the UDM VPN Monitor project.

## Semantic Versioning (SemVer)

This project follows [Semantic Versioning](https://semver.org/) (SemVer) principles:

- **MAJOR.MINOR.PATCH** format (e.g., `1.2.3`)
- **MAJOR**: Breaking changes that are incompatible with previous versions
- **MINOR**: New features that are backwards compatible
- **PATCH**: Bug fixes that are backwards compatible

## Pre-1.0.0 Versioning Strategy

During the pre-release phase (before `1.0.0`), we use the `0.MINOR.PATCH` format:

- **MINOR** increments for new features or significant changes
- **PATCH** increments for bug fixes
- **No limit on MINOR version**: You can go `0.1.0` → `0.2.0` → ... → `0.9.0` → `0.10.0` → `0.11.0` → ... → `0.199.0` → `1.0.0`

### Version Number Examples

```
0.1.0  → Initial release
0.1.1  → Bug fix release
0.2.0  → New feature release
0.2.1  → Bug fix release
0.3.0  → Another new feature release
...
0.9.0  → Feature release
0.10.0 → Feature release (no limit at 9!)
0.11.0 → Feature release
...
0.99.0 → Feature release
1.0.0  → Production-ready release
```

## When to Increment Versions

### PATCH (0.x.1 → 0.x.2)
- Bug fixes
- Security patches
- Documentation corrections
- Minor refactoring that doesn't change behavior

### MINOR (0.1.0 → 0.2.0)
- New features
- Significant enhancements
- New configuration options
- New scripts or utilities
- Major refactoring that improves functionality

### MAJOR (0.x.x → 1.0.0)
- Production-ready release
- Breaking changes (after 1.0.0)
- Major architectural changes (after 1.0.0)

## Version Number Locations

Version numbers must be updated in **all** of the following locations:

1. **CHANGELOG.md** - Add new version entry at the top
2. **vpn-monitor.sh** - Update `SCRIPT_VERSION` variable and `# Version:` comment
3. **install.sh** - Update `# Version:` comment
4. **vpn-keepalive.sh** - Update `SCRIPT_VERSION` variable and `# Version:` comment
5. **All lib/*.sh files** - Update `# Version:` comment in each file:
   - `lib/common.sh`
   - `lib/config.sh`
   - `lib/config_schema.sh`
   - `lib/constants.sh`
   - `lib/detection.sh`
   - `lib/lockfile.sh`
   - `lib/logging.sh`
   - `lib/recovery.sh`
   - `lib/state.sh`
6. **Utility scripts** - Update `# Version:` comment:
   - `check-config.sh`
   - `check-utilities.sh`
   - `analyze-logs.sh`
   - `uninstall.sh`

## Version Update Checklist

When releasing a new version:

- [ ] Update version in CHANGELOG.md (add new entry at top)
- [ ] **Use the automated script**: `./scripts/update-version.sh <new_version>` to update all version numbers
  - Or use `--dry-run` flag to preview changes: `./scripts/update-version.sh <new_version> --dry-run`
  - The script automatically updates all files listed below
- [ ] Manually update `# Version:` comment in `vpn-monitor.sh` (if script missed it)
- [ ] Manually update `SCRIPT_VERSION` in `vpn-monitor.sh` (if script missed it)
- [ ] Manually update `SCRIPT_VERSION` in `vpn-keepalive.sh` (if script missed it)
- [ ] Manually update `# Version:` comment in `vpn-keepalive.sh` (if script missed it)
- [ ] Manually update `# Version:` comment in `install.sh` (if script missed it)
- [ ] Manually update `# Version:` comment in all `lib/*.sh` files (if script missed any)
- [ ] Manually update `# Version:` comment in utility scripts (if script missed any)
- [ ] Verify version consistency: `grep -r "Version:" --include="*.sh" .`
- [ ] Test that `--version` flag works correctly
- [ ] Test that install script detects version upgrades correctly

### Automated Version Update

The `scripts/update-version.sh` script automates version number updates across all project files:

```bash
# Preview changes (dry run)
./scripts/update-version.sh 0.4.3 --dry-run

# Actually update versions
./scripts/update-version.sh 0.4.3
```

The script:
- Validates version format (SemVer: MAJOR.MINOR.PATCH)
- Updates `# Version:` comments in all script files
- Updates `SCRIPT_VERSION` variables in `vpn-monitor.sh` and `vpn-keepalive.sh`
- Updates all library files (`lib/*.sh`)
- Updates utility scripts (`analyze-logs.sh`, `check-config.sh`, `check-utilities.sh`, `uninstall.sh`)
- Verifies updates after completion
- Provides colored output and error handling

## Version Extraction

The installation script (`install.sh`) automatically extracts version numbers using:

1. **Primary method**: Extracts `SCRIPT_VERSION` from `vpn-monitor.sh`
2. **Fallback method**: Extracts `# Version:` comment from `install.sh`

This allows the install script to display upgrade information when installing over an existing installation.

## Best Practices

1. **Always update CHANGELOG.md first** - This documents what changed
2. **Update all version locations** - Consistency is critical
3. **Use descriptive CHANGELOG entries** - Document what changed and why
4. **Tag releases in git** - Use tags like `v0.2.0` for releases
5. **Reserve 1.0.0 for production-ready** - Don't rush to 1.0.0

## Transitioning to 1.0.0

When the project is ready for production use:

- All critical features are implemented and tested
- Documentation is complete
- Test coverage is adequate
- The project has been stable in production-like environments
- Breaking changes are acceptable (since it's the first major release)

After `1.0.0`, follow standard SemVer:
- `1.0.0` → `1.0.1` (bug fix)
- `1.0.1` → `1.1.0` (new feature)
- `1.1.0` → `2.0.0` (breaking change)
