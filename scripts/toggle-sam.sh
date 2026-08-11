#!/usr/bin/env bash
#
# Enable or disable the SAM.gov intake branch on Contract Scanner and on the
# restored WEBS Test workflow (if present), without deleting nodes.
#
#   ./scripts/toggle-sam.sh off [--yes]
#   ./scripts/toggle-sam.sh on  [--yes]
#   ./scripts/toggle-sam.sh status
#
# Off = disconnect NAICS List -> SAM.gov Query (and disable the SAM node).
# On  = restore that edge and re-enable the node.
#
# Does not touch database.sqlite. Uses n8n CLI only. Backs up before mutate.
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/opt/homebrew/opt/node@24/bin:/opt/homebrew/bin:/usr/bin:/bin"

ACTION="${1:-status}"
YES=0
for arg in "${@:2}"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
  esac
done

STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="/tmp/omega-toggle-sam-${STAMP}"
mkdir -p "$WORK"
BACKUP_DIR="${REPO}/backups/toggle-sam"
mkdir -p "$BACKUP_DIR"

# Primary production scanner + optional WEBS test (may still be BLOB-corrupted)
IDS=(0bTuf3RMzVQHjH8E z0ZcPBe8fDmKcl9I)

echo "=============================================="
echo " OMEGACORTEX  toggle SAM.gov intake: ${ACTION}"
echo "=============================================="

if [[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:5678/rest/settings)" != "200" ]]; then
  echo "n8n is not responding on localhost:5678."
  exit 1
fi

status_one() {
  local id="$1" file="$2"
  python3 - "$id" "$file" <<'PY'
import json,sys
wid, path = sys.argv[1], sys.argv[2]
try:
    data=json.load(open(path))
except Exception as e:
    print(f"{wid}: unreadable ({e})")
    sys.exit(0)
wf=data[0] if isinstance(data,list) else data
nodes=wf.get("nodes")
if not isinstance(nodes, list):
    print(f"{wf.get('name',wid)}: nodes not a list (BLOB?) — skip")
    sys.exit(0)
by={n["name"]:n for n in nodes}
sam=by.get("SAM.gov Query")
conns=wf.get("connections",{})
naics=conns.get("NAICS List",{}).get("main",[[]])
targets=[d["node"] for b in naics for d in b]
linked="SAM.gov Query" in targets
disabled=bool(sam.get("disabled")) if sam else None
print(f"{wf.get('name')}: SAM node={'present' if sam else 'missing'} disabled={disabled} NAICS->SAM={linked}")
PY
}

for id in "${IDS[@]}"; do
  n8n export:workflow --id="$id" --output="${WORK}/${id}.json" >/dev/null 2>&1 || {
    echo "  export failed for ${id} (may not exist)"
    continue
  }
  python3 "${REPO}/scripts/decode-buffers.py" "${WORK}/${id}.json" "${WORK}/${id}.decoded.json" >/dev/null 2>&1 || true
  if [[ -f "${WORK}/${id}.decoded.json" ]]; then
    status_one "$id" "${WORK}/${id}.decoded.json"
  else
    status_one "$id" "${WORK}/${id}.json"
  fi
done

if [[ "$ACTION" == "status" ]]; then
  exit 0
fi

if [[ "$ACTION" != "on" && "$ACTION" != "off" ]]; then
  echo "Usage: $0 on|off|status [--yes]"
  exit 1
fi

if [[ "$YES" -ne 1 ]]; then
  read -r -p "Apply SAM ${ACTION} to live workflows? (yes/no) " ANSWER
  [[ "$ANSWER" == "yes" ]] || { echo "Aborted."; exit 0; }
fi

for id in "${IDS[@]}"; do
  src="${WORK}/${id}.decoded.json"
  [[ -f "$src" ]] || src="${WORK}/${id}.json"
  [[ -f "$src" ]] || continue

  python3 - "$src" "$WORK/${id}.patched.json" "$ACTION" <<'PY'
import json, sys
src, dst, action = sys.argv[1], sys.argv[2], sys.argv[3]
data=json.load(open(src))
wfs=data if isinstance(data,list) else [data]
changed=False
for wf in wfs:
    nodes=wf.get("nodes")
    if not isinstance(nodes, list):
        print(f"  skip {wf.get('name')}: nodes not list")
        continue
    by={n["name"]:n for n in nodes}
    if "SAM.gov Query" not in by or "NAICS List" not in by:
        print(f"  skip {wf.get('name')}: no SAM branch")
        continue
    sam=by["SAM.gov Query"]
    conns=wf.setdefault("connections", {})
    naics=conns.setdefault("NAICS List", {}).setdefault("main", [[]])
    if not naics:
        naics.append([])
        conns["NAICS List"]["main"]=naics
    branch=naics[0]
    has=any(d.get("node")=="SAM.gov Query" for d in branch)
    if action=="off":
        naics[0]=[d for d in branch if d.get("node")!="SAM.gov Query"]
        sam["disabled"]=True
        # Keep a marker so we can restore cleanly
        sam.setdefault("notes", "")
        if "OMEGA_SAM_TOGGLED_OFF" not in str(sam.get("notes")):
            sam["notes"]=(sam.get("notes") or "") + "\nOMEGA_SAM_TOGGLED_OFF"
        changed=True
        print(f"  {wf.get('name')}: SAM disabled, NAICS->SAM disconnected")
    else:
        sam["disabled"]=False
        if not has:
            naics[0].append({"node":"SAM.gov Query","type":"main","index":0})
        notes=str(sam.get("notes") or "").replace("OMEGA_SAM_TOGGLED_OFF","").strip()
        if notes:
            sam["notes"]=notes
        elif "notes" in sam:
            del sam["notes"]
        changed=True
        print(f"  {wf.get('name')}: SAM enabled, NAICS->SAM connected")
if not changed:
    print("  no changes")
json.dump(wfs if isinstance(data,list) else wfs[0], open(dst,"w"), indent=1)
open(src+".changed","w").write("1" if changed else "0")
PY

  if [[ "$(cat "${src}.changed" 2>/dev/null || echo 0)" != "1" ]]; then
    continue
  fi

  # Only import if nodes verified as list
  if ! python3 "${REPO}/scripts/verify-backup.py" "${WORK}/${id}.patched.json" >/dev/null; then
    echo "  VERIFY FAIL for ${id} — not importing"
    continue
  fi

  cp "${WORK}/${id}.json" "${BACKUP_DIR}/${id}-pre-${STAMP}.json"
  echo "  importing ${id}"
  n8n import:workflow --input="${WORK}/${id}.patched.json" 2>&1 | sed 's/^/    /'
  n8n publish:workflow --id="$id" 2>&1 | sed 's/^/    /' || true
  # Keep production scanner active; WEBS test stays inactive unless already active
  if [[ "$id" == "0bTuf3RMzVQHjH8E" ]]; then
    n8n update:workflow --id="$id" --active=true 2>&1 | sed 's/^/    /' || true
  fi
done

echo
echo "--- Restarting n8n ---"
launchctl kickstart -k gui/501/com.omegacortex.n8n
sleep 15
for i in $(seq 1 10); do
  [[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:5678/rest/settings)" == "200" ]] && break
  sleep 4
done

echo
echo "--- Status after ---"
for id in "${IDS[@]}"; do
  n8n export:workflow --id="$id" --output="${WORK}/${id}.after.json" >/dev/null 2>&1 || continue
  python3 "${REPO}/scripts/decode-buffers.py" "${WORK}/${id}.after.json" "${WORK}/${id}.after.decoded.json" >/dev/null 2>&1 || true
  f="${WORK}/${id}.after.decoded.json"
  [[ -f "$f" ]] || f="${WORK}/${id}.after.json"
  status_one "$id" "$f"
done

echo
echo "Done. SAM intake is ${ACTION}."
