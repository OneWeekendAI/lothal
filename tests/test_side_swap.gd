class_name TestSideSwap
extends RefCounted
## Swapping from the side panel (PLAN Section 3): clicking a part on the drone opens the Parts panel
## on exactly that part's categories, marks the fitted part and scrolls to it; a click on a card
## swaps it in place; the bottom swap strip is gone. (Replaces the strip's picker-fit and
## strip-polish suites.)
##
## ## The checks that could have passed while proving nothing
##
## - ONE GENERATED TEST PER SLOT for "opens exactly that slot's categories": the expected ids are
##   built HERE from the catalog and PartSwap.SLOTS, and compared as sorted lists with the cards
##   counted in the shelf's node tree, so an extra, a missing or a stale card from the last slot
##   fails that slot's test by name.
## - The panel is opened by a real `click_at` on the part, not by calling `open_slot`.
## - The panel starts SHUT and with other categories open, so "opens if closed" and "collapses the
##   others" can fail (a panel that was already open on the right category proves nothing).
## - The drone's rect is projected from the GLB meshes' boxes through the camera at its GOAL, and
##   compared with the panel's own node offsets; at 1280x720 the home view's drone reaches under the
##   panel, so a panel that moved nothing fails there. Run at both window sizes, for every slot.
## - The click that swaps is released over the card through `end_drag` (the live path: the shelf's
##   button is never "pressed" because the drag swallows the release); a release off the card must
##   swap nothing, and with nothing selected a click swaps nothing.
## - The scroll target is compared with the fitted card's own estimated position, and the fitted
##   part is moved to a far card first so a list that fitted without scrolling cannot pass.

const CLASS_ID := "five_inch"
const SIZES := [Vector2(1280, 720), Vector2(1920, 1080)]
const ADDRESS := {"battery": "part/battery", "motor": "part/motor/FL", "prop": "part/prop/FR",
	"stack": "part/stack", "camera": "part/camera", "antennas": "part/antennas"}


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var ds := _ds(catalog, SIZES[0])
	var home: Dictionary = ds.session.selection.duplicate(true)
	results.append_array(_test_strip_gone(ds))
	for slot in PartSwap.SLOTS:
		results.append(_test_click_opens_slot(ds, catalog, String(slot)))
		_reset(ds, home)
	results.append(_test_opens_if_closed_collapses_others(ds))
	_reset(ds, home)
	results.append_array(_test_fitted_follows(ds, catalog))
	_reset(ds, home)
	results.append_array(_test_scroll_to_fitted(ds))
	_reset(ds, home)
	results.append_array(_test_misfit_reason(ds))
	_reset(ds, home)
	results.append_array(_test_click_path(ds))
	_reset(ds, home)
	results.append_array(_test_hover_preview(ds))
	_reset(ds, home)
	results.append_array(_test_clearing(ds))
	_reset(ds, home)
	results.append(_test_camera_restored(ds))
	ds.free()
	for sz in SIZES:
		var d2 := _ds(catalog, sz)
		for slot in ADDRESS:
			results.append(_test_drone_beside_panel(d2, String(slot), sz))
		d2.free()
	return results


static func _ds(catalog: PartsCatalog, sz: Vector2) -> DesignSpace:
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), catalog)
	ds.size = sz
	ds.rig.aspect = sz.x / sz.y
	return ds


static func _reset(ds: DesignSpace, home: Dictionary) -> void:
	ds.select("")
	ds.shelf.set_open(false)
	ds.shelf.expanded = {}
	ds.session.selection = home.duplicate(true)
	ds.session._undo.clear()
	ds.session._redo.clear()
	ds.refresh()
	ds.rig.snap_home()


static func _drone_rect(ds: DesignSpace) -> Rect2:
	return PickerPlace.screen_rect(PickerPlace.settled(ds.rig), ds.mesh_boxes().map(func(e): return e["box"]), ds.size)


## What the panel must offer for `slot` with misfits shown: every catalog part of its categories
## (plus "not fitted" where a category can be empty), as sorted "category/id" strings.
static func _expected(catalog: PartsCatalog, slot: String) -> Array:
	var out: Array = []
	for cat in PartSwap.SLOTS[slot]:
		if PartSwap.can_be_empty(String(cat)):
			out.append("%s/" % cat)
		for part in catalog.list_category(String(cat)):
			out.append("%s/%s" % [cat, String((part as Dictionary)["part_id"])])
	out.sort()
	return out


## A screen point (ndc) whose ray passes through the part's own shape; NAN when none does.
static func _clickable_ndc(ds: DesignSpace, address: String) -> Vector2:
	var box := ds.picks.box_of(address)
	for k in 25:
		var off := Vector3((k % 5 - 2) * box.size.x * 0.2, 0.0, (floori(k / 5.0) - 2) * box.size.z * 0.2)
		var ndc := ds.rig.project(box.get_center() + off)
		var ray := ds.rig.ray(ndc)
		if ds.picks.hits(ray["origin"], ray["dir"]).any(func(h): return String(h["address"]) == address):
			return ndc
	return Vector2(NAN, NAN)


## A real click on the first address of `slot` that a click reaches; "" when none does.
static func _click_slot(ds: DesignSpace, slot: String) -> String:
	for a in ds.picks.addresses():
		if PartSwap.slot_of(String(a)) != slot:
			continue
		ds.select("")
		ds.rig.snap_home()
		var ndc := _clickable_ndc(ds, String(a))
		if not is_nan(ndc.x):
			for i in 6:
				if ds.click_at(ndc) == String(a):
					break
		if ds.selected == String(a):
			return String(a)
	return ""


static func _test_strip_gone(ds: DesignSpace) -> Array:
	var props: Array = ds.get_property_list().map(func(p): return String(p["name"]))
	var all_nodes := ds.find_children("*", "", true, false).map(func(n): return String(n.name))
	return [
		TestResult.new("the bottom swap strip no longer exists: no strip properties on the stage",
			not props.has("strip") and not props.has("strip_slot") and not props.has("_picker_list"),
			str(props.filter(func(n): return n.contains("strip") or n.contains("picker")))),
		TestResult.new("no strip methods either (dock, rect, scroll, card rows)",
			not ds.has_method("strip_rect") and not ds.has_method("place_picker") and not ds.has_method("open_picker")
			and not ds.has_method("picker_rows") and not ds.has_method("press_row"), ""),
		TestResult.new("and no node called SwapStrip or SwapPicker anywhere under the stage",
			not all_nodes.has("SwapStrip") and not all_nodes.has("SwapPicker"), ""),
		TestResult.new("the strip's layout constants are gone",
			not (DesignSpace as GDScript).get_script_constant_map().has("STRIP_H"), ""),
	]


static func _test_click_opens_slot(ds: DesignSpace, catalog: PartsCatalog, slot: String) -> TestResult:
	var name := "clicking the %s part opens the Parts panel on exactly the %s categories, fitted part marked" % [slot, slot]
	ds.shelf.set_open(false)
	var a := _click_slot(ds, slot)
	if a == "":
		return TestResult.new(name, false, "no click reached the slot")
	for cat in PartSwap.SLOTS[slot]:
		ds.shelf.set_show_misfits(String(cat), true)
	var want := _expected(catalog, slot)
	var got: Array = ds.shelf.rows.map(func(r): return "%s/%s" % [r["category"], r["id"]])
	got.sort()
	# The cards actually in the shelf's tree, not only the row table.
	var cards: Array = ds.shelf.list.get_children().filter(func(c): return c is Button and String(c.name).begins_with("Part_"))
	var in_tree := cards.size() == got.size() and ds.shelf.rows.all(func(r): return cards.has(r["button"]))
	var cats: Array = (PartSwap.SLOTS[slot] as Array).map(func(c): return String(c))
	var open_cats: Array = ds.shelf.expanded.keys().filter(func(c): return ds.shelf.expanded[c])
	open_cats.sort()
	cats.sort()
	var fitted_ok := true
	for cat in PartSwap.SLOTS[slot]:
		var f: Array = ds.shelf.rows.filter(func(r): return r["fitted"] and String(r["category"]) == String(cat))
		fitted_ok = fitted_ok and f.size() == 1 and String(f[0]["id"]) == String(ds.session.selection[cat])
	return TestResult.new(name, ds.shelf.open and ds.swap_slot == slot and open_cats == cats and got == want
		and in_tree and fitted_ok,
		"open %s slot '%s' expanded %s; %d cards in tree; fitted ok %s; got %s want %s" % [ds.shelf.open, ds.swap_slot,
			open_cats, cards.size(), fitted_ok, got, want])


static func _test_opens_if_closed_collapses_others(ds: DesignSpace) -> TestResult:
	ds.select("")
	ds.shelf.set_open(true)
	ds.shelf.toggle_category("camera")
	ds.shelf.toggle_category("vtx")
	ds.shelf.set_open(false)
	var was_closed := not ds.shelf.open
	ds.select("part/battery")
	var open_cats: Array = ds.shelf.expanded.keys().filter(func(c): return ds.shelf.expanded[c])
	var cam_rows: Array = ds.shelf.rows.filter(func(r): return String(r["category"]) in ["camera", "vtx"])
	return TestResult.new("selecting a part opens the shut panel, expands its category and collapses the ones left open",
		was_closed and ds.shelf.open and open_cats == ["battery"] and cam_rows.is_empty(), "expanded %s" % [open_cats])


static func _test_fitted_follows(ds: DesignSpace, catalog: PartsCatalog) -> Array:
	var out: Array = []
	ds.select("part/battery")
	ds.shelf.set_show_misfits("battery", true)
	var before := String(ds.session.selection["battery"])
	var other := ""
	for p in catalog.list_category("battery"):
		var id := String(p["part_id"])
		if id != before and PartSwap.judge(ds.session, catalog, "battery", id, false)["ok"]:
			other = id
			break
	var v := ds.click_card("battery", other)
	var f: Array = ds.shelf.rows.filter(func(r): return r["fitted"])
	out.append(TestResult.new("a swap from the panel moves the fitted mark to the new part, and only there",
		v["ok"] and f.size() == 1 and String(f[0]["id"]) == other and ds.session.selection["battery"] == other,
		"%s -> %s, marked %s" % [before, other, f.map(func(r): return r["id"])]))
	out.append(TestResult.new("the swap went through the session: one undo step",
		ds.session.can_undo(), ""))
	ds.undo()
	f = ds.shelf.rows.filter(func(r): return r["fitted"])
	out.append(TestResult.new("undo puts the old part back, and the mark with it",
		ds.session.selection["battery"] == before and f.size() == 1 and String(f[0]["id"]) == before
		and ds.swap_slot == "battery", ""))
	ds.redo()
	f = ds.shelf.rows.filter(func(r): return r["fitted"])
	out.append(TestResult.new("redo swaps it in again",
		ds.session.selection["battery"] == other and f.size() == 1 and String(f[0]["id"]) == other, ""))
	return out


static func _test_scroll_to_fitted(ds: DesignSpace) -> Array:
	var out: Array = []
	ds.select("part/motor/FL")
	var far: Dictionary = {}
	for r in ds.shelf.rows:
		if r["ok"] and (far.is_empty() or float(r["y"]) > float(far["y"])):
			far = r
	ds.click_card("motor", String(far["id"]))
	var fitted: Array = ds.shelf.rows.filter(func(r): return r["fitted"])
	var y: float = float(fitted[0]["y"]) if fitted.size() == 1 else -1.0
	out.append(TestResult.new("with a far card fitted, the panel's scroll goal is its position less a little of the heading",
		fitted.size() == 1 and y + PartsShelf.CARD_H > PartsShelf.MAX_LIST_H and is_equal_approx(ds.shelf.scroll_target, y - 56.0),
		"y %.0f target %.0f" % [y, ds.shelf.scroll_target]))
	var first: Dictionary = ds.shelf.rows[0]
	ds.select("")
	ds.select("part/motor/FL")
	var again: Array = ds.shelf.rows.filter(func(r): return r["fitted"])
	out.append(TestResult.new("selecting the part again scrolls to it again (not left where it was)",
		again.size() == 1 and is_equal_approx(ds.shelf.scroll_target, float(again[0]["y"]) - 56.0)
		and float(again[0]["y"]) > float(first["y"]), "target %.0f" % ds.shelf.scroll_target))
	# A fitted card already in view: the list stays at the top, so the category's head shows.
	ds.click_card("motor", String(first["id"]))
	var near: Array = ds.shelf.rows.filter(func(r): return r["fitted"])
	out.append(TestResult.new("a fitted card that is already in view leaves the list at the top, head and chips showing",
		near.size() == 1 and float(near[0]["y"]) + PartsShelf.CARD_H <= PartsShelf.MAX_LIST_H and ds.shelf.scroll_target == 0.0,
		"y %.0f target %.0f" % [float(near[0]["y"]), ds.shelf.scroll_target]))
	return out


static func _test_misfit_reason(ds: DesignSpace) -> Array:
	var out: Array = []
	ds.select("part/motor/FL")
	ds.shelf.set_show_misfits("motor", true)
	var bad: Array = ds.shelf.rows.filter(func(r): return not r["ok"])
	if bad.is_empty():
		return [TestResult.new("a misfit motor card shows its reason", false, "no misfit in the motor list")]
	var row: Dictionary = bad[0]
	var lab: Label = row["reason_label"]
	out.append(TestResult.new("a misfit card shows its one-line reason on the card, no hover needed",
		lab != null and lab.visible and lab.text == String(row["reason"]) and lab.text != "", "'%s'" % row["reason"]))
	var name_label := ((row["button"] as Button).get_child(0) as Control).get_node("Name") as Label
	out.append(TestResult.new("and the card is dimmed",
		name_label.get_theme_color("font_color") == PartsShelf.INK_FAINT, ""))
	var good: Array = ds.shelf.rows.filter(func(r): return r["ok"])
	out.append(TestResult.new("a card that fits has no reason line",
		not good.is_empty() and good.all(func(r): return r["reason_label"] == null), ""))
	ds.select("")
	var bad2: Array = ds.shelf.rows.filter(func(r): return not r["ok"])
	out.append(TestResult.new("with nothing selected the misfit cards carry no reason line (the drag-and-drop shelf as before)",
		bad2.all(func(r): return r["reason_label"] == null), ""))
	return out


static func _test_click_path(ds: DesignSpace) -> Array:
	var out: Array = []
	var catalog := PartsCatalog.load_default()
	ds.select("part/battery")
	var before := String(ds.session.selection["battery"])
	var target := ""
	for p in catalog.list_category("battery"):
		var id := String(p["part_id"])
		if id != before and PartSwap.judge(ds.session, catalog, "battery", id, false)["ok"]:
			target = id
			break
	var b := ds.shelf.row_of(target)["button"] as Button
	b.position = Vector2(10, 10)
	b.size = Vector2(60, 60)
	# Released far from the card: a drop, not a click.
	ds.begin_shelf_drag(target)
	ds.end_drag(b.get_global_rect().get_center() + Vector2(600, 0))
	out.append(TestResult.new("pressed on a card and released away from it swaps nothing in place",
		ds.session.selection["battery"] == before, ""))
	ds.begin_shelf_drag(target)
	var v := ds.end_drag(b.get_global_rect().get_center())
	out.append(TestResult.new("pressed and released on the same card swaps it in, through the session",
		v.get("ok", false) and ds.session.selection["battery"] == target and ds.session.can_undo(), str(v)))
	ds.select("")
	var other := ""
	for p in catalog.list_category("battery"):
		if String(p["part_id"]) != target and PartSwap.judge(ds.session, catalog, "battery", String(p["part_id"]), false)["ok"]:
			other = String(p["part_id"])
			break
	if not ds.shelf.expanded.get("battery", false):
		ds.shelf.toggle_category("battery")
	var held := ds.session.selection.duplicate(true)
	out.append(TestResult.new("with no part selected a click on a card swaps nothing",
		ds.click_card("battery", other).is_empty() and ds.session.selection == held, ""))
	return out


static func _test_hover_preview(ds: DesignSpace) -> Array:
	var out: Array = []
	ds.select("part/battery")
	ds.shelf.set_show_misfits("battery", true)
	var row: Dictionary = ds.shelf.row_of("battery_6s_1300")
	var b := row["button"] as Button
	var held := ds.session.selection.duplicate(true)
	b.mouse_entered.emit()
	out.append(TestResult.new("the pointer on a card previews its readout deltas, through the card's own signal",
		(ds.delta_labels["auw_g"] as Label).visible and not ds.previewing.is_empty() and ds.session.selection == held,
		str(ds.previewing.keys())))
	b.mouse_exited.emit()
	out.append(TestResult.new("and leaving it clears them", not (ds.delta_labels["auw_g"] as Label).visible and ds.previewing.is_empty(), ""))
	ds.select("part/motor/FL")
	ds.shelf.set_show_misfits("motor", true)
	var bad: Array = ds.shelf.rows.filter(func(r): return not r["ok"])
	(bad[0]["button"] as Button).mouse_entered.emit()
	out.append(TestResult.new("a misfit card previews nothing",
		not bad.is_empty() and ds.previewing.is_empty() and not (ds.delta_labels["auw_g"] as Label).visible, ""))
	ds.select("")
	ds.shelf.set_show_misfits("battery", true)
	if not ds.shelf.expanded.get("battery", false):
		ds.shelf.toggle_category("battery")
	var any: Array = ds.shelf.rows.filter(func(r): return String(r["category"]) == "battery" and r["ok"])
	if not any.is_empty():
		(any[0]["button"] as Button).mouse_entered.emit()
	out.append(TestResult.new("with nothing selected a hover previews nothing", ds.previewing.is_empty(), ""))
	return out


static func _test_clearing(ds: DesignSpace) -> Array:
	var out: Array = []
	ds.select("part/battery")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	ds._unhandled_key_input(esc)
	out.append(TestResult.new("Escape clears the selection and the swap mode, and the panel stays open",
		ds.selected == "" and ds.swap_slot == "" and ds.shelf.swap_cats.is_empty() and ds.shelf.open
		and ds.shelf.rows.all(func(r): return not r["fitted"]), ""))
	ds.select("part/battery")
	ds.click_at(Vector2(-0.97, 0.97))
	out.append(TestResult.new("a click on empty space clears it too",
		ds.selected == "" and ds.swap_slot == "" and ds.shelf.swap_cats.is_empty(), ds.selected))
	return out


static func _test_camera_restored(ds: DesignSpace) -> TestResult:
	ds.select("")
	ds.shelf.set_open(false)
	ds.rig.snap_home()
	var t0 := ds.rig.goal_target
	var d0 := ds.rig.goal_distance
	ds.select("part/battery")
	var moved := not (ds.rig.goal_target.is_equal_approx(t0) and is_equal_approx(ds.rig.goal_distance, d0))
	ds.select("")
	ds.shelf.set_open(false)
	return TestResult.new("closing the panel puts the camera back where it was (it moved while open: %s)" % moved,
		moved and ds.rig.goal_target.is_equal_approx(t0) and is_equal_approx(ds.rig.goal_distance, d0),
		"now %s %f (was %s %f)" % [ds.rig.goal_target, ds.rig.goal_distance, t0, d0])


static func _test_drone_beside_panel(ds: DesignSpace, slot: String, sz: Vector2) -> TestResult:
	ds.select("")
	ds.shelf.set_open(false)
	ds.rig.snap_home()
	ds.select(String(ADDRESS[slot]))
	ds.rig.snap()
	var r := _drone_rect(ds)
	var edge := ds.shelf.offset_left + PartsShelf.WIDTH
	return TestResult.new("%dx%d, %s selected: the drone is right of the panel, clear of the right column and on screen" % [sz.x, sz.y, slot],
		ds.shelf.open and r.position.x >= edge - 1.0 and r.end.x <= sz.x - PickerPlace.COLUMN_W + 1.0
		and r.position.y >= 0.0 and r.end.y <= sz.y,
		"drone %s, panel edge %.0f" % [r, edge])
