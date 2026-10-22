class_name TestMountRow
extends RefCounted
## The soft mount as something a builder picks and a project keeps — SM3 and its persistence slice.
##
## SM2 made `Build.mount_id` reach `VibrationModel`, from `Build.from_ids` and from nowhere else: the
## state P10b's guard was in until P10f gave it a row. This file asserts the four links that make the
## mount real, each on the THING DOWNSTREAM rather than on the id, for `TestGuardRow`'s reason — an id
## that is carried, saved and reopened but never reaches the Build reads correctly at every step and
## changes no number:
##
##   1. The Lab's selection carries the mount, and the Lab's own build fits it.
##   2. A mount saved to a project comes back FITTED ON THE REBUILT BUILD, not merely in the parts block.
##   3. A project file written before the mount existed reopens with none fitted — the aircraft it was.
##   4. A mount id the catalog no longer knows is reported, and nothing is substituted for it.
##   5. Opening a saved drone (`apply_selection`) puts the mount back on the Lab's row.

const FIRM := "mount_grommet_70a_firm"
const SOFT := "mount_grommet_50a_soft"


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	results.append(_the_selection_carries_the_mount())
	results.append(_a_saved_mount_comes_back_on_the_rebuilt_build(catalog))
	results.append(_a_file_from_before_the_mount_reopens_with_none(catalog))
	results.append(_a_mount_that_left_the_catalog_is_reported_not_substituted())
	results.append(_opening_a_saved_drone_puts_the_mount_back())
	# --- SM3: the sheet, the row, the dock halves
	results.append(_an_assumed_hardness_says_so(catalog))
	results.append(_a_read_hardness_carries_no_caveat(catalog))
	results.append(_the_damping_band_is_labelled_assumed(catalog))
	results.append(_the_sheets_frequency_is_the_vibration_models(catalog))
	results.append(_no_mount_reads_no_pad(catalog))
	results.append(_the_row_is_modelled_and_counted(catalog))
	results.append(_the_row_names_the_durometer(catalog))
	results.append(_the_mount_sheet_is_the_mount_alone(catalog))
	results.append(_the_motor_sheet_has_no_mount(catalog))
	# --- SM5: the mount's mass
	results.append(_a_fitted_mount_weighs_four_grommet_sets(catalog))
	results.append(_the_mount_sits_at_the_motors_with_no_local_tensor(catalog))
	results.append(_a_zero_thickness_mount_adds_exactly_nothing(catalog))
	results.append(_a_pad_with_no_mount_part_adds_exactly_nothing(catalog))
	results.append(_a_mount_does_not_leak_into_the_guards_mass(catalog))
	return results


static func _reference_project(name: String) -> Project:
	var project := Project.create(name)
	project.parts["frame"] = ReferenceBuild.FRAME_ID
	project.parts["motor"] = ReferenceBuild.MOTOR_ID
	project.parts["propeller"] = ReferenceBuild.PROPELLER_ID
	project.parts["battery"] = ReferenceBuild.BATTERY_ID
	project.parts["esc"] = ReferenceBuild.ESC_ID
	project.parts["flight_controller"] = ReferenceBuild.FC_ID
	return project


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

static func _the_selection_carries_the_mount() -> TestResult:
	var lab := LabScreen.new(PartsCatalog.load_default())
	lab.motor_details.select_mount(FIRM)
	var carried := String(lab.selection().get("mount", "<absent>"))
	var on_build := String(lab.current_build().mount.get("part_id", ""))
	lab.free()
	return TestResult.new(
		"LabScreen's selection carries the soft mount, and current_build() fits it",
		carried == FIRM and on_build == FIRM,
		"selection says \"%s\", the build fits \"%s\"" % [carried, on_build])


## Asserted on the rebuilt Build's mount AND its mount frequency: a `to_build` that left the id in the
## components block would write and read the file correctly and hand `from_ids` nothing.
static func _a_saved_mount_comes_back_on_the_rebuilt_build(catalog: PartsCatalog) -> TestResult:
	var project := _reference_project("mount round trip")
	project.parts["mount"] = SOFT
	var reopened := Project.from_dict(project.to_dict())
	var missing: Array = []
	var build := reopened.to_build(catalog, missing)
	var fitted := "" if build == null else String(build.mount.get("part_id", ""))
	var spec := VibrationModel.soft_mount_spec_for(build) if build != null else {}
	return TestResult.new(
		"a soft mount saved to a project comes back fitted on the rebuilt aircraft",
		fitted == SOFT and float(spec.get("shore_a", 0.0)) == 50.0 and missing.is_empty(),
		"rebuilt with \"%s\", spec Shore %s, missing %s" % [fitted, spec.get("shore_a"), missing])


## A file whose parts block has never heard of `mount`, read back as the aircraft it was saved as.
static func _a_file_from_before_the_mount_reopens_with_none(catalog: PartsCatalog) -> TestResult:
	var today := _reference_project("before mounts")
	var written := today.to_dict()
	var parts: Dictionary = (written["decisions"] as Dictionary)["parts"]
	parts.erase("mount")
	var missing: Array = []
	var reopened := Project.from_dict(written)
	var build := reopened.to_build(catalog, missing)
	var ref_build := today.to_build(catalog, [])
	var same_mass := build != null and build.all_up_weight_g() == ref_build.all_up_weight_g()
	return TestResult.new(
		"a project file from before soft mounts reopens with no mount fitted, mass unchanged",
		build != null and build.mount.is_empty() and same_mass and missing.is_empty()
			and String(reopened.parts.get("mount", "<absent>")) == "",
		"mount %s, AUW %s vs %.4f, parts.mount \"%s\"" % [
			{} if build == null else build.mount, "-" if build == null else str(build.all_up_weight_g()),
			ref_build.all_up_weight_g(), reopened.parts.get("mount", "<absent>")])


static func _a_mount_that_left_the_catalog_is_reported_not_substituted() -> TestResult:
	var lab := LabScreen.new(PartsCatalog.load_default())
	lab.motor_details.select_mount(FIRM)
	var failed := lab.apply_selection({"mount": "mount_that_was_deleted"})
	var still := lab.motor_details.mount_id()
	lab.free()
	var reported := false
	for entry in failed:
		if String(entry["category"]) == "mount" and String(entry["part_id"]) == "mount_that_was_deleted":
			reported = true
	return TestResult.new(
		"a mount id the catalog no longer knows is reported, and the row is left where it was",
		reported and still == FIRM,
		"reported=%s, row still fits \"%s\"" % [reported, still])


static func _opening_a_saved_drone_puts_the_mount_back() -> TestResult:
	var lab := LabScreen.new(PartsCatalog.load_default())
	var failed := lab.apply_selection({"mount": SOFT})
	var row := lab.motor_details.mount_id()
	var on_build := String(lab.current_build().mount.get("part_id", ""))
	lab.free()
	return TestResult.new(
		"apply_selection fits a saved mount on the Lab's row and its build",
		failed.is_empty() and row == SOFT and on_build == SOFT,
		"failed %s, row \"%s\", build \"%s\"" % [failed, row, on_build])


# ---------------------------------------------------------------------------
# SM3 — the sheet, the row and the dock halves
# ---------------------------------------------------------------------------

## The reference build with a mount fitted and the Lab's tweaks resolved on it, as the Lab builds it:
## the pad defaults to the part's own thickness (SM2), so the mount is a pad that exists.
static func _fitted(catalog: PartsCatalog, mount_id: String) -> Build:
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, {}, null, "", {}, mount_id)
	build.set_assembly(AssemblyTweaks.new().resolved_m(build))
	return build


static func _an_assumed_hardness_says_so(catalog: PartsCatalog) -> TestResult:
	var text := MotorDetails.mount_row_text("hardness", catalog.get_part(FIRM), null)
	return TestResult.new("mount sheet: a guessed Shore value carries (assumed) on the number",
		text == "Shore 70A (assumed)", text)


## The 60A entry's durometer is the one field it READ (its `assumed` list omits shore_a).
static func _a_read_hardness_carries_no_caveat(catalog: PartsCatalog) -> TestResult:
	var text := MotorDetails.mount_row_text("hardness", catalog.get_part("mount_grommet_60a"), null)
	return TestResult.new("mount sheet: a Shore value the entry read is shown bare",
		text == "Shore 60A", text)


static func _the_damping_band_is_labelled_assumed(catalog: PartsCatalog) -> TestResult:
	var text := MotorDetails.mount_row_text("damping", catalog.get_part(FIRM), null)
	return TestResult.new("mount sheet: the damping is the overlay's band, labelled assumed",
		text == "ζ 0.05–0.15 (assumed)", text)


static func _the_sheets_frequency_is_the_vibration_models(catalog: PartsCatalog) -> TestResult:
	var build := _fitted(catalog, SOFT)
	var want := "~%d Hz" % roundi(VibrationModel.for_build(build).mount_hz())
	var text := MotorDetails.mount_row_text("f_n", catalog.get_part(SOFT), build)
	return TestResult.new("mount sheet: f_n is VibrationModel's for the same build, with its ~",
		text == want and is_finite(VibrationModel.for_build(build).mount_hz()), "%s vs %s" % [text, want])


static func _no_mount_reads_no_pad(catalog: PartsCatalog) -> TestResult:
	var build := _fitted(catalog, "")
	var text := MotorDetails.mount_row_text("f_n", {}, build)
	var hardness := MotorDetails.mount_row_text("hardness", {}, build)
	return TestResult.new("mount sheet: with nothing fitted the pad reads 'no pad' and no Shore value",
		text == "no pad" and hardness == "—", "%s / %s" % [text, hardness])


static func _the_row_is_modelled_and_counted(catalog: PartsCatalog) -> TestResult:
	var rows := SectionRows.rows("Propulsion", _fitted(catalog, FIRM))
	var row: Dictionary = {}
	for candidate in rows:
		if candidate["id"] == &"soft_mounts":
			row = candidate
	var counted := SectionRows.count(rows)
	return TestResult.new("propulsion rows: Soft mounts has a page and a status dot, and counts in N of M",
		str(row.get("status", "")) == SectionRows.OK and counted.y == 4
			and str((row.get("page", {}) as Dictionary).get("diagram", "")) == "mount",
		"status %s, count %s, page %s" % [row.get("status"), counted, row.get("page")])


static func _the_row_names_the_durometer(catalog: PartsCatalog) -> TestResult:
	var build := _fitted(catalog, FIRM)
	var choice := SectionRows.choice_of(&"soft_mounts", build, {})
	var number := SectionRows.number_of(&"soft_mounts", build, {})
	var want := "~%d Hz mount" % roundi(VibrationModel.for_build(build).mount_hz())
	return TestResult.new("propulsion rows: Soft mounts says the durometer and the mount frequency",
		choice == "70A silicone" and number == want, "%s / %s want %s" % [choice, number, want])


static func _the_mount_sheet_is_the_mount_alone(catalog: PartsCatalog) -> TestResult:
	var panel := MotorDetails.new(catalog)
	panel.render(catalog.get_part(ReferenceBuild.MOTOR_ID), ReferenceBuild.build())
	panel.set_dock_sheet("mount")
	var parts := panel.sheet_parts()
	var title := panel.shown_title()
	panel.free()
	return TestResult.new("motor sheet: the Soft mounts page shows the mount and not the motor's rows",
		parts["mount"] and not parts["rows"] and not parts["bench"] and title == "SOFT MOUNT",
		"%s, title %s" % [parts, title])


static func _the_motor_sheet_has_no_mount(catalog: PartsCatalog) -> TestResult:
	var panel := MotorDetails.new(catalog)
	panel.render(catalog.get_part(ReferenceBuild.MOTOR_ID), ReferenceBuild.build())
	panel.set_dock_sheet("motor")
	var parts := panel.sheet_parts()
	panel.free()
	return TestResult.new("motor sheet: the Motors page keeps its rows and doors, without the mount",
		parts["rows"] and parts["bench"] and not parts["mount"], str(parts))


# ---------------------------------------------------------------------------
# SM5 — the mount's own mass in Build.mass_parts()
# ---------------------------------------------------------------------------

## `_fitted` with the pad forced to `pad_m`, so a test can name the thickness it is about.
static func _at_pad(catalog: PartsCatalog, mount_id: String, pad_m: float, guard_id := "") -> Build:
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, {}, null, guard_id, {}, mount_id)
	var resolved := AssemblyTweaks.new().resolved_m(build)
	resolved["soft_mount_m"] = pad_m
	build.set_assembly(resolved)
	return build


static func _mount_parts(build: Build) -> Array:
	var out: Array = []
	for part in build.mass_parts():
		if (part as PartMass).label.begins_with("Soft mount"):
			out.append(part)
	return out


## Four sets, each `SoftMount.mount_mass_kg` at the pad in force — the same mass the frame mode adds.
static func _a_fitted_mount_weighs_four_grommet_sets(catalog: PartsCatalog) -> TestResult:
	var bare := _at_pad(catalog, "", 0.001)
	var mounted := _at_pad(catalog, FIRM, 0.001)
	var each_g := SoftMount.mount_mass_kg(0.001, SoftMount.spec_from_part(catalog.get_part(FIRM))) * 1000.0
	var added := mounted.all_up_weight_g() - bare.all_up_weight_g()
	return TestResult.new("SM5: a fitted 1.0 mm mount adds four grommet sets to the all-up weight",
		each_g > 0.0 and absf(added - 4.0 * each_g) < 1e-9,
		"added %.6f g, want 4 × %.6f g" % [added, each_g])


static func _the_mount_sits_at_the_motors_with_no_local_tensor(catalog: PartsCatalog) -> TestResult:
	var build := _at_pad(catalog, FIRM, 0.001)
	var parts := _mount_parts(build)
	var ok := parts.size() == MotorLayout.MOTOR_NAMES.size()
	for i in parts.size():
		var part := parts[i] as PartMass
		ok = ok and part.local_inertia_diag == Vector3.ZERO \
			and part.position_m == MotorLayout.motor_position(MotorLayout.MOTOR_NAMES[i], build.arm_m)
	return TestResult.new("SM5: one mount part per motor, at the motor, with Vector3.ZERO local inertia",
		ok, "%d parts" % parts.size())


static func _a_zero_thickness_mount_adds_exactly_nothing(catalog: PartsCatalog) -> TestResult:
	var bare := _at_pad(catalog, "", 0.0)
	var mounted := _at_pad(catalog, FIRM, 0.0)
	return TestResult.new("SM5: a fitted mount at zero thickness adds exactly 0 g and no part",
		mounted.all_up_weight_g() == bare.all_up_weight_g() and _mount_parts(mounted).is_empty(),
		"%.9f vs %.9f g" % [mounted.all_up_weight_g(), bare.all_up_weight_g()])


## The Lab's pad with no part picked: the vibration model still runs the class-typical grommet, but
## nothing was chosen, so nothing is weighed.
static func _a_pad_with_no_mount_part_adds_exactly_nothing(catalog: PartsCatalog) -> TestResult:
	var padded := _at_pad(catalog, "", 0.002)
	var flat := _at_pad(catalog, "", 0.0)
	return TestResult.new("SM5: an unfitted pad adds exactly 0 g, whatever its thickness",
		padded.all_up_weight_g() == flat.all_up_weight_g() and _mount_parts(padded).is_empty(),
		"%.9f vs %.9f g" % [padded.all_up_weight_g(), flat.all_up_weight_g()])


## `PropulsionFigures.guard_roll_inertia_fraction` is a twin difference (`without_guard`); a twin
## that dropped the mount would hand the mount's m·d² to the guard's roll-inertia bite.
static func _a_mount_does_not_leak_into_the_guards_mass(catalog: PartsCatalog) -> TestResult:
	var both := _at_pad(catalog, FIRM, 0.001, "guard_bumper_5in_abs")
	var mount_only := _at_pad(catalog, FIRM, 0.001)
	var bare := mount_only.mass_properties.inertia.z.z
	var want := (both.mass_properties.inertia.z.z - bare) / bare
	var got := PropulsionFigures.guard_roll_inertia_fraction(both)
	return TestResult.new("SM5: the guard's roll-inertia share is measured against a twin that keeps the mount",
		got == want and got > 0.0, "%.12f vs %.12f" % [got, want])
