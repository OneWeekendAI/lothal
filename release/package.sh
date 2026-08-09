#!/usr/bin/env bash
# Package both platform builds into release artifacts and sign the manifest.
#
#   ./release/package.sh 0.1.0
#
# Produces build/release/v<version>/ containing the two zips, SHA256SUMS.txt, and latest.json
# — the signed document every installed Lothal reads to learn that this release exists.
#
# Nothing here talks to the network. Uploading is release/upload.sh, deliberately separate, so
# that the step which signs with the private key and the step which touches the public bucket
# are never the same command.

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: release/package.sh <version> [--macos-only]   e.g. 0.1.0" >&2; exit 1; }

# --macos-only exists because the Rust native core (rust/, lothal.gdextension) is macOS-only:
# there is no windows.* entry and no .dll, and the GDScript physics classes it replaced are
# deleted, so a Windows export today has no powertrain at all. Packaging the stale pre-port
# Windows build alongside a hardened macOS one would ship the very GDScript the port exists to
# remove, and pointing the manifest at a 0.1.0 Windows zip under a 0.2.0 version would make
# that build offer ITSELF the update forever (see the version check below).
#
# Omitting the platform is safe by construction: UpdateCheck.parse_manifest returns
# "no build for this platform" when downloads has no entry for the running OS, so a Windows
# user is told nothing rather than handed a broken download. upload.sh keeps the newest three
# release prefixes, so v0.1.0 stays in the bucket and existing Windows links keep working.
MACOS_ONLY=0
[ "${2:-}" = "--macos-only" ] && MACOS_ONLY=1

PRIVATE_KEY="${LOTHAL_SIGNING_KEY:-$HOME/.lothal/update_private.pem}"
BASE_URL="${LOTHAL_BASE_URL:-https://dl.meetdev.in}"
NOTES_URL="${LOTHAL_NOTES_URL:-https://github.com/OneWeekendAI/lothal-public/releases}"

MAC_APP="build/Lothal.app"
WIN_DIR="build/windows"
OUT="build/release/v$VERSION"

# The version in the binary and the version being packaged must be the same number. They are
# written in two places by two different hands, and when they drift the failure is silent and
# permanent: a v0.2.0 build that still reports 0.1.0 will offer ITSELF the 0.2.0 update, on
# every launch, forever.
IN_CODE=$(sed -n 's/^const CURRENT := "\(.*\)"$/\1/p' src/app/version.gd)
[ "$IN_CODE" = "$VERSION" ] || {
  echo "error: src/app/version.gd says CURRENT = \"$IN_CODE\", but packaging \"$VERSION\"." >&2
  echo "       Update the constant and rebuild — the binaries in build/ carry the old number." >&2
  exit 1
}

# The SAME check against export_presets.cfg, which is a third hand writing the number and was
# missed by the check above — v0.2.0 shipped with a bundle still declaring 0.1.0 because of it.
#
# This one does not break the update channel, so nothing fails loudly: the app reports the right
# version to the user and the wrong one to the operating system. The costs are quiet and awkward
# to undo — the Finder's Get Info and Windows' file properties both name the old release, and
# macOS refuses to install a bundle over one whose CFBundleShortVersionString is not lower, so a
# genuinely newer build can be declined as already-present.
#
# All three keys are checked, not just the first: short_version is what people read, version is
# what macOS compares, and product_version is the Windows resource. They drift independently.
for key in short_version version product_version; do
  found=$(sed -n "s|^application/$key=\"\(.*\)\"$|\1|p" export_presets.cfg | sort -u)
  [ "$found" = "$VERSION" ] || {
    echo "error: export_presets.cfg has application/$key = \"$found\", but packaging \"$VERSION\"." >&2
    echo "       Update it and re-export — the bundle would declare the wrong version to the OS." >&2
    exit 1
  }
done

[ -f "$PRIVATE_KEY" ] || {
  echo "error: no signing key at $PRIVATE_KEY" >&2
  echo "       Run release/keygen.sh once, or point LOTHAL_SIGNING_KEY at your backup." >&2
  exit 1
}

# The public key must be the mate of the private one. Signing with a key whose public half is
# not the one compiled into the binaries produces a manifest that verifies nowhere — and the
# only symptom is that nobody is ever offered an update, which is indistinguishable from
# nobody having run the app.
openssl rsa -in "$PRIVATE_KEY" -pubout 2>/dev/null | diff -q - keys/update_public.pem >/dev/null || {
  echo "error: $PRIVATE_KEY is not the mate of keys/update_public.pem." >&2
  echo "       Manifests signed with it would verify on no installed copy of Lothal." >&2
  exit 1
}

[ -d "$MAC_APP" ] || { echo "error: no macOS build at $MAC_APP — run ./build_macos.sh" >&2; exit 1; }
if [ "$MACOS_ONLY" = "0" ]; then
  [ -f "$WIN_DIR/Lothal.exe" ] || { echo "error: no Windows build at $WIN_DIR — run ./build_windows.sh" >&2; exit 1; }

  # Refuse to package Windows while the native core is macOS-only. Without this, forgetting
  # --macos-only silently zips whatever stale build sits in build/windows/ — and the only one
  # that exists is from before the Rust port, so it carries motor_model.gdc, propeller_model.gdc,
  # battery_model.gdc and powertrain.gdc: the exact GDScript the port exists to remove, in the
  # form that decompiles in ten minutes. That is a moat breach dressed as a successful release,
  # and it nearly shipped.
  #
  # This used to check `grep -q '^windows' lothal.gdextension`, on the reasoning that the
  # gdextension is what decides whether an export can load a native core. That guard silently
  # disarmed itself the moment the windows.* entries were ADDED to the gdextension in
  # preparation for the CI build — declaring the library is a statement of intent that costs one
  # line, while producing the .dll requires a Windows runner, so the declaration necessarily
  # lands first and the guard would wave through every release in the gap. A check that stops
  # protecting you exactly when you start doing the risky thing is worse than no check, because
  # it reads as protection.
  #
  # So the guard is on the artifact, and specifically on the EXPORT OUTPUT rather than on the
  # source tree. Godot copies a GDExtension's declared library in beside the executable, so a
  # Windows export that loaded the core has lothal_core.dll sitting in $WIN_DIR and one that did
  # not, does not. That makes the check a direct test of the hazard — "does this exact build
  # carry a physics engine" — rather than a proxy for it.
  #
  # A timestamp comparison was tried here first and is not sufficient: it can only order the
  # files, and the pre-port export is a self-consistent set of files that happens to be wrong.
  # Freshly rebuilding the stale Windows tree would satisfy any mtime rule while still shipping
  # the deleted GDScript. Presence of the core is not orderable and not fakeable by rebuilding.
  [ -f "$WIN_DIR/lothal_core.dll" ] || {
    echo "error: $WIN_DIR/Lothal.exe has no lothal_core.dll beside it, so this export never" >&2
    echo "       loaded the native core. The Rust core owns the powertrain and the licence" >&2
    echo "       gate and the GDScript versions were deleted in the port, so this build has" >&2
    echo "       no physics and cannot be activated — and if it predates the port it carries" >&2
    echo "       the decompilable GDScript physics the port exists to remove." >&2
    echo "       Build Windows via the windows-build workflow, or use:" >&2
    echo "       release/package.sh $VERSION --macos-only" >&2
    exit 1
  }
fi

# Re-check the bundle here as well as in build_macos.sh. This is the last point before the
# artifact becomes a download, and a bundle can be broken after it was built — by an editor
# touching a file inside it, by a copy that dropped extended attributes.
codesign --verify --deep --strict "$MAC_APP" >/dev/null 2>&1 || {
  echo "error: $MAC_APP signature does not verify; it would not launch on another Mac." >&2
  exit 1
}

rm -rf "$OUT"
mkdir -p "$OUT"

MAC_ZIP="Lothal-$VERSION-macos-universal.zip"
WIN_ZIP="Lothal-$VERSION-windows-x64.zip"

echo "==> zipping macOS bundle"
# ditto rather than zip: it preserves the resource forks and extended attributes that carry the
# code signature. A plain `zip` of a signed .app can arrive with the signature stripped, which
# puts the download straight back into the state that will not launch.
ditto -c -k --sequesterRsrc --keepParent "$MAC_APP" "$OUT/$MAC_ZIP"

if [ "$MACOS_ONLY" = "0" ]; then
  echo "==> zipping Windows build"
  ditto -c -k "$WIN_DIR" "$OUT/$WIN_ZIP"
else
  echo "==> SKIPPING Windows (--macos-only): no build will be advertised for it"
fi

echo "==> hashing"
if [ "$MACOS_ONLY" = "0" ]; then
  ( cd "$OUT" && shasum -a 256 "$MAC_ZIP" "$WIN_ZIP" > SHA256SUMS.txt )
else
  ( cd "$OUT" && shasum -a 256 "$MAC_ZIP" > SHA256SUMS.txt )
fi
cat "$OUT/SHA256SUMS.txt" | sed 's/^/  /'

MAC_SHA=$(awk -v f="$MAC_ZIP" '$2 == f {print $1}' "$OUT/SHA256SUMS.txt")
MAC_SIZE=$(stat -f%z "$OUT/$MAC_ZIP")
if [ "$MACOS_ONLY" = "0" ]; then
  WIN_SHA=$(awk -v f="$WIN_ZIP" '$2 == f {print $1}' "$OUT/SHA256SUMS.txt")
  WIN_SIZE=$(stat -f%z "$OUT/$WIN_ZIP")
else
  WIN_SHA=""
  WIN_SIZE=0
fi

echo "==> writing manifest"
# The payload is built as a compact single-line JSON string and then signed AS THAT STRING.
# UpdateCheck verifies the signature over the payload text exactly as it arrives, never over a
# re-serialisation of it — key order and float formatting do not survive a round trip through
# two different JSON writers, and a signature that depends on them would verify here and fail
# in the field.
PAYLOAD=$(python3 -c '
import json, sys
version, released, notes, base, mz, ms, msz, wz, ws, wsz = sys.argv[1:]
downloads = {
    "macos": {"url": "%s/v%s/%s" % (base, version, mz), "size": int(msz), "sha256": ms},
}
# An empty Windows hash means --macos-only: the key is OMITTED rather than written with blank
# fields. A present-but-empty entry would pass the type checks in parse_manifest and hand a
# Windows user a zero-byte download; an absent key returns "no build for this platform" and
# offers nothing, which is the honest answer while the native core is macOS-only.
if ws:
    downloads["windows"] = {"url": "%s/v%s/%s" % (base, version, wz), "size": int(wsz), "sha256": ws}
print(json.dumps({
    "schema": 1,
    "version": version,
    "released": released,
    "min_version": "0.0.0",
    "notes_url": notes,
    "downloads": downloads,
}, separators=(",", ":"), sort_keys=True))
' "$VERSION" "$(date -u +%Y-%m-%d)" "$NOTES_URL" "$BASE_URL" \
  "$MAC_ZIP" "$MAC_SHA" "$MAC_SIZE" "$WIN_ZIP" "$WIN_SHA" "$WIN_SIZE")

printf '%s' "$PAYLOAD" > "$OUT/payload.json"
SIGNATURE=$(openssl dgst -sha256 -sign "$PRIVATE_KEY" "$OUT/payload.json" | openssl base64 -A)

python3 -c '
import json, sys
payload, signature, out = sys.argv[1:]
open(out, "w").write(json.dumps({"payload": payload, "signature": signature}))
' "$PAYLOAD" "$SIGNATURE" "$OUT/latest.json"

rm "$OUT/payload.json"

# Verify the signature we just made, with the public key that ships in the binary, before this
# ever reaches a user. A packaging script that emits manifests nobody can verify is exactly the
# failure this whole design is meant to make impossible, and it costs one openssl call to rule
# out here rather than after the release is live.
python3 -c '
import json, sys
doc = json.load(open(sys.argv[1]))
sys.stdout.write(doc["payload"])
' "$OUT/latest.json" > "$OUT/.verify_payload"
python3 -c '
import base64, json, sys
doc = json.load(open(sys.argv[1]))
open(sys.argv[2], "wb").write(base64.b64decode(doc["signature"]))
' "$OUT/latest.json" "$OUT/.verify_sig"

if openssl dgst -sha256 -verify keys/update_public.pem \
     -signature "$OUT/.verify_sig" "$OUT/.verify_payload" >/dev/null 2>&1; then
  echo "  manifest signature verifies against keys/update_public.pem"
else
  echo "error: the manifest just written does NOT verify against the shipped public key." >&2
  rm -f "$OUT/.verify_payload" "$OUT/.verify_sig"
  exit 1
fi
rm -f "$OUT/.verify_payload" "$OUT/.verify_sig"

echo
echo "packaged: $(pwd)/$OUT"
ls -lh "$OUT" | sed 's/^/  /'
echo
echo "next: release/upload.sh $VERSION --dry-run"
