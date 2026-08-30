class_name PropellerShelfChip
extends Button
## One blade on the shelf: its planform silhouette, with its name under it.
##
## A `Button` that paints its own diagram, rather than a panel with a click handler, so it gets the
## focus ring, the hover state and the keyboard behaviour every other control in the app has. The
## same shape `FrameLayoutShelf`'s chips take.

var document: PropellerDocument
var caption := ""


func _init(p_document: PropellerDocument = null, p_caption: String = "") -> void:
	document = p_document
	caption = p_caption
	tooltip_text = p_caption
	focus_mode = Control.FOCUS_ALL


func _draw() -> void:
	if document == null:
		return

	var pts := PlanformEdits.points(document.chord)
	if pts.size() < 2:
		return

	var widest := 0.0
	for point in pts:
		widest = maxf(widest, float(point[1]))
	if widest <= 0.0:
		return

	# The silhouette fills the chip's upper two-thirds; the caption owns the rest.
	var body := Rect2(Vector2(8.0, 6.0), Vector2(maxf(size.x - 16.0, 1.0),
		maxf(size.y * 0.62, 1.0)))
	var centre_y := body.position.y + body.size.y * 0.5

	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	for point in pts:
		var x: float = body.position.x + body.size.x * clampf(float(point[0]), 0.0, 1.0)
		var half: float = body.size.y * 0.5 * (float(point[1]) * 0.5) / widest
		upper.append(Vector2(x, centre_y - half))
		lower.append(Vector2(x, centre_y + half))
	var outline := PackedVector2Array(upper)
	for i in range(lower.size() - 1, -1, -1):
		outline.append(lower[i])
	draw_colored_polygon(outline, Color(LothalTheme.ACCENT, 0.35))

	draw_string(ThemeDB.fallback_font, Vector2(8.0, size.y - 8.0), caption,
		HORIZONTAL_ALIGNMENT_LEFT, size.x - 16.0, LothalTheme.FONT_SIZE_SMALL,
		LothalTheme.TEXT_MAIN)
