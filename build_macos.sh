#!/usr/bin/env bash
# Build Lothal.app — a double-clickable macOS bundle (universal: Intel + Apple Silicon).
#
# Prerequisites (checked below):
#   - Godot 4.7.1 on PATH        (brew install --cask godot)
#   - Matching export templates  (~1 GB, installed to
#     ~/Library/Application Support/Godot/export_templates/<version>/)
#
# The bundle carries an AD-HOC signature and no Apple Developer ID.
#
# Ad-hoc is not optional and not cosmetic. Godot's export leaves the template's OWN signature
# on the binary (identifier godot.macos.template_release.arm64, Godot's team id), and swapping
# in Lothal's icon and Info.plist invalidates it — `codesign --verify` reports "code has no
# resources but signature indicates they must be present". On Apple Silicon the kernel refuses
# to run a binary whose signature is broken, and no amount of right-click -> Open or xattr will
# rescue it: the app simply never opens, on every Mac that is not this one. Re-signing ad-hoc
# below replaces that wreckage with a valid signature under Lothal's own identifier.
#
# What ad-hoc does NOT do is satisfy Gatekeeper, which wants a Developer ID. Downloaders still
# need to right-click -> Open once, or run:
#   xattr -dr com.apple.quarantine /Applications/Lothal.app
# The difference is that after ad-hoc signing those instructions actually work.

set -euo pipefail

cd "$(dirname "$0")"

GODOT="${GODOT:-godot}"
VERSION="4.7.1.stable"
TEMPLATE_DIR="$HOME/Library/Application Support/Godot/export_templates/$VERSION"
OUT="build/Lothal.app"

command -v "$GODOT" >/dev/null 2>&1 || {
  echo "error: '$GODOT' not on PATH. Install with: brew install --cask godot" >&2
  exit 1
}

HAVE=$("$GODOT" --version 2>/dev/null | head -1)
[ "$HAVE" != "${HAVE#$VERSION}" ] || {
  echo "error: expected Godot $VERSION, found $HAVE" >&2
  echo "       export templates are version-locked; update VERSION or Godot." >&2
  exit 1
}

[ -f "$TEMPLATE_DIR/macos.zip" ] || {
  echo "error: macOS export template missing at:" >&2
  echo "       $TEMPLATE_DIR/macos.zip" >&2
  echo "       Download Godot_v${VERSION%.stable}-stable_export_templates.tpz from" >&2
  echo "       https://github.com/godotengine/godot/releases and unzip its" >&2
  echo "       templates/ contents into that directory." >&2
  exit 1
}

# Encryption guard. `encrypt_pck=true` against stock export templates produces a build that
# exports without complaint and then cannot decrypt its own pack at startup — it dies on every
# machine, including this one, with no useful error. The key has to be compiled INTO the
# template, so the only safe combination is encryption plus templates from build_templates.sh.
if grep -q '^encrypt_pck=true' export_presets.cfg; then
  [ -f "$TEMPLATE_DIR/.lothal_encrypted" ] || {
    echo "error: encrypt_pck=true but the installed export templates carry no encryption key." >&2
    echo "       This export would produce a build that cannot start." >&2
    echo "       Run ./release/build_templates.sh first, or set encrypt_pck=false." >&2
    exit 1
  }
  SCRIPT_AES256_ENCRYPTION_KEY=$(tr -d '\n ' < "$TEMPLATE_DIR/.lothal_encrypted")
  export SCRIPT_AES256_ENCRYPTION_KEY
  echo "==> exporting with PCK encryption"
fi

# Native core: build the Rust GDExtension universal, BEFORE the suite runs — the suite
# tests the classes the dylib provides, and running it first would test the GDScript
# that is being replaced. The lipo'd universal dylib lands in build/, which the export
# ships inside the .pck (res://build/liblothal_core.dylib).
echo "==> building native core (universal)"
(cd rust && \
  cargo build --release --target aarch64-apple-darwin && \
  cargo build --release --target x86_64-apple-darwin)
lipo -create \
  rust/target/aarch64-apple-darwin/release/liblothal_core.dylib \
  rust/target/x86_64-apple-darwin/release/liblothal_core.dylib \
  -output build/liblothal_core.dylib
[ -f build/liblothal_core.dylib ] || { echo "error: native core build produced no dylib" >&2; exit 1; }

# Regenerate the bundle icon whenever the vector source is newer than the .icns.
if [ ! -f icon.icns ] || [ icon.svg -nt icon.icns ]; then
  echo "==> rendering icon.icns from icon.svg"
  "$GODOT" --headless --script res://tools/render_icon.gd
  iconutil -c icns build/icon.iconset -o icon.icns
fi

# Tests are the gate: never ship a build that cannot pass its own suite.
if [ "${SKIP_TESTS:-0}" != "1" ]; then
  echo "==> running test suite"
  "$GODOT" --headless --script res://tests/run_tests.gd
fi

echo "==> exporting $OUT"
rm -rf "$OUT"
mkdir -p build
# --export-release writes the .app directly because the path ends in .app.
"$GODOT" --headless --export-release "macOS" "$OUT"

[ -d "$OUT" ] || { echo "error: export produced no bundle at $OUT" >&2; exit 1; }

# Godot does not always mark the launcher executable when exporting headless.
BIN="$OUT/Contents/MacOS/Lothal"
[ -f "$BIN" ] && chmod +x "$BIN"

# Replace the export template's stale signature with a valid ad-hoc one. See the header.
echo "==> ad-hoc signing"
codesign --force --deep --sign - "$OUT"

# The gate, not a courtesy: an invalidly signed bundle is the one defect that is invisible on
# the machine that built it and total on every other Mac. Shipping it would mean a release that
# does not start, discovered by users rather than here.
codesign --verify --deep --strict "$OUT" 2>&1 | sed 's/^/  /'
if ! codesign --verify --deep --strict "$OUT" >/dev/null 2>&1; then
  echo "error: bundle signature does not verify — this build would not launch on any other Mac" >&2
  exit 1
fi

echo
echo "built: $(cd build && pwd)/Lothal.app  ($(du -sh "$OUT" | cut -f1))"
lipo -archs "$BIN" 2>/dev/null | sed 's/^/archs: /' || true
codesign -dv "$OUT" 2>&1 | grep -E "^(Identifier|Signature)" | sed 's/^/  /' || true
echo "run:   open $OUT"
