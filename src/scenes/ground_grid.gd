class_name GroundGrid
extends RefCounted
## Generates the ground's grid texture procedurally. Nothing in Lothal is a canned asset,
## and a grid is the cheapest possible fix for the one thing the first 3D build got wrong:
## against a flat untextured plane there is no optical flow, so a pilot cannot judge
## altitude, speed, or which way they are drifting. The grid is not decoration — it is the
## instrument that makes the drone's motion legible.

const TEXTURE_SIZE := 256
## One texture tile per this many metres of ground.
const METRES_PER_TILE := 2.0

const BASE_COLOR := Color(0.16, 0.18, 0.21)
const LINE_COLOR := Color(0.34, 0.40, 0.47)
const MAJOR_LINE_COLOR := Color(0.52, 0.62, 0.72)

## A tile: base fill, a thin line on two edges, and a brighter line every fourth tile so
## there is a coarser scale to read distance against as well as a fine one.
static func build_texture() -> ImageTexture:
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(BASE_COLOR)

	@warning_ignore("integer_division")
	var line_width := maxi(1, TEXTURE_SIZE / 128)
	for i in TEXTURE_SIZE:
		for w in line_width:
			image.set_pixel(i, w, LINE_COLOR)
			image.set_pixel(w, i, LINE_COLOR)

	return ImageTexture.create_from_image(image)

static func build_material(ground_size_m: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = build_texture()
	material.uv1_scale = Vector3.ONE * (ground_size_m / METRES_PER_TILE)
	material.roughness = 0.95
	# Distant ground is nearly edge-on, where a repeating grid aliases into moire. Anisotropic
	# filtering is what keeps the horizon from shimmering.
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material
