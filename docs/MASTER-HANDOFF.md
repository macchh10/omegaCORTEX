# OMEGACORTEX Lead Intelligence Agent — Master Handoff

Single source of truth. Supersedes `claude-code-handoff.md`, `claude-code-handoff-round2.md`, and `omegacortex-final-work-order.md`. Written Aug 10, 2026.

Assume no prior context. Read this entire document before touching anything.

---

# 1. What this system is for

**OMEGACORTEX LLC** is a three-person AI engineering and systems integration firm in Sammamish, Washington. This n8n system is its government contract lead pipeline. It scans federal (SAM.gov) and Washington State (WEBS) procurement portals, tracks opportunities over time, scores them, and drafts outreach emails to contracting officers.

**Owner and primary user:** Luis Lozada, Sales Director. He does his own debugging and will check your work.

**The single success criterion:** Luis opens Gmail, sees a small number of drafts, and trusts that each one is a real opportunity OMEGACORTEX can win. Volume is not the goal. Precision is. Zero drafts is an acceptable output. A wrong draft is not.

## Capability profile (needed for scoring work)

Core specialties:
- Applied LLM systems, document intelligence, agentic pipelines
- Healthcare interoperability: HL7 FHIR, Da Vinci implementation guides, CMS-0057-F compliance
- Enterprise integration: SAP PI/PO, CPI, Integration Suite (10+ years)
- Linux and cloud infrastructure, automation, identity and access management

Team: Ivan Lozada (Founder, 25 years enterprise IT and mission-critical infrastructure), Antonio Lozada (Technical Director, SAP integration), Luis Lozada (Sales Director).

Status and certifications:
- Washington State Micro Business
- Registered WEBS vendor
- HIPAA-ready
- OMWBE certification **in process**

**Certification blockers.** Cannot prime on set-asides for HUBZone, 8(a), SDVOSB, WOSB/EDWOSB, or Buy Indian. No federal corporate past performance yet. These are teaming targets only.

**Practical consequence:** Washington State work is more accessible than federal right now. Already a WEBS vendor, no set-aside blockers, local presence. Do not treat state leads as second-class.

---

# 2. Environment

- **n8n 2.33.7** at `http://localhost:5678`
- **Node 24.19.0** at `/opt/homebrew/opt/node@24/bin/node`. Critical: `/opt/homebrew/bin/node` is Node 20.20.2 and n8n refuses to start on it.
- Installed globally via npm at `/opt/homebrew/lib/node_modules/n8n`, not Homebrew formula
- Database: SQLite at `~/.n8n/database.sqlite`
- LaunchAgent `com.omegacortex.n8n`, plist at `~/Library/LaunchAgents/com.omegacortex.n8n.plist`
- Working directory: `/Users/luislozada/Documents/New project`
- Logs: `~/Library/Logs/omegacortex-n8n.log` and `omegacortex-n8n-error.log`
- Timezone: America/New_York
- Mac wakes daily at 5:00 AM via `pmset repeat wakeorpoweron`

Restart:
```bash
launchctl kickstart -k gui/501/com.omegacortex.n8n
```

Reload after editing the plist (kickstart alone will not pick up plist changes):
```bash
launchctl bootout gui/501/com.omegacortex.n8n
launchctl bootstrap gui/501 ~/Library/LaunchAgents/com.omegacortex.n8n.plist
```

Health check, expect `200`:
```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:5678/rest/settings
```

**Note on Claude Code connectivity.** A local LLM proxy called **omniroute** runs at `localhost:20128`. If `ANTHROPIC_BASE_URL` points at it and omniroute is down, Claude Code fails with `ConnectionRefused`. Check with `env | grep -i anthropic`. Prefer `unset ANTHROPIC_BASE_URL` while doing production work.

---

# 3. Workflow inventory

| Workflow | ID | Nodes | State | Schedule (ET) |
|---|---|---|---|---|
| Lead Intelligence v2 | `Om3gaLeadIntelV2` | 43 | Active, published | Daily 6:00 AM |
| Contract Scanner | `0bTuf3RMzVQHjH8E` | 9 | Active, published | Daily 5:20 AM, Fri 5:40 AM |
| Context Failure Logger | `Om3gaContextFailure` | 7 | Active | On failure |
| Contract Scanner - WEBS Test | `z0ZcPBe8fDmKcl9I` | 36 | Inactive | None |
| Intelligence v2 - Federal Test | `Iv2Tst4k9Qm2Lp7Xs` | 12 | Inactive | Manual |
| Reliability Test Harness | `Om3gaReliabilityHarness` | 6 | Inactive | Manual |
| ZZ TEMP publish-semantics probe | `5ToIbeWkCWOFLywk` | 2 | **Active — DELETE THIS** | 11:59 PM |

The probe was created during diagnosis to test n8n publish behavior. It is disposable. Instance should end with 6 workflows.

## Pipeline flow

```
5:20 AM  Contract Scanner    SAM.gov + USASpending  ->  All Leads (Sheets)
6:00 AM  Lead Intelligence   All Leads -> Opportunity State -> Agent Intel
                             -> award research -> draft gate -> Gmail draft
```

Contract Scanner feeds Lead Intelligence. If the scanner fails, no new leads arrive and the whole pipeline runs on stale data.

## Data model

Google Sheets is the system of record. Known tabs: All Leads, Opportunity State, Agent Intel, Award Intelligence, Agency Intel, Outreach Queue, WEBS Leads, Company Profile, Scoring Model, plus Context Hub tabs (README, Current Snapshot, Run History, ChatGPT Brief).

There is an **open, unfinished project** to consolidate three separate workbooks (SOURCE, OPERATING, HUB) into one master workbook, promoting SOURCE as the single file and freezing the others as read-only archives. Known problems in that plan: outreach data is dual-written to both SOURCE Outreach Queue and OPERATING Contract Outreach, and Award Intelligence has internal duplicates (970 rows for 188 unique keys). **Do not start this merge without Luis. It is out of scope for the current work.**

---

# 4. Incident history and root causes

## 4.1 Workflow corruption (resolved)

On **Aug 9 at 03:32:56**, two workflows had their `nodes` and `connections` columns written to SQLite as **binary BLOBs instead of JSON**. Both share that timestamp to the millisecond (`.680` and `.681`), indicating one scripted operation.

The n8n editor calls `nodes.filter()` on open. Against a BLOB this throws `a.nodes.filter is not a function`. On n8n 2.8.4 that crash was swallowed and the router silently redirected to a blank new workflow with `?new=true`, making it appear the work had been deleted. It had not. Node count was a red herring; storage format was the variable.

**Suspected cause:** a prior automated session writing directly to `database.sqlite`. Claude Code history references that file path, and issue #42 in that history reads "Trigger recurrence rules stripped during n8n restart; schedules non-functional," which fits the same pattern.

**Resolution:** upgraded n8n 2.8.4 to 2.33.7 (which surfaced the real error instead of hiding it), decoded the byte arrays back to JSON, reimported via CLI. Lead Intelligence v2 fully recovered with all 43 nodes. WEBS Test was subsequently repaired to 36 nodes.

## 4.2 Node version mismatch (resolved)

After upgrading, n8n would not boot. The LaunchAgent's `PATH` began with `/opt/homebrew/bin` (Node 20.20.2) while n8n 2.33 requires 22.22+. The shell worked because it resolves `node@24` first. Fixed by prepending `/opt/homebrew/opt/node@24/bin` to the plist `PATH`.

## 4.3 Google Sheets rate limiting (diagnosed, unfixed)

Of 53 failed executions analyzed, **25 were Google Sheets 429**, "The service is receiving too many requests from you."

Sheets allows **60 requests per minute per user**. Retry is configured almost everywhere at 5 tries with a 5-second wait, and the worst node at 6 tries with 8 seconds. Every retry lands inside the same already-exhausted quota minute, fails, and consumes more quota. **The retry configuration is actively making it worse.**

Sheets calls per run: Lead Intelligence v2 makes 12 (11 Sheets nodes plus one HTTP node to `sheets.googleapis.com`), Contract Scanner 2, Context Failure Logger 3.

Note: this did **not** recur on Aug 10, because Contract Scanner failed early and never consumed quota. Expect it to return the moment the scanner is fixed.

## 4.4 SAM.gov timeout (diagnosed, unfixed)

`SAM.gov Query` in Contract Scanner has failed every run since at least Aug 8 with `ECONNABORTED` after 345 seconds.

The query requests `limit=1000` over a **60-day** window, per NAICS code, batched one at a time, with a 60-second timeout. Each attempt exceeds the timeout; five retries burn 345 seconds. The workflow runs daily, so a 60-day lookback re-requests the same two months every morning.

## 4.5 Award research queries the wrong database (diagnosed, unfixed)

In execution 117, `Select Leads for Research` chose 25 leads, `Search Comparable Awards` ran 25 queries, and **every one returned 0 results**. `Select Award Candidates` emitted 0 items, so award intel, scoring, the draft gate, and Gmail draft creation never executed.

Cause: all 25 leads came from **WEBS** (Washington State) while the query targets **USASpending** (federal only). It sent agency names like `Thurston EDC`, `Okanogan County Transit Authority`, and `University of Washington` as federal toptier agencies. Those can never match.

This compounds with 4.4. With the SAM.gov scanner down, only WEBS records change, so every award query is doomed.

## 4.6 No relevance model (the real problem)

The agent surfaces whatever changed rather than what OMEGACORTEX can win. Its 25 "research-worthy" leads on Aug 10 included a networking mixer, welding equipment, land appraisals, forest health work, and youth social services. Two had 0 and 1 days remaining.

Meanwhile the single best-fit opportunity in the pipeline received no special treatment. See section 7.

---

# 5. Current verified state (Aug 10, 3:54 PM ET)

- n8n 2.33.7 on Node 24, healthy, responding 200
- Execution **117**, Lead Intelligence v2, Aug 10 6:00:13 AM: **success in 32 seconds**, first clean end-to-end run
- Execution **116**, Contract Scanner, Aug 10 5:20:11 AM: **error** after 345 seconds, SAM.gov timeout
- All three production workflows active, published, and registered in `/rest/active-workflows`
- Sheets backoff fix: **not applied** (0 of 12, 0 of 2, 0 of 3 nodes)
- Probe workflow: **still present**, instance has 7 workflows
- Gmail credential: **untested** since upgrade; execution 117 never reached those nodes
- 117 executions stored with full payloads

Execution 117 node-by-node:
```
Read All Leads               534 items
Read Opportunity State       519 items
Classify Opportunity Changes 519 items
Changed Opportunity State     34 items
Opportunity State Output      34 items
Read Existing Agent Intel    241 items
Read Agency Intel            100 items
Select Leads for Research     25 items
Search Comparable Awards      25 items
Select Award Candidates        0 items   <- pipeline stops
```

## Backups

- `~/n8n-backups/20260810/all-workflows.json` — all 6, but the two formerly corrupted workflows are Buffer-encoded and **unusable** in this file
- `~/n8n-backups/20260810/lead-intel-v2-fixed.json` — 43 nodes, decoded, clean
- `~/n8n-backups/20260810/webs-test-fixed.json` — 36 nodes, decoded, clean
- `~/n8n-backups/20260810/com.omegacortex.n8n.plist.bak`

---

# 6. Hard rules

1. **Never write to `~/.n8n/database.sqlite` directly.** This caused the original corruption. Use the n8n CLI or REST API only. This rule is non-negotiable.
2. **Gmail is drafts only. Never send email.** Absolute, from the owner.
3. **Back up before every mutation.**
4. Two workflows fire on schedule every morning. Never leave anything deactivated.
5. Do not commit anything to git until the API key in section 8.1 is removed and rotated.

## Traps that will cost you hours

- `n8n import:workflow` **deactivates** the target workflow. It runs deactivate-then-overwrite. Always reactivate and verify afterward.
- A `PATCH` to `/rest/workflows/:id` updates the **draft** only. `versionId` is the draft, `activeVersionId` is what actually runs. Changes are not live until published. A PATCH does **not** deactivate a published workflow (verified).
- The n8n UI caps `waitBetweenTries` at 5000ms in this build. Apply larger values via CLI or API.
- `n8n export:workflow` faithfully exports BLOB corruption as `{"type":"Buffer","data":[...]}`. Verify exports contain real arrays: `python3 -c "import json;d=json.load(open(F));print(type(d[0]['nodes']).__name__, len(d[0]['nodes']))"` should print `list` and a count, not `dict 2`.
- REST calls need a `browser-id` header matching the session. CLI is usually simpler.
- Execution data is stored in `flatted` format, not plain JSON. It needs unflattening before inspection.

---

# 7. The work, in dependency order

Do not advance a phase until its acceptance criteria pass.

## PHASE 0 — Housekeeping

**0.1** Delete workflow `5ToIbeWkCWOFLywk` (`ZZ TEMP publish-semantics probe`). Instance ends with 6.

**0.2** The SAM.gov API key is hardcoded in plain text as the `api_key` query parameter on the `SAM.gov Query` node, beginning `SAM-9667a6e3`. It is therefore present in every export under `~/n8n-backups/`. Move it to an n8n credential or environment variable, then rotate it at sam.gov.

**0.3** Apply Sheets backoff. For every `n8n-nodes-base.googleSheets` node and every `httpRequest` node whose parameters contain `sheets.googleapis.com`, set `retryOnFail: true`, `maxTries: 3`, `waitBetweenTries: 60000`.

**Acceptance:** 6 workflows; all Sheets-touching nodes at 60000ms; no plaintext key in any workflow JSON.

## PHASE 1 — Restore lead intake

**1.1** `postedFrom`: 60 days to **10 days**.
**1.2** `limit`: `1000` to **200**.
**1.3** If still timing out, `options.timeout` to `120000`.

**Acceptance:** Manual Contract Scanner run completes, `SAM.gov Query` returns records, `Google Sheet Output` writes new SAM.gov rows to All Leads.

## PHASE 2 — Route enrichment by source

**2.1** Branch on `Source` before `Prepare Lead Award Searches`. `SAM.gov` follows the existing USASpending path. `WEBS` skips award research entirely and passes to scoring with `Award Evidence = "N/A - State opportunity"`.

**2.2** WEBS leads must not be penalized for missing federal award history. Its absence is expected, not a negative signal.

**Acceptance:** A mixed run produces award candidates for SAM.gov leads and passes WEBS leads through without querying USASpending.

## PHASE 3 — Build the relevance model

This is the missing brain. Run the gate and score **before** award research so irrelevant leads never consume API calls.

### 3.1 Hard exclusions (drop, never draft)

- `Days Left < 5`
- Set-aside OMEGACORTEX cannot prime: HUBZone, 8(a), SDVOSB, WOSB/EDWOSB, Buy Indian. Retain only as teaming targets.
- Notice type `Justification`, `Award Notice`, or sole-source intent naming another vendor
- Non-IT keyword match (case-insensitive, title or description):

```
appraisal, weld, forestry, timber, wildfire, HFR, janitorial, landscaping,
construction, roofing, flooring, paving, HVAC, plumbing, food service, catering,
uniform, vehicle, fuel, ammunition, furniture, carpet, printer paper, roll stock,
tree, trail, wetland, dredg, asbestos, pest control, security guard, custodial,
shuttle, transit operations, bus, snow removal, laundry
```

- Event titles (`industry day`, `meet the`, `networking`, `outreach event`, `vendor fair`, `conference`) route to a separate Events tab. Never draft a bid response for these.

### 3.2 Capability score

Threshold **3** to enter award research, **6** to be draft-eligible.

**Tier 1, 4 points each:**
```
FHIR, HL7, Da Vinci, CMS-0057, prior authorization, interoperability,
health information exchange, EHR integration, healthcare data exchange,
SAP, PI/PO, CPI, Integration Suite, middleware, ESB, iPaaS,
LLM, generative AI, agentic, RAG, document intelligence, intelligent document processing
```

**Tier 2, 2 points each:**
```
systems integration, API, data integration, data pipeline, ETL, data architecture,
identity management, IAM, ICAM, SSO, single sign-on, Entra, Okta, Active Directory,
automation, workflow automation, modernization, legacy migration, cloud migration,
Linux, infrastructure engineering, DevSecOps, CI/CD,
artificial intelligence, machine learning, analytics, business intelligence, Power BI
```

**Tier 3, 1 point each:**
```
IT services, software development, application development, technical support,
data management, database, SQL, reporting, dashboard, consulting services
```

**NAICS bonus, 3 points.** Federal: `541511`, `541512`, `541513`, `541519`, `518210`. Washington State uses NIGP commodity codes, not NAICS. Build that allowlist empirically from codes on WEBS leads that pass the keyword gate, review once with Luis, then hardcode. Do not guess code meanings.

**PSC bonus, 3 points.** Any code starting `D`, plus `7A20`, `7A21`, and `R408` when the description is IT-related.

### 3.3 Capacity realism (down-weight, do not exclude)

- Requires 24x7x365 staffed NOC or SOC: **-4**
- Ceiling above $10M, or 3+ recent corporate references required: **-3**
- On-site staffing outside Washington State: **-3**
- Active clearance or CMMC Level 2 required at award: **-3**

Net-negative leads become **teaming targets** in a separate tab with likely primes, not prime drafts.

### 3.4 Draft gate

Draft only when all hold:
1. Passed every hard exclusion
2. Capability score ≥ **6**
3. `Days Left` between **5 and 90**
4. Named contact with valid email
5. No existing draft for this Lead Key, checked against Outreach Queue **and** Gmail search
6. If previously drafted, a genuine material change: new deadline, reopened after expiry, scope amendment, or set-aside change. An identical-fingerprint repost is not a change.

Record in Outreach Queue **why**: score, which Tier 1 and Tier 2 terms matched, and pursuit route (prime, teaming, or capability introduction).

### 3.5 Validation (this is how you know it works)

Re-score the existing 534 leads and confirm:

- **`Federal & State Interoperability and Prior Authorization Project (FSIPAP)`**, WA Health Care Authority, scores **top 3**
- `Meet the BIGS!`, `Roll Stock`, `MOD-WELD Cart`, `Appraisal - Clallam County`, `French Butte HFR`, `Uniform Act Review Appraisal Services` all score zero or are excluded
- `60 FSS IT Specialist` (Travis AFB) is excluded from prime drafting on the HUBZone rule but retained as a teaming target

**If FSIPAP does not surface near the top, the model is wrong. Fix it before proceeding.**

## PHASE 4 — Make failures and silence visible

**4.1** Context Failure Logger writes to a spreadsheet nobody opens. Add email notification to Luis on any workflow error with workflow name, failed node, error message, and execution URL.

**4.2** Silence alarms. Alert when:
- Contract Scanner returns 0 new leads two consecutive days
- Lead Intelligence produces 0 award candidates across all researched SAM.gov leads
- Any workflow has not executed within 26 hours of its expected schedule
- 0 drafts for 7 consecutive days while 5+ leads scored above threshold

**4.3** Fix remaining errors: 4 stale Sheets nodes reporting `Column names were updated after the node's setup`; tab-name errors for `All Leads` and `Agency Intel`; 3 Code node syntax errors (`Invalid or unexpected token`, `Unexpected token ')'`, one at line 210).

## PHASE 5 — Durability

**5.1** Pin the n8n version. Do not auto-update. Update deliberately with backup and test run.
**5.2** Nightly backup: export all workflows, verify `nodes` is a JSON array not a Buffer, commit to a **private** git repo. Only after 0.2.
**5.3** Restore drill into a clean n8n. An untested backup is not a backup.
**5.4** Prune executions to 30 days.

---

# 8. Open items needing Luis

- **FSIPAP**, WA Health Care Authority, closes **Aug 19**. Contact Jack Kent, `jack.kent@hca.wa.gov`. Interoperability plus prior authorization is CMS-0057-F, the exact stated specialty, on a state vehicle with no certification blocker. Highest-value opportunity in the pipeline and it does not require the agent to be fixed.
- Gmail OAuth: if the token is stale, re-authentication requires Luis's Google login. Report and stop; do not attempt it. Background he already knows: the Google Cloud OAuth app must be in Production, not Testing, or refresh tokens expire every 7 days. Project `483574768857`.
- 22 legacy Gmail drafts from the old workflow predate the current gate and should not be treated as recommendations. Deleting them needs his approval.
- The three-workbook merge (section 3) is unstarted and out of scope.

---

# 9. Definition of done

1. 6 workflows, active where intended, published, opening without error
2. Contract Scanner returns SAM.gov records and writes new leads
3. Mixed run enriches SAM.gov leads, passes WEBS leads through without a federal query
4. FSIPAP scores top 3; mixer, welding cart, and appraisals score zero
5. At least one draft generated, correct in tone and reasoning, with justification recorded
6. An induced failure produces an email to Luis
7. Nightly backup runs, verified clean, contains no secrets
8. Two consecutive scheduled mornings complete with zero unexplained errors

Report what is done, what is not, and what needs Luis. Verify against the live instance. Do not claim success without evidence.
