class_name TestDesignPickerFit
extends RefCounted
## The swap picker at 1280x720 on the 5" (PLAN Section 3 fixes): it never covers the drone, stays
## clear of the right column, and its fitted and hovered rows scroll into view.
##
## ## The checks that could have passed while proving nothing
##
## - ONE GENERATED CHECK PER SELECTION. Each case starts from the snapped home view, selects the
##   part, then SETTLES the camera (`rig.snap`) before measuring: the picker is placed for the view
##   the camera is easing to, so measuring against the unmoved camera would test the wrong frame.
## - The drone's rect in the overlap check is the picker-independent `drone_screen_rect` at the
##   settled camera, and the picker's width is at least PICKER_W: headless the panel's stylebox
##   margins make it 336 wide, in the window it is 360, so the narrower number would flatter it.
## - The column check is the full right 340 px strip (readouts on top, inspector growing up from
##   the bottom), wider than the 300 px readouts box the old swap test used.
## - Scrolling: there is no scene tree here, so containers never lay out. Each row's span is
##   computed by THIS test by walking the list's children and summing their minimum heights plus
##   the VBox separation (exactly what a VBox with no expanding children does), and each scroll
##   case also demands the scroll actually moved (> 0), so a list that fit without scrolling, or a
##   row that happened to sit at the top, cannot pass. The real window is checked by screenshot.

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
	for a in SELECTIONS:
		results.append_array(_test_selection(ds, String(a)))
	results.append(_test_room_given_back(ds))
	results.append(_test_room_not_needed(ds))
	_reset(ds, home)
	results.append(_test_chosen_far_row(ds, "part/motor/FL", "motor"))
	_reset(ds, home)
	results.append(_test_chosen_far_row(ds, "part/battery", "battery"))
	_reset(ds, home)
	results.append(_test_hovered_far_row(ds, "part/motor/FL"))
	_reset(ds, home)
	results.append(_test_hovered_far_row(ds, "part/prop/FR"))
	_reset(ds, home)
	results.append(_test_hover_in_view_stays(ds))
	ds.free()
	return results


static func _reset(ds: DesignSpace, home: Dictionary) -> void:
	ds.select("")
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


static func _picker_rect(ds: DesignSpace) -> Rect2:
	return Rect2(ds.picker.position, Vector2(maxf(ds.picker.size.x, DesignSpace.PICKER_W), ds.picker.size.y))


static func _part_px(ds: DesignSpace, address: String) -> Vector2:
	var ndc := ds.rig.project(ds.picks.box_of(address).get_center())
	return Vector2((ndc.x + 1.0) * 0.5 * ds.size.x, (1.0 - ndc.y) * 0.5 * ds.size.y)


static func _test_selection(ds: DesignSpace, address: String) -> Array:
	_open(ds, address)
	var r := _picker_rect(ds)
	var drone := ds.drone_screen_rect()
	var out: Array = []
	out.append(TestResult.new("the picker does not cover the drone with %s selected (1280x720, home)" % address,
		ds.picker.visible and drone.size.x > 0.0 and not r.intersects(drone), "picker %s drone %s" % [r, drone]))
	var column := Rect2(Vector2(ds.size.x - 340.0, 0.0), Vector2(340.0, ds.size.y))
	var readouts := Rect2(Vector2(ds.size.x - 300.0, 48.0), Vector2(260.0, 400.0))
	var p := _part_px(ds, address)
	out.append(TestResult.new("the picker is on screen, clear of the readouts column and level with %s" % address,
		Rect2(Vector2.ZERO, ds.size).encloses(r) and not r.intersects(column) and not r.intersects(readouts)
		and p.y >= r.position.y - 40.0 and p.y <= r.end.y + 40.0, "picker %s part %s" % [r, p]))
	return out


static func _test_room_given_back(ds: DesignSpace) -> TestResult:
	ds.select("")
	ds.place_picker()
	ds.rig.snap_home()
	var t0 := ds.rig.goal_target
	var d0 := ds.rig.goal_distance
	ds.select("part/battery")
	var backed := ds.rig.goal_distance > d0 * 1.1
	ds.select("")
	ds.place_picker()
	return TestResult.new("the camera backs off to make room, and goes back when the picker closes",
		backed and ds.rig.goal_target.is_equal_approx(t0) and is_equal_approx(ds.rig.goal_distance, d0),
		"backed %s, now %s %f (was %s %f)" % [backed, ds.rig.goal_target, ds.rig.goal_distance, t0, d0])


static func _test_room_not_needed(ds: DesignSpace) -> TestResult:
	ds.select("")
	ds.place_picker()
	ds.rig.snap_home()
	ds.rig.goal_distance = ds.rig.max_distance()
	ds.rig.pan(0.15, 0.0)
	ds.rig.snap()
	var t0 := ds.rig.goal_target
	# The setup must leave room on one side by the test's own arithmetic, or it proves nothing.
	var d := ds.drone_screen_rect()
	var w := DesignSpace.PICKER_W
	var room := d.end.x + 24.0 + w <= ds.size.x - 340.0 or d.position.x - 24.0 - w >= 0.0
	ds.select("part/battery")
	ds.place_picker()
	var r := _picker_rect(ds)
	var ok := room and ds.rig.goal_target == t0 and ds.rig.goal_distance == ds.rig.max_distance() \
		and not r.intersects(ds.drone_screen_rect())
	var detail := "room %s; picker %s drone %s goal %s %f (was %s)" % [room, r, ds.drone_screen_rect(), ds.rig.goal_target, ds.rig.goal_distance, t0]
	ds.select("")
	ds.place_picker()
	ds.rig.snap_home()
	return TestResult.new("zoomed out, with room beside the drone, the camera stays put and the picker still clears it",
		ok, detail)


## The row's [top, bottom] in the list, by this test's own walk of the list's minimum heights.
static func _span(ds: DesignSpace, i: int) -> Vector2:
	var row: Dictionary = ds.picker_rows()[i]
	var b: Control = row["button"]
	var last: Control = row["reason_label"] if row["reason_label"] != null else b
	var list := ds._picker_list
	var sep := float(list.get_theme_constant("separation"))
	var y := 0.0
	var top := -1.0
	for c in list.get_children():
		var h := (c as Control).get_combined_minimum_size().y
		if c == b:
			top = y
		if c == last:
			return Vector2(top, y + h)
		y += h + sep
	return Vector2(-1, -1)


static func _in_view(ds: DesignSpace, i: int) -> Dictionary:
	var scroll := ds._picker_list.get_parent() as ScrollContainer
	var v := float(scroll.scroll_vertical)
	var h := scroll.custom_minimum_size.y
	var s := _span(ds, i)
	return {"ok": v > 0.0 and s.x >= v - 1.0 and s.y <= v + h + 1.0,
		"detail": "row %d spans %s, scroll shows %.0f..%.0f" % [i, s, v, v + h]}


static func _test_chosen_far_row(ds: DesignSpace, address: String, cat: String) -> TestResult:
	_open(ds, address)
	var rows := ds.picker_rows()
	var last := -1
	for i in rows.size():
		if String(rows[i]["category"]) == cat and rows[i]["ok"]:
			last = i
	if last < 0:
		return TestResult.new("choosing the last %s row keeps it in view" % cat, false, "no usable row")
	var id := String(rows[last]["id"])
	var res := ds.press_row(last)
	var now := -1
	for i in ds.picker_rows().size():
		if ds.picker_rows()[i]["fitted"] and String(ds.picker_rows()[i]["id"]) == id:
			now = i
	if not res.get("ok", false) or now < 0:
		return TestResult.new("choosing the last %s row keeps it in view" % cat, false, "choose %s, fitted row %d" % [res, now])
	var v := _in_view(ds, now)
	return TestResult.new("choosing the last %s row (%s) keeps the fitted row scrolled into view" % [cat, id],
		v["ok"], v["detail"])


static func _test_hovered_far_row(ds: DesignSpace, address: String) -> TestResult:
	_open(ds, address)
	var last := ds.picker_rows().size() - 1
	var scroll := ds._picker_list.get_parent() as ScrollContainer
	scroll.scroll_vertical = 0
	ds.hover_row(last)
	var v := _in_view(ds, last)
	return TestResult.new("hovering the last row of the %s picker scrolls it into view" % address,
		v["ok"], v["detail"])


static func _test_hover_in_view_stays(ds: DesignSpace) -> TestResult:
	_open(ds, "part/motor/FL")
	var scroll := ds._picker_list.get_parent() as ScrollContainer
	scroll.scroll_vertical = 0
	var before := scroll.scroll_vertical
	ds.hover_row(1)
	var after := scroll.scroll_vertical
	return TestResult.new("hovering a row already in view does not scroll the picker",
		before == 0 and after == 0, "scroll %d -> %d" % [before, after])
