# Runbook

Day-to-day operation. For architecture, incident history, and the work plan, see [`MASTER-HANDOFF.md`](MASTER-HANDOFF.md).

---

## Daily, two minutes

```bash
./scripts/health-check.sh
```

Then open `http://localhost:5678/home/executions` and look for red.

If Contract Scanner (5:20 AM) and Lead Intelligence v2 (6:00 AM) are both green, you're done.

**A green run that produced nothing is still a failure.** On Aug 10 the 6:00 AM run succeeded in 32 seconds and generated zero drafts because every award query returned nothing. Check that `Select Award Candidates` emitted more than 0 items.

## Weekly, fifteen minutes

Read failure *patterns*, not individual failures. One root cause usually produces many errors. Of 53 failures analyzed on Aug 10, 25 traced to a single cause.

```bash
./scripts/backup.sh
```

Confirm it verifies clean. A backup containing `{"type":"Buffer"}` instead of a node array is not a backup.

Check Gmail still authenticates. Google OAuth tokens die quietly, and if the app is in Testing rather than Production, refresh tokens expire every 7 days.

## Monthly

Rotate the SAM.gov API key.

Prune executions to 30 days. Each stores full payloads.

Test a restore into a clean n8n. An untested backup is not a backup.

---

## Committing

```bash
./scripts/scan-secrets.sh && git add -A && git commit
```

Never commit without the scan. Exported workflow JSON carries whatever was typed directly into HTTP Request and Code nodes, which is how the SAM.gov key ended up in every export.

To enforce it:

```bash
cat > .git/hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
exec "$(git rev-parse --show-toplevel)/scripts/scan-secrets.sh"
EOF
chmod +x .git/hooks/pre-commit
```

---

## Common failures

### n8n will not start

Almost always the Node version. n8n 2.33+ requires Node >= 22.22. `/opt/homebrew/bin/node` is 20.20.2; `/opt/homebrew/opt/node@24/bin/node` is 24.19.0. The LaunchAgent has its own `PATH` and does not inherit your shell's.

```bash
tail -30 ~/Library/Logs/omegacortex-n8n-error.log
grep -A2 "<key>PATH</key>" ~/Library/LaunchAgents/com.omegacortex.n8n.plist
```

`/opt/homebrew/opt/node@24/bin` must come first. After editing the plist, `kickstart` is not enough:

```bash
launchctl bootout gui/501/com.omegacortex.n8n
launchctl bootstrap gui/501 ~/Library/LaunchAgents/com.omegacortex.n8n.plist
```

### A workflow opens as a blank canvas

Its `nodes` are stored as a binary BLOB rather than JSON. On old n8n this silently redirected to a new empty workflow with `?new=true`, which looks exactly like data loss. It is not. The data is intact, just encoded.

```bash
n8n export:workflow --id=<ID> --output=/tmp/wf.json
python3 scripts/verify-backup.py /tmp/wf.json     # expect FAIL
python3 scripts/decode-buffers.py /tmp/wf.json /tmp/wf-fixed.json
n8n import:workflow --input=/tmp/wf-fixed.json
n8n update:workflow --id=<ID> --active=true       # import DEACTIVATES the target
```

Then republish in the UI. Root cause is always a direct write to `database.sqlite`. Find what did it and stop it.

### "The service is receiving too many requests from you"

Google Sheets 429. The quota is 60 requests per minute per user. A 5-second retry lands inside the same exhausted minute, fails, and burns more quota. Set `waitBetweenTries` to 60000 on every Sheets-touching node. The UI caps that field at 5000ms, so apply it via CLI or API.

### SAM.gov ECONNABORTED

The query window and page size are too large. Narrow `postedFrom` to about 10 days and drop `limit` to 200. A daily job does not need a 60-day lookback.

### Claude Code: ConnectionRefused

Not Claude Code. A local proxy called omniroute runs at `localhost:20128`, and if `ANTHROPIC_BASE_URL` points at it while it is down, you get this.

```bash
env | grep -i anthropic
unset ANTHROPIC_BASE_URL
```

---

## Traps

- `n8n import:workflow` **deactivates** the target. Always reactivate and verify.
- `PATCH /rest/workflows/:id` updates the **draft** only. `versionId` is the draft, `activeVersionId` is what runs. Not live until published. A PATCH does not deactivate a published workflow.
- The UI caps `waitBetweenTries` at 5000ms in this build.
- `n8n export:workflow` faithfully exports BLOB corruption. Always verify.
- REST calls need a `browser-id` header matching the session. CLI is simpler.
- Execution data is stored in `flatted` format, not plain JSON. Unflatten before inspecting.
- The Mac must be awake. Missed schedule triggers are **not** caught up.
