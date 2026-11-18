class_name TestB5CameraDebris
extends RefCounted
## B5 (REALISM_REVIEW.md), R2.3 + R2.5: the FPV camera on a soft mount, the prop disc, crash debris. Every visual
## here is a function of sim state: the vibration model's own tones, the rigid body's rate, the motor rpm, R1.1's
## prop damage and impact speed.

const SCRATCH_COND := "user://b5_conditions.json"
const SCRATCH_SITES := "user://b5_sites.json"
const DT := 1.0 / 120.0


static func _booted() -> Node:
	for path in [SCRATCH_COND, SCRATCH_SITES]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var m: Node = load("res://src/scenes/main.tscn").instantiate()
	m.conditions_path = SCRATCH_COND
	m.sites_path = SCRATCH_SITES
	m.conditions_library = ConditionsLibrary.with_default()
	m.notification(Node.NOTIFICATION_READY)
	return m


static func _spun(rpm: float, imbalance_kg: float, blade_kg: float) -> VibrationModel:
	var v := VibrationModel.new()
	v.imbalance_kg = imbalance_kg
	v.blade_pass_kg = blade_kg
	v.set_rpm(PackedFloat64Array([rpm, rpm * 1.03, rpm * 0.97, rpm * 1.01]))
	for i in 37:
		v.angular_rate_at(i * 0.001)
	return v


static func run() -> Array:
	var r: Array = []
	_camera(r)
	_resonance(r)
	_disc(r)
	_debris(r)
	_through_main(r)
	for path in [SCRATCH_COND, SCRATCH_SITES]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	return r


static func _camera(r: Array) -> void:
	var mount := FpvMount.new("tpu")
	var base := mount.vibration_offset(_spun(24000.0, VibrationModel.DEFAULT_IMBALANCE_KG, VibrationModel.BLADE_PASS_EQUIVALENT_KG))
	var doubled := mount.vibration_offset(_spun(24000.0, 2.0 * VibrationModel.DEFAULT_IMBALANCE_KG, 2.0 * VibrationModel.BLADE_PASS_EQUIVALENT_KG))
	var ratio := doubled.length() / maxf(base.length(), 1e-30)
	r.append(TestResult.new("b5 r2.3: camera shake is linear in the vibration input (2x forcing -> 2x shake)",
		base.length() > 1e-9 and absf(ratio - 2.0) < 1e-6, "base %s rad, ratio %.6f" % [base.length(), ratio]))
	var none := mount.vibration_offset(_spun(24000.0, 0.0, 0.0))
	var still := mount.vibration_offset(_spun(0.0, VibrationModel.DEFAULT_IMBALANCE_KG, VibrationModel.BLADE_PASS_EQUIVALENT_KG))
	var quiet := FpvMount.new("tpu")
	for i in 200:
		quiet.step_body(Vector3(0.1, -0.2, 0.3), 0.001)
	r.append(TestResult.new("b5 r2.3: zero vibration gives zero shake (no forcing, stopped motors, steady body rate)",
		none == Vector3.ZERO and still == Vector3.ZERO and quiet.offset(null) == Vector3.ZERO,
		"%s %s %s" % [none, still, quiet.offset(null)]))
	# The soft mount isolates the motor lines (all far above 45 Hz); a hard mount passes them unchanged.
	var hard := FpvMount.new("hard").vibration_offset(_spun(24000.0, VibrationModel.DEFAULT_IMBALANCE_KG, VibrationModel.BLADE_PASS_EQUIVALENT_KG))
	r.append(TestResult.new("b5 r2.3: the soft mount passes less of the 400 Hz lines than a hard mount",
		hard.length() > 5.0 * base.length(), "hard %s, tpu %s" % [hard.length(), base.length()]))
	# The tone angle is the integral of the same law's rate: one motor, 1x only, integrated finely over a revolution.
	var v := VibrationModel.new()
	v.blade_pass_kg = 0.0
	v.set_rpm(PackedFloat64Array([12000.0, 0.0, 0.0, 0.0]))
	var dt := 1e-6
	var ang := 0.0
	var lo := INF
	var hi := -INF
	var tone_peak := 0.0
	for i in 5000:   # one revolution at 200 Hz
		var rate := v.angular_rate_at(i * dt)
		ang += rate.x * dt
		lo = minf(lo, ang)
		hi = maxf(hi, ang)
		if i % 50 == 0:
			tone_peak = maxf(tone_peak, absf((v.tone_angles()[0]["angle"] as Vector3).x))
	var integrated := 0.5 * (hi - lo)
	r.append(TestResult.new("b5 r2.3: a tone's angle is the integral of the vibration law's own rate (within 1%)",
		integrated > 0.0 and absf(tone_peak / integrated - 1.0) < 0.01, "tone %s, integrated %s" % [tone_peak, integrated]))


static func _resonance(r: Array) -> void:
	var zeta := 0.10
	var fn := 45.0
	var analytic := sqrt(1.0 + 4.0 * zeta * zeta) / (2.0 * zeta)
	var t_res := FpvMount.transmissibility(fn, fn, zeta)
	r.append(TestResult.new("b5 r2.3: mount transfer at resonance = sqrt(1 + 4 zeta^2) / (2 zeta)",
		absf(t_res - analytic) < 1e-9, "%.6f vs %.6f" % [t_res, analytic]))
	# The time-domain mount, shaken at its own frequency, reaches the same steady-state magnitude.
	var mount := FpvMount.new("tpu")
	var w := TAU * mount.natural_hz
	var a := 0.01
	var dt := 1e-5
	var peak := 0.0
	var n := int(0.6 / dt)
	for i in n:
		var t := (i + 1) * dt
		mount.step_body(Vector3(a * w * cos(w * t), 0, 0), dt)
		if t > 0.5:
			peak = maxf(peak, absf(a * sin(w * t) + mount.rel_angle.x))
	var measured := peak / a
	var want := mount.transmissibility_at(mount.natural_hz)
	r.append(TestResult.new("b5 r2.3: the integrated mount's gain at resonance matches the analytic form (2%)",
		absf(measured / want - 1.0) < 0.02, "%.4f vs %.4f" % [measured, want]))


static func _disc(r: Array) -> void:
	var rpms := [0.0, 100.0, 300.0, 600.0, 900.0, 30000.0]
	var alphas: Array = []
	var rising := true
	for i in rpms.size():
		alphas.append(SimDroneModel.disc_alpha(rpms[i], 3))
		if i > 0 and i < 5 and alphas[i] <= alphas[i - 1]:
			rising = false
	r.append(TestResult.new("b5 r2.5: disc opacity is a function of rpm: 0 stopped, rising, full coverage at speed",
		alphas[0] == 0.0 and rising and is_equal_approx(alphas[5], SimDroneModel.BLUR_ALPHA), str(alphas)))
	r.append(TestResult.new("b5 r2.5: a chipped prop's swept radius follows its lost thrust ((1 - N d)^(1/4))",
		SimDroneModel.chip_radius_fraction(0.0, 3) == 1.0
		and is_equal_approx(SimDroneModel.chip_radius_fraction(0.2, 3), pow(0.4, 0.25))
		and SimDroneModel.chip_radius_fraction(0.5, 3) == 0.0, ""))


static func _debris(r: Array) -> void:
	var th := CrashDebris.ENERGY_THRESHOLD_J
	r.append(TestResult.new("b5 r2.5: debris only above the energy threshold, count rising with energy",
		CrashDebris.fragment_count(th * 0.99) == 0 and CrashDebris.fragment_count(th) >= 1
		and CrashDebris.fragment_count(4.0 * th) > CrashDebris.fragment_count(th)
		and CrashDebris.fragment_count(8.0 * th) > CrashDebris.fragment_count(4.0 * th),
		"%d %d %d" % [CrashDebris.fragment_count(th), CrashDebris.fragment_count(4.0 * th), CrashDebris.fragment_count(8.0 * th)]))
	var d := CrashDebris.new()
	var none := d.shed(Vector3(0, 1, 0), Vector3(3, 0, 0), th * 0.5)
	var some := d.shed(Vector3(0, 1, 0), Vector3(3, 0, 0), th * 6.0)
	var leaves := d.fragments.size() == some and d.get_child_count() == some
	var max_x := 0.0
	for i in int(3.0 / DT):
		d.step(DT)
		for f in d.fragments:
			max_x = maxf(max_x, (f["node"] as Node3D).position.x)
	var settled := true
	for f in d.fragments:
		settled = settled and bool(f["rest"]) and absf((f["node"] as Node3D).position.y - CrashDebris.FRAGMENT_SIZE_M.y * 0.5) < 1e-6
	r.append(TestResult.new("b5 r2.5: fragments leave with the impact velocity, fall, and settle on the ground",
		none == 0 and some == 6 and leaves and max_x > 0.5 and settled, "none %d some %d max_x %.2f settled %s" % [none, some, max_x, settled]))
	for i in int(CrashDebris.LIFETIME_S / DT) + 2:
		d.step(DT)
	r.append(TestResult.new("b5 r2.5: fragments despawn after LIFETIME_S", d.fragments.is_empty() and d.get_child_count() == 0,
		str(d.fragments.size())))
	d.free()


static func _through_main(r: Array) -> void:
	var m := _booted()
	for i in 60:
		m._physics_process(DT)
	m._apply_camera_mount()   # what _process does each drawn frame (out of tree, _process's wash update errors)
	var eye: Node3D = m.airframe.camera_eye()
	var vib: VibrationModel = m.core.gyro.vibration
	var want: Basis = Basis.from_euler(m.camera_mount.offset(vib)) * m._eye_base
	# The offset is microradians at hover (see FpvMount), below a quaternion angle's float precision, so the lens is
	# compared column by column: equal to the mount's rotation of the base, and moved from the base by about |offset|.
	var off: Vector3 = m.camera_mount.offset(vib)
	var err := 1.0
	var moved := 0.0
	if eye != null:
		err = (eye.basis.x - want.x).length() + (eye.basis.y - want.y).length() + (eye.basis.z - want.z).length()
		moved = maxf((eye.basis.z - m._eye_base.z).length(), maxf((eye.basis.x - m._eye_base.x).length(), (eye.basis.y - m._eye_base.y).length()))
	r.append(TestResult.new("b5 r2.3: the FPV lens is the airframe's lens moved by the mount's offset of the live vibration",
		eye != null and m.camera_mount.vibration_offset(vib).length() > 0.0 and err < 1e-7
		and moved > 0.3 * off.length() and moved < 2.0 * off.length(), "offset %s moved %s err %s" % [off.length(), moved, err]))
	# Damage set on the core reaches the drawn prop.
	m.core.prop_damage[1] = 0.2
	m._physics_process(DT)
	var model: SimDroneModel = m.airframe
	var n1: String = MotorLayout.MOTOR_NAMES[1]
	var n0: String = MotorLayout.MOTOR_NAMES[0]
	r.append(TestResult.new("b5 r2.5: R1.1 damage reaches the drawn prop (chipped disc, wobble), and only that prop",
		is_equal_approx(model.prop_damage_drawn(n1), 0.2) and model.chip_drawn(n1) < 1.0 and model.wobble_drawn(n1) > 0.0
		and model.chip_drawn(n0) == 1.0 and model.wobble_drawn(n0) == 0.0 and model.disc_alpha_drawn(n1) > 0.0,
		"chip %.3f wobble %.4f alpha %.3f" % [model.chip_drawn(n1), model.wobble_drawn(n1), model.disc_alpha_drawn(n1)]))
	m.core.prop_damage[1] = 0.0
	# Debris through the flight path: a soft touch sheds nothing, a hard hit sheds by energy.
	var soft: int = m.shed_debris(Vector3.ZERO, Vector3.ZERO, 1.0)
	var hard: int = m.shed_debris(Vector3.ZERO, Vector3(0, -7, 0), 7.0)
	var harder: int = m.shed_debris(Vector3.ZERO, Vector3(0, -12, 0), 12.0)
	r.append(TestResult.new("b5 r2.5: main sheds no debris at 1 m/s and more at 12 than at 7 m/s",
		soft == 0 and hard > 0 and harder > hard, "%d %d %d" % [soft, hard, harder]))
	m.crash_debris.clear()
	# A real descent into the ground: R1.1 damages a prop and the frame sheds fragments.
	var p: Vector3 = m.core.rigid_body.position_m
	var gy: float = m.terrain.height_at(p.x, p.z)
	m.core.rigid_body.position_m = Vector3(p.x, gy + 0.15, p.z)
	m.core.rigid_body.velocity_mps = Vector3(0, -6.0, 0)
	var spawned := 0
	for i in 10:
		m._physics_process(DT)
		spawned = maxi(spawned, m.crash_debris.fragments.size())
	r.append(TestResult.new("b5 r2.5: a 6 m/s ground hit in flight sheds fragments",
		spawned > 0, "%d fragments, impact %.2f m/s" % [spawned, m.last_frame_impact_mps]))
	m.free()
