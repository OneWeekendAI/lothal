class_name TestMassProperties
extends RefCounted
## Tests 1-4 from week1.md Day 2: mass, COM, and inertia tensor of the reference build.

const EPSILON := 1e-6

static func run() -> Array:
	var results: Array = []
	var parts := ReferenceBuild.mass_parts()
	var mp := MassProperties.compute(parts)

	var expected_mass_kg := 0.496
	results.append(TestResult.new(
		"total mass = sum of part masses (~496 g)",
		absf(mp.total_mass_kg - expected_mass_kg) < 0.001,
		"got %.4f kg" % mp.total_mass_kg
	))

	results.append(TestResult.new(
		"COM of symmetric build sits at the geometric origin",
		mp.com_m.length() < EPSILON,
		"got %s" % mp.com_m
	))

	var i := mp.inertia
	var off_diag_max: float = max(absf(i.x.y), max(absf(i.x.z), absf(i.y.z)))
	results.append(TestResult.new(
		"inertia tensor of a symmetric X-quad is diagonal",
		off_diag_max < 1e-9,
		"max off-diagonal = %.12f" % off_diag_max
	))

	var i_xx := i.x.x
	var i_yy := i.y.y
	var i_zz := i.z.z
	# Body frame here is Y-up (coordinate contract), so the vertical/yaw axis is Y,
	# not Z as in physics.md's generic aerospace phrasing — see feedback_lothal_code_structure.
	results.append(TestResult.new(
		"I_yy (yaw) > I_xx ~= I_zz (yaw inertia highest on a flat quad)",
		i_yy > i_xx and i_yy > i_zz and absf(i_xx - i_zz) / i_xx < 0.05,
		"I_xx=%.8f I_yy=%.8f I_zz=%.8f" % [i_xx, i_yy, i_zz]
	))

	return results
