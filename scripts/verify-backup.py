#!/usr/bin/env python3
"""
Verify an n8n workflow export is usable.

The failure this catches: n8n's exporter faithfully writes out BLOB-corrupted
workflows as {"type": "Buffer", "data": [...]} instead of a node array. Such a
backup looks fine, has a plausible file size, and is completely unusable for
restore. This happened on Aug 9 2026 and nearly cost the 43-node production
workflow.

Usage:
    ./verify-backup.py <file.json> [...]

Exit codes:
    0  all workflows have proper JSON node arrays
    1  at least one workflow is BLOB-encoded or malformed
"""

import json
import sys


def is_buffer(value):
    return (
        isinstance(value, dict)
        and value.get("type") == "Buffer"
        and isinstance(value.get("data"), list)
    )


def check_file(path):
    try:
        with open(path) as fh:
            data = json.load(fh)
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL  {path}\n      could not parse: {exc}")
        return False

    workflows = data if isinstance(data, list) else [data]
    ok = True

    for wf in workflows:
        name = wf.get("name", "<unnamed>")
        nodes = wf.get("nodes")

        if is_buffer(nodes):
            print(f"FAIL  {name}\n      nodes stored as Buffer BLOB, unusable for restore")
            print( "      decode with scripts/decode-buffers.py before trusting this file")
            ok = False
        elif not isinstance(nodes, list):
            print(f"FAIL  {name}\n      nodes is {type(nodes).__name__}, expected list")
            ok = False
        elif len(nodes) == 0:
            print(f"WARN  {name}\n      0 nodes, workflow is empty")
        else:
            conns = wf.get("connections")
            flag = "  (connections are BLOB)" if is_buffer(conns) else ""
            print(f"OK    {name}  ->  {len(nodes)} nodes{flag}")
            if flag:
                ok = False

    return ok


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)

    results = [check_file(p) for p in sys.argv[1:]]

    print()
    if all(results):
        print("PASS  every workflow has a proper JSON node array")
        sys.exit(0)

    print("FAIL  at least one workflow is unusable, do not rely on this backup")
    sys.exit(1)


if __name__ == "__main__":
    main()
