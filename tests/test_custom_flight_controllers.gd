class_name TestCustomFlightControllers
extends RefCounted
## Builder-entered flight controllers (LTHL-25, part B). Read tests/test_custom_frames.gd first for
## the shape of every test here, and tests/test_custom_escs.gd for the other half of the same stack.
##
## The four gyro specs are the point of this suite, and only ONE of them is typed. `gyro_noise_rad_s`
## is DERIVED — the IMU's published rate noise density carried across the sample rate — and the
## derivation is checked against every shipped board rather than asserted. `gyro_bias_rad_s` is
## derived too but is ILLUSTRATIVE, because no datasheet publishes calibration residue; the two
## derivations look alike and are not equally trustworthy, and this suite asserts that the code says
## so out loud.
##
## THE SELF-CHECK RUNS OVER ALL SIX SHIPPED ENTRIES, not over the four distinct IMUs. The MPU-6000
## appears twice, at 1 kHz on the reference board and at 8 kHz on the whoop, and the 2.8x gap
## between their published noise floors on IDENTICAL HARDWARE is the single most misreadable number
## in flight_controllers.json. A self-check that visited each IMU once would skip precisely the row
## that proves the formula tracks the sample rate rather than the part.

const EPS := 0.05

## The shipped `gyro_noise_rad_s` figures are published to two significant figures, so the
## derivation reproduces them to half of the last digit and no tighter. A looser bound would let a
## wrong formula through; a tighter one would fail on the catalog's own rounding.
const NOISE_TOLERANCE := 0.00005


static func run() -> Array:
	var results: Array = []
	results.append(_test_reference_build_is_out_of_reach())
	results.append(_test_a_colliding_id_is_refused_and_the_catalog_survives())
	results.append(_test_the_derivation_reproduces_every_shipped_board())
	results.append(_test_every_imu_in_the_table_carries_a_datasheet())
	results.append(_test_an_unknown_imu_needs_a_density_and_says_so())
	results.append(_test_a_noisier_board_has_a_lower_d_ceiling())
	results.append(_test_bias_is_derived_from_grade_and_labelled_illustrative())
	results.append(_test_a_heavy_fc_adds_exactly_its_excess())
	results.append(_test_a_mismatched_fc_pattern_raises_the_fc_fit_warning())
	results.append(_test_an_off_catalog_sample_rate_is_coherent())
	results.append(_test_a_custom_fc_separates_datasheet_noise_from_illustrative_bias())
	results.append(_test_unknown_fields_survive_a_round_trip())
	return results


# ---------------------------------------------------------------------------
# Scratch and restore
# ---------------------------------------------------------------------------

static func _scratch(suffix: String) -> String:
	var path := "user://test_custom_fcs_%s.json" % suffix
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


static func _find(warnings: Array, id: StringName) -> BuildWarning:
	for warning in warnings:
		if (warning as BuildWarning).id == id:
			return warning
	return null


static func _build_on(catalog: PartsCatalog, fc_id: String) -> Build:
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID, fc_id)


static func _with_saved(records: Array, body: Callable) -> Variant:
	var previous := ""
	if FileAccess.file_exists(CustomFlightControllers.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomFlightControllers.SAVE_PATH)

	var document := CustomFlightControllers.new()
	for record in records:
		document.add(record)
	document.save(CustomFlightControllers.SAVE_PATH)

	var result: Variant = body.call(PartsCatalog.load_with_custom())
	_restore(CustomFlightControllers.SAVE_PATH, previous)
	return result


## An H743-class board on a current-generation IMU, which is what the "Done" line of this slice
## asks to fly. Built through make_record so the record's shape lives in one place.
static func _record_h743_class() -> Dictionary:
	return CustomFlightControllers.make_record("Shed H743 Board", "ICM-42688-P", 8000.0,
		12.0, "30.5x30.5", "H743", 8000, "off the product page, gyro rate from my Betaflight config")


# ---------------------------------------------------------------------------
# The oracles
# ---------------------------------------------------------------------------

static func _test_reference_build_is_out_of_reach() -> TestResult:
	var seen: bool = _with_saved([CustomFlightControllers.make_record("Reference Impostor FC",
			"ICM-42688-P", 8000.0, 9999.0, "30.5x30.5", "H743", 8000,
			"invented to try to move the oracle")],
		func(merged: PartsCatalog) -> bool:
			return not merged.get_part("custom_reference_impostor_fc").is_empty())

	var build := ReferenceBuild.build()
	var auw := build.all_up_weight_g()
	var twr := build.thrust_to_weight()
	var hover := build.hover_throttle()
	var pinned := absf(auw - 496.0) < EPS and absf(twr - 11.69) < 0.01 and absf(hover - 0.296) < 0.001

	return TestResult.new(
		"a defined custom FC does not move the reference build's 496 g / 11.69 / 29.6%",
		bool(seen) and pinned,
		"merged sees it=%s, AUW %.2f g, TWR %.2f, hover %.1f%%" % [
			seen, auw, twr, hover * 100.0])


static func _test_a_colliding_id_is_refused_and_the_catalog_survives() -> TestResult:
	var path := _scratch("collision")
	_write_raw(path, JSON.stringify({
		"schema": 1,
		"flight_controllers": [{
			"part_id": Build.DEFAULT_FC_ID,
			"name": "Not the reference board",
			"category": "flight_controller",
			"mass_g": 999.0,
			"mounting": {"attachment": "bolt", "pattern": "30.5x30.5"},
			"specs": {
				"gyro_sample_rate_hz": 8000.0, "gyro_cutoff_hz": 150.0,
				"gyro_noise_rad_s": 0.0044, "gyro_bias_rad_s": 0.0012,
			},
			"source": "hand-edited to try to shadow the reference board",
		}],
	}))

	var document := CustomFlightControllers.load_from(path)
	var refused := document.records().is_empty() and not document.rejections().is_empty()

	var shipped := PartsCatalog.load_default().get_part(Build.DEFAULT_FC_ID)
	var intact := absf(float(shipped.get("mass_g", 0.0)) - Build.FC_BUDGET_MASS_G) < EPS

	_wipe(path)
	return TestResult.new(
		"an FC claiming a shipped id is refused, and the shipped board is untouched",
		refused and intact,
		"file refused=%s (%s), shipped mass %.1f g" % [
			refused, document.rejections(), float(shipped.get("mass_g", 0.0))])


# ---------------------------------------------------------------------------
# The derivation, and what backs it
# ---------------------------------------------------------------------------

## The derivation's self-check, over EVERY shipped entry. Not tuned to fit: the densities come from
## the datasheets and the formula from the schema, and this test reports whatever they produce.
##
## The whoop board is the row that matters most. It carries the same MPU-6000 as the reference board
## at 8x the sample rate and a 2.8x higher published noise floor, and a derivation that quietly
## keyed off the IMU alone would reproduce five entries and miss that one.
static func _test_the_derivation_reproduces_every_shipped_board() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var boards := catalog.list_category("flight_controller")
	var failures: Array[String] = []
	var lines: Array[String] = []

	for board in boards:
		var specs: Dictionary = board.get("specs", {})
		var imu := str(board.get("catalog", {}).get("imu", ""))
		var rate := float(specs.get("gyro_sample_rate_hz", 0.0))
		var stored := float(specs.get("gyro_noise_rad_s", 0.0))
		var density := CustomFlightControllers.density_for(imu)
		if density <= 0.0:
			failures.append("%s: %s is not in the IMU table" % [board["part_id"], imu])
			continue
		var derived := CustomFlightControllers.derived_noise_rad_s(density, rate)
		lines.append("%s %s@%.0f: stored %.5f derived %.5f" % [
			board["part_id"], imu, rate, stored, derived])
		if absf(derived - stored) > NOISE_TOLERANCE:
			failures.append("%s: stored %.5f, derived %.5f, off by %.6f" % [
				board["part_id"], stored, derived, absf(derived - stored)])

	return TestResult.new(
		"the noise derivation reproduces every shipped board's published gyro_noise_rad_s, including the MPU-6000 at both its rates",
		failures.is_empty() and boards.size() == 6,
		"%d boards; %s" % [boards.size(),
			"; ".join(lines) if failures.is_empty() else "MISSES: " + str(failures)])


## The table is only as honest as its citations. An IMU admitted without a datasheet reference
## produces a board whose noise floor is fiction, and the D-gain ceiling is computed from it — the
## same fabrication motors.json's `validation` block forbids by name.
##
## Seeded with exactly the four already cited in flight_controllers.json and no others.
static func _test_every_imu_in_the_table_carries_a_datasheet() -> TestResult:
	var uncited: Array[String] = []
	for imu in CustomFlightControllers.IMU_DENSITY:
		var entry: Dictionary = CustomFlightControllers.IMU_DENSITY[imu]
		if str(entry.get("datasheet", "")).strip_edges() == "":
			uncited.append(str(imu))
		if float(entry.get("density_deg_s_per_sqrt_hz", 0.0)) <= 0.0:
			uncited.append("%s (no density)" % imu)

	var expected := ["MPU-6000", "ICM-20602", "ICM-42688-P", "BMI270"]
	var exactly_the_four := CustomFlightControllers.IMU_DENSITY.size() == expected.size()
	for imu in expected:
		if not CustomFlightControllers.IMU_DENSITY.has(imu):
			exactly_the_four = false

	return TestResult.new(
		"every IMU in the density table carries a datasheet citation, and the table is exactly the four the catalog cites",
		uncited.is_empty() and exactly_the_four,
		"%d rows, uncited=%s, exactly the catalog's four=%s" % [
			CustomFlightControllers.IMU_DENSITY.size(), uncited, exactly_the_four])


## The escape hatch that keeps the table honest. A builder whose IMU is not one of the four is not
## blocked — they enter the density themselves, with a source — and a builder who enters neither is
## refused by name rather than flown on a fabricated noise floor.
static func _test_an_unknown_imu_needs_a_density_and_says_so() -> TestResult:
	var with_density := CustomFlightControllers.new().add(
		CustomFlightControllers.make_record("Shed Exotic Board", "ICM-45686", 8000.0, 9.0,
			"30.5x30.5", "H743", 8000, "density 0.0038 deg/s/sqrt(Hz) from TDK DS-000577 rev 1.0",
			0.0038))
	var without := CustomFlightControllers.new().add(
		CustomFlightControllers.make_record("Shed Mystery Board", "ICM-45686", 8000.0, 9.0,
			"30.5x30.5", "H743", 8000, "off the product page"))

	var names_it := false
	for problem in without:
		if problem.contains("ICM-45686") and problem.contains("density"):
			names_it = true

	# And the supplied density must actually be what the board flies on, not merely accepted.
	var record := CustomFlightControllers.make_record("Shed Exotic Board", "ICM-45686", 8000.0,
		9.0, "30.5x30.5", "H743", 8000, "density from the datasheet", 0.0038)
	var expected := CustomFlightControllers.derived_noise_rad_s(0.0038, 8000.0)
	var used: bool = absf(float(record["specs"]["gyro_noise_rad_s"]) - expected) < 1e-9

	return TestResult.new(
		"an IMU outside the table flies on a builder-supplied density, and is refused by name without one",
		with_density.is_empty() and not without.is_empty() and names_it and used,
		"with density accepted=%s, without refused=%s naming it=%s, density used=%s (%.6f)" % [
			with_density.is_empty(), not without.is_empty(), names_it, used, expected])


## Direction AND magnitude, through rate_tune.gd rather than by watching a number move. At a fixed
## sample rate and cutoff the ceiling is exactly inversely proportional to the board's noise floor,
## so the BMI270's 2.5x density over the ICM-42688-P's must buy 2.5x less D — a test that only
## checked "lower" would pass on a formula that got the physics backwards by a constant.
static func _test_a_noisier_board_has_a_lower_d_ceiling() -> TestResult:
	var result: Dictionary = _with_saved([
			CustomFlightControllers.make_record("Shed Quiet Board", "ICM-42688-P", 8000.0, 8.0,
				"30.5x30.5", "H743", 8000, "off the product page"),
			CustomFlightControllers.make_record("Shed Noisy Board", "BMI270", 8000.0, 8.0,
				"30.5x30.5", "F405", 8000, "off the product page"),
		],
		func(merged: PartsCatalog) -> Dictionary:
			return {
				"quiet": RateTune.kd_ceiling_for(_build_on(merged, "custom_shed_quiet_board")),
				"noisy": RateTune.kd_ceiling_for(_build_on(merged, "custom_shed_noisy_board")),
			})

	var quiet := float(result["quiet"])
	var noisy := float(result["noisy"])
	var density_ratio := CustomFlightControllers.density_for("BMI270") \
		/ CustomFlightControllers.density_for("ICM-42688-P")
	var lower := noisy < quiet
	var ratio := quiet / noisy if noisy > 0.0 else INF
	var proportional := absf(ratio - density_ratio) < 0.01

	return TestResult.new(
		"a noisier IMU yields a proportionally lower D-gain ceiling, at the same sample rate",
		lower and proportional,
		"quiet %.3f, noisy %.3f, ratio %.3f against the %.3fx density ratio" % [
			quiet, noisy, ratio, density_ratio])


## Bias is derived like noise and is NOT like noise: no datasheet publishes calibration residue, so
## the figure is a class-typical residue scaled by sensor grade and nothing more. The code has to
## say that where a reader will meet it, or the two derivations become one in the reader's head.
static func _test_bias_is_derived_from_grade_and_labelled_illustrative() -> TestResult:
	var current := CustomFlightControllers.derived_bias_rad_s("ICM-42688-P")
	var budget := CustomFlightControllers.derived_bias_rad_s("BMI270")
	var spans := absf(current - 0.0012) < 1e-9 and absf(budget - 0.0026) < 1e-9
	var ordered := current < budget

	# An override is what someone who has actually characterised their board enters, and it must
	# survive rather than be recomputed over.
	var measured := CustomFlightControllers.make_record("Shed Characterised", "ICM-42688-P",
		8000.0, 8.0, "30.5x30.5", "H743", 8000, "bias measured over ten bench calibrations",
		NAN, 0.00085)
	var override_kept: bool = absf(float(measured["specs"]["gyro_bias_rad_s"]) - 0.00085) < 1e-9
	var flagged: bool = measured["derivation"]["gyro_bias_rad_s"] == false

	var derived := _record_h743_class()
	var derived_flagged: bool = derived["derivation"]["gyro_bias_rad_s"] == true \
		and derived["derivation"]["gyro_noise_rad_s"] == true

	return TestResult.new(
		"bias is derived from sensor grade across the catalog's own 0.0012-0.0026 span, overridable, and flagged as derived",
		spans and ordered and override_kept and flagged and derived_flagged,
		"current %.4f, budget %.4f, spans=%s, override kept=%s, flags=%s/%s" % [
			current, budget, spans, override_kept, flagged, derived_flagged])


static func _test_a_heavy_fc_adds_exactly_its_excess() -> TestResult:
	var heavy_mass := Build.FC_BUDGET_MASS_G + 4.0
	var result: Dictionary = _with_saved([
			CustomFlightControllers.make_record("Shed Budget FC", "ICM-20602", 8000.0,
				Build.FC_BUDGET_MASS_G, "30.5x30.5", "F405", 8000, "off the product page"),
			CustomFlightControllers.make_record("Shed Heavy FC", "ICM-20602", 8000.0,
				heavy_mass, "30.5x30.5", "H743", 8000, "off the product page"),
		],
		func(merged: PartsCatalog) -> Dictionary:
			return {
				"budget": _build_on(merged, "custom_shed_budget_fc").all_up_weight_g(),
				"heavy": _build_on(merged, "custom_shed_heavy_fc").all_up_weight_g(),
			})

	var at_budget := absf(float(result["budget"]) - 496.0) < EPS
	var excess := float(result["heavy"]) - float(result["budget"])
	var exact := absf(excess - 4.0) < EPS

	return TestResult.new(
		"an FC at the budget mass leaves the aircraft at 496 g; 4 g over adds exactly 4 g",
		at_budget and exact,
		"at budget %.2f g, heavy %.2f g, difference %.2f g (want 4.00)" % [
			result["budget"], result["heavy"], excess])


## The FC's own fit warning, which is a different call site and a different warning id from the
## ESC's. Tested separately for exactly that reason.
static func _test_a_mismatched_fc_pattern_raises_the_fc_fit_warning() -> TestResult:
	var result: Dictionary = _with_saved([
			CustomFlightControllers.make_record("Shed 20x20 FC", "ICM-20602", 8000.0, 5.0,
				"20x20", "F405", 8000, "off the product page"),
		],
		func(merged: PartsCatalog) -> Dictionary:
			var warnings := _build_on(merged, "custom_shed_20x20_fc").warnings()
			var fc_warning := _find(warnings, &"fc_stack_mount")
			return {
				"raised": fc_warning != null,
				"names_both": fc_warning != null and fc_warning.message.contains("20x20") \
					and fc_warning.message.contains("30.5x30.5"),
				# The ESC is the reference board and fits, so its warning must stay silent — this is
				# what proves the two call sites are actually independent.
				"esc_clear": _find(warnings, &"stack_mount") == null,
			})

	return TestResult.new(
		"a custom 20x20 FC raises the FC's own fit warning and leaves the ESC's silent",
		result["raised"] and result["names_both"] and result["esc_clear"],
		"raised=%s, names both patterns=%s, ESC warning silent=%s" % [
			result["raised"], result["names_both"], result["esc_clear"]])


## A sample rate that is neither the reference board's 1 kHz nor any catalog value. The physics has
## to hold there rather than be assumed to: raw integrated noise rises as sqrt(rate), and the PT1
## averages proportionally more of it away, so what actually reaches the FC FALLS. That is the
## catalog schema's own claim about why the raw figure is not a hardware comparison, and it is
## asserted here against the reference board rather than as a bare number.
static func _test_an_off_catalog_sample_rate_is_coherent() -> TestResult:
	var result: Dictionary = _with_saved([
			CustomFlightControllers.make_record("Shed 4k Board", "MPU-6000", 4000.0, 8.0,
				"30.5x30.5", "F405", 8000, "gyro rate read off my Betaflight config"),
		],
		func(merged: PartsCatalog) -> Dictionary:
			var custom := _build_on(merged, "custom_shed_4k_board")
			var reference_build := ReferenceBuild.build()
			return {
				"raw_4k": custom.gyro().noise_rad_s,
				"raw_1k": reference_build.gyro().noise_rad_s,
				"at_fc_4k": custom.gyro().sample_step_noise_rad_s(),
				"at_fc_1k": reference_build.gyro().sample_step_noise_rad_s(),
				"ceiling": RateTune.kd_ceiling_for(custom),
			})

	# Same MPU-6000, 4x the rate: sqrt(4) = 2x the raw floor.
	var raw_ratio := float(result["raw_4k"]) / float(result["raw_1k"])
	# 2.0 within 5%, not within 1%. The comparison is a DERIVED figure against the catalog's
	# PUBLISHED one, and the catalog publishes to two significant figures — the reference board's
	# 0.0028 is 1.4% above the 0.00276 the same formula produces. A tighter bound here would be
	# asserting the catalog's rounding rather than the physics.
	var raw_doubles := absf(raw_ratio - 2.0) < 0.1
	# And what reaches the FC goes DOWN, not up — the whole point of the density argument.
	var quieter_at_fc: bool = float(result["at_fc_4k"]) < float(result["at_fc_1k"])
	var ceiling_finite: bool = float(result["ceiling"]) > 0.0 and is_finite(float(result["ceiling"]))

	return TestResult.new(
		"a custom board at an off-catalog 4 kHz integrates 2x the raw noise of the 1 kHz reference and delivers less of it to the FC",
		raw_doubles and quieter_at_fc and ceiling_finite,
		"raw %.5f vs %.5f (%.2fx), at the FC %.6f vs %.6f, kd ceiling %.3f" % [
			result["raw_4k"], result["raw_1k"], raw_ratio,
			result["at_fc_4k"], result["at_fc_1k"], result["ceiling"]])


## The provenance warning, and the one thing it has to get right that no other category's does: the
## derived noise floor is backed by a published datasheet, and the derived bias is not backed by
## anything. Saying "both derived" and stopping would flatten the difference the whole file is
## built around.
static func _test_a_custom_fc_separates_datasheet_noise_from_illustrative_bias() -> TestResult:
	var result: Dictionary = _with_saved([_record_h743_class()],
		func(merged: PartsCatalog) -> Dictionary:
			var warning := _find(_build_on(merged, "custom_shed_h743_board").warnings(),
				&"custom_flight_controller")
			var message: String = warning.message if warning != null else ""
			return {
				"raised": warning != null,
				"quotes_source": message.contains("Betaflight config"),
				"names_datasheet": message.contains("DS-000347"),
				# Case-insensitive: the message shouts ILLUSTRATIVE, and this asserts that the word
				# is there, not how loudly it is said.
				"says_illustrative": message.to_lower().contains("illustrative"),
				"characteristic": warning != null \
					and warning.severity == BuildWarning.Severity.CHARACTERISTIC,
				"reference_clear": _find(ReferenceBuild.build().warnings(),
					&"custom_flight_controller") == null,
			})

	return TestResult.new(
		"a custom-FC build quotes its source, names the datasheet behind its noise floor, and calls its bias illustrative",
		result["raised"] and result["quotes_source"] and result["names_datasheet"] \
			and result["says_illustrative"] and result["characteristic"] \
			and result["reference_clear"],
		"raised=%s, quotes source=%s, names datasheet=%s, says illustrative=%s, characteristic=%s, reference clear=%s" % [
			result["raised"], result["quotes_source"], result["names_datasheet"],
			result["says_illustrative"], result["characteristic"], result["reference_clear"]])


static func _test_unknown_fields_survive_a_round_trip() -> TestResult:
	var path := _scratch("unknown")
	var record := _record_h743_class()
	record["specs"]["gyro_notch_hz"] = 260.0
	record["future_block"] = {"anything": [1, 2, 3]}

	var document := CustomFlightControllers.new()
	var problems := document.add(record)
	document.save(path)

	var reloaded := CustomFlightControllers.load_from(path)
	var stored := reloaded.get_flight_controller("custom_shed_h743_board")
	var kept_spec: bool = absf(float(stored.get("specs", {}).get("gyro_notch_hz", 0.0)) - 260.0) < 1e-9
	# Compared as floats — see the same note in tests/test_custom_escs.gd.
	var kept_block: bool = Array(stored.get("future_block", {}).get("anything", [])) \
		.map(func(value: Variant) -> float: return float(value)) == [1.0, 2.0, 3.0]

	_wipe(path)
	return TestResult.new(
		"a field this version does not know about survives a save and load",
		problems.is_empty() and kept_spec and kept_block,
		"accepted=%s, unknown spec kept=%s, unknown block kept=%s" % [
			problems.is_empty(), kept_spec, kept_block])
