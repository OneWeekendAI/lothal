class_name TestControlPath
extends RefCounted
## Two structural guarantees, and the anti-windup that makes the loop recoverable.
##
## The structural half is checked by reading the SOURCE, the way test_bench.gd checks that
## the bench never names the flight half. Both properties are absences, and an absence
## cannot be asserted at runtime: a second mixer call site or a controller reaching for
## ground truth would produce numbers that still look entirely plausible. The only way to
## see them is to look for the text.
##
##   1. MotorMixer.mix is called from exactly ONE place. Lothal previously had two control
##      laws each calling it, which is how angle mode came to have an open-loop yaw axis
##      that no fix to the rate loop ever reached.
##   2. Nothing in src/fc/ names rigid_body.angular_velocity_rad_s. A flight controller that
##      can see ground truth is not a flight controller; the gyro seam would exist on paper
##      only, and every sensor lag, bias and noise term in it would be decoration.

const DT := 0.001

static func _code_only(source: String) -> String:
	var lines: PackedStringArray = []
	for line in source.split("\n"):
		var hash_index := line.find("#")
		lines.append(line if hash_index < 0 else line.substr(0, hash_index))
	return "\n".join(lines)

static func _gd_files(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for name in DirAccess.get_files_at(dir_path):
		if name.ends_with(".gd"):
			out.append(dir_path.path_join(name))
	for name in DirAccess.get_directories_at(dir_path):
		out.append_array(_gd_files(dir_path.path_join(name)))
	return out

static func run() -> Array:
	var results: Array = []

	# --- One mixer call site ---
	var callers: PackedStringArray = []
	for path in _gd_files("res://src"):
		if path == "res://src/sim/motor_mixer.gd":
			continue   # its own definition, not a call
		var code := _code_only(FileAccess.get_file_as_string(path))
		if code.contains("MotorMixer.mix"):
			callers.append(path.get_file())
	results.append(TestResult.new(
		"MotorMixer.mix is called from exactly one place in src/",
		callers.size() == 1 and callers[0] == "rate_mode_controller.gd",
		"callers: %s" % ("none" if callers.is_empty() else ", ".join(callers))
	))

	# --- The FC cannot reach around the gyro ---
	var peekers: PackedStringArray = []
	for path in _gd_files("res://src/fc"):
		if _code_only(FileAccess.get_file_as_string(path)).contains("angular_velocity_rad_s"):
			peekers.append(path.get_file())
	results.append(TestResult.new(
		"nothing in src/fc/ so much as names the body's true angular velocity",
		peekers.is_empty(),
		"checked %d files in src/fc/%s" % [_gd_files("res://src/fc").size(),
			"" if peekers.is_empty() else " — " + ", ".join(peekers) + " names it"]
	))

	# The scene must hand the controller the SENSOR, not the body. Checked positively as well
	# as negatively: an empty file would satisfy the absence above.
	var main_code := _code_only(FileAccess.get_file_as_string("res://src/scenes/main.gd"))
	results.append(TestResult.new(
		"the scene feeds the flight controller from core.gyro and from nothing else",
		main_code.contains("fc.update(core.rigid_body.orientation, core.gyro.rate_rad_s")
			and not main_code.contains("angular_velocity_rad_s,"),
		"main.gd's single FC call site passes core.gyro.rate_rad_s"
	))

	# --- Anti-windup ---
	# A PID pinned against its output limit must not keep banking integral it will have to
	# give back. Without this, a wound-up yaw integrator takes seconds to unwind, and the
	# aircraft ignores the sticks the whole time — the "I can't get it back" symptom.
	var wound := PIDController.new(2.3, 0.15, 0.0)
	for i in 2000:
		wound.update(1.0, 0.0, DT)   # error pinned at 1.0: output saturates immediately
	# Error goes to zero. Anything the output still produces is pure accumulated integral.
	var residual := wound.update(0.0, 0.0, DT)
	results.append(TestResult.new(
		"a PID held against its output limit for 2 s carries no integral out of the stop",
		absf(residual) < 0.001,
		"output with zero error after 2 s of saturation = %.6f" % residual
	))

	# And it must be able to REVERSE immediately, not spend time unwinding first. This is the
	# check that a wound integrator would fail even where the one above might be argued away.
	var reversing := PIDController.new(2.3, 0.15, 0.0)
	for i in 2000:
		reversing.update(1.0, 0.0, DT)
	var reversed := reversing.update(-1.0, 0.0, DT)
	results.append(TestResult.new(
		"and it reverses on the instant the setpoint does, rather than unwinding first",
		reversed < -0.99,
		"output one tick after the setpoint flipped from +1 to -1 = %.4f" % reversed
	))

	# The integrator must still INTEGRATE. Conditional integration that simply never
	# integrates would pass both checks above and would be a strictly worse controller than
	# the one being replaced — a P+D loop with a steady-state error nothing ever removes.
	var trimming := PIDController.new(0.1, 2.0, 0.0)
	var first := trimming.update(0.1, 0.0, DT)
	var last := 0.0
	for i in 200:
		last = trimming.update(0.1, 0.0, DT)
	results.append(TestResult.new(
		"a small unsaturated error still accumulates: the I term is intact, not disabled",
		last > first * 2.0,
		"output grew from %.5f to %.5f over 200 ms of a steady 0.1 error" % [first, last]
	))

	# Recovery from the stop must not need the error to change SIGN, only to become small
	# enough that the output comes back into range. That is the difference between
	# conditional integration and a crude disable-I-while-saturated.
	var recovering := PIDController.new(2.3, 0.15, 0.0)
	for i in 500:
		recovering.update(1.0, 0.0, DT)
	var small := 0.0
	for i in 500:
		small = recovering.update(0.05, 0.0, DT)   # same sign, no longer saturating
	results.append(TestResult.new(
		"integration resumes as soon as the output is back in range, without changing sign",
		small > 2.3 * 0.05,
		"steady 0.05 error settles at %.5f, above the %.5f that P alone would give"
			% [small, 2.3 * 0.05]
	))

	return results
