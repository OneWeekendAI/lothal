class_name TestRealisticParts
extends RefCounted
## The drawn electronics (PartAssets) against the catalog: every catalog part of the seven kinds is
## sized to its published box and seated on y = 0; two motors differ by their catalog ratio; and the
## whole five_inch drone stays inside a triangle and texture budget.
##
## One result per part id, so a break says how many parts it took. The budget numbers are printed.

const TRIANGLE_BUDGET := 60000
const TEXTURE_BUDGET_PX := 2048
const TOL_M := 0.0005
const CATEGORY := {
	"motor": "motor", "flight_controller": "flight_controller", "battery": "battery",
	"camera": "camera", "vtx": "vtx", "antenna": "antenna", "receiver": "receiver",
}
const FRAME_NODE_PREFIX := "frame_"   # five_inch.glb: plates, arms, screws, standoffs, tail mount


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	for kind in PartAssets.kinds():
		for part in catalog.list_category(String(CATEGORY[kind])):
			results.append(_test_part(kind, part))
	results.append(_test_swap_truth(catalog))
	results.append_array(_test_fit_prop(catalog))
	results.append_array(_test_budgets(catalog))
	return results


static func _mm(v: Vector3) -> String:
	return "%.1f x %.1f x %.1f mm" % [v.x * 1000.0, v.y * 1000.0, v.z * 1000.0]


static func _test_part(kind: String, part: Dictionary) -> TestResult:
	var id := String(part.get("part_id", "?"))
	var want := PartAssets.target_size(kind, part)
	var node := PartAssets.instance(kind, part)
	var box := PartAssets.measured_aabb(node)
	var unsized := bool(node.get_meta("lothal_unsized", false))
	node.free()
	var ok := false
	if unsized:
		ok = want == Vector3.ZERO   # undimensioned entries are honest about it; flagged in the name
	else:
		ok = absf(box.size.x - want.x) <= TOL_M \
			and absf(box.size.y - want.y) <= TOL_M and absf(box.size.z - want.z) <= TOL_M \
			and absf(box.position.y) <= TOL_M
	return TestResult.new("%s %s: drawn box = catalog box, seated" % [kind, id], ok,
		"%s%s; catalog %s; measured %s, min.y %.2f mm" % [("UNSIZED " if unsized else ""), kind, _mm(want), _mm(box.size), box.position.y * 1000.0])


static func _test_swap_truth(catalog: PartsCatalog) -> TestResult:
	var a := catalog.get_part("motor_2207_1960kv")
	var b := catalog.get_part("motor_0802_19000kv")
	var na := PartAssets.instance("motor", a)
	var nb := PartAssets.instance("motor", b)
	var sa := PartAssets.measured_aabb(na).size
	var sb := PartAssets.measured_aabb(nb).size
	na.free()
	nb.free()
	var ta := SwapLook.size_of("motor", a)
	var tb := SwapLook.size_of("motor", b)
	var ok := sa.x > sb.x and sa.y > sb.y and absf(sa.x / sb.x - ta.x / tb.x) < 0.01 \
		and absf(sa.y / sb.y - ta.y / tb.y) < 0.01
	return TestResult.new("swap truth: two motors draw in the catalog ratio", ok,
		"%s vs %s (want ratio x %.3f, y %.3f)" % [_mm(sa), _mm(sb), ta.x / tb.x, ta.y / tb.y])


## Real stack order: bell top -> prop hub -> nut, shaft through the nut. One result per motor in the
## catalog, so a break says how many motors it took.
static func _test_fit_prop(catalog: PartsCatalog) -> Array:
	var out: Array = []
	for part in catalog.list_category("motor"):
		var node := PartAssets.instance("motor", part)
		if bool(node.get_meta("lothal_unsized", false)):
			node.free()
			continue
		var hub := 0.006
		PartAssets.fit_prop(node, hub)
		var bell_top := PartAssets.measured_aabb(node).end.y
		var nut := PartAssets.decor_y_range(node, "x_prop_nut")
		var shaft := PartAssets.decor_y_range(node, "x_shaft")
		node.free()
		var ok := absf(nut.x - (bell_top + hub)) <= 0.0001 and shaft.y >= nut.x
		out.append(TestResult.new("fit_prop %s: nut sits on bell top + hub height, shaft reaches the nut" % String(part.get("part_id", "?")), ok,
			"bell top %.2f mm, hub %.2f mm, nut bottom %.2f mm, shaft top %.2f mm" % [bell_top * 1000.0, hub * 1000.0, nut.x * 1000.0, shaft.y * 1000.0]))
	return out


static func _first(catalog: PartsCatalog, category: String) -> Dictionary:
	var l := catalog.list_category(category)
	return l[0] if not l.is_empty() else {}


static func _frame_triangles() -> int:
	var scene := load("res://assets/models/classes/five_inch.glb") as PackedScene
	var root := scene.instantiate()
	var total := 0
	for child in root.get_child(0).get_children():   # the glTF's single top node holds the drawn parts
		if String(child.name).begins_with(FRAME_NODE_PREFIX):
			total += PartAssets.triangle_count(child)
	root.free()
	return total


static func five_inch_breakdown(catalog: PartsCatalog) -> Dictionary:
	var drone_seed: Dictionary = {}
	for c in DroneClass.CLASSES:
		if String(c["id"]) == "five_inch":
			drone_seed = c["seed"]
	var out := {}
	var motor := catalog.get_part(String(drone_seed["motor"]))
	var per := {
		"motor": motor, "flight_controller": catalog.get_part(String(drone_seed["flight_controller"])),
		"battery": catalog.get_part(String(drone_seed["battery"])),
		"camera": catalog.get_part(String(drone_seed.get("camera", ""))) if drone_seed.has("camera") else _first(catalog, "camera"),
		"vtx": catalog.get_part(String(drone_seed.get("vtx", ""))) if drone_seed.has("vtx") else _first(catalog, "vtx"),
		"antenna": catalog.get_part(String(drone_seed.get("antenna", ""))) if drone_seed.has("antenna") else _first(catalog, "antenna"),
		"receiver": catalog.get_part(String(drone_seed.get("receiver", ""))) if drone_seed.has("receiver") else _first(catalog, "receiver"),
	}
	for kind in per:
		var n := PartAssets.instance(String(kind), per[kind])
		var t := PartAssets.triangle_count(n)
		out[kind] = t * (4 if kind == "motor" else 1)
		n.free()
	var pm := PropellerMesh.new()
	pm.rebuild(catalog.get_part(String(drone_seed["propeller"])))
	out["propellers (4)"] = PartAssets.triangle_count(pm) * 4
	pm.free()
	out["frame"] = _frame_triangles()
	return out


static func _test_budgets(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var bd := five_inch_breakdown(catalog)
	var total := 0
	var line := ""
	for k in bd:
		total += int(bd[k])
		line += "%s %d, " % [k, int(bd[k])]
	print("five_inch triangles: %stotal %d (budget %d)" % [line, total, TRIANGLE_BUDGET])
	out.append(TestResult.new("budget: five_inch whole drone under %d triangles" % TRIANGLE_BUDGET,
		total < TRIANGLE_BUDGET, "total %d; %s" % [total, line]))
	var worst := 0
	var which := ""
	var files: Array = []
	for f in PartAssets.FILES.values():
		files.append(PartAssets.DIR + String(f))
	files.append("res://assets/models/classes/five_inch.glb")
	for path in files:
		var root := (load(path) as PackedScene).instantiate()
		var px := PartAssets.max_texture_px(root)
		root.free()
		if px > worst:
			worst = px
			which = String(path)
	out.append(TestResult.new("budget: every texture in the part and five_inch GLBs <= %d px" % TEXTURE_BUDGET_PX,
		worst <= TEXTURE_BUDGET_PX, "largest %d px (%s)" % [worst, which]))
	return out
