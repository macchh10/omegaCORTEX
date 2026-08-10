# OMEGACORTEX n8n — Recovery & Failure Diagnosis
**Night of Aug 10, 2026**

---

## 1. Your workflow was never lost

Lead Intelligence v2 is fully recovered: 43 nodes, all connections, published and active.

### What actually happened

Something wrote directly to your SQLite database on **Aug 9 at 03:32:56** and stored the `nodes` and `connections` columns for two workflows as **raw binary BLOBs** instead of JSON. Both broken records share that timestamp to the millisecond, one at `.680` and one at `.681`, so it was a single scripted operation.

The n8n editor calls `nodes.filter()` when opening a workflow. Against a BLOB that throws `a.nodes.filter is not a function`. On n8n 2.8.4 that crash was swallowed and the router silently redirected you to a blank new workflow, which is why it looked like your work had vanished.

The correlation was perfect once measured:

| Workflow | `nodes` stored as | Opened? |
|---|---|---|
| Lead Intelligence v2 (43) | Buffer BLOB | No |
| Contract Scanner - WEBS Test (36) | Buffer BLOB | No |
| Contract Scanner (9) | array | Yes |
| Context Failure Logger (7) | array | Yes |
| Reliability Test Harness (6) | array | Yes |
| Intelligence v2 - Federal Test (12) | array | Yes |

Node count was a red herring. Storage format was the variable.

### The repair chain

Upgrading n8n from 2.8.4 to 2.33.7 did not fix the data, but it made n8n report the real error instead of hiding it behind a redirect. That upgrade then exposed a second, unrelated problem: your LaunchAgent's `PATH` started with `/opt/homebrew/bin`, which is Node **20.20.2**, while n8n 2.33 requires **22.22+**. Your shell worked because it resolves `/opt/homebrew/opt/node@24/bin` first. Fixed by reordering `PATH` in the plist.

Final step was decoding the byte array back to JSON locally and reimporting through n8n's own CLI so it was written correctly.

### Still outstanding

**Contract Scanner - WEBS Test** is still stored as a BLOB. Its import failed with `SQLITE_CONSTRAINT: FOREIGN KEY constraint failed`, caused by a missing active-version record that n8n 2.x's versioning expects. The import deactivates first and overwrites second, so the deactivation committed and the data write rolled back. That's why it now shows neither published nor publishable.

Its decoded content is safe at `/tmp/webs-test-fixed.json` with all 36 nodes. It's inactive and unscheduled, so nothing depends on it.

---

## 2. The 88.9% failure rate

53 failed executions analyzed. This is not a logic problem in your agent.

| Cause | Count |
|---|---|
| Google Sheets 429 rate limit | 25 |
| HTTP timeouts (SAM.gov) | 7 |
| Sheets schema stale ("column names were updated") | 4 |
| Sheet tab "All Leads" not found | 4 |
| Resource not found | 4 |
| Workflow config invalid | 3 |
| Code node syntax errors | 3 |
| Credential forbidden | 1 |
| Other | 2 |

**Roughly half of every failure is one thing: Google Sheets quota.**

### Why your existing retries don't help

Retry is already configured on nearly every node, typically 5 tries with a 5 second wait. That looked right but is the wrong shape for this specific error.

Google Sheets enforces a quota of **60 requests per minute, per user**. Five retries at 5 seconds spans 25 seconds, so every retry lands inside the *same* quota minute that is already exhausted. They all fail, and each one consumes more quota, making the next node likelier to fail too. The retries are actively making it worse.

### The structural cause

Lead Intelligence v2 makes **12 separate Google Sheets calls** in a single run (11 Sheets nodes plus 1 HTTP node hitting `sheets.googleapis.com`). Contract Scanner adds 2, Context Failure Logger adds 3. Several use `appendOrUpdate`, which issues multiple API requests per node depending on row count.

When Contract Scanner runs at 5:20 and Lead Intelligence at 6:00, they draw on the same per-user quota pool.

### The fix, in priority order

1. **Raise backoff past the quota window.** Set `waitBetweenTries` to 60000ms on all Google Sheets nodes so a retry lands in a fresh quota minute. This alone should convert most of those 25 failures into successes. Runs get slower, they stop failing.
2. **Reduce total call count.** The durable fix. Consolidate the 12 Sheets calls in Lead Intelligence v2. Several read the same spreadsheet separately and could be a single read passed through Code nodes.
3. **Fix the tab name mismatch.** "Sheet with ID All Leads not found" and "Sheet with name Agency Intel not found" mean a tab was renamed, moved, or the node points at the wrong spreadsheet.
4. **Re-map the stale Sheets nodes.** "Column names were updated after the node's setup" means the node cached a header row that has since changed. Reopen the node and refresh its column mapping.
5. **Fix the 3 Code node syntax errors.** `Invalid or unexpected token` and `Unexpected token ')'` are hard failures that no retry will fix.
6. **Raise SAM.gov timeouts.** 7 failures were `ECONNABORTED` and connection timeouts. One run spent 5m45s before aborting.

---

## 3. Why I stopped short of applying the fixes

I verified the PATCH API works cleanly against an inactive workflow. Nodes survive as a proper array and active state is preserved.

What I could not safely test is what happens when you PATCH a **published, active** workflow under n8n 2.x's new versioning model. If editing creates an unpublished draft, Lead Intelligence v2 would silently stop being scheduled, and your 6:00 AM run tomorrow would not fire at all.

Trading a partial failure for a guaranteed no-run, unattended, with you asleep, is not a good trade. The fixes are worth about 10 minutes with you awake to confirm the published badge stays green.

---

## 4. Current state

Verified live against the running instance:

| Workflow | Nodes | Status | Schedule (ET) |
|---|---|---|---|
| Lead Intelligence v2 | 43 | Active, published | Daily 6:00 AM |
| Contract Scanner | 9 | Active, published | Daily 5:20 AM + Fri 5:40 AM |
| Context Failure Logger | 7 | Active | On failure |
| Contract Scanner - WEBS Test | 36 | Inactive, still BLOB | None |
| Intelligence v2 - Federal Test | 12 | Inactive | Manual |
| Reliability Test Harness | 6 | Inactive | Manual |

Running n8n **2.33.7** on Node **24.19.0**, timezone America/New_York.

### Backups

- `~/n8n-backups/20260810/all-workflows.json` — all 6, but the 2 corrupted ones are still Buffer-encoded in this file
- `/tmp/lead-intel-v2-fixed.json` — 43 nodes, decoded and clean
- `/tmp/webs-test-fixed.json` — 36 nodes, decoded and clean
- `~/n8n-backups/20260810/com.omegacortex.n8n.plist.bak`

Note the main backup does **not** contain usable copies of the two corrupted workflows. The decoded `/tmp` files are the good copies, and `/tmp` is cleared on reboot. Move them somewhere permanent.

---

## 5. Risks for tomorrow morning

**Sleep.** If the Mac is asleep at 5:20, both runs are skipped silently. n8n does not catch up missed schedule triggers. Confirm `pmset -g sched` shows the wake.

**Gmail OAuth.** Untested since the version jump and full dependency reinstall. One failure in the log was already `Forbidden - perhaps check your credentials`. If the token is stale, the run reaches the draft step and dies there.

**Rate limiting is unchanged.** Nothing from section 2 has been applied. Expect roughly the same failure pattern at 6:00 AM.

---

## 6. First things to do when you're up

Confirm the wake schedule stuck, move the two decoded JSON files out of `/tmp`, then run Lead Intelligence v2 manually once and watch where it dies. That single run tells us whether Gmail still authenticates and confirms the rate-limit diagnosis before we change anything.

Then we apply the backoff fix and watch the published badge to make sure it stays green.
