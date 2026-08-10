#!/usr/bin/env bash
#
# Export every n8n workflow, decode any BLOB corruption, verify the result.
#
# Writes a dated snapshot into backups/ (gitignored) and refreshes workflows/
# with per-workflow files for committing. workflows/ is only updated after the
# secret scan passes, so a hardcoded key cannot reach git through this path.
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M)"
OUT="${REPO}/backups/${STAMP}"
mkdir -p "$OUT"

# The LaunchAgent runs Node 24. A shell without it will fail on n8n 2.33+.
export PATH="/opt/homebrew/opt/node@24/bin:$PATH"

echo "n8n $(n8n --version 2>/dev/null || echo '(version unavailable)')"
echo "Backing up to ${OUT}"
echo

RAW="${OUT}/all-workflows.raw.json"
n8n export:workflow --all --output="$RAW"

echo
echo "Decoding any Buffer-encoded workflows..."
CLEAN="${OUT}/all-workflows.json"
python3 "${REPO}/scripts/decode-buffers.py" "$RAW" "$CLEAN"

echo
echo "Verifying..."
if ! python3 "${REPO}/scripts/verify-backup.py" "$CLEAN"; then
  echo
  echo "Backup FAILED verification. Investigate before trusting it."
  exit 1
fi

# Also snapshot the LaunchAgent plist, which encodes the Node 24 PATH fix.
cp ~/Library/LaunchAgents/com.omegacortex.n8n.plist "${OUT}/" 2>/dev/null || true

echo
echo "Scanning snapshot for credentials..."
if ! "${REPO}/scripts/scan-secrets.sh" "$OUT"; then
  echo
  echo "Snapshot saved to ${OUT} but NOT staged into workflows/."
  echo "Remove the credential, rotate it, then re-run this script."
  exit 1
fi

echo
echo "Staging per-workflow files into workflows/ ..."
python3 - "$CLEAN" "${REPO}/workflows" <<'PY'
import json, re, sys, pathlib

src, dest = sys.argv[1], pathlib.Path(sys.argv[2])
dest.mkdir(parents=True, exist_ok=True)

for wf in json.load(open(src)):
    slug = re.sub(r'[^a-z0-9]+', '-', wf.get('name', 'unnamed').lower()).strip('-')
    path = dest / f"{slug}.json"
    path.write_text(json.dumps(wf, indent=1, sort_keys=True))
    print(f"  {path.name}  ({len(wf.get('nodes', []))} nodes)")
PY

echo
echo "Done. Snapshot: ${OUT}"
echo "Review 'git diff workflows/' then commit."
