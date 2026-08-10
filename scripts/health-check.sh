#!/usr/bin/env bash
#
# Is n8n up, are the right workflows armed, and did this morning's runs pass.
#
# Run this daily. It is the two-minute check from docs/RUNBOOK.md.
#
set -uo pipefail

BASE="http://localhost:5678"
export PATH="/opt/homebrew/opt/node@24/bin:$PATH"

echo "=== n8n health ==="
CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE}/rest/settings" 2>/dev/null || echo "000")

if [[ "$CODE" != "200" ]]; then
  echo "DOWN. /rest/settings returned ${CODE}"
  echo
  echo "Process:"
  pgrep -fl n8n || echo "  no n8n process running"
  echo
  echo "LaunchAgent:"
  launchctl print gui/501/com.omegacortex.n8n 2>/dev/null \
    | grep -E "state =|last exit code" | sed 's/^/  /' || echo "  not loaded"
  echo
  echo "Last errors:"
  tail -20 ~/Library/Logs/omegacortex-n8n-error.log 2>/dev/null | sed 's/^/  /'
  echo
  echo "A Node version mismatch is the most common cause. n8n 2.33+ needs Node"
  echo ">= 22.22, and /opt/homebrew/bin/node is Node 20. The plist PATH must put"
  echo "/opt/homebrew/opt/node@24/bin first."
  exit 1
fi

echo "UP  (${BASE})  n8n $(n8n --version 2>/dev/null || echo '?')"
echo "Node $(node --version 2>/dev/null || echo '?')"

echo
echo "=== wake schedule ==="
pmset -g sched 2>/dev/null | sed 's/^/  /' || echo "  unavailable"
echo "  (Mac must be awake before 5:20 AM or scheduled runs are silently skipped)"

echo
echo "=== workflows and recent executions ==="
echo "Open ${BASE}/home/executions and confirm:"
echo "  - Contract Scanner ran at 5:20 AM and succeeded"
echo "  - Lead Intelligence v2 ran at 6:00 AM and succeeded"
echo "  - no unexplained red rows"
echo
echo "A green run that produced nothing is still a failure. Check that"
echo "Select Award Candidates emitted more than 0 items."
