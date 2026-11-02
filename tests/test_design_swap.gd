class_name TestDesignSwap
extends RefCounted
## Click to swap, in place, on the 5" (PLAN Section 3).
##
## ## The checks that could have passed while proving nothing
##
## - ONE GENERATED TEST PER SLOT AND PART. Each one clicks that part's card in the real side panel and
##   compares the panel's labels with a `Build.from_ids` the test makes ITSELF from the selection it
##   expects, not with the session's own figures (which would agree with anything the session did).
## - Before each case the session is put back to the default WITHOUT a refresh, so the labels still
##   show the previous case's drone: a swap that forgot to refresh, or refreshed before it changed
##   the selection, shows the wrong numbers and fails ("lags one swap behind").
## - Whether a case is refused is decided by the test from the direct build's own impossible
##   warnings, so a picker that refused nothing, or everything, fails the cases it got wrong.
## - The known misfits are found in the catalog, not hard-coded, and the test fails if none exists.
## - A refused card is clicked through the stage's own `click_card` AND released on its button through
##   `end_drag` (the live path), so a panel that only dimmed a misfit, without refusing it, fails.

const CLASS_ID := "five_inch"
const HARD := [&"motor_mount", &"prop_clearance", &"stack_mount", &"fc_stack_mount"]
const KEYS := ["auw_g", "thrust_to_weight", "hover_throttle", "flight_time_min", "top_speed_kmh"]


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), catalog)
	ds.size = Vector2(1280, 720)
	ds.rig.aspect = 1280.0 / 720.0
	var home: Dictionary = ds.session.selection.duplicate(true)
	results.append_array(_test_slots_cover_categories(ds))
	for slot in PartSwap.SLOTS:
		for cat in PartSwap.SLOTS[slot]:
			var ids: Array = [""] if PartSwap.can_be_empty(String(cat)) else []
			for part in catalog.list_category(String(cat)):
				ids.append(String(part["part_id"]))
			for id in ids:
				results.append(_test_case(ds, catalog, home, String(slot), String(cat), String(id)))
	_reset(ds, home)
	results.append_array(_test_known_misfits(ds, catalog, home))
	_reset(ds, home)
	results.append_array(_test_two_swaps_in_a_row(ds, catalog, home))
	_reset(ds, home)
	results.append_array(_test_preview(ds, catalog, home))
	_reset(ds, home)
	results.append_array(_test_undo_redo(ds, catalog, home))
	_reset(ds, home)
	results.append_array(_test_picker_beside_part(ds, catalog))
	_reset(ds, home)
	results.append_array(_test_warnings_shown(ds, catalog, home))
	_reset(ds, home)
	results.append_array(_test_part_redrawn(ds, catalog, home))
	_reset(ds, home)
	results.append_array(_test_motor_outline(ds))
	ds.free()
	return results


static func _reset(ds: DesignSpace, home: Dictionary) -> void:
	ds.session.selection = home.duplicate(true)
	ds.session._undo.clear()
	ds.session._redo.clear()
	ds.refresh()
	ds.apply_look()


## The build the test expects, made directly from ids (not through the session or Project).
static func _direct(catalog: PartsCatalog, sel: Dictionary) -> Build:
	var comps := {}
	for c in Build.OPTIONAL_COMPONENTS:
		comps[c] = String(sel.get(c, ""))
	return Build.from_ids(catalog, String(sel["frame"]), String(sel["motor"]),
		String(sel["propeller"]), String(sel["battery"]), String(sel["esc"]),
		String(sel["flight_controller"]), comps, null, String(sel.get("guard", "")), {},
		String(sel.get("mount", "")))


static func _labels(ds: DesignSpace) -> Dictionary:
	var out := {}
	for k in KEYS:
		out[k] = (ds.value_labels[k] as Label).text
	return out


static func _want_labels(b: Build) -> Dictionary:
	var r := DesignSession.readouts_of(b)
	var out := {}
	for k in KEYS:
		out[k] = DesignSpace.format_readout(k, r)
	return out


static func _hard(b: Build) -> Array:
	return b.warnings().filter(func(w): return w.severity == BuildWarning.Severity.IMPOSSIBLE and HARD.has(w.id))


## The shelf's cards for the selected slot, misfits shown (they are hidden by default).
static func _open(ds: DesignSpace, slot: String) -> void:
	ds.open_slot(slot)
	for cat in PartSwap.SLOTS[slot]:
		ds.shelf.set_show_misfits(String(cat), true)


static func _row_index(ds: DesignSpace, cat: String, id: String) -> int:
	var rows := ds.shelf.rows
	for i in rows.size():
		if String(rows[i]["category"]) == cat and String(rows[i]["id"]) == id:
			return i
	return -1


## Whether the card is drawn dimmed: its name in the faint ink.
static func _dimmed(row: Dictionary) -> bool:
	var name := ((row["button"] as Button).get_child(0) as Control).get_node("Name") as Label
	return name.get_theme_color("font_color") == PartsShelf.INK_FAINT


static func _test_slots_cover_categories(ds: DesignSpace) -> Array:
	var results: Array = []
	var cats: Array = []
	for slot in PartSwap.SLOTS:
		cats.append_array(PartSwap.SLOTS[slot])
		results.append(TestResult.new("the 5\" has a pick address for the %s slot" % slot,
			ds.picks.addresses().any(func(a): return PartSwap.slot_of(String(a)) == slot), ""))
	var want := ["battery", "motor", "propeller", "flight_controller", "esc", "camera", "vtx",
		"antenna", "receiver", "guard"]
	var missing := want.filter(func(c): return not cats.has(c))
	results.append(TestResult.new("every swappable category (PLAN Section 3's list) has a picker",
		missing.is_empty(), str(missing)))
	return results


## One swap: press the row; applied cases must show exactly the direct build, refused cases must
## leave everything as it was.
static func _test_case(ds: DesignSpace, catalog: PartsCatalog, home: Dictionary, slot: String,
		cat: String, id: String) -> TestResult:
	var name := "swap %s / %s -> %s" % [slot, cat, id if id != "" else "(not fitted)"]
	# Back to the default without a refresh: the labels keep the previous case's drone.
	ds.session.selection = home.duplicate(true)
	ds.session._undo.clear()
	ds.session._redo.clear()
	_open(ds, slot)
	var i := _row_index(ds, cat, id)
	if i < 0:
		return TestResult.new(name, false, "no card in the panel")
	var want_sel := home.duplicate(true)
	want_sel[cat] = id
	var direct := _direct(catalog, want_sel)
	var refuse := direct == null or not _hard(direct).is_empty()
	var before := _labels(ds)
	var v := ds.click_card(cat, id)
	if refuse:
		var ok: bool = not v["ok"] and ds.session.selection == home and _labels(ds) == before \
			and String(v["reason"]) != "" and not ds.session.can_undo()
		return TestResult.new(name + " is refused and changes nothing", ok,
			"verdict %s, selection changed %s" % [v, ds.session.selection != home])
	var got := ds.session.readouts(catalog)
	var want_r := DesignSession.readouts_of(direct)
	var same := got.size() == want_r.size()
	for k in KEYS:
		same = same and is_equal_approx(float(got[k]), float(want_r[k])) or (is_nan(float(got[k])) and is_nan(float(want_r[k])))
	var labels_ok := _labels(ds) == _want_labels(direct)
	return TestResult.new(name + " shows a direct Build.from_ids of that selection",
		v["ok"] and ds.session.selection == want_sel and same and labels_ok,
		"verdict ok=%s labels %s want %s" % [v["ok"], _labels(ds), _want_labels(direct)])


static func _test_known_misfits(ds: DesignSpace, catalog: PartsCatalog, home: Dictionary) -> Array:
	var results: Array = []
	var frame := catalog.get_part(String(home["frame"]))
	var pad := String(frame["specs"].get("motor_mount", ""))
	var max_in := float(frame["specs"].get("max_prop_inches", 0.0))
	var motor := {}
	for m in catalog.list_category("motor"):
		if String(m.get("mount_pattern", "")) != pad and String(m.get("mount_pattern", "")) != "":
			motor = m
			break
	var prop := {}
	for p in catalog.list_category("propeller"):
		if float(p["specs"]["diameter_inches"]) > max_in:
			prop = p
			break
	results.append(TestResult.new("the catalog has a motor whose bolt pattern is not the 5\" arm pad's",
		not motor.is_empty(), "pad %s" % pad))
	results.append(TestResult.new("and a prop larger than the frame's %.1f\" maximum" % max_in,
		not prop.is_empty(), ""))
	if motor.is_empty() or prop.is_empty():
		return results
	for case in [["motor", "motor", motor, [String(motor["mount_pattern"]), pad]],
			["prop", "propeller", prop, [String(prop["name"]), "%.1f" % max_in]]]:
		var slot := String(case[0])
		var cat := String(case[1])
		var part: Dictionary = case[2]
		var sides: Array = case[3]
		_open(ds, slot)
		var i := _row_index(ds, cat, String(part["part_id"]))
		var row: Dictionary = ds.shelf.rows[i] if i >= 0 else {}
		var before := _labels(ds)
		var reason := String(row.get("reason", ""))
		var names_both: bool = sides.all(func(s): return reason.contains(String(s)))
		results.append(TestResult.new("%s (%s) is listed dimmed, its reason naming both sides, on the card itself" % [part["name"], cat],
			i >= 0 and _dimmed(row) and not row["ok"] and names_both
			and row["reason_label"] != null and (row["reason_label"] as Label).text == reason
			and (row["reason_label"] as Label).visible,
			"reason '%s', wants %s" % [reason, sides]))
		var direct := _direct(catalog, home.merged({cat: part["part_id"]}, true))
		var first := PartSwap.first_sentence(_hard(direct)[0].message) if not _hard(direct).is_empty() else "?"
		results.append(TestResult.new("and the reason is the blocking warning's first sentence, word for word",
			reason == first, "'%s' vs '%s'" % [reason, first]))
		var live := {}
		if i >= 0:
			# The live path: pressed on the card, released on it.
			var b := row["button"] as Button
			b.position = Vector2(10, 10)
			b.size = Vector2(60, 60)
			ds.begin_shelf_drag(String(part["part_id"]))
			live = ds.end_drag(b.get_global_rect().get_center())
		var v := ds.choose(cat, String(part["part_id"]))
		results.append(TestResult.new("clicking it, or choosing it directly, applies nothing",
			not v["ok"] and ds.session.selection == home and _labels(ds) == before
			and not ds.session.can_undo() and not bool(live.get("ok", false)), str(v)))
	return results


static func _test_two_swaps_in_a_row(ds: DesignSpace, catalog: PartsCatalog, home: Dictionary) -> Array:
	var results: Array = []
	var sel := home.duplicate(true)
	for id in ["battery_6s_1300", "battery_4s_1300"]:
		_open(ds, "battery")
		ds.click_card("battery", id)
		sel["battery"] = id
		results.append(TestResult.new("after swapping to %s the readouts are that drone's, not the last one's" % id,
			_labels(ds) == _want_labels(_direct(catalog, sel)), str(_labels(ds))))
	return results


static func _test_preview(ds: DesignSpace, catalog: PartsCatalog, home: Dictionary) -> Array:
	var results: Array = []
	_open(ds, "battery")
	var shown := ds.hover_card("battery", "battery_6s_1300")
	var now := DesignSession.readouts_of(_direct(catalog, home))
	var then := DesignSession.readouts_of(_direct(catalog, home.merged({"battery": "battery_6s_1300"}, true)))
	var ok := shown.size() == KEYS.size()
	var texts: Array = []
	for k in KEYS:
		var d := float(then[k]) - float(now[k])
		var l := ds.delta_labels[k] as Label
		texts.append(l.text)
		ok = ok and l.visible and l.text == DesignSpace.format_delta(k, d)
	results.append(TestResult.new("hovering a pack shows each readout's signed change from a direct build",
		ok, str(texts)))
	var bar := ds.delta_bars["auw_g"] as ColorRect
	var d_auw := float(then["auw_g"]) - float(now["auw_g"])
	var grows_right := bar.position.x >= DesignSpace.DELTA_TRACK_W * 0.5 - 0.01
	results.append(TestResult.new("with a bar on the side of its sign, sized by the change",
		bar.size.x > 1.0 and grows_right == (d_auw > 0.0), "w %.1f x %.1f d %.1f" % [bar.size.x, bar.position.x, d_auw]))
	results.append(TestResult.new("hovering changes nothing: same selection, same readouts",
		ds.session.selection == home and _labels(ds) == _want_labels(_direct(catalog, home)), ""))
	results.append(TestResult.new("while previewing, the fitted drone's issue count and marks step aside",
		not ds.issues_label.visible and not (ds.mark_buttons["thrust_to_weight"] as Button).visible, ""))
	ds.clear_preview()
	results.append(TestResult.new("leaving the card hides the deltas",
		not (ds.delta_labels["auw_g"] as Label).visible, ""))
	results.append(TestResult.new("and brings the issue count and the T:W mark back",
		ds.issues_label.visible and (ds.mark_buttons["thrust_to_weight"] as Button).visible, ""))
	_open(ds, "motor")
	var bad: Array = ds.shelf.rows.filter(func(r): return not r["ok"])
	var none := bad.is_empty() or ds.hover_card(String(bad[0]["category"]), String(bad[0]["id"])).is_empty()
	results.append(TestResult.new("hovering a refused card previews nothing",
		not bad.is_empty() and none and not (ds.delta_labels["auw_g"] as Label).visible, ""))
	# preview() judges on its own too, not only through the row's disabled flag.
	var direct := {} if bad.is_empty() else ds.preview(String(bad[0]["category"]), String(bad[0]["id"]))
	results.append(TestResult.new("previewing a refused part directly shows nothing",
		not bad.is_empty() and direct.is_empty() and not (ds.delta_labels["auw_g"] as Label).visible,
		str(direct.keys())))
	return results


static func _key(code: Key, shift := false) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.ctrl_pressed = true
	k.shift_pressed = shift
	return k


static func _test_undo_redo(ds: DesignSpace, catalog: PartsCatalog, home: Dictionary) -> Array:
	var results: Array = []
	ds.choose("battery", "battery_6s_1300")
	var one := ds.session.selection.duplicate(true)
	var mot := ""
	for m in catalog.list_category("motor"):
		if String(m["part_id"]) != String(home["motor"]) and PartSwap.judge(ds.session, catalog, "motor", String(m["part_id"]))["ok"]:
			mot = String(m["part_id"])
			break
	ds.choose("motor", mot)
	var two := ds.session.selection.duplicate(true)
	ds._unhandled_key_input(_key(KEY_Z))
	results.append(TestResult.new("Ctrl+Z undoes the last swap, readouts included",
		ds.session.selection == one and _labels(ds) == _want_labels(_direct(catalog, one)), str(_labels(ds))))
	ds.undo()
	results.append(TestResult.new("and again goes back to the default drone",
		ds.session.selection == home and _labels(ds) == _want_labels(_direct(catalog, home)) and not ds.session.can_undo(), ""))
	ds._unhandled_key_input(_key(KEY_Z, true))
	results.append(TestResult.new("Ctrl+Shift+Z redoes it",
		ds.session.selection == one and _labels(ds) == _want_labels(_direct(catalog, one)), ""))
	ds.redo()
	results.append(TestResult.new("and redo again reaches the second swap", ds.session.selection == two, ""))
	ds.undo()
	ds.choose("battery", "battery_4s_1300")
	results.append(TestResult.new("a new swap after an undo clears the redo stack",
		not ds.session.can_redo() and not ds.redo(), ""))
	var refused := ds.choose("propeller", "prop_7x4x3")
	results.append(TestResult.new("a refused swap adds no undo step",
		refused["ok"] == false and ds.undo() and ds.session.selection == one, str(refused)))
	return results


static func _test_picker_beside_part(ds: DesignSpace, catalog: PartsCatalog) -> Array:
	var results: Array = []
	ds.shelf.set_open(false)
	ds.select("part/battery")
	ds.shelf.set_show_misfits("battery", true)
	var rows := ds.shelf.rows
	var packs := catalog.list_category("battery")
	results.append(TestResult.new("selecting the battery opens the Parts panel on every catalog pack, and only on packs",
		ds.shelf.open and ds.swap_slot == "battery" and rows.size() == packs.size()
		and ds.shelf.expanded == {"battery": true}, "%d rows, %d packs, %s" % [rows.size(), packs.size(), ds.shelf.expanded]))
	var fitted := rows.filter(func(x): return x["fitted"])
	results.append(TestResult.new("exactly one card is the fitted pack, and it says so",
		fitted.size() == 1 and String(fitted[0]["id"]) == String(ds.session.selection["battery"])
		and (fitted[0]["button"] as Button).find_child("Fitted", false, false) != null
		and ((fitted[0]["button"] as Button).find_child("Fitted", false, false) as Label).text == "FITTED", ""))
	var p := catalog.get_part("battery_6s_1300")
	var row: Dictionary = rows[_row_index(ds, "battery", "battery_6s_1300")]
	var col := (row["button"] as Button).get_child(0) as Control
	var name_label := col.get_node("Name") as Label
	var spec_label := col.get_node("Spec") as Label
	results.append(TestResult.new("a card names the part with one key spec under it",
		name_label.text == String(p["name"]) and spec_label.text == PartCaption.for_card(p, "battery", String(p["name"]))
		and spec_label.text != name_label.text and spec_label.text != "", spec_label.text))
	ds.select("part/stack")
	var cats := {}
	for x in ds.shelf.rows:
		cats[x["category"]] = true
	results.append(TestResult.new("the stack opens flight controllers, ESCs and receivers, and collapses the battery",
		ds.shelf.expanded == {"flight_controller": true, "esc": true, "receiver": true}
		and cats.has("flight_controller") and cats.has("esc") and cats.has("receiver") and not cats.has("battery"),
		str(ds.shelf.expanded)))
	ds.select("frame/plate/top")
	results.append(TestResult.new("selecting a frame region stops swapping (no slot, no fitted mark)",
		ds.swap_slot == "" and ds.shelf.swap_cats.is_empty() and ds.shelf.rows.all(func(r): return not r["fitted"]), ""))
	ds.select("part/motor/FL")
	ds.clear_selection()
	results.append(TestResult.new("clearing the selection stops it too, and a click on a card then swaps nothing",
		ds.swap_slot == "" and ds.click_card("motor", String(ds.session.selection["motor"])).is_empty(), ""))
	return results


static func _test_warnings_shown(ds: DesignSpace, catalog: PartsCatalog, home: Dictionary) -> Array:
	var results: Array = []
	var v := ds.choose("battery", "battery_1s_300")
	var direct := _direct(catalog, home.merged({"battery": "battery_1s_300"}, true))
	var longs: Array = []
	for w in BuildWarning.by_severity(direct.warnings()):
		if w.severity != BuildWarning.Severity.CHARACTERISTIC:
			longs.append(w.message)
	results.append(TestResult.new("a pack that cannot lift the 5\" is applied, not refused (only hard misfits refuse)",
		v["ok"] and ds.session.selection["battery"] == "battery_1s_300", str(v.get("reason", ""))))
	# Section 8: the panel counts them; each pin opens its sentence, word for word, in the inspector.
	results.append(TestResult.new("and the panel counts its warnings in the warning accent",
		not longs.is_empty() and ds.issues_label.text == WarningPins.count_text(longs.size())
		and ds.issues_label.get_theme_color("font_color") == LothalTheme.WARNING,
		"'%s' vs %d" % [ds.issues_label.text, longs.size()]))
	var opened: Array = []
	for p in ds.warning_pins:
		ds.open_warning([String(p["id"])])
		opened.append(ds.inspector_lines().back() if not ds.inspector_lines().is_empty() else "")
	results.append(TestResult.new("and each one's pin opens its sentence word for word", opened == longs,
		"%s vs %s" % [opened, longs]))
	_reset(ds, home)
	var home_n := 0
	for w in _direct(catalog, home).warnings():
		if w.severity != BuildWarning.Severity.CHARACTERISTIC:
			home_n += 1
	results.append(TestResult.new("back on the default 5\" the count is its own warnings', not the last pack's",
		ds.issues_label.text == WarningPins.count_text(home_n), "'%s' vs %d" % [ds.issues_label.text, home_n]))
	return results


static func _wrap_box(ds: DesignSpace) -> AABB:
	var node := ds._look_nodes["battery"] as MeshInstance3D
	var ext := DesignSpace._wrap_extent_y(node.mesh)
	var box := AABB()
	var first := true
	for i in node.mesh.get_surface_count():
		var mat := node.mesh.surface_get_material(i)
		if mat == null or not String(mat.resource_name).begins_with("lipo_"):
			continue
		for v in node.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
			var w := node.transform * (v as Vector3)
			if first:
				box = AABB(w, Vector3.ZERO)
				first = false
			else:
				box = box.expand(w)
	return box if ext.x < ext.y else AABB()


static func _test_part_redrawn(ds: DesignSpace, catalog: PartsCatalog, home: Dictionary) -> Array:
	var results: Array = []
	var before := _wrap_box(ds)
	var pick_before := ds.picks.box_of("part/battery")
	var drawn_size := Build.battery_size_of(catalog.get_part(String(home["battery"])))
	ds.choose("battery", "battery_6s_1300")
	var after := _wrap_box(ds)
	# Laid flat, as build_drone.py draws every pack (larger section dimension across).
	var raw := Build.battery_size_of(catalog.get_part("battery_6s_1300"))
	var want := Vector3(maxf(raw.x, raw.y), minf(raw.x, raw.y), raw.z)
	# The drawn pack matches its catalogue size within 2 mm (TestClassPicker); the swapped one must
	# match the new pack's within the same 2 mm, and the change must be the catalogue's change.
	var err := (after.size - want).abs()
	results.append(TestResult.new("a swapped pack is drawn at the new pack's catalog size (within 2 mm)",
		err.x < 0.002 and err.y < 0.002 and err.z < 0.002 and (after.size - before.size).length() > 0.001,
		"drawn %s want %s (was %s, drawn seed %s)" % [after.size * 1000.0, want * 1000.0, before.size * 1000.0, drawn_size * 1000.0]))
	results.append(TestResult.new("and still sits on its pad (underside unmoved)",
		absf(after.position.y - before.position.y) < 0.0002, "%.4f vs %.4f" % [after.position.y, before.position.y]))
	results.append(TestResult.new("the pick shape moved with it",
		not ds.picks.box_of("part/battery").is_equal_approx(pick_before), ""))
	results.append(TestResult.new("and the pack wears its own figures, not the drawn print",
		ds.pack_label_text() == "6S 1300 MAH %dC" % int(catalog.get_part("battery_6s_1300")["specs"]["c_rating"]),
		ds.pack_label_text()))
	_reset(ds, home)
	results.append(TestResult.new("back on the drawn pack the print returns and the label goes",
		ds.pack_label_text() == "" and _wrap_box(ds).is_equal_approx(before), ""))
	var drawn_m := SwapLook.size_of("motor", catalog.get_part(String(home["motor"])))
	var bigger := ""
	for m in catalog.list_category("motor"):
		var s := SwapLook.size_of("motor", m)
		if s.x > drawn_m.x * 1.05 and PartSwap.judge(ds.session, catalog, "motor", String(m["part_id"]))["ok"]:
			bigger = String(m["part_id"])
			break
	var mb := ds.picks.box_of("part/motor/FL")
	var pb := ds.picks.box_of("part/prop/FL")
	if bigger != "":
		ds.choose("motor", bigger)
	var ratio := SwapLook.size_of("motor", catalog.get_part(bigger)).x / drawn_m.x if bigger != "" else 0.0
	var mb2 := ds.picks.box_of("part/motor/FL")
	results.append(TestResult.new("a bigger motor is drawn wider by the catalog bell ratio",
		bigger != "" and is_equal_approx(snappedf(mb2.size.x / mb.size.x, 0.001), snappedf(ratio, 0.001)),
		"%s ratio %.3f drawn %.3f" % [bigger, ratio, mb2.size.x / maxf(mb.size.x, 1e-9)]))
	var ry := SwapLook.size_of("motor", catalog.get_part(bigger)).y / drawn_m.y if bigger != "" else 1.0
	var lift := (float((ds._look_base["prop_FL"]["xf"] as Transform3D).origin.y)
		- float((ds._look_base["motor_FL"]["xf"] as Transform3D).origin.y)) * (ry - 1.0)
	var moved := ds.picks.box_of("part/prop/FL").position.y - pb.position.y
	results.append(TestResult.new("and its prop moves with the bell's new height",
		bigger != "" and absf(moved - lift) < 1e-5, "moved %.5f want %.5f" % [moved, lift]))
	return results


static func _test_motor_outline(ds: DesignSpace) -> Array:
	var results: Array = []
	ds.hovered = "part/motor/FL"
	ds._apply_marks()
	var hull := ds._motor_hulls[false] as MeshInstance3D
	var mi := ds.picks.entry_for("part/motor/FL")["node"] as MeshInstance3D
	var box := ds.picks.box_of("part/motor/FL")
	var cyl := hull.mesh as CylinderMesh
	results.append(TestResult.new("a hovered motor is outlined by one hull round its bell, not by its vents",
		hull.visible and mi.material_overlay == null
		and is_equal_approx(cyl.top_radius, maxf(box.size.x, box.size.z) * 0.5)
		and hull.position.is_equal_approx(box.get_center()), ""))
	var ink: Color = DesignSpace.HOVER_INK
	results.append(TestResult.new("and the hover ink reads clearly (light grey, at least 2 px)",
		ink.get_luminance() >= 0.75 and DesignSpace.HOVER_WIDTH_PX >= 2.0, "%.2f %.1f" % [ink.get_luminance(), DesignSpace.HOVER_WIDTH_PX]))
	ds.hovered = ""
	ds._apply_marks()
	results.append(TestResult.new("and the hull goes when the pointer leaves", not hull.visible, ""))
	return results
