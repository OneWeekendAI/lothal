class_name DroneCore
extends RefCounted
## The physics core (architecture.md): a Powertrain plus a rigid body. Zero engine/scene
## dependencies — a scene node drives this by calling step() every substep and reading
## rigid_body afterward, nothing more.
##
## Everything electrical lives in Powertrain, which runs perfectly well without this class.
## That is what lets Lothal Labs bench a motor with no flight simulation: the field is the
## garage plus an integrator, and there is only one copy of the electrical model.

const GRAVITY_MPS2 := 9.81

var powertrain: Powertrain
var mass_properties: MassProperties
var rigid_body := RigidBodyState.new()
## The aircraft's rate sensor. It lives here, on the aircraft, rather than in the scene:
## the flight controller must have exactly ONE route to a rate, and if a consumer can reach
## around this to rigid_body.angular_velocity_rad_s then the seam exists on paper only.
##
## HANDED IN rather than constructed here, because its four figures are properties of the
## FLIGHT CONTROLLER that is fitted (data/parts/flight_controllers.json) and a core that
## built its own would be a second opinion about what board this aircraft has. A core built
## without one gets the stock sensor, so every call site written before flight controllers
## were selectable still means what it meant.
var gyro: Gyro
## The accelerometer on the same IMU (R1.2): body-frame specific force, with noise, bias and the
## gyro's vibration. The attitude estimator reads this; nothing else should.
var accel := Accelerometer.new()
## The FC's battery-voltage sensor (R1.3): the pack's true voltage through ADC noise and a low-pass.
## Its `cells` is the fitted pack's cell count; the reference is cells x Betaflight's full-cell voltage.
var vbat := VbatSensor.new()
## The air's own motion, or null on a still day. HANDED IN, not constructed here, for the same
## reason `gyro` is: null means "nobody has told this core about the field it is flying at",
## which is every core built before F7 and every test that has never heard of `Wind` — those keep
## flying the calm air they always did, and check 1 is the proof that keeping this null costs them
## nothing. `Sim authors nothing`: this class never writes to it, only reads `velocity_mps()`.
var wind: Wind = null
var arm_m: float
## 0.5 * rho * Cd * A, supplied per build — a 7" airframe presents far more area than a 3".
var drag_coefficient: float
## SR1: 0.5*rho*Cd*A per BODY axis (x side, y top/rotor axis, z frontal), or (-1,-1,-1) for "isotropic,
## use drag_coefficient" (every core built before directional drag, and every test that never heard of it).
var drag_axes := Vector3(-1.0, -1.0, -1.0)

## SR1 ground effect (Cheeseman-Bennett). OFF by default: every flight written before this had no
## ground under it, and a hover test that sits at y = 0 would otherwise be flattered by a floor it
## never had. A caller that has a ground turns it on and says where it is.
var ground_effect_enabled := false
## World height of the ground plane, m.
var ground_y_m := 0.0
## GROUND CONTACT, opt-in and OFF by default. This core is a free body: with it off, an aircraft whose thrust is
## below its weight simply sinks through y = ground_y_m, which is what every flight written before this
## expected (the sim's crash check and respawn live in the scene, not here). With it ON the ground pushes
## back: the centre of mass cannot go below `ground_y_m + rest_height_m`, and while it is held there it
## neither sinks nor tumbles. THIS IS NOT A THROTTLE GATE: nothing here looks at thrust or mass. The
## aircraft stays down because gravity beats the rotors, and rises the instant the rotors beat gravity.
var ground_contact_enabled := false
## TURTLE MODE (FlightController.turtle): the ESCs spin every motor BACKWARDS, so each prop pushes along body -Y and
## its reaction torque flips sign. Set by the scene from the FC each substep.
var motors_reversed := false
## ESTIMATE. Thrust a pitched FPV prop makes run backwards, as a fraction of forward thrust at the same rpm: the
## airfoil meets the air on its trailing edge and its camber works against it. Plausible for a 5" tri-blade; to be
## replaced by a thrust-stand reading. The powertrain still draws forward-spin current for it (also an estimate).
const REVERSED_THRUST_FRACTION := 0.5
## How high the centre of mass sits above the lowest point of the aircraft when it rests, m (Build.rest_height_m).
var rest_height_m := 0.0
## B1 ROTOR H-FORCE: the in-plane drag of each rotor in edgewise flow, from blade-element theory (RotorHForce,
## Leishman / Johnson). Per rotor, H = -(Omega * P + Lambda * I) * v_inplane at that rotor's hub, against the AIR.
## `h_coeffs` is (P, I) for the fitted blade, set at construction; zero (no planform) means no H-force.
## `rotor_h_force_enabled` exists so a test can ablate it.
var h_coeffs := Vector2.ZERO
var air_density_kgm3 := 1.225
var rotor_h_force_enabled := true
## Blade pitch at 0.75 R and the flap-response factor of the flapping H-force (RotorHForce.flap_per_mps); a var so a
## test can ablate flapping alone.
var theta_75 := 0.0
var flap_response := RotorHForce.FLAP_RESPONSE
## Mean flap tilt a1 (rad) of the rotors, from the state at the START of this tick (the rpm and thrust the last tick or
## prime_motors left), at the aircraft's air velocity; the powertrain reads its flow in that tilted tip-path plane.
var flap_tilt_rad := 0.0
## Ablation switch: false reads the power flow at the SHAFT, charging the flapping H-force as shaft power (the B1 bug).
var flap_tpp_enabled := true
var _k_t := 0.0
## The BEMT ratio surface (cached in Rust, the same table the powertrain holds), for the first-tick thrust estimate.
var _ratios: BemtRatios
## Rotor radius, m (from the propeller), the length scale the ground effect is measured in.
var prop_radius_m := 0.0635
## Height of the rotor plane above the CoM, m. ESTIMATED 0.02 (motors sit just above the plate).
var rotor_above_com_m := 0.02

## Cheeseman-Bennett thrust gain at constant power for a rotor of radius R with its disc z above the
## ground:  T/T_inf = 1 / (1 - (R / 4z)^2). The formula is a far-field image-vortex result and has no
## business below z = R/2, so z is floored there (gain 1.33). ABOVE z = R it is faded to exactly 1.0
## at z = 2R with a cosine taper (the textbook gain at 2R is still 1.6 percent; a hover test wants a
## finite effect range, and the measured gain beyond 1 diameter is within the scatter).
## R1.1: what the aircraft can hit. Null (the default) means no collision at all, exactly as before.
var collision_world: CollisionWorld = null
## R1.1: thrust fraction each motor has LOST to impacts, 0 (sound) .. 1 (gone), in MotorLayout.MOTOR_NAMES order.
var prop_damage: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
## R1.1: set when a hit reaches CollisionConstants.CRASH_SPEED_MPS. The scene reads it and respawns.
var crashed := false
## R1.1: the largest normal speed of the latest step's contacts, and of the whole flight since repair().
var last_impact_speed_mps := 0.0
var peak_impact_speed_mps := 0.0

## Back to a sound aircraft: damage and the crash flag cleared (a respawn is a new airframe).
func repair() -> void:
	prop_damage = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	crashed = false
	last_impact_speed_mps = 0.0
	peak_impact_speed_mps = 0.0

static func ground_effect_gain(height_m: float, radius_m: float) -> float:
	if radius_m <= 0.0 or height_m >= 2.0 * radius_m:
		return 1.0
	var z := maxf(height_m, 0.5 * radius_m)
	var gain := 1.0 / (1.0 - pow(radius_m / (4.0 * z), 2.0))
	var fade := 1.0
	if z > radius_m:
		fade = 0.5 * (1.0 + cos(PI * (z - radius_m) / radius_m))
	return 1.0 + (gain - 1.0) * fade

## The published observables layer — the SAME instance the powertrain fills, so a consumer
## cannot tell which half published what. Refilled at the end of every step(); no consumer
## should read physics internals directly.
var observables: Observables
## The motor commands of the most recent step(), MotorLayout.MOTOR_NAMES order. Published so a test can
## measure the flight controller's command variance (R1.4: it is what turns into copper loss).
var last_motor_cmds := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])

## The build's `config` decision block (C1), for the one value of it that reaches the physics:
## motor spin direction, read through MotorLayout.spin_map() — design §5. Empty means today's
## constants, so a core built by any caller that has never heard of Config is the aircraft it
## always was.
var config: Dictionary = {}

func _init(p_mass_properties: MassProperties, p_motor_model: MotorModel, p_arm_m: float, p_k_t: float, p_k_q: float, p_battery: BatteryModel, p_motor_max_amps: float, p_rated_rpm: float, p_drag_coefficient: float, p_pole_pairs: float = 7.0, p_blades: float = 3.0, p_prop_radius_m: float = 0.0635, p_gyro: Gyro = null, p_prop_pitch_m: float = 0.10922,
		p_air_density_kgm3: float = AirDensity.standard_kgm3(),
		p_blade_chord_mm: PackedFloat64Array = PackedFloat64Array(),
		p_guard_closure: float = 0.0,
		p_blade_twist: PackedFloat64Array = PackedFloat64Array()) -> void:
	# ONE call, always `create_with_guard`. A branch on `p_guard_closure > 0.0` would be two
	# code paths to keep in step for no gain: `Powertrain.create` itself delegates here with
	# 0.0, and the Rust cache key bit-encodes 0.0 verbatim, so an unguarded build reaches the
	# SAME cache entry `create` used to and pays no extra solve. Its 496 g / 11.69:1 / 29.6%
	# oracles are bit-identical for that reason rather than because a branch skipped the code.
	powertrain = Powertrain.create_with_guard(p_motor_model, p_k_t, p_k_q, p_battery,
		p_motor_max_amps, p_rated_rpm, p_pole_pairs, p_blades, p_prop_radius_m,
		p_prop_pitch_m, p_air_density_kgm3, p_blade_chord_mm, p_guard_closure, p_blade_twist)
	observables = powertrain.observables
	mass_properties = p_mass_properties
	arm_m = p_arm_m
	prop_radius_m = p_prop_radius_m
	drag_coefficient = p_drag_coefficient
	h_coeffs = RotorHForce.coefficients(p_blades, p_prop_radius_m, p_prop_pitch_m, p_blade_chord_mm, p_blade_twist,
		p_air_density_kgm3)
	air_density_kgm3 = p_air_density_kgm3
	_k_t = p_k_t
	_ratios = BemtRatios.for_prop_with_guard(2.0 * p_prop_radius_m, p_prop_pitch_m, p_blades, p_blade_chord_mm,
		p_guard_closure, p_blade_twist)
	theta_75 = RotorHForce.theta_75(p_prop_radius_m, p_prop_pitch_m, p_blade_twist)
	gyro = p_gyro if p_gyro != null else Gyro.new()
	vbat.cells = int(p_battery.cells)
	_publish(Vector3.ZERO)

## Current drawn by ONE motor at a given RPM. Delegates: there is one such function in the
## codebase and it is the powertrain's.
func current_at_rpm(rpm: float) -> float:
	return powertrain.current_at_rpm(rpm)

## Places all four motors at the steady-state RPM for a given throttle, and the pack at
## the voltage that draws. Motors otherwise start dead: spinning up through the ~30 ms lag
## costs about 0.4 m/s of downward velocity, and with no altitude hold in week 1 that
## velocity never comes back — the drone spawns and sinks forever at a constant rate.
func prime_motors(throttle: float) -> void:
	powertrain.prime(throttle)
	# Priming is a state change like any other, and consumers read observables between a
	# respawn and the next step(). Leaving the flight half stale here means the HUD spends
	# one frame reporting the g-force of the flight that just ended in a crash.
	_publish(Vector3.ZERO)

## motor_throttle_cmds = {"M1": 0..1, "M2": 0..1, "M3": 0..1, "M4": 0..1}
## B1: the rotors' mean flap tilt a1 (RotorHForce.flap_per_mps x v_edge / T) at body air velocity `v_body`, from the
## current rpm and published thrust. Zero with the H-force off or flapping ablated.
func _mean_flap_tilt(v_body: Vector3) -> float:
	if not rotor_h_force_enabled or h_coeffs == Vector2.ZERO or flap_response == 0.0:
		return 0.0
	var v_e := Vector2(v_body.x, v_body.z).length()
	if v_e <= 0.0:
		return 0.0
	var omega := 0.0
	var thrust := 0.0
	for i in MotorLayout.MOTOR_NAMES.size():
		omega += powertrain.motor_rpm[i] * TAU / 60.0 * 0.25
		thrust += powertrain.observables.thrust_n[i] * 0.25
	if omega <= 1.0:
		return 0.0
	var a1 := flap_tilt_rad
	var passes := 1
	var rpm := omega * 60.0 / TAU
	if thrust <= 0.0:
		# Straight after prime_motors nothing has published a thrust yet: the thrust this rpm makes in the tilted
		# tip-path plane (the powertrain's own law) stands in, settled with a1 in three passes as Build does.
		passes = 8
	for _p in passes:
		if passes > 1:
			var flow := RotorHForce.tpp_flow(v_body.y, v_e, a1)
			thrust = PropellerModel.thrust_n(_k_t, rpm) * _ratios.thrust_ratio(rpm, flow.x, flow.y)
		if thrust <= 0.0:
			return 0.0
		var inflow := RotorHForce.inflow_mps(thrust, v_body.y, v_e, air_density_kgm3, prop_radius_m)
		a1 = RotorHForce.flap_per_mps(thrust, omega, prop_radius_m, inflow, v_e, theta_75, flap_response) * v_e / thrust
	return a1


func step(motor_throttle_cmds: Dictionary, dt: float) -> void:
	# The powertrain advances first: the forces below are built from the RPM this produces,
	# which is the same ordering the single fused loop had. Across the FFI the powertrain's
	# step takes the commands as a typed array (MotorLayout.MOTOR_NAMES order), so the
	# string-keyed Dictionary is unpacked here, once, rather than carried across the boundary.
	var cmds := PackedFloat64Array()
	for name in MotorLayout.MOTOR_NAMES:
		cmds.append(motor_throttle_cmds.get(name, 0.0))
	last_motor_cmds = cmds
	# The powertrain is told how the aircraft is MOVING, not just what the sticks asked for. Without
	# this line the propeller behaves identically parked and at 120 km/h: no unloading at speed, and
	# no translational lift, so forward flight costs the same current as hovering. Both halves
	# matter and they pull opposite ways — see PropellerModel's forward-flight block.
	#
	# In the BODY frame, because that is where the rotor axis is: thrust is along body +Y, so the
	# component of velocity that unloads the prop is simply .y, and nothing has to decide what a
	# lean angle's sign convention is. Taken BEFORE integration, so it is the velocity this tick's
	# forces are being built at, which is the same convention every other term here uses.
	#
	# AIRSPEED, not ground speed: what unloads a prop and pushes against a frame is the air moving
	# past it, and wind is exactly the difference between the two. Subtracted in the WORLD frame,
	# THEN rotated into body — subtracting after rotation would rotate the wind by the aircraft's
	# own attitude instead of leaving it as the ground-referenced vector it is (check 4/5's guard).
	# Wind reaches here and the drag term below, and nowhere else: everything downstream of the
	# powertrain — thrust, lean, current, the edgewise-flow term — still reads a velocity and never
	# knows where it came from.
	# Advanced once per substep, here — the ONE place the gust process steps forward, so a
	# consumer reading wind.velocity_mps() between substeps (the HUD) sees this tick's value
	# without itself advancing anything.
	var wind_mps := wind.update_at(dt, rigid_body.position_m, maxf(rigid_body.position_m.y - ground_y_m, 0.0)) if wind != null else Vector3.ZERO
	var relative_velocity_mps := rigid_body.velocity_mps - wind_mps
	# B1: the powertrain reads the flow in the rotors' TIP-PATH PLANE, flapped back by last tick's mean a1 (see
	# RotorHForce.tpp_flow): flapping tilts the thrust and does no work, so it must not reach the shaft power.
	var v_power := rigid_body.orientation.inverse() * relative_velocity_mps
	flap_tilt_rad = _mean_flap_tilt(v_power)
	if flap_tpp_enabled and flap_tilt_rad != 0.0:
		var e := Vector2(v_power.x, v_power.z)
		var e_len := e.length()
		if e_len > 0.0:
			var tpp := RotorHForce.tpp_flow(v_power.y, e_len, flap_tilt_rad)
			var dir := e / e_len
			v_power = Vector3(dir.x * tpp.y, tpp.x, dir.y * tpp.y)
	powertrain.step_in_flight(cmds, dt, v_power)

	var total_force := Vector3(0, -GRAVITY_MPS2 * mass_properties.total_mass_kg, 0)
	var total_torque := Vector3.ZERO
	var total_thrust_body_n := 0.0

	# Resolved once per step rather than per motor, and from the SAME accessor the mixer reads.
	var spin_map := MotorLayout.spin_map(config)
	var ge_gain := 1.0
	if ground_effect_enabled and not motors_reversed:
		ge_gain = ground_effect_gain(rigid_body.position_m.y + rotor_above_com_m - ground_y_m, prop_radius_m)

	for i in MotorLayout.MOTOR_NAMES.size():
		var name: String = MotorLayout.MOTOR_NAMES[i]
		# A damaged prop gives only what is left of it (R1.1): the same scaling reaches the torque below.
		var thrust_n: float = powertrain.observables.thrust_n[i] * (1.0 - prop_damage[i])
		# Read, not recomputed: the powertrain stepped and published a line above, so this is the
		# reaction torque of THIS tick's rpm, and it is the same number any consumer reading the
		# observables layer sees. A second k_q x omega^2 here would agree with it exactly until
		# the day one of the two was edited.
		var reaction_n_m: float = powertrain.observables.reaction_torque_n_m[i]
		if motors_reversed:
			thrust_n *= -REVERSED_THRUST_FRACTION
			reaction_n_m = -reaction_n_m

		total_thrust_body_n += thrust_n * ge_gain

		# Arms are measured from the CENTRE OF MASS, not from the frame's origin — the aircraft
		# rotates about the former, and the inertia tensor this torque is about to be integrated
		# against is already computed about it too (MassProperties). MotorLayout owns the cross
		# product; this loop must not grow a second one, which is the duplication that made the
		# reference point possible to get wrong in only one of two places.
		var tau := MotorLayout.thrust_torque(name, thrust_n * ge_gain, arm_m, mass_properties.com_m)
		var spin: float = spin_map[name]
		var reaction_about_y := -spin * reaction_n_m   # Newton's third law: opposes the rotor's own spin
		total_torque += Vector3(tau.x, reaction_about_y, tau.z)

	# Thrust is generated along BODY +Y and must be rotated into the world frame before it
	# is summed with gravity and drag (physics.md §4, "along body +Y"). Skipping this
	# rotation leaves the drone unable to translate at all: it banks and stays put, because
	# a tilted quad's thrust would still point straight up. Torque stays in the body frame,
	# which is where the inertia tensor and the gyroscopic term live.
	total_force += rigid_body.orientation * Vector3(0, total_thrust_body_n, 0)

	# Drag is against the AIR, the same relative_velocity_mps the powertrain read above — flying
	# downwind at wind speed costs no drag, into it costs more, exactly like the airspeed the
	# powertrain sees (check 6's guard: wind reaching one and not the other is the stated mutation).
	var speed := relative_velocity_mps.length()
	if speed > 0.0:
		if drag_axes.x < 0.0:
			total_force += -relative_velocity_mps.normalized() * drag_coefficient * speed * speed
		else:
			# Directional: the air is resolved into the BODY frame, each body axis has its own area, and
			# the force is rotated back. A leaned aircraft therefore presents a mix of frontal and top
			# area, which is the body-angle effect the scalar could not carry.
			var v_body := rigid_body.orientation.inverse() * relative_velocity_mps
			var f_body := -speed * Vector3(drag_axes.x * v_body.x, drag_axes.y * v_body.y, drag_axes.z * v_body.z)
			total_force += rigid_body.orientation * f_body

	# B1 rotor H-force (see RotorHForce): per rotor, from that hub's own air-relative velocity (aircraft velocity
	# minus wind, plus omega x r), in the rotor plane, applied AT the hub so it also pitches/yaws the aircraft.
	# Not modelled for a reversed prop (turtle is a ground manoeuvre at near-zero airspeed).
	if rotor_h_force_enabled and h_coeffs != Vector2.ZERO and not motors_reversed:
		var v_air_body := rigid_body.orientation.inverse() * relative_velocity_mps
		var w_body := rigid_body.angular_velocity_rad_s
		var h_force_body := Vector3.ZERO
		for i in MotorLayout.MOTOR_NAMES.size():
			var omega: float = powertrain.motor_rpm[i] * TAU / 60.0
			if omega <= 1.0:
				continue
			var hub := MotorLayout.motor_position(MotorLayout.MOTOR_NAMES[i], arm_m) - mass_properties.com_m
			hub.y = rotor_above_com_m
			var v_hub := v_air_body + w_body.cross(hub)
			var v_plane := Vector3(v_hub.x, 0.0, v_hub.z)
			if v_plane.length_squared() <= 0.0:
				continue
			var t_i: float = powertrain.observables.thrust_n[i] * (1.0 - prop_damage[i]) * ge_gain
			var inflow := RotorHForce.inflow_mps(t_i, v_hub.y, v_plane.length(), air_density_kgm3, prop_radius_m)
			var v_e := v_plane.length()
			var flap_i := RotorHForce.flap_per_mps(t_i, omega, prop_radius_m, inflow, v_e, theta_75, flap_response)
			var per := RotorHForce.per_mps(h_coeffs, omega, inflow) * (1.0 - prop_damage[i]) + flap_i
			var h_i := -per * v_plane
			h_force_body += h_i
			total_torque += hub.cross(h_i)
		total_force += rigid_body.orientation * h_force_body

	# Specific force — total force minus gravity — is captured BEFORE integration, while
	# the force that produced this tick's acceleration is still in hand. Recovering it
	# afterwards from a velocity difference would be a numerical derivative of an
	# integrated quantity, which is both noisier and one tick late.
	var specific_force := total_force + Vector3(0, GRAVITY_MPS2 * mass_properties.total_mass_kg, 0)
	var accel_orientation := rigid_body.orientation   # the body the force acted on, before it moves

	rigid_body.integrate(total_force, total_torque, mass_properties.total_mass_kg, mass_properties.inertia, mass_properties.inertia_inverse, dt)
	if ground_contact_enabled:
		var floor_y := ground_y_m + rest_height_m
		if rigid_body.position_m.y <= floor_y and rigid_body.velocity_mps.y <= 0.0:
			rigid_body.position_m.y = floor_y
			# Supported: the ground takes the weight, and a body sitting on it does not spin or slide.
			rigid_body.velocity_mps = Vector3.ZERO
			rigid_body.angular_velocity_rad_s = Vector3.ZERO
			# And it pushes back: an accelerometer on the ground reads 1 g, not the near-zero a
			# bare thrust sum would give.
			specific_force.y += maxf(0.0, -total_force.y)
	if collision_world != null:
		_resolve_collisions()

	# The sensor's shake follows the MOTORS, so the four current rpms are handed over before the
	# sample. Four rather than one average: they are not equal while the aircraft is manoeuvring,
	# and that inequality is what turns the signal into a beating, wandering thing instead of a
	# single sine. Pushed rather than pulled because Gyro must not know what a Powertrain is —
	# it is a sensor, and this core is the one thing that holds both halves.
	if gyro.vibration is VibrationModel:
		gyro.vibration.set_rpm(powertrain.motor_rpm)
		gyro.vibration.set_damage(prop_damage)

	# Sampled AFTER integration, so the reading the controller picks up at the top of the
	# next substep is one tick old. That is not an approximation to apologise for — it is
	# what a real loop does, and the delay is part of what the gains are tuned against.
	gyro.update(rigid_body.angular_velocity_rad_s, dt)
	vbat.update(powertrain.observables.voltage_live_v, dt)
	accel.update(accel_orientation.inverse() * (specific_force / mass_properties.total_mass_kg),
		gyro.last_vibration_rad_s, dt)

	_publish(specific_force)

## Fills the FLIGHT half of the observables layer; the powertrain half is already filled by
## Powertrain.publish(). Republishing the powertrain half here is what this split exists to
## prevent, so this function must never recompute rpm, thrust, blade-pass or voltage.
##
## It does still CALL powertrain.publish(), which is a different thing: tests/test_observables.gd
## writes RPM straight into core.motor_rpm and then calls _publish, expecting blade-pass to be
## recomputed from it — precisely the check that blade-pass has one expression in the codebase.
## The republish is idempotent; it recomputes from stored state and integrates nothing.
## R1.1: the aircraft's contact points, body frame, from the COM. The central body, the four arm hubs and
## the four prop tips: the frame's and props' own extents (arm_m, prop_radius_m), not a bounding box.
## Each is {"r": Vector3, "radius": float, "motor": int (-1 for the body)}.
func contact_points() -> Array[Dictionary]:
	# B4/Q1: cached on the inputs that define it, since this ran (nine dictionaries) every 1 kHz substep.
	var key := [arm_m, mass_properties.com_m, rotor_above_com_m, prop_radius_m]
	if key == _contact_key:
		return _contact_cache
	_contact_key = key
	_contact_cache = _build_contact_points()
	_contact_bound_r = 0.0
	for point in _contact_cache:
		_contact_bound_r = maxf(_contact_bound_r, (point["r"] as Vector3).length() + float(point["radius"]))
	return _contact_cache


## The radius of a sphere about the COM holding every contact sphere (set with the contact-point cache).
var _contact_bound_r := 0.0


var _contact_key: Array = []
var _contact_cache: Array[Dictionary] = []


func _build_contact_points() -> Array[Dictionary]:
	var points: Array[Dictionary] = [{"r": Vector3.ZERO, "radius": CollisionConstants.BODY_RADIUS_M, "motor": -1}]
	for i in MotorLayout.MOTOR_NAMES.size():
		var hub := MotorLayout.motor_position(MotorLayout.MOTOR_NAMES[i], arm_m) - mass_properties.com_m
		hub.y = rotor_above_com_m
		var outward := Vector3(hub.x, 0.0, hub.z).normalized()
		points.append({"r": hub, "radius": CollisionConstants.POINT_RADIUS_M, "motor": i})
		points.append({"r": hub + outward * prop_radius_m, "radius": CollisionConstants.POINT_RADIUS_M, "motor": i})
	return points


## Pushes the aircraft out of whatever it overlaps and applies the impulse for each contact. Below
## BOUNCE_SPEED_MPS: restitution + friction. Up to CRASH_SPEED_MPS: no bounce, the touching prop(s) lose
## thrust. At or above it: `crashed`.
func _resolve_collisions() -> void:
	last_impact_speed_mps = 0.0
	var mass := mass_properties.total_mass_kg
	var points := contact_points()
	# B4/Q1: one query for the whole aircraft when it is clear of everything (exact: see CollisionWorld.clear_of).
	if collision_world.clear_of(rigid_body.position_m, _contact_bound_r):
		return
	for point in points:
		var r_body: Vector3 = point["r"]
		var r_world := rigid_body.orientation * r_body
		var hit := collision_world.contact(rigid_body.position_m + r_world, float(point["radius"]))
		if hit.is_empty():
			continue
		var normal: Vector3 = hit["normal"]
		rigid_body.position_m += normal * float(hit["depth"])
		var speed := rigid_body.approach_speed(r_body, normal)
		if speed <= 0.0:
			continue
		last_impact_speed_mps = maxf(last_impact_speed_mps, speed)
		peak_impact_speed_mps = maxf(peak_impact_speed_mps, speed)
		var restitution := 0.0
		if speed >= CollisionConstants.CRASH_SPEED_MPS:
			crashed = true
		elif speed >= CollisionConstants.BOUNCE_SPEED_MPS:
			_damage_from_hit(int(point["motor"]), speed)
		elif speed >= CollisionConstants.REST_SPEED_MPS:
			restitution = CollisionConstants.RESTITUTION
		rigid_body.apply_contact_impulse(r_body, normal, restitution, CollisionConstants.FRICTION, mass,
			mass_properties.inertia_inverse)


func _damage_from_hit(motor: int, speed: float) -> void:
	var band := CollisionConstants.CRASH_SPEED_MPS - CollisionConstants.BOUNCE_SPEED_MPS
	var severity := clampf((speed - CollisionConstants.BOUNCE_SPEED_MPS) / band, 0.0, 1.0)
	var lost := severity * CollisionConstants.MAX_DAMAGE_PER_HIT
	if motor >= 0:
		prop_damage[motor] = minf(1.0, prop_damage[motor] + lost)
	else:
		for i in prop_damage.size():
			prop_damage[i] = minf(1.0, prop_damage[i] + lost * CollisionConstants.BODY_HIT_DAMAGE_SHARE)


func _publish(specific_force_n: Vector3) -> void:
	powertrain.publish()

	observables.weight_n = mass_properties.total_mass_kg * GRAVITY_MPS2

	observables.position_m = rigid_body.position_m
	observables.velocity_mps = rigid_body.velocity_mps
	observables.orientation = rigid_body.orientation
	observables.angular_velocity_rad_s = rigid_body.angular_velocity_rad_s
	observables.gyro_rad_s = gyro.rate_rad_s
	observables.airspeed_mps = rigid_body.velocity_mps.length()

	var specific_accel := specific_force_n / mass_properties.total_mass_kg
	observables.accel_body_mps2 = rigid_body.orientation.inverse() * specific_accel
	observables.g_force = specific_accel.length() / GRAVITY_MPS2
