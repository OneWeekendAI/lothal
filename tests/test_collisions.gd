class_name TestCollisions
extends RefCounted
## R1.1: real collision. The ground, the obstacles and the gate rings stop the aircraft, a soft hit bounces,
## a hard hit damages the prop that touched and cuts ITS thrust, and a harder one crashes it.
##
## Every number asserted is derived from `CollisionConstants` (each an estimate there), so retuning a
## threshold moves these checks with it instead of silently decoupling them. Each check was proven to fail
## with its logic reverted — see the R1.1 entry in REALISM_TRACKER.md.

const DT := 0.001


static func run() -> Array:
	var results: Array = []
	results.append_array(_ground_bounce())
	results.append_array(_obstacle_hit())
	results.append_array(_gate_ring())
	results.append_array(_prop_damage_cuts_thrust())
	results.append_array(_high_speed_crash())
	return results


static func _core(world: CollisionWorld) -> DroneCore:
	var core: DroneCore = ReferenceBuild.build_drone_core()
	core.collision_world = world
	core.rigid_body.orientation = Quaternion.IDENTITY
	return core


static func _run_steps(core: DroneCore, steps: int) -> void:
	for _i in steps:
		core.step({}, DT)


## A level aircraft dropped from 0.2 m lands on its body at ~1.8 m/s: under the bounce threshold, so it
## rebounds at RESTITUTION times the impact speed, with no damage and no crash.
static func _ground_bounce() -> Array:
	var results: Array = []
	var core := _core(CollisionWorld.new(null))
	core.rigid_body.position_m = Vector3(0, 0.2, 0)
	var rebound := 0.0
	var landed := false
	for _i in 600:
		core.step({}, DT)
		if core.last_impact_speed_mps > 0.0:
			landed = true
		if landed and core.rigid_body.velocity_mps.y > 0.0:
			rebound = maxf(rebound, core.rigid_body.velocity_mps.y)
	var impact := core.peak_impact_speed_mps
	results.append(TestResult.new("ground bounce: lands below the bounce threshold",
		impact > CollisionConstants.REST_SPEED_MPS and impact < CollisionConstants.BOUNCE_SPEED_MPS,
		"impact %.3f m/s, bounce threshold %.1f" % [impact, CollisionConstants.BOUNCE_SPEED_MPS]))
	results.append(TestResult.new("ground bounce: rebounds at restitution x impact speed",
		absf(rebound - CollisionConstants.RESTITUTION * impact) < 0.1 * impact,
		"rebound %.3f m/s, expected %.3f" % [rebound, CollisionConstants.RESTITUTION * impact]))
	results.append(TestResult.new("ground bounce: no damage and no crash",
		not core.crashed and core.prop_damage == PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		"crashed %s damage %s" % [core.crashed, core.prop_damage]))
	results.append(TestResult.new("ground bounce: the ground holds it (never below the surface)",
		core.rigid_body.position_m.y >= CollisionConstants.BODY_RADIUS_M - 1.0e-6,
		"y %.4f m" % core.rigid_body.position_m.y))

	# Friction: sliding along the ground at 1 m/s loses horizontal speed to the ground, not just to drag.
	var slider := _core(CollisionWorld.new(null))
	slider.rigid_body.position_m = Vector3(0, 0.2, 0)
	slider.rigid_body.velocity_mps = Vector3(1.0, 0, 0)
	var frictionless: DroneCore = _core(null)
	frictionless.rigid_body.position_m = Vector3(0, 0.2, 0)
	frictionless.rigid_body.velocity_mps = Vector3(1.0, 0, 0)
	_run_steps(slider, 400)
	_run_steps(frictionless, 400)
	results.append(TestResult.new("ground friction: a landing slide loses horizontal speed",
		slider.rigid_body.velocity_mps.x < frictionless.rigid_body.velocity_mps.x - 0.05,
		"with ground %.3f m/s, free fall %.3f m/s" % [slider.rigid_body.velocity_mps.x, frictionless.rigid_body.velocity_mps.x]))
	return results


static func _pole() -> Obstacle:
	return Obstacle.place(Obstacle.POLE, 1.0, 0.0, {"radius": 0.1, "height": 10.0}, null)


## Flown at a pole at 3 m/s the aircraft is stopped by it (and without the world it flies straight through).
## The fast side of the aircraft takes the damage.
static func _obstacle_hit() -> Array:
	var results: Array = []
	var pole := _pole()
	var obstacles: Array[Obstacle] = [pole]
	var core := _core(CollisionWorld.new(null, obstacles))
	var ghost: DroneCore = _core(null)
	for c in [core, ghost]:
		c.rigid_body.position_m = Vector3(0, 5.0, 0)
		c.rigid_body.velocity_mps = Vector3(3.0, 0, 0)
	var max_x := -INF
	for _i in 600:
		core.step({}, DT)
		ghost.step({}, DT)
		max_x = maxf(max_x, core.rigid_body.position_m.x)
	var face_x := pole.position.x - 0.1
	results.append(TestResult.new("obstacle hit: the aircraft does not pass through the pole",
		max_x < face_x + 0.02, "max x %.3f m, pole face %.3f m" % [max_x, face_x]))
	results.append(TestResult.new("obstacle hit: the same flight with no world does pass it",
		ghost.rigid_body.position_m.x > pole.position.x + 0.1, "ghost x %.3f m" % ghost.rigid_body.position_m.x))
	results.append(TestResult.new("obstacle hit: it is thrown back, not stuck on the pole",
		core.rigid_body.velocity_mps.x < 0.0, "vx %.3f m/s" % core.rigid_body.velocity_mps.x))
	results.append(TestResult.new("obstacle hit: the impact normal speed is recorded",
		core.peak_impact_speed_mps > 2.9, "peak %.3f m/s" % core.peak_impact_speed_mps))
	return results


## A ring's tube is solid, its aperture is not.
static func _gate_ring() -> Array:
	var results: Array = []
	var gate := GateCourse.make_gate(Vector3(2.0, 5.0, 0.0), 0.0, 1.5)   # heading 0: normal (0, 0, -1)
	var gates: Array[Dictionary] = [gate]
	var through := _core(CollisionWorld.new(null, [] as Array[Obstacle], gates))
	through.rigid_body.position_m = Vector3(2.0, 5.0, 0.6)
	through.rigid_body.velocity_mps = Vector3(0, 0, -3.0)
	var ring := _core(CollisionWorld.new(null, [] as Array[Obstacle], gates))
	ring.rigid_body.position_m = Vector3(2.0 + 1.5 + CollisionConstants.GATE_TUBE_RADIUS_M, 5.0, 0.6)
	ring.rigid_body.velocity_mps = Vector3(0, 0, -3.0)
	var ring_min_z := INF
	for _i in 600:
		through.step({}, DT)
		ring.step({}, DT)
		ring_min_z = minf(ring_min_z, ring.rigid_body.position_m.z)
	results.append(TestResult.new("gate ring: flying through the aperture touches nothing",
		through.peak_impact_speed_mps == 0.0 and through.rigid_body.position_m.z < -1.0,
		"peak %.3f, z %.3f" % [through.peak_impact_speed_mps, through.rigid_body.position_m.z]))
	results.append(TestResult.new("gate ring: flying into the ring itself is stopped",
		ring_min_z > -0.2 and ring.peak_impact_speed_mps > 1.0,
		"min z %.3f, peak %.3f m/s" % [ring_min_z, ring.peak_impact_speed_mps]))
	return results


## A prop-tip hit between the two thresholds damages the motors on the side that hit, and a damaged motor
## gives less thrust than the same motor undamaged at the same command.
static func _prop_damage_cuts_thrust() -> Array:
	var results: Array = []
	var obstacles: Array[Obstacle] = [_pole()]
	var core := _core(CollisionWorld.new(null, obstacles))
	core.rigid_body.position_m = Vector3(0, 5.0, 0)
	var speed := 0.5 * (CollisionConstants.BOUNCE_SPEED_MPS + CollisionConstants.CRASH_SPEED_MPS)
	core.rigid_body.velocity_mps = Vector3(speed, 0, 0)
	_run_steps(core, 400)
	# +x is the M1/M2 side (MotorLayout.motor_position), M3/M4 are the far side.
	var near := maxf(core.prop_damage[0], core.prop_damage[1])
	var far := maxf(core.prop_damage[2], core.prop_damage[3])
	results.append(TestResult.new("prop damage: a mid-speed hit damages the props that touched, not the far ones",
		near > 0.0 and far == 0.0 and not core.crashed,
		"near %.3f far %.3f crashed %s" % [near, far, core.crashed]))

	var sound: DroneCore = ReferenceBuild.build_drone_core()
	var hurt: DroneCore = ReferenceBuild.build_drone_core()
	hurt.prop_damage = PackedFloat64Array([0.5, 0.0, 0.0, 0.0])
	var cmds := {"M1": 0.5, "M2": 0.5, "M3": 0.5, "M4": 0.5}
	for _i in 100:
		sound.step(cmds, DT)
		hurt.step(cmds, DT)
	var obs_thrust: float = sound.powertrain.observables.thrust_n[0]
	# Same command, same rpm (the powertrain is undamaged); only the delivered thrust differs: the damaged
	# craft accelerates upward less and rolls toward the damaged corner's side.
	results.append(TestResult.new("prop damage: the damaged motor's thrust is cut (less lift, same command)",
		hurt.rigid_body.velocity_mps.y < sound.rigid_body.velocity_mps.y - 1.0e-3,
		"vy sound %.4f hurt %.4f (thrust0 %.3f N)" % [sound.rigid_body.velocity_mps.y, hurt.rigid_body.velocity_mps.y, obs_thrust]))
	results.append(TestResult.new("prop damage: and unbalances the airframe (torque from the weak corner)",
		hurt.rigid_body.angular_velocity_rad_s.length() > sound.rigid_body.angular_velocity_rad_s.length() + 1.0e-3,
		"|w| sound %.4f hurt %.4f" % [sound.rigid_body.angular_velocity_rad_s.length(), hurt.rigid_body.angular_velocity_rad_s.length()]))
	return results


## Past the hard threshold the hit crashes the aircraft; just under it, it does not.
static func _high_speed_crash() -> Array:
	var results: Array = []
	var fast := _core(CollisionWorld.new(null))
	fast.rigid_body.position_m = Vector3(0, 0.1, 0)
	fast.rigid_body.velocity_mps = Vector3(0, -(CollisionConstants.CRASH_SPEED_MPS + 2.0), 0)
	_run_steps(fast, 50)
	var slow := _core(CollisionWorld.new(null))
	slow.rigid_body.position_m = Vector3(0, 0.1, 0)
	slow.rigid_body.velocity_mps = Vector3(0, -(CollisionConstants.CRASH_SPEED_MPS - 2.0), 0)
	_run_steps(slow, 50)
	results.append(TestResult.new("crash: a ground hit past the crash speed crashes the aircraft",
		fast.crashed, "impact %.2f m/s" % fast.peak_impact_speed_mps))
	results.append(TestResult.new("crash: a hit just under it damages but does not crash",
		not slow.crashed and slow.peak_impact_speed_mps >= CollisionConstants.BOUNCE_SPEED_MPS,
		"impact %.2f m/s, crashed %s" % [slow.peak_impact_speed_mps, slow.crashed]))
	fast.repair()
	results.append(TestResult.new("crash: repair() clears the crash and the damage",
		not fast.crashed and fast.prop_damage[0] == 0.0, "crashed %s" % fast.crashed))
	return results
