extends SceneTree
## Runs ONE suite: godot --headless --script res://tools/run_one_suite.gd -- <SuiteClass>
##
## A development aid, deliberately not in run_tests.gd's SUITES and not a gate: the full runner is
## still what "the tests pass" means. This exists because mutation-testing a single suite — revert,
## break something on purpose, check that the right assertion fires, revert again — is a loop you
## run a dozen times, and the full suite is minutes per turn.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: run_one_suite.gd -- <SuiteClass>")
		quit(2)
		return

	var suite_name := args[0]
	if not ClassDB.class_exists(suite_name) and not _is_global_class(suite_name):
		print("no such registered class: %s" % suite_name)
		quit(2)
		return

	var script: Script = load(_path_of(suite_name))

	# RULING 71. REFUSE A SUITE THIS RUNNER CANNOT CALL, INSTEAD OF HANGING ON IT.
	#
	# `TestShellLayout.run(tree: SceneTree)` (tests/test_shell_layout.gd) takes an argument — it
	# builds a shell in a SubViewport and awaits `process_frame`, because a container has no size
	# until one has been processed. The call below passes none. That arity mismatch throws
	# `Invalid call to function 'run' in base 'GDScript'. Expected 1 argument(s).` from INSIDE
	# `_init()`, which aborts `_init()` on the spot — ABOVE the Ruling 30 and Ruling 27 guards
	# further down this file, so neither of them can catch it — the SceneTree never reaches
	# `quit()`, and the process then idles for ever. Three orphaned Godot processes on the Field
	# room plan came from that, one found at 12h19m elapsed on 36s of CPU, and
	# `tools/run_tests_safe.sh --suite TestShellLayout` hung 100% of the time because it is the
	# obvious spelling for a suite that has its own runner.
	#
	# DETECTED GENERALLY, NOT BY NAME: `Script.get_script_method_list()` carries each method's
	# `args` and `default_args`, so the number of arguments `run()` REQUIRES is readable at
	# runtime and no suite is special-cased here. Verified on this repo 2026-09-24:
	# `TestShellLayout`'s entry reads `args` = one `SceneTree` named `tree`, `default_args` = [].
	#
	# COROUTINE-NESS IS NOT DETECTABLE HERE. Measured three times (F12; F12 review; F12 fix round 1,
	# all 2026-09-24): a zero-argument coroutine's method-list entry is BYTE-IDENTICAL to a plain
	# function's — `flags=33 args=[] default_args=[]`, the same 33 (NORMAL|STATIC) that
	# `TestShellLayout.run` carries — so no amount of reading the method list separates them.
	# It is caught AFTER the call instead; see `_call_run()` and the guard below it.
	var required_args := _required_arg_count(script, "run")
	if required_args < 0:
		print("[REFUSED] suite \"%s\" has no static run() this runner can call" % suite_name)
		quit(2)
		return
	if required_args > 0:
		print("[REFUSED] suite \"%s\" declares run() with %d required argument(s); this runner calls run() with none." % [suite_name, required_args])
		print("Calling it anyway throws a SCRIPT ERROR inside _init(), which aborts before quit() and hangs the process for ever (Ruling 71).")
		if suite_name == "TestShellLayout":
			print("Run it with its own runner instead:")
			print("    HOME=<scratch> godot --headless --script res://tools/run_layout_suite.gd")
			print("  or: tools/run_tests_safe.sh --layout")
		else:
			print("A suite that needs arguments needs its own runner — see tools/run_layout_suite.gd for the pattern.")
		quit(2)
		return

	# THE CALL GOES THROUGH A HELPER, AND THAT IS THE WHOLE FIX. Ruling 71, round 2.
	#
	# This used to read `var results: Array = script.run()`, inline, right here. MEASURED 2026-09-24
	# against a throwaway zero-argument coroutine suite (`tools/_probe_coro_suite.gd`, deleted after
	# the trip), calling it by exactly this path:
	#
	#     SCRIPT ERROR: Trying to call an async function without "await".
	#         [0] _call_it   [1] _init
	#
	# **The CALL aborts. It does not return anything to inspect.** The probe recorded
	# `typeof=0` (nil), `is_Array=false`, and a sentinel set immediately after the call still
	# `false` — so execution never got past `script.run()` itself. That matters because the F12
	# review predicted the opposite: that the call would RETURN a `GDScriptFunctionState`
	# (`typeof=24`) and that a typed `: Array` assignment would then throw
	# `Trying to assign value of type 'Object'…`. On Godot 4.7.1, by this path, it does not get that
	# far — 4.7 refuses the call outright. **The `: Array` annotation was never the thing that made
	# it fatal**, so merely relaxing the annotation to `Variant` would NOT have closed this hole.
	#
	# What DOES close it is where the call happens. A `SCRIPT ERROR` aborts the function it is IN
	# and the caller resumes with that function's return-type default — the property `tests/
	# real_files.gd` is built on, and the same one that makes the arity error above fatal when it is
	# raised directly inside `_init()`. So the call is made inside `_call_run()`: the abort kills the
	# HELPER, `_init()` survives it, gets `null` back, and can refuse LOUDLY instead of idling for
	# ever. The probe confirmed `_init` reached its own end after the abort.
	#
	# This is general, not coroutine-specific: any run() that dies at the call — a coroutine, a
	# parse-time-invisible bad call, anything nobody has thought of — lands in the same refusal.
	var returned: Variant = _call_run(script)

	if not returned is Array:
		print("[REFUSED] suite \"%s\" did not return an Array from run() (got %s)." % [suite_name, type_string(typeof(returned))])
		print("Either run() is a coroutine — Godot 4.7 refuses to call an async function without `await`, and this runner")
		print("cannot await on a suite's behalf, because WHAT to await is per-suite — or it aborted at the call itself.")
		print("A suite that needs frames needs its own runner: see tools/run_layout_suite.gd, which awaits process_frame.")
		print("If you expected this suite to work here, run it directly to see the SCRIPT ERROR above this line.")
		quit(2)
		return

	var results: Array = returned

	# RULING 30. An empty `results` array means `run()` itself aborted before appending anything —
	# for example a `SCRIPT ERROR` in the setup calls between `RealFiles.hold()` and the sections
	# dict (see tests/real_files.gd's "WHAT ACTUALLY RUNS BETWEEN hold() AND THE SECTIONS" section),
	# which is explicitly NOT covered by RealFiles' guarantee. Before this guard, that produced
	# `0/0 failed` — a FALSE GREEN, and a worse failure mode than the hang Ruling 27 fixed: a hang
	# is at least loud. `tests/run_tests.gd` already treats a suite returning nothing as a FAIL for
	# exactly this reason; this matches it.
	if results.is_empty():
		print("[FAIL] suite \"%s\" produced no results (run() aborted before returning, or the class failed to register)" % suite_name)
		print("")
		print("1/1 failed in %s" % suite_name)
		quit(1)
		return

	# RULING 27. A `null` element means a section aborted mid-way and its `results.append(...)`
	# received the aborted function's return-type default rather than a TestResult — see
	# tests/real_files.gd for why that is expected, survivable behaviour and not a crash. Before
	# this guard existed, `result.passed` on that `null` threw its OWN SCRIPT ERROR here, which
	# aborted `_init()` before it reached `quit()` below — the whole process then sat idle forever,
	# reporting nothing, indistinguishable from a stuck test without reading the engine's own log.
	# Reported LOUD and FAILED rather than skipped: a null element is itself the defect a mutation
	# run exists to catch, and silently passing over it would trade a hang for a false green, which
	# is worse than either.
	var failed := 0
	for i in results.size():
		var result = results[i]
		if result == null:
			failed += 1
			print("[FAIL] suite \"%s\" produced a null result at index %d (a section aborted and never appended a TestResult — see tests/real_files.gd)" % [suite_name, i])
			continue
		if not result.passed:
			failed += 1
		print("[%s] %s (%s)" % ["PASS" if result.passed else "FAIL", result.name, result.detail])

	print("")
	print("%d/%d failed in %s" % [failed, results.size(), suite_name])
	quit(1 if failed > 0 else 0)


func _is_global_class(suite_name: String) -> bool:
	return _path_of(suite_name) != ""


func _path_of(suite_name: String) -> String:
	for entry in ProjectSettings.get_global_class_list():
		if str(entry.get("class", "")) == suite_name:
			return str(entry.get("path", ""))
	return ""


## Number of arguments `method_name` REQUIRES on `script` — total args minus those with defaults.
## Returns -1 when the script declares no such method at all. Used by the Ruling 71 guard above.
func _required_arg_count(script: Script, method_name: String) -> int:
	for m in script.get_script_method_list():
		if str(m.get("name", "")) == method_name:
			var args: Array = m.get("args", [])
			var defaults: Array = m.get("default_args", [])
			return maxi(0, args.size() - defaults.size())
	return -1


## Calls `run()` ON PURPOSE FROM A HELPER rather than inline in `_init()`. Ruling 71.
## A GDScript `SCRIPT ERROR` aborts the function it is raised in and lets the CALLER resume with
## this function's return-type default (`null` for Variant) — so an abort at the call site kills
## only this helper, and `_init()` lives to refuse loudly. Inline, the same abort would take
## `_init()` with it, never reach `quit()`, and leave the process idling for ever, which is the
## entire failure mode Ruling 71 exists to kill. Do not inline this call back into `_init()`.
##
## THE ONE CASE THIS DOES NOT COVER, named so the `is Array` refusal upstream is not read as
## belt-and-braces and deleted: a suite whose `run()` AWAITS returns a `GDScriptFunctionState`
## from this call, not its results — perfectly successfully, with no abort anywhere. The helper
## cannot tell that apart from a healthy return, and `await`ing it here would defeat the whole
## point of the helper. So the non-`Array` refusal in `_init()` is what catches it, and it is
## load-bearing rather than defensive. `tests/run_tests.gd` handles the awaiting suite the other
## way — helper returns the state, caller awaits it — because it is the one runner that has to.
func _call_run(script: Script) -> Variant:
	return script.run()
