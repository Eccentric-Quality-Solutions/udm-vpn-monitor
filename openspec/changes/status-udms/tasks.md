## 1. Fleet status script

- [x] 1.1 Create `scripts/manage/status-udms.sh` with `--help`, `--config`, `--host`, `--bind-ip`, `--username`, `--port`, `--timeout`, `--dry-run`
- [x] 1.2 Implement config resolution: `--config FILE` override; default `deploy-udms.conf` then fallback `control-udms.conf`; fail clearly if neither exists
- [x] 1.3 Reuse `read_manage_host_config()` from `scripts/manage/lib/ssh_control.sh`; reset bind IP per host in batch mode
- [x] 1.4 Build combined remote probe (live `SCRIPT_VERSION`, `vpn-monitor-control.sh status`, cron grep on `/var/spool/cron/crontabs/root`); parse locally with `parse_script_version_line()` from `lib/common.sh`
- [x] 1.5 Source `deploy-registry.sh`; call `get_deployed_info()` per host; compute registry drift marker (`match`, `drift`, `no_registry`, `n/a`)
- [x] 1.6 Print tab-separated table with header and fleet summary counts; non-zero exit if any host unreachable or probe failed

## 2. Tests

- [x] 2.1 Create `tests/test_fleet_status.sh` with mocked SSH covering: help, config missing/empty, dry-run remote command, bind-ip reset, installed/not installed/unreachable hosts, registry match/drift/no_registry, summary counts
- [x] 2.2 Add code-to-test mapping entry in `docs/testing/RELEVANT_TESTS.md`
- [x] 2.3 Run `TEST_TIMEOUT=120 bats tests/test_fleet_status.sh`
- [x] 2.4 Run `shellcheck --severity=error` on new/changed scripts; `shfmt -d` on same files

## 3. Packaging and documentation

- [x] 3.1 Include `status-udms.sh` in `scripts/prepare_install_package.sh` if other `scripts/manage/*.sh` are packaged; extend `tests/test_prepare_install_package.sh` if needed
- [x] 3.2 Update `docs/scripts/CENTRAL_MANAGEMENT_GAPS.md` §3 — mark fleet inventory implemented; reference `status-udms.sh`
- [x] 3.3 Add usage examples to script `--help` output (mirror style of `control-remote-udm.sh`)
