class_name TestWireTubes
extends RefCounted
## WireTubes: three phase wires per motor as round tubes, stack to motor base.

const PAD := Vector3(0.0, 0.020, 0.0)
const MOTORS := [Vector3(0.05, 0.022, 0.05), Vector3(-0.05, 0.022, 0.05), Vector3(-0.05, 0.022, -0.05), Vector3(0.05, 0.022, -0.05)]
const RADIUS := 0.0009


static func run() -> Array:
	var results: Array = []
	var inst := WireTubes.build(PAD, MOTORS, RADIUS, 3)
	var arrays: Array = (inst.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var per_tube := WireTubes.RINGS * WireTubes.SIDES + 2

	results.append(_test_counts(verts, idx, per_tube))
	for m in MOTORS.size():
		for w in 3:
			results.append(_test_tube(verts, per_tube, m, w))
	results.append(_test_outward(verts, idx))
	results.append(_test_awg())
	results.append(_test_material(inst))
	inst.free()
	return results


static func _ring(verts: PackedVector3Array, per_tube: int, tube: int, ring: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var start := tube * per_tube + ring * WireTubes.SIDES
	for k in WireTubes.SIDES:
		out.append(verts[start + k])
	return out


static func _centre(points: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p in points:
		c += p
	return c / float(points.size())


static func _test_counts(verts: PackedVector3Array, idx: PackedInt32Array, per_tube: int) -> TestResult:
	var tubes := MOTORS.size() * 3
	# Per tube: 8 sides x 2 triangles x (rings-1) for the wall, plus an 8-triangle fan at each end.
	var expected := tubes * (WireTubes.SIDES * 2 * (WireTubes.RINGS - 1) + 2 * WireTubes.SIDES)
	return TestResult.new("wire tubes: %d tubes (3 per motor), triangle count matches the formula" % tubes,
		verts.size() == tubes * per_tube and int(idx.size() / 3.0) == expected,
		"%d vertices (want %d), %d triangles (want %d)" % [verts.size(), tubes * per_tube, int(idx.size() / 3.0), expected])


static func _test_tube(verts: PackedVector3Array, per_tube: int, motor: int, wire: int) -> TestResult:
	var tube := motor * 3 + wire
	var first := _centre(_ring(verts, per_tube, tube, 0))
	var last_ring := _ring(verts, per_tube, tube, WireTubes.RINGS - 1)
	var last := _centre(last_ring)
	var d_first := first.distance_to(PAD)
	var d_last := last.distance_to(MOTORS[motor])
	var worst_radius_err := 0.0
	var lowest := INF
	for r in WireTubes.RINGS:
		var ring := _ring(verts, per_tube, tube, r)
		var c := _centre(ring)
		lowest = minf(lowest, c.y)
		for p in ring:
			worst_radius_err = maxf(worst_radius_err, absf(p.distance_to(c) - RADIUS))
	var ok: bool = d_first <= 0.001 and d_last <= 0.001 and worst_radius_err <= 0.00001 and lowest > PAD.y - 0.010
	return TestResult.new("motor %d wire %d: ends on pad and motor, radius true, sag clears the frame" % [motor, wire], ok,
		"start %.3f mm off, end %.3f mm off, radius err %.4f mm, lowest %.2f mm below pad" % [
			d_first * 1000.0, d_last * 1000.0, worst_radius_err * 1000.0, (PAD.y - lowest) * 1000.0])


static func _test_awg() -> TestResult:
	var r20 := WireTubes.radius_for_awg(20)
	var ok := absf(r20 - 0.0009) < 0.0001 and WireTubes.radius_for_awg(16) > WireTubes.radius_for_awg(18) \
		and WireTubes.radius_for_awg(18) > r20
	return TestResult.new("radius_for_awg: 20 AWG about 0.9 mm and thicker for lower gauge", ok, "20 AWG %.3f mm" % (r20 * 1000.0))


static func _test_material(inst: MeshInstance3D) -> TestResult:
	var m := inst.material_override as StandardMaterial3D
	var c := m.albedo_color
	return TestResult.new("wire tubes: matte greyscale material",
		absf(c.r - 0.06) < 1e-4 and c.r == c.g and c.g == c.b and absf(m.roughness - 0.7) < 1e-4,
		"albedo %s roughness %.2f" % [c, m.roughness])


## Same winding convention as the blade mesh (proved outward by tests/test_propeller_mesh.gd): the
## signed volume sum of v0 . (v1 x v2) / 6 is positive for it, so it must be for the tubes too.
static func _test_outward(verts: PackedVector3Array, idx: PackedInt32Array) -> TestResult:
	var vol := 0.0
	for i in range(0, idx.size(), 3):
		vol += verts[idx[i]].dot(verts[idx[i + 1]].cross(verts[idx[i + 2]])) / 6.0
	return TestResult.new("wire tubes: faces wound outward like the blade mesh", vol > 0.0, "signed volume %s" % vol)
