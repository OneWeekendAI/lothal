class_name LabScreen
extends Control
## Lothal Labs — the garage, and the screen the app opens on (labs-and-sim.md §2).
##
## Four rails on the left — frame, motor, propeller, pack — the generated airframe in the middle,
## and the details, the derived stats and the charger on the right. Nothing here flies. There is
## no integrator, no flight controller and no audio synthesiser in this file, and that absence is
## the entire point of the Lab/Sim split — choosing a frame is arithmetic and should not cost a
## laptop's fans.
##
## The 3D content lives in a SubViewport with its OWN World3D. That is not decoration: Sim
## is a separate scene with its own cameras and lights, and giving Lab a private world is
## what stops the two from rendering into each other. It also means a hidden Lab genuinely
## stops drawing (UPDATE_WHEN_VISIBLE) rather than quietly rendering behind the field.
##
## One handler drives everything (_on_selection_changed): geometry, all four details panels, the
## charger, and the stats. There is no apply button and there is no second path — a stat cannot
## disagree with the airframe on screen because both are rebuilt from the same Build in the same
## call, whichever rail the change came from.
##
## Time does not pass in Lab, with exactly one exception: the charger. That is the compressed half
## of labs-and-sim.md §5's asymmetry — draining runs at 1:1 in the benches and in the field, and
## charging runs at 10:1 here, because there is a charger in the garage and not one in the field.
const VIEWPORT_SIZE := Vector2i(1280, 720)

## The camera sits at a FIXED distance, deliberately — and this is the one piece of framing
## that must not be clever. Zooming to fit each frame would normalise away the thing worth
## seeing: a 65 mm whoop must look tiny beside a 10" long-range, and it only does if the
## camera holds still. So the distance is computed ONCE, from the largest arm in the catalog,
## and then never moves. Derived rather than authored, so adding a 13" frame reframes the room
## instead of hanging it off the edge of the viewport (which is exactly what a hand-picked
## 0.62 m did to the 10" entry).
const CAMERA_FOV := 38.0
## Fraction of the viewport width the largest airframe should span. Leaves the biggest frame
## visibly inside the room rather than touching both edges.
##
## Raised from 0.78 when the props arrived. The widest legitimate build in the catalog went from
## a bare 10" frame (215 mm half-span) to a 10" frame carrying 10" props (342 mm), and since the
## distance is chosen by that build and then held for every build, the reference 5" quad lost a
## third of its size on screen — which is the one thing this viewport cannot afford, because
## propeller twist is the detail it now exists to show. The margin left over is smaller, but it
## is the biggest build that gets close to the edges and nothing else.
const LARGEST_FRAME_SCREEN_FRACTION := 0.95

## The camera orbits the airframe on two angles: AZIMUTH around the vertical, and ELEVATION
## above and below the horizon. Together those reach every point on the sphere, which is what
## matters as soon as Lab holds more than a frame — a battery tray, a payload mount and the
## bottom plate are all under the build, and a yaw-only turntable can never look at any of
## them. There is deliberately no third rotation: roll would not reveal a single surface the
## other two cannot already reach, it would only change which way is up on screen, and losing
## which way is up is expensive on a screen whose whole job is judging an airframe.
##
## The camera moves and the airframe stays level, rather than tumbling the model. Same
## pictures, but the build keeps its own sense of up and the lighting stays consistent.
const ELEVATION_LIMIT_DEG := 85.0
const START_AZIMUTH_DEG := 0.0
const START_ELEVATION_DEG := 22.0

## The idle orbit: a continuous turn about the vertical, plus a slow rise and fall through the
## horizon so the view drifts between looking down on the top plate and up at the underside.
## The vertical drift is what makes the object read as solid; a pure yaw spin can look like a
## flat picture on a rotating card.
const AUTO_ORBIT_DEG_S := 11.0
const AUTO_ELEVATION_CENTRE_DEG := 14.0
const AUTO_ELEVATION_SWING_DEG := 32.0
const AUTO_ELEVATION_PERIOD_S := 26.0

## Drag speed when the builder takes the orbit over by hand — horizontal for azimuth,
## vertical for elevation.
const DRAG_DEG_PER_PIXEL := 0.4

## The rate Lab turns the props at: a hand spin, the way you flick a prop with a finger to check it
## clears the arm and runs true. Lab has no powertrain — that is the thrust stand's slice — so this
## is the one number on this screen that is a display choice rather than a consequence of a part, and
## it is here rather than in PropellerMesh for exactly that reason: the propeller renders a rate it is
## given, and Lab is what gives it one. When the bench lands it feeds real RPM through the same input.
##
## Slow, deliberately. It has to stay well under PropellerMesh's aliasing threshold (600 RPM for a
## tri-blade at 60 fps), because the blade twist is what this viewport exists to show and above that
## threshold the blades are replaced by a blur disc.
const HAND_SPIN_RPM := 150.0

## The air the garage quotes its numbers in — the SELECTED course's field (air_density.gd).
##
## Lab holds it rather than reaching for CourseLibrary itself, for the same reason it is handed a
## PackCharge rather than loading one: the shell owns the state two rooms touch, and a second
## reader would be a second copy that could go stale the moment the field editor changed it.
##
## Standard until the shell says otherwise, which is what keeps a LabScreen built in a test — or
## before any library is loaded — quoting the same figures it always has.
var air := AirDensity.standard()

var catalog: PartsCatalog
var picker: FramePicker
var motor_picker: MotorPicker
var propeller_picker: PropellerPicker
var battery_picker: BatteryPicker
var esc_picker: EscPicker
var fc_picker: FcPicker
var electronics_picker: ElectronicsPicker
var details: FrameDetails
## The four Airframe tabs. Read-only inspectors over the airframe maths (airframe.md §3–§5); none
## of them owns state, so a reload rebuilds them with everything else and nothing is lost.
var structure_details: StructureDetails
var arms_details: ArmsDetails
var fasteners_details: FastenersDetails
var layout_details: LayoutDetails

## The frame the Airframe tabs are describing, as geometry.
##
## HELD, not regenerated per repaint. The four tabs no longer take a Build — a frame is a frame with
## nothing bolted to it (airframe.md §1) — so what they need is a document, and the document has to
## outlive a selection change or an edit made in the Airframe room would be thrown away the moment
## somebody picked a different propeller. It is regenerated only when the SELECTED FRAME changes,
## which is the one event that really does mean "you are now looking at a different object".
var frame_document: AirframeDocument
var _frame_document_id := ""
var motor_details: MotorDetails
var propeller_details: PropellerDetails
var battery_details: BatteryDetails
var harness_stub: HarnessStub
var esc_details: EscDetails
var fc_details: FcDetails
var electronics_details: ElectronicsDetails
## The charger. Lab's, because charging is a garage activity — there is a charger in the garage
## and there is not one in the field (labs-and-sim.md §5).
var charge_panel: PackChargePanel
## How much charge is in each pack. Injected by AppShell so every room shares one set of packs;
## tests pass their own, so the suite never depends on or overwrites the packs of whoever runs it.
var pack_charge: PackCharge
var assembly_panel: AssemblyPanel
var tune_panel: TunePanel
## The builder's fit adjustments, loaded from disk on the way in and saved on every change. Lab
## owns them because Lab is where the drone is assembled (labs-and-sim.md §1); Sim reads the same
## file and never writes it.
var tweaks: AssemblyTweaks
## The builder's PID gains, per build. Loaded here rather than in the panel for the same reason
## `tweaks` is: Lab is the only writer, and a copy held by a widget would be a second place a gain
## lives.
var pid_tunes: PidTunes = PidTunes.load_from()
## The tune in force for the current selection — derived from the plant, with anything saved on
## THIS build laid over it. Held so that both the tuning panel and the FC panel are quoting one
## object rather than each deriving their own.
var tune: RateTune = null
## The whole generated aircraft. `frame_model` is kept as a name because it is what Lab's
## screenshot tooling and tests reach for, but it is the airframe's frame now, not a
## free-standing one.
var airframe: AirframeModel
var frame_model: FrameModel

## The right-hand details column. Held as a field so the fit panel can be brought to the front by
## name — capture_lab.gd photographs it, and there is no other way to reach a tab from outside.
var panels: TabContainer

## The tabbed rail column. Held as a field, not a local of _init, because reload_catalog() needs
## to swap its children (a new frame is a new catalog, and a rail built against the old one would
## go on filtering and framing off stale options) without discarding the TabContainer itself —
## the tab_changed wiring below is made once, against this node, and stays good across a reload.
var _rails: TabContainer

var _viewport: SubViewport
## The camera boom. Rotating this orbits the camera; the airframe itself never moves.
var _orbit: Node3D
var _camera: Camera3D
var _dragging := false

## The idle orbit runs until somebody takes hold of the view, and then it stops for good. It
## does NOT resume: an orbit that starts creeping again after you let go carries the angle you
## just chose away from you, which is precisely wrong when the reason you chose it was to look
## at one particular thing — a mount, a tray, the underside of a plate.
var auto_orbit := true

var _azimuth_rad := deg_to_rad(START_AZIMUTH_DEG)
var _elevation_rad := deg_to_rad(START_ELEVATION_DEG)
var _auto_elevation_time := 0.0

## `p_tweaks` is the assembly configuration to open with. It defaults to whatever is on disk,
## which is the real startup path; tests pass their own so the suite never depends on, or
## overwrites, the configuration of the person running it.
func _init(p_catalog: PartsCatalog, p_tweaks: AssemblyTweaks = null,
		p_pack_charge: PackCharge = null) -> void:
	catalog = p_catalog
	tweaks = p_tweaks if p_tweaks != null else AssemblyTweaks.load_from()
	pack_charge = p_pack_charge if p_pack_charge != null else PackCharge.new()

	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.anchor_right = 1.0
	row.anchor_bottom = 1.0
	add_child(row)

	# Three rails behind tabs rather than three rails side by side. Side by side would put six
	# columns on screen and leave the airframe — the thing being judged — as a sliver in the
	# middle, which inverts what this screen is for. Tabs also match how the decision is
	# actually made: one component at a time, against a build that stays whole between visits.
	_rails = TabContainer.new()
	_rails.custom_minimum_size = Vector2(292, 0)
	_rails.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_rails)

	_build_rails()

	var viewport_container := SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(viewport_container)

	_viewport = SubViewport.new()
	_viewport.size = VIEWPORT_SIZE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport_container.add_child(_viewport)

	_build_world()

	panels = TabContainer.new()
	panels.custom_minimum_size = Vector2(336, 0)
	panels.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(panels)

	details = FrameDetails.new()
	details.name = "Frame"
	panels.add_child(details)

	# The four Airframe tabs (airframe.md §1). They are panels and not rails because none of them
	# is a thing you pick: an arm, a bolted joint and an inertia tensor are consequences of the
	# frame you already chose, not entries in a catalog. All four render against the SAME frame
	# dictionary the Frame panel gets, which is what keeps them from describing a different
	# aircraft than the one on screen.
	structure_details = StructureDetails.new()
	structure_details.name = "Structure"
	panels.add_child(structure_details)

	arms_details = ArmsDetails.new()
	arms_details.name = "Arms"
	panels.add_child(arms_details)

	fasteners_details = FastenersDetails.new()
	fasteners_details.name = "Fasteners"
	panels.add_child(fasteners_details)

	layout_details = LayoutDetails.new()
	layout_details.name = "Layout"
	panels.add_child(layout_details)

	motor_details = MotorDetails.new(catalog)
	motor_details.name = "Motor"
	panels.add_child(motor_details)

	propeller_details = PropellerDetails.new(catalog)
	propeller_details.name = "Prop"
	panels.add_child(propeller_details)
	# Fitting a guard is a selection change like any other, and it has to run through the SAME
	# handler: it moves the mass, the roll inertia, the ring on the aircraft and — for a duct —
	# the current the aircraft draws. A dropdown that only redrew its own panel would report an
	# aircraft nobody built.
	#
	# Connected HERE and not beside the rails' six connections, because the guard's control is a
	# panel and the panels are built after the rails — the rail block runs while
	# `propeller_details` is still null.
	propeller_details.guard_changed.connect(func(_guard_id: String) -> void:
		_on_selection_changed())

	# The pack tab holds two things: what the battery IS, and what state it is in. They are stacked
	# in one tab rather than split across two, because "4S 1500, and it is 12% full" is one thought.
	#
	# It scrolls, and it is the only panel that needs to. The pack has ten spec rows to the frame's
	# six, and the charger sits under the five derived stats — which on a laptop-height window put
	# the charge readout below the bottom of the screen entirely. Vertical only: a details column
	# that scrolls sideways has a layout bug rather than a scrollbar.
	var pack_tab := ScrollContainer.new()
	pack_tab.name = "Pack"
	pack_tab.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panels.add_child(pack_tab)

	var pack_column := VBoxContainer.new()
	pack_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pack_tab.add_child(pack_column)

	# The charger goes ABOVE the spec sheet, which is the opposite of the order the other panels
	# use and is deliberate. Every other panel is reference material — the numbers on a part do
	# not change while you look at them. The charge does, it is the only control on the right-hand
	# column, and it is the reason you opened this tab twice in an evening. Reference belongs
	# under the thing you act on.
	charge_panel = PackChargePanel.new(pack_charge, catalog)
	charge_panel.charge_changed.connect(_on_charge_changed)
	pack_column.add_child(charge_panel)

	battery_details = BatteryDetails.new()
	pack_column.add_child(battery_details)

	esc_details = EscDetails.new()
	esc_details.name = "ESC"
	panels.add_child(esc_details)

	# Power's third panel (PW4). It sits beside Pack and ESC because that is the system it belongs
	# to — every ampere from cell to motor lead — and it holds its place with a note saying the
	# model is shipped and the view is PW5's. A named panel in SYSTEMS with no tab behind it routes
	# to nothing and hides silently; see GlassShell._show_only_tabs.
	harness_stub = HarnessStub.new()
	panels.add_child(harness_stub)

	fc_details = FcDetails.new()
	fc_details.name = "FC"
	panels.add_child(fc_details)

	electronics_details = ElectronicsDetails.new()
	electronics_details.name = "Electronics"
	panels.add_child(electronics_details)

	# A panel with no rail behind it, because a fit adjustment is not a part choice: there is
	# nothing to browse and nothing to filter. It sits with the other panels rather than becoming a
	# fourth column, which would take screen space from the airframe — the thing being judged.
	assembly_panel = AssemblyPanel.new(tweaks)
	assembly_panel.name = "Fit"
	assembly_panel.tweaks_changed.connect(_on_tweaks_changed)
	panels.add_child(assembly_panel)

	# Tuning lives in Lab (labs-and-sim.md §7, resolved — see pid_tunes.gd for the argument), and it
	# sits beside Fit for the same reason Fit does: there is nothing to browse, so there is no rail
	# behind it. It goes LAST because it is the only tab that is meaningless until the aircraft is
	# assembled — every other panel describes a part, and this one describes what the parts add up
	# to.
	tune_panel = TunePanel.new()
	tune_panel.name = "Tune"
	tune_panel.tune_changed.connect(_on_tune_changed)
	panels.add_child(tune_panel)

	# Working on a rail should show the panel for the part being chosen, so the two columns
	# never describe different components. Connected once, against the TabContainer itself, which
	# survives a reload_catalog() even though its children (the rails) do not.
	# Ignore the transient -1 TabContainer emits while reload_catalog() tears the rails down —
	# panels does not allow deselection, and _build_rails() reselects a real tab right after.
	_rails.tab_changed.connect(func(index: int) -> void:
		if index < 0:
			return
		panels.current_tab = index)

	# Lab opens on the reference build rather than on whatever happens to be first in each
	# catalog file — a 65 mm whoop frame under a 2807 and a 10" prop is a strange thing to
	# greet somebody with, and the reference build is the one combination the project's own
	# oracles describe. Selected BEFORE the handlers are connected so the first paint happens
	# once, from a complete selection, rather than three times through partial ones.
	picker.select_id(ReferenceBuild.FRAME_ID)
	motor_picker.select_id(ReferenceBuild.MOTOR_ID)
	propeller_picker.select_id(ReferenceBuild.PROPELLER_ID)
	battery_picker.select_id(ReferenceBuild.BATTERY_ID)
	esc_picker.select_id(ReferenceBuild.ESC_ID)
	fc_picker.select_id(ReferenceBuild.FC_ID)

	_on_selection_changed()


## Picks the previous id back up if the rebuilt catalog still has it (the common case: an
## unrelated frame was added, or a different one deleted), and falls back to the reference id
## when it does not (the one case that changes it: the part just deleted was the one selected).
func _reselect(rail: PartPicker, previous_id: String, fallback_id: String) -> void:
	if previous_id == "" or not rail.select_id(previous_id):
		rail.select_id(fallback_id)


## The six rails, built fresh against `catalog`. Called once from _init and again from
## reload_catalog() — the one seam a catalog reload rebuilds through, so there is exactly one
## place that knows how a rail is made and wired.
func _build_rails() -> void:
	picker = FramePicker.new(catalog)
	picker.name = "Frame"
	_rails.add_child(picker)

	motor_picker = MotorPicker.new(catalog)
	motor_picker.name = "Motor"
	_rails.add_child(motor_picker)

	propeller_picker = PropellerPicker.new(catalog)
	propeller_picker.name = "Prop"
	_rails.add_child(propeller_picker)

	battery_picker = BatteryPicker.new(catalog)
	battery_picker.name = "Pack"
	_rails.add_child(battery_picker)

	esc_picker = EscPicker.new(catalog)
	esc_picker.name = "ESC"
	_rails.add_child(esc_picker)

	fc_picker = FcPicker.new(catalog)
	fc_picker.name = "FC"
	_rails.add_child(fc_picker)

	electronics_picker = ElectronicsPicker.new(catalog)
	electronics_picker.name = "Electronics"
	_rails.add_child(electronics_picker)
	# The one rail whose signal is not part_selected, because it does not select a part — it
	# emits the whole payload at once. Same destination as all six others: one handler rebuilds
	# the aircraft, so a bay emptied here cannot leave a panel describing a camera that is off.
	electronics_picker.components_changed.connect(_on_selection_changed)

	# A frame added or deleted changes the CATALOG, not just the rail — the camera distance is
	# computed from the largest arm in it, so the whole screen is rebuilt rather than the list
	# repopulated. Rebuilding is cheap here and a partially-refreshed Lab is the kind of state that
	# takes an afternoon to explain.
	picker.custom_frames_changed.connect(reload_catalog)

	# A motor added or deleted needs the same rebuild, and for one reason beyond keeping the rail
	# in step: the motor is what the drawn bell and the whole propulsion chain come from, so a
	# repopulated list beside a stale aircraft would be showing the builder someone else's motor.
	motor_picker.custom_motors_changed.connect(reload_catalog)

	# A propeller added or deleted rebuilds for two reasons at once: the drawn disc comes from its
	# diameter and blade count, and — the one that is not about this rail at all — a custom motor's
	# thrust_test may name the prop that just appeared, so the MOTOR list is what a merge changes.
	# PartsCatalog.load_with_custom merges props before motors precisely so that resolves.
	propeller_picker.custom_propellers_changed.connect(reload_catalog)

	# A pack added or deleted needs the same rebuild, and it is the category where a stale screen
	# would mislead most: the pack is usually the largest single mass in the build, so mass, CG and
	# every hover-throttle figure hanging off them move with it.
	battery_picker.custom_batteries_changed.connect(reload_catalog)

	# The two halves of the stack. Neither rail cross-references anything else, so neither needs the
	# ordering note the prop rail carries — but both reload for the same reason all six do: the
	# categories are not independent on screen, and a build panel showing the aircraft from before a
	# part existed is the failure this signal prevents.
	esc_picker.custom_escs_changed.connect(reload_catalog)
	fc_picker.custom_flight_controllers_changed.connect(reload_catalog)

	for rail in [picker, motor_picker, propeller_picker, battery_picker, esc_picker, fc_picker]:
		rail.part_selected.connect(_on_part_selected)


## Rebuilds Lab against a freshly-loaded catalog: a custom part was just added or deleted on one
## of the four authoring rails (frame, motor, propeller, pack). One seam for all four rather than
## a per-category refresh, because the categories are not independent — a custom prop changes what
## the motor rail can resolve — and a partially-refreshed Lab is the kind of state that takes an
## afternoon to explain. Named and public because it is also the seam a future "reload the catalog from
## disk" would use, and because the alternative — patching the rail in place — leaves the camera
## framed for the frame set that existed a moment ago (see _camera_distance_m).
##
## The current selection is carried over rather than reset to the reference build — adding a
## frame should not knock a builder off whatever they were looking at, and select_id() falling
## back to the reference id covers the one case that changes: the frame just deleted was the one
## selected.
##
## Old rail and world nodes are queue_free()'d rather than free()'d. This runs from inside a
## signal a rail child emitted from its own method body (FramePicker._delete_selected), so freeing
## that node immediately would free an object still executing on the call stack; queue_free() is
## the form Godot documents as safe to call on a node from within its own code.
func reload_catalog() -> void:
	var previous := selection()
	catalog = PartsCatalog.load_with_custom()

	for child in _rails.get_children():
		_rails.remove_child(child)
		child.queue_free()
	_build_rails()

	for child in _viewport.get_children():
		_viewport.remove_child(child)
		child.queue_free()
	_build_world()

	_reselect(picker, previous.get("frame", ""), ReferenceBuild.FRAME_ID)
	_reselect(motor_picker, previous.get("motor", ""), ReferenceBuild.MOTOR_ID)
	_reselect(propeller_picker, previous.get("propeller", ""), ReferenceBuild.PROPELLER_ID)
	_reselect(battery_picker, previous.get("battery", ""), ReferenceBuild.BATTERY_ID)
	_reselect(esc_picker, previous.get("esc", ""), ReferenceBuild.ESC_ID)
	_reselect(fc_picker, previous.get("flight_controller", ""), ReferenceBuild.FC_ID)
	# The payload restores by a different route than _reselect, and the difference is "": an empty
	# bay is a VALID previous selection here, where on every other rail an empty id means "nothing
	# was chosen, fall back". So the fallback is only taken when the id no longer resolves — a
	# custom camera deleted out from under the rail — and never merely because it is empty.
	for category in Build.OPTIONAL_COMPONENTS:
		var previous_id := str(previous.get(category, Build.DEFAULT_COMPONENT_IDS[category]))
		if not electronics_picker.select_component(category, previous_id):
			electronics_picker.select_component(
				category, str(Build.DEFAULT_COMPONENT_IDS[category]))

	_on_selection_changed()


## The viewport the airframe is drawn in. Named accessor because the screenshot tooling and the
## tests reach for it, and because its World3D does not exist until this screen is inside the tree —
## a caller that needs the world has to be handed the viewport and resolve it later.
func viewport() -> SubViewport:
	return _viewport


## The rail column, for a shell that wants to place it somewhere other than where this screen puts
## it. Named accessor rather than making `_rails` public, because the point is to let a container
## be MOVED, not to let its tabs be rebuilt from outside — reload_catalog() is the only thing
## permitted to swap its children, and that stays in this file.
##
## GlassShell reparents this and `panels` out of the row on the way in, which is what leaves the
## SubViewportContainer alone in an HBox and therefore full-bleed. Nothing else here changes.
func rails() -> TabContainer:
	return _rails


## Lab's private 3D world: a turntable pivot holding the generated airframe, a camera at a
## fixed distance, and enough light to read carbon against nylon.
func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Light enough to read a near-black airframe against, dark enough to still look like a
	# workshop rather than a spec sheet. The first pass at 0.09 lost the frame entirely.
	env.background_color = Color(0.16, 0.17, 0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.57, 0.66)
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_environment := WorldEnvironment.new()
	world_environment.environment = env
	_viewport.add_child(world_environment)

	# The airframe sits still and level at the origin; only the camera moves.
	airframe = AirframeModel.new()
	frame_model = airframe.frame_model
	_viewport.add_child(airframe)

	_orbit = Node3D.new()
	_viewport.add_child(_orbit)

	# A dimmer fill fixed in the world, grazing almost horizontally. Carbon fibre is nearly
	# black and a single light turns half the airframe into a silhouette, which hides the arms.
	# Kept near-horizontal rather than steeply overhead so it still does something once the
	# orbit drops below the airframe.
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-6.0, 145.0, 0.0)
	fill_light.light_energy = 0.45
	_viewport.add_child(fill_light)

	# A weak bounce from below, standing in for the bench the build is sitting over. Without it
	# the underside — the view a battery tray or a payload mount is actually judged from — is
	# the one angle in the whole orbit that is lit only by ambient.
	var bounce_light := DirectionalLight3D.new()
	bounce_light.rotation_degrees = Vector3(62.0, 20.0, 0.0)
	bounce_light.light_energy = 0.32
	_viewport.add_child(bounce_light)

	_camera = Camera3D.new()
	# Horizontal FOV, held constant while the column's aspect changes — see _camera_distance_m.
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = CAMERA_FOV
	_camera.near = 0.005
	_camera.far = 20.0
	# Parked out along the boom's +Z with no rotation of its own. A camera looks down its own
	# -Z, so from there it already points straight back at the origin — and it keeps pointing
	# there for every possible boom rotation, with no look_at and no aiming maths that could
	# drift. Rotating the boom is then the entire orbit, and the distance is structurally
	# impossible to change by accident, which is what protects the no-zoom guarantee.
	_camera.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, _camera_distance_m()))
	_orbit.add_child(_camera)

	# The key light rides the boom, so whichever side of the build you orbit to is the side
	# that is lit. Underneath a frame is the one view that is otherwise always in shadow, and
	# it is exactly the view a battery tray or a payload mount needs.
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-28.0, -22.0, 0.0)
	key_light.light_energy = 1.5
	key_light.shadow_enabled = true
	_orbit.add_child(key_light)

	_apply_orbit()


## Distance at which the CATALOG'S LARGEST airframe spans LARGEST_FRAME_SCREEN_FRACTION of
## the view — so the framing is chosen by the biggest frame that exists and then held for
## every frame, big or small. Falls back to the reference build's arm if the catalog somehow
## has no frames, rather than dividing by zero and putting the camera at the origin.
func _camera_distance_m() -> float:
	var largest_arm_m := 0.0
	for frame in catalog.list_category("frame"):
		largest_arm_m = maxf(largest_arm_m, float(frame["specs"]["arm_mm"]) / 1000.0)
	if largest_arm_m <= 0.0:
		largest_arm_m = Build.REFERENCE_ARM_M

	# The props reach beyond the arm tips, so the widest thing the room has to hold is the
	# biggest arm carrying the biggest prop. Taking the arm alone put a 10" prop on a 10" frame
	# half off the edge of the viewport — and since Lab deliberately never zooms, there is no
	# recovering from that at the time it happens.
	var largest_prop_radius_m := 0.0
	for prop in catalog.list_category("propeller"):
		largest_prop_radius_m = maxf(
			largest_prop_radius_m, float(prop["specs"]["diameter_inches"]) * Build.INCH_M * 0.5)

	# Arm length is centre-to-motor, so the airframe spans twice that tip to tip.
	var span_m := (largest_arm_m + largest_prop_radius_m) * 2.0
	var required_width_m := span_m / LARGEST_FRAME_SCREEN_FRACTION

	# CAMERA_FOV is the HORIZONTAL angle, because the camera is set to KEEP_WIDTH (see
	# _build_world). That is load-bearing rather than incidental: Lab's viewport is the middle
	# column of a three-column layout, so it is portrait, and its aspect changes with the
	# window. Under Godot's default KEEP_HEIGHT the horizontal field of view would depend on
	# that column's width — which put the 10" frame's arms straight off both edges.
	return (required_width_m * 0.5) / tan(deg_to_rad(CAMERA_FOV) * 0.5)


## Any rail, one handler. The part that changed is deliberately ignored: the answer to "what
## should the screen show now" is the whole current selection, and taking the argument would
## invite a partial update that got some of it.
func _on_part_selected(_part: Dictionary) -> void:
	_on_selection_changed()


## The air the garage quotes in, changed. One method rather than a bare property assignment,
## because setting the air without re-deriving leaves five stats and every warning describing the
## previous field — and the whole point of this feature is that those numbers follow the place.
func set_air(p_air: AirDensity) -> void:
	air = p_air
	_on_selection_changed()


## Regenerates the Airframe document when, and only when, the selected frame changes.
##
## The guard is the whole function. Without it every selection change — a different pack, a nudged
## battery — would rebuild the geometry from the catalog and silently discard anything edited in the
## Airframe room, which is the one failure mode a document-backed editor must not have.
func _refresh_frame_document(frame: Dictionary) -> void:
	var id := str(frame.get("part_id", ""))
	if frame_document != null and id == _frame_document_id:
		return
	_frame_document_id = id
	frame_document = AirframeDocument.from_catalog_frame(frame)


## The single path from a selection to everything that shows it. Geometry, all three panels'
## spec rows and the five derived stats are rebuilt from ONE Build in ONE call, so there is no
## ordering in which a panel could be showing one component while the viewport shows another —
## the failure this project has already been bitten by.
func _on_selection_changed() -> void:
	var build := current_build()
	# The assembly reaches the BUILD before it reaches the drawing, because it is no longer only a
	# drawing: where the pack is strapped and how far it is slid decide where its mass sits, and
	# every panel below reads mass properties off this object. Resolved once, here, and handed to
	# both — the same dictionary, so the aircraft that is weighed is the aircraft that is drawn.
	build.set_assembly(tweaks.resolved_m(build))
	airframe.rebuild(build, tweaks)
	# A rebuild is new propellers, and they have to be turning: the hand spin is a property of the
	# room, not of the props that happen to be fitted.
	airframe.set_all_rates_rpm(HAND_SPIN_RPM)
	details.render(build.frame, build)
	# All four against the same frame, in the same call as every other panel — one handler rebuilds
	# everything, so an Airframe tab cannot be describing the frame you had a selection ago.
	_refresh_frame_document(build.frame)
	structure_details.render(frame_document)
	arms_details.render(frame_document)
	fasteners_details.render(frame_document)
	layout_details.render(frame_document)
	motor_details.render(build.motor, build)
	propeller_details.render(build.propeller, build)
	battery_details.render(build.battery, build)
	esc_details.render(build.esc, build)
	# The tune is derived BEFORE the FC panel is rendered, because that panel quotes what the
	# board's noise costs at the D gain actually installed — and "actually installed" is this
	# object. Derived from scratch on every selection change rather than patched: a part change
	# moves the plant, and a baseline that did not follow it would be the fixed-gain bug again in
	# a smaller box.
	tune = pid_tunes.tune_for(build)
	fc_details.render(build.fc, build, tune)
	charge_panel.render(build)
	electronics_details.render_components(build)
	# The fit panel is re-rendered on a PART change too, not only on a fit change: the limits are
	# derived from the parts, so a smaller motor has to narrow the shim slider then and there.
	# The airframe goes in as well as the build, because the fit rows are measured off the geometry
	# that was just rebuilt two lines above — so the overhang on the panel is the overhang on the
	# screen, in the same call, and cannot describe a pack that is no longer fitted.
	assembly_panel.render(build, airframe)
	tune_panel.render(build, tune)


## A shim, a pad or a standoff moved. Same single path as a part change — the geometry, the panels
## and the stats are all rebuilt from one Build — and then the configuration is written to disk.
##
## Saved on every change rather than on exit, because there is no exit: Lothal is closed by closing
## the window, and a configuration that only persists when you quit politely is a configuration that
## does not persist. The file is a few dozen bytes.
func _on_tweaks_changed() -> void:
	_on_selection_changed()
	tweaks.save()


## A gain was edited or reverted. NOT the same path as a part change: re-deriving here would throw
## away the edit that was just made, since the derivation knows nothing about what the builder
## typed. So the tune the panel already holds is recorded as-is and written straight through, for
## the reason a tweak is — there is no exit to save on.
func _on_tune_changed() -> void:
	pid_tunes.remember(current_build(), tune)
	pid_tunes.save()
	# The FC panel's noise row quotes the installed D gain, so it is the one other thing on screen
	# that a tuning edit makes stale.
	var build := current_build()
	fc_details.render(build.fc, build, tune)


## The charger was started, stopped, or had its compression changed. Written straight through,
## for the same reason a tweak is: there is no exit to save on.
func _on_charge_changed() -> void:
	pack_charge.save()


## Brings one of the right-hand panels to the front by its tab name ("Frame", "Motor", "Prop",
## "Fit"). Returns false for a name that is not there rather than selecting something arbitrary.
func show_panel(panel_name: String) -> bool:
	for i in panels.get_tab_count():
		if panels.get_tab_title(i) == panel_name:
			panels.current_tab = i
			return true
	return false


## The build currently selected across the four rails. Public because it is what crosses the
## boundary into Sim (labs-and-sim.md §4) — the field flies exactly the Build the garage
## assembled, and AppShell hands this one over rather than rebuilding it.
##
## The pack used to be pinned here to ReferenceBuild.BATTERY_ID, which was honest while there was
## no battery rail and is the single line this slice existed to delete: every number Lab reported
## was a number about one particular 4S 1500, and a rail that emitted a selection nobody read
## would have looked finished from every angle except the stats.
##
## **The guard comes from the Prop panel and not from a rail** (P10f). It is the same shape of
## deletion one slice later: `Build.from_ids` has taken a `guard_id` since P10b and nothing in the
## app passed one, so every number Lab reported was a number about an unguarded aircraft even when
## the ring was on screen. The trailing argument rather than a seventh picker, because the row is
## a dropdown on an inspector — see `PropellerDetails.guard_changed` for why it lives there.
func current_build() -> Build:
	return Build.from_ids(
		catalog,
		picker.selected_part()["part_id"],
		motor_picker.selected_part()["part_id"],
		propeller_picker.selected_part()["part_id"],
		battery_picker.selected_part()["part_id"],
		esc_picker.selected_part()["part_id"],
		fc_picker.selected_part()["part_id"],
		electronics_picker.component_ids(),
		air,
		propeller_details.guard_id()
	)


## Fits a whole selection at once — the mirror of selection(), and the direction that makes
## opening a saved drone possible at all.
##
## Returns the categories it COULD NOT fit, each with the id that failed. Nothing is substituted:
## a part that has left the catalog leaves its rail where it was and is named to the caller, so the
## app can say "this build used motor_custom_ab12, which is no longer in your parts". Quietly
## selecting a default instead would change the aircraft's mass and say nothing, which is the one
## behaviour a project file must never produce.
##
## Lives here rather than in the shell because the rails are this screen's — the shell is allowed
## to ask for a selection and to hand one back, and is not allowed to know how many pickers there
## are. Adding a seventh category means editing this function and selection() together, in one
## file, which is why they are next to each other.
func apply_selection(selection_by_category: Dictionary) -> Array:
	var failed: Array = []
	var pickers := {
		"frame": picker,
		"motor": motor_picker,
		"propeller": propeller_picker,
		"battery": battery_picker,
		"esc": esc_picker,
		"flight_controller": fc_picker,
	}
	for category in pickers:
		var part_id := String(selection_by_category.get(category, ""))
		if part_id == "":
			continue
		if not (pickers[category] as PartPicker).select_id(part_id):
			failed.append({"category": category, "part_id": part_id})

	for category in Build.OPTIONAL_COMPONENTS:
		if not selection_by_category.has(category):
			continue
		var part_id := String(selection_by_category[category])
		# "" is a real answer here — not fitted — and ElectronicsPicker takes it as one.
		if not electronics_picker.select_component(category, part_id) and part_id != "":
			failed.append({"category": category, "part_id": part_id})

	# The guard, by the same rule as the rest: "" is a real answer (not fitted), and an id this
	# catalog no longer knows is REPORTED rather than substituted. A guard silently dropped to
	# "none" would reopen a saved drone lighter, with more roll authority and — if it was a duct —
	# more current draw than the one that was saved.
	if selection_by_category.has("guard"):
		var guard_id := String(selection_by_category["guard"])
		if not propeller_details.select_guard(guard_id):
			failed.append({"category": "guard", "part_id": guard_id})
	return failed


## The whole selection as a category -> part_id dictionary — what crosses the door into the bench
## and into the field. Assembled here rather than at each door, so a fifth category cannot be
## added to the rails and forgotten by one of the two things that reads them.
func selection() -> Dictionary:
	var out := {
		"frame": picker.selected_part()["part_id"],
		"motor": motor_picker.selected_part()["part_id"],
		"propeller": propeller_picker.selected_part()["part_id"],
		"battery": battery_picker.selected_part()["part_id"],
		"esc": esc_picker.selected_part()["part_id"],
		"flight_controller": fc_picker.selected_part()["part_id"],
	}
	# Merged rather than listed, for the reason this function exists at all: the payload is
	# already a category -> id dictionary in exactly this shape, and copying its four keys out by
	# hand would be the fifth place a component category has to be remembered.
	out.merge(electronics_picker.component_ids())
	# The guard rides in the same dictionary as every other category, which is what lets the
	# project file, the bench door and the field door all carry it without any of them knowing
	# that it comes from an inspector row rather than from a rail.
	out["guard"] = propeller_details.guard_id()
	return out


# ---------------------------------------------------------------------------
# The inspection orbit
# ---------------------------------------------------------------------------

## Points the camera at the airframe from the given angles. Elevation is clamped short of
## either pole: straight overhead is where an orbit rig's up-vector becomes undefined, and
## going past it flips the airframe over, which is disorienting and tells you nothing new.
func set_orbit(azimuth_rad: float, elevation_rad: float) -> void:
	var limit := deg_to_rad(ELEVATION_LIMIT_DEG)
	_azimuth_rad = azimuth_rad
	_elevation_rad = clampf(elevation_rad, -limit, limit)
	_apply_orbit()


## Nudges the orbit, as a drag does. This is the builder taking the view over, so the idle
## motion stops and stays stopped.
func orbit_by(azimuth_delta_rad: float, elevation_delta_rad: float) -> void:
	auto_orbit = false
	set_orbit(_azimuth_rad + azimuth_delta_rad, _elevation_rad + elevation_delta_rad)


func elevation_deg() -> float:
	return rad_to_deg(_elevation_rad)


func azimuth_deg() -> float:
	return rad_to_deg(_azimuth_rad)


## The camera's transform in Lab's world, composed by hand rather than read from
## global_transform — Lab is constructed before it is parented, and in the headless tests it
## is never parented at all.
func camera_world_transform() -> Transform3D:
	return _orbit.transform * _camera.transform


## Azimuth about the vertical, then elevation in the frame that azimuth already turned. Node3D
## defaults to YXZ euler order, which composes them in exactly that order, so the two angles
## behave as an orbit rather than as two independent world-axis spins.
##
## The X rotation is negated because a camera parked at +Z swings DOWN under a positive
## rotation about +X, and a positive elevation should raise it.
func _apply_orbit() -> void:
	if _orbit != null:
		_orbit.rotation = Vector3(-_elevation_rad, _azimuth_rad, 0.0)


## The charger, and then the orbit. Charging is the one thing in Lab where time passes at all —
## and it is the compressed half of labs-and-sim.md §5's asymmetry, the draining half of which
## happens in the benches and in the field.
##
## The file is written on the frames that actually moved something rather than on every frame,
## and only while the charger is running. That is a few writes a second while a pack fills and
## none at all the rest of the time, which is the same bargain the assembly tweaks strike: a
## configuration that only persists when you quit politely is a configuration that does not
## persist, and Lothal is closed by closing the window.
func _process(delta: float) -> void:
	if charge_panel != null and charge_panel.tick(delta):
		pack_charge.save()

	if _orbit == null or _dragging or not auto_orbit:
		return

	_auto_elevation_time += delta
	var phase := TAU * _auto_elevation_time / AUTO_ELEVATION_PERIOD_S
	set_orbit(
		_azimuth_rad + deg_to_rad(AUTO_ORBIT_DEG_S) * delta,
		deg_to_rad(AUTO_ELEVATION_CENTRE_DEG + AUTO_ELEVATION_SWING_DEG * sin(phase))
	)


## Drag anywhere over the viewport to orbit by hand: horizontal swings around the build,
## vertical rises over the top plate and drops under the belly. Releasing hands the azimuth
## back to the slow automatic turn, but leaves the elevation where it was put.
##
## There is deliberately no scroll-to-zoom. The camera distance is what makes two frames
## comparable at a glance (see _camera_distance_m), and a zoom control would let that go
## without anything looking wrong.
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		return

	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		orbit_by(
			deg_to_rad(motion.relative.x * DRAG_DEG_PER_PIXEL),
			deg_to_rad(-motion.relative.y * DRAG_DEG_PER_PIXEL)
		)
