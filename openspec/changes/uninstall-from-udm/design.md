## Context

Central management tooling (`scripts/manage/`) already deploys and controls VPN Monitor across a fleet via SSH. `deploy-to-udm.sh` runs `uninstall.sh` as step 3 of a full upgrade pipeline, but there is no way to uninstall remotely without also transferring and installing a new package. Operators today use manual SSH:

```bash
ssh root@<udm-ip> '/data/vpn-monitor/uninstall.sh --yes --keep-config'
```

`control-remote-udm.sh` established the pattern for thin remote wrappers: SSH to `/data/vpn-monitor/`, invoke an on-UDM script, support single-host and batch config modes. This change applies the same pattern to uninstall.

Constraints: UDM OS 4.3+ only; bash + standard utilities; no python3/jq/node; reuse `scripts/manage/lib/ssh_control.sh`.

## Goals / Non-Goals

**Goals:**

- Remote uninstall of VPN Monitor from one or many UDMs without package transfer.
- Flag parity with local `uninstall.sh` and with deploy's uninstall step defaults.
- Reuse SSH ControlMaster, BindAddress, and credential patterns from existing manage scripts.
- BATS tests with mocked SSH (same approach as `tests/test_remote_control.sh`).
- Close gap documented in `docs/scripts/CENTRAL_MANAGEMENT_GAPS.md` §1.

**Non-Goals:**

- Adding `--uninstall-only` to `deploy-to-udm.sh` (may follow later per §5; separate scripts keep deploy pipeline focused).
- Unified fleet config across deploy/control/centralize (separate gap §4).
- Live fleet inventory or version verification before uninstall.
- Changing on-UDM `uninstall.sh` behavior (remote scripts are thin SSH wrappers).
- Web UI or REST API.

## Decisions

### 1. Separate scripts rather than deploy mode flag

**Decision:** Add `uninstall-from-udm.sh` (single host) and `uninstall-from-udms.sh` (batch), mirroring the deploy/control script split.

**Rationale:** Uninstall has no package, log tail, or install steps — a dedicated script is clearer than extending `deploy-to-udm.sh` with `--uninstall-only` that skips half the pipeline. Keeps deploy script complexity stable; `--uninstall-only` on deploy can be a thin wrapper later if desired.

**Alternatives considered:**
- *`deploy-to-udm.sh --uninstall-only`*: Fewer files, but deploy script already long; mixes concerns.
- *Single script with `--config` like control-remote-udm.sh*: Possible, but batch deploy uses a separate `deploy-to-udms.sh`; consistency favors two scripts.

### 2. Remote command construction

**Decision:** Build remote command identically to `deploy-to-udm.sh` uninstall step (lines ~446–463):

```bash
if [[ -x /data/vpn-monitor/uninstall.sh ]]; then
  /data/vpn-monitor/uninstall.sh --yes [flags]
else
  echo 'No installation found' >&2; exit 1
fi
```

Default flags (match deploy defaults): `--keep-config`, `--remove-state`, `--remove-logs`.

Forwarded flags (mutually exclusive pairs validated locally):
- Config: `--keep-config` | `--remove-config`
- State: `--keep-state` | `--remove-state`
- Logs: `--keep-logs` | `--remove-logs`

**Rationale:** Operators expect remote uninstall to behave like deploy's uninstall step. Duplicating flag logic in one place is acceptable; optional follow-up is extracting `build_uninstall_command()` to `scripts/manage/lib/uninstall_remote.sh` shared by deploy and uninstall scripts.

### 3. SSH and logging

**Decision:** Source `scripts/manage/lib/ssh_control.sh`; use same options as `control-remote-udm.sh`: `--host`, `--config`, `--bind-ip`, `--username`, `--port`, `--timeout`, `--dry-run`. Log to `logs/uninstall-from-udm.log` / `logs/uninstall-from-udms.log` (sanitized, no credentials).

**Rationale:** Consistent operator experience; existing patterns documented in `docs/reference/CODE_PATTERNS.md`.

### 4. Batch config file

**Decision:** Default config `deploy-udms.conf` for batch script (same fleet list as deploy). Document that `control-udms.conf` works if hosts match.

**Rationale:** Uninstall fleet list most likely matches deploy fleet. Avoids introducing a fourth config file before unified fleet config (gap §4).

### 5. Deploy registry cleanup

**Decision:** Optional `--update-registry` flag removes host line from `logs/deploy-registry` via new helper `remove_registry_entry()` in `deploy-registry.sh`. Default: no registry change (registry is controller bookkeeping; uninstall on UDM does not imply controller knows).

**Rationale:** Best-effort hygiene without requiring registry sync. Matches proposal impact section.

### 6. Pre-uninstall log archive

**Decision:** Do **not** archive logs remotely before uninstall (unlike deploy step 2). Operators can use `centralize-logs.sh` beforehand or pass `--keep-logs`.

**Rationale:** Uninstall-only workflow is often "remove quickly"; archive-on-deploy remains in deploy pipeline. `--keep-logs` preserves logs on target if needed.

## Risks / Trade-offs

- **[Risk] Accidental fleet-wide uninstall** → Batch script prints host list and requires confirmation unless `--yes` is passed (match local `uninstall.sh` non-interactive pattern).
- **[Risk] Registry drift if `--update-registry` omitted** → Document in help text; optional flag for operators who use registry.
- **[Risk] Duplicated uninstall command builder vs deploy** → Accept for v1; extract shared helper if both scripts diverge.
- **[Trade-off] No reinstall rollback** → Uninstall is destructive to monitor installation; rollback requires redeploy via `deploy-to-udm.sh`. VPN tunnels unaffected.

## Migration Plan

1. Add scripts and optional `remove_registry_entry()` helper.
2. Add BATS tests with SSH mocks.
3. Update `docs/scripts/CENTRAL_MANAGEMENT_GAPS.md` §1 status to implemented.
4. No on-UDM migration — uses existing `uninstall.sh`.

**Rollback:** Reinstall with `deploy-to-udm.sh`. Uninstall itself has no partial state on controller beyond optional registry line removal.

## Open Questions

- Should batch script default to `--update-registry`? **Proposal: no** — opt-in keeps registry semantics explicit.
- Extract `build_uninstall_command()` shared with deploy in this change or follow-up? **Proposal: follow-up** unless duplication exceeds ~15 lines during implementation.
