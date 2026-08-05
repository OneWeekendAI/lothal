class_name FrameBenchScreen
extends Control
## The frame bench (labs-and-sim.md §2.1) — the fourth of Lab's component benches, and the one that
## closes the loop: the frame is the FIRST part you choose and was the only one you could not test.
##
## Read FrameBench's header for what is being measured and why. This file is the room around it.
##
## ---------------------------------------------------------------------------
## WHAT IT LOOKS LIKE
## ---------------------------------------------------------------------------
##
## The assembled airframe, hanging, at a fixed distance — and the distance is fixed by the CATALOG'S
## LARGEST frame rather than by the one on the bench, which is Lab's framing rule and is load-bearing
## here for a different reason. A bench that framed each subject to fill the view would draw a 3"
## toothpick and a 7" long-range at exactly the same size on screen, and the two screenshots this
## slice exists to produce would show two identically-sized aircraft rolling at different speeds for
## no visible reason. The size difference IS the lesson.
##
## THE BIFILAR PENDULUM IS THE REAL-WORLD ANALOGUE AND IS DELIBERATELY NOT DRAWN. Builders measure
## an airframe's moment of inertia by hanging it from two wires, twisting it and timing the swing —
## which is exactly what this bench does, and it was tempting to dress the room as one. But a
## bifilar rig measures the axis the wires hang along and this bench steps all three, so two thirds
## of the time the picture would show a rig that could not have produced the number beside it. The
## analogue is stated in words and the aircraft is drawn turning about the axis actually under test.
##
## ---------------------------------------------------------------------------
## THE COMPARISON IS THE SECOND LINE ON THE CHART
## ---------------------------------------------------------------------------
##
## One frame's inertia in kg*m^2 means nothing to anyone. So every run is drawn against the 5"
## reference build doing the same thing, stepped in lockstep on its own powertrain — the yardstick
## line. The band between them is the difference the frame made, which is the only form in which
## this number has ever meant anything to a builder.
##
## The yardstick's pack is its OWN, freshly built and held at the nominal datum. It never touches
## PackCharge: a comparison line that quietly drained the user's reference pack every time they
## looked at a frame would be the worst kind of consequence, since the only evidence would be a
## number that was wrong later.
##
## ---------------------------------------------------------------------------
## THE MOTORS TURN, SO IT COSTS AND IT IS AUDIBLE
## ---------------------------------------------------------------------------
##
## A step response asks four motors for four different throttles. They answer with real RPM out of a
## real pack, which drains (§5) exactly as it does on the thrust stand. The rotors turn on the rate
## the powertrain hands them and on no rate this file chooses (§2.1), and the bench makes noise
## through DroneAudio with no change to any file under src/audio/ — if anyone finds themselves
## editing one to make this room audible, it is publishing to the wrong place.
##
## NOTHING HERE FLIES. There is no rigid body, no integrator over six degrees of freedom, no flight
## controller and no DroneCore. One axis is free and the aircraft cannot go anywhere.

const PHYSICS_HZ := FrameBench.PHYSICS_HZ
const MAX_SUBSTEPS := 300

const VIEWPORT_SIZE := Vector2i(960, 720)
const CAMERA_FOV := 34.0
## How much of the view the catalog's LARGEST airframe spans. Held for every frame, big or small —
## see the header. Lab's own constant is 0.68; this is tighter because the bench has no rails
## alongside it and the chart underneath takes the height instead.
const LARGEST_FRAME_SCREEN_FRACTION := 0.60

## Three-quarter view from above and off the nose. Straight on, a roll is a line rotating about a
## point and reads as nothing; from directly above it does not read at all.
const CAMERA_AZIMUTH_DEG := 26.0
const CAMERA_ELEVATION_DEG := 24.0

## The chart's y axis, in deg/s. Fixed rather than fitted, for the reason BandTrace's own header
## gives: an axis that rescaled to its data would draw every frame's response as the same shape.
const AXIS_TOP_DEG_S := FrameBench.TARGET_RATE_DEG_S * 1.3

## The x axis, in seconds. Sized for the SLOWEST frame in the catalog — the 10" long-range, which
## takes 68 ms — rather than for FrameBench.RUN_SECONDS, which is the backstop for a build that
## never arrives and would draw every real response inside the leftmost twentieth of the chart.
##
## Fixed rather than fitted to the run, for BandTrace's own reason: an axis that rescaled would draw
## the 65 mm whoop's 26 ms and the 10" long-range's 68 ms as identical curves, and the difference
## between them is the answer.
const CHART_SPAN_S := 0.10
const AXIS_STEP_DEG_S := 100.0
## One sample per PHYSICS SUBSTEP. Far finer than the other benches', because their events last
## seconds and a roll step is over in forty milliseconds — at the battery bench's interval the whole
## response would be ten points. The backstop run is 0.8 s, so this cannot exceed BandTrace's own
## sample ceiling before decimation takes over.
const SAMPLE_INTERVAL := 1.0 / FrameBench.PHYSICS_HZ

var catalog: PartsCatalog
var frame_id: String
var motor_id: String
var propeller_id: String
var battery_id: String
var esc_id: String

var bench: FrameBench
## The 5" reference build running the identical step, on its own pack, as the yardstick line. Null
## only if the reference build itself failed to assemble.
var yardstick: FrameBench
var pack_charge: PackCharge = null
## The builder's own assembly configuration, or null for whatever the parts imply. Handed over by
## AppShell rather than re-read from disk, the same way the catalog and the pack charge are: Lab is
## the only writer of it, and a second copy read here could disagree with the one Lab is editing.
##
## The bench NEEDS it, which it did not before this slice. Where the pack is strapped now decides
## where the aircraft's mass is, so a bench that built its aircraft without the assembly would
## report the inertia and the centre of mass of a differently-assembled quad from the one in the
## garage — and the centre-of-mass row is the one row on this panel where that would be the whole
## content of the reading.
var tweaks: AssemblyTweaks = null

var airframe: AirframeModel
var trace: BandTrace
var instruments: FrameInstruments
var drone_audio: DroneAudio

## Which axis the next run steps. Roll on arrival: it is the axis the arm-length result lives on.
var axis := FrameBench.AXIS_ROLL
## Off on arrival. Walking into the room must not start spinning motors, and a bench you have to
## start is also what a real one is.
var running := false

var _build: Build
var _viewport: SubViewport
var _camera: Camera3D
var _title: Label
var _run_button: Button
var _axis_buttons: Dictionary = {}
## What the yardstick measured on its own completed run, for the panel's comparison sentence. Empty
## while the bench is sitting on the reference frame, which is when there is nothing to compare to.
var _comparison: Dictionary = {}
## How much of each bench's per-substep history has already been drawn. The trace is fed from the
## histories rather than sampled once per frame: a roll step is over in tens of milliseconds, so a
## screen sampling at 60 Hz would draw the entire response as three points and the two lines would
## be two straight segments that happened to end in different places.
var _drawn := 0


func _init(p_catalog: PartsCatalog, p_frame_id: String = "", p_motor_id: String = "",
		p_propeller_id: String = "", p_battery_id: String = "", p_esc_id: String = "",
		p_pack_charge: PackCharge = null, p_tweaks: AssemblyTweaks = null) -> void:
	catalog = p_catalog
	pack_charge = p_pack_charge
	tweaks = p_tweaks
	frame_id = p_frame_id if p_frame_id != "" else ReferenceBuild.FRAME_ID
	motor_id = p_motor_id if p_motor_id != "" else ReferenceBuild.MOTOR_ID
	propeller_id = p_propeller_id if p_propeller_id != "" else ReferenceBuild.PROPELLER_ID
	battery_id = p_battery_id if p_battery_id != "" else ReferenceBuild.BATTERY_ID
	esc_id = p_esc_id if p_esc_id != "" else ReferenceBuild.ESC_ID

	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.anchor_right = 1.0
	row.anchor_bottom = 1.0
	add_child(row)

	# Padded for the same reason the other benches' stages are: with no panel behind this column it
	# runs to the window edges and the caption loses its first character.
	var stage_pad := MarginContainer.new()
	stage_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		stage_pad.add_theme_constant_override("margin_%s" % side, LothalTheme.SPACE_2)
	row.add_child(stage_pad)

	var stage := VBoxContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_pad.add_child(stage)

	_title = Label.new()
	_title.theme_type_variation = &"MutedLabel"
	stage.add_child(_title)

	var viewport_container := SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(viewport_container)

	# Its own World3D, for the same reason Lab and the thrust stand have one: Sim is a separate
	# scene with its own cameras and lights, and a shared world lets two rooms render into each other.
	_viewport = SubViewport.new()
	_viewport.size = VIEWPORT_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	# Without this the bench is SILENT, and silently so — a SubViewport does not route 3D audio
	# unless asked. The same line, and the same trap, as BenchScreen's.
	_viewport.audio_listener_enable_3d = true
	viewport_container.add_child(_viewport)

	_build_world()

	trace = BandTrace.new()
	trace.x_axis = BandTrace.XAxis.TIME_FINE
	trace.x_max = CHART_SPAN_S
	trace.base_interval = SAMPLE_INTERVAL
	trace.y_unit = "deg/s"
	trace.y_step = AXIS_STEP_DEG_S
	trace.upper_colour = InstrumentPanel.MUTED_COLOUR
	trace.lower_colour = InstrumentPanel.EFFICIENCY_COLOUR
	trace.fill_colour = Color(0.55, 0.86, 0.68, 0.14)
	trace.reference_label = "%.0f deg/s" % FrameBench.TARGET_RATE_DEG_S
	trace.empty_hint = "Throw the stick and see how hard this airframe is to start turning."
	trace.custom_minimum_size = Vector2(420, 180)
	trace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.add_child(trace)

	_build_controls(stage)

	instruments = FrameInstruments.new()
	instruments.custom_minimum_size = Vector2(InstrumentPanel.PANEL_WIDTH, 0)
	instruments.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(instruments)

	_rebuild()


## The bench's private 3D world: the airframe hanging on its two wires, lit well enough to read
## carbon against nylon, and a camera at a distance the whole catalog shares.
func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.50, 0.55, 0.64)
	env.ambient_light_energy = 1.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_environment := WorldEnvironment.new()
	world_environment.environment = env
	_viewport.add_child(world_environment)

	airframe = AirframeModel.new()
	airframe.name = "Airframe"
	_viewport.add_child(airframe)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-32.0, -34.0, 0.0)
	key_light.light_energy = 1.55
	key_light.shadow_enabled = true
	_viewport.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-6.0, 140.0, 0.0)
	fill_light.light_energy = 0.48
	_viewport.add_child(fill_light)

	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = CAMERA_FOV
	_camera.near = 0.005
	_camera.far = 20.0
	# Composed by hand rather than aimed with look_at, for the same reason LabScreen and BenchScreen
	# compose theirs: this screen is built before it is parented, and in the headless tests it is
	# never parented at all. Node3D.look_at needs a tree and prints an ERROR without one, which in
	# the runner reads exactly like a failing test.
	var distance := _camera_distance_m()
	var offset := Basis.from_euler(Vector3(
		-deg_to_rad(CAMERA_ELEVATION_DEG), deg_to_rad(CAMERA_AZIMUTH_DEG), 0.0)) \
		* Vector3(0.0, 0.0, distance)
	_camera.transform = Transform3D(Basis.looking_at(-offset, Vector3.UP), offset)
	_viewport.add_child(_camera)

	# The synthesiser the flight sim and the thrust stand use, unmodified, reading the same
	# Observables. Nothing about the frame bench is a new audio path.
	drone_audio = DroneAudio.new()
	drone_audio.name = "FrameBenchAudio"
	_viewport.add_child(drone_audio)


## The distance at which the CATALOG'S LARGEST airframe fills LARGEST_FRAME_SCREEN_FRACTION of the
## view. Deliberately not per-build — see the header. This is Lab's rule and Lab's arithmetic; the
## fall-back exists so a catalog with no frames puts the camera somewhere rather than at the origin.
func _camera_distance_m() -> float:
	var largest_arm_m := 0.0
	for frame in catalog.list_category("frame"):
		largest_arm_m = maxf(largest_arm_m, float(frame["specs"]["arm_mm"]) / 1000.0)
	if largest_arm_m <= 0.0:
		largest_arm_m = Build.REFERENCE_ARM_M

	var largest_prop_radius_m := 0.0
	for prop in catalog.list_category("propeller"):
		largest_prop_radius_m = maxf(
			largest_prop_radius_m, float(prop["specs"]["diameter_inches"]) * Build.INCH_M * 0.5)

	var span_m := (largest_arm_m + largest_prop_radius_m) * 2.0
	return (span_m / LARGEST_FRAME_SCREEN_FRACTION * 0.5) / tan(deg_to_rad(CAMERA_FOV) * 0.5)


func _build_controls(stage: VBoxContainer) -> void:
	var controls := HBoxContainer.new()
	stage.add_child(controls)

	var caption := Label.new()
	caption.text = "AXIS"
	caption.theme_type_variation = &"MutedLabel"
	controls.add_child(caption)

	# Three axes rather than roll alone. Roll is where the arm-length result lives, but yaw is in a
	# different regime entirely and a bench that only offered roll would leave the builder believing
	# all three behave alike.
	for index in FrameBench.AXIS_NAMES.size():
		var button := Button.new()
		button.text = String(FrameBench.AXIS_NAMES[index]).capitalize()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(84, 28)
		button.pressed.connect(set_axis.bind(index))
		controls.add_child(button)
		_axis_buttons[index] = button

	_run_button = Button.new()
	_run_button.custom_minimum_size = Vector2(148, 28)
	_run_button.pressed.connect(start_run)
	controls.add_child(_run_button)


## Regenerates the airframe, the bench and its yardstick for the current selection, and clears the
## trace. A new frame is a new run: two step responses drawn over each other are not two runs, they
## are one illegible chart — and the second line on this chart already means something else.
func _rebuild() -> void:
	_build = Build.from_ids(catalog, frame_id, motor_id, propeller_id, battery_id, esc_id)
	# The assembly reaches the build before the drawing, exactly as it does in Lab: the mass model
	# reads it, and everything this screen reports is read off the resulting mass properties.
	if tweaks != null:
		_build.set_assembly(tweaks.resolved_m(_build))
	airframe.rebuild(_build, tweaks)
	airframe.transform = Transform3D.IDENTITY

	# The bench is handed the DRAWN airframe, so the clearance on the panel is the clearance of the
	# aircraft on screen rather than a second derivation of it (airframe_model.gd:193).
	bench = FrameBench.for_build(_build, airframe)
	if pack_charge != null:
		pack_charge.apply_to(battery_id, bench.powertrain.battery)

	# The yardstick's own pack, freshly built and held at the nominal datum. Never PackCharge's —
	# see the header.
	yardstick = FrameBench.for_build(ReferenceBuild.build())
	yardstick.powertrain.battery.set_to_nominal_datum()

	running = false
	_comparison = {}
	_drawn = 0
	trace.clear()
	trace.configure(0.0, AXIS_TOP_DEG_S, FrameBench.TARGET_RATE_DEG_S)
	_refresh_labels()
	instruments.render_build(bench, _comparison)
	instruments.render_live(bench.readings())
	_publish_to_screen()


func _refresh_labels() -> void:
	_title.text = "%s carrying four %s on %s — %.0f mm arms, %.0f g all up" % [
		_build.frame["name"], _build.motor["name"], _build.propeller["name"],
		_build.arm_m * 1000.0, _build.all_up_weight_g()]
	if _run_button != null:
		_run_button.text = "Running…" if running else "Throw the %s stick" % FrameBench.AXIS_NAMES[axis]
		_run_button.disabled = running
	for index in _axis_buttons:
		(_axis_buttons[index] as Button).button_pressed = index == axis
		(_axis_buttons[index] as Button).disabled = running


## Picks the axis the next run steps. Kept as a plain method the button's signal calls, so the bench
## stays drivable from a test and from the screenshot tool.
func set_axis(p_axis: int) -> void:
	if running:
		return
	axis = clampi(p_axis, 0, FrameBench.AXIS_NAMES.size() - 1)
	trace.clear()
	_refresh_labels()
	instruments.render_live(bench.readings())


## Puts a different frame on the bench, or different parts on the frame.
func set_selection(p_frame_id: String, p_motor_id: String, p_propeller_id: String,
		p_battery_id: String, p_esc_id: String) -> void:
	frame_id = p_frame_id
	motor_id = p_motor_id
	propeller_id = p_propeller_id
	battery_id = p_battery_id
	esc_id = p_esc_id
	_rebuild()


## Trims both aircraft at their own hover throttle and throws full stick on the chosen axis.
##
## Each at ITS OWN hover, deliberately, and it is the only fair comparison: a 7" long-range and the
## 5" reference do not hover at the same throttle, and stepping both from the reference's trim would
## measure one of them from a collective it never sits at.
func start_run() -> void:
	trace.clear()
	airframe.transform = Transform3D.IDENTITY
	bench.begin(axis, bench.hover_collective())
	yardstick.begin(axis, yardstick.hover_collective())
	_drawn = 0
	running = true
	_refresh_labels()


## One frame of bench. Separate from _process so a headless test — and the screenshot tool — can
## drive it without a scene tree delivering frames, and so the two never drive it at once.
func advance(delta: float) -> void:
	if not running:
		return

	bench.advance(delta)
	# The yardstick keeps stepping after this build has arrived, and vice versa: whichever reaches
	# 500 deg/s second is the one whose line has further to travel, and cutting it off at the other's
	# finish would hide exactly the difference the chart exists to show.
	yardstick.advance(delta)
	_draw_new_history()

	var reading := bench.readings()
	instruments.render_live(reading)
	_publish_to_screen()

	if not bench.running and not yardstick.running:
		running = false
		# The comparison sentence needs the yardstick's COMPLETED run, which is why it is captured
		# here rather than at the start: before the step there is no torque to quote a ratio of.
		_comparison = yardstick.readings() if frame_id != ReferenceBuild.FRAME_ID else {}
		instruments.render_build(bench, _comparison)
		_refresh_labels()


## Everything on screen comes from the published observables and from the bench's own measurement,
## and from nowhere else. The rotors in particular: PropellerMesh renders a rate it is handed and
## derives none, and the hand giving it one here is holding the number the powertrain computed.
## Feeds the chart every substep neither bench has drawn yet, paired by index so the two lines are
## read against the same clock. A bench that has already finished holds its last rate rather than
## dropping off the chart — the reference build reaching 500 deg/s first is the WHOLE result, and a
## line that simply stopped there would read as data running out rather than as an aircraft arriving.
func _draw_new_history() -> void:
	var mine: Array = bench.history
	var theirs: Array = yardstick.history
	var available: int = maxi(mine.size(), theirs.size())
	while _drawn < available:
		var mine_row: Array = mine[mini(_drawn, mine.size() - 1)] if not mine.is_empty() else [0.0, 0.0]
		var their_row: Array = theirs[mini(_drawn, theirs.size() - 1)] if not theirs.is_empty() else [0.0, 0.0]
		# The clock is whichever bench is still running, not this build's own — both step at the same
		# dt, so index i is the same instant for both. Taking this build's elapsed time would freeze
		# the x axis the moment it arrived and leave the reference's remaining travel undrawn, which
		# is precisely the part of the comparison worth seeing.
		trace.sample(maxf(float(mine_row[0]), float(their_row[0])),
			float(their_row[1]), float(mine_row[1]))
		_drawn += 1


func _publish_to_screen() -> void:
	airframe.set_rates_rpm(bench.powertrain.observables.rpm)
	# The airframe turns by exactly the angle the measurement says it turned — not by an animation
	# curve chosen to look like rotation. Roll is about -Z, pitch about +X, yaw about -Y
	# (physics.md §1), which is the same contract inertia_kg_m2() is expressed in.
	var spin_axis: Vector3 = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, -1, 0)][bench.axis]
	airframe.transform = Transform3D(Basis(spin_axis, bench.angle_rad), Vector3.ZERO)


func _process(delta: float) -> void:
	if visible:
		advance(delta)
		if drone_audio != null and drone_audio.is_inside_tree():
			drone_audio.update(bench.powertrain.observables, _camera.global_position)


## Writes what this run took out of the pack back to the persistent store. Called when the room is
## left rather than every frame — see BatteryBenchScreen.persist_pack_charge. Only the bench's own
## pack: the yardstick's is not the user's.
func persist_pack_charge() -> void:
	if pack_charge != null:
		pack_charge.record_from(battery_id, bench.powertrain.battery)


## The airframe under test, as a Build. Public because the bench is judged against the same analytic
## numbers Build computes, and the tests ask it for them.
func current_build() -> Build:
	return _build


## The viewport the airframe and the synthesiser both live in. Exposed so a test can assert the one
## property that decides whether any of this is audible — see test_bench.gd.
func audio_viewport() -> SubViewport:
	return _viewport


func camera_transform() -> Transform3D:
	return _camera.transform


## What the bench is reading, as numbers, with the yardstick's alongside — so a test and the panel
## cannot disagree about what the bench says.
func readings() -> Dictionary:
	var out := bench.readings()
	out["yardstick_rate_deg_s"] = yardstick.readings()["rate_deg_s"]
	out["yardstick_peak_alpha_rad_s2"] = yardstick.peak_alpha_rad_s2
	out["yardstick_inertia_kg_m2"] = yardstick.inertia_kg_m2()[bench.axis]
	out["yardstick_time_to_rate_s"] = yardstick.time_to_rate_s
	return out
