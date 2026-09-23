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
## "Link" sits last, where LabScreen adds it — Control's second rail (C3), and the second
## instance of ElectronicsPicker rather than a new class.
const RAIL_TITLES := ["Frame", "Motor", "Prop", "Pack", "ESC", "FC", "Electronics", "Link"]
## The four Airframe tabs sit immediately after Frame, in LabScreen's order. They are the first
## panels in this list with no rail beside them — Airframe has none — which is the case
## `_show_only_tabs` had never been asked to route before.
## "Harness" sits immediately after ESC, where LabScreen puts it — Power's third panel (PW4), and
## the first entry in this list that is not a part at all.
## "Link" sits immediately after "Electronics", where LabScreen puts it — Control's third panel
## (C3), a stub until C6 writes LinkDetails.
## "Camera" sits immediately before "Electronics", where LabScreen puts it so it is Video's front tab — Video's second panel
## (video slice V5), the uptilt.
## "Motors" sits immediately before "Print", where LabScreen puts it — Config's first panel (C3),
## and the first tab of a system that was a stub until this slice.
## "Ports" sits immediately after "Motors", where LabScreen puts it — Config's second panel (C5),
## the serial-port budget and the override field beside it.
## "Failsafe" sits immediately after "Ports", where LabScreen puts it — Config's third panel (C6),
## what happens when the link drops and the three checks predictable from the build.
## "Rates" sits immediately after "Failsafe", where LabScreen puts it — Config's fourth panel (C8),
## the pilot's max rate and expo and the sim-versus-real statement over them.
const PANEL_TITLES := ["Frame", "Structure", "Arms", "Fasteners", "Layout",
	"Motor", "Prop", "Pack", "ESC", "Harness", "FC", "Camera", "Electronics", "Link", "Fit", "Tune",
	"Motors", "Ports", "Failsafe", "Rates", "Sheet", "Print"]


## THE SYSTEMS WHOSE RAILS AND PANELS ARE NOT LABSCREEN'S TABS (F10).
##
## Every check in this file below is about `_show_only_tabs` routing a system's names into Lab's
## two TabContainers. Field's names route nowhere there on purpose: it is a room that brings its
## own rail and its own three panels, and the shell hides Lab's columns for it exactly as it does
## for Airframe. Run through the routing checks unexempted, it reports "mis-routed" for a system
## that is not routed at all.
##
## **AN EXPLICIT LIST, in `INSPECTOR_DOORS`' shape and for its reason:** an exemption a system
## could grant itself is one it can grant by accident, and then a genuine mis-routing goes quiet.
## The claim is checked one assertion down — every system named here must have names that Lab
## really does NOT build, so this cannot excuse a typo in a system that was meant to route.
const SYSTEMS_WITH_THEIR_OWN_TABS := ["Field"]


static func run() -> Array:
	var results: Array = []
	results.append(_test_the_exemption_is_real())
	results.append_array(_test_every_transition("rails", RAIL_TITLES, "rails"))
	results.append_array(_test_every_transition("panels", PANEL_TITLES, "panels"))
	results.append(_test_unknown_titles_change_nothing())
	results.append_array(_test_power_owns_the_current_path())
	results.append(_test_no_category_is_decided_by_two_systems())
	results.append_array(_test_every_rail_routes_to_its_own_panel())
	results.append(_test_the_status_strip_says_how_many_systems_there_are())
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
## **THIS IS THE SILENT ONE.** The completeness ring is arithmetic over `decided_by` across ten
## systems, and nothing on screen looks wrong when a category is named twice: the arc still lands
## between nothing and everything, the strip still reads "n of 10". What breaks is what the fraction
## MEANS — one choice credited to two systems moves the arc by two tenths, so a builder who picks
## an ESC is told they have decided two of the ten things there are to decide. Leaving `esc` under
## Control while adding it to Power is exactly that mistake, and it is a one-word omission in a
## two-word edit.
##
## Note for anyone reading the plan beside this: the plan says the duplicate makes the ring "count
## more things than there are". It does not — `_decided_count` counts SYSTEMS satisfied, never
## categories, so the numerator is capped at ten and the arc cannot overflow. The defect is real
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
## picking a frame moves the arc by two tenths. **It is not obviously wrong the way a shared `esc`
## would be, and deciding it means deciding whether Airframe is a decision at all**, which is open
## question §8.1 (whether ten collapses to six). Recorded here so that the answer is a visible
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
	var shell_width := shell.size.x

	# QC5: THE LEFT-HAND COLUMN IS THE WINDOW EDGE NOW, and asserting that is the point of keeping
	# this check rather than deleting it with the rail. Power's shelves are both reachable through
	# the finder, so its column is down; `_overlay_band`'s left edge is what the viewport starts at,
	# and the gap being measured is the whole of the window between the margin and the inspector.
	var rail_up := shell._rail_glass.visible
	var viewport_left: float = GlassShell.CLUSTER_MARGIN
	# The inspector is anchored to the right edge, so its offset_left is negative from 1280.
	var inspector_left := shell.size.x + shell._inspector.offset_left
	var gap := inspector_left - viewport_left
	shell.free()

	# 731 px is what it MEASURED after the rail came down, against the 403 px left between the two
	# columns before it. Power is the narrowest case on the screen, because its Harness panel makes
	# the inspector 537 px wide — the widest inspector in the app. A floor and not an equality,
	# because the panel is sized to its own content.
	return TestResult.new(
		"with Power focused the rail column is down and the viewport runs from the margin to the inspector",
		not rail_up and gap >= 725.0,
		"rail up %s, the viewport runs %.0f to %.0f px — %.0f px of a %.0f px window" % [
			rail_up, viewport_left, inspector_left, gap, shell_width])


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
			if SYSTEMS_WITH_THEIR_OWN_TABS.has(str(system["name"])):
				continue
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


# ---------------------------------------------------------------------------
# The rail column and the panel column are two different lists
# ---------------------------------------------------------------------------

## Choosing a rail brings up the panel OF THE SAME NAME, for every rail every system owns.
##
## The two columns were synced by index, on a comment claiming "index 4 is still ESC on both
## sides". That stopped being true when Airframe's four panels landed between Frame and Motor:
## seven rails against fourteen panels, so the ESC rail resolved to the Layout panel and the FC
## rail to Motor. Nothing errored, because `TabContainer` refuses a hidden tab — inside Power,
## Layout is hidden, the assignment did not take, and the column simply kept showing whatever was
## there before. A wrong panel that looks like an unchanged one is why this survived two slices.
##
## **The resolution is asserted, not the selection.** `current_tab` does not take effect until the
## container is laid out and the runner processes no frames — this suite's header says so about
## `_show_only_tabs` and it is no less true here — so reading the selection back would agree with
## index wiring and title wiring alike. `panel_for_rail()` returns the index it resolved, and that
## index's TITLE is what is compared, which is the thing index wiring gets wrong.
##
## One result per system rather than one over all of them, so the failure count says how much of
## the shell is mis-routed rather than only that something is.
static func _test_every_rail_routes_to_its_own_panel() -> Array:
	var results: Array = []
	var shell := GlassShell.new()
	var lab := shell.lab
	var rail_titles := _titles_of(lab.rails())

	for system in GlassShell.SYSTEMS:
		if SYSTEMS_WITH_THEIR_OWN_TABS.has(str(system["name"])):
			continue
		var owned: Array = system.get("rails", [])
		if owned.is_empty():
			continue
		var wrong: Array = []
		for title in owned:
			var rail_index := rail_titles.find(str(title))
			var panel_index := lab.panel_for_rail(rail_index)
			var landed := "nothing" if panel_index < 0 \
				else lab.panels.get_tab_title(panel_index)
			if landed != str(title):
				wrong.append("%s (rail %d) -> %s (panel %d)" % [
					title, rail_index, landed, panel_index])
		results.append(TestResult.new(
			"%s: every rail brings up the panel of its own name" % system["name"],
			wrong.is_empty(),
			"rails %s resolve correctly" % [owned] if wrong.is_empty()
				else "mis-routed: %s" % [wrong]))

	# And the rails no system claims are routed too — a rail reachable in the app but named by no
	# SYSTEMS entry would be invisible to every check above.
	var unclaimed: Array = []
	var claimed: Array = []
	for system in GlassShell.SYSTEMS:
		if SYSTEMS_WITH_THEIR_OWN_TABS.has(str(system["name"])):
			continue
		claimed.append_array(system.get("rails", []))
	for title in rail_titles:
		if not claimed.has(title):
			unclaimed.append(title)
	var stray: Array = []
	for title in unclaimed:
		var panel_index := lab.panel_for_rail(rail_titles.find(str(title)))
		if panel_index < 0 or lab.panels.get_tab_title(panel_index) != str(title):
			stray.append(title)
	shell.free()

	results.append(TestResult.new(
		"and every rail LabScreen builds is claimed by a system, or at least routes to its own panel",
		stray.is_empty(),
		"claimed by no system: %s · of those, mis-routed: %s" % [unclaimed, stray]))
	return results


## What the file SAYS about how many systems there are agrees with how many there are.
##
## Ten entries under a comment reading "the nine systems", and a status strip documented as constant
## at "five of nine" while it renders six of ten. Both figures are derived here from `SYSTEMS`
## itself, so this cannot be satisfied by writing today's numbers into the prose — it is satisfied
## by the prose agreeing with the table, whatever the table becomes.
static func _test_the_status_strip_says_how_many_systems_there_are() -> TestResult:
	const WORDS := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
		"nine", "ten", "eleven", "twelve"]
	var decided := 0
	for system in GlassShell.SYSTEMS:
		if not (system["decided_by"] as Array).is_empty():
			decided += 1
	var total_word: String = WORDS[GlassShell.SYSTEMS.size()]
	var decided_word: String = WORDS[decided]

	var source := FileAccess.get_file_as_string("res://src/ui/glass_shell.gd")
	var wanted := [
		"The %s systems of §5" % total_word,
		"starts at %s of %s rather than at zero" % [decided_word, total_word],
		"constant at %s of %s" % [decided_word, total_word],
	]
	var absent: Array = []
	for phrase in wanted:
		if not source.contains(phrase):
			absent.append(phrase)

	return TestResult.new(
		"glass_shell.gd's prose counts the systems the table actually holds",
		absent.is_empty() and not source.is_empty(),
		"%d systems, %d decided; missing from the file: %s" % [
			GlassShell.SYSTEMS.size(), decided, absent])


## The exemption above, checked — so it cannot excuse a system that was supposed to route.
##
## Two ways `SYSTEMS_WITH_THEIR_OWN_TABS` could be wrong and both are asserted: it could name a
## system that does not exist (a typo, or one deleted later), and it could name one whose rails and
## panels ARE Lab's tabs, which would silence the routing checks for a system that genuinely needs
## them. The second is the one that matters — it is how a real mis-routing would go quiet.
static func _test_the_exemption_is_real() -> TestResult:
	var shell := GlassShell.new()
	var rail_titles := _titles_of(shell.lab.rails())
	var panel_titles := _titles_of(shell.lab.panels)
	shell.free()

	var missing: Array = []
	var wrongly_exempt: Array = []
	for name in SYSTEMS_WITH_THEIR_OWN_TABS:
		var system := _system(str(name))
		if system.is_empty():
			missing.append(name)
			continue
		for title in system.get("rails", []):
			if rail_titles.has(str(title)):
				wrongly_exempt.append("rail %s" % title)
		for title in system.get("panels", []):
			if panel_titles.has(str(title)):
				wrongly_exempt.append("panel %s" % title)
	return TestResult.new(
		"every system exempted from the routing checks is real, and really has tabs of its own",
		missing.is_empty() and wrongly_exempt.is_empty()
			and not SYSTEMS_WITH_THEIR_OWN_TABS.is_empty(),
		"no such system: %s · names LabScreen does build after all: %s" % [
			missing, wrongly_exempt])
