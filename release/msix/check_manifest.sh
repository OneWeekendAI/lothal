#!/usr/bin/env bash
# Everything about the MSIX manifest that can be checked WITHOUT Windows.
#
# The packaging step runs on a CI runner, so every mistake in it costs a full pipeline to find —
# Rust, Godot, 986 tests and two exports, for a typo in an XML attribute. This script front-loads
# the checks that do not need MakeAppx, so the runner is spent on the one thing only it can do.
#
# What it CANNOT catch is MakeAppx's own cross-attribute validation rules, which are not in the
# published schema and not in the docs — "Square310x310Logo requires Wide310x150Logo" is the one
# that has already cost a run. There is no offline oracle for those. The defence against them is
# not a better checker, it is a manifest that declares as little as possible: every optional
# element left out is a rule that cannot be broken. Keep it that way.

set -euo pipefail
cd "$(dirname "$0")"

TEMPLATE="AppxManifest.xml.in"
fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

# ---- 1. Placeholders, and the guard's own false positive ------------------------------------
# package_msix.ps1 substitutes exactly these four and then refuses to pack if any at-delimited
# upper-case token survives — including one written inside a comment, which is how a sentence of
# documentation once failed the build.
expected="IDENTITY_NAME IDENTITY_PUBLISHER PACKAGE_VERSION PUBLISHER_DISPLAY_NAME"
found=$(grep -o '@[A-Z_]\{2,\}@' "$TEMPLATE" | tr -d '@' | sort -u | tr '\n' ' ')
want=$(echo "$expected" | tr ' ' '\n' | sort -u | tr '\n' ' ')
[ "$found" = "$want" ] || err "placeholder set is [$found], expected [$want] — an unknown token will fail the substitution guard"

# ---- 2. XML, including the double-hyphen rule ------------------------------------------------
# XML forbids "--" inside a comment, so a row of hyphens used as a section rule invalidates the
# whole file. MakeAppx reports that as a bare HRESULT with no line number.
python3 - "$TEMPLATE" <<'PY' || fail=1
import sys, xml.dom.minidom
src = open(sys.argv[1]).read()
for name, val in [("IDENTITY_NAME", "X.Y"), ("IDENTITY_PUBLISHER", "CN=x"),
                  ("PUBLISHER_DISPLAY_NAME", "x"), ("PACKAGE_VERSION", "0.0.0.0")]:
    src = src.replace("@%s@" % name, val)
try:
    xml.dom.minidom.parseString(src)
except Exception as e:
    print("FAIL: manifest is not well-formed XML: %s" % e, file=sys.stderr)
    sys.exit(1)
PY

# ---- 3. Every referenced asset exists, at the size its name claims ---------------------------
# A missing asset fails the pack; an asset whose pixels do not match its name packs fine and is
# then rejected by Store ingestion or renders blurred, which is far more expensive to discover.
while IFS= read -r ref; do
    path="${ref//\\//}"
    if [ ! -f "$path" ]; then
        err "manifest references $ref, which does not exist"
        continue
    fi
    # Square44x44Logo.png -> 44x44. StoreLogo.png carries no size in its name; 50x50 is the
    # documented requirement and is asserted by name below rather than inferred.
    base=$(basename "$path")
    case "$base" in
        Square*x*Logo.png)
            dims=${base#Square}; dims=${dims%Logo.png}
            want_w=${dims%x*}; want_h=${dims#*x} ;;
        StoreLogo.png) want_w=50; want_h=50 ;;
        *) continue ;;
    esac
    got_w=$(sips -g pixelWidth  "$path" | tail -1 | awk '{print $2}')
    got_h=$(sips -g pixelHeight "$path" | tail -1 | awk '{print $2}')
    [ "$got_w" = "$want_w" ] && [ "$got_h" = "$want_h" ] \
        || err "$base is ${got_w}x${got_h}, should be ${want_w}x${want_h}"
done < <(grep -o 'assets\\[A-Za-z0-9]*\.png' "$TEMPLATE" | sort -u)

# ---- 4. Assets on disk that nothing references -----------------------------------------------
# Not fatal — but an unreferenced logo is usually the remains of an element that was removed from
# the manifest, and it ships inside the package for no reason.
for f in assets/*.png; do
    grep -q "assets\\\\$(basename "$f")" "$TEMPLATE" || echo "note: $f is not referenced by the manifest"
done

[ "$fail" -eq 0 ] && echo "manifest checks passed" || exit 1
