#!/bin/bash
# Sunday QA for SAM Hunter and WEBS. launchd (com.omegacortex.sunday-qa) runs this
# at 09:00 and 15:00 on Sundays; the hour picks review A or B. Brief: qa/SUNDAY-QA.md
#
#   sunday-qa.sh [A|B]     force a review
#   DRY_RUN=1 sunday-qa.sh show the prompt, spend nothing

set -uo pipefail

ROOT="$HOME/omegaCORTEX"
# claude finds its keychain login through USER; without it the run says "Not logged in".
export USER="${USER:-$(id -un)}" LOGNAME="${LOGNAME:-$(id -un)}"
export PATH="/opt/homebrew/opt/node@24/bin:/opt/homebrew/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
DAY="$(date +%Y-%m-%d)"
REVIEW="${1:-$([ "$(date +%H)" -lt 12 ] && echo A || echo B)}"
LOGDIR="$ROOT/qa/logs"
LOG="$LOGDIR/$DAY-$REVIEW.log"
LOCK="$LOGDIR/sunday-qa.lock"
TIMEOUT_SECONDS=3600

mkdir -p "$ROOT/qa/reports" "$LOGDIR"

if ! mkdir "$LOCK" 2>/dev/null; then
  OWNER=$(cat "$LOCK/pid" 2>/dev/null)
  if [ -n "$OWNER" ] && kill -0 "$OWNER" 2>/dev/null; then echo "review already running ($OWNER)" >> "$LOG"; exit 0; fi
  rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null; mkdir "$LOCK" 2>/dev/null || exit 0
fi
echo $$ > "$LOCK/pid"
trap 'rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null' EXIT

PROMPT="Sunday QA review $REVIEW for $DAY. Follow qa/SUNDAY-QA.md exactly: run the review $REVIEW checklist, fix only what the brief allows, and write qa/reports/$DAY-$REVIEW.md before anything else ends the run. Nobody is watching and Lu will not answer questions, so decide within the rules and put anything outside them under NEEDS LU."

if [ "${DRY_RUN:-0}" = 1 ]; then echo "$PROMPT"; exit 0; fi

echo "[$(date '+%F %T')] start review $REVIEW" >> "$LOG"
cd "$ROOT" || exit 1
claude -p "$PROMPT" --permission-mode bypassPermissions --add-dir "$ROOT/sam-hunter" >> "$LOG" 2>&1 &
PID=$!
( sleep "$TIMEOUT_SECONDS"; kill -TERM "$PID" 2>/dev/null ) &
WATCH=$!
wait "$PID"; RC=$?
kill "$WATCH" 2>/dev/null
echo "[$(date '+%F %T')] end review $REVIEW rc=$RC" >> "$LOG"

if [ ! -s "$ROOT/qa/reports/$DAY-$REVIEW.md" ]; then
  printf '# Sunday QA %s %s\n\nFAILED: claude exited %s without writing a report. See qa/logs/%s-%s.log\n' \
    "$DAY" "$REVIEW" "$RC" "$DAY" "$REVIEW" > "$ROOT/qa/reports/$DAY-$REVIEW.md"
fi
