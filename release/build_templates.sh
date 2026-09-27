#!/usr/bin/env bash
# Build the macOS release export template with the PCK encryption key compiled in.
#
#   ./release/build_templates.sh
#
# This is the one step that makes `encrypt_pck` meaningful, and it is unavoidable: the AES key
# that decrypts the pack has to live inside the executable, so it must be present when the
# executable is COMPILED. Stock templates from the Godot download have no key, which is why
# an encrypted export against them produces a build that exports cleanly and then refuses to
# start on every machine including this one.
#
# Output: $LOTHAL_TEMPLATES/macos.zip (default ~/.lothal/templates/4.7.1.stable/), packaged like
# the official template (macos_template.app/ with Contents/MacOS/godot_macos_release.universal),
# release binary only. build_macos.sh stages it into build/templates/, where the macOS preset's
# custom_template/release points. The Windows template is built by CI
# (.github/workflows/windows.yml) from the GODOT_PCK_KEY secret, not here.
#
# Budget ~1 hour on a 10-core M-series Mac (arm64 + x86_64, then lipo). Needs:
#   brew install scons           and a full Xcode
#   MoltenVK static xcframework  (MoltenVK-macos.tar from github.com/KhronosGroup/MoltenVK
#                                 releases; path in $LOTHAL_MOLTENVK). Homebrew's molten-vk is
#                                 arm64-only and cannot link the x86_64 half.
# ANGLE is not installed, so the template has no ANGLE/OpenGL-over-Metal fallback; Lothal runs
# on Forward+ (Metal on arm64, MoltenVK on x86_64), which does not need it.
#
# The key: login Keychain generic password, account lothal-pck, service lothal-pck-key, with a
# plaintext copy at ~/.lothal/pck_key.txt (0600). A template built with a different key than
# the last release is not an upgrade — it is an app that cannot read its own pack. Never rotate
# it casually, never commit it.
#
# ---------------------------------------------------------------------------
# WHAT THIS BUYS, AND WHAT IT DOES NOT
# ---------------------------------------------------------------------------
#
# It does not make Lothal's source secret. The key is in the binary by necessity (as a plain
# 32-byte array — release/check_template_key.py finds it that way), and the tool that unpacks
# Godot games knows how to go looking for it. What it does is change who can do it: without
# encryption, `gdsdecomp` recovers the whole project in one click. With it, the attacker needs
# to extract the key from the binary first. A speed bump, honestly described.

set -euo pipefail
cd "$(dirname "$0")/.."

GODOT_VERSION="4.7.1-stable"
SRC_DIR="${LOTHAL_GODOT_SRC:-$HOME/src/godot-4.7.1}"
MVK="${LOTHAL_MOLTENVK:-$HOME/src/moltenvk/MoltenVK/MoltenVK/static/MoltenVK.xcframework}"
LOTHAL_TEMPLATES="${LOTHAL_TEMPLATES:-$HOME/.lothal/templates/4.7.1.stable}"

command -v scons >/dev/null 2>&1 || { echo "error: scons not found — brew install scons" >&2; exit 1; }
[ -f "$MVK/macos-arm64_x86_64/libMoltenVK.a" ] || {
  echo "error: universal static MoltenVK not found at $MVK (see header)" >&2; exit 1; }

SCRIPT_AES256_ENCRYPTION_KEY="${GODOT_SCRIPT_ENCRYPTION_KEY:-}"
if [ -z "$SCRIPT_AES256_ENCRYPTION_KEY" ]; then
  SCRIPT_AES256_ENCRYPTION_KEY=$(security find-generic-password -a lothal-pck -s lothal-pck-key -w login.keychain 2>/dev/null || true)
fi
printf '%s' "$SCRIPT_AES256_ENCRYPTION_KEY" | grep -Eq '^[0-9a-fA-F]{64}$' || {
  echo "error: no PCK key (Keychain lothal-pck-key, or GODOT_SCRIPT_ENCRYPTION_KEY)." >&2
  echo "       Generating a new one is a decision, not a fallback — see the header." >&2
  exit 1
}
export SCRIPT_AES256_ENCRYPTION_KEY

if [ ! -d "$SRC_DIR" ]; then
  echo "==> cloning godot $GODOT_VERSION"
  mkdir -p "$(dirname "$SRC_DIR")"
  git clone --depth 1 --branch "$GODOT_VERSION" https://github.com/godotengine/godot.git "$SRC_DIR"
fi

(
  cd "$SRC_DIR"
  echo "==> building macOS templates (this is the slow part)"
  for arch in arm64 x86_64; do
    scons -j"$(sysctl -n hw.ncpu)" platform=macos target=template_release arch=$arch \
      production=yes vulkan_sdk_path="$MVK"
  done
  lipo -create bin/godot.macos.template_release.x86_64 bin/godot.macos.template_release.arm64 \
    -output bin/godot.macos.template_release.universal
)

echo "==> assembling macos.zip"
STAGE="$(mktemp -d)"
cp -R "$SRC_DIR/misc/dist/macos_template.app" "$STAGE/"
mkdir -p "$STAGE/macos_template.app/Contents/MacOS"
cp "$SRC_DIR/bin/godot.macos.template_release.universal" \
  "$STAGE/macos_template.app/Contents/MacOS/godot_macos_release.universal"
chmod +x "$STAGE/macos_template.app/Contents/MacOS/"*
mkdir -p "$LOTHAL_TEMPLATES"
rm -f "$LOTHAL_TEMPLATES/macos.zip"
( cd "$STAGE" && zip -q -r -y "$LOTHAL_TEMPLATES/macos.zip" macos_template.app )
rm -rf "$STAGE"

GODOT_SCRIPT_ENCRYPTION_KEY="$SCRIPT_AES256_ENCRYPTION_KEY" \
  python3 release/check_template_key.py "$LOTHAL_TEMPLATES/macos.zip"

echo
echo "Encrypted macOS template: $LOTHAL_TEMPLATES/macos.zip"
echo "build_macos.sh picks it up from there."
