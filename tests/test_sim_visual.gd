class_name TestSimVisual
extends RefCounted
## What the field draws between the 120 Hz physics ticks, and what it kicks up.
##
##   - The drawn aircraft is the BLEND of the last two physics poses at the engine's interpolation
##     fraction, set in _process; a physics tick records poses and never sets the drawn transform
##     (so a 144 Hz display sees 144 distinct poses, not 120 repeated ones).
##   - A teleport (respawn, restart) blends nothing across the jump.
##   - The chase camera's ease is frame-rate independent: the same wall time gives the same distance
##     closed at 30 or 120 frames per second.
##   - Rotor wash is a function of the thrust and the height: nothing high up, more when low, more
##     with more thrust, and it is the momentum-theory induced velocity that sets the scale.

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

	# Pure blend.
	var a := Transform3D(Basis(Quaternion(Vector3.UP, 0.0)), Vector3(0, 1, 0))
	var b := Transform3D(Basis(Quaternion(Vector3.UP, 1.0)), Vector3(2, 1, 4))
	var mid: Transform3D = sim.interpolated_pose(a, b, 0.5)
	results.append(TestResult.new("the blend at 0.5 is the midpoint position and half the rotation",
		mid.origin.is_equal_approx(Vector3(1, 1, 2))
		and absf(mid.basis.get_rotation_quaternion().get_angle() - 0.5) < 1e-4, str(mid)))
	results.append(TestResult.new("the blend at 0 and 1 are the two physics poses exactly",
		sim.interpolated_pose(a, b, 0.0).origin.is_equal_approx(a.origin)
		and sim.interpolated_pose(a, b, 1.0).origin.is_equal_approx(b.origin), ""))

	# A tick records, _process draws.
	var p0 := Vector3(5, 3, -5)
	var p1 := Vector3(5.1, 3.0, -5.2)
	sim._snap_visual(p0, Quaternion.IDENTITY)
	sim._push_visual(p1, Quaternion.IDENTITY)
	results.append(TestResult.new("a physics tick does not move the drawn drone (only _process does)",
		sim.drone.position.is_equal_approx(p0), str(sim.drone.position)))
	sim.core.rigid_body.position_m = p1   # keep the camera's target sane
	sim.interpolation_fraction_override = 0.25
	sim._process(1.0 / 144.0)
	sim.interpolation_fraction_override = -1.0
	var d: Vector3 = sim.drone.position
	var along := (d - p0).dot(p1 - p0) / (p1 - p0).length_squared()
	var off_line := ((d - p0) - (p1 - p0) * along).length()
	results.append(TestResult.new("_process draws the pose a quarter of the way between the two ticks (not the latest tick)",
		d.is_equal_approx(p0 + (p1 - p0) * 0.25), str(d)))
	results.append(TestResult.new("after _process the drawn drone lies on the segment between the last two physics poses",
		along >= -1e-6 and along <= 1.0 + 1e-6 and off_line < 1e-5, "t %.3f off %.2e" % [along, off_line]))
	var fractions := {}
	for f in [0.1, 0.5, 0.9]:
		fractions[f] = sim.interpolated_pose(sim._vis_prev, sim._vis_curr, f).origin.x
	results.append(TestResult.new("three render frames between two ticks draw three distinct poses",
		fractions[0.1] < fractions[0.5] and fractions[0.5] < fractions[0.9], str(fractions)))
	sim._snap_visual(Vector3(50, 3, 50), Quaternion.IDENTITY)
	results.append(TestResult.new("a teleport snaps both poses: nothing is blended across the jump",
		sim._vis_prev.origin.is_equal_approx(sim._vis_curr.origin) and sim.drone.position.is_equal_approx(Vector3(50, 3, 50)), ""))

	# Camera ease independent of frame rate.
	var remaining := []
	for steps in [30, 60, 240]:
		sim._snap_visual(Vector3(0, 5, 0), Quaternion.IDENTITY)
		sim._cam_yaw = 0.0
		sim._chase_transform.origin = Vector3(10, 5, 10)
		for i in steps:
			sim._update_camera(1.0 / steps)
		var target: Vector3 = Vector3(0, 5, 0) + Vector3(0, 0, 1) * 0.0 + sim.CAMERA_OFFSET * sim._camera_scale
		remaining.append((sim._chase_transform.origin - target).length())
	results.append(TestResult.new("the chase camera closes the same distance in one second at 30, 60 and 240 fps",
		absf(remaining[0] - remaining[1]) < 0.002 and absf(remaining[1] - remaining[2]) < 0.002, str(remaining)))
	sim.queue_free()
	await tree.process_frame

	# Rotor wash.
	var rho := 1.225
	var area := 4.0 * PI * 0.0635 * 0.0635
	var hover_thrust := 7.0
	var high := PropWash.intensity(3.0, hover_thrust, area, rho, 0.127)
	var low := PropWash.intensity(0.15, hover_thrust, area, rho, 0.127)
	var low_weak := PropWash.intensity(0.15, 0.5, area, rho, 0.127)
	results.append(TestResult.new("rotor wash: none at 3 m, strong at 15 cm, weak when the thrust is weak",
		high == 0.0 and low > 0.5 and low_weak < low, "3 m %.2f, 0.15 m %.2f, weak %.2f" % [high, low, low_weak]))
	results.append(TestResult.new("rotor wash grows monotonically as the aircraft comes down",
		PropWash.intensity(0.2, hover_thrust, area, rho, 0.127) >= PropWash.intensity(0.6, hover_thrust, area, rho, 0.127)
		and PropWash.intensity(0.6, hover_thrust, area, rho, 0.127) >= PropWash.intensity(1.2, hover_thrust, area, rho, 0.127), ""))
	results.append(TestResult.new("rotor wash is zero with no thrust and no disc",
		PropWash.intensity(0.1, 0.0, area, rho, 0.127) == 0.0 and PropWash.intensity(0.1, 5.0, 0.0, rho, 0.127) == 0.0, ""))
	return results
