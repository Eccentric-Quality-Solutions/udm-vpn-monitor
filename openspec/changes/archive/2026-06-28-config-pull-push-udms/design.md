## Context

Gap §1 in `docs/scripts/CENTRAL_MANAGEMENT_GAPS.md`: operators can only append new config keys on deploy or edit via raw SSH. Each UDM’s `vpn-monitor.conf` is intentionally unique (site IP, location names, ping targets). A fleet template diff was considered and rejected as overcomplicated for this workflow.

Desired operator model:

1. **Pull** live configs to the controller working tree
2. **Edit** locally (manual or bulk edit under `configs/`)
3. **Push** back with timestamped backup of the previous remote file

Constraints: UDM OS 4.3+; bash + standard utilities; reuse `scripts/manage/lib/ssh_control.sh`; same fleet config format as `status-udms.sh`. `check-config.sh` is installed on each UDM at `/data/vpn-monitor/check-config.sh`.

## Goals / Non-Goals

**Goals:**

- `pull-config-from-udms.sh` — SCP live config from fleet (or `--host`) into `configs/<host>/vpn-monitor.conf` (path overridable via `--config-dir`).
- `push-config-to-udms.sh` — push local file to UDM with dual backup (remote + controller), atomic install, remote `check-config.sh`, rollback remote file on validation failure.
- Standard CLI: `--config`, `--host`, `--bind-ip`, `--username`, `--port`, `--timeout`, `--dry-run`, `--help`.
- Skip hosts without VPN Monitor installed (no config path / missing install dir) with clear status.
- Close gap §1 for pull/push/validate; remove `diff-config-udms.sh` from suggested additions in docs.
- Gitignore `configs/` so site-specific data is not committed.

**Non-Goals:**

- Fleet-wide diff against repo template (`diff-config-udms.sh`).
- Key-scoped merge or bulk policy push without editing local files.
- Unified fleet config (gap §2) — reuse `deploy-udms.conf` / `control-udms.conf` fallback like `status-udms.sh`.
- Restarting IPsec, reloading monitor, or changing cron on push.
- Web UI or SQLite inventory.

## Decisions

### 1. Two scripts (pull + push), each with `--host` batch mode

**Decision:** `pull-config-from-udms.sh` and `push-config-to-udms.sh`. Optional `--host` for single-target; otherwise iterate fleet config. Mirror `status-udms.sh` rather than four separate single/batch files.

**Rationale:** Clear verbs for pull vs push; shared SSH/fleet parsing duplicated minimally between two files.

**Alternatives considered:**
- *Single `sync-config-udms.sh` with subcommands*: Fewer files but muddier help and exit semantics; rejected.
- *Separate `-udm` + `-udms` files each*: Consistent with deploy split but heavy for two symmetric operations; rejected.

### 2. Controller directory layout

**Decision:** Default root `${REPO_ROOT}/configs/`:

```
configs/
  <host>/
    vpn-monitor.conf          # working copy (pull overwrites; operator edits)
  backups/
    <host>/
      vpn-monitor.conf.<UTC-or-local-ts>   # snapshot before each push (remote content)
```

Override with `--config-dir DIR`. Pull creates `configs/<host>/` as needed. Push reads `configs/<host>/vpn-monitor.conf` unless `--file PATH` is passed.

**Rationale:** One obvious place to edit; backups separated from working copies.

**Alternatives considered:**
- *Under `scripts/manage/configs/`*: Harder to find; repo root keeps parity with `logs/deploy-registry`.

### 3. Pull behavior

**Decision:** For each host:

1. SSH probe: `/data/vpn-monitor/vpn-monitor.conf` exists (and optionally monitor script installed).
2. SCP remote → local working path (atomic: write to `vpn-monitor.conf.tmp` then `mv`).
3. Report per host: `ok`, `not_installed`, `no_remote_config`, `unreachable`, `error`.

Pull overwrites local working copy. Optional future `--if-newer` out of scope for v1.

**Rationale:** Simple refresh from live truth before edit.

### 4. Push behavior and backups

**Decision:** For each host:

1. Verify local source file exists.
2. **Dry-run:** print planned backup path, SCP target, and remote `check-config.sh` command.
3. **Remote backup:** before overwrite, copy live config to `/data/vpn-monitor/backups/vpn-monitor.conf.<timestamp>` via remote shell (`mkdir -p`, `cp`). Skip backup step if no existing config (first install edge case — still validate push).
4. **Controller backup:** SCP current remote config to `configs/backups/<host>/vpn-monitor.conf.<timestamp>` before push (if remote file exists).
5. SCP new file to `/data/vpn-monitor/vpn-monitor.conf.tmp`.
6. Remote: `/data/vpn-monitor/check-config.sh` against `.tmp` (or validate then mv pattern: mv to `.tmp`, check, mv to final).
7. On success: `mv vpn-monitor.conf.tmp vpn-monitor.conf` on UDM.
8. On validation failure: remove `.tmp`, leave live config unchanged, exit non-zero for that host.

Timestamp format: `YYYY-MM-DDTHHMMSS` (filesystem-safe, local time or UTC — pick one and document in help; prefer UTC for sortability).

**Rationale:** Dual backup gives rollback on UDM and audit on controller. Atomic write + check-config matches project patterns.

**Alternatives considered:**
- *Backup only on UDM*: Loses controller audit trail; both chosen.
- *Local edit backup only*: Does not protect against bad push on device; rejected.

### 5. Remote validation

**Decision:** Invoke installed `/data/vpn-monitor/check-config.sh` over SSH with config path argument if supported, or `cd /data/vpn-monitor && ./check-config.sh` per existing script interface (verify during implementation).

**Rationale:** Gap §1 explicitly lists missing remote check-config invocation.

### 6. Fleet config and SSH

**Decision:** Same as `status-udms.sh`: `--config FILE`; default `deploy-udms.conf` then `control-udms.conf`; `read_manage_host_config()`; per-host bind IP reset in batch mode.

### 7. Output and exit codes

**Decision:** Tab-separated status table to stdout; summary on stderr. Exit 0 only if all hosts succeeded. Pull: partial success still non-zero if any host failed. Push: non-zero if any push/validation failed.

### 8. Tests

**Decision:**

- `tests/test_pull_config_from_udms.sh` — mocked scp/ssh: help, paths, dry-run, not installed, pull success, unreachable.
- `tests/test_push_config_to_udms.sh` — mocked scp/ssh: backup paths, atomic flow, check-config failure rollback, dry-run.

**Rationale:** Same approach as `tests/test_fleet_status.sh` and deploy tests.

## Risks / Trade-offs

- **[Risk] Pull overwrites uncommitted local edits** → Document in help; operator pulls before edit session or uses VCS locally.
- **[Risk] Push bad config passes SCP but fails check** → Mitigated by validate-before-mv; live file unchanged.
- **[Risk] Secrets in `configs/` committed to git** → Add `configs/` to `.gitignore`; document in gaps doc.
- **[Risk] Config change not picked up until cron** → Document in help; no automatic reload (by design — avoids VPN blips).
- **[Risk] Backup directory growth on UDM** → Out of scope v1; operator prunes `/data/vpn-monitor/backups/` manually or future retention flag.
- **[Trade-off] No “local newer than remote” warning** → Accept for v1; add if operators collide with on-box SSH edits.

## Migration Plan

1. Add pull/push scripts and BATS tests.
2. Add `configs/` to `.gitignore`; optional `configs/README` or note in gaps doc.
3. Update `CENTRAL_MANAGEMENT_GAPS.md` §1 — mark pull/push implemented; remove `diff-config-udms.sh` from suggestions.
4. Include scripts in `prepare_install_package.sh` if other manage scripts are packaged.

**Rollback after bad push:** Restore from `/data/vpn-monitor/backups/vpn-monitor.conf.<timestamp>` on UDM or re-push previous file from `configs/backups/`.

## Open Questions

- Does `check-config.sh` accept `-c FILE` for non-default path? **Verify at implementation**; adapt remote command accordingly.
- Sanitize `<host>` for directory names when host is a hostname with dots? **Use host string as-is** (IPs and hostnames are safe); document if FQDN paths look odd.
- Batch push all hosts in fleet config without explicit `--host`? **Yes for v1** — pushes each `configs/<host>/vpn-monitor.conf` that exists; skip or warn if missing local file.
