## 1. Pull config script

- [x] 1.1 Create `scripts/manage/pull-config-from-udms.sh` with `--help`, `--config`, `--host`, `--config-dir`, `--bind-ip`, `--username`, `--port`, `--timeout`, `--dry-run`
- [x] 1.2 Implement fleet config resolution matching `status-udms.sh` (default `deploy-udms.conf` then `control-udms.conf`)
- [x] 1.3 Reuse `read_manage_host_config()` and per-host bind IP reset from `scripts/manage/lib/ssh_control.sh`
- [x] 1.4 Implement remote probe + SCP pull to `configs/<host>/vpn-monitor.conf` with atomic local write; report `ok`, `not_installed`, `no_remote_config`, `unreachable`, `error`
- [x] 1.5 Print tab-separated status table and fleet summary; non-zero exit if any host failed

## 2. Push config script

- [x] 2.1 Create `scripts/manage/push-config-to-udms.sh` with `--help`, `--config`, `--host`, `--file`, `--config-dir`, `--bind-ip`, `--username`, `--port`, `--timeout`, `--dry-run`
- [x] 2.2 Implement timestamped remote backup under `/data/vpn-monitor/backups/` before overwrite
- [x] 2.3 Implement controller backup under `configs/backups/<host>/` (SCP current remote file when present)
- [x] 2.4 Push with atomic remote install (`vpn-monitor.conf.tmp` → validate → `mv`); run remote `check-config.sh --config` on staged file; leave live config unchanged on failure
- [x] 2.5 Print tab-separated status table and fleet summary; non-zero exit if any host failed; skip/warn when local file missing in batch mode

## 3. Tests

- [x] 3.1 Create `tests/test_pull_config_from_udms.sh` with mocked SCP/SSH: help, fleet config, dry-run, pull success, not installed, unreachable
- [x] 3.2 Create `tests/test_push_config_to_udms.sh` with mocked SCP/SSH: help, dry-run, backup paths, success, check-config failure rollback, missing local file
- [x] 3.3 Add code-to-test mapping entries in `docs/testing/RELEVANT_TESTS.md`
- [x] 3.4 Run `TEST_TIMEOUT=120 bats tests/test_pull_config_from_udms.sh tests/test_push_config_to_udms.sh`
- [x] 3.5 Run `shellcheck --severity=error` and `shfmt -d` on new/changed scripts

## 4. Packaging, hygiene, and documentation

- [x] 4.1 Add `configs/` to `.gitignore`
- [x] 4.2 Include pull/push scripts in `scripts/prepare_install_package.sh` and `tests/test_prepare_install_package.sh` if other manage scripts are packaged
- [x] 4.3 Update `docs/scripts/CENTRAL_MANAGEMENT_GAPS.md` §1 — mark pull/push implemented; remove `diff-config-udms.sh` from suggested additions; document pull-edit-push workflow
- [x] 4.4 Document in script `--help`: local layout, backups, rollback, config applies on next cron (no IPsec restart)
