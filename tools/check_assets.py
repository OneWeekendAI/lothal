#!/usr/bin/env python3
"""Licence-ledger check: every shipped file under assets/ must have exactly one row in ASSETS.txt.

Run as `python3 -I tools/check_assets.py` from anywhere. Exit 0 clean, 1 with a list of offenders.
Refuses: files not in the ledger, rows for missing files, malformed rows, disallowed licences, duplicates.
Godot `.import` sidecars are generated and exempt. Mirrors tests/test_asset_ledger.gd.
"""
import os
import re
import sys

ALLOWED = ("CC0-1.0", "GPL-3.0-or-later (own work)")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def check(ledger_text, files):
    """Pure: ledger text + list of 'assets/...' paths -> {kind: [messages]}."""
    errs = {"malformed": [], "licence": [], "duplicate": [], "unlisted": [], "missing": []}
    seen = {}
    for n, line in enumerate(ledger_text.split("\n"), 1):
        line = line.rstrip("\r")
        if line.strip() == "" or line.startswith("#"):
            continue
        cols = line.split("\t")
        path = cols[0]
        if (len(cols) != 5 or any(c.strip() == "" for c in cols) or not path.startswith("assets/")
                or path.endswith("/") or any(ch in path for ch in "*?[") or not DATE.match(cols[4])):
            errs["malformed"].append("line %d: %s" % (n, line[:80]))
            continue
        if cols[3] not in ALLOWED:
            errs["licence"].append("line %d: %s has licence %r" % (n, path, cols[3]))
        if path in seen:
            errs["duplicate"].append("line %d: %s (first on line %d)" % (n, path, seen[path]))
        seen[path] = n
    fileset = set(files)
    errs["unlisted"] = ["not in ledger: %s" % f for f in sorted(fileset) if f not in seen]
    errs["missing"] = ["row for missing file: %s" % p for p in sorted(seen) if p not in fileset]
    return errs


def walk(root):
    out = []
    for d, _, fs in os.walk(os.path.join(root, "assets")):
        for f in fs:
            if not f.endswith(".import"):
                out.append(os.path.relpath(os.path.join(d, f), root).replace(os.sep, "/"))
    return sorted(out)


def main():
    root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    ledger = os.path.join(root, "ASSETS.txt")
    if not os.path.isfile(ledger):
        print("check_assets: ASSETS.txt is missing")
        return 1
    with open(ledger, encoding="utf-8") as fh:
        errs = check(fh.read(), walk(root))
    bad = [(k, m) for k, ms in errs.items() for m in ms]
    for k, m in bad:
        print("check_assets: %s: %s" % (k, m))
    if bad:
        print("check_assets: FAILED, %d problem(s)" % len(bad))
        return 1
    print("check_assets: ok, %d files all in ASSETS.txt" % len(walk(root)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
