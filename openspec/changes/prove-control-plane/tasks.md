## 1. Default observe-only on UDM

- [x] 1.1 Change `get_default_operating_mode` in `lib/control/operating_mode.sh` to return `observe-only`
- [x] 1.2 Change `ensure_operating_mode_initialized` to initialize missing state as `observe-only` (do not overwrite existing mode)
- [x] 1.3 Update `install.sh` comment for `init_operating_mode_state` (currently says default `running`) and any install success/help text that claims recovery starts immediately
- [x] 1.4 Update architecture/state docs that state the default mode is `running` when the file is missing (`docs/reference/ARCHITECTURE.md`, `docs/reference/STATE_SYSTEM.md` only where factually wrong)

## 2. Tests for default mode

- [x] 2.1 Update `tests/test_operating_mode.sh` for missing-file and init defaults → `observe-only`; preserve upgrade/existing-mode cases
- [x] 2.2 Update install-related expectations in `tests/test_install.sh` (and any fixtures) that assert initial mode `running`
- [x] 2.3 Run `TEST_TIMEOUT=120 bats tests/test_operating_mode.sh tests/test_install.sh` (and any other files found via `docs/testing/RELEVANT_TESTS.md` for operating mode / install)
- [x] 2.4 Run `shellcheck --severity=error` and `shfmt -d` on changed shell files

## 3. Control-plane acceptance documentation

- [x] 3.1 Add `docs/scripts/CONTROL_PLANE_ACCEPTANCE.md` with the checklist: deploy, verify observe-only, pause/start, config pull/push, centralize logs, status/registry; include keepalive note and post-validation canary `start` step
- [x] 3.2 Cross-link from `docs/research/SERVER_APP_RECOMMENDATIONS.md` (Bash fleet sufficient for this milestone; full server deferred) and script `--help` or manage README if one exists
- [x] 3.3 Add CHANGELOG entry for BREAKING safe-by-default: new installs / missing mode → `observe-only`
- [x] 3.4 Update `docs/testing/RELEVANT_TESTS.md` if new docs/helpers need mapping

## 4. Optional helper (only if cheap)

- [x] 4.1 Decide doc-only vs `scripts/manage/prove-control-plane.sh` that prints (or dry-runs) checklist invocations; implement only if it stays a thin wrapper
- [x] 4.2 If helper added: minimal BATS coverage with mocked SSH patterns and shellcheck/shfmt — N/A (doc-only; no helper)

## 5. Operator validation (real or staged fleet)

- [ ] 5.1 Fill `deploy-udms.conf` / `control-udms.conf` for target hosts
- [ ] 5.2 Execute `CONTROL_PLANE_ACCEPTANCE.md` end-to-end; file gaps as follow-ups (do not expand into management server)
- [ ] 5.3 Only after checklist passes: canary `start` when ready for recovery testing
