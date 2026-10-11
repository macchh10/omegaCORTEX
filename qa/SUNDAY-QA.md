# Sunday QA brief (SAM Hunter + WEBS)

Two unattended reviews run every Sunday from `scripts/sunday-qa.sh` (LaunchAgent
`com.omegacortex.sunday-qa`): review A at 09:00 ET, review B at 15:00 ET. Nobody is
watching. Find what is wrong or weak, fix what you safely can, write down the rest.

Start by reading `agents/LATEST.md`, `agents/PROTOCOL.md`, the last two reports in
`qa/reports/`, and `qa/FINDINGS.md`. Never re-report an open finding as new; update it.

## Review A (09:00): health and decisions

1. SAM Hunter runs: every `sam-hunter/data/logs/run_*.json` since last Sunday.
   Status, errors, fetched/prefilter/prime/sub counts, attachments, award matches.
   Run `sam_hunter_doctor`. Compare volume with the week before.
2. Board quality: every Prime and Sub on the board (`sam_hunter_today` with days=7,
   plus the Capture Deck board). For each, is the route right? Read the notice text
   in a DB copy. Look for wrong partners, sole sources routed to teaming, expired
   leads still on the board, duplicates, missing contacts.
3. Missed opportunities: the top 30 parked notices by total. Anything parked that a
   human pursued (check LATEST.md, LOG.md) is a rule miss.
4. WEBS: n8n `OMEGACORTEX WEBS Triage` executions (`~/.n8n/database.sqlite`,
   read-only) and the age of `omegacortex-data/webs-intake-feed.json`. A green run
   that processed zero notices is a failure, not a success.

## Review B (15:00): second pass

1. Re-check every fix review A made today: tests, regression, git log, run output.
   Revert anything that made results worse.
2. Look where review A did not: Archive/route text for leaked partner names
   (`deck/archive-data.json` is public), decision log staleness, deck cards with no
   status change in 14 days, untouched deadlines in the next 10 days, LaunchAgent
   exit codes (`launchctl list | grep omegacortex`), disk and log sizes.
3. Weak decisions: leads passed or no-bid by the team that the scoring loved, and
   leads pursued that it parked. These feed `sam_hunter_learn`, they are not bugs.

## What you may fix on your own

- Rule, config and code fixes in `sam-hunter/` when ALL of these hold: a new test
  covers the case, `npm test` passes, and `qualify eval` on a DB copy
  (`SAM_HUNTER_DATA=<scratch copy>`) keeps good_pass and bad_pass at or above the
  previous report. Diff the board before and after; every card that moves must be
  explained in the report. Commit with a message that names the notice that
  exposed the problem, then push to `macchh10/sam-hunter` with
  `gh auth token -u macchh10` for that one command. Never switch the active gh
  account (it belongs to another business).
- Infrastructure fixes that are plainly broken (wrong path, dead LaunchAgent,
  stale lock), with a backup of anything you overwrite.
- `qa/FINDINGS.md`, reports, and the agents mailbox files.

## What waits for Lu (write it under NEEDS LU, do not do it)

- `recheck --apply`, deck card status changes, or any write that moves a live
  card. List the exact cards it would move and why.
- Anything sent, submitted, posted or paid. HubSpot writes. LinkedIn. Email other
  than the one draft below.
- Deck UI changes or Netlify deploys (they need QA in signed-in Chrome first).
- Deleting n8n workflows, rotating keys, changing set-aside or clearance policy,
  or any rule change that drops a good regression case.
- Fixes that fail tests or regression after two attempts: revert and report.

## Output

- `qa/reports/<YYYY-MM-DD>-<A|B>.md`: what was checked, findings (each with
  evidence, severity, fixed or open), fixes with commit hashes, NEEDS LU.
- Update `qa/FINDINGS.md` (one row per finding: id, first seen, status, owner).
- Session end per `CLAUDE.md`: append `agents/LOG.md`, refresh `agents/LATEST.md`,
  one outbox note, and one Gmail draft to luis@omegacortex.ai with subject
  "OMEGACORTEX agents: <date> Sunday QA <A|B>". Plain text, no dashes, short.
