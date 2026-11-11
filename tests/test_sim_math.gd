class_name TestSimMath
extends RefCounted
## Physics the interactive sim switches on that headless harness runs leave off (FREE),
## each with a source and a case that fails without it:
##
##   GROUND EFFECT (Cheeseman and Bennett, the image-vortex result in DroneCore.ground_effect_gain).
##     The core is built with it on, and the ground it feels is the TERRAIN under the aircraft (a hill
##     is ground), refreshed every physics tick, not the y = 0 plane. With it, the same throttle at 6 cm
##     above the ground gives a higher climb rate than at 5 m; the effect is absent above two radii.
##   REAR-ROTOR INTERFERENCE AS A THRUST LOSS (SR1.5; Aerospace 8(11):349, 2021: 11 percent at 5-15 m/s).
##     In free flight the rear pair makes 0.89 of the front pair's thrust at equal rpm at 11.5 m/s, and
##     exactly 1.0 in hover. A core built WITHOUT the key (every harness, mission and golden) keeps the
##     old mean power factor: ratio 1.0. That second assertion is what proves no golden moved.
##
## Every old -> new figure is in the result detail, so a reader sees what the change did.

## The sim's own option set, read from the script so the test cannot drift from what the scene flies.
static var FREE: Dictionary = load("res://src/scenes/main.gd").FREE_FLIGHT_PHYSICS

static func run(tree: SceneTree) -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var build := DesignSession.default_for_class("five_inch").build(catalog)

	var sim: Node = load("res://src/scenes/main.tscn").instantiate()
	sim.initial_build = build
	sim.initial_drone_class = "five_inch"
	tree.root.add_child(sim)
	await tree.process_frame
	await tree.process_frame

	results.append(TestResult.new("the sim's core flies with ground effect and the rear-thrust loss switched on",
		sim.core.ground_effect_enabled and float(sim.core.powertrain.rear_thrust_loss) > 0.0,
		"ge %s" % sim.core.ground_effect_enabled))

	# The ground is the terrain under the aircraft.
	sim.terrain = Terrain.shaped(Terrain.SLOPE, 400.0, 400.0, {"rise_m": 20.0, "direction_deg": 0.0})
	var at := Vector3(40.0, 16.0, 0.0)
	sim.core.rigid_body.position_m = at
	sim.core.rigid_body.velocity_mps = Vector3.ZERO
	sim.core.prime_motors(sim._hover_throttle)
	var want: float = sim.terrain.height_at(at.x, at.z)
	sim._physics_process(1.0 / 120.0)
	results.append(TestResult.new("the ground the rotors feel is the terrain height under the aircraft, not y = 0",
		want > 1.0 and absf(sim.core.ground_y_m - want) < 0.05, "terrain %.2f m, core ground %.2f m" % [want, sim.core.ground_y_m]))
	sim.queue_free()
	await tree.process_frame

	# Ground effect numbers: same throttle, two heights.
	var low := _climb_rate(build, 0.06)
	var high := _climb_rate(build, 5.0)
	results.append(TestResult.new("same throttle: 6 cm over the ground climbs faster than 5 m up (old: equal)",
		low > high + 0.01, "6 cm %.3f m/s over 0.1 s, 5 m %.3f m/s" % [low, high]))
	var plain_low := _climb_rate(build, 0.06, {})
	results.append(TestResult.new("the headless default (no key) has no ground effect: 6 cm equals 5 m",
		absf(plain_low - _climb_rate(build, 5.0, {})) < 1e-6, "%.5f" % plain_low))

	# Rear loss.
	var fwd := _thrusts_at(build, 11.5, FREE)
	var hov := _thrusts_at(build, 0.0, FREE)
	var old := _thrusts_at(build, 11.5, {})
	results.append(TestResult.new("free flight, 11.5 m/s, equal rpm: rear pair at 0.89 of the front pair (old: 1.000)",
		absf(fwd[0] / fwd[1] - 0.89) < 0.006 and absf(fwd[2] / fwd[3] - 0.89) < 0.006,
		"new %.4f, old %.4f" % [fwd[0] / fwd[1], old[0] / old[1]]))
	results.append(TestResult.new("free flight in hover: no rear loss (ratio 1.0)", absf(hov[0] / hov[1] - 1.0) < 0.001,
		"%.4f" % (hov[0] / hov[1])))
	results.append(TestResult.new("a core built without the key keeps the old model, so no golden moves (ratio 1.0)",
		absf(old[0] / old[1] - 1.0) < 0.001, "%.4f" % (old[0] / old[1])))
	return results


## Vertical velocity gained in 0.1 s at hover throttle from rest, `y` above the ground plane.
static func _climb_rate(build: Build, y: float, opts: Dictionary = {"ground_effect": true, "rear_thrust_loss": true}) -> float:
	var core := build.build_drone_core(opts)
	core.rigid_body.position_m = Vector3(0, y, 0)
	core.prime_motors(build.hover_throttle_for(core.powertrain.battery))
	core.rigid_body.velocity_mps = Vector3.ZERO
	var cmds := {}
	for n in MotorLayout.MOTOR_NAMES:
		cmds[n] = build.hover_throttle_for(core.powertrain.battery)
	for i in 100:
		core.rigid_body.position_m = Vector3(0, y, 0)
		core.step(cmds, 0.001)
	return core.rigid_body.velocity_mps.y


static func _thrusts_at(build: Build, v_forward: float, opts: Dictionary) -> PackedFloat32Array:
	var opts2 := opts.duplicate()
	opts2["off"] = true
	var core := build.build_drone_core(opts2)
	if opts.get("rear_thrust_loss", false):
		# "off" skips apply_field_physics only; the loss form is chosen in build_drone_core itself.
		pass
	for i in 400:
		core.rigid_body.position_m = Vector3(0, 50, 0)
		core.rigid_body.velocity_mps = Vector3(0, 0, -v_forward)
		# Held level: the unequal thrust pitches the aircraft, and a tumbling body turns "forward" around.
		core.rigid_body.orientation = Quaternion.IDENTITY
		core.rigid_body.angular_velocity_rad_s = Vector3.ZERO
		core.step({"M1": 0.5, "M2": 0.5, "M3": 0.5, "M4": 0.5}, 0.001)
	return core.powertrain.observables.thrust_n
