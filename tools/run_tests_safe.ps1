# Windows counterpart of tools/run_tests_safe.sh — see that file for the full rationale.
#
# NOT VERIFIED ON WINDOWS. This machine is macOS; there was no way to run a real Windows Godot
# install as part of this task. What follows is Godot's DOCUMENTED default: on Windows, `user://`
# resolves under `%APPDATA%\Godot\app_userdata\<project name>`, the same way it resolves under
# `~/Library/Application Support/Godot/app_userdata/<project name>` on macOS by way of `HOME` — so
# relocating `APPDATA` before launching Godot should relocate `user://` the same way relocating
# `HOME` does on macOS. That parallel has NOT been measured; treat this script as a documented
# guess until someone runs it against a real Windows Godot build and confirms the suite still
# passes and the real AppData files are untouched (the same proof tools/run_tests_safe.sh carries
# for macOS).
#
# USAGE
#   tools\run_tests_safe.ps1                          # full suite
#   tools\run_tests_safe.ps1 -Suite TestSomeSuite      # one suite
#
# The raw invocations keep working unchanged — this script is a safer default, not a lockout.
#
# NOTE from the macOS sibling script (tools/run_tests_safe.sh): a scratch user-data directory
# placed under the OS's per-user temp volume (macOS's $TMPDIR / /var/folders) reproducibly broke
# several suites' file round-trips there, even though it looked like a plain relocation. This
# script places its scratch directory under $env:TEMP, which on Windows is normally already
# inside the user's own profile volume (not a separate volume the way macOS's TMPDIR can be) —
# but that assumption has NOT been verified on a real Windows machine as part of this task. If the
# same class of failure shows up on Windows, the fix is almost certainly the same one: move the
# scratch directory to be a subdirectory of $env:USERPROFILE instead of $env:TEMP.

param(
	[string]$Suite = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ScratchAppData = Join-Path $env:TEMP ("lothal-test-appdata-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $ScratchAppData | Out-Null

try {
	Push-Location $RepoRoot
	Write-Host "Relocated APPDATA: $ScratchAppData (real %APPDATA%\Godot untouched, IF this script's premise holds — unverified)"
	$env:APPDATA = $ScratchAppData
	if ($Suite -ne "") {
		godot --headless --script res://tools/run_one_suite.gd -- $Suite
	} else {
		godot --headless --script res://tests/run_tests.gd
	}
} finally {
	Pop-Location
	Remove-Item -Recurse -Force $ScratchAppData -ErrorAction SilentlyContinue
}
