class_name PayloadMesh
extends RefCounted
## The payload drawn: a plain box and the mount it hangs on (a hook and strap, a gimbal yoke, or a bolted plate).
##
## The node's ORIGIN is the attach point on the underside of the aircraft (Build.payload_attach_m), and
## everything hangs below it: the mount fills the gap PayloadPart.mount_gap_m, the box starts at the foot of
## the gap. So drawing it at the attach point is all a caller does to place it, and the box is where
## Build.payload_centre_m weighs it, to the millimetre. Axes are body axes in the caller's space: width
## across X, height up Y, length along Z.

const BOX_INK := Color(0.30, 0.31, 0.34)
const MOUNT_INK := Color(0.55, 0.56, 0.58)


static func build(spec: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Payload"
	if spec.is_empty():
		return root
	var size := PayloadPart.size_m(spec)
	var gap := PayloadPart.mount_gap_m(spec)
	var mount := String(spec.get("mount", "plate"))

	var box := _box(size, BOX_INK, 0.55, 0.45)
	box.name = "PayloadBox"
	box.position = Vector3(0.0, -(gap + size.y * 0.5), 0.0)
	root.add_child(box)

	var span := minf(size.x, size.z)
	match mount:
		"hook":
			# A short post from the aircraft down to a cross-bar over the box, and a hook ring on the box's top.
			var post := _cyl(0.0025, gap, MOUNT_INK)
			post.name = "MountPost"
			post.position = Vector3(0.0, -gap * 0.5, 0.0)
			root.add_child(post)
			var bar := _box(Vector3(minf(span * 0.5, 0.03), 0.003, 0.006), MOUNT_INK, 0.8, 0.35)
			bar.name = "MountBar"
			bar.position = Vector3(0.0, -gap, 0.0)
			root.add_child(bar)
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.0045
			torus.outer_radius = 0.0075
			torus.rings = 16
			torus.ring_segments = 8
			ring.mesh = torus
			ring.material_override = _mat(MOUNT_INK, 0.8, 0.35)
			ring.name = "MountHook"
			ring.rotation = Vector3(PI * 0.5, 0.0, 0.0)
			ring.position = Vector3(0.0, -gap + 0.0045, 0.0)
			root.add_child(ring)
		"gimbal":
			# Two dampers either side and a top plate: the soft mount a gimbal hangs from.
			var plate := _box(Vector3(span * 0.8, 0.002, span * 0.8), MOUNT_INK, 0.8, 0.35)
			plate.name = "MountPlate"
			plate.position = Vector3(0.0, -0.001, 0.0)
			root.add_child(plate)
			for side in [-1.0, 1.0]:
				var damper := _cyl(0.0045, gap - 0.002, MOUNT_INK)
				damper.name = "MountDamper"
				damper.position = Vector3(side * span * 0.28, -0.002 - (gap - 0.002) * 0.5, 0.0)
				root.add_child(damper)
		_:
			var slab := _box(Vector3(size.x * 0.8, gap, size.z * 0.8), MOUNT_INK, 0.8, 0.35)
			slab.name = "MountPlate"
			slab.position = Vector3(0.0, -gap * 0.5, 0.0)
			root.add_child(slab)
	return root


static func _mat(c: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = rough
	return m


static func _box(size: Vector3, c: Color, metallic: float, rough: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c, metallic, rough)
	return mi


static func _cyl(radius: float, height: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = _mat(c, 0.8, 0.35)
	return mi
