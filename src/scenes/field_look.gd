class_name FieldLook
extends Node3D
## R2.1: what the sim's field looks like, every part of it read from sim state.
##
##   * Grass: instanced tufts standing ON the ground the collider has. Each tuft's y is `Terrain.height_at` at its x/z,
##     the same call TerrainMesh draws and collides with, so a tuft cannot float or sink against the physics.
##   * Grass sway: the shader's wind uniforms are written from the R1.6 `Wind` (mean wind at grass height + the current
##     turbulence), nowhere else. Calm air gives `sway_amp` exactly 0 and the shader multiplies every moving term by it.
##   * Trees: instanced on the backdrop hills OUTSIDE the field rectangle. They are scenery, drawn and not collided,
##     exactly like the hills they stand on (BackdropHills), and they are kept out of the flyable field so nothing the
##     pilot can reach is something the physics does not have.
##   * Sky, sun, shadows, fog and exposure are authored in main.tscn (one DirectionalLight3D lights the scene AND places
##     the sky's sun, so they cannot disagree).
##
## Numbers marked ESTIMATE are not measured; nothing in the repo measures a blade of grass.

## Tufts per square metre over the field. ESTIMATE, chosen for look and for frame time.
const TUFT_DENSITY := 3.0
## Hard cap on tufts, so a large site thins out rather than blowing the frame budget.
const MAX_TUFTS := 70000
## The grass is placed over at most this half-extent around the site centre, in metres.
const MAX_HALF_M := 90.0
## Grass chunk edge, in metres: one MultiMesh per chunk so the engine can cull and range-fade whole chunks.
const CHUNK_M := 15.0
## Beyond this a chunk is not drawn (it fades over FADE_M first), in metres.
const GRASS_RANGE_M := 75.0
const FADE_M := 12.0
## Blade height at scale 1, in metres. ESTIMATE: a mown-meadow 25-40 cm.
const BLADE_HEIGHT_M := 0.34
## Largest tip displacement, as a fraction of the blade height: a blade does not lie flat in a gale. ESTIMATE.
const MAX_BEND := 0.7
## Wind speed at which the bend reaches 63 % of MAX_BEND, in m/s. ESTIMATE.
const BEND_SPEED_MPS := 6.0
## The wind is read at this height above the ground, in metres: grass height, not the 10 m reference.
const GRASS_WIND_HEIGHT_M := 0.5

const TREE_COUNT := 520
const TREE_MARGIN_M := 10.0

const _GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled;

// Written every frame from the sim's Wind (FieldLook.set_wind). sway_amp is the tip displacement in metres and is 0 in
// calm air; every moving term below is a multiple of it, so calm air is a still field.
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float sway_amp = 0.0;
uniform float wind_speed = 0.0;
uniform float gust_mix = 0.0;
uniform vec3 base_col : source_color = vec3(0.08, 0.17, 0.045);
uniform vec3 tip_col : source_color = vec3(0.24, 0.38, 0.11);
uniform vec3 dry_col : source_color = vec3(0.36, 0.34, 0.16);
// Density and blade height fall to nothing between these two camera distances, so the grass has no edge.
uniform float fade_start = 22.0;
uniform float fade_end = 78.0;

varying float v_tip;
varying float v_tone;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	float t = 1.0 - UV.y;
	v_tip = t;
	vec3 origin = MODEL_MATRIX[3].xyz;
	v_tone = hash21(floor(origin.xz * 2.0));
	// Distance fade: thin out tufts by a per-tuft hash (density) and shrink the survivors (height).
	float dist = distance(origin, CAMERA_POSITION_WORLD);
	float keep = 1.0 - smoothstep(fade_start, fade_end, dist);
	float pick = hash21(origin.xz * 7.31 + 3.7);
	if (pick > keep) {
		VERTEX = vec3(0.0);
	} else {
		VERTEX.y *= mix(0.25, 1.0, keep);
	}
	float along = dot(origin.xz, wind_dir);
	// Gust patches ride the mean wind; a larger gust_mix makes them deeper.
	float patch = 0.5 + 0.5 * sin(along * 0.17 - TIME * wind_speed * 0.6 + sin(origin.x * 0.09 + origin.z * 0.06) * 2.5);
	float flutter = sin(along * 1.9 - TIME * (2.0 + 0.45 * wind_speed) + v_tone * 6.2831);
	float disp = sway_amp * t * t * (0.7 + 0.3 * patch * (0.4 + gust_mix) + 0.18 * flutter);
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * disp;
	off.y = -0.35 * abs(disp) * t;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
}

void fragment() {
	vec3 col = mix(base_col, tip_col, v_tip);
	col = mix(col, dry_col, smoothstep(0.6, 1.0, v_tone) * 0.3);
	col *= 0.88 + 0.24 * fract(v_tone * 7.3);
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.15;
	// Lit like the lawn under it rather than as a thousand separate cards.
	vec3 up_view = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL = normalize(mix(NORMAL, up_view, 0.65));
	BACKLIGHT = col * 0.35;
}
"""

static var _grass_shader: Shader
static var _tuft_mesh: ArrayMesh

var grass_material: ShaderMaterial
var tuft_count := 0
var tree_count := 0
## Every tuft and tree origin placed, for tests and for nobody else.
var tuft_origins := PackedVector3Array()
var tree_origins := PackedVector3Array()


static func grass_shader() -> Shader:
	if _grass_shader == null:
		_grass_shader = Shader.new()
		_grass_shader.code = _GRASS_SHADER
	return _grass_shader


# ---------------------------------------------------------------------------
# Wind -> sway. Pure, so a test can call it.
# ---------------------------------------------------------------------------

## Tip displacement of a blade, in metres, for a wind of `mean_mps` plus a turbulence of `gust_mps` (both magnitudes at grass
## height). Zero at zero; saturating, because a blade bends over and stays there. ESTIMATE shape.
static func sway_amplitude_m(mean_mps: float, gust_mps: float) -> float:
	var v := maxf(mean_mps, 0.0) + maxf(gust_mps, 0.0)
	return BLADE_HEIGHT_M * MAX_BEND * (1.0 - exp(-v / BEND_SPEED_MPS))


## The shader parameters for a wind's current state: {sway_amp, wind_dir, wind_speed, gust_mix}. The only function that
## reads a Wind for the grass. A null wind is calm.
static func wind_params(wind: Wind) -> Dictionary:
	if wind == null:
		return {"sway_amp": 0.0, "wind_dir": Vector2(1.0, 0.0), "wind_speed": 0.0, "gust_mix": 0.0}
	var mean := wind.mean_at(GRASS_WIND_HEIGHT_M)
	var turb := wind.turbulence_mps()
	var mean_h := Vector2(mean.x, mean.z)
	var turb_h := Vector2(turb.x, turb.z)
	var mean_len := mean_h.length()
	var gust_len := turb_h.length()
	var total := mean_len + gust_len
	var dir := Vector2(1.0, 0.0)
	if mean_len > 1.0e-4:
		dir = mean_h / mean_len
	elif gust_len > 1.0e-4:
		dir = turb_h / gust_len
	return {
		"sway_amp": sway_amplitude_m(mean_len, gust_len),
		"wind_dir": dir,
		"wind_speed": mean_len,
		"gust_mix": gust_len / total if total > 1.0e-6 else 0.0,
	}


## Push the wind's state into the grass. Called every frame by Main.
func set_wind(wind: Wind) -> void:
	if grass_material == null:
		return
	var p := wind_params(wind)
	for key in p:
		grass_material.set_shader_parameter(key, p[key])


# ---------------------------------------------------------------------------
# Placement. Static and deterministic: same terrain, same field.
# ---------------------------------------------------------------------------

static func _hash(i: int, salt: int) -> float:
	var h := (i * 374761393 + salt * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float((h ^ (h >> 16)) & 0xffff) / 65535.0


static func _or_default(p_terrain: Terrain) -> Terrain:
	return p_terrain if p_terrain != null else Terrain.flat(Terrain.DEFAULT_WIDTH_M, Terrain.DEFAULT_LENGTH_M)


## Grass placement rectangle: the site, capped at MAX_HALF_M each way. Returns [centre, half].
static func grass_area(p_terrain: Terrain) -> Array:
	var terrain := _or_default(p_terrain)
	var half := terrain.half_extent()
	return [terrain.center(), Vector2(minf(half.x, MAX_HALF_M), minf(half.y, MAX_HALF_M))]


## Tuft origins over the grass area, y read from `Terrain.height_at` and from nothing else.
static func tuft_positions(p_terrain: Terrain) -> PackedVector3Array:
	var terrain := _or_default(p_terrain)
	var area := grass_area(terrain)
	var c: Vector2 = area[0]
	var half: Vector2 = area[1]
	var want := mini(int(4.0 * half.x * half.y * TUFT_DENSITY), MAX_TUFTS)
	var out := PackedVector3Array()
	out.resize(want)
	for i in want:
		var x := c.x + (_hash(i, 1) * 2.0 - 1.0) * half.x
		var z := c.y + (_hash(i, 2) * 2.0 - 1.0) * half.y
		out[i] = Vector3(x, terrain.height_at(x, z), z)
	return out


## True where a tree may stand: beyond the flyable field by TREE_MARGIN_M, and inside a clump (slow noise high).
static func tree_allowed(x: float, z: float, p_terrain: Terrain) -> bool:
	var terrain := _or_default(p_terrain)
	var half := terrain.half_extent()
	var c := terrain.center()
	var out_x := absf(x - c.x) - half.x
	var out_z := absf(z - c.y) - half.y
	if maxf(out_x, out_z) < TREE_MARGIN_M:
		return false
	return BackdropHills._fbm((x - c.x) * 0.02 + 5.0, (z - c.y) * 0.02 - 9.0) >= 0.5


## Tree origins on the backdrop hills, outside the field rectangle, in loose clumps.
static func tree_positions(p_terrain: Terrain) -> PackedVector3Array:
	var terrain := _or_default(p_terrain)
	var c := terrain.center()
	var out := PackedVector3Array()
	var tries := 0
	while out.size() < TREE_COUNT and tries < TREE_COUNT * 12:
		tries += 1
		var x := c.x + (_hash(tries, 11) * 2.0 - 1.0) * BackdropHills.RADIUS_M * 0.9
		var z := c.y + (_hash(tries, 12) * 2.0 - 1.0) * BackdropHills.RADIUS_M * 0.9
		if not tree_allowed(x, z, terrain):
			continue
		out.append(Vector3(x, BackdropHills.height_world(x, z, terrain), z))
	return out


# ---------------------------------------------------------------------------
# Meshes
# ---------------------------------------------------------------------------

## One tuft: seven tapered blades fanned around the origin, UV.y = 1 at the root and 0 at the tip.
static func tuft_mesh() -> ArrayMesh:
	if _tuft_mesh != null:
		return _tuft_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in 7:
		var ang := TAU * (float(b) / 7.0) + _hash(b, 5) * 0.8
		var r := 0.03 + 0.07 * _hash(b, 6)
		var base := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var tangent := Vector3(-sin(ang), 0.0, cos(ang))
		var h := BLADE_HEIGHT_M * (0.65 + 0.7 * _hash(b, 7))
		var w := 0.011 * (0.8 + 0.5 * _hash(b, 8))
		# Blades lean outward a little so the tuft opens like grass.
		var lean := Vector3(cos(ang), 0.0, sin(ang)) * (0.05 + 0.08 * _hash(b, 9))
		var bl := base - tangent * w
		var br := base + tangent * w
		var ml := base + lean * 0.5 + Vector3(0.0, h * 0.55, 0.0) - tangent * w * 0.6
		var mr := base + lean * 0.5 + Vector3(0.0, h * 0.55, 0.0) + tangent * w * 0.6
		var tip := base + lean + Vector3(0.0, h, 0.0)
		# The material is double sided and flips its own normal, so the winding is not load-bearing.
		_tri(st, bl, br, mr, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0.45))
		_tri(st, bl, mr, ml, Vector2(0, 1), Vector2(1, 0.45), Vector2(0, 0.45))
		_tri(st, ml, mr, tip, Vector2(0, 0.45), Vector2(1, 0.45), Vector2(0.5, 0))
	st.generate_normals()
	_tuft_mesh = st.commit()
	return _tuft_mesh


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_uv(uc)
	st.add_vertex(c)


## Tree variants built (0-2 conifers with different tier jitter, 3 a deciduous blob).
const TREE_VARIANTS := 4
static var _tree_meshes := {}

const _TRUNK := Color(0.19, 0.13, 0.09)
const _NEEDLE := Color(0.17, 0.27, 0.16)
const _LEAF := Color(0.20, 0.30, 0.10)


## One tree variant. Conifers: a dark trunk and 3-5 stacked, jittered, ragged-rimmed tiers (alpha-free). Variant 3 is a lumpy
## deciduous crown on a trunk. About 9 m tall at scale 1. Normals are authored (outward, lifted toward up for soft light).
static func tree_mesh(variant: int = 0) -> ArrayMesh:
	variant = clampi(variant, 0, TREE_VARIANTS - 1)
	if _tree_meshes.has(variant):
		return _tree_meshes[variant]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if variant < 3:
		var tiers := 3 + variant
		_trunk(st, 0.0, 3.0, 0.26, 0.13)
		var base_y := 1.4
		var top_y := 9.0
		for t in tiers:
			var f := float(t) / float(tiers)
			var y0 := lerpf(base_y, top_y - 3.2, f) + (_hash(t, 40 + variant) - 0.5) * 0.5
			var h := lerpf(3.6, 2.6, f) + _hash(t, 50 + variant) * 0.8
			var r := lerpf(2.2, 0.9, f) * (0.88 + 0.25 * _hash(t, 60 + variant))
			_tier(st, y0, h, r, variant * 31 + t)
	else:
		_trunk(st, 0.0, 4.2, 0.24, 0.11)
		for k in 4:
			var c := Vector3((_hash(k, 70) - 0.5) * 2.0, 5.2 + _hash(k, 71) * 1.6, (_hash(k, 72) - 0.5) * 2.0)
			_blob(st, c, 1.9 + 0.8 * _hash(k, 73), k)
	_tree_meshes[variant] = st.commit()
	return _tree_meshes[variant]


static func _vtx(st: SurfaceTool, p: Vector3, n: Vector3, col: Color) -> void:
	st.set_color(col)
	st.set_normal(n.normalized())
	st.add_vertex(p)


## A tapered trunk, 6 sided. Colour is the trunk's and flagged by alpha 0 (the shader reads alpha as "needle weight").
static func _trunk(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float) -> void:
	var seg := 6
	var col := Color(_TRUNK.r, _TRUNK.g, _TRUNK.b, 0.0)
	for i in seg:
		var a0 := TAU * float(i) / seg
		var a1 := TAU * float(i + 1) / seg
		var n0 := Vector3(cos(a0), 0.0, sin(a0))
		var n1 := Vector3(cos(a1), 0.0, sin(a1))
		var p00 := n0 * r0 + Vector3(0, y0, 0)
		var p01 := n1 * r0 + Vector3(0, y0, 0)
		var p10 := n0 * r1 + Vector3(0, y1, 0)
		var p11 := n1 * r1 + Vector3(0, y1, 0)
		for q in [[p00, n0], [p01, n1], [p10, n0], [p01, n1], [p11, n1], [p10, n0]]:
			var nn: Vector3 = q[1]
			_vtx(st, q[0], nn, col)


## One needle tier: a ragged skirt at y0 rising to a point at y0+h, drooping slightly at the rim.
static func _tier(st: SurfaceTool, y0: float, h: float, r: float, seed_i: int) -> void:
	var seg := 11
	var rim := PackedVector3Array()
	for i in seg:
		var a := TAU * float(i) / seg + (_hash(i, 80 + seed_i) - 0.5) * 0.25
		var rr := r * (0.78 + 0.4 * _hash(i, 90 + seed_i))
		rim.append(Vector3(cos(a) * rr, y0 - 0.25 * _hash(i, 95 + seed_i), sin(a) * rr))
	var tip := Vector3((_hash(seed_i, 99) - 0.5) * 0.15, y0 + h, 0.0)
	var dark := Color(_NEEDLE.r * 0.55, _NEEDLE.g * 0.55, _NEEDLE.b * 0.55, 1.0)
	var lit := Color(_NEEDLE.r, _NEEDLE.g, _NEEDLE.b, 1.0)
	for i in seg:
		var p0 := rim[i]
		var p1 := rim[(i + 1) % seg]
		var mid := (p0 + p1) * 0.5
		var n := Vector3(mid.x, r * 0.55, mid.z)
		var n0 := Vector3(p0.x, r * 0.55, p0.z)
		var n1 := Vector3(p1.x, r * 0.55, p1.z)
		_vtx(st, p0, n0, dark)
		_vtx(st, p1, n1, dark)
		_vtx(st, tip, n + Vector3(0, 0.8 * r, 0), lit)


## A lumpy crown: an 8x6 sphere with per-vertex radius noise.
static func _blob(st: SurfaceTool, c: Vector3, r: float, seed_i: int) -> void:
	var nu := 8
	var nv := 6
	var pts := []
	for v in nv + 1:
		var row := []
		var th := PI * float(v) / nv
		for u in nu:
			var ph := TAU * float(u) / nu
			var rr := r * (0.8 + 0.4 * _hash(v * 16 + u, 110 + seed_i))
			var d := Vector3(sin(th) * cos(ph), cos(th) * 0.85, sin(th) * sin(ph))
			row.append([c + d * rr, d])
		pts.append(row)
	var lo := Color(_LEAF.r * 0.6, _LEAF.g * 0.6, _LEAF.b * 0.6, 1.0)
	var hi := Color(_LEAF.r, _LEAF.g, _LEAF.b, 1.0)
	for v in nv:
		for u in nu:
			var u1 := (u + 1) % nu
			var a: Array = pts[v][u]
			var b: Array = pts[v][u1]
			var d2: Array = pts[v + 1][u]
			var e: Array = pts[v + 1][u1]
			for q in [a, b, d2, b, e, d2]:
				var pos: Vector3 = q[0]
				_vtx(st, pos, q[1], lo.lerp(hi, clampf((pos.y - c.y) / r * 0.5 + 0.5, 0.0, 1.0)))


# ---------------------------------------------------------------------------
# Scene
# ---------------------------------------------------------------------------

## Build (or rebuild) the grass and trees for a terrain. Children are freed first, so adopting a new course replaces them.
func rebuild(p_terrain: Terrain) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	grass_material = ShaderMaterial.new()
	grass_material.shader = grass_shader()
	tuft_origins = tuft_positions(p_terrain)
	tuft_count = tuft_origins.size()
	_build_grass_chunks()
	tree_origins = tree_positions(p_terrain)
	tree_count = tree_origins.size()
	_build_trees()


func _build_grass_chunks() -> void:
	var buckets := {}
	for i in tuft_origins.size():
		var p := tuft_origins[i]
		var key := Vector2i(floori(p.x / CHUNK_M), floori(p.z / CHUNK_M))
		if not buckets.has(key):
			buckets[key] = PackedInt32Array()
		buckets[key].append(i)
	for key in buckets:
		var ids: PackedInt32Array = buckets[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = tuft_mesh()
		mm.instance_count = ids.size()
		for j in ids.size():
			var i := ids[j]
			var s := 0.75 + 0.8 * _hash(i, 3)
			var bs := Basis(Vector3.UP, _hash(i, 4) * TAU).scaled(Vector3(1.0, s, 1.0))
			mm.set_instance_transform(j, Transform3D(bs, tuft_origins[i]))
		var inst := MultiMeshInstance3D.new()
		inst.name = "Grass_%d_%d" % [key.x, key.y]
		inst.multimesh = mm
		inst.material_override = grass_material
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The shader fades density and height to zero by 78 m; the chunk is culled just past that, invisibly.
		inst.visibility_range_end = GRASS_RANGE_M + FADE_M
		# Blades bend up to ~0.3 m; the mesh AABB is the tuft's, so grow it a little for the culler.
		inst.extra_cull_margin = 1.0
		add_child(inst)


func _build_trees() -> void:
	if tree_origins.is_empty():
		return
	var groups := []
	for v in TREE_VARIANTS:
		groups.append([])
	for i in tree_origins.size():
		# Mostly conifers; roughly one in eight is deciduous.
		var v := 3 if _hash(i, 24) > 0.88 else int(_hash(i, 25) * 3.0) % 3
		groups[v].append(i)
	var mat := ShaderMaterial.new()
	mat.shader = tree_shader()
	for v in TREE_VARIANTS:
		var ids: Array = groups[v]
		if ids.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = tree_mesh(v)
		mm.instance_count = ids.size()
		for j in ids.size():
			var i: int = ids[j]
			var s := 0.7 + 0.9 * _hash(i, 21)
			var lean := Basis(Vector3(cos(_hash(i, 26) * TAU), 0.0, sin(_hash(i, 26) * TAU)), (_hash(i, 27) - 0.5) * 0.12)
			var bs := lean * Basis(Vector3.UP, _hash(i, 22) * TAU).scaled(Vector3(s, s * (0.9 + 0.3 * _hash(i, 23)), s))
			# Sunk 0.4 m so a trunk on a slope has no gap under it.
			mm.set_instance_transform(j, Transform3D(bs, tree_origins[i] - Vector3(0, 0.4, 0)))
		var inst := MultiMeshInstance3D.new()
		inst.name = "Trees_%d" % v
		inst.multimesh = mm
		inst.material_override = mat
		inst.extra_cull_margin = 40.0
		add_child(inst)


static var _tree_shader: Shader


## Trees: vertex colour (alpha 0 = trunk, 1 = foliage), a per-tree hue/value shift from the tree's position, both faces lit.
static func tree_shader() -> Shader:
	if _tree_shader == null:
		_tree_shader = Shader.new()
		_tree_shader.code = """
shader_type spatial;
render_mode cull_back;
varying vec3 v_col;
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float h = hash21(floor(o.xz));
	float g = hash21(floor(o.xz) + 17.0);
	// Hue drifts between blue-green and olive; value shifts a little. Trunks (alpha 0) are not tinted.
	vec3 tint = vec3(1.0 + (h - 0.5) * 0.5, 1.0 + (g - 0.5) * 0.18, 1.0 - (h - 0.5) * 0.4) * (0.85 + 0.3 * g);
	// Authored as sRGB-looking values; the lit path wants linear.
	v_col = pow(mix(COLOR.rgb, COLOR.rgb * tint, COLOR.a), vec3(2.2));
}
void fragment() {
	vec3 c = v_col;
	if (!FRONT_FACING) { c *= 0.7; }
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.05;
}
"""
	return _tree_shader
