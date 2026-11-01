class_name TestDesignShelf
extends RefCounted
## Shelf, drag and drop, snap, remove on the 5" (PLAN Section 5), the logic half: PartSnap and the
## DesignSession methods drop / remove / flight_state / shelf. No drawing.
##
## ## The checks that could have passed while proving nothing
##
## - Drop points and expected mounts are made HERE from the GLB's own nodes (their drawn boxes), not
##   from PartSnap.mount_map, so a map that put a mount in the wrong place fails the drop near it.
## - CROSS DROPS: a part released right on ANOTHER category's mount (a battery on the camera, a
##   motor on a prop, a receiver on the battery) must still go on its own mount. A resolver that
##   took the nearest mount without looking at the part's category fails every one of them.
## - The wrong-pattern parts are found in the catalog by their pattern (a motor not drilled for the
##   arm pad, a 20x20 board on the 30.5 stack), and a drop of each must be refused with the direct
##   build's own blocking warning, so a resolver that skipped the mounting check fails.
## - Readouts after each drop are compared with `==` against a `Build.from_ids` made HERE from the
##   selection the test expects, not with anything the session computed.
## - "Cannot fly" is checked as the panel shows it: every readout label a dash, and no digit in it.
## - Undo/redo compares readouts, selection and the frame document with `==` at every step.
## - One test per case: each failure counts once (feedback: loop tests hide coverage).

const CLASS_ID := "five_inch"
const GLB := "res://assets/models/classes/five_inch.glb"
const HARD := [&"motor_mount", &"prop_clearance", &"stack_mount", &"fc_stack_mount"]
const KEYS := ["auw_g", "thrust_to_weight", "hover_throttle", "flight_time_min", "top_speed_kmh"]
const DASH := "—"
## 20 mm above a mount's drawn centre: "near", not on it.
const NEAR := Vector3(0.0, 0.02, 0.0)
## category -> GLB node names it mounts on, as the TEST knows the model (not PartSnap's table).
const NODES := {"battery": ["battery"], "camera": ["camera"], "flight_controller": ["stack"],
	"esc": ["stack"], "receiver": ["stack"], "vtx": ["antennas"], "antenna": ["antennas"]}


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var root: Node = (load(GLB) as PackedScene).instantiate()
	var map := PartSnap.mount_map(root)
	var boxes := _boxes(root)
	var home := DesignSession.default_for_class(CLASS_ID).selection.duplicate(true)

	results.append(_test_map(map, boxes))
	# One drop per part type near its own mount; four corners for motors, props and guards.
	for cat in NODES:
		results.append(_test_drop(catalog, map, boxes, home, String(cat), String(NODES[cat][0])))
	for corner in PartSnap.CORNERS:
		results.append(_test_drop(catalog, map, boxes, home, "motor", "motor_" + corner))
		results.append(_test_drop(catalog, map, boxes, home, "propeller", "prop_" + corner))
		results.append(_test_drop(catalog, map, boxes, home, "guard", "prop_" + corner))
	# Cross drops: on another category's mount, still to its own.
	results.append(_test_cross(catalog, map, boxes, home, "battery", "camera", "part/battery"))
	results.append(_test_cross(catalog, map, boxes, home, "motor", "prop_FR", "part/motor/FR"))
	results.append(_test_cross(catalog, map, boxes, home, "propeller", "motor_BL", "part/prop/BL"))
	results.append(_test_cross(catalog, map, boxes, home, "camera", "stack", "part/camera"))
	results.append(_test_cross(catalog, map, boxes, home, "receiver", "battery", "part/stack"))
	results.append(_test_cross(catalog, map, boxes, home, "antenna", "battery", "part/antennas"))
	# Refusals.
	results.append(_test_wrong_pattern(catalog, map, boxes, home, "motor", "motor_FL"))
	results.append(_test_wrong_pattern(catalog, map, boxes, home, "flight_controller", "stack"))
	results.append(_test_wrong_pattern(catalog, map, boxes, home, "esc", "stack"))
	results.append(_test_wrong_pattern(catalog, map, boxes, home, "propeller", "prop_FL"))
	results.append(_test_no_mount(catalog, map, boxes, home))
	results.append(_test_far(catalog, map, home))
	results.append(_test_edge(catalog, map, boxes, home, 0.05, true))
	results.append(_test_edge(catalog, map, boxes, home, 0.07, false))
	results.append(_test_preview(catalog, map, boxes, home, root))
	results.append(_test_same_part(catalog, map, boxes, home))
	# Remove.
	results.append(_test_remove_battery_state(catalog))
	results.append(_test_remove_battery_dashes(catalog))
	results.append(_test_remove_battery_panel(catalog))
	results.append(_test_remove_then_drop(catalog, map, boxes, home))
	results.append(_test_drop_on_cannot_fly(catalog, map, boxes, home))
	results.append(_test_wrong_pattern_on_cannot_fly(catalog, map, boxes, home))
	results.append(_test_remove_at_motor(catalog, home))
	results.append(_test_remove_optional(catalog, home))
	results.append(_test_remove_frame(home))
	# Shelf.
	results.append(_test_shelf_lists(catalog, home))
	results.append(_test_replace_to_shelf(catalog, map, boxes, home))
	results.append(_test_remove_to_shelf(catalog, home))
	# History.
	results.append_array(_test_history(catalog, map, boxes, home))
	root.free()
	return results


## GLB node name -> its drawn box in the root frame, every visible mesh; plus "*" = the whole drone.
static func _boxes(root: Node) -> Dictionary:
	var out := {}
	var all := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or String(mi.name).begins_with("pick_"):
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var box := xf * mi.get_aabb()
		out[String(mi.name)] = {"box": box, "xf": xf}
		all = box if first else all.merge(box)
		first = false
	out["*"] = {"box": all, "xf": Transform3D.IDENTITY}
	return out


static func _at(boxes: Dictionary, node_name: String) -> Vector3:
	return (boxes[node_name]["box"] as AABB).get_center()


static func _address(node_name: String) -> String:
	for pre in ["motor_", "prop_"]:
		if node_name.begins_with(pre):
			return "part/%s/%s" % [pre.trim_suffix("_"), node_name.substr(len(pre))]
	return "part/" + node_name


static func _direct(catalog: PartsCatalog, sel: Dictionary) -> Build:
	var comps := {}
	for c in Build.OPTIONAL_COMPONENTS:
		comps[c] = String(sel.get(c, ""))
	return Build.from_ids(catalog, String(sel["frame"]), String(sel["motor"]),
		String(sel["propeller"]), String(sel["battery"]), String(sel["esc"]),
		String(sel["flight_controller"]), comps, null, String(sel.get("guard", "")), {},
		String(sel.get("mount", "")))


static func _hard(b: Build) -> Array:
	return b.warnings().filter(func(w): return w.severity == BuildWarning.Severity.IMPOSSIBLE and HARD.has(w.id))


static func _fresh() -> DesignSession:
	return DesignSession.default_for_class(CLASS_ID)


## A catalog part of `category`, not fitted on `home`, whose direct build has no hard misfit.
static func _fitting(catalog: PartsCatalog, home: Dictionary, category: String) -> String:
	for p in catalog.list_category(category):
		var id := String(p["part_id"])
		if id == String(home.get(category, "")):
			continue
		var b := _direct(catalog, home.merged({category: id}, true))
		if b != null and _hard(b).is_empty():
			return id
	return ""


## A part of `category` whose pattern disagrees with the 5" frame (found by pattern, then confirmed
## by the direct build's hard warning).
static func _misfit(catalog: PartsCatalog, home: Dictionary, category: String) -> String:
	var frame := catalog.get_part(String(home["frame"]))
	for p in catalog.list_category(category):
		var id := String(p["part_id"])
		var wrong := false
		match category:
			"motor":
				var pat := String(p.get("mount_pattern", ""))
				wrong = pat != "" and pat != String(frame["specs"].get("motor_mount", ""))
			"propeller":
				wrong = float(p["specs"]["diameter_inches"]) > float(frame["specs"].get("max_prop_inches", 99.0))
			_:
				wrong = String(p.get("mounting", {}).get("pattern", "")).begins_with("20")
		if wrong and not _hard(_direct(catalog, home.merged({category: id}, true))).is_empty():
			return id
	return ""


static func _same_readouts(s: DesignSession, catalog: PartsCatalog, sel: Dictionary) -> bool:
	var want := DesignSession.readouts_of(_direct(catalog, sel))
	return not want.is_empty() and s.readouts(catalog) == want


static func _test_map(map: Dictionary, boxes: Dictionary) -> TestResult:
	var want := ["part/battery", "part/camera", "part/stack", "part/antennas"]
	for c in PartSnap.CORNERS:
		want.append("part/motor/" + c)
		want.append("part/prop/" + c)
	var mounts: Dictionary = map["mounts"]
	var bad: Array = []
	for a in want:
		var node := String(a).replace("part/", "").replace("/", "_")
		if not mounts.has(a) or (mounts[a]["centre"] as Vector3).distance_to(_at(boxes, node)) > 1e-6:
			bad.append(a)
	var b: AABB = map["bounds"]
	var ok := bad.is_empty() and b.position.is_equal_approx(boxes["*"]["box"].position) \
		and b.size.is_equal_approx(boxes["*"]["box"].size)
	return TestResult.new("the 5\" mount map has every mount at its drawn part, and the drone's bounds",
		ok, "bad %s, bounds %s" % [bad, b])


static func _test_drop(catalog: PartsCatalog, map: Dictionary, boxes: Dictionary, home: Dictionary,
		category: String, node_name: String) -> TestResult:
	var id := _fitting(catalog, home, category)
	var s := _fresh()
	var name := "a %s dropped near %s attaches to %s, readouts = direct Build" % [category, node_name, _address(node_name)]
	if id == "":
		return TestResult.new(name, false, "no fitting %s in the catalog" % category)
	var v := s.drop(catalog, id, _at(boxes, node_name) + NEAR, map)
	var want := home.merged({category: id}, true)
	var ok: bool = v["kind"] == "snap" and v["mount"] == _address(node_name) and v["category"] == category \
		and s.selection == want and v["replaced"] == String(home.get(category, "")) \
		and _same_readouts(s, catalog, want) and s.can_undo()
	return TestResult.new(name, ok, "%s %s -> %s %s (%s)" % [category, id, v["kind"], v["mount"], v["reason"]])


static func _test_cross(catalog: PartsCatalog, map: Dictionary, boxes: Dictionary, home: Dictionary,
		category: String, on_node: String, want_mount: String) -> TestResult:
	var id := _fitting(catalog, home, category)
	var s := _fresh()
	var v := s.drop(catalog, id, _at(boxes, on_node), map)
	var want := home.merged({category: id}, true)
	var ok: bool = v["kind"] == "snap" and v["mount"] == want_mount and s.selection == want \
		and _same_readouts(s, catalog, want)
	return TestResult.new("a %s released right on %s still goes on %s, not the nearest mount" % [category, on_node, want_mount],
		ok, "%s -> %s %s, sel %s" % [id, v["kind"], v["mount"], s.selection.get(category)])


static func _test_wrong_pattern(catalog: PartsCatalog, map: Dictionary, boxes: Dictionary,
		home: Dictionary, category: String, node_name: String) -> TestResult:
	var id := _misfit(catalog, home, category)
	var name := "a wrong-pattern %s dropped on %s is refused with the blocking warning, nothing changes" % [category, node_name]
	if id == "":
		return TestResult.new(name, false, "no misfit %s in the catalog" % category)
	var s := _fresh()
	var want := PartSwap.first_sentence(_hard(_direct(catalog, home.merged({category: id}, true)))[0].message)
	var v := s.drop(catalog, id, _at(boxes, node_name) + NEAR, map)
	var ok: bool = v["kind"] == "refused" and v["reason"] == want and v["reason"] != "" \
		and v["mount"] == "" and not String(v["reason"]).contains("\n") \
		and s.selection == home and not s.can_undo()
	return TestResult.new(name, ok, "%s: %s '%s' vs '%s'" % [id, v["kind"], v["reason"], want])


static func _test_no_mount(catalog: PartsCatalog, map: Dictionary, boxes: Dictionary, home: Dictionary) -> TestResult:
	var gps: Array = catalog.list_category("gps")
	var s := _fresh()
	var v := s.drop(catalog, String(gps[0]["part_id"]) if not gps.is_empty() else "", _at(boxes, "stack"), map)
	var ok: bool = not gps.is_empty() and v["kind"] == "refused" and String(v["reason"]) != "" \
		and v["mount"] == "" and s.selection == home and not s.can_undo()
	return TestResult.new("a GPS (no GPS mount on the 5\") dropped on the drone is refused with a reason",
		ok, "%s '%s'" % [v["kind"], v["reason"]])


static func _test_far(catalog: PartsCatalog, map: Dictionary, home: Dictionary) -> TestResult:
	var s := _fresh()
	var v := s.drop(catalog, _fitting(catalog, home, "battery"), Vector3(0.0, 0.6, 0.0), map)
	var ok: bool = v["kind"] == "nothing" and v["mount"] == "" and s.selection == home and not s.can_undo() \
		and s.readouts(catalog) == DesignSession.readouts_of(_direct(catalog, home))
	return TestResult.new("a battery dropped 0.6 m above the drone does nothing", ok, str(v["kind"]))


static func _test_edge(catalog: PartsCatalog, map: Dictionary, boxes: Dictionary, home: Dictionary,
		beyond: float, snaps: bool) -> TestResult:
	var b: AABB = boxes["*"]["box"]
	var p := Vector3(b.end.x + beyond, b.get_center().y, b.get_center().z)
	var s := _fresh()
	var id := _fitting(catalog, home, "battery")
	var v := s.drop(catalog, id, p, map)
	var ok: bool = (v["kind"] == "snap" and v["mount"] == "part/battery" and s.selection["battery"] == id) if snaps \
		else (v["kind"] == "nothing" and s.selection == home)
	return TestResult.new("a battery dropped %d mm beside the drone's side %s" % [int(beyond * 1000), "snaps (generous capture)" if snaps else "does nothing"],
		ok, "%s %s" % [v["kind"], v["mount"]])


static func _test_preview(catalog: PartsCatalog, map: Dictionary, boxes: Dictionary, home: Dictionary,
		root: Node) -> TestResult:
	var s := _fresh()
	var id := _fitting(catalog, home, "motor")
	var v := PartSnap.resolve(s, catalog, id, _at(boxes, "motor_BR") + NEAR, map)
	var corners: Array = PartSnap.CORNERS.map(func(c): return "part/motor/" + c)
	var drawn := (root.find_child("motor_BR", true, false) as Node3D).transform
	var ok: bool = v["kind"] == "snap" and v["mount"] == "part/motor/BR" \
		and (v["ghost_xf"] as Transform3D).is_equal_approx(drawn) \
		and (v["centre"] as Vector3).distance_to(_at(boxes, "motor_BR")) < 1e-6 \
		and (v["mounts"] as Array).size() == 4 and corners.all(func(c): return (v["mounts"] as Array).has(c)) \
		and v["replaces"] == home["motor"] and s.selection == home and not s.can_undo()
	return TestResult.new("the drag preview names the target mount, its drawn transform, all four motor corners, and changes nothing",
		ok, "%s %s mounts %s" % [v["kind"], v["mount"], v["mounts"]])


static func _test_same_part(catalog: PartsCatalog, map: Dictionary, boxes: Dictionary, home: Dictionary) -> TestResult:
	var s := _fresh()
	var v := s.drop(catalog, String(home["battery"]), _at(boxes, "battery"), map)
	return TestResult.new("dropping the battery already fitted snaps but adds no undo step",
		v["kind"] == "snap" and s.selection == home and not s.can_undo(), str(v["kind"]))


static func _test_remove_battery_state(catalog: PartsCatalog) -> TestResult:
	var s := _fresh()
	var r := s.remove("battery")
	var st := s.flight_state(catalog)
	var ok: bool = r["ok"] and s.selection["battery"] == "" and not st["flies"] \
		and st["missing"] == ["battery"] and st["line"] == "no battery: cannot fly" and s.can_undo()
	return TestResult.new("removing the battery leaves the slot empty: \"no battery: cannot fly\"", ok, str(st))


static func _test_remove_battery_dashes(catalog: PartsCatalog) -> TestResult:
	var s := _fresh()
	s.remove("battery")
	var r := s.readouts(catalog)
	var shown: Array = KEYS.map(func(k): return DesignSpace.format_readout(k, r))
	var ok: bool = r.is_empty() and shown.all(func(t): return t == DASH)
	return TestResult.new("and its readouts are absent, formatted as dashes, not zeros", ok, "%s %s" % [r, shown])


static func _test_remove_battery_panel(catalog: PartsCatalog) -> TestResult:
	var ds := DesignSpace.new(_fresh(), catalog)
	ds.session.remove("battery")
	ds.refresh()
	var texts: Array = KEYS.map(func(k): return (ds.value_labels[k] as Label).text)
	var digit := RegEx.create_from_string("[0-9]")
	var ok: bool = texts.all(func(t): return t == DASH and digit.search(String(t)) == null)
	ds.free()
	return TestResult.new("and the Design Space panel shows a dash in every readout", ok, str(texts))


static func _test_remove_then_drop(catalog: PartsCatalog, map: Dictionary, boxes: Dictionary, home: Dictionary) -> TestResult:
	var s := _fresh()
	s.remove("battery")
	var id := _fitting(catalog, home, "battery")
	var v := s.drop(catalog, id, _at(boxes, "battery") + NEAR, map)
	var want := home.merged({"battery": id}, true)
	var ok: bool = v["kind"] == "snap" and v["replaced"] == "" and s.flight_state(catalog)["flies"] \
		and s.flight_state(catalog)["line"] == "" and _same_readouts(s, catalog, want)
	return TestResult.new("a battery dropped into the empty slot flies again, readouts = direct Build", ok, str(v["kind"]))


static func _test_drop_on_cannot_fly(catalog: PartsCatalog, map: Dictionary, boxes: Dictionary, home: Dictionary) -> TestResult:
	var s := _fresh()
	s.remove("battery")
	var id := _fitting(catalog, home, "motor")
	var v := s.drop(catalog, id, _at(boxes, "motor_FL") + NEAR, map)
	var ok: bool = v["kind"] == "snap" and s.selection["motor"] == id and s.selection["battery"] == "" \
		and s.readouts(catalog).is_empty()
	return TestResult.new("a motor dropped on a drone with no battery is judged on its mounting and attaches",
		ok, "%s '%s'" % [v["kind"], v["reason"]])


static func _test_wrong_pattern_on_cannot_fly(catalog: PartsCatalog, map: Dictionary, boxes: Dictionary, home: Dictionary) -> TestResult:
	var s := _fresh()
	s.remove("battery")
	var before := s.selection.duplicate(true)
	var v := s.drop(catalog, _misfit(catalog, home, "motor"), _at(boxes, "motor_FL") + NEAR, map)
	var ok: bool = v["kind"] == "refused" and String(v["reason"]).contains(String(catalog.get_part(String(home["frame"]))["specs"]["motor_mount"])) \
		and s.selection == before
	return TestResult.new("and a wrong-pattern motor on that drone is still refused for its bolt pattern", ok, "'%s'" % v["reason"])


static func _test_remove_at_motor(catalog: PartsCatalog, home: Dictionary) -> TestResult:
	var s := _fresh()
	var r := s.remove_at("part/motor/FL")
	var st := s.flight_state(catalog)
	var ok: bool = r["ok"] and s.selection == home.merged({"motor": ""}, true) and st["line"] == "no motors: cannot fly"
	return TestResult.new("removing the motor on arm FL takes the motors off: \"no motors: cannot fly\"", ok, str(st))


static func _test_remove_optional(catalog: PartsCatalog, home: Dictionary) -> TestResult:
	var s := _fresh()
	var r := s.remove_at("part/camera")
	var want := home.merged({"camera": ""}, true)
	var ok: bool = r["ok"] and s.selection == want and s.flight_state(catalog)["flies"] \
		and _same_readouts(s, catalog, want)
	return TestResult.new("removing the camera (optional) still flies, readouts = direct Build without it", ok, str(r))


static func _test_remove_frame(home: Dictionary) -> TestResult:
	var s := _fresh()
	var r := s.remove("frame")
	return TestResult.new("the frame cannot be removed (refused with a reason, nothing changes)",
		not r["ok"] and String(r["reason"]) != "" and s.selection == home and not s.can_undo(), str(r))


static func _shelf_ids(s: DesignSession, catalog: PartsCatalog, category: String) -> Array:
	for row in s.shelf(catalog):
		if row["category"] == category:
			return (row["parts"] as Array).map(func(p): return String(p["id"]))
	return []


static func _test_shelf_lists(catalog: PartsCatalog, home: Dictionary) -> TestResult:
	var s := _fresh()
	var bad: Array = []
	var cats: Array = s.shelf(catalog).map(func(r): return String(r["category"]))
	for cat in ["battery", "motor", "propeller", "guard", "flight_controller", "esc", "receiver", "camera", "vtx", "antenna"]:
		var want: Array = []
		for p in catalog.list_category(cat):
			if String(p["part_id"]) != String(home.get(cat, "")):
				want.append(String(p["part_id"]))
		if not cats.has(cat) or _shelf_ids(s, catalog, cat) != want:
			bad.append(cat)
	return TestResult.new("the shelf lists, by category, every catalog part that is not fitted", bad.is_empty(), str(bad))


static func _test_replace_to_shelf(catalog: PartsCatalog, map: Dictionary, boxes: Dictionary, home: Dictionary) -> TestResult:
	var s := _fresh()
	var id := _fitting(catalog, home, "battery")
	var v := s.drop(catalog, id, _at(boxes, "battery") + NEAR, map)
	var shelf := _shelf_ids(s, catalog, "battery")
	var ok: bool = v["replaced"] == home["battery"] and shelf.has(String(home["battery"])) and not shelf.has(id)
	return TestResult.new("replacing the battery sends the old pack back to the shelf, and the new one leaves it",
		ok, "replaced %s" % v["replaced"])


static func _test_remove_to_shelf(catalog: PartsCatalog, home: Dictionary) -> TestResult:
	var s := _fresh()
	var before := _shelf_ids(s, catalog, "camera")
	s.remove("camera")
	var after := _shelf_ids(s, catalog, "camera")
	return TestResult.new("a removed camera is back on the shelf",
		not before.has(String(home["camera"])) and after.has(String(home["camera"])), "")


## drop battery, drill, remove battery, drop motor; then undo x4 and redo x4, every state `==`.
static func _test_history(catalog: PartsCatalog, map: Dictionary, boxes: Dictionary, home: Dictionary) -> Array:
	var results: Array = []
	var s := _fresh()
	var states: Array = [_state(s, catalog)]
	s.drop(catalog, _fitting(catalog, home, "battery"), _at(boxes, "battery") + NEAR, map)
	states.append(_state(s, catalog))
	var drilled := _drill_somewhere(s)
	states.append(_state(s, catalog))
	s.remove("battery")
	states.append(_state(s, catalog))
	s.drop(catalog, _fitting(catalog, home, "motor"), _at(boxes, "motor_FR") + NEAR, map)
	states.append(_state(s, catalog))
	results.append(TestResult.new("history setup: four distinct steps (drop, drill, remove, drop)",
		drilled and _distinct(states), "drilled %s" % drilled))
	var labels := ["the motor drop", "the battery removal", "the drill", "the battery drop"]
	for i in range(4):
		s.undo()
		var want: Dictionary = states[3 - i]
		results.append(TestResult.new("undo of %s restores the state before it bit for bit" % labels[i],
			_state(s, catalog) == want, ""))
	results.append(TestResult.new("after four undos the readouts equal a fresh default session's exactly",
		s.readouts(catalog) == _fresh().readouts(catalog) and not s.can_undo(), ""))
	for i in range(4):
		s.redo()
		results.append(TestResult.new("redo %d gives back step %d bit for bit" % [i + 1, i + 1],
			_state(s, catalog) == states[i + 1], ""))
	return results


static func _state(s: DesignSession, catalog: PartsCatalog) -> Dictionary:
	return {"selection": s.selection.duplicate(true), "readouts": s.readouts(catalog),
		"doc": s.frame_document().to_dictionary() if s.frame_document() != null else {}}


static func _distinct(states: Array) -> bool:
	for i in states.size():
		for j in range(i + 1, states.size()):
			if states[i] == states[j]:
				return false
	return true


## Drills an M3 hole somewhere legal on the top plate: the first grid point the session accepts.
static func _drill_somewhere(s: DesignSession) -> bool:
	var plate := s.plate_of_mesh("frame_plate_top")
	if plate < 0:
		return false
	for x in range(-15, 16, 5):
		for y in range(-60, 61, 5):
			if s.drill(plate, Vector2(x, y), 3.0)["ok"]:
				return true
	return false
