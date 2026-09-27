#!/usr/bin/env python3
"""Prove an export template was compiled with the PCK key in GODOT_SCRIPT_ENCRYPTION_KEY.

    GODOT_SCRIPT_ENCRYPTION_KEY=<hex> python3 release/check_template_key.py <template>

<template> is a raw template binary (.exe / Mach-O) or a macOS template .zip, in which case
every binary under Contents/MacOS/ is checked.

Why this exists: an export against a template built with a DIFFERENT key succeeds without a
word and produces a build that cannot open its own pack. Godot compiles the key into the
binary as a plain 32-byte array (core/io/file_access_encrypted.h: script_encryption_key), so
the bytes are searchable, and their presence is the cheapest proof the pairing is right.
Prints nothing about the key itself. Exit 0 = found, 1 = not found / bad input.
"""
import os
import sys
import zipfile


def main() -> int:
    key_hex = os.environ.get("GODOT_SCRIPT_ENCRYPTION_KEY", "").strip()
    if len(key_hex) != 64:
        print("check_template_key: GODOT_SCRIPT_ENCRYPTION_KEY is not 64 hex chars", file=sys.stderr)
        return 1
    key = bytes.fromhex(key_hex)
    # Stock templates carry Godot's default all-zero key array, so a zero key "matches" them.
    if key == bytes(32):
        print("check_template_key: all-zero key is Godot's default, not a key", file=sys.stderr)
        return 1
    path = sys.argv[1]
    blobs = []
    if path.endswith(".zip"):
        with zipfile.ZipFile(path) as z:
            for name in z.namelist():
                if "/Contents/MacOS/" in name and not name.endswith("/"):
                    blobs.append((name, z.read(name)))
    else:
        with open(path, "rb") as f:
            blobs.append((path, f.read()))
    if not blobs:
        print(f"check_template_key: no template binary found in {path}", file=sys.stderr)
        return 1
    ok = True
    for name, data in blobs:
        if key in data:
            print(f"check_template_key: key present in {name}")
        else:
            print(f"check_template_key: key NOT present in {name}", file=sys.stderr)
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
