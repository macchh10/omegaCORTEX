# Status

Last verified: **Aug 10, 2026, 7:00 PM ET**, full scan against the live instance.

Update this file as phases complete. Do not mark anything done without evidence.

---

## System

| | |
|---|---|
| n8n | 2.33.7 |
| Node | 24.19.0 |
| Health | UP, `/rest/settings` returns 200 |
| Wake schedule | `wakepoweron at 5:00AM every day` confirmed |

## Workflows

| Workflow | ID | Nodes | Active | Published |
|---|---|---|---|---|
| Lead Intelligence v2 | `Om3gaLeadIntelV2` | 43 | yes | yes |
| Contract Scanner | `0bTuf3RMzVQHjH8E` | 9 | yes | yes |
| Context Failure Logger | `Om3gaContextFailure` | 7 | yes | yes |
| Contract Scanner - WEBS Test | `z0ZcPBe8fDmKcl9I` | 36 | no | no |
| Intelligence v2 - Federal Test | `Iv2Tst4k9Qm2Lp7Xs` | 12 | no | no |
| Reliability Test Harness | `Om3gaReliabilityHarness` | 6 | no | no |
| ZZ TEMP publish-semantics probe | `5ToIbeWkCWOFLywk` | 2 | yes | **delete** |

Instance shows **7** workflows. Should be **6**.

## Last scheduled runs

| Exec | Workflow | Time | Result |
|---|---|---|---|
| 117 | Lead Intelligence v2 | Aug 10, 6:00:13 AM | **success**, 32s |
| 116 | Contract Scanner | Aug 10, 5:20:11 AM | error, 345s, SAM.gov `ECONNABORTED` |

Execution 117 was the first clean end-to-end run. It produced **0 drafts** because `Select Award Candidates` emitted 0 items.

---

## Phase progress

**Full scan at 7:00 PM confirmed zero phases have been executed.** The system is
in the same state as the 3:54 PM scan. Verified unchanged: probe workflow still
active (7 workflows), SAM.gov still `limit=1000` over a 60-day window, API key
still plaintext, Sheets backoff still 0/12, 0/2, 0/3.

Lifetime totals: **117 executions, 54 errors, 46% failure rate.**

| Phase | Status |
|---|---|
| 0 — Housekeeping | **not started** |
| 0.1 delete probe workflow | not started |
| 0.2 remove and rotate SAM.gov key | not started |
| 0.3 Sheets backoff to 60000ms | not started — 0/12, 0/2, 0/3 nodes |
| 1 — Restore SAM.gov intake | not started |
| 2 — Route enrichment by source | not started |
| 3 — Relevance model | not started |
| 4 — Failure and silence alerts | not started |
| 5 — Durability | not started |

## Resolved

- Workflow BLOB corruption — Lead Intelligence v2 recovered with all 43 nodes, WEBS Test repaired to 36
- n8n 2.8.4 editor crash — upgraded to 2.33.7
- LaunchAgent Node 20 vs Node 24 mismatch — plist `PATH` corrected
- Mac sleep risk — `pmset` daily 5:00 AM wake confirmed

## Open, needs Luis

- **FSIPAP**, WA Health Care Authority, closes **Aug 19**. Contact Jack Kent, `jack.kent@hca.wa.gov`. Interoperability plus prior authorization is CMS-0057-F, the exact stated specialty, on a state vehicle with no certification blocker. Does not require the agent to be fixed.
- Gmail OAuth untested since the upgrade. Re-authentication requires his Google login.
- 22 legacy Gmail drafts from the old workflow predate the current gate. Deleting them needs approval.
- Three-workbook merge (SOURCE / OPERATING / HUB) unstarted and out of scope.
