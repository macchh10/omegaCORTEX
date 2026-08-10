# Handoff: OMEGACORTEX n8n repair tasks

You are working on a local n8n instance on this Mac. Read this whole brief before touching anything.

## Environment

- n8n **2.33.7**, running at `http://localhost:5678`
- Node **24.19.0** at `/opt/homebrew/opt/node@24/bin/node`. Note `/opt/homebrew/bin/node` is Node 20.20.2 and n8n will refuse to start on it.
- Managed by LaunchAgent `com.omegacortex.n8n`, plist at `~/Library/LaunchAgents/com.omegacortex.n8n.plist`
- Database: SQLite at `~/.n8n/database.sqlite`
- Logs: `~/Library/Logs/omegacortex-n8n.log` and `-error.log`
- Timezone America/New_York

Restart with:

```bash
launchctl kickstart -k gui/501/com.omegacortex.n8n
```

Health check (expect `200`):

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:5678/rest/settings
```

## Hard rules

1. **Never write to `database.sqlite` directly.** Direct SQLite writes are what caused the original damage: two workflows had their `nodes` and `connections` columns stored as binary BLOBs instead of JSON, which made the editor crash with `a.nodes.filter is not a function`. Use the n8n CLI or REST API only.
2. **Back up before every mutation.** Backups already exist in `~/n8n-backups/20260810/`.
3. **These workflows are production.** Two fire on schedule every morning, 5:20 AM and 6:00 AM Eastern. Do not leave anything deactivated.

## Known n8n 2.x behavior you must account for

- Workflows have a draft/published split. `versionId` is the draft, `activeVersionId` is what actually runs. A `PATCH` to `/rest/workflows/:id` updates the draft only. Changes do **not** take effect until published.
- A PATCH does **not** deactivate a published workflow. Verified.
- `n8n import:workflow` **does** deactivate the target workflow. It runs deactivate-then-overwrite. Always reactivate and verify afterward.
- REST calls need a `browser-id` header matching the session, so CLI is usually simpler than curl.

## Current state

| Workflow | ID | Nodes | Status | Schedule (ET) |
|---|---|---|---|---|
| Lead Intelligence v2 | `Om3gaLeadIntelV2` | 43 | Active, published | Daily 6:00 AM |
| Contract Scanner | `0bTuf3RMzVQHjH8E` | 9 | Active, published | Daily 5:20 AM, Fri 5:40 AM |
| Context Failure Logger | `Om3gaContextFailure` | 7 | Active, published | On failure |
| Contract Scanner - WEBS Test | `z0ZcPBe8fDmKcl9I` | 36 | Inactive, **still BLOB** | None |
| Intelligence v2 - Federal Test | `Iv2Tst4k9Qm2Lp7Xs` | 12 | Inactive | Manual |
| Reliability Test Harness | `Om3gaReliabilityHarness` | 6 | Inactive | Manual |
| ZZ TEMP publish-semantics probe | `5ToIbeWkCWOFLywk` | 2 | **Active, delete this** | Daily 11:59 PM |

---

# TASK 1 — Google Sheets rate limiting (highest priority)

## The problem

53 executions failed. 25 of them are Google Sheets `429`, message "The service is receiving too many requests from you". This is the single largest cause and it is not a logic bug.

Google Sheets allows **60 requests per minute per user**. Current retry settings are typically 5 tries at a 5 second wait, and the worst offender is 6 tries at 8 seconds. Every retry lands inside the same already-exhausted quota minute, so retries fail and consume more quota, making downstream nodes fail too.

Node counts hitting Sheets per run: Lead Intelligence v2 makes **12** (11 Google Sheets nodes plus 1 HTTP node calling `sheets.googleapis.com`), Contract Scanner makes 2, Context Failure Logger makes 3.

The single worst node is **`Read Source Context`** in Lead Intelligence v2. It is an `httpRequest` to `https://sheets.googleapis.com/v4/spreadsheets/1e0WbOZrdVTKS3...` set to 6 tries at 8000ms. It alone accounts for 10 of the 53 failures.

## The fix

For every node in the three active workflows where the type is `n8n-nodes-base.googleSheets`, or the type is `n8n-nodes-base.httpRequest` and its parameters contain `sheets.googleapis.com`, set:

```
retryOnFail: true
maxTries: 3
waitBetweenTries: 60000
```

60000ms pushes each retry into a fresh quota window. Note the n8n **UI** caps this field at 5000ms in some builds, so apply it through the CLI or API, not by hand in the editor.

## Suggested approach

Export, transform with Python, import, reactivate, verify. Roughly:

```bash
n8n export:workflow --id=Om3gaLeadIntelV2 --output=/tmp/li.json
# transform JSON
n8n import:workflow --input=/tmp/li-fixed.json
n8n update:workflow --id=Om3gaLeadIntelV2 --active=true
```

Verify `active` is true and the workflow appears in `/rest/active-workflows` afterward. Check the editor opens and shows the published badge.

If you prefer the REST API, remember the draft/published split above and publish explicitly.

## After this fix

Expect runs to be **slower** and to **succeed**. A retry now costs a minute instead of failing. That trade is correct.

The durable fix, which is a larger job, is reducing the 12 Sheets calls in Lead Intelligence v2. Several nodes read the same spreadsheet independently and could be consolidated into one read passed through Code nodes. Propose a plan, do not do this unattended.

---

# TASK 2 — Repair Contract Scanner - WEBS Test

Workflow `z0ZcPBe8fDmKcl9I` still has `nodes` and `connections` stored as binary BLOBs. It cannot be opened or published.

A clean decoded copy with all 36 nodes already exists at:

```
~/n8n-backups/20260810/webs-test-fixed.json
```

Importing it previously failed with:

```
Active version not found for workflow
SQLITE_CONSTRAINT: FOREIGN KEY constraint failed
```

Cause: n8n 2.x expects each workflow row to point at an active version record, and this one's is missing. The migration could not create it because building a version requires parsing the nodes, and the nodes were unreadable. The import deactivates first and overwrites second, so the deactivation committed while the data write rolled back.

Approaches worth trying, in order of preference:

1. Import under a **new ID** as a fresh workflow, confirm it opens with 36 nodes, then delete the broken original.
2. Investigate the workflow version tables and repair the missing active-version row through the API.

This workflow is inactive and unscheduled, so nothing depends on it. Do not risk the production workflows to save it.

---

# TASK 3 — Delete the probe workflow

`5ToIbeWkCWOFLywk`, named `ZZ TEMP publish-semantics probe (safe to delete)`. It was created to test publish semantics and is currently active with a trigger at 11:59 PM. It only passes data through a Code node, so it is harmless, but it should not be on the instance. Delete it.

---

# TASK 4 — Verify Gmail credentials

The Gmail OAuth credential has not been exercised since n8n was upgraded from 2.8.4 to 2.33.7 and every dependency was reinstalled. One execution in the log failed with `Forbidden - perhaps check your credentials?`.

Lead Intelligence v2 contains `Create Gmail Draft - Never Send` and `Search Gmail Outreach History`. **Drafts only. Never send email.** That constraint is absolute and comes from the owner.

Check whether the credential still authenticates. If the token is stale, do not attempt to re-authenticate yourself, since that requires the owner's Google login. Report it and stop.

Related background the owner already knows: the Google Cloud OAuth app should be in Production, not Testing, or refresh tokens expire every 7 days. Project number `483574768857`.

---

# TASK 5 — Remaining execution failures

After the rate-limit fix, these remain from the failure analysis:

- **7x HTTP timeouts** on SAM.gov (`ECONNABORTED`, connection timed out). One run spent 5m45s before aborting. Raise the request timeout and confirm retry settings on `SAM.gov Query` in Contract Scanner.
- **4x** `Sheet with ID All Leads not found` and **1x** `Sheet with name Agency Intel not found`. A tab was renamed or moved, or a node points at the wrong spreadsheet. Needs checking against the actual Google Sheet.
- **4x** `Column names were updated after the node's setup`. Google Sheets nodes cached a header row that has since changed. The node's column mapping must be refreshed.
- **3x** `The workflow has issues and cannot be executed`. A node is misconfigured. Open the workflow and find the node showing an error triangle.
- **3x Code node syntax errors**: `Invalid or unexpected token`, `Unexpected token ')'`, and one referencing `[line 210]`. These are hard failures that no retry will fix. Find and repair them.

---

# Verification checklist

When done, confirm all of the following:

1. `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:5678/rest/settings` returns `200`
2. All three production workflows show `active: true` and appear in `/rest/active-workflows`
3. Each opens in the editor without error and shows a green published badge
4. Every Sheets-touching node reports `waitBetweenTries: 60000`
5. The probe workflow is gone
6. `pmset -g sched` still shows `wakepoweron at 5:00AM every day`
7. A manual run of Lead Intelligence v2 completes further than before, and you report exactly which node it stops at

## Report back

State plainly what you fixed, what you could not fix, and what still needs the owner. Do not claim success without verifying against the live instance. The owner does his own debugging and will check your work.
