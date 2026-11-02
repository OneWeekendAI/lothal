class_name TestDesignPickerFit
extends RefCounted
## The swap strip at 1280x720 on the 5" (PLAN Section 3): clicking a part opens it with exactly that
## slot's alternatives, it is docked at the bottom clear of everything else on screen, the camera
## lifts the drone clear of it, and the fitted or hovered card scrolls into view. The old pop-up is gone.
##
## ## The checks that could have passed while proving nothing
##
## - ONE GENERATED TEST PER SLOT for "exactly that slot's alternatives": the expected ids are built
##   HERE from the catalog and PartSwap.SLOTS, and compared as sorted lists with the strip's own
##   card buttons (counted in the node tree, not only the row table), so an extra, a missing or a
##   stale card from the last slot fails that slot's test by name.
## - The strip is opened by a real `click_at` on the part, not by calling `open_picker`.
## - "The pop-up is gone" is three checks: no `picker` property, no node named SwapPicker anywhere
##   under the stage, and the strip a different node from anything called a picker.
## - Scrolling: there is no scene tree here, so containers never lay out. Each card's span is
##   computed by THIS test by walking the list's children and summing their minimum widths plus
##   the HBox separation (exactly what an HBox with no expanding children does), and each scroll
##   case also demands the scroll actually moved (> 0), so a list that fit without scrolling, or a
##   card that happened to sit at the left, cannot pass. The real window is checked by screenshot.

const CLASS_ID := "five_inch"
const SIZE := Vector2(1280, 720)
const SELECTIONS := ["part/battery", "part/motor/FL", "part/motor/FR", "part/motor/BL", "part/motor/BR",
	"part/camera", "part/stack", "part/antennas", "part/prop/FR"]


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), catalog)
	ds.size = SIZE
	ds.rig.aspect = SIZE.x / SIZE.y
	var home: Dictionary = ds.session.selection.duplicate(true)
	results.append_array(_test_popup_gone(ds))
	for slot in PartSwap.SLOTS:
		results.append(_test_click_opens_slot(ds, catalog, String(slot)))
		_reset(ds, home)
	for a in SELECTIONS:
		results.append_array(_test_selection(ds, String(a)))
	results.append(_test_camera_untouched(ds))
	results.append(_test_beside_shelf(ds))
	results.append(_test_closes(ds))
	_reset(ds, home)
	results.append(_test_chosen_far_card(ds, "part/motor/FL", "motor"))
	_reset(ds, home)
	results.append(_test_chosen_far_card(ds, "part/battery", "battery"))
	_reset(ds, home)
	results.append(_test_hovered_far_card(ds, "part/motor/FL"))
	_reset(ds, home)
	results.append(_test_hovered_far_card(ds, "part/prop/FR"))
	_reset(ds, home)
	results.append(_test_hover_in_view_stays(ds))
	ds.free()
	return results


static func _reset(ds: DesignSpace, home: Dictionary) -> void:
	ds.select("")
	ds.shelf.set_open(false)
	ds.session.selection = home.duplicate(true)
	ds.session._undo.clear()
	ds.session._redo.clear()
	ds.refresh()
	ds.rig.snap_home()


static func _open(ds: DesignSpace, address: String) -> void:
	ds.select("")
	ds.place_picker()
	ds.rig.snap_home()
	ds.select(address)
	ds.rig.snap()
	ds.place_picker()


## What the strip must offer for `slot`: every catalog part of its categories (plus "not fitted" where
## a category can be empty), as sorted "category/id" strings.
static func _expected(catalog: PartsCatalog, slot: String) -> Array:
	var out: Array = []
	for cat in PartSwap.SLOTS[slot]:
		if PartSwap.can_be_empty(String(cat)):
			out.append("%s/" % cat)
		for part in catalog.list_category(String(cat)):
			out.append("%s/%s" % [cat, String((part as Dictionary)["part_id"])])
	out.sort()
	return out


## A screen point (ndc) whose ray passes through the part's own shape, found without selecting
## anything; NAN when no sampled point of its box does.
static func _clickable_ndc(ds: DesignSpace, address: String) -> Vector2:
	var box := ds.picks.box_of(address)
	for k in 25:
		var off := Vector3((k % 5 - 2) * box.size.x * 0.2, 0.0, (floori(k / 5.0) - 2) * box.size.z * 0.2)
		var ndc := ds.rig.project(box.get_center() + off)
		var ray := ds.rig.ray(ndc)
		if ds.picks.hits(ray["origin"], ray["dir"]).any(func(h): return String(h["address"]) == address):
			return ndc
	return Vector2(NAN, NAN)


static func _test_click_opens_slot(ds: DesignSpace, catalog: PartsCatalog, slot: String) -> TestResult:
	var name := "clicking the %s part opens the strip with exactly the %s alternatives" % [slot, slot]
	# A real click on a point of the part: the first address of the slot that a click reaches (a part
	# drawn behind another, like the stack behind its wires, cannot be clicked at its centre).
	var tried: Array = []
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
		tried.append("%s->%s" % [a, ds.selected])
		if ds.selected == String(a):
			break
	if ds.selected == "" or PartSwap.slot_of(ds.selected) != slot:
		return TestResult.new(name, false, "no click reached the slot: %s" % [tried])
	var want := _expected(catalog, slot)
	var got: Array = ds.picker_rows().map(func(r): return "%s/%s" % [r["category"], r["id"]])
	got.sort()
	# The cards actually in the strip's tree, not only the row table.
	var cards: Array = ds._picker_list.get_children().filter(func(c): return c is Button)
	var in_tree := cards.size() == got.size() and ds.picker_rows().all(func(r): return cards.has(r["button"]))
	return TestResult.new(name,
		ds.strip.visible and ds.strip_slot == slot and got == want and in_tree and ds.strip.is_ancestor_of(cards[0]),
		"visible %s slot '%s'; %d cards in tree; got %s want %s" % [ds.strip.visible, ds.strip_slot, cards.size(), got, want])


static func _test_popup_gone(ds: DesignSpace) -> Array:
	var props: Array = ds.get_property_list().map(func(p): return String(p["name"]))
	_open(ds, "part/battery")
	return [
		TestResult.new("the pop-up picker no longer exists: no `picker` property on the stage",
			not props.has("picker") and props.has("strip"), str(props.filter(func(n): return n.contains("pick")))),
		TestResult.new("and no node named SwapPicker is anywhere under the stage",
			ds.find_child("SwapPicker", true, false) == null and ds.find_child("SwapStrip", true, false) == ds.strip, ""),
	]


static func _test_selection(ds: DesignSpace, address: String) -> Array:
	_open(ds, address)
	var r := ds.strip_rect()
	var out: Array = []
	var s := ds.size
	var bad: Array = []
	for pair in _others(ds):
		if r.intersects(pair[1]):
			bad.append("%s %s" % [pair[0], pair[1]])
	out.append(TestResult.new("the strip with %s selected is on screen, docked at the bottom, clear of every other panel and link (1280x720)" % address,
		ds.strip.visible and Rect2(Vector2.ZERO, s).encloses(r) and r.end.y >= s.y - 24.0 and bad.is_empty()
		and ds.strip.offset_left == r.position.x and ds.strip.offset_top == r.position.y,
		"strip %s overlaps %s" % [r, bad]))
	return out


## Every other thing on screen the strip must clear, as [name, rect]; measured here from the layout
## constants (not from the stage's own avoid list, which the strip is part of).
static func _others(ds: DesignSpace) -> Array:
	var s := ds.size
	var out := [["back link", Rect2(32, 20, 108, 32)], ["home link", Rect2(32, s.y - 56, 108, 32)],
		["readouts", Rect2(s.x - DesignSpace.PANEL_W - DesignSpace.PANEL_EDGE, 48, DesignSpace.PANEL_W, 352.0)],
		["inspector column", Rect2(s.x - 340.0, s.y - 24.0 - 260.0, 340.0, 260.0)]]
	if ds.shelf.visible and ds.shelf.open:
		out.append(["shelf", Rect2(32, 64, PartsShelf.WIDTH, s.y - 64.0)])
	return out


static func _test_camera_untouched(ds: DesignSpace) -> TestResult:
	# The strip lifts the drone clear of itself (tests/test_strip_polish.gd checks where it ends up)
	# and closing it gives the camera back exactly: the home view, bit for bit.
	ds.select("")
	ds.place_picker()
	ds.rig.snap_home()
	var t0 := ds.rig.goal_target
	var d0 := ds.rig.goal_distance
	ds.select("part/battery")
	var moved := not (ds.rig.goal_target.is_equal_approx(t0) and is_equal_approx(ds.rig.goal_distance, d0))
	ds.select("")
	ds.place_picker()
	return TestResult.new("closing the strip puts the camera back where it was (it moved while open: %s)" % moved,
		moved and ds.rig.goal_target.is_equal_approx(t0) and is_equal_approx(ds.rig.goal_distance, d0),
		"now %s %f (was %s %f)" % [ds.rig.goal_target, ds.rig.goal_distance, t0, d0])


static func _test_beside_shelf(ds: DesignSpace) -> TestResult:
	ds.shelf.set_open(true)
	_open(ds, "part/battery")
	var r := ds.strip_rect()
	var edge := ds.shelf.offset_left + PartsShelf.WIDTH
	var ok := r.position.x >= edge and ds.strip.offset_left == r.position.x
	ds.shelf.set_open(false)
	return TestResult.new("with the parts shelf open the strip starts to its right", ok, "strip %s, shelf edge %.0f" % [r, edge])


static func _test_closes(ds: DesignSpace) -> TestResult:
	_open(ds, "part/battery")
	var was := ds.strip.visible
	ds.select("")
	return TestResult.new("clearing the selection (Escape or an empty click) closes the strip",
		was and not ds.strip.visible and ds.strip_slot == "", "")


## The card's [left, right] in the list, by this test's own walk of the list's minimum widths.
static func _span(ds: DesignSpace, i: int) -> Vector2:
	var b: Control = ds.picker_rows()[i]["button"]
	var list := ds._picker_list
	var sep := float(list.get_theme_constant("separation"))
	var x := 0.0
	for c in list.get_children():
		var w := (c as Control).get_combined_minimum_size().x
		if c == b:
			return Vector2(x, x + w)
		x += w + sep
	return Vector2(-1, -1)


static func _in_view(ds: DesignSpace, i: int) -> Dictionary:
	var scroll := ds._picker_list.get_parent() as ScrollContainer
	var v := float(scroll.scroll_horizontal)
	var w := scroll.custom_minimum_size.x
	var s := _span(ds, i)
	return {"ok": v > 0.0 and s.x >= v - 1.0 and s.y <= v + w + 1.0,
		"detail": "card %d spans %s, scroll shows %.0f..%.0f" % [i, s, v, v + w]}


static func _test_chosen_far_card(ds: DesignSpace, address: String, cat: String) -> TestResult:
	_open(ds, address)
	var rows := ds.picker_rows()
	var last := -1
	for i in rows.size():
		if String(rows[i]["category"]) == cat and rows[i]["ok"]:
			last = i
	if last < 0:
		return TestResult.new("choosing the last %s card keeps it in view" % cat, false, "no usable card")
	var id := String(rows[last]["id"])
	var res := ds.press_row(last)
	var now := -1
	for i in ds.picker_rows().size():
		if ds.picker_rows()[i]["fitted"] and String(ds.picker_rows()[i]["id"]) == id:
			now = i
	if not res.get("ok", false) or now < 0:
		return TestResult.new("choosing the last %s card keeps it in view" % cat, false, "choose %s, fitted card %d" % [res, now])
	var v := _in_view(ds, now)
	return TestResult.new("choosing the last %s card (%s) keeps the fitted card scrolled into view" % [cat, id],
		v["ok"], v["detail"])


static func _test_hovered_far_card(ds: DesignSpace, address: String) -> TestResult:
	_open(ds, address)
	var last := ds.picker_rows().size() - 1
	var scroll := ds._picker_list.get_parent() as ScrollContainer
	scroll.scroll_horizontal = 0
	ds.hover_row(last)
	var v := _in_view(ds, last)
	return TestResult.new("hovering the last card of the %s strip scrolls it into view" % address,
		v["ok"], v["detail"])


static func _test_hover_in_view_stays(ds: DesignSpace) -> TestResult:
	_open(ds, "part/motor/FL")
	var scroll := ds._picker_list.get_parent() as ScrollContainer
	scroll.scroll_horizontal = 0
	var before := scroll.scroll_horizontal
	ds.hover_row(1)
	var after := scroll.scroll_horizontal
	return TestResult.new("hovering a card already in view does not scroll the strip",
		before == 0 and after == 0, "scroll %d -> %d" % [before, after])
