class_name TestStripPolish
extends RefCounted
## The swap strip's polish: no card or caption cut by the strip's edges, the drone kept above the
## strip, and a misfit's reason readable without hovering.
##
## ## The checks that could have passed while proving nothing
##
## - Clipping is judged from THIS file's own walk of the list's children (their minimum widths and
##   the HBox separation) against the scroll area's width and offset, at every scroll position the
##   arrows can reach (not only the first one): an item is fine only if it lies wholly inside the
##   view or wholly outside it. The view must also never be wider than the strip allows, and the
##   first and the last card must each be reachable whole.
## - The drone's rect is projected from the GLB meshes' boxes through the camera at its GOAL (the
##   view the eased camera arrives at), and compared with the strip's own node offsets, not with
##   strip_rect(). It is generated per slot and per window size; at 1280x720 the home view's drone
##   reaches below the strip's top, so a strip that moved nothing fails there.
## - The reason test clicks a dimmed card through its gui_input (no hover), then exits the card, and
##   the line must still read that card's own reason; opening another strip clears it.

const CLASS_ID := "five_inch"
const SIZES := [Vector2(1280, 720), Vector2(1920, 1080)]
const ADDRESS := {"battery": "part/battery", "motor": "part/motor/FL", "prop": "part/prop/FR",
	"stack": "part/stack", "camera": "part/camera", "antennas": "part/antennas"}


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	for sz in SIZES:
		var ds := _ds(catalog, sz)
		for slot in ADDRESS:
			results.append(_test_drone_above(ds, String(slot), sz))
			results.append(_test_no_clipping(ds, String(slot), sz))
		ds.free()
	var ds1 := _ds(catalog, SIZES[0])
	results.append(_test_drone_above_with_shelf(ds1))
	results.append_array(_test_reason(ds1))
	ds1.free()
	return results


static func _ds(catalog: PartsCatalog, sz: Vector2) -> DesignSpace:
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), catalog)
	ds.size = sz
	ds.rig.aspect = sz.x / sz.y
	return ds


static func _open(ds: DesignSpace, slot: String) -> void:
	ds.select("")
	ds.shelf.set_open(false)
	ds.place_picker()
	ds.rig.snap_home()
	ds.select(String(ADDRESS[slot]))
	ds.rig.snap()
	ds.place_picker()


static func _strip_top(ds: DesignSpace) -> float:
	return ds.strip.offset_top


static func _drone_rect(ds: DesignSpace) -> Rect2:
	return PickerPlace.screen_rect(PickerPlace.settled(ds.rig), ds.mesh_boxes().map(func(e): return e["box"]), ds.size)


static func _test_drone_above(ds: DesignSpace, slot: String, sz: Vector2) -> TestResult:
	_open(ds, slot)
	var r := _drone_rect(ds)
	var top := _strip_top(ds)
	return TestResult.new("%dx%d, %s strip: the drone's lowest edge stays above the strip and on screen" % [sz.x, sz.y, slot],
		ds.strip.visible and r.end.y <= top and r.position.y >= 0.0 and r.position.x >= 0.0 and r.end.x <= sz.x,
		"drone %s, strip top %.0f" % [r, top])


static func _test_drone_above_with_shelf(ds: DesignSpace) -> TestResult:
	ds.select("")
	ds.rig.snap_home()
	ds.shelf.set_open(true)
	ds.select("part/battery")
	ds.rig.snap()
	ds.place_picker()
	var r := _drone_rect(ds)
	var edge := ds.shelf.offset_left + PartsShelf.WIDTH
	var top := _strip_top(ds)
	var ok := ds.strip.visible and r.end.y <= top and r.position.x >= edge - 1.0
	ds.shelf.set_open(false)
	return TestResult.new("1280x720 with the shelf open: the drone is above the strip and right of the shelf", ok,
		"drone %s, strip top %.0f, shelf edge %.0f" % [r, top, edge])


## Items of the strip's list as [left, right] in list px, from minimum widths (this test's own walk).
static func _items(ds: DesignSpace) -> Array:
	var out: Array = []
	var x := 0.0
	var sep := float(ds._picker_list.get_theme_constant("separation"))
	for c in ds._picker_list.get_children():
		var w := (c as Control).get_combined_minimum_size().x
		out.append(Vector2(x, x + w))
		x += w + sep
	return out


## "" when every item is whole in, or wholly out of, the view; else which one is cut.
static func _cut(ds: DesignSpace) -> String:
	var scroll := ds._picker_list.get_parent() as ScrollContainer
	var v := float(scroll.scroll_horizontal)
	var w := scroll.custom_minimum_size.x
	var items := _items(ds)
	for i in items.size():
		var a: Vector2 = items[i]
		var inside := a.x >= v - 0.5 and a.y <= v + w + 0.5
		var outside := a.y <= v + 0.5 or a.x >= v + w - 0.5
		if not inside and not outside:
			return "item %d spans %s, view %.0f..%.0f" % [i, a, v, v + w]
	return ""


static func _test_no_clipping(ds: DesignSpace, slot: String, sz: Vector2) -> TestResult:
	var name := "%dx%d, %s strip: no card is cut by the strip's edges at any scroll position" % [sz.x, sz.y, slot]
	_open(ds, slot)
	var scroll := ds._picker_list.get_parent() as ScrollContainer
	for i in 4:
		ds.place_picker()   # lets the opening reveal of the fitted card finish
	scroll.scroll_horizontal = 0
	ds.place_picker()
	var avail := ds.strip.offset_right - ds.strip.offset_left - 2.0 * DesignSpace.STRIP_PAD - 56.0
	var items := _items(ds)
	var seen_first := _cut(ds) == "" and scroll.scroll_horizontal == 0
	var problems: Array = []
	var positions := 0
	var last_x := -1
	for step in 60:
		var c := _cut(ds)
		if c != "":
			problems.append(c)
		if scroll.custom_minimum_size.x > avail + 0.5:
			problems.append("view %.0f wider than the strip allows (%.0f)" % [scroll.custom_minimum_size.x, avail])
		positions += 1
		if scroll.scroll_horizontal == last_x:
			break
		last_x = scroll.scroll_horizontal
		ds.scroll_strip(1)
	var v := float(scroll.scroll_horizontal)
	var last_whole: bool = (items[items.size() - 1] as Vector2).y <= v + scroll.custom_minimum_size.x + 0.5
	return TestResult.new(name, problems.is_empty() and seen_first and last_whole,
		"%s; first whole %s, last whole %s, %d positions" % [problems.slice(0, 2), seen_first, last_whole, positions])


static func _test_reason(ds: DesignSpace) -> Array:
	var out: Array = []
	_open(ds, "motor")
	var rows := ds.picker_rows()
	var bad := -1
	var good := -1
	for i in rows.size():
		if not rows[i]["ok"] and bad < 0:
			bad = i
		if rows[i]["ok"] and good < 0:
			good = i
	if bad < 0 or good < 0:
		return [TestResult.new("a dimmed motor card shows its reason without hover", false, "no misfit or no fit card")]
	out.append(TestResult.new("with nothing hovered or clicked, no reason line shows", ds.strip_reason() == "", "'%s'" % ds.strip_reason()))
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	(rows[bad]["button"] as Button).gui_input.emit(ev)
	out.append(TestResult.new("clicking a dimmed card shows its reason line, no hover needed",
		ds.strip_reason() == String(rows[bad]["reason"]) and ds.strip_reason() != "", "'%s'" % ds.strip_reason()))
	(rows[bad]["button"] as Button).mouse_exited.emit()
	out.append(TestResult.new("the reason stays after the pointer leaves the card",
		ds.strip_reason() == String(rows[bad]["reason"]), "'%s'" % ds.strip_reason()))
	_open(ds, "battery")
	out.append(TestResult.new("opening another strip clears the reason line", ds.strip_reason() == "", "'%s'" % ds.strip_reason()))
	return out
