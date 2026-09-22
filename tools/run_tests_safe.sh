#!/usr/bin/env bash
## Runs the GDScript test suite(s) with `user://` relocated to a throwaway directory, so a test
## run can never read or write the developer's real Lothal application data at
## `~/Library/Application Support/Godot/app_userdata/Lothal` (macOS) or the Linux equivalent under
## `~/.local/share/godot/app_userdata/Lothal`.
##
## WHY THIS EXISTS: `RoomHost.new()` and several suites (see tests/real_files.gd) read and write
## real `user://` paths — `sites.json`, `courses.json`, `conditions.json`, `assembly_tweaks.json`,
## `custom_parts.json`, `app_settings.json` — on purpose, to prove the SHIPPED defaults are wired
## up correctly. `RealFiles` (tests/real_files.gd) puts those files back after every suite that
## touches them, but it cannot survive the engine process itself dying mid-run (a segfault, an OOM
## kill, `--quit`/^C between the hold and the release). This script closes that gap a different
## way: `user://` on desktop platforms is derived from the OS's per-user data-home variable
## (`HOME` on macOS/Linux, by way of `~/Library/Application Support` / XDG data dirs), so pointing
## that variable at an empty scratch directory before Godot starts makes the ENTIRE run operate on
## a directory that was never the developer's, in the first place — no restore needed, and no way
## for a killed process to leave anything behind on the real path.
##
## Measured on this repo (task F4b, 2026-09): `HOME=<scratch> godot --headless --script
## res://tests/run_tests.gd` relocates the whole user dir to
## `<scratch>/Library/Application Support/Godot/app_userdata/Lothal`, the suite passes at the same
## count it does normally, and the developer's real files are untouched. Godot 4.7 has no
## `--user-data-dir` flag and ignores `XDG_DATA_HOME` on macOS.
##
## THE SCRATCH DIRECTORY IS CREATED UNDER $HOME, NOT UNDER $TMPDIR — BUT READ THIS BEFORE TRUSTING
## IT AS A MEASURED CONSTRAINT, because that is not what it currently is. On one run, on this
## machine, a scratch dir under macOS's per-user `$TMPDIR` (`/var/folders/...`, what `mktemp -d`
## uses by default) produced 37 reproducible-looking failures across TestStudio, project
## save/round-trip, and printed-export/divergence and custom-parts suites — writes that reported
## success but whose data did not come back (`recorder.save()` "succeeded" but the file listed 0
## rows, a `.lothal` container wrote but reopened empty). Full output from that run is kept
## (gitignored, not part of the shipped repo) at
## .superpowers/sdd/2026-09-21-field-room-plan/task-F4b-tmpfolders-observed-failure.log
## (37 `[FAIL]` lines, task F4b, 2026-09-22).
##
## A LATER ATTEMPT, ON THE SAME MACHINE, COULD NOT REPRODUCE IT: two fresh runs against a fresh
## `/var/folders`-rooted scratch dir both came back `ALL 2805 TESTS PASSED`, zero `[FAIL]`
## (F4b review round 1, 2026-09). So this is an observation made once, not a proven property of
## `/var/folders` — it may have been transient: a stale `.import`/shader cache from an earlier run
## on the same volume, disk pressure, a concurrent process, some other one-off condition on that
## machine at that moment. The cause was never found either way, before or after the failure
## disappeared.
##
## The workaround stays anyway, because it costs nothing and is free insurance either way: if the
## failure IS real but merely intermittent, this avoids it; if it was never real, creating the
## scratch dir under `$HOME` instead of `$TMPDIR` has no downside worth naming. Don't read the
## comment above as license to delete this on the grounds that "it didn't reproduce" — it also
## didn't cost anything to keep. If you get a clean reproduction (of the failure recurring, or of
## it never being real) either way, update this comment with what you found.
##
## USAGE
##   tools/run_tests_safe.sh                              # full suite (tests/run_tests.gd)
##   tools/run_tests_safe.sh --suite TestSomeSuite         # one suite (tools/run_one_suite.gd)
##
## The raw invocations (`godot --headless --script res://tests/run_tests.gd`, `... run_one_suite.gd
## -- <SuiteClass>`) keep working unchanged — this script is a safer default, not a lockout.
##
## WINDOWS: not implemented here and not verified on this machine (macOS). Godot's documented
## default `user://` location on Windows is `%APPDATA%\Godot\app_userdata\Lothal`, so the Windows
## analogue would be relocating `APPDATA` the same way this script relocates `HOME` — see
## tools/run_tests_safe.ps1, which does that, but it has NOT been run against a real Windows Godot
## install as part of this task. Treat it as a documented guess, not a proven fact, until someone
## verifies it on Windows.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Under the real $HOME's own volume, deliberately NOT under $TMPDIR/mktemp's default — see the
# note above the top of this file for why /var/folders (macOS's per-user TMPDIR) is unsafe here.
scratch_home="${HOME}/.lothal-test-home.$$.$RANDOM"
mkdir -p "$scratch_home"
cleanup() {
	rm -rf "$scratch_home"
}
trap cleanup EXIT

cd "$REPO_ROOT"

if [[ "${1:-}" == "--suite" ]]; then
	if [[ -z "${2:-}" ]]; then
		echo "usage: tools/run_tests_safe.sh --suite <SuiteClass>" >&2
		exit 2
	fi
	suite_class="$2"
	echo "Relocated HOME: $scratch_home (real ~/Library/Application Support/Godot untouched)"
	HOME="$scratch_home" godot --headless --script res://tools/run_one_suite.gd -- "$suite_class"
else
	echo "Relocated HOME: $scratch_home (real ~/Library/Application Support/Godot untouched)"
	HOME="$scratch_home" godot --headless --script res://tests/run_tests.gd
fi
