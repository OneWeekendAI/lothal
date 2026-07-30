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
## the pilot's position on the ground and the chase camera.

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

@onready var drone: Node3D = $Drone
@onready var camera: Camera3D = $Camera3D
@onready var ground_mesh: MeshInstance3D = $Ground/GroundMesh

# Behind (+Z, per the coordinate contract's -Z-is-forward) and above the ~15cm frame.
# Applied in the drone's own heading frame, not world space (see _update_camera).
const CAMERA_OFFSET := Vector3(0, 0.9, 2.4)
## How quickly the camera closes on its target position, per second.
const CAMERA_FOLLOW_RATE := 6.0
## Aim slightly above the airframe so the drone sits low in frame and the gate ahead gets
## the screen space, rather than the drone sitting dead centre hiding what it is flying at.
const CAMERA_LOOK_AHEAD_UP := 0.6

const GROUND_SIZE_M := 400.0

# Where the drone sits before the course exists (and the seed for _previous_position).
# The real start line comes from GateCourse.start_position() — spawning airborne matters
# either way, since the ground plane's surface is y = 0.
const SPAWN_POSITION := Vector3(0, 2.0, 0)
## Frame half-height (~5 mm) plus a little clearance: below this the drone has hit the ground.
const CRASH_ALTITUDE_M := 0.02

var core: DroneCore
var build: Build
var build_panel: BuildPanel
var hud: Hud
var course := GateCourse.new()
var lap_timer := LapTimer.new()
var course_renderer: CourseRenderer
var drone_audio: DroneAudio
var _l_was_pressed := false
var rate_controller := RateModeController.new()
var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0}
var use_rate_mode := false
var _mode_button_was_pressed := false
var _tab_was_pressed := false
## Previous frame's position, so gate passage is tested against the segment actually
## travelled rather than against a single sample (see GateCourse.segment_passes_gate).
var _previous_position := SPAWN_POSITION
var _last_heading := Basis.IDENTITY
## Cached per build: hover_throttle() sweeps the thrust curve to find its peak, which is
## far too much work to redo on every input frame.
var _hover_throttle := 0.0

func _ready() -> void:
	ground_mesh.material_override = GroundGrid.build_material(GROUND_SIZE_M)

	course_renderer = CourseRenderer.new(course)
	add_child(course_renderer)

	# Added before the build panel, because the panel emits build_changed from its own
	# _ready and that path runs all the way through to placing the listener.
	drone_audio = DroneAudio.new()
	add_child(drone_audio)

	var ui_layer := CanvasLayer.new()
	add_child(ui_layer)

	hud = Hud.new()
	ui_layer.add_child(hud)

	build_panel = BuildPanel.new(PartsCatalog.load_default(), {
		"frame": ReferenceBuild.FRAME_ID,
		"motor": ReferenceBuild.MOTOR_ID,
		"propeller": ReferenceBuild.PROPELLER_ID,
		"battery": ReferenceBuild.BATTERY_ID,
	})
	build_panel.build_changed.connect(_on_build_changed)
	ui_layer.add_child(build_panel)   # emits build_changed on _ready, which builds the core

## Every part change lands here: new mass properties, new coefficients, new drone. The
## airframe is rebuilt from scratch rather than patched, so there is no way for a stat on
## the panel to disagree with what is being flown.
func _on_build_changed(new_build: Build) -> void:
	build = new_build
	_hover_throttle = build.hover_throttle()
	core = build.build_drone_core()
	_fit_drone_mesh_to_arm(build.arm_m)
	# A lap time belongs to a build. Swapping a part mid-lap starts the attempt over rather
	# than letting a 6S pack finish a lap a 4S one started.
	_restart_course()

## The rendered airframe follows arm length, so swapping a 3" frame for a 7" is visible as
## well as felt. Godot primitives only — no Blender this week (week1.md day 3).
func _fit_drone_mesh_to_arm(arm_m: float) -> void:
	var offset := arm_m * cos(deg_to_rad(45.0))
	for motor_name in MotorLayout.MOTOR_NAMES:
		var node := drone.get_node_or_null("Motor_%s" % motor_name) as Node3D
		if node != null:
			var pos := MotorLayout.motor_position(motor_name, arm_m)
			node.position = pos
	var frame_mesh := drone.get_node_or_null("Frame") as MeshInstance3D
	if frame_mesh != null:
		frame_mesh.scale = Vector3.ONE * (offset / 0.0778)   # 0.0778 = the .tscn's 110 mm arm

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
		drone_audio.set_listener(drone_audio.listener_mode, course.start_position())
	_reset_to(course.start_position(), course.start_forward())

## Day 3's gate (week1.md): "Ground is one static box; hitting it resets to spawn." Day 6
## moves that to the last gate cleared, so a clip on gate 6 does not send a new pilot back
## to the start line. Ground contact is a plain altitude test rather than a Jolt query —
## the ground is a single flat plane this week, so a shape cast would cost more than it tells us.
func _respawn_after_crash() -> void:
	lap_timer.invalidate_lap()
	_reset_to(course.respawn_position(), course.next_gate()["position"] - course.respawn_position())

## Places the drone level, stationary, and pointed at `forward` (yaw only — respawning
## already banked would just hand the pilot a second crash).
func _reset_to(position: Vector3, forward: Vector3) -> void:
	core.rigid_body.position_m = position
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
	rate_controller.reset()
	rc.throttle = _hover_throttle
	_previous_position = position

	# Snap the camera rather than let it ease in from wherever the crash left it — easing
	# across the map after every respawn is disorienting and costs the pilot the first second.
	drone.position = position
	drone.quaternion = core.rigid_body.orientation
	_last_heading = Basis.IDENTITY
	camera.global_position = position + _drone_heading() * CAMERA_OFFSET
	camera.look_at(position + Vector3.UP * CAMERA_LOOK_AHEAD_UP, Vector3.UP)

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

	if Input.get_connected_joypads().is_empty():
		_read_keyboard()
	else:
		_read_gamepad()

	var substep_dt := delta / SUBSTEPS
	for i in SUBSTEPS:
		var motor_cmds: Dictionary
		if use_rate_mode:
			motor_cmds = rate_controller.update(core.rigid_body.angular_velocity_rad_s, rc, substep_dt)
		else:
			motor_cmds = AngleModeController.update(core.rigid_body.orientation, core.rigid_body.angular_velocity_rad_s, rc)
		core.step(motor_cmds, substep_dt)

	# Score the segment actually flown this frame, BEFORE any crash reset — otherwise a
	# pass that ends in a clip just past the ring is silently thrown away.
	_score_gates(delta)

	if core.rigid_body.position_m.y < CRASH_ALTITUDE_M:
		_respawn_after_crash()

	drone.position = core.rigid_body.position_m
	drone.quaternion = core.rigid_body.orientation
	_previous_position = core.rigid_body.position_m

	_update_camera(delta)

	# Audio and the HUD are handed the same published observables and nothing else — the
	# property architecture.md calls the test of the design. Adding this consumer changed
	# no physics.
	drone_audio.update(core.observables, camera.global_position)

	hud.render(core, build, course, lap_timer, use_rate_mode)
	hud.tick_banner(delta)

## Swaps between hearing the drone from where the pilot stands and hearing it from the
## chase camera. Ground is the default and the more convincing of the two, but the camera
## is what the eyes are doing, and some people want those to agree.
func _toggle_listener() -> void:
	var next := DroneAudio.Listener.CHASE_CAMERA
	if drone_audio.listener_mode == DroneAudio.Listener.CHASE_CAMERA:
		next = DroneAudio.Listener.PILOT_GROUND
	drone_audio.set_listener(next, course.start_position())
	hud.show_banner("EARS: %s" % ("PILOT" if next == DroneAudio.Listener.PILOT_GROUND else "CHASE"))

## Chase cam. The offset is rotated by the drone's HEADING, not left in world space: with a
## fixed world offset the camera keeps facing -Z no matter which way the drone is pointed,
## so turning the drone swings the target out of frame instead of the camera following it
## round. That is survivable for a hover test and fatal for a gate course — the gate you are
## meant to fly at spends most of the lap off-screen.
##
## Yaw only, deliberately. Rolling the camera with the airframe is what an FPV feed actually
## looks like, and it is also what makes people put the controller down after ten seconds.
func _update_camera(delta: float) -> void:
	var heading := _drone_heading()
	var target_position := drone.position + heading * CAMERA_OFFSET

	# Eased rather than snapped, so the camera lags the airframe slightly through a fast
	# rotation instead of pivoting rigidly with it.
	var blend := clampf(delta * CAMERA_FOLLOW_RATE, 0.0, 1.0)
	camera.global_position = camera.global_position.lerp(target_position, blend)
	camera.look_at(drone.position + Vector3.UP * CAMERA_LOOK_AHEAD_UP, Vector3.UP)

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
		use_rate_mode = not use_rate_mode
		rate_controller.reset()   # clear integral/derivative history from the other mode
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
