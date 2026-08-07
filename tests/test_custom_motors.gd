class_name TestCustomMotors
extends RefCounted
## Builder-entered motors (LTHL-22). The frames suite next door guards two things above all
## else — a custom part becoming the reference build, and a half-written user:// document
## stopping Lab from opening — and both of those are inherited here rather than re-argued.
##
## What is NEW in this slice, and what most of this file is about, is that a motor's headline
## thrust figure is not a description of the motor. It is a number off a manufacturer's table,
## and k_t is FITTED from it, so a digit typed wrong does not make the aircraft slightly wrong:
## it makes an aircraft that flies on thrust nobody measured. Three of the tests below exist
## only to catch that, and the fourth — the missing thrust_test refusal — exists because
## build.gd:222 fits k_t against an empty dictionary and produces a drone that silently does
## not fly.

const EPS := 0.05
const GRAVITY_MPS2 := 9.81


static func run() -> Array:
	var results: Array = []
	results.append(_test_a_custom_motor_does_not_move_the_reference_build())
	results.append(_test_a_colliding_id_is_refused_and_the_catalog_survives())
	results.append(_test_a_motor_without_a_thrust_test_is_refused())
	results.append(_test_a_thrust_test_naming_no_prop_is_refused_and_says_which())
	results.append(_test_the_k_t_band_is_asserted_from_both_sides())
	results.append(_test_a_thrust_figure_off_by_ten_is_caught())
	results.append(_test_two_custom_stators_draw_independently())
	results.append(_test_a_custom_motor_cannot_be_validated())
	results.append(_test_a_custom_motor_raises_the_frame_fit_warning())
	results.append(_test_unknown_fields_survive_a_round_trip())
	results.append(_test_a_custom_motor_is_selectable_and_flyable())
	results.append(_test_custom_browsing_buckets_are_the_catalogs_own())
	results.append(_test_the_dialog_saves_a_motor_and_refuses_a_bad_one())
	return results


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## A real motor off a real product page: a 2810 1100KV on 6S, the long-range and cinelifter class.
## Built through make_record rather than hand-written, so a change to the record's shape cannot
## leave these tests asserting the old one. Its mount is 16x16 to match the reference build's
## frame, so that a test about thrust is not also quietly a test about bolt holes.
##
## The TEST PROP is an 8" three-blade, and that detail is not decoration. The first version of
## this fixture quoted 2400 g on a 5" prop, and the k_t band flagged it — correctly, because
## nobody sells a 2810 for 5" props and no manufacturer publishes that row. The band caught an
## invented spec on its first outing, which is the entire argument for it, so the fixture moved
## to a row a real product page would carry rather than the bound moving to accept the fixture.
static func _record_2810() -> Dictionary:
	return CustomMotors.make_record(
		"Shed 2810 1100KV", 62.0, 28.0, 10.0, 1100.0, 2400.0, 45.0, 14, "16x16",
		"prop_8x45x3", 22.2, "manufacturer thrust table, 8x4.5x3 at 22.2 V, off the product page")


static func _scratch(suffix: String) -> String:
	var path := "user://test_custom_motors_%s.json" % suffix
	_wipe(path)
	return path


static func _wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _write_raw(path: String, text: String) -> void:
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string(text)
	handle.close()


static func _restore(path: String, previous: String) -> void:
	if previous == "":
		_wipe(path)
	else:
		_write_raw(path, previous)


## The thrust figure a motor must publish for its fitted k_t to come out at exactly `k_t`, on
## its own test prop and voltage. The inverse of PropellerModel.fit_k_t, so that a test can
## place a motor at a chosen distance from the band edge instead of guessing a gram figure and
## hoping. Any drift between this and the fit shows up as the boundary tests going soft, which
## is why it is written from the same two lines rather than from a remembered constant.
static func _thrust_g_for_k_t(k_t: float, kv: float, voltage_v: float) -> float:
	var omega := PropellerModel.rpm_to_rad_s(kv * voltage_v)
	return k_t * omega * omega / GRAVITY_MPS2 * 1000.0


## A build on the reference airframe with one custom motor fitted, and its warnings.
static func _warnings_with_motor(record: Dictionary) -> Array:
	var previous := ""
	if FileAccess.file_exists(CustomMotors.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomMotors.SAVE_PATH)

	var doc := CustomMotors.new()
	var rejections := doc.add(record)
	doc.save(CustomMotors.SAVE_PATH)
	var catalog := PartsCatalog.load_with_custom()

	var out: Array = []
	if rejections.is_empty():
		var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, str(record["part_id"]),
			ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
			ReferenceBuild.FC_ID)
		out = build.warnings()

	_restore(CustomMotors.SAVE_PATH, previous)
	return out


static func _has_warning(warnings: Array, id: StringName) -> bool:
	for warning in warnings:
		if (warning as BuildWarning).id == id:
			return true
	return false


# ---------------------------------------------------------------------------
# 1. The oracle
# ---------------------------------------------------------------------------

## THE test, in the frames suite's words: defining a custom motor — any custom motor, including
## one built to try — must not move 496 g / 11.69 : 1 / 29.6% by a gram or a point. Written at
## the real CustomMotors.SAVE_PATH, not at a scratch path, because the real path is the hazard.
##
## The oracle is asserted TWICE, on purpose, and the second time is the one that earns its place.
##
## ReferenceBuild.build() reads load_default(), which no custom part can reach, so asserting only
## that is a test that cannot fail: no regression in this slice can move a number that is
## computed from a catalog the slice cannot touch. It is worth one line as a canary and no more.
##
## The assertion that CAN fail is the same aircraft built from the MERGED catalog. That is the
## catalog Lab and Sim actually fly, it is where a custom part could shadow a shipped id, and it
## goes wrong the moment the id space stops being two spaces — which is why the document written
## here contains a hand-edited record wearing the reference build's own motor id, the collision a
## builder can really produce and the one that would silently replace the 1450 g oracle with a
## number they typed.
static func _test_a_custom_motor_does_not_move_the_reference_build() -> TestResult:
	var previous := ""
	if FileAccess.file_exists(CustomMotors.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomMotors.SAVE_PATH)

	var doc := CustomMotors.new()
	doc.add(CustomMotors.make_record(
		"Reference Impostor", 9999.0, 22.0, 7.0, 1960.0, 99999.0, 32.0, 14, "16x16",
		"prop_5x43x3", 14.8, "invented to try to move the oracle"))
	doc.save(CustomMotors.SAVE_PATH)

	# Spliced in under the loader, the way a hand-edit arrives: a record claiming the reference
	# build's motor id and ten times its thrust.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CustomMotors.SAVE_PATH))
	var impostor := CustomMotors.make_record("Shadow", 32.0, 22.0, 7.0, 1960.0, 14500.0, 32.0, 14,
		"16x16", "prop_5x43x3", 14.8, "hand-edited to shadow the reference build")
	impostor["part_id"] = ReferenceBuild.MOTOR_ID
	(raw["motors"] as Array).append(impostor)
	_write_raw(CustomMotors.SAVE_PATH, JSON.stringify(raw, "  "))

	# The merged catalog really does hold the legitimate one — otherwise this proves nothing about
	# isolation, only that nothing happened.
	var merged := PartsCatalog.load_with_custom()
	var merged_has_it: bool = not merged.get_part("custom_reference_impostor").is_empty()

	var build := ReferenceBuild.build()
	var pinned := _is_the_oracle(build)

	# The one that can fail: the same six ids, through the catalog Lab flies.
	var from_merged := Build.from_ids(merged, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID)
	var merged_pinned := _is_the_oracle(from_merged)

	var shipped_motors: int = PartsCatalog.load_default().list_category("motor").size()
	var merged_motors: int = merged.list_category("motor").size()

	_restore(CustomMotors.SAVE_PATH, previous)
	return TestResult.new(
		"a defined custom motor does not move the reference build's 496 g / 11.69 / 29.6%",
		merged_has_it and pinned and merged_pinned and merged_motors == shipped_motors + 1,
		"merged sees it=%s, %d shipped vs %d merged motors, shipped build %.2f g / %.2f TWR, merged build %.2f g / %.2f TWR" % [
			merged_has_it, shipped_motors, merged_motors,
			build.all_up_weight_g(), build.thrust_to_weight(),
			from_merged.all_up_weight_g(), from_merged.thrust_to_weight()])


static func _is_the_oracle(build: Build) -> bool:
	return absf(build.all_up_weight_g() - 496.0) < EPS \
		and absf(build.thrust_to_weight() - 11.69) < 0.01 \
		and absf(build.hover_throttle() - 0.296) < 0.001


# ---------------------------------------------------------------------------
# 2. The id space
# ---------------------------------------------------------------------------

## From the document's end AND from the in-memory end, because a builder can hand-edit this file
## and the file is the thing that reaches the catalog. The id chosen is the reference build's own
## motor, which is the collision that would actually matter.
static func _test_a_colliding_id_is_refused_and_the_catalog_survives() -> TestResult:
	var path := _scratch("collision")
	_write_raw(path, JSON.stringify({
		"schema": 1,
		"motors": [{
			"part_id": ReferenceBuild.MOTOR_ID,
			"name": "Not the reference build's motor",
			"category": "motor",
			"mass_g": 999.0,
			"mount_pattern": "16x16",
			"specs": {"kv": 1960, "stator_diameter_mm": 22, "stator_height_mm": 7,
				"max_thrust_g": 99999.0, "max_amps": 32.0, "poles": 14},
			"thrust_test": {"prop_id": "prop_5x43x3", "voltage_v": 14.8},
			"source": "hand-edited to collide",
		}],
	}, "  "))

	var doc := CustomMotors.load_from(path)
	var refused := doc.motors().is_empty() and not doc.rejections().is_empty()

	var catalog := PartsCatalog.load_default()
	var reference_motor: Dictionary = catalog.get_part(ReferenceBuild.MOTOR_ID)
	var untouched := absf(float(reference_motor["specs"]["max_thrust_g"]) - 1450.0) < 0.001

	var direct := CustomMotors.new()
	var record := _record_2810()
	record["part_id"] = ReferenceBuild.MOTOR_ID
	var direct_refused := not direct.add(record).is_empty()

	_wipe(path)
	return TestResult.new(
		"a motor id colliding with a catalog id is refused, and the catalog entry is untouched",
		refused and untouched and direct_refused,
		"file refused=%s, direct refused=%s, catalog %s still %.0f g" % [
			refused, direct_refused, ReferenceBuild.MOTOR_ID,
			float(reference_motor["specs"]["max_thrust_g"])])


# ---------------------------------------------------------------------------
# 3 and 4. thrust_test is mandatory, and its prop must exist
# ---------------------------------------------------------------------------

## The one hard requirement. build.gd:222 does catalog.get_part(motor.thrust_test.prop_id) and
## fits k_t off what comes back; with no thrust_test that is a fit against an empty dictionary,
## and the result is an aircraft that does not fly and never says why. So this is a REFUSAL and
## not a warning, and it is checked at both ends the way the collision is.
##
## The second half matters as much as the first: a bad record must not stop Lab from opening.
## One hand-edited line costs the builder that line and nothing else.
static func _test_a_motor_without_a_thrust_test_is_refused() -> TestResult:
	var cases := [
		{"label": "missing thrust_test", "mutate": func(r: Dictionary) -> void: r.erase("thrust_test")},
		{"label": "empty thrust_test", "mutate": func(r: Dictionary) -> void: r["thrust_test"] = {}},
		{"label": "no prop_id", "mutate": func(r: Dictionary) -> void: (r["thrust_test"] as Dictionary).erase("prop_id")},
		{"label": "zero voltage", "mutate": func(r: Dictionary) -> void: r["thrust_test"]["voltage_v"] = 0.0},
		{"label": "no thrust figure", "mutate": func(r: Dictionary) -> void: (r["specs"] as Dictionary).erase("max_thrust_g")},
		{"label": "zero thrust figure", "mutate": func(r: Dictionary) -> void: r["specs"]["max_thrust_g"] = 0.0},
		{"label": "no kv", "mutate": func(r: Dictionary) -> void: (r["specs"] as Dictionary).erase("kv")},
		{"label": "empty source", "mutate": func(r: Dictionary) -> void: r["source"] = ""},
	]
	var accepted_anyway: Array[String] = []
	for case in cases:
		var doc := CustomMotors.new()
		var record := _record_2810()
		(case["mutate"] as Callable).call(record)
		var rejections := doc.add(record)
		if rejections.is_empty() or not doc.motors().is_empty():
			accepted_anyway.append(str(case["label"]))

	# Through the file, with a named reason — and Lab still opens behind it.
	var path := _scratch("no_thrust_test")
	var bad := _record_2810()
	bad.erase("thrust_test")
	_write_raw(path, JSON.stringify({"schema": 1, "motors": [bad]}, "  "))
	var doc_from_file := CustomMotors.load_from(path)
	var named := false
	for rejection in doc_from_file.rejections():
		if rejection.contains("thrust_test"):
			named = true
	var lab_still_opens := PartsCatalog.load_with_custom(path).is_valid()
	_wipe(path)

	return TestResult.new(
		"a motor with no thrust test, no thrust figure or no provenance is refused by name",
		accepted_anyway.is_empty() and doc_from_file.motors().is_empty() and named and lab_still_opens,
		"%d cases, accepted-when-it-should-not-have: %s; file rejection names thrust_test=%s, catalog still valid=%s" % [
			cases.size(), accepted_anyway, named, lab_still_opens])


## A prop_id that does not resolve is the same failure with a subtler face: the record looks
## complete, and the fit still runs against an empty dictionary. Refused at load like a malformed
## catalog file, and the message has to SAY WHICH ID, because "invalid motor" sends a builder
## looking at the wrong field.
static func _test_a_thrust_test_naming_no_prop_is_refused_and_says_which() -> TestResult:
	var doc := CustomMotors.new()
	var record := _record_2810()
	record["thrust_test"]["prop_id"] = "prop_does_not_exist"
	var rejections := doc.add(record)

	var names_the_id := false
	for rejection in rejections:
		if rejection.contains("prop_does_not_exist"):
			names_the_id = true

	# And a CUSTOM prop, once that slice exists, must be as good as a catalog one — so the check
	# is "resolves in the merged catalog", not "is in data/parts/propellers.json". Asserted here
	# by the one case available today: a catalog prop resolves.
	var good := CustomMotors.new()
	var good_rejections := good.add(_record_2810())

	return TestResult.new(
		"a thrust test naming a prop that does not exist is refused, and the message names it",
		not rejections.is_empty() and names_the_id and doc.motors().is_empty()
			and good_rejections.is_empty(),
		"refused=%s, names the bad id=%s, good record accepted=%s %s" % [
			not rejections.is_empty(), names_the_id, good_rejections.is_empty(), good_rejections])


# ---------------------------------------------------------------------------
# 5 and 6. The k_t cross-check
# ---------------------------------------------------------------------------

## The finding this slice is built on: k_t = thrust_N / omega^2 is a PURE PROPELLER coefficient,
## with no motor term in it, so every motor tested on one prop should fit the same k_t — and
## across the shipped catalog they do not. That disagreement is the honest error bar on
## max_thrust_g as a spec, and MotorPlausibility turns it into the band.
##
## Asserted from BOTH SIDES of the boundary, because a check that only ever fires is as useless
## as one that never does. The two motors here differ in one field, and the field is placed
## against the band edge the implementation reports rather than against a gram figure typed here
## — a hardcoded figure would go stale the moment a motor is added to the catalog, and would be
## asserting a snapshot of the band rather than the band.
static func _test_the_k_t_band_is_asserted_from_both_sides() -> TestResult:
	var catalog := PartsCatalog.load_default()
	# The band is asked for on the fixture's OWN test prop rather than on a prop named here, so
	# that moving the fixture cannot leave this test measuring a boundary the motor is nowhere
	# near — which is precisely the mistake that would make it pass for the wrong reason.
	var test_prop: Dictionary = catalog.get_part(str(_record_2810()["thrust_test"]["prop_id"]))
	var band := MotorPlausibility.k_t_band_for_prop(catalog, test_prop)

	var kv := 1100.0
	var voltage := 22.2

	# Just inside the upper edge, and just outside it. One percent, which is far tighter than
	# any real spread and therefore pins the comparison to the edge itself.
	var inside := _record_2810()
	inside["specs"]["max_thrust_g"] = _thrust_g_for_k_t(float(band["high"]) * 0.99, kv, voltage)
	var outside := _record_2810()
	outside["specs"]["max_thrust_g"] = _thrust_g_for_k_t(float(band["high"]) * 1.01, kv, voltage)
	outside["name"] = "Shed 2810 Overclaimed"

	var inside_warns := _has_warning(_warnings_with_motor(inside), &"implausible_thrust_coefficient")
	var outside_warns := _has_warning(_warnings_with_motor(outside), &"implausible_thrust_coefficient")

	# And the low edge, since a thrust figure can be typed small as easily as large.
	var under := _record_2810()
	under["name"] = "Shed 2810 Underclaimed"
	under["specs"]["max_thrust_g"] = _thrust_g_for_k_t(float(band["low"]) * 0.99, kv, voltage)
	var under_warns := _has_warning(_warnings_with_motor(under), &"implausible_thrust_coefficient")

	return TestResult.new(
		"a k_t inside the catalog's band is quiet; one either side of it warns",
		not inside_warns and outside_warns and under_warns,
		"band %s..%s on %s: inside warns=%s, over warns=%s, under warns=%s" % [
			float(band["low"]), float(band["high"]), test_prop["part_id"],
			inside_warns, outside_warns, under_warns])


## The failure mode the band exists for, in the form it actually arrives in: a decimal point in
## the wrong place. 2400 g typed as 24000 g is a build with ten times the thrust nobody measured,
## and every number downstream of it — TWR, hover throttle, top speed — is fiction.
static func _test_a_thrust_figure_off_by_ten_is_caught() -> TestResult:
	var record := _record_2810()
	record["specs"]["max_thrust_g"] = 24000.0
	var warnings := _warnings_with_motor(record)

	var caught := _has_warning(warnings, &"implausible_thrust_coefficient") \
		or _has_warning(warnings, &"implausible_thrust_density")

	# The honest one still passes both, so this is not a check that fires on everything.
	var honest := _has_warning(_warnings_with_motor(_record_2810()), &"implausible_thrust_coefficient") \
		or _has_warning(_warnings_with_motor(_record_2810()), &"implausible_thrust_density")

	return TestResult.new(
		"a max_thrust_g off by a factor of ten is caught, and the real figure is not",
		caught and not honest, "24000 g caught=%s, 2400 g quiet=%s" % [caught, not honest])


# ---------------------------------------------------------------------------
# 7. The geometry
# ---------------------------------------------------------------------------

## MotorMesh's own argument, applied to motors that are not in the catalog. A fixed bell under a
## uniform scale factor passes every "bigger motor is bigger" check ever written; it cannot pass
## one that asks for a WIDER bell and a SHORTER motor at the same time.
##
## The pair is a custom 2207 against a custom 2805 rather than the 2207/2807 the ticket names,
## for exactly the reason the check exists: a 2807 is wider than a 2207 but not shorter (both are
## 7 mm of stator), so that pair is reachable by a scale factor and would prove nothing. 22x7
## against 28x5 is the real thing. The 2807 is asserted too, on size alone.
static func _test_two_custom_stators_draw_independently() -> TestResult:
	var tall := CustomMotors.make_record("Shed 2207", 32.0, 22.0, 7.0, 1960.0, 1450.0, 32.0, 14,
		"16x16", "prop_5x43x3", 14.8, "off the product page")
	var wide := CustomMotors.make_record("Shed 2805", 55.0, 28.0, 5.0, 1300.0, 2200.0, 42.0, 14,
		"16x16", "prop_5x43x3", 22.2, "off the product page")
	var big := CustomMotors.make_record("Shed 2807", 52.0, 28.0, 7.0, 1300.0, 2250.0, 42.0, 14,
		"16x16", "prop_5x43x3", 22.2, "off the product page")

	var tall_mesh := MotorMesh.new()
	tall_mesh.rebuild(tall)
	var wide_mesh := MotorMesh.new()
	wide_mesh.rebuild(wide)
	var big_mesh := MotorMesh.new()
	big_mesh.rebuild(big)

	var tall_radius := _bell_radius(tall_mesh)
	var wide_radius := _bell_radius(wide_mesh)
	var big_radius := _bell_radius(big_mesh)
	var tall_height := _generated_height(tall_mesh)
	var wide_height := _generated_height(wide_mesh)
	var big_height := _generated_height(big_mesh)

	tall_mesh.free()
	wide_mesh.free()
	big_mesh.free()

	var independent := wide_radius > tall_radius + 0.001 and wide_height < tall_height - 0.001
	var bigger := big_radius > tall_radius + 0.001 and big_height > tall_height

	return TestResult.new(
		"a custom 2805 draws a wider AND shorter motor than a custom 2207",
		independent and bigger,
		"2207 r=%.4f h=%.4f | 2805 r=%.4f h=%.4f | 2807 r=%.4f h=%.4f" % [
			tall_radius, tall_height, wide_radius, wide_height, big_radius, big_height])


## Measured off the generated mesh, never re-read from the record — re-reading stator_diameter_mm
## and comparing it to itself is the test that cannot fail. Both helpers are test_motor_mesh.gd's,
## deliberately duplicated rather than shared: they are the measuring instrument, and an
## instrument two suites can silently change together is one instrument, not two readings.
static func _bell_radius(mesh: MotorMesh) -> float:
	var bell := mesh.get_node("Bell") as MeshInstance3D
	return (bell.mesh as CylinderMesh).top_radius


static func _generated_height(mesh: MotorMesh) -> float:
	var top := -INF
	var bottom := INF
	for child in mesh.get_children():
		var instance := child as MeshInstance3D
		if instance == null:
			continue
		var aabb := instance.mesh.get_aabb()
		top = maxf(top, instance.position.y + aabb.end.y)
		bottom = minf(bottom, instance.position.y + aabb.position.y)
	return top - bottom


# ---------------------------------------------------------------------------
# 8. What a custom motor may never claim
# ---------------------------------------------------------------------------

## `validation` means an independently-measured HELD-OUT point — the thing that stops the thrust
## stand marking its own homework (thrust_validation.gd's header). A user-entered number is
## neither independent nor held out: it comes from the same page the fit came from, and quoting
## it back would produce a bench that congratulates itself on data it was handed.
##
## So the block is REFUSED on the record, and the bench must report every custom motor as "not
## validated" — which is not a gap in the feature, it is the honest reading of what is known.
static func _test_a_custom_motor_cannot_be_validated() -> TestResult:
	var doc := CustomMotors.new()
	var record := _record_2810()
	record["validation"] = [{
		"prop_id": "prop_5x5x3", "voltage_v": 22.2, "measured_thrust_g": 2400.0,
		"source": "the same product page, honest",
	}]
	var rejections := doc.add(record)
	var names_validation := false
	for rejection in rejections:
		if rejection.contains("validation"):
			names_validation = true

	# And the accepted motor reads as unvalidated on the bench, through the real summary path.
	var previous := ""
	if FileAccess.file_exists(CustomMotors.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomMotors.SAVE_PATH)
	var accepted := CustomMotors.new()
	accepted.add(_record_2810())
	accepted.save(CustomMotors.SAVE_PATH)
	var catalog := PartsCatalog.load_with_custom()
	var summary := ThrustValidation.summary_for(catalog, catalog.get_part("custom_shed_2810_1100kv"))
	var points := ThrustValidation.evaluate_motor(catalog, catalog.get_part("custom_shed_2810_1100kv"))
	_restore(CustomMotors.SAVE_PATH, previous)

	return TestResult.new(
		"a custom motor cannot carry a validation block, and the bench calls it not validated",
		not rejections.is_empty() and names_validation and doc.motors().is_empty()
			and summary == "not validated" and points.is_empty(),
		"refused=%s (names validation=%s), bench says \"%s\", %d points" % [
			not rejections.is_empty(), names_validation, summary, points.size()])


# ---------------------------------------------------------------------------
# 9. The warning that already exists
# ---------------------------------------------------------------------------

## build.gd:852 already tells a builder when a motor's bolt pattern does not match the frame's.
## Nothing in this slice should have to teach it about custom motors — it reads mount_pattern off
## whatever dictionary it is handed — and this test is here to prove that it did not have to.
##
## mount_pattern is TOP LEVEL and not in specs, matching the shipped catalog, which is the whole
## reason it fires without changes. A record that put it in specs would fail here rather than in
## some later slice, which is the point.
static func _test_a_custom_motor_raises_the_frame_fit_warning() -> TestResult:
	# The reference build's frame is drilled 16x16. A 25x25 motor does not bolt to it.
	var wrong := CustomMotors.make_record("Shed Wrong Mount", 62.0, 28.0, 10.0, 1100.0, 2400.0,
		45.0, 14, "25x25", "prop_5x43x3", 22.2, "off the product page")
	var wrong_warns := _has_warning(_warnings_with_motor(wrong), &"motor_mount")
	var right_warns := _has_warning(_warnings_with_motor(_record_2810()), &"motor_mount")

	return TestResult.new(
		"a custom motor whose bolt pattern does not fit the frame raises the existing warning",
		wrong_warns and not right_warns,
		"25x25 on a 16x16 frame warns=%s, 16x16 quiet=%s" % [wrong_warns, not right_warns])


# ---------------------------------------------------------------------------
# 10. The document
# ---------------------------------------------------------------------------

## json_store.gd's third rule at both levels, and one thing the frames suite could not check:
## that the two categories share one document without eating each other. A frames block written
## by the frames dialog must survive a motors save, and vice versa.
static func _test_unknown_fields_survive_a_round_trip() -> TestResult:
	var path := _scratch("unknown")
	var doc := CustomMotors.new()
	var record := _record_2810()
	record["future_field"] = {"kv_at_temperature": 42.0}
	doc.add(record)
	doc.save(path)

	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	raw["escs"] = [{"part_id": "custom_someday"}]
	_write_raw(path, JSON.stringify(raw, "  "))

	var reloaded := CustomMotors.load_from(path)
	reloaded.save(path)
	var final: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))

	var kept_top: bool = final.has("escs")
	var kept_field: bool = not final["motors"].is_empty() \
		and (final["motors"][0] as Dictionary).has("future_field")

	# The neighbouring category, which is the case that only exists now there are two. Written the
	# way a dialog writes — load the document, add to it, save it — because that is the only
	# writer there is, and it is the path on which the motors block has to survive. A FRESH
	# CustomFrames saved over this file would clobber the motors, correctly: it was never told
	# what was there. The preservation contract is about round-tripping, not about amnesia.
	var frames_doc := CustomFrames.load_from(path)
	frames_doc.add(CustomFrames.make_record("Shed 5", 112.0, 112.0, 5.1, "16x16", "30.5x30.5",
		"carbon fibre", "measured on my kitchen scale"))
	frames_doc.save(path)
	var motors_survived: int = CustomMotors.load_from(path).motors().size()
	var frames_survived: int = CustomFrames.load_from(path).frames().size()

	_wipe(path)
	return TestResult.new(
		"unknown blocks, unknown record fields and the neighbouring category all survive a save",
		kept_top and kept_field and motors_survived == 1 and frames_survived == 1,
		"top-level kept=%s, record field kept=%s, after a frames save: %d motors / %d frames" % [
			kept_top, kept_field, motors_survived, frames_survived])


# ---------------------------------------------------------------------------
# The whole point: it flies, on its own numbers
# ---------------------------------------------------------------------------

## A custom motor is not a catalog entry that happens to load. It has to go all the way through
## Build.from_ids to a flyable aircraft, and the numbers off the product page have to be the
## numbers the physics runs on.
##
## The assertion is the fitted k_t, recomputed here from the record's own four figures — thrust,
## KV, test voltage, test prop — and moved onto the fitted prop the way Build does. That is the
## one number every other number on the build hangs off, and computing it independently is what
## makes this a test rather than a demonstration: if the build read the catalog's 2207 instead,
## or dropped the prop rescaling, or fitted against the wrong voltage, these two disagree.
##
## Deliberately NOT asserted against a hardcoded newton figure. A literal here would pin the
## rules of thumb in scale_k_t_to_prop, which are documented as replaceable, and this test is
## about the custom motor's numbers reaching the physics rather than about those exponents.
static func _test_a_custom_motor_is_selectable_and_flyable() -> TestResult:
	var previous := ""
	if FileAccess.file_exists(CustomMotors.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomMotors.SAVE_PATH)

	var record := _record_2810()
	var doc := CustomMotors.new()
	doc.add(record)
	doc.save(CustomMotors.SAVE_PATH)
	var catalog := PartsCatalog.load_with_custom()

	# On a 6S pack, not the reference build's 4S. A 1100KV motor whose thrust table was headed
	# 22.2 V is a 6S motor, and flown on 4S it turns 16 000 rpm and hovers at 99% throttle — a
	# true statement about that pairing, but a knife-edge to hang an assertion on. Pairing it with
	# the pack it was measured on is both the honest build and the stable one.
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, str(record["part_id"]),
		ReferenceBuild.PROPELLER_ID, "battery_6s_1300", ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID)

	# The same fit, from the record rather than from the build.
	var specs: Dictionary = record["specs"]
	var test: Dictionary = record["thrust_test"]
	var expected_at_test := PropellerModel.fit_k_t(float(specs["max_thrust_g"]),
		float(specs["kv"]) * float(test["voltage_v"]))
	var expected := PropellerModel.scale_k_t_to_prop(expected_at_test,
		ThrustValidation.geometry_of(catalog.get_part(str(test["prop_id"]))),
		build.prop_geometry())

	var k_t_ok := absf(build.k_t - expected) < expected * 0.001
	# And it is a DIFFERENT aircraft from the reference build, so this cannot be passing by
	# quietly having flown the catalog's 2207.
	var reference_build := ReferenceBuild.build()
	var differs := absf(build.k_t - reference_build.k_t) > reference_build.k_t * 0.05
	var flies := build.thrust_to_weight() > 1.0 and build.hover_throttle() > 0.0 \
		and build.hover_throttle() < 1.0

	_restore(CustomMotors.SAVE_PATH, previous)
	return TestResult.new(
		"a 2810 entered off a product page flies, on the k_t its own four figures imply",
		k_t_ok and differs and flies,
		"k_t %s (want %s), reference %s, AUW %.0f g, TWR %.2f, hover %.1f%%" % [
			build.k_t, expected, reference_build.k_t, build.all_up_weight_g(),
			build.thrust_to_weight(), build.hover_throttle() * 100.0])


# ---------------------------------------------------------------------------
# Browsing, and the authoring surface
# ---------------------------------------------------------------------------

## MotorPicker's Stator and KV filters build their options straight off these strings
## (PartPicker._derive_options), so a value the catalog does not already use is a filter bucket
## with exactly one motor in it, forever. The frames suite makes the same check about size_class
## and for the same reason.
##
## Derived rather than compared against a literal like "28xx", so this keeps checking the real
## thing — agreement with the catalog — rather than one snapshot of it.
static func _test_custom_browsing_buckets_are_the_catalogs_own() -> TestResult:
	var stator_buckets: Dictionary = {}
	var kv_buckets: Dictionary = {}
	for motor in PartsCatalog.load_default().list_category("motor"):
		var block: Dictionary = (motor as Dictionary).get("catalog", {})
		stator_buckets[str(block.get("stator_class", ""))] = true
		kv_buckets[str(block.get("kv_class", ""))] = true

	var record := _record_2810()
	var stator := str(record["catalog"]["stator_class"])
	var kv_class := str(record["catalog"]["kv_class"])

	return TestResult.new(
		"a custom motor's stator and KV buckets are ones the shipped catalog already browses along",
		stator_buckets.has(stator) and kv_buckets.has(kv_class),
		"derived \"%s\" / \"%s\"; catalog stators %s, KV classes %s" % [
			stator, kv_class, stator_buckets.keys(), kv_buckets.keys()])


## The authoring surface, driven through its public methods rather than by synthesising input
## events — the same way the frames suite drives its dialog. What is under test is that the
## dialog goes through CustomMotors rather than writing a record of its own shape, and that a
## refusal comes back to the builder instead of being swallowed.
static func _test_the_dialog_saves_a_motor_and_refuses_a_bad_one() -> TestResult:
	var previous := ""
	if FileAccess.file_exists(CustomMotors.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomMotors.SAVE_PATH)
	_wipe(CustomMotors.SAVE_PATH)

	var dialog := CustomMotorDialog.new()
	dialog.set_fields("Shed 2810 1100KV", 62.0, 28.0, 10.0, 1100.0, 2400.0, 45.0, 14, "16x16",
		"prop_8x45x3", 22.2, "manufacturer thrust table, 8x4.5x3 at 22.2 V")
	var accepted := dialog.submit()
	var on_disk: bool = not CustomMotors.load_from(CustomMotors.SAVE_PATH) \
		.get_motor("custom_shed_2810_1100kv").is_empty()

	# The two refusals a builder can actually produce from this form: no provenance, and a test
	# prop that is not a prop. Both must come back as words, and neither may reach the file.
	dialog.set_fields("No Source", 62.0, 28.0, 10.0, 1100.0, 2400.0, 45.0, 14, "16x16",
		"prop_8x45x3", 22.2, "  ")
	var no_source := dialog.submit()
	dialog.set_fields("No Prop", 62.0, 28.0, 10.0, 1100.0, 2400.0, 45.0, 14, "16x16",
		"prop_nonsense", 22.2, "off the product page")
	var no_prop := dialog.submit()
	var count := CustomMotors.load_from(CustomMotors.SAVE_PATH).motors().size()
	dialog.free()

	_restore(CustomMotors.SAVE_PATH, previous)

	# Not just THAT each was refused, but that it was refused for the field actually left broken —
	# a refusal for the wrong reason is a passing test hiding a broken rule.
	var names_source := false
	for problem in no_source:
		if problem.contains("source"):
			names_source = true
	var names_prop := false
	for problem in no_prop:
		if problem.contains("prop_nonsense"):
			names_prop = true

	return TestResult.new(
		"the dialog saves a good motor and hands back words for the two it must refuse",
		accepted.is_empty() and on_disk and names_source and names_prop and count == 1,
		"accepted=%s, on disk=%s, refusals %d (names source=%s) / %d (names the bad prop=%s), %d motors in the file" % [
			accepted, on_disk, no_source.size(), names_source, no_prop.size(), names_prop, count])
