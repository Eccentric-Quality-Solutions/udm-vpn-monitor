# Deploy Scripts Flow Diagram

This document describes how `deploy-to-udms.sh` and `deploy-to-udm.sh` work together, including password handling and SSH authentication.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  DEPLOYER (runs on UDM A, laptop, or server)                                 │
│                                                                             │
│  deploy-to-udms.sh                                                          │
│       │                                                                     │
│       │  for each UDM in deploy-udms.conf                                   │
│       │       │                                                             │
│       │       ├──► read username, password (interactive)                     │
│       │       ├──► export SSH_PASSWORD="$password"                          │
│       │       ├──► SSH_PASSWORD=... deploy-to-udm.sh --target-ip UDM_B ...  │
│       │       │         │                                                   │
│       │       │         └──► deploy-to-udm.sh (child process)                │
│       │       │                   │                                         │
│       │       │                   ├──► validate_params (reads SSH_PASSWORD)  │
│       │       │                   ├──► execute_scp (1x)                      │
│       │       │                   ├──► execute_ssh (5x: archive, uninstall,   │
│       │       │                   │              extract, install, tail)   │
│       │       │                   └──► exit                                  │
│       │       │                                                             │
│       │       ├──► run_tail_f (optional, interactive tail -f)               │
│       │       └──► unset SSH_PASSWORD  ◄── cleanup before next UDM         │
│       │                                                                     │
│       └──► Deployment summary, exit                                         │
└─────────────────────────────────────────────────────────────────────────────┘

                              │
                              │  SSH/SCP over network
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  TARGET UDMs (UDM B, UDM C, ...)                                            │
│  - Receive SCP (package file)                                                │
│  - Receive SSH (run uninstall, extract, install commands)                   │
│  - Run sshd only; no deploy scripts run here                                │
└─────────────────────────────────────────────────────────────────────────────┘
```

## deploy-to-udms.sh Flow (Batch)

```
START
  │
  ├─► parse_args (--config, --file, --skip-tail)
  │
  ├─► Validate config file exists
  │
  ├─► ensure_package (create udm-vpn-monitor.zip if missing)
  │
  ├─► Read UDM list from config (host [bind_ip] per line)
  │
  └─► FOR EACH UDM in config:
        │
        ├─► read username, password (from stdin/TTY)
        │
        ├─► if password empty → skip, fail_count++
        │
        ├─► export SSH_PASSWORD="$password"
        ├─► unset password (clear from shell memory)
        │
        ├─► deploy_args = (--file, --target-ip, --username, --append-missing-config, [--bind-ip])
        │
        ├─► SSH_PASSWORD="$SSH_PASSWORD" deploy-to-udm.sh "${deploy_args[@]}"
        │     (explicit env var ensures child receives it)
        │
        ├─► if success && !skip_tail:
        │     run_tail_f (tail -f on remote log until Ctrl+C)
        │
        ├─► unset SSH_PASSWORD   ◄── CLEANUP: remove from env before next UDM
        │
        └─► next UDM (or exit loop)
  │
  └─► Print summary, exit
```

## deploy-to-udm.sh Flow (Single UDM)

```
START
  │
  ├─► parse_args (--file, --target-ip, --username, --password, --password-file, etc.)
  │
  ├─► validate_params:
  │     │
  │     ├─► Password source (priority order):
  │     │     1. --password-file  → read from file into SSH_PASSWORD
  │     │     2. --password       → use argument
  │     │     3. SSH_PASSWORD env → printenv SSH_PASSWORD
  │     │
  │     └─► If none: ERROR "SSH password is required"
  │
  ├─► Step 1: execute_scp (transfer package to /tmp/)
  ├─► Step 2: execute_ssh (archive logs)
  ├─► Step 3: execute_ssh (uninstall)
  ├─► Step 4: execute_ssh (extract package)
  ├─► Step 5: execute_ssh (install)
  ├─► Step 6: execute_ssh (tail log lines)
  │
  └─► exit
```

## Password → SSH/SCP: The Critical Detail

**Important:** The `ssh` and `scp` commands do NOT read any environment variable for the password. They always prompt interactively when using password auth.

To avoid prompts, we need a helper:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  How the password gets to ssh/scp                                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Option A: sshpass (if available)                                           │
│  ─────────────────────────────────                                         │
│    SSHPASS="$SSH_PASSWORD" sshpass -e ssh ...                               │
│    sshpass reads SSHPASS env var and feeds it to ssh's stdin                 │
│    → No prompts                                                              │
│                                                                              │
│  Option B: expect (if available, sshpass not)                               │
│  ─────────────────────────────────────────────────────                     │
│    expect script watches for "password:" prompt, sends $SSH_PASSWORD         │
│    → No prompts (expect automates the interaction)                          │
│                                                                              │
│  Option C: neither sshpass nor expect                                       │
│  ─────────────────────────────────────                                     │
│    Plain: ssh ... or scp ...                                                │
│    → PROMPTS for password each time (6+ times per UDM)                      │
│    → SSH_PASSWORD env var is IGNORED by ssh/scp                             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Env Var Cleanup

| When                    | SSH_PASSWORD state                                      |
|-------------------------|---------------------------------------------------------|
| Start of each UDM loop  | Not set (or from previous UDM, cleared at end of loop) |
| After read password     | `export SSH_PASSWORD="$password"`                      |
| During deploy-to-udm.sh | Available to child (passed explicitly)                  |
| After deploy completes  | Still set (needed for run_tail_f if sshpass available)  |
| End of UDM iteration    | `unset SSH_PASSWORD` ← **cleaned up**                  |
| Next UDM                | Fresh prompt for new password                          |
| Script exit             | Process ends, all env vars gone                        |

## Summary: Will It Prompt?

| Deployer has | Password in env | Result                          |
|--------------|-----------------|---------------------------------|
| sshpass      | Yes             | No prompts (sshpass feeds it)   |
| expect       | Yes             | No prompts (expect sends it)    |
| neither      | Yes             | **Prompts** (ssh/scp ignore env) |

The env var is used by deploy-to-udm.sh for validation and by sshpass/expect for automation. Plain ssh/scp never see it.
