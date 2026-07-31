class_name TestTranslation
extends RefCounted
## The checks that the day 2-4 gates structurally could not catch, because every one of
## them holds the drone near level, where body frame and world frame agree.
##
## A quadcopter has exactly one control mechanism for going somewhere: tilt, so that part
## of its thrust points sideways. If thrust is summed in the world frame instead of the
## body frame, the drone banks correctly, self-levels correctly, passes every hover and
## step-response test — and cannot move. That is the bug these tests exist to hold down.

const DT := 0.001

static func run() -> Array:
	var results: Array = []
	results.append(_banked_flight_accelerates_sideways())
	results.append(_body_yaw_does_not_tilt_a_rolled_drone())
	results.append_array(_holds_altitude_at_published_hover_throttle())
	return results


## Hold full right roll stick in angle mode (a 30 deg bank) and fly for 3 seconds.
## tan(30 deg) * 9.81 = 5.66 m/s^2 lateral, so ~17 m/s after 3 s in the +X (right)
## direction. World-frame thrust gives exactly 0.0.
static func _banked_flight_accelerates_sideways() -> TestResult:
	var core := ReferenceBuild.build_drone_core()
	var rc := {"roll": 1.0, "pitch": 0.0, "yaw": 0.0, "throttle": 1.0}
	var fc := FlightController.new()   # angle mode by default

	for i in int(3.0 / DT):
		var cmds := fc.update(core.rigid_body.orientation, core.gyro.rate_rad_s, rc, DT)
		core.step(cmds, DT)

	var lateral_mps := core.rigid_body.velocity_mps.x
	return TestResult.new(
		"banked 30deg to the right: thrust vectors, drone accelerates right",
		lateral_mps > 5.0,
		"lateral velocity after 3s = %.3f m/s (+X = right)" % lateral_mps
	)


## Spin about the body's own yaw axis while rolled 90 degrees. Body-frame angular
## velocity integrated with the world-frame quaternion form rotates the drone about the
## world vertical instead, which tips the body axis over. The body's up vector must not
## move when the rotation is about that very axis.
static func _body_yaw_does_not_tilt_a_rolled_drone() -> TestResult:
	var body := RigidBodyState.new()
	body.orientation = Quaternion(Vector3(0, 0, 1), deg_to_rad(90.0)).normalized()
	var body_up_before := body.orientation * Vector3.UP

	var inertia := Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	body.angular_velocity_rad_s = Vector3(0, 1.0, 0)   # 1 rad/s about BODY +Y (yaw)
	for i in int(1.0 / DT):
		body.integrate(Vector3.ZERO, Vector3.ZERO, 1.0, inertia, inertia, DT)

	var body_up_after := body.orientation * Vector3.UP
	var drift_deg := rad_to_deg(body_up_before.angle_to(body_up_after))
	return TestResult.new(
		"yawing about the body axis does not tilt a rolled drone",
		drift_deg < 0.5,
		"body up-axis moved %.3f deg (should be 0)" % drift_deg
	)


## The published hover throttle has to actually hover. Solving it against nominal pack
## voltage while the sim runs on sagged voltage leaves a ~2% thrust deficit — invisible in
## a "velocity stays bounded" check, but a 12 m sink over ten seconds on screen.
##
## This was one assertion — 10 s hands-off, within 1 m — until BatteryModel grew a
## state-of-charge term. It now has to be two, because two different things are being claimed and
## the change made only one of them still true:
##
## 1. THE THROTTLE IS SOLVED CORRECTLY. That is what the original test was about, and it is
##    unaffected: a hover throttle solved against the wrong voltage is wrong from the first
##    instant, so it is measured at half a second, before drain has done anything worth measuring
##    (about 0.1% of the pack, worth 3 mm/s of sink against the 100 mm/s a 2% deficit would give).
##
## 2. THE DRONE THEN SINKS ANYWAY, because the pack is emptying and its resting voltage is
##    falling with it. That is not a regression, it is the new model being right — a real quad
##    held at one throttle setting descends slowly as the pack goes down, which is most of why
##    hovering hands-off is not a thing anyone does. The original 1 m bound survives intact as
##    the control: the SAME aircraft on a pack too large to empty still holds altitude, which is
##    what attributes the sink to the state-of-charge term and to nothing else.
static func _holds_altitude_at_published_hover_throttle() -> Array:
	var results: Array = []
	var hover := ReferenceBuild.hover_throttle()

	var draining := ReferenceBuild.build_drone_core()
	var early_climb_rate := _fly_hands_off(draining, hover, 0.5)
	results.append(TestResult.new(
		"the published hover throttle hovers: no sink at all in the first half second",
		absf(early_climb_rate) < 0.03,
		"%.4f m/s after 0.5 s (a 2%% thrust deficit would read about -0.10 m/s)" % early_climb_rate
	))

	_fly_hands_off(draining, hover, 9.5)
	var drained_drift := draining.rigid_body.position_m.y

	# The control: the identical aircraft on a pack whose capacity is large enough that ten
	# seconds of hover empties none of it. Nothing else about the pack changes — same nominal
	# voltage, same internal resistance, so the same sag under the same current.
	var full := ReferenceBuild.build_drone_core()
	full.powertrain.battery.capacity_mah *= 100000.0
	_fly_hands_off(full, hover, 10.0)
	var undrained_drift := full.rigid_body.position_m.y

	results.append(TestResult.new(
		"10s hands-off on a pack that cannot empty: holds altitude within 1 m",
		absf(undrained_drift) < 1.0,
		"altitude drift = %.3f m (V_live=%.2f V, I=%.1f A)" % [
			undrained_drift, full.observables.voltage_live_v, full.observables.current_total_a]
	))

	results.append(TestResult.new(
		"on a real pack it sinks instead, and the drain is the whole of the difference",
		drained_drift < -0.5 and drained_drift < undrained_drift - 0.5,
		"%.2f m draining (%.1f%% of the pack used) vs %.2f m on a pack that cannot empty" % [
			drained_drift, draining.observables.capacity_used_fraction * 100.0, undrained_drift]
	))

	return results


## Flies `seconds` of hands-off angle mode at a fixed throttle, and reports the climb rate at the
## end. Continues from wherever the core already is, so a run can be measured part way through
## and then carried on rather than being started again from a different state.
static func _fly_hands_off(core: DroneCore, throttle: float, seconds: float) -> float:
	if core.observables.rpm[0] <= 0.0:
		core.prime_motors(throttle)
	var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": throttle}
	var fc := FlightController.new()   # angle mode by default
	for _i in int(seconds / DT):
		var cmds := fc.update(core.rigid_body.orientation, core.gyro.rate_rad_s, rc, DT)
		core.step(cmds, DT)
	return core.rigid_body.velocity_mps.y
