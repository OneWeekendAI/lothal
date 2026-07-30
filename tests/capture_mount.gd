extends SceneTree
## Dev tool, not a test: shoots a CLOSE-UP of one motor-and-propeller mount, framed on the
## bell-to-blade gap, and writes a PNG.
##
##   godot --script res://tests/capture_mount.gd -- <out.png> [motor_id] [prop_id]
##                                                  [elevation_deg] [spacer_mm] [pad_mm] [rpm]
##                                                  [settle_frames]
##
## Lab's own camera is deliberately fixed at a distance chosen by the largest frame in the
## catalog and deliberately cannot zoom (lab_screen.gd), which is right for comparing airframes
## and useless for judging a 2 mm clearance: on a 1152 px capture of the reference build, the
## whole motor is about eight pixels tall. capture_lab.gd therefore cannot photograph the one
## thing the mounting slice is about, and "the last several bugs on this project were found by
## looking at the images" is only true if the images show the thing.
##
## So this builds one motor and one prop on their own, with a camera framed on the assembly. It
## deliberately does NOT go through Lab: nothing here is asserting how Lab looks, only what the
## generated hardware looks like at a distance a builder's eye would be at.
##
## Note that it runs WITHOUT --headless. Godot's dummy renderer has no framebuffer to read back,
## so any capture script needs a real window (same as capture_frame.gd).

const VIEWPORT := Vector2i(1000, 700)

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://mount.png"
	var motor_id: String = args[1] if args.size() > 1 else ReferenceBuild.MOTOR_ID
	var prop_id: String = args[2] if args.size() > 2 else ReferenceBuild.PROPELLER_ID
	var elevation_deg: float = float(args[3]) if args.size() > 3 else 6.0
	var spacer_mm: float = float(args[4]) if args.size() > 4 else 0.0
	var pad_mm: float = float(args[5]) if args.size() > 5 else 0.0
	# A rate to turn at, exactly as Lab or Sim would hand one in — which is also how the blur disc
	# gets photographed, since it is what a rate above the aliasing threshold draws.
	var rpm: float = float(args[6]) if args.size() > 6 else 0.0
	var settle: int = int(args[7]) if args.size() > 7 else 8

	var catalog := PartsCatalog.load_default()
	var motor_part: Dictionary = catalog.get_part(motor_id)
	var prop_part: Dictionary = catalog.get_part(prop_id)
	if motor_part.is_empty() or prop_part.is_empty():
		print("no such motor/prop: %s / %s" % [motor_id, prop_id])
		quit(1)
		return

	# `root` IS the window here, and it is the framebuffer that gets read back at the end.
	DisplayServer.window_set_size(VIEWPORT)
	root.size = VIEWPORT

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.57, 0.66)
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = env
	root.add_child(world_environment)

	var propeller := PropellerMesh.new()
	propeller.rebuild(prop_part)
	var motor := MotorMesh.new()
	motor.rebuild(motor_part, propeller.stack_height_m, spacer_mm / 1000.0, pad_mm / 1000.0)
	propeller.position = Vector3(0, motor.prop_mount_height_m + propeller.underside_m, 0)
	propeller.spin = MotorLayout.SPIN["M1"]
	propeller.set_rate_rpm(rpm)
	motor.add_child(propeller)
	root.add_child(motor)

	# Framed on the motor's own height, so a 0802 and a 2807 both fill the frame and the gap is
	# judged at the same apparent size on each. Aiming at the bell-to-blade join rather than at
	# the middle of the assembly is the whole point of the shot.
	var focus := Vector3(0, motor.prop_mount_height_m, 0)
	var camera := Camera3D.new()
	# ORTHOGONAL, deliberately. This shot exists to judge a 2 mm axial gap, and under perspective
	# at the distance needed to fill the frame with a 10 mm motor, the blade nearest the camera is
	# at half the focal distance and projects across the bell — which reads exactly like the
	# interference bug being looked for. An elevation view is what a fit check is drawn as.
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = motor.total_height_m * 2.6
	camera.near = 0.0005
	camera.far = 2.0
	camera.position = focus + Vector3(0, 0, maxf(propeller.radius_m, motor.total_height_m) * 3.0
		).rotated(Vector3.RIGHT, -deg_to_rad(elevation_deg))
	root.add_child(camera)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-28.0, -22.0, 0.0)
	key_light.light_energy = 1.5
	root.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-6.0, 145.0, 0.0)
	fill_light.light_energy = 0.45
	root.add_child(fill_light)

	# Aimed after a frame has passed, not on the way in. In a SceneTree script, `root` is not itself
	# inside the tree during _init, so a child added here is not either — and look_at on a node
	# outside the tree does nothing except push an error, leaving the camera pointed down its own -Z.
	# That frames the assembly by accident from a low angle and misses it entirely from a high one,
	# so the symptom is a blank PNG at some elevations and a correct one at others.
	await process_frame
	camera.look_at(focus, Vector3.UP)

	for i in settle:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d) — %s on %s, seat %.4f m, stack %.4f m, %.0f RPM, blades drawn: %s, blur: %s, angle %.3f rad" % [
		out_path, image.get_width(), image.get_height(), motor_id, prop_id,
		motor.prop_mount_height_m, propeller.stack_height_m, rpm,
		propeller.blades_drawn(), propeller.blur_drawn(), propeller.rotation.y])
	quit()
