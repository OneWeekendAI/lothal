extends SceneTree
## Dev tool, not a test: drives the prop designer with mouse and key events through Input in a real
## window (PD15). Every press lands wherever the window's hit test sends it, so a covered, zero-sized
## or clipped control fails here where calling its handler would pass.
##
##   godot --path . --script res://tests/capture_prop_input.gd -- <out_prefix> [WxH]
##
## Needs a real window; run with HOME pointed at a scratch directory. Prints PASS/FAIL lines.

var prefix: String
var fails := 0


func _check(what: String, ok: bool, extra: Variant = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, extra])
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(tag: String) -> void:
	await _frames(12)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [prefix, tag])


func _move(at: Vector2, held := false) -> void:
	var m := InputEventMouseMotion.new()
	# Events arrive in window pixels; the layout's 1280x720 is stretched to larger windows.
	var pixel: Vector2 = root.get_final_transform() * at
	m.position = pixel
	m.global_position = pixel
	m.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(m)
	await _frames(2)


func _button(at: Vector2, pressed: bool) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	var pixel: Vector2 = root.get_final_transform() * at
	b.position = pixel
	b.global_position = pixel
	b.pressed = pressed
	b.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(b)
	await _frames(2)


func _click(c: Control) -> void:
	if c == null or not c.is_visible_in_tree():
		_check("clickable", false, c)
		return
	var at := c.get_global_rect().get_center()
	await _move(at)
	var hit := root.gui_get_hovered_control()
	if hit != c and not c.is_ancestor_of(hit):
		_check("hit test reaches %s" % c.name, false, hit)
	await _button(at, true)
	await _button(at, false)
	await _frames(4)


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		Input.parse_input_event(k)
		await _frames(2)


func _type(text: String) -> void:
	for ch in text:
		var k := InputEventKey.new()
		k.unicode = ch.unicode_at(0)
		k.keycode = OS.find_keycode_from_string(ch.to_upper())
		k.pressed = true
		Input.parse_input_event(k)
		await _frames(1)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	prefix = args[0]
	if args.size() > 1:
		var p := args[1].split("x")
		DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
		root.size = Vector2i(int(p[0]), int(p[1]))
	var shell := GlassShell.new()
	root.add_child(shell)
	await _frames(4)
	shell._on_project_action("new")
	shell.class_picker.show_class("five_inch")
	shell.class_picker.choose()
	await _frames(20)
	var ds: DesignSpace = shell.design_space
	ds.shelf.set_open(true)
	ds.shelf.toggle_category("propeller")
	await _frames(10)
	ds.shelf.scroll.scroll_vertical = 100000
	await _frames(10)
	# The shelf's + tile.
	await _click(ds.shelf.find_child("AddProp", true, false) as Control)
	await _frames(6)
	var d: PropDesigner = ds.prop_designer
	_check("+ tile opens the designer", d != null)
	if d == null:
		quit(1)
		return
	await _frames(30)
	# Twist drag: press on a knot, two motions, release.
	var scroll := d.find_child("LeftScroll", true, false) as ScrollContainer
	scroll.ensure_control_visible(d.twist_editor)
	await _frames(6)
	var before := d.twist_editor.table().duplicate()
	var e := d.twist_editor
	var pts := PlanformEdits.points(before)
	var mid: Array = pts[int(pts.size() * 0.5)]
	var from := e.get_global_transform().origin + e.to_pixels(float(mid[0]), rad_to_deg(float(mid[1])))
	var idx := e.station_at(from - e.get_global_transform().origin)
	_check("press lands on a knot", idx >= 0, idx)
	await _move(from)
	await _button(from, true)
	_check("drag begins", e.dragging_station == idx, e.dragging_station)
	await _move(from + Vector2(0, -8), true)
	await _move(from + Vector2(0, -22), true)
	await _button(from + Vector2(0, -22), false)
	await _frames(6)
	var after := d.twist_editor.table()
	_check("twist drag changed the table", after != before, "knot %d" % idx)
	_check("drag ended", e.dragging_station == -1)
	await _shot("twist_dragged")
	# Undo, by its button.
	await _click(d.undo_button)
	_check("Undo button restores", d.twist_editor.table() == before)
	await _click(d.redo_button)
	_check("Redo button reapplies", d.twist_editor.table() == after)
	# Tabs by mouse.
	for tab: Control in _tabs(d):
		await _click(tab)
		print("TAB %s -> %s" % [tab.name, d.active_tab])
		_check("tab %s took" % tab.name, String(tab.name).to_lower().contains(d.active_tab))
		await _shot("tab_%s" % d.active_tab)
	# Type a name, click Save.
	await _click(d.name_field)
	await _type("Inputprop")
	_check("typed name reached the doc", d.doc.name.contains("Inputprop"), d.doc.name)
	await _click(d.save_button)
	await _frames(10)
	_check("save said so", d.status_label.text != "", d.status_label.text)
	await _shot("saved")
	# Esc closes; the shelf shows the saved card.
	await _key(KEY_ESCAPE)
	await _frames(10)
	_check("Esc closed the designer", ds.prop_designer == null)
	ds.shelf.scroll.scroll_vertical = 0
	await _shot("shelf_after_save")
	var card := ds.shelf.find_child("Part_custom_inputprop", true, false)
	if card == null:
		for n in ds.shelf.find_children("Part_custom*", "", true, false):
			card = n
	_check("shelf carries the saved prop by real input", card != null, card)
	# Lab's real door: the Prop panel button.
	shell._close_design_space()
	await _frames(10)
	for i in GlassShell.SYSTEMS.size():
		if str(GlassShell.SYSTEMS[i]["name"]) == "Propulsion":
			shell._select_system(i)
	shell._show_page(SectionRows.rows("Propulsion", shell.lab.current_build())[1])
	await _frames(20)
	await _shot("lab_page")
	var door: Button = shell.lab.propeller_details._design_button
	_check("Lab door visible", door.is_visible_in_tree())
	_check("hidden top-strip door stays hidden", not shell._room_door_glass.visible)
	await _click(door)
	await _frames(10)
	_check("Design this blade opens the designer", shell.prop_designer != null)
	await _shot("from_lab_door")
	await _key(KEY_ESCAPE)
	await _frames(10)
	_check("Esc closes from Lab", shell.prop_designer == null)
	# The finder's authoring button: the rail itself is hidden since the finder replaced it.
	await _key(KEY_ESCAPE)
	await _frames(6)
	var prop_system := shell._focused_index
	for slot in 4:
		if shell._rail_for_system(prop_system, slot) == shell.lab.propeller_picker:
			shell.open_finder(prop_system, slot)
	await _frames(10)
	await _shot("finder")
	var new_door: Control = shell._finder._new_button if shell._finder != null else null
	await _click(new_door)
	await _frames(10)
	_check("finder New opens the designer", shell.prop_designer != null)
	await _shot("from_rail_new")
	print("INPUT fails=%d" % fails)
	quit(1 if fails > 0 else 0)


func _tabs(d: PropDesigner) -> Array[Control]:
	var out: Array[Control] = []
	for n in d.find_children("Tab*", "Button", true, false):
		if (n as Control).is_visible_in_tree():
			out.append(n)
	return out
