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

The **canonical** set of files that carry the project version is what `scripts/update-version.sh` updates. Update these via the script (see below); do not edit version numbers by hand except when adding a new file that should be tracked.

1. **CHANGELOG.md** — Add a new version entry at the top (script does not modify CHANGELOG).
2. **Main scripts** — `vpn-monitor.sh` and `vpn-keepalive.sh` have `SCRIPT_VERSION` and `# Version:`; `vpn-monitor-wrapper.sh` and `vpn-monitor-control.sh` have `# Version:` only.
3. **Installation** — `# Version:` only:
   - `install.sh`
   - `uninstall.sh`
4. **Utility scripts** — `# Version:` only:
   - `analyze-logs.sh`
   - `check-config.sh`
   - `check-utilities.sh`
5. **Library** — All `lib/**/*.sh` files (recursive), `# Version:` only. Includes top-level `lib/*.sh` and all files under `lib/config/`, `lib/control/`, `lib/detection/`, `lib/recovery/`, `lib/state/`, etc.

**Other scripts** that carry a `# Version:` comment for their own use (e.g. `compare-config.sh`, `scripts/anonymize/*.sh`, `scripts/api/list-udm-vpns.sh`, `scripts/export-udm-routes-firewall.sh`) are **not** updated by `scripts/update-version.sh`. Update those manually when you change them, if desired.

## Version Update Checklist

When releasing a new version:

- [ ] Update version in **CHANGELOG.md** (add new entry at top).
- [ ] Run **automated script**: `./scripts/update-version.sh <new_version>` (use `--dry-run` to preview).
- [ ] Verify version consistency: `grep -r "Version:" --include="*.sh" .` (and optionally `SCRIPT_VERSION`).
- [ ] Test `--version` on `vpn-monitor.sh` and `vpn-keepalive.sh`.
- [ ] Test that install script shows upgrade info when installing over an existing installation.

### Automated Version Update

The `scripts/update-version.sh` script updates version numbers in all tracked files:

```bash
# Preview changes (dry run)
./scripts/update-version.sh 0.8.4 --dry-run

# Apply updates
./scripts/update-version.sh 0.8.4
```

The script:

- Validates version format (SemVer: `MAJOR.MINOR.PATCH`).
- Updates `SCRIPT_VERSION` and `# Version:` in `vpn-monitor.sh` and `vpn-keepalive.sh`; updates `# Version:` in `vpn-monitor-wrapper.sh` and `vpn-monitor-control.sh`.
- Updates `# Version:` in `install.sh`, `uninstall.sh`, `analyze-logs.sh`, `check-config.sh`, and `check-utilities.sh`.
- Updates `# Version:` in every `lib/**/*.sh` file (discovered recursively).
- Optionally stages files with `git add` when the only change in the file is the version update.
- Verifies updates and prints colored progress/errors.

## Version Extraction

**Install script (`install.sh`)** — Used to show upgrade info when installing over an existing installation:

1. **Primary**: Reads `SCRIPT_VERSION` from the source `vpn-monitor.sh` (via `get_script_version()`).
2. **Fallback**: Reads `# Version:` from `install.sh` if `vpn-monitor.sh` has no `SCRIPT_VERSION`.

**Deployment scripts** — `scripts/manage/deploy-to-udm.sh`, `deploy-to-udms.sh`, and `deploy-registry.sh` derive the package version by extracting `SCRIPT_VERSION` from `vpn-monitor.sh` inside the zip/tar package (for skip-if-same-version and deployment registry).

## Best Practices

1. **Update CHANGELOG.md first** — Document what changed before bumping the version.
2. **Use `scripts/update-version.sh` for tracked files** — Keeps all canonical version locations in sync; avoid editing version numbers by hand in those files.
3. **Use descriptive CHANGELOG entries** — Document what changed and why.
4. **Tag releases in git** — Use tags like `v0.8.3` for releases.
5. **Reserve 1.0.0 for production-ready** — Don't rush to 1.0.0.

The install package produced by `scripts/prepare_install_package.sh` is named `udm-vpn-monitor.zip` (or `.tar.gz`); the version is not in the filename. The version inside the package (from `vpn-monitor.sh`’s `SCRIPT_VERSION`) is what install and deployment scripts use.

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
