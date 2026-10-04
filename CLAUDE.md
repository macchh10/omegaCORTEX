# OMEGACORTEX workspace

Everything OMEGACORTEX lives in this folder. Start Claude Code here: `cd ~/omegaCORTEX && claude`

## Where things go

- `pursuits/<solicitation-number>-<short-name>/` : one folder per federal or state opportunity. Solicitation files, `rfq-brief.md`, questions, volumes, pricing workpapers.
- `leads/<campaign-name>/` : networking and outreach work (evaluations, drafts, contact research).
- `policies/` : company policies reused across quotes (C-SCRM, background checks, anti-tampering, insider threat, security plans).
- `capability/` : capability statement, past performance write-ups, resumes, boilerplate.
- `docs/`, `scripts/`, `workflows/` : the n8n lead intelligence agent. See README.md and docs/MASTER-HANDOFF.md before touching these.

If a new kind of OMEGACORTEX work doesn't fit, create a clearly named subfolder here. Never save OMEGACORTEX files outside this folder, and never save non-OMEGACORTEX work inside it.

## Git

- This repo pushes to GitHub (macchh10/omegaCORTEX). `pursuits/`, `leads/`, `policies/` and `capability/` are gitignored on purpose: pursuit strategy and pricing never leave this Mac.
- Run `scripts/scan-secrets.sh` before every commit.
- Commit at the end of each work session.

## Session discipline

- One session, one job. When the topic changes, update the relevant brief file and start fresh.
- Every pursuit folder keeps its `rfq-brief.md` current, so the next session can pick up from the file alone.
- Before any external draft, check every factual claim against what OMEGACORTEX has actually done. No federal past performance is claimed until an award exists.

## Consolidated here on 2026-09-16

- `sam-hunter/` : SAM.gov capture pipeline, MCP server, and the Capture Deck. Its own git repo (macchh10/sam-hunter), gitignored from this one so it is never nested as a submodule. A symlink at `~/sam-hunter` points here as a safety net.
- `n8n-backups/` : dated n8n workflow exports. Treat as containing unredacted secrets.
- `omegacortex-data/` : WEBS intake feed and document drop.

The sam-hunter MCP server is registered in `~/Library/Application Support/Claude/claude_desktop_config.json` and `~/.claude.json` at `~/omegaCORTEX/sam-hunter/mcp/server.mjs`. The LaunchAgent `com.omegacortex.samhunter` runs `src/cli.mjs` daily at 07:00 from this path. If you move this folder again, update all four.
