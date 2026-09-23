class_name TestDock
extends RefCounted
## QC3 — THE DOCK LOST NOTHING.
##
## The slice retires three floating clusters into one, and the failure mode of a consolidation is
## not a crash: it is an action that quietly did not come across. A screenshot cannot show that,
## because a missing button looks exactly like a tidier row. So the whole of this file is one idea
## — every action the three clusters offered, named, one check each.
##
## ## Why the list below is a literal and `Dock.action_names()` is a walk
##
## The two sides have to come from different places or the check is a tautology. The dock's side is
## walked off the live node tree, so deleting a button removes a name; this side is written out by
## hand from what the three retired clusters actually offered, so it does not follow the dock when
## the dock loses something. A single shared constant would have passed a deletion of both halves.
##
## ## One check per action, not a loop over the list
##
## `feedback_loop_tests_hide_coverage`: a looping check fails once and says "1 failure" whether one
## action or eleven went missing, and the name of the failing line is the loop's name rather than
## the action's. Eleven lines is eleven failures and eleven names.
##
## ## What is NOT here
##
## Anything that needs a layout pass — the dock's width, its clearance from the inspector and from
## the overlay tray's band — lives in `tests/test_shell_layout.gd`, which is the one suite in this
## project that waits for frames. A `Container` reports a combined minimum size of (0, 0) until a
## frame has been processed, so a width check written here would have compared 0 against 1256 and
## passed forever.


## What the SYSTEM DROPDOWN offered: ten systems, six of which now have an icon and four of which
## are behind the overflow menu. All ten are named here because all ten were destinations, and a
## slice that kept the six with pictures would have deleted four without saying so.
const SYSTEMS_OFFERED := ["Drone", "Airframe", "Propulsion", "Power", "Control", "Video",
	"Printed", "Config", "Ground kit", "Field"]

## What the BOTTOM-LEFT TOOL CLUSTER offered. `Choose overlays` is the ▾ chooser, which is a
## separate action from the Overlays toggle — one decides whether charts are up and the other
## decides which, and the whole of W0.7 is what happens when the second one does not exist.
## `Status` is the readout: it is not a button, and it is listed for exactly that reason — a
## capability that nothing clicks is the easiest to drop.
##
## `Completeness` — THE RING — USED TO BE ON THIS LIST AND IS DELIBERATELY OFF IT. That is this
## file admitting a capability was dropped, which is the only honest way to drop one here. The ring
## drew an incomplete blue arc with nothing inside it, which is the "in flight" shape and reads as
## WAIT; the `Status` entry directly beside it already says "6 of 10 systems decided" in words,
## with the number. The dock now shows the sentence and not the spinner. Removing the name from
## this literal is what makes `_the_ring_is_adopted_but_not_shown` the only thing asserting where
## the ring went — if it is ever shown again, that check is where it says so.
const TOOLS_OFFERED := ["Overlays", "Choose overlays", "Explode", "X-ray", "Measure", "Status"]

## What the BOTTOM-RIGHT CLUSTER offered: the two modes, and the rooms behind the Rooms menu named
## one by one rather than as "Rooms". A check satisfied by an empty menu button would be the same
## omission one level down.
## `room:field_editor` WAS ON THIS LIST AND HAS BEEN RE-POINTED, not deleted (F10). The field is a
## destination on the dock now — a system icon, not a menu row — so the action is still offered and
## is still named here; it is named as "Field", in SYSTEMS_OFFERED, which is where it now lives.
## `_the_field_moved_from_the_menu_to_the_dock` below is what asserts the move in both directions,
## in the shape `test_room_host.gd` uses for the three benches that made the same journey.
const MODES_OFFERED := ["Lab", "Sim", "room:frame_bench", "room:studio"]

## A stand-in for `GlassShell.SYSTEMS`, carrying only what the dock reads: a name, and whether
## there is a model behind it. Written out rather than imported from `GlassShell`, because building
## a real shell needs a tree, a rendered frame and a catalog — `test_glass_shell.gd` says so about
## itself — and none of that is needed to ask a row of buttons what it offers.
const FIXTURE := [
	{"name": "Drone", "rails": ["Frame"], "panels": ["Frame"]},
	{"name": "Airframe", "rails": [], "panels": ["Arms"]},
	{"name": "Propulsion", "rails": ["Motor"], "panels": ["Motor"]},
	{"name": "Power", "rails": ["Pack"], "panels": ["Pack"]},
	{"name": "Control", "rails": ["FC"], "panels": ["FC"]},
	{"name": "Video", "rails": ["Camera"], "panels": ["Camera"]},
	{"name": "Printed", "rails": [], "panels": ["Printed"]},
	{"name": "Config", "rails": [], "panels": []},
	{"name": "Ground kit", "rails": [], "panels": []},
	# Field is modelled now (F10): `FieldSystem` is its rail and its three panels. The fixture
	# carries that, because whether a system is modelled is what decides its overflow entry reads
	# "soon" — and Field has no overflow entry to read anything any more.
	{"name": "Field", "rails": ["Sites"], "panels": ["Site"]},
]


static func run() -> Array:
	var results: Array = []
	var dock := _fixture_dock()
	var offered := dock.action_names()

	for action in SYSTEMS_OFFERED:
		results.append(_offers(offered, action, "the system dropdown"))
	for action in TOOLS_OFFERED:
		results.append(_offers(offered, action, "the bottom-left tool cluster"))
	for action in MODES_OFFERED:
		results.append(_offers(offered, action, "the bottom-right Lab/Sim/Rooms cluster"))

	results.append(_seven_systems_have_icons(dock))
	results.append(_the_field_moved_from_the_menu_to_the_dock())
	results.append(_the_overflow_menu_selects_the_system_it_names(dock))
	results.append(_a_fallback_label_is_a_named_failure(dock))
	results.append(_measure_is_a_named_failure_too(dock))
	results.append(_the_ring_is_kept_alive(dock))
	results.append(_the_ring_is_not_shown(dock))
	results.append(_a_hidden_control_is_not_an_offered_action(dock))
	dock.free()
	return results


## One action, one line. `source` names the cluster it came from, so a red line says which of the
## three consolidations dropped something rather than only that something is gone.
static func _offers(offered: PackedStringArray, action: String, source: String) -> TestResult:
	return TestResult.new(
		"the dock still offers \"%s\", which %s offered" % [action, source],
		Array(offered).has(action),
		"the dock offers %s" % [Array(offered)])


## Seven icons, and they are the seven `ICONED_SYSTEMS` names. Asserted as a COUNT AND A SET,
## because either alone passes a defect: seven buttons drawn for the wrong seven systems satisfies
## the count, and a set check that only asks "are these seven present" is satisfied by ten.
##
## SIX BECAME SEVEN IN F10 and the number is re-pointed rather than loosened — it stays an equality
## against `ICONED_SYSTEMS.size()`, so an eighth icon appearing without an edit to that list still
## fails.
static func _seven_systems_have_icons(dock: Dock) -> TestResult:
	var named: Array[String] = []
	for button in dock.system_buttons:
		named.append(str(button.name))
	named.sort()
	var want := Dock.ICONED_SYSTEMS.duplicate()
	want.sort()
	return TestResult.new(
		"seven systems carry an icon, and they are the seven ICONED_SYSTEMS names",
		named.size() == 7 and named == want and want.size() == 7,
		"the icons are %s, ICONED_SYSTEMS is %s" % [named, want])


## The overflow menu's popup ids are positions in the POPUP, and the systems it opens are positions
## in `GlassShell.SYSTEMS`. Those two sequences are not the same sequence, and the bug that writes
## itself is `add_item(name, system_index)` — which works by accident for exactly as long as the
## unmodelled systems happen to sit at the start of the list.
##
## Driven through the popup's own signal rather than by reading `_menu_indices`, so the translation
## is exercised on the path a click takes.
static func _the_overflow_menu_selects_the_system_it_names(dock: Dock) -> TestResult:
	var popup := dock.more_menu.get_popup()
	var chosen: Array[int] = []
	dock.system_chosen.connect(func(index: int) -> void: chosen.append(index))
	var names: Array[String] = []
	for index in popup.item_count:
		chosen.clear()
		# THE ITEM'S OWN ID, not its position. Emitting `index` was the first draft and it could not
		# fail: `id_pressed.emit(i)` bypasses the popup, so the handler was always handed 0..3 —
		# exactly the ids a correct menu issues — whatever ids the items actually carried. Under the
		# `add_item(name, system_index)` mutation the items carry 0, 7, 8, 9 and the old loop still
		# fed the handler 0, 1, 2, 3 and got four right answers. Mutation confirmed red only after
		# this line read `get_item_id`.
		popup.id_pressed.emit(popup.get_item_id(index))
		names.append("" if chosen.is_empty() else str(FIXTURE[chosen[0]]["name"]))
	# The three without an icon, in the order they appear in SYSTEMS. Drone is first and is the one
	# the "ids are positions" bug cannot get right: it is index 0 of the popup and index 0 of
	# SYSTEMS, so it passes under the bug and Config and Ground kit do not. Field left this list in
	# F10 — it has an icon — and the list is re-pointed rather than shortened by one without saying
	# so: `_the_field_moved_from_the_menu_to_the_dock` asserts the move.
	return TestResult.new(
		"each overflow entry opens the system it names",
		names == ["Drone", "Config", "Ground kit"],
		"the three entries opened %s" % [names])


## The honest half of "an icon that needs a tooltip has failed": where a glyph could not carry its
## meaning the control carries a WORD, and the word is on the button rather than in a tooltip.
##
## Asserted as a pair — every control named in `ICON_FALLBACK_LABELS` shows text, and every control
## not named in it shows none. The second half is what stops this becoming a licence to label
## everything: quietly adding a word to Propulsion, rather than adding it to the list of admitted
## failures where a reader would find it, goes red here.
static func _a_fallback_label_is_a_named_failure(dock: Dock) -> TestResult:
	var labelled: Array[String] = []
	var wordless: Array[String] = []
	# BOTH GROUPS, because both draw glyphs and both gave some up — two of the three declared
	# failures are tools. A check that walked only the systems would have let a tool be labelled
	# without appearing in the list that is supposed to be the record of every one.
	for group in [dock.systems_group, dock.tools_group]:
		for child in group.get_children():
			if not (child is Dock.DockIcon):
				continue
			if str((child as Button).text) != "":
				labelled.append(str(child.name))
			else:
				wordless.append(str(child.name))
	var want: Array = Dock.ICON_FALLBACK_LABELS.keys()
	want.sort()
	labelled.sort()
	# THE COUNT IS DERIVED FROM THE TWO LISTS THE ICONS ARE BUILT FROM, not from a typed 10. It was
	# `10 - want.size()`, which meant "ten systems minus the labelled ones" and was only ever right
	# while the systems row and the tools row happened to total ten drawn glyphs. F10 added a
	# seventh system icon and the number moved; derived, it moves with the lists, and it still
	# fails the moment an extra word is added, which is what the check is for.
	var drawn_total: int = Dock.ICONED_SYSTEMS.size() + Dock.TOOLS.size()
	return TestResult.new(
		"only the icons named as failures carry a word",
		labelled == want and wordless.size() == drawn_total - want.size(),
		"labelled: %s, declared failures: %s, drawn: %s of %d" % [
			labelled, want, wordless, drawn_total])


## MEASURE CARRIES THE WORD, asserted by name and not only through the pair check above.
##
## `_a_fallback_label_is_a_named_failure` compares the labelled controls against
## `ICON_FALLBACK_LABELS.keys()`, so it stays green if Measure is quietly taken back OUT of that
## dictionary and back to a glyph — both sides move together and the pair agrees with itself. This
## line is the one that does not move: it names the control and the word, so reverting the icon to
## the comb that shipped goes red here. The 18 px crop is the evidence; this is the record of it.
static func _measure_is_a_named_failure_too(dock: Dock) -> TestResult:
	var measure: Button = dock.tools_group.get_node_or_null("Measure") as Button
	return TestResult.new(
		"Measure carries the word \"Measure\", because the ruler glyph read as a text glyph",
		measure != null and measure.text == "Measure"
			and str(Dock.ICON_FALLBACK_LABELS.get("Measure", "")) == "Measure",
		"Measure's text is \"%s\"" % ["<missing>" if measure == null else measure.text])


## THE RING IS STILL PARENTED, which is not a detail. `GlassShell` builds it, keeps a member on it
## and writes `fraction` and `tooltip_text` on every project change; a dock that dropped the node
## instead of hiding it would leak it, and a dock that freed it would leave that member dangling —
## `!= null` is true for a freed object, so the shell's own guard would not catch it. Asserted
## separately from "not shown" so the two failures are two lines: dropped, and shown.
static func _the_ring_is_kept_alive(dock: Dock) -> TestResult:
	var ring := dock.tools_group.get_node_or_null("Completeness")
	return TestResult.new(
		"the completeness ring the shell handed in is still parented, not dropped or freed",
		ring != null and is_instance_valid(ring),
		"tools_group holds %s" % [dock.tools_group.get_children()])


static func _the_ring_is_not_shown(dock: Dock) -> TestResult:
	var ring := dock.tools_group.get_node_or_null("Completeness") as Control
	return TestResult.new(
		"the completeness ring is hidden — the words beside it carry the count",
		ring != null and not ring.visible,
		"the ring is %s" % ["missing" if ring == null else "visible=%s" % ring.visible])


## The ring is hidden, so `action_names()` must not keep naming it. This is the half that catches
## the OTHER way of getting this wrong: hiding the control but leaving the capability list saying
## the dock offers it, which is a list that reports what nobody can see.
static func _a_hidden_control_is_not_an_offered_action(dock: Dock) -> TestResult:
	var offered := Array(dock.action_names())
	return TestResult.new(
		"a hidden control is not reported as an action the dock offers",
		not offered.has("Completeness"),
		"the dock offers %s" % [offered])


static func _fixture_dock() -> Dock:
	var dock := Dock.new(FIXTURE, StyleBoxFlat.new())
	# The ring is the shell's to build — it is an inner class of `GlassShell` — so the dock is
	# handed one, exactly as the shell hands it one. A plain Control stands in: what is being
	# checked is that the dock gives it a home and a name, not what it draws.
	dock.adopt_ring(Control.new())
	return dock


## F10 — THE FIELD IS ON THE DOCK AND IS NO LONGER IN THE ROOMS MENU, both halves by name.
##
## The shape is `test_room_host.gd`'s for the three benches that moved to inspectors: a set check
## alone would be satisfied by putting the entry back in the menu and taking the icon away, because
## the two halves would swap and the totals would agree. So the move is asserted in both
## directions, and the direction it moved IN is asserted against the live list rather than the
## constant — `MODES_OFFERED` above lost the row, and this is what says where it went.
static func _the_field_moved_from_the_menu_to_the_dock() -> TestResult:
	var in_menu := RoomMenu.room_ids().has("field_editor")
	var on_dock := Dock.ICONED_SYSTEMS.has("Field")
	return TestResult.new(
		"the field left the Rooms menu for an icon on the dock, and is in exactly one of the two",
		on_dock and not in_menu,
		"on the dock %s · in the Rooms menu %s (menu offers %s)" % [
			on_dock, in_menu, RoomMenu.room_ids()])
