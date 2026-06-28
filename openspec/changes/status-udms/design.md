## Context

Central management tooling (`scripts/manage/`) deploys, controls, and uninstalls VPN Monitor across a fleet via SSH. Operators today piece together visibility from three incomplete sources:

- `logs/deploy-registry` — controller bookkeeping (host, version, timestamp); can drift after manual installs/uninstalls
- `control-remote-udm.sh status` — operating mode only; no installed package version
- `centralize-logs.sh` — cron health during log pull; not a dedicated inventory command

Gap documented in `docs/scripts/CENTRAL_MANAGEMENT_GAPS.md` §3. Fleet config remains fragmented (`deploy-udms.conf`, `control-udms.conf`, `centralize.conf`); this change does **not** wait for unified config.

Constraints: UDM OS 4.3+ only; bash + standard utilities; no python3/jq/node; reuse `scripts/manage/lib/ssh_control.sh` and `deploy-registry.sh`.

## Goals / Non-Goals

**Goals:**

- Single command `status-udms.sh` reporting per host: live version, operating mode, cron presence, registry row, registry drift indicator.
- Read-only — no changes on UDMs or deploy registry.
- Reuse existing fleet config format (`host [bind_ip]`) and SSH patterns from `control-remote-udm.sh` / `uninstall-from-udms.sh`.
- BATS tests with mocked SSH (same approach as `tests/test_remote_control.sh`).
- Close gap §3 in `CENTRAL_MANAGEMENT_GAPS.md` when implemented.

**Non-Goals:**

- Unified fleet config (gap §4) — accept deploy or control config with sensible default/fallback.
- Pushing config, remote `check-config.sh`, or config diffs (gap §2).
- Extending `deploy-to-udm.sh` with status/version flags (use `status-udms.sh` instead).
- Semantic version comparison beyond string equality for drift detection.
- Web UI, SQLite inventory, or REST API.
- Changing on-UDM scripts or operating-mode behavior.

## Decisions

### 1. Single script `status-udms.sh` (batch-only)

**Decision:** One script that always iterates a config file (default fleet list). No separate single-host wrapper unless `--host` is useful for symmetry with other scripts.

**Rationale:** Primary use case is fleet visibility from a jump host. Optional `--host HOST [--bind-ip IP]` mirrors `control-remote-udm.sh` for ad-hoc checks without maintaining a config file.

**Alternatives considered:**
- *Separate `status-udm.sh` + `status-udms.sh`*: Consistent with deploy/uninstall split but adds file count for a read-only query; defer unless `--host`-only mode feels awkward in one file.

### 2. One SSH session per host with combined remote probe

**Decision:** After ControlMaster setup, run one remote shell snippet that prints structured fields, e.g. tab-separated:

```bash
# Pseudocode — actual script uses quoted paths and fallbacks
if [[ -f /data/vpn-monitor/vpn-monitor.sh ]]; then
  grep '^SCRIPT_VERSION=' /data/vpn-monitor/vpn-monitor.sh | head -1
else
  echo 'SCRIPT_VERSION='
fi
if [[ -x /data/vpn-monitor/vpn-monitor-control.sh ]]; then
  /data/vpn-monitor/vpn-monitor-control.sh status
else
  echo 'Operating mode: not installed'
fi
if grep -q vpn-monitor /var/spool/cron/crontabs/root 2>/dev/null; then
  echo 'CRON_PRESENT=yes'
else
  echo 'CRON_PRESENT=no'
fi
```

Controller parses `SCRIPT_VERSION=` via existing `parse_script_version_line()` from `lib/common.sh`, extracts `Operating mode:` from control status output, and reads `CRON_PRESENT`.

**Rationale:** Minimizes round trips (acceptable N hosts × ~1 SSH for small fleets). Avoids SCP-pulling crontab like `centralize-logs.sh` unless grep-on-remote is insufficient (UDM has the crontab file at `/var/spool/cron/crontabs/root` per `install.sh`).

**Alternatives considered:**
- *Invoke `control-remote-udm.sh status` as subprocess per host*: Extra SSH setup and harder to merge with version/cron in one report.
- *Three SSH calls per host*: Simpler parsing but 3× latency; rejected for small fleet acceptability.

### 3. Config file resolution

**Decision:** `--config FILE` overrides. Default order:

1. `${REPO_ROOT}/deploy-udms.conf` if it exists
2. Else `${REPO_ROOT}/control-udms.conf` if it exists
3. Else error with message listing both expected paths

**Rationale:** Matches uninstall batch default (`deploy-udms.conf`) while not blocking operators who only maintain `control-udms.conf`. Does not introduce a fourth config file.

### 4. Registry lookup (local)

**Decision:** Source `deploy-registry.sh`; call `get_deployed_info "$host"` for registry version and timestamp. Compute drift:

| Live version | Registry version | Drift marker |
|--------------|------------------|--------------|
| empty | any | `n/a` (not installed) |
| set | empty | `no_registry` |
| set | set, equal | `match` |
| set | set, differ | `drift` |

**Rationale:** Makes registry lies visible without writing to registry. String equality matches current `host_has_version()` semantics in deploy skip logic.

### 5. Output format

**Decision:** Human-readable tab-separated table to stdout with header row:

```
HOST	VERSION	MODE	CRON	REGISTRY_VERSION	REGISTRY_TIME	REGISTRY_MATCH
```

Use fixed column order for `awk`/grep post-processing. Per-host errors print `ERROR` or `UNREACHABLE` in VERSION column; details on stderr via `manage_log_*`.

**Rationale:** Consistent with registry TSV format; script-friendly without JSON dependency.

**Alternatives considered:**
- *JSON output*: Requires jq or custom parser; rejected per platform rules.
- *Verbose multi-line blocks per host*: Readable but poor for diffing fleets; table preferred with optional future `--verbose`.

### 6. SSH, logging, and exit codes

**Decision:** Source `ssh_control.sh`; options `--config`, `--host`, `--bind-ip`, `--username`, `--port`, `--timeout`, `--dry-run`, `--help`. Log informational messages to stderr only (no dedicated log file for v1 — read-only, low risk). Exit 0 when all hosts queried successfully; non-zero if any host unreachable or probe failed.

**Rationale:** Aligns with `control-remote-udm.sh`. Omit log file unless operators request audit trail later.

### 7. Tests

**Decision:** `tests/test_fleet_status.sh` with mocked `ssh`/`execute_ssh_control` patterns from remote control tests: help, config missing, empty config, dry-run remote command, bind-ip reset, registry drift parsing (local fixtures), unreachable host non-zero exit.

**Rationale:** Same proven approach; no live SSH in CI.

## Risks / Trade-offs

- **[Risk] Slow on large fleets** → Accept for v1 (explicit non-goal: small fleet). Future: parallel SSH or `--jobs` if needed.
- **[Risk] Crontab path differs on some UDM builds** → Use same path as `centralize-logs.sh` and `install.sh`; document in help.
- **[Risk] Parsing `vpn-monitor-control.sh status` output is brittle** → Prefer stable `Operating mode:` line; control script is project-owned.
- **[Risk] Registry vs live version semantics** → Document that live version is truth; registry is bookkeeping hint only.
- **[Trade-off] Combined remote script vs separate calls** → Faster but slightly more complex remote quoting; use `printf %q` / heredoc patterns from existing manage scripts.

## Migration Plan

1. Add `status-udms.sh` and BATS tests.
2. Update `docs/scripts/CENTRAL_MANAGEMENT_GAPS.md` §3 — mark fleet inventory implemented.
3. Add `docs/testing/RELEVANT_TESTS.md` mapping.
4. Include script in install package via `prepare_install_package.sh` if other manage scripts are packaged (match existing manage script inclusion).

**Rollback:** Remove script; no on-UDM state to revert.

## Open Questions

- Add `--host` single-target mode in v1? **Proposal: yes** — low cost, matches other manage scripts.
- Include keepalive status column? **Proposal: no for v1** — available in control status output but clutters table; mode + cron sufficient for gap §3. Can add column later.
- Package in `prepare_install_package.sh` in same change? **Proposal: yes** if other `scripts/manage/*.sh` are already included (verify during implementation).
