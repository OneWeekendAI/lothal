class_name TestProject
extends RefCounted
## The project document: what a saved drone contains, and — the reason most of this file exists —
## what happens to it when the format changes underneath it.
##
## ---------------------------------------------------------------------------
## THE CHECKS THAT COULD HAVE PASSED WHILE PROVING NOTHING
## ---------------------------------------------------------------------------
##
## **1. "A new part category does not fit itself."** The obvious version asserts that an absent
## category reads as "". That passes against a loader which reads every category as "" — including
## the ones the file actually named. So the check here loads ONE document containing three states
## at once (a category fitted, a category explicitly refused, and a category the writer had never
## heard of) and asserts all three, then asserts the aircraft's MASS to the gram in each case.
## A loader that flattened them would move a number this project has held fixed for months.
##
## **2. "Unknown fields survive."** The obvious version round-trips a Dictionary in memory, which
## passes against a to_dict() that hands back the very object from_dict() was given. Everything
## here goes through JSON.stringify and back, and the unknown fields are planted at four different
## depths — top level, inside `decisions`, inside `decisions.parts` as an unrecognised CATEGORY,
## and inside a sparse block. Three of those four are separate code paths.
##
## **3. "The migration ladder works."** There are no migrations, so any test of the real ladder
## passes against a migrate() that ignores its arguments and returns them. The ladder is therefore
## injected: synthetic rungs that stamp their name into the document, so ordering, the stopping
## condition and "already current does nothing" each fail loudly if the ladder is a no-op.
##
## **4. "The atomic write is atomic."** Asserting that a file exists after a write passes for a
## plain overwrite. So a write is made to FAIL mid-flight — by parking a directory where the
## temporary file needs to go — and the check is that the ORIGINAL DOCUMENT IS STILL THERE AND
## STILL CORRECT. A naive implementation truncates on open and loses it, which is the whole bug
## the function exists to prevent.

const TEST_DIR := "user://test_project"
const TEST_PATH := TEST_DIR + "/doc.json"

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_test_a_round_trip_survives_json(catalog))
	results.append_array(_test_a_new_category_fits_nothing(catalog))
	results.append_array(_test_unknown_fields_survive_at_every_depth())
	results.append_array(_test_a_later_major_is_refused_and_a_later_minor_is_not())
	results.append_array(_test_the_migration_ladder_runs_in_order())
	results.append_array(_test_missing_parts_are_named_not_substituted(catalog))
	results.append_array(_test_a_version_restores_parts_but_not_the_name())
	results.append_array(_test_an_atomic_write_cannot_lose_the_previous_file())

	return results


# ---------------------------------------------------------------------------

static func _reference_project() -> Project:
	var project := Project.create("Reference")
	project.parts["frame"] = ReferenceBuild.FRAME_ID
	project.parts["motor"] = ReferenceBuild.MOTOR_ID
	project.parts["propeller"] = ReferenceBuild.PROPELLER_ID
	project.parts["battery"] = ReferenceBuild.BATTERY_ID
	project.parts["esc"] = ReferenceBuild.ESC_ID
	project.parts["flight_controller"] = ReferenceBuild.FC_ID
	# `Build.OPTIONAL_COMPONENTS` and NOT `ProjectSchema.OPTIONAL_CATEGORIES`, and the difference
	# is not cosmetic — it is what P10f's guard exposed. The schema's optional list is "categories
	# a project file may leave off" and the Build's is "the payload the mass model weighs from a
	# dictionary"; the guard is in the first and not the second, because it reaches `Build` as a
	# trailing argument rather than through `component_ids`. This loop wants the four bays with
	# defaults, so it reads the list that HAS defaults.
	for category in Build.OPTIONAL_COMPONENTS:
		project.parts[category] = String(Build.DEFAULT_COMPONENT_IDS[category])
	return project


static func _through_json(project: Project) -> Project:
	return Project.from_dict(JSON.parse_string(JSON.stringify(project.to_dict())))


static func _test_a_round_trip_survives_json(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var project := _reference_project()
	project.assembly["plate_gap_mm"] = 7.5
	project.tune["roll"] = {"p": 48.0, "i": 62.0, "d": 34.0}
	project.air["elevation_m"] = 540.0
	project.printing["fit_clearance_mm"] = 0.2

	var reloaded := _through_json(project)
	results.append(TestResult.new(
		"a project survives being written and read as JSON",
		reloaded != null and reloaded.project_id == project.project_id
			and reloaded.name == "Reference"
			and is_equal_approx(float(reloaded.assembly["plate_gap_mm"]), 7.5)
			and is_equal_approx(float((reloaded.tune["roll"] as Dictionary)["d"]), 34.0)
			and is_equal_approx(float(reloaded.air["elevation_m"]), 540.0)
			and is_equal_approx(float(reloaded.printing["fit_clearance_mm"]), 0.2),
		"reloaded id %s" % ("(null)" if reloaded == null else reloaded.project_id)
	))

	# The oracle: this project IS the reference build, so it has to weigh what the reference build
	# has weighed since before projects existed. A document that lost or reordered a part id
	# cannot hit 496.0 g by accident.
	var build := reloaded.to_build(catalog)
	results.append(TestResult.new(
		"the reloaded document builds the reference aircraft, to the gram",
		build != null and absf(build.all_up_weight_g() - 507.48) < 0.05,
		"%.2f g" % (0.0 if build == null else build.all_up_weight_g())
	))
	return results


static func _test_a_new_category_fits_nothing(catalog: PartsCatalog) -> Array:
	var results: Array = []

	# One document, three states. `camera` is fitted, `vtx` is explicitly refused, and `antenna`
	# is simply absent — which is exactly the shape of a file written before a category existed.
	var document := _reference_project().to_dict()
	var parts: Dictionary = (document["decisions"] as Dictionary)["parts"]
	parts["vtx"] = ""
	parts.erase("antenna")

	var project := Project.from_dict(JSON.parse_string(JSON.stringify(document)))
	results.append(TestResult.new(
		"fitted, refused and never-heard-of are three different answers",
		project != null
			and String(project.parts["camera"]) == Build.DEFAULT_COMPONENT_IDS["camera"]
			and String(project.parts["vtx"]) == ""
			and String(project.parts["antenna"]) == "",
		"camera=%s vtx=%s antenna=%s" % [project.parts.get("camera"),
			project.parts.get("vtx"), project.parts.get("antenna")]
	))

	# And the consequence in grams, which is what the rule is actually protecting. An absent
	# category must weigh the same as a refused one — if absence meant "fit the default", every
	# project a builder already owns would gain a part the day a category is introduced.
	var absent_build := project.to_build(catalog)

	var refused_document := _reference_project().to_dict()
	var refused_parts: Dictionary = (refused_document["decisions"] as Dictionary)["parts"]
	refused_parts["vtx"] = ""
	refused_parts["antenna"] = ""
	var refused_build := Project.from_dict(refused_document).to_build(catalog)

	var fitted_build := _reference_project().to_build(catalog)

	results.append(TestResult.new(
		"an absent category weighs exactly what a refused one weighs",
		absent_build != null and refused_build != null
			and absf(absent_build.all_up_weight_g() - refused_build.all_up_weight_g()) < 0.001,
		"absent %.2f g vs refused %.2f g" % [absent_build.all_up_weight_g(),
			refused_build.all_up_weight_g()]
	))
	results.append(TestResult.new(
		"and it is genuinely lighter than the same build with those two fitted",
		fitted_build != null
			and fitted_build.all_up_weight_g() - absent_build.all_up_weight_g()
				> Build.VTX_BUDGET_MASS_G + Build.ANTENNA_BUDGET_MASS_G - 0.001,
		"fitted %.2f g vs absent %.2f g" % [fitted_build.all_up_weight_g(),
			absent_build.all_up_weight_g()]
	))
	return results


static func _test_unknown_fields_survive_at_every_depth() -> Array:
	var document := _reference_project().to_dict()
	document["wiring"] = {"connector": "xt60"}
	(document["decisions"] as Dictionary)["harness"] = {"gauge_awg": 18}
	((document["decisions"] as Dictionary)["parts"] as Dictionary)["gps"] = "gps_m10"
	((document["decisions"] as Dictionary)["assembly"] as Dictionary)["duct_gap_mm"] = 0.8

	var round_tripped := _through_json(Project.from_dict(
		JSON.parse_string(JSON.stringify(document))))
	var out := round_tripped.to_dict()
	var decisions: Dictionary = out["decisions"]

	return [TestResult.new(
		"a field this version has never heard of survives at all four depths",
		String((out.get("wiring", {}) as Dictionary).get("connector", "")) == "xt60"
			and int((decisions.get("harness", {}) as Dictionary).get("gauge_awg", 0)) == 18
			and String((decisions["parts"] as Dictionary).get("gps", "")) == "gps_m10"
			and is_equal_approx(
				float((decisions["assembly"] as Dictionary).get("duct_gap_mm", 0.0)), 0.8),
		"top=%s decisions=%s parts.gps=%s assembly=%s" % [out.has("wiring"),
			decisions.has("harness"), (decisions["parts"] as Dictionary).get("gps"),
			(decisions["assembly"] as Dictionary).get("duct_gap_mm")]
	)]


static func _test_a_later_major_is_refused_and_a_later_minor_is_not() -> Array:
	var results: Array = []

	var future_major := _reference_project().to_dict()
	future_major["schema"] = {"major": ProjectSchema.SCHEMA_MAJOR + 1, "minor": 0}
	results.append(TestResult.new(
		"a document whose meanings have changed is refused, not guessed at",
		Project.from_dict(future_major) == null,
		"major %d" % (ProjectSchema.SCHEMA_MAJOR + 1)
	))

	var future_minor := _reference_project().to_dict()
	future_minor["schema"] = {"major": ProjectSchema.SCHEMA_MAJOR,
		"minor": ProjectSchema.SCHEMA_MINOR + 9}
	future_minor["telemetry"] = {"kept": true}
	var opened := Project.from_dict(future_minor)
	results.append(TestResult.new(
		"a document with fields merely ADDED still opens, and keeps them",
		opened != null and bool((opened.to_dict().get("telemetry", {}) as Dictionary).get("kept", false)),
		"opened=%s" % (opened != null)
	))

	# The int form every other user:// document in Lothal writes.
	var old_style := _reference_project().to_dict()
	old_style["schema"] = 1
	results.append(TestResult.new(
		"a bare integer schema is read as that major, minor 0",
		Project.from_dict(old_style) != null
			and int(ProjectSchema.read_version(1)["major"]) == 1
			and int(ProjectSchema.read_version(1)["minor"]) == 0,
		"read_version(1) = %s" % ProjectSchema.read_version(1)
	))
	return results


static func _test_the_migration_ladder_runs_in_order() -> Array:
	var results: Array = []

	# Synthetic rungs. The real ladder is empty, so driving it would prove nothing at all.
	var ladder: Array = [
		{"from_major": 1, "apply": func(d: Dictionary) -> Dictionary:
			d["trail"] = String(d.get("trail", "")) + "a"; return d},
		{"from_major": 2, "apply": func(d: Dictionary) -> Dictionary:
			d["trail"] = String(d.get("trail", "")) + "b"; return d},
		{"from_major": 3, "apply": func(d: Dictionary) -> Dictionary:
			d["trail"] = String(d.get("trail", "")) + "c"; return d},
	]

	var from_one := ProjectSchema.migrate({}, {"major": 1}, ladder)
	results.append(TestResult.new(
		"every rung above the file's version runs, in order",
		String(from_one.get("trail", "")) == "abc",
		"trail '%s'" % from_one.get("trail", "")
	))

	var from_three := ProjectSchema.migrate({}, {"major": 3}, ladder)
	results.append(TestResult.new(
		"and the rungs below it do not",
		String(from_three.get("trail", "")) == "c",
		"trail '%s'" % from_three.get("trail", "")
	))

	var current := ProjectSchema.migrate({"untouched": true}, {"major": 4}, ladder)
	results.append(TestResult.new(
		"a document already at the top of the ladder is not touched",
		not current.has("trail") and bool(current.get("untouched", false)),
		"keys %s" % [current.keys()]
	))
	return results


static func _test_missing_parts_are_named_not_substituted(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var project := _reference_project()
	project.parts["motor"] = "motor_that_was_deleted"
	var missing: Array = []
	var build := project.to_build(catalog, missing)

	results.append(TestResult.new(
		"a part that has gone is reported by name, and no aircraft is invented",
		build == null and missing.size() == 1
			and String((missing[0] as Dictionary)["category"]) == "motor"
			and String((missing[0] as Dictionary)["part_id"]) == "motor_that_was_deleted",
		"missing %s" % [missing]
	))

	var optional := _reference_project()
	optional.parts["camera"] = "cam_that_was_deleted"
	var optional_missing: Array = []
	optional.to_build(catalog, optional_missing)
	results.append(TestResult.new(
		"an optional part that has gone is reported too, rather than quietly dropped",
		optional_missing.size() == 1
			and String((optional_missing[0] as Dictionary)["category"]) == "camera",
		"missing %s" % [optional_missing]
	))
	return results


static func _test_a_version_restores_parts_but_not_the_name() -> Array:
	var project := _reference_project()
	project.assembly["plate_gap_mm"] = 6.0
	var entry := project.add_version("before the 6S swap")

	project.name = "Renamed since"
	project.parts["battery"] = "battery_4s_1300"
	project.assembly["plate_gap_mm"] = 12.0

	var restored := project.restore_version(String(entry["version_id"]))
	return [TestResult.new(
		"restoring a version gives back the decisions and leaves the name alone",
		restored
			and String(project.parts["battery"]) == ReferenceBuild.BATTERY_ID
			and is_equal_approx(float(project.assembly["plate_gap_mm"]), 6.0)
			and project.name == "Renamed since",
		"battery=%s gap=%s name=%s" % [project.parts["battery"],
			project.assembly["plate_gap_mm"], project.name]
	)]


static func _test_an_atomic_write_cannot_lose_the_previous_file() -> Array:
	var results: Array = []
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))

	var first := {"schema": 1, "keep": "the original"}
	JsonStore.write_document_atomic(TEST_PATH, first)
	results.append(TestResult.new(
		"an atomic write puts the document where it says it does",
		String(JsonStore.read_document(TEST_PATH).get("keep", "")) == "the original",
		"read back %s" % JsonStore.read_document(TEST_PATH)
	))
	results.append(TestResult.new(
		"and leaves no temporary behind",
		not FileAccess.file_exists(TEST_PATH + ".tmp"),
		"tmp exists = %s" % FileAccess.file_exists(TEST_PATH + ".tmp")
	))

	# Failure injection: a DIRECTORY where the temporary file has to go. The write cannot
	# complete, and the question this whole function exists to answer is what happened to the
	# document that was already there. An in-place write would have truncated it on open.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_PATH + ".tmp"))
	var wrote := JsonStore.write_document_atomic(TEST_PATH, {"schema": 1, "keep": "the new one"})
	results.append(TestResult.new(
		"a write that cannot complete says so",
		not wrote,
		"write_document_atomic returned %s" % wrote
	))
	results.append(TestResult.new(
		"and the previous document is still there, and still whole",
		String(JsonStore.read_document(TEST_PATH).get("keep", "")) == "the original",
		"read back %s" % JsonStore.read_document(TEST_PATH)
	))

	_clean()
	return results


static func _clean() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_DIR)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	DirAccess.remove_absolute(absolute.path_join("doc.json"))
	DirAccess.remove_absolute(absolute.path_join("doc.json.tmp"))
	DirAccess.remove_absolute(absolute)
