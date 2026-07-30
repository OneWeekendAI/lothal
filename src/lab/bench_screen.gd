class_name BenchScreen
extends Control
## The thrust stand (labs-and-sim.md §2.1) — the most important of Lab's component benches
## and the one that defines the pattern: choose a candidate, put it on the bench, run it,
## judge it, keep it or reject it.
##
## What is under test is never a motor alone. A motor's behaviour is meaningless without the
## propeller bolted to it — the same 2207 is a mild freestyle motor on a 5x4.3 and an
## overloaded, current-limited brick on a 7-inch — so the unit under test is the PAIRING, and
## the pairing is whichever one is currently chosen on Lab's rails.
##
## NOTHING HERE FLIES. There is no rigid body, no integrator, no flight controller and no
## DroneCore anywhere in this file. It holds a Powertrain, which is the electro-mechanical
## half of the simulation and runs perfectly well without the other half. That absence is the
## entire point of the Lab/Sim split, and tests/test_bench.gd asserts it rather than trusting it.
##
## The bench is audible, and getting it audible took no audio code at all. DroneAudio and
## RotorSynth read only the published Observables; a Powertrain fills every field they read;
## so attaching the existing synthesiser to a bench is a two-line wiring job. If anyone ever
## finds themselves editing a file under src/audio/ to make a bench make noise, the split is
## wrong and this comment is the thing that was violated.

## Physics runs at 1 kHz, the same substep the flight loop uses, regardless of frame rate. A
## bench that stepped once per frame would be a different electrical model from the one Sim
## flies, which is precisely what sharing Powertrain exists to prevent.
const PHYSICS_HZ := 1000.0
## A long frame must not turn into a thousand substeps and a stall; it turns into a slightly
## short one instead. Bench state is not safety-critical and a hitch should cost accuracy,
## not responsiveness.
const MAX_SUBSTEPS := 40

## The swept ramp: idle to full and back. Long enough to watch the pack sag on the way up and
## recover on the way down, short enough that nobody walks away from it.
const SWEEP_SECONDS := 8.0

const VIEWPORT_SIZE := Vector2i(960, 720)
const CAMERA_FOV := 34.0
## How much of the view the swept disc should span. The pairing is the subject; unlike Lab,
## the bench frames whatever is on it rather than holding one distance for comparability,
## because here you are judging one pairing rather than comparing two airframes.
const SUBJECT_SCREEN_FRACTION := 0.62
## How far below the rotor the camera aims, as a fraction of the mount height. Keeps the column
## and its base plate in shot without letting the pairing drift out of the top of the frame.
const AIM_DROP_FRACTION := 0.42

var catalog: PartsCatalog
## The pairing under test, handed in by whoever opened the bench. Lab's rails decide it.
var motor_id: String
var propeller_id: String
var battery_id: String

var powertrain: Powertrain
var stand: BenchStand
var instruments: BenchInstruments
var drone_audio: DroneAudio

## Commanded throttle, 0..1. Driven by the slider, or by the sweep while one is running.
var throttle := 0.0
var sweeping := false

var _build: Build
var _viewport: SubViewport
var _camera: Camera3D
var _slider: HSlider
var _sweep_button: Button
var _throttle_label: Label
var _sweep_elapsed := 0.0
## Set while the sweep drives the slider, so the slider's own signal does not fight it.
var _applying_sweep := false


func _init(p_catalog: PartsCatalog, p_motor_id: String = "", p_propeller_id: String = "", p_battery_id: String = "") -> void:
	catalog = p_catalog
	motor_id = p_motor_id if p_motor_id != "" else ReferenceBuild.MOTOR_ID
	propeller_id = p_propeller_id if p_propeller_id != "" else ReferenceBuild.PROPELLER_ID
	battery_id = p_battery_id if p_battery_id != "" else ReferenceBuild.BATTERY_ID

	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.anchor_right = 1.0
	row.anchor_bottom = 1.0
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	# The stand and its throttle in one column: labs-and-sim.md puts the control "under it",
	# and a throttle across the room from the thing it drives is a different instrument.
	var stage := VBoxContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_constant_override("separation", 6)
	row.add_child(stage)

	var viewport_container := SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(viewport_container)

	# Its own World3D, for the same reason Lab has one: Sim is a separate scene with its own
	# cameras and lights, and a shared world lets two rooms render into each other.
	_viewport = SubViewport.new()
	_viewport.size = VIEWPORT_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	# Without this the bench is SILENT, and silently so. A SubViewport does not route 3D audio
	# unless asked: it defaults to false, and an AudioStreamPlayer3D inside one with no listener
	# simply plays to nobody. Sim never needed it because main.tscn is a scene on the root
	# viewport, where 3D audio is on already — so "the audio code needs no changes" was true and
	# the bench was still going to make no noise.
	_viewport.audio_listener_enable_3d = true
	viewport_container.add_child(_viewport)

	_build_world()
	_build_throttle(stage)

	instruments = BenchInstruments.new()
	instruments.custom_minimum_size = Vector2(336, 0)
	instruments.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(instruments)

	_rebuild()


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

	stand = BenchStand.new()
	stand.name = "Stand"
	_viewport.add_child(stand)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-34.0, -38.0, 0.0)
	key_light.light_energy = 1.6
	key_light.shadow_enabled = true
	_viewport.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-8.0, 132.0, 0.0)
	fill_light.light_energy = 0.5
	_viewport.add_child(fill_light)

	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = CAMERA_FOV
	_camera.near = 0.005
	_camera.far = 20.0
	_viewport.add_child(_camera)

	# The synthesiser the flight sim uses, unmodified, reading the same Observables. The bench
	# is a fixed source in front of a fixed listener, so there is no doppler and no motion.
	drone_audio = DroneAudio.new()
	drone_audio.name = "BenchAudio"
	_viewport.add_child(drone_audio)


func _build_throttle(stage: VBoxContainer) -> void:
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	stage.add_child(controls)

	var caption := Label.new()
	caption.text = "THROTTLE"
	caption.add_theme_color_override("font_color", BenchInstruments.LABEL_COLOUR)
	controls.add_child(caption)

	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.001
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.custom_minimum_size = Vector2(240, 0)
	_slider.value_changed.connect(_on_slider_changed)
	controls.add_child(_slider)

	_throttle_label = Label.new()
	_throttle_label.text = "0 %"
	_throttle_label.custom_minimum_size = Vector2(56, 0)
	_throttle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls.add_child(_throttle_label)

	_sweep_button = Button.new()
	_sweep_button.text = "Sweep"
	_sweep_button.custom_minimum_size = Vector2(84, 0)
	_sweep_button.pressed.connect(start_sweep)
	controls.add_child(_sweep_button)


## Regenerates the stand and the powertrain for the current pairing, and reframes the camera.
## A new pairing is a new powertrain: the pack starts full and the motor starts stopped,
## because that is what putting a different motor on the stand means.
func _rebuild() -> void:
	_build = Build.from_ids(catalog, ReferenceBuild.FRAME_ID, motor_id, propeller_id, battery_id)

	var geometry := _build.prop_geometry()
	powertrain = Powertrain.new(
		_build.motor_model(), _build.k_t, _build.k_q, _build.battery_model(),
		_build.effective_max_amps, _build.rated_rpm(),
		_build.pole_pairs(), geometry.blades, geometry.diameter_m * 0.5
	)

	stand.rebuild(_build)
	_frame_camera()
	instruments.render_build(_build, catalog)
	_publish_to_screen()


## Eye level with the pairing, far enough back to hold the whole disc. The camera looks at the
## mount rather than at the origin, so a tall stand and a short one both frame the same subject.
func _frame_camera() -> void:
	# The subject is the ROTOR, which hangs off the end of the boom rather than sitting over the
	# base — see BenchStand.mount_position_m. The stand is placed so that subject lands at the
	# world origin, which keeps the framing arithmetic below about the pairing and nothing else.
	stand.position = -stand.mount_position_m
	var subject := Vector3.ZERO

	# Aimed a little BELOW the rotor rather than straight at it, so the column and its base
	# stay in shot. A bench framed tightly on the pairing alone shows a propeller floating in
	# the dark, and the stand is most of what makes the picture read as a thrust stand.
	subject = Vector3(0.0, -stand.mount_position_m.y * AIM_DROP_FRACTION, 0.0)

	# The frame has to hold the subject in BOTH directions, and which one binds changes with
	# the prop. A 10" disc is wider than the stand is tall; a 1.6" whoop prop is not remotely,
	# and the 26 cm column decides the shot instead. Sizing on width alone put every small prop
	# comfortably in frame horizontally and 24 degrees off the top of it.
	var width_m := maxf(stand.prop_radius_m * 2.0, 0.05) + stand.mount_position_m.x
	var height_m := stand.mount_position_m.y + stand.prop_radius_m

	# CAMERA_FOV is the HORIZONTAL angle (the camera is KEEP_WIDTH), so the vertical half-angle
	# has to come back through the viewport's aspect rather than being assumed equal.
	var tan_half_h := tan(deg_to_rad(CAMERA_FOV) * 0.5)
	var aspect := float(VIEWPORT_SIZE.x) / float(VIEWPORT_SIZE.y)
	var tan_half_v := tan_half_h / aspect

	var distance := maxf(
		(width_m / SUBJECT_SCREEN_FRACTION * 0.5) / tan_half_h,
		(height_m / SUBJECT_SCREEN_FRACTION * 0.5) / tan_half_v)

	# Slightly off-axis and a little above, so the disc reads as a disc rather than as a line
	# and the mounting stack underneath stays visible.
	var offset := Vector3(0.28, 0.20, 1.0).normalized() * distance

	# The transform is composed by hand rather than aimed with look_at, for the same reason
	# LabScreen composes its orbit by hand: this screen is built before it is parented, and in
	# the headless tests it is never parented at all. Node3D.look_at needs a tree and prints an
	# ERROR without one — which in this runner reads exactly like a failing test.
	_camera.transform = Transform3D(Basis.looking_at(-offset, Vector3.UP), subject + offset)


## The viewport the stand and the synthesiser both live in. Exposed so a test can assert the
## one property that decides whether any of this is audible — see test_bench.gd.
func audio_viewport() -> SubViewport:
	return _viewport


## The camera's transform in the bench's own world. Composed rather than read from
## global_transform for the same reason LabScreen exposes one: this screen is built before it
## is parented, and in the headless tests it is never parented at all.
func camera_transform() -> Transform3D:
	return _camera.transform


## The pairing under test, as a Build. Public because the bench is judged against the same
## analytic numbers Build computes, and the tests ask it for them.
func current_build() -> Build:
	return _build


## Puts a different pairing on the stand. Called when the bench is opened with Lab's current
## selection behind it.
func set_pairing(p_motor_id: String, p_propeller_id: String, p_battery_id: String = "") -> void:
	motor_id = p_motor_id
	propeller_id = p_propeller_id
	if p_battery_id != "":
		battery_id = p_battery_id
	set_throttle(0.0)
	sweeping = false
	_rebuild()


func set_throttle(value: float) -> void:
	throttle = clampf(value, 0.0, 1.0)
	if _slider != null and not is_equal_approx(_slider.value, throttle):
		_applying_sweep = true
		_slider.value = throttle
		_applying_sweep = false
	if _throttle_label != null:
		_throttle_label.text = "%.0f %%" % (throttle * 100.0)


func _on_slider_changed(value: float) -> void:
	if _applying_sweep:
		return
	# Taking hold of the throttle by hand ends the sweep, the same way taking hold of Lab's
	# orbit ends its idle turn. A ramp that kept running under your fingers would be fighting you.
	sweeping = false
	set_throttle(value)


## Runs the throttle from idle to full and back, so the whole curve gets seen rather than the
## one point you happened to stop the slider at.
func start_sweep() -> void:
	sweeping = true
	_sweep_elapsed = 0.0
	set_throttle(0.0)


## One frame of bench: advance the ramp if one is running, step the powertrain at a fixed
## 1 kHz, turn the rotor at the RPM that produced, and refresh the readout.
##
## Separate from _process so a headless test can drive the bench without a scene tree
## delivering frames — the same seam PropellerMesh.advance() exists for.
func advance(delta: float) -> void:
	if sweeping:
		_sweep_elapsed += delta
		var phase := _sweep_elapsed / SWEEP_SECONDS
		if phase >= 1.0:
			sweeping = false
			set_throttle(0.0)
		else:
			# Up over the first half, down over the second, to the highest throttle this
			# pairing can actually reach rather than to a nominal 100% it is current-limited
			# out of.
			var triangle := 1.0 - absf(phase * 2.0 - 1.0)
			set_throttle(_build.max_throttle_fraction() * triangle)

	var substeps := clampi(int(ceil(delta * PHYSICS_HZ)), 1, MAX_SUBSTEPS)
	var dt := delta / float(substeps)
	var cmds := {"M1": throttle, "M2": throttle, "M3": throttle, "M4": throttle}
	for _i in substeps:
		powertrain.step(cmds, dt)

	stand.advance(delta)
	_publish_to_screen()


## Everything the screen shows comes from the published observables and from nowhere else.
## The rotor's rate in particular: PropellerMesh renders a rate it is handed and derives none,
## and the hand that gives it one here is holding the number the powertrain computed. A bench
## that spun its prop at a rate of its own choosing would look completely correct and agree
## with nothing — the exact failure the observables layer exists to prevent.
func _publish_to_screen() -> void:
	stand.set_rate_rpm(powertrain.observables.rpm[Observables.index_of(BenchStand.BENCH_MOTOR)])
	instruments.render_live(powertrain.observables)


func _process(delta: float) -> void:
	if visible:
		advance(delta)
		if drone_audio != null and drone_audio.is_inside_tree():
			drone_audio.update(powertrain.observables, _camera.global_position)


# ---------------------------------------------------------------------------
# What the bench is reading, as numbers. Straight off the published observables, so a test
# and the panel cannot disagree about what the bench says.
# ---------------------------------------------------------------------------

func readings() -> Dictionary:
	return BenchInstruments.readings(powertrain.observables)

func rpm() -> float:
	return readings()["rpm"]

func thrust_g() -> float:
	return readings()["thrust_g"]

func current_a() -> float:
	return readings()["current_a"]

func voltage_v() -> float:
	return readings()["voltage_v"]

func efficiency_g_per_w() -> float:
	return readings()["efficiency_g_per_w"]
