#!/usr/bin/env bash
# Build Lothal.exe — the Windows x86_64 build, cross-exported from this Mac.
#
# Godot exports Windows from any host; the only Windows-native step is rcedit, which stamps the
# icon and version metadata into the .exe, and that runs under wine. Without rcedit the export
# still succeeds and still runs — it just carries Godot's default icon and blank file
# properties, which on a download people are already being asked to trust is not a small thing.
#
# The .exe is UNSIGNED. SmartScreen will show "Windows protected your PC" until the release has
# accumulated enough downloads for Microsoft's reputation system, or until there is an EV code
# signing certificate. Users get past it with More info -> Run anyway. Say so on the download
# page rather than letting them discover it.

set -euo pipefail

cd "$(dirname "$0")"

GODOT="${GODOT:-godot}"
VERSION="4.7.1.stable"
TEMPLATE_DIR="$HOME/Library/Application Support/Godot/export_templates/$VERSION"
OUT="build/windows/Lothal.exe"

command -v "$GODOT" >/dev/null 2>&1 || {
  echo "error: '$GODOT' not on PATH. Install with: brew install --cask godot" >&2
  exit 1
}

HAVE=$("$GODOT" --version 2>/dev/null | head -1)
[ "$HAVE" != "${HAVE#$VERSION}" ] || {
  echo "error: expected Godot $VERSION, found $HAVE" >&2
  exit 1
}

[ -f "$TEMPLATE_DIR/windows_release_x86_64.exe" ] || {
  echo "error: Windows export template missing at:" >&2
  echo "       $TEMPLATE_DIR/windows_release_x86_64.exe" >&2
  exit 1
}

# rcedit is a single Windows binary run through wine. Its absence is a warning rather than an
# error so a build can still be produced in a hurry, but the warning is loud because shipping
# an unsigned .exe that ALSO carries a stranger's icon and no publisher string is the version of
# this download that looks most like malware.
RCEDIT="${RCEDIT:-$HOME/.lothal/rcedit-x64.exe}"
if [ ! -f "$RCEDIT" ]; then
  echo "warning: rcedit not found at $RCEDIT" >&2
  echo "         The .exe will carry Godot's default icon and no version metadata." >&2
  echo "         Fix: download rcedit-x64.exe from" >&2
  echo "         https://github.com/electron/rcedit/releases into $HOME/.lothal/" >&2
  echo "         and set it in Godot: Editor Settings -> Export -> Windows -> rcedit." >&2
fi

if [ "${SKIP_TESTS:-0}" != "1" ]; then
  echo "==> running test suite"
  "$GODOT" --headless --script res://tests/run_tests.gd
fi

echo "==> exporting $OUT"
rm -rf build/windows
mkdir -p build/windows
"$GODOT" --headless --export-release "Windows Desktop" "$OUT"

[ -f "$OUT" ] || { echo "error: export produced no executable at $OUT" >&2; exit 1; }

# The .pck sits beside the .exe unless embedded. Both must travel together in the zip; an .exe
# shipped alone starts and then dies with an unhelpful error about a missing main scene.
echo
echo "built: $(cd build/windows && pwd)"
ls -lh build/windows | sed 's/^/  /'
