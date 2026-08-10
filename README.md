# OMEGACORTEX Lead Intelligence Agent

Government contract lead pipeline for OMEGACORTEX LLC. Scans SAM.gov (federal) and WEBS (Washington State) procurement portals, tracks opportunities over time, scores them against firm capability, and drafts outreach to contracting officers.

**Success criterion:** Luis opens Gmail, sees a small number of drafts, and trusts each one is a real opportunity OMEGACORTEX can win. Precision over volume. Zero drafts is acceptable. A wrong draft is not.

---

## Start here

New to this project, human or agent: read [`docs/MASTER-HANDOFF.md`](docs/MASTER-HANDOFF.md) in full before touching anything. It assumes zero prior context and covers the environment, incident history, hard rules, and the phased work plan.

For day-to-day operation, see [`docs/RUNBOOK.md`](docs/RUNBOOK.md).

**Every session ends with a handoff.** See [`docs/HANDOFF-PROTOCOL.md`](docs/HANDOFF-PROTOCOL.md) and append to [`docs/SESSION-LOG.md`](docs/SESSION-LOG.md) before you push.

---

## Hard rules

1. **Never write to `~/.n8n/database.sqlite` directly.** Direct SQLite writes corrupted two workflows on Aug 9, 2026 and cost a full night of recovery. Use the n8n CLI or REST API only.
2. **Gmail is drafts only. Never send email.**
3. **Run `scripts/scan-secrets.sh` before every commit.** The SAM.gov API key was hardcoded in a workflow node. Exported workflow JSON can carry credentials.
4. Back up before every mutation.
5. Two workflows fire on schedule every morning. Never leave anything deactivated.

---

## Layout

```
docs/
  MASTER-HANDOFF.md    Full context, incident history, phased work plan
  RUNBOOK.md           Daily operation, failure signatures, traps
  HANDOFF-PROTOCOL.md  Multi-device access, session start/end discipline
  SESSION-LOG.md       Append one entry per session, newest first
  STATUS.md            Verified state and phase progress
scripts/               Backup, decode, verify, secret scan, health check
workflows/             Redacted workflow JSON, committed
backups/               Local exports, gitignored
```

## Working from another device

n8n runs on the **Mac mini** and cannot be copied or synced. Use Tailscale plus SSH so every device is a window into that one instance:

```bash
ssh luislozada@macmini
cd ~/Documents/omegacortex-agent && claude
```

Details in [`docs/HANDOFF-PROTOCOL.md`](docs/HANDOFF-PROTOCOL.md).

---

## Quick reference

| Workflow | ID | Schedule (ET) |
|---|---|---|
| Contract Scanner | `0bTuf3RMzVQHjH8E` | Daily 5:20 AM, Fri 5:40 AM |
| Lead Intelligence v2 | `Om3gaLeadIntelV2` | Daily 6:00 AM |
| Context Failure Logger | `Om3gaContextFailure` | On failure |

n8n 2.33.7 at `http://localhost:5678`, Node 24, LaunchAgent `com.omegacortex.n8n`.

```bash
./scripts/health-check.sh          # is it up and are schedules armed
./scripts/backup.sh                # export, decode, verify
./scripts/scan-secrets.sh          # run before every commit
./scripts/verify-backup.py FILE    # confirm an export is not BLOB-corrupted
```

---

## Current status

See [`docs/STATUS.md`](docs/STATUS.md), updated as phases complete.
