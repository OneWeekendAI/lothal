# Sourced by build_macos.sh / build_windows.sh. Not executable on its own.
#
#   lothal_pck_prepare <template-file-name>
#
# 1. Resolves the PCK key into GODOT_SCRIPT_ENCRYPTION_KEY — the variable the Godot EDITOR
#    reads at export time (editor/export/editor_export_platform.h). Not to be confused with
#    SCRIPT_AES256_ENCRYPTION_KEY, which is read only by scons when compiling a template.
#    Source order: an already-set env var, then the login Keychain (lothal-pck-key).
# 2. Stages the custom template from $LOTHAL_TEMPLATES into build/templates/, where
#    export_presets.cfg's custom_template/release points.
# 3. Proves the template carries this exact key (release/check_template_key.py).
#
# Every failure is fatal. An encrypted export with a missing or mismatched key does not fail —
# it produces a build that exports cleanly and cannot open its own pack on any machine.

LOTHAL_TEMPLATES="${LOTHAL_TEMPLATES:-$HOME/.lothal/templates/4.7.1.stable}"

lothal_pck_prepare() {
  local name="$1"
  if [ -z "${GODOT_SCRIPT_ENCRYPTION_KEY:-}" ] && command -v security >/dev/null 2>&1; then
    GODOT_SCRIPT_ENCRYPTION_KEY=$(security find-generic-password -a lothal-pck -s lothal-pck-key -w login.keychain 2>/dev/null || true)
  fi
  GODOT_SCRIPT_ENCRYPTION_KEY=$(printf '%s' "${GODOT_SCRIPT_ENCRYPTION_KEY:-}" | tr -d '\n ')
  if ! printf '%s' "$GODOT_SCRIPT_ENCRYPTION_KEY" | grep -Eq '^[0-9a-fA-F]{64}$'; then
    echo "error: no PCK encryption key." >&2
    echo "       Set GODOT_SCRIPT_ENCRYPTION_KEY (64 hex chars) or restore the Keychain entry" >&2
    echo "       'lothal-pck-key' (account lothal-pck). See memory note project_lothal_keys." >&2
    echo "       Exporting without it would ship a build that cannot open its own pack." >&2
    exit 1
  fi
  export GODOT_SCRIPT_ENCRYPTION_KEY

  local src="$LOTHAL_TEMPLATES/$name"
  [ -f "$src" ] || {
    echo "error: encrypted export template missing: $src" >&2
    echo "       Stock templates cannot decrypt the pack. Build it with release/build_templates.sh" >&2
    echo "       (macOS) or take it from the windows-build CI artifact (Windows)." >&2
    exit 1
  }
  mkdir -p build/templates
  cp "$src" "build/templates/$name"
  python3 release/check_template_key.py "build/templates/$name" || {
    echo "error: $src was not compiled with this PCK key — the export would not launch." >&2
    exit 1
  }
  echo "==> exporting with PCK encryption (template: $src)"
}
