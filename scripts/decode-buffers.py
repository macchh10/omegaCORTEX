#!/usr/bin/env python3
"""
Repair a BLOB-corrupted n8n workflow export.

When a workflow's nodes/connections are written to SQLite as binary instead of
JSON, n8n exports them as {"type": "Buffer", "data": [byte, byte, ...]}. The
byte array IS the workflow, just encoded. This decodes it back to real JSON so
it can be reimported.

This is what recovered the 43-node Lead Intelligence v2 workflow on Aug 10 2026.

Usage:
    ./decode-buffers.py <input.json> <output.json>

Then reimport, and remember n8n import:workflow DEACTIVATES the target:
    n8n import:workflow --input=<output.json>
    n8n update:workflow --id=<ID> --active=true
"""

import json
import sys

FIELDS = ("nodes", "connections", "pinData", "settings", "staticData", "meta")


def decode(value):
    if (
        isinstance(value, dict)
        and value.get("type") == "Buffer"
        and isinstance(value.get("data"), list)
    ):
        return json.loads(bytes(value["data"]).decode("utf-8"))
    return value


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)

    src, dst = sys.argv[1], sys.argv[2]

    with open(src) as fh:
        data = json.load(fh)

    workflows = data if isinstance(data, list) else [data]

    for wf in workflows:
        for field in FIELDS:
            if field in wf:
                wf[field] = decode(wf[field])

    with open(dst, "w") as fh:
        json.dump(workflows, fh, indent=1)

    for wf in workflows:
        nodes = wf.get("nodes")
        count = len(nodes) if isinstance(nodes, list) else "STILL BROKEN"
        print(f"{count}  nodes  --  {wf.get('name', '<unnamed>')}")

    print(f"\nwrote {dst}")


if __name__ == "__main__":
    main()
