#!/usr/bin/env bash
#
# Applies Phase 0.3 and Phase 1 from docs/MASTER-HANDOFF.md.
#
#   Phase 0.3  Google Sheets backoff -> retryOnFail, maxTries 3, waitBetweenTries 60000
#   Phase 1    SAM.gov query -> postedFrom 60d to 10d, limit 1000 to 200, timeout 120s
#
# Safe to re-run. Idempotent. Exports first, shows a before/after diff, asks for
# confirmation, imports, reactivates, then verifies against the live instance.
#
# It does NOT touch business logic, connections, or node structure. Only the
# retry settings on Sheets-touching nodes and three query parameters on one
# HTTP node.
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/opt/homebrew/opt/node@24/bin:/opt/homebrew/bin:/usr/bin:/bin"

STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="/tmp/omega-phase01-${STAMP}"
mkdir -p "$WORK"

IDS=(Om3gaLeadIntelV2 0bTuf3RMzVQHjH8E Om3gaContextFailure)

echo "=============================================="
echo " OMEGACORTEX  Phase 0.3 + Phase 1"
echo "=============================================="
echo "n8n $(n8n --version 2>/dev/null || echo '?')   Node $(node --version 2>/dev/null || echo '?')"
echo "Working dir: ${WORK}"
echo

if [[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:5678/rest/settings)" != "200" ]]; then
  echo "n8n is not responding on localhost:5678. Start it first."
  exit 1
fi

# ---------- 1. Export ----------
echo "--- Exporting current workflows ---"
for id in "${IDS[@]}"; do
  n8n export:workflow --id="$id" --output="${WORK}/${id}.json" >/dev/null 2>&1 \
    || { echo "export failed for ${id}"; exit 1; }
  echo "  exported ${id}"
done

# ---------- 2. Decode any BLOB corruption ----------
echo
echo "--- Decoding (no-op if already clean) ---"
for id in "${IDS[@]}"; do
  python3 "${REPO}/scripts/decode-buffers.py" "${WORK}/${id}.json" "${WORK}/${id}.decoded.json" \
    || { echo "decode failed for ${id}"; exit 1; }
done

# ---------- 3. Transform ----------
echo
echo "--- Planned changes ---"
python3 - "$WORK" "${IDS[@]}" <<'PY'
import json, sys, pathlib, re

work = pathlib.Path(sys.argv[1])
ids = sys.argv[2:]
changes = 0

def is_sheets(node):
    t = node.get("type", "")
    if "googleSheets" in t:
        return True
    if "httpRequest" in t and "sheets.googleapis.com" in json.dumps(node.get("parameters", {})):
        return True
    return False

for wid in ids:
    src = work / f"{wid}.decoded.json"
    data = json.load(open(src))
    wfs = data if isinstance(data, list) else [data]

    for wf in wfs:
        print(f"\n{wf.get('name')}")
        for node in wf.get("nodes", []):

            # --- Phase 0.3: Sheets backoff ---
            if is_sheets(node):
                old = node.get("waitBetweenTries", 0)
                if old != 60000 or not node.get("retryOnFail"):
                    print(f"  [0.3] {node['name']}: wait {old} -> 60000, tries -> 3")
                    node["retryOnFail"] = True
                    node["maxTries"] = 3
                    node["waitBetweenTries"] = 60000
                    changes += 1

            # --- Phase 1: SAM.gov query ---
            if node.get("name") == "SAM.gov Query":
                params = node.setdefault("parameters", {})
                opts = params.setdefault("options", {})

                old_to = opts.get("timeout")
                if old_to != 120000:
                    print(f"  [1.3] timeout {old_to} -> 120000")
                    opts["timeout"] = 120000
                    changes += 1

                qp = params.get("queryParameters", {}).get("parameters", [])
                for p in qp:
                    if p.get("name") == "limit" and str(p.get("value")) != "200":
                        print(f"  [1.2] limit {p.get('value')} -> 200")
                        p["value"] = "200"
                        changes += 1
                    if p.get("name") == "postedFrom":
                        v = str(p.get("value", ""))
                        nv = re.sub(r"days:\s*\d+", "days: 10", v)
                        if nv != v:
                            print(f"  [1.1] postedFrom window -> 10 days")
                            p["value"] = nv
                            changes += 1

    json.dump(wfs, open(work / f"{wid}.patched.json", "w"), indent=1)

print(f"\n{changes} change(s) staged.")
(work / "CHANGE_COUNT").write_text(str(changes))
PY

COUNT="$(cat "${WORK}/CHANGE_COUNT" 2>/dev/null || echo 0)"
if [[ "$COUNT" == "0" ]]; then
  echo
  echo "Nothing to change. Already applied."
  exit 0
fi

# ---------- 4. Verify patched files ----------
echo
echo "--- Verifying patched files ---"
for id in "${IDS[@]}"; do
  python3 "${REPO}/scripts/verify-backup.py" "${WORK}/${id}.patched.json" >/dev/null \
    || { echo "VERIFY FAILED for ${id}. Aborting, nothing imported."; exit 1; }
done
echo "  all patched files verified"

# ---------- 5. Confirm ----------
echo
echo "About to import ${COUNT} change(s) into the LIVE instance."
echo "Originals preserved at ${WORK}/<id>.json"
read -r -p "Proceed? (yes/no) " ANSWER
[[ "$ANSWER" == "yes" ]] || { echo "Aborted. Nothing changed."; exit 0; }

# ---------- 6. Import + reactivate ----------
echo
echo "--- Importing ---"
for id in "${IDS[@]}"; do
  echo "  ${id}"
  n8n import:workflow --input="${WORK}/${id}.patched.json" 2>&1 | sed 's/^/    /'
  # import deactivates the target; put it back
  n8n update:workflow --id="$id" --active=true 2>&1 | sed 's/^/    /'
done

echo
echo "--- Restarting n8n ---"
launchctl kickstart -k gui/501/com.omegacortex.n8n
sleep 20

# ---------- 7. Verify live ----------
echo
echo "--- Verifying against the live instance ---"
for i in $(seq 1 12); do
  [[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:5678/rest/settings)" == "200" ]] && break
  sleep 5
done

for id in "${IDS[@]}"; do
  n8n export:workflow --id="$id" --output="${WORK}/${id}.after.json" >/dev/null 2>&1
  python3 "${REPO}/scripts/decode-buffers.py" "${WORK}/${id}.after.json" "${WORK}/${id}.after.decoded.json" >/dev/null
done

python3 - "$WORK" "${IDS[@]}" <<'PY'
import json, sys, pathlib
work = pathlib.Path(sys.argv[1]); ids = sys.argv[2:]
ok = True
for wid in ids:
    data = json.load(open(work / f"{wid}.after.decoded.json"))
    for wf in (data if isinstance(data, list) else [data]):
        nodes = wf.get("nodes", [])
        sheets = [n for n in nodes if "googleSheets" in n.get("type","")
                  or ("httpRequest" in n.get("type","")
                      and "sheets.googleapis.com" in json.dumps(n.get("parameters",{})))]
        fixed = [n for n in sheets if n.get("waitBetweenTries") == 60000]
        mark = "OK " if len(fixed) == len(sheets) else "FAIL"
        if mark == "FAIL": ok = False
        print(f"{mark}  {wf.get('name')}: sheets backoff {len(fixed)}/{len(sheets)}")

        sam = next((n for n in nodes if n.get("name") == "SAM.gov Query"), None)
        if sam:
            qp = sam["parameters"].get("queryParameters", {}).get("parameters", [])
            lim = next((p["value"] for p in qp if p["name"] == "limit"), "?")
            pf  = next((str(p["value"]) for p in qp if p["name"] == "postedFrom"), "?")
            to  = sam["parameters"].get("options", {}).get("timeout")
            good = str(lim) == "200" and "days: 10" in pf and to == 120000
            if not good: ok = False
            print(f"{'OK ' if good else 'FAIL'}  SAM.gov: limit={lim} timeout={to} window={'10d' if 'days: 10' in pf else '?'}")
sys.exit(0 if ok else 1)
PY
LIVE_OK=$?

echo
echo "--- Schedules ---"
curl -s -H "browser-id: cli" http://localhost:5678/rest/active-workflows 2>/dev/null | head -c 300
echo

echo
echo "=============================================="
if [[ $LIVE_OK -eq 0 ]]; then
  echo " APPLIED AND VERIFIED"
else
  echo " APPLIED BUT VERIFICATION FAILED - check above"
fi
echo "=============================================="
cat <<'EOF'

DO THIS NOW, IN THE BROWSER:

  1. Open http://localhost:5678
  2. Open each of these and confirm the badge reads "Published" in green:
       OMEGACORTEX Contract Scanner
       OMEGACORTEX Lead Intelligence v2
       OMEGACORTEX Context Failure Logger
     If any shows "Publish" instead, click it, then Publish in the modal.
     An unpublished workflow will NOT fire at 5:20 or 6:00 AM.

  3. Open OMEGACORTEX Contract Scanner and click "Execute workflow".
     Watch SAM.gov Query. It should return records in well under a minute
     instead of timing out after 345 seconds.

STILL MANUAL (2 minutes, in the n8n UI):

  - Delete the workflow "ZZ TEMP publish-semantics probe (safe to delete)"
  - Move the SAM.gov api_key into an n8n credential and rotate it at sam.gov

EOF
