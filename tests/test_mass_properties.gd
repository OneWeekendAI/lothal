class_name TestMassProperties
extends RefCounted
## Tests 1-4 from week1.md Day 2: mass, COM, and inertia tensor of the reference build.

const EPSILON := 1e-6

static func run() -> Array:
	var results: Array = []
	var parts := ReferenceBuild.mass_parts()
	var mp := MassProperties.compute(parts)

	var expected_mass_kg := 0.5075
	results.append(TestResult.new(
		"total mass = sum of part masses (~507 g)",
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
	# X IS STILL EXACTLY ZERO AND Z IS NO LONGER, and the split is LTHL-11's. Every part on this
	# aircraft is on the centreline or symmetric about it, so a lateral drift still means the mount
	# resolution or the frame's mass distribution is wrong — that half of the check is untouched,
	# at the same bound.
	#
	# Fore and aft, the camera now sits at the front edge of the centre plate and the VTX and the
	# antenna at the rear, so the build carries a real 0.18 mm aft offset. That is a fact about a
	# real quad rather than a defect: the four components weigh 21 g between them and they are not
	# in the same place. What is asserted instead is that the offset is EXACTLY the moment those
	# components make — the same aircraft with nothing in its bays comes out at exactly zero, which
	# is the version of the old claim that is still true and still catches an asymmetric arm.
	results.append(TestResult.new(
		"COM of a symmetric build is laterally exact: no X, and no Z once the bays are empty",
		absf(mp.com_m.x) < EPSILON
			and absf(ReferenceBuild.fore_aft_symmetric().mass_properties.com_m.z) < EPSILON
			and absf(ReferenceBuild.fore_aft_symmetric().mass_properties.com_m.x) < EPSILON,
		"fitted %s, bays empty %s" % [mp.com_m, ReferenceBuild.fore_aft_symmetric().mass_properties.com_m]
	))
	results.append(TestResult.new(
		"and the fitted build's 0.18 mm aft offset is exactly the four components' own moment",
		absf(mp.com_m.z - _component_moment_z(ReferenceBuild.build())) < 1e-9,
		"com.z = %.9f m, the components' moment / total mass = %.9f m" % [
			mp.com_m.z, _component_moment_z(ReferenceBuild.build())]
	))
	# 11.633 mm until LTHL-11, 11.971 after it, and 11.832 since PW2. The four components sit on and
	# between the plates rather than at the origin, and three of the four are above the plate
	# midplane — so taking 21 g out of a box at y = 0 and putting it where it actually lives raises
	# the whole aircraft's centre of mass by a third of a millimetre. PW2 moved it back DOWN by
	# a seventh of a millimetre, which is the opposite of what a heavier aircraft suggests and is the
	# harness being real: the 14 g lump sat at the origin, and what replaced it is 8 g of lead lying
	# in the plane of the frame and 5 g of straps at the origin against only 3 g of plug up at the
	# pack and 3.5 g of capacitor on the ESC. The bound is unchanged.
	results.append(TestResult.new(
		"COM sits above the plates, because the pack is strapped on top of them",
		absf(mp.com_m.y - 0.011832) < 1e-5,
		"got %.5f m up" % mp.com_m.y
	))

	# DIAGONAL WHEN THE BAYS ARE EMPTY, AND OFF-DIAGONAL IN ONE TERM WHEN THEY ARE NOT — which is
	# the same partition as the centre-of-mass check above, and for the same reason. A product of
	# inertia needs mass that is off-axis in TWO axes at once: the camera is forward AND low, the
	# antenna is aft AND high, so they make an I_yz and nothing else. I_xy and I_xz must still be
	# exactly zero, because nothing on this aircraft is off-centre laterally, and that is the half
	# of the claim that would catch a crossed axis.
	var i := mp.inertia
	var symmetric := ReferenceBuild.fore_aft_symmetric().mass_properties.inertia
	var symmetric_max: float = max(absf(symmetric.x.y), max(absf(symmetric.x.z), absf(symmetric.y.z)))
	results.append(TestResult.new(
		"inertia tensor of a symmetric X-quad is diagonal",
		symmetric_max < 1e-9,
		"max off-diagonal = %.12f with the bays empty" % symmetric_max
	))
	results.append(TestResult.new(
		"and with the bays filled the only off-diagonal term is I_yz, the camera against the antenna",
		absf(i.x.y) < 1e-12 and absf(i.x.z) < 1e-12 and absf(i.y.z) > 1e-9,
		"I_xy = %.12f, I_xz = %.12f, I_yz = %.12f" % [i.x.y, i.x.z, i.y.z]
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
	# The pack was the WHOLE of this difference until LTHL-11, and it is now the largest of three
	# terms: the four unbundled components lie fore-and-aft too, so they contribute the same way a
	# pack does, and PW2's main lead contributes for a different reason — it is on the centreline,
	# so its position cancels, but it is a rod lying fore-and-aft and a rod has no inertia about its
	# own axis at all. The claim is unchanged in kind and is now stated as a PARTITION — every part that
	# is symmetric in X and Z contributes exactly nothing, and the parts that do contribute account
	# for the total to numerical precision. That is strictly stronger than the old form, which
	# asserted a single term and could not have noticed a fifth one appearing.
	var contributions := _pitch_minus_roll_contributions(ReferenceBuild.build())
	# The symmetric parts contribute 9.7e-9, not zero, and it is worth being exact about why rather
	# than loosening a bound around it. A part that is symmetric in the AIRFRAME is not symmetric
	# about a centre of mass 0.18 mm behind the airframe's origin: the front motors end up 0.18 mm
	# further from the pitch axis than the rear ones, and the algebra collapses to one term —
	# com.z^2 times the mass of everything symmetric. It is second order in a fifth of a
	# millimetre, which is why it is 0.011% of the difference it sits inside, and it is asserted at
	# its predicted value rather than as "small".
	var symmetric_mass := 0.0
	var component_labels := _component_labels(ReferenceBuild.build())
	for part in ReferenceBuild.build().mass_parts():
		if (part as PartMass).label != "Pack" and (part as PartMass).label != "Main lead" \
				and not component_labels.has((part as PartMass).label):
			symmetric_mass += (part as PartMass).mass_kg
	var predicted_residue: float = mp.com_m.z * mp.com_m.z * symmetric_mass

	results.append(TestResult.new(
		"pitch inertia exceeds roll inertia, and the parts lying fore-and-aft are the whole of it",
		i_xx > i_zz and absf((i_xx - i_zz) - contributions["total"]) < 1e-9
			and absf(contributions["symmetric_parts"] - predicted_residue) < 1e-10
			# And the new term is real rather than a bucket that happens to be empty.
			and contributions["main_lead"] > 0.0,
		"I_xx - I_zz = %.9f, of which the pack accounts for %.9f, the camera, VTX and antenna for %.9f and the main lead for %.9f; the %.0f g of symmetric parts add %.12f against a predicted com.z^2 * m of %.12f" % [
			i_xx - i_zz, contributions["pack"], contributions["components"],
			contributions["main_lead"],
			symmetric_mass * 1000.0, contributions["symmetric_parts"], predicted_residue]
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


## The four optional components' fore/aft moment, divided by the whole aircraft's mass — which is
## where the centre of mass sits when nothing else is off the origin fore or aft, and the empty-bay
## build above is what establishes that nothing else is.
static func _component_moment_z(build: Build) -> float:
	var moment := 0.0
	for category in Build.OPTIONAL_COMPONENTS:
		if not build.components.has(category):
			continue
		var component: Dictionary = build.components[category]
		var seat := MountLayout.seated_centre_m(
			MountLayout.by_id(build.mount_points(), String(Build.COMPONENT_MOUNTS[category])),
			Build.component_size_of(component))
		moment += float(component["mass_g"]) / 1000.0 * seat.z
	return moment / build.mass_properties.total_mass_kg


## Each part's own contribution to I_xx - I_zz, taken about the build's centre of mass and summed
## into three buckets: the pack, the four unbundled components, and everything else.
##
## Hand-derived rather than read off MassProperties, which is the point of it as a cross-check. For
## a part at displacement d from the centre of mass, the parallel-axis term adds m*(d.y^2 + d.z^2)
## to I_xx and m*(d.x^2 + d.y^2) to I_zz, so the difference is m*(d.z^2 - d.x^2) plus whatever its
## own box already differs by. Anything on the centreline with d.z = d.x contributes zero, which is
## every motor pair, the frame, the boards, the receiver and the wiring.
static func _pitch_minus_roll_contributions(build: Build) -> Dictionary:
	var com := build.mass_properties.com_m
	var out := {"pack": 0.0, "components": 0.0, "main_lead": 0.0, "symmetric_parts": 0.0,
		"total": 0.0}
	var component_names: Array[String] = []
	for category in Build.OPTIONAL_COMPONENTS:
		if build.components.has(category):
			component_names.append(str(build.components[category]["name"]))

	for part in build.mass_parts():
		var entry := part as PartMass
		var d: Vector3 = entry.position_m - com
		var contribution: float = entry.local_inertia_diag.x - entry.local_inertia_diag.z \
			+ entry.mass_kg * (d.z * d.z - d.x * d.x)
		out["total"] += contribution
		if entry.label == "Pack":
			out["pack"] += contribution
		elif component_names.has(entry.label):
			out["components"] += contribution
		elif entry.label == "Main lead":
			# THE THIRD TERM, AND IT IS A LOCAL TENSOR RATHER THAN A POSITION (PW2). The main lead
			# sits on the centreline, so its m·d² terms cancel exactly the way every symmetric
			# part's do — but it is a ROD lying fore-and-aft, and a rod has no inertia about its own
			# axis. So it contributes to pitch and nothing to roll, which is real: a wire lying
			# along the aircraft resists pitching and does not resist rolling.
			out["main_lead"] += contribution
		else:
			out["symmetric_parts"] += contribution
	return out


## The labels of the optional components fitted to this build, for telling them apart from the
## symmetric entries in the mass list. The label rather than the category, because a PartMass
## carries the part's own name and nothing else that identifies it.
static func _component_labels(build: Build) -> Array[String]:
	var out: Array[String] = []
	for category in Build.OPTIONAL_COMPONENTS:
		if build.components.has(category):
			out.append(str(build.components[category]["name"]))
	return out
