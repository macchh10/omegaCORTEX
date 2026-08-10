#!/usr/bin/env bash
#
# Scan for credentials before committing.
#
# Why this exists: the SAM.gov API key was hardcoded in plain text as a query
# parameter on the SAM.gov Query node. Every workflow export therefore contained
# it. Exported n8n JSON routinely carries API keys typed directly into HTTP
# Request nodes and Code nodes.
#
# Run this before every commit. Wire it into .git/hooks/pre-commit if you want
# it enforced (see docs/RUNBOOK.md).
#
set -uo pipefail

TARGET="${1:-.}"
FOUND=0

echo "Scanning ${TARGET} for credentials..."
echo

scan() {
  local label="$1" pattern="$2"
  local hits
  hits=$(grep -rInE "$pattern" "$TARGET" \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=backups \
    --exclude="scan-secrets.sh" \
    2>/dev/null || true)

  if [[ -n "$hits" ]]; then
    echo "!! ${label}"
    # Print file:line only. Never echo the secret value itself.
    echo "$hits" | cut -d: -f1,2 | sed 's/^/     /' | sort -u
    echo
    FOUND=1
  fi
}

scan "SAM.gov API key"        'SAM-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}'
scan "Generic api_key param"  'api_key=[A-Za-z0-9_-]{12,}'
scan "Bearer token"           'Bearer[[:space:]]+[A-Za-z0-9._-]{20,}'
scan "Google API key"         'AIza[0-9A-Za-z_-]{35}'
scan "Google OAuth client"    '[0-9]+-[0-9a-z]{32}\.apps\.googleusercontent\.com'
scan "OAuth client secret"    'GOCSPX-[A-Za-z0-9_-]{20,}'
scan "AWS access key"         'AKIA[0-9A-Z]{16}'
scan "Private key block"      'BEGIN[[:space:]]+(RSA|EC|OPENSSH|PRIVATE)[[:space:]]*PRIVATE[[:space:]]+KEY'
scan "Slack token"            'xox[baprs]-[A-Za-z0-9-]{10,}'
scan "Assigned secret"        '"(password|passwd|secret|token|apiKey|accessToken)"[[:space:]]*:[[:space:]]*"[^"]{12,}"'

if [[ $FOUND -eq 1 ]]; then
  echo "BLOCKED. Credentials found. Do not commit."
  echo
  echo "Fix by moving the value into an n8n credential or environment variable,"
  echo "rotating the exposed key at its provider, then re-exporting the workflow."
  exit 1
fi

echo "Clean. No credentials detected."
exit 0
