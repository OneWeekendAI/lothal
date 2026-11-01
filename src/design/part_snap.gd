class_name PartSnap
extends RefCounted
## Shelf, drag and drop, snap (PLAN Section 5): where a part dropped near the drone attaches, and
## whether it may. Pure: no Node is kept, nothing is drawn, nothing is remembered between calls.
##
## ## A drop is resolved by the PART, never by the nearest mount
##
## The part's catalog category names the mounts it can go on (MOUNTS_BY_CATEGORY): a battery has
## one, a motor or a prop four (one per corner), a receiver rides the stack. Only among THOSE mounts
## does the drop point choose (the nearest corner), so a battery released over the camera still goes
## on the battery pad. Then the part's mounting is judged exactly as a swap is (`PartSwap.judge`: bolt
## pattern to the arm pad, board pattern to the stack, prop clearance), and a hard misfit is refused
## with the blocking warning's first sentence. Nearest-mount-alone would put a battery on the camera
## mount and a 20x20 board on a 30.5 stack; the suite (test_design_shelf.gd) checks both.
##
## ## Generous capture
##
## A drop counts when it lands within CAPTURE_M of the drone's drawn bounds (no aiming at holes);
## further away it is "nothing" and changes nothing. Inside, the point only picks a corner.
##
## ## Spaces
##
## Every point and transform here is in the class GLB's ROOT frame (metres, the frame the Blender
## export wrote; DesignSpace offsets that root to stand the drone on y=0, so a stage point p is
## `root.transform.affine_inverse() * p` here). `mount_map` reads it from the instantiated GLB.

## Beyond the drone's drawn bounds by this much (metres) a drop is "nothing". The 5" is ~0.27 m
## across its props; 6 cm is a thumb's width on screen at the default zoom.
const CAPTURE_M := 0.06
const CORNERS := ["FL", "FR", "BL", "BR"]
## Catalog category -> the drawn nodes (GLB mesh names) it can be mounted on. Receiver and guard have
## no node of their own: the receiver rides the stack, a guard rings the props.
const MOUNTS_BY_CATEGORY := {
	"battery": ["battery"],
	"motor": ["motor_FL", "motor_FR", "motor_BL", "motor_BR"],
	"propeller": ["prop_FL", "prop_FR", "prop_BL", "prop_BR"],
	"guard": ["prop_FL", "prop_FR", "prop_BL", "prop_BR"],
	"flight_controller": ["stack"], "esc": ["stack"], "receiver": ["stack"],
	"camera": ["camera"],
	"vtx": ["antennas"], "antenna": ["antennas"],
}
## The shelf's categories, in shelf order (PartSwap.SLOTS order, flattened).
const SHELF_CATEGORIES := ["battery", "motor", "propeller", "guard", "flight_controller", "esc",
	"receiver", "camera", "vtx", "antenna"]
## Mount address -> the category "remove" takes off it (the drawn part on that mount).
const PRIMARY_CATEGORY := {"battery": "battery", "motor": "motor", "prop": "propeller",
	"stack": "flight_controller", "camera": "camera", "antennas": "antenna"}
## The required categories as the "cannot fly" line names them.
const MISSING_NAMES := {"frame": "frame", "motor": "motors", "propeller": "props",
	"battery": "battery", "esc": "ESC", "flight_controller": "flight controller"}


## The mounts of an instantiated class model: {mounts: {address: {node, xf, centre}}, bounds: AABB}.
## `xf` is the node's drawn transform and `centre` its drawn box's centre, both in `root`'s frame;
## `bounds` covers every visible (non pick-proxy) mesh. Read once per model load: a swap or a drop
## moves the drawn nodes (SwapLook), and the mounts are where the drone was drawn to take them.
static func mount_map(root: Node) -> Dictionary:
	var mounts := {}
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	if root == null:
		return {"mounts": mounts, "bounds": AABB()}
	var wanted := {}
	for cat in MOUNTS_BY_CATEGORY:
		for n in MOUNTS_BY_CATEGORY[cat]:
			wanted[n] = true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var nm := String(mi.name)
		if mi.mesh == null or nm.begins_with(PickRegistry.PROXY_PREFIX):
			continue
		var xf := _xform_in(mi, root)
		var box := xf * mi.get_aabb()
		lo = lo.min(box.position)
		hi = hi.max(box.end)
		if wanted.has(nm):
			mounts[PickRegistry.address_of(nm)] = {"node": nm, "xf": xf, "centre": box.get_center()}
	var bounds := AABB(lo, hi - lo) if lo.x < INF else AABB()
	return {"mounts": mounts, "bounds": bounds}


static func _xform_in(node: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Is `point` close enough to the drone for a drop to count?
static func in_reach(map: Dictionary, point: Vector3) -> bool:
	var b: AABB = map.get("bounds", AABB())
	if b.size == Vector3.ZERO:
		return false
	return b.grow(CAPTURE_M).has_point(point)


## The mount addresses a category goes on, on this model (for lighting every corner a motor fills).
static func mounts_for(map: Dictionary, category: String) -> Array:
	var out: Array = []
	var mounts: Dictionary = map.get("mounts", {})
	for n in MOUNTS_BY_CATEGORY.get(category, []):
		var address := PickRegistry.address_of(String(n))
		if mounts.has(address):
			out.append(address)
	return out


## What dropping `part_id` at `point` would do. Never changes `session`. Returns
##   {kind: "snap" | "refused" | "nothing", part_id, category, mount, mounts, reason, replaces,
##    ghost_xf, centre}
## - "nothing": the drop is out of reach (or no part was given); mount "" and reason "".
## - "refused": a one-line reason; mount "" (no ghost); the session must stay as it is.
## - "snap": `mount` is the address it attaches to (the nearest of the category's mounts),
##   `mounts` every address the category fills (four for a motor), `replaces` the id fitted there
##   now ("" for an empty slot), `ghost_xf` / `centre` the mount's drawn transform and box centre.
## This is also the drag preview: call it each frame the part is over the drone.
static func resolve(session: DesignSession, catalog: PartsCatalog, part_id: String,
		point: Vector3, map: Dictionary) -> Dictionary:
	var out := {"kind": "nothing", "part_id": part_id, "category": "", "mount": "", "mounts": [],
		"reason": "", "replaces": "", "ghost_xf": Transform3D.IDENTITY, "centre": Vector3.ZERO}
	if part_id == "" or not in_reach(map, point):
		return out
	out["kind"] = "refused"
	var part := catalog.get_part(part_id)
	if part.is_empty():
		out["reason"] = "%s is not in the catalog." % part_id
		return out
	var category := String(part.get("category", ""))
	out["category"] = category
	var candidates := mounts_for(map, category)
	if candidates.is_empty() or not session.selection.has(category):
		out["reason"] = "This drone has nowhere to mount %s." % String(part.get("name", part_id))
		return out
	var verdict := PartSwap.judge(judging_session(session, catalog), catalog, category, part_id, false)
	if not verdict["ok"]:
		out["reason"] = String(verdict["reason"])
		out["refused_by"] = verdict.get("refused_by")
		return out
	var mounts: Dictionary = map["mounts"]
	var best := ""
	var best_d := INF
	for address in candidates:
		var d := point.distance_to(mounts[address]["centre"])
		if d < best_d:
			best_d = d
			best = address
	out["kind"] = "snap"
	out["mount"] = best
	out["mounts"] = candidates
	out["replaces"] = String(session.selection.get(category, ""))
	out["ghost_xf"] = mounts[best]["xf"]
	out["centre"] = mounts[best]["centre"]
	return out


## The session a drop's mounting is judged on. A drone with a required slot empty does not build,
## and `PartSwap.judge` reads the misfits off a build; so the empty required slots are filled, for
## judging only, with the class's default parts. A motor dropped on a drone with no battery is then
## judged against its arm pads, which is what mounting depends on, and is not refused for the pack.
static func judging_session(session: DesignSession, catalog: PartsCatalog) -> DesignSession:
	var missing := missing_required(session, catalog)
	if missing.is_empty():
		return session
	var defaults := DroneClass.parts_for(session.drone_class)
	var trial := DesignSession.from_selection(session, String(missing[0]),
		String(defaults.get(missing[0], "")))
	for cat in missing:
		trial.selection[cat] = String(defaults.get(cat, ""))
	return trial


## The required categories with nothing (or nothing the catalog knows) fitted, in schema order.
static func missing_required(session: DesignSession, catalog: PartsCatalog) -> Array:
	var out: Array = []
	for cat in ProjectSchema.REQUIRED_CATEGORIES:
		var id := String(session.selection.get(cat, ""))
		if id == "" or catalog.get_part(id).is_empty():
			out.append(cat)
	return out


## "no battery: cannot fly", or "" when nothing required is missing.
static func cannot_fly_line(missing: Array) -> String:
	if missing.is_empty():
		return ""
	var names: Array = missing.map(func(c): return "no " + String(MISSING_NAMES.get(c, c)))
	return "%s: cannot fly" % ", ".join(PackedStringArray(names))


## The category `remove` takes off a mount address ("part/motor/FL" -> "motor"), "" if none.
static func category_at(address: String) -> String:
	var p := address.split("/")
	if p.size() < 2 or p[0] != "part":
		return ""
	return String(PRIMARY_CATEGORY.get(p[1], ""))


## The shelf: [{category, name, parts: [{id, name, numbers}]}] in SHELF_CATEGORIES order. Every
## catalog part of each category that is NOT fitted, so a part removed or replaced is back on it
## and a fitted one is not. No verdicts here (they cost a build each); the drag preview judges.
static func shelf(session: DesignSession, catalog: PartsCatalog) -> Array:
	var out: Array = []
	for cat in SHELF_CATEGORIES:
		if not session.selection.has(cat):
			continue
		var fitted := String(session.selection.get(cat, ""))
		var parts: Array = []
		for part in catalog.list_category(cat):
			var id := String((part as Dictionary).get("part_id", ""))
			if id == "" or id == fitted:
				continue
			parts.append({"id": id, "name": String(part.get("name", id)),
				"numbers": PartSwap.deciding_numbers(part, cat)})
		out.append({"category": cat, "name": String(PartSwap.CATEGORY_NAMES.get(cat, cat)),
			"parts": parts})
	return out
