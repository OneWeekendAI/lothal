class_name MassProperties
extends RefCounted
## Composite mass, centre of mass, and inertia tensor of an assembled build.
## Parallel-axis offsets are measured from the COMPOSITE centre of mass, never
## from the origin — see physics.md §2 for why that distinction matters.

var total_mass_kg: float
var com_m: Vector3
var inertia: Basis          # 3x3 tensor stored as a Basis (columns = X/Y/Z rows)
var inertia_inverse: Basis

static func compute(parts: Array) -> MassProperties:
	var result := MassProperties.new()

	var total_mass := 0.0
	var moment := Vector3.ZERO
	for part in parts:
		total_mass += part.mass_kg
		moment += part.mass_kg * part.position_m
	var com := moment / total_mass if total_mass > 0.0 else Vector3.ZERO

	var i_total := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	for part in parts:
		var d: Vector3 = part.position_m - com
		var d_sq := d.length_squared()

		# Local tensor: axis-aligned in the body frame for every part in this build,
		# so no B_i * I_local * B_i^T rotation is needed (see physics.md §2, note 2).
		var local := Basis(
			Vector3(part.local_inertia_diag.x, 0, 0),
			Vector3(0, part.local_inertia_diag.y, 0),
			Vector3(0, 0, part.local_inertia_diag.z)
		)

		# Parallel axis theorem: I += m * (|d|^2 * E - d ⊗ d)
		var shift := Basis(
			Vector3(d_sq - d.x * d.x, -d.x * d.y, -d.x * d.z),
			Vector3(-d.y * d.x, d_sq - d.y * d.y, -d.y * d.z),
			Vector3(-d.z * d.x, -d.z * d.y, d_sq - d.z * d.z)
		)

		i_total = _add(i_total, _add(local, _scale(shift, part.mass_kg)))

	result.total_mass_kg = total_mass
	result.com_m = com
	result.inertia = i_total
	result.inertia_inverse = i_total.inverse()
	return result

static func _add(a: Basis, b: Basis) -> Basis:
	return Basis(a.x + b.x, a.y + b.y, a.z + b.z)

static func _scale(a: Basis, s: float) -> Basis:
	return Basis(a.x * s, a.y * s, a.z * s)
