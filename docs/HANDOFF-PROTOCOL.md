# Handoff protocol

Every working session ends with a handoff. No exceptions. This is what makes the project portable across the Mac mini, the MacBook Pro, and any future device.

---

## Where things live

| What | Where | Why |
|---|---|---|
| Docs, handoffs, scripts, workflow JSON | This git repo, pushed to GitHub | Versioned, conflict-free, readable from any device including a phone browser |
| The running n8n instance | Mac mini only, `localhost:5678` | It is a server on the LAN, not a file. It does not sync and cannot be copied. |
| Local exports and snapshots | `backups/`, gitignored | May contain unredacted credentials |

**Do not put handoffs in iCloud, Dropbox, or a synced folder.** No version history, sync conflicts corrupt files mid-write, and it does not work from a phone. The repo is strictly better for this.

---

## Reaching the Mac mini from anywhere

n8n runs on the Mac mini. Work happens there regardless of which device you are sitting at. Other devices are windows into it, not copies of it.

Set up [Tailscale](https://tailscale.com) on the Mac mini and every device you want to work from. Free for personal use, roughly ten minutes, and nothing is exposed to the public internet.

Once connected, from any device:

```bash
ssh luislozada@macmini
cd ~/Documents/omegacortex-agent
claude
```

That session is identical to sitting at the mini. Same n8n, same database, same CLI, no drift.

For the n8n UI, open `http://macmini:5678` in the browser on any Tailscale-connected device.

**Enable Remote Login on the Mac mini** if it isn't already: System Settings, General, Sharing, Remote Login on.

### What cannot be done remotely

Nothing, once Tailscale is up. Without it, a cloud or off-network session cannot reach n8n at all, cannot run `n8n export:workflow`, cannot read `~/.n8n/database.sqlite`, and cannot control the LaunchAgent. A cloud environment is useful only for pure code and docs work.

---

## Ending a session

Run this before you stop, every time.

```bash
./scripts/health-check.sh                  # confirm nothing was left broken
./scripts/scan-secrets.sh                  # never commit credentials
# update docs/STATUS.md with verified state
# append a session entry to docs/SESSION-LOG.md
git add -A && git commit && git push
```

A session that ends without a pushed handoff did not happen. The next device will not know what changed.

### Non-negotiable before stopping

1. No workflow is left deactivated. `Contract Scanner`, `Lead Intelligence v2`, and `Context Failure Logger` must be active and published.
2. `docs/STATUS.md` reflects the live instance, verified, not assumed.
3. A session entry is appended to `docs/SESSION-LOG.md`.
4. Everything is committed and pushed.

If you must stop mid-repair with something broken, say so loudly at the top of the session entry and state exactly what is broken and what the next step is.

---

## Session entry format

Append to `docs/SESSION-LOG.md`, newest at the top.

```markdown
## 2026-08-11 — Mac mini — Phase 0 and 1

**State at start:** 7 workflows, probe still present, SAM.gov failing since Aug 8.

**Done**
- Deleted probe workflow 5ToIbeWkCWOFLywk, instance now 6
- Moved SAM.gov key to n8n credential, rotated at sam.gov
- Sheets backoff to 60000ms on 17 nodes across 3 workflows
- SAM.gov postedFrom 60d -> 10d, limit 1000 -> 200

**Verified**
- Manual Contract Scanner run: SAM.gov returned 184 records, 41 new rows written
- All 3 production workflows active and published
- scan-secrets.sh clean

**Not done**
- Phase 2 routing not started

**Broken or risky**
- None

**Next step**
- Phase 2: branch on Source before Prepare Lead Award Searches

**Needs Luis**
- Gmail OAuth still untested, will need his Google login if the token is stale
```

Be honest in the Broken section. A handoff that hides a problem is worse than no handoff.

---

## Starting a session

```bash
git pull
cat docs/SESSION-LOG.md | head -60      # what happened last
./scripts/health-check.sh               # what is true right now
```

Trust `health-check.sh` over the log. The log says what someone believed; the health check says what is actually running.

---

## Fast triage when something fails

From any device:

```bash
ssh luislozada@macmini
cd ~/Documents/omegacortex-agent && ./scripts/health-check.sh
```

If n8n is down, the script prints the process state, LaunchAgent exit code, and last errors. The most common cause is the Node version, covered in `RUNBOOK.md`.

If n8n is up but a run failed, open `http://macmini:5678/home/executions` and find the red row. `RUNBOOK.md` has the known failure signatures and their fixes.

Remember the failure mode that is not red: a green run that produced nothing. Check that `Select Award Candidates` emitted more than 0 items.
