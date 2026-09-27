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
#
# The macOS preset is encrypted unconditionally now, so this always runs: key from env or
# Keychain into GODOT_SCRIPT_ENCRYPTION_KEY, custom template staged into build/templates/, and
# the template proven to carry that key. Any gap exits here, loudly. See release/pck_key.sh.
. release/pck_key.sh
lothal_pck_prepare macos.zip

# Native core: build the Rust GDExtension universal, BEFORE the suite runs — the suite
# tests the classes the dylib provides, and running it first would test the GDScript
# that is being replaced. The lipo'd universal dylib lands in build/, which the export
# ships inside the .pck (res://build/liblothal_core.dylib).
echo "==> building native core (universal)"
# Strip build-machine paths out of the binary. Panic messages embed the source path of the
# panicking file, so without this the shipped dylib carries /Users/<name>/.cargo/registry/...
# and the repo's absolute path. RUSTFLAGS (not rust/.cargo/config.toml) because the prefixes
# are per-machine and config.toml cannot expand $HOME. Keep in sync with windows.yml.
RUST_SYSROOT="$(cd rust && rustc --print sysroot)"
export RUSTFLAGS="${RUSTFLAGS:-} --remap-path-prefix=$HOME/.cargo=/cargo --remap-path-prefix=${RUSTUP_HOME:-$HOME/.rustup}=/rustup --remap-path-prefix=$RUST_SYSROOT=/rustc-sysroot --remap-path-prefix=$PWD=/lothal"
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
  # Gated on the runner's own sentinel, not the exit code: Godot exits 0 on a parse error.
  SUITE_OUT="$("$GODOT" --headless --script res://tests/run_tests.gd 2>&1)" || true
  printf '%s\n' "$SUITE_OUT" | grep -E '^\[FAIL\]' || true
  printf '%s\n' "$SUITE_OUT" | tail -n 3
  printf '%s\n' "$SUITE_OUT" | grep -Eq '^ALL [0-9]+ TESTS PASSED' || {
    echo "error: test suite did not report \"ALL n TESTS PASSED\"" >&2
    exit 1
  }

  # The golden cross-checks compare the Rust crate against the GDScript it replaced. The
  # unit suite CANNOT stand in for them: a 1% error in plausibility.rs's log_log_fit passes
  # all 911 tests and is caught only here. They are not in run_tests.gd's SUITES because a
  # full catalog sweep costs seconds rather than milliseconds, so the build is where they run.
  #
  # Both are gated on their success SENTINEL, not on the exit code, because
  # `godot --headless --script` exits 0 on a parse error — measured, not assumed. An
  # exit-code-only gate would wave through a cross-check that failed to compile, which is
  # precisely how tests/rust_crosscheck.gd spent its life reporting success for work it
  # never did.
  run_crosscheck() {
    local label="$1" script="$2" sentinel="$3" out
    echo "==> $label"
    out="$("$GODOT" --headless --script "$script" 2>&1)" || true
    printf '%s\n' "$out" | tail -n 4
    if ! printf '%s\n' "$out" | grep -q "$sentinel"; then
      echo "error: $label did not report \"$sentinel\" — the Rust core disagrees with its" >&2
      echo "       GDScript reference, or the cross-check itself failed to run." >&2
      exit 1
    fi
  }
  run_crosscheck "tier 1 cross-check (sim core)" \
    res://tools/crosscheck/run_crosscheck.gd "RUST CROSSCHECK OK"
  run_crosscheck "tier 2 cross-check (fitting pipeline)" \
    res://tests/rust_crosscheck_tier2.gd "TIER2 CROSSCHECK OK"
else
  echo "WARNING: SKIP_TESTS=1 — suite AND both golden cross-checks skipped." >&2
  echo "         Nothing has verified the Rust core against its GDScript reference." >&2
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
