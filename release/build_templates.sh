#!/usr/bin/env bash
# Build export templates with a PCK encryption key compiled in.
#
#   ./release/build_templates.sh
#
# This is the one step that makes `encrypt_pck` meaningful, and it is unavoidable: the AES key
# that decrypts the pack has to live inside the executable, so it must be present when the
# executable is COMPILED. Stock templates from the Godot download have no key, which is why
# flipping encrypt_pck=true against them produces a build that exports cleanly, ships happily,
# and then refuses to start on every machine including this one.
#
# Budget an hour or two. It compiles Godot from source, twice for macOS (x86_64 and arm64) and
# once for Windows, and it needs scons, a full Xcode install, and the mingw-w64 toolchain:
#
#   brew install scons mingw-w64
#   xcode-select --install
#
# ---------------------------------------------------------------------------
# WHAT THIS BUYS, AND WHAT IT DOES NOT
# ---------------------------------------------------------------------------
#
# It does not make Lothal's source secret. The key is in the binary by necessity, and the tool
# that unpacks Godot games knows how to go looking for it. What it does is change who can do
# it: without encryption, `gdsdecomp` recovers the whole project in one click from a download
# anyone can find. With it, the attacker needs a debugger and the intent to use one. That is a
# speed bump, honestly described — the moat is the physics work and the data, not the text.

set -euo pipefail
cd "$(dirname "$0")/.."

GODOT_VERSION="4.7.1-stable"
SRC_DIR="${LOTHAL_GODOT_SRC:-$HOME/.lothal/godot-src}"
KEY_FILE="${LOTHAL_PCK_KEY:-$HOME/.lothal/pck_key.txt}"
TEMPLATE_DIR="$HOME/Library/Application Support/Godot/export_templates/4.7.1.stable"

command -v scons >/dev/null 2>&1 || { echo "error: scons not found — brew install scons" >&2; exit 1; }

# The key is 64 hex characters: a 256-bit AES key. Generated once and kept with the signing
# key, because a build made with a different key than the last one is not an upgrade — it is a
# different application that cannot read anything the previous one wrote.
if [ ! -f "$KEY_FILE" ]; then
  mkdir -p "$(dirname "$KEY_FILE")"
  openssl rand -hex 32 > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
  echo "==> generated a new PCK key at $KEY_FILE — BACK IT UP with the signing key"
fi

SCRIPT_AES256_ENCRYPTION_KEY=$(tr -d '\n ' < "$KEY_FILE")
export SCRIPT_AES256_ENCRYPTION_KEY

[ ${#SCRIPT_AES256_ENCRYPTION_KEY} -eq 64 ] || {
  echo "error: $KEY_FILE must hold exactly 64 hex characters (a 256-bit key)" >&2
  exit 1
}

if [ ! -d "$SRC_DIR" ]; then
  echo "==> cloning godot $GODOT_VERSION"
  mkdir -p "$(dirname "$SRC_DIR")"
  git clone --depth 1 --branch "$GODOT_VERSION" https://github.com/godotengine/godot.git "$SRC_DIR"
fi

cd "$SRC_DIR"
git fetch --depth 1 origin "$GODOT_VERSION" 2>/dev/null || true
git checkout -q "$GODOT_VERSION"

echo "==> building macOS templates (this is the slow part)"
scons platform=macos target=template_release arch=x86_64 production=yes
scons platform=macos target=template_release arch=arm64 production=yes
lipo -create bin/godot.macos.template_release.x86_64 bin/godot.macos.template_release.arm64 \
  -output bin/godot.macos.template_release.universal

echo "==> building Windows template"
scons platform=windows target=template_release arch=x86_64 production=yes

echo "==> assembling macos.zip"
rm -rf /tmp/lothal_macos_template
mkdir -p /tmp/lothal_macos_template
cp -R misc/dist/macos_template.app /tmp/lothal_macos_template/
mkdir -p /tmp/lothal_macos_template/macos_template.app/Contents/MacOS
cp bin/godot.macos.template_release.universal \
  /tmp/lothal_macos_template/macos_template.app/Contents/MacOS/godot_macos_release.universal
chmod +x /tmp/lothal_macos_template/macos_template.app/Contents/MacOS/*
( cd /tmp/lothal_macos_template && zip -q -r "$TEMPLATE_DIR/macos.zip" macos_template.app )

echo "==> installing Windows template"
cp bin/godot.windows.template_release.x86_64.exe "$TEMPLATE_DIR/windows_release_x86_64.exe"

# A marker the build scripts check for. Its absence is what stops an encrypted export from
# being attempted against stock templates, which is the failure that ships a build nobody can
# launch — silently, because the export itself succeeds.
printf '%s\n' "$SCRIPT_AES256_ENCRYPTION_KEY" > "$TEMPLATE_DIR/.lothal_encrypted"
chmod 600 "$TEMPLATE_DIR/.lothal_encrypted"

echo
echo "Custom encrypted templates installed to:"
echo "  $TEMPLATE_DIR"
echo
echo "Now turn encryption on in export_presets.cfg for BOTH presets:"
echo "  encrypt_pck=true"
echo "  encrypt_directory=true"
echo
echo "Then rebuild. build_macos.sh and build_windows.sh will refuse to export with"
echo "encryption enabled unless these templates are in place."
