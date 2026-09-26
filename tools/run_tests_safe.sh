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
##   tools/run_tests_safe.sh --layout                      # the shell-layout suite (tools/run_layout_suite.gd)
##
## RULING 71 — `--suite TestShellLayout` USED TO HANG FOR EVER, and it is the spelling everybody
## reaches for. That suite's `run()` takes a `SceneTree` and awaits frames; the generic runner
## calls `run()` with no arguments, which throws inside `_init()` above its own guards and leaves
## the process idling. It is now ROUTED to `tools/run_layout_suite.gd` below, loudly, and
## `tools/run_one_suite.gd` refuses the call on its own account as well, so the raw invocation is
## covered too. A safe wrapper that hangs on a spelling people keep using is not safe.
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

# ---------------------------------------------------------------------------------------------
# THE WATCHDOG (Ruling 71). A run that hangs must FAIL, not sit there.
#
# WHY IT IS HAND-ROLLED AND NOT `timeout`: MEASURED ON THIS MACHINE, 2026-09-24 — `command -v`
# finds NEITHER `timeout` NOR `gtimeout` (no GNU coreutils on the PATH), and `$BASH_VERSION` is
# GNU bash 3.2.57, macOS's system bash, which has NO `wait -n`. So this is written in portable
# bash 3.2: start Godot in the background, poll for its exit in a bounded loop, and on expiry
# terminate it. Do NOT "simplify" this back to `timeout` without re-checking that it is installed.
#
# IT MAY ONLY EVER KILL `$!` — THE ONE CHILD PID THIS SCRIPT ITSELF STARTED. Never a pattern
# match, never `pkill godot`. The reason is on the record: a pattern kill once destroyed the
# builder's real Lothal application data by taking out a Godot process that was not a test run at
# all. A PID we started is ours; anything else belongs to someone else, and is reported, not killed.
#
# THE BOUND. MEASURED 2026-09-24 on this machine: a full green run of `tests/run_tests.gd` through
# this script took 302 s wall (ALL 3166 TESTS PASSED). The bound below is 1200 s — roughly 4x that
# measurement. The headroom is deliberately generous because a loaded machine, a cold shader/import
# cache, or a few hundred more tests must NOT trip this; the watchdog exists to catch the 12-hour
# idle-forever failure mode, not to police a slow afternoon. A single-suite run is far shorter, but
# gets the same bound: there is no measurement justifying a tighter one, and a guessed tight bound
# would turn a slow suite into a spurious failure.
#
# Overridable from the environment ONLY so that the watchdog can be TRIPPED on purpose: a guard
# nobody has fired is a claim, not evidence. `WATCHDOG_SECONDS=20 tools/run_tests_safe.sh ...` is
# how this was proven to fire (see the F12 report). It is not a knob for routine use.
WATCHDOG_SECONDS="${WATCHDOG_SECONDS:-1200}"

run_bounded() {
	local limit="$1"
	shift
	"$@" &
	local child=$!          # OUR child, and the ONLY pid this function is permitted to signal.
	local waited=0
	while kill -0 "$child" 2>/dev/null; do
		if [[ "$waited" -ge "$limit" ]]; then
			echo "" >&2
			echo "[WATCHDOG] TIMED OUT: no exit after ${limit}s (Ruling 71)." >&2
			echo "[WATCHDOG] Terminating pid $child - the child this script started, and nothing else." >&2
			kill -TERM "$child" 2>/dev/null || true
			sleep 5
			if kill -0 "$child" 2>/dev/null; then
				kill -KILL "$child" 2>/dev/null || true
			fi
			wait "$child" 2>/dev/null || true
			echo "[WATCHDOG] If the log ends without a \"reached the end of _init()\" line, the run HUNG rather than being truncated." >&2
			return 124
		fi
		sleep 1
		waited=$((waited + 1))
	done
	local status=0
	wait "$child" || status=$?
	return "$status"
}

mode="full"
target=""
if [[ "${1:-}" == "--layout" ]]; then
	mode="layout"
elif [[ "${1:-}" == "--suite" ]]; then
	if [[ -z "${2:-}" ]]; then
		echo "usage: tools/run_tests_safe.sh --suite <SuiteClass>" >&2
		exit 2
	fi
	target="$2"
	if [[ "$target" == "TestShellLayout" ]]; then
		# RULING 71. Routed, not run: see the note at the top of this file. Said out loud so the
		# next person learns the right spelling rather than silently getting a different runner.
		echo "[ROUTED] TestShellLayout takes a SceneTree and awaits frames, so tools/run_one_suite.gd" >&2
		echo "[ROUTED] cannot call it - that invocation hangs for ever (Ruling 71)." >&2
		echo "[ROUTED] Running tools/run_layout_suite.gd instead. Use --layout directly next time." >&2
		mode="layout"
	else
		mode="suite"
	fi
fi

echo "Relocated HOME: $scratch_home (real ~/Library/Application Support/Godot untouched)"
status=0
case "$mode" in
	layout)
		run_bounded "$WATCHDOG_SECONDS" env HOME="$scratch_home" godot --headless --script res://tools/run_layout_suite.gd || status=$?
		;;
	suite)
		run_bounded "$WATCHDOG_SECONDS" env HOME="$scratch_home" godot --headless --script res://tools/run_one_suite.gd -- "$target" || status=$?
		;;
	*)
		run_bounded "$WATCHDOG_SECONDS" env HOME="$scratch_home" godot --headless --script res://tests/run_tests.gd || status=$?
		;;
esac
exit "$status"
