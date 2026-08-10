# Handoff round 2 — OMEGACORTEX n8n

Read `claude-code-handoff.md` first for environment details, hard rules, and n8n 2.x draft/publish behavior. This document supersedes its task priorities based on evidence from the Aug 10 morning runs.

## What is now working

Execution **117**, Lead Intelligence v2, Aug 10 6:00:13 AM, **success** in 32 seconds. First clean end-to-end run. No Google Sheets rate limit errors occurred, despite the backoff fix never being applied.

Execution **116**, Contract Scanner, Aug 10 5:20:11 AM, **error** after 345 seconds.

Contract Scanner - WEBS Test now reads 36 nodes instead of a BLOB, so it was repaired.

## Corrected priority

The Sheets rate limiting did **not** recur. It is now a lower priority than originally stated, because Contract Scanner failed early and never consumed quota, leaving the 6:00 run clear. Expect it to return once Contract Scanner is fixed and both workflows compete for the same 60-requests-per-minute budget. Apply the backoff fix, but it is no longer the top item.

The real blockers are below.

---

# TASK A — SAM.gov query times out (blocks the whole pipeline)

`SAM.gov Query` in Contract Scanner (`0bTuf3RMzVQHjH8E`) fails every run with `ECONNABORTED`, "The connection was aborted, perhaps the server is offline". It has failed at least Aug 8, 9, and 10.

Current configuration:

```
url:       https://api.sam.gov/opportunities/v2/search
timeout:   60000
retry:     5 tries, 5000ms wait
batching:  batchSize 1, batchInterval 1000
query:     postedFrom = now minus 60 days
           postedTo   = now
           ncode      = {{ $json.ncode }}
           limit      = 1000
           ptype      = p,k,r,o,s,i,u
```

The request asks for up to **1000 records across a 60-day window for every NAICS code**, one code at a time. Each attempt exceeds the 60 second timeout, five retries burn 345 seconds, and the node dies. The workflow runs daily, so a 60-day lookback re-requests the same two months of data every morning.

Suggested fix, in order:

1. Narrow `postedFrom` from 60 days to about 7 to 10 days. Daily runs make a long window pointless, and dedupe downstream already handles overlap.
2. Reduce `limit` from 1000 to 100 or 200.
3. Only if still slow, raise `timeout` above 60000.

Validate by executing Contract Scanner manually and confirming `SAM.gov Query` returns results rather than timing out. Confirm downstream `Process Contracts` and `Google Sheet Output` receive items.

## Security issue found in this node

The SAM.gov API key is **hardcoded in plain text** as the `api_key` query parameter, beginning `SAM-9667a6e3`. It is stored in the workflow JSON, which means it is present in every export in `~/n8n-backups/`.

Move it to an n8n credential or an environment variable, and rotate the key since it has been sitting in exported files. Do not commit any of those exports to git until this is resolved. The owner has been considering a GitHub backup repo, so this must be fixed first.

---

# TASK B — Award research queries a federal database with state agency names

This is why zero drafts are produced, and it is an architectural mismatch rather than a bad setting.

In execution 117, `Select Leads for Research` chose 25 leads, `Search Comparable Awards` ran 25 queries, and **every single one returned 0 results**. `Select Award Candidates` therefore emitted 0 items and the entire downstream chain, including award intel, scoring, the draft gate, and Gmail draft creation, never executed.

The cause: all 25 leads came from **WEBS**, the Washington State procurement portal, and the workflow queries **USASpending**, which contains only **federal** awards. The generated request body filters on:

```json
"agencies": [{ "type": "awarding", "tier": "toptier", "name": "<agency>" }]
```

with agency names taken straight from the WEBS lead. Observed values across the 25 searches:

```
4x  Transportation, Dept of
3x  Enterprise Services (DES), Dept
3x  Commerce, Dept
2x  Health Care Authority
2x  Natural Resources, Department of
2x  Okanogan County Transit Authority
1x  University of Washington
1x  Washington State University
1x  Thurston EDC
1x  Washington Technology Solutions (WaTech)
1x  Washington Traffic Safety Commission
1x  Community Colleges of Spokane
1x  Superintendent of Public Instruction, Office of
1x  Revenue, Department of
1x  Military Department
```

None of these are federal toptier agencies. `Thurston EDC` and `Okanogan County Transit Authority` are county-level. These queries can never return results, no matter how long they run.

### Why all 25 were WEBS leads

Contract Scanner is the SAM.gov feeder and has been failing since at least Aug 8. With no fresh federal leads arriving, the only opportunities showing changes are WEBS records. So Task A and Task B compound: fixing SAM.gov restores federal leads, which are the ones USASpending can actually match.

### Suggested fix

Branch on lead source before award research. Route `Source == SAM.gov` leads into the USASpending query. For WEBS leads either skip award research entirely and let them proceed to scoring on other signals, or find an appropriate Washington State award data source.

Do not simply widen the USASpending filter. A state lead has no federal award history to find, so a looser query would return irrelevant matches and pollute Award Intelligence.

Propose the branching approach to the owner before implementing. This changes pipeline logic, not just configuration.

---

# TASK C — Still outstanding from round 1

**Delete the probe workflow.** `5ToIbeWkCWOFLywk`, `ZZ TEMP publish-semantics probe (safe to delete)`. Still present and still active with an 11:59 PM trigger. Instance now has 7 workflows and should have 6.

**Apply the Sheets backoff fix.** Verified as still unapplied: 0 of 12 qualifying nodes in Lead Intelligence v2, 0 of 2 in Contract Scanner, 0 of 3 in Context Failure Logger carry `waitBetweenTries: 60000`. Lower priority now, but do it before Contract Scanner is restored, since that is when quota pressure returns.

**Verify Gmail credentials.** Execution 117 never reached the Gmail nodes, so the credential is still untested after the version upgrade. Drafts only, never send.

---

# Verification

Report each of these against the live instance, not from assumption:

1. Contract Scanner executes manually and `SAM.gov Query` returns records
2. Lead Intelligence v2 executes and `Select Award Candidates` emits more than 0 items for at least one SAM.gov-sourced lead
3. All three production workflows remain `active: true` and present in `/rest/active-workflows`
4. The probe workflow is gone and the instance shows exactly 6 workflows
5. The SAM.gov API key no longer appears in plain text in the workflow JSON

State clearly what you fixed, what you could not, and what needs the owner's decision.
