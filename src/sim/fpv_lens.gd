class_name FpvLens
extends RefCounted
## The FPV camera's lens (R2.2): what field of view and what distortion the fitted camera part has, the CPU mirror of
## the distortion shader, and the shader itself.
##
## HOW THE PICTURE IS MADE. A Camera3D can only draw a rectilinear projection, and a real FPV lens is a wide, barrelled
## fisheye. So the world is drawn rectilinear through a wider-than-the-lens camera (`source_fov_deg`) and a fullscreen
## shader remaps every output pixel back to the source pixel the lens would have put there. Output pixel position p is
## measured in units of the picture's HALF-WIDTH (x in [-1, 1], y in [-1/aspect, 1/aspect]); r = |p|. Then:
##
##   fisheye_equidistant : ray angle theta = r * hfov / 2           (image radius proportional to angle)
##   brown_conrady       : tan(theta) = tan(hfov / 2) * r * (1 + k1 r^2 + k2 r^4) / (1 + k1 + k2)
##
## Both put the horizontal picture edge (r = 1) at exactly hfov / 2 off the axis, which is what makes "the part's FOV" a
## property of the picture rather than of a render setting. The Brown-Conrady polynomial is written in the
## distorted -> undistorted direction (what a post-process needs: for each output pixel, where in the rectilinear render
## is it), k > 0 is barrel. The source plane coordinate of the ray is tan(theta) along p's direction.
##
## The shader text below repeats this arithmetic in GLSL; `ray_tan`, `source_ndc`, `vignette` and `ca_scale` are the CPU
## mirror a test can run, and the test compares the mirror against an independent forward model and the engine's own
## projection. Vignetting and chromatic aberration are LABELLED ESTIMATES (the constants below), not measured: real values
## depend on the lens and the sensor and nobody has published them for these parts.

## Used when a part carries no valid `lens` block (custom parts, a camera not yet given one). A labelled estimate of a
## typical FPV lens, deliberately NOT 90 deg: a 90 deg picture would hide that the fitted camera says nothing.
const DEFAULT := {
	"hfov_deg": 125.0,
	"model": "fisheye_equidistant",
	"k1": 0.0,
	"k2": 0.0,
	"estimated": true,
	"is_default": true,
	"lens_source": "DEFAULT ESTIMATE: this camera part has no lens data; typical FPV lens (about 145 deg diagonal).",
}
const MODELS := ["fisheye_equidistant", "brown_conrady"]
const MIN_HFOV_DEG := 20.0
const MAX_HFOV_DEG := 175.0
## A ray more than this far off axis cannot be drawn by the rectilinear source camera; picture beyond it goes black.
const MAX_THETA_RAD := 1.4835299     # 85 deg
## The widest rectilinear source camera allowed, horizontal degrees.
const MAX_SOURCE_FOV_DEG := 170.0

## ESTIMATES. Corner darkening at the picture corner (fraction of light lost), and the lateral chromatic aberration as a
## fraction of radius per unit of corner distortion (red sampled outward, blue inward, by ca * r^2).
const VIGNETTE_STRENGTH := 0.30
const CA_PER_DISTORTION := 0.010
## The vignette starts at this radius (half-widths) and is fully on at VIGNETTE_END.
const VIGNETTE_START := 0.45
const VIGNETTE_END := 1.25


## The lens a part carries, normalised and validated; DEFAULT when the part has none or it is unusable.
static func from_part(part: Dictionary) -> Dictionary:
	var raw: Variant = part.get("lens", null)
	if not (raw is Dictionary):
		return DEFAULT.duplicate()
	var lens: Dictionary = raw
	var hfov := float(lens.get("hfov_deg", 0.0))
	var model := str(lens.get("model", ""))
	var k1 := float(lens.get("k1", 0.0))
	var k2 := float(lens.get("k2", 0.0))
	if hfov < MIN_HFOV_DEG or hfov > MAX_HFOV_DEG or not MODELS.has(model):
		return DEFAULT.duplicate()
	if model == "brown_conrady" and (1.0 + k1 + k2 < 0.2 or hfov >= 170.0):
		return DEFAULT.duplicate()
	return {
		"hfov_deg": hfov,
		"model": model,
		"k1": k1,
		"k2": k2,
		"estimated": bool(lens.get("estimated", true)),
		"is_default": false,
		"lens_source": str(lens.get("lens_source", "")),
	}


## tan of the ray's angle off the axis for an output radius r (half-widths).
static func ray_tan(lens: Dictionary, r: float) -> float:
	var half := deg_to_rad(float(lens["hfov_deg"])) * 0.5
	if str(lens["model"]) == "fisheye_equidistant":
		return tan(minf(r * half, MAX_THETA_RAD))
	var k1 := float(lens["k1"])
	var k2 := float(lens["k2"])
	var r2 := r * r
	return tan(half) * r * (1.0 + k1 * r2 + k2 * r2 * r2) / (1.0 + k1 + k2)


## tan(half the source camera's horizontal FOV): large enough that every output pixel's ray is inside the render.
static func source_tan(lens: Dictionary, aspect: float) -> float:
	var need := 0.0
	var steps := 64
	for i in steps + 1:
		var t := float(i) / float(steps)
		# Walk the right edge and the top edge; the picture is symmetric.
		for p in [Vector2(1.0, t / aspect), Vector2(t, 1.0 / aspect)]:
			var r: float = p.length()
			var tn := ray_tan(lens, r)
			var dir: Vector2 = p / r if r > 1e-9 else Vector2.ZERO
			need = maxf(need, maxf(absf(dir.x) * tn, absf(dir.y) * tn * aspect))
	return minf(maxf(need, tan(deg_to_rad(float(lens["hfov_deg"])) * 0.5)), tan(deg_to_rad(MAX_SOURCE_FOV_DEG) * 0.5))


## The horizontal FOV, degrees, the rectilinear source camera must be given.
static func source_fov_deg(lens: Dictionary, aspect: float) -> float:
	return rad_to_deg(atan(source_tan(lens, aspect))) * 2.0


## Where, as a source-camera NDC (x right, y DOWN, each [-1, 1] across the render), the output position p (half-width
## units, y down) is read from. The CPU mirror of src_ndc() in the shader.
static func source_ndc(lens: Dictionary, p: Vector2, aspect: float) -> Vector2:
	var r := p.length()
	if r < 1e-9:
		return Vector2.ZERO
	var dir := p / r
	var st := source_tan(lens, aspect)
	var tn := ray_tan(lens, r)
	return Vector2(dir.x * tn / st, dir.y * tn * aspect / st)


## How far the lens bends the corner relative to a rectilinear lens of the same hfov, as a fraction. 0 for rectilinear.
static func distortion_amount(lens: Dictionary, aspect: float) -> float:
	var rc := Vector2(1.0, 1.0 / aspect).length()
	var rectilinear := tan(deg_to_rad(float(lens["hfov_deg"])) * 0.5) * rc
	return absf(ray_tan(lens, rc) / rectilinear - 1.0)


## Lateral chromatic aberration strength: channel radius scale is 1 +/- ca_scale * r^2.
static func ca_scale(lens: Dictionary, aspect: float) -> float:
	return minf(CA_PER_DISTORTION * distortion_amount(lens, aspect), 0.03)


## Brightness multiplier at output radius r.
static func vignette(r: float) -> float:
	var t := clampf((r - VIGNETTE_START) / (VIGNETTE_END - VIGNETTE_START), 0.0, 1.0)
	var s := t * t * (3.0 - 2.0 * t)
	return 1.0 - VIGNETTE_STRENGTH * s


## The uniform values the shader is fed, for this lens at this aspect.
static func shader_params(lens: Dictionary, aspect: float) -> Dictionary:
	return {
		"fisheye": 1.0 if str(lens["model"]) == "fisheye_equidistant" else 0.0,
		"half_hfov": deg_to_rad(float(lens["hfov_deg"])) * 0.5,
		"k1": float(lens["k1"]),
		"k2": float(lens["k2"]),
		"src_tan": source_tan(lens, aspect),
		"aspect": aspect,
		"ca": ca_scale(lens, aspect),
		"vig": VIGNETTE_STRENGTH,
	}


static var _shader_inset: Shader
static var _shader_screen: Shader


## `screen` true: reads the main viewport's rendered screen (a full-screen ColorRect). False: reads a Control's own TEXTURE
## (the SubViewportContainer showing the inset).
static func shader(screen: bool) -> Shader:
	if screen:
		if _shader_screen == null:
			_shader_screen = Shader.new()
			_shader_screen.code = shader_code(true)
		return _shader_screen
	if _shader_inset == null:
		_shader_inset = Shader.new()
		_shader_inset.code = shader_code(false)
	return _shader_inset


static func shader_code(screen: bool) -> String:
	var decl := "uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;" if screen else ""
	var sampler := "screen_tex" if screen else "TEXTURE"
	return """shader_type canvas_item;
%s
uniform float fisheye = 1.0;
uniform float half_hfov = 1.16;
uniform float k1 = 0.0;
uniform float k2 = 0.0;
uniform float src_tan = 2.0;
uniform float aspect = 1.7777778;
uniform float ca = 0.0;
uniform float vig = 0.3;

const float MAX_THETA = %f;
const float VIG_START = %f;
const float VIG_END = %f;

// tan of the ray angle for an output radius r in half-widths. Mirrors FpvLens.ray_tan.
float ray_tan(float r) {
	if (fisheye > 0.5) {
		return tan(min(r * half_hfov, MAX_THETA));
	}
	float r2 = r * r;
	return tan(half_hfov) * r * (1.0 + k1 * r2 + k2 * r2 * r2) / (1.0 + k1 + k2);
}

// Source-render uv for output position p (half-width units, y down). Mirrors FpvLens.source_ndc.
vec2 src_uv(vec2 p) {
	float r = length(p);
	if (r < 1e-9) { return vec2(0.5); }
	vec2 dir = p / r;
	float tn = ray_tan(r);
	return vec2(0.5 + 0.5 * dir.x * tn / src_tan, 0.5 + 0.5 * dir.y * tn * aspect / src_tan);
}

vec4 fetch_at(sampler2D tex, vec2 uv) {
	vec4 c = textureLod(tex, uv, 0.0);
	// Outside the render (or past 85 deg off axis) the lens sees nothing the camera drew: black.
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	return vec4(c.rgb * inside, 1.0);
}

#define SRC %s

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * 2.0, (UV.y - 0.5) * 2.0 / aspect);
	float r = length(p);
	float r2 = r * r;
	// Lateral chromatic aberration: red reads slightly further out than green, blue slightly further in.
	vec3 col;
	col.r = fetch_at(SRC, src_uv(p * (1.0 + ca * r2))).r;
	col.g = fetch_at(SRC, src_uv(p)).g;
	col.b = fetch_at(SRC, src_uv(p * (1.0 - ca * r2))).b;
	float t = clamp((r - VIG_START) / (VIG_END - VIG_START), 0.0, 1.0);
	col *= 1.0 - vig * t * t * (3.0 - 2.0 * t);
	COLOR = vec4(col, 1.0);
}
""" % [decl, MAX_THETA_RAD, VIGNETTE_START, VIGNETTE_END, sampler]
