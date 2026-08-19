class_name FrameNumbersDrawer
extends VBoxContainer
## The strip under the canvas: what the frame currently weighs and how hard it is to turn, with the
## four detail tabs one click behind it.
##
## ## Why the readouts moved here
##
## They used to be the whole right-hand column, which put the room's only fixed real-estate under
## numbers a builder cannot change, and left the controls that shape a frame with nowhere to live.
## But the numbers are not optional either — they are the reason this room computes anything at
## all, and §0's claim ("widen an arm and the resonance moves") is only visible if something on
## screen moves while you drag. So they became a strip: always showing the four figures that answer
## "is this frame any good" — mass, balance, roll and yaw inertia — with the full tabs available
## but folded away.
##
## ## Why the summary row is four numbers and not five
##
## Each one has to be readable in the half-second between two drags, which is the whole point of
## putting them where the drawing is. Mass is the headline; roll and yaw inertia are what the frame
## does to the tune; and the CG offset is the one that says the frame is WRONG rather than merely
## heavy — a frame whose centre of gravity is off-axis trims itself sideways forever. Everything
## else, including every beam and fastener figure, is behind the toggle.

## The four detail tabs, built here rather than borrowed from Lab's inspector: those belong to the
## fitted aircraft's panel stack, and this drawer describes the frame OPEN IN THE EDITOR. They are
## usually the same frame and they stop being the same the moment anything is drawn.
var structure := StructureDetails.new()
var arms := ArmsDetails.new()
var fasteners := FastenersDetails.new()
var layout := LayoutDetails.new()

var materials := FrameMaterials.load_default()

var _summary: HBoxContainer
var _values: Dictionary = {}
var _toggle: Button
var _tabs: TabContainer
## Rendering four tab-fulls of rows costs real time, and during a drag it is time spent on text
## nobody is reading. The tabs are therefore rendered only while they are open, and marked stale
## while they are not.
var _stale := true
var _document: AirframeDocument


func _init() -> void:
	add_theme_constant_override("separation", 4)

	_summary = HBoxContainer.new()
	_summary.add_theme_constant_override("separation", LothalTheme.SPACE_3)
	add_child(_summary)

	for spec in [
		{"key": "mass", "label": "Mass"},
		{"key": "cg", "label": "CG offset"},
		{"key": "roll", "label": "Roll inertia"},
		{"key": "yaw", "label": "Yaw inertia"},
		{"key": "warnings", "label": "Checks"},
	]:
		_summary.add_child(_stat(str(spec["key"]), str(spec["label"])))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.add_child(spacer)

	_toggle = Button.new()
	_toggle.text = "Details ▾"
	_toggle.toggle_mode = true
	_toggle.tooltip_text = "Structure, arms, fasteners and layout in full"
	_toggle.toggled.connect(_on_toggled)
	_toggle.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	_summary.add_child(_toggle)

	_tabs = TabContainer.new()
	_tabs.visible = false
	_tabs.custom_minimum_size = Vector2(0, 260)
	for panel in [structure, arms, fasteners, layout]:
		_tabs.add_child(panel)
	structure.name = "Structure"
	arms.name = "Arms"
	fasteners.name = "Fasteners"
	layout.name = "Layout"
	add_child(_tabs)


## Points the drawer at a frame. Cheap by design: the summary is one properties computation, and
## the tabs are only rendered if somebody has them open.
func show_document(document: AirframeDocument) -> void:
	_document = document
	if document == null:
		return
	var props := AirframeProperties.compute(document, materials)
	var cg_offset := Vector2(props.cg_m.x, props.cg_m.z).length() * 1000.0

	_set_stat("mass", "%.0f g" % props.total_mass_g())
	# Millimetres off the axis rather than a coordinate triple: the question a builder is asking is
	# "is it centred", and a number that is 0.0 when the answer is yes answers it at a glance.
	_set_stat("cg", "centred" if cg_offset < 0.5 else "%.1f mm off" % cg_offset)
	# Gram·square-metre, because kg·m² of a 5" frame is 0.0003 and a screenful of leading zeros is
	# not a readout. The tab behind this prints both.
	_set_stat("roll", "%.2f g·m²" % (props.roll_inertia_kg_m2() * 1000.0))
	_set_stat("yaw", "%.2f g·m²" % (props.yaw_inertia_kg_m2() * 1000.0))

	var warnings := FrameWarnings.of(document, props)
	_set_stat("warnings", "all clear" if warnings.is_empty()
		else "%d to look at" % warnings.size())
	var checks := _values["warnings"] as Label
	checks.add_theme_color_override("font_color",
		LothalTheme.TEXT_MAIN if warnings.is_empty() else LothalTheme.WARNING)

	_stale = true
	if _tabs.visible:
		_render_tabs()


func _on_toggled(open: bool) -> void:
	_tabs.visible = open
	_toggle.text = "Details ▴" if open else "Details ▾"
	if open:
		_render_tabs()


func _render_tabs() -> void:
	if not _stale or _document == null:
		return
	structure.render(_document)
	arms.render(_document)
	fasteners.render(_document)
	layout.render(_document)
	_stale = false


func _stat(key: String, label_text: String) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	var caption := Label.new()
	caption.text = label_text
	caption.theme_type_variation = &"SmallLabel"
	caption.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	column.add_child(caption)
	var value := Label.new()
	value.text = "—"
	column.add_child(value)
	_values[key] = value
	return column


func _set_stat(key: String, text: String) -> void:
	if _values.has(key):
		(_values[key] as Label).text = text


## The summary as text, for the capture tooling and the tests — a drawer that renders is not the
## same claim as a drawer that renders the right numbers, and only this can be asserted headless.
func summary_text() -> String:
	var out := PackedStringArray()
	for key in ["mass", "cg", "roll", "yaw", "warnings"]:
		out.append((_values[key] as Label).text)
	return " · ".join(out)
