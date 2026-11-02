class_name TestDesignShelfUi
extends RefCounted
## Shelf, drag and drop, snap and remove on the 5" (PLAN Section 5), the 3D and UI half: the shelf,
## the drag ghost and lit mount, the refusal beside the cursor, release, drag-off, Delete, the
## "cannot fly" panel; and the Section 5 small fixes (monochrome selected tool button, a legible
## "Not modelled" line, Home clear of the picker and the shelf).
##
## ## The checks that could have passed while proving nothing
##
## - Drag points are made HERE: the screen pixel of a mount's drawn box centre, projected from the
##   GLB node's own box through the camera, never asked of PartSnap or the drag code.
## - The ghost is checked by where it is (its stage box centre near the mount's) and that it is
##   translucent, not only that "a ghost exists".
## - Release is checked against a Build made HERE from the expected selection (readout labels ==
##   format_readout of that Build), and the replaced part must be back on the shelf.
## - Drag-off and Delete go through the real input handlers (_gui_input / _input /
##   _unhandled_key_input) with synthesised events, not through the session.
## - Colours are judged by number: saturation of the selected tool button's fill, border and text,
##   contrast ratio of the "Not modelled" line against the stage background.
## - Home is checked after moving the camera away first, so a Home that did nothing fails too.
## - One test per case (feedback: loop tests hide coverage).

const CLASS_ID := "five_inch"
const SIZE := Vector2(1280, 720)
const DASH := "—"
const KEYS := ["auw_g", "thrust_to_weight", "hover_throttle", "flight_time_min", "top_speed_kmh"]
## Max saturation for "monochrome" (the theme's accent blue is ~0.64).
const MONO_SAT := 0.08
## WCAG AA for small text.
const MIN_CONTRAST := 4.5


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	results.append_array(_test_shelf(catalog))
	results.append_array(_test_ghost_fit(catalog))
	results.append_array(_test_ghost_motor(catalog))
	results.append_array(_test_refused(catalog))
	results.append_array(_test_far_release(catalog))
	results.append_array(_test_release_attaches(catalog))
	results.append_array(_test_drag_off(catalog))
	results.append_array(_test_delete(catalog))
	results.append_array(_test_cannot_fly(catalog))
	results.append_array(_test_tool_button_mono(catalog))
	results.append_array(_test_not_modelled_contrast(catalog))
	results.append_array(_test_home_picker(catalog))
	results.append_array(_test_home_shelf(catalog))
	results.append_array(_test_captions())
	results.append_array(_test_cards(catalog))
	return results


static func _ds(catalog: PartsCatalog) -> DesignSpace:
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), catalog)
	ds.size = SIZE
	ds.rig.aspect = SIZE.x / SIZE.y
	return ds


static func _done(ds: DesignSpace) -> void:
	if ds.get_parent() != null:
		ds.get_parent().remove_child(ds)
	ds.free()


## The screen pixel of GLB node `node_name`'s drawn box centre (as the test knows the model).
static func _px_of_node(ds: DesignSpace, node_name: String) -> Vector2:
	var mi := ds.model.find_child(node_name, true, false) as MeshInstance3D
	var c := PickRegistry._xform_to(mi, ds._stage) * mi.get_aabb().get_center()
	return PickerPlace.to_px(ds.rig.project(c), ds.size)


static func _stage_centre(mi: MeshInstance3D, ds: DesignSpace) -> Vector3:
	return (PickRegistry._xform_to(mi, ds._stage) * mi.get_aabb()).get_center()


## First shelf part of `category` the verdicts call fitting (ok) or not, other than the fitted one.
static func _shelf_part(ds: DesignSpace, category: String, ok: bool) -> String:
	var v := ds._shelf_judge(category)
	for g in ds.session.shelf(ds._catalog):
		if String(g["category"]) != category:
			continue
		for p in g["parts"]:
			if bool(v.get(String(p["id"]), {"ok": true})["ok"]) == ok:
				return String(p["id"])
	return ""


static func _shelf_ids(ds: DesignSpace, category: String) -> Array:
	for g in ds.session.shelf(ds._catalog):
		if String(g["category"]) == category:
			return (g["parts"] as Array).map(func(p): return String(p["id"]))
	return []


## A stylebox as the running app resolves it: the control's own override, else the Design Space's
## theme (LothalTheme). Outside the scene tree Godot does not hand the theme down, so the test walks
## it the same way instead of reading the engine default.
static func _style(c: Control, type: String, item: String) -> StyleBox:
	if c.has_theme_stylebox_override(item):
		return c.get_theme_stylebox(item)
	return LothalTheme.get_theme().get_stylebox(item, type)


static func _colour(c: Control, type: String, item: String) -> Color:
	if c.has_theme_color_override(item):
		return c.get_theme_color(item)
	return LothalTheme.get_theme().get_color(item, type)


static func _sat(c: Color) -> float:
	var hi := maxf(c.r, maxf(c.g, c.b))
	var lo := minf(c.r, minf(c.g, c.b))
	return 0.0 if hi <= 0.0 else (hi - lo) / hi


static func _lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


static func _contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _mouse(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	return e


static func _motion(pos: Vector2, rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.relative = rel
	return e


static func _labels_text(ds: DesignSpace) -> Array:
	return KEYS.map(func(k): return (ds.value_labels[k] as Label).text)


# ---------------------------------------------------------------------------

static func _test_shelf(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	out.append(TestResult.new("the shelf starts collapsed to its Parts header (no rows)",
		not ds.shelf.open and ds.shelf.rows.is_empty() and not ds.shelf.scroll.visible, "open=%s" % ds.shelf.open))
	ds.shelf.set_open(true)
	ds.shelf.toggle_category("motor")
	var rows: Array = ds.shelf.rows.filter(func(r): return String(r["category"]) == "motor")
	var oks: Array = rows.map(func(r): return bool(r["ok"]))
	var first_bad := oks.find(false)
	var sorted := first_bad >= 0 and not oks.slice(first_bad).has(true) and oks.has(true)
	if sorted:
		# The misfits sit under their own "does not fit" line.
		var b0 := rows[first_bad]["button"] as Button
		var prev := ds.shelf.list.get_child(b0.get_index() - 1)
		sorted = prev is Label and (prev as Label).text.begins_with("Does not fit")
	out.append(TestResult.new("an opened category lists the motors that fit this 5\" first, then the ones that do not",
		sorted, "%s" % [oks]))
	var bad: Dictionary = rows[first_bad] if first_bad >= 0 else {}
	out.append(TestResult.new("a motor that does not fit is faint and carries its reason",
		not bad.is_empty() and String(bad["reason"]) != ""
		and (bad["button"] as Button).get_theme_color("font_color") == PartsShelf.INK_FAINT, "%s" % bad.get("reason", "")))
	ds.shelf.toggle_category("battery")
	var cells: Array = ds.shelf.rows.filter(func(r): return String(r["category"]) == "battery") \
		.map(func(r): return int(catalog.get_part(String(r["id"])).get("specs", {}).get("cells", 0)))
	var last_big := -1
	var first_1s := cells.size()
	for i in cells.size():
		if int(cells[i]) >= 4:
			last_big = i
		if int(cells[i]) == 1 and first_1s == cells.size():
			first_1s = i
	out.append(TestResult.new("among packs that mount, every 4S-6S pack is listed before any 1S whoop pack",
		last_big >= 0 and first_1s < cells.size() and last_big < first_1s, "%s" % [cells]))
	_done(ds)
	return out


static func _test_ghost_fit(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	var id := _shelf_part(ds, "battery", true)
	var at := _px_of_node(ds, "battery")
	ds.shelf.set_open(true)
	ds.shelf.toggle_category("battery")
	var row := ds.shelf.row_of(id)
	if not row.is_empty():
		(row["button"] as Button).button_down.emit()
	var v := ds.drag_over(at)
	var ghosts := ds.ghost_nodes()
	out.append(TestResult.new("dragging a fitting pack from the shelf over the drone shows one ghost",
		ds.drag_kind == "shelf" and String(v.get("kind", "")) == "snap" and ghosts.size() == 1, "%s, %d ghosts" % [v.get("kind"), ghosts.size()]))
	var pack := ds.model.find_child("battery", true, false) as MeshInstance3D
	var g: MeshInstance3D = ghosts[0] if ghosts.size() > 0 else null
	var gc := _stage_centre(g, ds) if g != null else Vector3(INF, INF, INF)
	out.append(TestResult.new("the ghost sits on the battery mount (box centres within 15 mm)",
		gc.distance_to(_stage_centre(pack, ds)) < 0.015, "%s vs %s" % [gc, _stage_centre(pack, ds)]))
	var m := (g.material_override as StandardMaterial3D) if g != null else null
	out.append(TestResult.new("the ghost is translucent",
		m != null and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and m.albedo_color.a < 0.6, "%s" % [m.albedo_color if m else Color()]))
	out.append(TestResult.new("the battery mount lights up (outlined) while the ghost shows",
		ds.lit_mounts() == ["part/battery"] and pack.material_overlay != null, "%s" % [ds.lit_mounts()]))
	out.append(TestResult.new("the hint beside the cursor names the target mount",
		ds.drop_hint_text().contains("Battery") and _near(ds, at),
		"'%s' at %s" % [ds.drop_hint_text(), ds.drop_label.position]))
	_done(ds)
	return out


static func _test_ghost_motor(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	var id := _shelf_part(ds, "motor", true)
	ds.begin_shelf_drag(id)
	ds.drag_over(_px_of_node(ds, "motor_FR"))
	out.append(TestResult.new("a fitting motor dragged over a corner ghosts and lights all four motor mounts",
		ds.ghost_nodes().size() == 4 and ds.lit_mounts().size() == 4 and ds.drop_hint_text().contains("Motor"),
		"%d ghosts, %s, '%s'" % [ds.ghost_nodes().size(), ds.lit_mounts(), ds.drop_hint_text()]))
	_done(ds)
	return out


static func _test_refused(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	var id := _shelf_part(ds, "motor", false)
	var reason := String(ds._shelf_judge("motor")[id]["reason"]) if id != "" else ""
	var at := _px_of_node(ds, "motor_FR")
	ds.begin_shelf_drag(id)
	var v := ds.drag_over(at)
	out.append(TestResult.new("a motor that cannot mount on the arm pads shows no ghost and lights nothing",
		id != "" and String(v.get("kind", "")) == "refused" and ds.ghost_nodes().is_empty() and ds.lit_mounts().is_empty(),
		"%s %s" % [id, v.get("kind")]))
	out.append(TestResult.new("its one-line reason shows beside the cursor, in the warning accent",
		ds.drop_hint_text() != "" and ds.drop_hint_text() == reason
		and ds.drop_label.get_theme_color("font_color") == LothalTheme.WARNING
		and _near(ds, at), "'%s'" % ds.drop_hint_text()))
	var lab := Rect2(ds.drop_label.position, ds.drop_label.get_combined_minimum_size())
	out.append(TestResult.new("the reason stays clear of the readouts column",
		lab.end.x <= SIZE.x - PickerPlace.COLUMN_W and lab.position.x >= 0.0, "%s" % lab))
	var before: Dictionary = ds.session.selection.duplicate()
	ds.end_drag(at)
	out.append(TestResult.new("releasing the refused motor changes nothing and clears the hint",
		ds.session.selection == before and not ds.session.can_undo() and ds.drop_hint_text() == "", ""))
	_done(ds)
	return out


static func _test_far_release(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	var id := _shelf_part(ds, "battery", true)
	var before: Dictionary = ds.session.selection.duplicate()
	var shown := _labels_text(ds)
	ds.begin_shelf_drag(id)
	var far := Vector2(1100, 690)
	var v := ds.drag_over(far)
	var ghosted := ds.ghost_nodes().size()
	ds.end_drag(far)
	out.append(TestResult.new("a release far from the drone does nothing (no ghost, no change, no undo step)",
		String(v.get("kind", "")) == "nothing" and ghosted == 0 and ds.session.selection == before
		and not ds.session.can_undo() and _labels_text(ds) == shown and ds.drag_kind == "",
		"%s, %d ghosts" % [v.get("kind"), ghosted]))
	_done(ds)
	return out


static func _test_release_attaches(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	var old := String(ds.session.selection["battery"])
	var id := _shelf_part(ds, "battery", true)
	var shown := _labels_text(ds)
	ds.begin_shelf_drag(id)
	ds.drag_over(_px_of_node(ds, "battery"))
	ds.end_drag(_px_of_node(ds, "battery"))
	out.append(TestResult.new("releasing the fitting pack on the drone fits it", String(ds.session.selection["battery"]) == id,
		"%s" % ds.session.selection["battery"]))
	var sel: Dictionary = ds.session.selection.duplicate()
	var b := TestDesignShelf._direct(catalog, sel)
	var want: Array = []
	if b != null:
		var direct := DesignSession.readouts_of(b)
		want = KEYS.map(func(k): return DesignSpace.format_readout(k, direct))
	out.append(TestResult.new("the readouts update to the new build's own figures",
		b != null and _labels_text(ds) == want and want != shown, "%s vs %s" % [_labels_text(ds), want]))
	out.append(TestResult.new("the replaced pack is back on the shelf and the new one is not",
		_shelf_ids(ds, "battery").has(old) and not _shelf_ids(ds, "battery").has(id), old))
	out.append(TestResult.new("after the drop no ghost or hint is left",
		ds.ghost_nodes().is_empty() and ds.drop_hint_text() == "" and ds.drag_kind == "", ""))
	_done(ds)
	return out


static func _test_drag_off(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	var at := _px_of_node(ds, "camera")
	ds.select("part/camera")
	var old := String(ds.session.selection["camera"])
	# First a carry that ends still over the drone: nothing is removed.
	ds._gui_input(_mouse(at, true))
	var near := at + Vector2(12, 6)
	ds._gui_input(_motion(near, near - at))
	ds._input(_mouse(near, false))
	out.append(TestResult.new("carrying the selected camera and releasing it still over the drone keeps it",
		ds.drag_kind == "" and String(ds.session.selection["camera"]) == old and not ds.session.can_undo(),
		"camera '%s'" % ds.session.selection["camera"]))
	ds._gui_input(_mouse(at, true))
	var mid := at + Vector2(20, 10)
	ds._gui_input(_motion(mid, mid - at))
	var far := Vector2(1100, 690)
	ds._input(_motion(far, far - mid))
	var hint := ds.drop_hint_text()
	ds._input(_mouse(far, false))
	out.append(TestResult.new("dragging the selected camera off the drone and releasing removes it",
		String(ds.session.selection["camera"]) == "" and hint.contains("Remove"), "'%s', camera '%s'" % [hint, ds.session.selection["camera"]]))
	out.append(TestResult.new("the removed camera is back on the shelf and no longer drawn or pickable",
		_shelf_ids(ds, "camera").has(old) and not (ds.model.find_child("camera", true, false) as Node3D).visible
		and not ds.picks.addresses().has("part/camera"), ""))
	_done(ds)
	return out


static func _test_delete(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	ds.select("part/antennas")
	var k := InputEventKey.new()
	k.keycode = KEY_DELETE
	k.pressed = true
	ds._unhandled_key_input(k)
	out.append(TestResult.new("Delete removes the selected part", String(ds.session.selection["antenna"]) == "",
		"antenna '%s'" % ds.session.selection["antenna"]))
	ds.select("frame/plate/bottom")
	var before: Dictionary = ds.session.selection.duplicate()
	ds._unhandled_key_input(k)
	out.append(TestResult.new("Delete on the frame removes nothing", ds.session.selection == before, ""))
	_done(ds)
	return out


static func _test_cannot_fly(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	# A swapped pack first, so its printed label is live when the pack is removed.
	ds.choose("battery", _shelf_part(ds, "battery", true))
	ds.select("part/battery")
	var count_before := ds.issues_label.text
	var r := ds.remove_selected()
	# Owner-approved warnings design: the panel says "1 issue" (amber); the old flight line
	# "no battery: cannot fly" duplicated it and was removed.
	out.append(TestResult.new("with the battery removed the panel reads \"1 issue\" in the warning accent, with no flight line",
		r["ok"] and ds.issues_label.visible and ds.issues_label.text == "1 issue"
		and ds.issues_label.get_theme_color("font_color") == LothalTheme.WARNING and ds.panel.find_child("FlightState", true, false) == null,
		"'%s'" % ds.issues_label.text))
	out.append(TestResult.new("every readout shows a dash, not a zero", _labels_text(ds) == KEYS.map(func(_k): return DASH),
		"%s" % [_labels_text(ds)]))
	var pack := ds.model.find_child("battery", true, false) as MeshInstance3D
	out.append(TestResult.new("apply_look hides the pack, its printed label goes with it, and it cannot be picked",
		not pack.visible and ds.pack_label_text() == "" and not ds.picks.addresses().has("part/battery"),
		"visible=%s label='%s'" % [pack.visible, ds.pack_label_text()]))
	ds.select("part/camera")
	out.append(TestResult.new("the inspector still fills for another part with no build", ds.inspector_lines().size() >= 2,
		"%s" % [ds.inspector_lines()]))
	ds.open_picker("battery")
	var pack_rows: Array = ds.picker_rows().filter(func(row): return String(row["category"]) == "battery")
	out.append(TestResult.new("the battery picker opens on the empty slot and offers packs",
		ds.picker.visible and ds.picker_slot == "battery" and pack_rows.size() >= 2 and pack_rows.size() == ds.picker_rows().size(),
		"%d rows" % ds.picker_rows().size()))
	ds.undo()
	out.append(TestResult.new("undo puts the pack back: the count returns to the seed's and the readouts return",
		ds.issues_label.text == count_before and not _labels_text(ds).has(DASH), "%s" % [_labels_text(ds)]))
	_done(ds)
	return out


static func _test_tool_button_mono(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	ds.select("frame/arm/FL")
	ds.set_frame_tool("drill")
	var b := ds.tool_row.tool_buttons["drill"] as Button
	var worst := 0.0
	var where := ""
	for st in ["pressed", "hover_pressed"]:
		var sb := _style(b, "Button", st) as StyleBoxFlat
		if sb == null:
			worst = 1.0
			where = st + " not flat"
			continue
		for c in [sb.bg_color, sb.border_color]:
			if _sat(c) > worst:
				worst = _sat(c)
				where = st
	for cname in ["font_pressed_color", "font_hover_pressed_color"]:
		if _sat(_colour(b, "Button", cname)) > worst:
			worst = _sat(_colour(b, "Button", cname))
			where = cname
	out.append(TestResult.new("the selected Drill button is monochrome (fill, border and text saturation <= %.2f)" % MONO_SAT,
		b.button_pressed and worst <= MONO_SAT, "%.2f at %s" % [worst, where]))
	var le := ds.tool_row.free_size.get_line_edit()
	var fsb := _style(le, "LineEdit", "focus") as StyleBoxFlat
	out.append(TestResult.new("the free-diameter field's focus ring is monochrome too",
		fsb != null and _sat(fsb.border_color) <= MONO_SAT, "%s" % [fsb.border_color if fsb else Color()]))
	_done(ds)
	return out


static func _test_not_modelled_contrast(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	ds.select("frame/arm/FL")
	var lead := ds.tool_row.tags_box.get_child(0) as Label
	var c := _contrast(_colour(lead, "Label", "font_color"), DesignSpace.STAGE_BG)
	out.append(TestResult.new("the \"Not modelled\" line reads at >= %.1f:1 against the stage" % MIN_CONTRAST,
		lead.text.begins_with("Not modelled") and c >= MIN_CONTRAST, "%.2f:1" % c))
	_done(ds)
	return out


## The hint label sits beside the cursor: its box, grown by 24 px, contains the cursor point.
static func _near(ds: DesignSpace, at: Vector2) -> bool:
	return Rect2(ds.drop_label.position, ds.drop_label.get_combined_minimum_size()).grow(24.0).has_point(at)


static func _overlap(a: Rect2, b: Rect2) -> float:
	var i := a.intersection(b)
	return i.size.x * i.size.y if a.intersects(b) else 0.0


static func _test_home_picker(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	ds.select("part/battery")
	ds.rig.orbit(0.9, 0.2)
	ds.rig.pan(0.3, 0.1)
	ds.rig.snap()
	ds.go_home()
	ds.rig.snap()
	ds.place_picker()
	var drone := ds.drone_screen_rect()
	var pr := Rect2(ds.picker.position, Vector2(maxf(ds.picker.size.x, DesignSpace.PICKER_W), ds.picker.size.y))
	out.append(TestResult.new("Home with the picker open frames the drone clear of the picker (and the right column)",
		ds.picker.visible and _overlap(drone, pr) == 0.0 and drone.end.x <= SIZE.x - PickerPlace.COLUMN_W
		and is_equal_approx(ds.rig.goal_yaw, CameraRig.HOME_YAW),
		"drone %s picker %s" % [drone, pr]))
	_done(ds)
	return out


static func _test_home_shelf(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	ds.shelf.set_open(true)
	ds.rig.pan(-0.3, 0.0)
	ds.rig.snap()
	ds.go_home()
	ds.rig.snap()
	var drone := ds.drone_screen_rect()
	var edge := ds.shelf.offset_left + PartsShelf.WIDTH
	out.append(TestResult.new("Home with the shelf open frames the drone clear of the shelf",
		drone.position.x >= edge and drone.end.x <= SIZE.x - PickerPlace.COLUMN_W, "drone %s, shelf edge %.0f" % [drone, edge]))
	ds.shelf.set_open(false)
	ds.rig.snap()
	var plain := CameraRig.new(ds.rig.radius, ds.rig.height)
	out.append(TestResult.new("closing the shelf gives the plain home view back",
		ds.rig.goal_distance == plain.goal_distance and ds.rig.goal_target.is_equal_approx(plain.goal_target),
		"%f vs %f" % [ds.rig.goal_distance, plain.goal_distance]))
	_done(ds)
	return out


## Hand-written (category, part, expected caption) triples: the expected text is typed here, never
## computed by PartCaption. One generated test per category.
const CAPTION_CASES := [
	["battery", {"specs": {"cells": 4, "mah": 1500.0}}, "4S 1500 mAh"],
	["motor", {"specs": {"stator_diameter_mm": 22, "stator_height_mm": 7, "kv": 1950}}, "2207 1950KV"],
	["propeller", {"specs": {"diameter_inches": 5.1, "pitch_inches": 3.0, "blades": 3}}, "5.1 in 3-blade"],
	["esc", {"specs": {"continuous_a": 45.0, "channels": 4}}, "45 A 4-ch"],
	["flight_controller", {"mounting": {"pattern": "30.5x30.5"}}, "30.5x30.5 mm"],
	["guard", {"specs": {"kind": "bumper", "outer_radius_mm": 72.0}}, "bumper 144 mm"],
	["receiver", {"specs": {"length_mm": 12.0, "width_mm": 8.0, "height_mm": 3.0}}, "12 x 8 mm"],
	["camera", {"specs": {"length_mm": 19.0, "width_mm": 19.0, "height_mm": 20.0}}, "19 x 19 mm"],
	["vtx", {"specs": {"length_mm": 28.5, "width_mm": 22.0, "height_mm": 5.0}}, "28.5 x 22 mm"],
	["antenna", {"specs": {"length_mm": 40.0, "width_mm": 4.0, "height_mm": 4.0}}, "40 x 4 mm"],
]


static func _test_captions() -> Array:
	var out: Array = []
	for c in CAPTION_CASES:
		var got: String = PartCaption.key_spec(c[1], String(c[0]))
		out.append(TestResult.new("the shelf caption for a %s is its one key spec (%s)" % [c[0], c[2]],
			got == String(c[2]), "got '%s'" % got))
	return out


## The shelf shows pictures: a card per part with a drawn picture, the name and the caption, in a grid.
static func _test_cards(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := _ds(catalog)
	ds.shelf.set_open(true)
	for cat in ["battery", "motor", "propeller"]:
		ds.shelf.toggle_category(cat)
	var bad := 0
	var empty_caption := 0
	for r in ds.shelf.rows:
		var b := r["button"] as Button
		var pic := b.find_child("Picture", true, false) as Control
		var cap := b.find_child("Spec", true, false) as Label
		if pic == null or pic.custom_minimum_size.x < 40.0 or pic.get_script() != PartPicture:
			bad += 1
		if cap == null or cap.text == "" or cap.text != String(r["caption"]):
			empty_caption += 1
	out.append(TestResult.new("every shelf row is a card with a drawn picture",
		not ds.shelf.rows.is_empty() and bad == 0, "%d of %d without" % [bad, ds.shelf.rows.size()]))
	out.append(TestResult.new("every shelf card carries its key-spec caption",
		not ds.shelf.rows.is_empty() and empty_caption == 0, "%d without" % empty_caption))
	return out
