class_name TestCallouts
extends RefCounted
## Callouts that explain why (PLAN Section 8) on the 5": layout, numbers, tracking.
##
## ## The checks that could have passed while proving nothing
##
## - THE SILHOUETTE HERE IS NOT THE LAYOUT'S. The layout uses each mesh's cached convex hull; this
##   test projects EVERY triangle vertex of every drawn mesh at the case's camera, hulls those, and
##   intersects each label's rect with each polygon. A layout that skipped a mesh, or a stale cache,
##   is caught by geometry it never saw.
## - THE UI RECTS HERE ARE THE TEST'S OWN, written from the panels' offsets and sizes (readouts,
##   inspector, tool row, shelf, swap strip, back and home links), not
##   `callout_avoid_rects`, so dropping a panel from that list fails here.
## - NO EMPTY PASSES. Every overlap/crossing case also demands at least MIN_SHOWN labels: an empty
##   layout overlaps nothing.
## - NUMBERS ARE CALLED, NOT COMPARED TO A TYPED STRING. Each callout's last line must start with
##   its table format applied to `Build.call(method)` on a fresh build; the battery and frame
##   numbers are also checked against the catalogue part's own mass_g, and the swap case demands
##   the battery number CHANGES to the new pack's mass.
## - One generated check per case (size x view x state x property), so the failure count means
##   something.

const CLASS_ID := "five_inch"
const SIZES := [Vector2(1280, 720), Vector2(1920, 1080)]
## The three home-view angles (the isometric home and its two neighbours a quarter turn away) and
## one orbited, low view. [name, yaw deg, pitch deg or -1 for the home pitch]
const VIEWS := [["home", 45.0, -1.0], ["home+90", 135.0, -1.0], ["home-90", -45.0, -1.0],
	["orbited low", 200.0, 18.0]]
const MIN_SHOWN := 3


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID), catalog)
	var home: Dictionary = ds.session.selection.duplicate(true)
	for sz in SIZES:
		_set_size(ds, sz)
		for v in VIEWS:
			_view(ds, v)
			ds.update_callouts()
			results.append_array(_geometry(ds, "%dx%d %s" % [sz.x, sz.y, v[0]]))
		for state in ["battery hovered", "battery selected (strip)", "shelf open", "frame selected (tool row)"]:
			_reset(ds, home)
			_state(ds, String(state))
			ds.update_callouts()
			results.append_array(_geometry(ds, "%dx%d home, %s" % [sz.x, sz.y, state]))
		_reset(ds, home)
	_set_size(ds, SIZES[0])
	_reset(ds, home)
	results.append_array(_numbers(ds, catalog))
	results.append(_collapsed_at_rest(ds))
	results.append(_expanded_on_hover(ds))
	results.append(_expanded_on_selection(ds))
	_reset(ds, home)
	results.append(_pocket_says_stiffness(ds))
	_reset(ds, home)
	results.append(_pin_follows_orbit(ds))
	_reset(ds, home)
	results.append(_process_relays_out(ds))
	_reset(ds, home)
	results.append(_swap_moves_number(ds, catalog))
	_reset(ds, home)
	results.append(_hidden_without_build(ds))
	_reset(ds, home)
	results.append(_hidden_while_zoomed(ds))
	results.append_array(_avoid_lists(ds, home))
	ds.free()
	results.append(_cap_six())
	results.append(_drops_lowest_priority())
	results.append(_keeps_pin_order())
	results.append(_opposite_sides_never_overlap())
	return results


static func _set_size(ds: DesignSpace, sz: Vector2) -> void:
	ds.size = sz
	ds.rig.aspect = sz.x / sz.y


static func _view(ds: DesignSpace, v: Array) -> void:
	ds.select("")
	ds.hovered = ""
	ds.rig.snap_home()
	ds.rig.goal_yaw = deg_to_rad(float(v[1]))
	if float(v[2]) >= 0.0:
		ds.rig.goal_pitch = deg_to_rad(float(v[2]))
	ds.rig.snap()


static func _reset(ds: DesignSpace, home: Dictionary) -> void:
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


static func _state(ds: DesignSpace, state: String) -> void:
	match state:
		"battery hovered":
			ds.hovered = "part/battery"
		"battery selected (strip)":
			ds.select("part/battery")
			ds.rig.snap()
			ds.place_picker()
		"shelf open":
			ds.shelf.set_open(true)
			ds.rig.snap()
		"frame selected (tool row)":
			ds.select("frame/arm/BL")
			ds.rig.snap()


# ---------------------------------------------------------------------------
# Geometry, judged on this test's own silhouette and UI rects
# ---------------------------------------------------------------------------

static func _true_silhouette(ds: DesignSpace) -> Array:
	var out: Array = []
	for entry in ds.picks.entries:
		if entry["proxy"]:
			continue
		var mi := entry["node"] as MeshInstance3D
		var pts := (entry["xform"] as Transform3D) * mi.mesh.get_faces()
		var flat := PackedVector2Array()
		for p in pts:
			var ndc := ds.rig.project(p)
			flat.append(Vector2((ndc.x + 1.0) * 0.5 * ds.size.x, (1.0 - ndc.y) * 0.5 * ds.size.y))
		out.append(Geometry2D.convex_hull(flat))
	return out


static func _ui_rects(ds: DesignSpace) -> Dictionary:
	var s := ds.size
	var out := {"back link": Rect2(32, 20, 108, 32), "home link": Rect2(32, s.y - 56, 108, 32),
		"readouts": Rect2(s.x - DesignSpace.PANEL_W - DesignSpace.PANEL_EDGE, 48, DesignSpace.PANEL_W, maxf(352.0, ds.panel.get_combined_minimum_size().y))}
	if ds.inspector.visible:
		var h := ds.inspector.get_combined_minimum_size().y
		out["inspector"] = Rect2(s.x - 340, s.y - 24 - h, 300, h)
	if ds.tool_row.visible:
		out["tool row"] = Rect2(Vector2(32, 64), ds.tool_row.get_combined_minimum_size().max(Vector2(300, 0)))
	if ds.shelf.visible:
		out["shelf"] = Rect2(Vector2(32, 64), ds.shelf.get_combined_minimum_size().max(Vector2(PartsShelf.WIDTH, 0)))
	if ds.strip.visible:
		out["swap strip"] = ds.strip_rect()
	return out


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


static func _geometry(ds: DesignSpace, case: String) -> Array:
	var shown: Array = ds.callouts.shown
	var n := shown.size()
	var few := n < MIN_SHOWN
	var out: Array = []
	# label / label
	var bad := ""
	for i in n:
		for j in range(i + 1, n):
			if (shown[i]["rect"] as Rect2).intersects(shown[j]["rect"] as Rect2):
				bad = "%s over %s" % [shown[i]["id"], shown[j]["id"]]
	out.append(TestResult.new("%s: no label covers another label" % case, bad == "" and not few,
		"%d shown; %s" % [n, bad]))
	# label / silhouette
	bad = ""
	var sil := _true_silhouette(ds)
	for s in shown:
		var rp := _rect_poly(s["rect"])
		for poly in sil:
			if not Geometry2D.intersect_polygons(rp, poly).is_empty():
				bad = "%s over the drone" % s["id"]
				break
	out.append(TestResult.new("%s: no label covers the drone's silhouette" % case, bad == "" and not few,
		"%d shown, %d meshes; %s" % [n, sil.size(), bad]))
	# label / UI
	bad = ""
	var ui := _ui_rects(ds)
	for s in shown:
		for k in ui:
			if (s["rect"] as Rect2).intersects(ui[k] as Rect2):
				bad = "%s over the %s" % [s["id"], k]
	out.append(TestResult.new("%s: no label covers a panel (%s)" % [case, ", ".join(ui.keys())],
		bad == "" and not few, "%d shown; %s" % [n, bad]))
	# on screen, at most six
	bad = ""
	var screen := Rect2(Vector2.ZERO, ds.size)
	for s in shown:
		if not screen.encloses(s["rect"] as Rect2):
			bad = "%s off screen" % s["id"]
	# At most six NUMBERED callouts; warning pins (Section 8 warnings) are counted apart.
	var nc := _callouts_only(shown).size()
	out.append(TestResult.new("%s: 3 to 6 labels, all on screen" % case, bad == "" and nc >= MIN_SHOWN and nc <= 6,
		"%d shown, %d callouts; %s" % [n, nc, bad]))
	# leaders
	bad = ""
	for i in n:
		for j in range(i + 1, n):
			if Geometry2D.segment_intersects_segment(shown[i]["pin"], shown[i]["end"], shown[j]["pin"], shown[j]["end"]) != null:
				bad = "%s x %s" % [shown[i]["id"], shown[j]["id"]]
	out.append(TestResult.new("%s: no two leaders cross" % case, bad == "" and not few, "%d shown; %s" % [n, bad]))
	return out


# ---------------------------------------------------------------------------
# Numbers
# ---------------------------------------------------------------------------

static func _last_line(ds: DesignSpace, id: String) -> String:
	var it := ds.callouts.item(id)
	if it.is_empty():
		return ""
	var lines: Array = it["lines"]
	return String(lines[lines.size() - 1])


## Every callout, shown expanded (hover its anchor), carries `format % Build.call(method)`.
static func _numbers(ds: DesignSpace, catalog: PartsCatalog) -> Array:
	var out: Array = []
	var b := ds.session.build(catalog)
	for e in Callouts.TABLE:
		ds.hovered = String(e["anchor"])
		ds.update_callouts()
		var it := ds.callouts.item(String(e["id"]))
		var method := String(e["method"])
		var want := String(e["format"]) % float(b.call(method))
		var line := _last_line(ds, String(e["id"]))
		out.append(TestResult.new("callout %s shows Build.%s() = %s" % [e["id"], method, want],
			not it.is_empty() and bool(it["expanded"]) and line.begins_with(want + "  "), "label: '%s'" % line))
		var cat := String(e["confidence"])
		var tag := "computed" if cat == "computed" else PartFacts.confidence(String(catalog.get_part(String(ds.session.selection.get(cat, ""))).get("source", "")))
		out.append(TestResult.new("callout %s carries its confidence tag '%s'" % [e["id"], tag],
			line.ends_with("  " + tag), "label: '%s'" % line))
	ds.hovered = ""
	var pack := catalog.get_part(String(ds.session.selection["battery"]))
	out.append(TestResult.new("Build.battery_mass_g is the fitted pack's catalogue mass",
		is_equal_approx(b.battery_mass_g(), float(pack["mass_g"])), "%s vs %s" % [b.battery_mass_g(), pack["mass_g"]]))
	var frame := catalog.get_part(String(ds.session.selection["frame"]))
	out.append(TestResult.new("Build.frame_mass_g is the unedited frame's catalogue mass",
		is_equal_approx(b.frame_mass_g(), float(frame["mass_g"])), "%s vs %s" % [b.frame_mass_g(), frame["mass_g"]]))
	return out


static func _swap_moves_number(ds: DesignSpace, catalog: PartsCatalog) -> TestResult:
	var before := ds.session.build(catalog).battery_mass_g()
	var other := ""
	for opt in PartSwap.options(ds.session, catalog, "battery", {}):
		var id := String(opt["id"])
		if opt["ok"] and id != String(ds.session.selection["battery"]) \
				and not is_equal_approx(float(catalog.get_part(id).get("mass_g", 0.0)), before):
			other = id
			break
	if other == "":
		return TestResult.new("a battery swap moves the battery callout's number", false, "no other pack fits")
	ds.choose("battery", other)
	ds.hovered = "part/battery"
	ds.update_callouts()
	var after := ds.session.build(catalog).battery_mass_g()
	var line := _last_line(ds, "battery")
	var want := "%.0f g pack" % float(catalog.get_part(other)["mass_g"])
	return TestResult.new("a battery swap moves the battery callout's number",
		line.begins_with(want + "  ") and not is_equal_approx(before, after),
		"%s -> '%s' (want %s)" % [other, line, want])


# ---------------------------------------------------------------------------
# States
# ---------------------------------------------------------------------------

static func _collapsed_at_rest(ds: DesignSpace) -> TestResult:
	ds.update_callouts()
	var bad := ""
	for s in ds.callouts.shown:
		if s["expanded"] or (s["rect"] as Rect2).size.x >= CalloutLayer.EXPANDED_W or (s["rect"] as Rect2).size.y > 40.0:
			bad = String(s["id"])
	return TestResult.new("at rest every label is collapsed (number + name only)",
		bad == "" and ds.callouts.shown.size() >= MIN_SHOWN, "%d shown; %s" % [ds.callouts.shown.size(), bad])


static func _expanded_on_hover(ds: DesignSpace) -> TestResult:
	ds.hovered = "part/battery"
	ds.update_callouts()
	var it := ds.callouts.item("battery")
	var others_collapsed := ds.callouts.shown.all(func(s): return s["id"] == "battery" or not s["expanded"])
	ds.hovered = ""
	var ok: bool = not it.is_empty() and it["expanded"] and String(it["lines"][0]) == String(Callouts.entry("battery")["why"]) \
		and (it["rect"] as Rect2).size.y > 40.0 and others_collapsed
	return TestResult.new("hovering the battery expands its callout with its why-sentence", ok, str(it.get("lines", [])))


static func _expanded_on_selection(ds: DesignSpace) -> TestResult:
	ds.select("part/motor/BL")
	ds.rig.snap()
	ds.place_picker()
	ds.update_callouts()
	var it := ds.callouts.item("motors")
	return TestResult.new("selecting any motor expands the motors callout",
		not it.is_empty() and it["expanded"], str(it.get("lines", [])))


static func _pocket_says_stiffness(ds: DesignSpace) -> TestResult:
	ds.hovered = "frame/pocket/arm_FL/1"
	ds.update_callouts()
	var it := ds.callouts.item("frame")
	ds.hovered = ""
	var text := " ".join(it.get("lines", []))
	return TestResult.new("hovering a pocket expands the frame callout, which says stiffness is not modelled",
		not it.is_empty() and it["expanded"] and text.contains("Stiffness is not modelled"), text)


static func _pin_px(ds: DesignSpace, address: String) -> Vector2:
	var ndc := ds.rig.project(ds.picks.box_of(address).get_center())
	return Vector2((ndc.x + 1.0) * 0.5 * ds.size.x, (1.0 - ndc.y) * 0.5 * ds.size.y)


static func _pin_follows_orbit(ds: DesignSpace) -> TestResult:
	var a := ds.callouts.item("battery")
	ds.rig.orbit(deg_to_rad(70.0), 0.0)
	ds.rig.snap()
	ds.update_callouts()
	var b := ds.callouts.item("battery")
	if a.is_empty() or b.is_empty():
		return TestResult.new("the battery pin follows the battery when the camera orbits", false, "not shown")
	var want := _pin_px(ds, "part/battery")
	var moved := (a["pin"] as Vector2).distance_to(b["pin"])
	return TestResult.new("the battery pin follows the battery when the camera orbits",
		(b["pin"] as Vector2).distance_to(want) < 0.5 and moved > 20.0, "moved %.1f px; off by %.2f" % [moved, (b["pin"] as Vector2).distance_to(want)])


## The frame loop re-lays the callouts out: an orbit followed by one _process step moves the pins.
static func _process_relays_out(ds: DesignSpace) -> TestResult:
	ds._process(0.0)   # the frame loop has seen this view once (it skips a frame nothing changed in)
	var a := ds.callouts.item("motors")
	ds.rig.orbit(deg_to_rad(-60.0), 0.0)
	ds._process(2.0)
	var b := ds.callouts.item("motors")
	var want := _pin_px(ds, "part/motor/FR")
	var ok: bool = not a.is_empty() and not b.is_empty() and (b["pin"] as Vector2).distance_to(want) < 0.5 \
		and (a["pin"] as Vector2).distance_to(b["pin"]) > 20.0
	return TestResult.new("each frame re-lays the callouts out for the camera (orbit + one _process)", ok,
		"%s -> %s, want %s" % [a.get("pin"), b.get("pin"), want])


static func _hidden_without_build(ds: DesignSpace) -> TestResult:
	var before := ds.callouts.shown.size()
	ds.set_part("frame", "")
	var no_build := ds.session.build(ds._catalog) == null
	ds.update_callouts()
	# The numbered callouts go; the missing frame's warning pin (Section 8 warnings) stays.
	var left := _callouts_only(ds.callouts.shown).size()
	return TestResult.new("with no build there are no callouts", before >= MIN_SHOWN and no_build and left == 0,
		"before %d, build null %s, after %d" % [before, no_build, left])


## The numbered callouts among what is shown (warning pins are their own kind, capped separately).
static func _callouts_only(shown: Array) -> Array:
	return shown.filter(func(s): return String(s.get("kind", "callout")) == "callout")


static func _hidden_while_zoomed(ds: DesignSpace) -> TestResult:
	ds.rig.zoom_toward(0.3, Vector2.ZERO)
	ds.rig.snap()
	ds.update_callouts()
	return TestResult.new("zoomed in, the callouts step aside", ds.rig.is_zoomed_in() and ds.callouts.shown.is_empty(),
		"%d shown" % ds.callouts.shown.size())


# ---------------------------------------------------------------------------
# The pure layout
# ---------------------------------------------------------------------------

static func _items(n: int, x: float, y0: float, dy: float) -> Array:
	var out: Array = []
	for i in n:
		out.append({"id": "i%d" % i, "pin": Vector2(x, y0 + dy * i), "size": Vector2(80, 24), "priority": i})
	return out


static func _cap_six() -> TestResult:
	var items := _items(9, 640, 80, 60)
	items.reverse()   # least important first, so the layout's own priority sort is what is tested
	var placed := Callouts.layout(items, [], [], Vector2(1280, 720))
	var ids := placed.map(func(p): return p["id"])
	return TestResult.new("layout shows at most six of nine items, the six most important",
		ids.size() == 6 and ids == ["i0", "i1", "i2", "i3", "i4", "i5"], str(ids))


static func _drops_lowest_priority() -> TestResult:
	# A drone filling the screen but for a 60 px strip on the left and right: two rows each fit.
	var size := Vector2(1280, 720)
	var drone := [PackedVector2Array([Vector2(130, 0), Vector2(1150, 0), Vector2(1150, 720), Vector2(130, 720)])]
	var items := _items(6, 640, 300, 10)
	for it in items:
		it["size"] = Vector2(100, 400)
	var placed := Callouts.layout(items, drone, [], size)
	var ids := placed.map(func(p): return p["id"])
	return TestResult.new("a crowded layout keeps its most important items and drops the rest",
		ids.size() == 2 and ids == ["i0", "i1"], str(ids))


## Two pins close together on the left with the space below the first label blocked: the second
## label must not jump above the first (its leader would then cross); it goes elsewhere or not at all.
static func _keeps_pin_order() -> TestResult:
	var items := [{"id": "upper", "pin": Vector2(300, 400), "size": Vector2(80, 24), "priority": 0},
		{"id": "lower", "pin": Vector2(300, 410), "size": Vector2(80, 24), "priority": 1}]
	var placed := Callouts.layout(items, [], [Rect2(0, 424, 1280, 296)], Vector2(1280, 720))
	var y := {}
	for p in placed:
		if p["side"] == "left":
			y[p["id"]] = (p["rect"] as Rect2).position.y
	var ok: bool = y.has("upper") and (not y.has("lower") or y["lower"] > y["upper"])
	return TestResult.new("labels on one side keep their pins' top-to-bottom order", ok, str(y))


## Labels on opposite sides can meet: the left side walled off sends the first label right, and the
## second pin's own left label would land on it.
static func _opposite_sides_never_overlap() -> TestResult:
	var items := [{"id": "a", "pin": Vector2(300, 300), "size": Vector2(80, 24), "priority": 0},
		{"id": "b", "pin": Vector2(420, 300), "size": Vector2(80, 24), "priority": 1}]
	var placed := Callouts.layout(items, [], [Rect2(0, 0, 290, 720)], Vector2(1280, 720))
	var bad := placed.size() < 2
	for i in placed.size():
		for j in range(i + 1, placed.size()):
			if (placed[i]["rect"] as Rect2).intersects(placed[j]["rect"] as Rect2):
				bad = true
	return TestResult.new("labels on opposite sides never overlap each other", not bad,
		str(placed.map(func(p): return [p["id"], p["side"], p["rect"]])))


## The avoid list holds every panel that is showing, each at least as large as this test's own rect.
static func _avoid_lists(ds: DesignSpace, home: Dictionary) -> Array:
	var out: Array = []
	for state in ["battery selected (strip)", "shelf open", "frame selected (tool row)"]:
		_reset(ds, home)
		_state(ds, String(state))
		var ui := _ui_rects(ds)
		var avoid := ds.callout_avoid_rects()
		for k in ui:
			var r: Rect2 = ui[k]
			var held := avoid.any(func(a): return (a as Rect2).grow(0.5).encloses(r))
			out.append(TestResult.new("%s: the callouts avoid the %s" % [state, k], held, "%s in %s" % [r, avoid]))
	return out
