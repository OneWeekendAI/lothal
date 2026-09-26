class_name TestControlPersistence
extends RefCounted
## GPS AND BUZZER ACROSS A SAVE AND A REOPEN — control-room design §2.3, slice C5.
##
## The production change this slice needed is one line, and C4 already made it: `gps` and `buzzer`
## are in `ProjectSchema.OPTIONAL_CATEGORIES`, because C4's fourth coverage property was red for
## both until they were. What is left is the half that was always the substance — ASSERTING the
## schema's absent-means-not-fitted rule rather than trusting it.
##
## THE ROW THAT MATTERS IS THE SECOND ONE, and `project_schema.gd`'s own rule 2 wrote its
## specification a year before the category existed:
##
##   "a GPS category is added next month, and a file written today has no `gps` key. If absent
##    meant 'fit the default', every project a builder already owns silently gains a GPS receiver
##    and a few grams — the app would change their aircraft without being asked."
##
## That is this file's second check, finally run against a real document rather than left as prose.
##
## THE FIXTURE IS HAND-WRITTEN, and the plan is emphatic about why: **a fixture produced by
## today's writer cannot demonstrate what yesterday's writer produced.** `tests/test_project.gd`'s
## own new-category check builds its document from `_reference_project().to_dict()` and then
## `erase()`s a key — which is this version's writer with a hole punched in it, and which would go
## on passing even if the writer started emitting a key the reader then defaulted. The document
## below is typed out as a JSON string: it is what a pre-C2 Lothal actually wrote, `gps` and
## `buzzer` absent because that Lothal had never heard of them.

## A project document as Lothal wrote them BEFORE `gps` and `buzzer` existed — typed by hand, not
## generated. The parts block is dense over the categories that version knew and silent about the
## two it did not, which is the whole point: absence here is historical, not a deletion.
##
## IT IS ALSO SILENT ABOUT `antenna`, AND THAT IS LOAD-BEARING RATHER THAN INCIDENTAL. Asserting the
## absent-means-not-fitted rule on `gps` and `buzzer` ALONE cannot fail: design §3 gave neither a
## default, so a reader that fell back to `DEFAULT_COMPONENT_IDS` would still return "" for both and
## the check would stay green with the schema rule deleted. The property is guarded twice over, and
## a mutation can only ever remove one guard at a time. `antenna` has a default, so it is the
## category that actually holds the schema rule to account — and the mutation "an absent key means
## fit the default" reddens the row below only because it is here.
const PRE_EXISTENCE_DOCUMENT := """{
  "schema": {"major": 1, "minor": 0},
  "project_id": "prj_pre_c2_fixture",
  "name": "A build saved before the GPS existed",
  "created_at": "2026-08-01T10:00:00Z",
  "updated_at": "2026-08-01T10:00:00Z",
  "lothal_version": "0.9.0",
  "decisions": {
    "parts": {
      "frame": "frame_5in_freestyle",
      "motor": "motor_2207_1960kv",
      "propeller": "prop_5x43x3",
      "battery": "battery_4s_1500",
      "esc": "esc_4in1_45a_30x30",
      "flight_controller": "fc_f405_30x30",
      "camera": "cam_micro_analog",
      "vtx": "vtx_analog_400mw",
      "receiver": "rx_elrs_2400",
      "guard": ""
    }
  }
}"""


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_test_both_survive_a_round_trip(catalog))
	results.append_array(_test_a_file_written_before_they_existed_fits_neither(catalog))
	results.append_array(_test_refused_is_not_the_same_as_never_heard_of(catalog))
	results.append_array(_test_the_second_write_is_identical_to_the_first(catalog))
	results.append_array(_test_custom_gps_and_buzzer_travel_in_the_container())

	return results


## C7: a builder's OWN GPS and buzzer, fitted, must travel inside the `.lothal` file — a shared drone
## whose GPS id resolves in nobody else's catalog opens without its highest mass.
##
## VERIFIED RATHER THAN ASSUMED, and the verification found no production change was needed:
## `ProjectContainer._collect_custom_parts` walks the document's sibling arrays and the project's
## parts block without a category list, so `gps` and `buzzer` travel by the same code as a motor.
## These rows are what keeps that true. The unfitted half is not decoration: "copy the whole file"
## passes the fitted rows too.
##
## FAILS IF: `_collect_custom_parts` skips either category (a filter on project.parts, or on the
## document's array keys), or copies everything regardless of what is fitted.
## Scratch files under user://test_control_persistence/ only.
static func _test_custom_gps_and_buzzer_travel_in_the_container() -> Array:
	var results: Array = []
	var dir := "user://test_control_persistence"
	var custom_path := dir + "/custom_parts.json"
	var container_path := dir + "/custom." + ProjectContainer.EXTENSION
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for stale in [custom_path, container_path]:
		if FileAccess.file_exists(stale):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(stale))

	var gps := CustomGps.new()
	gps.add(CustomGps.make_record("Shed mast", 12.0, 22.0, 22.0, 7.0, 65.0, "GPS", true, "UBX", "scale"))
	gps.add(CustomGps.make_record("Shed spare", 5.0, 16.0, 16.0, 6.0, 0.0, "GPS", false, "UBX", "scale"))
	gps.save(custom_path)
	var buzzers := CustomBuzzers.load_from(custom_path)
	buzzers.add(CustomBuzzers.make_record("Shed finder", 3.0, 20.0, 15.0, 9.0, true, null, "scale"))
	buzzers.save(custom_path)

	var project := _fitted_project()
	project.parts["gps"] = CustomGps.id_for("Shed mast")
	project.parts["buzzer"] = CustomBuzzers.id_for("Shed finder")
	var wrote := ProjectContainer.make(project).write(container_path, custom_path)
	var reopened := ProjectContainer.open(container_path)
	var carried: Dictionary = reopened.custom_parts() if reopened != null else {}

	var gps_ids: Array = []
	for record in carried.get("gps", []):
		gps_ids.append(str(record["part_id"]))
	var buzzer_ids: Array = []
	for record in carried.get("buzzers", []):
		buzzer_ids.append(str(record["part_id"]))

	results.append(TestResult.new(
		"a fitted custom GPS travels inside the .lothal container, mast and all",
		wrote and gps_ids.has(CustomGps.id_for("Shed mast"))
			and float(((carried.get("gps", [{}]) as Array)[0] as Dictionary).get("specs", {}).get("mast_height_mm", -1.0)) == 65.0,
		"written=%s, gps carried=%s" % [wrote, gps_ids]))
	results.append(TestResult.new(
		"a fitted custom buzzer travels inside the .lothal container",
		wrote and buzzer_ids.has(CustomBuzzers.id_for("Shed finder")),
		"written=%s, buzzers carried=%s" % [wrote, buzzer_ids]))
	results.append(TestResult.new(
		"and a custom GPS this drone does not fit stays out of its file",
		wrote and not gps_ids.has(CustomGps.id_for("Shed spare")) and gps_ids.size() == 1,
		"gps carried=%s" % [gps_ids]))

	for stale in [custom_path, container_path]:
		if FileAccess.file_exists(stale):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(stale))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	return results


## A project the builder really did fit a GPS and a buzzer to, through JSON and back.
##
## By ID rather than by "is something fitted", because the failure this catches is a category that
## persists as a boolean or as the default rather than as the part that was chosen — the masted
## module coming back as the flat one would satisfy any weaker assertion.
static func _test_both_survive_a_round_trip(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var project := _fitted_project()
	var reopened := Project.from_dict(JSON.parse_string(JSON.stringify(project.to_dict())))

	for category in Build.added_components():
		var wanted := String(project.parts.get(category, ""))
		var got := "" if reopened == null else String(reopened.parts.get(category, ""))
		results.append(TestResult.new(
			"a %s saved by id reopens as that same id" % category,
			reopened != null and got == wanted and wanted != "",
			"saved \"%s\", reopened \"%s\"" % [wanted, got]))

	# And it has to be the same AIRCRAFT, not merely the same strings: a part id that survives the
	# document and is dropped on the way to Build is the same defect one layer down.
	var build: Build = null
	if reopened != null:
		build = reopened.to_build(catalog)
	var fitted: Array[String] = []
	if build != null:
		for category in Build.added_components():
			if build.components.has(category):
				fitted.append(String(category))
	results.append(TestResult.new(
		"and the reopened document builds an aircraft carrying both of them",
		build != null and fitted.size() == Build.added_components().size(),
		"built %s, carrying %s" % ["a build" if build != null else "nothing", str(fitted)]))

	return results


## THE CHECK THIS SLICE EXISTS FOR. A document written before either category existed must reopen
## with neither fitted — not with the catalog default, which would add mass to an aircraft the
## builder never agreed to change.
##
## Asserted at both layers, because they can disagree: the parts block may say "" while `to_build`
## still hands `Build.from_ids` a default, and `from_ids` reads `DEFAULT_COMPONENT_IDS` for any
## category whose id it is not given. Design §3 is what makes the second half hold — neither added
## component HAS a default — so this check is also the last line of defence on that decision.
static func _test_a_file_written_before_they_existed_fits_neither(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var parsed = JSON.parse_string(PRE_EXISTENCE_DOCUMENT)
	var project: Project = null
	if parsed is Dictionary:
		project = Project.from_dict(parsed as Dictionary)

	results.append(TestResult.new(
		"the hand-written pre-existence document is readable at all",
		project != null,
		"parsed=%s, project=%s" % [parsed is Dictionary, project != null]))

	if project == null:
		return results

	# The fixture must really be silent about them, or every row below passes for the wrong reason.
	var block: Dictionary = ((parsed as Dictionary)["decisions"] as Dictionary)["parts"]
	results.append(TestResult.new(
		"and it really is silent about gps, buzzer and antenna, so this is not a vacuous check",
		not block.has("gps") and not block.has("buzzer") and not block.has("antenna"),
		"the fixture's parts block names %s" % [block.keys()]))

	# THE ROW THAT ACTUALLY HOLDS THE SCHEMA RULE TO ACCOUNT, for the reason the header gives: a
	# category with a default is the only kind whose absence a defaulting reader would fill in.
	results.append(TestResult.new(
		"an absent antenna reopens as not fitted, though a default for it exists",
		String(project.parts.get("antenna", "")) == ""
			and String(Build.DEFAULT_COMPONENT_IDS.get("antenna", "")) != "",
		"antenna reopened as \"%s\", its default being \"%s\"" % [
			project.parts.get("antenna", ""), Build.DEFAULT_COMPONENT_IDS.get("antenna", "")]))

	for category in Build.added_components():
		results.append(TestResult.new(
			"a file written before %s existed reopens with no %s fitted" % [category, category],
			String(project.parts.get(category, "")) == "",
			"reopened as \"%s\"" % String(project.parts.get(category, ""))))

	var build := project.to_build(catalog)
	var surprises: Array[String] = []
	for category in Build.added_components():
		if build != null and build.components.has(category):
			surprises.append("%s (%s)" % [category, build.components[category].get("name", "?")])

	results.append(TestResult.new(
		"and the aircraft it builds carries neither of them, so nobody's drone gained mass",
		build != null and surprises.is_empty(),
		"fitted by surprise: %s" % ["none" if surprises.is_empty() else ", ".join(surprises)]))

	return results


## "" and absent are two different answers and must stay two. The builder who explicitly said no to
## a buzzer and the builder whose Lothal had never heard of one look identical after loading — both
## come back "" — but they must arrive there by different routes, and the route matters the moment
## anything ever treats absence as "use the default".
static func _test_refused_is_not_the_same_as_never_heard_of(_catalog: PartsCatalog) -> Array:
	var results: Array = []

	var document := _fitted_project().to_dict()
	var parts: Dictionary = (document["decisions"] as Dictionary)["parts"]
	parts["gps"] = ""            # explicitly refused
	parts.erase("buzzer")        # never heard of
	# And a category that HAS a default, refused explicitly. Same reason the pre-existence fixture
	# goes silent about the antenna: "" is indistinguishable from the default for gps and buzzer,
	# because design §3 gave neither one, so neither can witness a reader that fills "" back in.
	parts["antenna"] = ""

	var reopened := Project.from_dict(JSON.parse_string(JSON.stringify(document)))

	results.append(TestResult.new(
		"a gps explicitly saved as \"\" reopens as not fitted, not as a default",
		reopened != null and String(reopened.parts.get("gps", "!")) == "",
		"reopened as \"%s\"" % [String(reopened.parts.get("gps", "!")) if reopened != null else "<unreadable>"]))

	results.append(TestResult.new(
		"an absent buzzer reopens as not fitted, by the same answer and a different route",
		reopened != null and String(reopened.parts.get("buzzer", "!")) == "",
		"reopened as \"%s\"" % [String(reopened.parts.get("buzzer", "!")) if reopened != null else "<unreadable>"]))

	results.append(TestResult.new(
		"an antenna refused with \"\" stays refused, though a default for it exists",
		reopened != null and String(reopened.parts.get("antenna", "!")) == ""
			and String(Build.DEFAULT_COMPONENT_IDS.get("antenna", "")) != "",
		"antenna reopened as \"%s\", its default being \"%s\"" % [
			"" if reopened == null else reopened.parts.get("antenna", "!"),
			Build.DEFAULT_COMPONENT_IDS.get("antenna", "")]))

	# The dense-write rule: whatever route it came in by, it goes out NAMED, so the next version to
	# open this file can tell "not fitted" from "never heard of" exactly as this one could.
	var written: Dictionary = (reopened.to_dict()["decisions"] as Dictionary)["parts"]
	results.append(TestResult.new(
		"and both are written back out densely, so the next version can still tell them apart",
		written.has("gps") and written.has("buzzer"),
		"written parts block names %s" % [written.keys()]))

	return results


## Write, read, write. The second document must equal the first exactly — a category that is read
## but not written, or written under a different spelling, shows up here and nowhere else.
static func _test_the_second_write_is_identical_to_the_first(_catalog: PartsCatalog) -> Array:
	var results: Array = []

	var first := _fitted_project().to_dict()
	var second := Project.from_dict(JSON.parse_string(JSON.stringify(first))).to_dict()

	# `updated_at` is the one field a reopen is allowed to move; compare the parts block, which is
	# what this slice changed, rather than the whole document.
	var a: Dictionary = (first["decisions"] as Dictionary)["parts"]
	var b: Dictionary = (second["decisions"] as Dictionary)["parts"]

	results.append(TestResult.new(
		"round-tripping a build with both fitted writes the same parts block the second time",
		JSON.stringify(a, "", true, true) == JSON.stringify(b, "", true, true),
		"first %s, second %s" % [JSON.stringify(a), JSON.stringify(b)]))

	for category in Build.added_components():
		results.append(TestResult.new(
			"and %s is in the second write, spelled as it was in the first" % category,
			b.has(category) and String(a.get(category, "")) == String(b.get(category, "!")),
			"first \"%s\", second \"%s\"" % [a.get(category, ""), b.get(category, "<absent>")]))

	return results


## The reference project with a GPS and a buzzer really fitted. The masted GPS on purpose: it is
## the entry whose `mast_height_mm` is non-zero, so a round trip that quietly swapped it for the
## flat module would change the aircraft's centre of mass and not merely its part id.
## `Project.create` and the ids by hand rather than `ProjectLibrary.starting_project()`, which is
## the house pattern in `tests/test_project.gd` and is not a style preference: `starting_project`
## names an unnamed build by scanning the builds folder AND the trash on disk, so a test that used
## it would reach into real `user://` state to answer a question about a dictionary.
static func _fitted_project() -> Project:
	var project := Project.create("C5 fixture")
	project.parts["frame"] = ReferenceBuild.FRAME_ID
	project.parts["motor"] = ReferenceBuild.MOTOR_ID
	project.parts["propeller"] = ReferenceBuild.PROPELLER_ID
	project.parts["battery"] = ReferenceBuild.BATTERY_ID
	project.parts["esc"] = ReferenceBuild.ESC_ID
	project.parts["flight_controller"] = ReferenceBuild.FC_ID
	for category in Build.carved_components():
		project.parts[category] = String(Build.DEFAULT_COMPONENT_IDS[category])
	project.parts["gps"] = "gps_masted_long_range"
	project.parts["buzzer"] = "buzz_selfpowered_cell"
	return project
