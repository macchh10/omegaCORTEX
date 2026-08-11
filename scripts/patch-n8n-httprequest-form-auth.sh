#!/usr/bin/env bash
# Patch n8n HttpRequestV3 so httpCustomAuth.body merges into form/formData
# after form-urlencoded conversion. Required for WEBS ASP.NET login.
# Re-run after n8n upgrades. Idempotent.
set -euo pipefail
HR="$(dirname "$(dirname "$(which n8n)")")/lib/node_modules/n8n/node_modules/n8n-nodes-base/dist/nodes/HttpRequest/V3/HttpRequestV3.node.js"
# Homebrew node@24 path fallback
if [[ ! -f "$HR" ]]; then
  HR="/opt/homebrew/lib/node_modules/n8n/node_modules/n8n-nodes-base/dist/nodes/HttpRequest/V3/HttpRequestV3.node.js"
fi
[[ -f "$HR" ]] || { echo "HttpRequestV3.node.js not found"; exit 1; }
python3 - "$HR" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
if 'OMEGACORTEX patch: form-urlencoded' in text:
    print('already patched:', path)
    raise SystemExit(0)
old = """                    if (customAuth.body) {
                        requestOptions.body = { ...requestOptions.body, ...customAuth.body };
                        authDataKeys.body = Object.keys(customAuth.body);
                    }"""
new = """                    if (customAuth.body) {
                        // OMEGACORTEX patch: form-urlencoded moves body→form before auth merge.
                        // Without this, customAuth.body lands on JSON body and never reaches the wire as form fields.
                        if (requestOptions.form && typeof requestOptions.form === 'object') {
                            requestOptions.form = { ...requestOptions.form, ...customAuth.body };
                            delete requestOptions.body;
                            authDataKeys.form = Object.keys(customAuth.body);
                        }
                        else if (requestOptions.formData && typeof requestOptions.formData === 'object') {
                            requestOptions.formData = { ...requestOptions.formData, ...customAuth.body };
                            delete requestOptions.body;
                            authDataKeys.formData = Object.keys(customAuth.body);
                        }
                        else {
                            requestOptions.body = { ...(requestOptions.body || {}), ...customAuth.body };
                            authDataKeys.body = Object.keys(customAuth.body);
                        }
                    }"""
if old not in text:
    raise SystemExit(f'pattern not found in {path}')
path.write_text(text.replace(old, new, 1))
print('patched', path)
PY
echo "Restart n8n for the patch to load: launchctl kickstart -k gui/\$(id -u)/com.omegacortex.n8n"
