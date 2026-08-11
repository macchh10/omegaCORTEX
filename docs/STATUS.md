# Status

Last verified: **Aug 10, 2026, ~10:50 PM ET**, against the live instance at `localhost:5678`.

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
| Lead Intelligence v2 | `Om3gaLeadIntelV2` | 46 | yes | yes |
| Contract Scanner | `0bTuf3RMzVQHjH8E` | 9 | yes | yes |
| Context Failure Logger | `Om3gaContextFailure` | 7 | yes | yes |
| Contract Scanner - WEBS Test | `z0ZcPBe8fDmKcl9I` | 36 | no | no |
| Intelligence v2 - Federal Test | `Iv2Tst4k9Qm2Lp7Xs` | 12 | no | no |
| Reliability Test Harness | `Om3gaReliabilityHarness` | 6 | no | no |
| ZZ TEMP publish-semantics probe | `5ToIbeWkCWOFLywk` | 2 | **no** | **no** — still listed; delete in UI |

Instance still shows **7** workflows (probe present but inactive/unpublished). Target is **6** after UI delete. No CLI delete command exists in n8n 2.33.7.

## Last runs (verified)

| Exec | Workflow | Time (UTC) | Result |
|---|---|---|---|
| 119 | Lead Intelligence v2 | Aug 11 02:32 | **success** ~10s — post WA-awards fix |
| 118 | Lead Intelligence v2 | Aug 11 02:29 | **success** ~14s — post Phase 2 |
| 117 | Lead Intelligence v2 | Aug 10 10:00 | success (scheduled), pre-Phase-2, Scoring starved |
| 116 | Contract Scanner | Aug 10 09:20 | error, SAM.gov timeout (pre Phase 1 live apply on that run) |

Post-Phase-2 evidence (exec 118): Select Research → Route → Bypass → Join → **Agent Intel v2 Scoring non-zero** (WEBS path; federal award path not required for state leads).

Post-WA-awards evidence (exec 119): Scoring emitted `Evidence Confidence: N/A - State` for WEBS; Evaluate Draft Eligibility no longer blocked on Low evidence. Remaining blockers are capability/priority/deadline/active (Phase 3).

Lifetime totals at verify: **119 executions, 54 errors**.

---

## Phase progress

| Phase | Status |
|---|---|
| 0 — Housekeeping | **mostly done** |
| 0.1 delete probe workflow | **partial** — unpublished + deactivated; still in inventory (delete in UI) |
| 0.2 remove SAM.gov key from nodes | **done in n8n** — credential `SamGovApiKey01` / `SAM.gov API Key` (`httpQueryAuth`); both SAM.gov Query nodes use it; **exports clean of `SAM-9667`**. **Luis must rotate the key at sam.gov** (old key was in historical exports/backups). |
| 0.3 Sheets backoff to 60000ms | **done** — Lead Intel 11/11 Sheets nodes, Scanner 2/2, Failure Logger 3/3 (`retryOnFail`, `waitBetweenTries=60000`, `maxTries=3`) |
| 1 — Restore SAM.gov intake | **params done, intake OFF** — Scanner `limit=200`, timeout `120000`, credentialed; **SAM node disabled** and NAICS→SAM disconnected via `toggle-sam.sh off` until key is rotated and intake is intentionally re-enabled |
| 2 — Route enrichment by source | **done** — `Route by Source` / `Bypass Award Research` / `Join Award Paths`; Lead Intel **46** nodes; Scoring fed only from Join |
| 3 — Relevance model | **not started** |
| 4 — Failure and silence alerts | not started |
| 5 — Durability | not started |

## Credentials (live)

| ID | Name | Type |
|---|---|---|
| `SamGovApiKey01` | SAM.gov API Key | `httpQueryAuth` |
| `yONjLL3PZRcbpSVP` | OMEGACORTEX Gmail Drafts | `gmailOAuth2` |
| `W3bsAuth8mK2pL9xQ` | WEBS Account | `httpCustomAuth` |
| `4sj2JhBHtqJbKMaq` / `kp88wWGNVwa5Ufgk` | Google Sheets accounts | `googleSheetsOAuth2Api` |
| `z4IHFzqOhm49A8AV` | Query Auth account | `httpQueryAuth` (not the SAM key) |

## Scripts added this session

- `scripts/apply-phase-2.sh` — Phase 2 source routing (export/import/publish/verify; `--yes` / `--dry-run` / `--revert`)
- `scripts/apply-wa-awards.sh` — state-lead scoring + draft-gate fix
- `scripts/toggle-sam.sh` — `on` / `off` / `status` for SAM intake on Scanner + WEBS Test

## Resolved (cumulative)

- Workflow BLOB corruption recovery (Lead Intel, WEBS Test)
- n8n 2.8.4 → 2.33.7; LaunchAgent Node 24 PATH
- Sheets 429 backoff on production Sheets nodes
- SAM.gov query shape (limit/window/timeout) on production Scanner
- Phase 2 WEBS bypass so Scoring is not starved when award candidates are 0
- State leads no longer hard-require federal USASpending evidence
- SAM API key removed from live workflow node parameters (credential attached)

## Open / risky

- Probe workflow still in the instance (inactive). Delete in UI → 6 workflows.
- SAM.gov key **not yet rotated** at sam.gov. Historical `~/n8n-backups/` and pre-credential exports may still contain the old key — treat as compromised until rotated.
- SAM intake is intentionally **off**. Re-enable only after rotation: `./scripts/toggle-sam.sh on --yes`, then publish + restart, then manual Scanner run.
- WEBS Test SAM node still has legacy `limit=1000` (node disabled; not production path).
- No relevance model yet — Pursue/draft volume will stay low or noisy until Phase 3.
- Gmail remains **drafts only**. Never send.

## Open, needs Luis

- **Rotate SAM.gov API key** at sam.gov, then update n8n credential `SAM.gov API Key` with the new value.
- **Delete probe** `5ToIbeWkCWOFLywk` in the n8n UI.
- **FSIPAP**, WA Health Care Authority, closes **Aug 19**. Contact Jack Kent, `jack.kent@hca.wa.gov`.
- Gmail OAuth untested since the upgrade if drafts fail.
- 22 legacy Gmail drafts from the old workflow — delete only with approval.
- Three-workbook merge (SOURCE / OPERATING / HUB) unstarted and out of scope.
