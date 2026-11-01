class_name FrameLook
extends RefCounted
## PLAN Section 6, the look of the realistic frame: the materials FrameGen's surfaces are drawn with and
## the studio the Design Space lights them in. Monochrome throughout: every colour here has R == G == B.
##
## Carbon faces: a 2x2 twill of 2 mm tows (eight tows across FrameView's 16 mm UV tile), generated here
## as albedo, normal, roughness and an anisotropy flow map. The flow map points along each tow, so warp
## and weft tows throw their highlight in different directions and the pattern changes as the camera
## orbits; a thin clearcoat on top carries the sharp reflection of the studio's softboxes. Cut edges
## are lighter and matte (sanded fibre ends, no resin skin). Standoffs are mid-grey anodised aluminium,
## screw heads black oxide steel.

const TILE_PX := 512
const TOWS_PER_TILE := 8            ## 16 mm tile / 8 = 2 mm tows, a 3K twill
const FIBRES_PER_TOW := 9
const NORMAL_STRENGTH := 18.0

const FACE_CLEARCOAT := 0.6
const FACE_CLEARCOAT_ROUGHNESS := 0.06
const FACE_ANISOTROPY := 0.75
const FACE_SPECULAR := 0.35
const EDGE_GREY := 0.30
const EDGE_ROUGHNESS := 0.92
## Anodised aluminium reads grey only by what it reflects; in a dark studio a polished metal reads
## black (seen: the first capture), so the standoff is a satin finish that spreads the softbox.
const STANDOFF_GREY := 0.62
const SCREW_GREY := 0.035

## Studio: where the key's softbox sits (and the key light shines from), and the rim's.
const KEY_ROTATION_DEG := Vector3(-52.0, -35.0, 0.0)
const RIM_ROTATION_DEG := Vector3(-20.0, 165.0, 0.0)
## The key's angular size. Its SHADOW is softened further by blur; its large-source reflection is the
## softbox in STUDIO_SKY. Measured: at 5 deg Godot widens the key's specular lobe until every horizontal
## plate reads mid-grey whatever its albedo (screw close-up, black albedo: 131/255 at 5 deg, 67 at 0).
const KEY_ANGULAR_DEG := 1.5
const SSAO_INTENSITY := 1.4
const SOFTBOX_POWER := 2.2
const RIM_STRIP_POWER := 1.6

static var _maps: Dictionary = {}
static var _images: Dictionary = {}


## {albedo, normal, roughness, flow} ImageTextures for one twill tile, built once per process.
static func twill_maps() -> Dictionary:
	if not _maps.is_empty():
		return _maps
	var n := TILE_PX
	var h := PackedFloat32Array()
	h.resize(n * n)
	var warp := PackedByteArray()
	warp.resize(n * n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in n:
		var cy := (y + 0.5) / n * TOWS_PER_TILE
		var iy := int(cy)
		var fv := cy - iy
		for x in n:
			var cx := (x + 0.5) / n * TOWS_PER_TILE
			var ix := int(cx)
			var fu := cx - ix
			var w := posmod(ix - iy, 4) < 2
			var across := fv if w else fu
			var along := fu if w else fv
			var crown := sqrt(sin(PI * across)) * (0.72 + 0.28 * sin(PI * along))
			var fib := sin(TAU * across * FIBRES_PER_TOW) * 0.03
			h[y * n + x] = crown * 0.65 + fib + rng.randfn(0.0, 0.008)
			warp[y * n + x] = 1 if w else 0
	var alb := PackedByteArray()
	var nrm := PackedByteArray()
	var rough := PackedByteArray()
	var flow := PackedByteArray()
	alb.resize(n * n * 3)
	nrm.resize(n * n * 3)
	rough.resize(n * n * 3)
	flow.resize(n * n * 4)
	for y in n:
		for x in n:
			var i := y * n + x
			var hv := h[i]
			var gx := (h[y * n + (x + 1) % n] - h[y * n + (x - 1 + n) % n]) * 0.5 * NORMAL_STRENGTH
			var gy := (h[((y + 1) % n) * n + x] - h[((y - 1 + n) % n) * n + x]) * 0.5 * NORMAL_STRENGTH
			var nv := Vector3(-gx, gy, 1.0).normalized() * 0.5 + Vector3(0.5, 0.5, 0.5)
			var a := clampf((0.055 if warp[i] == 1 else 0.045) + 0.05 * hv, 0.0, 1.0)
			var r := clampf(0.40 + 0.30 * (1.0 - clampf(hv, 0.0, 1.0)) + rng.randfn(0.0, 0.015), 0.0, 1.0)
			var av := int(round(pow(a, 1.0 / 2.2) * 255.0))
			for c in 3:
				alb[i * 3 + c] = av
				rough[i * 3 + c] = int(round(r * 255.0))
			nrm[i * 3] = int(round(nv.x * 255.0))
			nrm[i * 3 + 1] = int(round(nv.y * 255.0))
			nrm[i * 3 + 2] = int(round(nv.z * 255.0))
			# Flow along the tow: warp tows run along U (+tangent), weft along V. Alpha = strength.
			flow[i * 4] = 255 if warp[i] == 1 else 128
			flow[i * 4 + 1] = 128 if warp[i] == 1 else 255
			flow[i * 4 + 2] = 128
			flow[i * 4 + 3] = 255
	var imgs := {
		"albedo": Image.create_from_data(n, n, false, Image.FORMAT_RGB8, alb),
		"normal": Image.create_from_data(n, n, false, Image.FORMAT_RGB8, nrm),
		"roughness": Image.create_from_data(n, n, false, Image.FORMAT_RGB8, rough),
		"flow": Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, flow),
	}
	for k in imgs:
		_maps[k] = _tex(imgs[k])
		_images[_maps[k]] = imgs[k]
	return _maps


## The CPU-side image a twill texture was made from (ImageTexture.get_image reads back from the GPU,
## which the headless dummy renderer cannot do), or null for a texture FrameLook did not make.
static func image_of(tex: Texture2D) -> Image:
	return _images.get(tex) as Image


static func _tex(img: Image) -> ImageTexture:
	var mipped := img.duplicate() as Image
	mipped.generate_mipmaps()
	return ImageTexture.create_from_image(mipped)


## The carbon twill on every plate face (FrameGen.SURF_FACE).
static func face_material() -> StandardMaterial3D:
	var m := twill_maps()
	var mat := StandardMaterial3D.new()
	mat.resource_name = "carbon_twill_face"
	mat.albedo_color = Color(1, 1, 1)
	mat.albedo_texture = m["albedo"]
	# A runtime ImageTexture is sampled as linear unless forced: measured, the tile's 0.05 albedo drew
	# as ~0.25 (light grey plates) without this.
	mat.albedo_texture_force_srgb = true
	mat.metallic = 0.0
	mat.metallic_specular = FACE_SPECULAR
	mat.roughness = 1.0
	mat.roughness_texture = m["roughness"]
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.normal_enabled = true
	mat.normal_texture = m["normal"]
	mat.normal_scale = 1.0
	mat.clearcoat_enabled = true
	mat.clearcoat = FACE_CLEARCOAT
	mat.clearcoat_roughness = FACE_CLEARCOAT_ROUGHNESS
	mat.anisotropy_enabled = true
	mat.anisotropy = FACE_ANISOTROPY
	mat.anisotropy_flowmap = m["flow"]
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


## The CNC-cut edge (FrameGen.SURF_EDGE): lighter than the face and matte.
static func edge_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "carbon_cut_edge"
	mat.albedo_color = Color(EDGE_GREY, EDGE_GREY, EDGE_GREY)
	mat.metallic = 0.0
	mat.roughness = EDGE_ROUGHNESS
	mat.metallic_specular = 0.3
	return mat


static func standoff_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "standoff_anodised_aluminium"
	mat.albedo_color = Color(STANDOFF_GREY, STANDOFF_GREY, STANDOFF_GREY)
	mat.metallic = 0.8
	mat.roughness = 0.42
	return mat


static func screw_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "screw_black_oxide"
	mat.albedo_color = Color(SCREW_GREY, SCREW_GREY, SCREW_GREY)
	mat.metallic = 0.85
	mat.roughness = 0.38
	return mat


## The studio as the environment's sky: never seen (the background is a flat colour), only reflected
## and used for ambient. A dark room, a large softbox where the key is, a tall strip behind for the rim,
## a faint ceiling bounce. Grey only.
const STUDIO_SKY := """
shader_type sky;
uniform vec3 key_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 rim_dir = vec3(0.0, 0.3, -1.0);
uniform float key_power = 2.2;
uniform float rim_power = 1.6;
float box(vec3 d, vec3 c, float inner, float outer) {
	return smoothstep(cos(outer), cos(inner), dot(d, normalize(c)));
}
void sky() {
	vec3 d = normalize(EYEDIR);
	float v = mix(0.012, 0.06, smoothstep(-0.3, 0.8, d.y));
	v += key_power * box(d, key_dir, radians(16.0), radians(30.0));
	vec3 r = normalize(rim_dir);
	vec3 side = normalize(cross(r, vec3(0.0, 1.0, 0.0)));
	float strip = 1.0 - smoothstep(0.08, 0.16, abs(dot(d, side)));
	v += rim_power * strip * smoothstep(0.55, 0.8, dot(d, r));
	v += 0.12 * smoothstep(0.75, 0.98, d.y);
	COLOR = vec3(v);
}
"""


## The direction a light at `rotation_deg` (DirectionalLight3D.rotation) comes FROM.
static func from_dir(rotation_deg: Vector3) -> Vector3:
	var r := Vector3(deg_to_rad(rotation_deg.x), deg_to_rad(rotation_deg.y), deg_to_rad(rotation_deg.z))
	return Basis.from_euler(r).z


static func studio_sky() -> Sky:
	var sh := Shader.new()
	sh.code = STUDIO_SKY
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("key_dir", from_dir(KEY_ROTATION_DEG))
	mat.set_shader_parameter("rim_dir", from_dir(RIM_ROTATION_DEG))
	mat.set_shader_parameter("key_power", SOFTBOX_POWER)
	mat.set_shader_parameter("rim_power", RIM_STRIP_POWER)
	var sky := Sky.new()
	sky.sky_material = mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	return sky
