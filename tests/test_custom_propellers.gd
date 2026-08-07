class_name TestCustomPropellers
extends RefCounted
## Builder-entered propellers (LTHL-23). This slice closes the loop LTHL-22 opens: a custom
## motor's `thrust_test.prop_id` may name a custom prop, so the two documents share a load order
## and a delete-refusal contract, and both sides of that live here.
##
## Two things this suite exists to prevent above everything else it checks: a custom prop silently
## becoming the reference build's prop (inherited from the frames and motors suites), and a
## delete taking the neighbouring motor down with it — which is the new failure mode.

const EPS := 0.05


static func run() -> Array:
	var results: Array = []
	results.append(_test_reference_build_is_untouched_by_any_custom_prop())
	results.append(_test_a_colliding_id_is_refused_and_the_catalog_survives())
	results.append(_test_extrapolation_warning_fires_on_a_far_prop_and_not_on_the_test_prop())
	results.append(_test_deleting_a_depended_on_prop_is_refused_and_names_the_motor())
	results.append(_test_load_order_resolves_a_custom_motor_named_a_custom_prop())
	results.append(_test_a_custom_prop_over_the_frame_raises_the_existing_clearance_warning())
	results.append(_test_propeller_mesh_at_the_extremes())
	results.append(_test_two_and_four_blade_custom_props_draw_differently())
	results.append(_test_unknown_fields_survive_a_round_trip())
	results.append(_test_extrapolation_bound_is_at_least_the_catalog_noise_floor())
	results.append(_test_a_custom_prop_is_selectable_and_flyable())
	return results


# ---------------------------------------------------------------------------
# Fixtures and helpers
# ---------------------------------------------------------------------------

## A real prop off a real product page: a 5" tri-blade in the neighbourhood of the reference
## build's own, so a test that puts it on the reference motor is exercising this slice's
## machinery rather than an extrapolation warning that would fire independently.
static func _record_5in() -> Dictionary:
	return CustomPropellers.make_record(
		"Shed 5x4.3x3", 4.5, 5.0, 4.3, 3, "polycarbonate",
		"measured on my scale, dimensions off the product page")


## A 7" prop, deliberately far in diameter from the reference motor's 5" test prop, so
## PropExtrapolation has something to warn about.
static func _record_7in() -> Dictionary:
	return CustomPropellers.make_record(
		"Shed 7x4x3", 9.0, 7.0, 4.0, 3, "glass-filled nylon",
		"off the product page")


static func _scratch(suffix: String) -> String:
	var path := "user://test_custom_propellers_%s.json" % suffix
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


static func _has_warning(warnings: Array, id: StringName) -> bool:
	for warning in warnings:
		if (warning as BuildWarning).id == id:
			return true
	return false


## Runs `body` with the real user:// file replaced by whatever `body` writes to it, and restores
## whatever was there before. Every test that touches CustomParts.SAVE_PATH does this dance, and
## keeping it in one helper stops a test from forgetting the restore and quietly shifting the file
## every later suite in the run reads.
static func _with_scratch_savepath(body: Callable) -> Variant:
	var previous := ""
	if FileAccess.file_exists(CustomParts.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomParts.SAVE_PATH)
	_wipe(CustomParts.SAVE_PATH)
	var result = body.call()
	_restore(CustomParts.SAVE_PATH, previous)
	return result


# ---------------------------------------------------------------------------
# 1. The oracle
# ---------------------------------------------------------------------------

## Defining a custom prop — any custom prop, including one wearing an id that tries to shadow the
## reference build's — must not move 496 g / 11.69 / 29.6% by a gram or a point. Same shape as
## test_custom_motors.gd's oracle test, and for the same reason: load_default() is what the
## reference build reads, and load_with_custom() is what Lab flies, and the isolation between
## the two IS the whole of the collision defence.
static func _test_reference_build_is_untouched_by_any_custom_prop() -> TestResult:
	var check := func() -> Dictionary:
		var doc := CustomPropellers.new()
		doc.add(CustomPropellers.make_record("Reference Impostor", 999.0, 5.0, 4.3, 3,
			"polycarbonate", "invented to try to move the oracle"))
		doc.save(CustomParts.SAVE_PATH)

		# The impostor with the reference build's own prop id, spliced in through a hand edit —
		# the collision the prefix rule refuses.
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CustomParts.SAVE_PATH))
		var impostor := CustomPropellers.make_record("Shadow", 999.0, 5.0, 4.3, 3, "polycarbonate",
			"hand-edited to shadow the reference build")
		impostor["part_id"] = ReferenceBuild.PROPELLER_ID
		(raw["propellers"] as Array).append(impostor)
		_write_raw(CustomParts.SAVE_PATH, JSON.stringify(raw, "  "))

		var merged := PartsCatalog.load_with_custom()
		var oracle := ReferenceBuild.build()
		var from_merged_build := Build.from_ids(merged, ReferenceBuild.FRAME_ID,
			ReferenceBuild.MOTOR_ID, ReferenceBuild.PROPELLER_ID,
			ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID)
		var shipped_count: int = PartsCatalog.load_default().list_category("propeller").size()
		var merged_count: int = merged.list_category("propeller").size()
		return {"reference": oracle, "from_merged": from_merged_build,
			"shipped_count": shipped_count, "merged_count": merged_count}

	var out: Dictionary = _with_scratch_savepath(check)
	var ref_build: Build = out["reference"]
	var from_merged: Build = out["from_merged"]
	var pinned := _is_the_oracle(ref_build) and _is_the_oracle(from_merged)
	var counts_agree: bool = int(out["merged_count"]) == int(out["shipped_count"]) + 1

	return TestResult.new(
		"a defined custom prop does not move the reference build's 496 g / 11.69 / 29.6%",
		pinned and counts_agree,
		"%d shipped vs %d merged props, reference %.2f g / %.2f TWR, merged reference %.2f g / %.2f TWR" % [
			out["shipped_count"], out["merged_count"],
			ref_build.all_up_weight_g(), ref_build.thrust_to_weight(),
			from_merged.all_up_weight_g(), from_merged.thrust_to_weight()])


static func _is_the_oracle(build: Build) -> bool:
	return absf(build.all_up_weight_g() - 496.0) < EPS \
		and absf(build.thrust_to_weight() - 11.69) < 0.01 \
		and absf(build.hover_throttle() - 0.296) < 0.001


# ---------------------------------------------------------------------------
# 2. Id-space collision
# ---------------------------------------------------------------------------

static func _test_a_colliding_id_is_refused_and_the_catalog_survives() -> TestResult:
	var path := _scratch("collision")
	_write_raw(path, JSON.stringify({
		"schema": 1,
		"propellers": [{
			"part_id": ReferenceBuild.PROPELLER_ID,
			"name": "Not the reference build's prop",
			"category": "propeller",
			"mass_g": 999.0,
			"specs": {"diameter_inches": 5.0, "pitch_inches": 4.3, "blades": 3},
			"catalog": {"blade_count": "3-blade", "diameter_class": "5\"",
				"intended_use": "custom", "material": "polycarbonate"},
			"source": "hand-edited to collide",
		}],
	}, "  "))

	var doc := CustomPropellers.load_from(path)
	var refused := doc.propellers().is_empty() and not doc.rejections().is_empty()

	var catalog := PartsCatalog.load_default()
	var reference_prop: Dictionary = catalog.get_part(ReferenceBuild.PROPELLER_ID)
	var untouched := absf(float(reference_prop["mass_g"]) - 4.5) < 0.001

	var direct := CustomPropellers.new()
	var record := _record_5in()
	record["part_id"] = ReferenceBuild.PROPELLER_ID
	var direct_refused := not direct.add(record).is_empty()

	_wipe(path)
	return TestResult.new(
		"a propeller id colliding with a catalog id is refused, and the catalog entry is untouched",
		refused and untouched and direct_refused,
		"file refused=%s, direct refused=%s, catalog %s still %.2f g" % [
			refused, direct_refused, ReferenceBuild.PROPELLER_ID, float(reference_prop["mass_g"])])


# ---------------------------------------------------------------------------
# 3. The extrapolation warning, from both sides of its boundary
# ---------------------------------------------------------------------------

## The heart of this slice's honesty story: a prop far from the motor's own test prop is having
## its thrust computed by extrapolating two rules of thumb, and PropExtrapolation says so. This
## asserts the boundary from BOTH sides — a custom 7" on the reference motor (which was tested
## on a 5" prop) fires, and the reference motor on its own 5" test prop does not.
static func _test_extrapolation_warning_fires_on_a_far_prop_and_not_on_the_test_prop() -> TestResult:
	var check := func() -> Dictionary:
		var doc := CustomPropellers.new()
		doc.add(_record_7in())
		doc.save(CustomParts.SAVE_PATH)
		var catalog := PartsCatalog.load_with_custom()

		# The reference motor's own thrust_test is on prop_5x43x3. Flying it on a custom 7" prop
		# extrapolates by (7/5)^4 = 3.84x — well beyond the 2.0x bound.
		var far := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
			"custom_shed_7x4x3", ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
			ReferenceBuild.FC_ID)
		var ref_build := ReferenceBuild.build()  # motor on its own test prop — factor 1.0
		return {"far_warns": _has_warning(far.warnings(), PropExtrapolation.NAME),
			"reference_warns": _has_warning(ref_build.warnings(), PropExtrapolation.NAME)}

	var out: Dictionary = _with_scratch_savepath(check)
	return TestResult.new(
		"a custom 7\" prop on a motor tested on a 5\" prop warns; the same motor on its own test prop is quiet",
		out["far_warns"] and not out["reference_warns"],
		"far build warns=%s, motor on its own test prop warns=%s" % [
			out["far_warns"], out["reference_warns"]])


# ---------------------------------------------------------------------------
# 4. Delete-refusal
# ---------------------------------------------------------------------------

## The failure mode a naive remove() would produce: a custom motor whose thrust_test names this
## custom prop is left fitting k_t against an empty dictionary — the silent-fail motors.json's
## _schema warns about, back-doored by a delete rather than by a missing field.
static func _test_deleting_a_depended_on_prop_is_refused_and_names_the_motor() -> TestResult:
	var check := func() -> Dictionary:
		var props := CustomPropellers.new()
		props.add(_record_5in())
		props.save(CustomParts.SAVE_PATH)
		# Load the motors document — even fresh — so its unknown_top preserves the propellers block
		# instead of overwriting the file. Same dialog-writes-what-it-reads pattern
		# tests/test_custom_motors.gd uses for the frames/motors round trip.
		var motors := CustomMotors.load_from()
		var motor := CustomMotors.make_record("Shed Motor", 32.0, 22.0, 7.0, 1960.0, 1450.0,
			32.0, 14, "16x16", "custom_shed_5x4_3x3", 14.8,
			"manufacturer table on a prop I entered myself")
		var motor_rejections := motors.add(motor)
		motors.save(CustomParts.SAVE_PATH)

		# Load the two documents afresh, the way a Lab surface would.
		var reloaded_props := CustomPropellers.load_from()
		var reloaded_motors := CustomMotors.load_from()

		var block_message := reloaded_props.removal_block_message(reloaded_motors,
			"custom_shed_5x4_3x3")
		var refused := not reloaded_props.remove_or_refuse("custom_shed_5x4_3x3", reloaded_motors)
		var still_there: bool = not reloaded_props.get_propeller("custom_shed_5x4_3x3").is_empty()

		# And an independent prop whose id nobody names IS removable — otherwise this proves only
		# that remove_or_refuse is broken.
		reloaded_props.add(_record_7in())
		var independent_removed := reloaded_props.remove_or_refuse("custom_shed_7x4x3",
			reloaded_motors)

		return {"motor_ok": motor_rejections.is_empty(), "block_names": block_message.contains("Shed Motor"),
			"refused": refused, "still_there": still_there,
			"independent_removed": independent_removed}

	var out: Dictionary = _with_scratch_savepath(check)
	return TestResult.new(
		"deleting a custom prop a custom motor depends on is refused, and the message names the motor",
		out["motor_ok"] and out["block_names"] and out["refused"] and out["still_there"]
			and out["independent_removed"],
		"motor accepted=%s, block message names motor=%s, delete refused=%s, prop still present=%s, independent prop removed=%s" % [
			out["motor_ok"], out["block_names"], out["refused"], out["still_there"],
			out["independent_removed"]])


# ---------------------------------------------------------------------------
# 5. Load order: motor→prop resolution across the same file
# ---------------------------------------------------------------------------

## The whole reason CustomPropellers loads before CustomMotors: a motor citing a custom prop must
## resolve at load time, or the record is refused with "not a propeller Lothal knows about" and
## the aircraft the builder just described is silently unavailable.
##
## This test fails if the order in PartsCatalog.load_with_custom is reversed, or if the catalog
## handed to CustomMotors.read_from doesn't already hold the custom prop.
static func _test_load_order_resolves_a_custom_motor_named_a_custom_prop() -> TestResult:
	var check := func() -> Dictionary:
		var props := CustomPropellers.new()
		props.add(_record_5in())
		props.save(CustomParts.SAVE_PATH)

		# Same round-trip discipline as the delete test: load so the motors' unknown_top preserves
		# the propellers block rather than the second save wiping the file.
		var motors := CustomMotors.load_from()
		var motor := CustomMotors.make_record("Shed Motor", 32.0, 22.0, 7.0, 1960.0, 1450.0,
			32.0, 14, "16x16", "custom_shed_5x4_3x3", 14.8,
			"manufacturer table on a prop I entered myself")
		var direct_rejections := motors.add(motor)
		motors.save(CustomParts.SAVE_PATH)

		# The path that ACTUALLY matters: reload from disk. If the load order is wrong or the
		# catalog seam is not threaded through, the motor's thrust_test.prop_id fails to resolve
		# and the motor is dropped on the floor.
		var reloaded_motors := CustomMotors.load_from()
		var motor_present: bool = not reloaded_motors.get_motor("custom_shed_motor").is_empty()
		var no_rejections: bool = reloaded_motors.rejections().is_empty()
		return {"direct_ok": direct_rejections.is_empty(), "motor_present": motor_present,
			"no_rejections": no_rejections}

	var out: Dictionary = _with_scratch_savepath(check)
	return TestResult.new(
		"a custom motor whose thrust_test names a custom prop loads without complaint",
		out["direct_ok"] and out["motor_present"] and out["no_rejections"],
		"direct add ok=%s, present after reload=%s, reload rejections empty=%s" % [
			out["direct_ok"], out["motor_present"], out["no_rejections"]])


# ---------------------------------------------------------------------------
# 6. The existing clearance warning fires for custom props
# ---------------------------------------------------------------------------

## build.gd:846 already warns when a prop's diameter exceeds the frame's max_prop_inches. Nothing
## in this slice should have had to teach it about custom props — it reads specs.diameter_inches
## off whatever dictionary it is handed — and this test proves it did not have to.
static func _test_a_custom_prop_over_the_frame_raises_the_existing_clearance_warning() -> TestResult:
	var check := func() -> Dictionary:
		var props := CustomPropellers.new()
		# 10" prop on the reference frame's 5" clearance.
		props.add(CustomPropellers.make_record("Too Big", 20.0, 10.0, 5.0, 2, "polycarbonate",
			"off a 10\" long-range prop's product page"))
		props.save(CustomParts.SAVE_PATH)
		var catalog := PartsCatalog.load_with_custom()

		var over := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
			"custom_too_big", ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
			ReferenceBuild.FC_ID)
		var ref_build := ReferenceBuild.build()
		return {"over_warns": _has_warning(over.warnings(), &"prop_clearance"),
			"reference_warns": _has_warning(ref_build.warnings(), &"prop_clearance")}

	var out: Dictionary = _with_scratch_savepath(check)
	return TestResult.new(
		"a custom prop bigger than the frame's max_prop_inches raises the existing prop_clearance warning",
		out["over_warns"] and not out["reference_warns"],
		"10\" on a 5\" frame warns=%s, reference quiet=%s" % [
			out["over_warns"], not out["reference_warns"]])


# ---------------------------------------------------------------------------
# 7. Renderer at the extremes
# ---------------------------------------------------------------------------

## PropellerMesh's twist and chord derivations must not crash on the accepted range's edges. A
## degenerate value must guard rather than divide by zero. Not a rendering-fidelity test — that
## belongs in test_propeller_mesh.gd — but a not-crashing test on the geometry a custom prop
## dialog can push through it.
static func _test_propeller_mesh_at_the_extremes() -> TestResult:
	var cases := [
		CustomPropellers.make_record("Tiny", 0.5, 1.0, 0.5, 2, "polycarbonate", "extreme small"),
		CustomPropellers.make_record("Huge", 100.0, 30.0, 15.0, 3, "polycarbonate", "extreme large"),
		CustomPropellers.make_record("HighPitch", 5.0, 5.0, 20.0, 3, "polycarbonate", "steep pitch"),
		CustomPropellers.make_record("Single", 3.0, 5.0, 4.0, 1, "polycarbonate", "single blade"),
	]
	var failures: Array[String] = []
	for record in cases:
		var mesh := PropellerMesh.new()
		mesh.rebuild(record)
		if mesh.radius_m <= 0.0 or mesh.blade_count < 1 or mesh.stack_height_m <= 0.0:
			failures.append(str(record["name"]))
		mesh.free()

	return TestResult.new(
		"propeller_mesh produces valid geometry at the extremes and does not crash outside them",
		failures.is_empty(),
		"4 extreme records, failures: %s" % [failures])


# ---------------------------------------------------------------------------
# 8. Two- and four-blade custom props draw differently
# ---------------------------------------------------------------------------

static func _test_two_and_four_blade_custom_props_draw_differently() -> TestResult:
	var two := CustomPropellers.make_record("Shed 5x4 Bi", 3.5, 5.0, 4.0, 2, "polycarbonate", "bi")
	var four := CustomPropellers.make_record("Shed 5x4 Quad", 5.5, 5.0, 4.0, 4, "polycarbonate", "quad")

	var two_mesh := PropellerMesh.new()
	two_mesh.rebuild(two)
	var four_mesh := PropellerMesh.new()
	four_mesh.rebuild(four)

	var two_count := _count_blade_nodes(two_mesh)
	var four_count := _count_blade_nodes(four_mesh)
	var two_chord := _widest_chord_m(two_mesh)
	var four_chord := _widest_chord_m(four_mesh)

	two_mesh.free()
	four_mesh.free()

	# More blades, narrower each — PropellerMesh.CHORD_BLADE_COUNT_EXPONENT.
	var ok := two_count == 2 and four_count == 4 and two_chord > four_chord + 0.001
	return TestResult.new(
		"a custom 4-blade and a custom 2-blade of the same diameter differ in blade count and chord",
		ok, "2-blade count=%d chord=%.4f, 4-blade count=%d chord=%.4f" % [
			two_count, two_chord, four_count, four_chord])


static func _count_blade_nodes(mesh: PropellerMesh) -> int:
	var n := 0
	for child in mesh.get_children():
		if String(child.name).begins_with("Blade_"):
			n += 1
	return n


## Reads the widest chord off the generated blade mesh's AABB — the same "measure the geometry
## rather than re-read the input" discipline test_custom_motors.gd's _bell_radius uses.
static func _widest_chord_m(mesh: PropellerMesh) -> float:
	for child in mesh.get_children():
		if not String(child.name).begins_with("Blade_"):
			continue
		var instance := child as MeshInstance3D
		var aabb := instance.mesh.get_aabb()
		# Blade-local +X is radial; chord lies in the YZ plane and is stretched into Y/Z by twist.
		return aabb.size.z
	return 0.0


# ---------------------------------------------------------------------------
# 9. Unknown fields survive
# ---------------------------------------------------------------------------

static func _test_unknown_fields_survive_a_round_trip() -> TestResult:
	var path := _scratch("unknown")
	var doc := CustomPropellers.new()
	var record := _record_5in()
	record["future_field"] = {"efficiency_at_hover": 0.6}
	doc.add(record)
	doc.save(path)

	# Splice a top-level block in, the way a later Lothal would have written one.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	raw["motors"] = [{"part_id": "custom_someday"}]
	_write_raw(path, JSON.stringify(raw, "  "))

	var reloaded := CustomPropellers.load_from(path)
	reloaded.save(path)
	var final: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))

	var kept_top: bool = final.has("motors")
	var kept_field: bool = not final["propellers"].is_empty() \
		and (final["propellers"][0] as Dictionary).has("future_field")

	_wipe(path)
	return TestResult.new(
		"unknown top-level blocks and unknown record fields survive a save/load round trip",
		kept_top and kept_field, "top-level kept=%s, record field kept=%s" % [kept_top, kept_field])


# ---------------------------------------------------------------------------
# The bound itself — held to the 1.8x noise floor
# ---------------------------------------------------------------------------

## PropExtrapolation.EXTRAPOLATION_BOUND is the whole promise the warning makes. This test holds
## the constant to at least the 1.8x floor documented in its header: a bound below the catalog's
## own motor-to-motor k_t disagreement on the same prop would fire on scaled values that are inside
## the catalog's own noise, which is exactly the false positive the header rules out.
static func _test_extrapolation_bound_is_at_least_the_catalog_noise_floor() -> TestResult:
	var noise_floor := 1.8
	var ok: bool = PropExtrapolation.EXTRAPOLATION_BOUND >= noise_floor
	return TestResult.new(
		"the extrapolation bound is at least the 1.8x catalog motor-to-motor noise floor",
		ok, "EXTRAPOLATION_BOUND=%.2f, floor=%.2f" % [
			PropExtrapolation.EXTRAPOLATION_BOUND, noise_floor])


# ---------------------------------------------------------------------------
# The whole point: a custom prop flies
# ---------------------------------------------------------------------------

static func _test_a_custom_prop_is_selectable_and_flyable() -> TestResult:
	var check := func() -> Dictionary:
		var doc := CustomPropellers.new()
		doc.add(_record_5in())
		doc.save(CustomParts.SAVE_PATH)
		var catalog := PartsCatalog.load_with_custom()

		var candidate := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
			"custom_shed_5x4_3x3", ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
			ReferenceBuild.FC_ID)
		return {"flown": candidate, "custom_warns": _has_warning(candidate.warnings(), &"custom_propeller")}

	var out: Dictionary = _with_scratch_savepath(check)
	var flown: Build = out["flown"]
	var flies := flown.thrust_to_weight() > 1.0 and flown.hover_throttle() > 0.0 \
		and flown.hover_throttle() < 1.0
	return TestResult.new(
		"a custom 5\" prop on the reference motor flies, and the build says it is custom",
		flies and out["custom_warns"],
		"AUW %.0f g, TWR %.2f, hover %.1f%%, custom warning=%s" % [
			flown.all_up_weight_g(), flown.thrust_to_weight(),
			flown.hover_throttle() * 100.0, out["custom_warns"]])
