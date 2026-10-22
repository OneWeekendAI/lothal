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
