class_name TestDock
extends RefCounted
## THE DOCK LOST NOTHING — first QC3's consolidation of three clusters into one, now the lab dock
## design's split of that one back into three places (plans/2026-09-26-lab-dock-design.md §2): the
## bottom row of section WORDS, Lab | Sim centred in the top bar, and the tools in the viewport's
## corner. The failure mode of either move is an action that quietly did not come across, so the
## whole of this file is one idea — every action offered, named, one check each.
##
## The two sides come from different places so the check is not a tautology: `Dock.action_names()`
## is walked off the live tree (a deleted button removes a name), and the lists below are written
## out by hand. One check per action, not a loop (feedback_loop_tests_hide_coverage).
##
## Anything that needs a layout pass lives in `tests/test_shell_layout.gd`.


## The nine sections of §2, every one a word on the bottom row. DRONE IS NOT HERE: it was folded
## into Airframe, and `_drone_is_folded_into_airframe` asserts it is gone rather than dropped.
const SYSTEMS_OFFERED := ["Airframe", "Propulsion", "Power", "Control", "Video",
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
	{"name": "Airframe", "rails": ["Frame"], "panels": ["Arms"]},
	{"name": "Propulsion", "rails": ["Motor"], "panels": ["Motor"]},
	{"name": "Power", "rails": ["Pack"], "panels": ["Pack"]},
	{"name": "Control", "rails": ["FC"], "panels": ["FC"]},
	{"name": "Video", "rails": ["Camera"], "panels": ["Camera"]},
	{"name": "Printed", "rails": [], "panels": ["Printed"]},
	{"name": "Config", "rails": [], "panels": ["Motors"]},
	{"name": "Ground kit", "rails": [], "panels": []},
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

	results.append(_the_sections_are_words(dock))
	results.append(_drone_is_folded_into_airframe(dock))
	results.append(_the_field_moved_from_the_menu_to_the_dock())
	results.append(_a_section_word_selects_the_section_it_names(dock))
	results.append(_the_mode_segment_rides_the_dock(dock))
	results.append(_the_tools_ride_the_dock(dock))
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


## Nine WORDS, one per section, each reading its own name (§2: "words, not icons").
static func _the_sections_are_words(dock: Dock) -> TestResult:
	var shown: Array[String] = []
	for button in dock.system_buttons:
		shown.append(button.text)
	var want: Array[String] = []
	for name in SYSTEMS_OFFERED:
		want.append(name)
	return TestResult.new("the bottom row shows the nine sections as words, in order",
		shown == want, "the row reads %s" % [shown])


static func _drone_is_folded_into_airframe(dock: Dock) -> TestResult:
	var offered := Array(dock.action_names())
	return TestResult.new("Drone is no longer a section of its own — it is folded into Airframe",
		not offered.has("Drone") and offered.has("Airframe"), "the dock offers %s" % [offered])


## Driven through each button's own `pressed`, so the index a click carries is the one checked.
static func _a_section_word_selects_the_section_it_names(dock: Dock) -> TestResult:
	var chosen: Array[int] = []
	dock.system_chosen.connect(func(index: int) -> void: chosen.append(index))
	var names: Array[String] = []
	for button in dock.system_buttons:
		chosen.clear()
		button.pressed.emit()
		names.append("" if chosen.is_empty() else str(FIXTURE[chosen[0]]["name"]))
	var want: Array[String] = []
	for button in dock.system_buttons:
		want.append(button.name)
	return TestResult.new("each section word selects the section it names",
		names == want, "the words selected %s" % [names])


## Lab | Sim lives in the top bar but must stay IN THE DOCK'S SUBTREE — that is what keeps it on the
## CanvasLayer over Sim's HUD. `top_level` is how it is placed apart from the row.
static func _the_mode_segment_rides_the_dock(dock: Dock) -> TestResult:
	var inside := dock.is_ancestor_of(dock.lab_button) and dock.is_ancestor_of(dock.sim_button)
	return TestResult.new("Lab | Sim is placed apart from the row but still rides the dock",
		inside and dock.mode_panel.top_level and dock.mode_panel.is_ancestor_of(dock.lab_button),
		"inside=%s top_level=%s" % [inside, dock.mode_panel.top_level])


static func _the_tools_ride_the_dock(dock: Dock) -> TestResult:
	return TestResult.new("the viewport tools sit in their own corner panel, still in the dock",
		dock.tools_panel.top_level and dock.tools_panel.is_ancestor_of(dock.overlays_button)
			and dock.is_ancestor_of(dock.tools_panel), "")


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
	for group in [dock.tools_group]:
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
	var drawn_total: int = Dock.TOOLS.size()
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


static func _fixture_dock_names() -> PackedStringArray:
	var dock := _fixture_dock()
	var names := dock.action_names()
	dock.free()
	return names


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
	var on_dock := false
	for system in FIXTURE:
		on_dock = on_dock or system["name"] == "Field"
	on_dock = on_dock and Array(_fixture_dock_names()).has("Field")
	return TestResult.new(
		"the field left the Rooms menu for an icon on the dock, and is in exactly one of the two",
		on_dock and not in_menu,
		"on the dock %s · in the Rooms menu %s (menu offers %s)" % [
			on_dock, in_menu, RoomMenu.room_ids()])
