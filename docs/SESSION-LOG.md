# Session log

Newest first. Format and rules in [`HANDOFF-PROTOCOL.md`](HANDOFF-PROTOCOL.md).

Every session appends an entry here before pushing. A session without a pushed handoff did not happen.

---

## 2026-08-10 22:50 — Mac mini — Phase 0.2/0.3, 1 params, 2, WA awards

**State at start:** Live instance already had Phase 0.3 Sheets backoff and Phase 1 SAM query params on production workflows (contrary to stale STATUS/SESSION-LOG). Phase 2 / WA awards / toggle-sam scripts were missing from the repo. Probe present and active. SAM.gov API key still plaintext on SAM.gov Query nodes. Agent Intel v2 Scoring had been 0 when only WEBS leads were researched.

**Done**
- Created and applied `scripts/apply-phase-2.sh`: IF `Route by Source` (WEBS), Code `Bypass Award Research`, Merge `Join Award Paths`; Scoring fed only from Join. Lead Intelligence v2 now **46** nodes.
- Created and applied `scripts/apply-wa-awards.sh`: Scoring + Evaluate Draft Eligibility treat state/WEBS leads as `Evidence Confidence: N/A - State` and do not block Pursue/drafts solely for missing federal award history.
- Created `scripts/toggle-sam.sh` and set SAM intake **off** on Contract Scanner + WEBS Test (node disabled, NAICS→SAM disconnected).
- Restored WEBS Test from fixed backup to **36** nodes (was BLOB-corrupted again); left inactive/unpublished.
- Imported credential `SamGovApiKey01` / `SAM.gov API Key` (`httpQueryAuth`, query name `api_key`). Patched both SAM.gov Query nodes to `genericCredentialType` + credential; removed embedded `api_key` param. Live full export: **no `SAM-9667` plaintext**.
- Unpublished and deactivated probe `5ToIbeWkCWOFLywk` (no CLI delete in 2.33.7). Still listed in inventory.
- Reconfirmed production trio active + published: Lead Intel, Contract Scanner, Context Failure Logger.
- `scripts/scan-secrets.sh` clean on the repo.

**Verified (live)**
- Health 200; n8n 2.33.7; Node 24.19.0; wake 5:00 AM.
- Sheets backoff 60000ms: Lead Intel 11/11, Scanner 2/2, Failure Logger 3/3.
- Scanner SAM: `limit=200`, timeout 120000, credentialed, **disabled**.
- Exec **118** (post Phase 2): success; Scoring non-zero via WEBS bypass path.
- Exec **119** (post WA awards): success; state evidence path; gate no longer Low-evidence blocking WEBS; remaining blockers capability/priority/deadline/active.
- Lifetime at handoff: 119 executions, 54 errors.

**Not done**
- Probe not fully deleted (UI delete still required) — instance 7 workflows, should be 6.
- SAM.gov key **not rotated** at sam.gov (Luis only).
- SAM intake left off on purpose until rotation + intentional re-enable.
- Phase 3 relevance model not started.
- No new Gmail drafts expected until relevance/capability scoring improves; Gmail still drafts-only.

**Broken or risky**
- Old SAM key may still exist in `~/n8n-backups/` and pre-fix exports — rotate before treating intake as safe.
- WEBS Test SAM node still has legacy `limit=1000` (disabled, non-prod).
- `n8n execute` conflicts with LaunchAgent ports; bootout/execute/bootstrap if manual CLI runs are needed.
- Never write `~/.n8n/database.sqlite` directly.

**Next step**
1. Luis: rotate SAM.gov API key; update n8n credential `SAM.gov API Key`.
2. Luis: delete probe workflow in UI.
3. When ready for federal intake: `./scripts/toggle-sam.sh on --yes`, publish Scanner, restart, manual Scanner run, confirm records.
4. Phase 3: relevance / capability model (FSIPAP-class signal, exclusions, deadlines).

**Needs Luis**
- SAM key rotation + credential value update
- Probe UI delete
- FSIPAP (HCA, closes Aug 19) — manual pursuit, does not wait on agent
- Gmail OAuth if draft creation fails on next eligible run

## 2026-08-10 23:15 — Phase 0.3 + Phase 1 automation prepared

**Built** `scripts/apply-phase-0-1.sh`. One command applies the Sheets backoff
and the SAM.gov query fix, with export, decode, diff preview, confirmation
prompt, import, reactivate, and live verification. Idempotent, safe to re-run.
Transform logic dry-run tested against realistic node structures.

**Key finding that reshaped the plan.** Mapped the full connection graph of Lead
Intelligence v2. The entire scoring and draft chain hangs off award research in
series: Select Award Candidates -> award fetches -> Normalize Award Intelligence
-> Agent Intel v2 Scoring -> draft gate -> Gmail. When award candidates hit zero,
everything downstream starves.

But the award research is not broken. USASpending works correctly for SAM.gov
opportunities. It returned zeros only because Contract Scanner has been dead
since Aug 8, leaving nothing but WEBS records to research. **Restoring intake
should unblock the draft chain without touching business logic.** This makes
Phase 2 routing a quality improvement rather than a prerequisite.

**Not applied.** Writes to the live instance are blocked on the assistant side by
a safety classifier. The script exists so Luis runs it himself.

**Next step**
Run `./scripts/apply-phase-0-1.sh`, republish all three workflows in the UI,
then manually execute Contract Scanner and confirm SAM.gov returns records.

**Still manual**
Delete the probe workflow. Move the SAM.gov key to a credential and rotate it.

## 2026-08-10 19:00 — Full verification scan — no changes made

**Purpose:** confirm whether the system is production-ready. Read-only scan.

**Verdict: not ready. Zero phases executed. State identical to the 3:54 PM scan.**

**Verified against the live instance**
- 7 workflows present, should be 6. Probe `5ToIbeWkCWOFLywk` still active with an 11:59 PM trigger.
- `SAM.gov Query` unchanged: `limit=1000`, `postedFrom` 60 days. Still failing.
- SAM.gov API key still hardcoded in plaintext on that node.
- Sheets backoff unapplied: 0/12 Lead Intelligence, 0/2 Contract Scanner, 0/3 Failure Logger.
- All three production workflows active, published, schedules armed.
- Lifetime: 117 executions, 54 errors, 46% failure rate.
- Last runs: exec 117 Lead Intelligence success in 32s producing 0 drafts; exec 116 Contract Scanner error after 345s.

**What works**
Lead Intelligence v2 executes end to end without crashing and writes Opportunity State and all four Context Hub tabs.

**What does not**
Intake is dead, so no new leads arrive. Award research returns 0 candidates, so scoring, the draft gate, and Gmail never execute. Net output is zero drafts.

**Next step**
Phase 0 in `MASTER-HANDOFF.md` §7. Nothing has begun.

## 2026-08-10 — Mac mini — Emergency recovery

**State at start:** Lead Intelligence v2 appeared to have lost all 43 nodes. Opening it showed a blank canvas. 88.9% execution failure rate.

**Done**
- Diagnosed the blank canvas. Nothing was lost. Two workflows had `nodes` and `connections` written to SQLite as binary BLOBs instead of JSON, on Aug 9 at 03:32:56, both to the same millisecond, indicating one scripted operation. The editor calls `nodes.filter()` on open, which throws against a BLOB. n8n 2.8.4 swallowed that crash and silently redirected to a new empty workflow, which looked exactly like data loss.
- Upgraded n8n 2.8.4 to 2.33.7. This did not repair data but made n8n report the real error instead of hiding it.
- Fixed a LaunchAgent Node version mismatch. The plist `PATH` began with `/opt/homebrew/bin` (Node 20.20.2) while n8n 2.33 requires 22.22+. Prepended `/opt/homebrew/opt/node@24/bin`.
- Recovered Lead Intelligence v2 by decoding the byte arrays back to JSON and reimporting. All 43 nodes intact.
- Contract Scanner - WEBS Test subsequently repaired to 36 nodes.
- Confirmed `pmset repeat wakeorpoweron` daily 5:00 AM wake.
- Analyzed all 53 failed executions and categorized root causes.

**Verified**
- Execution 117, Lead Intelligence v2, Aug 10 6:00:13 AM: success in 32 seconds, first clean end-to-end run
- All three production workflows active, published, registered in `/rest/active-workflows`

**Not done**
- Every phase in the master handoff. Nothing from Section 7 has been executed.

**Broken or risky**
- Contract Scanner fails every run at `SAM.gov Query` with `ECONNABORTED` after 345 seconds. Query requests limit=1000 over a 60-day window per NAICS code against a 60-second timeout. Failing since at least Aug 8, so no new federal leads are arriving.
- Award research queries USASpending, which is federal-only, using Washington State agency names from WEBS leads. In execution 117 all 25 searches returned 0 results, so the draft chain never executed. Zero drafts.
- No relevance model. The agent surfaces whatever changed rather than what OMEGACORTEX can win. Its 25 "research-worthy" leads included a networking mixer, welding equipment, land appraisals, and forest health work. Two had 0 and 1 days remaining.
- SAM.gov API key hardcoded in plain text in the `SAM.gov Query` node, therefore present in every export under `~/n8n-backups/`.
- Probe workflow `5ToIbeWkCWOFLywk` still active. Instance has 7 workflows, should have 6.
- Google Sheets backoff not applied. 25 of 53 failures were Sheets 429. Did not recur on Aug 10 only because Contract Scanner failed early and never consumed quota. Expect it back once the scanner works.

**Next step**
- Phase 0 in `MASTER-HANDOFF.md` Section 7.

**Needs Luis**
- **FSIPAP**, WA Health Care Authority, closes **Aug 19**. Contact Jack Kent, `jack.kent@hca.wa.gov`. Interoperability plus prior authorization is CMS-0057-F, the exact stated specialty, on a state vehicle with no certification blocker. Highest-value lead in the pipeline and it does not require the agent to be fixed.
- Gmail OAuth untested since the upgrade. Re-authentication requires his Google login.
- 22 legacy Gmail drafts predate the current gate and should not be treated as recommendations. Deleting them needs approval.
