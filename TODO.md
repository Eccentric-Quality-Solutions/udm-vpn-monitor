# TODO

This file tracks planned improvements and tasks for the UDM VPN Monitor project.

**Last Reviewed:** 2026-08-02  
**Last Updated:** 2026-08-02

## Human

- Need to regularly identify and mitigate slow tests
- Interactive mode doesn't seem to trigger auto?
- If you don't enter a locaiton it seems like the app doesn't fully install/start (makes sense, but probably want to handle differently).

## High Priority

### Prove control plane on live fleet (ops)
Moved from OpenSpec change `prove-control-plane` (tasks 5.1–5.3) before archive. Checklist: `docs/scripts/CONTROL_PLANE_ACCEPTANCE.md`.

- [ ] Fill `deploy-udms.conf` / `control-udms.conf` for target hosts
- [ ] Execute `CONTROL_PLANE_ACCEPTANCE.md` end-to-end; file gaps as follow-ups (do not expand into management server)
- [ ] Only after checklist passes: canary `start` when ready for recovery testing

## Medium Priority

### Add Explicit Log File Permissions
**Action:** Add `chmod 644` (or equivalent) for log files after create/rotate. State files already get `chmod 600` via `atomic_write_file()` in `lib/common.sh`.
**Effort:** LOW
**Benefit:** Explicit permissions improve consistency with state-file posture

---

**Note:** For additional future considerations that are less immediate, see [FUTURE.md](FUTURE.md).
