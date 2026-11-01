class_name TestDesignPicking
extends RefCounted
## Picking every part and every frame region of the 5" (PLAN Section 2).
##
## ## The checks that could have passed while proving nothing
##
## - Reachability is ONE GENERATED TEST PER ADDRESS, not a loop with one verdict, so the failure
##   count says how many addresses broke. Each one aims the real camera rig at a point ON that
##   address (a triangle centroid of its own mesh, not a box centre that can sit in empty air) from
##   a fixed set of angles and clicks through `DesignSpace.click_at`, the path the mouse takes.
## - The address list is pinned against the names the export must carry, so a registry that lost
##   the standoffs would not pass by having nothing to test.
## - "Floor selects nothing" first selects something, so a click that did nothing would fail it.
## - The inspector's mass is compared with the catalog entry of a battery that is NOT the default,
##   after a swap, so a panel that cached the first selection fails.
## - Click versus drag goes through `_gui_input` with real mouse events.

const CLASS_ID := "five_inch"
## yaw degrees x pitch degrees, the fixed camera angles every address is tried from.
const YAWS := [45.0, 135.0, 225.0, 315.0, 0.0, 90.0, 180.0, 270.0]
const PITCHES := [60.0, 30.0, 8.0, 88.0]
## A click selects the front thing; each click again in place steps one deeper. An address must be
## selected within this many clicks from some fixed angle.
const MAX_DEPTH := 4
const REQUIRED := ["part/battery", "part/camera", "part/stack", "part/antennas", "part/wires",
	"frame/plate/top", "frame/plate/bottom", "frame/tail_mount"]


static func run() -> Array:
	var results: Array = []
	var ds := DesignSpace.new(DesignSession.default_for_class(CLASS_ID))
	results.append_array(_test_registry_shape(ds))
	for address in ds.picks.addresses():
		results.append(_test_reachable(ds, String(address)))
	results.append_array(_test_front_to_back(ds))
	results.append_array(_test_floor_selects_nothing(ds))
	results.append_array(_test_hover_and_escape(ds))
	results.append_array(_test_inspector_numbers(ds))
	results.append_array(_test_click_not_drag(ds))
	results.append_array(_test_rebuild_regenerates(ds))
	ds.free()
	return results


static func _test_registry_shape(ds: DesignSpace) -> Array:
	var results: Array = []
	var addrs := ds.picks.addresses()
	var missing: Array = []
	var want := REQUIRED.duplicate()
	for c in ["FL", "FR", "BL", "BR"]:
		want.append_array(["part/motor/" + c, "part/prop/" + c, "frame/arm/" + c, "frame/pad/" + c])
	for i in range(1, 9):
		want.append_array(["frame/standoff/%d" % i, "frame/screw/top/%d" % i, "frame/screw/bottom/%d" % i])
	for a in want:
		if not addrs.has(a):
			missing.append(a)
	results.append(TestResult.new("the 5\" registry carries every part, plate, arm, pad, standoff and screw",
		missing.is_empty(), "missing %s" % [missing]))
	var holes := addrs.filter(func(a): return String(a).begins_with("frame/hole/") or String(a).begins_with("frame/pocket/"))
	results.append(TestResult.new("and the frame's holes and pockets (at least 20)",
		holes.size() >= 20, "%d" % holes.size()))
	var seen := {}
	var shared: Array = []
	for entry in ds.picks.entries:
		var a := String(entry["address"])
		if seen.has(a):
			shared.append(a)
		seen[a] = true
	results.append(TestResult.new("no two pick shapes share an address", shared.is_empty(), str(shared)))
	var proxies := ds.picks.entries.filter(func(e): return e["proxy"])
	var drawn := proxies.filter(func(e): return (e["node"] as MeshInstance3D).visible)
	var boxed := ds.mesh_boxes().filter(func(b): return String(b["name"]).begins_with(PickRegistry.PROXY_PREFIX))
	results.append(TestResult.new("hole and pocket proxies are pick shapes only: hidden, and out of the drawn bounds",
		proxies.size() >= 20 and drawn.is_empty() and boxed.is_empty(),
		"%d proxies, %d drawn, %d in mesh_boxes" % [proxies.size(), drawn.size(), boxed.size()]))
	results.append(TestResult.new("and no address is the legacy unsplit frame",
		not addrs.has("frame/body") and not addrs.has("frame/arms"), ""))
	return results


## A point on `address`'s own surface, model space: the centroid of its triangle nearest the box
## centre (a pad: of its arm's triangles inside the pad, the one furthest out).
static func _anchor(ds: DesignSpace, address: String) -> Vector3:
	var entry := ds.picks.entry_for(address)
	var xf := entry["xform"] as Transform3D
	var faces := (entry["node"] as MeshInstance3D).mesh.get_faces()
	var box := ds.picks.box_of(address)
	var pad := address.begins_with("frame/pad/")
	var best := box.get_center()
	var best_score := INF
	var stride := 3 * maxi(1, int(faces.size() / 12000.0))
	for i in range(0, faces.size() - 2, stride):
		var c := xf * ((faces[i] + faces[i + 1] + faces[i + 2]) / 3.0)
		var score := c.distance_to(box.get_center())
		if pad:
			var bc := box.get_center()
			if Vector2(c.x - bc.x, c.z - bc.z).length() > box.size.x * 0.5 * 0.98:
				continue
			score = -Vector2(c.x, c.z).length()
		if score < best_score:
			best_score = score
			best = c
	return best


static func _aim(ds: DesignSpace, p: Vector3, yaw_deg: float, pitch_deg: float, dist: float) -> void:
	var rig := ds.rig
	rig.goal_target = p
	rig.goal_yaw = deg_to_rad(yaw_deg)
	rig.goal_pitch = deg_to_rad(pitch_deg)
	rig.goal_distance = dist
	rig.snap()
	rig.target = p


## Finds, from the fixed angles, the view where `address` is nearest the front of the pile along
## the ray (the registry's own ordered hits, cheap), then replays that view through
## `DesignSpace.click_at`, clicking in place as many times as the pile needs: the mouse's path.
static func _test_reachable(ds: DesignSpace, address: String) -> TestResult:
	var p := _anchor(ds, address)
	var box := ds.picks.box_of(address)
	var dist := maxf(box.size.length() * 4.0, 0.06)
	var best := 99
	var best_view := Vector2.ZERO
	var fronts: Array = []
	for pitch in PITCHES:
		for yaw in YAWS:
			_aim(ds, p, yaw, pitch, dist)
			var ray := ds.rig.ray(ds.rig.project(p))
			var order: Array = ds.picks.hits(ray["origin"], ray["dir"]).map(func(h): return String(h["address"]))
			var idx := order.find(address)
			if idx >= 0 and idx < best:
				best = idx
				best_view = Vector2(yaw, pitch)
			elif idx < 0 and not order.is_empty() and not fronts.has(order[0]):
				fronts.append(order[0])
			if best == 0:
				break
		if best == 0:
			break
	if best >= MAX_DEPTH:
		return TestResult.new("click reaches %s" % address, false,
			("deepest %d" % (best + 1)) if best < 99 else "never on the ray; front hits: %s" % [fronts])
	_aim(ds, p, best_view.x, best_view.y, dist)
	ds.clear_selection()
	ds._last_click_ndc = Vector2(INF, INF)
	var ndc := ds.rig.project(p)
	var got := ""
	for i in best + 1:
		got = ds.click_at(ndc)
	return TestResult.new("click reaches %s" % address, got == address,
		"yaw %d pitch %d, %d clicks, got %s" % [best_view.x, best_view.y, best + 1, got])


## Clicking again in place walks the pile front to back: each selection is further along the ray
## than the one before, and the first is the pack seen from above.
static func _test_front_to_back(ds: DesignSpace) -> Array:
	var p := _anchor(ds, "part/battery")
	_aim(ds, p, 45.0, 88.0, 0.4)
	var ndc := ds.rig.project(p)
	var ray := ds.rig.ray(ndc)
	var dist := {}
	for h in ds.picks.hits(ray["origin"], ray["dir"]):
		dist[h["address"]] = float(h["distance"])
	ds.clear_selection()
	ds._last_click_ndc = Vector2(INF, INF)
	var seq: Array = []
	for i in mini(3, dist.size()):
		seq.append(ds.click_at(ndc))
	var ascending := seq.size() == 3
	for i in range(1, seq.size()):
		ascending = ascending and float(dist.get(seq[i], -1.0)) > float(dist.get(seq[i - 1], INF))
	return [TestResult.new("a click selects the nearest surface, and again steps strictly deeper",
		not seq.is_empty() and seq[0] == "part/battery" and ascending, "%s %s" % [seq, dist])]


static func _test_floor_selects_nothing(ds: DesignSpace) -> Array:
	var results: Array = []
	ds.rig.snap_home()
	ds.select("part/battery")
	var floor_point := Vector3(ds.rig.radius * 1.8, 0.0, -ds.rig.radius * 1.8)
	var got := ds.click_at(ds.rig.project(floor_point))
	results.append(TestResult.new("a click on the floor selects nothing and clears the selection",
		got == "" and ds.selected == "" and ds.inspector_lines().is_empty(), "got '%s'" % got))
	return results


static func _test_hover_and_escape(ds: DesignSpace) -> Array:
	var results: Array = []
	var p := _anchor(ds, "part/battery")
	_aim(ds, p, 45.0, 60.0, 0.4)
	var h := ds.hover_at(ds.rig.project(p))
	results.append(TestResult.new("hover names the part under the pointer",
		h == "part/battery" and ds.hover_label.visible and ds.hover_label.text == "Battery",
		"%s '%s'" % [h, ds.hover_label.text]))
	var outlined := (ds.picks.entry_for("part/battery")["node"] as MeshInstance3D).material_overlay != null
	results.append(TestResult.new("and outlines it", outlined, ""))
	ds.click_at(ds.rig.project(p))
	var dismissed := [false]
	var cb := func(): dismissed[0] = true
	ds.dismissed.connect(cb)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	ds._unhandled_key_input(esc)
	results.append(TestResult.new("Esc clears the selection and does not leave",
		ds.selected == "" and not dismissed[0] and not ds.inspector.visible, ds.selected))
	ds._unhandled_key_input(esc)
	results.append(TestResult.new("a second Esc, with nothing selected, leaves", dismissed[0], ""))
	ds.dismissed.disconnect(cb)
	return results


static func _test_inspector_numbers(ds: DesignSpace) -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	ds.set_part("battery", "battery_6s_1300")
	ds.select("part/battery")
	var part := catalog.get_part("battery_6s_1300")
	var want := "Mass: %.1f g" % float(part["mass_g"])
	var lines := ds.inspector_lines()
	results.append(TestResult.new("the inspector shows the fitted battery's catalog mass",
		lines.has(want) and lines.has("Part: %s" % part["name"]), "%s want %s" % [lines, want]))
	# Literal verdicts, not PartFacts.confidence() echoed back: the pack's source says
	# "representative", the motor's is a manufacturer thrust table.
	results.append(TestResult.new("with its confidence read from its source (a representative pack: typical)",
		lines.has("Confidence: typical (not one product)"), str(lines)))
	ds.select("part/motor/FL")
	results.append(TestResult.new("and a motor with a manufacturer table: published",
		ds.inspector_lines().has("Confidence: published"), str(ds.inspector_lines())))
	ds.select("frame/standoff/1")
	var doc := AirframeDocument.from_catalog_frame(catalog.get_part(String(ds.session.selection["frame"])))
	var items := FrameHardware.standoffs(doc)
	var g := FrameHardware.item_mass_g(items[items.size() - 1], FrameMaterials.load_default())
	results.append(TestResult.new("a standoff shows FrameHardware's grams",
		ds.inspector_lines().has("Mass: %.2f g each" % g), str(ds.inspector_lines())))
	ds.select("frame/hole/arm_FL/1")
	var hl := ds.inspector_lines()
	results.append(TestResult.new("a hole shows its drawn diameter, labelled as drawn",
		hl.size() > 2 and String(hl[1]).begins_with("Diameter: ") and hl.has("Confidence: drawn model, not the frame document"),
		str(hl)))
	# A slot on a diagonal arm: measured along itself, not by its square axis-aligned bounds.
	ds.select("frame/pocket/arm_FR/1")
	var sz := ds.inspector_lines().filter(func(l): return String(l).begins_with("Size: "))
	var dims := String(sz[0]).trim_prefix("Size: ").trim_suffix(" mm").split(" x ") if not sz.is_empty() else PackedStringArray()
	results.append(TestResult.new("an arm's pocket reads as the slot it is (long side over 1.5x the short)",
		dims.size() == 2 and float(dims[0]) > 1.5 * float(dims[1]), str(sz)))
	ds.set_part("battery", ReferenceBuild.BATTERY_ID)
	ds.clear_selection()
	return results


static func _mouse(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	return e


static func _test_click_not_drag(ds: DesignSpace) -> Array:
	var results: Array = []
	ds.size = Vector2(1280, 720)
	ds.rig.aspect = 1280.0 / 720.0
	var p := _anchor(ds, "part/battery")
	_aim(ds, p, 45.0, 60.0, 0.4)
	var ndc := ds.rig.project(p)
	var px := Vector2((ndc.x + 1.0) * 0.5 * 1280.0, (1.0 - ndc.y) * 0.5 * 720.0)
	ds.clear_selection()
	ds._gui_input(_mouse(px, true))
	ds._gui_input(_mouse(px, false))
	results.append(TestResult.new("press and release in place selects", ds.selected == "part/battery", ds.selected))
	ds.clear_selection()
	ds._gui_input(_mouse(px, true))
	var mv := InputEventMouseMotion.new()
	mv.position = px + Vector2(40, 0)
	mv.relative = Vector2(40, 0)
	ds._gui_input(mv)
	ds._gui_input(_mouse(px + Vector2(40, 0), false))
	results.append(TestResult.new("a drag orbits and selects nothing", ds.selected == "", ds.selected))
	return results


static func _test_rebuild_regenerates(ds: DesignSpace) -> Array:
	var results: Array = []
	# Replace the battery's mesh with a tiny box far away, as a regenerated mesh would: until the
	# pick shapes are rebuilt the old pack is still clickable (stale), and after it is not.
	var p := _anchor(ds, "part/battery")
	_aim(ds, p, 45.0, 60.0, 0.4)
	var ndc := ds.rig.project(p)
	var node := ds.picks.entry_for("part/battery")["node"] as MeshInstance3D
	var old_mesh := node.mesh
	var tiny := BoxMesh.new()
	tiny.size = Vector3(0.001, 0.001, 0.001)
	node.mesh = tiny
	var stale := String(ds.pick(ndc).get("address", ""))
	ds.rebuild_picks()
	var fresh := String(ds.pick(ndc).get("address", ""))
	results.append(TestResult.new("pick shapes follow a regenerated mesh after rebuild_picks",
		stale == "part/battery" and fresh != "part/battery", "before %s after %s" % [stale, fresh]))
	node.mesh = old_mesh
	ds.rebuild_picks()
	return results
