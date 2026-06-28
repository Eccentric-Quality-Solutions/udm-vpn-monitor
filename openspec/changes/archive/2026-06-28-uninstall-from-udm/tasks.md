## 1. Registry helper (optional cleanup)

- [x] 1.1 Add `remove_registry_entry()` to `scripts/manage/deploy-registry.sh` — remove tab-separated line matching host (atomic rewrite)
- [x] 1.2 Add BATS coverage for `remove_registry_entry()` in existing deploy-registry tests or `tests/test_remote_uninstall.sh`

## 2. Single-host remote uninstall

- [x] 2.1 Create `scripts/manage/uninstall-from-udm.sh` with `--host`, `--bind-ip`, `--username`, `--port`, `--timeout`, `--dry-run`, `--help`
- [x] 2.2 Implement uninstall flag parsing (`--keep-config`/`--remove-config`, `--keep-state`/`--remove-state`, `--keep-logs`/`--remove-logs`) with local conflict validation; defaults match deploy (`--keep-config`, `--remove-state`, `--remove-logs`)
- [x] 2.3 Build and execute remote `uninstall.sh --yes` command; fail clearly when `/data/vpn-monitor/uninstall.sh` missing
- [x] 2.4 Reuse `scripts/manage/lib/ssh_control.sh` ControlMaster patterns; log to `logs/uninstall-from-udm.log` (sanitized)
- [x] 2.5 Implement `--update-registry` to call `remove_registry_entry()` after successful uninstall
- [x] 2.6 Add `--yes` for non-interactive batch confirmation skip (single-host may default to prompt unless `--yes`)

## 3. Batch remote uninstall

- [x] 3.1 Create `scripts/manage/uninstall-from-udms.sh` reading `--config FILE` (default `deploy-udms.conf`, format `host [bind_ip]`)
- [x] 3.2 Loop hosts calling single-host logic; print per-host summary; non-zero exit if any host failed
- [x] 3.3 Prompt for confirmation listing all hosts unless `--yes`; log to `logs/uninstall-from-udms.log`
- [x] 3.4 Forward uninstall flags and `--update-registry` to each host invocation

## 4. Tests

- [x] 4.1 Create `tests/test_remote_uninstall.sh` with mocked SSH covering: single-host uninstall, flag forwarding, missing install, batch success/failure, `--update-registry`, no package transfer
- [x] 4.2 Add code-to-test mapping entry in `docs/testing/RELEVANT_TESTS.md`
- [x] 4.3 Run `TEST_TIMEOUT=120 bats tests/test_remote_uninstall.sh`
- [x] 4.4 Run `shellcheck --severity=error` on new/changed scripts; `shfmt -d` on same files

## 5. Documentation

- [x] 5.1 Update `docs/scripts/CENTRAL_MANAGEMENT_GAPS.md` §1 — mark remote uninstall implemented; reference new scripts
- [x] 5.2 Add usage examples to script `--help` output (mirror style of `control-remote-udm.sh`)
