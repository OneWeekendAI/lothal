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
## QC4 (§5): ~320 px, down from 348. It can narrow because it stops repeating what the rail shows
## beside it — the part's identity is the panel's header, not a row of it.
##
## STILL A FLOOR AND NOT A WIDTH. `_fit_columns` measures the panels and takes the larger, so on
## every system whose rows already want more than this the number below changes nothing at all —
## including the one `tests/test_shell_layout.gd` measures the overlay tray's band against. That is
## why this edit could be made without moving the band, and it was verified by measuring rather
## than by reasoning.
const INSPECTOR_WIDTH := 320.0
## The most of the window the inspector may claim, however long its rows get. Under half: past that
## the thing being inspected has less room than the description of it, which inverts what a
## full-bleed viewport is for. 0.45 rather than 0.42 because the widest tab in the app — Layout, at
## 561 px — lands just inside it on a 1333 px window, and a ceiling that cut the widest real panel
## by a handful of pixels would be a bound chosen to be tidy rather than to be right.
const MAX_INSPECTOR_FRACTION := 0.45
## How far the floating columns stop short of the bottom, so they never collide with the
## bottom-left tool cluster or the bottom-right toggle.
const BOTTOM_KEEPOUT := 76.0

## How far the summoned finder keeps from the dock above which it must fit, and from the top of the
## window. See `_fit_finder`.
const FINDER_EDGE_GAP := 12.0

## Which CanvasLayer the Lab/Sim toggle rides. Ten, matching the old tab bar, and for the identical
## reason: Sim's HUD is on a layer of its own and draws straight over anything in the ordinary tree.
## The toggle is the ONLY way out of the field, so a toggle underneath the HUD is an app you cannot
## leave. See _build_dock.
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

## The ten systems of §5, in order, each carrying the rails and panels it owns.
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
## Whether ten collapses to six is open question §8.1 and is NOT settled here. Ten is what the
## design says, so ten is what the frame is drawn with — the point of building the shape is to
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
		#
		# `receiver` ARRIVED THE SAME WAY THE ESC LEFT, and the same two halves had to move
		# together (C3). The rail came with it: `Link` is the receiver, the GPS and the buzzer —
		# the aircraft's connection to the outside — and it is a second ElectronicsPicker rather
		# than a share of Video's, so there is no longer any bay Control decides and Video renders.
		# `decided_by` gains `receiver` ONLY here: Video never named it, so the ring has always
		# counted it once, and this moves the credit rather than adding it.
		"name": "Control",
		"rails": ["FC", "Link"],
		"panels": ["FC", "Link", "Tune"],
		"decided_by": ["flight_controller", "receiver"],
	},
	{
		# THREE BAYS, AND THEY ARE ALL VIDEO'S. Until C3 this rail carried the receiver too — not
		# as a decision but because one ElectronicsPicker emitted all four bays as one payload and
		# splitting it meant parameterising the picker. It is parameterised now: the picker takes
		# its categories, both rails derive them from `Build.COMPONENT_SYSTEM`, and the receiver is
		# picked under Control on the `Link` rail. `decided_by` is unchanged and always was
		# correct — the receiver was never named here, so no ring arithmetic moves with it.
		#
		# The asymmetry that REMAINS is a different one, and it is the naming §7 records: `antennas`
		# is VTX antennas only, and the receiver's antenna is a string on the receiver entry rather
		# than a part. Left visible rather than papered over.
		#
		# `Camera` is V5's: the uptilt, found where the camera is rather than in Airframe's Fit tab.
		# A panel and no rail, because a mount angle is a setting and not a part to pick.
		"name": "Video",
		"rails": ["Electronics"],
		"panels": ["Camera", "Electronics"],
		"decided_by": ["camera", "vtx"],
	},
	{
		# Printed-room PR0: one panel and no rail. Printed parts are generated from the build, not
		# browsed (plans/2026-09-14-printed-room-design.md §3), so the list sits on the panel beside
		# the fit clearance that shapes every one of them. No `decided_by`: nothing here is a part
		# choice the completeness ring should wait on.
		"name": "Printed",
		"rails": [],
		"panels": ["Print"],
		"decided_by": [],
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
	"Control": ["Stack", "Board_FC", "Component_receiver", "Component_gps", "Component_buzzer"],
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
## QC4's overlay, and the two nodes that make it modal.
##
## `_dim` is added to the tree BEFORE the inspector and `_finder_glass` AFTER the dock, and that
## ordering is the whole of §5's "the inspector is not dimmed with the canvas": a sibling added
## later draws later, so the dim covers the viewport, the rail and the rooms and stops underneath
## the one panel that has to stay readable while a choice is being made.
var _dim: ColorRect
var _finder_glass: PanelContainer
## Rebuilt on every open rather than kept and re-pointed. The finder is derived entirely from the
## rail it is summoned over — category, noun and filter keys all come off that PartPicker — so a
## retained instance would need every one of those swapped, which is a second construction path
## that only runs on the second open.
var _finder: PartFinder
var _inspector_stub: SystemStub
## The drone this shell is describing, and the file it lives in. Its `parts` are kept in step with
## the rails by _sync_project(), and AUTOSAVE_SECONDS later it is on disk.
var container: ProjectContainer
## Where the Printed room's exports are written — the per-part buttons and "Export printed parts…"
## alike (printed-room PR4). A variable so a test can point it at a directory it clears first.
var printed_export_dir: String = FrameWorkbench.EXPORT_DIRECTORY
## What the last whole-room export said, exactly as the status line shows it. For tests.
var last_printed_export_summary := ""
## Whether a successful single-part export opens the exports folder. True for a builder; a test that
## drives the Export buttons turns it off, because the status label exists from `_init` and a suite
## that opens Finder on every run is a suite nobody runs.
var open_folder_after_export := true
## What opening this drone found about its printed parts (printed-room PR5): one finding per part whose
## newest print record no longer matches what the build generates. Empty for a drone that matches.
var printed_divergence: Array = []
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
## THE DOCK — QC3. One centred cluster at the bottom that carries what three separate clusters used
## to: the system dropdown out of the top bar, the bottom-left tools and the bottom-right Lab/Sim.
## See `src/ui/dock.gd` for why it is its own file and where the status readout and the ring went.
var _dock: Dock
## The three members below are no longer three panels — they are the dock's three GROUPS, and they
## keep their old names on purpose. Every retraction path in this file already talks about "the
## tools" and "the Lab/Sim cluster" by these names (`_on_room_changed`, `_select_system`,
## `_set_room_open`, `_show_empty_state`), and each one hides a different subset: Sim takes the
## systems and the tools, Airframe takes the tools alone. Renaming them would have meant re-deciding
## four retraction rules at once in a slice that is about geometry.
var _tools_glass: Control
## The system icons, held so the empty state can hide them while keeping the chip — the two live
## project actions ride the chip, not the systems.
var _dropdown_glass: Control
## The Lab/Sim/Rooms group, held so the empty state can hide it: there is no build to take to
## the field, and a toggle that flies nothing would be a button that lies.
var _bottom_right_glass: Control
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
## The Power room — the harness designer, PW5. An overlay on the same terms as the blade designer:
## Power has two rails and they are still the point, so the room opens on request rather than with
## the system. See `_build_power_room`.
var _power_room: PowerWorkbench

## Every overlay room and the close button that belongs to it, as `{room, close_glass}` rows.
##
## **THIS LIST EXISTS BECAUSE OF W0.7's DEFECT FAMILY.** Three code paths retracted the shell's
## chrome and one of them omitted a term, and the fix there was to remove the argument a caller
## could omit. There are now two overlay rooms and four paths that have to put them away —
## `_select_system`, `_show_empty_state`, `_on_room_changed` and each room's own opener — so the
## same shape would be eight lines that have to agree, written in four places. `_retract_rooms()`
## walks this list instead, which means a THIRD room is one append here and nothing else, and a
## room that is not in the list is a room `tests/test_power_room.gd` names.
var _overlay_rooms: Array[Dictionary] = []

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
## And the Power room's. A second button rather than one that renames itself: the two rooms can
## never be open at once, but a button whose text is the only thing saying which room you are in is
## a button that lies for one frame every time that changes.
var _power_room_close_glass: PanelContainer


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
	_build_power_room()
	_build_thrust_overlay()
	# THE DIM GOES IN HERE, between the canvas and the inspector, and the position IS the rule.
	# §5: the build summary is the consequence of the choice being made, so it stays readable while
	# the choice is made. Godot draws siblings in tree order, so everything added above this line
	# is dimmed by it and everything added below is not.
	_build_dim()
	_build_inspector()
	# Between the inspector and the top cluster, so the chip draws over it but it covers the model
	# and the floating columns. The empty state must never hide the project chip — New and Open are
	# the only way out of it.
	_build_empty_state()
	_build_top_cluster()
	_build_dock()
	# Last, so it is over every piece of chrome in this layer. The dock rides its own CanvasLayer
	# and is therefore still above it, which is correct rather than tolerated: the overlay is 368 px
	# wide and centred, the dock stands in the bottom keepout, and a finder that could cover the way
	# out of the garage would be a modal with no escape that is not a keystroke.
	_build_finder_glass()


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
	#
	# But a NEW drone is only born when there is nothing to come back to. Adopting unconditionally
	# wrote a fresh container on every single launch, so `user://builds` filled with hundreds of
	# untouched "Untitled build N" files and the next default name counted them all — a builder who
	# had saved nothing was shown "Untitled build 422". Reopening the last drone is also what an app
	# with no save button owes a builder: closing it was never a decision to discard it.
	#
	# A recent entry that will not open is skipped rather than fatal, and a shell that resumes
	# nothing falls through to the fresh drone `_init` already made. `open_project` leaves the
	# container untouched when a file is bad, which is what `container.path` is being asked here.
	var resumed := false
	for path in settings.existing_recent_projects():
		open_project(path)
		if container.path == path:
			resumed = true
			break
	if not resumed:
		adopt(container.project)

	# The shell has no signal from Lab to listen to — LabScreen emits none — so it listens to the
	# rails directly. Fine for an experiment, and worth naming as the reason it is not fine
	# permanently: reload_catalog() rebuilds these pickers, and these connections would go with
	# them. A `selection_changed` signal on LabScreen is the real fix when this stops being an
	# experiment.
	for picker in [lab.picker, lab.motor_picker, lab.propeller_picker, lab.battery_picker,
			lab.esc_picker, lab.fc_picker]:
		picker.part_selected.connect(func(_part: Dictionary) -> void: _refresh_status())
	# Both payload rails, by asking rather than by naming one: a bay emptied on either changes what
	# the completeness ring and the status line have to say, and a shell that listened to one of
	# the two would go stale on exactly the three components C3 moved.
	for rail in lab.component_rails():
		rail.components_changed.connect(_refresh_status)

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
	_layout_dock()


# ---------------------------------------------------------------------------
# The clusters
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

	# THE SYSTEM DROPDOWN IS NOT HERE ANY MORE — it is the dock's six icons plus its overflow menu
	# (QC3). The bar keeps the project's identity: the chip, the door into this system's room, and
	# the way out of it. What left was a 180 px control whose whole job was navigation, and
	# navigation is what the dock is.

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
	_blade_room_close_glass = _close_button("Close blade designer",
		func() -> void: set_blade_room_open(false))
	bar.add_child(_blade_room_close_glass)
	_power_room_close_glass = _close_button("Close harness designer",
		func() -> void: set_power_room_open(false))
	bar.add_child(_power_room_close_glass)

	# THE LIST THE RETRACT PATHS WALK, assembled where both halves of both rooms finally exist. A
	# room registered here is a room every path puts away; a room that forgets to register is what
	# `tests/test_power_room.gd` is looking for, and it looks by comparing this list against the
	# overlay rooms the shell actually holds rather than against a second hand-written list.
	_overlay_rooms = [
		{"name": "the blade designer", "room": _blade_room,
			"close_glass": _blade_room_close_glass},
		{"name": "the harness designer", "room": _power_room,
			"close_glass": _power_room_close_glass},
	]


## One glass-backed way out of a room, in the top strip. Two rooms, one shape — see
## `_build_close_door`'s header for why the button is up here rather than over the room.
func _close_button(text: String, action: Callable) -> PanelContainer:
	var close_glass := _glass_panel()
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 28)
	button.pressed.connect(action)
	close_glass.add_child(button)
	close_glass.visible = false
	return close_glass


## Puts EVERY overlay room away, and its way out with it.
##
## The single retraction, called by every path that has to end with no room on screen. W0.7 shipped
## the version of this where each path did it by hand and one path forgot a term; the argument a
## caller could omit was removed there, and here the whole list is removed from the caller's hands.
## It does not touch the rail, the inspector or the tools — those are per-system and
## `_select_system` owns them.
func _retract_rooms() -> void:
	for entry in _overlay_rooms:
		var room: Control = entry["room"]
		var close_glass: Control = entry["close_glass"]
		if room != null:
			room.visible = false
		if close_glass != null:
			close_glass.visible = false


## QC5 (§6): THE COLUMN IS RETIRED, AND THE PICKERS INSIDE IT ARE NOT.
##
## `_rail_glass` still exists and Lab's rail column is still reparented into it, because
## `PartPicker` is the app's only implementation of "fit this part on the live build" —
## `RailFitter._fit` is `rail.select_id()`, the rail emits `part_selected`, LabScreen rebuilds the
## aircraft and the panels re-render. Freeing the pickers would mean writing a second fitting path
## that the status line, the autosave and the 3D model do not hear about, which is the defect
## `rail_fitter.gd`'s header is entirely about.
##
## So the pickers stay ALIVE, IN THE TREE, AND OFF THE SCREEN: they are the model behind the
## finder. `visible` is what QC5 changes, and `_select_system` is the one place that sets it —
## it is false for every system whose shelves the finder can open, which is all of them except
## the two that own an `ElectronicsPicker` (see `_column_rail_titles`).
##
## Alive-and-hidden rather than removed from the tree for a second reason: the authoring dialogs
## are `add_child`ed onto the picker itself (`MotorPicker._open_dialog`), so a picker outside the
## tree is a "New custom motor…" that opens nothing.
##
## The rail's stub half went with the column — see `_build_inspector` and `SystemStub`.
func _build_rail_glass() -> void:
	_rail_glass = _glass_panel()
	_rail_glass.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_rail_glass.anchor_bottom = 1.0
	_rail_glass.offset_left = CLUSTER_MARGIN
	_rail_glass.offset_top = CLUSTER_MARGIN + TOP_BAR_HEIGHT + LothalTheme.SPACE_2
	_rail_glass.offset_right = CLUSTER_MARGIN + RAIL_WIDTH
	_rail_glass.offset_bottom = -BOTTOM_KEEPOUT
	_rail_glass.visible = false
	add_child(_rail_glass)


## Right: the inspector, plus the stub that replaces it for an unmodelled system.
##
## §5 SAYS IT APPEARS ONLY WHEN SOMETHING IS SELECTED, AND SINCE QC4 IT DOES. The paragraph that
## used to stand here argued the opposite — that Lab always has a selection, so the rule belonged
## to some other screen — and that argument was only true because this shell had no way to select
## NOTHING. It has one now: `_focused_index` may be -1, `clear_selection()` puts it there, and
## Escape over the canvas is the builder's route to it. That state is the resting state Quiet
## Canvas is named after: the drone, undimmed, with a dock under it and no panel describing
## anything.
##
## The panel is still CONSTRUCTED unconditionally — it holds Lab's reparented columns, which exist
## from `_ready` whatever is selected. What gates is `visible`, in `_select_system`, which is also
## the one place that knows what "selected" currently means.
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
	lab.print_panel.export_requested.connect(_on_printed_export_requested)
	lab.print_panel.divergence_kept.connect(keep_divergence)
	lab.print_panel.divergence_reprint_requested.connect(reprint_part)


## The harness designer — Power's room, PW5 — built hidden and opened from the Harness panel's own
## door and from the top strip.
##
## AN OVERLAY, on the blade designer's terms and for its reasons: Power has a Pack rail and an ESC
## rail and a builder in Power is usually choosing a pack, not re-gauging phase wire. So the room
## opens on request, sits in the same rect, and retracts through the same list.
##
## It is handed `lab.build_with_open_harness()` at OPEN time rather than at construction, because
## the harness a room edits is the harness of the aircraft currently selected — and at `_init` the
## rails have not chosen anything yet.
func _build_power_room() -> void:
	_power_room = PowerWorkbench.new()
	_power_room.set_anchors_preset(Control.PRESET_FULL_RECT)
	_power_room.offset_left = CLUSTER_MARGIN
	_power_room.offset_right = -CLUSTER_MARGIN
	_power_room.offset_top = TOP_BAR_HEIGHT + CLUSTER_MARGIN
	_power_room.offset_bottom = -BOTTOM_KEEPOUT
	_power_room.visible = false
	add_child(_power_room)

	# THE EDIT HAS TO REACH THE AIRCRAFT. The harness is real mass at real positions, so a main lead
	# that just got 60 mm longer moved the centre of mass and changed what every panel says. This is
	# the same rebuild a part change takes — `LabScreen.refresh_build` — rather than a second path
	# that could fall behind it.
	#
	# It does NOT re-open the room. `refresh_build` makes a new `Build`; handing that back to the
	# room would re-enter `_refresh` and emit again, forever. The room keeps the aircraft it was
	# opened with, and that aircraft carries Lab's own `Harness` object — which is the whole reason
	# `build_with_open_harness` exists.
	_power_room.document_changed.connect(func(_harness: Harness) -> void: lab.refresh_build())

	# THE PACK'S OFFSET IS NOT THIS ROOM'S TO WRITE (PW6). It is one of the assembly tweaks, it is
	# already shown and edited on the Fit panel, and `AssemblyPanel.set_tweak_mm` is the single path
	# a tweak change takes — it snaps to the step, clamps to the range the fitted parts allow, and
	# emits the signal Lab rebuilds and saves on. So the room's slider is routed straight into that
	# path rather than given one of its own; a second writer would be a second place the number
	# lives, and the two would agree until somebody moved the panel's slider.
	_power_room.pack_offset_edited.connect(func(millimetres: float) -> void:
		lab.assembly_panel.set_tweak_mm(AssemblyTweaks.BATTERY_OFFSET, millimetres))

	lab.harness_panel.harness_room_requested.connect(_on_harness_room_requested)


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


func _on_guard_stl_requested(guard_id: String) -> void:
	if guard_id == "":
		return
	var guard := lab.catalog.get_part(guard_id)
	var solid_name := _safe_export_name(guard_id)
	var path := "%s/%s.stl" % [FrameWorkbench.EXPORT_DIRECTORY, solid_name]
	DirAccess.make_dir_recursive_absolute(FrameWorkbench.EXPORT_DIRECTORY)
	_report_export(PropulsionExport.write_guard(guard, path), path)


## The Printed room's Export buttons. Each id routes into the export that already exists for that
## part — the prop guard goes through the same handler Propulsion's own button uses, so there is one
## guard export and two doors to it, never two exports.
func _on_printed_export_requested(part_id: String) -> void:
	if part_id == PrintedParts.PROP_GUARD:
		_on_guard_stl_requested(lab.propeller_details.guard_id())
		return
	# Every generated part goes through the one dispatcher the whole-room export uses, on the build WITH
	# the assembly on it: the camera mount prints at the Camera tilt, which `current_build()` alone lacks.
	var solid := PrintedParts.solid_for(lab.build_with_open_harness(), part_id)
	if not bool(solid["ok"]):
		_report_export({"ok": false, "reason": String(solid["reason"])}, "")
		return
	var solid_name := _safe_export_name(String(solid["solid_name"]))
	var path := printed_export_dir.path_join("%s.stl" % solid_name)
	DirAccess.make_dir_recursive_absolute(printed_export_dir)
	_report_export(StlWriter.write_bodies(solid_name, solid["bodies"], path) if solid.has("bodies")
		else StlWriter.write(solid_name, solid["triangles"], path), path)


## "Export printed parts…" — every part this drone prints, written to the exports folder AND into the
## drone's own file under printed/, each with a print record (printed-room PR4). A refused part is
## named and refuses only itself. The container is written at once when it has a home, so the record of
## a print does not wait for the next autosave; a container with no path (a test's) writes nothing.
func export_printed_parts() -> Dictionary:
	if container == null or lab == null:
		return {}
	_sync_project()
	var result := PrintedExport.export_all(lab.build_with_open_harness(),
		printed_export_dir, container)
	if not (result.get("written", []) as Array).is_empty() and container.path != "":
		container.write()
	last_printed_export_summary = String(result.get("summary", ""))
	if _status_label != null:
		_status_label.text = last_printed_export_summary
	return result


## Says what happened, and says it the way `StlWriter` said it. A refusal names the part and the
## reason — "the surface is not closed", "the solid is inside out" — rather than "export failed",
## because the first is something a builder can report and the second is not.
func _report_export(result: Dictionary, path: String) -> void:
	if _status_label == null:
		return
	if bool(result["ok"]):
		_status_label.text = "Wrote %s" % ProjectSettings.globalize_path(path)
		if open_folder_after_export:
			OS.shell_open(ProjectSettings.globalize_path(path.get_base_dir()))
	else:
		_status_label.text = "NOT EXPORTED — %s" % String(result["reason"])


## One spelling of a safe file name, shared with PrintedExport so a part exported from its button and
## from the project menu lands under the same name.
static func _safe_export_name(text: String) -> String:
	return PrintedExport.safe_name(text)


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
		# PW5. Power keeps its Pack and ESC rails, so its room is a door rather than the system's
		# view — the same arrangement, one entry, and no second branch at the call site.
		"Power": return "Design harness…"
		_: return ""


## Opens the focused system's room on the part the RAIL has selected.
##
## `propeller_picker.selected_part()` rather than a lookup by id, because it is the same record the
## Prop panel renders and the same one its own button emits — one definition of "the blade being
## looked at", so the two doors cannot open on different blades.
func _on_room_door_pressed() -> void:
	if lab == null:
		return
	# Matched on the SYSTEM, the same key `room_door_label` matched on to decide the button existed
	# at all. A door whose label and whose destination were chosen by two different rules is a door
	# that can say one thing and open another.
	match str(SYSTEMS[_focused_index]["name"]):
		"Propulsion": _on_design_blade_requested(lab.propeller_picker.selected_part())
		"Power": _on_harness_room_requested()


## The Harness panel's own door, and the top strip's. Both land here rather than one of them
## opening the room directly — `EscDetails`' posture: the panel says what happened and the shell
## decides what to do about it.
func _on_harness_room_requested() -> void:
	set_power_room_open(true)


## The Power room — PW5. Same accessor and same reason as `blade_room()` above.
func power_room() -> PowerWorkbench:
	return _power_room


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
	_set_room_open(_blade_room, _blade_room_close_glass, open)


## Opens or closes the harness designer (PW5). The blade designer's twin, through the same one
## function, so the two rooms cannot come to disagree about what a room costs the chrome.
##
## Public for `set_blade_room_open`'s reason: it is what a test drives, rather than synthesising a
## click on a button whose position is a layout decision.
func set_power_room_open(open: bool) -> void:
	if open and _power_room != null and lab != null:
		# THE AIRCRAFT IS FETCHED ON THE WAY IN, not held. `build_with_open_harness` seats LAB'S OWN
		# `Harness` in a build made from the rails as they stand now, so the room edits the document
		# the rest of the app reads — see that function for why a copy would silently lose the edit.
		_power_room.set_build(lab.build_with_open_harness(), lab.tweaks, lab.frame_document)
	_set_room_open(_power_room, _power_room_close_glass, open)


## Puts one overlay room up or down, and takes the same three things away from the viewport while
## it is up: the 3D world (switched OFF rather than covered — a viewport nobody can see should not
## be rendering), the viewport tools that act on a model the room is over, and the rail and
## inspector columns whose space the room needs.
##
## ONE FUNCTION FOR BOTH ROOMS. The alternative — a `set_power_room_open` that repeated these eight
## lines — is W0.7's defect written on purpose: eight things to retract, two places to remember
## them, and the day a ninth is added it goes into one of the two.
func _set_room_open(room: Control, close_glass: Control, open: bool) -> void:
	if room == null:
		return
	# EVERY room goes down first, including this one. Opening the harness designer while the blade
	# designer is up would stack two opaque overlays and hand the builder one close button.
	_retract_rooms()
	room.visible = open
	close_glass.visible = open
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

	_inspector_stub = SystemStub.new()
	_inspector_stub.visible = false
	_inspector.add_child(_inspector_stub)


# ---------------------------------------------------------------------------
# The finder — QC4's other half: the overlay wired to the live build
# ---------------------------------------------------------------------------

## The sheet of dark over the canvas while the finder is up.
##
## A `ColorRect` and not a modulate on the viewport, because three separate things have to go dim
## together — the 3D view, the rail column and whichever room is open — and they are not siblings
## of one node. Mouse-stopping: the drone behind it turns on drag, and a click that fell through a
## dimmed canvas would rotate the model the builder cannot see.
func _build_dim() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.anchor_right = 1.0
	_dim.anchor_bottom = 1.0
	_dim.color = Color(0.02, 0.03, 0.05, 0.62)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	add_child(_dim)


## The glass the summoned finder sits in. Built once and empty; the finder itself is made on each
## open, because it is derived from the rail it is opened over.
##
## Centred by ANCHORS rather than by arithmetic — all four at 0.5 with both grow directions BOTH —
## so it stays centred through a resize without the shell being told. A `PanelContainer` takes its
## size from its child, and the child is 368 px wide by §4, so nothing here names a size.
func _build_finder_glass() -> void:
	_finder_glass = _glass_panel()
	# THE ONE PANEL IN THIS SHELL THAT IS NOT GLASS.
	#
	# `GLASS_ALPHA` is 0.86, and the argument for it holds for every panel that sits over the
	# MODEL: a part inspector you can see the airframe through is why the viewport is full-bleed.
	# The finder is not over the model. It is over the inspector on one side and the rail column or
	# the frame designer on the other, and 14% of a panel of dense right-aligned numbers came
	# through it as legible text — the FC inspector's "Processor F40", "Gyro MPU-600" and two
	# paragraphs of amber warning read straight through the list of flight controllers, and the
	# charger's "1356 of 1500 mAh" read through the battery shelf. Two columns of text occupying the
	# same pixels is not a transparency effect, it is two documents on one page.
	#
	# Opaque, therefore, with the shadow doubled so the panel still reads as being IN FRONT rather
	# than drawn on — which was the whole job the alpha was doing.
	var solid := _glass_stylebox()
	solid.bg_color = Color(LothalTheme.PANEL_BG.r, LothalTheme.PANEL_BG.g, LothalTheme.PANEL_BG.b)
	solid.shadow_size = LothalTheme.SHADOW_SIZE * 2
	_finder_glass.add_theme_stylebox_override("panel", solid)
	_finder_glass.anchor_left = 0.5
	_finder_glass.anchor_top = 0.5
	_finder_glass.anchor_right = 0.5
	_finder_glass.anchor_bottom = 0.5
	_finder_glass.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_finder_glass.grow_vertical = Control.GROW_DIRECTION_BOTH
	# The four `margin_*` constants that used to be set here are GONE, and their absence is the
	# note: `margin_left` and friends are `MarginContainer` constants. A `PanelContainer` insets its
	# child by its stylebox's content margins and by nothing else, so those four lines styled
	# nothing at all while reading, to every later editor, like the panel's padding.
	_finder_glass.visible = false
	add_child(_finder_glass)
	# The column is re-squeezed on every resize, not only when it opens: a window dragged shorter
	# with the finder up is exactly the case the fixed height got wrong.
	resized.connect(_fit_finder)


## Squeezes the open finder into the room between the top of the window and the dock.
##
## THE ARITHMETIC IS THE PANEL'S, NOT THE WINDOW'S, and that is the part worth stating. The glass is
## centred by anchors — all four at 0.5, both grow directions BOTH — so it grows from the middle in
## BOTH directions at once: a column `h` tall on a window `H` tall has its bottom edge at
## `H/2 + h/2`. Clearing a dock whose top is `d` therefore allows `h <= 2*(d - gap) - H`, not
## `h <= d - gap`. A check written against the second form passes on a tall window and ships an
## overlay whose last two rows are behind Lab/Sim on a short one.
func _fit_finder() -> void:
	if _finder == null or _dock == null or not _finder_glass.visible:
		return
	var height := size.y
	if height <= 0.0:
		return
	var dock_top := _dock.get_global_rect().position.y - get_global_rect().position.y
	if dock_top <= 0.0:
		dock_top = height
	var allowance := minf(
		2.0 * (dock_top - FINDER_EDGE_GAP) - height,
		height - 2.0 * FINDER_EDGE_GAP)
	# What the PanelContainer's own stylebox takes off the top and bottom before the column gets
	# any of it. Asked of the stylebox rather than written as SPACE_2 * 2, because the panel is
	# handed its box above and a constant here would be a second copy of that decision.
	var chrome: float = _finder_glass.get_theme_stylebox("panel").get_minimum_size().y
	_finder.fit_to_height(allowance - chrome)


## The rail a system's finder is summoned over: the PartPicker behind that system's FIRST rail tab,
## which is §4's "that system's first category" read off the tree rather than retyped.
##
## Found by walking the rails and matching the tab title, not by a system-name-to-member table. A
## table would be a second list of which rail belongs to which system, and `SYSTEMS[i]["rails"]` is
## already that list — P10f's finding was two such lists that were never the same list.
##
## Returns null for a system with no rail at all (Airframe, Printed, and the four unmodelled ones)
## and for a slot holding an `ElectronicsPicker`: that rail fits three bays at once and has no
## single category, so there is nothing for a one-category finder to open on. Named here rather
## than left to be discovered, because "the Video icon does not open a finder" looks like a wiring
## omission and is not one.
##
## `slot` is the position in `SYSTEMS[index]["rails"]`, because a system owns more than one shelf
## and QC5 made all of them reachable — see `_finder_categories`.
func _rail_for_system(index: int, slot := 0) -> PartPicker:
	if index < 0 or index >= SYSTEMS.size():
		return null
	var titles: Array = SYSTEMS[index].get("rails", [])
	if slot < 0 or slot >= titles.size():
		return null
	for child in lab.rails().get_children():
		if child is PartPicker and str(child.name) == str(titles[slot]):
			return child as PartPicker
	return null


## Every shelf of a system the finder CAN open, as `{"position": i, "title": t}` — the header
## segments of §4, and the reason retiring the rail did not delete half the catalog.
##
## Propulsion owns Motor and Prop, Power owns Pack and ESC, Control owns FC and Link. The rail
## column showed all of them as tabs; a finder that only ever opened on `rails[0]` would have made
## propellers, ESCs and receivers unreachable the moment the column came down — and every existing
## check opens on the first shelf, so nothing would have gone red.
##
## Derived by ASKING THE TREE what each title resolves to, not by a second table of which systems
## have two shelves. `SYSTEMS[i]["rails"]` is already that list, and P10f's finding was two lists
## that were never the same list.
func _finder_categories(index: int) -> Array:
	var out: Array = []
	if index < 0 or index >= SYSTEMS.size():
		return out
	var titles: Array = SYSTEMS[index].get("rails", [])
	for i in titles.size():
		if _rail_for_system(index, i) != null:
			out.append({"position": i, "title": str(titles[i])})
	return out


## The titles that still need a COLUMN, because the finder cannot open them: the shelves whose rail
## is an `ElectronicsPicker`. Video's `Electronics` and Control's `Link`.
##
## **This is the honest remainder of QC5 and it is named rather than hidden.** A payload rail fits
## three bays at once from one control — it has no single category, no single noun and no single
## selection — so `PartFinder`, which is built from exactly those three things, cannot be summoned
## over it. Deleting the column for those two systems would have deleted the camera, the VTX, the
## antenna, the receiver, the GPS and the buzzer from the app; keeping it is the affordance staying
## reachable, which the alternative was not.
##
## Computed as the complement of `_finder_categories` over the same title list, so a shelf cannot
## fall out of both and be reachable from neither.
func _column_rail_titles(index: int) -> Array:
	var out: Array = []
	if index < 0 or index >= SYSTEMS.size():
		return out
	var titles: Array = SYSTEMS[index].get("rails", [])
	for i in titles.size():
		if _rail_for_system(index, i) == null:
			out.append(str(titles[i]))
	return out


## Clicking a system icon in the dock: focus the system, then summon its finder (§4, "Opening").
##
## Separate from `select_system_by_name`, deliberately, and the split is the interaction. A CLICK
## is a builder saying "I want to choose a part of this"; a programmatic selection is the capture
## tool, a room closing, or `_ready` restoring what was chosen — and a finder that popped up every
## time a room closed would be the app interrupting work nobody asked it to interrupt.
func _on_system_chosen(index: int) -> void:
	_select_system(index)
	open_finder(index)


## Summons the finder over the focused system's first category, listing, highlighted on the part
## that is fitted right now.
##
## Returns false for a system with no single-category rail, which is not a failure — it is the
## honest answer for Airframe and the four stubs, and the caller (a dock click) has already done
## the half of its job that always applies.
func open_finder(index: int, slot := 0) -> bool:
	var rail := _rail_for_system(index, slot)
	if rail == null:
		return false
	# Removed before freeing rather than queue_free()d in place: a queued node is still a child
	# until the frame ends, so opening twice in one frame would leave the PanelContainer sizing
	# itself around two finders.
	if _finder != null:
		_finder_glass.remove_child(_finder)
		_finder.queue_free()
		_finder = null
	# EVERY ARGUMENT BUT THE SYSTEM NAME COMES OFF THE RAIL. The category, the noun and the three
	# filter axes are the rail's own, so the finder browses the same shelf along the same facets
	# the rail browses — which is what makes QC5's deletion of the rail a deletion rather than a
	# rewrite of what it knew.
	_finder = PartFinder.new(lab.catalog, str(SYSTEMS[index]["name"]),
		rail.category, rail.noun, rail.filter_keys)
	_finder.set_fitter(RailFitter.new(rail))
	# THE OTHER SHELVES OF THIS SYSTEM, and the authoring row that used to sit under the rail's
	# list. Both are what make the retirement a move rather than a deletion — see
	# `_finder_categories` and `_on_finder_authoring`.
	_finder.set_categories(_finder_categories(index), slot)
	_finder.category_chosen.connect(func(other: int) -> void: open_finder(index, other))
	var actions := _rail_action_buttons(rail)
	if actions.size() >= 2:
		# The rail's own wording — "New custom motor…" — carried across rather than composed here,
		# so there is still one spelling of it.
		_finder.set_actions((actions[0] as Button).text)
		_finder.new_part_requested.connect(func() -> void: _on_finder_authoring(index, slot, 0))
		_finder.delete_part_requested.connect(func() -> void: _on_finder_authoring(index, slot, 1))
	# The × in the finder's corner and Escape are THE SAME PATH — `close_finder`, which cancels and
	# retracts. A close that only hid the overlay would leave the build wearing the last part
	# previewed, which is the one thing the builder did not choose.
	_finder.close_requested.connect(close_finder)
	_finder_glass.add_child(_finder)
	# The id the build is wearing, which is what the snapshot is taken of. §4.1: this highlights it
	# and does NOT preview it — re-fitting the part already fitted would put a phantom entry in the
	# seam's log and make "how many previews happened" unanswerable.
	_finder.open_on(str(rail.selected_part().get("part_id", "")))
	_finder_glass.visible = true
	_dim.visible = true
	# Squeezed BEFORE the first frame it is visible for, so it is never drawn at its unconstrained
	# height even once.
	_fit_finder()
	return true


## Escape. Closes the overlay and puts the build back to the record it was wearing when the finder
## opened — after any number of previews, and restoring NOTHING when nothing was fitted (§4.1).
## Both of those rules live in `PartFinder.cancel()`; this function must not re-implement either,
## which is why it does not look at what was previewed.
func close_finder() -> void:
	if not finder_open():
		return
	_finder.cancel()
	_retract_finder()


## Enter. Commits the highlighted part through the same seam the previews went through, so the
## build is already wearing it and the commit is the overlay coming down.
func commit_finder() -> void:
	if not finder_open():
		return
	_finder.accept()
	_retract_finder()


## THE TWO AUTHORING BUTTONS UNDER A RAIL'S LIST, found on the rail rather than rebuilt.
##
## `PartPicker.add_custom_buttons` puts one `HBoxContainer` of `[New custom …, Delete]` under every
## authoring rail, and each subclass wires its own dialog and its own `CustomMotors`/`CustomFrames`
## document to them. Those handlers ARE the implementation of writing a custom part, and this shell
## must not grow a second one: a "New custom motor…" in the finder that saved through its own path
## would be a second way to write the same file.
##
## So the finder's row is a proxy, and this is what it proxies to. WALKED rather than reached for by
## member name, because the slot is private to `PartPicker` and this slice may not edit that file.
## `OptionButton` is excluded because it IS a `Button` and the filter dropdowns would otherwise come
## back first; a `Window` is not descended into, because an open authoring dialog is a child of the
## picker and its OK button is not an action of this rail.
static func _rail_action_buttons(rail: PartPicker) -> Array:
	var out: Array = []
	_collect_action_buttons(rail, out)
	return out


static func _collect_action_buttons(node: Node, into: Array) -> void:
	for child in node.get_children():
		if child is Window:
			continue
		if child is Button and not (child is OptionButton) and not (child is MenuButton):
			into.append(child)
		_collect_action_buttons(child, into)


## A press on the finder's New or Delete, routed to the rail's own button.
##
## **THE FINDER COMES DOWN FIRST, AND THAT IS NOT TIDINESS.** Both actions end in
## `LabScreen.reload_catalog()`, which `remove_child`s and `queue_free`s every rail and builds new
## ones. The live `RailFitter` holds the picker it was constructed with, and in GDScript
## `freed_object != null` is TRUE — this codebase has been bitten by exactly that once already — so
## a finder left up over a deleted custom motor would arrow into a freed `PartPicker`. Retracting is
## the one answer that cannot get this wrong; the builder re-opens the finder from the dock and
## their new part is in the list.
##
## The rail is looked up FRESH on every press rather than captured, for the same reason.
func _on_finder_authoring(index: int, slot: int, action: int) -> void:
	var rail := _rail_for_system(index, slot)
	if rail == null:
		return
	var actions := _rail_action_buttons(rail)
	if action < 0 or action >= actions.size():
		return
	var button: Button = actions[action]
	if button.disabled:
		return
	_retract_finder()
	if _finder != null:
		_finder_glass.remove_child(_finder)
		_finder.queue_free()
		_finder = null
	button.pressed.emit()


func _retract_finder() -> void:
	_finder_glass.visible = false
	_dim.visible = false


func finder_open() -> bool:
	return _finder != null and _finder_glass != null and _finder_glass.visible and _finder.is_open()


## The live finder, for tests and for the capture tool. Null until one has been summoned.
func finder() -> PartFinder:
	return _finder


## Whether the canvas is currently dimmed. A function rather than a member read so a test asserts
## the same thing the screen shows.
func canvas_dimmed() -> bool:
	return _dim != null and _dim.visible


## Deselects: no system focused, no rail, no inspector, nothing on the model dimmed. §5's resting
## state, and the state the inspector's "only when something is selected" rule needs in order to
## mean anything — a rule whose false branch is unreachable is a rule no check can fail.
func clear_selection() -> void:
	_select_system(-1)


## Escape, and the one key this shell binds. Two meanings, innermost first: close the finder if one
## is up, otherwise let go of the selection. That is the same "back out of what you are in" the key
## means everywhere else, and it is why the resting state is reachable without a tenth control.
##
## `_unhandled_key_input` and not `_input`: the finder's own LineEdit has to keep every keystroke
## that is a character, and an `_input` handler upstream of it would eat the query as it was typed.
func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if finder_open():
		match key_event.keycode:
			KEY_ESCAPE:
				close_finder()
			KEY_ENTER, KEY_KP_ENTER:
				commit_finder()
			KEY_UP:
				_finder.move_highlight(-1)
			KEY_DOWN:
				_finder.move_highlight(1)
			_:
				return
		accept_event()
		return
	if key_event.keycode == KEY_ESCAPE:
		clear_selection()
		accept_event()


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


## THE DOCK. One centred cluster at the bottom, carrying what `_build_bottom_left_cluster` and
## `_build_bottom_right_cluster` used to carry separately, plus the system dropdown out of the top
## bar — QC3 of the Quiet Canvas plan, and three of the four floating clusters gone.
##
## ## It rides the CanvasLayer, and that is the way back
##
## Sim puts its HUD and its build panel on a CanvasLayer of its own, which draws over everything in
## the ordinary tree. The first working Lab/Sim toggle was an ordinary Control, so the moment it
## took you to the field it vanished under Sim's HUD and the app had no way back short of quitting.
## The old shell knew this — it is why the tab bar rode `layer = 10` — and now that the toggle is
## one end of a cluster carrying eight other things, the whole cluster inherits the requirement.
## `test_room_host.gd` asserts it by walking up from the Lab button to a CanvasLayer.
##
## The tools and the system icons are retracted in Sim anyway, so nothing of theirs is ever under a
## HUD; they lose the shell's theme inheritance by being on a layer, which is why the panel sets
## `theme` explicitly below — unthemed is a state a screenshot shows and a test does not.
##
## ## What stayed disabled, and why that is honest
##
## Explode, X-ray and Measure are still three slots with no feature behind them, exactly as they
## were in the corner. Turning them on together would make this row a menu of promises, and QC3 is
## about where the controls live and not about what they do.
func _build_dock() -> void:
	var layer := CanvasLayer.new()
	layer.layer = TOGGLE_LAYER
	add_child(layer)

	_dock = Dock.new(SYSTEMS, _glass_stylebox())
	_dock.theme = LothalTheme.get_theme()
	_dock.system_chosen.connect(_on_system_chosen)
	layer.add_child(_dock)

	_dropdown_glass = _dock.systems_group
	_tools_glass = _dock.tools_group
	_bottom_right_glass = _dock.mode_group

	_overlays_button = _dock.overlays_button
	_overlays_button.toggled.connect(set_thrust_overlay_visible)
	_overlays_menu_button = _dock.overlays_menu
	var popup := _overlays_menu_button.get_popup()
	popup.id_pressed.connect(_on_overlay_chosen)
	# `about_to_popup` rather than a rebuild on every tick, because the menu has to show the CURRENT
	# band's capacity and nothing notifies it of a window resize.
	popup.about_to_popup.connect(_populate_overlay_menu)

	_status_label = _dock.status_label
	# The ring is built here and handed over rather than built inside the dock, because it is an
	# inner class of this file — a `Dock` that named `GlassShell` would be a parse cycle.
	_ring = CompletenessRing.new()
	_dock.adopt_ring(_ring)

	_lab_button = _dock.lab_button
	_lab_button.pressed.connect(func() -> void: rooms.show_lab())
	_sim_button = _dock.sim_button
	_sim_button.pressed.connect(func() -> void: rooms.show_sim())
	_room_menu = _dock.room_menu
	_room_menu.room_chosen.connect(_open_room)

	# A CENTRED CONTROL SIZED BY ITS CONTENT HAS TO BE TOLD WHEN EITHER CHANGES, and this is the one
	# way the dock differs from the four anchored clusters it replaces. `minimum_size_changed` fires
	# when the row grows — a longer Rooms menu, a bigger UI scale — and `resized` on this shell fires
	# when the window does. Neither can recurse into the other: `layout_in` writes offsets, which
	# change no minimum.
	_dock.minimum_size_changed.connect(_layout_dock)
	resized.connect(_layout_dock)
	_layout_dock.call_deferred()


## Puts the dock against the bottom of the window, centred.
##
## Separate from `_build_dock` because it runs again on every resize, and deferred at build time for
## the reason `_fit_columns` is: a Control that has never been laid out reports a combined minimum
## size of (0, 0), so a dock positioned at construction would be centred on nothing.
func _layout_dock() -> void:
	if _dock == null:
		return
	_dock.layout_in(size, CLUSTER_MARGIN, BOTTOM_KEEPOUT)


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
	# THE SYSTEM ICONS GO OUT TO THE FIELD WITH THE TOOLS, and this line is new because the thing it
	# hides used to be inside `_top_bar` — the dropdown retracted for free as part of the strip. The
	# dock is not in the strip, so the retraction has to be said. Without it the field would carry
	# six icons that change what is fitted, which is precisely the authoring §5 says Sim must make
	# impossible BY THE SHAPE OF THE SCREEN rather than by discipline.
	_dropdown_glass.visible = in_lab
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
		# AND SO DO THE OVERLAY ROOMS, which this path did not do. Same argument as the canvas above,
		# and the same omission W0.7 named: the blade designer and the harness designer are children
		# of the shell, drawn over `rooms`, so walking to the field with one open flew the course
		# under a planform editor. It went unnoticed because the way back always ends in
		# `_select_system`, which retracts them — so the room was only wrong while you were flying.
		_retract_rooms()


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
	# NOTHING SELECTED — §5's resting state, and the branch that makes "the inspector appears only
	# when something is selected" a rule with a false side. Everything the focused system would
	# have asked for is put away and nothing replaces it: no rail, no inspector, no room, no plan
	# editor, and the model lit in full rather than dimmed around a focus that no longer exists.
	#
	# Before the branch below rather than inside it, because `SYSTEMS[index]` on the next line is
	# what -1 would crash on.
	if index < 0:
		_deselect()
		return
	var system: Dictionary = SYSTEMS[index]

	# NO OVERLAY ROOM SURVIVES A SYSTEM CHANGE. Leaving the blade designer up while the builder
	# walked to Power would put a planform editor over a pack they had just asked to look at, and
	# the harness designer has the mirror of that problem. Retracted directly rather than through
	# `set_*_room_open`, because those functions end by calling THIS one and the two would recurse.
	_retract_rooms()
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
	# QC5: THE COLUMN IS UP ONLY FOR A SHELF THE FINDER CANNOT OPEN. That is the whole retirement,
	# in one expression, and it is derived from the tree rather than from a list of exceptions —
	# see `_column_rail_titles`. An unmodelled system no longer shows it either: its stub is one
	# panel now, in the inspector.
	var column_titles := _column_rail_titles(index)
	_rail_glass.visible = modelled and not column_titles.is_empty()
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
	lab.rails().visible = _rail_glass.visible
	lab.panels.visible = modelled
	_inspector_stub.visible = not modelled

	if modelled:
		if has_rails and not column_titles.is_empty():
			_show_only_tabs(lab.rails(), column_titles)
		_show_only_tabs(lab.panels, system["panels"])
	else:
		_inspector_stub.show_system(system)

	# The dock's icon for this system, lit. Here rather than in `select_system_by_name`, because
	# every route in ends here and only one of them goes through that function.
	if _dock != null:
		_dock.set_focused(index)

	_apply_focus()
	_refresh_status()
	# Which tabs have to fit just changed with the system, so the column's width has to be asked
	# again. Deferred for the same reason it is everywhere else here: a panel that has just been
	# shown has not been laid out yet, and its combined minimum size is still the previous answer.
	_fit_columns.call_deferred()


## The nothing-selected half of `_select_system`, kept beside it rather than folded into it.
##
## Written out rather than expressed as "the same thing with empty lists" because the two are not
## the same shape: a focused system HIDES things (the rail Airframe has none of, the viewport the
## plan editor covers) and this state hides the chrome and shows the canvas. The one line the two
## must agree on is `_dock.set_focused`, which already answers -1 by lighting nothing — QC3 wrote
## it that way for `select_system_by_name` being callable before the dock was ever clicked.
##
## The thrust overlay goes with the selection. It is a chart about the Propulsion system, and left
## floating over an unfocused drone it would be describing a system nobody had chosen.
func _deselect() -> void:
	_retract_rooms()
	if _room_door_glass != null:
		_room_door_glass.visible = false
	_rail_glass.visible = false
	# THE POINT OF THE WHOLE SLICE, in one line. Everything else here was already reachable.
	_inspector.visible = false
	if _workbench != null:
		_workbench.visible = false
	# The canvas comes BACK — the plan editor was covering it and the viewport was switched off
	# with it, and a resting state showing a blank rectangle where the drone should be would be
	# worse than any panel.
	var viewport_container := lab.viewport().get_parent()
	if viewport_container is Control:
		(viewport_container as Control).visible = true
	if _tools_glass != null:
		_tools_glass.visible = true
	_sync_thrust_overlay()
	if _dock != null:
		_dock.set_focused(-1)
	_apply_focus()
	_refresh_status()
	_fit_columns.call_deferred()


## Selects a system by its name. The seam the capture tool drives, so a screenshot goes through the
## same path a click does rather than a private one beside it.
##
## It no longer has to put a dropdown in step, because `_select_system` lights the dock's icon — one
## place, reached by every route in. The old two-line version was a pair that could disagree, and
## did: a caller that used `_select_system` directly left the dropdown reading the previous system.
## Safe to call before the shell is inside the tree: it records the choice on `_focused_index`, and
## `_ready()` re-applies whatever it finds there.
func select_system_by_name(system_name: String) -> bool:
	for i in SYSTEMS.size():
		if str(SYSTEMS[i]["name"]) == system_name:
			_select_system(i)
			return true
	return false


## Brings the first tab named in `titles` to the front, then hides every tab not named there.
##
## Hidden rather than removed, which is what keeps LabScreen's `tab_changed → panels.current_tab`
## sync working on a stable list: hiding does not renumber the tabs, so a title still names the same
## tab either side of a system change. The claim this comment USED to make — "index 4 is still ESC
## on both sides" — was the index sync's justification and had been false since Airframe's four
## panels landed between Frame and Motor. Seven rails, fourteen panels, and the ESC rail routed to
## Layout. LabScreen resolves that by title now, which is what makes hiding-not-removing enough.
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
	# Nothing focused dims nothing, which is the same answer this function already gives for Drone
	# and for an unmodelled system, reached one line earlier.
	if _focused_index < 0 or _focused_index >= SYSTEMS.size():
		_fade_below(lab.airframe, "", "")
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
## which is why the figure starts at six of ten rather than at zero.
##
## **Today it is constant at six of ten, and that is worth saying rather than hiding.** Every rail
## opens on a selection and none can be cleared, so all six modelled systems are decided from the
## first frame and the arc never moves. I expected Video to make it live — a whoop publishes no
## camera or VTX bay — but the picker keeps its ids regardless of the frame, so `selection()` never
## returns an empty one. Checked, not assumed.
##
## Left in anyway, because the ring is a slot in the frame and a frame is what this file is. What it
## must NOT become is a number that looks live and is not: when the four unmodelled systems arrive
## the arc starts moving on its own, and until then this comment is the honest label.
## Keep (PR7): acknowledges the finding for `part_id` in this drone's printing block, writes the drone
## when it has a home, and checks again. The record stays.
func keep_divergence(part_id: String) -> void:
	for finding in printed_divergence:
		if String(finding["part"]) == part_id:
			PrintedDivergence.acknowledge(lab.printing, finding)
	_sync_project()
	if container != null and container.path != "":
		container.write()
	_report_printed_divergence()


## Reprint (PR7): re-exports only `part_id` through the shared export, appending its record, writes the
## drone when it has a home, and checks again.
func reprint_part(part_id: String) -> void:
	if container == null or lab == null:
		return
	_sync_project()
	var result := PrintedExport.export_part(lab.build_with_open_harness(), part_id,
		printed_export_dir, container)
	if bool(result["ok"]) and container.path != "":
		container.write()
	_report_printed_divergence()
	if not bool(result["ok"]) and _status_label != null:
		_status_label.text = "NOT REPRINTED — %s" % String(result["reason"])


## The status line as it reads now. For tests.
func status_text() -> String:
	return _status_label.text if _status_label != null else ""


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
	# The system's name, or the em-dash that stands for "none chosen". The readout is the one place
	# the focused system is named in words, so with nothing focused it has to say that rather than
	# index -1 into SYSTEMS and take the shell down with it.
	var focused_name := str(SYSTEMS[_focused_index]["name"]) if _focused_index >= 0 \
		and _focused_index < SYSTEMS.size() else "No system"
	_status_label.text = "%s  ·  %d of %d systems decided" % [
		focused_name, decided, SYSTEMS.size()]
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
	# The printing block follows the lab's working copy the same way (printed-room PR0). Copied, not
	# shared, so the dirty check compares two objects rather than one object with itself.
	container.project.printing = lab.printing.duplicate(true)


## Rename is ProjectChip's own; everything else lands here.
func _on_project_action(action_id: String) -> void:
	match action_id:
		"new":
			adopt(ProjectLibrary.starting_project())
		"duplicate":
			adopt(ProjectLibrary.duplicate_of(container.project))
		"open":
			_open_dialog.popup_centered_ratio(0.6)
		"export_printed":
			export_printed_parts()
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
	_report_printed_divergence()
	return missing


## Printed-room PR5: generates every printed part again and says which no longer match their print
## records. After `_refresh_status`, so the finding is what the status line ends up saying.
func _report_printed_divergence() -> void:
	printed_divergence = []
	if container == null or lab == null:
		return
	printed_divergence = PrintedDivergence.check(container.project, container,
		lab.build_with_open_harness())
	lab.print_panel.set_divergence(printed_divergence)
	if printed_divergence.is_empty() or _status_label == null:
		return
	var lines: Array = []
	for finding in printed_divergence:
		lines.append(String(finding["message"]))
	_status_label.text = " ".join(PackedStringArray(lines))


## Fits a project's parts on the rails. Whatever could not be fitted comes back named — see
## LabScreen.apply_selection, which refuses to substitute.
func apply_project(project: Project) -> Array:
	if lab == null:
		return []
	# Printing first, so the rebuild the selection triggers already describes this drone's parts.
	lab.set_printing(project.printing)
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
	_retract_rooms()
	_tools_glass.visible = false
	_dropdown_glass.visible = false
	if _bottom_right_glass != null:
		_bottom_right_glass.visible = false
	# AND THE DOCK ITSELF, not only its three groups. Three hidden groups inside a visible panel is
	# an empty glass pill floating over "No drone open" — a piece of chrome describing nothing,
	# which is the one thing the empty state exists to avoid.
	if _dock != null:
		_dock.visible = false
	var viewport_container := lab.viewport().get_parent()
	if viewport_container is Control:
		(viewport_container as Control).visible = false


## Undoes the empty state — every New and Open lands here. The per-system visibility of the columns
## and the model is `_select_system`'s job, so this re-runs it against the focused system rather
## than guessing at what to show.
func _show_project() -> void:
	_empty_state.visible = false
	_dropdown_glass.visible = true
	if _dock != null:
		_dock.visible = true
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
	# THE TOKEN, WHOLE — alpha included. This line used to read BORDER's three channels and force
	# alpha to 0.9, which is the trap worth naming: re-mixing a colour token's channels while
	# forcing a different alpha silently INVERTS the token's meaning the moment the token changes
	# representation. BORDER was once an opaque grey, so rgb(BORDER)+0.9 happened to land on a dim
	# hairline; BORDER is now white-at-low-alpha, and the identical expression started painting a
	# near-solid white outline — measured at RGB (231, 232, 232) on the tools cluster, the
	# brightest thing on screen. The alpha IS the token here; discarding it discards the line.
	# A cluster does want a firmer edge than a panel nested inside it, and the theme already has a
	# name for that, so ask for BORDER_STRONG rather than mixing one by hand.
	box.border_color = LothalTheme.BORDER_STRONG
	box.set_border_width_all(1)
	# RADIUS_PANEL (10), not a hand-written 8. The panels a cluster contains are RADIUS_CONTROL (7),
	# and 8-around-7 is a one-pixel difference that reads as a slip rather than as nesting — the
	# outer corner has to be visibly rounder than the inner one for the containment to be legible.
	box.set_corner_radius_all(LothalTheme.RADIUS_PANEL)
	box.set_content_margin_all(LothalTheme.SPACE_2)
	# A cluster that FLOATS over the viewport casts a shadow onto it. Without one these are
	# translucent rectangles painted on the picture rather than panels in front of it, which is
	# most of why the shell read as flat while being named for glass.
	box.shadow_color = LothalTheme.SHADOW
	box.shadow_size = LothalTheme.SHADOW_SIZE
	box.shadow_offset = LothalTheme.SHADOW_OFFSET
	box.anti_aliasing = true
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
## QC5: THERE IS ONE STUB, AND IT IS THE INSPECTOR'S. There used to be two halves — the rail side
## carried "WHAT BELONGS HERE" and the list, the inspector side carried the reasoning and the
## source. The rail column is retired, so the half that lived in it had to go somewhere or the
## list of parts would have been deleted along with the panel that happened to hold it. It is the
## most visible half of a stub: "why there is nothing here" is an explanation, and the list is the
## content being explained.
class SystemStub extends VBoxContainer:
	var _title: Label
	var _body: VBoxContainer

	func _init() -> void:
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

		var heading := Label.new()
		heading.text = "WHAT BELONGS HERE"
		heading.theme_type_variation = "SmallLabel"
		_body.add_child(heading)
		for item in stub["items"]:
			var line := Label.new()
			line.text = "·  %s" % item
			_body.add_child(line)

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
