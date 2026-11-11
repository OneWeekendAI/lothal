class_name PropBladeTab
extends VBoxContainer
## The propeller sheet's Blade tab: the way into the blade designer (planform, twist, section, wind
## tunnel, structure, mount stack) and the home of the blades drawn in the old Propulsion room.
## Those lived in `BladeLibrary` files that nothing in the Design Space listed once the room became
## unreachable; each is listed here and opens in the designer as a new prop.
##
## Pressing a button closes the sheet and opens the designer over the Design Space (the designer
## is a window of its own, with the part's own undo, save and fit).

var ds: DesignSpace
var sheet: PartSheet
var designer_button: Button
## blade id -> its Open button.
var blade_buttons := {}


func _init(p_ds: DesignSpace, p_sheet: PartSheet = null) -> void:
	ds = p_ds
	sheet = p_sheet
	name = "PropBladeTab"
	add_theme_constant_override("separation", LothalTheme.SPACE_3)
	var intro := DsUi.label("Draw the blade: chord and twist along its length, the section, thickness, material and the pad it sits on. The wind tunnel, thrust stand and structure checks are in the designer.", DsUi.INK_MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(420, 0)
	add_child(intro)
	designer_button = DsUi.button("Open the blade designer", false, true)
	designer_button.name = "OpenBladeDesigner"
	designer_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	designer_button.pressed.connect(func(): _open(""))
	add_child(designer_button)
	var entries := BladeLibrary.entries()
	if entries.is_empty():
		return
	add_child(DsUi.section("Blades you drew earlier"))
	for e in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", LothalTheme.SPACE_2)
		var id := String(e["id"])
		var l := DsUi.label("%s   %.1f in, %d blades" % [e["name"], float(e["diameter_mm"]) / PropellerDocument.INCH_TO_MM, int(e["blades"])], DsUi.INK)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := DsUi.button("Open")
		b.name = "Blade_" + id
		var path := String(e["path"])
		b.pressed.connect(func(): _open(path))
		row.add_child(b)
		blade_buttons[id] = b
		row.custom_minimum_size = Vector2(420, 0)
		add_child(row)


func _open(blade_path: String) -> void:
	if sheet != null:
		sheet.close()
	ds.open_prop_designer("", blade_path)
