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

const SUBSTEPS := 8   # 120 Hz physics_process x 8 = 1 kHz dynamics (physics.md §6)
const STICK_DEADZONE := 0.08
const MAX_YAW_RATE_CMD := 1.0
const MODE_TOGGLE_BUTTON := JOY_BUTTON_A

@onready var drone: Node3D = $Drone

var core: DroneCore
var rate_controller := RateModeController.new()
var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0}
var use_rate_mode := false
var _mode_button_was_pressed := false

func _ready() -> void:
	core = ReferenceBuild.build_drone_core()
	rc.throttle = ReferenceBuild.hover_throttle()   # hands-off default: hover, not idle

func _physics_process(delta: float) -> void:
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

	drone.position = core.rigid_body.position_m
	drone.quaternion = core.rigid_body.orientation

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
	rc.throttle = clampf(ReferenceBuild.hover_throttle() + throttle_axis * 0.3, 0.0, 1.0)

func _deadzone(value: float) -> float:
	if absf(value) < STICK_DEADZONE:
		return 0.0
	return value
