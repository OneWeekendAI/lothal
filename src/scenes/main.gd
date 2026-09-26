extends Node3D
## Wires the verified physics core (src/sim, src/assembly, src/fc) into a 3D scene.
## This script is a thin consumer that reads DroneCore's state and moves nodes; it
## contains no dynamics (architecture.md's layering). Two FlightController
## implementations sit behind one interface (angle mode, rate/acro mode). A real
## gamepad is preferred when one is connected; keyboard is the laptop-only fallback
## (both digital, bang-bang input — there is no analog feel from a keyboard).
##
## Keyboard:  Arrows = pitch/roll   A/D = yaw   W/S = throttle trim   Space = mode toggle
## Gamepad:   right stick = pitch/roll   left stick = yaw/throttle   button A = mode toggle
## Tab hides the build panel; parts are picked with the mouse. L swaps the listener between
## the pilot's position on the ground and the chase camera. C swaps the FPV feed between the
## corner inset and the whole screen. R arms and disarms the flight recorder; the HUD says so for
## as long as it is running, and disarming writes the log to user://logs.

const SUBSTEPS := 8   # 120 Hz physics_process x 8 = 1 kHz dynamics (physics.md §6)
const STICK_DEADZONE := 0.08
const MAX_YAW_RATE_CMD := 1.0
## Analog throttle trim either side of hover, in absolute throttle. A stick is modulated
## continuously, so the full range is usable.
const STICK_THROTTLE_TRIM := 0.3
## Vertical acceleration, in g, that a fully-held keyboard throttle key should produce.
## See keyboard_throttle().
const KEYBOARD_CLIMB_G := 0.25
const MODE_TOGGLE_BUTTON := JOY_BUTTON_A

## Where flight logs land, taken from the library that reads them rather than spelled out again
## here. A writer and a reader that each declare the directory separately agree right up until one
## of them is edited — and the symptom would be Studio listing an empty room while the logs pile up
## somewhere else.
const LOG_DIR := FlightLogLibrary.LOG_DIR

@onready var drone: Node3D = $Drone
@onready var camera: Camera3D = $Camera3D
@onready var ground_mesh: MeshInstance3D = $Ground/GroundMesh
@onready var ground_collision: CollisionShape3D = $Ground/CollisionShape3D

# Behind (+Z, per the coordinate contract's -Z-is-forward) and above the ~15cm frame.
# Applied in the drone's own heading frame, not world space (see _update_camera).
const CAMERA_OFFSET := Vector3(0, 0.9, 2.4)
## How quickly the camera closes on its target position, per second.
const CAMERA_FOLLOW_RATE := 6.0
## Aim slightly above the airframe so the drone sits low in frame and the gate ahead gets
## the screen space, rather than the drone sitting dead centre hiding what it is flying at.
const CAMERA_LOOK_AHEAD_UP := 0.6

# Where the drone sits before the course exists (and the seed for _previous_position).
# The real start line comes from GateCourse.start_position() — spawning airborne matters
# either way, since the ground plane's surface is y = 0.
const SPAWN_POSITION := Vector3(0, 2.0, 0)
## Frame half-height (~5 mm) plus a little clearance: this far above the ground and the drone has
## hit it. Read from GateCourse rather than typed here, because the course places the start line
## and the respawn at exactly this clearance and a second copy of the number is how a spawn ends up
## below the altitude this test rejects — a respawn loop, with no evidence but a drone that will
## not stay put.
const CRASH_ALTITUDE_M := GateCourse.GROUND_CLEARANCE_M

var core: DroneCore
var build: Build
## The air's own motion at the selected weather (design §4.3). Built once in `_ready`, HANDED to
## every `core` this scene builds after — one stream survives a part swap, and only a respawn
## (`_reset_to`) re-seeds it, the same rule `core.gyro` lives under. Read-only here and in
## `DroneCore`: `Sim authors nothing`, and `ConditionsLibrary.load_from()` is a read.
var wind: Wind
## The name of the conditions set `wind` was built from, held because `Wind` keeps only the numbers
## a builder typed and not the label on them. Stamped onto every Build this scene flies so the
## HUD's countdown and Lab's estimate are quoted in — and named after — the same weather.
var conditions_name := Conditions.STANDARD_NAME
var build_panel: BuildPanel
## The visible aircraft, generated from `build` rather than authored in main.tscn — see the
## comment on the Drone node there, and AirframeModel's header.
var airframe: AirframeModel
## The parts this scene opens on, as a category -> part_id dictionary. AppShell sets it from
## Lab's rails before adding the scene to the tree, which is how the build crosses the door
## (labs-and-sim.md §4). Left empty it falls back to the reference build, so main.tscn still
## runs on its own — capture_frame.gd and F5-from-the-editor both load it directly.
var initial_selection: Dictionary = {}
## The designer's edit to the fitted frame, set by RoomHost beside `initial_selection` — the frame
## drawn in the garage is the frame flown in the field. `{}` flies the catalogue frame.
var initial_frame_edit: Dictionary = {}
## How much of the top of the screen is already covered when this scene is reached through
## AppShell, which draws its tab bar on a CanvasLayer above the flight scene. Set the same way
## and for the same reason as `initial_selection`: zero when main.tscn runs on its own.
var ui_top_inset := 0.0
## The builder's fit adjustments, read from the same file Lab writes. Read from disk rather than
## handed over with the selection, deliberately: it is one file, Lab is the only writer, and a copy
## passed through the door would be a second place for the shim height to live. Sim never writes it
## — the field authors nothing (labs-and-sim.md §1).
var tweaks: AssemblyTweaks = AssemblyTweaks.load_from()
## How much charge each pack has left. AppShell hands its own instance over so both rooms are
## looking at one set of packs within a session; a direct load of main.tscn reads the file itself.
##
## This is the ONE thing Sim writes back (labs-and-sim.md §4). Fly for four minutes on a
## four-minute pack and you land on an empty battery, and it is still empty when you walk back
## into the garage. That is not Sim authoring anything — it is Sim reporting what happened, which
## is what §3 says the field is for.
var pack_charge: PackCharge = PackCharge.load_from()
## The builder's PID gains, read from the same file Lab writes — and READ ONLY. Sim flies the tune
## the garage set and may not write one back (labs-and-sim.md §1, "Sim authors nothing"; §7's
## corollary, which is what settled where tuning lives). There is no in-flight tuning control, and
## the absence is the boundary rather than an omission.
var pid_tunes: PidTunes = PidTunes.load_from()
var hud: Hud
## The field, read from the library Lab writes. Read from disk rather than handed over with the
## selection, for exactly the reason `tweaks` above is: it is one file, Lab is the only writer, and
## a copy passed through the door would be a second place a gate position lives. Sim never writes
## it — the field authors nothing (labs-and-sim.md §1). AppShell may replace this with its own
## instance before _ready so that both rooms are looking at one library within a session.
var course_library: CourseLibrary = CourseLibrary.load_from()
var course: GateCourse = course_library.selected()
## The places the courses are laid out in, read the same way and for the same reason as
## `course_library` above: one file, Lab is the only writer, and Sim reads it and never writes it.
## RoomHost replaces this with its own instance before `adopt_selected_course()` so both rooms read
## one library (room_host.gd's `show_sim`). This load is what a direct run of `main.tscn` gets, and
## it is why the field initialiser stays: there is no door in that case to hand anything over.
var site_library: SiteLibrary = SiteLibrary.load_from()
## THE WEATHER, handed across the door like the other two libraries (`RoomHost.show_sim`) so that
## Lab and Sim look at ONE set within a session. This `load_from()` is the standalone-boot
## fallback — main.tscn run on its own from the editor, and capture_frame.gd — where there is no
## door to hand anything over; it is not the door path's copy.
##
## It used to be read fresh in `_ready` instead, which is the thing `room_host.gd`'s own comment
## forbids in as many words: "not a second copy read off disk before the save". That was safe only
## because every weather edit saves synchronously, and it is the seam a piece of unpersisted
## weather state falls straight through.
var conditions_library: ConditionsLibrary = ConditionsLibrary.load_from()
## THE GROUND (F4). Null is flat at zero — a course whose site is missing is flown on the field
## every course was flown on before terrain existed, rather than on nothing.
var terrain: Terrain = _course_terrain()
## WHAT IS STANDING ON IT (F6). Read off the same site `terrain` came from, so the two can never
## name two different places — an obstacle and a hill that quietly disagreed about which site they
## were describing is exactly the stale-reading failure this whole room exists to close. Empty for
## a site that is not there, the same "nothing means nothing standing" reading `terrain`'s `null`
## already carries.
var obstacles: Array[Obstacle] = _course_obstacles()
## Keyed on the course being flown, so a time set on one track is never reported as the record on
## another. See lap_timer.gd's header — this is the one line that stops a best lap becoming a lie.
var lap_timer := LapTimer.new(_lap_key())
var course_renderer: CourseRenderer
var drone_audio: DroneAudio
## The feed from the fitted camera — inset by default, whole screen on C. See FpvView: the swap
## moves the PLACEMENT between two permanent cameras rather than moving a camera between viewports,
## so there is no state in which a viewport has none.
var fpv_view: FpvView
var _l_was_pressed := false
var _c_was_pressed := false
var _r_was_pressed := false
## The recorder, when one is armed, and null the rest of the time (LTHL-51).
##
## RECORDING IS EXPLICIT AND THE NULL IS THE OFF STATE. The alternative shapes — always-on, or an
## always-on ring buffer — were considered and rejected on cost: at 55 columns and 1 kHz a session
## buffers 55 MB per minute, and a scene that quietly accumulated that for as long as the app was
## left open is a scene that eventually falls over in a way the pilot did not ask for. The price is
## stated plainly because it is real: the flight worth having is often the one nobody expected, and
## an unarmed recorder cannot produce it. That is what the persistent HUD indicator is for — it
## makes the armed state something the pilot can see rather than remember.
##
## A LOG BELONGS TO ONE AIRCRAFT. The header names the build that flew, so a recording cannot
## survive a part change; _on_build_changed closes it out rather than letting one file span two
## aircraft while claiming to describe one.
var _recorder: FlightRecorder = null
## One control path. The mode switch changes what produces the rate setpoints and nothing
## else — see src/fc/flight_controller.gd.
var fc := FlightController.new()
var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0}
var _mode_button_was_pressed := false
var _tab_was_pressed := false
## Previous frame's position, so gate passage is tested against the segment actually
## travelled rather than against a single sample (see GateCourse.segment_passes_gate).
var _previous_position := SPAWN_POSITION
var _last_heading := Basis.IDENTITY
## Where the chase view is, independent of which camera node is currently rendering it. See
## _update_camera for why this cannot live on the node.
var _chase_transform := Transform3D.IDENTITY
## Cached per build: hover_throttle() sweeps the thrust curve to find its peak, which is
## far too much work to redo on every input frame.
var _hover_throttle := 0.0

## Takes the course the handed-over library has selected, and re-keys the lap timer to it. Called
## by AppShell after it hands `course_library` over and BEFORE this scene enters the tree, so the
## field is finished by the time _ready builds anything from it — the same ordering, and for the
## same reason, as the build crossing the door.
##
## Re-keying the timer is the part that must not be forgotten: a timer still holding the previous
## course's best would be reporting a record set somewhere else, which is the exact failure
## lap_timer.gd's header exists to describe.
func adopt_selected_course() -> void:
	course = course_library.selected()
	terrain = _course_terrain()
	obstacles = _course_obstacles()
	lap_timer = LapTimer.new(_lap_key())
	_rebuild_ground()


## THE KEY A BEST LAP IS FILED UNDER, and the ONE place this scene builds it. Both callers —
## the initialiser above and `adopt_selected_course()` — go through here, because two spellings of
## a hash is how one of them quietly stops passing the world.
##
## PASSING THE WORLD IS THE WHOLE POINT, and it is the line that was missing. `fingerprint()`
## defaults all three of `p_air`/`p_site`/`p_conditions` to `null` (see `gate_course.gd:312`), and
## a bare `course.fingerprint()` therefore keys a lap on the GATE GEOMETRY AND NOTHING ELSE — so a
## lap flown at 3500 m in a 20 m/s gale over a 6 m rise is filed under the same key as a calm
## sea-level lap on flat ground. That is, word for word, the record `gate_course.gd`'s own header
## exists to prevent, and it shipped: `air` was a property on `GateCourse` before the field room,
## the bare call read it, and turning it into a defaulted argument silently absorbed this call
## site.
##
## The air is COMPOSED from the same two typed facts the Field room composes it from
## (`AirDensity.compose`, and `FieldSystem.air()` one door over), not read off a third place.
##
## Appending terms does NOT orphan an existing best lap: every term is gated on being
## non-standard (`p_air.is_standard()`, `terrain.is_flat_at_zero()`, `has_steady_wind()`), so on
## default data the hash is byte-identical to the bare call's. That is pinned by
## `tests/test_fingerprint_survival.gd`, and measured: applying this fix moved no check.
func _lap_key() -> String:
	var where := _course_site()
	var weather := conditions_library.selected()
	return course.fingerprint(AirDensity.compose(where, weather), where, weather)


## The site under the open course. A course pointing at a site that is not there falls back to the
## selected one, on the Field room's `site()` rule: a damaged file lands somewhere flyable and the
## room still opens. `terrain` and `obstacles` both read off THIS, never off two separate lookups,
## so they cannot name two different sites on the same frame.
func _course_site() -> Site:
	var where := site_library.site(course.site_id)
	if where == null:
		where = site_library.selected()
	return where


## The ground under the open course. Null is flat at zero — see the field's own header.
func _course_terrain() -> Terrain:
	var where := _course_site()
	return where.terrain if where != null else null


## What is standing on that same ground. Empty for a site that is not there, matching
## `_course_terrain()`'s null.
func _course_obstacles() -> Array[Obstacle]:
	var where := _course_site()
	return where.obstacles if where != null else []


## The ground's mesh, collider and grid tiling — all from `terrain` (F5), plus whatever
## `obstacles` (F6) stands on it, drawn and collidable through the SAME triangle list `TerrainMesh`
## builds either from.
##
## CALLED FROM TWO PLACES, AND ONLY ONE OF THEM HAS THE NODES. `_ready` always has them. But
## `RoomHost.show_sim` calls `adopt_selected_course()` BEFORE `add_child(sim)`, and `@onready`
## members resolve on tree entry — so on the shipped path into Sim, `ground_mesh` and
## `ground_collision` are still null when the adopt path reaches here. That used to raise
## `Invalid assignment of property 'mesh' ... on a base object of type 'Nil'` on EVERY entry into
## Sim: harmless, because `_ready` rebuilds a few lines later and every field the adopt path sets
## was already set before the call, but it is production stderr noise on the happy path, and real
## aborts hide in exactly that texture.
##
## So the nodes are GUARDED rather than assumed, inline and not behind a helper (this repo's own
## abort rule: a guard in a helper still aborts the helper). Returning early is correct and not a
## skipped rebuild: the only way to get here without the nodes is before `_ready`, and `_ready`
## rebuilds unconditionally. The staleness the two call sites exist to prevent is unaffected —
## `RoomHost` frees `sim` on exit, so a re-entry runs `_ready` again anyway.
##
## `GROUND_SIZE_M` used to be an independent 400 m constant; it is not one any more (Ruling 34) —
## it was only ever the grid material's tiling size (`GroundGrid.build_material`'s `uv1_scale`),
## so it now follows the terrain's own extent, the way the field room already ties its
## ground tiling to the layout it is drawing.
func _rebuild_ground() -> void:
	if ground_mesh == null or ground_collision == null:
		return
	ground_mesh.mesh = TerrainMesh.build_mesh(terrain, obstacles)
	ground_collision.shape = TerrainMesh.build_collider(terrain, obstacles)
	var extent := terrain.extent() if terrain != null else Vector2(Terrain.DEFAULT_WIDTH_M, Terrain.DEFAULT_LENGTH_M)
	var ground_size := maxf(absf(extent.x), absf(extent.y))
	ground_mesh.material_override = GroundGrid.build_material(ground_size)

## Whether the aircraft has hit the ground. STILL AN ALTITUDE COMPARISON and deliberately not a
## physics query: the recorded decision above was that a shape cast costs more than it tells us,
## and `Terrain.height_at` is arithmetic, so giving the ground a shape does not overturn it. Static
## and pure so the decision can be tested by calling it as well as by reading it.
##
## `p_terrain` null is flat at zero, the ground this scene tested against before F4.
static func _check_crash(at: Vector3, p_terrain: Terrain) -> bool:
	var ground := p_terrain.height_at(at.x, at.z) if p_terrain != null else 0.0
	return at.y < ground + CRASH_ALTITUDE_M


## THE AIR'S OWN MOTION, built from the builder's selected conditions — the settling time
## included. `Wind._init` takes `p_gust_tau_s` as a defaulted argument rather than reading it off
## the set, so a bare `Wind.new(conditions)` silently flies at the shipped default no matter what
## the Field room's "Gust settle" field says. That is what this scene used to do, and it is why
## that field had no consumer at all: it moved a number nothing downstream ever read.
##
## Static and pure for `_check_crash`'s reason: it can be CALLED by a check rather than read out
## of the source. BUT THAT IS AN API, NOT THE WIRING, and this header used to claim otherwise —
## a check that calls `Main.make_wind()` says nothing about whether `_ready` below calls it, and
## measured, reverting the line that does to `Wind.new(selected_conditions)` left the whole suite
## green. The wiring is covered separately, by a check that BOOTS `main.tscn` and reads
## `scene.wind` (`tests/test_field_room.gd`'s `_the_booted_scene_flies_the_typed_settle_time`).
## Neither stands alone: this one is the oracle, that one is the subject.
static func make_wind(p_conditions: Conditions) -> Wind:
	return Wind.new(p_conditions, p_conditions.gust_tau_s)

func _ready() -> void:
	# Read off the HANDED-OVER library (see `conditions_library` above), not re-loaded here. The
	# standalone-boot fallback is that member's own initialiser, so this line is the same object
	# either way and there is never a second copy.
	var selected_conditions := conditions_library.selected()
	wind = make_wind(selected_conditions)
	conditions_name = selected_conditions.conditions_name
	_rebuild_ground()

	course_renderer = CourseRenderer.new(course)
	add_child(course_renderer)

	# Added before the build panel, because the panel emits build_changed from its own
	# _ready and that path runs all the way through to placing the listener.
	drone_audio = DroneAudio.new()
	add_child(drone_audio)

	var ui_layer := CanvasLayer.new()
	add_child(ui_layer)

	# Stated here as well as on AppShell. Sim inherits the shell's theme when it is reached
	# through the door, but main.tscn also runs on its own — F5 from the editor, and
	# capture_frame.gd — and unthemed is exactly the state in which a screenshot of Sim stops
	# being a picture of the app. Same cached Theme either way, so the door path is unchanged.
	var theme := LothalTheme.get_theme()

	hud = Hud.new()
	hud.theme = theme
	ui_layer.add_child(hud)

	# Bottom right, which is the one corner of this screen nothing else claims — the build panel is
	# top left, the lap block top right, and the HUD's flight readouts bottom left.
	var fpv_overlay := MarginContainer.new()
	fpv_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	fpv_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fpv_overlay.add_theme_constant_override("margin_right", 12)
	fpv_overlay.add_theme_constant_override("margin_bottom", 12)
	ui_layer.add_child(fpv_overlay)

	fpv_view = FpvView.new()
	fpv_view.theme = theme
	fpv_overlay.add_child(fpv_view)

	airframe = AirframeModel.new()
	drone.add_child(airframe)

	# load_with_custom so a frame the builder entered in Lab can be FLOWN. Reading, not authoring:
	# labs-and-sim.md's rule is that Lab authors and Sim does not, and nothing in this scene
	# creates or edits a custom part — it resolves the ids it was handed.
	build_panel = BuildPanel.new(PartsCatalog.load_with_custom(), _opening_selection())
	build_panel.frame_edit = initial_frame_edit
	build_panel.theme = theme
	# This scene owns both, so this is where the two are told about each other rather than
	# either one reaching across for the other's geometry.
	build_panel.top_inset = ui_top_inset
	build_panel.bottom_reserve = Hud.FLIGHT_BLOCK_HEIGHT
	build_panel.build_changed.connect(_on_build_changed)
	ui_layer.add_child(build_panel)   # emits build_changed on _ready, which builds the core

## Every part change lands here: new mass properties, new coefficients, new drone. The
## airframe is rebuilt from scratch rather than patched, so there is no way for a stat on
## the panel to disagree with what is being flown.
func _on_build_changed(new_build: Build) -> void:
	# Before anything else, because everything below replaces the aircraft this log is about. A
	# recording that ran on through a part swap would carry one header naming one build over rows
	# flown by two, and nothing in the file would say where the change happened.
	if _recorder != null:
		_stop_recording()
	build = new_build
	core = build.build_drone_core()
	# The field this build is about to fly in, not a fresh calm core — a `DroneCore` is built with
	# no opinion about the air (`wind = null`, drone_core.gd), and this is the one path every part
	# change lands on, so there is no ordering in which the aircraft on screen flies one weather and
	# the loop stepping it assumes another.
	core.wind = wind
	# And the same weather onto the Build itself, not only onto the loop stepping it (F8 fix round
	# 1, review finding 5). `remaining_flight_time_min()` — the HUD's "N min left" — averages over
	# the mission profile in this Build's own `field_wind_mps`, so leaving it at 0.0 here would
	# have the garage quote one number under the selected conditions and the HUD count down from
	# the calm one, which is precisely the split that function's docstring promises cannot happen.
	build.field_wind_mps = wind.speed_mps
	build.field_conditions_name = conditions_name
	# The pack comes out of the bag as it actually is. Seeded here rather than inside Build,
	# which must stay pure: the reference build's 11.7:1 and 29% are quoted at the nominal
	# voltage datum and cannot become a function of how much flying anyone has done.
	pack_charge.apply_to(build.battery["part_id"], core.powertrain.battery)
	# Solved AFTER the pack is seeded, and against that pack rather than against nominal, so
	# centring the stick hovers whatever came out of the bag. A fresh pack rests above nominal
	# and needs less than the quoted 29%; a half-used one needs a little more. Left alone from
	# here: the pack drains as you fly and the aircraft drifts slowly down, which is the
	# consequence, not a bug.
	_hover_throttle = build.hover_throttle_for(core.powertrain.battery)
	# The gains follow the aircraft. Adopted rather than reconstructed, so the integrator state
	# holding the aircraft trimmed survives — and adopted HERE, on the one path every part change
	# lands on, so there is no ordering in which the airframe on screen is one aircraft and the
	# loop flying it is tuned for another.
	fc.rate_loop.adopt_tune(pid_tunes.tune_for(build))
	# And the motor map the builder configured, on the same one path, for the same reason: the
	# core above already flies it, and a mixer commanding yaw through a different map than the
	# physics reacts with is the disagreement config-room design §5.1 exists to prevent.
	fc.rate_loop.config = build.config
	# One call, and the airframe on screen is the airframe being flown — frame, motors and
	# props, all from this same Build. There is no second description of the aircraft to keep
	# in step, which is what the old _fit_drone_mesh_to_arm was: a scale factor applied to a
	# box, correcting a 110 mm arm that had been baked into the scene file.
	airframe.rebuild(build, tweaks)
	# Re-pointed on every rebuild, and it has to be: a rebuild frees the old ComponentMesh, so a
	# lens held across one is a freed node. Handed the airframe's own answer to where its camera is
	# rather than looking one up here.
	if fpv_view != null:
		fpv_view.attach(airframe.camera_eye())
	# A lap time belongs to a build. Swapping a part mid-lap starts the attempt over rather
	# than letting a 6S pack finish a lap a 4S one started.
	_restart_course()

## The parts to open on: whatever Lab handed over, falling back to the reference build for a
## direct load of main.tscn. Filled per-category so a partial hand-over still yields a complete
## selection rather than a missing key deep inside Build.
func _opening_selection() -> Dictionary:
	var defaults := {
		"frame": ReferenceBuild.FRAME_ID,
		"motor": ReferenceBuild.MOTOR_ID,
		"propeller": ReferenceBuild.PROPELLER_ID,
		"battery": ReferenceBuild.BATTERY_ID,
		"esc": ReferenceBuild.ESC_ID,
		"flight_controller": ReferenceBuild.FC_ID,
	}
	# The optional components join the same table, from Build's own defaults. Merged rather than
	# written out, so a fifth component cannot be added to the mass model and left off the one
	# aircraft that loads without Lab in front of it.
	defaults.merge(Build.DEFAULT_COMPONENT_IDS)
	for category in defaults:
		# has() rather than get(category, default), because "" is a real hand-over here — an empty
		# bay — and a value-based fallback would quietly refit a camera the builder took off.
		if initial_selection.has(category):
			defaults[category] = initial_selection[category]
	return defaults

## Back to gate 1 with a fresh clock — a new build gets a clean attempt.
func _restart_course() -> void:
	course.reset()
	lap_timer.invalidate_lap()
	if course_renderer != null:
		course_renderer.highlight_next()
	if drone_audio != null:
		# The pilot stands at the start line and stays there. That is the whole point of the
		# default listener: the drone leaves, comes back, and passes — which is where
		# distance, air absorption and doppler actually do something.
		drone_audio.set_listener(drone_audio.listener_mode, course.start_position(terrain))
	_reset_to(course.start_position(terrain), course.start_forward())

## Day 3's gate (week1.md): "Ground is one static box; hitting it resets to spawn." Day 6
## moves that to the last gate cleared, so a clip on gate 6 does not send a new pilot back
## to the start line. Ground contact is a plain altitude test rather than a Jolt query —
## the ground is a shape now (F4) but it is still arithmetic, so a shape cast would still cost
## more than it tells us. See _check_crash.
func _respawn_after_crash() -> void:
	# A crash is a landing, and a landing is when the pack state is written down. Recorded rather
	# than reset: hitting the ground does not refill a battery.
	persist_pack_charge()
	lap_timer.invalidate_lap()
	# The teleport below moves position and velocity discontinuously. A recording that spans it
	# and says nothing is a log that lies about acceleration — see FlightRecorder.discontinuities.
	# The lap is NOT split into a second file: a lap that ends in the dirt is still data, and the
	# most interesting seconds in the file are the ones just before it.
	if _recorder != null:
		_recorder.discontinuities += 1
	# Asked once. The two calls this replaced were one arithmetic answer either way; now that the
	# answer reads the terrain, they were also one shape of the ground being sampled twice.
	var at := course.respawn_position(terrain)
	_reset_to(at, course.next_gate()["position"] - at)

## Places the drone level, stationary, and pointed at `forward` (yaw only — respawning
## already banked would just hand the pilot a second crash).
func _reset_to(p_position: Vector3, forward: Vector3) -> void:
	core.rigid_body.position_m = p_position
	core.rigid_body.velocity_mps = Vector3.ZERO
	core.rigid_body.angular_velocity_rad_s = Vector3.ZERO

	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length() > 0.001:
		# Basis.looking_at points -Z down `forward`, which is the coordinate contract's
		# forward, so this needs no correction term.
		core.rigid_body.orientation = Basis.looking_at(flat.normalized(), Vector3.UP).get_rotation_quaternion()
	else:
		core.rigid_body.orientation = Quaternion.IDENTITY

	# Spawn with the motors already at hover RPM. Spinning up from dead through the ~30 ms
	# lag costs ~0.4 m/s of sink, and with no altitude hold this week that never comes back.
	core.prime_motors(_hover_throttle)
	# The drone is somewhere else now. Without this the synthesiser ramps from the RPM and
	# frequency it had at the moment of the crash to the ones it has after the respawn,
	# which is heard as a swoop across a teleport that never happened.
	if drone_audio != null:
		drone_audio.reset()
	fc.reset()
	# A respawn is a fresh sensor too: without this the gyro carries its filter state and its
	# noise stream across a teleport, which is the same class of artefact as the audio swoop
	# the line above prevents.
	core.gyro.reset()
	# And a respawn replays the same gust rather than continuing the old stream, for the identical
	# reason: "the same flight twice" must mean the same flight, gust for gust.
	wind.reset()
	rc.throttle = _hover_throttle
	_previous_position = position

	# Snap the camera rather than let it ease in from wherever the crash left it — easing
	# across the map after every respawn is disorienting and costs the pilot the first second.
	drone.position = position
	drone.quaternion = core.rigid_body.orientation
	_last_heading = Basis.IDENTITY
	_chase_transform.origin = position + _drone_heading() * CAMERA_OFFSET
	_chase_transform = _chase_transform.looking_at(
		position + Vector3.UP * CAMERA_LOOK_AHEAD_UP, Vector3.UP)
	# The FPV lens needs no snap: it is bolted to the airframe, which has already been moved.
	fpv_view.place_lenses(camera, _chase_transform)

## Writes the pack's state back to the shared store. Called on landing, and by AppShell on the
## way out of the field — walking back to the garage is the other way a flight ends.
func persist_pack_charge() -> void:
	if core != null and build != null:
		pack_charge.record_from(build.battery["part_id"], core.powertrain.battery)


func _physics_process(delta: float) -> void:
	if core == null:
		return
	if Input.is_key_pressed(KEY_TAB) != _tab_was_pressed:
		_tab_was_pressed = Input.is_key_pressed(KEY_TAB)
		if _tab_was_pressed:
			build_panel.visible = not build_panel.visible

	if Input.is_key_pressed(KEY_L) != _l_was_pressed:
		_l_was_pressed = Input.is_key_pressed(KEY_L)
		if _l_was_pressed:
			_toggle_listener()

	if Input.is_key_pressed(KEY_C) != _c_was_pressed:
		_c_was_pressed = Input.is_key_pressed(KEY_C)
		if _c_was_pressed:
			_toggle_fpv()

	if Input.is_key_pressed(KEY_R) != _r_was_pressed:
		_r_was_pressed = Input.is_key_pressed(KEY_R)
		if _r_was_pressed:
			_toggle_recording()

	if Input.get_connected_joypads().is_empty():
		_read_keyboard()
	else:
		_read_gamepad()

	var substep_dt := delta / SUBSTEPS
	for i in SUBSTEPS:
		var motor_cmds := fc.update(core.rigid_body.orientation, core.gyro.rate_rad_s, rc, substep_dt)
		core.step(motor_cmds, substep_dt)
		# EVERY SUBSTEP, i.e. the full 1 kHz, and inside the loop rather than once per frame.
		# Sampling at the 120 Hz frame rate instead would be a decimation by 8 that the header
		# could not report, and it would alias everything above 60 Hz — which is where the frame
		# resonance this log exists to measure lives. capture() appends to a packed buffer and
		# touches no file, which is what makes it affordable here; the determinism test in
		# tests/test_flight_recorder.gd is what proves it does not perturb the flight.
		if _recorder != null:
			_recorder.capture(core.observables)

	# Score the segment actually flown this frame, BEFORE any crash reset — otherwise a
	# pass that ends in a clip just past the ring is silently thrown away.
	_score_gates(delta)

	if _check_crash(core.rigid_body.position_m, terrain):
		_respawn_after_crash()

	drone.position = core.rigid_body.position_m
	drone.quaternion = core.rigid_body.orientation
	_previous_position = core.rigid_body.position_m

	_update_camera(delta)

	# The rotors turn at the RPM the physics computed, per motor, from the same published
	# observables the audio and the HUD read. There is no second place a rotor speed exists: what you
	# see turning, what you hear, and what is making thrust are one number (architecture.md).
	airframe.set_rates_rpm(core.observables.rpm)

	# Audio and the HUD are handed the same published observables and nothing else — the
	# property architecture.md calls the test of the design. Adding this consumer changed
	# no physics.
	# The CHASE listener is the chase VIEW's position, which after a C press is no longer the scene
	# camera's — reading the node here would put the ears wherever the FPV lens is and call it chase.
	drone_audio.update(core.observables, _chase_transform.origin)

	hud.render(core, build, course, lap_timer, fc.is_rate_mode())
	# Off the recorder's own figures, not off a frame counter here. See Hud.set_recording.
	hud.set_recording(_recorder != null,
		_recorder.duration_s() if _recorder != null else 0.0,
		_recorder.row_count() if _recorder != null else 0)
	hud.tick_banner(delta)

## Swaps between hearing the drone from where the pilot stands and hearing it from the
## chase camera. Ground is the default and the more convincing of the two, but the camera
## is what the eyes are doing, and some people want those to agree.
func _toggle_listener() -> void:
	var next := DroneAudio.Listener.CHASE_CAMERA
	if drone_audio.listener_mode == DroneAudio.Listener.CHASE_CAMERA:
		next = DroneAudio.Listener.PILOT_GROUND
	drone_audio.set_listener(next, course.start_position(terrain))
	hud.show_banner("EARS: %s" % ("PILOT" if next == DroneAudio.Listener.PILOT_GROUND else "CHASE"))

## Swaps the FPV feed between the corner inset and the whole screen. Says so in the banner either
## way, including when the build has no camera to fly off — a key that silently does nothing reads
## as a broken key rather than as an aircraft without a camera on it.
func _toggle_fpv() -> void:
	if not fpv_view.is_fitted():
		hud.show_banner("VIEW: no camera fitted")
		return
	hud.show_banner("VIEW: %s" % ("FPV" if fpv_view.toggle_main() else "CHASE"))

## R, and it is a toggle rather than a hold: a log worth having is minutes long and no key is held
## for minutes.
func _toggle_recording() -> void:
	if _recorder == null:
		_start_recording()
	else:
		_stop_recording()

## Arms the recorder against the aircraft that is flying RIGHT NOW.
##
## Three things are handed over and each one would be wrong to look up later. The build, because
## the header names it. The tune, because the gains in force are the garage's and the recorder
## refuses to guess them — `null` there would write a log that declined to say what flew. And
## `core.gyro`, THE SENSOR THAT IS ACTUALLY IN THE AIRCRAFT: Build.gyro() constructs a fresh one
## on every call, so asking the build would describe a sensor that never flew, and the header's
## filtering block — the thing that decides whether a log is admissible to the resonance analysis
## at all — would be describing the wrong instrument.
func _start_recording() -> void:
	_recorder = FlightRecorder.new(build, 1, pid_tunes.tune_for(build), core.gyro)
	hud.show_banner("REC  started")

## Writes the buffer out and disarms. A failed write says so on the HUD and still disarms, because
## the alternative is a recorder that stays armed accumulating rows nobody can get out.
func _stop_recording() -> void:
	var recorder := _recorder
	_recorder = null
	if recorder.row_count() == 0:
		hud.show_banner("REC  nothing captured")
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
	var path := log_path(Time.get_datetime_dict_from_system())
	if recorder.save(path):
		# The count, not just the fact. A pilot who armed the recorder by hand is the only thing
		# standing between a 55 MB/minute buffer and a full disk, and "wrote 132000 rows" is the
		# number that makes the next decision for them.
		hud.show_banner("REC  saved  %d rows  %s" % [recorder.row_count(), path.get_file()], 4.0)
	else:
		hud.show_banner("REC  COULD NOT WRITE  %s" % path, 4.0)

## Timestamped, and deliberately NOT named after the build.
##
## Build.fingerprint() is slash-joined part ids, which is a path and not a filename, and mangling
## it into one would produce a second, lossy spelling of an identity that already has a canonical
## one. The aircraft is named INSIDE the file, where a reader — Studio, or a human with an editor —
## gets the full fingerprint rather than a flattened approximation of it. The filename's only job
## is to be unique and to sort chronologically, which a fixed-width timestamp does for free.
##
## Takes the clock as an argument rather than reading it, so this is testable without one.
static func log_path(now: Dictionary) -> String:
	return "%s/flight-%04d%02d%02d-%02d%02d%02d.csv" % [
		LOG_DIR, now["year"], now["month"], now["day"], now["hour"], now["minute"], now["second"]]

## Leaving the field ends a flight, and an armed recorder must not go down with the scene. This is
## the same reasoning as persist_pack_charge — which is deliberately NOT the hook used here, since
## a crash calls that one and a crash is not the end of a recording.
func _exit_tree() -> void:
	if _recorder != null:
		_stop_recording()

## Chase cam. The offset is rotated by the drone's HEADING, not left in world space: with a
## fixed world offset the camera keeps facing -Z no matter which way the drone is pointed,
## so turning the drone swings the target out of frame instead of the camera following it
## round. That is survivable for a hover test and fatal for a gate course — the gate you are
## meant to fly at spends most of the lap off-screen.
##
## Yaw only, deliberately. Rolling the camera with the airframe is what an FPV feed actually
## looks like, and it is also what makes people put the controller down after ten seconds. Now that
## an actual FPV feed exists, that sentence is a division of labour rather than a compromise: this
## view stays watchable and FpvView rolls.
##
## THE CHASE PLACEMENT IS HELD IN A FIELD RATHER THAN ON A CAMERA NODE, because after a C press the
## node it lands on is the inset's, not the scene's. Easing off `camera.global_position` would read
## its state back off whichever camera happened to be wearing the chase view last frame, so a swap
## would make the chase view jump from wherever the OTHER view was standing.
func _update_camera(delta: float) -> void:
	var heading := _drone_heading()
	var target_position := drone.position + heading * CAMERA_OFFSET

	# Eased rather than snapped, so the camera lags the airframe slightly through a fast
	# rotation instead of pivoting rigidly with it.
	var blend := clampf(delta * CAMERA_FOLLOW_RATE, 0.0, 1.0)
	_chase_transform.origin = _chase_transform.origin.lerp(target_position, blend)
	_chase_transform = _chase_transform.looking_at(
		drone.position + Vector3.UP * CAMERA_LOOK_AHEAD_UP, Vector3.UP)

	# One call places both lenses. Which node ends up with which view is FpvView's business.
	fpv_view.place_lenses(camera, _chase_transform)

## The drone's yaw as a basis, with pitch and roll flattened out. Falls back to the last
## heading when the drone is pointed straight up or down, where yaw is undefined.
func _drone_heading() -> Basis:
	var forward := core.rigid_body.orientation * Vector3(0, 0, -1)
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length() < 0.05:
		return _last_heading
	_last_heading = Basis.looking_at(flat.normalized(), Vector3.UP)
	return _last_heading

## Gate scoring and lap timing. The timer is ticked before the gate test so a lap's final
## instant is inside the lap rather than in the next one.
func _score_gates(delta: float) -> void:
	lap_timer.tick(delta)

	if not course.advance(_previous_position, core.rigid_body.position_m):
		return

	var completed_lap := course.just_completed_lap()
	var previous_best := lap_timer.best_lap_s
	lap_timer.on_gate_passed(completed_lap)
	course_renderer.highlight_next()

	if not completed_lap:
		return
	if previous_best <= 0.0 or lap_timer.last_lap_s < previous_best:
		hud.show_banner("NEW BEST  %s" % LapTimer.format(lap_timer.last_lap_s))
	else:
		hud.show_banner("LAP  %s" % LapTimer.format(lap_timer.last_lap_s))

func _read_gamepad() -> void:
	var mode_pressed := Input.is_joy_button_pressed(0, MODE_TOGGLE_BUTTON)
	_apply_mode_toggle(mode_pressed)

	var roll_axis := _deadzone(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X))
	var pitch_axis := _deadzone(-Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	var yaw_axis := _deadzone(Input.get_joy_axis(0, JOY_AXIS_LEFT_X))
	var throttle_axis := _deadzone(-Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	_apply_rc(roll_axis, pitch_axis, yaw_axis, throttle_axis)

func _read_keyboard() -> void:
	_apply_mode_toggle(Input.is_key_pressed(KEY_SPACE))

	var roll_axis := 0.0
	if Input.is_key_pressed(KEY_RIGHT): roll_axis += 1.0
	if Input.is_key_pressed(KEY_LEFT): roll_axis -= 1.0

	var pitch_axis := 0.0
	if Input.is_key_pressed(KEY_UP): pitch_axis += 1.0
	if Input.is_key_pressed(KEY_DOWN): pitch_axis -= 1.0

	var yaw_axis := 0.0
	if Input.is_key_pressed(KEY_D): yaw_axis += 1.0
	if Input.is_key_pressed(KEY_A): yaw_axis -= 1.0

	var throttle_axis := 0.0
	if Input.is_key_pressed(KEY_W): throttle_axis += 1.0
	if Input.is_key_pressed(KEY_S): throttle_axis -= 1.0

	_apply_rc(roll_axis, pitch_axis, yaw_axis, throttle_axis)

func _apply_mode_toggle(pressed: bool) -> void:
	if pressed and not _mode_button_was_pressed:
		fc.toggle_mode()   # also clears integral/derivative history from the other mode
	_mode_button_was_pressed = pressed

func _apply_rc(roll_axis: float, pitch_axis: float, yaw_axis: float, throttle_axis: float) -> void:
	rc.roll = roll_axis
	rc.pitch = pitch_axis
	rc.yaw = yaw_axis * MAX_YAW_RATE_CMD
	# Throttle stick is a trim around hover, not an absolute 0..1 — full-stick-down should
	# not cut the motors to zero and drop it; there is no altitude hold this week (week1.md).
	#
	# The trim range is smaller on a keyboard, because keyboard input is bang-bang: a key is
	# either fully down or fully up, so a range wide enough to be expressive on an analog
	# stick leaves a keyboard pilot choosing between hover-minus-a-lot and climbing out of
	# the map. Leaning to fly forward already costs vertical thrust, so a keyboard pilot
	# needs a usable amount of "slightly more than hover" to hold height through a gate.
	if Input.get_connected_joypads().is_empty():
		rc.throttle = keyboard_throttle(_hover_throttle, throttle_axis)
	else:
		rc.throttle = clampf(_hover_throttle + throttle_axis * STICK_THROTTLE_TRIM, 0.0, 1.0)

## Keyboard throttle, as a multiple of THIS build's hover throttle rather than a fixed
## absolute trim.
##
## Two reasons an absolute trim is the wrong shape. Thrust goes as throttle squared, so a
## trim of +0.12 on a build that hovers at 29% is nearly double the thrust — about 1 g of
## climb, which flies the drone straight over the top of a gate rather than through it
## (measured: it crossed gate 1's plane 5.8 m off-centre through a 1.5 m ring). And hover
## throttle varies hugely across the catalog — 26% on a 6S pack, 40% on the Li-ion — so any
## single absolute number is too coarse for one build and too weak for another.
##
## Solving thrust = weight * (1 + a/g) with thrust proportional to throttle squared gives
## the multiplier below, so a fully-held key means the same *acceleration* on every build.
static func keyboard_throttle(hover_throttle: float, axis: float) -> float:
	var target_g := clampf(axis, -1.0, 1.0) * KEYBOARD_CLIMB_G
	return clampf(hover_throttle * sqrt(maxf(1.0 + target_g, 0.0)), 0.0, 1.0)

func _deadzone(value: float) -> float:
	if absf(value) < STICK_DEADZONE:
		return 0.0
	return value
