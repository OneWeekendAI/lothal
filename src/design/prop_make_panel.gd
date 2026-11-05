class_name PropMakePanel
extends VBoxContainer
## The Make it tab: is this prop makeable, and the file and sheet that say how.

var shell: PropDesigner
var figs: Dictionary = {}
var shaft_value: Label
var refusal_label: Label
var result_label: Label
var stl_button: Button
var txt_button: Button
var last: Dictionary = {}
var _stl_dialog: FileDialog
var _txt_dialog: FileDialog

const ROWS := ["thinnest", "bore", "hub", "solid"]
const NAMES := {"thinnest": "Thinnest section", "bore": "Bore", "hub": "Hub", "solid": "STL solid"}


func _init(p_shell: PropDesigner) -> void:
	shell = p_shell
	add_theme_constant_override("separation", LothalTheme.SPACE_2)
	var grid := shell._figure_grid(ROWS, func(k: String) -> String: return NAMES[k], figs, 110.0)
	grid.name = "MakeFigures"
	add_child(grid)
	shaft_value = shell._add_stepper(self, "MakeShaft", "Shaft", "The motor shaft this prop goes on.",
		func(): shell.step_shaft(-PropDesigner.STEP_SHAFT_MM), func(): shell.step_shaft(PropDesigner.STEP_SHAFT_MM), 90.0)
	refusal_label = shell._faint("")
	refusal_label.name = "MakeRefusal"
	refusal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	refusal_label.add_theme_color_override("font_color", DesignSpace.WARN_INK)
	add_child(refusal_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", LothalTheme.SPACE_2)
	stl_button = shell._bar_button("MakeStl", "Export STL", _ask_stl_path, "Hub and blades with the bore, as one file")
	row.add_child(stl_button)
	txt_button = shell._bar_button("MakeTxt", "Save as .txt", _ask_txt_path, "The making sheet as a text file")
	row.add_child(txt_button)
	add_child(row)
	result_label = shell._faint("")
	result_label.name = "MakeResult"
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(result_label)
	var note := shell._faint("Flat section, not an airfoil. Ideal / model.")
	note.name = "MakeNote"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)


func _put(key: String, text: String, tag: String) -> void:
	(figs[key] as Label).text = text
	(figs[key + "_tag"] as Label).text = tag


func refresh() -> void:
	last = PropExport.build(shell.doc, shell.bore_mm())
	_put("thinnest", "%.2f mm" % float(last.thinnest_mm), "at %d %% of radius, needs %.1f mm" % [roundi(float(last.thinnest_r_frac) * 100.0), PropExport.MIN_SECTION_MM])
	_put("bore", "%.2f mm" % shell.bore_mm(), "%.2f mm shaft plus fit%s" % [shell.shaft_mm(), ", shaft assumed" if shell.shaft_is_assumed() else ""])
	shaft_value.text = "%.1f mm" % shell.shaft_mm()
	var makeable := bool(last.ok)
	_put("hub", "%.1f mm" % (float(last.hub_radius_mm) * 2.0), "across")
	var rho := shell.materials.density(shell.doc.material_id)
	_put("solid", "%.2f g" % (float(last.solid_mm3) * rho * 1e-6) if makeable else "–", "with the bore out" if makeable else "")
	refusal_label.text = String(last.reason)
	refusal_label.visible = not makeable
	stl_button.disabled = not makeable


## Writes the STL. True when a file was written. The page says which.
func export_stl(path: String) -> bool:
	var done := PropExport.write(shell.doc, shell.bore_mm(), path)
	if bool(done.ok):
		result_label.text = "Written: %s" % path.get_file()
		result_label.remove_theme_color_override("font_color")
	else:
		result_label.text = String(done.reason)
		result_label.add_theme_color_override("font_color", DesignSpace.WARN_INK)
	return bool(done.ok)


func _file_name() -> String:
	var n := shell.doc.name.strip_edges()
	return (n if n != "" else "prop").to_snake_case()


func _ask_stl_path() -> void:
	if _stl_dialog == null:
		_stl_dialog = _dialog("*.stl ; STL file", func(path: String): export_stl(path))
	_stl_dialog.current_file = "%s.stl" % _file_name()
	_stl_dialog.popup_centered_ratio(0.6)


func _ask_txt_path() -> void:
	if _txt_dialog == null:
		_txt_dialog = _dialog("*.txt ; Text file", func(path: String): shell.save_specs(path))
	_txt_dialog.current_file = "%s.txt" % _file_name()
	_txt_dialog.popup_centered_ratio(0.6)


func _dialog(filter: String, on_path: Callable) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray([filter])
	dialog.file_selected.connect(on_path)
	add_child(dialog)
	return dialog
