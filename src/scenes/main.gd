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
## Tab hides the build panel; parts are picked with the mouse.

const SUBSTEPS := 8   # 120 Hz physics_process x 8 = 1 kHz dynamics (physics.md §6)
const STICK_DEADZONE := 0.08
const MAX_YAW_RATE_CMD := 1.0
const MODE_TOGGLE_BUTTON := JOY_BUTTON_A

@onready var drone: Node3D = $Drone
@onready var camera: Camera3D = $Camera3D

# Behind (+Z, per the coordinate contract's -Z-is-forward) and above the ~15cm frame.
const CAMERA_OFFSET := Vector3(0, 0.35, 0.7)

# Spawn airborne — the ground plane's surface is y = 0, so spawning at the origin puts the
# drone inside it.
const SPAWN_POSITION := Vector3(0, 2.0, 0)
## Frame half-height (~5 mm) plus a little clearance: below this the drone has hit the ground.
const CRASH_ALTITUDE_M := 0.02

var core: DroneCore
var build: Build
var build_panel: BuildPanel
var rate_controller := RateModeController.new()
var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0}
var use_rate_mode := false
var _mode_button_was_pressed := false
var _tab_was_pressed := false
## Cached per build: hover_throttle() sweeps the thrust curve to find its peak, which is
## far too much work to redo on every input frame.
var _hover_throttle := 0.0

func _ready() -> void:
	var ui_layer := CanvasLayer.new()
	add_child(ui_layer)

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
	_reset_to_spawn()

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

## Day 3's gate (week1.md): "Ground is one static box; hitting it resets to spawn."
## Ground contact is a plain altitude test rather than a Jolt query — the ground is a
## single flat plane this week, so a shape cast would cost more than it tells us.
func _reset_to_spawn() -> void:
	core.rigid_body.position_m = SPAWN_POSITION
	core.rigid_body.velocity_mps = Vector3.ZERO
	core.rigid_body.orientation = Quaternion.IDENTITY
	core.rigid_body.angular_velocity_rad_s = Vector3.ZERO
	# Spawn with the motors already at hover RPM. Spinning up from dead through the ~30 ms
	# lag costs ~0.4 m/s of sink, and with no altitude hold this week that never comes back.
	core.prime_motors(_hover_throttle)
	rate_controller.reset()
	rc.throttle = _hover_throttle

func _physics_process(delta: float) -> void:
	if core == null:
		return
	if Input.is_key_pressed(KEY_TAB) != _tab_was_pressed:
		_tab_was_pressed = Input.is_key_pressed(KEY_TAB)
		if _tab_was_pressed:
			build_panel.visible = not build_panel.visible

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

	if core.rigid_body.position_m.y < CRASH_ALTITUDE_M:
		_reset_to_spawn()

	drone.position = core.rigid_body.position_m
	drone.quaternion = core.rigid_body.orientation

	# Chase-cam: always framed on the drone rather than a fixed, hand-baked transform —
	# robust to the drone drifting (no altitude hold yet) and to the frame's small size.
	camera.global_position = drone.position + CAMERA_OFFSET
	camera.look_at(drone.position, Vector3.UP)

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
	rc.throttle = clampf(_hover_throttle + throttle_axis * 0.3, 0.0, 1.0)

func _deadzone(value: float) -> float:
	if absf(value) < STICK_DEADZONE:
		return 0.0
	return value
