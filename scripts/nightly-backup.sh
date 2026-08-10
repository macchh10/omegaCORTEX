#!/usr/bin/env bash
#
# Unattended nightly backup. Export, decode, verify, scan, commit, push.
#
# Installed as a LaunchAgent. See docs/SETUP.md.
# Commits only when there is an actual change, so the log stays meaningful.
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

export PATH="/opt/homebrew/opt/node@24/bin:/opt/homebrew/bin:/usr/bin:/bin"
STAMP="$(date '+%Y-%m-%d %H:%M')"

echo "=== nightly backup ${STAMP} ==="

if ! ./scripts/backup.sh; then
  echo "BACKUP FAILED. Not committing."
  exit 1
fi

if git diff --quiet -- workflows/ && git diff --cached --quiet -- workflows/; then
  echo "No workflow changes. Nothing to commit."
  exit 0
fi

git add workflows/
git commit -q -m "Nightly workflow backup ${STAMP}"

if git remote get-url origin >/dev/null 2>&1; then
  if git push -q; then
    echo "Pushed."
  else
    echo "Commit made locally but push failed. Push manually."
    exit 1
  fi
else
  echo "No remote configured. Committed locally only."
fi

echo "Done."
