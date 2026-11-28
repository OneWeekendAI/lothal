class_name PartAssets
extends RefCounted
## The drawn electronics (assets/models/parts/*.glb) sized to the CATALOG, not to the model they
## were drawn at. Each file is authored at a reference size with its seat (bottom-centre) on the
## origin; instance() scales the measured box (every mesh not named x_*) to exactly what the same
## size functions the stage and the loader use say: SwapLook.size_of for the motor and the stack,
## Build.battery_size_of for the pack, Build.component_size_of for the small parts. A part with no
## published dimensions keeps its drawn size and carries meta "lothal_unsized" = true, never a guess.

const DIR := "res://assets/models/parts/"
const FILES := {
	"motor": "motor.glb", "flight_controller": "stack.glb", "battery": "battery.glb",
	"camera": "camera.glb", "vtx": "vtx.glb", "antenna": "antenna.glb", "receiver": "receiver.glb",
}
const DECOR_PREFIX := "x_"

static var _cache := {}


static func kinds() -> Array:
	return FILES.keys()


## The catalog box for `part`, metres in the part's own axes (x across, y up, z along), or
## Vector3.ZERO when the catalog does not publish enough to say.
static func target_size(kind: String, part: Dictionary) -> Vector3:
	var specs: Dictionary = part.get("specs", {})
	match kind:
		"motor":
			var s := SwapLook.size_of("motor", part)
			return s if s.x > 0.0 and s.y > 0.0 else Vector3.ZERO
		"flight_controller":
			var pattern := String(part.get("mounting", {}).get("pattern", ""))
			if pattern == "":
				return Vector3.ZERO
			return StackMesh.size_m(pattern)
		"battery", "camera", "vtx", "receiver", "antenna":
			if not (float(specs.get("length_mm", 0.0)) > 0.0 and float(specs.get("width_mm", 0.0)) > 0.0
					and float(specs.get("height_mm", 0.0)) > 0.0):
				return Vector3.ZERO
			if kind == "battery":
				return Build.battery_size_of(part)
			var c := Build.component_size_of(part)   # (width, height, length)
			if kind == "antenna":
				# length_mm is how tall the whip stands; the seat footprint is width x width.
				return Vector3(c.x, c.z, c.x)
			return c
	return Vector3.ZERO


static func _scene(kind: String) -> PackedScene:
	if not _cache.has(kind):
		_cache[kind] = load(DIR + String(FILES.get(kind, ""))) as PackedScene
	return _cache[kind]


static func instance(kind: String, part: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Part_" + kind
	var ps := _scene(kind)
	if ps == null:
		root.set_meta("lothal_unsized", true)
		return root
	var inner := ps.instantiate() as Node3D
	root.add_child(inner)
	var target := target_size(kind, part)
	if target == Vector3.ZERO:
		root.set_meta("lothal_unsized", true)
		return root
	var ref := measured_aabb(root).size
	if ref.x <= 0.0 or ref.y <= 0.0 or ref.z <= 0.0:
		root.set_meta("lothal_unsized", true)
		return root
	# Scale about the origin (the seat's centre), so the seat stays where it was.
	inner.transform = Transform3D(Basis.from_scale(Vector3(target.x / ref.x, target.y / ref.y, target.z / ref.z)), Vector3.ZERO)
	return root


## Stacks the motor's decorative parts the way a real rotor goes together: bell top, prop hub, then
## the nut on top, with the shaft long enough to come up through the nut. `hub_height_m` is the prop
## hub's real height (PropellerMesh.stack_height_m). The measured box (x_ nodes excluded) is untouched.
static func fit_prop(motor_root: Node3D, hub_height_m: float) -> void:
	var nut := motor_root.find_child(DECOR_PREFIX + "prop_nut", true, false) as MeshInstance3D
	var shaft := motor_root.find_child(DECOR_PREFIX + "shaft", true, false) as MeshInstance3D
	if nut == null or nut.mesh == null or motor_root.get_child_count() == 0:
		return
	var inner := motor_root.get_child(0) as Node3D
	var sy := inner.transform.basis.y.length()
	if sy <= 0.0:
		return
	var bell_top := measured_aabb(motor_root).end.y
	var nut_box := nut.mesh.get_aabb()
	# Root-space nut bottom = sy * (node.y + nut_box.position.y)  ->  solve for node.y.
	var nut_bottom := bell_top + hub_height_m
	nut.transform = Transform3D(Basis.IDENTITY, Vector3(0, nut_bottom / sy - nut_box.position.y, 0))
	if shaft == null or shaft.mesh == null:
		return
	var nut_top := nut_bottom + nut_box.size.y * sy
	var sb := shaft.mesh.get_aabb()
	var k := maxf(1.0, (nut_top / sy - sb.position.y) / sb.size.y)
	shaft.transform = Transform3D(Basis.from_scale(Vector3(1, k, 1)), Vector3(0, sb.position.y * (1.0 - k), 0))


## Root-space y range of a decorative node (its mesh box through the chain of transforms).
static func decor_y_range(motor_root: Node3D, node_name: String) -> Vector2:
	var n := motor_root.find_child(node_name, true, false) as MeshInstance3D
	if n == null or n.mesh == null:
		return Vector2.ZERO
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != motor_root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	var b: AABB = xf * n.mesh.get_aabb()
	return Vector2(b.position.y, b.end.y)


## The measured box in `root`'s space: every MeshInstance3D below it except decorative x_ nodes.
static func measured_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var state := {"have": false}
	_walk_box(root, Transform3D.IDENTITY, box, state)
	return state.get("box", AABB())


static func _walk_box(n: Node, xf: Transform3D, _unused: AABB, state: Dictionary) -> void:
	for child in n.get_children():
		if String(child.name).begins_with(DECOR_PREFIX):
			continue
		var cxf := xf
		if child is Node3D:
			cxf = xf * (child as Node3D).transform
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			var b: AABB = cxf * (child as MeshInstance3D).mesh.get_aabb()
			if state["have"]:
				state["box"] = (state["box"] as AABB).merge(b)
			else:
				state["box"] = b
				state["have"] = true
		_walk_box(child, cxf, _unused, state)


static func triangle_count(root: Node) -> int:
	var total := 0
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		total += int((root as MeshInstance3D).mesh.get_faces().size() / 3.0)
	for child in root.get_children():
		total += triangle_count(child)
	return total


static func max_texture_px(root: Node) -> int:
	var best := 0
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var mats: Array = [mi.material_override, mi.material_overlay]
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				mats.append(mi.get_surface_override_material(s))
				mats.append(mi.mesh.surface_get_material(s))
		for m in mats:
			best = maxi(best, _material_px(m))
	for child in root.get_children():
		best = maxi(best, max_texture_px(child))
	return best


static func _material_px(m: Variant) -> int:
	var best := 0
	if m is BaseMaterial3D:
		for slot in BaseMaterial3D.TEXTURE_MAX:
			var t := (m as BaseMaterial3D).get_texture(slot as BaseMaterial3D.TextureParam)
			if t != null:
				best = maxi(best, maxi(t.get_width(), t.get_height()))
	elif m is ShaderMaterial:
		for p in (m as ShaderMaterial).shader.get_shader_uniform_list() if (m as ShaderMaterial).shader != null else []:
			var v: Variant = (m as ShaderMaterial).get_shader_parameter(String(p["name"]))
			if v is Texture2D:
				best = maxi(best, maxi((v as Texture2D).get_width(), (v as Texture2D).get_height()))
	return best
