class_name TestArmGuard
extends RefCounted
## The arm guard — printed-room slice PR1 (plans/2026-09-14-printed-room-plan.md, PR1 checks 1–7).
##
## Where each check could pass while proving nothing, and what stops it:
##   - "the solid is manifold" passes on an EMPTY list only if nobody counts; the count is asserted
##     first, and the volume is held to the tube's closed form so a box would fail.
##   - "clearance applies" at the default clearance cannot see clearance being ignored; it is checked
##     at 0.10 and 0.35 mm and the bore must grow by exactly 2 × 0.25.
##   - "mass reaches the build" on an unfitted build is always green; the fixture FITS all four.
##   - "a frame without thickness is refused" is a rule that says no; the 5" freestyle is the fixture
##     it says yes to.
##   - "drawn is exported" at the default wall could agree by accident; a 2.4 mm wall is used.

const EPS := 1e-6


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var freestyle := catalog.get_part("frame_5in_freestyle")
	var whoop := catalog.get_part("frame_65mm_whoop")

	results.append_array(_the_solid_is_the_tube(freestyle))
	results.append(_reversed_is_refused(freestyle))
	results.append(_clearance_widens_the_bore(freestyle))
	results.append_array(_a_frame_without_thickness_is_refused(freestyle, whoop))
	results.append_array(_tip_width_is_a_labelled_guess(freestyle, catalog.get_part("frame_5in_race")))
	results.append_array(_mass_is_opt_in_and_symmetric(catalog))
	results.append_array(_drawn_is_exported_and_seated(catalog))
	return results


static func _the_solid_is_the_tube(frame: Dictionary) -> Array:
	var dims := ArmGuard.dimensions(frame, {})
	var triangles := ArmGuard.triangles_mm(dims)
	var report := StlWriter.check_manifold(triangles)
	var expected := ArmGuard.volume_mm3(dims)
	var volume := float(report["volume_mm3"])
	return [
		TestResult.new("the 5\" freestyle's arm guard has triangles to check (32 = 8 per side: outer, bore, two ends)",
			triangles.size() == 32, "%d triangles" % triangles.size()),
		TestResult.new("and they form a closed, outward solid whose volume is the tube's closed form",
			bool(report["ok"]) and absf(volume - expected) < 1e-3 * expected,
			"ok %s, %.3f mm³ vs (outer − bore) × length = %.3f mm³, reasons %s" % [
				report["ok"], volume, expected, report["reasons"]]),
	]


static func _reversed_is_refused(frame: Dictionary) -> TestResult:
	var reversed: Array = []
	for t in ArmGuard.triangles_mm(ArmGuard.dimensions(frame, {})):
		reversed.append(PackedVector3Array([t[0], t[2], t[1]]))
	var result := StlWriter.write("arm_guard", reversed, "user://exports/_never_written.stl")
	return TestResult.new("the same sleeve wound inside out is refused, by name, and not written",
		not bool(result["ok"]) and String(result["reason"]).begins_with("arm_guard:")
			and not FileAccess.file_exists("user://exports/_never_written.stl"),
		String(result["reason"]))


static func _clearance_widens_the_bore(frame: Dictionary) -> TestResult:
	var tight := {}
	PrintSettings.set_clearance_mm(tight, 0.10)
	var loose := {}
	PrintSettings.set_clearance_mm(loose, 0.35)
	var t := ArmGuard.dimensions(frame, tight)
	var l := ArmGuard.dimensions(frame, loose)
	var dw := float(l["bore_width_mm"]) - float(t["bore_width_mm"])
	var dh := float(l["bore_height_mm"]) - float(t["bore_height_mm"])
	# And the triangles carry it, not only the dictionary: the solid's bounding width moves too.
	var span_t := _y_span(ArmGuard.triangles_mm(t))
	var span_l := _y_span(ArmGuard.triangles_mm(l))
	return TestResult.new(
		"0.35 mm clearance opens the bore by exactly 0.5 mm over 0.10 mm, in both directions and in the solid",
		absf(dw - 0.5) < 1e-4 and absf(dh - 0.5) < 1e-4 and absf((span_l - span_t) - 0.5) < 1e-3,
		"width +%.4f, height +%.4f, solid +%.4f mm" % [dw, dh, span_l - span_t])


static func _a_frame_without_thickness_is_refused(freestyle: Dictionary, whoop: Dictionary) -> Array:
	var refused := ArmGuard.dimensions(whoop, {})
	var accepted := ArmGuard.dimensions(freestyle, {})
	var path := "user://exports/_whoop_arm_guard.stl"
	# Cleared first: a run where the refusal was broken WROTE this file, and without this every later
	# run would fail against that leftover rather than against the code (found in PR1's mutation run).
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var written := StlWriter.write("arm_guard", ArmGuard.triangles_mm(refused), path)
	return [
		TestResult.new("a moulded whoop that publishes no arm thickness is refused, naming the part and the field",
			not bool(refused["ok"]) and String(refused["reason"]).begins_with("arm_guard:")
				and String(refused["reason"]).contains("arm_thickness_mm")
				and String(refused["reason"]).contains("frame_65mm_whoop"),
			String(refused.get("reason", ""))),
		TestResult.new("and its export writes no file, while the 5\" freestyle is accepted",
			not bool(written["ok"]) and not FileAccess.file_exists(path) and bool(accepted["ok"]),
			"write ok %s; freestyle ok %s" % [written["ok"], accepted["ok"]]),
	]


static func _tip_width_is_a_labelled_guess(freestyle: Dictionary, race: Dictionary) -> Array:
	var published := ArmGuard.dimensions(freestyle, {})
	var fallback := ArmGuard.dimensions(race, {})
	var edited_printing := {}
	ArmGuard.set_value(edited_printing, ArmGuard.TIP_WIDTH, 14.0)
	var edited := ArmGuard.dimensions(race, edited_printing)
	return [
		TestResult.new("untouched, tip width opens at the frame's published arm width (12 mm) and is marked a guess",
			is_equal_approx(float(published["tip_width_mm"]), 12.0) and bool(published["tip_width_guessed"]),
			"%.1f mm, guessed %s" % [published["tip_width_mm"], published["tip_width_guessed"]]),
		TestResult.new("a frame with no published width opens at 10 mm; a set width is used and not called a guess",
			is_equal_approx(float(fallback["tip_width_mm"]), 10.0) and bool(fallback["tip_width_guessed"])
				and is_equal_approx(float(edited["tip_width_mm"]), 14.0) and not bool(edited["tip_width_guessed"]),
			"fallback %.1f, edited %.1f guessed %s" % [fallback["tip_width_mm"], edited["tip_width_mm"],
				edited["tip_width_guessed"]]),
	]


static func _mass_is_opt_in_and_symmetric(_catalog: PartsCatalog) -> Array:
	var base := ReferenceBuild.build()
	var unfitted := ReferenceBuild.build()
	unfitted.set_printing({ArmGuard.BLOCK: {ArmGuard.WALL: 2.4}})
	var fitted := ReferenceBuild.build()
	var printing := {}
	ArmGuard.set_value(printing, ArmGuard.FITTED, true)
	ArmGuard.set_value(printing, ArmGuard.WALL, 2.4)
	fitted.set_printing(printing)

	var each := ArmGuard.mass_kg(ArmGuard.dimensions(fitted.frame, printing))
	var m0 := base.mass_properties.total_mass_kg
	var m1 := fitted.mass_properties.total_mass_kg
	var moment0 := base.mass_properties.com_m * m0
	var moment1 := fitted.mass_properties.com_m * m1
	return [
		# 507.48 g, not the 496.0 g the printed-room design quotes: PW2 re-baselined the reference build
		# when the harness replaced the 14 g lump (TestHarness.REFERENCE_AUW_G). The design doc is stale.
		TestResult.new("the reference build still weighs 507.48 g, and printing settings alone add nothing",
			absf(m0 * 1000.0 - TestHarness.REFERENCE_AUW_G) < 0.01
				and absf(unfitted.mass_properties.total_mass_kg - m0) < 1e-12,
			"%.3f g, unfitted-with-settings %.3f g" % [m0 * 1000.0,
				unfitted.mass_properties.total_mass_kg * 1000.0]),
		TestResult.new("fitting the guards adds exactly four sleeves' mass",
			each > 0.0 and absf((m1 - m0) - 4.0 * each) < 1e-12,
			"+%.4f g for 4 × %.4f g" % [(m1 - m0) * 1000.0, each * 1000.0]),
		TestResult.new("and moves no first moment: four seats symmetric about the centreline",
			(moment1 - moment0).length() < 1e-12,
			"moment change %s kg·m" % [moment1 - moment0]),
	]


static func _drawn_is_exported_and_seated(_catalog: PartsCatalog) -> Array:
	var build := ReferenceBuild.build()
	var printing := {}
	ArmGuard.set_value(printing, ArmGuard.FITTED, true)
	ArmGuard.set_value(printing, ArmGuard.WALL, 2.4)
	build.set_printing(printing)

	var airframe := AirframeModel.new()
	airframe.rebuild(build)
	var dims := ArmGuard.dimensions(build.frame, printing)
	var expected_triangles := ArmGuard.triangles_mm(dims).size()
	var drawn: ArmGuardMesh = airframe.arm_guard_meshes.get("M2", null)
	var vertices := drawn.drawn_vertex_count() if drawn != null else -1

	var seats_agree := drawn != null
	var worst := 0.0
	var masses := ArmGuard.part_masses(build, printing)
	for i in MotorLayout.MOTOR_NAMES.size():
		var name: String = MotorLayout.MOTOR_NAMES[i]
		var mesh: ArmGuardMesh = airframe.arm_guard_meshes.get(name, null)
		if mesh == null or i >= masses.size():
			seats_agree = false
			continue
		worst = maxf(worst, (mesh.position - (masses[i] as PartMass).position_m).length())
	# The sleeve's local X must land on the arm: take M2 (front-right, nose −Z) as the case whose sign
	# an atan2 gets wrong.
	var along := ArmGuardMesh.arm_basis("M2") * Vector3.RIGHT
	var arm_dir := MotorLayout.motor_position("M2", 1.0).normalized()
	airframe.free()

	return [
		TestResult.new("the drawn sleeve is the exported triangle list, at a 2.4 mm wall",
			expected_triangles > 0 and vertices == expected_triangles * 3,
			"%d vertices drawn for %d triangles" % [vertices, expected_triangles]),
		TestResult.new("every drawn sleeve sits where Build weighs it, and M2's bore runs along its arm",
			seats_agree and worst < 1e-9 and along.distance_to(arm_dir) < 1e-6,
			"worst seat gap %.12f m; M2 axis %s vs arm %s" % [worst, along, arm_dir]),
	]


static func _y_span(triangles: Array) -> float:
	var lo := INF
	var hi := -INF
	for t in triangles:
		for p in t:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
	return hi - lo
