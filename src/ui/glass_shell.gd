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
		"name": "Airframe",
		"rails": ["Frame"],
		"panels": ["Frame", "Fit"],
		"decided_by": ["frame"],
	},
	{
		"name": "Propulsion",
		"rails": ["Motor", "Prop"],
		"panels": ["Motor", "Prop"],
		"decided_by": ["motor", "propeller"],
	},
	{
		"name": "Power",
		"rails": ["Pack"],
		"panels": ["Pack"],
		"decided_by": ["battery"],
	},
	{
		"name": "Control",
		"rails": ["ESC", "FC"],
		"panels": ["ESC", "FC", "Tune"],
		"decided_by": ["esc", "flight_controller"],
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

## Which 3D nodes belong to which system, matched against the nearest ancestor whose name matches.
## Anything matching nothing belongs to Airframe — the frame is what is left when every fitted part
## is accounted for, which is also literally true of a frame.
const SYSTEM_NODE_PREFIXES := {
	"Propulsion": ["Motor_", "Propeller_"],
	"Power": ["Battery"],
	"Control": ["Stack", "Component_receiver"],
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
var _sim_button: Button
var _lab_button: Button
var _focused_index := 0


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

	# Order matters below: every cluster is added AFTER `rooms`, so it draws over the viewport. This
	# is the arrangement §5 chose Godot for — Controls floating over a SubViewportContainer at full
	# z-order, which is the one thing the Tauri hybrid could not do.
	_build_rail_glass()
	_build_inspector()
	_build_top_cluster()
	_build_bottom_left_cluster()
	_build_bottom_right_cluster()


func _ready() -> void:
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

	var inspector_width := maxf(INSPECTOR_WIDTH, lab.panels.get_combined_minimum_size().x)
	_inspector.offset_left = -(inspector_width + LothalTheme.SPACE_2 * 2 + CLUSTER_MARGIN)


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
	bar.add_child(dropdown_glass)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)


## Left: the rail column, floated, plus the stub that replaces it for an unmodelled system.
##
## §5 says a system's parts belong in a thin strip along the TOP, not in a column at the left. This
## is that deviation, and it is the largest one on this screen: a strip means rebuilding PartPicker
## horizontally, which is component work. Worth naming precisely because the screenshots make the
## cost visible — with glass on both sides the model keeps about half the window, which is closer
## to the old three-column layout than to the design.
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

	row.add_child(VSeparator.new())

	_status_label = Label.new()
	_status_label.theme_type_variation = "SmallLabel"
	row.add_child(_status_label)

	_ring = CompletenessRing.new()
	row.add_child(_ring)


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
	# The layer is not a Control, so the theme does not reach this panel down the tree the way it
	# reaches the other three. Set here rather than left to inherit, because unthemed is a state a
	# screenshot shows and a test does not.
	glass.theme = LothalTheme.get_theme()
	glass.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	glass.anchor_left = 1.0
	glass.anchor_top = 1.0
	glass.anchor_right = 1.0
	glass.anchor_bottom = 1.0
	glass.offset_left = -186.0 - CLUSTER_MARGIN
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
	var in_lab := rooms.showing_lab()
	_lab_button.button_pressed = in_lab
	_sim_button.button_pressed = rooms.sim != null

	_top_bar.visible = in_lab
	_tools_glass.visible = in_lab
	if in_lab:
		# Re-applies the focused system rather than just showing the two columns, because which of
		# them is visible is a property of the system chosen — an unmodelled system shows stubs, and
		# blindly unhiding here would put a Frame rail up under a dropdown reading "Config".
		_select_system(_focused_index)
	else:
		_rail_glass.visible = false
		_inspector.visible = false


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
	var modelled := _is_modelled(system)

	# The glass panels themselves are shown here rather than only in `_build_*`, because Sim
	# retracts them — see _on_room_changed. Walking back into the garage has to put back exactly
	# what the chosen system asks for, and the two columns inside them are separate: the panel is
	# the frame, and a stub is what the frame holds for a system with no model.
	_rail_glass.visible = true
	_inspector.visible = true
	lab.rails().visible = modelled
	lab.panels.visible = modelled
	_rail_stub.visible = not modelled
	_inspector_stub.visible = not modelled

	if modelled:
		_show_only_tabs(lab.rails(), system["rails"])
		_show_only_tabs(lab.panels, system["panels"])
	else:
		_rail_stub.show_system(system)
		_inspector_stub.show_system(system)

	_apply_focus()
	_refresh_status()


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


static func _is_modelled(system: Dictionary) -> bool:
	return not (system["rails"] as Array).is_empty()


# ---------------------------------------------------------------------------
# System focus — the thing that makes a full-bleed viewport earn its space
# ---------------------------------------------------------------------------

## Fades every mesh that does not belong to the focused system.
##
## Walks the airframe rather than consulting AirframeModel's dictionaries of meshes, because the
## dictionaries hold the roots and the transparency has to reach the GeometryInstance3D leaves — a
## motor is a node with meshes under it, not a mesh. Classification is by nearest matching ANCESTOR
## for the same reason: a propeller blade knows nothing about being propulsion, and the node three
## levels up is the one that does.
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
	_fade_below(lab.airframe, "", focused)


func _fade_below(node: Node, inherited_system: String, focused: String) -> void:
	var system := inherited_system
	if system == "":
		system = _system_of_name(node.name)
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
