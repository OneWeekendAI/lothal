class_name GroundGrid
extends RefCounted
## The sim's ground look: grassland, procedural, no canned assets. The ground still carries a
## faint grid — the grid is not decoration, it is the optical flow that lets a pilot judge
## altitude, speed and drift — but it now sits on grass instead of on slate.
##
## The terrain mesh carries no UVs (TerrainMesh adds vertices only), so every pattern here is
## read from WORLD position in the shader. A UV-mapped texture sampled the whole field at one
## texel, which is why the ground used to render as a single near-black colour.

## Kept for callers: the grid pitch, in metres.
const METRES_PER_TILE := 2.0

const _GROUND_SHADER := """
shader_type spatial;
// Both faces: TerrainMesh's winding reads as back-facing from above here, and its generated
// normals point down. The fragment flips the normal to whichever side is being looked at.
render_mode cull_disabled;

uniform float tile_m = 2.0;
uniform vec3 grass_dark : source_color = vec3(0.24, 0.42, 0.14);
uniform vec3 grass_light : source_color = vec3(0.52, 0.70, 0.28);
uniform vec3 dry_grass : source_color = vec3(0.72, 0.68, 0.40);
uniform vec3 dirt : source_color = vec3(0.45, 0.36, 0.25);
uniform vec3 rock : source_color = vec3(0.50, 0.48, 0.45);
uniform vec3 snow : source_color = vec3(0.92, 0.94, 0.96);
uniform float snow_line = 1.0e9;
uniform float grid_strength = 0.10;

varying vec3 world_pos;
varying vec3 world_nrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int k = 0; k < 4; k++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz;
	float big = fbm(p * 0.04);
	float mid = fbm(p * 0.12 + 7.0);
	float fine = noise(p * 3.0);
	vec3 col = mix(grass_dark, grass_light, smoothstep(0.35, 0.65, big));
	col = mix(col, dry_grass, smoothstep(0.62, 0.8, mid) * 0.55);
	col *= 0.9 + 0.2 * fine;

	float steep = 1.0 - clamp(abs(world_nrm.y), 0.0, 1.0);
	col = mix(col, dirt, smoothstep(0.25, 0.5, steep) * 0.7);
	col = mix(col, rock, smoothstep(0.5, 0.75, steep + (mid - 0.5) * 0.2));
	float snowy = smoothstep(snow_line, snow_line + 6.0, world_pos.y + (big - 0.5) * 8.0);
	col = mix(col, snow, snowy * smoothstep(0.55, 0.25, steep));

	// The flight grid: thin lines every tile_m, fading with distance so the horizon stays calm.
	vec2 g = abs(fract(p / tile_m + 0.5) - 0.5) / fwidth(p / tile_m);
	float line = 1.0 - clamp(min(g.x, g.y), 0.0, 1.0);
	float fade = 1.0 - smoothstep(30.0, 90.0, length(world_pos - CAMERA_POSITION_WORLD));
	col = mix(col, col * 1.35 + 0.04, line * grid_strength * fade * 3.0);

	if (!FRONT_FACING) { NORMAL = -NORMAL; }
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
"""

static var _shader: Shader


static func _ground_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = _GROUND_SHADER
	return _shader


## The flyable field's material: grass plus the flight grid.
static func build_material(_ground_size_m: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _ground_shader()
	material.set_shader_parameter("tile_m", METRES_PER_TILE)
	return material


## The backdrop hills' material: the same palette with no grid and snow on the tallest tops.
static func build_backdrop_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _ground_shader()
	material.set_shader_parameter("grid_strength", 0.0)
	material.set_shader_parameter("snow_line", 38.0)
	return material
