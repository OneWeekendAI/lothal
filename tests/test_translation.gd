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
	results.append(_holds_altitude_at_published_hover_throttle())
	return results


## Hold full right roll stick in angle mode (a 30 deg bank) and fly for 3 seconds.
## tan(30 deg) * 9.81 = 5.66 m/s^2 lateral, so ~17 m/s after 3 s in the +X (right)
## direction. World-frame thrust gives exactly 0.0.
static func _banked_flight_accelerates_sideways() -> TestResult:
	var core := ReferenceBuild.build_drone_core()
	var rc := {"roll": 1.0, "pitch": 0.0, "yaw": 0.0, "throttle": 1.0}

	for i in int(3.0 / DT):
		var cmds := AngleModeController.update(core.rigid_body.orientation, core.rigid_body.angular_velocity_rad_s, rc)
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
static func _holds_altitude_at_published_hover_throttle() -> TestResult:
	var core := ReferenceBuild.build_drone_core()
	var hover := ReferenceBuild.hover_throttle()
	core.prime_motors(hover)
	var rc := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": hover}

	for i in int(10.0 / DT):
		var cmds := AngleModeController.update(core.rigid_body.orientation, core.rigid_body.angular_velocity_rad_s, rc)
		core.step(cmds, DT)

	var altitude_m := core.rigid_body.position_m.y
	return TestResult.new(
		"10s hands-off at published hover throttle: holds altitude within 1 m",
		absf(altitude_m) < 1.0,
		"altitude drift = %.3f m (V_live=%.2f V, I=%.1f A)" % [altitude_m, core.last_voltage_v, core.last_current_total_a]
	)
