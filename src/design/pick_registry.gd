class_name PickRegistry
extends RefCounted
## What the pointer is on, in the Design Space (PLAN Section 2): every drawn piece of the drone, and
## every empty cut in its frame, mapped to one data address.
##
## ## One place makes the pick shapes, from the drawn meshes
##
## `rebuild` walks the model and, for each MeshInstance3D, makes a `TriangleMesh` (Godot's BVH over
## the mesh's own triangles) in that mesh's local frame. A click is a ray tested against those BVHs:
## the hit is on the triangles the user sees, not on a bounding box. Nothing else makes a pick shape,
## so whoever regenerates a mesh (Section 4) calls `rebuild` and the two cannot drift apart.
##
## A hole or a pocket has no triangles to hit: it is the absence of material. The Blender export
## (tools/blender/build_drone.py) therefore writes one closed prism per cut, `pick_hole_*` /
## `pick_pocket_*`, from the very point list that carved the cut. Those meshes are hidden here and
## kept only as pick shapes. Cuts that something passes through (standoff holes, motor mount holes)
## get no proxy: they are reached through the standoff, screw or motor that fills them.
##
## ## One address per pick shape, with one stated exception
##
## Every shape maps to exactly one address, except an arm, whose tip within the motor's footprint
## radius is the arm's motor pad: the pad is a disc ON the arm, the same carbon, so it is a
## sub-region of the arm's shape rather than a second shape (a second shape would either cover the
## arm's surface or sit inside it). `addresses()` lists both.
##
## Addresses (strings, stable across rebuilds):
##   part/<slot>[/<corner>]   battery, camera, stack, antennas, wires, motor/FL, prop/BR ...
##   frame/plate/top|bottom   frame/arm/FL   frame/pad/FL   frame/standoff/3   frame/screw/top/3
##   frame/tail_mount         frame/hole/<owner>/<n>        frame/pocket/<owner>/<n>
##   frame/body, frame/arms   (models exported before the frame was split; other classes)

const PROXY_PREFIX := "pick_"
const CORNER_NAMES := {"FL": "front left", "FR": "front right", "BL": "back left", "BR": "back right"}
const PART_NAMES := {"battery": "Battery", "camera": "Camera", "stack": "FC / ESC stack",
	"antennas": "VTX antennas", "wires": "Wiring", "motor": "Motor", "prop": "Propeller",
	"gps": "GPS", "payload": "Payload", "gear": "Landing gear", "aio": "AIO board", "ducts": "Ducts",
	"cine_camera": "Cinema camera"}
const OWNER_NAMES := {"plate_top": "top plate", "plate_bottom": "bottom plate",
	"tail_mount": "tail mount"}
## The pad is the arm within this multiple of the motor's half-width of the motor axis.
const PAD_RADIUS_K := 1.0

## The BVHs are built in millimetres. Godot's ray-triangle test rejects a triangle whose edge
## product is under its float epsilon (1e-5), and the 5" model's triangles are a millimetre or two
## across in metres: built in metres, every small part (props, wires, every hole) was unhittable.
const TO_PICK := Transform3D(Vector3(1000, 0, 0), Vector3(0, 1000, 0), Vector3(0, 0, 1000), Vector3.ZERO)

## {address, node, xform (model-space), tm: TriangleMesh in mm, tm_xform/tm_inv (mm <-> model),
##  box (model-space AABB), proxy: bool}
var entries: Array = []
## arm address -> {address, centre (model space), axis_up, radius}
var pads: Dictionary = {}


## Makes every pick shape from `root`'s meshes. `space` is the node whose frame the rays are given
## in (the stage); proxies are hidden. Call again whenever a mesh is regenerated.
func rebuild(root: Node, space: Node) -> void:
	entries.clear()
	pads.clear()
	if root == null:
		return
	var motors := {}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var nm := String(mi.name)
		var proxy := nm.begins_with(PROXY_PREFIX)
		if proxy:
			mi.visible = false
		elif not mi.visible:
			# A drawn part that is hidden is not on the drone (removed, or "not fitted"): nothing
			# there to pick (Section 5: a removed battery must not stay selectable).
			continue
		var xf := _xform_to(mi, space)
		var tm := TriangleMesh.new()
		if not tm.create_from_faces(TO_PICK * mi.mesh.get_faces()):
			continue
		var tm_xf := xf * TO_PICK.affine_inverse()
		var entry := {"address": address_of(nm), "node": mi, "xform": xf, "tm_xform": tm_xf,
			"tm_inv": tm_xf.affine_inverse(), "tm": tm, "box": xf * mi.get_aabb(), "proxy": proxy}
		entries.append(entry)
		if nm.begins_with("motor_"):
			motors[nm.substr(6)] = entry
	for entry in entries:
		var a := String(entry["address"])
		if not a.begins_with("frame/arm/"):
			continue
		var corner := a.get_slice("/", 2)
		if not motors.has(corner):
			continue
		var mbox := motors[corner]["box"] as AABB
		var c := mbox.get_center()
		pads[a] = {"address": "frame/pad/" + corner, "centre": Vector3(c.x, 0.0, c.z),
			"radius": 0.5 * maxf(mbox.size.x, mbox.size.z) * PAD_RADIUS_K}


## Hides the export's hole and pocket proxies under `root` (they are pick shapes, never drawn).
static func hide_proxies(root: Node) -> void:
	for node in root.find_children(PROXY_PREFIX + "*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = false


static func _xform_to(node: Node, space: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != space:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## The address a mesh node's name stands for.
static func address_of(mesh_name: String) -> String:
	var n := mesh_name
	if n.begins_with("pick_hole_") or n.begins_with("pick_pocket_"):
		var kind := "hole" if n.begins_with("pick_hole_") else "pocket"
		var rest := n.substr(len("pick_%s_" % kind))
		var cut := rest.rfind("_")
		return "frame/%s/%s/%s" % [kind, rest.substr(0, cut), rest.substr(cut + 1)]
	if n == "frame":
		return "frame/body"
	if n == "frame_arms":
		return "frame/arms"
	if n.begins_with("frame_plate_"):
		return "frame/plate/" + n.substr(12)
	if n.begins_with("frame_arm_"):
		return "frame/arm/" + n.substr(10)
	if n.begins_with("frame_standoff_"):
		return "frame/standoff/" + n.substr(15)
	if n.begins_with("frame_screw_"):
		var parts := n.substr(12).split("_")
		return "frame/screw/%s/%s" % [parts[0], parts[1] if parts.size() > 1 else "1"]
	if n == "frame_tail_mount":
		return "frame/tail_mount"
	for pre in ["motor_", "prop_"]:
		if n.begins_with(pre):
			return "part/%s/%s" % [pre.trim_suffix("_"), n.substr(len(pre))]
	return "part/" + n


## What the inspector and the hover label call an address.
static func display_name(address: String) -> String:
	var p := address.split("/")
	if p.size() < 2:
		return address
	if p[0] == "part":
		var base := String(PART_NAMES.get(p[1], p[1].capitalize()))
		return base if p.size() < 3 else "%s, %s" % [base, _corner(p[2])]
	match p[1]:
		"body": return "Frame"
		"arms": return "Arms"
		"plate": return "%s plate" % p[2].capitalize()
		"arm": return "Arm, %s" % _corner(p[2])
		"pad": return "Motor pad, %s" % _corner(p[2])
		"standoff": return "Standoff %s" % p[2]
		"screw": return "Screw %s, %s plate" % [p[3], p[2]]
		"tail_mount": return "Tail mount"
		"hole", "pocket":
			return "%s %s, %s" % [p[1].capitalize(), p[3], _owner(p[2])]
	return address


static func _corner(c: String) -> String:
	return String(CORNER_NAMES.get(c, c))


static func _owner(o: String) -> String:
	if OWNER_NAMES.has(o):
		return OWNER_NAMES[o]
	if o.begins_with("arm_"):
		return "arm " + _corner(o.substr(4))
	return o


## Every address a click can select, each once.
func addresses() -> Array:
	var out: Array = []
	for entry in entries:
		if not out.has(entry["address"]):
			out.append(entry["address"])
	for a in pads:
		out.append(pads[a]["address"])
	return out


## The entry drawing `address` (for a pad, its arm). Empty if none.
func entry_for(address: String) -> Dictionary:
	for entry in entries:
		if entry["address"] == address:
			return entry
	for a in pads:
		if pads[a]["address"] == address:
			return entry_for(a)
	return {}


## The nearest pick shape along the ray (model space): {address, position, distance, entry} or {}.
func hit(origin: Vector3, dir: Vector3) -> Dictionary:
	var all := hits(origin, dir)
	return all[0] if not all.is_empty() else {}


## Every pick shape the ray passes into, nearest first, one per address: what a click selects
## first, and what clicking again in the same place steps through.
func hits(origin: Vector3, dir: Vector3) -> Array:
	var out: Array = []
	var nd := dir.normalized()
	for entry in entries:
		var box := entry["box"] as AABB
		if box.grow(1e-5).intersects_ray(origin, nd) == null:
			continue
		var inv := entry["tm_inv"] as Transform3D
		var h: Dictionary = (entry["tm"] as TriangleMesh).intersect_ray(inv * origin, (inv.basis * nd).normalized())
		if h.is_empty():
			continue
		var wp: Vector3 = (entry["tm_xform"] as Transform3D) * (h["position"] as Vector3)
		var d := (wp - origin).dot(nd)
		if d <= 0.0:
			continue
		out.append({"address": _region(String(entry["address"]), wp), "position": wp, "distance": d,
			"entry": entry})
	out.sort_custom(func(x, y): return float(x["distance"]) < float(y["distance"]))
	var seen := {}
	var unique: Array = []
	for h in out:
		if not seen.has(h["address"]):
			seen[h["address"]] = true
			unique.append(h)
	return unique


## An arm hit inside the motor's footprint is the arm's motor pad.
func _region(address: String, p: Vector3) -> String:
	if pads.has(address):
		var pad: Dictionary = pads[address]
		var c := pad["centre"] as Vector3
		if Vector2(p.x - c.x, p.z - c.z).length() <= float(pad["radius"]):
			return String(pad["address"])
	return address


## The model-space box of an address (a pad's is its disc's square).
func box_of(address: String) -> AABB:
	for a in pads:
		if pads[a]["address"] == address:
			var arm := entry_for(a)["box"] as AABB
			var c := pads[a]["centre"] as Vector3
			var r := float(pads[a]["radius"])
			return AABB(Vector3(c.x - r, arm.position.y, c.z - r), Vector3(2 * r, arm.size.y, 2 * r))
	var e := entry_for(address)
	return e["box"] if not e.is_empty() else AABB()


## The box a cut is MEASURED by: for a hole or pocket, its footprint in its own long direction
## (x = length, y = through, z = width, metres), so a slot on a diagonal arm reads as a slot and
## not as its square axis-aligned bounds. Anything else: `box_of`.
func measure_box(address: String) -> AABB:
	var entry := entry_for(address)
	if entry.is_empty() or not entry["proxy"]:
		return box_of(address)
	var pts := (entry["xform"] as Transform3D) * (entry["node"] as MeshInstance3D).mesh.get_faces()
	var best := Vector2(INF, 0.0)
	for deg in 180:
		var u := Vector2.from_angle(deg_to_rad(deg))
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for q in pts:
			var v := Vector2(q.x, q.z)
			var a := Vector2(v.dot(u), v.dot(u.orthogonal()))
			lo = lo.min(a)
			hi = hi.max(a)
		if hi.y - lo.y < best.x:
			best = Vector2(hi.y - lo.y, hi.x - lo.x)
	var b := box_of(address)
	return AABB(b.position, Vector3(best.y, b.size.y, best.x))
