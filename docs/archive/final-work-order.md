# OMEGACORTEX Agent — Final Work Order

Supersedes `claude-code-handoff.md` and `claude-code-handoff-round2.md` for priorities. Keep those for environment details and n8n 2.x behavior.

Goal: Luis opens Gmail, sees a small number of drafts, and trusts that each one is a real opportunity OMEGACORTEX can win. Nothing else counts as done.

---

## Environment quick reference

- n8n **2.33.7**, `http://localhost:5678`, Node 24 at `/opt/homebrew/opt/node@24/bin/node`
- LaunchAgent `com.omegacortex.n8n`, restart: `launchctl kickstart -k gui/501/com.omegacortex.n8n`
- Health: `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:5678/rest/settings` returns `200`
- **Never write to `~/.n8n/database.sqlite` directly.** That caused the original corruption.
- `n8n import:workflow` deactivates the target. Always reactivate and verify.
- PATCH edits a draft only. Changes are live only after publishing.

## Workflow IDs

| Workflow | ID |
|---|---|
| Lead Intelligence v2 | `Om3gaLeadIntelV2` |
| Contract Scanner | `0bTuf3RMzVQHjH8E` |
| Context Failure Logger | `Om3gaContextFailure` |
| Contract Scanner - WEBS Test | `z0ZcPBe8fDmKcl9I` |
| ZZ TEMP probe (**delete**) | `5ToIbeWkCWOFLywk` |

---

# PHASE 0 — Housekeeping (do first, 10 minutes)

**0.1** Delete workflow `5ToIbeWkCWOFLywk`. Instance must end with 6 workflows.

**0.2** The SAM.gov API key is hardcoded in plain text in the `SAM.gov Query` node's `api_key` query parameter, beginning `SAM-9667a6e3`. It is therefore in every export under `~/n8n-backups/`. Move it to an n8n credential or environment variable, then rotate it at sam.gov. Nothing goes to git until this is done.

**0.3** Apply Google Sheets backoff. For every node of type `n8n-nodes-base.googleSheets`, and every `httpRequest` node whose parameters contain `sheets.googleapis.com`, set `retryOnFail: true`, `maxTries: 3`, `waitBetweenTries: 60000`. That is 12 nodes in Lead Intelligence v2, 2 in Contract Scanner, 3 in Context Failure Logger. Sheets allows 60 requests per minute per user, so a 5-second retry lands inside the same exhausted window and makes things worse. The n8n UI caps this field at 5000ms in some builds, so apply via CLI or API.

**Acceptance:** 6 workflows, all Sheets-touching nodes at 60000ms, no plaintext key in any workflow JSON.

---

# PHASE 1 — Restore lead intake (nothing downstream matters until this works)

`SAM.gov Query` in Contract Scanner has failed every run since at least Aug 8 with `ECONNABORTED` after 345 seconds.

Current query asks for `limit=1000` across a **60-day** window, per NAICS code, batched one at a time, with a 60-second timeout. Each attempt exceeds the timeout. The workflow runs daily, so a 60-day lookback re-requests the same two months every morning.

**1.1** Change `postedFrom` from 60 days to **10 days**.

**1.2** Change `limit` from `1000` to `200`.

**1.3** If still timing out, raise `options.timeout` to `120000`.

**Acceptance:** Manual execution of Contract Scanner completes, `SAM.gov Query` returns records, and `Google Sheet Output` writes rows. Confirm new SAM.gov-sourced rows appear in All Leads.

---

# PHASE 2 — Route enrichment by lead source

Execution 117 ran 25 award searches and every one returned 0 results, because all 25 leads were from **WEBS** (Washington State) while the query hits **USASpending** (federal only). It sent agency names like `Thurston EDC`, `Okanogan County Transit Authority`, and `University of Washington` as federal toptier agencies. Those can never match.

**2.1** Branch on `Source` before `Prepare Lead Award Searches`.

- `Source == "SAM.gov"` → existing USASpending path
- `Source == "WEBS"` → skip award research entirely, pass through to scoring with `Award Evidence = "N/A - State opportunity"`

**2.2** WEBS leads must not be penalized in scoring for missing award history. Absence of federal award data is expected for a state opportunity, not a negative signal.

**Acceptance:** A run containing both sources produces award candidates for SAM.gov leads and passes WEBS leads through to scoring without querying USASpending.

---

# PHASE 3 — Build the relevance model (this is the missing brain)

This is the actual reason the agent is not sharp. It currently surfaces whatever changed. On Aug 10 its 25 "research-worthy" leads included a networking mixer, welding equipment, land appraisals, forest health work, and youth social services, while the single best-fit opportunity in the pipeline sat undifferentiated at position one.

Implement a hard gate, then a score. Both run **before** award research so the pipeline stops wasting calls on irrelevant leads.

## 3.1 Hard exclusions (drop immediately, never draft)

Drop the lead if any of these is true:

- `Days Left < 5`. Nothing useful can happen in under five days. Execution 117 selected leads at 0 and 1 days left.
- Set-aside is one OMEGACORTEX cannot meet as prime: **HUBZone, 8(a), SDVOSB, WOSB/EDWOSB, Buy Indian**. Keep these only if explicitly flagged as a teaming or subcontract target, never for a prime draft.
- Notice type is `Justification`, `Award Notice`, or a sole-source intent naming another vendor. The decision is already made.
- Title or description matches the non-IT exclusion list below.

**Non-IT exclusion keywords** (case-insensitive, match on title or description):

```
appraisal, weld, forestry, timber, wildfire, HFR, janitorial, landscaping,
construction, roofing, flooring, paving, HVAC, plumbing, food service, catering,
uniform, vehicle, fuel, ammunition, furniture, carpet, printer paper, roll stock,
tree, trail, wetland, dredg, asbestos, pest control, security guard, custodial,
shuttle, transit operations, bus, snow removal, laundry
```

**Event exclusion:** titles containing `industry day`, `meet the`, `networking`, `outreach event`, `vendor fair`, `conference` are relationship items, not procurements. Route them to a separate Events tab. Never draft a bid response for them.

## 3.2 Capability match (must score above zero to proceed)

Score keyword hits across title, description, NAICS, and PSC. A lead must reach at least **3 points** to enter award research and at least **6 points** to be eligible for a draft.

**Tier 1, 4 points each — core specialty, exact match to stated capability:**

```
FHIR, HL7, Da Vinci, CMS-0057, prior authorization, interoperability,
health information exchange, EHR integration, healthcare data exchange,
SAP, PI/PO, CPI, Integration Suite, middleware, ESB, iPaaS,
LLM, generative AI, agentic, RAG, document intelligence, intelligent document processing
```

**Tier 2, 2 points each — strong adjacent fit:**

```
systems integration, API, data integration, data pipeline, ETL, data architecture,
identity management, IAM, ICAM, SSO, single sign-on, Entra, Okta, Active Directory,
automation, workflow automation, modernization, legacy migration, cloud migration,
Linux, infrastructure engineering, DevSecOps, CI/CD,
artificial intelligence, machine learning, analytics, business intelligence, Power BI
```

**Tier 3, 1 point each — plausible but generic:**

```
IT services, software development, application development, technical support,
data management, database, SQL, reporting, dashboard, consulting services
```

**NAICS bonus, 3 points.** Federal: `541511`, `541512`, `541513`, `541519`, `518210`.
Washington State uses NIGP commodity codes, not NAICS. Build the state allowlist empirically: pull the distinct codes present on WEBS leads that pass the keyword gate, review them with Luis once, then hardcode the approved list. Do not guess the code meanings.

**PSC bonus, 3 points.** Any code starting `D` (IT and Telecom), plus `7A20`, `7A21`, `R408` when the description is IT-related.

## 3.3 Capacity realism (down-weight, do not exclude)

OMEGACORTEX is three principals with no federal corporate past performance yet. Subtract points when the opportunity clearly exceeds that:

- Requires 24x7x365 staffed NOC or SOC: **minus 4**
- Names a ceiling above $10M, or requires 3+ recent corporate references: **minus 3**
- Requires on-site staffing outside Washington State: **minus 3**
- Requires an active clearance or CMMC Level 2 at time of award: **minus 3**

A lead that goes negative here becomes a **teaming target**, not a prime draft. Track it in a separate Teaming tab with the likely primes.

## 3.4 Draft gate

Create a Gmail draft only when **all** of the following hold:

1. Passed every hard exclusion
2. Capability score at or above **6**
3. `Days Left` between **5 and 90**
4. A named contact with a valid email exists
5. No draft already exists for this Lead Key, checked against Outreach Queue **and** Gmail search
6. If previously drafted, the opportunity has a genuine material change: new deadline, reopened after expiry, scope amendment, or set-aside change. A re-post with identical fingerprint is not a change.

Every draft must record **why** in Outreach Queue: score, which Tier 1 or Tier 2 terms matched, and the pursuit route (prime, teaming, or capability introduction).

**Drafts only. Never send. This is absolute.**

## 3.5 Validation against known data

Re-run scoring over the existing 534 leads and confirm:

- `Federal & State Interoperability and Prior Authorization Project (FSIPAP)`, WA Health Care Authority, scores in the top 3. It is interoperability plus prior authorization, which is CMS-0057-F, the exact stated specialty, on a state vehicle where OMEGACORTEX is already a WEBS vendor with no certification blocker.
- `Meet the BIGS!`, `Roll Stock`, `MOD-WELD Cart`, `Appraisal - Clallam County`, `French Butte HFR`, `Uniform Act Review Appraisal Services` all score zero or are excluded.
- The `60 FSS IT Specialist` Travis AFB lead is excluded from prime drafting on the HUBZone rule but retained as a teaming target.

If FSIPAP does not surface near the top, the model is wrong. Fix it before proceeding.

---

# PHASE 4 — Make failures and silence visible

The worst failure mode is not an error. It is a green run that quietly produces nothing, which is exactly what happened on Aug 10.

**4.1** Context Failure Logger currently writes failures to a spreadsheet nobody opens. Add an email notification to Luis on any workflow error, containing workflow name, failed node, error message, and execution URL.

**4.2** Add a silence alarm. Alert when any of these is true:

- Contract Scanner returns 0 new leads two consecutive days
- Lead Intelligence v2 produces 0 award candidates across all researched SAM.gov leads in a run
- Any workflow has not executed within 26 hours of its expected schedule
- 0 drafts generated for 7 consecutive days while 5 or more leads scored above the draft threshold

**4.3** Fix the 4 stale Sheets nodes reporting `Column names were updated after the node's setup`, the tab-name errors for `All Leads` and `Agency Intel`, and the 3 Code node syntax errors (`Invalid or unexpected token`, `Unexpected token ')'`, one at line 210).

---

# PHASE 5 — Durability

**5.1** Pin the n8n version. Being on 2.8.4 with a known editor crash cost a full night. Do not auto-update. Update deliberately with a backup and a test run.

**5.2** Nightly automated backup: export all workflows, verify `nodes` is a JSON array and not a Buffer, then commit to a **private** git repo. Only after Phase 0.2 removes the API key.

**5.3** Restore drill: prove a backup can be restored into a clean n8n. An untested backup is not a backup.

**5.4** Prune executions. 117 stored with full payloads. Keep 30 days.

---

# Definition of done

1. All 6 workflows present, active where intended, published, opening without error
2. Contract Scanner returns SAM.gov records and writes new leads
3. A mixed run enriches SAM.gov leads and passes WEBS leads through without a federal query
4. FSIPAP scores top 3; the mixer, welding cart, and appraisals score zero
5. At least one draft generated, correct in tone and reasoning, with its justification recorded
6. An induced failure produces an email to Luis
7. Nightly backup runs, is verified as clean, and contains no secrets
8. Two consecutive scheduled mornings complete with zero unexplained errors

Report what is done, what is not, and what needs Luis. Verify against the live instance. Do not claim success without evidence.
