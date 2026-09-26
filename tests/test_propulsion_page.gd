class_name TestPropulsionPage
extends RefCounted
## The Propulsion item pages (lab dock design §3, §4): Motors, Propellers and Prop guards, headless.
##
## What this suite guards: each page's numbers and its drawing come from ONE computation
## (`PropulsionFigures`), shared with the row, so the list, the two page numbers and the chart
## cannot disagree. And the Motors number says what it is — the thrust this pack can drive, not the
## catalogue's test-stand figure — because the two differ (1047 g against 1450 g on the reference
## build) and a bare "thrust each" beside a sheet reading "Max thrust 1450 g" reads as a bug.
##
## One test per case.


static func run() -> Array:
	var out: Array = []
	var build := ReferenceBuild.build()
	var catalog := PartsCatalog.load_default()
	var guarded := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, {}, null, "guard_bumper_5in_abs")

	# --- the shared figures
	out.append(_peak_each_is_the_builds_peak_over_four(build))
	out.append(_peak_each_is_below_the_catalogue_on_this_pack(build))
	out.append(_the_ceiling_names_what_binds(build))
	out.append(_the_curve_ends_at_the_ceiling(build))
	out.append(_the_curve_peaks_at_the_row_number(build))
	out.append(_the_catalogue_test_is_read_not_invented(build))
	out.append(_hover_each_is_a_quarter_of_the_weight(build))
	out.append(_hover_rpm_is_the_rpm_at_hover_throttle(build))
	out.append(_guard_mass_is_four_computed_rings(guarded))
	out.append(_no_guard_adds_nothing(build))
	out.append(_guard_roll_inertia_is_the_twin_difference(build, guarded))
	out.append(_guard_tip_gap_is_prop_guards_own(guarded))

	# --- the rows
	out.append(_motors_row_says_this_pack(build))
	out.append(_guards_row_fitted_reads_mass_and_roll(guarded))

	# --- the page numbers
	out.append(_motors_page_numbers(build))
	out.append(_propellers_page_numbers(build))
	out.append(_guards_page_numbers_fitted(guarded))
	out.append(_guards_page_numbers_none(build))
	return out


static func _row(rows: Array, id: StringName) -> Dictionary:
	for row in rows:
		if row["id"] == id:
			return row
	return {}


static func _peak_each_is_the_builds_peak_over_four(build: Build) -> TestResult:
	var want := float(build.peak_thrust()["thrust_n"]) / 4.0 / Build.GRAVITY_MPS2 * 1000.0
	var got := PropulsionFigures.peak_each_g(build)
	return TestResult.new("propulsion figures: peak each is Build.peak_thrust / 4, in grams",
		is_equal_approx(got, want) and got > 100.0, "%.1f vs %.1f" % [got, want])


## The reference build's reason for this whole slice: on its 4S 1500 the reachable thrust is well
## under the 1450 g the motor was rated at on a stand.
static func _peak_each_is_below_the_catalogue_on_this_pack(build: Build) -> TestResult:
	var got := PropulsionFigures.peak_each_g(build)
	var rated := float(build.motor["specs"]["max_thrust_g"])
	return TestResult.new("propulsion figures: the reference pack reaches less than the catalogue figure",
		got < rated - 100.0, "%.0f g vs catalogue %.0f g" % [got, rated])


static func _the_ceiling_names_what_binds(build: Build) -> TestResult:
	var ceiling := PropulsionFigures.throttle_ceiling(build)
	return TestResult.new("propulsion figures: the throttle ceiling is the weakest link's, named",
		is_equal_approx(float(ceiling["fraction"]), build.max_throttle_fraction())
			and ceiling["limiter"] == "pack", str(ceiling))


static func _the_curve_ends_at_the_ceiling(build: Build) -> TestResult:
	var curve := PropulsionFigures.thrust_curve_each_g(build, 20)
	var last: Vector2 = curve[curve.size() - 1] if not curve.is_empty() else Vector2.ZERO
	return TestResult.new("propulsion figures: the thrust curve runs 0 to the throttle ceiling",
		curve.size() == 21 and (curve[0] as Vector2).x == 0.0
			and is_equal_approx(last.x, build.max_throttle_fraction()), "%d points, last %s" % [
			curve.size(), last])


static func _the_curve_peaks_at_the_row_number(build: Build) -> TestResult:
	var best := 0.0
	for point in PropulsionFigures.thrust_curve_each_g(build, 400):
		best = maxf(best, (point as Vector2).y)
	var peak := PropulsionFigures.peak_each_g(build)
	return TestResult.new("propulsion figures: the curve's highest point is the row's peak",
		absf(best - peak) < 0.5, "curve %.1f, peak %.1f" % [best, peak])


static func _the_catalogue_test_is_read_not_invented(build: Build) -> TestResult:
	var test := PropulsionFigures.catalogue_test(build)
	return TestResult.new("propulsion figures: the catalogue point is the motor's published test",
		is_equal_approx(float(test["grams"]), 1450.0) and is_equal_approx(float(test["volts"]), 14.8)
			and str(test["prop"]) == "5x4.3x3", str(test))


static func _hover_each_is_a_quarter_of_the_weight(build: Build) -> TestResult:
	var got := PropulsionFigures.hover_each_g(build)
	return TestResult.new("propulsion figures: hover each is a quarter of the all-up weight",
		is_equal_approx(got, build.all_up_weight_g() / 4.0), "%.1f" % got)


static func _hover_rpm_is_the_rpm_at_hover_throttle(build: Build) -> TestResult:
	var got := PropulsionFigures.hover_rpm(build)
	return TestResult.new("propulsion figures: hover rpm is rpm_at_throttle(hover throttle)",
		is_equal_approx(got, build.rpm_at_throttle(build.hover_throttle())) and got > 1000.0,
		"%.0f" % got)


static func _guard_mass_is_four_computed_rings(guarded: Build) -> TestResult:
	var got := PropulsionFigures.guard_added_g(guarded)
	var ring := PropGuard.mass_kg(guarded.guard["specs"]) * 1000.0
	return TestResult.new("propulsion figures: guard mass is four rings from PropGuard.mass_kg",
		is_equal_approx(got, ring * 4.0) and got > 10.0, "%.2f vs 4 × %.2f" % [got, ring])


static func _no_guard_adds_nothing(build: Build) -> TestResult:
	return TestResult.new("propulsion figures: no guard adds 0 g and 0 roll inertia",
		PropulsionFigures.guard_added_g(build) == 0.0
			and PropulsionFigures.guard_roll_inertia_fraction(build) == 0.0, "")


## The build's own roll inertia (I_ZZ, AirframeProperties' convention) with the guards against the
## same aircraft without them — not PropGuard's point-mass scalar, which the tensor does not use.
static func _guard_roll_inertia_is_the_twin_difference(build: Build, guarded: Build) -> TestResult:
	var bare := build.mass_properties.inertia.z.z
	var with_guard := guarded.mass_properties.inertia.z.z
	var want := (with_guard - bare) / bare
	var got := PropulsionFigures.guard_roll_inertia_fraction(guarded)
	return TestResult.new("propulsion figures: guard roll inertia is the with/without I_ZZ difference",
		absf(got - want) < 1e-6 and got > 0.05, "%.4f vs %.4f" % [got, want])


static func _guard_tip_gap_is_prop_guards_own(guarded: Build) -> TestResult:
	var doc := PropellerDetails.document_for(guarded.propeller)
	var want := PropGuard.tip_clearance_mm(guarded.guard["specs"], doc.radius_mm())
	var got := PropulsionFigures.guard_tip_gap_mm(guarded)
	return TestResult.new("propulsion figures: the guard's tip gap is PropGuard.tip_clearance_mm",
		is_equal_approx(got, want) and got > 0.0, "%.2f vs %.2f" % [got, want])


## The fix for "1047 g thrust each" beside a sheet reading "Max thrust 1450 g": the row says the
## number is what THIS pack drives.
static func _motors_row_says_this_pack(build: Build) -> TestResult:
	var row := _row(SectionRows.rows("Propulsion", build, []), &"motors")
	var want := "%d g max each on this pack" % roundi(PropulsionFigures.peak_each_g(build))
	return TestResult.new("propulsion rows: Motors reads '<g> max each on this pack'",
		row.get("number") == want and want.length() <= WarningRows.SHORT_MAX,
		"'%s' want '%s'" % [row.get("number"), want])


static func _guards_row_fitted_reads_mass_and_roll(guarded: Build) -> TestResult:
	var row := _row(SectionRows.rows("Propulsion", guarded, []), &"guards")
	var want := "+%d g · roll inertia +%d%%" % [roundi(PropulsionFigures.guard_added_g(guarded)),
		roundi(PropulsionFigures.guard_roll_inertia_fraction(guarded) * 100.0)]
	return TestResult.new("propulsion rows: a fitted guard reads its added mass and roll inertia",
		row.get("number") == want, "'%s' want '%s'" % [row.get("number"), want])


static func _motors_page_numbers(build: Build) -> TestResult:
	var got := SectionRows.page_numbers(&"motors", build)
	var want := [["Max each, this pack", "%d g" % roundi(PropulsionFigures.peak_each_g(build))],
		["Throttle ceiling", "%d%% · pack" % roundi(build.max_throttle_fraction() * 100.0)]]
	return TestResult.new("page numbers: Motors shows this pack's peak and the throttle ceiling",
		got == want, "%s want %s" % [got, want])


static func _propellers_page_numbers(build: Build) -> TestResult:
	var got := SectionRows.page_numbers(&"propellers", build)
	var want := [["Hover throttle", "%d%%" % roundi(build.hover_throttle() * 100.0)],
		["Hover rpm", "%d rpm" % roundi(PropulsionFigures.hover_rpm(build))]]
	return TestResult.new("page numbers: Propellers shows hover throttle and hover rpm",
		got == want, "%s want %s" % [got, want])


static func _guards_page_numbers_fitted(guarded: Build) -> TestResult:
	var got := SectionRows.page_numbers(&"guards", guarded)
	var want := [["Added mass", "+%d g" % roundi(PropulsionFigures.guard_added_g(guarded))],
		["Roll inertia", "+%d%%" % roundi(PropulsionFigures.guard_roll_inertia_fraction(guarded) * 100.0)]]
	return TestResult.new("page numbers: Prop guards shows added mass and roll inertia when fitted",
		got == want, "%s want %s" % [got, want])


static func _guards_page_numbers_none(build: Build) -> TestResult:
	var got := SectionRows.page_numbers(&"guards", build)
	return TestResult.new("page numbers: with no guard fitted the page says so, no invented figure",
		got == [["Added mass", "none fitted"], ["Roll inertia", "—"]], str(got))
