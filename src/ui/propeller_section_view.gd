class_name PropellerSectionView
extends Control
## The blade's SECTION at the caret's radius, drawn at scale — propulsion.md §7.1, slice P10d.
##
## ## Why this view exists at all
##
## Chord, thickness and blade angle are three numbers a builder can read off a panel, and reading
## them tells you almost nothing: the question a blade actually raises is what the three of them
## make TOGETHER at 70% radius, and that is a picture. It is also the only view in the room where
## `beta(r)` is visible as an angle rather than as a figure in degrees, which is what makes an
## authored twist table something a builder can check rather than something they have to trust.
##
## ## It draws the document's own section, not a section of its own
##
## Every corner comes from `PropellerDocument.section_corners_mm(r_frac)` — the same four points
## `PropellerMesh` builds its vertices from. That is P10d's rule applied to the last shape that
## still could have been duplicated: chord stopped being defined twice, and the section must not
## become the second copy in its place. So the whole of this file's geometry is one call, a scale
## and a translate, and `test_propeller_section_view.gd` asserts the drawn corners equal the mesh's
## own vertices at the same radius.
##
## ## A `_draw` and not a SubViewport
##
## The design sketch proposed a small SubViewport with a section-only camera, reusing the mesh's
## drawing so the view would be `beta(r)` "for definitely". Extracting `section_corners_mm` reaches
## that guarantee more directly and more cheaply: the two views are the same four points rather
## than two renderings of one mesh. It also keeps the view provable — a SubViewport has no World3D
## until it enters the tree, so every assertion about what it shows would have needed a live scene,
## and the guarantee this file is FOR would have been the one thing left untested.

## The margin around the section, in pixels — room for the chord line's end caps and the caption.
const MARGIN_PX := 18.0

var document: PropellerDocument
var r_frac := 0.7


func _init(p_document: PropellerDocument = null) -> void:
	document = p_document
	custom_minimum_size = Vector2(220, 120)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_document(p_document: PropellerDocument) -> void:
	document = p_document
	queue_redraw()


func set_r_frac(value: float) -> void:
	r_frac = clampf(value, 0.0, 1.0)
	queue_redraw()


## Millimetres per pixel, fitted so the widest station of the whole blade fills the view — NOT the
## chord at this radius. Refitting per radius would rescale the drawing as the caret moved, so a
## tapering blade would look the same width everywhere and the one thing the view is for — how the
## section changes along the blade — would be the one thing it could not show.
func scale_px_per_mm() -> float:
	if document == null:
		return 1.0
	var widest := 0.0
	for point in PlanformEdits.points(document.chord):
		widest = maxf(widest, float(point[1]))
	if widest <= 0.0:
		return 1.0
	var usable := minf(maxf(size.x - MARGIN_PX * 2.0, 1.0), maxf(size.y - MARGIN_PX * 2.0, 1.0))
	return usable / widest


## The section's corners in PIXELS, in the document's own order. Public because it is what the
## tests read: the assertion that this view and the mesh draw one shape is an assertion about
## these points, and rendering is not needed to make it.
func corner_pixels() -> PackedVector2Array:
	var out := PackedVector2Array()
	if document == null:
		return out
	var centre := size * 0.5
	var px_per_mm := scale_px_per_mm()
	for corner in document.section_corners_mm(r_frac):
		# Y DOWN in screen space, so the axial axis is negated: a section pitched nose-up in the
		# model must not read as nose-down on the canvas.
		out.append(centre + Vector2(corner.x, -corner.y) * px_per_mm)
	return out


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), LothalTheme.SURFACE_BASE)
	if document == null:
		return

	var centre := size * 0.5
	# The plane of rotation, so the blade angle is visible as an angle AGAINST something. A pitched
	# rectangle floating on an empty field reads as a rectangle.
	draw_line(Vector2(MARGIN_PX * 0.5, centre.y), Vector2(size.x - MARGIN_PX * 0.5, centre.y),
		LothalTheme.BORDER, 1.0)

	var corners := corner_pixels()
	if corners.size() < 4:
		return
	draw_colored_polygon(corners, Color(LothalTheme.ACCENT, 0.22))
	var outline := PackedVector2Array(corners)
	outline.append(corners[0])
	draw_polyline(outline, LothalTheme.ACCENT, 1.5)

	# The chord LINE — the section's own long axis, from mid-leading-edge to mid-trailing-edge.
	# Drawn from the corners rather than re-derived from beta, so it cannot disagree with the shape
	# it is measuring.
	var leading := (corners[1] + corners[2]) * 0.5
	var trailing := (corners[0] + corners[3]) * 0.5
	draw_line(leading, trailing, LothalTheme.WARNING, 1.0)

	var caption := "r/R %.2f   c %.2f mm   beta %.1f deg   t/c %.0f%%" % [
		r_frac, document.chord_at(r_frac), rad_to_deg(document.beta_rad(r_frac)),
		document.thickness_ratio * 100.0]
	draw_string(ThemeDB.fallback_font, Vector2(MARGIN_PX * 0.5, size.y - 6.0), caption,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, LothalTheme.FONT_SIZE_SMALL, LothalTheme.TEXT_MUTED)
