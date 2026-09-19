class_name TestRoomHost
extends RefCounted
## RoomHost as the single owner of room lifecycle, and GlassShell's Lab/Sim toggle driving it.
##
## ---------------------------------------------------------------------------
## WHY THIS SUITE EXISTS
## ---------------------------------------------------------------------------
##
## The rules it checks were previously enforced by there being exactly ONE shell. That is no longer
## true — two shells now ask for rooms, and the property that matters is that they ask the same
## object rather than each holding a copy. A copy is not a style problem: `_close_rooms()` freeing
## an instance immediately is the only thing standing between a builder and a Powertrain turning
## behind a screen nobody is looking at, and the evidence of that bug is a battery that is wrong
## twenty minutes later.
##
## ---------------------------------------------------------------------------
## THE CHECKS THAT COULD HAVE PASSED WHILE PROVING NOTHING, AND WHAT WAS DONE INSTEAD
## ---------------------------------------------------------------------------
##
## **1. "Every room is freed on the way out."** Two ways this check can be worthless, and both were
## live. Asserting `host.bench == null` after `show_lab()` passes against a `show_bench()` that
## never opened one — so each case asserts the room was NON-null first, and reports the pair
## together. And asserting the FIELD is null passes against a teardown that nulls the reference and
## leaves the node alive, which is the bug itself wearing the fix's clothes. Mutation found that
## one: deleting `frame_bench.free()` while keeping `frame_bench = null` passed. So what is asserted
## is `is_instance_valid()` on the instance captured before leaving.
##
## **2. "AppShell and GlassShell share the lifecycle."** Asserting both have a `rooms` field passes
## against two shells each constructing their own RoomHost, which is precisely the bug. There is no
## shared instance to compare — they are separate windows — so what is asserted instead is that
## NEITHER shell reimplements the mechanism: neither source file contains a `free()` of a room or a
## `persist_pack_charge`, and both delegate. Read off source because the property being checked is
## "this code does not exist", which no runtime call can demonstrate.
##
## **3. "Sim retracts the chrome."** Asserting the rail is hidden in Sim passes against a shell that
## hides it and never puts it back — an app you can fly once and then never choose a part in again.
## So the check flies and RETURNS, and asserts the chrome came back.
##
## **4. And the version of 3 that looks right and is not.** Coming back from Sim must restore the
## system that was chosen when you left, not system zero. A restore written as
## `_select_system(0)` — or as a blind `visible = true` on both columns — passes any check that
## only asks "is the rail back". So the shell is put on **Power** before it flies, and the check
## asserts the Pack rail is what returns. Against `_select_system(0)` this reads "Frame" and fails.
##
## **5. And the unmodelled case, which is where a blind restore actually bites.** Left from
## **Config** — a system with no model, showing stubs and NO rail — a shell that restores by
## unhiding both columns comes back with a Frame rail up under a dropdown reading "Config". So the
## same journey is made out of Config and the check asserts the stub returned and the columns did
## not.


static func run() -> Array:
	var results: Array = []
	results.append_array(_test_every_room_opens_and_is_freed())
	results.append_array(_test_neither_shell_owns_the_lifecycle())
	results.append_array(_test_sim_retracts_the_chrome_and_lab_restores_it())
	results.append_array(_test_returning_lands_on_the_system_you_left())
	results.append_array(_test_the_room_menu_reaches_every_room())
	return results


# ---------------------------------------------------------------------------
# The rooms
# ---------------------------------------------------------------------------

## Every door, opened and left, asserting both halves. The four benches and Sim hold a running
## Powertrain; the field editor and Studio do not, and are here anyway because "freed on the way
## out" is a property of every room rather than of the expensive ones.
static func _test_every_room_opens_and_is_freed() -> Array:
	var results: Array = []
	var host := RoomHost.new()

	# Field name -> the door that opens it. Driven as data so a room added later without a matching
	# entry here is a visible omission rather than a test that quietly covers six of seven.
	var doors := {
		"bench": host.show_bench,
		"battery_bench": host.show_battery_bench,
		"esc_bench": host.show_esc_bench,
		"frame_bench": host.show_frame_bench,
		"field_editor": host.show_field_editor,
		"studio": host.show_studio,
		"sim": host.show_sim,
	}

	for field in doors:
		(doors[field] as Callable).call()
		var room: Object = host.get(field)
		var opened: bool = room != null
		var lab_hidden := not host.showing_lab()
		host.show_lab()
		# **The instance, not the field.** Clearing `frame_bench` to null while leaving the node
		# alive passes any check that only reads the field back — and a bench that is still alive
		# is the exact thing this rule exists to prevent, so the check that only reads the field is
		# a check that cannot fail against the bug it was written for. Caught by mutation: deleting
		# `frame_bench.free()` and keeping `frame_bench = null` passed the first version of this.
		var freed: bool = opened and not is_instance_valid(room)
		var lab_back := host.showing_lab() and host.lab.visible

		results.append(TestResult.new(
			"%s is built on entry and freed on the way out" % field,
			opened and freed and lab_hidden and lab_back,
			"opened=%s, hid Lab=%s, instance freed=%s, Lab back=%s" % [
				opened, lab_hidden, freed, lab_back]))

	# One room at a time, and the assertion is about the OTHERS. Entering a second room without
	# leaving the first is the shape the tab bar allowed and the toggle does not, so the check that
	# matters is that opening any door closes whatever was behind it.
	host.show_bench()
	var left_behind: Object = host.bench
	host.show_sim()
	var only_sim := not is_instance_valid(left_behind) and host.sim != null
	host.show_lab()
	results.append(TestResult.new(
		"entering a room closes whatever was running behind it",
		only_sim,
		"bench freed on the way into Sim: %s" % only_sim))

	# Walking through every room without touching anything must leave nothing to write. Without
	# this the suite would overwrite the packs of whoever runs it with an empty shelf — the same
	# argument TestPackCharge makes, restated because this suite opens every room too.
	results.append(TestResult.new(
		"walking through every room without running anything leaves nothing to save",
		not host.pack_charge.has_unsaved_changes(),
		"has_unsaved_changes = %s after eight room changes" % host.pack_charge.has_unsaved_changes()))

	host.free()
	return results


## Neither shell may contain the mechanism — only the request. See §2 in the header for why this is
## a source check rather than a runtime one.
static func _test_neither_shell_owns_the_lifecycle() -> Array:
	var results: Array = []

	for path in ["res://src/ui/app_shell.gd", "res://src/ui/glass_shell.gd"]:
		var code := TestPidTunes._code_only(FileAccess.get_file_as_string(path))
		# `.free()` on a room, and the write-back that must accompany it. Either appearing in a
		# shell means that shell has started keeping its own opinion about leaving a room.
		var frees_a_room := code.contains("persist_pack_charge") or code.contains("_close_rooms")
		var instantiates_sim := code.contains("SIM_SCENE)") or code.contains("instantiate()")
		results.append(TestResult.new(
			"%s asks for rooms and does not own them" % path.get_file(),
			not frees_a_room and not instantiates_sim,
			"tears down a room=%s, instantiates Sim=%s" % [frees_a_room, instantiates_sim]))

	return results


# ---------------------------------------------------------------------------
# The toggle
# ---------------------------------------------------------------------------

## Out to the field and back, asserting the chrome went away and came back.
##
## The retraction is not decoration: with no part picker on screen there is nothing to change a
## part WITH, so "Sim authors nothing" holds by construction rather than by discipline (§9).
static func _test_sim_retracts_the_chrome_and_lab_restores_it() -> Array:
	var results: Array = []
	var shell := GlassShell.new()

	var lab_chrome := _chrome_of(shell)
	shell.rooms.show_sim()
	var sim_chrome := _chrome_of(shell)
	shell.rooms.show_lab()
	var back_chrome := _chrome_of(shell)

	# THREE clusters, not four, and the rail is deliberately NOT among them (QC5). The garage's
	# default focus is Airframe, whose shelves the finder now opens, so its column is down — a
	# check that still demanded `rail` would be asserting the thing the slice removed.
	#
	# The rail's absence is asserted SEPARATELY rather than dropped. Deleting the term would have
	# left a check that passes whether the column is down because QC5 retired it or up because a
	# regression brought it back, and "the garage shows its clusters" is exactly the check that
	# should notice a column reappearing.
	var all_up: bool = lab_chrome["top"] and lab_chrome["tools"] and lab_chrome["inspector"]
	results.append(TestResult.new(
		"the garage shows its three clusters",
		all_up,
		"top=%s tools=%s inspector=%s" % [lab_chrome["top"], lab_chrome["tools"],
			lab_chrome["inspector"]]))

	results.append(TestResult.new(
		"and the garage does NOT show a parts rail — the finder opens Airframe's shelves",
		not lab_chrome["rail"],
		"rail=%s" % [lab_chrome["rail"]]))

	var all_gone: bool = not sim_chrome["top"] and not sim_chrome["tools"] \
		and not sim_chrome["rail"] and not sim_chrome["inspector"]
	results.append(TestResult.new(
		"the field retracts every cluster — nothing on screen can author a part",
		all_gone,
		"top=%s tools=%s rail=%s inspector=%s" % [sim_chrome["top"], sim_chrome["tools"],
			sim_chrome["rail"], sim_chrome["inspector"]]))

	results.append(TestResult.new(
		"and walking back into the garage puts them back",
		back_chrome == lab_chrome,
		"back: %s" % [back_chrome]))

	# THE WAY BACK MUST DRAW OVER SIM. Sim puts its HUD and its build panel on a CanvasLayer, which
	# covers everything in the ordinary tree — so a toggle built as a plain Control vanishes the
	# instant it takes you to the field, and the app has no way back to the garage short of
	# quitting. That is what happened, and the screenshot is how it was found: `visible` was true
	# the whole time, so nothing above could have caught it.
	var layer := _canvas_layer_over(shell._lab_button)
	results.append(TestResult.new(
		"the way back rides a CanvasLayer above Sim's HUD, or there is no way back",
		layer != null and layer.layer > 1,
		"toggle is on layer %s" % ("none — ordinary tree" if layer == null else str(layer.layer))))

	shell.rooms.show_lab()
	shell.free()
	return results


## One system's rail titles, off GlassShell's own table.
static func _rails_of(system_name: String) -> Array:
	for system in GlassShell.SYSTEMS:
		if str(system["name"]) == system_name:
			return system["rails"]
	return []


## Where a system sits in `GlassShell.SYSTEMS`, by name.
##
## Derived from the same array the shell indexes rather than written out, for `_rails_of`'s reason
## one line up: a hardcoded 2 would keep passing if a system were inserted above Power and would be
## asserting the wrong aircraft. Returns -1 for a name that is not there, which cannot equal a real
## focus index, so a typo in the name fails the check instead of quietly matching nothing.
static func _index_of(system_name: String) -> int:
	for i in GlassShell.SYSTEMS.size():
		if str(GlassShell.SYSTEMS[i]["name"]) == system_name:
			return i
	return -1


## The nearest CanvasLayer above a node, or null if it is in the ordinary tree.
static func _canvas_layer_over(node: Node) -> CanvasLayer:
	var walk := node
	while walk != null:
		if walk is CanvasLayer:
			return walk
		walk = walk.get_parent()
	return null


## The restore lands on the system you left, in both directions that matter: a modelled system whose
## rail must come back holding ITS parts, and an unmodelled one whose rail must not come back at all.
static func _test_returning_lands_on_the_system_you_left() -> Array:
	var results: Array = []
	var shell := GlassShell.new()

	# Power, not Airframe. Airframe is index 0, so leaving from it would pass against a restore
	# hardcoded to zero — the check would agree with the bug.
	shell.select_system_by_name("Power")
	shell.rooms.show_sim()
	shell.rooms.show_lab()
	results.append(TestResult.new(
		"returning from the field lands on the system you left, not the first one",
		# Asserted on the FOCUS, not on the visible rail titles. The original read
		# `_visible_rail_titles(shell) == _rails_of("Power")`, which was the right idea while every
		# system wore its shelves in a column: QC5 made both of Power's shelves finder-reachable, so
		# its column is down and the titles come back `[]` — the check failed for a reason that had
		# nothing to do with what it asserts. The focus index is what "which system came back"
		# actually means, and it survives a shelf moving from the column into the finder.
		shell._focused_index == _index_of("Power"),
		"focus is %d, Power is %d, rail shows %s" % [
			shell._focused_index, _index_of("Power"), _visible_rail_titles(shell)]))

	# Config has no model: stubs, and no rail column at all. A restore that unhides both columns
	# comes back with a Frame rail under a dropdown reading "Config".
	shell.select_system_by_name("Config")
	var stub_before := shell.lab.rails().visible
	shell.rooms.show_sim()
	shell.rooms.show_lab()
	results.append(TestResult.new(
		"and an unmodelled system comes back as a stub, not as somebody else's rail",
		not stub_before and not shell.lab.rails().visible and not shell.lab.panels.visible,
		"rails visible before=%s after=%s" % [stub_before, shell.lab.rails().visible]))

	shell.free()
	return results


## Every room reached from an inspector rather than from the Rooms menu — P10f.
##
## **A LIST, and deliberately not a flag on RoomHost.** The design doc's §7 names the way this
## amendment could land green while a room loses its door: an exemption that a room sets for
## itself is one a room can set by accident, and then it simply vanishes from both the menu and
## this check. An explicit list next to the assertion is an edit a reviewer sees in the same diff
## as the room, which is the whole difference.
##
## Adding to it is therefore a claim, and the claim is checked one assertion down: every id here
## must be a door RoomHost actually has, so a typo or a room that is later deleted fails rather
## than quietly excusing nothing.
const INSPECTOR_DOORS := ["battery_bench", "bench", "esc_bench"]


## The rooms that are neither Lab nor Sim, reached the way a builder reaches them.
##
## **The coverage check is the one that matters.** Asserting that some named ids open some rooms
## passes forever while a new room is added to RoomHost and left with no door — which is precisely
## the failure this shell is exposed to, because the tab bar that used to list every room is gone.
## So RoomHost's own doors are derived rather than typed out — every `show_*` method that is not
## Lab or Sim — and each must be reachable from EITHER the Rooms menu OR an inspector.
##
## P10f moved the thrust stand from the first to the second. That change had to amend this check
## rather than break it: deleting the `bench` entry from `RoomMenu.ENTRIES` while
## `RoomHost.show_bench()` still exists fails the original set equality, and "the menu no longer
## lists Thrust" is the opposite polarity of that assertion — it would have sat beside a failing
## check rather than replacing it. The guarantee is unchanged: no room is left with no door.
static func _test_the_room_menu_reaches_every_room() -> Array:
	var results: Array = []
	var host := RoomHost.new()

	var doors: Array = []
	for method in host.get_method_list():
		var name: String = method["name"]
		if name.begins_with("show_") and name != "show_lab" and name != "show_sim":
			doors.append(name.trim_prefix("show_"))
	doors.sort()
	var reachable: Array = []
	reachable.append_array(RoomMenu.room_ids())
	reachable.append_array(INSPECTOR_DOORS)
	reachable.sort()

	results.append(TestResult.new(
		"every room RoomHost can open has a door — in the Rooms menu or on an inspector — and "
			+ "nothing has a door to a room it cannot open",
		doors == reachable and not doors.is_empty(),
		"RoomHost opens %s · reachable %s (menu %s + inspector %s)" % [
			doors, reachable, RoomMenu.room_ids(), INSPECTOR_DOORS]))

	# The exemption list is itself checked, so it cannot excuse a room that does not exist.
	var stale: Array = []
	for room_id in INSPECTOR_DOORS:
		if not doors.has(room_id):
			stale.append(room_id)
	results.append(TestResult.new(
		"and every inspector-reached room named here is a room RoomHost actually has",
		stale.is_empty(),
		"not doors: %s" % [stale] if not stale.is_empty() else "all of %s" % [INSPECTOR_DOORS]))

	# THE MENU NO LONGER LISTS THRUST, asserted by name rather than left to the set equality
	# above — which a re-addition would satisfy by moving `bench` back into the menu and out of
	# INSPECTOR_DOORS in one edit. This is the assertion that makes putting it back a visible
	# decision.
	results.append(TestResult.new(
		"the Rooms menu no longer lists the thrust stand",
		not RoomMenu.room_ids().has("bench"),
		"menu offers %s" % [RoomMenu.room_ids()]))

	# The same assertion for the ESC bench, which P10f named as the next to move and left in the
	# menu. Written as its own check rather than folded into the one above, because two rooms
	# sharing one assertion means one of them can come back and the check still fails for the
	# other — a failure that names the wrong room is barely better than no failure.
	results.append(TestResult.new(
		"the Rooms menu no longer lists the ESC bench",
		not RoomMenu.room_ids().has("esc_bench"),
		"menu offers %s" % [RoomMenu.room_ids()]))

	# And the pack bench, PW4's move, for the same reason again. Three rooms, three assertions: a
	# failure has to name the bench that came back, and one shared assertion could not.
	results.append(TestResult.new(
		"the Rooms menu no longer lists the pack bench",
		not RoomMenu.room_ids().has("battery_bench"),
		"menu offers %s" % [RoomMenu.room_ids()]))

	host.free()

	# And each id actually lands. A menu that names rooms and opens none is the same missing door
	# wearing a label.
	var shell := GlassShell.new()
	var unreachable: Array = []
	for room_id in RoomMenu.room_ids():
		shell._open_room(room_id)
		if shell.rooms.get(room_id) == null:
			unreachable.append(room_id)
		shell.rooms.show_lab()

	results.append(TestResult.new(
		"and every entry opens the room it names",
		unreachable.is_empty(),
		"did not open: %s" % [unreachable] if not unreachable.is_empty() else
			"all %d opened" % RoomMenu.room_ids().size()))

	# The chrome retracts for a bench exactly as it does for Sim: a rail floating over a thrust
	# stand would be a part picker on a screen where changing a part means nothing.
	# QC4 gave the inspector a second way to be invisible: it now gates on selection, so with
	# nothing selected it is simply absent. `not _inspector.visible` therefore no longer means
	# "retraction happened" on its own — it also holds for a shell whose inspector never appeared
	# at all, which is the one failure this check exists to catch. So the precondition is captured
	# and asserted BEFORE the door opens: the check now states the state it started in, and a
	# shell that stopped showing the inspector fails here instead of sliding through the
	# conclusion.
	var inspector_up_before := shell._inspector.visible
	shell._open_room("frame_bench")
	var retracted := not shell._top_bar.visible and not shell._rail_glass.visible \
		and not shell._inspector.visible and not shell._tools_glass.visible
	shell.rooms.show_lab()
	results.append(TestResult.new(
		"a bench retracts the chrome the same way the field does",
		inspector_up_before and retracted,
		"inspector up beforehand: %s · chrome retracted on the frame bench: %s" % [
			inspector_up_before, retracted]))

	# AND THE INSPECTOR PATH DOES THE SAME — P10f moved this assertion onto the new door, which is
	# where the design doc says it should now live. Driven through the SIGNAL the Motor panel
	# emits rather than by calling `_open_room` again: that would re-assert what the line above
	# already proved and would say nothing about whether the button is connected to anything. The
	# bench must be open afterwards, which is what distinguishes "the chrome went away" from "the
	# signal did nothing and the chrome was already down".
	# Same QC4 precondition as above, and needed independently here: this site opens a different
	# door, so it has to prove for itself that the inspector was up before the signal fired.
	var inspector_up_before_bench := shell._inspector.visible
	shell.lab.motor_details.thrust_bench_requested.emit()
	var bench_open := shell.rooms.bench != null
	var bench_retracted := not shell._top_bar.visible and not shell._rail_glass.visible \
		and not shell._inspector.visible and not shell._tools_glass.visible
	shell.rooms.show_lab()
	results.append(TestResult.new(
		"the thrust stand opens from the Motor inspector, and retracts the chrome identically",
		inspector_up_before_bench and bench_open and bench_retracted,
		"inspector up beforehand=%s opened=%s retracted=%s" % [
			inspector_up_before_bench, bench_open, bench_retracted]))

	# §7.5's "no room is left running" on the new path rather than assumed from the old. Asserted
	# on `is_instance_valid` of the instance captured while it was up: asserting the FIELD is null
	# passes against a teardown that nulls the reference and leaves a Powertrain turning, which is
	# the bug wearing the fix's clothes — the same mutation this suite's header records finding in
	# `frame_bench.free()`.
	shell.lab.motor_details.thrust_bench_requested.emit()
	var bench_instance: Node = shell.rooms.bench
	var was_open := bench_instance != null
	shell.rooms.show_lab()
	results.append(TestResult.new(
		"and the bench opened from the inspector is FREED on the way out, not merely forgotten",
		was_open and not is_instance_valid(bench_instance),
		"was open: %s · still alive: %s" % [was_open, is_instance_valid(bench_instance)]))

	shell.free()
	return results


static func _chrome_of(shell: GlassShell) -> Dictionary:
	return {
		"top": shell._top_bar.visible,
		"tools": shell._tools_glass.visible,
		"rail": shell._rail_glass.visible,
		"inspector": shell._inspector.visible,
	}


static func _visible_rail_titles(shell: GlassShell) -> Array:
	var rails := shell.lab.rails()
	var shown: Array = []
	if not rails.visible:
		return shown
	for i in rails.get_tab_count():
		if not rails.is_tab_hidden(i):
			shown.append(rails.get_tab_title(i))
	return shown
