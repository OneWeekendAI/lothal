extends SceneTree
## Dev tool, not a test (B3/E1): measures how dark a gate's shadow on the grass is, on the real main scene, in a WINDOW.
##
##   godot --path . --script res://tests/probe_shadow_ratio.gd -- <out_dir>
##
## It looks down at the ground where gate 0's ring shadow falls (found from the sun's own direction, not guessed), renders
## the frame twice, gates casting and gates not casting, and compares the two on the pixels the shadow darkened. The ratio
## printed is mean luminance in shadow / mean luminance of the same pixels lit. A cloudless day's shadow keeps the sky's
## light; the review's bar is >= 0.35.

const W := 1280
const H := 720


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://b3"
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))
	root.size = Vector2i(W, H)
	var scene: Node = load("res://src/scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 90:
		await process_frame
	var sun := scene.get_node("DirectionalLight3D") as DirectionalLight3D
	var env := (scene.get_node("WorldEnvironment") as WorldEnvironment).environment
	if OS.get_environment("B3_SSAO") == "0":
		env.ssao_enabled = false
	if OS.get_environment("B3_AMB") != "":
		env.ambient_light_energy = float(OS.get_environment("B3_AMB"))
	if OS.get_environment("B3_SKYC") != "":
		env.ambient_light_sky_contribution = float(OS.get_environment("B3_SKYC"))
	if OS.get_environment("B3_SKYE") != "":
		(env.sky.sky_material as PhysicalSkyMaterial).energy_multiplier = float(OS.get_environment("B3_SKYE"))
	if OS.get_environment("B3_COLOR") != "":
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.5, 0.6, 0.8)
	print("[b3] ambient source %d energy %.2f sky_contribution %.2f ssao %s" % [env.ambient_light_source, env.ambient_light_energy, env.ambient_light_sky_contribution, env.ssao_enabled])
	var travel := -sun.global_transform.basis.z.normalized()
	var gate: Dictionary = scene.course_renderer.course.gates[0]
	var c: Vector3 = gate["position"]
	var ground := 0.0
	if scene.get("terrain") != null and scene.terrain != null:
		ground = scene.terrain.height_at(c.x, c.z)
	var s := c - travel * ((c.y - ground) / travel.y)
	var cam := Camera3D.new()
	cam.fov = 60.0
	scene.add_child(cam)
	cam.global_position = s + Vector3(0.0, 7.0, 0.01)
	cam.look_at(s, Vector3.UP)
	cam.make_current()
	# Hide the HUD so only the ground is measured.
	for n in scene.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var on := await _grab(60)
	on.save_png(out_dir + "/shadow_on.png")
	var casters: Array = scene.course_renderer.find_children("*", "GeometryInstance3D", true, false)
	for g in casters:
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var off := await _grab(60)
	off.save_png(out_dir + "/shadow_off.png")
	var sum_on := 0.0
	var sum_off := 0.0
	var n := 0
	var lit_sum := 0.0
	var lit_n := 0
	var ratios := PackedFloat32Array()
	for y in range(0, H, 2):
		for x in range(0, W, 2):
			var a := on.get_pixel(x, y).get_luminance()
			var b := off.get_pixel(x, y).get_luminance()
			if b > 0.02 and a < 0.8 * b:
				sum_on += a
				ratios.append(a / b)
				sum_off += b
				n += 1
			else:
				lit_sum += b
				lit_n += 1
	var ratio := sum_on / maxf(sum_off, 1e-6)
	ratios.sort()
	# The core of the shadow, not its soft edge: the darkest tenth of the shadowed pixels.
	var core := ratios[int(ratios.size() * 0.05)] if ratios.size() > 0 else 1.0
	print("[b3] shadow core ratio (5th percentile of shadow/lit per pixel) %.3f" % core)
	print("[b3] shadow pixels %d, shadow/lit ratio %.3f (shadow mean %.3f, same pixels lit %.3f, frame lit mean %.3f)" % [
		n, ratio, sum_on / maxf(n, 1), sum_off / maxf(n, 1), lit_sum / maxf(lit_n, 1)])
	quit()


func _grab(settle: int) -> Image:
	for i in settle:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
