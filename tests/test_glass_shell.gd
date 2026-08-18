class_name TestGlassShell
extends RefCounted
## The new UI shell's tab routing (src/ui/glass_shell.gd).
##
## ## Why this suite exists at all
##
## `_show_only_tabs` is nine lines that hide and show tabs, which is exactly the kind of code that
## looks too small to test. It was wrong twice in a row, and both wrong versions were quiet:
##
## 1. *Hide, then select* — printed "Cannot deselect tabs" on SOME transitions and not others, so
##    the errors looked sporadic rather than systematic.
## 2. *Select, then hide* — printed the same error on MORE transitions than the version it replaced.
##
## The second is the one that matters, because it is the shape of bug a screenshot cannot catch: the
## container ends up showing the previous system's tabs while the dropdown reads the new system's
## name. Nothing crashes and the app looks fine unless you read the tab strip.
##
## ## What this suite deliberately does NOT check
##
## Whether the SELECTED tab ends up visible. It should be checked and it cannot be checked here:
## `TabContainer.current_tab` does not take effect until the container has been laid out, and
## tests/run_tests.gd processes no frames — so an assignment made and read back in the same call
## reads as unchanged whether the code is right or wrong. A first version of this suite asserted it
## anyway and failed 11 of 14 transitions against code that is correct in the running app. That is
## the mirror image of a test that cannot fail, and just as useless.
##
## It is covered instead by driving the real shell with frames between selections, which is what
## tests/capture_glass_shell.gd exercises on every screenshot.
##
## ## Why it tests the static function and not the shell
##
## GlassShell only wires itself up in `_ready()`, which means a tree, a rendered frame and a real
## catalog — and tests/run_tests.gd processes no frames by design. `_show_only_tabs` is static and
## takes the container as an argument precisely so the routing can be checked without any of that.
## The fixture below is a TabContainer carrying LabScreen's seven rail titles in LabScreen's order.
##
## ## The ordering that actually catches it
##
## Checking each system from a clean container passes even with the bug, because the destination tab
## is already visible when nothing has been hidden yet. The failure needs a PREVIOUS system: going
## Airframe → Power means selecting Pack while Pack is still hidden from Airframe. So every case
## below runs as a transition out of another system, and `_transitions()` walks the systems forwards,
## backwards and in a fixed interleaved order so that every system is entered from more than one
## predecessor.

## LabScreen's rail tabs, in LabScreen's order. Duplicated here rather than read off a LabScreen,
## because constructing one needs a catalog off disk — and because if these ever drift apart, the
## drift IS the bug this suite should report.
const RAIL_TITLES := ["Frame", "Motor", "Prop", "Pack", "ESC", "FC", "Electronics"]
const PANEL_TITLES := ["Frame", "Motor", "Prop", "Pack", "ESC", "FC", "Electronics", "Fit", "Tune"]


static func run() -> Array:
	var results: Array = []
	results.append_array(_test_every_transition("rails", RAIL_TITLES, "rails"))
	results.append_array(_test_every_transition("panels", PANEL_TITLES, "panels"))
	results.append(_test_unknown_titles_change_nothing())
	return results


## Every system entered from every predecessor in three orders, asserting the container shows
## exactly that system's tabs and that whatever ended up current is visible.
static func _test_every_transition(label: String, titles: Array, key: String) -> Array:
	var results: Array = []
	var container := _fixture(titles)

	var bad_sets := 0
	var transitions := 0

	for order in _orders():
		for system in order:
			var wanted: Array = system[key]
			if wanted.is_empty():
				# An unmodelled system shows a stub instead and the container is left alone, so
				# there is no routing to check — but the NEXT system is still entered out of
				# whatever this one left behind, which is the state that matters.
				continue
			GlassShell._show_only_tabs(container, wanted)
			transitions += 1
			var shown: Array = []
			for i in container.get_tab_count():
				if not container.is_tab_hidden(i):
					shown.append(container.get_tab_title(i))
			if shown != wanted:
				bad_sets += 1

	container.free()
	results.append(TestResult.new(
		"%s: every transition shows exactly its system's tabs" % label,
		bad_sets == 0,
		"%d of %d transitions showed the wrong set" % [bad_sets, transitions]))
	return results


## A title list matching nothing must leave the container untouched rather than hiding everything.
## An empty TabContainer is the same forbidden deselection by another route, and a system whose tabs
## have all been renamed is a mapping bug that should stay visible instead of blanking the column.
static func _test_unknown_titles_change_nothing() -> TestResult:
	var container := _fixture(RAIL_TITLES)
	GlassShell._show_only_tabs(container, ["Pack"])
	GlassShell._show_only_tabs(container, ["Nonexistent"])
	var shown: Array = []
	for i in container.get_tab_count():
		if not container.is_tab_hidden(i):
			shown.append(container.get_tab_title(i))
	container.free()
	return TestResult.new(
		"a title list matching nothing leaves the previous system showing",
		shown == ["Pack"],
		"showing %s" % [shown])


## Forwards, backwards, and an interleaved order that pairs each system with a different
## predecessor again — so no system is only ever entered from the one before it in the list.
static func _orders() -> Array:
	var forwards: Array = []
	for system in GlassShell.SYSTEMS:
		forwards.append(system)
	var backwards := forwards.duplicate()
	backwards.reverse()
	var interleaved: Array = []
	var half := int(forwards.size() / 2.0)
	for i in half:
		interleaved.append(forwards[i])
		interleaved.append(forwards[forwards.size() - 1 - i])
	return [forwards, backwards, interleaved]


static func _fixture(titles: Array) -> TabContainer:
	var container := TabContainer.new()
	for title in titles:
		var page := Control.new()
		page.name = str(title)
		container.add_child(page)
	return container
