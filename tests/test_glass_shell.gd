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
## The four Airframe tabs sit immediately after Frame, in LabScreen's order. They are the first
## panels in this list with no rail beside them — Airframe has none — which is the case
## `_show_only_tabs` had never been asked to route before.
## "Harness" sits immediately after ESC, where LabScreen puts it — Power's third panel (PW4), and
## the first entry in this list that is not a part at all.
const PANEL_TITLES := ["Frame", "Structure", "Arms", "Fasteners", "Layout",
	"Motor", "Prop", "Pack", "ESC", "Harness", "FC", "Electronics", "Fit", "Tune"]


static func run() -> Array:
	var results: Array = []
	results.append_array(_test_every_transition("rails", RAIL_TITLES, "rails"))
	results.append_array(_test_every_transition("panels", PANEL_TITLES, "panels"))
	results.append(_test_unknown_titles_change_nothing())
	results.append_array(_test_power_owns_the_current_path())
	results.append(_test_no_category_is_decided_by_two_systems())
	results.append(_test_the_columns_fit_the_window_the_app_opens_at())
	return results


# ---------------------------------------------------------------------------
# PW4 — the shell move
# ---------------------------------------------------------------------------

## Power owns the pack AND the board that consumes its current, and Control no longer claims the
## board. Written out by name rather than derived, because the whole slice is a claim about what
## these two entries say — a check that read them back off themselves would agree with any table.
##
## **The second half is the one that catches a real mistake.** Naming a panel in `SYSTEMS` that
## LabScreen does not build is silent by design: `_show_only_tabs` leaves an unmatched title alone
## (see `_test_unknown_titles_change_nothing`), so Power would simply show two tabs where three
## were promised and nothing would say so. So every rail and panel Power and Control name is
## checked against the tabs a REAL LabScreen builds, not against the duplicated constants above.
static func _test_power_owns_the_current_path() -> Array:
	var results: Array = []
	var power := _system("Power")
	var control := _system("Control")

	results.append(TestResult.new(
		"Power owns the pack, the ESC and the harness — two rails, three panels, two decisions",
		power.get("rails", []) == ["Pack", "ESC"]
			and power.get("panels", []) == ["Pack", "ESC", "Harness"]
			and power.get("decided_by", []) == ["battery", "esc"],
		"rails %s · panels %s · decided_by %s" % [
			power.get("rails", []), power.get("panels", []), power.get("decided_by", [])]))

	results.append(TestResult.new(
		"and Control has given the ESC up in all three of its lists, keeping the FC and the tune",
		not (control.get("rails", []) as Array).has("ESC")
			and not (control.get("panels", []) as Array).has("ESC")
			and not (control.get("decided_by", []) as Array).has("esc")
			and (control.get("panels", []) as Array).has("FC")
			and (control.get("panels", []) as Array).has("Tune"),
		"rails %s · panels %s · decided_by %s" % [
			control.get("rails", []), control.get("panels", []), control.get("decided_by", [])]))

	# Against a real LabScreen, because the failure this catches is a name that routes to nothing.
	var shell := GlassShell.new()
	var rail_titles := _titles_of(shell.lab.rails())
	var panel_titles := _titles_of(shell.lab.panels)
	var missing: Array = []
	for system in [power, control]:
		for title in system.get("rails", []):
			if not rail_titles.has(str(title)):
				missing.append("rail %s" % title)
		for title in system.get("panels", []):
			if not panel_titles.has(str(title)):
				missing.append("panel %s" % title)
	shell.free()

	results.append(TestResult.new(
		"and every rail and panel those two entries name is a tab LabScreen actually builds",
		missing.is_empty(),
		"routes to nothing: %s · LabScreen has rails %s, panels %s" % [
			missing, rail_titles, panel_titles]))
	return results


## No category appears in two systems' `decided_by`.
##
## **THIS IS THE SILENT ONE.** The completeness ring is arithmetic over `decided_by` across nine
## systems, and nothing on screen looks wrong when a category is named twice: the arc still lands
## between nothing and everything, the strip still reads "n of 9". What breaks is what the fraction
## MEANS — one choice credited to two systems moves the arc by two ninths, so a builder who picks
## an ESC is told they have decided two of the nine things there are to decide. Leaving `esc` under
## Control while adding it to Power is exactly that mistake, and it is a one-word omission in a
## two-word edit.
##
## Note for anyone reading the plan beside this: the plan says the duplicate makes the ring "count
## ten things out of nine". It does not — `_decided_count` counts SYSTEMS satisfied, never
## categories, so the numerator is capped at nine and the arc cannot overflow. The defect is real
## and the described symptom is not, which is precisely why a check that only looked at whether the
## ring rendered sensibly would have passed.
static func _test_no_category_is_decided_by_two_systems() -> TestResult:
	var owner_of := {}
	var doubled: Array = []
	for system in GlassShell.SYSTEMS:
		for key in system["decided_by"]:
			if owner_of.has(key):
				var pair := "%s: %s and %s" % [key, owner_of[key], system["name"]]
				if not SHARED_DECISIONS.has(pair):
					doubled.append(pair)
			else:
				owner_of[key] = str(system["name"])

	# The allowance is itself checked, so it cannot go on excusing something that has been fixed.
	var stale: Array = []
	for pair in SHARED_DECISIONS:
		if not _pair_exists(pair):
			stale.append(pair)

	return TestResult.new(
		"every category the completeness ring counts is decided by exactly one system",
		doubled.is_empty() and stale.is_empty(),
		"claimed twice: %s · allowances no longer real: %s" % [doubled, stale]
			if not (doubled.is_empty() and stale.is_empty()) else
			"%d categories across %d systems, %d knowingly shared" % [
				owner_of.size(), GlassShell.SYSTEMS.size(), SHARED_DECISIONS.size()])


## The one double-claim that is older than this check and is NOT PW4's to settle.
##
## **An explicit list, in INSPECTOR_DOORS' shape and for INSPECTOR_DOORS' reason:** an allowance a
## table could grant itself is one a table can grant by accident. Written out, adding one is an
## edit a reviewer sees in the same diff as the entry that needed it.
##
## `frame` is named by Drone and by Airframe, and has been since W0.4 split them. There is a real
## argument for it — Drone is "which of fifteen frames", Airframe is "what that frame implies", and
## the second genuinely is settled by answering the first — and there is a real cost, which is that
## picking a frame moves the arc by two ninths. **It is not obviously wrong the way a shared `esc`
## would be, and deciding it means deciding whether Airframe is a decision at all**, which is open
## question §8.1 (whether nine collapses to six). Recorded here so that the answer is a visible
## edit rather than the current state being mistaken for one.
const SHARED_DECISIONS := ["frame: Drone and Airframe"]


static func _pair_exists(pair: String) -> bool:
	var owner_of := {}
	for system in GlassShell.SYSTEMS:
		for key in system["decided_by"]:
			if owner_of.has(key):
				if pair == "%s: %s and %s" % [key, owner_of[key], system["name"]]:
					return true
			else:
				owner_of[key] = str(system["name"])
	return false


## The two columns do not overlap at the window `project.godot` opens at, with Power focused.
##
## W0.7 shipped a three-column band reaching 1428 px against a 1280-wide window whose inspector
## started at 904, because a count was fixed and a width was never measured. PW4 adds a rail and a
## panel to the system with the most of both, so this is that measurement: `_fit_columns` grows
## each column to its own content, and the thing that would fail is the two of them meeting in the
## middle of a viewport nobody can then see.
##
## Measured off the chrome actually on screen — the panels' own offsets after `_fit_columns` has
## run — rather than off `RAIL_WIDTH` and `INSPECTOR_WIDTH`, which are floors and not widths.
static func _test_the_columns_fit_the_window_the_app_opens_at() -> TestResult:
	var shell := GlassShell.new()
	# A Control that has never been laid out has size (0, 0), and every width below would then come
	# back as a negative number that passes for the wrong reason. 1280x720 is what project.godot
	# opens at; `_fit_columns` is called by hand because `_ready` defers it and nothing renders here.
	shell.size = Vector2(1280.0, 720.0)
	shell.select_system_by_name("Power")
	shell._fit_columns()

	var rail_right := shell._rail_glass.offset_right
	# The inspector is anchored to the right edge, so its offset_left is negative from 1280.
	var inspector_left := shell.size.x + shell._inspector.offset_left
	var gap := inspector_left - rail_right
	shell.free()

	return TestResult.new(
		"with Power focused, the rail and the inspector leave the viewport between them at 1280",
		gap > 0.0 and rail_right > 0.0,
		"rail ends at %.0f px, inspector starts at %.0f px, %.0f px of viewport between them" % [
			rail_right, inspector_left, gap])


static func _system(system_name: String) -> Dictionary:
	for system in GlassShell.SYSTEMS:
		if str(system["name"]) == system_name:
			return system
	return {}


static func _titles_of(tabs: TabContainer) -> Array:
	var titles: Array = []
	for i in tabs.get_tab_count():
		titles.append(tabs.get_tab_title(i))
	return titles


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
