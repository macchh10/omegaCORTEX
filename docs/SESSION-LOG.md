# Session log

Newest first. Format and rules in [`HANDOFF-PROTOCOL.md`](HANDOFF-PROTOCOL.md).

Every session appends an entry here before pushing. A session without a pushed handoff did not happen.

---

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
