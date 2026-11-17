class_name TestVbatCompensation
extends RefCounted
## R1.3: Betaflight-style battery-voltage compensation. The FC scales motor output by
## reference / MEASURED voltage, blended by vbat_sag_compensation (0-100 %, default off), and the
## measurement is a noisy, filtered sensor, never the pack's true voltage.

const DT := 0.001
const FLIGHT_S := 12.0

## Hovers the fore/aft-symmetric reference on a pack that drains from full to `end_soc` during the
## flight, throttle solved for the FULL pack, through the real FC. Returns the altitude change (m).
static func _drain_drift_m(percent: float, end_soc: float) -> float:
	var build := ReferenceBuild.fore_aft_symmetric()
	var core := build.build_drone_core()
	var pack: BatteryModel = core.powertrain.battery
	pack.used_mah = 0.0
	var throttle := build.hover_throttle_for(pack)
	core.prime_motors(throttle)
	var fc := FlightController.new()
	VbatSensor.set_percent(fc.rate_loop.config, percent)
	var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": throttle}
	var steps := int(FLIGHT_S / DT)
	var start_y: float = core.rigid_body.position_m.y
	for i in steps:
		pack.used_mah = pack.capacity_mah * (1.0 - end_soc) * float(i) / float(steps)
		core.step(fc.update(core.accel.reading_mps2, core.gyro.rate_rad_s, rc, DT, core.vbat), DT)
	return core.rigid_body.position_m.y - start_y

static func _code_only(src: String) -> String:
	var lines: Array = []
	for line in src.split("\n"):
		var hash_at := line.find("#")
		lines.append(line if hash_at < 0 else line.substr(0, hash_at))
	return "\n".join(lines)

static func _flight_y(with_sensor: bool) -> float:
	var core := ReferenceBuild.build_drone_core()
	var hover := ReferenceBuild.hover_throttle()
	core.prime_motors(hover)
	var fc := FlightController.new()
	var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": hover}
	for i in 3000:
		var v: VbatSensor = core.vbat if with_sensor else null
		core.step(fc.update(core.accel.reading_mps2, core.gyro.rate_rad_s, rc, DT, v), DT)
	return core.rigid_body.position_m.y

static func run() -> Array:
	var results: Array = []

	# ---- off is exactly as before ----
	var plain := MotorMixer.mix(0.4, 0.3, -0.2, 0.1)
	var unit := MotorMixer.mix(0.4, 0.3, -0.2, 0.1, {}, 1.0)
	var same := true
	for n in MotorLayout.MOTOR_NAMES:
		same = same and plain[n] == unit[n]
	var sag := VbatSensor.new(4, 0.0)
	sag.update(14.0, DT)
	var rl_off := RateModeController.new()
	var rl_none := RateModeController.new()
	var out_off := rl_off.update(Vector3(0.2, 0, 0), Vector3.ZERO, 0.4, DT, sag)
	var out_none := rl_none.update(Vector3(0.2, 0, 0), Vector3.ZERO, 0.4, DT)
	for n in MotorLayout.MOTOR_NAMES:
		same = same and out_off[n] == out_none[n]
	results.append(TestResult.new(
		"compensation off (default) leaves mixer and FC output bit-identical, even on a sagging pack",
		same and VbatSensor.percent({}) == 0.0, "mixer/FC outputs equal=%s" % same))

	var a := _flight_y(false)
	var b := _flight_y(true)
	results.append(TestResult.new(
		"off: a 3 s hover is identical with the sensor wired in and without it",
		a == b, "%.9f vs %.9f" % [a, b]))

	# ---- the scale law ----
	# B2/P6: Betaflight's law (mixer.c), relative to a full pack: (1 - a(v)) / (1 - a(full)),
	# a(v) = p * clamp(v_cell - 3.30, 0, 0.80) / 4.10. 4S at 14.0 V = 3.50 V/cell.
	var s := VbatSensor.new(4, 0.0)
	s.update(14.0, DT)
	var full_scale := VbatSensor.scale(100.0, s)
	var half_scale := VbatSensor.scale(50.0, s)
	var want100 := (1.0 - 0.20 / 4.10) / (1.0 - 0.80 / 4.10)
	var want50 := (1.0 - 0.5 * 0.20 / 4.10) / (1.0 - 0.5 * 0.80 / 4.10)
	results.append(TestResult.new(
		"scale is Betaflight's range attenuation relative to a full pack: %.4f at 100%%, %.4f at 50%%, 1.0 at 0%%" % [want100, want50],
		absf(full_scale - want100) < 1.0e-3 and absf(half_scale - want50) < 1.0e-3
			and VbatSensor.scale(0.0, s) == 1.0,
		"100%%: %.4f  50%%: %.4f" % [full_scale, half_scale]))
	var above := VbatSensor.new(4, 0.0)
	above.update(17.5, DT)
	results.append(TestResult.new("a pack above the reference is never cut back (scale >= 1)",
		VbatSensor.scale(100.0, above) == 1.0, "scale %.4f" % VbatSensor.scale(100.0, above)))
	# B2/P6: clamped as Betaflight clamps batteryGoodness. At or below the min cell voltage the scale
	# stops at full/min = 4.10/3.30; at or above the full cell voltage it is 1. The reference is
	# cells x 4.10 V, not the pack's resting voltage.
	# MUTATION: dropping the clampf in scale() gives 1.48 at 2.0 V/cell, fails.
	var dead := VbatSensor.new(4, 0.0)
	dead.update(8.0, DT)
	var at_min := VbatSensor.new(4, 0.0)
	at_min.update(13.2, DT)
	var cap := 4.10 / 3.30
	results.append(TestResult.new(
		"b2 p6: the scale is clamped like Betaflight's: %.4f at and below 3.30 V/cell, reference = cells x 4.10 V" % cap,
		absf(VbatSensor.scale(100.0, dead) - cap) < 1.0e-6 and absf(VbatSensor.scale(100.0, at_min) - cap) < 1.0e-6
			and absf(dead.reference_v - 16.4) < 1.0e-9,
		"2.0 V/cell %.4f, 3.30 V/cell %.4f, ref %.2f V" % [VbatSensor.scale(100.0, dead), VbatSensor.scale(100.0, at_min), dead.reference_v]))

	# B2/P5: at high throttle with a roll command and compensation on, the roll differential is kept
	# (scaled by the compensation, as Betaflight scales the whole range), not clipped off the high motors.
	# MUTATION: the pre-B2 per-motor minf(1, cmd * scale) after the mix keeps 0.12 of a 0.16 split, fails.
	var plain_hi := MotorMixer.mix(0.9, 0.2, 0.0, 0.0)
	var comp_hi := MotorMixer.mix(0.9, 0.2, 0.0, 0.0, {}, 1.2)
	var split_plain: float = (plain_hi["M3"] + plain_hi["M4"]) - (plain_hi["M1"] + plain_hi["M2"])
	var split_comp: float = (comp_hi["M3"] + comp_hi["M4"]) - (comp_hi["M1"] + comp_hi["M2"])
	var top := 0.0
	for n in MotorLayout.MOTOR_NAMES:
		top = maxf(top, comp_hi[n])
	results.append(TestResult.new(
		"b2 p5: at 90% throttle a roll command keeps its full motor differential (x scale) with compensation on",
		absf(split_plain) > 0.1 and absf(split_comp - 1.2 * split_plain) < 1.0e-9 and top <= 1.0,
		"split %.4f off, %.4f with scale 1.2 (want %.4f), max motor %.4f" % [split_plain, split_comp, 1.2 * split_plain, top]))

	# ---- never above 100% output ----
	var rl := RateModeController.new()
	VbatSensor.set_percent(rl.config, 100.0)
	var low := VbatSensor.new(4, 0.0)
	low.update(8.0, DT)   # a 2x scale
	var worst := 0.0
	for thr in [0.1, 0.5, 0.9, 1.0]:
		var o := rl.update(Vector3(1, 1, 1), Vector3.ZERO, thr, DT, low)
		for n in MotorLayout.MOTOR_NAMES:
			worst = maxf(worst, o[n])
	var m := MotorMixer.mix(0.95, 1.0, 1.0, 1.0, {}, 3.0)
	for n in MotorLayout.MOTOR_NAMES:
		worst = maxf(worst, m[n])
	results.append(TestResult.new("compensated motor output never exceeds 100%",
		worst <= 1.0 and worst > 0.99, "max output %.6f" % worst))

	# ---- drift over a draining pack ----
	var drift0 := _drain_drift_m(0.0, 0.1)
	var drift100 := _drain_drift_m(100.0, 0.1)
	results.append(TestResult.new(
		"100% compensation: hover altitude drift over a draining pack is clearly smaller than 0%",
		absf(drift100) < 0.5 * absf(drift0) and absf(drift0) > 0.3,
		"drift 0%%: %+.3f m, 100%%: %+.3f m" % [drift0, drift100]))

	# ---- the FC reads the filtered sensor, not the truth ----
	var sensor := VbatSensor.new(4, 0.0)
	sensor.update(16.0, DT)
	for i in 5:
		sensor.update(12.0, DT)   # the true voltage collapses; a 0.5 Hz filter barely moves
	results.append(TestResult.new(
		"the sensor lags a step in true voltage (filtered, not instantaneous)",
		sensor.filtered_v > 15.5 and sensor.filtered_v < 16.0,
		"filtered %.3f V after true fell to 12 V" % sensor.filtered_v))
	var noisy := VbatSensor.new(4, 0.05)
	var lo := INF
	var hi := -INF
	for i in 2000:
		noisy.update(15.0, DT)
		if i > 1000:
			lo = minf(lo, noisy.filtered_v)
			hi = maxf(hi, noisy.filtered_v)
	results.append(TestResult.new(
		"the sensor carries ADC noise (reading is not the true 15.000 V) and is smoothed (< 50 mV p-p)",
		hi - lo > 0.0 and hi - lo < 0.05 and not is_equal_approx(noisy.filtered_v, 15.0),
		"p-p %.4f V, last %.4f" % [hi - lo, noisy.filtered_v]))
	var core := ReferenceBuild.build_drone_core()
	core.prime_motors(ReferenceBuild.hover_throttle())
	for i in 300:
		core.step({"M1": 0.3, "M2": 0.3, "M3": 0.3, "M4": 0.3}, DT)
	results.append(TestResult.new(
		"the core's sensor is fed from the pack: tracks the live voltage but is not it",
		absf(core.vbat.filtered_v - core.observables.voltage_live_v) < 1.0
			and core.vbat.filtered_v != core.observables.voltage_live_v
			and core.vbat.cells == int(core.powertrain.battery.cells) and core.vbat.cells > 0
			and absf(core.vbat.reference_v - core.vbat.cells * VbatSensor.BF_FULL_CELL_V) < 1.0e-9,
		"sensor %.4f V, true %.4f V, ref %.2f V (%d cells x %.2f V, B2/P6)" % [core.vbat.filtered_v, core.observables.voltage_live_v,
			core.vbat.reference_v, core.vbat.cells, VbatSensor.BF_FULL_CELL_V]))
	var main_code := _code_only(FileAccess.get_file_as_string("res://src/scenes/main.gd"))
	var nav_code := _code_only(FileAccess.get_file_as_string("res://src/autopilot/nav_pilot.gd"))
	var fc_code := _code_only(FileAccess.get_file_as_string("res://src/fc/flight_controller.gd")
		+ FileAccess.get_file_as_string("res://src/fc/rate_mode_controller.gd"))
	results.append(TestResult.new(
		"call sites hand the FC core.vbat; the FC path never touches observables or the battery",
		main_code.contains("rc, substep_dt, core.vbat)") and nav_code.contains("last_rc, dt, core.vbat)")
			and not fc_code.contains("voltage_live") and not fc_code.contains("observables")
			and not fc_code.contains("resting_voltage"),
		"main/nav wired, FC path clean"))
	return results
