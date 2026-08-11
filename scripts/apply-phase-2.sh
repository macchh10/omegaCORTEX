#!/usr/bin/env bash
#
# Applies Phase 2 from docs/MASTER-HANDOFF.md to Lead Intelligence v2:
#   Route enrichment by Source before award research.
#   SAM.gov  -> existing USASpending path
#   WEBS     -> skip USASpending, emit N/A state markers, join at scoring
#
# Usage:
#   ./scripts/apply-phase-2.sh           # interactive confirm
#   ./scripts/apply-phase-2.sh --yes     # non-interactive
#   ./scripts/apply-phase-2.sh --revert  # restore pre-apply export
#   ./scripts/apply-phase-2.sh --dry-run # transform + report only
#
# Reversible. Does not write database.sqlite. Uses n8n CLI only.
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/opt/homebrew/opt/node@24/bin:/opt/homebrew/bin:/usr/bin:/bin"

YES=0
REVERT=0
DRY=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
    --revert) REVERT=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
  esac
done

STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="/tmp/omega-phase2-${STAMP}"
mkdir -p "$WORK"
WID="Om3gaLeadIntelV2"
BACKUP_DIR="${REPO}/backups/phase-2"
mkdir -p "$BACKUP_DIR"

echo "=============================================="
echo " OMEGACORTEX  Phase 2 — source routing"
echo "=============================================="
echo "n8n $(n8n --version 2>/dev/null || echo '?')   Node $(node --version 2>/dev/null || echo '?')"
echo "Working dir: ${WORK}"
echo

if [[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:5678/rest/settings)" != "200" ]]; then
  echo "n8n is not responding on localhost:5678. Start it first."
  exit 1
fi

if [[ "$REVERT" -eq 1 ]]; then
  LAST="$(ls -1t "${BACKUP_DIR}"/${WID}-pre-*.json 2>/dev/null | head -1 || true)"
  if [[ -z "$LAST" ]]; then
    echo "No Phase 2 backup found under ${BACKUP_DIR}"
    exit 1
  fi
  echo "Reverting from ${LAST}"
  if [[ "$YES" -ne 1 ]]; then
    read -r -p "Proceed with revert? (yes/no) " ANSWER
    [[ "$ANSWER" == "yes" ]] || { echo "Aborted."; exit 0; }
  fi
  n8n import:workflow --input="$LAST" 2>&1 | sed 's/^/  /'
  n8n publish:workflow --id="$WID" 2>&1 | sed 's/^/  /'
  n8n update:workflow --id="$WID" --active=true 2>&1 | sed 's/^/  /' || true
  echo "Revert imported and publish attempted. Verify in UI."
  exit 0
fi

echo "--- Exporting ${WID} ---"
n8n export:workflow --id="$WID" --output="${WORK}/${WID}.json" >/dev/null 2>&1 \
  || { echo "export failed"; exit 1; }
cp "${WORK}/${WID}.json" "${BACKUP_DIR}/${WID}-pre-${STAMP}.json"
echo "  backup: ${BACKUP_DIR}/${WID}-pre-${STAMP}.json"

python3 "${REPO}/scripts/decode-buffers.py" "${WORK}/${WID}.json" "${WORK}/${WID}.decoded.json" \
  || { echo "decode failed"; exit 1; }

echo
echo "--- Planned changes ---"
python3 - "$WORK" "$WID" <<'PY'
import json, sys, pathlib, copy, uuid

work = pathlib.Path(sys.argv[1])
wid = sys.argv[2]
src = work / f"{wid}.decoded.json"
data = json.load(open(src))
wfs = data if isinstance(data, list) else [data]
assert len(wfs) == 1
wf = wfs[0]
nodes = wf["nodes"]
conns = wf.setdefault("connections", {})
by_name = {n["name"]: n for n in nodes}
changes = []

required = [
    "Select Leads for Research",
    "Prepare Lead Award Searches",
    "Search Comparable Awards",
    "Select Award Candidates",
    "Fetch Award Details",
    "Prepare Award Transaction Queries",
    "Fetch Award Modifications",
    "Normalize Award Intelligence",
    "Award Intelligence Output",
    "Agent Intel v2 Scoring",
]
missing = [n for n in required if n not in by_name]
if missing:
    print("FATAL: missing nodes:", missing)
    sys.exit(2)

# Idempotency: already applied?
if "Route by Source" in by_name and "Bypass Award Research" in by_name and "Join Award Paths" in by_name:
    print("Already applied (Route by Source / Bypass / Join present).")
    (work / "CHANGE_COUNT").write_text("0")
    json.dump(wfs, open(work / f"{wid}.patched.json", "w"), indent=1)
    sys.exit(0)

sel = by_name["Select Leads for Research"]
prep = by_name["Prepare Lead Award Searches"]
norm = by_name["Normalize Award Intelligence"]
score = by_name["Agent Intel v2 Scoring"]

# Positions relative to existing layout
sx, sy = sel.get("position", [1760, 288])
px, py = prep.get("position", [1808, 672])
nx, ny = norm.get("position", [3088, 432])
scx, scy = score.get("position", [3312, 432])

def new_id(prefix):
    return f"{prefix}-{uuid.uuid4().hex[:10]}"

route_node = {
    "parameters": {
        "conditions": {
            "options": {
                "caseSensitive": False,
                "leftValue": "",
                "typeValidation": "loose",
                "version": 2,
            },
            "conditions": [
                {
                    "id": new_id("cond"),
                    "leftValue": "={{ $json.Source }}",
                    "rightValue": "WEBS",
                    "operator": {
                        "type": "string",
                        "operation": "contains",
                    },
                }
            ],
            "combinator": "and",
        },
        "options": {},
    },
    "id": new_id("route"),
    "name": "Route by Source",
    "type": "n8n-nodes-base.if",
    "typeVersion": 2.2,
    "position": [sx + 220, sy + 120],
}

bypass_code = r'''// WEBS / state leads skip federal USASpending research.
// Emit one marker row per lead so Agent Intel v2 Scoring still runs.
// Award Evidence is explicitly N/A — absence of federal history is expected.
const leads = $input.all().map(i => i.json);
const today = $now.toFormat('yyyy-MM-dd');
return leads.map(lead => {
  const key = lead['Lead Key'];
  return {
    json: {
      'Award Key': `${key}|STATE-NA`,
      'Lead Key': key,
      'Lead Source': lead.Source || 'WEBS',
      'Research Scope': 'State-N/A',
      'Award ID': '',
      'Generated Award ID': '',
      'Parent Award ID': '',
      'Solicitation ID': '',
      'Recipient': '',
      'Parent Recipient': '',
      'Awarding Agency': lead.Agency || '',
      'Sub Agency': lead['Sub Agency'] || '',
      'Awarding Office': lead.Office || '',
      'Funding Office': '',
      'Description': 'N/A - State opportunity (no federal USASpending research)',
      'Award Amount': 0,
      'Potential Award Amount': 0,
      'Start Date': '',
      'End Date': '',
      'Potential End Date': '',
      'Signed Date': '',
      'NAICS': lead.NAICS || '',
      'NAICS Description': '',
      'PSC': lead.PSC || '',
      'PSC Description': '',
      'Contract Type': '',
      'Pricing Type': '',
      'Set Aside': '',
      'Competition': '',
      'Offers Received': 0,
      'Solicitation Procedures': '',
      'Multiple / Single Award': '',
      'Modification Count': 0,
      'Latest Modification': '',
      'Latest Modification Date': '',
      'Recompete Signal': 'N/A - State opportunity',
      'Incumbent Strength': 'N/A',
      'Award Relevance': 0,
      'Source URL': lead['Source Link'] || '',
      'Date Researched': today,
      'Data Quality Notes': 'N/A - State opportunity. Federal award research intentionally skipped.',
      'Lead-Award Fingerprint': `${key}|STATE-NA`,
      'Award Evidence': 'N/A - State opportunity',
      'State Bypass': true,
    }
  };
});
'''

bypass_node = {
    "parameters": {"jsCode": bypass_code},
    "id": new_id("bypass"),
    "name": "Bypass Award Research",
    "type": "n8n-nodes-base.code",
    "typeVersion": 2,
    "position": [px + 200, py + 280],
}

join_node = {
    "parameters": {
        "mode": "append",
        "options": {},
    },
    "id": new_id("join"),
    "name": "Join Award Paths",
    "type": "n8n-nodes-base.merge",
    "typeVersion": 3.1,
    "position": [nx + 160, ny + 40],
}

nodes.extend([route_node, bypass_node, join_node])
changes.append("add IF Route by Source")
changes.append("add Code Bypass Award Research")
changes.append("add Merge Join Award Paths")

# Rewire:
# Select Leads for Research -> Route by Source
# Route false (federal) -> Prepare Lead Award Searches  (output index 1)
# Route true  (WEBS)    -> Bypass Award Research       (output index 0)
# Normalize Award Intelligence -> Join Award Paths input 0  (and keep Award Intelligence Output)
# Bypass Award Research -> Join Award Paths input 1
# Join Award Paths -> Agent Intel v2 Scoring

# Remove old Select -> Prepare edge
sel_conn = conns.get("Select Leads for Research", {})
main = sel_conn.get("main", [])
new_main = []
for branch in main:
    kept = [d for d in branch if d.get("node") != "Prepare Lead Award Searches"]
    new_main.append(kept)
# ensure at least one branch
if not new_main:
    new_main = [[]]
if not new_main[0]:
    new_main[0] = []
# add route
new_main[0].append({"node": "Route by Source", "type": "main", "index": 0})
conns["Select Leads for Research"] = {"main": new_main}
changes.append("Select Leads for Research -> Route by Source")

# Route outputs: [true/WEBS, false/federal] for If v2
conns["Route by Source"] = {
    "main": [
        [{"node": "Bypass Award Research", "type": "main", "index": 0}],
        [{"node": "Prepare Lead Award Searches", "type": "main", "index": 0}],
    ]
}
changes.append("Route true(WEBS)->Bypass; false(federal)->Prepare")

# Normalize currently connects to Award Intelligence Output and Agent Intel v2 Scoring
norm_conn = conns.get("Normalize Award Intelligence", {}).get("main", [[]])
norm_branch = list(norm_conn[0]) if norm_conn else []
# drop direct scoring edge; keep award output; add join input 0
norm_branch = [d for d in norm_branch if d.get("node") != "Agent Intel v2 Scoring"]
if not any(d.get("node") == "Award Intelligence Output" for d in norm_branch):
    # preserve if somehow missing
    pass
norm_branch.append({"node": "Join Award Paths", "type": "main", "index": 0})
conns["Normalize Award Intelligence"] = {"main": [norm_branch]}
changes.append("Normalize -> Join Award Paths (input 0); keep Award Intelligence Output")

conns["Bypass Award Research"] = {
    "main": [[{"node": "Join Award Paths", "type": "main", "index": 1}]]
}
changes.append("Bypass -> Join Award Paths (input 1)")

conns["Join Award Paths"] = {
    "main": [[{"node": "Agent Intel v2 Scoring", "type": "main", "index": 0}]]
}
changes.append("Join Award Paths -> Agent Intel v2 Scoring")

for c in changes:
    print(f"  + {c}")
print(f"\n{len(changes)} change(s) staged. Node count {len(nodes)}.")
(work / "CHANGE_COUNT").write_text(str(len(changes)))
json.dump(wfs, open(work / f"{wid}.patched.json", "w"), indent=1)

# Graph sanity
by_name = {n["name"]: n for n in nodes}
assert "Route by Source" in by_name
# Select must not point at Prepare directly
for branch in conns["Select Leads for Research"]["main"]:
    assert all(d["node"] != "Prepare Lead Award Searches" for d in branch)
# Scoring only from Join
score_sources = []
for src, outs in conns.items():
    for branches in outs.get("main", []):
        for d in branches:
            if d.get("node") == "Agent Intel v2 Scoring":
                score_sources.append(src)
assert score_sources == ["Join Award Paths"], score_sources
print("  graph sanity OK")
PY

COUNT="$(cat "${WORK}/CHANGE_COUNT" 2>/dev/null || echo 0)"
if [[ "$COUNT" == "0" ]]; then
  echo
  echo "Nothing to change. Already applied."
  exit 0
fi

echo
echo "--- Verifying patched file ---"
python3 "${REPO}/scripts/verify-backup.py" "${WORK}/${WID}.patched.json" \
  || { echo "VERIFY FAILED. Aborting."; exit 1; }

if [[ "$DRY" -eq 1 ]]; then
  echo "Dry run only. Patched file: ${WORK}/${WID}.patched.json"
  exit 0
fi

echo
echo "About to import Phase 2 into the LIVE instance (${COUNT} structural changes)."
echo "Backup: ${BACKUP_DIR}/${WID}-pre-${STAMP}.json"
if [[ "$YES" -ne 1 ]]; then
  read -r -p "Proceed? (yes/no) " ANSWER
  [[ "$ANSWER" == "yes" ]] || { echo "Aborted. Nothing changed."; exit 0; }
fi

echo
echo "--- Importing ---"
n8n import:workflow --input="${WORK}/${WID}.patched.json" 2>&1 | sed 's/^/  /'
echo "--- Publishing (import writes draft only) ---"
n8n publish:workflow --id="$WID" 2>&1 | sed 's/^/  /'
echo "--- Ensuring active ---"
n8n update:workflow --id="$WID" --active=true 2>&1 | sed 's/^/  /' || true

echo
echo "--- Restarting n8n ---"
launchctl kickstart -k gui/501/com.omegacortex.n8n
sleep 18
for i in $(seq 1 12); do
  [[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:5678/rest/settings)" == "200" ]] && break
  sleep 5
done

echo
echo "--- Verifying live ---"
n8n export:workflow --id="$WID" --output="${WORK}/${WID}.after.json" >/dev/null 2>&1
python3 "${REPO}/scripts/decode-buffers.py" "${WORK}/${WID}.after.json" "${WORK}/${WID}.after.decoded.json" >/dev/null
python3 - "$WORK" "$WID" <<'PY'
import json, sys, pathlib
work = pathlib.Path(sys.argv[1]); wid = sys.argv[2]
data = json.load(open(work / f"{wid}.after.decoded.json"))
wf = data[0] if isinstance(data, list) else data
names = {n["name"] for n in wf["nodes"]}
need = {"Route by Source", "Bypass Award Research", "Join Award Paths"}
ok = need.issubset(names)
print(("OK " if ok else "FAIL"), f"nodes present: {sorted(need & names)} missing={sorted(need-names)}")
print(f"  total nodes: {len(wf['nodes'])}")
conns = wf.get("connections", {})
# scoring source
srcs=[]
for src, outs in conns.items():
    for branches in outs.get("main", []):
        for d in branches:
            if d.get("node")=="Agent Intel v2 Scoring":
                srcs.append(src)
print(("OK " if srcs==["Join Award Paths"] else "FAIL"), "scoring fed by", srcs)
# select -> route
sel=conns.get("Select Leads for Research",{}).get("main",[[]])
sel_targets=[d["node"] for b in sel for d in b]
print(("OK " if "Route by Source" in sel_targets and "Prepare Lead Award Searches" not in sel_targets else "FAIL"),
      "Select targets", sel_targets)
sys.exit(0 if ok and srcs==["Join Award Paths"] else 1)
PY
LIVE_OK=$?

echo
echo "=============================================="
if [[ $LIVE_OK -eq 0 ]]; then
  echo " PHASE 2 APPLIED AND VERIFIED"
else
  echo " APPLIED BUT VERIFICATION FAILED"
fi
echo "=============================================="
echo
echo "Next: manually execute Lead Intelligence v2 and check item counts,"
echo "especially Agent Intel v2 Scoring (must be non-zero when research leads exist)."
echo "Revert: ./scripts/apply-phase-2.sh --revert --yes"
echo
