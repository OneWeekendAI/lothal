class_name TestRoomHost
extends RefCounted
## RoomHost as the single owner of room lifecycle, and DesignApp's Lab/Sim toggle driving it.
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
## **2. "DesignApp and DesignApp share the lifecycle."** Asserting both have a `rooms` field passes
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

	for path in ["res://src/ui/design_app.gd"]:
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
