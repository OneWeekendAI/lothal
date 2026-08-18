class_name RoomHost
extends Control
## The rooms, and the rules for entering and leaving them (labs-and-sim.md §1).
##
## This holds everything that used to live in `AppShell` except the tab bar itself: Lab, the four
## benches, the field editor, Studio, Sim, and the two stores every room touches. A shell decides
## how the builder ASKS for a room — eight tabs, or a dropdown and a Lab/Sim toggle — and this
## decides what actually happens when they do.
##
## **Extracted so there is exactly one owner of "no room is left running".** The rule is not
## expressible as a convention: it is `_close_rooms()` freeing an instance immediately, and every
## room that could have drained a pack writing its consequence back on the way out. Two shells each
## with their own copy would be two things that could leave a Powertrain turning behind a screen
## nobody is looking at, and the only evidence would be a battery that was wrong later. So the new
## shell does not reimplement any of this — it embeds one of these.
##
## The important behaviour, unchanged from where it was written:
##
## **Sim does not exist while you are in Lab.** It is instantiated when entered and FREED when
## left — not hidden, not paused. A paused node still holds a chase camera, a DroneAudio bus and a
## HUD CanvasLayer, and a flag saying it is idle is something that can rot. A freed instance cannot.
##
## **Lab persists.** It is cheap — no integrator lives in it — and the frame you chose should still
## be chosen when you walk back from the field. This is labs-and-sim.md §4's boundary: the build
## crosses from Lab to Sim, and nothing crosses back except consequences.
##
## Consequence worth naming: because Sim is rebuilt on entry, a lap in progress does not survive a
## trip to the garage. That is the intended reading — you landed and walked away.

const SIM_SCENE := "res://src/scenes/main.tscn"

var lab: LabScreen
## The flight simulation, or null whenever Lab is showing. Null IS the assertion — see above.
var sim: Node = null
## The thrust stand, or null whenever it is not the room you are in. Same argument as `sim`
## and for the same reason: a bench holds a running Powertrain and a live audio bus, so "it
## costs nothing while you are choosing parts" has to be an absence rather than a paused flag.
##
## It is a room rather than a panel inside Lab deliberately. labs-and-sim.md §2.1 puts the
## component benches inside Labs, and they are — but Lab's stated virtue is that it is quiet
## and cheap while you work, and a bench is the one part of the garage that runs a physics
## loop and makes noise. Putting it behind its own door keeps that promise literally true
## instead of nearly true.
var bench: BenchScreen = null
## The battery bench — a load test rather than a stand — or null when it is not the room you are
## in. Same argument as `bench` and `sim`: it holds a running Powertrain draining a real pack, and
## a pack that kept emptying while you were next door choosing propellers would be the worst kind
## of bug, since the only evidence would be a number that was wrong later.
var battery_bench: BatteryBenchScreen = null
## The ESC bench — a board swept against the motors chosen — or null when it is not the room you
## are in. Same argument as the other two: it holds a running Powertrain drawing real current out
## of a real pack, and a sweep left running behind Lab would be flattening a battery to answer a
## question nobody was still asking.
var esc_bench: EscBenchScreen = null
## The frame bench — the assembled aircraft stepped about one axis — or null when it is not the room
## you are in. Same argument as the other three: it holds a running Powertrain turning four motors
## at four different throttles out of a real pack, and a step response left running behind Lab would
## be flattening a battery to answer a question nobody was still asking.
var frame_bench: FrameBenchScreen = null
## The field editor — where the course is laid out — or null when it is not the room you are in.
## Freed on the way out like the others, but for a different reason: it holds no powertrain and
## costs no charge (laying out gates turns no motors, labs-and-sim.md §5). What it does hold is a
## SubViewport rendering a 3D world, and Lab's stated virtue is that it is quiet and cheap while
## you work.
var field_editor: FieldEditorScreen = null
## Studio — the flights already flown — or null when it is not the room you are in. Freed on the
## way out like the others, and for the field editor's reason rather than the benches': it turns
## no motors and costs no charge. What it holds is a list of headers read off disk, which goes
## stale the moment a flight is recorded next door, so a Studio kept alive behind Sim would be a
## room describing a history that had moved on. Rebuilding on entry re-reads the directory.
var studio: StudioScreen = null
## The courses that have been laid out, and which one is flown. Held here for the same reason
## `pack_charge` is: two rooms touch it — the editor writes it and the field reads it — and one
## instance within a session is what stops the door from handing over a stale copy.
var course_library := CourseLibrary.load_from()
## How much charge is in each pack right now. Loaded once on startup and held here rather than in
## any one room, because it is the one piece of state every room touches: two benches and the
## field all drain it, and Lab is where it gets charged back up. It is saved whenever a room that
## could have changed it is closed.
var pack_charge: PackCharge

## How much of the top of the screen the SHELL has already covered — the old tab bar's height, or
## zero for a shell whose chrome floats. Lab and every Control room are inset below it; Sim is told
## about it rather than inset, because it is a Node3D scene that owns the whole window and draws its
## own panel underneath.
##
## A property rather than a constant because it is the one thing about the rooms that genuinely
## differs between the two shells, and the alternative — each shell laying out the rooms itself —
## is how the lifecycle rules would end up duplicated again by a slower route.
var top_inset := 0.0:
	set(value):
		top_inset = value
		if _host != null:
			_host.offset_top = value
		if sim != null:
			sim.ui_top_inset = value

## Emitted whenever the room changed, so a shell can restyle whatever it uses to show which room
## you are in without this file knowing whether that is a row of buttons or a two-state toggle.
signal room_changed

var _host: Control
var _showing_lab := true


func _init(p_catalog: PartsCatalog = null, p_tweaks: AssemblyTweaks = null,
		p_pack_charge: PackCharge = null) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_PASS

	pack_charge = p_pack_charge if p_pack_charge != null else PackCharge.load_from()

	# Lab's Controls go in a host inset below whatever chrome the shell draws. Sim is added as a
	# direct child instead, because it is a Node3D scene carrying its own cameras and its own HUD
	# layer and has no business inside a Control layout.
	_host = Control.new()
	_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_host.anchor_right = 1.0
	_host.anchor_bottom = 1.0
	_host.offset_top = top_inset
	add_child(_host)

	lab = LabScreen.new(
		p_catalog if p_catalog != null else catalog_for_lab(), p_tweaks, pack_charge)
	# The garage quotes its numbers in the air of the course that is selected to be flown. Set here
	# rather than read by Lab, so there is one owner of the library and one reader of it.
	lab.air = course_library.selected().air
	_host.add_child(lab)


func catalog_for_lab() -> PartsCatalog:
	return PartsCatalog.load_with_custom()


func showing_lab() -> bool:
	return _showing_lab


## Back to the garage. Whatever was running is removed from the tree and freed immediately rather
## than queue_free()'d, so that "the flight loop has stopped" is true the moment this returns
## instead of at the end of the frame — which is also what makes it testable synchronously.
func show_lab() -> void:
	_close_rooms()
	_showing_lab = true
	lab.visible = true
	room_changed.emit()


## Onto the thrust stand, with the pairing currently chosen on Lab's rails. The bench judges
## the build being assembled next door — it has no fixture of its own, because a bench that
## tested something other than what you are building would be answering a question nobody asked.
##
## Built fresh every time, so the pack starts full and the motor starts stopped. A bench you
## walked away from mid-run and came back to still spinning would be a machine left unattended.
func show_bench() -> void:
	_close_rooms()
	var selection := lab.selection()
	_unplug_for(selection)
	bench = BenchScreen.new(
		lab.catalog,
		selection["motor"],
		selection["propeller"],
		selection["battery"],
		pack_charge
	)
	_enter_room(bench)


## Onto the battery bench, with the pack currently chosen on Lab's rail and the motors and props
## that will be pulling on it. Built fresh every time, for the same reason the thrust stand is: a
## bench you walked away from mid-run and came back to still under load would be a machine left
## unattended, and here it would have been quietly flattening a battery the whole time.
func show_battery_bench() -> void:
	_close_rooms()
	var selection := lab.selection()
	_unplug_for(selection)
	battery_bench = BatteryBenchScreen.new(
		lab.catalog,
		selection["motor"],
		selection["propeller"],
		selection["battery"],
		pack_charge
	)
	_enter_room(battery_bench)


## Onto the ESC bench, with the board currently chosen on Lab's rail and the motors that will be
## pulling through it. Built fresh every time, for the same reason the other two benches are: a
## bench you walked away from mid-sweep and came back to still at full throttle would be a machine
## left unattended.
func show_esc_bench() -> void:
	_close_rooms()
	var selection := lab.selection()
	_unplug_for(selection)
	esc_bench = EscBenchScreen.new(
		lab.catalog,
		selection["motor"],
		selection["propeller"],
		selection["battery"],
		selection["esc"],
		pack_charge,
		selection["frame"]
	)
	_enter_room(esc_bench)


## Onto the frame bench, with the whole aircraft Lab has assembled. It takes the FULL selection
## rather than a pairing, because what is under test here is the frame carrying its build — an empty
## frame has no interesting inertia, and swapping the pack changes the answer as much as swapping
## the frame does.
##
## Built fresh every time, for the same reason the other three benches are: a bench you walked away
## from mid-step and came back to still at full deflection would be a machine left unattended.
func show_frame_bench() -> void:
	_close_rooms()
	var selection := lab.selection()
	_unplug_for(selection)
	frame_bench = FrameBenchScreen.new(
		lab.catalog,
		selection["frame"],
		selection["motor"],
		selection["propeller"],
		selection["battery"],
		selection["esc"],
		pack_charge,
		lab.tweaks
	)
	_enter_room(frame_bench)


## Into the field editor, with the build currently on Lab's rails. The build is here for exactly one
## reason — a ring smaller than the aircraft that has to fly through it is impossible, and that is a
## comparison of two known dimensions — and this room changes nothing about it.
##
## Notably it does NOT call _unplug_for(). A charger running while you lay out gates is fine: this
## room draws no current, so there is nothing for it to overwrite. That is labs-and-sim.md §5 read
## literally rather than by analogy with the benches.
func show_field_editor() -> void:
	_close_rooms()
	field_editor = FieldEditorScreen.new(course_library, lab.current_build())
	# Editing the field changes what the aircraft next door CAN DO, so Lab's readout has to follow
	# it. Without this the builder types 3500 m, walks back to the garage and reads a
	# thrust-to-weight for a place they are not — which is the exact stale reading this feature
	# exists to remove, reintroduced one room over.
	field_editor.course_changed.connect(func() -> void:
		lab.set_air(course_library.selected().air))
	_enter_room(field_editor)


## Into Studio, to look at flights already flown (LTHL-54).
##
## The library is constructed HERE and fresh on every entry, rather than held as a field alongside
## course_library and pack_charge. Those two are shared because two rooms look at one set of packs
## and one set of courses within a session, and a second copy would be a second opinion. A log
## directory has exactly one reader and its contents change while the builder is somewhere else —
## every time they land in Sim. A cached library would open a room describing the history as it
## stood before the flight they just finished, which is the one flight they came in here to look at.
##
## Like the field editor, this does NOT call _unplug_for(): Studio draws no current, so there is
## nothing for it to overwrite.
func show_studio() -> void:
	_close_rooms()
	studio = StudioScreen.new(FlightLogLibrary.load_from())
	_enter_room(studio)


## Out to the field, flying what the garage built. The scene is instantiated fresh, handed
## Lab's selection, and only THEN added to the tree — the hand-over has to land before _ready
## runs, or the flight scene would spend a moment on a different aircraft and rebuild.
##
## This is the build crossing the boundary (labs-and-sim.md §4), and it is the whole point of
## the door: pick the 7" frame in the garage and the airframe in the field is a 7", because
## both rooms generate it from the same Build rather than each drawing their own.
func show_sim() -> void:
	_close_rooms()
	if sim == null:
		sim = load(SIM_SCENE).instantiate()
		sim.initial_selection = lab.selection()
		_unplug_for(sim.initial_selection)
		# Handed over rather than loaded by Sim, so both rooms are looking at ONE set of packs
		# within a session. Sim drains it and writes back on landing; it authors nothing else.
		sim.pack_charge = pack_charge
		# The field crosses the door the same way the build does, and in the same direction only.
		# Handed over rather than re-loaded so a course laid out next door is the course you fly
		# without a trip through the file; Sim reads it and never writes it (labs-and-sim.md §4).
		sim.course_library = course_library
		sim.adopt_selected_course()
		# Sim is a direct child rather than living in `_host`, so nothing insets it below the
		# shell's chrome the way Lab is inset. Its panel is told how much room that chrome takes
		# instead.
		sim.ui_top_inset = top_inset
		add_child(sim)
	_showing_lab = false
	lab.visible = false
	room_changed.emit()


## The three lines every Control room repeats on the way in. Collected because they are one step —
## "this room is now the room you are in" — and a room that was added to the tree without Lab being
## hidden would draw over the garage rather than replacing it.
func _enter_room(room: Control) -> void:
	_host.add_child(room)
	_showing_lab = false
	lab.visible = false
	room_changed.emit()


## Takes the pack this room is about to use off the charger. A pack cannot be plugged in and
## under load at once, and — the part that actually bites — every one of these rooms snapshots
## the pack on the way in and writes it back on the way out, so a charger still running into one
## of them has its whole contribution overwritten when you come back. Charging a pack you are
## NOT taking with you carries on untouched.
func _unplug_for(selection: Dictionary) -> void:
	if lab == null or lab.charge_panel == null:
		return
	if lab.charge_panel.release(str(selection.get("battery", ""))):
		pack_charge.save()


## Tears down whichever room is currently running. Freed immediately rather than
## queue_free()'d, so "the loop has stopped" is true the moment this returns instead of at the
## end of the frame — which is also what makes it testable synchronously.
## Every room that could have drained a pack writes its consequence back on the way out, and the
## store is saved once. Collected here rather than inside each room because the write-back is a
## property of LEAVING, and a room that saved on its own could only do it by guessing when it was
## about to be freed.
func _close_rooms() -> void:
	if sim != null:
		sim.persist_pack_charge()
		remove_child(sim)
		sim.free()
		sim = null
	if bench != null:
		bench.persist_pack_charge()
		_host.remove_child(bench)
		bench.free()
		bench = null
	if battery_bench != null:
		battery_bench.persist_pack_charge()
		_host.remove_child(battery_bench)
		battery_bench.free()
		battery_bench = null
	if esc_bench != null:
		esc_bench.persist_pack_charge()
		_host.remove_child(esc_bench)
		esc_bench.free()
		esc_bench = null
	if frame_bench != null:
		frame_bench.persist_pack_charge()
		_host.remove_child(frame_bench)
		frame_bench.free()
		frame_bench = null
	# No persist_pack_charge() here, and its absence is the assertion: the field editor cannot have
	# drained anything, because nothing in it turns. A write-back "for symmetry" would be inventing
	# a consequence, which is precisely what §5 does not permit.
	if field_editor != null:
		_host.remove_child(field_editor)
		field_editor.free()
		field_editor = null
	# No persist_pack_charge() here either, and for the same reason: Studio reads files. Nothing
	# in it turns, draws current or holds a Powertrain, so a write-back would be inventing a
	# consequence out of having opened a room.
	if studio != null:
		_host.remove_child(studio)
		studio.free()
		studio = null
	# Only when a room actually changed something. Opening a bench and walking straight back out
	# must not rewrite the file — see PackCharge._dirty.
	if pack_charge.has_unsaved_changes():
		pack_charge.save()
