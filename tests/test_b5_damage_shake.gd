class_name TestB5DamageShake
extends RefCounted
## B5 vibration sanity: R1.1 prop damage is imbalance (VibrationModel.set_damage). A damaged prop raises its motor's
## 1x line, and so the FPV camera's shake; a clean build stays near invisible.
##
## WHAT THE PHYSICS SAYS, MEASURED HERE (reference build, hover ~9150 rpm = 152 Hz 1x): clean, the frame (hard mount)
## shakes ~3 deg/s peak and 0.003 deg; the 45 Hz TPU mount passes ~10% of that. With one prop 30% damaged the hard
## mount sees ~18 deg/s and 0.018 deg, the TPU mount ~2 deg/s. A rigid-body cross-check agrees in size: 0.36 g lost
## at the tip at 958 rad/s is ~21 N rotating, 2.3 N m on ~0.003 kg m^2, so 770 rad/s^2 / 958^2 = 0.05 deg. At
## ~10.7 px per degree that is SUB-PIXEL as an angle: real damaged-prop footage shows it as rolling-shutter jello,
## which Lothal does not model. So the checks are on RATIOS and on the clean level, not on a pixel threshold the
## physics does not reach.

static func run() -> Array:
	var r: Array = []
	var m := TestB5CameraDebris._booted()
	for i in 60:
		m._physics_process(TestB5CameraDebris.DT)
	var vib: VibrationModel = m.core.gyro.vibration
	var tpu: FpvMount = m.camera_mount
	var hard := FpvMount.new("hard")
	var clean := [_line(vib, 1), rad_to_deg(tpu.vibration_peak_rate(vib)), rad_to_deg(hard.vibration_peak_rate(vib)), rad_to_deg(hard.vibration_peak_angle(vib))]
	m.core.prop_damage[1] = 0.3
	m._physics_process(TestB5CameraDebris.DT)
	var bad := [_line(vib, 1), rad_to_deg(tpu.vibration_peak_rate(vib)), rad_to_deg(hard.vibration_peak_rate(vib)), rad_to_deg(hard.vibration_peak_angle(vib))]
	var other := _line(vib, 0)
	m.core.prop_damage[1] = 0.0
	m.free()
	r.append(TestResult.new("b5 vib: R1.1 damage (30%) raises that motor's 1x line > 5x, and only that motor's",
		bad[0] > 5.0 * clean[0] and other < 2.0 * clean[0], "1x %s -> %s rad, motor 0 %s" % [clean[0], bad[0], other]))
	r.append(TestResult.new("b5 vib: the damaged prop shakes the camera > 4x harder (TPU and hard mount)",
		bad[1] > 4.0 * clean[1] and bad[2] > 4.0 * clean[2], "tpu %.2f -> %.2f deg/s, hard %.2f -> %.2f deg/s" % [clean[1], bad[1], clean[2], bad[2]]))
	r.append(TestResult.new("b5 vib: a clean build shakes the frame ~1-8 deg/s and under a pixel (< 0.03 deg)",
		clean[2] > 1.0 and clean[2] < 8.0 and clean[3] < 0.03 and clean[1] < clean[2], "hard %.2f deg/s %.4f deg, tpu %.2f deg/s" % [clean[2], clean[3], clean[1]]))
	return r


## Motor i's 1x line amplitude at the frame (no mount), rad.
static func _line(v: VibrationModel, motor: int) -> float:
	var a := v.tone_angles()
	var b := v.tone_angles(PI / 2.0)
	var k := 2 * motor
	if k >= a.size():
		return 0.0
	var a0: Vector3 = a[k]["angle"]
	var a1: Vector3 = b[k]["angle"]
	return sqrt(a0.length_squared() + a1.length_squared())
