#!/usr/bin/env bash
#
# WA State Award Intelligence — fix scoring + draft gate so WEBS / state leads
# are not blocked or down-ranked solely for lacking federal award history.
#
# Confirmed live defect (Aug 10/11):
#   Agent Intel v2 Scoring:
#     evidenceConfidence = awards ? ... : 'Low'
#     decision requires evidenceConfidence !== 'Low' to Pursue
#   Evaluate Draft Eligibility:
#     blocks when Evidence Confidence === 'Low'
#
# Fix:
#   - Detect Source containing WEBS (or Award Evidence / State Bypass markers)
#   - Set Evidence Confidence = 'N/A - State', Research Confidence accordingly
#   - Neutral awardRelevance (50) and agencyBuying floor so missing federal
#     awards are not a negative signal
#   - Do not push "No sufficiently relevant historical award evidence" for state
#   - Gate: skip the Low-evidence blocker when confidence starts with 'N/A'
#     or Source is WEBS / state
#
# Usage:
#   ./scripts/apply-wa-awards.sh
#   ./scripts/apply-wa-awards.sh --yes
#   ./scripts/apply-wa-awards.sh --revert
#   ./scripts/apply-wa-awards.sh --dry-run
#
set -euo pipefail

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
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \?//'; exit 0 ;;
  esac
done

STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="/tmp/omega-wa-awards-${STAMP}"
mkdir -p "$WORK"
WID="Om3gaLeadIntelV2"
BACKUP_DIR="${REPO}/backups/wa-awards"
mkdir -p "$BACKUP_DIR"

echo "=============================================="
echo " OMEGACORTEX  WA State Award Intelligence"
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
    echo "No WA-awards backup found under ${BACKUP_DIR}"
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
  echo "Revert done."
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
import json, sys, pathlib, re

work = pathlib.Path(sys.argv[1])
wid = sys.argv[2]
data = json.load(open(work / f"{wid}.decoded.json"))
wfs = data if isinstance(data, list) else [data]
wf = wfs[0]
by_name = {n["name"]: n for n in wf["nodes"]}
changes = 0

scoring = by_name.get("Agent Intel v2 Scoring")
gate = by_name.get("Evaluate Draft Eligibility")
if not scoring or not gate:
    print("FATAL: required code nodes missing")
    sys.exit(2)

scode = scoring["parameters"]["jsCode"]
gcode = gate["parameters"]["jsCode"]

# ---------- Scoring ----------
if "OMEGA_WA_STATE_AWARD_FIX" in scode:
    print("  scoring: already patched")
else:
    # Insert state detection + neutral evidence after allAwards/awards lines
    old = """  const allAwards=grouped[key]||[];
  const awards=allAwards.filter(a=>Number(a['Award Relevance']||0)>=55);"""
    new = """  const allAwards=grouped[key]||[];
  // OMEGA_WA_STATE_AWARD_FIX
  const isStateLead=/webs/i.test(String(lead.Source||''))
    || allAwards.some(a=>a['State Bypass']===true || /^N\\/A\\s*-\\s*State/i.test(String(a['Award Evidence']||a['Data Quality Notes']||'')));
  const awards=isStateLead?[]:allAwards.filter(a=>Number(a['Award Relevance']||0)>=55);"""
    if old not in scode:
        print("FATAL: scoring anchor (allAwards/awards) not found — refuse to patch blindly")
        sys.exit(3)
    scode = scode.replace(old, new, 1)
    changes += 1
    print("  scoring: add isStateLead detection")

    old = """  const awardRelevance=awards.length?Math.round(awards.reduce((s,a)=>s+Number(a['Award Relevance']),0)/awards.length):0;
  const evidenceConfidence=awards.length>=2&&awardRelevance>=65?'High':awards.length>=1?'Moderate':'Low';
  const agencyBuying=Math.min(100,20+awards.length*15+agencyEvidence.length*5);"""
    new = """  const awardRelevance=isStateLead?50:(awards.length?Math.round(awards.reduce((s,a)=>s+Number(a['Award Relevance']),0)/awards.length):0);
  const evidenceConfidence=isStateLead?'N/A - State':(awards.length>=2&&awardRelevance>=65?'High':awards.length>=1?'Moderate':'Low');
  const agencyBuying=isStateLead?Math.min(100,45+agencyEvidence.length*5):Math.min(100,20+awards.length*15+agencyEvidence.length*5);"""
    if old not in scode:
        print("FATAL: scoring evidenceConfidence anchor not found")
        sys.exit(3)
    scode = scode.replace(old, new, 1)
    changes += 1
    print("  scoring: neutral awardRelevance/evidence/agencyBuying for state")

    old = """  const incumbentOpenness=awards.length?Math.max(15,Math.round(100-concentration*70)):35;"""
    new = """  const incumbentOpenness=isStateLead?50:(awards.length?Math.max(15,Math.round(100-concentration*70)):35);"""
    if old not in scode:
        print("FATAL: incumbentOpenness anchor not found")
        sys.exit(3)
    scode = scode.replace(old, new, 1)
    changes += 1
    print("  scoring: neutral incumbentOpenness for state")

    old = """  const valueFit=!median?40:median<=5000000?70:median<=20000000?50:30;"""
    new = """  const valueFit=isStateLead?55:(!median?40:median<=5000000?70:median<=20000000?50:30);"""
    if old not in scode:
        print("FATAL: valueFit anchor not found")
        sys.exit(3)
    scode = scode.replace(old, new, 1)
    changes += 1
    print("  scoring: neutral valueFit for state")

    old = """  const decision=active&&!restricted&&!nonActionable&&!event&&capabilityFit>=70&&eligibility>=55&&score>=65&&evidenceConfidence!=='Low'?'Pursue':score>=40&&active?'Monitor':'Skip';"""
    new = """  const evidenceOk=isStateLead||evidenceConfidence!=='Low';
  const decision=active&&!restricted&&!nonActionable&&!event&&capabilityFit>=70&&eligibility>=55&&score>=65&&evidenceOk?'Pursue':score>=40&&active?'Monitor':'Skip';"""
    if old not in scode:
        print("FATAL: decision anchor not found")
        sys.exit(3)
    scode = scode.replace(old, new, 1)
    changes += 1
    print("  scoring: Pursue no longer requires federal award evidence for state")

    old = """  const incumbentSummary=sortedRecipients.length?sortedRecipients.slice(0,4).map(([n,c])=>n+' ('+c+'/'+awards.length+')').join('; '):'No sufficiently relevant comparable award identified';
  const relevantAwards=awards.slice().sort((a,b)=>Number(b['Award Relevance'])-Number(a['Award Relevance'])).slice(0,3).map(a=>a['Award ID']+' - '+a.Recipient+' - $'+Number(a['Award Amount']||0).toLocaleString('en-US')).join(' | ');"""
    new = """  const incumbentSummary=isStateLead?'N/A - State opportunity (federal incumbents not applicable)':(sortedRecipients.length?sortedRecipients.slice(0,4).map(([n,c])=>n+' ('+c+'/'+awards.length+')').join('; '):'No sufficiently relevant comparable award identified');
  const relevantAwards=isStateLead?'N/A - State opportunity':(awards.slice().sort((a,b)=>Number(b['Award Relevance'])-Number(a['Award Relevance'])).slice(0,3).map(a=>a['Award ID']+' - '+a.Recipient+' - $'+Number(a['Award Amount']||0).toLocaleString('en-US')).join(' | '));"""
    if old not in scode:
        print("FATAL: incumbentSummary anchor not found")
        sys.exit(3)
    scode = scode.replace(old, new, 1)
    changes += 1
    print("  scoring: state-aware incumbent/relevant award text")

    old = """  if (evidenceConfidence==='Low') risks.push('No sufficiently relevant historical award evidence');"""
    new = """  if (!isStateLead && evidenceConfidence==='Low') risks.push('No sufficiently relevant historical award evidence');
  if (isStateLead) risks.push('State opportunity — federal USASpending award history not applicable');"""
    if old not in scode:
        print("FATAL: risks Low-evidence anchor not found")
        sys.exit(3)
    scode = scode.replace(old, new, 1)
    changes += 1
    print("  scoring: state-aware risks")

    old = """  const reasons=['Capability fit: '+capabilityFit+'/100','Eligibility: '+eligibility+'/100','Relevant award evidence: '+awardRelevance+'/100 across '+awards.length+' accepted awards','Evidence confidence: '+evidenceConfidence,'Timing: '+timing+'/100','Change: '+lead['Change Classification']].join('; ');"""
    new = """  const reasons=['Capability fit: '+capabilityFit+'/100','Eligibility: '+eligibility+'/100',(isStateLead?'Award evidence: N/A - State opportunity':'Relevant award evidence: '+awardRelevance+'/100 across '+awards.length+' accepted awards'),'Evidence confidence: '+evidenceConfidence,'Timing: '+timing+'/100','Change: '+lead['Change Classification']].join('; ');"""
    if old not in scode:
        print("FATAL: reasons anchor not found")
        sys.exit(3)
    scode = scode.replace(old, new, 1)
    changes += 1
    print("  scoring: state-aware score reasons")

    # Live code keeps Last Researched + Research Coverage + Research Confidence compact.
    old = "'Research Coverage':'Source record; relevance-filtered USAspending awards; relevance-filtered Agency Intel; verified company profile',\n    'Research Confidence':evidenceConfidence==='High'?'High':evidenceConfidence==='Moderate'?'Medium':'Low','Source Link':lead['Source Link'],"
    new = "'Research Coverage':isStateLead?'Source record; state opportunity (federal award research skipped); relevance-filtered Agency Intel; verified company profile':'Source record; relevance-filtered USAspending awards; relevance-filtered Agency Intel; verified company profile',\n    'Research Confidence':isStateLead?'N/A - State':(evidenceConfidence==='High'?'High':evidenceConfidence==='Moderate'?'Medium':'Low'),'Source Link':lead['Source Link'],\n    'Award Evidence':isStateLead?'N/A - State opportunity':'Federal award research',"
    if old not in scode:
        # Fallback: Coverage alone
        old2 = "'Research Coverage':'Source record; relevance-filtered USAspending awards; relevance-filtered Agency Intel; verified company profile'"
        new2 = "'Research Coverage':isStateLead?'Source record; state opportunity (federal award research skipped); relevance-filtered Agency Intel; verified company profile':'Source record; relevance-filtered USAspending awards; relevance-filtered Agency Intel; verified company profile'"
        if old2 not in scode:
            print("FATAL: Research Coverage anchor not found")
            print("  snippet:", repr(scode[scode.find('Research Coverage')-20:scode.find('Research Coverage')+180]) if 'Research Coverage' in scode else 'missing')
            sys.exit(3)
        scode = scode.replace(old2, new2, 1)
        old3 = "'Research Confidence':evidenceConfidence==='High'?'High':evidenceConfidence==='Moderate'?'Medium':'Low'"
        new3 = "'Research Confidence':isStateLead?'N/A - State':(evidenceConfidence==='High'?'High':evidenceConfidence==='Moderate'?'Medium':'Low')"
        if old3 in scode:
            scode = scode.replace(old3, new3, 1)
        # Inject Award Evidence near Evidence Confidence field
        old4 = "'Evidence Confidence':evidenceConfidence"
        new4 = "'Evidence Confidence':evidenceConfidence,\n    'Award Evidence':isStateLead?'N/A - State opportunity':'Federal award research'"
        if old4 in scode and "'Award Evidence'" not in scode:
            scode = scode.replace(old4, new4, 1)
        changes += 1
        print("  scoring: state-aware research coverage/confidence (fallback anchors)")
    else:
        scode = scode.replace(old, new, 1)
        changes += 1
        print("  scoring: state-aware research coverage/confidence + Award Evidence field")

    scoring["parameters"]["jsCode"] = scode

# ---------- Gate ----------
if "OMEGA_WA_STATE_AWARD_FIX" in gcode:
    print("  gate: already patched")
else:
    old = """  if (String(lead?.['Evidence Confidence']) === 'Low') blockers.push('supporting evidence confidence is Low');"""
    new = """  // OMEGA_WA_STATE_AWARD_FIX — state leads must not be blocked for missing federal awards
  const evidenceConf = String(lead?.['Evidence Confidence'] || '');
  const isStateEvidence = /^N\\/A/i.test(evidenceConf)
    || /webs/i.test(String(lead?.Source || ''))
    || /^N\\/A\\s*-\\s*State/i.test(String(lead?.['Award Evidence'] || ''));
  if (!isStateEvidence && evidenceConf === 'Low') blockers.push('supporting evidence confidence is Low');"""
    if old not in gcode:
        print("FATAL: gate Low-evidence blocker anchor not found")
        sys.exit(3)
    gcode = gcode.replace(old, new, 1)
    changes += 1
    print("  gate: skip Low-evidence block for state / N/A evidence")

    # eligibility reason text should not imply federal evidence for state
    old = """    ? `${classification}; qualified at ${lead['Pursuit Score']}/100 with ${lead['Capability Fit']}/100 capability fit, verified contact, active deadline, and ${lead['Evidence Confidence']} evidence.`"""
    new = """    ? `${classification}; qualified at ${lead['Pursuit Score']}/100 with ${lead['Capability Fit']}/100 capability fit, verified contact, active deadline, and ${lead['Evidence Confidence']} evidence${isStateEvidence ? ' (state — federal awards not required)' : ''}.`"""
    if old not in gcode:
        print("WARN: gate reason string anchor not found (non-fatal)")
    else:
        gcode = gcode.replace(old, new, 1)
        changes += 1
        print("  gate: reason text notes state exception")

    gate["parameters"]["jsCode"] = gcode

print(f"\n{changes} change(s) staged.")
(work / "CHANGE_COUNT").write_text(str(changes))
json.dump(wfs, open(work / f"{wid}.patched.json", "w"), indent=1)

# Syntax check both codes via node --check
open(work / "scoring.js", "w").write(scoring["parameters"]["jsCode"])
open(work / "gate.js", "w").write(gate["parameters"]["jsCode"])
PY

COUNT="$(cat "${WORK}/CHANGE_COUNT" 2>/dev/null || echo 0)"

echo
echo "--- Syntax-checking patched Code nodes ---"
# n8n Code nodes are not full modules; wrap lightly for node --check
node --check "${WORK}/scoring.js" 2>&1 | sed 's/^/  scoring: /' || true
node --check "${WORK}/gate.js" 2>&1 | sed 's/^/  gate: /' || true
# node --check on bare scripts with const/$ may still parse; treat parse errors as fatal
if ! node --check "${WORK}/scoring.js" 2>/tmp/omega-score-syn.err; then
  # Allow ReferenceError-free parse: --check only parses
  if grep -q "SyntaxError" /tmp/omega-score-syn.err; then
    cat /tmp/omega-score-syn.err
    echo "FATAL: scoring syntax error"
    exit 1
  fi
fi
if ! node --check "${WORK}/gate.js" 2>/tmp/omega-gate-syn.err; then
  if grep -q "SyntaxError" /tmp/omega-gate-syn.err; then
    cat /tmp/omega-gate-syn.err
    echo "FATAL: gate syntax error"
    exit 1
  fi
fi
echo "  syntax OK"

if [[ "$COUNT" == "0" ]]; then
  echo
  echo "Nothing to change. Already applied."
  exit 0
fi

echo
echo "--- Verifying patched file ---"
python3 "${REPO}/scripts/verify-backup.py" "${WORK}/${WID}.patched.json" \
  || { echo "VERIFY FAILED. Aborting."; exit 1; }

# Confirm markers
python3 - <<PY
import json
wf=json.load(open("${WORK}/${WID}.patched.json"))
wf=wf[0] if isinstance(wf,list) else wf
s=next(n for n in wf["nodes"] if n["name"]=="Agent Intel v2 Scoring")["parameters"]["jsCode"]
g=next(n for n in wf["nodes"] if n["name"]=="Evaluate Draft Eligibility")["parameters"]["jsCode"]
assert "OMEGA_WA_STATE_AWARD_FIX" in s
assert "isStateLead" in s
assert "N/A - State" in s
assert "OMEGA_WA_STATE_AWARD_FIX" in g
assert "isStateEvidence" in g
print("  markers OK")
PY

if [[ "$DRY" -eq 1 ]]; then
  echo "Dry run only. Patched file: ${WORK}/${WID}.patched.json"
  exit 0
fi

echo
echo "About to import WA award intelligence fix into the LIVE instance (${COUNT} edits)."
echo "Backup: ${BACKUP_DIR}/${WID}-pre-${STAMP}.json"
if [[ "$YES" -ne 1 ]]; then
  read -r -p "Proceed? (yes/no) " ANSWER
  [[ "$ANSWER" == "yes" ]] || { echo "Aborted. Nothing changed."; exit 0; }
fi

echo
echo "--- Importing ---"
n8n import:workflow --input="${WORK}/${WID}.patched.json" 2>&1 | sed 's/^/  /'
echo "--- Publishing ---"
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
python3 - <<PY
import json
wf=json.load(open("${WORK}/${WID}.after.decoded.json"))
wf=wf[0] if isinstance(wf,list) else wf
s=next(n for n in wf["nodes"] if n["name"]=="Agent Intel v2 Scoring")["parameters"]["jsCode"]
g=next(n for n in wf["nodes"] if n["name"]=="Evaluate Draft Eligibility")["parameters"]["jsCode"]
ok = "OMEGA_WA_STATE_AWARD_FIX" in s and "isStateLead" in s and "OMEGA_WA_STATE_AWARD_FIX" in g and "isStateEvidence" in g
print(("OK " if ok else "FAIL"), "WA state award fix present in scoring+gate")
# Ensure hard Low block without state exception is gone
if "if (String(lead?.['Evidence Confidence']) === 'Low') blockers.push" in g and "isStateEvidence" not in g:
    print("FAIL bare Low blocker still present without exception")
    ok=False
import sys
sys.exit(0 if ok else 1)
PY
LIVE_OK=$?

echo
echo "=============================================="
if [[ $LIVE_OK -eq 0 ]]; then
  echo " WA AWARD FIX APPLIED AND VERIFIED"
else
  echo " APPLIED BUT VERIFICATION FAILED"
fi
echo "=============================================="
echo
echo "Next: execute Lead Intelligence v2 and confirm Agent Intel v2 Scoring > 0"
echo "and that WEBS leads can reach Decision=Pursue without federal awards."
echo "Revert: ./scripts/apply-wa-awards.sh --revert --yes"
echo
