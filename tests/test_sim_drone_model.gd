class_name TestSimDroneModel
extends RefCounted
## The field flies the Design Space's own drone model (assets/models/classes/<class>.glb), re-fitted to
## the Build by SwapLook, not the generated sticks-and-discs AirframeModel it used to draw.
##
## What is checked, in the order the owner would look:
##   - the node the sim moves IS the Design Space model: it holds the GLB's own meshes (frame plates,
##     bevelled screws, wiring) and holds no AirframeModel;
##   - its parts match the Build: motors on the arm tips MotorLayout puts them on, a pack that grows
##     with a bigger catalog pack, a camera that disappears when the build has none, the centre of
##     mass at the body origin;
##   - the props turn at the observable rpm with MotorLayout.SPIN's direction, and give way to a
##     swept disc where blades would alias;
##   - the FPV lens is the camera's own, tipped up by the saved tilt.

static func run(tree: SceneTree) -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var session := DesignSession.default_for_class("five_inch")
	var build := session.build(catalog)

	var sim: Node = load("res://src/scenes/main.tscn").instantiate()
	sim.initial_build = build
	sim.initial_drone_class = "five_inch"
	tree.root.add_child(sim)
	await tree.process_frame

	var model := sim.drone.get_node_or_null("SimDroneModel") as SimDroneModel
	results.append(TestResult.new("the sim's drone node holds a SimDroneModel (the Design Space model)",
		model != null and model.content != null, str(model)))
	if model == null or model.content == null:
		sim.queue_free()
		return results
	results.append(TestResult.new("it is the five_inch GLB: its own frame plates, screws and wiring are there",
		model.class_id == "five_inch" and model.content.find_child("frame_plate_top", true, false) != null
		and model.content.find_child("frame_screw_top_1", true, false) != null
		and model.content.find_child("wires", true, false) != null,
		model.class_id))
	results.append(TestResult.new("no generated AirframeModel is drawn beside it",
		sim.drone.find_children("*", "AirframeModel", true, false).is_empty(), ""))
	results.append(TestResult.new("no picking proxy mesh survives into the field",
		model.content.find_children("pick_*", "MeshInstance3D", true, false).is_empty(), ""))

	# Parts match the Build.
	var problems: Array[String] = []
	var half := build.arm_m / sqrt(2.0)
	for corner in ["FL", "FR", "BL", "BR"]:
		var m := model.part_nodes.get("motor_" + corner) as MeshInstance3D
		var p := model.part_nodes.get("prop_" + corner) as MeshInstance3D
		if m == null or p == null or not m.visible or not p.visible:
			problems.append("%s motor/prop missing" % corner)
			continue
		if absf(absf(m.position.x) - half) > 0.001 or absf(absf(m.position.z) - half) > 0.001:
			problems.append("%s motor at %s, arm tip is %.4f" % [corner, m.position, half])
		if absf(p.position.x - m.position.x) > 1e-4 or p.position.y <= m.position.y:
			problems.append("%s prop not on its motor shaft" % corner)
	results.append(TestResult.new("four motors on the arm tips of this Build, each with its prop above it",
		problems.is_empty(), "; ".join(problems)))
	results.append(TestResult.new("the body origin is the Build's centre of mass (model shifted by -com)",
		model.content.position.is_equal_approx(-build.mass_properties.com_m) and model.com_m.y > 0.005,
		"%s vs com %s" % [model.content.position, build.mass_properties.com_m]))
	var battery := model.part_nodes["battery"] as MeshInstance3D
	var seat: Vector3 = build.battery_seat()["position"]
	var centre_y := (battery.transform * battery.mesh.get_aabb().get_center()).y
	results.append(TestResult.new("the pack sits where Build weighs it (centre height within 4 mm of battery_seat)",
		absf(centre_y - seat.y) < 0.004, "drawn %.4f vs seat %.4f" % [centre_y, seat.y]))

	# A swapped pack is the catalog's size, a removed camera is gone.
	var bigger := ""
	var big_session := DesignSession.default_for_class("five_inch")
	for opt in catalog.list_category("battery"):
		var bid := String(opt["part_id"])
		if bid != String(big_session.selection["battery"]) and big_session.swap(catalog, "battery", bid)["ok"]:
			var cand := big_session.build(catalog)
			if Build.battery_size_of(cand.battery).x * Build.battery_size_of(cand.battery).z > 1.15 * Build.battery_size_of(build.battery).x * Build.battery_size_of(build.battery).z:
				bigger = bid
				break
			big_session = DesignSession.default_for_class("five_inch")
	if bigger != "":
		var swapped := SimDroneModel.new()
		swapped.rebuild(big_session.build(catalog), "five_inch", catalog)
		var a := (model.part_nodes["battery"] as MeshInstance3D).transform.basis.get_scale()
		var b := (swapped.part_nodes["battery"] as MeshInstance3D).transform.basis.get_scale()
		results.append(TestResult.new("a bigger catalog pack is drawn bigger (SwapLook ratio), not the seed pack",
			not a.is_equal_approx(b), "%s -> %s" % [a, b]))
		swapped.free()
	else:
		results.append(TestResult.new("catalog has a larger pack to swap in", false, "none found"))
	var cam_session := DesignSession.default_for_class("five_inch")
	cam_session.remove("camera")
	var no_cam := SimDroneModel.new()
	no_cam.rebuild(cam_session.build(catalog), "five_inch", catalog)
	results.append(TestResult.new("a build with no camera draws no camera and offers no lens",
		not (no_cam.part_nodes["camera"] as MeshInstance3D).visible and no_cam.camera_eye() == null, ""))
	no_cam.free()

	# Props.
	var rpm := PackedFloat32Array([1000.0, 2000.0, 3000.0, 4000.0])
	model.set_rates_rpm(rpm)
	var dt := 0.001
	model.advance(dt)
	var prop_problems: Array[String] = []
	for i in 4:
		var n: String = MotorLayout.MOTOR_NAMES[i]
		var want: float = rpm[i] / 60.0 * TAU * MotorLayout.SPIN[n] * dt
		var got := model.prop_angle(n)
		got = got if got < PI else got - TAU
		if absf(got - want) > 1e-4:
			prop_problems.append("%s turned %.5f, wanted %.5f" % [n, got, want])
	results.append(TestResult.new("each prop turns at its own motor's rpm, in MotorLayout.SPIN's direction",
		prop_problems.is_empty(), "; ".join(prop_problems)))
	model.set_rates_rpm(PackedFloat32Array([200.0, 200.0, 200.0, 28000.0]))
	results.append(TestResult.new("a slow rotor shows blades; a 28,000 rpm rotor shows the swept disc",
		not model.is_blurred("M1") and model.is_blurred("M4"), ""))
	model.set_rates_rpm(PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))

	# The lens.
	var eye := model.camera_eye()
	results.append(TestResult.new("the FPV lens is on the model and tipped up by the saved tilt (25 deg default)",
		eye != null and absf(rad_to_deg(atan2((eye.basis * Vector3(0, 0, -1)).y, -(eye.basis * Vector3(0, 0, -1)).z)) - 25.0) < 0.01
		and sim.fpv_view.is_fitted(),
		str(eye)))

	# Every class that has a model builds from its own seed.
	for id in DroneClass.ids():
		if not ResourceLoader.exists(DroneClass.model_path(id)):
			continue
		var seed_session := DesignSession.default_for_class(id)
		var seed_build := seed_session.build(catalog) if seed_session != null else null
		if seed_build == null:
			continue
		var m := SimDroneModel.new()
		m.rebuild(seed_build, id, catalog)
		var motors := 0
		for key in m.part_nodes:
			if String(key).begins_with("motor_") and (m.part_nodes[key] as MeshInstance3D).visible:
				motors += 1
		results.append(TestResult.new("%s: its seed build draws %d motors and %d spinning props" % [id, motors, m.prop_nodes.size()],
			m.prop_nodes.size() == 4 and motors >= 4, "%d props" % m.prop_nodes.size()))
		m.free()

	# A coaxial lower rotor blurs with its upper one (it shares the corner's rate, turning the other way).
	var coax_session := DesignSession.default_for_class("cinelifter")
	var coax := SimDroneModel.new()
	coax.rebuild(coax_session.build(catalog), "cinelifter", catalog)
	coax.set_rates_rpm(PackedFloat32Array([9000.0, 9000.0, 9000.0, 9000.0]))
	var lower := coax.part_nodes.get("prop_FL_lo") as MeshInstance3D
	var lower_disc := lower.get_node_or_null("BlurDisc") as MeshInstance3D if lower != null else null
	results.append(TestResult.new("cinelifter: the coaxial lower rotor shows a swept disc at speed too",
		lower_disc != null and lower_disc.visible, str(lower_disc)))
	coax.advance(0.001)
	results.append(TestResult.new("cinelifter: the lower rotor turns, and the opposite way to the upper",
		lower != null and absf(lower.basis.get_euler().y - coax.part_nodes["prop_FL"].basis.get_euler().y) > 1e-4, ""))
	coax.free()

	sim.queue_free()
	await tree.process_frame
	return results
