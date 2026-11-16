class_name TestFpvLens
extends RefCounted
## R2.2: the FPV lens. The feed is a rectilinear render remapped by a distortion shader (FpvLens); these tests hold the
## claims that would otherwise be silently wrong.
##
##   1. The projected FOV equals the part's FOV: a ray at hfov/2 off the axis, projected by the ENGINE's own perspective
##      projection of the source camera FpvView configures, lands where the shader's mapping reads for the horizontal
##      picture edge. Written from an independent forward lens model (ray angle -> output radius), not from ray_tan.
##   2. The CPU mirror of the shader formula matches that forward model at sampled radii, for both lens models.
##   3. Changing the camera part changes the FOV and the distortion that reach the shader.
##   4. A part with no lens data falls back to a labelled default that is not 90 deg.
##
## MUTATIONS (each run, each caught by the test named): fisheye radius law r*half -> r*half*0.9 (2, 1); Brown-Conrady
## normalisation (1+k1+k2) dropped (2, 1); set_camera_part ignoring the lens (3); FpvLens.DEFAULT.hfov_deg = 90 (4);
## _apply_fpv_lens writing a fixed 90 (1, 3); source_tan not covering the corners (5).
##
## The shader text itself cannot run headless; test 6 pins that its constants and formula tokens are the mirror's.

const EPS := 1e-6
const ASPECTS := [16.0 / 9.0, 2.7]


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	results.append(_projected_fov_equals_the_parts_fov(catalog))
	results.append(_the_mirror_matches_the_forward_model())
	results.append(_the_source_render_covers_the_corners())
	results.append(_changing_the_part_changes_fov_and_distortion(catalog))
	results.append(_no_lens_data_falls_back_to_a_labelled_default(catalog))
	results.append(_every_camera_part_has_a_valid_labelled_lens(catalog))
	results.append(_the_shader_text_carries_the_mirrors_formula())
	results.append(_vignette_and_ca_follow_the_distortion())
	return results


## Independent forward model: the output radius (half-widths) at which a ray `theta` off the axis lands.
static func _forward_radius(lens: Dictionary, theta: float) -> float:
	var half := deg_to_rad(float(lens["hfov_deg"])) * 0.5
	if str(lens["model"]) == "fisheye_equidistant":
		return theta / half
	# Brown-Conrady: solve tan(theta) = tan(half) * r * (1 + k1 r^2 + k2 r^4) / (1 + k1 + k2) by bisection.
	var lo := 0.0
	var hi := 3.0
	for i in 80:
		var mid := 0.5 * (lo + hi)
		var f: float = tan(half) * mid * (1.0 + lens["k1"] * mid * mid + lens["k2"] * pow(mid, 4.0)) / (1.0 + lens["k1"] + lens["k2"])
		if f < tan(theta):
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


static func _view_with(part: Dictionary) -> FpvView:
	var view := FpvView.new()
	view.set_camera_part(part)
	return view


## Drives place_lenses on a fresh camera for `view` fitted with the catalog's reference airframe and returns the camera.
static func _flown_camera(view: FpvView, airframe: AirframeModel) -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = 75.0
	view.attach(airframe.camera_eye())
	view.toggle_main()
	view.place_lenses(camera, Transform3D.IDENTITY)
	return camera


static func _reference(catalog: PartsCatalog) -> AirframeModel:
	var airframe := AirframeModel.new()
	airframe.rebuild(Build.from_ids(catalog, "frame_5in_freestyle", "motor_2207_1960kv",
		"prop_5x43x3", "battery_4s_1500"))
	return airframe


## 1. Mutation: _apply_fpv_lens writes a fixed fov, or the fisheye law changes -> caught.
static func _projected_fov_equals_the_parts_fov(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []
	var seen: Array[String] = []
	for part_id in ["cam_micro_analog", "cam_fullsize_analog", "cam_dji_o4_pro", "cam_sentera_6x_multispectral"]:
		var part := catalog.get_part(part_id)
		var lens := FpvLens.from_part(part)
		var airframe := _reference(catalog)
		var view := _view_with(part)
		var camera := _flown_camera(view, airframe)
		var aspect := view.target_aspect()
		# The engine's own projection of the source camera as configured (KEEP_WIDTH => flip_fov).
		var proj := Projection.create_perspective(camera.fov, aspect, camera.near, camera.far, true)
		for fraction: float in [1.0, 0.5, 0.2]:
			var theta := deg_to_rad(float(lens["hfov_deg"])) * 0.5 * fraction
			var ray := Vector4(sin(theta), 0.0, -cos(theta), 1.0)
			var clip := proj * ray
			var ndc_x := clip.x / clip.w
			var r_out := _forward_radius(lens, theta)
			var mirrored := FpvLens.source_ndc(lens, Vector2(r_out, 0.0), aspect).x
			if absf(ndc_x - mirrored) > 1e-4:
				problems.append("%s at %.0f%% of the half-FOV: engine projects x=%.5f, shader reads x=%.5f" % [
					part_id, fraction * 100.0, ndc_x, mirrored])
		# The picture edge IS the part's half-FOV: r = 1 must be a ray hfov/2 off the axis.
		var edge_theta := atan(FpvLens.ray_tan(lens, 1.0))
		if absf(rad_to_deg(edge_theta) * 2.0 - float(lens["hfov_deg"])) > 1e-3:
			problems.append("%s: picture edge is %.3f deg off axis, part says %.3f" % [part_id, rad_to_deg(edge_theta), float(lens["hfov_deg"]) * 0.5])
		seen.append("%s hfov %.0f -> source cam %.1f deg" % [part_id, float(lens["hfov_deg"]), camera.fov])
		airframe.free()
		view.free()
		camera.free()
	return TestResult.new("the projected FOV equals the part's FOV (edge ray, engine projection vs shader mapping)",
		problems.is_empty(), "; ".join(seen) if problems.is_empty() else str(problems))


## 2. Mutation: radius law scaled, or Brown normalisation dropped -> caught.
static func _the_mirror_matches_the_forward_model() -> TestResult:
	var problems: Array[String] = []
	var lenses := [
		{"hfov_deg": 133.0, "model": "fisheye_equidistant", "k1": 0.0, "k2": 0.0},
		{"hfov_deg": 108.0, "model": "brown_conrady", "k1": 0.30, "k2": 0.04},
		{"hfov_deg": 90.0, "model": "brown_conrady", "k1": -0.1, "k2": 0.0},
	]
	var checked := 0
	for lens in lenses:
		for r in [0.05, 0.2, 0.4, 0.7, 1.0, 1.15]:
			# Independent: from the output radius, the ray angle the lens model says it sees.
			var half := deg_to_rad(float(lens["hfov_deg"])) * 0.5
			var theta: float = 0.0
			if lens["model"] == "fisheye_equidistant":
				theta = r * half
			else:
				var k1: float = lens["k1"]
				var k2: float = lens["k2"]
				theta = atan(tan(half) * r * (1.0 + k1 * r * r + k2 * pow(r, 4.0)) / (1.0 + k1 + k2))
			var got := atan(FpvLens.ray_tan(lens, r))
			checked += 1
			if absf(got - theta) > 1e-6:
				problems.append("%s r=%.2f: mirror %.5f rad, model %.5f rad" % [lens["model"], r, got, theta])
	# Hand-computed anchors: equidistant 133 deg at r = 0.5 sees 33.25 deg; Brown at the edge is exactly hfov/2.
	var a := rad_to_deg(atan(FpvLens.ray_tan(lenses[0], 0.5)))
	if absf(a - 33.25) > 1e-4:
		problems.append("equidistant r=0.5 sees %.4f deg, expected 33.25" % a)
	var b := rad_to_deg(atan(FpvLens.ray_tan(lenses[1], 1.0)))
	if absf(b - 54.0) > 1e-4:
		problems.append("Brown-Conrady edge sees %.4f deg, expected 54" % b)
	return TestResult.new("the CPU mirror of the distortion formula matches the lens model at sampled radii",
		problems.is_empty(), "%d samples, %s" % [checked, "ok" if problems.is_empty() else str(problems)])


## 5. Mutation: source_tan returns the bare hfov/2 tangent -> the corners fall outside the render and this goes red.
static func _the_source_render_covers_the_corners() -> TestResult:
	var problems: Array[String] = []
	var lens := {"hfov_deg": 133.0, "model": "fisheye_equidistant", "k1": 0.0, "k2": 0.0}
	for aspect in ASPECTS:
		for p in [Vector2(1.0, 1.0 / aspect), Vector2(1.0, 0.0), Vector2(0.0, 1.0 / aspect), Vector2(0.6, 0.5 / aspect)]:
			var ndc := FpvLens.source_ndc(lens, p, aspect)
			if absf(ndc.x) > 1.0 + 1e-6 or absf(ndc.y) > 1.0 + 1e-6:
				problems.append("aspect %.2f pixel %s reads outside the render (%s)" % [aspect, p, ndc])
	return TestResult.new("the source render is wide enough to hold the picture's corners",
		problems.is_empty(), "ok" if problems.is_empty() else str(problems))


## 3. Mutation: set_camera_part ignores the lens, or the FOV written is constant -> caught.
static func _changing_the_part_changes_fov_and_distortion(catalog: PartsCatalog) -> TestResult:
	var results := {}
	for part_id in ["cam_micro_analog", "cam_fullsize_analog"]:
		var part := catalog.get_part(part_id)
		var airframe := _reference(catalog)
		var view := _view_with(part)
		var camera := _flown_camera(view, airframe)
		var material := view.lens_material()
		results[part_id] = {
			"fov": camera.fov,
			"hfov": float(view.lens_data()["hfov_deg"]),
			"k1": float(material.get_shader_parameter("k1")),
			"fisheye": float(material.get_shader_parameter("fisheye")),
			"half": float(material.get_shader_parameter("half_hfov")),
		}
		airframe.free()
		view.free()
		camera.free()
	var micro: Dictionary = results["cam_micro_analog"]
	var full: Dictionary = results["cam_fullsize_analog"]
	var ok: bool = not is_equal_approx(micro["fov"], full["fov"]) \
		and not is_equal_approx(micro["half"], full["half"]) \
		and micro["fisheye"] != full["fisheye"] and micro["k1"] != full["k1"] \
		and is_equal_approx(micro["half"], deg_to_rad(133.0) * 0.5) and is_equal_approx(full["k1"], 0.30)
	return TestResult.new("changing the camera part changes the FOV and the distortion reaching the shader",
		ok, "micro %s | full-size %s" % [micro, full])


## 4. Mutation: DEFAULT hfov 90, or from_part returning the DEFAULT without the label -> caught.
static func _no_lens_data_falls_back_to_a_labelled_default(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []
	var bare := {"part_id": "x", "name": "Bare camera", "category": "camera", "mass_g": 5.0}
	var broken := {"part_id": "y", "name": "Broken", "lens": {"hfov_deg": 400.0, "model": "pinhole"}}
	for part in [bare, broken, {}]:
		var lens := FpvLens.from_part(part)
		if not bool(lens.get("is_default", false)):
			problems.append("%s did not fall back to the default" % str(part.get("name", "{}")))
		if absf(float(lens["hfov_deg"]) - 90.0) < 1.0:
			problems.append("fallback FOV is 90")
		if not bool(lens["estimated"]) or not str(lens["lens_source"]).begins_with("DEFAULT ESTIMATE"):
			problems.append("fallback is not labelled as an estimate")
	var view := _view_with(bare)
	var airframe := _reference(catalog)
	var camera := _flown_camera(view, airframe)
	var expected := FpvLens.source_fov_deg(FpvLens.DEFAULT, view.target_aspect())
	if not is_equal_approx(camera.fov, expected):
		problems.append("camera fov %.2f is not the default lens's %.2f" % [camera.fov, expected])
	if not view.caption_text().contains("est."):
		problems.append("caption does not label the lens as an estimate: %s" % view.caption_text())
	airframe.free()
	view.free()
	camera.free()
	return TestResult.new("a part with no lens data renders through a labelled default, not 90 deg",
		problems.is_empty(), "default %.0f deg; %s" % [FpvLens.DEFAULT["hfov_deg"], "ok" if problems.is_empty() else str(problems)])


## Every catalog camera carries a lens block that survives validation and says where its numbers came from.
static func _every_camera_part_has_a_valid_labelled_lens(catalog: PartsCatalog) -> TestResult:
	var problems: Array[String] = []
	var n := 0
	for part in catalog.list_category("camera"):
		n += 1
		var lens := FpvLens.from_part(part)
		if bool(lens["is_default"]):
			problems.append("%s has no valid lens block" % part["part_id"])
		elif str(lens["lens_source"]).length() < 30:
			problems.append("%s lens has no source note" % part["part_id"])
		elif not (str(lens["lens_source"]).begins_with("ESTIMATE") or str(lens["lens_source"]).begins_with("PUBLISHED")):
			problems.append("%s lens source is neither ESTIMATE nor PUBLISHED" % part["part_id"])
	return TestResult.new("every catalog camera carries a valid lens block labelled ESTIMATE or PUBLISHED",
		problems.is_empty() and n >= 5, "%d cameras, %s" % [n, "ok" if problems.is_empty() else str(problems)])


## 6. The shader text is GLSL that cannot run here; pin that it repeats the mirror's formula and constants.
static func _the_shader_text_carries_the_mirrors_formula() -> TestResult:
	var problems: Array[String] = []
	for screen in [true, false]:
		var code := FpvLens.shader_code(screen)
		for token in ["tan(min(r * half_hfov, MAX_THETA))", "tan(half_hfov) * r * (1.0 + k1 * r2 + k2 * r2 * r2) / (1.0 + k1 + k2)",
				"0.5 + 0.5 * dir.x * tn / src_tan", "0.5 + 0.5 * dir.y * tn * aspect / src_tan",
				"(UV.y - 0.5) * 2.0 / aspect", "1.0 + ca * r2", "1.0 - ca * r2", "vig * t * t * (3.0 - 2.0 * t)"]:
			if not code.contains(token):
				problems.append("shader (screen=%s) lacks `%s`" % [screen, token])
		if not code.contains("const float MAX_THETA = %f;" % FpvLens.MAX_THETA_RAD):
			problems.append("MAX_THETA differs from the mirror's")
		if not code.contains("#define SRC %s" % ("screen_tex" if screen else "TEXTURE")):
			problems.append("wrong sampler for screen=%s" % screen)
	var shader := FpvLens.shader(true)
	var compiled := shader != null and shader.code.length() > 100
	return TestResult.new("the distortion shader repeats the CPU mirror's formula and constants",
		problems.is_empty() and compiled, "ok" if problems.is_empty() else str(problems))


## Vignette and chromatic aberration are estimates scaled by the distortion: none for a rectilinear lens, more for the
## stronger barrel, vignette dark at the corner and 1 at the centre.
static func _vignette_and_ca_follow_the_distortion() -> TestResult:
	var rect := {"hfov_deg": 70.0, "model": "brown_conrady", "k1": 0.0, "k2": 0.0}
	var fish := {"hfov_deg": 133.0, "model": "fisheye_equidistant", "k1": 0.0, "k2": 0.0}
	var barrel := {"hfov_deg": 108.0, "model": "brown_conrady", "k1": 0.30, "k2": 0.04}
	var a := 16.0 / 9.0
	var problems: Array[String] = []
	if FpvLens.ca_scale(rect, a) > 1e-9:
		problems.append("a rectilinear lens has chromatic aberration")
	if not (FpvLens.ca_scale(fish, a) > FpvLens.ca_scale(barrel, a) and FpvLens.ca_scale(barrel, a) > 0.0):
		problems.append("the fisheye (%.5f) does not bend more than the mild barrel (%.5f)" % [FpvLens.ca_scale(fish, a), FpvLens.ca_scale(barrel, a)])
	if absf(FpvLens.vignette(0.0) - 1.0) > EPS or not FpvLens.vignette(1.15) < 0.85 or not FpvLens.vignette(1.15) > 0.6:
		problems.append("vignette is %.3f at the centre and %.3f at the corner" % [FpvLens.vignette(0.0), FpvLens.vignette(1.15)])
	return TestResult.new("vignette and chromatic aberration are slight and scale with the distortion",
		problems.is_empty(), "ca fisheye %.5f, barrel %.5f, vignette corner %.3f" % [
			FpvLens.ca_scale(fish, a), FpvLens.ca_scale(barrel, a), FpvLens.vignette(1.15)])
