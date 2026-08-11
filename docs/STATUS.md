# Status

Last verified: **Aug 11, 2026, ~12:25 AM ET**, against the live instance at `localhost:5678`.

Update this file as phases complete. Do not mark anything done without evidence.

---

## System

| | |
|---|---|
| n8n | 2.33.7 |
| Node | 24.19.0 |
| Health | UP, `/rest/settings` returns 200 |
| Wake schedule | `wakepoweron at 5:00AM every day` confirmed |
| HttpRequest patch | **required** — `scripts/patch-n8n-httprequest-form-auth.sh` applied on disk (re-run after every n8n upgrade) |

## Operating mode (current)

**WEBS-only intake.** SAM.gov federal intake is intentionally **off**. Google Sheets hold WEBS-related rows only (federal bulk cleared earlier this session).

| Path | State |
|---|---|
| WEBS portal scrape → sheets | **LIVE and verified** (exec **155** success) |
| Lead Intelligence v2 (WEBS path) | **LIVE** — Phase 2 + WA awards scoring |
| Contract Scanner (SAM) | **inactive / SAM node disabled** |
| Gmail | **drafts only** — never send |

## Workflows

| Workflow | ID | Nodes | Active | Published |
|---|---|---|---|---|
| Lead Intelligence v2 | `Om3gaLeadIntelV2` | 46 | yes | yes |
| Contract Scanner - WEBS Test | `z0ZcPBe8fDmKcl9I` | 36 | **yes** | **yes** — Daily → live login; Manual → sample |
| Context Failure Logger | `Om3gaContextFailure` | 7 | yes | yes |
| Contract Scanner | `0bTuf3RMzVQHjH8E` | 9 | **no** | SAM disabled |
| Intelligence v2 - Federal Test | `Iv2Tst4k9Qm2Lp7Xs` | 12 | no | no |
| Reliability Test Harness | `Om3gaReliabilityHarness` | 6 | no | no |
| ZZ TEMP publish-semantics probe | `5ToIbeWkCWOFLywk` | 2 | no | no — delete in UI |
| ZZ WEBS Cred/Cmd Debug | `WebsCredDebug01/02` | — | no | **unpublished** — safe to delete in UI |

## Last runs (verified)

| Exec | Workflow | Result |
|---|---|---|
| **155** | WEBS Test | **success** — login → 9 bids → Deduplicate 9 Updated → **WEBS Leads / Agent Intel / All Leads Output each 9** |
| 154 | WEBS Test | success — Leads + Agent Intel 9; All Leads 0 (cross-source skip false positive; fixed before 155) |
| 153 | WEBS Test | error — Google Sheets cell >50k chars (fixed via SHEETS_CELL_MAX clip) |
| 119 | Lead Intelligence v2 | success — WA awards / state evidence path |

## WEBS blade (what works)

1. **Login:** `LoginPage.aspx` + form-urlencoded VIEWSTATE keypair + credential `WEBS Account` (`httpCustomAuth` body `txtEmail`/`txtPassword`).
2. **n8n core patch:** HttpRequestV3 merges `customAuth.body` into `requestOptions.form` when form-urlencoded (stock n8n drops creds). Marker: `OMEGACORTEX patch: form-urlencoded`.
3. **Scrape:** Search → 9 detail links → parse → normalize → enrich → dedupe.
4. **Sheets safety:** string fields clipped to **45,000** chars (Google limit 50,000) in Parse/Normalize/Dedupe/Maps.
5. **Dedup:** same-source WEBS IDs update All Leads; true cross-source dupes still skip All Leads clone.
6. **Triggers:** Daily WEBS → live login chain. Manual → `WEBS Test Sample` (safe). SAM/NAICS nodes disabled on WEBS Test.

## Phase progress

| Phase | Status |
|---|---|
| 0 — Housekeeping | **mostly done** |
| 0.1 delete probe workflow | **partial** — inactive; still in inventory (+ debug workflows) |
| 0.2 remove SAM.gov key from nodes | **done in n8n** — credentialed; **Luis must still rotate** at sam.gov |
| 0.3 Sheets backoff 60000ms | **done** on production Sheets nodes; WEBS output/load nodes also set |
| 1 — Restore SAM.gov intake | **params done, intake OFF** |
| 2 — Route enrichment by source | **done** — Lead Intel 46 nodes |
| WA awards / state evidence | **done** |
| WEBS live intake | **done** (exec 155) |
| Sheets WEBS-only clean | **done** (earlier this session) |
| 3 — Relevance model | **not started** |
| 4 — Failure and silence alerts | not started |
| 5 — Durability | not started |

## Credentials (live)

| ID | Name | Type |
|---|---|---|
| `SamGovApiKey01` | SAM.gov API Key | `httpQueryAuth` |
| `yONjLL3PZRcbpSVP` | OMEGACORTEX Gmail Drafts | `gmailOAuth2` |
| `W3bsAuth8mK2pL9xQ` | WEBS Account | `httpCustomAuth` (`body.txtEmail` / `body.txtPassword`) |
| `4sj2JhBHtqJbKMaq` / `kp88wWGNVwa5Ufgk` | Google Sheets accounts | `googleSheetsOAuth2Api` |
| `z4IHFzqOhm49A8AV` | Query Auth account | `httpQueryAuth` (not the SAM key) |

## Scripts

- `scripts/apply-phase-2.sh` — Phase 2 source routing
- `scripts/apply-wa-awards.sh` — state-lead scoring + draft-gate fix
- `scripts/toggle-sam.sh` — SAM intake on/off/status
- `scripts/patch-n8n-httprequest-form-auth.sh` — **re-apply after n8n upgrades**; then restart LaunchAgent
- `scripts/scan-secrets.sh` — run before every commit
- `scripts/decode-buffers.py` / `verify-backup.py` — export safety

## Open / risky

- **After any n8n upgrade:** run `./scripts/patch-n8n-httprequest-form-auth.sh` and restart n8n or WEBS login breaks again.
- Probe + WEBS debug workflows still listed. Delete in UI.
- SAM.gov key **not rotated** at sam.gov. Keep intake off until rotated.
- Phase 3 relevance model not started — Pursue/draft quality still limited.
- Gmail remains **drafts only**.
- `n8n execute` conflicts with LaunchAgent ports — bootout → execute → bootstrap.
- Never write `~/.n8n/database.sqlite` directly.

## Open, needs Luis

- **Rotate SAM.gov API key** at sam.gov; update n8n credential.
- **Delete** probe `5ToIbeWkCWOFLywk` and debug `WebsCredDebug01/02` in the n8n UI.
- **FSIPAP**, WA Health Care Authority, closes **Aug 19**. Contact Jack Kent.
- Gmail OAuth if draft creation fails.
- 22 legacy Gmail drafts — delete only with approval.
