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

	# LATERALLY at the origin, and 11.6 mm above it.
	#
	# This assertion used to read "the COM sits at the geometric origin", which held only because
	# every part except the four motors was pinned there. Now that the pack sits where it is
	# strapped, the vertical half of it is simply false — and finding out WHY was worth more than
	# the line: a 185 g pack on the TOP PLATE is 37% of a 496 g aircraft sitting 31 mm up, so a real
	# 5" quad's centre of mass is about a centimetre above its plates. "Centred on its mount"
	# constrains fore/aft and lateral only; the mount's own 12.5 mm height is real, and the frame's
	# origin is the plate midplane rather than a balance point.
	#
	# The two halves are asserted separately because they mean different things. X and Z at exactly
	# zero is the symmetry check this line was always worth. Y is a measurement.
	results.append(TestResult.new(
		"COM of a symmetric build is laterally exact: no X, no Z",
		absf(mp.com_m.x) < EPSILON and absf(mp.com_m.z) < EPSILON,
		"got %s" % mp.com_m
	))
	results.append(TestResult.new(
		"COM sits above the plates, because the pack is strapped on top of them",
		absf(mp.com_m.y - 0.011633) < 1e-5,
		"got %.5f m up" % mp.com_m.y
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
		"I_yy (yaw) > I_xx and I_zz (yaw inertia highest on a flat quad)",
		i_yy > i_xx and i_yy > i_zz,
		"I_xx=%.8f I_yy=%.8f I_zz=%.8f" % [i_xx, i_yy, i_zz]
	))

	# This used to read "I_xx ~= I_zz, within 5%", which was true of a pack estimated as a box
	# from mass and is not true of the real one. A 75 mm pack lying fore-and-aft is 4.5% further
	# from the pitch axis (X) than from the roll axis (Z), so pitch inertia genuinely exceeds roll
	# inertia — which is a real property of a real quad and the reason a quad rolls faster than it
	# pitches. Loosening the tolerance would have hidden that; asserting the direction shows it.
	#
	# The stronger half is where the asymmetry COMES FROM. Four arms on a symmetric X contribute
	# identically to I_xx and I_zz, and so do the square centre plate and the electronics box. So
	# the whole difference must be the pack's own, to numerical precision — an assertion that fails
	# if an arm term ever stops being symmetric, which "within 5%" could never have noticed.
	var pack := _battery_inertia(ReferenceBuild.build())
	results.append(TestResult.new(
		"pitch inertia exceeds roll inertia, and the pack lying fore-and-aft is the whole of it",
		i_xx > i_zz and absf((i_xx - i_zz) - (pack.x - pack.z)) < 1e-9,
		"I_xx - I_zz = %.9f, of which the pack's own box accounts for %.9f" % [
			i_xx - i_zz, pack.x - pack.z]
	))

	results.append_array(_pack_inertia_comes_from_the_catalog(ReferenceBuild.build()))

	return results


## The pack's own tensor is built from its PUBLISHED dimensions, and `_battery_size_m` survives
## only as the fallback for a catalog entry that has none.
##
## This is the single-source rule applied to the one component that had two answers. The drawn
## block and the inertia contribution must come from the same three numbers, or the app is back to
## the divergence AirframeModel exists to prevent — except invisible, because an inertia tensor
## does not appear on screen.
##
## Axis mapping is load-bearing and is asserted rather than assumed: nose is -Z (physics.md §1),
## so a pack's LENGTH lies along Z, its width across X and its height up Y. Feeding the same three
## numbers in the wrong order would produce a perfectly plausible tensor for a pack mounted
## sideways.
static func _pack_inertia_comes_from_the_catalog(build: Build) -> Array:
	var results: Array = []
	var specs: Dictionary = build.battery["specs"]
	var mass_kg: float = float(build.battery["mass_g"]) / 1000.0

	var expected := InertiaPrimitives.box(mass_kg, Vector3(
		float(specs["width_mm"]) / 1000.0,
		float(specs["height_mm"]) / 1000.0,
		float(specs["length_mm"]) / 1000.0))
	var actual := _battery_inertia(build)
	# What the old mass estimate would have said, quoted in the detail so the size of the change
	# is on the record rather than inferred.
	var estimated := InertiaPrimitives.box(mass_kg, Vector3(0.035, 0.030, 0.070)
		* pow(mass_kg / 0.185, 1.0 / 3.0))

	results.append(TestResult.new(
		"the pack's inertia is built from its published dimensions, length along the forward axis",
		actual.distance_to(expected) < 1e-12 and actual.distance_to(estimated) > 1e-6,
		"I=%s from %.0f x %.0f x %.0f mm; the mass estimate would have said %s" % [
			actual, float(specs["length_mm"]), float(specs["width_mm"]), float(specs["height_mm"]),
			estimated]
	))

	# A pack whose contributor has not filled the dimensions in still gets a box rather than a
	# point mass, which is what keeps the fallback worth having.
	var undimensioned: Dictionary = build.battery.duplicate(true)
	for key in ["length_mm", "width_mm", "height_mm"]:
		(undimensioned["specs"] as Dictionary).erase(key)
	build.battery = undimensioned
	var fallback := _battery_inertia(build)

	results.append(TestResult.new(
		"a pack with no published dimensions falls back to the estimate from mass",
		fallback.distance_to(estimated) < 1e-12,
		"I=%s, which is the 70x30x35 box scaled by the cube root of %.3f kg" % [fallback, mass_kg]
	))

	return results


## The battery's local tensor, found by its mass AND the position the mount resolution puts it at,
## rather than by an index into mass_parts() — an index would keep passing while pointing at the
## electronics.
##
## The position half of that test used to read `position_m == Vector3.ZERO`, which stopped being a
## way of recognising the pack the moment the pack acquired a position. It is asked of MountLayout
## now, which keeps the check doing what it was for: this is the entry the mount system placed, at
## the seat it placed it on, and not some other 185 g object.
static func _battery_inertia(build: Build) -> Vector3:
	var mass_kg: float = float(build.battery["mass_g"]) / 1000.0
	var mount := MountLayout.by_id(build.mount_points(), String(build.assembly_value("battery_mount")))
	var seated := MountLayout.seated_centre_m(mount, build.battery_size_m(),
		float(build.assembly_value("battery_offset_m")))
	for part in build.mass_parts():
		if absf(part.mass_kg - mass_kg) < 1e-9 and (part.position_m - seated).length() < 1e-9:
			return part.local_inertia_diag
	return Vector3.ZERO
