class_name GlassShell
extends Control
## The frame of the new UI — the shell, walkable, with nothing real behind the systems that have
## no model yet (CONTINUE-HERE.md §5).
##
## This implements the SHAPE and the NAVIGATION, and deliberately no feature. Selecting a system
## changes what is on the rail, what is in the inspector, and what is lit on the model. The five
## systems Lothal already models show their real screens; the four it does not show a stub that
## says what belongs there and where the list came from. Nothing here invents a spec, and nothing
## here saves.
##
## **It is built BESIDE the old shell, not in place of it** (§4). The eight tabs still work and the
## shipping app still boots them; reach this through `src/scenes/glass_shell.tscn` or
## `tests/capture_glass_shell.gd`. Both shells drive ONE `RoomHost`, so neither has its own opinion
## about what happens when you leave a room running.
##
## ## How full-bleed is achieved without editing LabScreen's layout
##
## LabScreen lays itself out as one HBoxContainer holding `[rails | viewport | panels]`, with the
## SubViewportContainer set to SIZE_EXPAND_FILL. So the viewport is already the element that takes
## whatever is left over — which means the way to make it full-bleed is not to rewrite the layout
## but to REMOVE the other two children from the row. `_ready()` reparents the rail column and the
## details column out into floating panels of this shell, the HBox is left holding one expanding
## child, and it fills.
##
## Nothing about Lab's behaviour changes as a result. The two containers are moved, not rebuilt, so
## every signal made in LabScreen._init survives — including the `_rails.tab_changed → panels`
## sync, which still keeps the two columns describing the same component. `show_panel()` and
## `viewport()` still work, which is why the capture tooling still works.
##
## ## What is deliberately still absent
##
## - **The project chip is live, and most of its menu is not.** The chip holds a real Project and
##   Rename works; New, Open, Duplicate, both exports and Reveal are greyed and each says what it
##   waits on. That split is not a compromise, it is the structure — ProjectMenu.ENTRIES carries
##   one `waiting_on` string per entry, and emptying it is the whole of turning one on.
## - **The bottom-left tools do nothing.** Overlays, explode, x-ray and measure are four features.
## - **The four benches, the field editor and Studio have no home here yet.** They are rooms in the
##   old shell and this shell opens only Lab and Sim. `RoomHost` can already open every one of them
##   — the missing piece is where in the dropdown model each belongs, which is a design question
##   rather than plumbing. Until it is answered the tab bar cannot be deleted (§4's W0.6).
## - **The parts strip is still a column.** §5 puts a system's parts in a thin strip along the top.
##   That means rebuilding PartPicker, which is component work; the rail floats at the left instead.
##   Named again on `_build_rail_glass()`, because it is the largest remaining gap between this
##   screen and the design.
const TOP_BAR_HEIGHT := 44.0
const CLUSTER_MARGIN := 12.0
const RAIL_WIDTH := 300.0
const INSPECTOR_WIDTH := 348.0
## The most of the window the inspector may claim, however long its rows get. Under half: past that
## the thing being inspected has less room than the description of it, which inverts what a
## full-bleed viewport is for. 0.45 rather than 0.42 because the widest tab in the app — Layout, at
## 561 px — lands just inside it on a 1333 px window, and a ceiling that cut the widest real panel
## by a handful of pixels would be a bound chosen to be tidy rather than to be right.
const MAX_INSPECTOR_FRACTION := 0.45
## How far the floating columns stop short of the bottom, so they never collide with the
## bottom-left tool cluster or the bottom-right toggle.
const BOTTOM_KEEPOUT := 76.0

## Which CanvasLayer the Lab/Sim toggle rides. Ten, matching the old tab bar, and for the identical
## reason: Sim's HUD is on a layer of its own and draws straight over anything in the ordinary tree.
## The toggle is the ONLY way out of the field, so a toggle underneath the HUD is an app you cannot
## leave. See _build_bottom_right_cluster.
const TOGGLE_LAYER := 10

## How much of the panel's opacity glass keeps. Not fully opaque — the whole argument for a
## full-bleed viewport is that the model stays visible, and a solid panel over it is just the old
## column with rounded corners. Not very transparent either: these panels carry numbers, and text
## over a moving airframe is unreadable long before it is beautiful.
const GLASS_ALPHA := 0.86

## What a dimmed mesh fades to when another system has focus. §5: "Selecting a system dims the
## rest of the model. This is what makes a full-bleed viewport earn its space."
##
## Dimmed rather than hidden, deliberately. Hiding the frame to look at the motors would leave four
## motors floating in space with nothing to judge their placement against, and placement is most of
## what there is to judge.
const DIM_TRANSPARENCY := 0.82

## The nine systems of §5, in order, each carrying the rails and panels it owns.
##
## `rails` and `panels` are TAB TITLES, matched against the containers LabScreen built. Titles
## rather than indices because indices are a property of the order LabScreen happens to add its
## children in, and a tenth panel inserted in the middle would silently repoint every system here.
##
## A system with an empty `rails` and `panels` has no model behind it and shows `stub` instead —
## greyed with a `soon` tag in the dropdown, per §5, but still SELECTABLE. That is this file's
## answer to open question §8.2 ("what does clicking a greyed item do"): it shows you what would be
## there. A tooltip was the alternative and it is worse, because the honest content of these four
## is a list of parts, and a list does not fit in a tooltip.
##
## Whether nine collapses to six is open question §8.1 and is NOT settled here. Nine is what the
## design says, so nine is what the frame is drawn with — the point of building the shape is to
## look at it and then answer that, not to answer it in advance.
const SYSTEMS := [
	{
		# THE AIRCRAFT ITSELF, and the only entry that is a choice rather than a consequence.
		#
		# Splitting this out of Airframe is what let Airframe become what §1 says it is. The old
		# single entry was doing two unrelated jobs at once: pick which of fifteen catalog frames
		# you are working on, and inspect what that choice implies. The first is shopping and the
		# second is engineering, and putting them behind one dropdown item meant the four things §1
		# actually names — frame, arms, the bolted joint, the soft mounts — had nowhere to live.
		"name": "Drone",
		"rails": ["Frame"],
		"panels": ["Frame", "Fit"],
		"decided_by": ["frame"],
	},
	{
		# THE FOUR THINGS §1 NAMES, minus the one with no model behind it.
		#
		# No rail, and that is not an omission. Every other system here is a list of parts you pick
		# from; none of these four is. An arm is a plate with a centreline (§2), a bolted joint is
		# generated from the bolt pattern, and an inertia tensor is an integral — you choose a frame
		# and these follow. So the rail column is hidden for this system entirely, which is the
		# first time this shell renders the full-bleed viewport the design asks for with nothing but
		# an inspector floating over it.
		#
		# STRAPS & PADS IS ABSENT. §6 models a pad as a spring and gives it a transmissibility, and
		# none of that is built — only the pad's material and mass exist. A fifth tab reading four
		# dashes would be worse than its absence, and the honest place for it is here, in a comment
		# that says why, until §6 has a model. Slice A6.
		"name": "Airframe",
		"rails": [],
		"panels": ["Structure", "Arms", "Fasteners", "Layout"],
		"decided_by": ["frame"],
	},
	{
		"name": "Propulsion",
		"rails": ["Motor", "Prop"],
		"panels": ["Motor", "Prop"],
		"decided_by": ["motor", "propeller"],
	},
	{
		# EVERY AMPERE FROM CELL TO MOTOR LEAD, and that sentence is the whole membership rule.
		#
		# The ESC used to sit under Control beside the FC and the tune, which was an accident of
		# when each part arrived rather than a statement about the aircraft: the ESC is where the
		# pack's current is CONSUMED, and every harness check asks about the pack and the board in
		# one breath — ampacity against what the board passes, sag against what the board sees.
		# Splitting them put the two halves of one question behind two dropdown entries.
		#
		# The FC stays in Control. It draws no meaningful current, so it fails the rule.
		"name": "Power",
		"rails": ["Pack", "ESC"],
		"panels": ["Pack", "ESC", "Harness"],
		"decided_by": ["battery", "esc"],
	},
	{
		# `esc` LEFT THIS LIST WITH THE PANEL. Both halves of the move have to happen together:
		# `decided_by` is what the completeness ring counts, and a category named by two systems is
		# credited twice by arithmetic that assumes each decision belongs somewhere once.
		"name": "Control",
		"rails": ["FC"],
		"panels": ["FC", "Tune"],
		"decided_by": ["flight_controller"],
	},
	{
		# The receiver belongs to Control and is reached from here, because ElectronicsPicker emits
		# all four bays as one payload and there is no way to split its rail without splitting the
		# picker. That is a real modelling asymmetry rather than a decision — the same family as the
		# two §7 already names, where `antennas` is VTX antennas only and the receiver's antenna is a
		# string on the receiver entry. Left visible rather than papered over.
		"name": "Video",
		"rails": ["Electronics"],
		"panels": ["Electronics"],
		"decided_by": ["camera", "vtx"],
	},
	{
		"name": "Printed",
		"rails": [],
		"panels": [],
		"decided_by": [],
		"stub": {
			"why": "Nothing here is modelled. The printed parts a build needs are known; what "
				+ "they weigh, where they mount and what they cost in fit are not.",
			"items": ["TPU camera mount", "Antenna mount", "Prop guards", "Battery pad",
				"Standoff spacers", "Payload mount"],
			"source": "CONTINUE-HERE.md §7 — components with no category at all",
		},
	},
	{
		"name": "Config",
		"rails": [],
		"panels": [],
		"decided_by": [],
		"stub": {
			"why": "Stage 5 of ten, and the one that kills more first builds than physics does. "
				+ "Zero model today. Betaflight SITL does not exist — flight_controller.gd:16 "
				+ "reserves the slot and nothing listens on port 9002.",
			"items": ["Motor direction and order", "ESC protocol", "Rates and modes", "Failsafe",
				"OSD layout", "Blackbox logging"],
			"source": "CONTINUE-HERE.md §3 and §6",
		},
	},
	{
		"name": "Ground kit",
		"rails": [],
		"panels": [],
		"decided_by": [],
		"stub": {
			"why": "Often more than half a first build's spend, and the half a beginner is least "
				+ "able to choose. It matters because these run BACKWARDS into the aircraft: DJI "
				+ "goggles decide your camera and VTX, an ELRS radio decides your receiver, a 6S "
				+ "build needs a 6S charger.",
			"items": ["Radio transmitter", "FPV goggles", "Charger", "LiPo bag", "Tools",
				"Spare props"],
			"source": "CONTINUE-HERE.md §7 — 'off the aircraft, and this is the real hole'",
		},
	},
	{
		# Field HAS a model — FieldEditorScreen and CourseLibrary are real and shipped. It is listed
		# unmodelled here because it is a ROOM in the old shell and this shell does not open rooms.
		# Porting it is shell work of the same kind as Lab's port, not a missing feature.
		"name": "Field",
		"rails": [],
		"panels": [],
		"decided_by": [],
		"stub": {
			"why": "This one is not missing — FieldEditorScreen and CourseLibrary are shipped and "
				+ "work. It is unreachable from HERE because it is a separate room in the old "
				+ "shell, and porting rooms into this frame is the next piece of shell work.",
			"items": ["Gate layout", "Air density and altitude", "Course selection"],
			"source": "labs-and-sim.md §5 — already built, not yet ported",
		},
	},
]

## Which 3D nodes belong to which system, matched against the nearest name that matches — the
## node's own first, and failing that the nearest ancestor's. Anything matching nothing belongs to
## Airframe — the frame is what is left when every fitted part is accounted for, which is also
## literally true of a frame.
##
## ## THE STACK IS SHARED, AND IT IS TWO BOARDS RATHER THAN ONE MESH
##
## The ESC moved to Power and the FC stayed in Control, so `Stack` — one node — now holds one part
## from each of two systems. I went looking for the "they are one mesh, so let both light it" case
## and it is not this: `StackMesh.rebuild` builds `Board_ESC` and `Board_FC` as separate
## `MeshInstance3D`s at their own two heights, which is the same split the mass model already makes
## (`Build.mass_parts` puts ESC mass at `esc_centre_height_m` and FC mass at `fc_centre_height_m`).
## Two nameable objects can be lit separately and should be, so Power lights the lower board and
## Control lights the upper one.
##
## **`Stack` stays under Control**, and that is a decision rather than a leftover. What is left
## under that name once the two boards are claimed is the four standoffs and the USB connector —
## hardware that belongs to neither board, holds both, and would read as a rendering fault if it
## faded out from under a board that stayed lit. Control is the system whose part is on top of it.
##
## **This is what makes the OWN-NAME-FIRST rule load-bearing**, and it did not used to be. While
## every prefix named a top-level node, "nearest matching ancestor" and "nearest matching node"
## were the same rule. `Board_ESC` sits UNDER `Stack`, so ancestor-only classification never asks
## it its name — Power would dim the board it had just been given. Checked against every other node
## name the airframe builds: none of `Cell_`, `Groove_`, `Shrink`, `Strap_`, `Lead_`, `Standoff_`,
## `Connector`, `Arm_`, `Pad_`, `Plate*` or `GuardRing` begins with a prefix in this table, so no
## other classification changes.
const SYSTEM_NODE_PREFIXES := {
	"Propulsion": ["Motor_", "Propeller_"],
	"Power": ["Battery", "Board_ESC"],
	"Control": ["Stack", "Board_FC", "Component_receiver"],
	"Video": ["Component_camera", "Component_vtx", "Component_antenna"],
}

## The rooms, and the only owner of the rules for entering and leaving them. This shell asks; it
## does not instantiate or free anything itself. See RoomHost — the reason it is a shared object
## rather than a copy is that two shells able to leave a Powertrain turning would be one too many.
var rooms: RoomHost
## The garage. A pass-through, because RoomHost builds it: this shell reparents Lab's two columns
## into floating glass and drives its rails, but it does not own its lifetime.
var lab: LabScreen:
	get: return rooms.lab

var _rail_glass: PanelContainer
var _inspector: PanelContainer
var _rail_stub: SystemStub
var _inspector_stub: SystemStub
var _system_dropdown: OptionButton
## The drone this shell is describing, and the file it lives in. Its `parts` are kept in step with
## the rails by _sync_project(), and AUTOSAVE_SECONDS later it is on disk.
var container: ProjectContainer
var chip: ProjectChip
var settings: AppSettings
var _autosave: Timer
var _open_dialog: FileDialog

## How often the shell asks whether anything changed. Not how often it writes — an unchanged
## project writes nothing (ProjectContainer.has_unsaved_changes), so this is the resolution of the
## "saved 4s ago" line as much as it is the save interval.
##
## One second, because the number the chip shows is in seconds and a chip that lagged its own
## claim by five seconds would be reporting a save that had not happened yet.
const AUTOSAVE_SECONDS := 1.0
var _status_label: Label
var _ring: CompletenessRing
## The four clusters, held so they can be RETRACTED for Sim (§5: "Sim is the same window with the
## chrome retracted"). Held rather than looked up, because the retraction is the mechanism that
## enforces "Sim authors nothing" — a shell that searched for its own panels by name could miss one
## and leave a part picker floating over a flight.
var _top_bar: HBoxContainer
var _tools_glass: PanelContainer
## The dropdown's own glass, held so the empty state can hide it while keeping the chip — the two
## live project actions ride the chip, not the dropdown.
var _dropdown_glass: PanelContainer
## The whole Lab/Sim cluster, held so the empty state can hide it: there is no build to take to
## the field, and a toggle that flies nothing would be a button that lies.
var _bottom_right_glass: PanelContainer
## The "No drone open" panel that replaces the chrome after a Delete.
var _empty_state: Control
var _sim_button: Button
var _lab_button: Button
var _room_menu: RoomMenu
var _focused_index := 0
## The plan editor, shown only while Airframe is the focused system.
var _workbench: FrameWorkbench
## The blade designer — Propulsion's room, opened on request rather than with the system. See
## `_build_blade_room` for why the two rooms differ in that.
var _blade_room: PropulsionWorkbench
var _blade_room_close: Button

## P10e's five analysis overlays, keyed by `OverlayTray.ENTRIES` id. Held on the shell rather than
## inside the tools cluster so the tray can be driven by a test without synthesising a click on a
## button whose position is a layout decision — the same posture `set_blade_room_open` takes.
##
## A dictionary rather than five named members, and that is not tidiness. The five were five
## members, and every operation on them — show, hide, refill, place — was five lines that had to be
## written five times and, being written five times, drifted: `_sync_thrust_overlay` guarded four of
## them for null and returned early on the fifth. What the tray does to all of them, it now does in
## a loop.
var _overlays: Dictionary = {}
## Which of the five the builder has ticked. Five at once is what shipped and what did not fit; see
## `OverlayTray` for why the default is two.
var _chosen_overlays: Array[String] = []
var _overlays_button: Button
## The chevron beside it. Two controls because they are two actions — put the tray up or take it
## down, and change what is in it — and one button doing both means either a click that opens a menu
## when you wanted a toggle, or a toggle you cannot reconfigure without one.
var _overlays_menu_button: MenuButton

## The top strip's door into the focused system's room, and the glass behind it. Shown only for a
## system that HAS a room reachable that way — today, Propulsion. See `_build_top_cluster`.
var _room_door: Button
var _room_door_glass: PanelContainer
## The way back out of the blade designer, and the glass behind it. In the top bar beside the door
## rather than floating over the room — see `_build_blade_room` for what floating cost.
var _blade_room_close_glass: PanelContainer


func _init(p_catalog: PartsCatalog = null, p_tweaks: AssemblyTweaks = null,
		p_pack_charge: PackCharge = null) -> void:
	theme = LothalTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0

	settings = AppSettings.load_from()
	container = ProjectContainer.make(ProjectLibrary.starting_project())
	var catalog := p_catalog if p_catalog != null else PartsCatalog.load_with_custom()

	# top_inset stays at zero, and that zero is the design. The old shell inset every room by 40 px
	# of tab bar; here the chrome floats over a full-bleed viewport, so there is nothing to inset
	# below — which is also why Sim's own panel needs no offset when it is reached from this shell.
	rooms = RoomHost.new(catalog, p_tweaks, p_pack_charge)
	rooms.room_changed.connect(_on_room_changed)
	add_child(rooms)

	_build_update_notice()

	# Order matters below: every cluster is added AFTER `rooms`, so it draws over the viewport. This
	# is the arrangement §5 chose Godot for — Controls floating over a SubViewportContainer at full
	# z-order, which is the one thing the Tauri hybrid could not do.
	_build_rail_glass()
	_build_workbench()
	_build_blade_room()
	_build_thrust_overlay()
	_build_inspector()
	# Between the inspector and the top cluster, so the chip draws over it but it covers the model
	# and the floating columns. The empty state must never hide the project chip — New and Open are
	# the only way out of it.
	_build_empty_state()
	_build_top_cluster()
	_build_bottom_left_cluster()
	_build_bottom_right_cluster()


func _ready() -> void:
	# The builder's UI scale, applied to the whole window. Carried over from the old shell rather
	# than reinvented: it is a setting somebody has already set, and a shell swap that quietly
	# reset it would be the app forgetting something the builder told it.
	if get_tree() != null and get_tree().root != null and settings != null:
		get_tree().root.content_scale_factor = settings.ui_scale

	# The reparent that makes the viewport full-bleed. Done here rather than in _init because
	# reparent() requires both nodes to be inside the tree.
	lab.rails().reparent(_rail_glass)
	lab.panels.reparent(_inspector)
	# Behind the glass, not in front of it. Lab's own containers style themselves opaque, which is
	# correct where they are — text over a turning airframe is unreadable — but it means the panel's
	# own translucency only shows in its margins. Accepted: the glass here is the frame around the
	# content, and the content is a spec sheet.
	_rail_glass.move_child(_rail_stub, -1)
	_inspector.move_child(_inspector_stub, -1)

	_autosave = Timer.new()
	_autosave.wait_time = AUTOSAVE_SECONDS
	_autosave.timeout.connect(_on_autosave_tick)
	add_child(_autosave)
	_autosave.start()

	_open_dialog = FileDialog.new()
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.filters = PackedStringArray(["*.%s ; Lothal drone" % ProjectContainer.EXTENSION])
	_open_dialog.current_dir = ProjectSettings.globalize_path(ProjectLibrary.DIR)
	_open_dialog.file_selected.connect(open_project)
	add_child(_open_dialog)

	# The drone this shell opened with needs a home too, or the first minute of work is the one
	# minute autosave cannot protect.
	adopt(container.project)

	# The shell has no signal from Lab to listen to — LabScreen emits none — so it listens to the
	# rails directly. Fine for an experiment, and worth naming as the reason it is not fine
	# permanently: reload_catalog() rebuilds these pickers, and these connections would go with
	# them. A `selection_changed` signal on LabScreen is the real fix when this stops being an
	# experiment.
	for picker in [lab.picker, lab.motor_picker, lab.propeller_picker, lab.battery_picker,
			lab.esc_picker, lab.fc_picker]:
		picker.part_selected.connect(func(_part: Dictionary) -> void: _refresh_status())
	lab.electronics_picker.components_changed.connect(_refresh_status)

	# Re-applies whatever is currently chosen, which is NOT always index 0 — and that distinction is
	# the whole reason this line is not `_select_system(0)`.
	#
	# A shell added to the tree from a SceneTree script's own `_init` has its `_ready` DEFERRED to
	# the first frame, because the tree is still coming up. So a caller that constructs the shell and
	# immediately selects a system — which is exactly what tests/capture_glass_shell.gd does — makes
	# its choice BEFORE this runs. Hardcoding 0 here silently threw that choice away one frame later,
	# and the symptom was a screenshot whose dropdown said "Power" over a rail showing frames.
	#
	# Worth knowing that headless could not see it: with no frames rendered, `_ready` had already run
	# by the time anything looked. It took a window and a settle loop to reproduce.
	_select_system(_focused_index)
	# Deferred because a Control's combined minimum size is not known until it has been laid out
	# once, and these two have just been reparented.
	_fit_columns.call_deferred()


## Widens the two floating columns to whatever their content actually needs.
##
## The constants above are a FLOOR, not a width, and this is the difference between a floating panel
## and a container child. In LabScreen the two columns live in an HBoxContainer, which hands every
## child at least its minimum size — so `custom_minimum_size = 336` was a floor there too, and the
## pack panel quietly took the ~390 px its monospace charger readout needs. Anchored to a fixed
## offset here, the same panel had nowhere to grow and simply drew past the window edge: the shot
## read "1500 of 15" and stopped.
##
## Measured rather than hand-tuned, because the number belongs to a font and a string and would
## rot the moment either changed. A hand-picked 400 would be correct until somebody added a digit.
func _fit_columns() -> void:
	var rail_width := maxf(RAIL_WIDTH, lab.rails().get_combined_minimum_size().x)
	_rail_glass.offset_right = CLUSTER_MARGIN + rail_width + LothalTheme.SPACE_2 * 2

	var inspector_width := maxf(INSPECTOR_WIDTH, _inspector_content_width(_focused_panel_titles()))
	# CLAMPED TO THE WINDOW, because a measurement is a request and not an entitlement. The panel is
	# anchored to the right edge and grows leftwards, so an unclamped request wider than the window
	# does not produce a wide panel — it produces a panel whose contents run off the right-hand edge,
	# which is what "1500 of 15" looked like and what the four Airframe tabs did again with their
	# longer sentences. Past this bound the panel stops growing and its own scroll takes over.
	var ceiling := maxf(INSPECTOR_WIDTH, size.x * MAX_INSPECTOR_FRACTION) if size.x > 0.0 \
		else inspector_width
	inspector_width = minf(inspector_width, ceiling)
	_inspector.offset_left = -(inspector_width + LothalTheme.SPACE_2 * 2 + CLUSTER_MARGIN)

	# The plan editor stops where the inspector begins, MEASURED the same way and for the same
	# reason. `INSPECTOR_WIDTH` is a floor and the panel is routinely wider than it, so an editor
	# sized against the constant put its own toolbar underneath the inspector — where the last
	# controls could be seen through the glass and not clicked.
	if _workbench != null:
		# To the window edge while the inspector is hidden, which in Airframe it always is. Sized
		# against the panel's measured left edge otherwise, because `INSPECTOR_WIDTH` is a floor and
		# the panel is routinely wider than it.
		_workbench.offset_right = -CLUSTER_MARGIN if not _inspector.visible \
			else _inspector.offset_left - CLUSTER_MARGIN

	# THE OVERLAY TRAY IS SIZED THE SAME WAY, and for the same reason the workbench is: both walls
	# of its band are columns that have just moved. A tray placed against `INSPECTOR_WIDTH` would
	# have been the constant-versus-measurement mistake one more time, in the corner that already
	# made it once.
	_layout_overlays()


# ---------------------------------------------------------------------------
# The four clusters
# ---------------------------------------------------------------------------

## Top: project chip → system dropdown.
func _build_top_cluster() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.anchor_right = 1.0
	bar.offset_left = CLUSTER_MARGIN
	bar.offset_top = CLUSTER_MARGIN
	bar.offset_right = -CLUSTER_MARGIN
	bar.offset_bottom = CLUSTER_MARGIN + TOP_BAR_HEIGHT
	bar.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	add_child(bar)
	_top_bar = bar

	# The project chip, and it is no longer inert: it holds a real Project with a real id and a
	# real name, Rename works, and the drone menu drops out of the name itself (§5 — "the project
	# name IS the menu", which is why there is no File button anywhere in this shell).
	#
	# Seven of its nine entries are greyed and say what they wait on, the same treatment SYSTEMS
	# already gives an unmodelled system and for the same reason: a builder who cannot see that
	# Duplicate exists cannot know the app intends to compare two drones.
	chip = ProjectChip.new(container.project)
	chip.add_theme_stylebox_override("panel", _glass_stylebox())
	chip.action_chosen.connect(_on_project_action)
	chip.recent_chosen.connect(open_project)
	bar.add_child(chip)

	var dropdown_glass := _glass_panel()
	_system_dropdown = OptionButton.new()
	_system_dropdown.custom_minimum_size = Vector2(180, 0)
	for i in SYSTEMS.size():
		var system: Dictionary = SYSTEMS[i]
		_system_dropdown.add_item(
			str(system["name"]) if _is_modelled(system) else "%s   soon" % system["name"], i)
		# Greyed but NOT disabled — see SYSTEMS. A builder who cannot see that Config exists cannot
		# know the app has an opinion about it, and one who cannot click it cannot find out what
		# that opinion is.
		if not _is_modelled(system):
			_system_dropdown.set_item_disabled(i, false)
			_system_dropdown.set_item_tooltip(i, "No model behind this yet — shows what belongs.")
	_system_dropdown.select(0)
	_system_dropdown.item_selected.connect(_select_system)
	dropdown_glass.add_child(_system_dropdown)
	_dropdown_glass = dropdown_glass
	bar.add_child(dropdown_glass)

	# THE ROOM DOOR, beside the system it belongs to.
	#
	# Propulsion's room — the blade designer — was reachable only from a "Design this blade…" button
	# inside the Prop TAB of the right-hand inspector. Two clicks deep, invisible while the Motor tab
	# was selected, and the first builder to use the app could not find it: "I can't see how I am
	# going to design props just like frames." Airframe announces its room by opening it with the
	# system; Propulsion could not, because its two rails are still the point and a room would cover
	# them. So the door moves to the top strip, where it is visible the whole time the system is
	# chosen and costs the viewport a button.
	#
	# The Prop panel's button STAYS. It is the one that carries the blade the panel is rendering,
	# which is not always the fitted one, and P10d's test asserts exactly that. This door carries the
	# FITTED blade, off the rail, which is what a door labelled by the system rather than by a row
	# should open.
	var door_glass := _glass_panel()
	_room_door = Button.new()
	_room_door.custom_minimum_size = Vector2(0, 28)
	_room_door.pressed.connect(_on_room_door_pressed)
	door_glass.add_child(_room_door)
	_room_door_glass = door_glass
	bar.add_child(door_glass)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	# The way out sits at the RIGHT-HAND end of the strip, beside "Contact us", rather than beside
	# the door it undoes. The bar's left end is the project's — chip, system, room door — and a
	# button that only exists while a room is open reads as an action on the room, not part of that
	# identity. Added before `contact` so the ordering is close-then-contact.
	_build_close_door(bar)

	# The way to reach us, carried over from the old tab row. A browser, not an in-app view, for
	# the reason ActivationScreen's button gave: anything resembling a sign-in window with no
	# address bar is shaped like the phishing people are taught to refuse.
	var contact := Button.new()
	contact.text = "Contact us"
	contact.flat = true
	contact.custom_minimum_size = Vector2(0, 28)
	contact.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	contact.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	contact.pressed.connect(func() -> void: OS.shell_open(LothalVersion.CONTACT_URL))
	bar.add_child(contact)


## Left: the rail column, floated, plus the stub that replaces it for an unmodelled system.
##
## §5 says a system's parts belong in a thin strip along the TOP, not in a column at the left. This
## is that deviation, and it is the largest one on this screen: a strip means rebuilding PartPicker
## horizontally, which is component work. Worth naming precisely because the screenshots make the
## cost visible — with glass on both sides the model keeps about half the window, which is closer
## to the old three-column layout than to the design.

## THE WAY OUT OF THE BLADE DESIGNER, BESIDE THE WAY IN.
##
## It is on the shell rather than in the room for the reason it always was: the room is a workspace
## and the shell owns where a workspace sits. What changed is WHERE on the shell.
##
## It used to float, pinned to the top-right corner of the viewport at the same height the room
## starts at — so it sat on the right-hand end of the room's own toolbar and buried the pitch
## spinbox and the rpm slider behind the words "Close blade designer".
##
## THE FIRST REPAIR WAS TO RESERVE A 54 PX STRIP ABOVE THE ROOM, and it is worth recording why that
## was wrong, because it looks obviously right. This room's content does not fit in less height than
## the window gives it: at 1280x720 the column ends 2 px above the room's own bottom edge. A
## `Control` does not clip its children, so taking 54 px off the top does not scroll or squash
## anything — the mount profile and the status line simply draw through the bottom of the room and
## under the Lab/Sim/Rooms cluster, which is what the second screenshot showed. Any repair that
## costs the room height has this consequence, so the repair must cost it none.
##
## The top bar is where this button always belonged anyway: `_room_door` — the way IN to this same
## room — is already in that bar for its own stated reason. The bar has a spacer in it, so a button
## costs the viewport nothing at all, and the way in and the way out end up in the same strip, which
## is an arrangement a builder learns once — at the right-hand end of it, beside "Contact us", so
## the strip's left end stays the project's identity and the room's own action sits apart from it.
##
## 2 px is a thin margin and it is not defended by anything here; `tests/test_shell_layout.gd` is
## what will notice when a pane's minimum grows past it.
##
## Built here rather than in `_build_blade_room` for the dull reason that `_init` builds the room
## first and the bar does not exist yet at that point.
func _build_close_door(bar: HBoxContainer) -> void:
	var close_glass := _glass_panel()
	_blade_room_close = Button.new()
	_blade_room_close.text = "Close blade designer"
	_blade_room_close.custom_minimum_size = Vector2(0, 28)
	_blade_room_close.pressed.connect(func() -> void: set_blade_room_open(false))
	close_glass.add_child(_blade_room_close)
	close_glass.visible = false
	_blade_room_close_glass = close_glass
	bar.add_child(close_glass)


func _build_rail_glass() -> void:
	_rail_glass = _glass_panel()
	_rail_glass.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_rail_glass.anchor_bottom = 1.0
	_rail_glass.offset_left = CLUSTER_MARGIN
	_rail_glass.offset_top = CLUSTER_MARGIN + TOP_BAR_HEIGHT + LothalTheme.SPACE_2
	_rail_glass.offset_right = CLUSTER_MARGIN + RAIL_WIDTH
	_rail_glass.offset_bottom = -BOTTOM_KEEPOUT
	add_child(_rail_glass)

	_rail_stub = SystemStub.new(true)
	_rail_stub.visible = false
	_rail_glass.add_child(_rail_stub)


## Right: the inspector, plus the stub that replaces it for an unmodelled system.
##
## §5 says the inspector appears only when something is selected. In Lab something is ALWAYS
## selected — the app opens on the reference build, so there is no empty state — which is why it is
## always shown here. The "only when selected" rule is real, but it belongs to the systems that have
## no default, and those are exactly the four that show a stub instead.
## The Airframe room's own workspace, filling the viewport area whenever Airframe is the focused
## system — airframe.md §7.1.
##
## IT COVERS THE 3D VIEW RATHER THAN SITTING BESIDE IT, and that is the point. Airframe's subject is
## a frame you are drawing, and a plan view is where you draw one: the 3D model is what the frame
## LOOKS like, and it is one dropdown click away in any other system. Splitting the viewport between
## the two would give you half a canvas to draw in and half a model too small to read.
##
## Added between the rail glass and the inspector so it draws over the viewport and under the
## floating chrome — the arrangement §5 chose Godot for.
func _build_workbench() -> void:
	_workbench = FrameWorkbench.new(lab.catalog)
	_workbench.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Clear of the floating chrome on three sides: the top bar, the inspector column on the right,
	# and the tool cluster along the bottom. The left edge runs almost to the window edge, because
	# Airframe hides the rail column entirely — there is no parts list for a frame you are drawing.
	_workbench.offset_left = CLUSTER_MARGIN
	_workbench.offset_right = -INSPECTOR_WIDTH - CLUSTER_MARGIN * 2.0   # refined by _fit_columns()
	_workbench.offset_top = TOP_BAR_HEIGHT + CLUSTER_MARGIN
	_workbench.offset_bottom = -BOTTOM_KEEPOUT
	_workbench.visible = false
	# The one wire that makes the room live: an edit repaints the four inspector tabs, so mass,
	# inertia, stiffness and the assembly checks move while a corner is being dragged.
	_workbench.document_changed.connect(_on_frame_edited)
	add_child(_workbench)
	# OPENED ON A LAYOUT, NOT ON THE FITTED FRAME. Handing the room `lab.current_build().frame` put
	# somebody's 5" freestyle product on screen — a vendor, a published mass and an inch size — in
	# front of a builder who has chosen none of those and is here to design a part. A generated
	# Quad X is the same amount of geometry to look at and makes no claim about anything.
	_workbench.start_from({})


## An edit in the plan view, pushed to the four Airframe tabs.
##
## Straight to the panels rather than through `LabScreen._on_selection_changed`, deliberately:
## nothing about the aircraft has changed — the same motor, pack and props are fitted — and
## rebuilding the whole 3D assembly on every mouse motion during a drag would be both wasteful and
## wrong, since the frame being drawn is not necessarily the frame that is fitted.
## The Airframe room, for the capture tooling and anything else that needs to drive it the way a
## click does rather than by reaching into a private field. Null until `_build_workbench` has run.
func workbench() -> FrameWorkbench:
	return _workbench


## The Propulsion room — the blade designer, propulsion.md §7.1, slice P10d. Same accessor and same
## reason as `workbench()` above.
func blade_room() -> PropulsionWorkbench:
	return _blade_room


## The blade designer, built hidden and opened from the Prop inspector's own button.
##
## **IT IS AN OVERLAY, NOT A SYSTEM VIEW, and that is a deliberate difference from Airframe.**
## Airframe's room replaces the whole viewport whenever Airframe is focused, because Airframe has no
## rails: there is no list of frames to pick from when the frame is the thing you are drawing.
## Propulsion has two rails and they are still the point — a builder in Propulsion is usually
## choosing a motor and a prop, not authoring a planform. Making the room the system's permanent
## view would take that away to deliver something most visits do not want.
##
## So it opens on request and closes again, and the way in is a button on the Prop panel, which is
## `room_menu.gd`'s own stated arrangement: a workspace belongs to the system it works on, reached
## from that system's inspector. It touches neither `RoomHost` nor `RoomMenu`, so the derived
## "every room has a door" invariant in `test_room_host.gd` is untouched — this room's door is not
## a menu entry, and P10f is the slice that generalises that.
func _build_blade_room() -> void:
	_blade_room = PropulsionWorkbench.new(lab.catalog)
	_blade_room.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blade_room.offset_left = CLUSTER_MARGIN
	_blade_room.offset_right = -CLUSTER_MARGIN
	_blade_room.offset_top = TOP_BAR_HEIGHT + CLUSTER_MARGIN
	_blade_room.offset_bottom = -BOTTOM_KEEPOUT
	_blade_room.visible = false
	add_child(_blade_room)

	# THE STORE CHANGED, SO THE BUILD PATH HAS TO HEAR ABOUT IT (§4 of
	# plans/2026-09-01-authored-blade-design.md). Every other way of writing a custom part already
	# ends in `LabScreen.reload_catalog` — the pickers' six `custom_*_changed` signals are all wired
	# to it — and the room's publish door was the one writer with nobody listening. Without this
	# line the record lands in `user://custom_parts.json` and reaches the rails, the details panel
	# and the aircraft only after a restart: a builder publishes a blade, walks back to the garage,
	# and the propeller they just made is not on the rail.
	#
	# `reload_catalog` re-reads the file and rebuilds the rails, which is why a republish of a blade
	# the aircraft is ALREADY flying lands too: the reselected prop resolves out of the new catalog,
	# and `current_build()` assembles a Build from it. `Build.refit_from` is the same rule stated
	# where a Build that outlives the reload can honour it.
	_blade_room.parts_published.connect(func(_record: Dictionary) -> void: lab.reload_catalog())

	# The way out is built with the way in, in `_build_top_cluster` — see `_build_close_door` for
	# why it lives in the top bar and not over the room.

	lab.propeller_details.design_blade_requested.connect(_on_design_blade_requested)

	# P10f'S THREE INSPECTOR DOORS. The thrust stand left the Rooms menu (see `room_menu.gd`'s own
	# header), and the two exports are here rather than on their panels because a details panel
	# that wrote a file would be a panel that knows where this app puts things.
	lab.motor_details.thrust_bench_requested.connect(_on_thrust_bench_requested)
	# The ESC bench, the second room to leave the Rooms menu for the inspector of the system it
	# tests — the move P10f named and left. Through the same `_open_room` as every other room, so
	# the lifecycle stays RoomHost's and there is no second construction path.
	lab.esc_details.esc_bench_requested.connect(func() -> void: _open_room("esc_bench"))
	# The pack bench, the third and the last one this menu had that tests a component (PW4). Its
	# panel did not change owner — Pack was already Power's — but the ESC's did, and a Power system
	# that reaches its ESC bench from an inspector while its pack bench is still in a global menu
	# would be two different answers to the same question inside one room.
	lab.battery_details.pack_bench_requested.connect(func() -> void: _open_room("battery_bench"))
	lab.motor_details.mount_stl_requested.connect(_on_mount_stl_requested)
	lab.propeller_details.guard_stl_requested.connect(_on_guard_stl_requested)


## The five analysis overlays — P10e — built once and placed by `OverlayTray`.
##
## Bottom left of the viewport, clear of the rail column and above the tool cluster that toggles
## them. That corner rather than the middle because an overlay is a thing you glance at while
## changing a prop on the rail, not a thing you read instead of the model.
##
## NO OFFSETS ARE SET HERE, and that is the fix. The five used to carry hand-written absolute
## offsets — three columns of 360 px from the rail, then a second row — which put the third column
## under the inspector and off the right-hand edge of any window narrower than about 1430 px. The
## app ships at 1280. Geometry now comes from `_layout_overlays`, against a band measured from the
## chrome that is actually on screen; see `OverlayTray` for the full account.
##
## Added BEFORE the empty state and the two clusters, so a shell with no drone open covers them and
## the tools still draw over them. They are charts about a fitted propeller; there is no honest
## version of one on a screen that says "no drone open".
func _build_thrust_overlay() -> void:
	# Constructed from the tray's own list, in the tray's own order, so a sixth overlay is one
	# entry there plus one line here rather than a member, a build block, a show line, a hide line
	# and a refill line — the shape that let the old code guard four of five for null.
	_overlays = {
		"thrust": ThrustOverlay.new(),
		"campbell": CampbellOverlay.new(),
		"vibration": VibrationOverlay.new(),
		"spin_up": SpinUpOverlay.new(),
		"prop_disc": PropDiscOverlay.new(),
	}
	for entry in OverlayTray.ENTRIES:
		var card: Control = _overlays[str(entry["id"])]
		# Placed by `_layout_overlays` in window coordinates, so the preset is the top-left corner
		# and every offset is absolute. Anchored to the BOTTOM edge previously, which is why the
		# cards moved correctly when the window got shorter and not when it got narrower.
		card.set_anchors_preset(Control.PRESET_TOP_LEFT)
		card.visible = false
		add_child(card)
	_chosen_overlays = []
	for id in OverlayTray.DEFAULT_CHOSEN:
		_chosen_overlays.append(str(id))


## The band the cards are allowed to occupy: what is left of the window once the four clusters have
## taken theirs.
##
## Measured from the nodes rather than from the constants, because two of the four edges MOVE. The
## rail and the inspector are both sized to their content by `_fit_columns` — `RAIL_WIDTH` and
## `INSPECTOR_WIDTH` are floors, not widths — so a band computed from the constants would have been
## the same class of mistake as the offsets it replaces, just further from the edge. `_fit_columns`
## calls this again for that reason.
##
## The inspector's left edge is taken only when it is VISIBLE. In Airframe it is hidden and the room
## owns that space, but Airframe also forbids the tray outright, so the branch matters for the one
## case that is neither: a system whose inspector has been retracted with the tray still up.
func _overlay_band() -> Rect2:
	var left := _rail_glass.offset_right + CLUSTER_MARGIN if _rail_glass != null \
		and _rail_glass.visible else CLUSTER_MARGIN
	var right := size.x + _inspector.offset_left - CLUSTER_MARGIN if _inspector != null \
		and _inspector.visible else size.x - CLUSTER_MARGIN
	var top := CLUSTER_MARGIN + TOP_BAR_HEIGHT + LothalTheme.SPACE_2
	var bottom := size.y - BOTTOM_KEEPOUT
	return Rect2(Vector2(left, top), Vector2(maxf(right - left, 0.0), maxf(bottom - top, 0.0)))


## Puts each visible card where the tray says it goes.
##
## Called on every event that can change the band — a system change, a room change, a window
## resize, a column re-fit — because the band is a function of the chrome and the chrome moves.
func _layout_overlays() -> void:
	var showing: Array[String] = []
	for entry in OverlayTray.ENTRIES:
		var id := str(entry["id"])
		if _overlays.has(id) and (_overlays[id] as Control).visible:
			showing.append(id)
	var rects := OverlayTray.layout(_overlay_band(), showing.size())
	for index in showing.size():
		var card: Control = _overlays[showing[index]]
		if index >= rects.size():
			# Beyond capacity. Hidden rather than drawn somewhere it does not fit — the chooser
			# refuses to tick past capacity, so this is the window having SHRUNK under a tray that
			# already fitted, and a card half under the inspector is worse than a card absent.
			card.visible = false
			continue
		var rect: Rect2 = rects[index]
		card.offset_left = rect.position.x
		card.offset_top = rect.position.y
		card.offset_right = rect.end.x
		card.offset_bottom = rect.end.y


## Shows or hides the chosen overlays, refilling them from the CURRENT build on the way up.
##
## Refilled on show rather than kept live, because a BEMT solve is not free and an overlay nobody
## is looking at must not cost the rails a solve per click. Everything that changes the aircraft
## already ends in `_refresh_status`, which refreshes those that are up — so the chart a builder is
## looking at follows the rail, and the chart nobody is looking at costs nothing.
##
## Public for the same reason `set_blade_room_open` is: it is what a test and the capture tooling
## drive, rather than a click at a coordinate. The name is P10e's and is kept so the capture script
## keeps working; what it toggles is now the tray rather than one chart.
func set_thrust_overlay_visible(shown: bool) -> void:
	if _overlays_button != null:
		_overlays_button.button_pressed = shown
	_sync_thrust_overlay()


## Puts the tray where the toggle and the screen together say it belongs.
##
## TAKES NO ARGUMENT, and that is the fix for the defect that let five Propulsion charts float over
## the Airframe room. It used to take an `allowed` bool that each of three callers computed for
## itself, and `_select_system` — the caller that hides the tool cluster for Airframe — never called
## it at all. The state is read here instead, through `OverlayTray.allowed`, so a caller cannot omit
## a term it does not pass and a fourth retraction path gets the rule for free.
func _sync_thrust_overlay() -> void:
	if _overlays.is_empty():
		return
	var allowed := OverlayTray.allowed(
		rooms == null or rooms.showing_lab(),
		_blade_room != null and _blade_room.visible,
		_focused_system_covers_viewport())
	var want: bool = allowed and _overlays_button != null and _overlays_button.button_pressed
	if want:
		_refill_thrust_overlay()
	for entry in OverlayTray.ENTRIES:
		var id := str(entry["id"])
		(_overlays[id] as Control).visible = want and _chosen_overlays.has(id)
	_layout_overlays()


## Airframe, and the reason it is asked as a question about the SYSTEM rather than by name at the
## call site: the plan editor takes the whole viewport, so a chart floating over it is a chart about
## a drone the builder cannot see. Any future system that owns the viewport answers true here and
## needs no second edit.
func _focused_system_covers_viewport() -> bool:
	var system: Dictionary = SYSTEMS[_focused_index]
	return _is_modelled(system) and str(system["name"]) == "Airframe"


func _refill_thrust_overlay() -> void:
	if _overlays.is_empty():
		return
	# `container == null` is the empty state — no drone, so no propeller, so no distribution. The
	# overlays say so in words rather than drawing a flat line, which would be a claim about a
	# blade that is not fitted.
	var build: Build = null if container == null or lab == null else lab.current_build()
	for entry in OverlayTray.ENTRIES:
		_overlays[str(entry["id"])].adopt(build)


## The chooser behind the chevron: the five by name, ticked or not.
##
## Rebuilt on every open rather than kept in step, because what it must show is the CURRENT band's
## capacity as well as the current ticks — and the band changes with the window, which nothing
## notifies this menu about. Five items is cheap enough that a rebuild is simpler than a
## subscription, and a menu that disagreed with the tray would be worse than either.
func _populate_overlay_menu() -> void:
	if _overlays_menu_button == null:
		return
	var popup := _overlays_menu_button.get_popup()
	popup.clear()
	var fits := OverlayTray.capacity(_overlay_band())
	for index in OverlayTray.ENTRIES.size():
		var entry: Dictionary = OverlayTray.ENTRIES[index]
		var id := str(entry["id"])
		popup.add_check_item(str(entry["title"]), index)
		popup.set_item_checked(index, _chosen_overlays.has(id))
		# Greyed rather than hidden when the window has no room for another, and the SAME treatment
		# an unmodelled system gets in the dropdown, for the same reason: a builder who cannot see
		# that a fifth chart exists cannot know to widen the window for it. Ticked items stay
		# enabled so there is always a way back down.
		if not _chosen_overlays.has(id) and _chosen_overlays.size() >= fits:
			popup.set_item_disabled(index, true)
			popup.set_item_tooltip(index, OverlayTray.refusal(_overlay_band()))


## Ticks or unticks one chart, and puts the tray up if it was down.
##
## Choosing a chart from a menu is an unambiguous request to see it, so it turns the toggle on
## rather than quietly changing what a hidden tray would contain — the "the toggle is on and the
## overlay is up cannot disagree" rule, in the one direction the toggle does not drive.
func _on_overlay_chosen(index: int) -> void:
	var id := str((OverlayTray.ENTRIES[index] as Dictionary)["id"])
	if _chosen_overlays.has(id):
		_chosen_overlays.erase(id)
	elif _chosen_overlays.size() >= OverlayTray.capacity(_overlay_band()):
		# Unreachable through the menu, which greys the item — reachable if this is ever called by
		# anything else. It refuses and says why, rather than accepting a card `_layout_overlays`
		# would then have to hide.
		if _status_label != null:
			_status_label.text = OverlayTray.refusal(_overlay_band())
		return
	else:
		_chosen_overlays.append(id)
		if _overlays_button != null:
			_overlays_button.button_pressed = true
	_sync_thrust_overlay()

## The thrust stand, opened from the Motor inspector — P10f.
##
## It goes through the SAME `_open_room` every other room goes through, rather than constructing a
## BenchScreen here. That is the whole content of "the room lifecycle is still RoomHost's": the
## bench is freed on the way out, the chrome retracts through `_on_room_changed`, and "no room is
## left running" is one object's guarantee and not two. A second construction path would be a
## second Powertrain that could be left turning behind a screen nobody is looking at.
func _on_thrust_bench_requested() -> void:
	_open_room("bench")


## The propulsion exports. Both land in the same `user://exports` folder `FrameWorkbench` writes
## to and both open it afterwards, on that room's own argument: a file you cannot find has not been
## exported. The path is in the status line too, because `OS.shell_open` does nothing headless.
func _on_mount_stl_requested(motor: Dictionary) -> void:
	if container == null:
		return
	# The stack on the AIRCRAFT, not a fresh one built from the same parts. It already carries the
	# builder's assembly tweaks — the pad thickness and the shim stack — and rebuilding it here
	# would be a second construction that could silently disagree with the one on screen about
	# exactly the two numbers a fit check is asked about.
	var mesh: MotorMesh = lab.airframe.motor_meshes.get(MotorLayout.MOTOR_NAMES[0])
	if mesh == null:
		return
	var solid_name := _safe_export_name(String(motor.get("part_id", "motor")) + "-mount")
	var path := "%s/%s.stl" % [FrameWorkbench.EXPORT_DIRECTORY, solid_name]
	DirAccess.make_dir_recursive_absolute(FrameWorkbench.EXPORT_DIRECTORY)
	_report_export(PropulsionExport.write_mount_stack(mesh, solid_name, path), path)


func _on_guard_stl_requested(guard_id: String, prop_tip_radius_m: float) -> void:
	if guard_id == "":
		return
	var guard := lab.catalog.get_part(guard_id)
	var solid_name := _safe_export_name(guard_id)
	var path := "%s/%s.stl" % [FrameWorkbench.EXPORT_DIRECTORY, solid_name]
	DirAccess.make_dir_recursive_absolute(FrameWorkbench.EXPORT_DIRECTORY)
	_report_export(PropulsionExport.write_guard(guard, prop_tip_radius_m, path), path)


## Says what happened, and says it the way `StlWriter` said it. A refusal names the part and the
## reason — "the surface is not closed", "the solid is inside out" — rather than "export failed",
## because the first is something a builder can report and the second is not.
func _report_export(result: Dictionary, path: String) -> void:
	if _status_label == null:
		return
	if bool(result["ok"]):
		_status_label.text = "Wrote %s" % ProjectSettings.globalize_path(path)
		OS.shell_open(ProjectSettings.globalize_path(FrameWorkbench.EXPORT_DIRECTORY))
	else:
		_status_label.text = "NOT EXPORTED — %s" % String(result["reason"])


static func _safe_export_name(text: String) -> String:
	var out := ""
	for index in text.length():
		var character := text[index]
		out += character if character.is_valid_identifier() or character.is_valid_int() \
			or character == "-" else "_"
	return "part" if out.is_empty() else out


## What the top strip's door says for a system, or "" for a system that has none.
##
## A LOOKUP ON THE SYSTEM rather than an `if name == "Propulsion"` at the call site, because the
## next system to grow a room — Power has a pack bench, Config has nothing yet — must be one entry
## here and not a second branch somewhere else. The empty string is the answer for the other eight,
## including Airframe: Airframe's room opens WITH the system, and a door to a room you are already
## standing in is a button that does nothing.
##
## Static so it can be checked without a shell. That is not a nicety in this file — `GlassShell`
## needs a tree, a frame and a catalog before any of it runs, so a rule left inside an instance
## method is a rule no headless test can reach, which is how the missing overlay retraction stayed
## invisible until somebody opened the app.
static func room_door_label(system: Dictionary) -> String:
	if not _is_modelled(system):
		return ""
	match str(system["name"]):
		"Propulsion": return "Design blade…"
		_: return ""


## Opens the focused system's room on the part the RAIL has selected.
##
## `propeller_picker.selected_part()` rather than a lookup by id, because it is the same record the
## Prop panel renders and the same one its own button emits — one definition of "the blade being
## looked at", so the two doors cannot open on different blades.
func _on_room_door_pressed() -> void:
	if lab == null:
		return
	_on_design_blade_requested(lab.propeller_picker.selected_part())


func _on_design_blade_requested(prop: Dictionary) -> void:
	var part_id := str(prop.get("part_id", ""))
	if part_id != "":
		_blade_room.open_preset(part_id)
	set_blade_room_open(true)


## Opens or closes the blade designer, and takes the same three things away from the viewport that
## the Airframe room does: the 3D world (switched OFF rather than covered — a viewport nobody can
## see should not be rendering), the viewport tools that act on a model the room is over, and the
## rail and inspector columns whose space the room needs.
##
## Public because it is what a test drives, and what the capture tooling drives, rather than
## synthesising a click on a button whose position is a layout decision.
func set_blade_room_open(open: bool) -> void:
	if _blade_room == null:
		return
	_blade_room.visible = open
	_blade_room_close_glass.visible = open
	_rail_glass.visible = not open and _rail_glass.visible
	_tools_glass.visible = not open and _tools_glass.visible
	# The overlay retracts with the tools, and comes back if the toggle was left on. The room
	# covers the viewport it draws over, and a chart floating on top of the blade designer would be
	# describing the aircraft rather than the blade being drawn. Coming back REFILLED is the point
	# of routing this through `_sync_thrust_overlay`: the blade you just published is the blade the
	# curve should be about the moment the room closes.
	_sync_thrust_overlay()
	_inspector.visible = not open and _inspector.visible
	var viewport_container := lab.viewport().get_parent()
	if viewport_container is Control:
		(viewport_container as Control).visible = not open
	# Closing puts back exactly what the focused system asks for, rather than guessing — the same
	# reason `_show_project` re-runs the selection instead of restoring what it remembers.
	if not open:
		_select_system(_focused_index)


func _on_frame_edited(document: AirframeDocument) -> void:
	lab.frame_document = document
	# ONLY WHEN SOMEBODY CAN SEE THEM. The room's own drawer renders the same four panels against
	# the same document, and in Airframe the shell's inspector is hidden — so rendering these too
	# would be four tab-fulls of rows rebuilt on every mouse motion of a vertex drag, for text that
	# is not on screen. They stay wired for every other route into this signal.
	# `_inspector == null` is the room being CONSTRUCTED: the workbench opens a frame in its own
	# constructor, which publishes an edit before the shell's later clusters exist. Skipping is
	# right in both cases — `_select_system` renders the panels when a system is actually chosen.
	if _inspector == null or not _inspector.visible:
		return
	lab.structure_details.render(document)
	lab.arms_details.render(document)
	lab.fasteners_details.render(document)
	lab.layout_details.render(document)
	# The rows just changed, so the width they want just changed with them. Deferred because a
	# Control's combined minimum size is not up to date until the layout pass after the labels were
	# set — measuring here would size the panel to the text it held a moment ago.
	_fit_columns.call_deferred()


## The widest that any of THIS SYSTEM'S inspector tabs wants to be.
##
## Two things this has to get right, and the first version got neither.
##
## **Why it asks the panels rather than the container.** `get_combined_minimum_size()` on the
## TabContainer is no longer enough: the spec panels can now scroll horizontally, and a
## ScrollContainer deliberately stops claiming its child's width once it can scroll it. That is the
## behaviour that stops a long value running off the window, and its cost is that the tab no longer
## ASKS for the width its rows need. So the rows are asked directly.
##
## **Why it measures every tab of the system and not the visible one.** In a TabContainer exactly
## one child is visible — the tab in front — so filtering on `visible` sizes the column to whichever
## tab happens to be open. Airframe's four tabs want 446, 515, 540 and 561 px; sized to Structure at
## 446, clicking Arms or Layout clipped every value on the right, which is precisely the fault this
## function exists to fix, moved one click away. Measuring all four also means the column does not
## CHANGE WIDTH as you tab across it, which would make the canvas beside it jump for no reason the
## builder can see.
func _inspector_content_width(titles: Array) -> float:
	var widest := lab.panels.get_combined_minimum_size().x
	for child in lab.panels.get_children():
		if child is SpecPanel and titles.has(str(child.name)):
			widest = maxf(widest, (child as SpecPanel).content_width())
	return widest


## The panel titles the focused system routes to. Empty for an unmodelled system, which shows a stub
## instead — and a stub is sized by its own text, not by a spec grid.
func _focused_panel_titles() -> Array:
	if _focused_index < 0 or _focused_index >= SYSTEMS.size():
		return []
	return SYSTEMS[_focused_index].get("panels", [])


func _build_inspector() -> void:
	_inspector = _glass_panel()
	_inspector.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_inspector.anchor_left = 1.0
	_inspector.anchor_right = 1.0
	_inspector.anchor_bottom = 1.0
	_inspector.offset_left = -(INSPECTOR_WIDTH + CLUSTER_MARGIN)
	_inspector.offset_top = CLUSTER_MARGIN + TOP_BAR_HEIGHT + LothalTheme.SPACE_2
	_inspector.offset_right = -CLUSTER_MARGIN
	_inspector.offset_bottom = -BOTTOM_KEEPOUT
	add_child(_inspector)

	_inspector_stub = SystemStub.new(false)
	_inspector_stub.visible = false
	_inspector.add_child(_inspector_stub)


## The panel that replaces the whole workspace after a Delete.
##
## Two buttons and the project chip. The chip is the real escape hatch — New, Open, Reveal and
## RECENT all live there, and this panel's buttons are the same two actions one click closer. It
## is deliberately spare: the state after delete is "there is no drone", and a screen full of
## chrome describing nothing would be the app pretending otherwise.
func _build_empty_state() -> void:
	_empty_state = Control.new()
	_empty_state.set_anchors_preset(Control.PRESET_FULL_RECT)
	_empty_state.visible = false
	add_child(_empty_state)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_empty_state.add_child(centre)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", LothalTheme.SPACE_3)
	centre.add_child(box)

	var title := Label.new()
	title.text = "No drone open"
	title.theme_type_variation = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var hint := Label.new()
	hint.text = ("You deleted the drone you were on. New starts a fresh build; Open finds one you "
		+ "saved. Your recent drones are in the menu at the top left.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.theme_type_variation = "MutedLabel"
	hint.custom_minimum_size = Vector2(420, 0)
	box.add_child(hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	box.add_child(row)

	var new_button := Button.new()
	new_button.text = "New drone"
	new_button.pressed.connect(func() -> void: adopt(ProjectLibrary.starting_project()))
	row.add_child(new_button)

	var open_button := Button.new()
	open_button.text = "Open…"
	open_button.pressed.connect(func() -> void: _open_dialog.popup_centered_ratio(0.6))
	row.add_child(open_button)


## Bottom left: the tools, the live status, and the completeness ring.
##
## The four tools are drawn and disabled. That is the honest state — each is a feature, and §5's
## argument is that they arrive as OVERLAYS rather than as rooms. Drawing them now is what makes
## that claim checkable: if four disabled buttons already crowd this corner, the overlay idea has a
## problem worth knowing about before four features are built on top of it.
func _build_bottom_left_cluster() -> void:
	var glass := _glass_panel()
	glass.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	glass.anchor_top = 1.0
	glass.anchor_bottom = 1.0
	glass.offset_left = CLUSTER_MARGIN
	glass.offset_top = -(BOTTOM_KEEPOUT - CLUSTER_MARGIN)
	glass.offset_bottom = -CLUSTER_MARGIN
	add_child(glass)
	_tools_glass = glass

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	glass.add_child(row)

	for tool_name in ["Overlays", "Explode", "X-ray", "Measure"]:
		var button := Button.new()
		button.text = tool_name
		button.disabled = true
		button.custom_minimum_size = Vector2(0, 28)
		button.tooltip_text = "%s is a frame slot — no overlay behind it yet." % tool_name
		row.add_child(button)
		# THE FIRST BUTTON NOW HAS SOMETHING BEHIND IT (P10e). Overlays is a toggle rather than a
		# door: it puts a chart over the viewport and takes it away again, and nothing else on
		# screen moves. That is the whole of the "an overlay is not a room" claim this corner was
		# drawn early to test, now carrying one real feature instead of four slots.
		#
		# The other three stay disabled and keep their tooltip. Turning them on together would
		# have made the corner a menu of promises again.
		if tool_name == "Overlays":
			button.disabled = false
			button.toggle_mode = true
			button.button_pressed = false
			button.tooltip_text = ("Analysis charts over the Lab. The chevron chooses which — "
				+ "five exist and the window decides how many fit at once.")
			button.toggled.connect(set_thrust_overlay_visible)
			_overlays_button = button

			# The chooser. A separate control from the toggle because they are two actions, and
			# because the alternative shipped: five charts up at once, laid out for a screen nobody
			# has, two of them under the inspector. Which charts is now a decision the builder makes
			# instead of one the window makes badly.
			#
			# `about_to_popup` rather than a rebuild on every tick, because the menu has to show the
			# CURRENT band's capacity and nothing notifies it of a window resize.
			var chooser := MenuButton.new()
			chooser.text = "▾"
			chooser.flat = false
			chooser.custom_minimum_size = Vector2(0, 28)
			chooser.tooltip_text = "Choose which analysis charts are up."
			var popup := chooser.get_popup()
			popup.id_pressed.connect(_on_overlay_chosen)
			popup.about_to_popup.connect(_populate_overlay_menu)
			row.add_child(chooser)
			_overlays_menu_button = chooser

	row.add_child(VSeparator.new())

	_status_label = Label.new()
	_status_label.theme_type_variation = "SmallLabel"
	row.add_child(_status_label)

	_ring = CompletenessRing.new()
	row.add_child(_ring)


## The bar that says a newer Lothal exists, and the link out to us.
##
## Both come straight from the old shell, and both ride the toggle's CanvasLayer for the reason the
## toggle does: Sim's HUD is on a layer of its own and would draw over anything in the ordinary
## tree. An update bar that only appeared in the garage would be a bar most people never see.
##
## Not built at all in Store builds. The bar's only action is to open the dl.meetdev.in download
## page, and an app distributed through the Microsoft Store that points its users at an installer
## from somewhere else fails certification — Store copies update through the Store, so the bar would
## also be offering a route that is simply wrong for that install. The `store` feature comes from
## the "Windows Store" export preset's custom_features, so it is false in the editor and in every
## direct-download build.
func _build_update_notice() -> void:
	if OS.has_feature("store"):
		return
	var layer := CanvasLayer.new()
	layer.layer = TOGGLE_LAYER
	add_child(layer)

	var notice := UpdateNotice.new(LothalVersion.MANIFEST_URL)
	notice.theme = LothalTheme.get_theme()
	notice.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	notice.anchor_top = 1.0
	notice.anchor_right = 1.0
	notice.anchor_bottom = 1.0
	notice.offset_top = -UpdateNotice.BAR_HEIGHT
	layer.add_child(notice)


## Bottom right: Lab / Sim. Two states, nothing else (§5).
##
## **On a CanvasLayer, and that is not a detail — it is the way back.** Sim puts its HUD and its
## build panel on a CanvasLayer of its own, which draws over everything in the ordinary tree. The
## first working version of this toggle was an ordinary Control, so the moment it took you to the
## field it disappeared underneath Sim's HUD and the app had no way back to the garage short of
## quitting. The old shell already knew this — it is why the tab bar rode `layer = 10` — and the
## knowledge had to travel with the control that replaced it.
##
## The other three clusters stay in the ordinary tree deliberately. They are retracted in Sim
## anyway, so nothing of theirs is ever underneath a HUD, and a Control inside the shell's own tree
## inherits its theme and its layout without a second root to keep in step.
##
## **Live.** The door is RoomHost's, not this shell's — these two buttons ask, and the retraction of
## the chrome that follows is `_on_room_changed`. That split is what lets the toggle be real without
## this file becoming a second owner of "no room is left running".
##
## §5's argument is that Sim is "the same window with the chrome retracted", and the toggle is what
## makes that literally true: the same window, the same viewport position, four clusters that go
## away. A tab in a row of eight could never have expressed it, because a tab bar is chrome that
## stays.
func _build_bottom_right_cluster() -> void:
	var layer := CanvasLayer.new()
	layer.layer = TOGGLE_LAYER
	add_child(layer)

	var glass := _glass_panel()
	_bottom_right_glass = glass
	# The layer is not a Control, so the theme does not reach this panel down the tree the way it
	# reaches the other three. Set here rather than left to inherit, because unthemed is a state a
	# screenshot shows and a test does not.
	glass.theme = LothalTheme.get_theme()
	glass.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	glass.anchor_left = 1.0
	glass.anchor_top = 1.0
	glass.anchor_right = 1.0
	glass.anchor_bottom = 1.0
	glass.offset_left = -292.0 - CLUSTER_MARGIN
	glass.offset_top = -(BOTTOM_KEEPOUT - CLUSTER_MARGIN)
	glass.offset_right = -CLUSTER_MARGIN
	glass.offset_bottom = -CLUSTER_MARGIN
	layer.add_child(glass)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	glass.add_child(row)

	_lab_button = Button.new()
	_lab_button.text = "Lab"
	_lab_button.toggle_mode = true
	_lab_button.button_pressed = true
	_lab_button.custom_minimum_size = Vector2(80, 30)
	_lab_button.tooltip_text = "The garage. Choose parts, assemble, bench, tune."
	_lab_button.pressed.connect(func() -> void: rooms.show_lab())
	row.add_child(_lab_button)

	_sim_button = Button.new()
	_sim_button.text = "Sim"
	_sim_button.toggle_mode = true
	_sim_button.custom_minimum_size = Vector2(80, 30)
	_sim_button.tooltip_text = ("The field. Flies what the garage built, and authors nothing "
		+ "except what the flight actually cost the pack.")
	_sim_button.pressed.connect(func() -> void: rooms.show_sim())
	row.add_child(_sim_button)

	# The six rooms that are neither Lab nor Sim. Beside the toggle rather than inside it, because
	# they are not a third state of the same thing — see RoomMenu for why this is a holding
	# position and what replaces it.
	_room_menu = RoomMenu.new()
	_room_menu.room_chosen.connect(_open_room)
	row.add_child(_room_menu)


## Opens one of the rooms behind the Rooms menu. A match rather than a dictionary of Callables,
## because an id that names no room must be a visible error rather than a menu entry that silently
## does nothing.
func _open_room(room_id: String) -> void:
	match room_id:
		"bench": rooms.show_bench()
		"battery_bench": rooms.show_battery_bench()
		"esc_bench": rooms.show_esc_bench()
		"frame_bench": rooms.show_frame_bench()
		"field_editor": rooms.show_field_editor()
		"studio": rooms.show_studio()
		_: push_error("no such room: %s" % room_id)


## Retracts the chrome for Sim and puts it back for Lab (§5).
##
## Everything except this toggle goes away out at the field: no dropdown, no project chip, no rail,
## no inspector, no tools. **The shape of the screen is what enforces "Sim authors nothing"** — with
## no part picker on screen there is nothing to change a part WITH, so the rule holds by
## construction rather than by discipline (§9). That is the whole reason the retraction is here and
## not a nicety.
##
## Autosave keeps running underneath, and that is not a contradiction: the pack draining is a
## consequence Sim reports, not a decision it authors, and the drone on disk does not change while
## you fly it.
func _on_room_changed() -> void:
	# EVERY room retracts the chrome, not only Sim. A bench, the field editor and Studio each own
	# the whole window the way Sim does, and a rail floating over a thrust stand would be a part
	# picker on a screen where changing a part means nothing — the same authoring-where-you-should-
	# not-be that the retraction exists to make impossible.
	var in_lab := rooms.showing_lab()
	_lab_button.button_pressed = in_lab
	_sim_button.button_pressed = rooms.sim != null

	_top_bar.visible = in_lab
	_tools_glass.visible = in_lab
	# The overlay goes with the tools that switch it on. It draws a chart about the aircraft in
	# the garage, and left up over a bench or the field it would be a chart about a drone that is
	# not the subject of the screen it is floating on.
	_sync_thrust_overlay()
	if in_lab:
		# Re-applies the focused system rather than just showing the two columns, because which of
		# them is visible is a property of the system chosen — an unmodelled system shows stubs, and
		# blindly unhiding here would put a Frame rail up under a dropdown reading "Config".
		_select_system(_focused_index)
	else:
		_rail_glass.visible = false
		_inspector.visible = false
		# The plan canvas goes with them. It is a child of this shell rather than of Lab, so nothing
		# else hides it — and left up it would float a frame you were drawing over the course you
		# are now flying, opaque, on top of the one room that owns the whole window.
		if _workbench != null:
			_workbench.visible = false


# ---------------------------------------------------------------------------
# Selecting a system — the one interaction this shell actually implements
# ---------------------------------------------------------------------------

## Points the whole screen at one system: its rails on the left, its panels on the right, its parts
## lit on the model and everything else dimmed.
##
## The three move together on purpose. §5's claim is that a dropdown can replace a sidebar and a tab
## row at once, and that only holds if choosing a system chooses everything — a dropdown that
## changed the lighting but left the Frame rail up would be a fourth navigation control rather than
## a replacement for three.
func _select_system(index: int) -> void:
	_focused_index = index
	var system: Dictionary = SYSTEMS[index]

	# THE BLADE DESIGNER DOES NOT SURVIVE A SYSTEM CHANGE. It is an overlay over Propulsion, and
	# leaving it up while the builder walked to Power would put a planform editor over a pack they
	# had just asked to look at. Hidden directly rather than through `set_blade_room_open`, because
	# that function ends by calling THIS one and the two would recurse.
	if _blade_room != null:
		_blade_room.visible = false
		_blade_room_close_glass.visible = false
	var modelled := _is_modelled(system)

	# The door into this system's room, if it has one. Hidden rather than disabled for the eight
	# that do not — a greyed "Design blade…" beside a Power dropdown would be a promise about packs
	# that nothing intends to keep, which is a different thing from the greyed dropdown entries,
	# where the greyness IS the message.
	if _room_door != null:
		var label := room_door_label(system)
		_room_door.text = label
		_room_door_glass.visible = label != ""

	# The glass panels themselves are shown here rather than only in `_build_*`, because Sim
	# retracts them — see _on_room_changed. Walking back into the garage has to put back exactly
	# what the chosen system asks for, and the two columns inside them are separate: the panel is
	# the frame, and a stub is what the frame holds for a system with no model.
	var has_rails := _has_rails(system)

	# A modelled system with no rails (Airframe) hides the whole left column — glass and all —
	# rather than floating an empty panel there. An UNMODELLED system still shows it, because that
	# is where its stub lives and the stub is the point.
	_rail_glass.visible = has_rails or not modelled
	_inspector.visible = true
	# THE PLAN EDITOR IS THE AIRFRAME ROOM. Shown for that system and hidden for every other one,
	# because a canvas floating over the Propulsion room would be editing a frame nobody was looking
	# at while covering the model they were.
	var in_airframe := modelled and str(system["name"]) == "Airframe"
	# THE 3D WORLD IS SWITCHED OFF, not merely covered.
	#
	# The workbench is a floating Control over a full-bleed SubViewportContainer, and every pixel of
	# the room the workbench does not paint — its margins, the strip beside the toolbar, the gap
	# above the canvas — was a window onto Lab's turntable. So a builder drawing a frame had another
	# drone's propellers turning behind their own toolbar. Hiding the container is the honest fix
	# rather than painting over it: a viewport nobody can see should not be rendering either, and
	# `UPDATE_WHEN_VISIBLE` means hiding it stops the work as well as the picture.
	var viewport_container := lab.viewport().get_parent()
	if viewport_container is Control:
		(viewport_container as Control).visible = not in_airframe
	# THE INSPECTOR COLUMN IS HANDED TO THE ROOM as well, and this is the second half of the same
	# argument as the viewport. Airframe's numbers now live in the drawer under its own canvas and
	# its controls live in its own right-hand column, so the shell's inspector would be a third
	# column showing the same four tabs — beside a room that already has them, in the space the
	# room's controls need. Every other system keeps it.
	_inspector.visible = not in_airframe
	if _workbench != null:
		_workbench.visible = in_airframe
		if in_airframe:
			# The tabs describe the frame OPEN IN THE EDITOR, not the one fitted to the build. They
			# are usually the same frame; they stop being the same the moment anything is drawn, and
			# an inspector describing the other one would be answering a question nobody asked.
			_on_frame_edited(_workbench.editor.document)
	# The viewport tools — overlays, explode, x-ray, measure — all act on the 3D model, which the
	# plan editor is covering. Hidden here rather than left to click through onto something the
	# builder cannot see.
	_tools_glass.visible = not in_airframe
	# AND THE CHARTS GO WITH THE TOOLS. This line is the defect: the cluster was hidden here and the
	# overlays it toggles were not, so choosing Airframe left five Propulsion charts floating over
	# the frame editor with their own dismiss button off-screen. The other two paths that retract
	# the chrome — `_on_room_changed` and `set_blade_room_open` — both called the sync; this one
	# never did. `_sync_thrust_overlay` now reads the state rather than being told it, so the
	# omission cannot recur silently, but the call still has to be made from the path that changes
	# the state.
	_sync_thrust_overlay()
	lab.rails().visible = modelled and has_rails
	lab.panels.visible = modelled
	_rail_stub.visible = not modelled
	_inspector_stub.visible = not modelled

	if modelled:
		if has_rails:
			_show_only_tabs(lab.rails(), system["rails"])
		_show_only_tabs(lab.panels, system["panels"])
	else:
		_rail_stub.show_system(system)
		_inspector_stub.show_system(system)

	_apply_focus()
	_refresh_status()
	# Which tabs have to fit just changed with the system, so the column's width has to be asked
	# again. Deferred for the same reason it is everywhere else here: a panel that has just been
	# shown has not been laid out yet, and its combined minimum size is still the previous answer.
	_fit_columns.call_deferred()


## Selects a system by its name, keeping the dropdown in step. The seam the capture tool drives, so
## a screenshot goes through the same path a click does rather than a private one beside it.
## Safe to call before the shell is inside the tree: it records the choice on `_focused_index`, and
## `_ready()` re-applies whatever it finds there.
func select_system_by_name(system_name: String) -> bool:
	for i in SYSTEMS.size():
		if str(SYSTEMS[i]["name"]) == system_name:
			_system_dropdown.select(i)
			_select_system(i)
			return true
	return false


## Brings the first tab named in `titles` to the front, then hides every tab not named there.
##
## Hidden rather than removed, which is what keeps LabScreen's `tab_changed → panels.current_tab`
## sync correct: hiding does not renumber the tabs, so index 4 is still ESC on both sides. Removing
## them would renumber one container and not the other, and the two columns would start describing
## different components — the exact bug that sync exists to prevent.
##
## **Unhide, then select, then hide — three passes, and the order is the whole function.**
##
## TabContainer will not hold a selection on a hidden tab and will not hold no selection at all, so
## every intermediate state has to keep one visible selected tab. Two orderings look right and are
## not:
##
## - *Hide, then select.* Hiding the currently selected tab forces TabBar to move the selection
##   itself, and if it has not reached a visible tab yet it tries to deselect. Forbidden, so it
##   prints "Cannot deselect tabs" and the selection ends up wherever the fallback left it.
## - *Select, then hide.* The destination is usually still hidden from the SYSTEM BEFORE THIS ONE —
##   going Airframe → Power means selecting Pack while Pack is hidden — so the assignment does not
##   take, the old tab stays current, and hiding it hits the same wall. This one is worse than the
##   first because it looks like it should work; it was my second wrong fix for this bug.
##
## Unhiding first is what removes the trap: by the time anything is selected the destination is
## visible, and by the time anything is hidden the selection has already left.
static func _show_only_tabs(tabs: TabContainer, titles: Array) -> void:
	var first := -1
	for i in tabs.get_tab_count():
		if titles.has(tabs.get_tab_title(i)):
			tabs.set_tab_hidden(i, false)
			if first < 0:
				first = i
	# Nothing to show. Leave the tabs exactly as it is rather than hiding every tab: an empty
	# TabContainer is the same forbidden deselection by another route, and a system whose tabs are
	# all missing is a mapping bug in SYSTEMS that should be visible, not swallowed.
	if first < 0:
		return
	tabs.current_tab = first
	for i in tabs.get_tab_count():
		if not titles.has(tabs.get_tab_title(i)):
			tabs.set_tab_hidden(i, true)


## Whether a system has anything behind it at all — the test that decides between showing the real
## columns and showing the `soon` stub.
##
## PANELS COUNT, NOT JUST RAILS. It used to be rails alone, which was right while every modelled
## system was a parts picker and is wrong now that Airframe is four inspectors over computed
## geometry with nothing to pick. A system with panels and no rail is fully modelled; it just has
## no shopping list.
static func _is_modelled(system: Dictionary) -> bool:
	return not ((system["rails"] as Array).is_empty() and (system["panels"] as Array).is_empty())


## Whether this system has a parts list on the left. False for Airframe, which hides the rail column
## rather than showing an empty one.
static func _has_rails(system: Dictionary) -> bool:
	return not (system["rails"] as Array).is_empty()


# ---------------------------------------------------------------------------
# System focus — the thing that makes a full-bleed viewport earn its space
# ---------------------------------------------------------------------------

## Fades every mesh that does not belong to the focused system.
##
## Walks the airframe rather than consulting AirframeModel's dictionaries of meshes, because the
## dictionaries hold the roots and the transparency has to reach the GeometryInstance3D leaves — a
## motor is a node with meshes under it, not a mesh. Classification INHERITS DOWNWARDS for the same
## reason: a propeller blade knows nothing about being propulsion, and the node three levels up is
## the one that does. A node that names a system itself overrides what it inherited — which is how
## the two boards inside one `Stack` end up in two systems.
##
## An unmodelled system dims NOTHING rather than dimming everything. A screen where the whole
## aircraft has faded out would read as a rendering fault, and the stub beside it is already saying
## the honest thing.
func _apply_focus() -> void:
	if lab == null or lab.airframe == null:
		return
	var focused := str(SYSTEMS[_focused_index]["name"])
	if not _is_modelled(SYSTEMS[_focused_index]):
		focused = ""
	# Drone is the WHOLE aircraft, so it dims nothing. Dimming everything except the frame while a
	# builder is choosing between fifteen frames would hide the motors and props that make one frame
	# look different from another, which is most of what there is to see at that moment.
	if focused == "Drone":
		focused = ""
	_fade_below(lab.airframe, "", focused)


func _fade_below(node: Node, inherited_system: String, focused: String) -> void:
	# A NODE'S OWN NAME BEATS THE ONE IT INHERITS. See SYSTEM_NODE_PREFIXES: the ESC board and the
	# FC board are two children of one `Stack`, so a rule that stopped at the nearest matching
	# ANCESTOR could never see either of them.
	var own := _system_of_name(node.name)
	var system := own if own != "" else inherited_system
	if node is GeometryInstance3D:
		var owning := system if system != "" else "Airframe"
		(node as GeometryInstance3D).transparency = (
			0.0 if focused == "" or owning == focused else DIM_TRANSPARENCY)
	for child in node.get_children():
		_fade_below(child, system, focused)


## The system a node name belongs to, or "" for a name that names no system — which is most of
## them, and which means "inherit from above, and failing that, Airframe".
static func _system_of_name(node_name: StringName) -> String:
	var text := String(node_name)
	for system in SYSTEM_NODE_PREFIXES:
		for prefix in SYSTEM_NODE_PREFIXES[system]:
			if text.begins_with(String(prefix)):
				return String(system)
	return ""


# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------

## What the bottom-left strip reads: the focused system, and how many systems have been DECIDED.
##
## Decided, not scored. §9 forbids an aggregate quality score and the ring is deliberately "how much
## you have decided", not "how good the drone is" — so this counts slots that hold a choice and says
## nothing whatever about whether the choice is good. A system with no model can never be decided,
## which is why the figure starts at five of nine rather than at zero.
##
## **Today it is constant at five of nine, and that is worth saying rather than hiding.** Every rail
## opens on a selection and none can be cleared, so all five modelled systems are decided from the
## first frame and the arc never moves. I expected Video to make it live — a whoop publishes no
## camera or VTX bay — but the picker keeps its ids regardless of the frame, so `selection()` never
## returns an empty one. Checked, not assumed.
##
## Left in anyway, because the ring is a slot in the frame and a frame is what this file is. What it
## must NOT become is a number that looks live and is not: when the four unmodelled systems arrive
## the arc starts moving on its own, and until then this comment is the honest label.
func _refresh_status() -> void:
	_sync_project()
	if _status_label == null:
		return
	if container == null:
		# With no drone there is nothing decided, and the ring must not read as a score of nothing
		# — an empty arc is the honest rendering of an empty state.
		_status_label.text = "No drone open"
		if _ring != null:
			_ring.fraction = 0.0
			_ring.tooltip_text = "Nothing is open — New or Open a drone."
			_ring.queue_redraw()
		return
	# THE OVERLAY FOLLOWS THE RAIL. Every path that changes the aircraft — a picker, a reload
	# after the blade designer publishes, a project opening — already ends here, so hooking the
	# refill on this one function is what makes "publish a blade next door and watch the curve
	# move" true without a second notification path to keep in step.
	for entry in OverlayTray.ENTRIES:
		var id := str(entry["id"])
		if _overlays.has(id) and (_overlays[id] as Control).visible:
			_refill_thrust_overlay()
			break

	var decided := _decided_count()
	_status_label.text = "%s  ·  %d of %d systems decided" % [
		SYSTEMS[_focused_index]["name"], decided, SYSTEMS.size()]
	if _ring != null:
		_ring.fraction = float(decided) / float(SYSTEMS.size())
		_ring.tooltip_text = (
			"How much of the drone you have decided — not how good it is (§9). "
			+ "The four unmodelled systems can never be decided yet.")
		_ring.queue_redraw()


## Copies the rails' selection into the document.
##
## ONE DIRECTION ONLY, and that is the honest half of the wiring: the rails are still the source of
## truth for what is fitted, and the Project follows them. The other direction — a project OPENING
## and driving the rails — is what New and Open need, and it is why those two entries are greyed
## rather than half-wired. A shell that could load a drone into the pickers would have to own what
## happens to the one already there, and that question belongs with the container.
func _sync_project() -> void:
	if container == null or lab == null:
		return
	var selection := lab.selection()
	for category in selection:
		container.project.parts[category] = str(selection[category])


## Rename is ProjectChip's own; everything else lands here.
func _on_project_action(action_id: String) -> void:
	match action_id:
		"new":
			adopt(ProjectLibrary.starting_project())
		"duplicate":
			adopt(ProjectLibrary.duplicate_of(container.project))
		"open":
			_open_dialog.popup_centered_ratio(0.6)
		"reveal":
			OS.shell_show_in_file_manager(ProjectSettings.globalize_path(
				container.path if container.path != "" else ProjectLibrary.DIR))
		"delete":
			# The container is moved to the app's trash, not unlinked — §10 of the projects design,
			# and the reason there is no confirmation dialog. Nothing replaces it: the app closes
			# the drone and shows the empty state, because a delete that handed you a fresh
			# "Untitled build" in the same second looked exactly like a delete that did nothing.
			var gone := container.path
			if gone != "":
				ProjectLibrary.delete(gone)
				settings.forget_project(gone)
				settings.save()
			_clear_project()
		"rename":
			pass
		_:
			push_warning("project action '%s' is not built yet" % action_id)


## Takes on a new drone: gives it a home, fits it on the rails, and points the chip at it.
##
## A new project is WRITTEN BEFORE IT IS SHOWN. §5 removed the save button, and a document with no
## path cannot autosave — so a new drone that waited for a save would be the one document in the
## app whose work is lost by default, which is exactly what the save button used to prevent.
func adopt(project: Project) -> Array:
	ProjectLibrary.ensure_dir()
	container = ProjectContainer.make(project)
	container.write(ProjectLibrary.path_for(project))
	var missing := apply_project(project)
	chip.set_project(project, container.path)
	_show_project()
	_remember(container.path)
	_refresh_status()
	return missing


## Opens a container from anywhere on disk. Returns the categories that could not be fitted.
##
## A file that will not open leaves the drone on screen exactly as it was. The alternative — half
## adopting it and leaving the rails on the previous aircraft — would put the chip's name and the
## model on screen out of step, which is the state a builder cannot detect and cannot recover from.
func open_project(path: String) -> Array:
	var opened := ProjectContainer.open(path)
	if opened == null:
		push_warning("%s would not open" % path)
		return [{"category": "", "part_id": path}]
	container = opened
	var missing := apply_project(opened.project)
	chip.set_project(opened.project, opened.path)
	_show_project()
	_remember(opened.path)
	_refresh_status()
	return missing


## Fits a project's parts on the rails. Whatever could not be fitted comes back named — see
## LabScreen.apply_selection, which refuses to substitute.
func apply_project(project: Project) -> Array:
	if lab == null:
		return []
	return lab.apply_selection(project.parts)


func _remember(path: String) -> void:
	settings.remember_project(path)
	settings.save()
	chip.set_recent_paths(settings.existing_recent_projects())


## Closes the current drone without opening another — the state after Delete.
##
## The chip reads "No drone" and the menu's project-dependent entries grey, and the workspace is
## hidden behind the empty-state panel. Autosave has nothing to write (container is null), so this
## is the one state in the app that cannot create a project on its own — which is the entire point.
func _clear_project() -> void:
	container = null
	chip.set_project(null, "")
	_show_empty_state()
	_refresh_status()


## Shows the "No drone open" panel and hides everything the shell floats over the model — the
## dropdown, the rail, the inspector, the plan canvas, the tools, the Lab/Sim toggle. Only the chip
## stays: its New, Open, Reveal and RECENT are the way out.
func _show_empty_state() -> void:
	_empty_state.visible = true
	_dropdown_glass.visible = false
	_rail_glass.visible = false
	_inspector.visible = false
	if _workbench != null:
		_workbench.visible = false
	if _blade_room != null:
		_blade_room.visible = false
		_blade_room_close_glass.visible = false
	_tools_glass.visible = false
	if _bottom_right_glass != null:
		_bottom_right_glass.visible = false
	var viewport_container := lab.viewport().get_parent()
	if viewport_container is Control:
		(viewport_container as Control).visible = false


## Undoes the empty state — every New and Open lands here. The per-system visibility of the columns
## and the model is `_select_system`'s job, so this re-runs it against the focused system rather
## than guessing at what to show.
func _show_project() -> void:
	_empty_state.visible = false
	_dropdown_glass.visible = true
	if _bottom_right_glass != null:
		_bottom_right_glass.visible = true
	_select_system(_focused_index)


## The autosave tick. Asks, rather than writes: an unchanged project costs one JSON stringify.
func _on_autosave_tick() -> void:
	if container == null or container.path == "":
		return
	_sync_project()
	if container.has_unsaved_changes():
		container.write()
	chip.refresh()


func _decided_count() -> int:
	if lab == null:
		return 0
	var selection := lab.selection()
	var count := 0
	for system in SYSTEMS:
		var keys: Array = system["decided_by"]
		if keys.is_empty():
			continue
		var all_chosen := true
		for key in keys:
			if str(selection.get(key, "")) == "":
				all_chosen = false
		if all_chosen:
			count += 1
	return count


# ---------------------------------------------------------------------------
# Glass
# ---------------------------------------------------------------------------

## A floating panel. One helper rather than a theme type variation, because glass is a property of
## being a FLOATING CLUSTER in this shell and not of being a PanelContainer — the ordinary panels
## inside the inspector must stay opaque, or text lands on text.
func _glass_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _glass_stylebox())
	return panel


## The glass look on its own, for a Control that already exists and only wants the surface — the
## project chip is its own class, so it cannot be a PanelContainer this file made.
##
## Split out rather than letting a caller build a throwaway panel and steal its stylebox: an
## orphan Control never added to the tree is never freed, and four leaked ObjectDB instances at
## exit is exactly what that looked like.
static func _glass_stylebox() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(
		LothalTheme.PANEL_BG.r, LothalTheme.PANEL_BG.g, LothalTheme.PANEL_BG.b, GLASS_ALPHA)
	box.border_color = Color(
		LothalTheme.BORDER.r, LothalTheme.BORDER.g, LothalTheme.BORDER.b, 0.9)
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(LothalTheme.SPACE_2)
	return box


## What stands in for a system Lothal does not model yet.
##
## It says three things: what belongs here, why there is nothing behind it, and where that list came
## from. The third is the one that matters and is the reason this is not lorem ipsum — every item
## below is quoted from a document in landingpage/docs/lothal, so a stub can be checked rather than
## believed, and nobody later has to work out whether "prop guards" was researched or invented.
##
## §9: never invent a spec to unlock a feature. A stub that listed plausible masses for parts nobody
## has weighed would be exactly that, so these carry NO numbers at all.
class SystemStub extends VBoxContainer:
	## The rail side is the short form — a title and the list. The inspector side carries the
	## reasoning. Splitting them this way keeps each column doing on a stub what it does on a real
	## system: the rail is what you could pick, the inspector is what it means.
	var _rail_side: bool

	var _title: Label
	var _body: VBoxContainer

	func _init(p_rail_side: bool) -> void:
		_rail_side = p_rail_side
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_theme_constant_override("separation", LothalTheme.SPACE_3)

		_title = Label.new()
		_title.theme_type_variation = "TitleLabel"
		add_child(_title)

		var tag := Label.new()
		tag.text = "soon — nothing behind this yet"
		tag.theme_type_variation = "WarnLabel"
		add_child(tag)

		_body = VBoxContainer.new()
		add_child(_body)

	func show_system(system: Dictionary) -> void:
		_title.text = str(system["name"])
		for child in _body.get_children():
			_body.remove_child(child)
			child.free()

		var stub: Dictionary = system.get("stub", {})
		if stub.is_empty():
			return

		if _rail_side:
			var heading := Label.new()
			heading.text = "WHAT BELONGS HERE"
			heading.theme_type_variation = "SmallLabel"
			_body.add_child(heading)
			for item in stub["items"]:
				var line := Label.new()
				line.text = "·  %s" % item
				_body.add_child(line)
			return

		var why := Label.new()
		why.text = str(stub["why"])
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.theme_type_variation = "MutedLabel"
		_body.add_child(why)

		var source := Label.new()
		source.text = "Source: %s" % stub["source"]
		source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		source.theme_type_variation = "SmallLabel"
		_body.add_child(source)


## The completeness ring: how much of the drone you have DECIDED, drawn as an arc.
##
## An arc rather than a number or a bar, and this is the one piece of visual grammar here worth
## defending. §9 forbids an aggregate quality score, and the risk with any single figure is that it
## reads as one — "7/10" is a grade whatever the label says. A ring with no number in it can only be
## read as a fraction of a whole, which is exactly and only what it means.
class CompletenessRing extends Control:
	var fraction := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(34, 34)

	func _draw() -> void:
		var centre := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 3.0
		draw_arc(centre, radius, 0.0, TAU, 48, LothalTheme.BORDER, 3.0, true)
		if fraction <= 0.0:
			return
		# From twelve o'clock, clockwise — the direction a fraction of a whole is read in.
		draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + TAU * fraction, 48,
			LothalTheme.ACCENT, 3.0, true)
