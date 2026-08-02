## Context

Fleet controller tools currently live at `scripts/manage/` alongside developer helpers (`prepare_install_package.sh`, git hooks, anonymize). Operators and specs already treat this tree as the **control plane** (deploy, remote control, status, config pull/push, uninstall, log centralization). The UDM-side agent remains at repo root (`vpn-monitor.sh`, `lib/`, etc.).

This change is a layout promotion only: `scripts/manage/` → top-level `manage/`. Behavior and SSH patterns stay the same. Project convention: single deployment, no backwards-compatibility shims.

## Goals / Non-Goals

**Goals:**

- Make the fleet controller a first-class top-level peer to the UDM agent
- Keep `scripts/` for repo/dev/CI tooling only
- Update all path-sensitive code, package lists, tests, active OpenSpec specs, and operator-facing docs
- Preserve existing CLI flags, fleet config format, and ControlMaster SSH helpers

**Non-Goals:**

- Implementing a long-lived management server (Python/Go) — still deferred per SERVER_APP_RECOMMENDATIONS
- Changing deploy/control/status/config/uninstall behavior
- Adding compatibility wrappers at `scripts/manage/`
- Rewriting archived OpenSpec changes under `openspec/changes/archive/`
- Moving package prep or git hooks into `manage/`

## Decisions

### Decision: Top-level directory name is `manage/`

- **Choice:** `manage/` at repo root (not `agent/`, `agents/manage/`, or `control-plane/`)
- **Rationale:** Matches existing script names, docs language (“manage scripts”), and avoids introducing a new “agent” vocabulary for code that is already CLI/SSH tools
- **Alternatives considered:**
  - `agent/` / `agents/manage/` — clearer dual-agent metaphor; rejected because user selected `manage/` and existing paths say “manage”
  - `control/` — matches CONTROL_PLANE docs; rejected for same naming consistency

### Decision: Fix `REPO_ROOT` depth; no shim

- **Choice:** After move, `REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"` (was `../..`). Delete old `scripts/manage/` entirely.
- **Rationale:** Single deployment; shims hide breakage and double-maintain paths
- **Alternatives considered:** Thin wrappers under `scripts/manage/*.sh` that `exec` into `manage/` — rejected for churn and confusion

### Decision: Keep manage tools in the install package

- **Choice:** Continue shipping `manage/` scripts in zip/tar from `prepare_install_package.sh` (update path prefixes only)
- **Rationale:** Controllers sometimes unpack the package on a laptop/server; existing package already included these files
- **Alternatives considered:** Exclude manage tools from UDM package — out of scope; revisit only if package size or UDM install hygiene becomes a problem

### Decision: Doc update scope = operator-facing + active specs

- **Must update:** README, CONTROL_PLANE_ACCEPTANCE, CENTRALIZE_LOGS, SERVER_APP_RECOMMENDATIONS (active path cites), RELEVANT_TESTS, CHANGELOG, any `--help` / comment paths in moved scripts, `openspec/specs/*` that embed `scripts/manage/`
- **Leave alone:** Archived OpenSpec change folders; purely historical prose unless it is the only remaining operator instruction

### Decision: Bulk path rewrite after `git mv`

1. `git mv scripts/manage manage`
2. Update every moved script’s `REPO_ROOT` and `# shellcheck source=`
3. Ripgrep for `scripts/manage` and fix remaining references in tests/docs/package lists
4. Run relevant BATS + shellcheck/shfmt on `manage/**/*.sh`

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Missed hard-coded `scripts/manage` breaks tests or package | Ripgrep gate before declaring done; `test_prepare_install_package.sh` asserts new paths |
| Operator muscle memory / local scripts still point at old path | CHANGELOG **BREAKING** note; update README and CONTROL_PLANE_ACCEPTANCE first |
| `REPO_ROOT` wrong → logs/registry written outside repo | Smoke-check one script’s `--help` and a dry-run that prints resolved paths |
| Accidental stylistic doc rewrites | Minimize churn: replace path strings only |

## Migration Plan

1. Implement on a branch: move + path updates + tests
2. Operators: update any local wrappers/`PATH` aliases from `./scripts/manage/...` to `./manage/...`
3. Re-copy examples if needed: `manage/*.conf.example` (same filenames)
4. Rollback: revert the commit / restore tree (no UDM-side migration; controller-only)

## Open Questions

- None blocking. Optional later: exclude `manage/` from on-UDM install package if packages are applied only on UDMs (separate change).
