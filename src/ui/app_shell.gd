class_name AppShell
extends Control
## The two rooms, and the door between them (labs-and-sim.md §1).
##
## Lab is the garage and it is where the app opens. Sim is the field, reached deliberately.
## Before this shell existed, Lothal booted straight into a flight simulation with a parts
## panel bolted onto the side, which made every part change feel like a cheat-menu slider
## rather than a decision.
##
## The important behaviour is what happens on the way through the door:
##
## **Sim does not exist while you are in Lab.** It is instantiated when the tab is opened and
## FREED when it is left — not hidden, not paused. That is the honest form of "choosing parts
## does not cost a 1 kHz integrator, a renderer and a real-time audio synthesiser": a paused
## node still holds a chase camera, a DroneAudio bus and a HUD CanvasLayer, and a flag saying
## it is idle is something that can rot. A freed instance cannot.
##
## **Lab persists.** It is cheap — no integrator lives in it — and the frame you chose should
## still be chosen when you walk back from the field. This is the boundary labs-and-sim.md §4
## describes: the build crosses from Lab to Sim, and nothing crosses back except consequences.
##
## Consequence worth naming: because Sim is rebuilt on entry, a lap in progress does not
## survive a trip to the garage. That is the intended reading — you landed and walked away.

const SIM_SCENE := "res://src/scenes/main.tscn"
const TAB_BAR_HEIGHT := 40.0

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
## The courses that have been laid out, and which one is flown. Held here for the same reason
## `pack_charge` is: two rooms touch it — the editor writes it and the field reads it — and one
## instance within a session is what stops the door from handing over a stale copy.
var course_library := CourseLibrary.load_from()
## How much charge is in each pack right now. Loaded once on startup and held here rather than in
## any one room, because it is the one piece of state every room touches: two benches and the
## field all drain it, and Lab is where it gets charged back up. It is saved whenever a room that
## could have changed it is closed.
var pack_charge := PackCharge.load_from()

var _host: Control
## The CanvasLayer carrying the tab bar and the update notice. Held so the activation gate can
## hide the entire app behind itself — see `_ready()`.
var _tab_layer: CanvasLayer
## "Activated" tag sitting in the tab row once a licence has verified. Hidden until then.
var _account_label: Label
var _activation_layer: CanvasLayer = null
var _lab_button: Button
var _bench_button: Button
var _pack_bench_button: Button
var _esc_bench_button: Button
var _frame_bench_button: Button
var _field_button: Button
var _sim_button: Button
var _showing_lab := true

var settings: AppSettings

func _init() -> void:
	theme = LothalTheme.get_theme()
	settings = AppSettings.load_from()

	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Lab's Controls go in a host inset below the tab bar. Sim is added as a direct child
	# instead, because it is a Node3D scene carrying its own cameras and its own HUD layer
	# and has no business inside a Control layout.
	_host = Control.new()
	_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_host.anchor_right = 1.0
	_host.anchor_bottom = 1.0
	_host.offset_top = TAB_BAR_HEIGHT
	add_child(_host)

	lab = LabScreen.new(catalog_for_lab(), null, pack_charge)
	# The garage quotes its numbers in the air of the course that is selected to be flown. Set here
	# rather than read by Lab, so there is one owner of the library and one reader of it.
	lab.air = course_library.selected().air
	_host.add_child(lab)

	# The tab bar sits on a high CanvasLayer so it stays reachable over Sim, whose HUD is
	# itself on a CanvasLayer and would otherwise draw straight over the only way out.
	var tab_layer := CanvasLayer.new()
	tab_layer.layer = 10
	add_child(tab_layer)
	_tab_layer = tab_layer

	var bar := HBoxContainer.new()
	bar.position = Vector2(LothalTheme.SPACE_2, 6)
	tab_layer.add_child(bar)

	_lab_button = _add_tab(bar, "Lab", show_lab)
	_bench_button = _add_tab(bar, "Thrust", show_bench)
	_pack_bench_button = _add_tab(bar, "Pack", show_battery_bench)
	_esc_bench_button = _add_tab(bar, "ESC", show_esc_bench)
	_frame_bench_button = _add_tab(bar, "Frame", show_frame_bench)
	_field_button = _add_tab(bar, "Field", show_field_editor)
	_sim_button = _add_tab(bar, "Sim", show_sim)

	_account_label = Label.new()
	_account_label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	_account_label.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	_account_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_account_label.visible = false
	bar.add_child(_account_label)

	_refresh_tabs()

	# The update bar rides the same high CanvasLayer as the tabs, for the same reason: Sim's HUD
	# is on a layer of its own and would draw straight over anything sitting in the ordinary
	# tree. Anchored to the bottom rather than the top so it never crowds the tab row, and it
	# stays hidden unless a signed manifest offers something newer — see UpdateNotice.
	#
	# Not built at all in Store builds. The bar's only action is to open the dl.meetdev.in
	# download page, and an app distributed through the Microsoft Store that points its users at
	# an installer from somewhere else fails certification — Store copies update through the
	# Store, so the bar would also be offering a route that is simply wrong for that install.
	# The `store` feature comes from the "Windows Store" export preset's custom_features, so it
	# is false in the editor and in every direct-download build.
	if not OS.has_feature("store"):
		var notice := UpdateNotice.new(LothalVersion.MANIFEST_URL)
		notice.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		notice.anchor_top = 1.0
		notice.anchor_right = 1.0
		notice.anchor_bottom = 1.0
		notice.offset_top = -UpdateNotice.BAR_HEIGHT
		tab_layer.add_child(notice)

func _ready() -> void:
	if get_tree() != null and get_tree().root != null and settings != null:
		get_tree().root.content_scale_factor = settings.ui_scale

	_apply_activation_gate()


## Shows the app, or the activation screen, according to the licence on disk.
##
## Run from `_ready()` rather than `_init()` deliberately. The rooms are built in the constructor
## and the suite drives them by calling `AppShell.new()` without ever entering a tree — gating in
## the constructor would mean 838 tests exercising an app that had refused to build itself, and
## the pressure to add a bypass for them would arrive immediately. A bypass is precisely what must
## not exist: a seam that turns the gate off is a way in that needs no decompiler at all.
##
## The consequence is that the `capture_*` screenshot tools, which DO enter a tree, now need an
## activated user:// on the machine running them. That is the maintainer's own machine and it has
## one; a headless CI box would photograph the activation screen instead, which is the honest
## result rather than a bug.
##
## Missing, malformed and tampered licences all land here identically. That is the whole design —
## if a corrupt licence behaved differently from an absent one, the difference would eventually be
## somebody's way through.
func _apply_activation_gate() -> void:
	var licence := LicenceCheck.verify_stored()
	if licence.valid:
		_show_activated(licence.email)
		return

	print_verbose("activation gate: %s" % licence.reason)

	# Everything else is hidden rather than left underneath, and the screen goes on a layer above
	# the tab bar's. Leaving the tabs reachable would make the gate a suggestion: Sim is one click
	# away, and it neither knows nor cares whether a licence verified.
	_host.visible = false
	_tab_layer.visible = false

	_activation_layer = CanvasLayer.new()
	_activation_layer.layer = 20
	add_child(_activation_layer)

	var screen := ActivationScreen.new(LothalVersion.ACTIVATION_URL)
	screen.activated.connect(_on_activated)
	_activation_layer.add_child(screen)


## Called when the activation screen accepts a licence. The app appears without a relaunch — a
## restart here would be a second chance for something to go wrong immediately after the one step
## the user was already unsure about.
func _on_activated(email: String) -> void:
	if _activation_layer != null:
		_activation_layer.queue_free()
		_activation_layer = null

	_host.visible = true
	_tab_layer.visible = true
	_show_activated(email)


func _show_activated(_email: String) -> void:
	if _account_label == null:
		return
	_account_label.text = "Activated"
	_account_label.visible = true


func _add_tab(bar: HBoxContainer, text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(92, 28)
	button.pressed.connect(handler)
	bar.add_child(button)
	return button


## Overridable seam for the catalog Lab reads. Kept as a method rather than inlined so a test
## or a later "load a different catalog" path has somewhere to stand.
##
## load_with_custom rather than load_default because LAB IS WHERE A BUILDER'S OWN FRAMES LIVE —
## and because ReferenceBuild's catalog must stay the shipped one, which is why these are two
## functions rather than one with an argument.
func catalog_for_lab() -> PartsCatalog:
	return PartsCatalog.load_with_custom()


func showing_lab() -> bool:
	return _showing_lab


## Back to the garage. Sim is removed from the tree and freed immediately rather than
## queue_free()'d, so that "the flight loop has stopped" is true the moment this returns
## instead of at the end of the frame — which is also what makes it testable synchronously.
func show_lab() -> void:
	_close_rooms()
	_showing_lab = true
	lab.visible = true
	_refresh_tabs()


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
	_host.add_child(bench)
	_showing_lab = false
	lab.visible = false
	_refresh_tabs()


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
	_host.add_child(battery_bench)
	_showing_lab = false
	lab.visible = false
	_refresh_tabs()


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
	_host.add_child(esc_bench)
	_showing_lab = false
	lab.visible = false
	_refresh_tabs()


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
	_host.add_child(frame_bench)
	_showing_lab = false
	lab.visible = false
	_refresh_tabs()


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
	_host.add_child(field_editor)
	_showing_lab = false
	lab.visible = false
	_refresh_tabs()


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
	# Only when a room actually changed something. Opening a bench and walking straight back out
	# must not rewrite the file — see PackCharge._dirty.
	if pack_charge.has_unsaved_changes():
		pack_charge.save()


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
		# tab bar the way Lab is inset. Its panel is told how much room the bar takes instead.
		sim.ui_top_inset = TAB_BAR_HEIGHT
		add_child(sim)
	_showing_lab = false
	lab.visible = false
	_refresh_tabs()


func _refresh_tabs() -> void:
	_lab_button.button_pressed = _showing_lab
	_bench_button.button_pressed = bench != null
	_pack_bench_button.button_pressed = battery_bench != null
	_esc_bench_button.button_pressed = esc_bench != null
	_frame_bench_button.button_pressed = frame_bench != null
	_field_button.button_pressed = field_editor != null
	_sim_button.button_pressed = sim != null
