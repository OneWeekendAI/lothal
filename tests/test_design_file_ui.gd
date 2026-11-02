class_name TestDesignFileUi
extends RefCounted
## The save/open controls of the 5" Design Space (PLAN Section 9, UI half), on the real DesignSpace at
## 1280x720. Every save and open goes through DesignFile and a real file in a scratch folder
## (DesignFile.dir is pointed at user://test_design_file_ui; the real user://designs is never written,
## and a check proves it). Presses are made on the real buttons (pressed.emit) or the DesignSpace
## methods they call; Esc and Cmd+S through _unhandled_key_input with synthesised events.
## One test per case.

const CLASS_ID := "five_inch"
const SIZE := Vector2(1280, 720)
const SCRATCH := "user://test_design_file_ui"
const KEYS := ["auw_g", "thrust_to_weight", "hover_throttle", "flight_time_min", "top_speed_kmh"]


static func _ds(catalog: PartsCatalog) -> DesignSpace:
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), catalog)
	ds.size = SIZE
	ds.rig.aspect = SIZE.x / SIZE.y
	return ds


static func _done(ds: DesignSpace) -> void:
	if ds.get_parent() != null:
		ds.get_parent().remove_child(ds)
	ds.free()


## A swapped pack and a drilled hole, made through the UI paths (choose, the session's drill).
static func _edit(ds: DesignSpace) -> void:
	var cur := String(ds.session.selection["battery"])
	for p in ds._catalog.list_category("battery"):
		var id := String(p["part_id"])
		if id != cur and ds.choose("battery", id)["ok"]:
			break
	var fl := ds.session.plate_of_mesh("frame_arm_FL")
	var axis := AirframeDocument.point_of(ds.session.frame_document().plates[fl]["tip_point"]).normalized()
	ds.session.drill(fl, axis * 91.0, 3.0)
	ds._after_change()


static func _readouts(ds: DesignSpace) -> Array:
	return KEYS.map(func(k): return (ds.value_labels[k] as Label).text)


static func _wipe() -> void:
	var d := DirAccess.open(SCRATCH)
	if d != null:
		for f in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


static func _key(code: int, meta := false, shift := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code as Key
	e.pressed = true
	e.meta_pressed = meta
	e.shift_pressed = shift
	return e


static func _write(file: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	var f := FileAccess.open(SCRATCH + "/" + file, FileAccess.WRITE)
	f.store_string(text)
	f.close()


static func run() -> Array:
	var out: Array = []
	var catalog := PartsCatalog.load_default()
	var real_dir_before := DirAccess.dir_exists_absolute("user://designs")
	var saved_dir := DesignFile.dir
	DesignFile.dir = SCRATCH
	_wipe()

	# --- the controls exist and stay clear of everything else ---
	var ds := _ds(catalog)
	out.append(TestResult.new("the bar has Save, Save as and Open buttons and a name that starts as Untitled",
		ds.file_bar.save_button.text == "Save" and ds.file_bar.save_as_button.text == "Save as"
		and ds.file_bar.open_button.text == "Open" and ds.file_bar.name_label.text == "Untitled", ds.file_bar.name_label.text))
	var panel_r := Rect2(SIZE.x + ds.panel.offset_left, ds.panel.offset_top, ds.panel.offset_right - ds.panel.offset_left,
		maxf(ds.panel.offset_bottom - ds.panel.offset_top, ds.panel.get_combined_minimum_size().y))
	ds.shelf.set_open(true)
	var shelf_r := Rect2(ds.shelf.offset_left, ds.shelf.offset_top, PartsShelf.WIDTH, maxf(ds.shelf.size.y, ds.shelf.get_combined_minimum_size().y))
	ds.select("frame/arm/FL")
	var tool_m := ds.tool_row.get_combined_minimum_size()
	var tool_r := Rect2(ds.tool_row.offset_left, ds.tool_row.offset_top, maxf(ds.tool_row.offset_right - ds.tool_row.offset_left, tool_m.x), maxf(ds.tool_row.size.y, tool_m.y))
	ds.open_open_dialog()
	var rects := ds.file_bar.rects(SIZE)
	var clear := rects.size() == 2
	for r in rects:
		clear = clear and not (r as Rect2).intersects(panel_r) and not (r as Rect2).intersects(shelf_r)
	out.append(TestResult.new("the bar and its open dialog clear the readouts and the shelf at 1280x720", clear, str(rects)))
	var clear_tools := ds.tool_row.visible
	for r in rects:
		clear_tools = clear_tools and not (r as Rect2).intersects(tool_r)
	out.append(TestResult.new("the bar and its open dialog clear the frame tool row at 1280x720", clear_tools, "%s vs %s (tool row visible=%s)" % [rects, tool_r, ds.tool_row.visible]))
	var inside := true
	for r in rects:
		inside = inside and Rect2(Vector2.ZERO, SIZE).encloses(r)
	out.append(TestResult.new("the dialog sits inside the window", inside, str(rects)))
	out.append(TestResult.new("callout labels avoid the dialog while it is open", _contains_all(ds.callout_avoid_rects(), rects), ""))
	var row_end: float = (rects[0] as Rect2).end.y
	out.append(TestResult.new("the dialog hangs just under the bar row", (rects[1] as Rect2).position.y - row_end <= 40.0
		and (rects[1] as Rect2).position.y >= row_end, "%s" % [rects]))
	ds.file_bar.close_dialog()
	out.append(TestResult.new("closing the dialog takes its rect out of the avoid list", not _contains_all(ds.callout_avoid_rects(), [rects[1]]), ""))
	_done(ds)

	ds = _ds(catalog)
	ds.open_open_dialog()
	out.append(TestResult.new("Open with nothing saved says so, plainly",
		ds.file_bar.recent_buttons.size() == 1 and (ds.file_bar.recent_buttons[0] as Label).text == "No saved designs yet.", ""))
	_done(ds)

	# --- Save as, then Save ---
	ds = _ds(catalog)
	_edit(ds)
	ds.file_bar.save_as_button.pressed.emit()
	out.append(TestResult.new("Save as opens the dialog on a name field", ds.file_bar.dialog_open() and ds.file_bar.mode == "save_as"
		and ds.file_bar.name_edit.visible, ds.file_bar.mode))
	ds.file_bar.name_edit.text = "my build"
	ds.file_bar.confirm_button.pressed.emit()
	var path := SCRATCH + "/my build.lothaldesign"
	out.append(TestResult.new("confirming writes the file into the scratch folder", FileAccess.file_exists(path), path))
	out.append(TestResult.new("the dialog closes and the bar shows the design's name",
		not ds.file_bar.dialog_open() and ds.file_bar.name_label.text == "my build" and ds.design_name == "my build", ds.file_bar.name_label.text))
	out.append(TestResult.new("the bar says Saved", ds.file_bar.status_label.text == "Saved", ds.file_bar.status_label.text))
	var first_text := FileAccess.get_file_as_string(path)
	ds.session.set_arm_width(ds.session.plate_of_mesh("frame_arm_FL"), 1.2)
	ds._after_change()
	ds.file_bar.save_button.pressed.emit()
	out.append(TestResult.new("Save on a named design overwrites it without asking",
		not ds.file_bar.dialog_open() and FileAccess.get_file_as_string(path) != first_text, ""))
	out.append(TestResult.new("Save leaves no .tmp behind", not FileAccess.file_exists(path + ".tmp"), ""))
	_done(ds)

	ds = _ds(catalog)
	var before_files := DesignFile.list().size()
	ds.file_bar.save_button.pressed.emit()
	out.append(TestResult.new("Save on an unnamed design opens Save as and writes nothing",
		ds.file_bar.dialog_open() and ds.file_bar.mode == "save_as" and DesignFile.list().size() == before_files, ds.file_bar.mode))
	var r := ds.save_design("   ")
	out.append(TestResult.new("a blank name is not saved under an invented one", not r["ok"] and DesignFile.list().size() == before_files, str(r)))
	_done(ds)

	# --- Cmd+S, Esc ---
	ds = _ds(catalog)
	ds._unhandled_key_input(_key(KEY_S, true))
	out.append(TestResult.new("Cmd+S on an unnamed design opens Save as", ds.file_bar.dialog_open() and ds.file_bar.mode == "save_as", ds.file_bar.mode))
	var dismissed := [false]
	ds.dismissed.connect(func(): dismissed[0] = true)
	ds._unhandled_key_input(_key(KEY_ESCAPE))
	out.append(TestResult.new("Esc closes the dialog and does not leave the Design Space", not ds.file_bar.dialog_open() and not dismissed[0], str(dismissed)))
	ds.save_design("keys")
	var stamp_text := FileAccess.get_file_as_string(SCRATCH + "/keys.lothaldesign")
	ds.session.set_arm_width(ds.session.plate_of_mesh("frame_arm_FL"), 1.1)
	ds._unhandled_key_input(_key(KEY_S, true))
	out.append(TestResult.new("Cmd+S on a named design saves it in place",
		not ds.file_bar.dialog_open() and FileAccess.get_file_as_string(SCRATCH + "/keys.lothaldesign") != stamp_text, ""))
	_done(ds)

	# --- Open: the recent list ---
	_wipe()
	var a := _ds(catalog)
	a.save_design("a older")
	_done(a)
	OS.delay_msec(1100)
	a = _ds(catalog)
	_edit(a)
	a.save_design("z newer")
	var edited_readouts := _readouts(a)
	var edited_sel: Dictionary = a.session.selection.duplicate(true)
	var edited_doc: Variant = JSON.parse_string(JSON.stringify(a.session.frame_document().to_dictionary(), "", true, true))
	var edited_frame_g := float(a.session.build(catalog).frame["mass_g"])
	_done(a)
	ds = _ds(catalog)
	ds.file_bar.open_button.pressed.emit()
	var listed: Array = ds.file_bar.recent_buttons.map(func(b): return String(b.get_meta("file")) if b.has_meta("file") else "")
	out.append(TestResult.new("Open lists the saved designs, newest first", listed == ["z newer.lothaldesign", "a older.lothaldesign"], str(listed)))
	_write("notes.txt", "x")
	ds.open_open_dialog()
	out.append(TestResult.new("Open lists only design files", ds.file_bar.recent_buttons.size() == 2, str(ds.file_bar.recent_buttons.size())))
	for i in 10:
		_write("extra%d.lothaldesign" % i, "{}")
	ds.open_open_dialog()
	out.append(TestResult.new("the recent list is capped", ds.file_bar.recent_buttons.size() == 8, str(ds.file_bar.recent_buttons.size())))
	DirAccess.remove_absolute(SCRATCH + "/notes.txt")
	for i in 10:
		DirAccess.remove_absolute(SCRATCH + "/extra%d.lothaldesign" % i)
	_done(ds)

	# --- Open: an edited build restored ---
	ds = _ds(catalog)
	var home_readouts := _readouts(ds)
	ds.select("part/battery")
	ds.open_slot("battery")
	ds.open_open_dialog()
	var btn: Button = null
	for b in ds.file_bar.recent_buttons:
		if b is Button and String(b.get_meta("file", "")) == "z newer.lothaldesign":
			btn = b
	if btn != null:
		btn.pressed.emit()
	out.append(TestResult.new("opening the file changes the readouts to the saved ones", home_readouts != edited_readouts and _readouts(ds) == edited_readouts,
		"%s vs %s" % [_readouts(ds), edited_readouts]))
	out.append(TestResult.new("every part id is the saved one", ds.session.selection == edited_sel, str(ds.session.selection)))
	out.append(TestResult.new("the frame document is the saved one, element for element",
		JSON.parse_string(JSON.stringify(ds.session.frame_document().to_dictionary(), "", true, true)) == edited_doc, ""))
	out.append(TestResult.new("the flown frame mass is bit for bit the saved one", var_to_str(float(ds.session.build(catalog).frame["mass_g"])) == var_to_str(edited_frame_g), ""))
	out.append(TestResult.new("the drawn pack is the saved pack (not the one from before the open)",
		ds.pack_label_text() == SwapLook.pack_label(catalog.get_part(String(edited_sel["battery"]))) and ds.pack_label_text() != "", ds.pack_label_text()))
	out.append(TestResult.new("the dialog closes, the name shows, the bar says Opened",
		not ds.file_bar.dialog_open() and ds.file_bar.name_label.text == "z newer" and ds.file_bar.status_label.text == "Opened", ds.file_bar.name_label.text))
	out.append(TestResult.new("a loaded design starts with an empty undo history", not ds.session.can_undo() and not ds.session.can_redo(), ""))
	out.append(TestResult.new("the old swap mode and selection are gone after a load", ds.swap_slot == "" and ds.shelf.swap_cats.is_empty() and ds.selected == "", ds.selected))
	ds.save_design()
	out.append(TestResult.new("Save after an open writes back to the same file", DesignFile.list().has("z newer.lothaldesign") and ds.design_name == "z newer", ds.design_name))
	_done(ds)

	# --- Open: refused ---
	ds = _ds(catalog)
	_edit(ds)
	var keep_sel: Dictionary = ds.session.selection.duplicate(true)
	var keep_session := ds.session
	var keep_readouts := _readouts(ds)
	var newer := DesignFile.to_dict(ds.session, "x")
	newer["version"] = DesignFile.VERSION + 5
	_write("future.lothaldesign", JSON.stringify(newer))
	ds.open_open_dialog()
	ds.file_bar.show_status("Opened")
	var res := ds.open_design("future.lothaldesign")
	var expect := DesignFile.load_file(SCRATCH + "/future.lothaldesign", catalog)
	out.append(TestResult.new("a newer file is refused", not res["ok"], str(res)))
	out.append(TestResult.new("a refused open shows DesignFile's one line, unaltered, in the dialog",
		ds.file_bar.reason_label.visible and ds.file_bar.reason_label.text == String(expect["reason"]) and ds.file_bar.reason_label.text.find("\n") == -1
		and ds.file_bar.reason_label.text.contains("newer"), ds.file_bar.reason_label.text))
	out.append(TestResult.new("the refusal is in the warning amber", ds.file_bar.reason_label.get_theme_color("font_color") == LothalTheme.WARNING, ""))
	out.append(TestResult.new("a refused open keeps the dialog open", ds.file_bar.dialog_open(), ""))
	out.append(TestResult.new("a refused open leaves the drone untouched",
		ds.session == keep_session and ds.session.selection == keep_sel and _readouts(ds) == keep_readouts and ds.design_name == "", ""))
	out.append(TestResult.new("a refused open does not leave a stale \"Opened\" on the bar", ds.file_bar.status_label.text == "", ds.file_bar.status_label.text))
	out.append(TestResult.new("a refused open does not rename the design", ds.file_bar.name_label.text == "Untitled", ds.file_bar.name_label.text))
	ds.file_bar.close_dialog()
	out.append(TestResult.new("closing the dialog clears the amber line", not ds.file_bar.reason_label.visible, ""))
	_write("junk.lothaldesign", "not json at all {")
	out.append(TestResult.new("a file that is not JSON is refused, not a crash", not ds.open_design("junk.lothaldesign")["ok"], ""))
	_done(ds)

	# --- the no-battery panel ---
	ds = _ds(catalog)
	ds.select("part/battery")
	ds.remove_selected()
	out.append(TestResult.new("with no battery the panel keeps \"1 issue\" and no label says \"cannot fly\" outside the pin text",
		ds.issues_label.visible and ds.issues_label.text == "1 issue" and ds.panel.find_child("FlightState", true, false) == null, ds.issues_label.text))
	ds.save_design("no battery")
	var nb := DesignFile.load_file(SCRATCH + "/no battery.lothaldesign", catalog)
	out.append(TestResult.new("a drone with no battery saves and opens with no battery", nb["ok"] and String(nb["session"].selection["battery"]) == "", str(nb["reason"])))
	_done(ds)

	# --- isolation ---
	_wipe()
	DesignFile.dir = saved_dir
	out.append(TestResult.new("the real user://designs was not created or written by this suite",
		DirAccess.dir_exists_absolute("user://designs") == real_dir_before, ""))
	return out


static func _contains_all(have: Array, want: Array) -> bool:
	for w in want:
		if not have.has(w):
			return false
	return true
