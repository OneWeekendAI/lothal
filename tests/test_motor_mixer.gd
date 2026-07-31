class_name TestMotorMixer
extends RefCounted
## Does the mixer deliver the attitude authority it was asked for, regardless of where the
## collective throttle sits and regardless of the sign of the command?
##
## The old mixer clamped each motor to [0, 1] independently, so when a motor clipped the
## requested attitude torque was silently not delivered — and how much was lost depended on
## which motors clipped, which depends on the sign of the command. That is a plant asymmetry
## manufactured by the mixer, and it is invisible to every test that only checks the outputs
## are in range.
##
## So these checks are about the DIFFERENTIAL between motors, which is what actually becomes
## torque, rather than about the values themselves.

## The differential a roll command should produce across the left/right pairs: both left
## motors up by MIX_GAIN * roll_cmd and both right motors down by it, so the gap is twice
## that. This is the quantity that becomes roll torque through the arm.
static func _roll_differential(out: Dictionary) -> float:
	return ((out["M3"] + out["M4"]) - (out["M1"] + out["M2"])) * 0.5

static func _pitch_differential(out: Dictionary) -> float:
	return ((out["M2"] + out["M4"]) - (out["M1"] + out["M3"])) * 0.5

static func _yaw_differential(out: Dictionary) -> float:
	return ((out["M1"] + out["M4"]) - (out["M2"] + out["M3"])) * 0.5

static func _in_range(out: Dictionary) -> bool:
	for name in MotorLayout.MOTOR_NAMES:
		if out[name] < 0.0 or out[name] > 1.0:
			return false
	return true

static func run() -> Array:
	var results: Array = []
	var full := 2.0 * MotorMixer.MIX_GAIN   # the differential a full-deflection command owes

	# --- Authority survives a throttle floor ---
	# At 5% throttle a full roll command wants motors at 0.25 and -0.15. The old mixer
	# clamped the negative side to 0 and delivered 0.25 of the 0.40 asked for.
	var low := MotorMixer.mix(0.05, 1.0, 0.0, 0.0)
	results.append(TestResult.new(
		"full roll at 5% throttle still delivers full roll authority",
		absf(_roll_differential(low) - full) < 1e-6 and _in_range(low),
		"differential = %.4f of %.4f requested; motors %s" % [_roll_differential(low), full, low]
	))

	# --- ...and a throttle ceiling ---
	var high := MotorMixer.mix(0.95, 1.0, 0.0, 0.0)
	results.append(TestResult.new(
		"full roll at 95% throttle still delivers full roll authority",
		absf(_roll_differential(high) - full) < 1e-6 and _in_range(high),
		"differential = %.4f of %.4f requested; motors %s" % [_roll_differential(high), full, high]
	))

	# --- The asymmetry the old mixer manufactured ---
	# Equal and opposite commands, at a throttle where one direction clips and the other
	# does not, must produce equal and opposite authority. Under independent clamping they
	# did not, and that is direction-dependent behaviour with no physics behind it.
	var offset := 0.10
	var worst := 0.0
	for axis in ["roll", "pitch", "yaw"]:
		for cmd in [1.0, 0.6]:
			var pos := MotorMixer.mix(offset,
				cmd if axis == "roll" else 0.0,
				cmd if axis == "pitch" else 0.0,
				cmd if axis == "yaw" else 0.0)
			var neg := MotorMixer.mix(offset,
				-cmd if axis == "roll" else 0.0,
				-cmd if axis == "pitch" else 0.0,
				-cmd if axis == "yaw" else 0.0)
			var d_pos: float
			var d_neg: float
			match axis:
				"roll":
					d_pos = _roll_differential(pos)
					d_neg = _roll_differential(neg)
				"pitch":
					d_pos = _pitch_differential(pos)
					d_neg = _pitch_differential(neg)
				_:
					d_pos = _yaw_differential(pos)
					d_neg = _yaw_differential(neg)
			worst = maxf(worst, absf(d_pos + d_neg))
	results.append(TestResult.new(
		"authority is sign-independent on every axis, at a throttle low enough to clip",
		worst < 1e-6,
		"worst |(+cmd) + (-cmd)| across roll/pitch/yaw at %.0f%% throttle = %.9f" % [offset * 100.0, worst]
	))

	# --- Everything at once, and the demand still fits ---
	# The three mix rows are orthogonal sign patterns, so full deflection on all three axes
	# does NOT stack to 3 * MIX_GAIN everywhere — one motor sees all three agree and the rest
	# see one net contribution, for a spread of 4 * MIX_GAIN = 0.8. It fits, and all three
	# axes are delivered in full. Asserting this is what stops the scale-down guard below
	# from being mistaken for the normal path.
	var everything := MotorMixer.mix(0.29, 1.0, 1.0, 1.0)
	results.append(TestResult.new(
		"full deflection on all three axes at once still fits, and all three arrive in full",
		absf(_roll_differential(everything) - full) < 1e-6
			and absf(_pitch_differential(everything) - full) < 1e-6
			and absf(_yaw_differential(everything) - full) < 1e-6
			and _in_range(everything),
		"roll %.4f, pitch %.4f, yaw %.4f, all of %.4f requested; motors %s"
			% [_roll_differential(everything), _pitch_differential(everything),
				_yaw_differential(everything), full, everything]
	))

	# --- The scale-down guard ---
	# Unreachable at MIX_GAIN = 0.2 with the PID clamping its output to +/-1, so it is driven
	# here directly with commands past full deflection. It is not dead code: raising MIX_GAIN
	# past 0.25 makes it live, and that is exactly when a silent change to the TORQUE
	# DIRECTION would be hardest to notice. What must survive is the direction: one common
	# scale factor across all three axes, never per-axis clipping into a different demand.
	var over := MotorMixer.mix(0.5, 1.5, 1.5, 1.5)
	var over_full := full * 1.5
	var scale := _roll_differential(over) / over_full
	results.append(TestResult.new(
		"a demand too large to meet is scaled by one common factor, not clipped per axis",
		scale < 1.0 and _in_range(over)
			and absf(_pitch_differential(over) / over_full - scale) < 1e-6
			and absf(_yaw_differential(over) / over_full - scale) < 1e-6,
		"1.5x demand delivered at %.4f of what was asked, equally on all three axes" % scale
	))

	# --- The tradeoff, asserted rather than described ---
	# Airmode buys attitude authority with collective throttle. Full three-axis deflection
	# confines the collective to [0.2, 0.4]: hover at 29% sits inside that window and is
	# untouched, which is why none of the project's oracles moved — but a pilot at 95%
	# throttle throwing the aircraft around gets 40% and drops. That is a real consequence an
	# altitude controller added later has to be built knowing about, so it is pinned here
	# rather than left in a docstring.
	var punched := MotorMixer.mix(0.95, 1.0, 1.0, 1.0)
	var punched_mean := 0.0
	for name in MotorLayout.MOTOR_NAMES:
		punched_mean += punched[name]
	punched_mean /= 4.0
	var hover_mean_full := 0.0
	for name in MotorLayout.MOTOR_NAMES:
		hover_mean_full += everything[name]
	hover_mean_full /= 4.0
	results.append(TestResult.new(
		"the price is collective throttle, and hover is inside the window where it is free",
		absf(punched_mean - 0.4) < 1e-6 and absf(hover_mean_full - 0.29) < 1e-6,
		"full three-axis deflection: 95%% collective becomes %.1f%%, while 29%% hover stays %.1f%%"
			% [punched_mean * 100.0, hover_mean_full * 100.0]
	))

	# --- Hover is untouched ---
	# Airmode must do nothing at all in the regime the aircraft spends its life in, or every
	# oracle in the project would have moved.
	var hover := MotorMixer.mix(0.29, 0.05, -0.03, 0.02)
	var hover_mean := 0.0
	for name in MotorLayout.MOTOR_NAMES:
		hover_mean += hover[name]
	hover_mean /= 4.0
	results.append(TestResult.new(
		"small corrections around hover leave the collective exactly where it was put",
		absf(hover_mean - 0.29) < 1e-6,
		"asked 29.0%%, delivered %.4f%% mean throttle" % (hover_mean * 100.0)
	))

	# --- Never out of range ---
	var all_in_range := true
	for throttle in [0.0, 0.05, 0.29, 0.6, 0.95, 1.0]:
		for r in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			for p in [-1.0, 0.0, 1.0]:
				for y in [-1.0, 0.0, 1.0]:
					if not _in_range(MotorMixer.mix(throttle, r, p, y)):
						all_in_range = false
	results.append(TestResult.new(
		"every motor command lands in [0, 1] across the whole input space",
		all_in_range,
		"270 combinations of throttle x roll x pitch x yaw checked"
	))

	return results
