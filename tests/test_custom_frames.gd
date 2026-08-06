class_name TestCustomFrames
extends RefCounted
## Builder-entered frames (LTHL-21). Two things this suite exists to prevent, above everything
## else it checks: a custom frame silently becoming the reference build, and a half-written
## user:// document stopping Lab from opening.

const EPS := 0.05


static func run() -> Array:
	var results: Array = []
	results.append(_test_shipped_catalog_carries_no_custom_ids())
	results.append(_test_loader_refuses_a_custom_prefixed_entry())
	results.append(_test_reference_build_is_out_of_reach())
	results.append(_test_a_missing_document_is_no_custom_frames())
	results.append(_test_a_broken_document_is_no_custom_frames())
	results.append(_test_a_frame_without_an_arm_is_refused())
	results.append(_test_a_colliding_id_is_refused_and_the_catalog_survives())
	results.append(_test_unknown_fields_survive_a_round_trip())
	results.append(_test_a_custom_size_class_lands_in_the_catalogs_own_bucket())
	results.append(_test_a_custom_frame_does_not_move_the_reference_build())
	results.append(_test_a_custom_frame_is_selectable_and_flyable())
	results.append(_test_camera_distance_accounts_for_a_bigger_custom_frame())
	return results


## Catalog hygiene, not a loader test: this only shows that nothing in data/parts/ currently
## HAPPENS to use the reserved prefix, which is true whether or not the loader would refuse one.
## The loader's actual refusal is exercised by _test_loader_refuses_a_custom_prefixed_entry below,
## against a fixture built to contain the collision this file cannot.
static func _test_shipped_catalog_carries_no_custom_ids() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var offenders: Array[String] = []
	for part_id in catalog.by_id:
		if PartsCatalog.is_custom(part_id):
			offenders.append(str(part_id))
	return TestResult.new(
		"no shipped part claims the reserved custom_ prefix",
		offenders.is_empty() and catalog.is_valid(),
		"%d parts loaded, %d reserved-prefix offenders %s" % [
			catalog.by_id.size(), offenders.size(), offenders])


## Drives _load_category directly against a fixture holding one ordinary frame and one
## custom_-prefixed impostor, because CATEGORY_FILES has no such collision to offer. Checks all
## three of: the impostor is refused (absent from by_id), the refusal is surgical rather than a
## file-level abort (the ordinary entry beside it still loads), and the refusal is reported
## (load_errors names the offending id) rather than merely silent.
static func _test_loader_refuses_a_custom_prefixed_entry() -> TestResult:
	var catalog := PartsCatalog.new()
	catalog._load_category("frame", "res://tests/fixtures/frames_with_custom_id.json")
	var impostor_rejected := not catalog.by_id.has("custom_impostor")
	var ordinary_loaded := catalog.by_id.has("frame_fixture_ordinary")
	var error_named := false
	for error in catalog.load_errors:
		if error.contains("custom_impostor"):
			error_named = true
	return TestResult.new(
		"_load_category refuses a custom_-prefixed entry without dropping its neighbours",
		impostor_rejected and ordinary_loaded and error_named,
		"impostor rejected: %s, ordinary loaded: %s, error named it: %s (load_errors: %s)" % [
			impostor_rejected, ordinary_loaded, error_named, catalog.load_errors])


## The 496 g / 11.69 / 29.6% oracle, asserted here as well as in the day-2 tests, because THIS is
## the suite that would notice it moving for a custom-frames reason.
static func _test_reference_build_is_out_of_reach() -> TestResult:
	var build := ReferenceBuild.build()
	var auw := build.all_up_weight_g()
	var twr := build.thrust_to_weight()
	var hover := build.hover_throttle()
	var ok := absf(auw - 496.0) < EPS and absf(twr - 11.69) < 0.01 and absf(hover - 0.296) < 0.001
	return TestResult.new(
		"the reference build is 496 g / 11.69 : 1 / 29.6% hover",
		ok, "AUW %.2f g, TWR %.2f, hover %.1f%%" % [auw, twr, hover * 100.0])


## A path nothing else in the suite writes, wiped before and after so a leftover from a crashed
## run cannot make a later run pass or fail for the wrong reason.
static func _scratch(suffix: String) -> String:
	var path := "user://test_custom_frames_%s.json" % suffix
	_wipe(path)
	return path


static func _wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _write_raw(path: String, text: String) -> void:
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string(text)
	handle.close()


## A valid 350 mm record, used by several tests below. Built through make_record rather than
## hand-written, so a change to the record's shape cannot leave the tests asserting the old one.
static func _record_350() -> Dictionary:
	return CustomFrames.make_record(
		"Shed 350", 340.0, 350.0, 13.0, "25x25", "30.5x30.5", "carbon fibre",
		"measured on my kitchen scale, arms with a caliper")


static func _test_a_missing_document_is_no_custom_frames() -> TestResult:
	var path := _scratch("missing")
	var doc := CustomFrames.load_from(path)
	var ok := doc.frames().is_empty() and doc.rejections().is_empty()
	_wipe(path)
	return TestResult.new(
		"no file at all is zero custom frames and zero complaints",
		ok, "%d frames, %d rejections" % [doc.frames().size(), doc.rejections().size()])


## The four shapes of broken, all landing in the same place: no custom frames, Lab opens, and the
## complaint is a WARNING. If any of these printed an engine ERROR line the runner's output would
## be indistinguishable from a failing test, which json_store.gd's second rule exists to prevent.
static func _test_a_broken_document_is_no_custom_frames() -> TestResult:
	var cases := {
		"truncated": "{\"schema\": 1, \"frames\": [",
		"not_an_object": "[1, 2, 3]",
		"frames_not_an_array": "{\"schema\": 1, \"frames\": {\"a\": 1}}",
		"entry_not_an_object": "{\"schema\": 1, \"frames\": [\"a frame, honest\"]}",
	}
	var failures: Array[String] = []
	for label in cases:
		var path := _scratch(label)
		_write_raw(path, cases[label])
		var doc := CustomFrames.load_from(path)
		if not doc.frames().is_empty():
			failures.append("%s produced %d frames" % [label, doc.frames().size()])
		_wipe(path)
	return TestResult.new(
		"every shape of broken document loads as no custom frames",
		failures.is_empty(), "4 cases, failures: %s" % [failures])


## arm_mm is the one field with no defensible fallback: FrameModel divides by it and MotorLayout
## puts the motors on it, so absent or zero is not a degraded frame, it is an undefined one.
static func _test_a_frame_without_an_arm_is_refused() -> TestResult:
	var cases := [
		{"label": "missing arm", "mutate": func(r: Dictionary) -> void: r["specs"].erase("arm_mm")},
		{"label": "zero arm", "mutate": func(r: Dictionary) -> void: r["specs"]["arm_mm"] = 0.0},
		{"label": "negative arm", "mutate": func(r: Dictionary) -> void: r["specs"]["arm_mm"] = -110.0},
		{"label": "negative mass", "mutate": func(r: Dictionary) -> void: r["mass_g"] = -1.0},
		{"label": "empty source", "mutate": func(r: Dictionary) -> void: r["source"] = ""},
	]
	var failures: Array[String] = []
	for case in cases:
		var doc := CustomFrames.new()
		var record := _record_350()
		(case["mutate"] as Callable).call(record)
		var rejections := doc.add(record)
		if rejections.is_empty() or not doc.frames().is_empty():
			failures.append(str(case["label"]))
	return TestResult.new(
		"a frame with no defined geometry, no mass or no provenance is refused",
		failures.is_empty(), "5 cases, accepted-when-it-should-not-have: %s" % [failures])


## The landmine, from the document's end. add() and load_from() must BOTH refuse, because a
## builder can hand-edit this file and the file is the thing that reaches the catalog.
static func _test_a_colliding_id_is_refused_and_the_catalog_survives() -> TestResult:
	var path := _scratch("collision")
	_write_raw(path, JSON.stringify({
		"schema": 1,
		"frames": [{
			"part_id": "frame_5in_freestyle",
			"name": "Not the reference build",
			"category": "frame",
			"mass_g": 999.0,
			"specs": {"arm_mm": 350.0, "max_prop_inches": 13.0,
				"motor_mount": "25x25", "stack_mount": "30.5x30.5"},
			"catalog": {"frame_type": "freestyle", "material": "carbon fibre", "size_class": "13in"},
			"source": "hand-edited to collide",
		}],
	}, "  "))

	var doc := CustomFrames.load_from(path)
	var refused := doc.frames().is_empty() and not doc.rejections().is_empty()

	var catalog := PartsCatalog.load_default()
	var reference_part: Dictionary = catalog.get_part("frame_5in_freestyle")
	var untouched := absf(float(reference_part["mass_g"]) - 110.0) < 0.001

	# Same refusal through the in-memory path, since the dialog never writes the file first.
	var direct := CustomFrames.new()
	var record := _record_350()
	record["part_id"] = "frame_5in_freestyle"
	var direct_refused := not direct.add(record).is_empty()

	_wipe(path)
	return TestResult.new(
		"an id that is not custom_-prefixed is refused, and the catalog entry is untouched",
		refused and untouched and direct_refused,
		"file refused=%s, direct refused=%s, catalog 5in freestyle still %.0f g" % [
			refused, direct_refused, float(reference_part["mass_g"])])


## json_store.gd's third rule, at both levels: a top-level block this version never heard of, and
## a field inside a frame record it never heard of. Both come back untouched.
static func _test_unknown_fields_survive_a_round_trip() -> TestResult:
	var path := _scratch("unknown")
	var doc := CustomFrames.new()
	var record := _record_350()
	record["future_field"] = {"wing_area_cm2": 42.0}
	doc.add(record)
	doc.save(path)

	# Splice a top-level block in, the way a later Lothal would have written one.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	raw["motors"] = [{"part_id": "custom_someday"}]
	_write_raw(path, JSON.stringify(raw, "  "))

	var reloaded := CustomFrames.load_from(path)
	reloaded.save(path)
	var final: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))

	var kept_top: bool = final.has("motors")
	var kept_field: bool = not final["frames"].is_empty() \
		and (final["frames"][0] as Dictionary).has("future_field")

	_wipe(path)
	return TestResult.new(
		"unknown top-level blocks and unknown record fields survive a save/load round trip",
		kept_top and kept_field, "top-level kept=%s, record field kept=%s" % [kept_top, kept_field])


## FramePicker's Size filter derives its options from the shipped catalog's own size_class
## strings (PartPicker._derive_options). A custom frame whose size_class is spelled differently —
## "5in" against the catalog's "5\"" — does not merely look inconsistent, it lands in a filter
## bucket of one that nothing else can ever join, which is the exact failure size_class_for()'s own
## doc comment claims not to happen. Derived rather than hardcoded against a literal like "5\"", so
## this keeps checking the real thing (agreement with the catalog) rather than one snapshot of it.
static func _test_a_custom_size_class_lands_in_the_catalogs_own_bucket() -> TestResult:
	var catalog_buckets: Dictionary = {}
	for frame in PartsCatalog.load_default().list_category("frame"):
		var bucket := str((frame as Dictionary).get("catalog", {}).get("size_class", ""))
		if bucket != "":
			catalog_buckets[bucket] = true

	var record := CustomFrames.make_record(
		"Shed 510", 340.0, 210.0, 5.1, "25x25", "30.5x30.5", "carbon fibre",
		"measured on my kitchen scale")
	var derived := str(record["catalog"]["size_class"])
	var ok := catalog_buckets.has(derived)

	return TestResult.new(
		"a custom frame's size_class matches a bucket the shipped catalog already uses",
		ok, "derived \"%s\", catalog buckets: %s" % [derived, catalog_buckets.keys()])


## THE test. Defining a custom frame — any custom frame, including an absurd one — must not move
## 496 g / 11.69 : 1 / 29.6% by a gram or a point. Written with the file actually on disk at
## CustomFrames.SAVE_PATH, not at a scratch path, because the real hazard is the real path.
static func _test_a_custom_frame_does_not_move_the_reference_build() -> TestResult:
	var previous := ""
	if FileAccess.file_exists(CustomFrames.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomFrames.SAVE_PATH)

	var doc := CustomFrames.new()
	doc.add(CustomFrames.make_record("Reference Impostor", 9999.0, 350.0, 13.0,
		"25x25", "30.5x30.5", "carbon fibre", "invented to try to move the oracle"))
	doc.save(CustomFrames.SAVE_PATH)

	# The merged catalog really does have it — otherwise this test proves nothing about isolation,
	# only that nothing happened.
	var merged := PartsCatalog.load_with_custom()
	var merged_has_it: bool = not merged.get_part("custom_reference_impostor").is_empty()

	var build := ReferenceBuild.build()
	var auw := build.all_up_weight_g()
	var twr := build.thrust_to_weight()
	var hover := build.hover_throttle()
	var pinned := absf(auw - 496.0) < EPS and absf(twr - 11.69) < 0.01 and absf(hover - 0.296) < 0.001

	# And the shipped frame count is unchanged in load_default(), so nothing leaked sideways.
	var shipped_frames: int = PartsCatalog.load_default().list_category("frame").size()
	var merged_frames: int = merged.list_category("frame").size()

	_restore(CustomFrames.SAVE_PATH, previous)
	return TestResult.new(
		"a defined custom frame does not move the reference build's 496 g / 11.69 / 29.6%",
		merged_has_it and pinned and merged_frames == shipped_frames + 1,
		"merged sees it=%s, %d shipped vs %d merged frames, AUW %.2f g, TWR %.2f, hover %.1f%%" % [
			merged_has_it, shipped_frames, merged_frames, auw, twr, hover * 100.0])


## A custom frame is not a catalog entry that happens to load — it has to go all the way through
## Build.from_ids to a flyable aircraft, and its arm_mm has to reach both the drawn geometry and
## the mass model. The inertia half is isolated to the four motor/prop masses, whose parallel-axis
## contribution scales EXACTLY as radius squared when nothing else about them changes; the frame's
## own centre box grows too, which is real but would blur an exact ratio into a hand-wave.
static func _test_a_custom_frame_is_selectable_and_flyable() -> TestResult:
	var previous := ""
	if FileAccess.file_exists(CustomFrames.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomFrames.SAVE_PATH)

	var doc := CustomFrames.new()
	doc.add(CustomFrames.make_record("Shed 350", 340.0, 350.0, 13.0,
		"25x25", "30.5x30.5", "carbon fibre", "measured on my kitchen scale"))
	doc.save(CustomFrames.SAVE_PATH)
	var catalog := PartsCatalog.load_with_custom()

	var custom := Build.from_ids(catalog, "custom_shed_350", ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID)
	var reference_build := ReferenceBuild.build()

	# Geometry: the arms really are 350 mm long, measured off the generated pads.
	var model := FrameModel.new()
	model.rebuild(catalog.get_part("custom_shed_350"))
	var tip_m: float = (model.arm_tips[MotorLayout.MOTOR_NAMES[0]] as Node3D).position.length()
	var geometry_ok := absf(tip_m - 0.350) < 0.0005
	model.free()

	# Inertia: the parallel-axis ratio, on the terms that are purely parallel-axis.
	var ratio_expected := pow(350.0 / 110.0, 2.0)
	var ratio_actual := _motor_roll_inertia(custom) / _motor_roll_inertia(reference_build)
	var inertia_ok := absf(ratio_actual - ratio_expected) < ratio_expected * 0.01

	_restore(CustomFrames.SAVE_PATH, previous)
	return TestResult.new(
		"a 350 mm custom frame draws 350 mm arms and carries (350/110)^2 the motor roll inertia",
		geometry_ok and inertia_ok,
		"arm tip %.4f m (want 0.3500), motor roll inertia ratio %.3f (want %.3f)" % [
			tip_m, ratio_actual, ratio_expected])


## Roll inertia of the four motor+prop masses alone. Isolated by name because Build.mass_parts()
## labels them "Motor + prop <name>" (build.gd:270) — if that label changes this returns zero and
## the test fails loudly, which is the right failure. Roll is Z: test_mass_properties.gd's
## coordinate contract has the vertical/yaw axis as Y, and its own pitch-vs-roll assertion names
## X as pitch and Z as roll — confirmed by reading that file rather than assumed here.
static func _motor_roll_inertia(build: Build) -> float:
	var motor_parts: Array = []
	for part in build.mass_parts():
		if str(part.label).begins_with("Motor + prop"):
			motor_parts.append(part)
	if motor_parts.is_empty():
		return 0.0
	return MassProperties.compute(motor_parts).inertia.z.z


## Lab's camera distance is a CATALOG-WIDE constant, computed from the largest arm and then held
## for every frame so that switching frames does not zoom. A custom frame is selectable, so it
## belongs in that maximum — a 350 mm frame framed for a 215 mm catalog renders off the edge, and
## Lab deliberately has no way to zoom out at the time it happens.
static func _test_camera_distance_accounts_for_a_bigger_custom_frame() -> TestResult:
	var previous := ""
	if FileAccess.file_exists(CustomFrames.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomFrames.SAVE_PATH)

	var without := PartsCatalog.load_default()
	var largest_without := _largest_arm_m(without)

	var doc := CustomFrames.new()
	doc.add(CustomFrames.make_record("Shed 350", 340.0, 350.0, 13.0,
		"25x25", "30.5x30.5", "carbon fibre", "measured on my kitchen scale"))
	doc.save(CustomFrames.SAVE_PATH)
	var with := PartsCatalog.load_with_custom()
	var largest_with := _largest_arm_m(with)

	_restore(CustomFrames.SAVE_PATH, previous)
	return TestResult.new(
		"the largest arm Lab frames for includes a custom frame bigger than the catalog's biggest",
		absf(largest_without - 0.215) < 0.001 and absf(largest_with - 0.350) < 0.001,
		"largest arm %.3f m without the custom frame, %.3f m with it" % [
			largest_without, largest_with])


## The same expression LabScreen._camera_distance_m and FrameBenchScreen._camera_distance_m open
## with. Asserted against the CATALOG rather than by instantiating a screen, because what this test
## is about is which frames are in the set — the trigonometry either side of it is already covered
## by tests/test_lab.gd and is not what a custom frame can break.
static func _largest_arm_m(catalog: PartsCatalog) -> float:
	var largest := 0.0
	for frame in catalog.list_category("frame"):
		largest = maxf(largest, float(frame["specs"]["arm_mm"]) / 1000.0)
	return largest


## Puts back whatever was at a real user:// path before the test borrowed it, including putting
## back "nothing". A test that leaves a custom frame defined would silently change what every
## later suite in the same run is loading.
static func _restore(path: String, previous: String) -> void:
	if previous == "":
		_wipe(path)
		return
	_write_raw(path, previous)
