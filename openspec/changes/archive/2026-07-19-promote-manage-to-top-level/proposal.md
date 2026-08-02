## Why

The fleet controller lives under `scripts/manage/`, which makes it look like a one-off helper next to package prep and git hooks. It is a peer to the UDM agent (root scripts + `lib/`), not developer tooling. Promoting it to top-level `manage/` makes that architecture visible in the tree and matches how operators already think about the control plane.

## What Changes

- **BREAKING**: Move `scripts/manage/` → `manage/` (all fleet CLI scripts, `lib/`, and `*.conf.example` files)
- Update `REPO_ROOT` resolution and `# shellcheck source=` paths (directory depth changes from two levels to one)
- Update install package file lists, tests, operator docs, and OpenSpec main specs that cite `scripts/manage/`
- Leave `scripts/` for repo/dev tooling only (`prepare_install_package.sh`, hooks, anonymize, etc.)
- No behavioral change to deploy, control, status, config pull/push, uninstall, or log centralization — path and packaging only
- No compatibility shims under `scripts/manage/` (single deployment; operators update paths)

## Capabilities

### New Capabilities

- (none — layout relocation only)

### Modified Capabilities

- `remote-control`: Script path requirements change from `scripts/manage/control-remote-udm.sh` to `manage/control-remote-udm.sh`
- `fleet-status`: Script path requirements change from `scripts/manage/status-udms.sh` to `manage/status-udms.sh`
- `remote-uninstall`: Script path requirements change from `scripts/manage/uninstall-from-udm(s).sh` to `manage/`
- `remote-config-pull-push`: Script path requirements change from `scripts/manage/pull|push-config-to-udms.sh` to `manage/`

## Impact

- **Code**: Entire `scripts/manage/` tree → `manage/`; every manage script’s `REPO_ROOT`; shellcheck source directives; usage/`--help` text
- **Packaging**: `scripts/prepare_install_package.sh` and `tests/test_prepare_install_package.sh`
- **Tests**: Any BATS file or fixture that hardcodes `scripts/manage/`
- **Docs (must work)**: README, `docs/scripts/CONTROL_PLANE_ACCEPTANCE.md`, `docs/scripts/CENTRALIZE_LOGS.md`, `docs/research/SERVER_APP_RECOMMENDATIONS.md`, `docs/testing/RELEVANT_TESTS.md`, CHANGELOG
- **Docs (active specs)**: `openspec/specs/{remote-control,fleet-status,remote-uninstall,remote-config-pull-push}`
- **Out of scope**: Archived OpenSpec changes; historical research prose that is clearly archival (optional cleanup only if cited in active operator paths); long-lived management server (still deferred)
- **VPN/runtime**: No impact on UDM recovery, operating mode, or tunnel behavior — controller-host paths only
