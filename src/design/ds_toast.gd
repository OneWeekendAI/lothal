class_name DsToast
extends PanelContainer
## A one-line Design Space message that fades by itself: the refusal ("Cannot fly: ...") or a short
## hint. Same box as the file bar's dialogs (`DsUi.panel_style`), ink text, amber when it is a
## refusal. It never takes the mouse. `say` shows it, `message` reads it back (tests, screenshots).

var message := ""
var _label: Label
var _tween: Tween


func _init() -> void:
	name = "DsToast"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := DsUi.panel_style()
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	add_theme_stylebox_override("panel", box)
	_label = DsUi.label("", DsUi.INK, LothalTheme.FONT_SIZE_SMALL)
	add_child(_label)


## Shows `text` for `seconds` (0 keeps it until `clear`). `warn` draws it in the warning amber.
func say(text: String, warn := false, seconds := 5.0) -> void:
	message = text
	_label.text = text
	_label.add_theme_color_override("font_color", DsUi.WARN if warn else DsUi.INK)
	modulate.a = 1.0
	visible = true
	if _tween != null:
		_tween.kill()
		_tween = null
	if seconds > 0.0 and is_inside_tree():
		_tween = create_tween()
		_tween.tween_interval(seconds)
		_tween.tween_property(self, "modulate:a", 0.0, 0.4)
		_tween.tween_callback(clear)


func clear() -> void:
	message = ""
	visible = false
