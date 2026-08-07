class_name TestCustomBatteries
extends RefCounted
## Builder-entered batteries (LTHL-24). Read tests/test_custom_frames.gd first: the shape of every
## test here, and the two things above everything else (a custom pack cannot silently become the
## reference build, and a half-written user:// document cannot stop Lab from opening), is inherited
## from that suite. What is different is the physics — the pack is the biggest single mass and the
## only source of sag, and the one required spec (internal_r_ohm) is not printed on any wrapper —
## so this suite carries more physics assertions and fewer UI ones.

const EPS := 0.05
const K_TOLERANCE := 0.001  # for a self-check that must reproduce arithmetic exactly


static func run() -> Array:
	var results: Array = []
	results.append(_test_reference_build_is_out_of_reach())
	results.append(_test_a_colliding_id_is_refused_and_the_catalog_survives())
	results.append(_test_derived_internal_r_reproduces_the_catalog())
	results.append(_test_a_user_override_of_internal_r_survives_a_round_trip())
	results.append(_test_derived_nominal_v_matches_the_chemistry())
	results.append(_test_a_pack_outside_the_g_per_wh_band_warns())
	results.append(_test_a_pack_inside_the_g_per_wh_band_does_not_warn())
	results.append(_test_a_pack_wider_than_the_plate_raises_the_overhang_warning())
	results.append(_test_high_resistance_loses_more_rpm_ceiling_than_low_resistance())
	results.append(_test_pack_max_amps_respects_a_custom_c_rating())
	results.append(_test_unknown_fields_survive_a_round_trip())
	results.append(_test_a_custom_pack_names_itself_and_the_flight_time_multiplier())
	results.append(_test_a_li_ion_pack_at_lipo_c_warns_about_the_chemistry())
	results.append(_test_the_chemistry_table_agrees_with_the_battery_model())
	return results


# ---------------------------------------------------------------------------
# Scratch and restore, same shape as tests/test_custom_frames.gd
# ---------------------------------------------------------------------------

static func _scratch(suffix: String) -> String:
	var path := "user://test_custom_batteries_%s.json" % suffix
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
		return
	_write_raw(path, previous)


static func _record_4s_1300() -> Dictionary:
	# The shed 4S 1300 pack the rest of this suite uses. Built through make_record so a change to
	# the record's shape cannot leave the tests asserting the old one.
	return CustomBatteries.make_record(
		"Shed 4S 1300", 4, "LiPo", 1300.0, 95.0, 155.0, 77.0, 38.5, 27.0,
		"XT60", "measured on my kitchen scale, dimensions with a caliper")


static func _find(warnings: Array, id: StringName) -> BuildWarning:
	for warning in warnings:
		if (warning as BuildWarning).id == id:
			return warning
	return null


# ---------------------------------------------------------------------------
# The oracles
# ---------------------------------------------------------------------------

## 496 g / 11.69 / 29.6%, asserted here as well as in every other custom-parts suite because THIS
## is the suite that would notice a custom pack move it for a custom-battery reason. Anything that
## touches the id space or the catalog merge is exactly what makes this test the trip-wire.
static func _test_reference_build_is_out_of_reach() -> TestResult:
	var previous := ""
	if FileAccess.file_exists(CustomBatteries.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomBatteries.SAVE_PATH)

	var doc := CustomBatteries.new()
	doc.add(CustomBatteries.make_record("Reference Impostor Pack", 4, "LiPo", 1500.0, 75.0,
		9999.0, 75.0, 35.0, 37.0, "XT60", "invented to try to move the oracle"))
	doc.save(CustomBatteries.SAVE_PATH)

	# The merged catalog really does have it — otherwise this test proves nothing about isolation,
	# only that nothing happened.
	var merged := PartsCatalog.load_with_custom()
	var merged_has_it: bool = not merged.get_part("custom_reference_impostor_pack").is_empty()

	var build := ReferenceBuild.build()
	var auw := build.all_up_weight_g()
	var twr := build.thrust_to_weight()
	var hover := build.hover_throttle()
	var pinned := absf(auw - 496.0) < EPS and absf(twr - 11.69) < 0.01 and absf(hover - 0.296) < 0.001

	_restore(CustomBatteries.SAVE_PATH, previous)
	return TestResult.new(
		"a defined custom pack does not move the reference build's 496 g / 11.69 / 29.6%",
		merged_has_it and pinned,
		"merged sees it=%s, AUW %.2f g, TWR %.2f, hover %.1f%%" % [
			merged_has_it, auw, twr, hover * 100.0])


## The landmine, from the document's end. add() and load_from() must BOTH refuse, because a
## builder can hand-edit this file and the file is the thing that reaches the catalog.
static func _test_a_colliding_id_is_refused_and_the_catalog_survives() -> TestResult:
	var path := _scratch("collision")
	_write_raw(path, JSON.stringify({
		"schema": 1,
		"batteries": [{
			"part_id": "battery_4s_1500",
			"name": "Not the reference pack",
			"category": "battery",
			"mass_g": 9999.0,
			"mounting": {"attachment": "strap"},
			"specs": {
				"cells": 4, "nominal_v": 14.8, "mah": 1500.0,
				"internal_r_ohm": 0.015, "chemistry": "LiPo", "c_rating": 75.0,
				"length_mm": 75.0, "width_mm": 35.0, "height_mm": 37.0,
			},
			"catalog": {"cell_class": "4S", "connector": "XT60"},
			"source": "hand-edited to collide",
		}],
	}, "  "))

	var doc := CustomBatteries.load_from(path)
	var refused := doc.batteries().is_empty() and not doc.rejections().is_empty()

	var catalog := PartsCatalog.load_default()
	var reference_part: Dictionary = catalog.get_part("battery_4s_1500")
	var untouched := absf(float(reference_part["mass_g"]) - 185.0) < 0.001

	# Same refusal through the in-memory path, since the dialog never writes the file first.
	var direct := CustomBatteries.new()
	var record := _record_4s_1300()
	record["part_id"] = "battery_4s_1500"
	var direct_refused := not direct.add(record).is_empty()

	_wipe(path)
	return TestResult.new(
		"an id that is not custom_-prefixed is refused, and the catalog entry is untouched",
		refused and untouched and direct_refused,
		"file refused=%s, direct refused=%s, catalog 4S 1500 still %.0f g" % [
			refused, direct_refused, float(reference_part["mass_g"])])


# ---------------------------------------------------------------------------
# The derivation, and the honesty caveat that comes with it
# ---------------------------------------------------------------------------

## The self-check the header of custom_batteries.gd promises. For each shipped pack, compute what
## the K constant WOULD imply for its resistance, and check that the pack's own stored figure
## reproduces within the pre-registered spread — 1.8x for LiPo 2S+, 1.2x for Li-ion, 2.0x for 1S.
##
## What this test proves is a SELF-CONSISTENCY property of the catalog and the constant taken
## together — not that either agrees with any real pack's measured resistance. That is the whole
## admission the custom-provenance warning is written to make explicit. If a shipped pack falls
## outside its own chemistry's band, either the pack or the constant is out of step with the rest
## of the catalog, and the detail line names which pack.
static func _test_derived_internal_r_reproduces_the_catalog() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var failures: Array[String] = []

	for pack in catalog.list_category("battery"):
		var specs: Dictionary = pack.get("specs", {})
		var cells := int(specs.get("cells", 0))
		var chemistry := str(specs.get("chemistry", ""))
		var mah := float(specs.get("mah", 0.0))
		var c := float(specs.get("c_rating", 0.0))
		var stored_r := float(specs.get("internal_r_ohm", 0.0))
		if cells <= 0 or mah <= 0.0 or c <= 0.0 or stored_r <= 0.0:
			failures.append("%s: unusable spec (cells=%d, mAh=%.0f, C=%.0f, r=%.4f)" % [
				pack["part_id"], cells, mah, c, stored_r])
			continue
		var derived_r := CustomBatteries.derived_internal_r_ohm_for(cells, chemistry, mah, c)
		if derived_r <= 0.0:
			failures.append("%s: derivation returned zero" % pack["part_id"])
			continue
		var spread := CustomBatteries.spread_for(cells, chemistry)
		var ratio := stored_r / derived_r
		if ratio > spread or ratio < 1.0 / spread:
			failures.append("%s: stored %.4f Ohm, derived %.4f Ohm, ratio %.2fx outside %.2fx (%s %dS)" % [
				pack["part_id"], stored_r, derived_r, maxf(ratio, 1.0 / ratio), spread,
				chemistry, cells])

	return TestResult.new(
		"the K constants reproduce every shipped pack's internal resistance within the pre-registered band",
		failures.is_empty(),
		"%d shipped packs, %d outside their band%s" % [
			catalog.list_category("battery").size(), failures.size(),
			"" if failures.is_empty() else ": " + str(failures)])


## Overriding the derivation with a measured value is the whole point of the override — a builder
## who has a meter measures ONCE, and any silent recompute on the next save would throw that away.
## Round-trip through save and load to check the override is what comes back.
static func _test_a_user_override_of_internal_r_survives_a_round_trip() -> TestResult:
	var path := _scratch("override")
	var measured := 0.0325  # a value the K constants would not produce for this pack
	var doc := CustomBatteries.new()
	doc.add(CustomBatteries.make_record("Shed Measured", 4, "LiPo", 1300.0, 95.0,
		155.0, 77.0, 38.5, 27.0, "XT60", "measured with a battery analyser", measured))
	doc.save(path)

	var reloaded := CustomBatteries.load_from(path)
	var record := reloaded.get_battery("custom_shed_measured")
	var stored := float(record.get("specs", {}).get("internal_r_ohm", 0.0))
	var derivation_flag := bool(record.get("derivation", {}).get("internal_r_ohm", true))

	# And a further round trip — save, reload, save, reload — because the honest failure mode of a
	# "preserve override" implementation is one that survives the first round trip and forgets on
	# the second, once the loader has forgotten which value came from a measurement.
	reloaded.save(path)
	var again := CustomBatteries.load_from(path)
	var stored_again := float(again.get_battery("custom_shed_measured") \
		.get("specs", {}).get("internal_r_ohm", 0.0))

	_wipe(path)
	return TestResult.new(
		"a user override of internal_r_ohm survives save and load, and a second round trip after that",
		absf(stored - measured) < 1e-9 and absf(stored_again - measured) < 1e-9 \
			and derivation_flag == false,
		"stored=%.6f, stored_again=%.6f (want %.6f), derivation flag=%s (want false)" % [
			stored, stored_again, measured, derivation_flag])


## Two chemistries, two per-cell nominals, and one arithmetic each. Asserted against the two
## points parts.md and BatteryModel.NOMINAL_CELL_V state directly, so a drift in either the table
## or the multiplication surfaces here rather than later, at a hover throttle that is wrong.
static func _test_derived_nominal_v_matches_the_chemistry() -> TestResult:
	var lipo_4s := CustomBatteries.nominal_v_for(4, "LiPo")
	var liion_6s := CustomBatteries.nominal_v_for(6, "Li-ion")
	var ok := absf(lipo_4s - 14.8) < 1e-6 and absf(liion_6s - 21.6) < 1e-6
	return TestResult.new(
		"4S LiPo derives to 14.8 V and 6S Li-ion derives to 21.6 V, not 4 * 3.7 for both",
		ok,
		"4S LiPo=%.3f V (want 14.8), 6S Li-ion=%.3f V (want 21.6)" % [lipo_4s, liion_6s])


# ---------------------------------------------------------------------------
# The cross-checks
# ---------------------------------------------------------------------------

## A pack far outside its chemistry's g/Wh band warns. 1000 g on a 4S 1500 pack is 45 g/Wh, an
## order of magnitude past the LiPo band, and it is the shape of a real error — a decimal slip in
## the mass or a wrong mAh unit — that the check exists to catch.
static func _test_a_pack_outside_the_g_per_wh_band_warns() -> TestResult:
	var previous := ""
	if FileAccess.file_exists(CustomBatteries.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomBatteries.SAVE_PATH)

	var doc := CustomBatteries.new()
	doc.add(CustomBatteries.make_record("Shed Brick", 4, "LiPo", 1500.0, 75.0,
		1000.0, 75.0, 35.0, 37.0, "XT60", "invented for the g/Wh check"))
	doc.save(CustomBatteries.SAVE_PATH)

	var catalog := PartsCatalog.load_with_custom()
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, "custom_shed_brick",
		ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID)
	var warning := _find(build.warnings(), &"implausible_pack_mass_per_energy")

	_restore(CustomBatteries.SAVE_PATH, previous)
	return TestResult.new(
		"a pack far above its chemistry's g/Wh band raises implausible_pack_mass_per_energy",
		warning != null,
		"warning=%s" % [warning != null])


## The other side of the boundary: an in-band pack does NOT raise the warning. Without this the
## test above proves only that SOMETHING triggers it, not that the band is drawn where it should
## be. The 4S 1300 record used elsewhere in the suite is deliberately near the middle of the
## LiPo band.
static func _test_a_pack_inside_the_g_per_wh_band_does_not_warn() -> TestResult:
	var previous := ""
	if FileAccess.file_exists(CustomBatteries.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomBatteries.SAVE_PATH)

	var doc := CustomBatteries.new()
	doc.add(_record_4s_1300())
	doc.save(CustomBatteries.SAVE_PATH)

	var catalog := PartsCatalog.load_with_custom()
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, "custom_shed_4s_1300",
		ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID)
	var warning := _find(build.warnings(), &"implausible_pack_mass_per_energy")

	_restore(CustomBatteries.SAVE_PATH, previous)
	return TestResult.new(
		"an in-band custom pack does not raise implausible_pack_mass_per_energy",
		warning == null,
		"warning=%s (expected none)" % [warning != null])


## The AirframeModel path a custom pack must join, not a new geometry check. A 250 mm-wide pack on
## a 5" frame whose centre plate is 150 mm is wider than the plate, and AirframeModel already
## draws that and warns about it; this test proves that a CUSTOM pack reaches the same warning
## without the check having to be taught.
static func _test_a_pack_wider_than_the_plate_raises_the_overhang_warning() -> TestResult:
	var previous := ""
	if FileAccess.file_exists(CustomBatteries.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomBatteries.SAVE_PATH)

	var doc := CustomBatteries.new()
	# 250 mm wide across the airframe, on the reference 5" freestyle whose plate is 150 mm.
	doc.add(CustomBatteries.make_record("Shed Wide Pack", 6, "LiPo", 2200.0, 100.0,
		320.0, 75.0, 250.0, 30.0, "XT60", "invented for the overhang check"))
	doc.save(CustomBatteries.SAVE_PATH)

	var catalog := PartsCatalog.load_with_custom()
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, "custom_shed_wide_pack",
		ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID)

	var airframe := AirframeModel.new()
	airframe.rebuild(build)
	var fit := airframe.battery_fit_warnings()
	airframe.free()

	var wider := _find(fit, &"pack_wider_than_plate")

	_restore(CustomBatteries.SAVE_PATH, previous)
	return TestResult.new(
		"a custom pack wider than the frame's plate raises the existing pack_wider_than_plate warning",
		wider != null,
		"warning=%s" % [wider != null])


## Two custom packs identical in everything BUT internal resistance, dropped into otherwise
## identical builds. The high-r pack must reach a strictly lower full-throttle rpm than the low-r
## one, and by a magnitude that says the sag is doing real work — a couple of percent, not two
## decimal places.
##
## Asserts direction AND magnitude on purpose. A test that only checked "the number changed"
## would pass on a physics that swapped nominal_v in and out and did nothing with r.
static func _test_high_resistance_loses_more_rpm_ceiling_than_low_resistance() -> TestResult:
	var previous := ""
	if FileAccess.file_exists(CustomBatteries.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomBatteries.SAVE_PATH)

	var low_r := 0.005
	var high_r := 0.050
	var doc := CustomBatteries.new()
	doc.add(CustomBatteries.make_record("Shed Low R", 4, "LiPo", 1500.0, 75.0,
		185.0, 75.0, 35.0, 37.0, "XT60", "constructed with a low overridden r", low_r))
	doc.add(CustomBatteries.make_record("Shed High R", 4, "LiPo", 1500.0, 75.0,
		185.0, 75.0, 35.0, 37.0, "XT60", "constructed with a high overridden r", high_r))
	doc.save(CustomBatteries.SAVE_PATH)

	var catalog := PartsCatalog.load_with_custom()
	var low_build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, "custom_shed_low_r",
		ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID)
	var high_build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, "custom_shed_high_r",
		ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID)

	var low_rpm := low_build.rpm_at_throttle(1.0)
	var high_rpm := high_build.rpm_at_throttle(1.0)
	var direction_ok := high_rpm < low_rpm
	# The two resistances differ by a factor of 10 and by 45 mOhm; at four motors drawing tens of
	# amps this is on the order of a volt of sag at the pack, or several percent of RPM ceiling. A
	# noise-floor magnitude check rather than an oracle: at least 2% below the low-r ceiling.
	var magnitude_ok := (low_rpm - high_rpm) / low_rpm > 0.02

	_restore(CustomBatteries.SAVE_PATH, previous)
	return TestResult.new(
		"a high-r custom pack loses at least a couple of percent of RPM ceiling to a low-r one at the same voltage",
		direction_ok and magnitude_ok,
		"low-r rpm %.0f, high-r rpm %.0f, drop %.2f%%" % [
			low_rpm, high_rpm, (low_rpm - high_rpm) / low_rpm * 100.0])


## `Build.pack_max_amps` reads C as a hard cap on the whole build. A custom c_rating must flow
## through — an entered pack whose c_rating stayed hidden would let a builder ask for punch
## current the pack cannot deliver, and the throttle limits and warnings downstream would report
## the WRONG binding component.
static func _test_pack_max_amps_respects_a_custom_c_rating() -> TestResult:
	var previous := ""
	if FileAccess.file_exists(CustomBatteries.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomBatteries.SAVE_PATH)

	var c := 42.0
	var mah := 1000.0
	var doc := CustomBatteries.new()
	doc.add(CustomBatteries.make_record("Shed 4S 1000 C42", 4, "LiPo", mah, c,
		130.0, 70.0, 34.0, 27.0, "XT60", "invented for the pack_max_amps check"))
	doc.save(CustomBatteries.SAVE_PATH)

	var catalog := PartsCatalog.load_with_custom()
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, "custom_shed_4s_1000_c42",
		ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID)
	var expected := mah / 1000.0 * c
	var actual := build.pack_max_amps()

	_restore(CustomBatteries.SAVE_PATH, previous)
	return TestResult.new(
		"Build.pack_max_amps computes Ah * C for a custom pack, exactly as for a shipped one",
		absf(actual - expected) < 1e-6,
		"pack_max_amps=%.3f A (want %.3f)" % [actual, expected])


## json_store.gd's third rule, at both levels: a top-level block this version never heard of, and
## a field inside a battery record it never heard of. Both come back untouched.
static func _test_unknown_fields_survive_a_round_trip() -> TestResult:
	var path := _scratch("unknown")
	var doc := CustomBatteries.new()
	var record := _record_4s_1300()
	record["future_field"] = {"cycle_count": 42}
	doc.add(record)
	doc.save(path)

	# Splice a top-level block in, the way a later Lothal would have written one.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	raw["escs"] = [{"part_id": "custom_someday"}]
	_write_raw(path, JSON.stringify(raw, "  "))

	var reloaded := CustomBatteries.load_from(path)
	reloaded.save(path)
	var final: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))

	var kept_top: bool = final.has("escs")
	var kept_field: bool = not final["batteries"].is_empty() \
		and (final["batteries"][0] as Dictionary).has("future_field")

	_wipe(path)
	return TestResult.new(
		"unknown top-level blocks and unknown record fields survive a save/load round trip",
		kept_top and kept_field,
		"top-level kept=%s, record field kept=%s" % [kept_top, kept_field])


# ---------------------------------------------------------------------------
# The custom-provenance warning
# ---------------------------------------------------------------------------

## The one warning every custom pack carries, and it MUST name FLIGHT_CURRENT_TO_HOVER_RATIO by
## its own constant name — a builder chasing an unexpected flight time reads Lothal's warnings
## and greps the source for that string, and paraphrasing it here would mean the search misses.
##
## Also checks: quotes the builder's own source, is CHARACTERISTIC (not LIMITING — a custom pack
## does not bind the aircraft), and is absent from a catalog-pack build.
static func _test_a_custom_pack_names_itself_and_the_flight_time_multiplier() -> TestResult:
	var previous := ""
	if FileAccess.file_exists(CustomBatteries.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomBatteries.SAVE_PATH)

	var doc := CustomBatteries.new()
	doc.add(_record_4s_1300())
	doc.save(CustomBatteries.SAVE_PATH)
	var catalog := PartsCatalog.load_with_custom()

	var custom_build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, "custom_shed_4s_1300",
		ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID)
	var custom_warning := _find(custom_build.warnings(), &"custom_battery")
	var catalog_warning := _find(ReferenceBuild.build().warnings(), &"custom_battery")

	var names_constant: bool = custom_warning != null \
		and custom_warning.message.contains("FLIGHT_CURRENT_TO_HOVER_RATIO")
	var quotes_source: bool = custom_warning != null \
		and custom_warning.message.contains("kitchen scale")
	var is_characteristic: bool = custom_warning != null \
		and custom_warning.severity == BuildWarning.Severity.CHARACTERISTIC

	_restore(CustomBatteries.SAVE_PATH, previous)
	return TestResult.new(
		"a custom-pack build warns, names the flight-time constant and quotes provenance; a catalog build does not",
		custom_warning != null and catalog_warning == null and names_constant \
			and quotes_source and is_characteristic,
		"custom warning=%s, reference warning=%s, names constant=%s, quotes source=%s" % [
			custom_warning != null, catalog_warning != null, names_constant, quotes_source])


## A Li-ion pack at a LiPo-class C rating is a chemistry mis-selection, and it flows through into
## a pack_max_amps that lies about the pack. The check exists for that reading; without it, a
## builder who picked the wrong chemistry off the dropdown would see the whole aircraft claim
## punch-out current a Li-ion physically cannot deliver, and nothing would say a word.
static func _test_a_li_ion_pack_at_lipo_c_warns_about_the_chemistry() -> TestResult:
	var previous := ""
	if FileAccess.file_exists(CustomBatteries.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomBatteries.SAVE_PATH)

	var doc := CustomBatteries.new()
	doc.add(CustomBatteries.make_record("Shed Li-ion Wrong C", 6, "Li-ion", 4000.0, 75.0,
		590.0, 78.0, 64.0, 43.0, "XT60", "invented for the chemistry vs C check"))
	doc.save(CustomBatteries.SAVE_PATH)

	var catalog := PartsCatalog.load_with_custom()
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, "custom_shed_li_ion_wrong_c",
		ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID)
	var warning := _find(build.warnings(), &"implausible_li_ion_c_rating")

	_restore(CustomBatteries.SAVE_PATH, previous)
	return TestResult.new(
		"a Li-ion pack at a LiPo-class C rating raises implausible_li_ion_c_rating",
		warning != null,
		"warning=%s" % [warning != null])


## The two tables have to agree. NOMINAL_V_PER_CELL in custom_batteries.gd derives the record's
## voltage; NOMINAL_CELL_V in battery_model.gd hangs the discharge curve off it. If the two ever
## disagree, a derived pack would fly on a curve rooted at a different voltage than the one shown
## in the UI — the exact drift BatteryModel's own header says the tests exist to prevent.
static func _test_the_chemistry_table_agrees_with_the_battery_model() -> TestResult:
	var mismatches: Array[String] = []
	for chemistry in CustomBatteries.NOMINAL_V_PER_CELL:
		var here: float = float(CustomBatteries.NOMINAL_V_PER_CELL[chemistry])
		var there := BatteryModel.nominal_cell_v(chemistry)
		if absf(here - there) > 1e-9:
			mismatches.append("%s: custom_batteries=%.3f, battery_model=%.3f" % [chemistry, here, there])
	return TestResult.new(
		"custom_batteries and battery_model agree on every chemistry's per-cell nominal voltage",
		mismatches.is_empty(),
		"%d chemistries, mismatches: %s" % [
			CustomBatteries.NOMINAL_V_PER_CELL.size(), str(mismatches)])
