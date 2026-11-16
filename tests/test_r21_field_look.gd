class_name TestR21FieldLook
extends RefCounted
## R2.1 field look: the ground you SEE (mesh, grass, trees) is the ground the sim COLLIDES with, the grass sway reads the wind,
## and the sun, sky, shadows and fog in main.tscn are what they are claimed to be. One TestResult per case, never looped.
## Each case's mutation is named in its comment; each was run and caught.

const MAIN_SCRIPT := preload("res://src/scenes/main.gd")
const TOL := 1.0e-4


## A hilly 80 x 60 m heightfield terrain, heights up to ~8 m, centred off the origin so a missing centre shows.
static func _hilly() -> Terrain:
	var cols := 9
	var rows := 7
	var vals := PackedFloat32Array()
	vals.resize(cols * rows)
	for r in rows:
		for c in cols:
			vals[r * cols + c] = 4.0 + 4.0 * sin(c * 0.9) * cos(r * 1.3)
	var hf := Heightfield.make(100.0, -30.0, 10.0, cols, rows, vals)
	var t := Terrain.flat(hf.width_m(), hf.length_m(), hf.center().x, hf.center().y)
	t.heightfield = hf
	return t


static func _scene_over(terrain: Terrain) -> Node3D:
	var site := Site.new()
	site.site_id = "r21_site"
	site.terrain = terrain
	var sites := SiteLibrary.new()
	sites.put(site)
	var course := GateCourse.new([
		GateCourse.make_gate(Vector3(110.0, 4.0, 0.0), 0.0, 1.5),
		GateCourse.make_gate(Vector3(150.0, 4.0, 0.0), 0.0, 1.5),
	], "r21_course", "R2.1 course")
	course.site_id = site.site_id
	var courses := CourseLibrary.new()
	courses.put(course)
	var scene: Node3D = MAIN_SCRIPT.new()
	scene.site_library = sites
	scene.course_library = courses
	scene.ground_mesh = MeshInstance3D.new()
	scene.ground_collision = CollisionShape3D.new()
	scene.adopt_selected_course()
	return scene


static func _free_scene(scene: Node3D) -> void:
	scene.ground_mesh.free()
	scene.ground_collision.free()
	scene.free()


static func _cond(speed: float, gust: float) -> Conditions:
	var c := Conditions.new()
	c.wind_speed_mps = speed
	c.wind_from_deg = 270.0   # from the west: the air moves toward +X
	c.gustiness_mps = gust
	return c


static func run() -> Array:
	var out: Array = []
	var terrain := _hilly()
	var scene := _scene_over(terrain)

	# Mutation: TerrainMesh.vertices() writing y * 0.9 (a drawn hill the physics does not have) -> caught.
	var mesh_pts: PackedVector3Array = (scene.ground_mesh.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var worst_mesh := 0.0
	var top := 0.0
	for p in mesh_pts:
		worst_mesh = maxf(worst_mesh, absf(p.y - terrain.height_at(p.x, p.z)))
		top = maxf(top, p.y)
	out.append(TestResult.new("r2.1 terrain: every vertex of the sim's drawn ground sits at Terrain.height_at (hilly heightfield, off-origin)",
		mesh_pts.size() > 100 and top > 3.0 and worst_mesh < TOL,
		"%d vertices, top %.2f m, worst |y - height_at| %.6f m" % [mesh_pts.size(), top, worst_mesh]))

	# Mutation: build_collider fed a second, flattened triangle list -> caught.
	var shape := scene.ground_collision.shape as ConcavePolygonShape3D
	var faces: PackedVector3Array = shape.get_faces() if shape != null else PackedVector3Array()
	var worst_col := 0.0
	for p in faces:
		worst_col = maxf(worst_col, absf(p.y - terrain.height_at(p.x, p.z)))
	out.append(TestResult.new("r2.1 terrain: the collider's every point sits at Terrain.height_at, and is the same point list as the drawn mesh",
		faces.size() == mesh_pts.size() and worst_col < TOL,
		"%d collider points vs %d drawn, worst %.6f m" % [faces.size(), mesh_pts.size(), worst_col]))

	# Mutation: tuft_positions with y = 0.0 (grass on a flat floor under a hill) -> caught.
	var tufts := FieldLook.tuft_positions(terrain)
	var worst_tuft := 0.0
	var tuft_top := 0.0
	for p in tufts:
		worst_tuft = maxf(worst_tuft, absf(p.y - terrain.height_at(p.x, p.z)))
		tuft_top = maxf(tuft_top, p.y)
	out.append(TestResult.new("r2.1 grass: every tuft stands on Terrain.height_at, the surface the collider has",
		tufts.size() > 1000 and tuft_top > 3.0 and worst_tuft < TOL,
		"%d tufts, highest %.2f m, worst %.6f m" % [tufts.size(), tuft_top, worst_tuft]))

	# Mutation: grass_area ignoring the site centre -> tufts land off the field -> caught.
	var area := FieldLook.grass_area(terrain)
	var c: Vector2 = area[0]
	var half: Vector2 = area[1]
	var inside := true
	for p in tufts:
		inside = inside and absf(p.x - c.x) <= half.x + 1.0e-6 and absf(p.z - c.y) <= half.y + 1.0e-6
	out.append(TestResult.new("r2.1 grass: all tufts lie inside the site rectangle (centre %s, half %s)" % [c, half],
		inside and absf(c.x - terrain.center_x_m) < 1.0e-6, "inside %s" % inside))

	# Mutation: TREE_MARGIN_M = -100 (trees planted in the flyable field) -> caught.
	var trees := FieldLook.tree_positions(terrain)
	var th := terrain.half_extent()
	var min_out := INF
	var worst_tree := 0.0
	for p in trees:
		min_out = minf(min_out, maxf(absf(p.x - terrain.center_x_m) - th.x, absf(p.z - terrain.center_z_m) - th.y))
		worst_tree = maxf(worst_tree, absf(p.y - BackdropHills.height_world(p.x, p.z, terrain)))
	out.append(TestResult.new("r2.1 trees: scenery only, all outside the flyable field and standing on the backdrop hills' own height",
		trees.size() > 50 and min_out >= FieldLook.TREE_MARGIN_M - 1.0e-6 and worst_tree < TOL,
		"%d trees, nearest %.1f m outside the field, worst height error %.6f m" % [trees.size(), min_out, worst_tree]))

	# Every point inside the flyable field must refuse a tree, however high the clump noise; a grid scan guarantees
	# some inside points have high noise, so removing the margin makes this fail. The positive case is a placed tree.
	var inside_ok := 0
	var c0 := terrain.center()
	for i in 41:
		for j in 41:
			var px := c0.x + (float(i) / 40.0 * 2.0 - 1.0) * th.x
			var pz := c0.y + (float(j) / 40.0 * 2.0 - 1.0) * th.y
			if FieldLook.tree_allowed(px, pz, terrain):
				inside_ok += 1
	var outside_ok := trees.size() > 0 and FieldLook.tree_allowed(trees[0].x, trees[0].z, terrain)
	out.append(TestResult.new("r2.1 trees: tree_allowed refuses every point inside the field and accepts a placed tree outside",
		inside_ok == 0 and outside_ok, "%d inside points allowed, outside accepted %s" % [inside_ok, outside_ok]))
	_free_scene(scene)

	out.append(_calm_is_still())
	out.append(_wind_moves_grass())
	out.append(_gust_adds_sway())
	out.append(_direction_follows_wind())
	out.append(_shader_scales_by_sway())
	out.append(_sun_and_sky())
	out.append(_shadows())
	out.append(_fog_and_tonemap())
	return out


static func _field_look() -> FieldLook:
	var look := FieldLook.new()
	look.rebuild(Terrain.flat(20.0, 20.0))
	return look


## Mutation: wind_params returning a constant 0.2 m sway (grass that ignores the wind) -> caught by the calm and by the wind case.
static func _calm_is_still() -> TestResult:
	var look := _field_look()
	look.set_wind(Wind.new(_cond(0.0, 0.0)))
	var amp: float = look.grass_material.get_shader_parameter("sway_amp")
	var mix: float = look.grass_material.get_shader_parameter("gust_mix")
	var ok := amp == 0.0 and mix == 0.0 and FieldLook.sway_amplitude_m(0.0, 0.0) == 0.0
	look.free()
	return TestResult.new("r2.1 grass sway: calm air (0 m/s, 0 gust) gives zero sway amplitude in the shader", ok,
		"sway_amp %.6f, gust_mix %.6f" % [amp, mix])


static func _wind_moves_grass() -> TestResult:
	var look := _field_look()
	look.set_wind(Wind.new(_cond(8.0, 0.0)))
	var amp: float = look.grass_material.get_shader_parameter("sway_amp")
	look.set_wind(Wind.new(_cond(2.0, 0.0)))
	var weak: float = look.grass_material.get_shader_parameter("sway_amp")
	var gale := FieldLook.sway_amplitude_m(60.0, 0.0)
	look.free()
	var cap := FieldLook.BLADE_HEIGHT_M * FieldLook.MAX_BEND
	return TestResult.new("r2.1 grass sway: an 8 m/s wind sways more than a 2 m/s one, and a gale saturates under the bend cap",
		amp > 0.05 and amp > weak * 1.5 and weak > 0.0 and gale <= cap + 1.0e-9 and gale > 0.99 * cap,
		"8 m/s %.4f m, 2 m/s %.4f m, gale %.4f m (cap %.4f)" % [amp, weak, gale, cap])


## Mutation: wind_params dropping the turbulence term (gust_len treated as 0) -> caught.
static func _gust_adds_sway() -> TestResult:
	var w := Wind.new(_cond(5.0, 3.0))
	var pos := Vector3(0, 1.0, 0)
	for _i in 600:
		w.update_at(0.01, pos, pos.y)
	var look := _field_look()
	look.set_wind(w)
	var p := FieldLook.wind_params(w)
	var turb := w.turbulence_mps()
	var steady_only := FieldLook.sway_amplitude_m(Vector2(w.mean_at(FieldLook.GRASS_WIND_HEIGHT_M).x,
		w.mean_at(FieldLook.GRASS_WIND_HEIGHT_M).z).length(), 0.0)
	look.free()
	return TestResult.new("r2.1 grass sway: the live turbulence of the wind field adds to the sway and shows as a gust fraction",
		Vector2(turb.x, turb.z).length() > 0.05 and p["sway_amp"] > steady_only and p["gust_mix"] > 0.0,
		"turbulence %.3f m/s, sway %.4f vs steady-only %.4f, gust_mix %.3f" % [Vector2(turb.x, turb.z).length(), p["sway_amp"], steady_only, p["gust_mix"]])


## Mutation: wind_dir fixed at (1, 0) -> the north-wind half of this fails -> caught.
static func _direction_follows_wind() -> TestResult:
	var west := Conditions.new()
	west.wind_speed_mps = 6.0
	west.wind_from_deg = 270.0
	var north := Conditions.new()
	north.wind_speed_mps = 6.0
	north.wind_from_deg = 0.0
	var dw: Vector2 = FieldLook.wind_params(Wind.new(west))["wind_dir"]
	var dn: Vector2 = FieldLook.wind_params(Wind.new(north))["wind_dir"]
	# Wind.steady_vector: from the west moves toward +X; from the north moves toward +Z.
	return TestResult.new("r2.1 grass sway: the lean direction is the direction the air moves (west wind +X, north wind +Z)",
		dw.x > 0.99 and absf(dw.y) < 0.01 and dn.y > 0.99 and absf(dn.x) < 0.01,
		"west %s, north %s" % [dw, dn])


## Mutation: dropping the `sway_amp *` factor from the shader's displacement (blades that move in calm air) -> caught.
static func _shader_scales_by_sway() -> TestResult:
	var code := FieldLook.grass_shader().code
	var line := ""
	for l in code.split("\n"):
		if l.strip_edges().begins_with("float disp"):
			line = l
	var calm_still := line.find("sway_amp *") >= 0
	var offsets_use_disp := code.find("vec3(wind_dir.x, 0.0, wind_dir.y) * disp") >= 0 and code.find("off.y = -0.35 * abs(disp)") >= 0
	return TestResult.new("r2.1 grass shader: every moving term is a multiple of sway_amp, so zero amplitude is a still field",
		calm_still and offsets_use_disp and code.find("TIME") >= 0 and code.find("uniform float sway_amp = 0.0") >= 0,
		"disp line: %s" % line.strip_edges())


static func _main_nodes() -> Dictionary:
	var main: Node = (load("res://src/scenes/main.tscn") as PackedScene).instantiate()
	var sun := main.get_node("DirectionalLight3D") as DirectionalLight3D
	var env := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	var suns := 0
	for child in main.get_children():
		if child is DirectionalLight3D:
			suns += 1
	return {"main": main, "sun": sun, "env": env, "suns": suns}


## Mutation: sky_mode SKY_ONLY on the light (the sky's sun no longer follows it), or a second DirectionalLight3D -> caught.
static func _sun_and_sky() -> TestResult:
	var n := _main_nodes()
	var sun: DirectionalLight3D = n["sun"]
	var env: Environment = n["env"]
	var sky_ok := env.background_mode == Environment.BG_SKY and env.sky != null and env.sky.sky_material is PhysicalSkyMaterial
	var ok: bool = sky_ok and n["suns"] == 1 and sun.sky_mode == DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	var down: float = (-sun.transform.basis.z).y
	var mode: int = sun.sky_mode
	(n["main"] as Node).free()
	return TestResult.new("r2.1 sky: a physical sky whose sun is the scene's one DirectionalLight3D (LIGHT_AND_SKY), shining down from 10-60 degrees",
		ok and down < 0.0 and rad_to_deg(asin(-down)) > 10.0 and rad_to_deg(asin(-down)) < 60.0,
		"sky ok %s, suns %d, sky_mode %d, sun elevation %.1f deg" % [sky_ok, n["suns"], mode, rad_to_deg(asin(-down))])


## Mutation: the first split at 0.5 (a 150 m first cascade, a blurry drone shadow), 2 splits, or blend_splits back on (dither stipple on far shadows) -> caught.
static func _shadows() -> TestResult:
	var n := _main_nodes()
	var sun: DirectionalLight3D = n["sun"]
	var reach := sun.directional_shadow_max_distance
	var first := sun.directional_shadow_split_1 * reach
	var second := sun.directional_shadow_split_2 * reach
	var third := sun.directional_shadow_split_3 * reach
	var ok := sun.shadow_enabled and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS \
		and not sun.directional_shadow_blend_splits and reach >= 300.0 and first <= 15.0 and first >= 5.0 and second > first and third > second and third < reach
	(n["main"] as Node).free()
	return TestResult.new("r2.1 shadows: 4-split PSSM to 300 m with the first cascade 5-15 m (FPV range) and ordered splits", ok,
		"max %.0f m, splits at %.1f / %.1f / %.1f m" % [reach, first, second, third])


## Mutation: fog_density back to 0.0003, or tonemap back to filmic -> caught.
static func _fog_and_tonemap() -> TestResult:
	var n := _main_nodes()
	var env: Environment = n["env"]
	# 0.0003 per metre is 13 km of visibility: nothing at all inside the 600 m far plane. The look needs real extinction.
	var seen_at_300 := 1.0 - exp(-env.fog_density * 300.0)
	var ok := env.fog_enabled and seen_at_300 > 0.15 and env.fog_aerial_perspective > 0.3 \
		and env.tonemap_mode == Environment.TONE_MAPPER_ACES and env.ssao_enabled and env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY
	var cam := (n["main"] as Node).get_node("WorldEnvironment") as WorldEnvironment
	var exposure_ok := cam.camera_attributes is CameraAttributesPractical and (cam.camera_attributes as CameraAttributesPractical).auto_exposure_enabled
	(n["main"] as Node).free()
	return TestResult.new("r2.1 environment: ACES, ambient from the sky, SSAO, auto-exposure, and fog that hides >15% of the scene at 300 m with aerial perspective",
		ok and exposure_ok, "fog at 300 m %.0f%%, aerial %.2f, tonemap %d, auto exposure %s" % [
			seen_at_300 * 100.0, env.fog_aerial_perspective, env.tonemap_mode, exposure_ok])
