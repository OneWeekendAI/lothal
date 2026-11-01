class_name TestFrameLook
extends RefCounted
## PLAN Section 6, the look of the realistic frame, checked on the 5" Design Space's own stage and
## materials (not on fresh FrameLook calls): monochrome, the cut edge lighter and more matte than the
## face, a twill whose highlight depends on the view (anisotropy along the tows + a sharp clearcoat),
## aluminium standoffs and black screws, and the studio (soft key, rim, reflections from a studio sky,
## contact shadow, gentle SSAO; no glow, no depth-of-field blur). Pixels are judged by captures
## (build/capture_s6.gd); these checks pin the settings those captures were tuned on.

const CLASS_ID := "five_inch"
const GREY_TOL := 0.002


static func run() -> Array:
	var results: Array = []
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), PartsCatalog.load_default())
	var env := (ds._stage.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
	var face := ds.face_material as StandardMaterial3D
	var edge := ds.edge_material as StandardMaterial3D
	var hw := _hardware_mats(ds)
	results.append(_no_glow(env))
	results.append(_no_blur(ds))
	results.append(_greyscale(face, edge, hw))
	results.append(_white_lights(ds))
	results.append(_face_srgb(face))
	results.append(_edge_lighter(face, edge))
	results.append(_edge_matte(face, edge))
	results.append(_moving_highlight(face))
	results.append(_tow_width(face))
	results.append(_hardware(hw))
	results.append(_key_and_rim(ds, env))
	results.append(_reflections(env))
	results.append(_contact_shadow(ds))
	results.append(_ssao(env))
	results.append(_key_size(ds))
	ds.free()
	return results


static func _hardware_mats(ds: DesignSpace) -> Dictionary:
	var out := {}
	if ds.hardware_root == null:
		return out
	for c in ds.hardware_root.get_children():
		var mi := c as MeshInstance3D
		var kind := "standoff" if String(mi.name).begins_with("frame_standoff_") else "screw"
		var m := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if not out.has(kind):
			out[kind] = m
		elif out[kind] != m:
			out[kind + "_mixed"] = true
	return out


static func _is_grey(c: Color) -> bool:
	return absf(c.r - c.g) <= GREY_TOL and absf(c.g - c.b) <= GREY_TOL


## Mean linear value of a greyscale texture's red channel (its top mip, every 4th pixel).
static func _mean(tex: Texture2D, srgb: bool) -> float:
	var img := FrameLook.image_of(tex)
	if img == null:
		return -1.0
	var sum := 0.0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var v := img.get_pixel(x, y).r
			sum += pow(v, 2.2) if srgb else v
			n += 1
	return sum / maxf(n, 1)


static func _tex_grey(tex: Texture2D) -> bool:
	var img := FrameLook.image_of(tex)
	if img == null:
		return false
	for y in range(0, img.get_height(), 7):
		for x in range(0, img.get_width(), 7):
			if not _is_grey(img.get_pixel(x, y)):
				return false
	return true


static func _no_glow(env: Environment) -> TestResult:
	return TestResult.new("look: the studio has no glow or bloom", not env.glow_enabled, "glow %s" % env.glow_enabled)


static func _no_blur(ds: DesignSpace) -> TestResult:
	var attrs := ds.camera.attributes as CameraAttributesPractical
	var blur := attrs != null and (attrs.dof_blur_far_enabled or attrs.dof_blur_near_enabled)
	var world_attrs := ds.viewport.world_3d != null and ds.viewport.world_3d.camera_attributes != null
	return TestResult.new("look: no depth-of-field or motion blur on the stage camera", not blur and not world_attrs,
		"camera attrs %s, world attrs %s" % [attrs, world_attrs])


static func _greyscale(face: StandardMaterial3D, edge: StandardMaterial3D, hw: Dictionary) -> TestResult:
	var bad: Array = []
	if face == null or not _is_grey(face.albedo_color) or not _tex_grey(face.albedo_texture):
		bad.append("face")
	if edge == null or not _is_grey(edge.albedo_color):
		bad.append("edge")
	for k in ["standoff", "screw"]:
		if hw.get(k) == null or not _is_grey((hw[k] as StandardMaterial3D).albedo_color):
			bad.append(k)
	return TestResult.new("look: every frame material is greyscale (R = G = B, twill texture too)", bad.is_empty(), "%s" % [bad])


static func _white_lights(ds: DesignSpace) -> TestResult:
	var bad: Array = []
	for l in ds._stage.find_children("*", "DirectionalLight3D", true, false):
		if not _is_grey((l as Light3D).light_color):
			bad.append(l.name)
	return TestResult.new("look: every studio light is white", bad.is_empty(), "%s" % [bad])


static func _face_srgb(face: StandardMaterial3D) -> TestResult:
	return TestResult.new("look: the twill albedo is decoded as sRGB (dark carbon, not light-grey plates)",
		face != null and face.albedo_texture_force_srgb, "")


static func _edge_lighter(face: StandardMaterial3D, edge: StandardMaterial3D) -> TestResult:
	var f := _mean(face.albedo_texture, face.albedo_texture_force_srgb) * face.albedo_color.r
	var e := edge.albedo_color.r
	return TestResult.new("look: the cut edge is lighter than the carbon face (at least 3x)", e >= 3.0 * f,
		"edge %.3f face mean %.3f" % [e, f])


static func _edge_matte(face: StandardMaterial3D, edge: StandardMaterial3D) -> TestResult:
	var f := _mean(face.roughness_texture, false) * face.roughness
	return TestResult.new("look: the cut edge is matte, rougher than the face and without clearcoat",
		edge.roughness >= 0.8 and edge.roughness > f + 0.2 and not edge.clearcoat_enabled,
		"edge %.2f face mean %.2f" % [edge.roughness, f])


## Warp tows flow along U, weft along V: both must be present in quantity, or there is no orbit-dependent
## alternation; plus a sharp clearcoat for the moving reflection.
static func _moving_highlight(face: StandardMaterial3D) -> TestResult:
	var along_u := 0
	var along_v := 0
	var n := 0
	if FrameLook.image_of(face.anisotropy_flowmap) != null:
		var img := FrameLook.image_of(face.anisotropy_flowmap)
		for y in range(0, img.get_height(), 4):
			for x in range(0, img.get_width(), 4):
				var c := img.get_pixel(x, y)
				n += 1
				if c.r > 0.9 and absf(c.g - 0.5) < 0.05 and c.a > 0.9:
					along_u += 1
				elif c.g > 0.9 and absf(c.r - 0.5) < 0.05 and c.a > 0.9:
					along_v += 1
	var ok := face.anisotropy_enabled and face.anisotropy >= 0.3 and n > 0 \
		and along_u > n * 0.4 and along_v > n * 0.4 and face.clearcoat_enabled and face.clearcoat >= 0.3 \
		and face.clearcoat_roughness <= 0.15
	return TestResult.new("look: twill highlight moves with the view (anisotropy along warp and weft, sharp clearcoat)",
		ok, "aniso %s %.2f, u %d v %d of %d, coat %s %.2f/%.2f" % [face.anisotropy_enabled, face.anisotropy,
		along_u, along_v, n, face.clearcoat_enabled, face.clearcoat, face.clearcoat_roughness])


## Measured off the flow map: the run length of one direction along a row is two tows (2x2 twill).
static func _tow_width(face: StandardMaterial3D) -> TestResult:
	var img := FrameLook.image_of(face.anisotropy_flowmap)
	if img == null:
		return TestResult.new("look: twill tows are 1.5-3 mm wide (a 3K weave at true scale)", false, "no flow map")
	var w := img.get_width()
	var flips := 0
	for x in w:
		if (img.get_pixel(x, 0).r > 0.75) != (img.get_pixel((x + 1) % w, 0).r > 0.75):
			flips += 1
	var tile_mm := 1.0 / FrameView.UV_PER_MM / face.uv1_scale.x
	var tow_mm := tile_mm / (flips * 2.0) if flips > 0 else INF
	return TestResult.new("look: twill tows are 1.5-3 mm wide (a 3K weave at true scale)", tow_mm >= 1.5 and tow_mm <= 3.0,
		"tow %.2f mm (%d flips per %.0f mm tile)" % [tow_mm, flips, tile_mm])


static func _hardware(hw: Dictionary) -> TestResult:
	var so := hw.get("standoff") as StandardMaterial3D
	var sc := hw.get("screw") as StandardMaterial3D
	var ok := so != null and sc != null and not hw.has("standoff_mixed") and not hw.has("screw_mixed") \
		and so.metallic >= 0.5 and so.albedo_color.r >= 0.4 and sc.albedo_color.r <= 0.06 and sc.metallic >= 0.5
	return TestResult.new("look: standoffs are grey aluminium, screw heads black, one material per kind", ok,
		"standoff %s, screw %s" % [_grey_metal(so), _grey_metal(sc)])


static func _grey_metal(m: StandardMaterial3D) -> String:
	return "none" if m == null else "grey %.2f metallic %.2f" % [m.albedo_color.r, m.metallic]


static func _key_and_rim(ds: DesignSpace, env: Environment) -> TestResult:
	var key := ds._stage.get_node_or_null("Key") as DirectionalLight3D
	var rim := ds._stage.get_node_or_null("Rim") as DirectionalLight3D
	var sky: ShaderMaterial = null
	if env.sky != null:
		sky = env.sky.sky_material as ShaderMaterial
	var ok := key != null and rim != null and sky != null
	var detail := ""
	if ok:
		var kd := key.global_transform.basis.z if key.is_inside_tree() else key.basis.z
		var rd := rim.basis.z
		var softbox: Vector3 = sky.get_shader_parameter("key_dir")
		ok = key.shadow_enabled and key.shadow_blur >= 1.5 and rim.light_energy > 0.0 \
			and Vector2(kd.x, kd.z).dot(Vector2(rd.x, rd.z)) < 0.0 and softbox.normalized().dot(kd) > 0.99 \
			and sky.get_shader_parameter("key_power") is float and float(sky.get_shader_parameter("key_power")) > 0.5
		detail = "key %s rim %s softbox %s" % [kd, rd, softbox]
	return TestResult.new("look: one soft key with its softbox in the studio sky, and a rim from the far side", ok, detail)


static func _reflections(env: Environment) -> TestResult:
	return TestResult.new("look: reflections and ambient come from the studio sky",
		env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY and env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY
		and env.sky != null and env.sky.sky_material is ShaderMaterial, "")


static func _contact_shadow(ds: DesignSpace) -> TestResult:
	var blob := ds._stage.get_node_or_null("ContactShadow") as MeshInstance3D
	var key := ds._stage.get_node_or_null("Key") as DirectionalLight3D
	return TestResult.new("look: soft contact shadow under the drone and the key casts shadows",
		blob != null and blob.visible and blob.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and key != null and key.shadow_enabled, "")


static func _ssao(env: Environment) -> TestResult:
	return TestResult.new("look: gentle ambient occlusion (SSAO on, intensity 0.5-2)",
		env.ssao_enabled and env.ssao_intensity >= 0.5 and env.ssao_intensity <= 2.0, "%.2f" % env.ssao_intensity)


## The measured trap: a wide key widens its specular lobe until a black plate reads mid-grey.
static func _key_size(ds: DesignSpace) -> TestResult:
	var key := ds._stage.get_node_or_null("Key") as DirectionalLight3D
	return TestResult.new("look: the key's angular size stays at or under 2 deg (wider greys out the carbon)",
		key != null and key.light_angular_distance <= 2.0, "%.2f" % (key.light_angular_distance if key != null else -1.0))
