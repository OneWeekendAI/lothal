#!/usr/bin/env bash
# Build Lothal.app — a double-clickable macOS bundle (universal: Intel + Apple Silicon).
#
# Prerequisites (checked below):
#   - Godot 4.7.1 on PATH        (brew install --cask godot)
#   - Matching export templates  (~1 GB, installed to
#     ~/Library/Application Support/Godot/export_templates/<version>/)
#
# The bundle is UNSIGNED. It runs fine on this Mac. On someone else's Mac
# Gatekeeper will block it until they right-click -> Open, or run:
#   xattr -dr com.apple.quarantine /Applications/Lothal.app
# Signing properly needs an Apple Developer ID.

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

echo
echo "built: $(cd build && pwd)/Lothal.app  ($(du -sh "$OUT" | cut -f1))"
lipo -archs "$BIN" 2>/dev/null | sed 's/^/archs: /' || true
echo "run:   open $OUT"
