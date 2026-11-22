class_name TestTurtleMode
extends RefCounted
## Owner report: inverted on the ground in acro, "it sort of stuck". Measured, that is the physics: a quad on its
## back pushes its thrust into the ground, and no stick input lifts it. Real pilots get out with Betaflight's turtle
## mode (flip over after crash): the motors on one side spin BACKWARDS and flip it. These checks pin both halves.

const DT := 0.001
const Main := preload("res://src/scenes/main.gd")


static func run() -> Array:
	var results: Array = []
	results.append_array(_stays_turtled_without_turtle_mode())
	results.append_array(_turtle_mode_flips_it())
	results.append_array(_turtle_mix())
	results.append_array(_reversed_thrust_points_down_the_body())
	results.append_array(_turtled_detector())
	return results


static func _inverted_on_ground() -> Array:
	var core: DroneCore = ReferenceBuild.build_drone_core()
	core.collision_world = CollisionWorld.new(null)
	core.rigid_body.orientation = Quaternion(Vector3.FORWARD, PI)
	core.rigid_body.position_m = Vector3(0, 0.1, 0)
	var fc := FlightController.new()
	fc.mode = FlightController.Mode.ACRO
	return [core, fc]


## `release_at_up`: like a pilot, centre the sticks once the body's up axis passes this (2.0 = never).
static func _fly(core: DroneCore, fc: FlightController, rc: Dictionary, seconds: float, release_at_up := 2.0) -> float:
	var best_up := -1.0
	for _i in int(seconds / DT):
		if (core.rigid_body.orientation * Vector3.UP).y > release_at_up:
			rc.roll = 0.0
			rc.pitch = 0.0
		var cmds := fc.update(core.accel.reading_mps2, core.gyro.rate_rad_s, rc, DT, core.vbat)
		core.motors_reversed = fc.turtle
		core.step(cmds, DT)
		best_up = maxf(best_up, (core.rigid_body.orientation * Vector3.UP).y)
	return best_up


## Without turtle mode, full roll at the reported 36% throttle never lifts it off its back.
static func _stays_turtled_without_turtle_mode() -> Array:
	var pair := _inverted_on_ground()
	var core: DroneCore = pair[0]
	var fc: FlightController = pair[1]
	_fly(core, fc, {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0}, 0.5)
	var best_up := _fly(core, fc, {"roll": 1.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.36}, 2.0)
	return [TestResult.new("turtled: full roll at 36% throttle cannot right an inverted quad (thrust is into the ground)",
		best_up < -0.8 and not core.crashed, "best body-up y %.3f" % best_up)]


## With turtle on, full roll stick punched and released as the side lifts (as a pilot does: the props spin down after release) rights it within 2 s, and it lands
## upright and uncrashed.
static func _turtle_mode_flips_it() -> Array:
	var results: Array = []
	for axis in ["roll", "pitch"]:
		var pair := _inverted_on_ground()
		var core: DroneCore = pair[0]
		var fc: FlightController = pair[1]
		_fly(core, fc, {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0}, 0.5)
		fc.toggle_turtle()
		var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.36}
		rc[axis] = 1.0
		var best_up := _fly(core, fc, rc, 2.0, -0.8)
		rc[axis] = 0.0
		_fly(core, fc, rc, 1.0)
		var up := (core.rigid_body.orientation * Vector3.UP).y
		results.append(TestResult.new("turtle mode: full %s stick flips an inverted quad upright" % axis,
			best_up > 0.9 and up > 0.9 and not core.crashed,
			"best up %.3f, final up %.3f, crashed %s" % [best_up, up, core.crashed]))
	return results


## The mix: centred sticks run nothing; full roll runs exactly the two motors on one side; throttle is ignored.
static func _turtle_mix() -> Array:
	var results: Array = []
	var idle := FlightController.turtle_mix({"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 1.0})
	var idle_sum := 0.0
	for n in idle:
		idle_sum += float(idle[n])
	results.append(TestResult.new("turtle mix: centred sticks spin no motor, whatever the throttle", idle_sum == 0.0,
		str(idle)))
	var right := FlightController.turtle_mix({"roll": 1.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0})
	var left_on := float(right["M3"]) > 0.99 and float(right["M4"]) > 0.99
	var right_off := float(right["M1"]) == 0.0 and float(right["M2"]) == 0.0
	results.append(TestResult.new("turtle mix: full roll runs one side's pair at full and the other not at all",
		left_on and right_off, str(right)))
	var half := FlightController.turtle_mix({"roll": 0.5, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0})
	var expo := 0.65 * 0.5 + 0.35 * 0.125
	var fc := FlightController.new()
	fc.toggle_turtle()
	var via_update := fc.update(Vector3(0, 9.81, 0), Vector3.ZERO, {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.8}, DT)
	var any := 0.0
	for n in via_update:
		any += float(via_update[n])
	results.append(TestResult.new("turtle on: the FC bypasses the stabiliser and throttle (centred sticks, 80% throttle, motors off)",
		any == 0.0, str(via_update)))
	results.append(TestResult.new("turtle mix: half stick gives Betaflight's crashflip expo (35) power",
		absf(float(half["M3"]) - expo) < 1.0e-9, "M3 %.4f expected %.4f" % [float(half["M3"]), expo]))
	return results


## A reversed motor pushes along body -Y: a level quad with turtle-reversed full motors accelerates DOWN.
static func _reversed_thrust_points_down_the_body() -> Array:
	var core: DroneCore = ReferenceBuild.build_drone_core()
	core.rigid_body.orientation = Quaternion.IDENTITY
	core.rigid_body.position_m = Vector3(0, 10.0, 0)
	core.motors_reversed = true
	var cmds := {"M1": 1.0, "M2": 1.0, "M3": 1.0, "M4": 1.0}
	for _i in 200:
		core.step(cmds, DT)
	var free_fall_vy := -9.81 * 0.2
	var vy := core.rigid_body.velocity_mps.y
	return [TestResult.new("reversed motors push down the body axis (faster than free fall)",
		vy < free_fall_vy * 1.2, "vy %.3f m/s after 0.2 s, free fall %.3f" % [vy, free_fall_vy])]


static func _turtled_detector() -> Array:
	var inv := Quaternion(Vector3.FORWARD, PI)
	return [TestResult.new("the HUD's turtled test: on its back, still and low is turtled; upright or flying is not",
		Main.turtled(inv, Vector3.ZERO, 0.03) and not Main.turtled(Quaternion.IDENTITY, Vector3.ZERO, 0.03)
			and not Main.turtled(inv, Vector3(5, 0, 0), 0.03) and not Main.turtled(inv, Vector3.ZERO, 3.0), "")]
