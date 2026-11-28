class_name WireTubes
extends RefCounted
## Motor phase wires drawn as thin round tubes from the stack to each motor base: one ArrayMesh,
## `wires_per_motor` side-by-side tubes per motor, each a closed 8-sided tube along a gently
## sagging cubic Bezier. Matte black silicone (greyscale).
##
## Vertex layout per tube (relied on by tests/test_wire_tubes.gd): RINGS rings of SIDES vertices
## (ring 0 at the stack, last ring at the motor), then two cap-centre vertices. Tubes are emitted
## motor by motor, wire by wire.

const SIDES := 8
const RINGS := 12
## Sag of the Bezier control points, as a fraction of the run, capped so a long arm cannot droop
## through the frame: the curve itself dips about 3/4 of this.
const SAG_FRACTION := 0.10
const SAG_MAX_M := 0.008
## Centre-to-centre spacing between neighbouring wires mid-run, in wire diameters. The wires
## converge to the pad and the motor point at their ends (envelope 4t(1-t)).
const SPACING_DIAMETERS := 1.05
## Silicone wall thickness used for the outer radius, mm. Typical hobby silicone wire has a wall
## of about 0.5 mm.
const INSULATION_WALL_MM := 0.5


## Outer radius in metres for a given AWG: bare conductor diameter from the ASTM B258 definition,
## d_mm = 0.127 * 92^((36 - AWG) / 39) (20 AWG = 0.812 mm, 18 AWG = 1.024 mm, 16 AWG = 1.291 mm),
## plus INSULATION_WALL_MM of silicone each side. 20 AWG gives 0.906 mm, matching the ~1.8 mm OD of
## commercial 20 AWG silicone wire.
static func radius_for_awg(awg: int) -> float:
	var bare_mm := 0.127 * pow(92.0, float(36 - awg) / 39.0)
	return (bare_mm + 2.0 * INSULATION_WALL_MM) * 0.5 * 0.001


static func triangles_per_tube() -> int:
	return SIDES * 2 * (RINGS - 1) + SIDES * 2


## The centre line of wire `wire` of `wires` from `from` to `to`, RINGS points.
static func path_points(from: Vector3, to: Vector3, radius_m: float, wire: int, wires: int) -> PackedVector3Array:
	var run := to - from
	var sag := minf(run.length() * SAG_FRACTION, SAG_MAX_M)
	var c1 := from + run / 3.0 + Vector3(0, -sag, 0)
	var c2 := from + run * 2.0 / 3.0 + Vector3(0, -sag, 0)
	var flat := Vector3(run.x, 0, run.z)
	var lateral := Vector3.ZERO
	if flat.length() > 1e-9:
		lateral = flat.normalized().cross(Vector3.UP)
	var offset := (float(wire) - float(wires - 1) * 0.5) * 2.0 * radius_m * SPACING_DIAMETERS
	var out := PackedVector3Array()
	for i in RINGS:
		var t := float(i) / float(RINGS - 1)
		var u := 1.0 - t
		var p := from * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + to * t * t * t
		out.append(p + lateral * offset * 4.0 * t * u)
	return out


static func build(stack_pad: Vector3, motor_points: Array, radius_m: float, wires_per_motor := 3) -> MeshInstance3D:
	# Raw arrays rather than SurfaceTool, so the vertex layout above is exactly what is committed.
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for motor in motor_points:
		for w in wires_per_motor:
			var base := verts.size()
			var path := path_points(stack_pad, motor as Vector3, radius_m, w, wires_per_motor)
			var tangents := PackedVector3Array()
			for i in RINGS:
				var tangent := (path[mini(i + 1, RINGS - 1)] - path[maxi(i - 1, 0)]).normalized()
				tangents.append(tangent)
				var ref := Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
				var side := tangent.cross(ref).normalized()
				var up := side.cross(tangent).normalized()
				for k in SIDES:
					var a := TAU * float(k) / float(SIDES)
					var radial := side * cos(a) + up * sin(a)
					verts.append(path[i] + radial * radius_m)
					normals.append(radial)
			verts.append(path[0])
			normals.append(-tangents[0])
			verts.append(path[RINGS - 1])
			normals.append(tangents[RINGS - 1])
			for i in RINGS - 1:
				for k in SIDES:
					var k2 := (k + 1) % SIDES
					var a := base + i * SIDES + k
					var b := base + i * SIDES + k2
					indices.append_array([a, a + SIDES, b, b, a + SIDES, b + SIDES])
			var c0 := base + RINGS * SIDES
			var last := base + (RINGS - 1) * SIDES
			for k in SIDES:
				var k2 := (k + 1) % SIDES
				indices.append_array([c0, base + k, base + k2, c0 + 1, last + k2, last + k])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var inst := MeshInstance3D.new()
	inst.name = "WireTubes"
	inst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.06, 0.06)
	mat.roughness = 0.7
	mat.metallic = 0.0
	inst.material_override = mat
	return inst
