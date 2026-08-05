class_name TestTorqueReference
extends RefCounted
## The reference point torque is taken about.
##
## A motor's torque arm is the vector from the point the aircraft ROTATES about to where the
## thrust is applied — and the aircraft rotates about its centre of mass, not about the frame's
## geometric origin. Those coincided for the whole of the project's life so far, because every
## mass in every build sat at the origin or was symmetric about it, and while they coincide the
## distinction is invisible: r x F returns the same number either way.
##
## It stops being invisible the moment a mass moves off the origin, and it fails SILENTLY when it
## does. The aircraft still flies; every torque is simply wrong by (com x F), which reads as a tune
## that mysteriously stopped equalising across the catalog. The search would start in RateTune,
## which would be innocent.
##
## The other half of the same fact: MassProperties already shifts every part's inertia about the
## COMPOSITE CENTRE OF MASS (mass_properties.gd, parallel axis relative to `com`). So an
## origin-referenced torque handed to integrate() alongside that tensor is two different reference
## points in one equation of motion. This suite pins the one that is right.
##
## These tests are written to hold with the centre of mass AT the origin — which is where every
## build's still is when this suite lands — so they are the fix's proof and not its consequence.

const EPSILON := 1e-12

static func run() -> Array:
	var results: Array = []
	var arm_m := 0.11
	var thrust_n := 2.0

	# ---------------------------------------------------------------------------
	# The hazard itself: an offset centre of mass must change the torque.
	# ---------------------------------------------------------------------------
	# 40 mm forward is a pack slid to the end of a real 5" frame's travel, not a contrived number.
	# Forward is -Z (physics.md §1).
	var com_forward := Vector3(0.0, 0.0, -0.040)
	var at_origin := MotorLayout.thrust_torque("M2", thrust_n, arm_m, Vector3.ZERO)
	var at_com := MotorLayout.thrust_torque("M2", thrust_n, arm_m, com_forward)

	results.append(TestResult.new(
		"an offset centre of mass changes a motor's torque",
		(at_com - at_origin).length() > 1e-6,
		"origin %s vs com-referenced %s" % [at_origin, at_com]
	))

	# And by exactly the right amount: moving the reference point by `com` shortens every arm by
	# `com`, so the torque changes by -(com x F). Asserted as an identity rather than as a
	# magnitude, because a test that only checked "it differs" would pass for any wrong offset.
	var lift := Vector3(0.0, thrust_n, 0.0)
	var expected_delta := (-com_forward).cross(lift)
	results.append(TestResult.new(
		"the change is exactly -(com x F)",
		(at_com - at_origin - expected_delta).length() < 1e-9,
		"delta %s expected %s" % [at_com - at_origin, expected_delta]
	))

	# A motor DIRECTLY above the centre of mass has no torque arm at all. The cleanest statement
	# of what "about the centre of mass" means: put the reference point under the thrust and the
	# torque vanishes, whatever the frame's origin happens to be.
	var m2 := MotorLayout.motor_position("M2", arm_m)
	var under_m2 := MotorLayout.thrust_torque("M2", thrust_n, arm_m, m2)
	results.append(TestResult.new(
		"a motor directly above the CoM contributes no torque",
		under_m2.length() < 1e-9,
		"got %s" % under_m2
	))

	# ---------------------------------------------------------------------------
	# One reference point, one cross product.
	# ---------------------------------------------------------------------------
	# MotorLayout.torque_from_motor() and DroneCore both took r x F before this slice. That
	# duplication was survivable only while the answer could not differ; with a reference point to
	# get wrong it is two places to get it wrong in. torque_from_motor must now be a re-labelling
	# of thrust_torque into the coordinate contract's axes and nothing more, so this asserts the
	# two agree at an offset CoM — the exact case where a surviving second copy would show.
	var contract := MotorLayout.torque_from_motor("M2", thrust_n, 0.0, arm_m, com_forward)
	results.append(TestResult.new(
		"torque_from_motor re-labels thrust_torque rather than recomputing it",
		absf(float(contract["pitch"]) - at_com.x) < EPSILON
			and absf(float(contract["roll"]) + at_com.z) < EPSILON,
		"pitch %.12f vs %.12f, roll %.12f vs %.12f" % [
			contract["pitch"], at_com.x, contract["roll"], -at_com.z]
	))

	# ---------------------------------------------------------------------------
	# The refactor changed nothing while the CoM is still the origin.
	# ---------------------------------------------------------------------------
	# The reason this fix ships on its own, ahead of any mass moving: with com = 0 the new
	# reference point is the old one, so the whole 600-test suite is the regression check. This
	# line states that intent where it can be read.
	var default_arg := MotorLayout.thrust_torque("M3", thrust_n, arm_m)
	var explicit_zero := MotorLayout.thrust_torque("M3", thrust_n, arm_m, Vector3.ZERO)
	results.append(TestResult.new(
		"a com-less call is the origin-referenced answer, unchanged",
		(default_arg - explicit_zero).length() < EPSILON
			and (default_arg - MotorLayout.motor_position("M3", arm_m).cross(lift)).length() < EPSILON,
		"got %s" % default_arg
	))

	# ---------------------------------------------------------------------------
	# It reached the physics, not just the helper.
	# ---------------------------------------------------------------------------
	# DroneCore is the only consumer that integrates a torque, and it is the copy that would
	# survive a fix applied only to MotorLayout. Flown with an offset CoM, four EQUAL thrusts must
	# produce a pitching moment — the aircraft is being lifted off-centre. With the origin-
	# referenced arms it would sum to zero by symmetry and the drone would hang perfectly level,
	# which is the false-pass this asserts against.
	var core := ReferenceBuild.build_drone_core()
	core.mass_properties.com_m = Vector3(0.0, 0.0, -0.040)
	core.prime_motors(0.5)
	var throttles := {"M1": 0.5, "M2": 0.5, "M3": 0.5, "M4": 0.5}
	for i in 200:
		core.step(throttles, 1.0 / 1000.0)
	var pitch_rate: float = core.rigid_body.angular_velocity_rad_s.x
	results.append(TestResult.new(
		"DroneCore pitches under equal thrust when the CoM is off centre",
		absf(pitch_rate) > 0.01,
		"pitch rate %.4f rad/s after 0.2 s of level thrust" % pitch_rate
	))

	return results
