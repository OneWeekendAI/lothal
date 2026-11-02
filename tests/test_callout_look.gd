class_name TestCalloutLook
extends RefCounted
## The look of the callouts and warning pins (PLAN Section 8, Agent B): what `CalloutLayer` paints,
## read from `draw_ops()` (the very list `_draw` executes), and the blocking tint on the 3D part.
## One check per case.
##
## ## The checks that could have passed while proving nothing
##
## - EVERY OP IS JUDGED, NOT A SAMPLE: colour, width and size checks walk the whole op list, and each
##   first demands the list holds the ops it is about (a leader per shown item, a badge per callout),
##   so an empty layer cannot pass.
## - AMBER IS COUNTED, NOT JUST ALLOWED: each warning paints exactly four amber ops (leader, pin
##   dot, label dot, tag); a callout painted amber, or a warning painted grey, changes the count.
## - THE TINT IS READ OFF THE MESH the pick registry names for the anchor, not off `tinted_parts()`
##   (the flag A2 already tests); the outline under it is compared by identity with the selection /
##   hover material, so a tint that replaced the outline fails.

const CLASS_ID := "five_inch"
const SIZES := [Vector2(1280, 720), Vector2(1920, 1080)]
const AMBER_PER_WARNING := 4


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), catalog)
	var home: Dictionary = ds.session.selection.duplicate(true)
	for sz in SIZES:
		for angle in ["home", "orbit"]:
			_set_size(ds, sz)
			_reset(ds, home)
			if angle == "orbit":
				ds.rig.goal_yaw += deg_to_rad(70.0)
				ds.rig.goal_pitch = deg_to_rad(20.0)
				ds.rig.snap()
				ds.update_callouts()
			var tag := "%dx%d %s" % [sz.x, sz.y, angle]
			results.append(_discs_apart(ds, tag))
			results.append(_discs_near_pins(ds, tag))
			results.append(_leaders_clear_discs(ds, tag))
	_set_size(ds, SIZES[0])
	_reset(ds, home)
	results.append(_hairlines(ds))
	results.append(_leaders_from_discs(ds))
	results.append(_grey_or_amber(ds))
	results.append(_amber_counted(ds))
	results.append(_caution_ring(ds))
	results.append(_badges(ds))
	results.append(_readable(ds))
	results.append(_expanded_lines(ds))
	results.append(_no_tint_on_seed(ds))
	results.append(_readout_mark(ds))
	results.append(_issues_count(ds))
	results.append(_ring_amber(ds))
	_reset(ds, home)
	ds.select("part/battery")
	ds.remove_selected()
	ds.select("")
	ds.update_callouts()
	results.append(_blocking_solid(ds))
	results.append(_keyline(ds))
	results.append(_amber_counted(ds, "no battery: "))
	results.append(_tinted(ds, "frame/plate/top", "no battery: the top plate wears the amber tint"))
	ds.hovered = "frame/plate/top"
	ds._apply_marks()
	results.append(_outline_under_tint(ds, "frame/plate/top", ds._hover_mat, "no battery, plate hovered: the hover outline is kept under the tint"))
	ds.hovered = ""
	ds.select("frame/plate/top")
	results.append(_outline_under_tint(ds, "frame/plate/top", ds._select_mat, "no battery, plate selected: the selection outline is kept under the tint"))
	ds.select("")
	results.append(_outline_under_tint(ds, "frame/plate/top", null, "no battery, plate deselected: the tint stays, the outline goes"))
	var plate := _mesh(ds, "frame/plate/top")
	ds.undo()
	ds.update_callouts()
	results.append(TestResult.new("battery back (undo): the top plate's tint is gone",
		plate != null and is_instance_valid(plate) and not _is_tint(ds, plate.material_overlay) and ds._tinted.is_empty(),
		"%s" % [str(plate.material_overlay) if plate != null and is_instance_valid(plate) else "no plate"]))
	_reset(ds, home)
	ds.choose("propeller", "prop_16x12x4")
	ds.update_callouts()
	results.append(_tinted(ds, "part/motor/FR", "16\" props, cannot hover: the motor wears the amber tint"))
	_reset(ds, home)
	TestWarningPins._drop_on(ds, "motor_2808_1300kv", "part/motor/")
	var refused: Array = ds.tinted_parts()
	results.append(_tinted(ds, String(refused[0]) if refused.size() == 1 else "?", "refused motor drop: the mount it was refused at wears the amber tint"))
	var mount := _mesh(ds, String(refused[0]) if refused.size() == 1 else "")
	ds.begin_shelf_drag("motor_2808_1300kv")
	ds.cancel_drag()
	results.append(TestResult.new("refused drop, next drag: the refusal's tint is gone",
		mount != null and not _is_tint(ds, mount.material_overlay) and ds._tinted.is_empty(),
		"%s" % [str(mount.material_overlay) if mount != null else "no mount mesh"]))
	ds.free()
	results.append(_touching_pins())
	results.append(_leader_through_pin())
	return results


## Two callout pins 5 px apart whose leaders go opposite ways: the later disc steps straight away
## from the first, by no more than it must.
static func _touching_pins() -> TestResult:
	var items := [{"kind": "callout", "pin": Vector2(100, 100), "end": Vector2(20, 100)},
		{"kind": "callout", "pin": Vector2(105, 100), "end": Vector2(200, 100)}]
	var d := CalloutLayer.disc_centres(items)
	var need := 2.0 * CalloutLayer.BADGE_R + CalloutLayer.DISC_GAP
	var gap := (d[0] as Vector2).distance_to(d[1])
	var moved := (d[1] as Vector2).distance_to(items[1]["pin"])
	return TestResult.new("disc_centres: touching pins with leaders apart step straight apart, the least move",
		(d[0] as Vector2) == items[0]["pin"] and gap >= need - 0.01 and moved <= need - 5.0 + 0.5 and absf((d[1] as Vector2).y - 100.0) < 0.5,
		"%s gap %.1f moved %.1f" % [d, gap, moved])


## A later pin whose leader would run back through an earlier disc steps sideways off it.
static func _leader_through_pin() -> TestResult:
	var items := [{"kind": "callout", "pin": Vector2(100, 100), "end": Vector2(20, 60)},
		{"kind": "callout", "pin": Vector2(130, 100), "end": Vector2(20, 100)}]
	var d := CalloutLayer.disc_centres(items)
	var q := Geometry2D.get_closest_point_to_segment(d[0], d[1], items[1]["end"])
	return TestResult.new("disc_centres: a leader that would cross an earlier disc is moved off it",
		(d[0] as Vector2) == items[0]["pin"] and q.distance_to(d[0]) >= CalloutLayer.BADGE_R
		and (d[1] as Vector2).distance_to(items[1]["pin"]) <= 4.0 * CalloutLayer.BADGE_R,
		"%s, leader clears by %.1f" % [d, q.distance_to(d[0])])


static func _set_size(ds: DesignSpace, sz: Vector2) -> void:
	ds.size = sz
	ds.rig.aspect = sz.x / sz.y


static func _reset(ds: DesignSpace, home: Dictionary) -> void:
	ds.cancel_drag()
	ds.select("")
	ds.hovered = ""
	ds.callout_focus = ""
	ds.shelf.set_open(false)
	ds.session.selection = home.duplicate(true)
	ds.session._undo.clear()
	ds.session._redo.clear()
	ds._after_change()
	ds.go_home()
	ds.rig.snap_home()
	ds.update_callouts()


static func _ops(ds: DesignSpace, kind: String) -> Array:
	return ds.callouts.draw_ops().filter(func(o): return String(o["op"]) == kind)


static func _is_warning(s: Dictionary) -> bool:
	return String(s.get("kind", "")) == "warning"


static func _n_warnings(ds: DesignSpace) -> int:
	return ds.callouts.shown.filter(func(s): return _is_warning(s)).size()


static func _grey(c: Color) -> bool:
	return absf(c.r - c.g) < 0.02 and absf(c.g - c.b) < 0.02


static func _amber(c: Color) -> bool:
	var w := CalloutLayer.WARN_INK
	return is_equal_approx(c.r, w.r) and is_equal_approx(c.g, w.g) and is_equal_approx(c.b, w.b)


# ---------------------------------------------------------------------------
# Pins and leaders
# ---------------------------------------------------------------------------

static func _discs_apart(ds: DesignSpace, tag: String) -> TestResult:
	var shown := ds.callouts.shown
	var discs := CalloutLayer.disc_centres(shown)
	var worst := INF
	for i in shown.size():
		for j in i:
			var need := _r(shown[i]) + _r(shown[j])
			worst = minf(worst, (discs[i] as Vector2).distance_to(discs[j]) - need)
	return TestResult.new("%s: no pin disc is drawn over another" % tag,
		shown.size() >= 6 and worst >= 0.0, "%d shown, closest edge gap %.1f px" % [shown.size(), worst])


static func _r(s: Dictionary) -> float:
	return CalloutLayer.DOT_R if _is_warning(s) else CalloutLayer.BADGE_R


## A nudged disc stays on its part: within two badge widths of its pin.
static func _discs_near_pins(ds: DesignSpace, tag: String) -> TestResult:
	var shown := ds.callouts.shown
	var discs := CalloutLayer.disc_centres(shown)
	var worst := 0.0
	for i in shown.size():
		worst = maxf(worst, (discs[i] as Vector2).distance_to(shown[i]["pin"]))
	return TestResult.new("%s: every disc sits within %d px of its pin" % [tag, int(4.0 * CalloutLayer.BADGE_R)],
		shown.size() >= 6 and worst <= 4.0 * CalloutLayer.BADGE_R, "%d shown, furthest %.1f px" % [shown.size(), worst])


## No leader runs through another item's disc (it would read as a pin on the wrong line).
static func _leaders_clear_discs(ds: DesignSpace, tag: String) -> TestResult:
	var shown := ds.callouts.shown
	var discs := CalloutLayer.disc_centres(shown)
	var lines := _ops(ds, "line")
	var bad: Array = []
	for i in mini(shown.size(), lines.size()):
		for j in shown.size():
			if j == i:
				continue
			var q := Geometry2D.get_closest_point_to_segment(discs[j], lines[i]["a"], lines[i]["b"])
			if q.distance_to(discs[j]) < _r(shown[j]):
				bad.append("%s through %s" % [shown[i]["name"], shown[j]["name"]])
	return TestResult.new("%s: no leader passes through another pin's disc" % tag,
		lines.size() == shown.size() and shown.size() >= 6 and bad.is_empty(), "%s %s" % [bad, shown.map(func(s): return [s["name"], s["pin"], s["end"]])])


static func _hairlines(ds: DesignSpace) -> TestResult:
	var lines := _ops(ds, "line")
	var rings := _ops(ds, "ring")
	var bad: Array = lines.filter(func(o): return not is_equal_approx(float(o["width"]), 1.0)).map(func(o): return o["width"])
	var thick: Array = rings.filter(func(o): return float(o["width"]) > 1.5).map(func(o): return o["width"])
	return TestResult.new("seed: every leader is a 1 px hairline, every ring at most 1.5 px",
		lines.size() == ds.callouts.shown.size() and lines.size() >= 8 and bad.is_empty() and thick.is_empty(),
		"%d leaders for %d shown; leader widths off %s; rings over 1.5 %s" % [lines.size(), ds.callouts.shown.size(), bad, thick])


static func _leaders_from_discs(ds: DesignSpace) -> TestResult:
	var shown := ds.callouts.shown
	var discs := CalloutLayer.disc_centres(shown)
	var lines := _ops(ds, "line")
	var bad: Array = []
	for i in mini(shown.size(), lines.size()):
		var from := (lines[i]["a"] as Vector2).distance_to(discs[i])
		if absf(from - _r(shown[i])) > 0.5 or (lines[i]["b"] as Vector2).distance_to(shown[i]["end"]) > 0.5:
			bad.append(String(shown[i]["name"]))
	return TestResult.new("seed: each leader leaves its disc's edge and ends at its label",
		lines.size() == shown.size() and shown.size() >= 8 and bad.is_empty(), "off: %s" % [bad])


static func _grey_or_amber(ds: DesignSpace) -> TestResult:
	var bad: Array = []
	var ops := ds.callouts.draw_ops()
	for o in ops:
		var c: Color = o["color"]
		if not _grey(c) and not _amber(c):
			bad.append("%s %s" % [o["op"], c])
	return TestResult.new("seed: every colour drawn is a grey or the one amber (no red, no blue)",
		ops.size() > 30 and bad.is_empty(), "%d ops, off-palette %s" % [ops.size(), bad])


static func _amber_counted(ds: DesignSpace, prefix: String = "seed: ") -> TestResult:
	var amber := ds.callouts.draw_ops().filter(func(o): return _amber(o["color"] as Color)).size()
	var n := _n_warnings(ds)
	return TestResult.new(prefix + "amber paints the warnings only, four ops each (leader, pin, label dot, tag)",
		n >= 1 and amber == AMBER_PER_WARNING * n, "%d amber ops for %d warnings" % [amber, n])


static func _caution_ring(ds: DesignSpace) -> TestResult:
	var ops := ds.callouts.draw_ops()
	var rings := ops.filter(func(o): return String(o["op"]) == "ring" and _amber(o["color"] as Color)).size()
	var solid := ops.filter(func(o): return String(o["op"]) == "disc" and _amber(o["color"] as Color)).size()
	var n := _n_warnings(ds)
	return TestResult.new("seed: a caution is an amber ring (pin and label), never a solid amber dot",
		n == 2 and rings == 2 * n and solid == 0, "%d warnings, %d amber rings, %d amber discs" % [n, rings, solid])


static func _blocking_solid(ds: DesignSpace) -> TestResult:
	var ops := ds.callouts.draw_ops()
	var rings := ops.filter(func(o): return String(o["op"]) == "ring" and _amber(o["color"] as Color)).size()
	var solid := ops.filter(func(o): return String(o["op"]) == "disc" and _amber(o["color"] as Color)).size()
	var n := _n_warnings(ds)
	return TestResult.new("no battery: a blocking pin is a solid amber dot (pin and label), no ring",
		n == 1 and solid == 2 and rings == 0, "%d warnings, %d amber discs, %d amber rings" % [n, solid, rings])


## A solid dot often sits on its own tinted part: each one has a darker, wider disc under it.
static func _keyline(ds: DesignSpace) -> TestResult:
	var discs := _ops(ds, "disc")
	var solid: Array = discs.filter(func(o): return _amber(o["color"] as Color))
	var ok := solid.size() == 2
	for a in solid:
		var under: Array = []
		for o in discs:
			if (o["c"] as Vector2).is_equal_approx(a["c"]) and float(o["r"]) > float(a["r"]) and (o["color"] as Color).get_luminance() < 0.1:
				under.append(o)
		ok = ok and under.size() == 1 and discs.find(under[0]) < discs.find(a)
	return TestResult.new("no battery: every solid amber dot sits on a dark keyline disc drawn beneath it",
		ok, "%d solid dots; discs %s" % [solid.size(), discs.map(func(o): return [o["r"], o["color"]])])


static func _badges(ds: DesignSpace) -> TestResult:
	var want: Array = []
	for s in ds.callouts.shown:
		if not _is_warning(s):
			want.append(str(int(s["number"])))
			want.append(str(int(s["number"])))
	var got: Array = _ops(ds, "text").filter(func(o): return String(o["role"]) == "badge").map(func(o): return String(o["text"]))
	want.sort()
	got.sort()
	return TestResult.new("seed: every callout's pin and label carry its number in a disc of radius <= 8 px",
		want.size() >= 12 and got == want and CalloutLayer.BADGE_R <= 8.0 and CalloutLayer.BADGE_R >= 6.0,
		"want %s got %s, R %.1f" % [want, got, CalloutLayer.BADGE_R])


static func _readable(ds: DesignSpace) -> TestResult:
	var texts := _ops(ds, "text")
	var small: Array = texts.filter(func(o): return int(o["size"]) < LothalTheme.FONT_SIZE_SMALL).map(func(o): return o["text"])
	var names: Array = texts.filter(func(o): return String(o["role"]) == "name")
	var low: Array = names.filter(func(o): return int(o["size"]) < LothalTheme.FONT_SIZE_BODY or (o["color"] as Color).get_luminance() < 0.6).map(func(o): return o["text"])
	var bg := CalloutLayer.LABEL_BG
	return TestResult.new("seed: label type is readable (names >= body size and bright, nothing under small, dark opaque-ish plate)",
		names.size() == ds.callouts.shown.size() and small.is_empty() and low.is_empty() and bg.get_luminance() < 0.1 and bg.a >= 0.7,
		"%d names; too small %s; dim/small names %s; plate %s" % [names.size(), small, low, bg])


static func _expanded_lines(ds: DesignSpace) -> TestResult:
	ds.callout_focus = "battery"
	ds.update_callouts()
	var texts := _ops(ds, "text")
	var why: Array = texts.filter(func(o): return String(o["role"]) == "why")
	var num: Array = texts.filter(func(o): return String(o["role"]) == "number")
	ds.callout_focus = ""
	ds.update_callouts()
	var ok := why.size() == 1 and num.size() == 1 and _grey(why[0]["color"]) and _grey(num[0]["color"]) \
		and (num[0]["color"] as Color).get_luminance() > (why[0]["color"] as Color).get_luminance() \
		and float(why[0]["width"]) > 0.0 and String(num[0]["text"]).contains("185 g")
	return TestResult.new("battery expanded: the why line wraps muted, the number line reads brighter",
		ok, "%s / %s" % [why.map(func(o): return [o["text"], o["color"]]), num.map(func(o): return [o["text"], o["color"]])])


# ---------------------------------------------------------------------------
# The blocking tint
# ---------------------------------------------------------------------------

static func _mesh(ds: DesignSpace, address: String) -> MeshInstance3D:
	var e := ds.picks.entry_for(address)
	if e.is_empty():
		return null
	return e["node"] as MeshInstance3D


static func _is_tint(_ds: DesignSpace, m: Material) -> bool:
	if not (m is StandardMaterial3D):
		return false
	var c := (m as StandardMaterial3D).albedo_color
	return _amber(c) and c.a >= 0.1 and c.a <= 0.4 and (m as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED


static func _tinted(ds: DesignSpace, address: String, case: String) -> TestResult:
	var mi := _mesh(ds, address)
	var m: Material = mi.material_overlay if mi != null else null
	return TestResult.new(case + " (translucent amber overlay on its mesh)",
		ds.tinted_parts().has(address) and _is_tint(ds, m), "%s: overlay %s %s" % [address, m,
			str((m as StandardMaterial3D).albedo_color) if m is StandardMaterial3D else ""])


static func _outline_under_tint(ds: DesignSpace, address: String, outline: Material, case: String) -> TestResult:
	var mi := _mesh(ds, address)
	var m: Material = mi.material_overlay if mi != null else null
	return TestResult.new(case, _is_tint(ds, m) and m.next_pass == outline,
		"overlay %s, next pass %s, want %s" % [m, str(m.next_pass) if m != null else "-", outline])


static func _no_tint_on_seed(ds: DesignSpace) -> TestResult:
	var tinted: Array = []
	for e in ds.picks.entries:
		var mi := e["node"] as MeshInstance3D
		if mi != null and is_instance_valid(mi) and _is_tint(ds, mi.material_overlay):
			tinted.append(String(e["address"]))
	return TestResult.new("seed: cautions only, so no part is tinted",
		ds.picks.entries.size() > 5 and tinted.is_empty() and _n_warnings(ds) == 2, "tinted %s" % [tinted])


# ---------------------------------------------------------------------------
# The readouts panel
# ---------------------------------------------------------------------------

static func _readout_mark(ds: DesignSpace) -> TestResult:
	var mark := ds.mark_buttons["thrust_to_weight"] as Button
	var val := ds.value_labels["thrust_to_weight"] as Label
	var cell := mark.get_parent()
	var amber := true
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		amber = amber and _amber(mark.get_theme_color(st))
	var others: Array = []
	for k in ds.mark_buttons:
		if k != "thrust_to_weight" and (ds.mark_buttons[k] as Button).visible:
			others.append(k)
	return TestResult.new("seed: T:W carries an amber \"in air\" mark in its own cell, under its ring and label",
		mark.visible and mark.text.begins_with("▲") and mark.text.ends_with("in air") and amber
		and cell == val.get_parent().get_parent() and mark.get_index() > val.get_parent().get_index() and others.is_empty()
		and mark.get_theme_font_size("font_size") <= val.get_theme_font_size("font_size"),
		"'%s' visible %s amber %s same cell %s, other marks %s" % [mark.text, mark.visible, amber, cell == val.get_parent().get_parent(), others])


## The ring turns amber exactly where a warning moves its readout (the seed's T:W), grey elsewhere.
static func _ring_amber(ds: DesignSpace) -> TestResult:
	var marks := WarningPins.marks(ds.warning_pins)
	var bad: Array = []
	for k in ds.gauges:
		var g := ds.gauges[k] as ReadoutGauge
		var want := marks.has(k)
		if _amber(g.ink_color()) != want or g.warn != want:
			bad.append(k)
	return TestResult.new("seed: a ring is amber exactly when a warning moves its readout, else grey",
		marks.has("thrust_to_weight") and not marks.has("auw_g") and bad.is_empty(), "wrong: %s, marked %s" % [bad, marks.keys()])


static func _issues_count(ds: DesignSpace) -> TestResult:
	var l := ds.issues_label
	return TestResult.new("seed: the panel shows only \"2 issues\" in amber, small type",
		l.visible and l.text == "2 issues" and _amber(l.get_theme_color("font_color"))
		and l.get_theme_font_size("font_size") <= LothalTheme.FONT_SIZE_BODY,
		"'%s' visible %s %s" % [l.text, l.visible, l.get_theme_color("font_color")])
