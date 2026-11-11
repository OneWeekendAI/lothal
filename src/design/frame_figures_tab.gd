class_name FrameFiguresTab
extends HBoxContainer
## One of the frame sheet's reading tabs: Numbers (mass from geometry, centre of gravity, inertia),
## Arms (beam, first mode, strength), Hardware (screws, standoffs, straps and the battery pad) and
## Layout (motor positions and control effectiveness). The panels are the old Setup pages' own
## classes (StructureDetails, ArmsDetails, FastenersDetails + StrapsDetails, LayoutDetails), so the
## text is the same text; what is new is that they are read off the DESIGN's frame document and
## re-render whenever the design changes, so a plate drawn on the Shape tab moves them at once.

const KINDS := {
	"numbers": ["structure"],
	"arms": ["arms"],
	"hardware": ["fasteners", "straps"],
	"layout": ["layout"],
}

var ds: DesignSpace
var kind := ""
## panel kind -> the panel node.
var panels := {}
var renders := 0
const MIN_W := 380.0
const MAX_W := 820.0


func _init(p_ds: DesignSpace, p_kind: String) -> void:
	ds = p_ds
	kind = p_kind
	name = "FiguresTab_" + kind
	add_theme_constant_override("separation", LothalTheme.SPACE_4)
	for k in KINDS[kind]:
		var panel: Control
		match k:
			"structure": panel = StructureDetails.new()
			"arms": panel = ArmsDetails.new()
			"fasteners": panel = FastenersDetails.new()
			"straps": panel = StrapsDetails.new()
			"layout": panel = LayoutDetails.new()
		panel.custom_minimum_size = Vector2(380, 0)
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panels[k] = panel
		add_child(panel)
	ds.session.changed.connect(refresh)
	refresh()


## The frame document these figures read: the design's own, else the fitted catalogue frame's.
func document() -> AirframeDocument:
	var doc := ds.session.frame_document()
	if doc != null and ds.session.frame_editable():
		return doc
	var frame: Dictionary = ds._catalog.get_part(String(ds.session.selection.get("frame", "")))
	return AirframeDocument.from_catalog_frame(frame) if not frame.is_empty() else null


func refresh() -> void:
	var doc := document()
	for k in panels:
		if k == "straps":
			var build := ds.session.build(ds._catalog)
			(panels[k] as StrapsDetails).render_straps(doc, StrapsPads.figures(build, doc) if build != null else {})
		else:
			panels[k].render(doc)
	renders += 1
	# The rows are measured after they are drawn: ask again next frame, so a long value is not clipped.
	_fit_widths.call_deferred()
	if is_inside_tree():
		get_tree().create_timer(0.1).timeout.connect(_fit_widths)


## Each panel as wide as its rows want (the panel scrolls sideways only past the cap).
func _fit_widths() -> void:
	if not is_inside_tree():
		return
	for k in panels:
		var panel: SpecPanel = panels[k]
		# A value too long for its panel wraps onto a second line (sideways scrolling is off: the theme draws no bar).
		panel._scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var share := (size.x - 12.0 * panels.size()) / maxf(1.0, float(panels.size()))
		panel.custom_minimum_size.x = clampf(panel.content_width(), MIN_W, maxf(MIN_W, minf(MAX_W, share)))


func _exit_tree() -> void:
	if ds != null and ds.session.changed.is_connected(refresh):
		ds.session.changed.disconnect(refresh)
