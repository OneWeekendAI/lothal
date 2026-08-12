#!/usr/bin/env bash
# Package the platform builds into release artifacts and sign the manifest.
#
#   ./release/package.sh 0.3.0                            # all three platforms
#   ./release/package.sh 0.3.0 --platforms=macos,linux     # a subset
#   ./release/package.sh 0.3.0 --macos-only                # alias for --platforms=macos
#
# Produces build/release/v<version>/ containing one zip per platform, SHA256SUMS.txt, and
# latest.json — the signed document every installed Lothal reads to learn that this release
# exists.
#
# Nothing here talks to the network. Uploading is release/upload.sh, deliberately separate, so
# that the step which signs with the private key and the step which touches the public bucket
# are never the same command.
#
# ---------------------------------------------------------------------------
# WHY THIS IS TABLE-DRIVEN RATHER THAN A PAIR OF IF-BLOCKS
# ---------------------------------------------------------------------------
#
# It used to know about exactly two platforms and carry a --macos-only flag for the third state.
# When Linux shipped in v0.2.0 there was no branch for it, so the Linux zip was built and
# uploaded BY HAND alongside a SHA256SUMS.txt this script had generated for macOS alone.
#
# The result was not a missing feature, it was two broken install paths. The published README
# tells Linux users to run `sha256sum -c --ignore-missing SHA256SUMS.txt`, which exits 1 when
# the file names none of the downloaded files, and tells Windows users to compare against a
# value that came back null. Both blocks then print "CHECKSUM FAILED — do not run it" over a
# perfectly good download. A checksum file that is merely INCOMPLETE does not degrade politely;
# it reads to the user as evidence of tampering, which is the single worst thing an unsigned-
# binary product can tell someone on first contact.
#
# So the platform list is data, and every artifact this script emits is derived from that one
# list. Adding a platform cannot leave the hashes, the manifest and the zips disagreeing,
# because there is no longer a place to add one to only some of them.

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
[ -n "$VERSION" ] || {
  echo "usage: release/package.sh <version> [--platforms=macos,windows,linux]   e.g. 0.3.0" >&2
  exit 1
}
shift

KNOWN_PLATFORMS="macos windows linux"
PLATFORMS="$KNOWN_PLATFORMS"

for arg in "$@"; do
  case "$arg" in
    # Kept because it is named in this script's own error messages, in the release notes, and in
    # muscle memory. It is now just a spelling of --platforms=macos.
    --macos-only)
      PLATFORMS="macos"
      ;;
    --platforms=*)
      PLATFORMS="${arg#--platforms=}"
      PLATFORMS="${PLATFORMS//,/ }"
      ;;
    *)
      echo "error: unknown argument \"$arg\"" >&2
      echo "usage: release/package.sh <version> [--platforms=macos,windows,linux]" >&2
      exit 1
      ;;
  esac
done

[ -n "${PLATFORMS// /}" ] || { echo "error: --platforms selected nothing" >&2; exit 1; }

# A typo in a platform name must not silently produce a smaller release. Without this,
# --platforms=linix packages macOS-and-nothing-else and reports success, which is the same class
# of quiet under-delivery that the incomplete SHA256SUMS was.
for p in $PLATFORMS; do
  case " $KNOWN_PLATFORMS " in
    *" $p "*) ;;
    *)
      echo "error: unknown platform \"$p\" (known: $KNOWN_PLATFORMS)" >&2
      exit 1
      ;;
  esac
done

selected() { case " $PLATFORMS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

PRIVATE_KEY="${LOTHAL_SIGNING_KEY:-$HOME/.lothal/update_private.pem}"
BASE_URL="${LOTHAL_BASE_URL:-https://dl.meetdev.in}"
NOTES_URL="${LOTHAL_NOTES_URL:-https://github.com/OneWeekendAI/lothal-public/releases}"

MAC_APP="build/Lothal.app"
WIN_DIR="build/windows"
LINUX_DIR="build/linux"
OUT="build/release/v$VERSION"

echo "==> packaging v$VERSION for: $PLATFORMS"

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
# what macOS compares, and product_version is the Windows and Linux resource. They drift
# independently, and product_version is declared once per non-macOS preset, so `sort -u` here is
# load-bearing — it collapses agreeing presets and leaves two lines (failing the compare) the
# moment Windows and Linux disagree with each other.
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

# ---------------------------------------------------------------------------
# THE NATIVE-CORE GUARD
# ---------------------------------------------------------------------------
#
# Refuse to package a build whose export never loaded the Rust core. rust/ owns the powertrain,
# the battery and motor models, and the licence gate, and the GDScript implementations of all of
# it were deleted when the port landed. A build without the core is not degraded — it has no
# physics and cannot be activated — and if it predates the port it carries motor_model.gdc,
# propeller_model.gdc, battery_model.gdc and powertrain.gdc: the exact GDScript the port exists
# to remove, in the form that decompiles in ten minutes. That is a moat breach dressed as a
# successful release, and it nearly shipped once already.
#
# This used to check `grep -q '^windows' lothal.gdextension`, on the reasoning that the
# gdextension is what decides whether an export can load a native core. That guard silently
# disarmed itself the moment the windows.* entries were ADDED to the gdextension in preparation
# for the CI build — declaring the library is a statement of intent that costs one line, while
# producing the .dll requires a Windows runner, so the declaration necessarily lands first and
# the guard would wave through every release in the gap. A check that stops protecting you
# exactly when you start doing the risky thing is worse than no check, because it reads as
# protection.
#
# So the guard is on the artifact, and specifically on the EXPORT OUTPUT rather than on the
# source tree. Godot copies a GDExtension's declared library in beside the executable, so an
# export that loaded the core has it sitting in the build dir and one that did not, does not.
# That makes the check a direct test of the hazard — "does this exact build carry a physics
# engine" — rather than a proxy for it.
#
# A timestamp comparison was tried here first and is not sufficient: it can only order the
# files, and the pre-port export is a self-consistent set of files that happens to be wrong.
# Freshly rebuilding the stale tree would satisfy any mtime rule while still shipping the
# deleted GDScript. Presence of the core is not orderable and not fakeable by rebuilding.
#
# The .pck is checked on the same grounds: neither desktop preset embeds it, so an executable
# that travels alone starts and then dies complaining about a missing main scene.
require_files() {
  local platform="$1" dir="$2"; shift 2
  local missing=()
  for f in "$@"; do
    [ -f "$dir/$f" ] || missing+=("$f")
  done
  if [ ${#missing[@]} -ne 0 ]; then
    echo "error: $dir is not a complete $platform build — missing: ${missing[*]}" >&2
    echo "       An export without its native core has no powertrain and cannot be activated;" >&2
    echo "       one without its .pck does not start at all. If it predates the Rust port it" >&2
    echo "       also carries the decompilable GDScript physics the port exists to remove." >&2
    echo "       Build it via the $platform workflow, or drop it: --platforms=..." >&2
    exit 1
  fi
}

if selected macos; then
  [ -d "$MAC_APP" ] || { echo "error: no macOS build at $MAC_APP — run ./build_macos.sh" >&2; exit 1; }
  # Re-check the bundle here as well as in build_macos.sh. This is the last point before the
  # artifact becomes a download, and a bundle can be broken after it was built — by an editor
  # touching a file inside it, by a copy that dropped extended attributes.
  codesign --verify --deep --strict "$MAC_APP" >/dev/null 2>&1 || {
    echo "error: $MAC_APP signature does not verify; it would not launch on another Mac." >&2
    exit 1
  }
fi

if selected windows; then
  [ -d "$WIN_DIR" ] || { echo "error: no Windows build at $WIN_DIR — run the windows-build workflow" >&2; exit 1; }
  require_files windows "$WIN_DIR" Lothal.exe lothal_core.dll Lothal.pck
fi

if selected linux; then
  [ -d "$LINUX_DIR" ] || { echo "error: no Linux build at $LINUX_DIR — run the linux-build workflow" >&2; exit 1; }
  require_files linux "$LINUX_DIR" Lothal.x86_64 liblothal_core.so Lothal.pck

  # Linux has one requirement the other two do not: the executable bit. A GitHub Actions
  # artifact is itself a zip, and actions/upload-artifact does not preserve the mode — so the
  # tree this script packages from has usually been through a download that stripped it. If the
  # bit is missing here it is missing in the release zip, and the user's experience is a
  # double-click that does nothing at all, silently, with no error to search for.
  #
  # Restored rather than merely reported: this is not a signal that the build is wrong, it is a
  # known and total property of how the artifact travelled.
  [ -x "$LINUX_DIR/Lothal.x86_64" ] || {
    echo "  note: $LINUX_DIR/Lothal.x86_64 is not executable (CI artifacts drop the mode) — restoring it"
    chmod +x "$LINUX_DIR/Lothal.x86_64"
  }
fi

rm -rf "$OUT"
mkdir -p "$OUT"

zip_name() {
  case "$1" in
    macos)   echo "Lothal-$VERSION-macos-universal.zip" ;;
    windows) echo "Lothal-$VERSION-windows-x64.zip" ;;
    linux)   echo "Lothal-$VERSION-linux-x64.zip" ;;
  esac
}

# Zipping a plain directory ON A MAC, for a non-Mac user to open.
#
# `ditto -c -k` was used here and puts macOS's extended attributes into the archive as
# AppleDouble sidecars: the published v0.2.0 Linux zip contains ._Lothal.x86_64 and
# ._liblothal_core.so. They are inert, but they are visible, and a paying user's first look
# inside a proprietary download should not be a pile of files that look like the archive was
# assembled carelessly on someone's laptop. `zip -X` writes no extra attribute fields, and the
# explicit excludes keep Finder droppings out.
#
# -r . rather than -r * so that dotfiles are considered and can be excluded by name; the mode
# bits live in the external attributes field, which -X does NOT strip, so the executable bit
# set above survives into the archive.
zip_dir_clean() {
  local src="$1" dest="$2"
  ( cd "$src" && zip -q -r -X "$dest" . -x '.DS_Store' -x '._*' -x '__MACOSX/*' )
}

for p in $PLATFORMS; do
  zip=$(zip_name "$p")
  echo "==> zipping $p"
  case "$p" in
    macos)
      # ditto rather than zip: it preserves the resource forks and extended attributes that
      # carry the code signature. A plain `zip` of a signed .app can arrive with the signature
      # stripped, which puts the download straight back into the state that will not launch.
      # The AppleDouble concern above is inverted here — for the .app those sidecars are the
      # payload, and this zip is only ever opened on a Mac.
      ditto -c -k --sequesterRsrc --keepParent "$MAC_APP" "$OUT/$zip"
      ;;
    windows)
      zip_dir_clean "$WIN_DIR" "$(pwd)/$OUT/$zip"
      ;;
    linux)
      zip_dir_clean "$LINUX_DIR" "$(pwd)/$OUT/$zip"
      ;;
  esac
done

# Assert the Linux zip is actually usable before it becomes a download. Both of these are
# properties of the ARCHIVE rather than of the build, so nothing checked earlier covers them,
# and both fail in a way the user cannot diagnose: a stripped executable bit is a double-click
# that does nothing, and the AppleDouble sidecars are the "assembled on a laptop" smell that a
# proprietary product cannot afford. unzip -Z lists the mode in ls -l form.
if selected linux; then
  linux_zip="$OUT/$(zip_name linux)"
  if unzip -Z1 "$linux_zip" | grep -q '^\._\|/\._\|__MACOSX'; then
    echo "error: $linux_zip contains AppleDouble sidecars (._*) — it was zipped with ditto" >&2
    unzip -Z1 "$linux_zip" | grep '^\._\|/\._\|__MACOSX' >&2
    exit 1
  fi
  if ! unzip -Z "$linux_zip" Lothal.x86_64 | grep -q '^-rwx'; then
    echo "error: Lothal.x86_64 is not executable inside $linux_zip." >&2
    echo "       Users would double-click it and nothing at all would happen." >&2
    unzip -Z "$linux_zip" Lothal.x86_64 >&2
    exit 1
  fi
  echo "  linux zip: no AppleDouble sidecars, Lothal.x86_64 is executable"
fi

echo "==> hashing"
# Every selected platform, in one pass over the same list that produced the zips. This is the
# whole point of the rewrite: SHA256SUMS.txt cannot name a subset of what was built, because it
# is not written from a separate branch.
(
  cd "$OUT"
  files=()
  for p in $PLATFORMS; do files+=("$(zip_name "$p")"); done
  shasum -a 256 "${files[@]}" > SHA256SUMS.txt
)
sed 's/^/  /' "$OUT/SHA256SUMS.txt"

echo "==> writing manifest"
# The payload is built as a compact single-line JSON string and then signed AS THAT STRING.
# UpdateCheck verifies the signature over the payload text exactly as it arrives, never over a
# re-serialisation of it — key order and float formatting do not survive a round trip through
# two different JSON writers, and a signature that depends on them would verify here and fail
# in the field.
#
# Platforms absent from $PLATFORMS are OMITTED from downloads rather than written with blank
# fields. A present-but-empty entry passes the type checks in parse_manifest and hands the user
# a zero-byte download; an absent key makes parse_manifest return "no build for this platform",
# which offers nothing and is the honest answer.
ENTRIES="$OUT/.entries"
: > "$ENTRIES"
for p in $PLATFORMS; do
  zip=$(zip_name "$p")
  sha=$(awk -v f="$zip" '$2 == f {print $1}' "$OUT/SHA256SUMS.txt")
  size=$(stat -f%z "$OUT/$zip")
  [ -n "$sha" ] || { echo "error: no hash for $zip in SHA256SUMS.txt" >&2; exit 1; }
  printf '%s\t%s\t%s\t%s\n' "$p" "$zip" "$sha" "$size" >> "$ENTRIES"
done

PAYLOAD=$(python3 -c '
import json, sys
version, released, notes, base, entries = sys.argv[1:]
downloads = {}
for line in open(entries):
    if not line.strip():
        continue
    platform, zipname, sha, size = line.rstrip("\n").split("\t")
    downloads[platform] = {
        "url": "%s/v%s/%s" % (base, version, zipname),
        "size": int(size),
        "sha256": sha,
    }
if not downloads:
    sys.exit("refusing to sign a manifest with no downloads")
print(json.dumps({
    "schema": 1,
    "version": version,
    "released": released,
    "min_version": "0.0.0",
    "notes_url": notes,
    "downloads": downloads,
}, separators=(",", ":"), sort_keys=True))
' "$VERSION" "$(date -u +%Y-%m-%d)" "$NOTES_URL" "$BASE_URL" "$ENTRIES")

rm -f "$ENTRIES"

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

# Last gate, and the one that would have caught v0.2.0's incomplete checksum file: the three
# artifacts must describe the same set of platforms. They are produced by the same loop now, so
# this should be unfailable — which is exactly why it is cheap to assert. The failure it guards
# is not a bug in the loop, it is the next person adding a platform to two of the three places.
python3 -c '
import json, sys
out, expected = sys.argv[1], sys.argv[2].split()
doc = json.load(open(out + "/latest.json"))
manifest = set(json.loads(doc["payload"])["downloads"])
sums = {line.split()[1] for line in open(out + "/SHA256SUMS.txt") if line.strip()}
zips = set()
import os
for name in os.listdir(out):
    if name.endswith(".zip"):
        zips.add(name)
if manifest != set(expected):
    sys.exit("manifest lists %s, expected %s" % (sorted(manifest), sorted(expected)))
if sums != zips:
    sys.exit("SHA256SUMS.txt names %s but the directory holds %s" % (sorted(sums), sorted(zips)))
print("  manifest, SHA256SUMS.txt and the zips all describe: %s" % " ".join(sorted(expected)))
' "$OUT" "$PLATFORMS"

echo
echo "packaged: $(pwd)/$OUT"
ls -lh "$OUT" | sed 's/^/  /'
echo
echo "next: release/upload.sh $VERSION --dry-run"
