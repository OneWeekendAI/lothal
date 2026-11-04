class_name MotorDetailMesh
extends MotorMesh
## A recognisable brushless outrunner for the motor designer's 3D view, drawn from the designer's
## catalog-shaped record. It keeps MotorMesh's stack heights (so the prop seats exactly where it
## does everywhere else) and changes what fills them:
##   Base      - hub disc plus four arms ending in bolt lugs; MountHole0..3 sit on the record's
##               mount pattern (an NxN pattern puts the holes at the corners of an N by N square)
##   Stator    - the iron core and, through the gap under the bell, the copper winding (Winding)
##   Bell      - the can, open below, with a lid: rim, hub, five spokes and the vents between them
##   Shaft     - the record's shaft diameter (shaft_mm), not the stator-size guess MotorMesh uses
##   Adapter, Nut - as MotorMesh
## Monochrome greys; copper only on the winding. Roughly 3000 triangles.

## Visible stator height under the bell, against the stator's own height.
const GAP_TO_STATOR_HEIGHT := 1.5
const SPOKES := 5
## Segments round the bell and winding.
const SEGMENTS := 32

## Mount hole positions (x, z) in metres, filled by rebuild(); and their spacing (the N of NxN).
var hole_positions: Array = []
var mount_spacing_m := 0.0
var shaft_radius_m := 0.0


## Mount spacing in mm from a catalog pattern ("16x16" -> 16). A record without one gets a
## spacing in proportion to the stator, so the base still has holes.
static func mount_spacing_mm(motor: Dictionary) -> float:
	var parts := String(motor.get("mount_pattern", "")).split("x")
	if parts.size() == 2 and parts[0].is_valid_float() and float(parts[0]) > 0.0:
		return float(parts[0])
	return float(motor.get("specs", {}).get("stator_diameter_mm", FALLBACK_STATOR_DIAMETER_MM)) * 0.72


## The shaft diameter in metres: the record's own, else MotorMesh's guess.
static func shaft_diameter_m(motor: Dictionary) -> float:
	var mm := float(motor.get("specs", {}).get("shaft_mm", 0.0))
	if mm > 0.0:
		return mm / 1000.0
	return float(dimensions(motor)["shaft_radius"]) * 2.0


func rebuild(motor: Dictionary, prop_stack_m: float = 0.0, spacer_m: float = 0.0,
		soft_mount_m: float = 0.0) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var d := dimensions(motor)
	var specs: Dictionary = motor.get("specs", {})
	bell_radius_m = d["bell_radius"]
	var stator_r: float = d["stator_radius"]
	var bell_h: float = d["bell_height"]
	var base_h: float = d["base_height"]
	var shaft_d := shaft_diameter_m(motor)
	shaft_radius_m = shaft_d * 0.5
	var adapter_t := shaft_d * ADAPTER_THICKNESS_TO_SHAFT_DIAMETER_RATIO
	var adapter_r := shaft_d * 0.5 * ADAPTER_RADIUS_TO_SHAFT_RADIUS_RATIO
	var nut_r := shaft_d * NUT_WIDTH_TO_SHAFT_DIAMETER_RATIO * 0.5
	var nut_h := shaft_d * NUT_HEIGHT_TO_SHAFT_DIAMETER_RATIO
	var stator_h := float(specs.get("stator_height_mm", FALLBACK_STATOR_HEIGHT_MM)) / 1000.0

	var pad := maxf(soft_mount_m, 0.0)
	var spacer := clampf(spacer_m, 0.0, d["shim_reserve"])
	var base_bottom := pad
	var base_top := base_bottom + base_h
	var bell_top := base_top + bell_h
	prop_mount_height_m = bell_top + adapter_t + spacer
	var shaft_top: float = bell_top + adapter_t + d["shim_reserve"] + maxf(prop_stack_m, 0.0) + nut_h
	total_height_m = shaft_top

	if pad > 0.0:
		_cyl("SoftMount", stator_r * 1.05, pad, pad * 0.5, _rubber_material(), 20)

	# Base: hub, arms and lugs on the mount pattern.
	mount_spacing_m = mount_spacing_mm(motor) / 1000.0
	hole_positions.clear()
	var half := mount_spacing_m * 0.5
	var hole_r := clampf(mount_spacing_m * 0.075, 0.0004, stator_r * 0.2)
	var dark := _anodised_material()
	_cyl("Base", stator_r * 0.8, base_h, base_bottom + base_h * 0.5, dark, SEGMENTS)
	var i := 0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector2(sx * half, sz * half)
			hole_positions.append(p)
			var arm := MeshInstance3D.new()
			arm.name = "MountArm%d" % i
			var box := BoxMesh.new()
			var arm_len := p.length()
			box.size = Vector3(arm_len, base_h * 0.8, hole_r * 2.6)
			arm.mesh = box
			arm.material_override = dark
			arm.position = Vector3(p.x * 0.5, base_bottom + base_h * 0.4, p.y * 0.5)
			arm.rotation.y = -atan2(p.y, p.x)
			add_child(arm)
			var lug := MeshInstance3D.new()
			lug.name = "MountHole%d" % i
			var tor := TorusMesh.new()
			tor.inner_radius = hole_r
			tor.outer_radius = hole_r * 1.9
			tor.rings = 16
			tor.ring_segments = 6
			lug.mesh = tor
			lug.scale = Vector3(1.0, base_h * 0.8 / (hole_r * 0.9 * 2.0), 1.0)
			lug.material_override = dark
			lug.position = Vector3(p.x, base_bottom + base_h * 0.4, p.y)
			add_child(lug)
			i += 1

	# Stator through the gap: iron core and the copper winding with one lobe per slot.
	var gap := minf(stator_h * GAP_TO_STATOR_HEIGHT, bell_h * 0.5)
	_cyl("Stator", stator_r * 0.72, gap, base_top + gap * 0.5, _iron_material(), 24)
	var slots := _slot_count(String(specs.get("config", "12N14P")))
	var winding := MeshInstance3D.new()
	winding.name = "Winding"
	winding.mesh = _winding_mesh(stator_r * 0.98, stator_r * 0.62, gap, slots)
	winding.material_override = _copper_material()
	winding.position = Vector3(0.0, base_top, 0.0)
	add_child(winding)

	# Bell: open can from above the gap, then the vented lid.
	var wall_bottom := base_top + gap
	var wall_h := bell_top - wall_bottom
	var wall := _cyl("Bell", bell_radius_m, wall_h, wall_bottom + wall_h * 0.5, _bell_double_sided(), SEGMENTS)
	(wall.mesh as CylinderMesh).cap_top = false
	(wall.mesh as CylinderMesh).cap_bottom = false
	var rim_w := bell_radius_m * 0.13
	var lid_t := maxf(bell_radius_m * 0.07, 0.0005)
	var hub_r := maxf(adapter_r * 1.5, bell_radius_m * 0.26)
	_cyl("BellHub", hub_r, lid_t, bell_top - lid_t * 0.5, _bell_material(), 20)
	# An open ring of the lid between hub and rim is left empty (the vents); spokes cross it.
	var inner_r := bell_radius_m - rim_w
	for s in SPOKES:
		var a := TAU * float(s) / SPOKES
		var spoke := MeshInstance3D.new()
		spoke.name = "Spoke%d" % s
		var sb := BoxMesh.new()
		var sl := inner_r - hub_r + rim_w
		sb.size = Vector3(sl, lid_t, bell_radius_m * 0.13)
		spoke.mesh = sb
		spoke.material_override = _bell_material()
		var mid := (hub_r + inner_r) * 0.5
		spoke.position = Vector3(cos(a) * mid, bell_top - lid_t * 0.5, sin(a) * mid)
		spoke.rotation.y = -a
		add_child(spoke)
	var rim_ring := MeshInstance3D.new()
	rim_ring.name = "BellRim"
	rim_ring.mesh = _annulus_mesh(inner_r, bell_radius_m, lid_t, SEGMENTS)
	rim_ring.material_override = _bell_material()
	rim_ring.position = Vector3(0.0, bell_top - lid_t, 0.0)
	add_child(rim_ring)

	_cyl("Adapter", adapter_r, adapter_t, bell_top + adapter_t * 0.5, dark, 20)
	if spacer > 0.0:
		_cyl("Spacer", adapter_r * 0.85, spacer, bell_top + adapter_t + spacer * 0.5, _steel_material(), 16)
	var shaft_len := shaft_top - base_bottom - base_h * 0.5
	_cyl("Shaft", shaft_radius_m, shaft_len, base_bottom + base_h * 0.5 + shaft_len * 0.5, _steel_material(), 10)
	if prop_stack_m > 0.0:
		_cyl("Nut", nut_r, nut_h, prop_mount_height_m + prop_stack_m + nut_h * 0.5, _steel_material(), 16)


func _cyl(node_name: String, radius: float, height: float, centre_y: float,
		material: StandardMaterial3D, segments: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = segments
	cylinder.rings = 1
	node.mesh = cylinder
	node.material_override = material
	node.position = Vector3(0, centre_y, 0)
	add_child(node)
	return node


## Slot count from "12N14P" (12); 12 when unreadable.
static func _slot_count(config: String) -> int:
	var n := config.split("N")[0]
	return int(n) if n.is_valid_int() and int(n) >= 3 else 12


## A flat ring from r_in to r_out, `h` tall, y from 0 up. Sides and the top and bottom faces.
static func _annulus_mesh(r_in: float, r_out: float, h: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in segs:
		var a0 := TAU * float(k) / segs
		var a1 := TAU * float(k + 1) / segs
		var c0 := Vector2(cos(a0), sin(a0))
		var c1 := Vector2(cos(a1), sin(a1))
		_quad(st, Vector3(c0.x * r_out, 0, c0.y * r_out), Vector3(c1.x * r_out, 0, c1.y * r_out),
			Vector3(c1.x * r_out, h, c1.y * r_out), Vector3(c0.x * r_out, h, c0.y * r_out))
		_quad(st, Vector3(c1.x * r_in, 0, c1.y * r_in), Vector3(c0.x * r_in, 0, c0.y * r_in),
			Vector3(c0.x * r_in, h, c0.y * r_in), Vector3(c1.x * r_in, h, c1.y * r_in))
		_quad(st, Vector3(c0.x * r_in, h, c0.y * r_in), Vector3(c0.x * r_out, h, c0.y * r_out),
			Vector3(c1.x * r_out, h, c1.y * r_out), Vector3(c1.x * r_in, h, c1.y * r_in))
		_quad(st, Vector3(c1.x * r_in, 0, c1.y * r_in), Vector3(c1.x * r_out, 0, c1.y * r_out),
			Vector3(c0.x * r_out, 0, c0.y * r_out), Vector3(c0.x * r_in, 0, c0.y * r_in))
	st.generate_normals()
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, c, b, a, d, c]:
		st.add_vertex(v)


## The winding: `slots` lobes round a core, bulging at mid height. Radial normals, so it reads smooth.
static func _winding_mesh(r_out: float, r_valley: float, h: float, slots: int) -> ArrayMesh:
	var per := 4
	var n := slots * per
	var rows := 4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for j in rows + 1:
		var t := float(j) / rows
		var bulge := sin(t * PI) * 0.35 + 0.65
		var row: Array = []
		for k in n:
			var a := TAU * float(k) / n
			var lobe := 0.5 + 0.5 * cos(a * slots)
			var r := lerpf(r_valley, r_out, lobe) * lerpf(0.9, 1.0, bulge)
			row.append([Vector3(cos(a) * r, t * h, sin(a) * r), Vector3(cos(a), 0.0, sin(a))])
		grid.append(row)
	for j in rows:
		for k in n:
			var k2 := (k + 1) % n
			var p00: Array = grid[j][k]
			var p01: Array = grid[j][k2]
			var p10: Array = grid[j + 1][k]
			var p11: Array = grid[j + 1][k2]
			for q in [p00, p10, p01, p01, p10, p11]:
				st.set_normal(q[1])
				st.add_vertex(q[0])
	return st.commit()


func _bell_double_sided() -> StandardMaterial3D:
	var m := _bell_material()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _iron_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.17, 0.20)
	m.roughness = 0.5
	m.metallic = 0.6
	return m


## Copper, the only tint in the picture.
func _copper_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.80, 0.46, 0.27)
	m.roughness = 0.4
	m.metallic = 0.7
	return m
